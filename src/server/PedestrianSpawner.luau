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

local PEDESTRIAN_COUNT = 8
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

	local edge = CityConfig.ROAD_WIDTH / 2 + CityConfig.SIDEWALK_WIDTH / 2
	local spanStart = 15
	local spanEnd = -CityConfig.ROAD_LENGTH + 40

	for i = 1, PEDESTRIAN_COUNT do
		local side = if i % 2 == 0 then -1 else 1
		local laneZ = spanStart + (spanEnd - spanStart) * ((i - 0.5) / PEDESTRIAN_COUNT)
		local x = side * edge

		local pedestrian = Players:CreateHumanoidModelFromDescription(buildPedestrianDescription(), Enum.HumanoidRigType.R15)
		pedestrian.Name = "Pedestrian" .. i
		pedestrian.Parent = root

		local humanoid = pedestrian:FindFirstChildOfClass("Humanoid") :: Humanoid
		humanoid.WalkSpeed = WALK_SPEED

		loadWalkTrack(humanoid)

		local fromPos = Vector3.new(x, 1.2, laneZ - LANE_LENGTH / 2)
		local toPos = Vector3.new(x, 1.2, laneZ + LANE_LENGTH / 2)
		pedestrian:PivotTo(CFrame.lookAt(fromPos, toPos))

		loopWalk(pedestrian, humanoid, fromPos, toPos)
	end

	return root
end

return PedestrianSpawner
