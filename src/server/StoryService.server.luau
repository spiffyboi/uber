-- The story (see StoryConfig): runs a chapter's steps in order for whoever's
-- playing it -- people waiting on the sidewalk, getting in, getting out,
-- paying, robbing you, choosing for you -- and tells their client
-- (Story.client) where it's got to, which shows it: the way there, what's
-- said, the choices.
--
-- Chapters are started from the Story app once they unlock; the first (Ray)
-- starts from the intro's fare call. While one's going, the player's
-- "Busy" attribute is "story" and Dispatch stops offering fares (see
-- FareService). Finishing one saves straight away.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FareConfig = require(Shared:WaitForChild("FareConfig"))
local StoryConfig = require(Shared:WaitForChild("StoryConfig"))
local CityConfig = require(Shared:WaitForChild("CityConfig"))
local Joints = require(Shared:WaitForChild("Joints"))
local Routing = require(Shared:WaitForChild("Routing"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Passengers = require(script.Parent:WaitForChild("Passengers"))
local ChapelBuilder = require(script.Parent:WaitForChild("ChapelBuilder"))
local FlatBuilder = require(script.Parent:WaitForChild("FlatBuilder"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local storyUpdate = remotes:WaitForChild("StoryUpdate") :: RemoteEvent
local storyAction = remotes:WaitForChild("StoryAction") :: RemoteEvent
local acceptJob = remotes:WaitForChild("AcceptJob") :: RemoteEvent

-- How long a stop waits on the client to say everyone's finished talking
-- before getting on with it anyway (the client went away, say).
local TALK_TIMEOUT = 75

type Run = {
	chapter: number,
	step: number,
	token: number,
	phase: string,
	npc: Model?, -- whoever's riding along
	waiting: Model?, -- someone waiting at the next stop
	prop: BasePart?,
	lastSpot: any?,
	rideLength: number,
	deadline: number?,
	amount: number?,
	continued: number?, -- the token the client last said "done" for
	chose: any?,
	alley: any?, -- where the side-street scene's been set out (chapter 9)
	extras: { Instance }?, -- the people and props in it
	path: any?, -- the way a cutscene drives the cab (see drivePath)
}

local runs: { [Player]: Run } = {}
local nextToken = 0

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function carOf(player: Player): Model?
	return workspace:FindFirstChild(player.Name .. "_Car") :: Model?
end

local function choicesOf(player: Player): { [string]: any }
	local choices = {}
	for _, chapter in StoryConfig.CHAPTERS do
		for _, step in chapter.steps do
			if step.type == "choice" then
				choices[step.key] = PlayerData.getChoice(player, step.key)
			end
			-- And the ones made on the move, in a ride's lines.
			for _, line in step.lines or {} do
				if line.choice then
					choices[line.choice.key] = PlayerData.getChoice(player, line.choice.key)
				end
			end
		end
	end
	return choices
end

-- Is there a choice to make, or a cutscene to sit through, in this ride's
-- talk? (Then it can take a lot longer than usual.)
local function slowTalk(step): boolean
	if step.vision then
		return true
	end
	for _, line in step.lines or {} do
		if line.choice then
			return true
		end
	end
	return false
end

local function send(player: Player)
	local run = runs[player]
	storyUpdate:FireClient(player, {
		choices = choicesOf(player),
		run = run and {
			chapter = run.chapter,
			step = run.step,
			token = run.token,
			phase = run.phase,
			rideLength = run.rideLength,
			deadline = run.deadline,
			amount = run.amount,
			alley = run.alley,
			path = run.path,
		},
	})
end

local function setPhase(player: Player, run: Run, phase: string)
	run.phase = phase
	send(player)
end

local function alive(player: Player, run: Run): boolean
	return runs[player] == run and player.Parent ~= nil
end

-- Waits for the cab to be stopped within `radius` of `point`. False if the
-- chapter ended (or the player left) first.
local function waitStoppedNear(player: Player, run: Run, point: Vector3, radius: number, giveUpAt: number?): boolean
	while alive(player, run) do
		local car = carOf(player)
		local chassis = car and car.PrimaryPart
		if chassis then
			local stopped = chassis.AssemblyLinearVelocity.Magnitude < FareConfig.STOPPED_SPEED
			if stopped and (flat(chassis.Position) - flat(point)).Magnitude < radius then
				return true
			end
		end
		if giveUpAt and workspace:GetServerTimeNow() > giveUpAt then
			return false
		end
		task.wait(0.2)
	end
	return false
end

-- Waits for the client to say it's finished with this step (everyone's
-- said their piece).
local function waitContinue(player: Player, run: Run, timeout: number?)
	local started = os.clock()
	while alive(player, run) and run.continued ~= run.token do
		if os.clock() - started > (timeout or TALK_TIMEOUT) then
			break
		end
		task.wait(0.1)
	end
end

local function spawnCharacter(who: string, place): Model
	local character = StoryConfig.CHARACTERS[who]
	return Passengers.spawn(character.name, character.look, place.standing, place.stop)
end

-- A holdall sitting on the sidewalk.
local function spawnBag(place): BasePart
	local bag = Instance.new("Part")
	bag.Name = "StoryBag"
	bag.Size = Vector3.new(2.6, 1.3, 1.3)
	bag.Color = Color3.fromRGB(28, 28, 32)
	bag.Material = Enum.Material.Fabric
	bag.Anchored = true
	bag.CanCollide = false
	bag.CFrame = CFrame.new(place.standing + Vector3.new(0, -0.55, 0))
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1.2, 0.5, 0.15)
	handle.Color = bag.Color
	handle.Material = Enum.Material.Fabric
	handle.Anchored = true
	handle.CanCollide = false
	handle.CFrame = bag.CFrame * CFrame.new(0, 0.85, 0)
	handle.Parent = bag
	bag.Parent = workspace
	return bag
end

-- Muzzle flashes from a doorway: bursts of light, nothing else.
local function gunfire(at: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = "Gunfire"
	folder.Parent = workspace
	local flash = Instance.new("Part")
	flash.Size = Vector3.new(0.8, 0.8, 0.8)
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 200, 120)
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CastShadow = false
	flash.Transparency = 1
	flash.Parent = folder
	local light = Instance.new("PointLight")
	light.Color = flash.Color
	light.Range = 26
	light.Brightness = 0
	light.Parent = flash
	task.spawn(function()
		for _ = 1, 9 do
			flash.Position = at + Vector3.new(math.random(-3, 3), 3 + math.random() * 2, math.random(-3, 3))
			flash.Transparency = 0
			light.Brightness = 8
			task.wait(0.06)
			flash.Transparency = 1
			light.Brightness = 0
			task.wait(0.12 + math.random() * 0.35)
		end
		folder:Destroy()
	end)
end

local function cleanUp(run: Run)
	for _, thing in { run.npc, run.waiting, run.prop } do
		if thing then
			(thing :: Instance):Destroy()
		end
	end
	run.npc, run.waiting, run.prop = nil, nil, nil
	for _, thing in run.extras or {} do
		thing:Destroy()
	end
	run.extras, run.alley, run.path = nil, nil, nil
end

-- ===== The side street (chapter 9) =====
-- Partway along a ride, down a side street the cab's about to pass: Dez on
-- his knees on the sidewalk, and two men in dark coats behind him, one with
-- a gun out. Placed wherever the cab's actual route is about to cross a
-- side street (so it's there whichever way the player drives), far enough
-- ahead not to be seen going in; the glimpse itself -- and what happens --
-- is the player's own screen's (see StoryScenes.alley).

local ALLEY_DEPTH = 34 -- how far down the side street Dez is

-- The first side street the route crosses between `nearest` and `farthest`
-- studs ahead: where it crosses (the middle of the junction), which way
-- the cab will be going, and which way the side street runs off (the
-- driver's side if there's road that way, otherwise the other).
-- (A route's corners sit right on the junctions -- confirmed live: every point
-- of a run down Dunmore was a cross street -- so a crossing at the far end of a
-- stretch counts; the near end was the last stretch's far end.)
local function sideStreetAhead(route: { Vector3 }, nearest: number, farthest: number): (Vector3?, Vector3?, Vector3?)
	local walked = 0
	for i = 2, #route do
		local a, b = route[i - 1], route[i]
		local segment = flat(b - a)
		local length = segment.Magnitude
		if length > 1 then
			local dir = segment.Unit
			local driverSide = Vector3.new(dir.Z, 0, -dir.X)
			local crossings = {}
			if math.abs(dir.Z) > 0.9 then
				-- Along an avenue: the side streets are the cross streets.
				local x = a.X
				for _, avenue in CityConfig.AVENUES do
					if math.abs(avenue.x - a.X) < CityConfig.ROAD_WIDTH then
						x = avenue.x
					end
				end
				for _, street in CityConfig.CROSS_STREETS do
					local t = (street.z - a.Z) / (b.Z - a.Z)
					if t > 1e-3 and t <= 1 + 1e-3 then
						table.insert(crossings, { t = t, corner = Vector3.new(x, 0, street.z) })
					end
				end
			elseif math.abs(dir.X) > 0.9 then
				-- Along a cross street: the side roads are the avenues.
				local z = a.Z
				for _, street in CityConfig.CROSS_STREETS do
					if math.abs(street.z - a.Z) < CityConfig.CROSS_STREET_WIDTH then
						z = street.z
					end
				end
				for _, avenue in CityConfig.AVENUES do
					local t = (avenue.x - a.X) / (b.X - a.X)
					if t > 1e-3 and t <= 1 + 1e-3 then
						table.insert(crossings, { t = t, corner = Vector3.new(avenue.x, 0, z) })
					end
				end
			end
			table.sort(crossings, function(p, q)
				return p.t < q.t
			end)
			for _, crossing in crossings do
				local ahead = walked + length * crossing.t
				if ahead >= nearest and ahead <= farthest then
					for _, side in { driverSide, -driverSide } do
						local probe = crossing.corner + side * (ALLEY_DEPTH + 10)
						local inGrid = probe.X >= CityConfig.GRID_LEFT_X - 1
							and probe.X <= CityConfig.GRID_RIGHT_X + 1
							and probe.Z <= CityConfig.GRID_TOP_Z + 1
							and probe.Z >= CityConfig.GRID_BOTTOM_Z - 1
						if inGrid then
							return crossing.corner, dir, side
						end
					end
				end
			end
			walked += length
		end
	end
	return nil, nil, nil
end

-- Pins a rig's joints into a pose (so everyone sees it -- see Joints):
-- `bends` = { [jointName] = CFrame }.
local function pose(model: Model, bends: { [string]: CFrame })
	Joints.bend(model, bends)
end

local function setOutAlley(run: Run, corner: Vector3, travel: Vector3, side: Vector3)
	-- On the near sidewalk of the side street (the side the cab comes
	-- from), so he's in plain view looking down it from the junction.
	local streetHalf = if math.abs(travel.Z) > 0.9 then CityConfig.CROSS_STREET_WIDTH / 2 else CityConfig.ROAD_WIDTH / 2
	local kerb = -travel * (streetHalf + 2.5)
	local ground = Vector3.new(0, 1.2, 0)
	local dezSpot = corner + side * ALLEY_DEPTH + kerb + ground
	local extras = {}

	local dezLook = StoryConfig.CHARACTERS.dez.look
	local dez = Passengers.spawn("AlleyDez", dezLook, dezSpot, corner + kerb + ground)
	local animate = dez:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	-- On his knees: shins folded back, so he sits a leg's length lower.
	local lowerLeg = dez:FindFirstChild("LeftLowerLeg") :: BasePart?
	local drop = if lowerLeg then lowerLeg.Size.Y + 0.3 else 1.6
	pose(dez, {
		LeftKnee = CFrame.Angles(math.rad(-90), 0, 0),
		RightKnee = CFrame.Angles(math.rad(-90), 0, 0),
		LeftShoulder = CFrame.Angles(math.rad(-20), 0, math.rad(-10)),
		RightShoulder = CFrame.Angles(math.rad(-20), 0, math.rad(10)),
	})
	dez:PivotTo(dez:GetPivot() - Vector3.new(0, drop, 0))
	table.insert(extras, dez)

	local manLook = StoryConfig.CHARACTERS.alleyman.look
	local gunHand = nil
	for i, offset in { -1.6, 1.8 } do
		local spot = corner + side * (ALLEY_DEPTH + 4.5) + kerb + travel * offset + ground
		local man = Passengers.spawn("AlleyMan" .. i, manLook, spot, dezSpot)
		local a = man:FindFirstChild("Animate")
		if a then
			a:Destroy()
		end
		if i == 1 then
			-- The one with the gun: arm out, down at the back of Dez's head.
			pose(man, { RightShoulder = CFrame.Angles(math.rad(75), 0, 0) })
			gunHand = man:FindFirstChild("RightHand")
		else
			pose(man, { LeftShoulder = CFrame.Angles(math.rad(-10), 0, 0) })
		end
		table.insert(extras, man)
	end
	if gunHand then
		local gun = Instance.new("Part")
		gun.Name = "AlleyGun"
		gun.Size = Vector3.new(0.2, 0.3, 1)
		gun.Color = Color3.fromRGB(24, 24, 26)
		gun.Material = Enum.Material.Metal
		gun.CanCollide = false
		gun.CanQuery = false
		gun.Massless = true
		task.defer(function()
			-- After the pose has settled the hand where it goes.
			task.wait(0.1)
			gun.CFrame = gunHand.CFrame * CFrame.new(0, -0.35, -0.05) * CFrame.Angles(math.rad(90), 0, 0)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = gunHand
			weld.Part1 = gun
			weld.Parent = gun
			gun.Parent = gunHand.Parent
		end)
	end

	-- One sodium lamp over them on the wall, and a dumpster nearer the
	-- junction, so it reads as a side street nobody uses at night.
	local wall = kerb + (-travel * 3.5)
	local lamp = Instance.new("Part")
	lamp.Name = "AlleyLamp"
	lamp.Size = Vector3.new(0.8, 0.4, 0.8)
	lamp.Material = Enum.Material.Neon
	lamp.Color = Color3.fromRGB(255, 170, 90)
	lamp.Anchored = true
	lamp.CanCollide = false
	lamp.CFrame = CFrame.new(corner + side * (ALLEY_DEPTH + 2) + wall + Vector3.new(0, 10, 0))
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Color = lamp.Color
	light.Brightness = 3
	light.Range = 18
	light.Angle = 80
	light.Parent = lamp
	lamp.Parent = workspace
	table.insert(extras, lamp)
	local dumpster = Instance.new("Part")
	dumpster.Name = "AlleyDumpster"
	dumpster.Size = Vector3.new(6, 4, 3)
	dumpster.Color = Color3.fromRGB(34, 60, 44)
	dumpster.Material = Enum.Material.Metal
	dumpster.Anchored = true
	local along = side * (ALLEY_DEPTH - 12)
	dumpster.CFrame = CFrame.lookAt(corner + along + wall + Vector3.new(0, 1.2 + 2, 0), corner + along + wall + Vector3.new(0, 3.2, 0) + side)
	dumpster.Parent = workspace
	table.insert(extras, dumpster)

	run.extras = extras
	run.alley = {
		corner = corner + ground,
		travel = travel,
		side = side,
		dez = dezSpot,
		shooter = corner + side * (ALLEY_DEPTH + 4.5) + kerb - travel * 1.6 + ground,
	}
end

-- Watches a ride with an `alley` (chapter 9) and sets the scene out once
-- the cab's far enough along.
local function watchForAlley(player: Player, run: Run, step, token: number)
	local tries = 0
	while alive(player, run) and run.token == token and not run.alley do
		local car = carOf(player)
		local chassis = car and car.PrimaryPart
		if chassis and run.rideLength > 0 then
			local route, remaining = Routing.route(chassis.Position, step.spot.stop)
			local progress = 1 - remaining / run.rideLength
			if progress >= step.alley.at then
				tries += 1
				-- First choice: a side street a good way ahead, so it's in
				-- place before it's in sight. If there isn't one, take any
				-- side street at all up ahead -- the scene has to happen.
				local corner, travel, side = sideStreetAhead(route, 70, 420)
				if not corner and tries > 4 then
					corner, travel, side = sideStreetAhead(route, 15, 2000)
				end
				if corner and travel and side then
					setOutAlley(run, corner, travel, side)
					send(player)
				end
			end
		end
		task.wait(0.5)
	end
end

-- ===== Steps =====

local handlers: { [string]: (Player, Run, any) -> () } = {}

function handlers.text(player, run)
	setPhase(player, run, "text")
	task.wait(1.2)
end

function handlers.pickup(player, run, step)
	run.npc = spawnCharacter(step.who, step.spot)
	setPhase(player, run, "waiting")
	if not waitStoppedNear(player, run, step.spot.stop, FareConfig.PICKUP_RADIUS) then
		return
	end
	setPhase(player, run, "boarding")
	local car = carOf(player)
	if car and run.npc then
		Passengers.board(run.npc, car)
	end
end

function handlers.ride(player, run, step)
	local car = carOf(player)
	local from = if car and car.PrimaryPart then car.PrimaryPart.Position else step.spot.stop
	local _, length = Routing.route(from, step.spot.stop)
	run.rideLength = length
	run.lastSpot = step.spot
	-- Whoever's meeting the cab at the other end is already there waiting.
	local chapter = StoryConfig.CHAPTERS[run.chapter]
	local nextStep = chapter.steps[run.step + 1]
	if nextStep and nextStep.type == "handoff" then
		run.waiting = spawnCharacter(nextStep.who, nextStep.spot)
	end
	if step.alley then
		task.spawn(watchForAlley, player, run, step, run.token)
	end
	while alive(player, run) do
		run.deadline = if step.timeLimit then workspace:GetServerTimeNow() + step.timeLimit else nil
		setPhase(player, run, "riding")
		if waitStoppedNear(player, run, step.spot.stop, FareConfig.DROPOFF_RADIUS, run.deadline) then
			break
		end
		if not alive(player, run) then
			return
		end
		-- Out of time: say so, and go again.
		run.deadline = nil
		setPhase(player, run, "failed")
		task.wait(3)
	end
	run.deadline = nil
	setPhase(player, run, "arrived")
	waitContinue(player, run, if slowTalk(step) then 300 else nil)
end

function handlers.talk(player, run)
	setPhase(player, run, "talk")
	waitContinue(player, run)
end

-- "Kill the engine": the seat switched off (that's what engine-off is --
-- see CarSpawner/CarController). Switching a seat off throws out whoever's
-- in it, though -- confirmed live, which is what sent the robbery's camera
-- off: it was framing a driver who'd been tipped out onto the road -- so
-- they're put straight back. (Doing it in the same instant doesn't take;
-- a tenth of a second later does.)
local function stopEngine(player: Player)
	local car = carOf(player)
	local seat = car and car:FindFirstChild("DriveSeat") :: VehicleSeat?
	if not seat or seat.Disabled then
		return
	end
	local driver = seat.Occupant
	seat.Disabled = true
	if driver then
		-- And kept there for a moment: once in a while the ejection lands
		-- after the first re-seat (seen once in testing -- the driver ended
		-- up standing in the cab).
		task.spawn(function()
			for _ = 1, 15 do
				task.wait(0.1)
				if not driver.Parent or driver.Health <= 0 then
					break
				end
				if not driver.SeatPart then
					seat:Sit(driver)
				end
			end
		end)
	end
end

-- A cutscene the client plays (see StoryScenes); done when it says so.
-- The sets under the street a scene goes into, to be loaded on the
-- player's screen before it cuts inside (the world streams in around the
-- player, and the cab's up on the road -- confirmed live: the chapel's
-- room came up unlit for its first ten seconds).
local SCENE_SETS = {
	funeral = CityConfig.CHAPEL_ORIGIN,
	gunstore = CityConfig.GUNSTORE_ORIGIN,
	flat = CityConfig.FLAT_ORIGIN,
}

-- Which way a cab parked at `place`'s kerb faces: along the street, with
-- the kerb on its right.
local function kerbFacing(place): Vector3
	local toKerb = flat(place.standing) - flat(place.stop)
	return Vector3.yAxis:Cross(toKerb.Unit)
end

-- How high the cab's middle sits with its wheels on the road (the road's
-- top is at 1 -- see CarSpawner, which rests it the same way): from wherever
-- it is now, which may be up on a kerb.
local function restingHeight(car: Model): number
	local chassis = car.PrimaryPart :: BasePart
	local lowest = math.huge
	for _, part in car:GetDescendants() do
		if part:IsA("BasePart") and part.CanCollide then
			lowest = math.min(lowest, part.Position.Y - part.Size.Y / 2)
		end
	end
	return 1.05 + (chassis.Position.Y - lowest)
end

-- Puts the cab where `chassisAt` says (anchored first: the engine off), and
-- the player back in the driver's seat if they'd got out.
local function moveCab(player: Player, chassisAt: CFrame)
	local car = carOf(player)
	local chassis = car and car.PrimaryPart
	if not car or not chassis then
		return
	end
	stopEngine(player)
	chassis.Anchored = true
	chassis.AssemblyLinearVelocity = Vector3.zero
	local offset = chassis.CFrame:Inverse() * car:GetPivot()
	car:PivotTo(chassisAt * offset)
	local seat = car:FindFirstChild("DriveSeat") :: VehicleSeat?
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if seat and humanoid and humanoid.SeatPart ~= seat then
		seat:Sit(humanoid)
	end
end

-- `parkAt`: the cab back at that kerb, if it's wandered off (a scene that
-- happens outside a building needs the cab outside it); `settle`: put it
-- square at the kerb, wheels on the road, wherever it is.
local function parkCab(player: Player, place, settle: boolean?)
	local car = carOf(player)
	local chassis = car and car.PrimaryPart
	if not car or not chassis then
		return
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seated = humanoid and humanoid.SeatPart == car:FindFirstChild("DriveSeat")
	if not settle and seated and (flat(chassis.Position) - flat(place.stop)).Magnitude < 30 then
		return
	end
	local stop = Vector3.new(place.stop.X, restingHeight(car), place.stop.Z)
	moveCab(player, CFrame.lookAt(stop, stop + kerbFacing(place)))
end

-- ===== Driving in a cutscene =====
-- A scene with `drive` has the cab drive itself (on the player's screen --
-- see SelfDrive) along the route to `drive.to`, in the right-hand lane:
-- all the way there, or (`length`) just that far, stopping where there's
-- road enough ahead (`jam`: for a queue of traffic to sit in). The route's
-- worked out here, so this end knows where the cab finishes, and the cab's
-- put there once the scene's over.

local JAM_ROOM = 48

local function laneOffset(dir: Vector3): number
	return if math.abs(dir.Z) > 0.9 then CityConfig.LANE_WIDTH * 1.5 else CityConfig.CROSS_STREET_WIDTH / 4
end

-- The route moved over into the right-hand lane: each stretch shifted to
-- its right, the corners where the shifted stretches meet.
local function inLane(route: { Vector3 }): { Vector3 }
	local points = {}
	local segments = {}
	for i = 2, #route do
		local a, b = flat(route[i - 1]), flat(route[i])
		if (b - a).Magnitude > 0.5 then
			table.insert(segments, { a = a, b = b })
		end
	end
	for i, segment in segments do
		local dir = (segment.b - segment.a).Unit
		local right = Vector3.new(-dir.Z, 0, dir.X) * laneOffset(dir)
		segment.right = right
		if i == 1 then
			table.insert(points, segment.a + right)
		else
			local previous = segments[i - 1]
			local previousDir = (previous.b - previous.a).Unit
			if previousDir:Dot(dir) > 0.99 then
				-- Straight on through a junction: no corner.
				table.insert(points, segment.a + right)
			else
				-- A turn: where this stretch and the last, both shifted, cross.
				table.insert(points, segment.a + right + previous.right)
			end
		end
	end
	local last = segments[#segments]
	if last then
		table.insert(points, last.b + last.right)
	end
	return points
end

local function drivePath(player: Player, drive)
	local car = carOf(player)
	local chassis = car and car.PrimaryPart
	if not chassis then
		return nil
	end
	-- Driven at the height it sits on the road (not wherever it is: pulled up
	-- on a kerb, it drove the whole way floating -- reported).
	local y = restingHeight(car :: Model)
	if not drive.length then
		-- All the way, pulling in to the kerb the way the traffic on that side
		-- goes: to a point back along the kerb first, then straight in. (Routed
		-- straight to the stop, it came in from the far end and stopped facing
		-- the wrong way -- the depot's gunman ended up behind the cab.)
		local approach = drive.to.stop - kerbFacing(drive.to) * 40
		local points = inLane(Routing.route(chassis.Position, approach))
		if #points < 2 then
			return nil
		end
		table.insert(points, flat(drive.to.stop))
		return { points = points, y = y }
	end
	local route = Routing.route(chassis.Position, drive.to.stop)
	local points = inLane(route)
	if #points < 2 then
		return nil
	end
	-- Only so far: end mid-stretch with room ahead.
	local cut = { points[1] }
	local walked = 0
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local length = (b - a).Magnitude
		local latest = walked + length - (if drive.jam then JAM_ROOM else 0)
		if drive.length <= latest then
			local at = math.max(drive.length, walked)
			table.insert(cut, a + (b - a).Unit * (at - walked))
			return { points = cut, y = y, jam = drive.jam }
		end
		table.insert(cut, b)
		walked += length
	end
	return { points = cut, y = y }
end

-- Where the cab ends up after a driving scene: the end of its path, facing
-- along the last stretch.
local function endOfPath(path): CFrame
	local points = path.points
	local last, before = points[#points], points[#points - 1]
	local at = Vector3.new(last.X, path.y, last.Z)
	local dir = flat(last - before)
	return CFrame.lookAt(at, at + (if dir.Magnitude > 0.1 then dir.Unit else Vector3.zAxis))
end

-- ===== A scene's cast =====
-- People a scene needs, put where it needs them (`cast` -- see
-- StoryConfig): `who` (a character, spawned for it), or `passenger`
-- (whoever's in the cab -- or was, before they went inside), at a named spot.
-- `seated` sits them on what's there; `scale` makes them smaller (a child).
-- What they then do is the player's own screen's business (see LateScenes).

local function castSpot(name: string): CFrame?
	local bus = CityConfig.DEPOT_BUS
	local depot = StoryConfig.PLACES.depot
	local home = StoryConfig.PLACES.rayHome
	if name == "flatPhoto" then
		return FlatBuilder.spot("photo")
	elseif name == "flatKitchen" then
		return FlatBuilder.spot("kitchen")
	elseif name == "busGirl" then
		-- On a road-side seat, turned to the window.
		local seatTop = (bus * CFrame.new(-2.9, 1.55, 1.1)).Position
		return CFrame.lookAt(seatTop, seatTop - bus.RightVector)
	elseif name == "busMum" then
		local seatTop = (bus * CFrame.new(-2.3, 1.55, 4.9)).Position
		return CFrame.lookAt(seatTop, seatTop + bus.LookVector)
	elseif name == "depotGunman" then
		-- Round the corner, out of sight: on the Wharf St pavement, behind
		-- the depot's ticket hall. (He runs round it -- see LateScenes.)
		local _, far = CityConfig.lotZRange(CityConfig.DEPOT_LOT)
		local toKerb = (flat(depot.standing) - flat(depot.stop)).Unit
		local at = Vector3.new(depot.standing.X, 1.2, far - 3) + toKerb * 36
		return CFrame.lookAt(at, at - toKerb)
	elseif name == "rayStep" then
		-- On the sidewalk by his front door, facing the road.
		local toKerb = (flat(home.standing) - flat(home.stop)).Unit
		local at = home.standing + toKerb * 7
		return CFrame.lookAt(at, at - toKerb)
	end
	return nil
end

local function setCast(player: Player, run: Run, cast)
	run.extras = run.extras or {}
	for _, member in cast do
		local spot = castSpot(member.at)
		if not spot then
			warn(`StoryService: no cast spot called {member.at}`)
			continue
		end
		local npc: Model? = nil
		if member.passenger then
			npc = run.npc
			if npc then
				npc.Parent = workspace
			end
		elseif member.who then
			local character = StoryConfig.CHARACTERS[member.who]
			npc = Passengers.spawn(character.name, character.look, spot.Position, spot.Position + spot.LookVector)
			table.insert(run.extras :: { Instance }, npc :: Model)
		end
		if not npc then
			continue
		end
		-- Sent to the player whole and kept there, wherever they are: the
		-- scene that uses them starts straight away, and the world streams in
		-- around the player a bit at a time.
		npc.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		local animate = npc:FindFirstChild("Animate")
		if animate and not member.passenger then
			animate:Destroy()
		end
		if member.scale then
			npc:ScaleTo(member.scale)
		end
		if member.seated then
			local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
			root.Anchored = true
			local height = ChapelBuilder.sitDown(npc)
			npc:PivotTo(spot + Vector3.new(0, height, 0))
		else
			Passengers.place(npc, spot)
		end
	end
end

-- Ray, after the depot (chapter 10): slumped over the wheel of the cab, for
-- anyone to see. (Sat where the driver sits, the cab's own seat being
-- empty by then -- the player got out.)
local function slumpAtWheel(player: Player, run: Run, who: string)
	local car = carOf(player)
	local seat = car and car:FindFirstChild("DriveSeat") :: BasePart?
	local name = "Passenger_" .. StoryConfig.CHARACTERS[who].name
	local npc = nil
	for _, thing in run.extras or {} do
		if thing.Name == name then
			npc = thing
		end
	end
	if not seat or not npc then
		return
	end
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	local height = ChapelBuilder.sitDown(npc)
	Joints.bend(npc, {
		Waist = CFrame.Angles(math.rad(-38), 0, math.rad(8)),
		Neck = CFrame.Angles(math.rad(-30), 0, math.rad(12)),
		LeftShoulder = CFrame.Angles(math.rad(20), 0, 0),
		RightShoulder = CFrame.Angles(math.rad(20), 0, 0),
	})
	-- (At the wheel, which is left of the seat's middle -- as LateScenes
	-- sits him for the drive.)
	npc:PivotTo(seat.CFrame * CFrame.new(-0.75, seat.Size.Y / 2 + height - 0.1, 0.1))
end

function handlers.scene(player, run, step)
	if step.parkAt then
		parkCab(player, step.parkAt, step.settle)
	end
	if step.killEngine then
		stopEngine(player)
	end
	if step.cast then
		setCast(player, run, step.cast)
	end
	run.path = if step.drive then drivePath(player, step.drive) else nil
	local set = SCENE_SETS[step.scene]
	if set then
		pcall(function()
			player:RequestStreamAroundAsync(set, 8)
		end)
	end
	setPhase(player, run, "playing")
	waitContinue(player, run, 400)
	if not alive(player, run) then
		return
	end
	if run.path then
		moveCab(player, endOfPath(run.path))
		run.path = nil
	end
	if step.removePassenger and run.npc then
		run.npc:Destroy()
		run.npc = nil
	end
	if step.boardAfter and run.npc then
		-- Back in the cab (they got in during the scene).
		local car = carOf(player)
		if car then
			Passengers.board(run.npc, car, true)
		end
	end
	if step.slump then
		slumpAtWheel(player, run, step.slump)
	end
	if step.gives then
		PlayerData.setChoice(player, "has" .. step.gives, true)
	end
	if step.startEngine then
		local car = carOf(player)
		local seat = car and car:FindFirstChild("DriveSeat") :: VehicleSeat?
		if seat then
			seat.Disabled = false
		end
	end
end

-- The passenger gets out and goes into the building (chapter 9's Teddy,
-- into Quarry Houses). Kept, out of sight, for later: a scene's cast can
-- bring them back.
function handlers.goInside(player, run, step)
	local place, npc = run.lastSpot, run.npc
	if not place or not npc then
		return
	end
	local door = Passengers.awayFrom(place.standing, place.stop, 9)
	Passengers.getOut(npc, carOf(player), place.standing, door)
	setPhase(player, run, "goingIn")
	Passengers.walkTo(npc, door, 5)
	npc.Parent = nil
end

-- Waiting outside (chapter 9): nothing, for `delay` seconds -- then someone
-- (`who`) walks up the sidewalk past the cab and goes in the same door.
-- Then the player's to go in after them: done when they say so (see
-- Story.client).
function handlers.lookout(player, run, step)
	local place = run.lastSpot
	if not place then
		return
	end
	setPhase(player, run, "waiting")
	local started = os.clock()
	while alive(player, run) and os.clock() - started < (step.delay or 20) do
		task.wait(0.25)
	end
	if not alive(player, run) then
		return
	end
	local forward = kerbFacing(place)
	local character = StoryConfig.CHARACTERS[step.who]
	local from = place.standing - forward * 46
	local walker = Passengers.spawn(character.name, character.look, from, from + forward)
	run.extras = run.extras or {}
	table.insert(run.extras :: { Instance }, walker)
	local root = walker:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = false
	root:SetNetworkOwner(nil)
	local humanoid = walker:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.WalkSpeed = 7
	setPhase(player, run, "passing")
	Passengers.walkTo(walker, place.standing + forward * 1.5, 12)
	Passengers.walkTo(walker, Passengers.awayFrom(place.standing, place.stop, 9), 5)
	walker:Destroy()
	if not alive(player, run) then
		return
	end
	setPhase(player, run, "prompt")
	waitContinue(player, run, 900)
end

-- On foot, after the depot (chapter 10): the player's own to walk, until
-- the client says it's time (see Story.client).
function handlers.walk(player, run, step)
	setPhase(player, run, "walking")
	waitContinue(player, run, (step.seconds or 15) + 60)
end

-- Driving yourself somewhere: the same as a ride, with nobody aboard.
handlers.drive = function(player, run, step)
	handlers.ride(player, run, step)
end

-- Paying for something (chapter 7's pistol). If they're short, it takes
-- what there is -- the story doesn't stop for it.
function handlers.purchase(player, run, step)
	local paid = math.min(step.price, player:GetAttribute("Cash") or 0)
	PlayerData.addCash(player, -paid)
	PlayerData.setChoice(player, "has" .. step.item, true)
	run.amount = paid
	setPhase(player, run, "bought")
	task.wait(1.5)
end

function handlers.choice(player, run, step)
	run.chose = nil
	setPhase(player, run, "choosing")
	while alive(player, run) and run.chose == nil do
		task.wait(0.1)
	end
	if run.chose ~= nil then
		local option = step.options[run.chose]
		PlayerData.setChoice(player, step.key, option.value)
	end
end

function handlers.robbery(player, run, step)
	-- "Kill the engine." The cab stays parked till the player starts it
	-- again.
	stopEngine(player)
	setPhase(player, run, "threat")
	waitContinue(player, run)
	if not alive(player, run) then
		return
	end
	local taken = math.min(step.take, player:GetAttribute("Cash") or 0)
	PlayerData.addCash(player, -taken)
	run.amount = taken
	setPhase(player, run, "robbed")
	local place = run.lastSpot
	if run.npc and place then
		-- Out, onto the sidewalk, and away up the street at a sprint --
		-- whichever way's clear (see Passengers.letOut).
		local npc = run.npc :: Model
		run.npc = nil
		Passengers.letOut(npc, carOf(player), place.standing, place.stop, 22)
	end
	-- Long enough for the last shot of him running off.
	task.wait(5)
end

function handlers.errand(player, run, step)
	local place = run.lastSpot
	local npc = run.npc
	if not place or not npc then
		return
	end
	local car = carOf(player)
	local door = Passengers.awayFrom(place.standing, place.stop, 8)
	Passengers.getOut(npc, car, place.standing, door)
	run.deadline = workspace:GetServerTimeNow() + step.seconds
	setPhase(player, run, "waiting")
	Passengers.walkTo(npc, door, 4)
	npc.Parent = nil
	local shotsAt = run.deadline - 4
	while alive(player, run) and workspace:GetServerTimeNow() < (if step.gunfire then shotsAt else run.deadline) do
		task.wait(0.2)
	end
	if step.gunfire and alive(player, run) then
		setPhase(player, run, "gunfire")
		gunfire(door + (flat(place.standing) - flat(place.stop)).Unit * 6)
		task.wait(4)
	end
	if not alive(player, run) then
		return
	end
	-- Back out, and in.
	run.deadline = nil
	setPhase(player, run, "returning")
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.WalkSpeed = if step.gunfire then 20 else 10
	npc.Parent = workspace
	car = carOf(player)
	if car then
		Passengers.board(npc, car)
	end
end

function handlers.collect(player, run, step)
	run.prop = spawnBag(step.spot)
	setPhase(player, run, "waiting")
	if not waitStoppedNear(player, run, step.spot.stop, FareConfig.PICKUP_RADIUS) then
		return
	end
	if run.prop then
		run.prop:Destroy()
		run.prop = nil
	end
	setPhase(player, run, "collected")
	task.wait(1.5)
end

function handlers.handoff(player, run, step)
	local npc = run.waiting or spawnCharacter(step.who, step.spot)
	run.waiting = npc
	setPhase(player, run, "talk")
	waitContinue(player, run)
	run.waiting = nil
	task.spawn(function()
		local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.Anchored = false
			root:SetNetworkOwner(nil)
		end
		Passengers.walkTo(npc, Passengers.awayFrom(step.spot.standing, step.spot.stop, 10), 5)
		npc:Destroy()
	end)
end

function handlers.dropoff(player, run, step)
	local pay = if step.pay == "meter" then FareConfig.price(run.rideLength) else step.pay
	pay += step.tip or 0
	local place = run.lastSpot
	if run.npc and place then
		Passengers.letOut(run.npc, carOf(player), place.standing, place.stop)
		run.npc = nil
	end
	PlayerData.addCash(player, pay)
	run.amount = pay
	setPhase(player, run, "paid")
	task.wait(1.5)
	-- A cutscene of them going (Teddy, Okafor): the chapter waits for it.
	if step.outro == "tower" or step.outro == "vanish" then
		waitContinue(player, run, 40)
	end
end

-- `linger` (chapter 7's Teddy): out of the cab, a few steps to the foot of
-- the building, and stood there looking up at it -- for the rest of the
-- chapter, rather than walking off.
local dropoffAndGo = handlers.dropoff
function handlers.dropoff(player, run, step)
	local place = run.lastSpot
	local npc = run.npc
	if not (step.linger and npc and place) then
		dropoffAndGo(player, run, step)
		return
	end
	run.npc = nil
	run.extras = run.extras or {}
	table.insert(run.extras :: { Instance }, npc)
	local car = carOf(player)
	local foot = Passengers.awayFrom(place.standing, place.stop, 4)
	task.spawn(function()
		Passengers.getOut(npc, car, place.standing, foot)
		Passengers.walkTo(npc, foot, 4)
		local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and npc.Parent then
			root.Anchored = true
			local face = foot + (flat(place.standing) - flat(place.stop)).Unit * 10
			root.CFrame = CFrame.lookAt(root.Position, Vector3.new(face.X, root.Position.Y, face.Z))
		end
	end)
	local pay = (if step.pay == "meter" then FareConfig.price(run.rideLength) else step.pay) + (step.tip or 0)
	PlayerData.addCash(player, pay)
	run.amount = pay
	setPhase(player, run, "paid")
	task.wait(1.5)
	if step.outro then
		waitContinue(player, run, 40)
	end
end

function handlers.ending(player, run)
	setPhase(player, run, "ending")
	task.wait(7)
end

-- ===== Chapters =====

local startChapter: (Player, number) -> ()

-- The sky a chapter (or a step in it) holds the city to (see
-- WeatherService's WeatherForce); let go again when the chapter's over.
local function holdWeather(weather: string?)
	workspace:SetAttribute("WeatherForce", weather)
end

local function finish(player: Player, run: Run, completed: boolean)
	if runs[player] ~= run then
		return
	end
	if StoryConfig.CHAPTERS[run.chapter].weather then
		holdWeather(nil)
	end
	cleanUp(run)
	runs[player] = nil
	if completed then
		player:SetAttribute("StoryDone", run.chapter)
		task.spawn(PlayerData.save, player)
	end
	player:SetAttribute("Busy", nil)
	send(player)
	if completed then
		-- The story carries straight on: the next chapter starts a little
		-- while later (the client texts that it's coming). Given up on one,
		-- it waits for the Story app's Start button instead.
		local nextIndex = run.chapter + 1
		task.delay(StoryConfig.NEXT_CHAPTER_DELAY, function()
			if player.Parent and not runs[player] and (player:GetAttribute("StoryDone") or 0) == run.chapter then
				startChapter(player, nextIndex)
			end
		end)
	end
end

-- Story mode is everything but Free Play (which is fares only -- see
-- FareService).
local function inStoryMode(player: Player): boolean
	local mode = player:GetAttribute("GameMode")
	return mode ~= nil and mode ~= "free"
end

function startChapter(player: Player, index: number)
	if runs[player] or player:GetAttribute("Busy") or not inStoryMode(player) then
		return
	end
	local chapter = StoryConfig.CHAPTERS[index]
	if not chapter then
		return
	end
	if StoryConfig.status(index, player:GetAttribute("StoryDone") or 0) ~= "ready" then
		return
	end
	local run: Run = {
		chapter = index,
		step = 0,
		token = 0,
		phase = "",
		rideLength = 0,
	}
	runs[player] = run
	player:SetAttribute("Busy", "story")
	if chapter.weather then
		holdWeather(chapter.weather)
	end
	task.spawn(function()
		for stepIndex, step in chapter.steps do
			if not alive(player, run) then
				return
			end
			if not StoryConfig.applies(step, choicesOf(player)) then
				continue
			end
			nextToken += 1
			run.step = stepIndex
			run.token = nextToken
			run.amount = nil
			if step.weather then
				holdWeather(step.weather)
			end
			local ok, err = pcall(handlers[step.type], player, run, step)
			if not ok then
				warn(`StoryService: chapter {index} step {stepIndex} ({step.type}) failed: {err}`)
			end
		end
		finish(player, run, alive(player, run))
	end)
end

storyAction.OnServerEvent:Connect(function(player, action, value)
	if typeof(action) ~= "string" then
		return
	end
	local run = runs[player]
	if action == "start" and typeof(value) == "number" then
		startChapter(player, value)
	elseif action == "continue" and run and value == run.token then
		run.continued = value
	elseif action == "choose" and run and typeof(value) == "number" and run.phase == "choosing" then
		local step = StoryConfig.CHAPTERS[run.chapter].steps[run.step]
		if step.type == "choice" and step.options[value] then
			run.chose = value
		end
	elseif action == "rideChoice" and run and typeof(value) == "table" then
		-- A choice made on the move (see Story.client's playRide): which of
		-- the ride's lines it is, and which option.
		local step = StoryConfig.CHAPTERS[run.chapter].steps[run.step]
		local line = step.type == "ride" and typeof(value.line) == "number" and step.lines and step.lines[value.line]
		local choice = line and line.choice
		local option = choice and typeof(value.option) == "number" and choice.options[value.option]
		if option then
			PlayerData.setChoice(player, choice.key, option.value)
			send(player)
		end
	elseif action == "quit" and run then
		-- Walking away from a chapter: it starts again from the top next time.
		finish(player, run, false)
	end
end)

-- The shift starts (the intro's "Fare called in" is accepted, or a
-- continued story / bug test skips straight to the cab -- see
-- IntroCutscene): the next chapter -- Ray, for a new story; in a bug test,
-- the chapter picked on the menu. Nothing in Free Play.
acceptJob.OnServerEvent:Connect(function(player)
	if not PlayerData.waitLoaded(player) or not inStoryMode(player) then
		return
	end
	local testChapter = player:GetAttribute("TestChapter")
	local index = if typeof(testChapter) == "number" then testChapter else (player:GetAttribute("StoryDone") or 0) + 1
	if index == 1 then
		startChapter(player, 1)
	else
		-- A moment in the cab first, for the screen to fade up.
		task.delay(3, function()
			startChapter(player, index)
		end)
	end
end)

local function onPlayerAdded(player: Player)
	task.spawn(function()
		if PlayerData.waitLoaded(player) then
			send(player)
		end
	end)
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	local run = runs[player]
	if run then
		cleanUp(run)
		runs[player] = nil
	end
end)
