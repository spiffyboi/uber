-- Background traffic for the now two-way, four-lane strip: a handful of cars
-- looping the road's own length in both directions, slowing to a real stop
-- at a red/yellow light (see IntersectionBuilder) and rolling through on
-- green. No lane changes, no turns onto the cross streets, no yielding to
-- each other within a lane -- straight-line loop traffic is enough to make
-- the street read as alive without a full traffic-AI stack.

local InsertService = game:GetService("InsertService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))
local IntersectionBuilder = require(script.Parent.IntersectionBuilder)

local TrafficSpawner = {}

-- Tried mixing in the two candidates CarBuilder passed over for the player's
-- own cab (see CarBuilder's history) for background variety -- confirmed
-- live in Studio that at least one of them has its bounding box's long axis
-- along local X rather than Z (unlike the Fletcher mesh), so the same
-- meshSize.X/meshSize.Z chassis-sizing math CarBuilder/buildTrafficCar both
-- use produced a chassis 20+ studs wide and only ~9 long -- a visibly warped,
-- sideways car. Rather than hand-calibrate each candidate's own orientation
-- under time pressure, every traffic car just uses the one mesh already
-- proven correct end-to-end. A fleet of identical cabs also suits a taxi
-- company setting fine on its own.
local TRAFFIC_MESH_IDS = { 12342470926 }

local TRAFFIC_COUNT = 9
local MAX_SPEED = 34 -- studs/second, slower than the player's own top speed
local ACCEL = 22
local STOP_LOOKAHEAD = 34 -- how far ahead a car starts checking lights
local STOP_MARGIN = 16 -- stud offset from the intersection centre to the stop line

-- Car-following: stay back a real two seconds' worth of travel at current
-- speed, not just react to lights -- means a car queued behind another
-- (whether that's more traffic or the player's own cab) actually stops
-- instead of driving straight through/into it.
local FOLLOW_TIME = 2 -- seconds
local MIN_FOLLOW_GAP = 7 -- studs, the closest bumper-to-bumper gap even at a dead stop
local SAME_LANE_TOLERANCE = 4 -- studs of X difference still counted as "the same lane"

local cachedTemplates: { [number]: Model } = {}

local function getMeshTemplate(assetId: number): Model
	if cachedTemplates[assetId] then
		return cachedTemplates[assetId]
	end
	local container = InsertService:LoadAsset(assetId)
	local mesh = container:FindFirstChildWhichIsA("Model")
	assert(mesh, `traffic mesh asset {assetId} didn't contain a Model as expected`)
	mesh.Parent = nil
	container:Destroy()
	cachedTemplates[assetId] = mesh
	return mesh
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

-- Same technique as CarBuilder.rigMeshToChassis: weld every part of the
-- (already correctly positioned) mesh onto a single invisible chassis while
-- it's still sitting where it visually belongs, so this doesn't need to know
-- any of these meshes' own internal layouts either.
local function rigMeshToChassis(mesh: Instance, chassis: BasePart)
	for _, descendant in mesh:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Massless = true
			if descendant ~= chassis then
				weld(chassis, descendant)
			end
		end
	end
end

-- Builds one traffic car, kinematic (Anchored chassis moved by CFrame each
-- frame in startDriveLoop, not real physics) -- these never need a driver
-- seat or CarController's velocity math, just to exist as a solid,
-- collidable obstacle the player's own (unanchored, physics-driven) car can
-- actually run into. `direction` is -1 for outbound (facing -Z, the same
-- direction the whole opening cutscene already drives) or 1 for inbound.
local function buildTrafficCar(assetId: number, laneX: number, z: number, direction: number): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "TrafficCar"

	local cframe = CFrame.new(laneX, 3, z) * (if direction == 1 then CFrame.Angles(0, math.pi, 0) else CFrame.new())

	local mesh = getMeshTemplate(assetId):Clone()
	local _, meshSize = mesh:GetBoundingBox()
	-- Same 180 the player's own taxi mesh needs (see CarBuilder) -- the
	-- other two candidate meshes were measured live the same way when they
	-- were first tried out and share the same local +Z front.
	mesh:PivotTo(cframe * CFrame.Angles(0, math.pi, 0))
	mesh.Parent = model

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(meshSize.X * 0.9, meshSize.Y * 0.5, meshSize.Z * 0.95)
	chassis.Transparency = 1
	chassis.CFrame = cframe * CFrame.new(0, -meshSize.Y * 0.18, 0)
	chassis.CanCollide = true
	chassis.Anchored = true
	chassis.Parent = model
	model.PrimaryPart = chassis

	rigMeshToChassis(mesh, chassis)

	local halfLength = chassis.Size.Z / 2
	local taillight = Instance.new("Part")
	taillight.Name = "TaillightGlow"
	taillight.Size = Vector3.new(0.2, 0.2, 0.2)
	taillight.Transparency = 1
	taillight.CanCollide = false
	taillight.Massless = true
	taillight.CFrame = chassis.CFrame * CFrame.new(0, 0.3, halfLength)
	taillight.Parent = model
	weld(chassis, taillight)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 60, 60)
	-- Kept dim for the same reason CarBuilder's own taillight was cut down --
	-- see the "sparkle" investigation above; with up to 9 of these on the
	-- road at once, low brightness/range matters even more here.
	glow.Brightness = 0.5
	glow.Range = 4
	glow.Parent = taillight

	CollectionService:AddTag(model, "TrafficCar")
	return model, chassis
end

-- How far ahead (in this car's own direction of travel) the nearest
-- intersection is, and whether it's within a light's reach at all --
-- negative/huge-positive means "don't worry about it this frame".
local function nextIntersectionAhead(z: number, direction: number): number?
	local nearest = nil
	for _, intersectionZ in CityConfig.INTERSECTION_Z do
		local distanceAhead = (intersectionZ - z) * direction
		if distanceAhead > -4 and (nearest == nil or distanceAhead < nearest) then
			nearest = distanceAhead
		end
	end
	return nearest
end

-- Distance to the nearest *car* ahead in the same lane -- any other traffic
-- car, or the player's own (so a traffic car queued behind a stopped player
-- actually stops too, not just other AI). Checked fresh every frame rather
-- than cached, same as the light check above; with under a dozen cars total
-- this is cheap.
--
-- Returns the bumper-to-bumper gap, not the centre-to-centre distance: with
-- ~14-stud-long cars, the old centre-to-centre check let a queuing car stop
-- with its nose 7 studs *inside* the car ahead. These cars are anchored and
-- moved by CFrame, so overlapping the player's (physical) cab shoves it with
-- unlimited force -- confirmed live a traffic car ploughed into the player's
-- cab stopped in the outbound lane and flung it off the map, killing the
-- driver.
local function nextCarAhead(myChassis: BasePart, laneX: number, direction: number): number?
	local myZ = myChassis.Position.Z
	local nearest = nil
	for _, tagName in { "TrafficCar", "PlayerCar" } do
		-- The player's cab can sit at any angle and anywhere across the lane,
		-- so it counts as "in this lane" for anything overlapping it at all.
		local tolerance = if tagName == "PlayerCar" then CityConfig.LANE_WIDTH / 2 + 3 else SAME_LANE_TOLERANCE
		for _, other in CollectionService:GetTagged(tagName) do
			local otherChassis = (other :: Model).PrimaryPart
			if not otherChassis or otherChassis == myChassis then
				continue
			end
			if math.abs(otherChassis.Position.X - laneX) > tolerance then
				continue
			end
			local centreGap = (otherChassis.Position.Z - myZ) * direction
			-- The player's cab may be turned sideways, so use its longest
			-- side rather than assuming it's lined up with the lane.
			local otherHalf = math.max(otherChassis.Size.X, otherChassis.Size.Z) / 2
			local gap = centreGap - myChassis.Size.Z / 2 - otherHalf
			if centreGap > 0 and (nearest == nil or gap < nearest) then
				nearest = gap
			end
		end
	end
	return nearest
end

local function startDriveLoop(chassis: BasePart, laneX: number, direction: number, startZ: number)
	local z = startZ
	-- Every car sharing identical MAX_SPEED/ACCEL against the same global
	-- light schedule made them settle into an exact shared rhythm after a
	-- few cycles -- confirmed live in Studio, cars in different lanes and
	-- even opposite directions ended up parked at the literal same Z, well
	-- past what queueing at a stop line alone explains. A small per-car
	-- speed variance breaks that synchronization and reads more like real
	-- traffic (not everyone doing exactly the same speed) besides.
	local ownMaxSpeed = MAX_SPEED * (0.85 + math.random() * 0.3)
	local speed = ownMaxSpeed * 0.6

	task.spawn(function()
		while chassis.Parent do
			local dt = RunService.Heartbeat:Wait()
			if not chassis.Parent then
				break
			end

			local targetSpeed = ownMaxSpeed
			local aheadDistance = nextIntersectionAhead(z, direction)
			if aheadDistance and aheadDistance < STOP_LOOKAHEAD then
				local state = IntersectionBuilder.getMainRoadState()
				local stopDistance = aheadDistance - STOP_MARGIN
				if state ~= "green" and stopDistance < STOP_LOOKAHEAD - STOP_MARGIN then
					-- Close enough to a non-green light to need to be slowing
					-- for it: aim to be stopped by the time it reaches the
					-- line, not just clamp speed to zero -- a car already
					-- past its own stop line (stopDistance <= 0) commits to
					-- clearing the intersection instead of slamming to a halt
					-- inside it.
					if stopDistance <= 0 then
						targetSpeed = ownMaxSpeed
					else
						targetSpeed = math.clamp(stopDistance * 2.2, 0, ownMaxSpeed)
					end
				end
			end

			-- Car-following, independent of the light check above: whichever
			-- of the two demands the slower speed wins. `gap / FOLLOW_TIME`
			-- is the classic N-second-rule target -- at the desired 2-second
			-- gap this evaluates to exactly the car-ahead's own pace (neither
			-- closing nor falling back), and it naturally goes to zero as the
			-- gap shrinks toward MIN_FOLLOW_GAP, so a car smoothly brakes to
			-- a dead stop right behind whatever's stopped ahead of it rather
			-- than needing separate "stopped" logic.
			local carAheadGap = nextCarAhead(chassis, laneX, direction)
			if carAheadGap then
				local followSpeed = math.clamp((carAheadGap - MIN_FOLLOW_GAP) / FOLLOW_TIME, 0, ownMaxSpeed)
				targetSpeed = math.min(targetSpeed, followSpeed)
			end

			speed += math.clamp(targetSpeed - speed, -ACCEL * dt, ACCEL * dt)
			-- Normal braking above is gentle; if something is suddenly right
			-- in front (the player pulling out or stopping short), stop dead
			-- rather than drive into it.
			if carAheadGap and carAheadGap < MIN_FOLLOW_GAP then
				speed = 0
			end
			z += direction * speed * dt

			local wrapStart = 20
			local wrapEnd = -CityConfig.ROAD_LENGTH + 20
			if direction == -1 and z < wrapEnd then
				z = wrapStart
			elseif direction == 1 and z > wrapStart then
				z = wrapEnd
			end

			local facing = if direction == 1 then CFrame.Angles(0, math.pi, 0) else CFrame.new()
			chassis.CFrame = CFrame.new(laneX, chassis.Position.Y, z) * facing
		end
	end)
end

function TrafficSpawner.build()
	local root = Instance.new("Folder")
	root.Name = "Traffic"
	root.Parent = workspace

	local lanes = {}
	for _, x in CityConfig.OUTBOUND_LANE_X do
		table.insert(lanes, { x = x, direction = -1 })
	end
	for _, x in CityConfig.INBOUND_LANE_X do
		table.insert(lanes, { x = x, direction = 1 })
	end

	for i = 1, TRAFFIC_COUNT do
		local lane = lanes[((i - 1) % #lanes) + 1]
		local spanFraction = (i - 0.5) / TRAFFIC_COUNT
		local z = 20 - spanFraction * CityConfig.ROAD_LENGTH
		local assetId = TRAFFIC_MESH_IDS[((i - 1) % #TRAFFIC_MESH_IDS) + 1]

		local car, chassis = buildTrafficCar(assetId, lane.x, z, lane.direction)
		car.Name = `TrafficCar_{i}`
		car.Parent = root
		startDriveLoop(chassis, lane.x, lane.direction, z)
	end
end

return TrafficSpawner
