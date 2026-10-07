-- Populates the sidewalks with a handful of anonymous night-shift
-- pedestrians -- real R15 characters (same technique as the office's
-- dispatcher), each walking back and forth along a straight stretch of one
-- sidewalk. No pathfinding, no reacting to the player or traffic -- just
-- enough foot traffic that the street reads as lived-in instead of a set
-- with nobody on it.

local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))

local PedestrianSpawner = {}

local SKIN_TONES = {
	Color3.fromRGB(185, 150, 122),
	Color3.fromRGB(140, 100, 75),
	Color3.fromRGB(225, 195, 165),
	Color3.fromRGB(90, 65, 50),
}

-- Muted, period-plausible coat/trouser colours -- nothing bright enough to
-- read as a "character" the way the taxi's own livery does.
local CLOTHING_COLORS = {
	Color3.fromRGB(70, 66, 78),
	Color3.fromRGB(96, 92, 82),
	Color3.fromRGB(50, 55, 60),
	Color3.fromRGB(80, 40, 40),
	Color3.fromRGB(40, 60, 55),
	Color3.fromRGB(60, 58, 68),
}

local PEDESTRIAN_COUNT = 26
local WALK_SPEED = 7
local LANE_LENGTH = 45

-- Default R15 walk cycle, the same one the engine's own StarterCharacter
-- Animate script plays for a real player at normal WalkSpeed. Loaded and
-- played directly here rather than relying on the Animate LocalScript that
-- ships on a CreateHumanoidModelFromDescription rig -- confirmed live in
-- Studio that that script never actually runs for these pedestrians at all:
-- LocalScripts only auto-run when they're a descendant of an actual Player's
-- Character/Backpack/PlayerGui/PlayerScripts (or ReplicatedFirst), and an NPC
-- model sitting in Workspace that isn't any Player's Character doesn't
-- qualify. It's present, Enabled, and permanently inert. Driving the
-- animation ourselves from this Script (not a LocalScript) sidesteps that
-- entirely, since Scripts run regardless of ownership.
local WALK_ANIMATION_ID = "rbxassetid://913402848"

local function randomColor(palette: { Color3 }): Color3
	return palette[math.random(1, #palette)]
end

local function loadWalkTrack(humanoid: Humanoid): AnimationTrack
	local animator = humanoid:FindFirstChildOfClass("Animator") :: Animator
	local animation = Instance.new("Animation")
	animation.AnimationId = WALK_ANIMATION_ID
	local track = animator:LoadAnimation(animation)
	track.Looped = true
	-- The default walk cycle is authored against the engine's default
	-- WalkSpeed (16 studs/second). Played at native speed against this game's
	-- slower WALK_SPEED, the legs would cycle much faster than the body
	-- actually translates -- a moonwalk/skate look. Scaling playback by the
	-- same ratio keeps footfall matched to actual ground speed -- passed
	-- straight into Play() rather than a separate AdjustSpeed() call before
	-- it, since Play() resets speed back to 1 when called without one.
	track:Play(0, 1, humanoid.WalkSpeed / 16)
	return track
end

local function buildPedestrianDescription(): HumanoidDescription
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = randomColor(SKIN_TONES)
	local shirt = randomColor(CLOTHING_COLORS)
	description.TorsoColor = shirt
	description.LeftArmColor = shirt
	description.RightArmColor = shirt
	local pants = randomColor(CLOTHING_COLORS)
	description.LeftLegColor = pants
	description.RightLegColor = pants
	return description
end

-- Walks `humanoid` back and forth between `from` and `to` forever. Drives it
-- with Humanoid:Move() every step instead of Humanoid:MoveTo() -- confirmed
-- live in Studio that MoveTo *did* translate these NPCs correctly (position
-- advanced right on WalkSpeed) but left Humanoid.MoveDirection stuck at zero
-- the whole time, which is what the default Animate script actually watches
-- to decide whether to play the running animation. Net effect: pedestrians
-- visibly slid down the sidewalk without their legs moving. Move() sets
-- MoveDirection itself every frame, so the walk animation actually plays.
-- Each leg times out on its own in case a pedestrian gets wedged on a
-- streetlight base and never actually arrives.
local function loopWalk(pedestrian: Model, humanoid: Humanoid, from: Vector3, to: Vector3)
	task.spawn(function()
		local target = to
		while pedestrian.Parent do
			local rootPart = pedestrian:FindFirstChild("HumanoidRootPart") :: BasePart?
			-- If HumanoidRootPart is ever momentarily missing, the inner loop
			-- below never runs a single iteration -- its own condition is
			-- false before the first check -- which meant this outer loop
			-- span right back to the top with no `task.wait()` anywhere in
			-- between: a true non-yielding infinite loop. Confirmed live in
			-- Studio: the engine's own watchdog eventually force-kills a
			-- thread stuck like that ("Script timeout: exhausted allowed
			-- execution time"), which silently stops that one pedestrian
			-- walking forever rather than erroring loudly. This wait is what
			-- actually guarantees the loop yields every iteration regardless
			-- of whether rootPart was found.
			if not rootPart then
				task.wait(1)
				continue
			end
			local elapsed = 0
			while pedestrian.Parent and rootPart and elapsed < 15 do
				local toTarget = target - rootPart.Position
				local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
				if flat.Magnitude < 1.5 then
					break
				end
				humanoid:Move(flat.Unit)
				elapsed += task.wait()
			end
			humanoid:Move(Vector3.zero)
			if not pedestrian.Parent then
				return
			end
			target = if target == to then from else to
		end
	end)
end

function PedestrianSpawner.build()
	local root = Instance.new("Folder")
	root.Name = "Pedestrians"
	root.Parent = workspace

	-- A walk along the middle of an avenue sidewalk, away from the kerb
	-- clutter (streetlights, hydrants) and the shopfronts.
	local walkOut = CityConfig.ROAD_WIDTH / 2 + 5

	-- True if a walk from z1 to z2 on `side` of the avenue at `x` would cross
	-- a taxi rank, where cabs park right across the sidewalk line (confirmed
	-- live: a pedestrian paced back and forth straight into the player's
	-- parked cab).
	local function crossesRank(x: number, side: number, z1: number, z2: number): boolean
		for _, lot in CityConfig.LOTS do
			if lot.kind == "taxiRank" and lot.x == x and lot.side == side then
				local near, far = CityConfig.lotZRange(lot)
				if math.max(z1, z2) > far and math.min(z1, z2) < near then
					return true
				end
			end
		end
		return false
	end

	-- Every stretch of avenue sidewalk between two cross streets, either
	-- side, as a candidate walk -- spread round the whole grid, busiest on
	-- Marrow St where the player starts.
	local walks = {}
	for _, avenue in CityConfig.AVENUES do
		for c = 1, #CityConfig.CROSS_STREETS - 1 do
			local top = CityConfig.CROSS_STREETS[c].z - CityConfig.CROSS_BUILDING_EDGE - 4
			local bottom = CityConfig.CROSS_STREETS[c + 1].z + CityConfig.CROSS_BUILDING_EDGE + 4
			for side = -1, 1, 2 do
				local tries = if avenue.x == CityConfig.MAIN_AVENUE_X then 2 else 1
				-- A second walker on the same stretch keeps to a different
				-- line, so the two don't walk into each other.
				for k = 1, tries do
					local length = math.min(LANE_LENGTH, top - bottom)
					local z1 = top - math.random() * (top - bottom - length)
					local z2 = z1 - length
					if not crossesRank(avenue.x, side, z1, z2) then
						table.insert(walks, { x = avenue.x + side * (walkOut + (k - 1) * 3), z1 = z1, z2 = z2 })
					end
				end
			end
		end
	end

	for i = 1, PEDESTRIAN_COUNT do
		if #walks == 0 then
			break
		end
		local walk = table.remove(walks, math.random(1, #walks))

		local pedestrian = Players:CreateHumanoidModelFromDescription(buildPedestrianDescription(), Enum.HumanoidRigType.R15)
		pedestrian.Name = "Pedestrian" .. i
		-- The rig's scaling records are only needed while it's being built;
		-- dropping them trims ~80 objects off each walker.
		for _, descendant in pedestrian:GetDescendants() do
			if descendant:IsA("ValueBase") then
				descendant:Destroy()
			end
		end
		pedestrian.Parent = root

		local humanoid = pedestrian:FindFirstChildOfClass("Humanoid") :: Humanoid
		humanoid.WalkSpeed = WALK_SPEED
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

		loadWalkTrack(humanoid)

		local fromPos = Vector3.new(walk.x, 1.2, walk.z1)
		local toPos = Vector3.new(walk.x, 1.2, walk.z2)
		pedestrian:PivotTo(CFrame.lookAt(fromPos, toPos) + Vector3.new(0, 3, 0))

		loopWalk(pedestrian, humanoid, fromPos, toPos)
	end

	return root
end

return PedestrianSpawner
