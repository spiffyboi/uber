-- Background traffic on the whole street grid (see StreetGrid): cars drive
-- junction to junction in their own lane, pick a way on at each junction
-- (straight on, or a turn -- never a U-turn), stop at the line for a red or
-- a yellow they can't make, ease off for turns, and queue behind whatever is
-- ahead of them -- other traffic or a player's cab.
--
-- The server only moves an invisible, collidable box per car; that's what a
-- player's cab actually bumps into. The cab you see riding on it is drawn
-- by each player's own client (TrafficVisuals), from the lightweight cab
-- model this file puts in ReplicatedStorage. Measured live, simulating and
-- sending fourteen full-detail ~740-part cabs from the server every frame
-- was costing two thirds of every frame on its own.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CarBuilder = require(script.Parent.CarBuilder)
local StreetGrid = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StreetGrid"))

local TrafficSpawner = {}

local TRAFFIC_COUNT = 40
local CRUISE_SPEED = 32 -- studs/second, a little under the player's top speed
local TURN_SPEED = 12
local ACCEL = 11
local COMFORT_BRAKE = 15 -- how hard cars plan to brake for lights, turns and queues
local HARD_BRAKE = 60 -- how hard they can brake when something cuts in
local MIN_GAP = 4 -- bumper-to-bumper gap a queue settles at
local LOOKAHEAD = 50
local ROAD_TOP = 1
-- After this long stuck behind other traffic (not a red light, not a
-- player), a car gives up waiting and squeezes through, so a knot of cars
-- at a junction can't lock the street up for good.
local STUCK_LIMIT = 10
local GHOST_TIME = 3

type Node = StreetGrid.Node

type Car = {
	box: BasePart,
	halfLength: number,
	maxSpeed: number,
	speed: number,
	-- Where it is: driving a stretch from `from` to `to`, or turning through
	-- `to` onto the next one.
	phase: string,
	from: Node,
	to: Node,
	heading: Vector3,
	axis: string,
	lane: number,
	laneOffset: number,
	s: number,
	length: number,
	nextNode: Node?,
	nextHeading: Vector3?,
	nextLane: number,
	committed: boolean,
	-- The turn's curve.
	p0: Vector3,
	control: Vector3,
	p1: Vector3,
	-- Where it is right now, for everyone else's following checks.
	position: Vector3,
	forward: Vector3,
	stuck: number,
	ghostUntil: number,
	blockedByPlayer: number,
}

local cars: { Car } = {}

local function laneOffsetFor(axis: string, lane: number): number
	local offsets = StreetGrid.laneOffsets(axis)
	return offsets[math.clamp(lane, 1, #offsets)]
end

local function segmentPoint(car: Car, s: number): Vector3
	local right = StreetGrid.rightOf(car.heading)
	local start = car.from.position + car.heading * StreetGrid.stopDistance(car.axis)
	return start + car.heading * s + right * car.laneOffset
end

-- Picks where to go at the end of the current stretch.
local function chooseNext(car: Car)
	local options = {}
	for _, exit in StreetGrid.exits(car.to) do
		if exit.heading:Dot(car.heading) > -0.5 then
			local weight = if exit.heading:Dot(car.heading) > 0.5 then 2 else 1
			for _ = 1, weight do
				table.insert(options, exit)
			end
		end
	end
	local exit = options[math.random(1, #options)]
	car.nextNode = exit.node
	car.nextHeading = exit.heading
	local nextAxis = StreetGrid.axisOf(exit.heading)
	local lanes = #StreetGrid.laneOffsets(nextAxis)
	if exit.heading:Dot(car.heading) > 0.5 then
		car.nextLane = math.min(car.lane, lanes)
	elseif exit.heading:Dot(StreetGrid.rightOf(car.heading)) > 0.5 then
		car.nextLane = lanes -- a right turn ends up in the kerb lane
	else
		car.nextLane = 1 -- a left turn in the lane by the centre line
	end
end

local function startSegment(car: Car, from: Node, to: Node, heading: Vector3, lane: number)
	car.phase = "segment"
	car.from = from
	car.to = to
	car.heading = heading
	car.axis = StreetGrid.axisOf(heading)
	car.lane = lane
	car.laneOffset = laneOffsetFor(car.axis, lane)
	car.s = 0
	car.length = (to.position - from.position).Magnitude - 2 * StreetGrid.stopDistance(car.axis)
	car.committed = false
	chooseNext(car)
end

local function startTurn(car: Car)
	local nextHeading = car.nextHeading :: Vector3
	local nextAxis = StreetGrid.axisOf(nextHeading)
	car.p0 = segmentPoint(car, car.length)
	car.p1 = car.to.position + nextHeading * StreetGrid.stopDistance(nextAxis) + StreetGrid.rightOf(nextHeading) * laneOffsetFor(nextAxis, car.nextLane)
	if nextHeading:Dot(car.heading) > 0.5 then
		car.control = (car.p0 + car.p1) / 2
	else
		-- Where the incoming lane's line meets the outgoing lane's line.
		car.control = car.p0 + car.heading * (car.p1 - car.p0):Dot(car.heading)
	end
	local length = 0
	local previous = car.p0
	for k = 1, 8 do
		local t = k / 8
		local point = (1 - t) ^ 2 * car.p0 + 2 * (1 - t) * t * car.control + t ^ 2 * car.p1
		length += (point - previous).Magnitude
		previous = point
	end
	car.phase = "turn"
	car.s = 0
	car.length = length
end

-- Position and facing for wherever the car is along its current piece.
local function pose(car: Car): (Vector3, Vector3)
	if car.phase == "segment" then
		return segmentPoint(car, car.s), car.heading
	end
	local t = math.clamp(car.s / car.length, 0, 1)
	local point = (1 - t) ^ 2 * car.p0 + 2 * (1 - t) * t * car.control + t ^ 2 * car.p1
	local tangent = 2 * (1 - t) * (car.control - car.p0) + 2 * t * (car.p1 - car.control)
	if tangent.Magnitude < 1e-3 then
		tangent = car.heading
	end
	return point, tangent.Unit
end

-- The closest thing ahead in this car's path: bumper-to-bumper gap, and
-- whether it's a player's cab.
local function obstacleAhead(car: Car, now: number): (number?, boolean)
	local right = car.forward:Cross(Vector3.yAxis)
	local nearest: number? = nil
	local isPlayer = false
	if now >= car.ghostUntil then
		for _, other in cars do
			if other == car or other.forward:Dot(car.forward) < -0.5 then
				continue
			end
			local offset = other.position - car.position
			local ahead = offset:Dot(car.forward)
			if ahead <= 0 or ahead > LOOKAHEAD or math.abs(offset:Dot(right)) > 3.2 then
				continue
			end
			local gap = ahead - car.halfLength - other.halfLength
			if nearest == nil or gap < nearest then
				nearest = gap
				isPlayer = false
			end
		end
	end
	for _, model in CollectionService:GetTagged("PlayerCar") do
		local chassis = (model :: Model).PrimaryPart
		if not chassis then
			continue
		end
		local offset = Vector3.new(chassis.Position.X, 0, chassis.Position.Z) - Vector3.new(car.position.X, 0, car.position.Z)
		local ahead = offset:Dot(car.forward)
		-- The player's cab can sit at any angle and anywhere across the lane.
		local otherHalf = math.max(chassis.Size.X, chassis.Size.Z) / 2
		if ahead <= 0 or ahead > LOOKAHEAD or math.abs(offset:Dot(right)) > 3 + chassis.Size.X / 2 then
			continue
		end
		local gap = ahead - car.halfLength - otherHalf
		if nearest == nil or gap < nearest then
			nearest = gap
			isPlayer = true
		end
	end
	return nearest, isPlayer
end

-- Is the other lane of this avenue clear enough to pull into, around here?
local function otherLaneClear(car: Car, lane: number): boolean
	local target = segmentPoint({ from = car.from, heading = car.heading, axis = car.axis, laneOffset = laneOffsetFor(car.axis, lane) } :: any, car.s)
	for _, other in cars do
		if other ~= car and (other.position - target).Magnitude < 16 then
			return false
		end
	end
	return true
end

local function step(car: Car, dt: number, now: number)
	local target = car.maxSpeed
	local heldByLight = false

	if car.phase == "segment" then
		local toLine = car.length - car.s
		local state = StreetGrid.signalState(car.to, car.axis)
		-- `committed`: caught by a yellow too close to stop comfortably, so
		-- it carries on through (even if it's turned red by the time it gets
		-- to the line, a second later) rather than slamming to a halt in
		-- the junction.
		if state ~= "green" and not car.committed then
			local stoppingDistance = car.speed ^ 2 / (2 * COMFORT_BRAKE)
			if state == "yellow" and toLine < stoppingDistance then
				car.committed = true
			else
				target = math.min(target, math.sqrt(2 * COMFORT_BRAKE * math.max(0, toLine - 0.5)))
				heldByLight = toLine < 12
			end
		end
		local nextHeading = car.nextHeading :: Vector3
		if nextHeading:Dot(car.heading) < 0.5 then
			target = math.min(target, math.sqrt(TURN_SPEED ^ 2 + 2 * COMFORT_BRAKE * math.max(0, toLine)))
		end
	else
		local nextHeading = car.nextHeading :: Vector3
		if nextHeading:Dot(car.heading) < 0.5 then
			target = math.min(target, TURN_SPEED)
		end
	end

	local gap, isPlayer = obstacleAhead(car, now)
	if gap then
		target = math.min(target, math.sqrt(2 * COMFORT_BRAKE * math.max(0, gap - MIN_GAP)))
	end

	if target > car.speed then
		car.speed = math.min(target, car.speed + ACCEL * dt)
	else
		car.speed = math.max(target, car.speed - HARD_BRAKE * dt)
	end
	-- Right on top of something (it pulled out, or stopped short): stop dead
	-- rather than drive into it. These boxes are anchored and moved outright,
	-- so overlapping a player's cab would shove it with unlimited force.
	if gap and gap < MIN_GAP * 0.5 then
		car.speed = 0
	end

	-- Stuck behind another car (not a light, not a player) for too long.
	if car.speed < 0.5 and gap and not isPlayer and not heldByLight then
		car.stuck += dt
		if car.stuck > STUCK_LIMIT then
			car.ghostUntil = now + GHOST_TIME
			car.stuck = 0
		end
	else
		car.stuck = 0
	end

	-- Parked behind a player's cab on an avenue: pull round it.
	if car.phase == "segment" and car.speed < 0.5 and gap and isPlayer and gap < 15 then
		car.blockedByPlayer += dt
		local lanes = #StreetGrid.laneOffsets(car.axis)
		if car.blockedByPlayer > 3 and lanes > 1 then
			local otherLane = if car.lane == 1 then 2 else 1
			if otherLaneClear(car, otherLane) then
				car.lane = otherLane
				car.blockedByPlayer = 0
			end
		end
	else
		car.blockedByPlayer = 0
	end
	-- Drift toward the lane it's meant to be in (only differs mid lane change).
	if car.phase == "segment" then
		local wanted = laneOffsetFor(car.axis, car.lane)
		car.laneOffset += math.clamp(wanted - car.laneOffset, -4 * dt, 4 * dt)
	end

	car.s += car.speed * dt
	while car.s >= car.length do
		local overflow = car.s - car.length
		if car.phase == "segment" then
			startTurn(car)
		else
			startSegment(car, car.to, car.nextNode :: Node, car.nextHeading :: Vector3, car.nextLane)
		end
		car.s = overflow
	end

	local position, forward = pose(car)
	car.position = position
	car.forward = forward
end

-- Starts a car part way along a random stretch, clear of everyone else.
local function placeCar(car: Car): boolean
	local nodes = StreetGrid.allNodes()
	for _ = 1, 30 do
		local node = nodes[math.random(1, #nodes)]
		local exits = StreetGrid.exits(node)
		local exit = exits[math.random(1, #exits)]
		local axis = StreetGrid.axisOf(exit.heading)
		local lane = math.random(1, #StreetGrid.laneOffsets(axis))
		startSegment(car, node, exit.node, exit.heading, lane)
		car.s = math.random() * math.max(0, car.length - 10)
		local position = segmentPoint(car, car.s)
		local clear = true
		for _, other in cars do
			if (other.position - position).Magnitude < 20 then
				clear = false
				break
			end
		end
		if clear then
			car.position = position
			car.forward = car.heading
			return true
		end
	end
	return false
end

function TrafficSpawner.build()
	-- The cab model clients draw traffic with (see TrafficVisuals).
	local template = CarBuilder.getLiteTemplate()
	local assets = Instance.new("Folder")
	assets.Name = "CityAssets"
	assets.Parent = ReplicatedStorage
	local shared = template:Clone()
	shared.Parent = assets

	local boxSize = template:GetAttribute("BoxSize") :: Vector3
	local boxHeight = ROAD_TOP + (template.PrimaryPart :: BasePart).Position.Y

	local root = Instance.new("Folder")
	root.Name = "Traffic"
	root.Parent = workspace

	for i = 1, TRAFFIC_COUNT do
		local box = Instance.new("Part")
		box.Name = `TrafficCar_{i}`
		box.Size = boxSize
		box.Transparency = 1
		box.Anchored = true
		box.CanCollide = true
		box.CanTouch = false
		box.CastShadow = false
		-- Which paint job clients draw it in (see TrafficVisuals).
		box:SetAttribute("Paint", math.random(1, 100))

		local car = {
			box = box,
			halfLength = boxSize.Z / 2,
			-- A little variety, so cars don't all fall into lockstep.
			maxSpeed = CRUISE_SPEED * (0.85 + math.random() * 0.3),
			speed = 0,
			stuck = 0,
			ghostUntil = 0,
			blockedByPlayer = 0,
			position = Vector3.zero,
			forward = Vector3.zAxis,
		} :: any
		if placeCar(car) then
			car.speed = car.maxSpeed * 0.5
			box.CFrame = CFrame.lookAt(car.position, car.position + car.forward) + Vector3.new(0, boxHeight, 0)
			box.Parent = root
			CollectionService:AddTag(box, "TrafficCar")
			table.insert(cars, car)
		else
			box:Destroy()
		end
	end

	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		dt = math.min(dt, 0.1)
		for _, car in cars do
			step(car, dt, now)
		end
		table.clear(parts)
		table.clear(frames)
		for _, car in cars do
			table.insert(parts, car.box)
			table.insert(frames, CFrame.lookAt(car.position, car.position + car.forward) + Vector3.new(0, boxHeight, 0))
		end
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end)
end

return TrafficSpawner
