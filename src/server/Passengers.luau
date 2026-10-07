-- The people who ride in the back: waiting on the sidewalk, walking to the
-- cab and getting in, getting out and walking off. Used by FareService
-- (ordinary fares) and StoryService (the story's characters).

local Players = game:GetService("Players")

local Passengers = {}

local WALK_ANIMATION_ID = "rbxassetid://913402848"

export type Look = { skin: Color3, shirt: Color3, pants: Color3 }

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function loadWalk(humanoid: Humanoid): AnimationTrack?
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = WALK_ANIMATION_ID
	local track = animator:LoadAnimation(animation)
	track.Looped = true
	return track
end

local function standingHeight(npc: Model): number
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	return humanoid.HipHeight + root.Size.Y / 2
end

-- Walks `npc` toward `target` (ignoring height) for at most `timeout`
-- seconds. Driven with Humanoid:Move each step, with the walk animation
-- played by hand -- the same way the pedestrians walk (see
-- PedestrianSpawner for why the rig's own Animate script can't be used).
function Passengers.walkTo(npc: Model, target: Vector3, timeout: number)
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end
	local track = loadWalk(humanoid)
	if track then
		track:Play(0.1, 1, humanoid.WalkSpeed / 16)
	end
	local elapsed = 0
	while elapsed < timeout and npc.Parent do
		local offset = flat(target) - flat(root.Position)
		if offset.Magnitude < 1.5 then
			break
		end
		humanoid:Move(offset.Unit)
		elapsed += task.wait()
	end
	humanoid:Move(Vector3.zero)
	if track then
		track:Stop(0.2)
	end
end

-- A passenger standing at `standing` facing `facing` (the road), waiting.
function Passengers.spawn(name: string, look: Look, standing: Vector3, facing: Vector3): Model
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = look.skin
	description.TorsoColor = look.shirt
	description.LeftArmColor = look.shirt
	description.RightArmColor = look.shirt
	description.LeftLegColor = look.pants
	description.RightLegColor = look.pants
	local npc = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	npc.Name = "Passenger_" .. name
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.WalkSpeed = 8
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	local height = standingHeight(npc)
	npc:PivotTo(CFrame.lookAt(standing + Vector3.new(0, height, 0), Vector3.new(facing.X, standing.Y + height, facing.Z)))
	root.Anchored = true
	npc.Parent = workspace
	return npc
end

-- Walks the passenger to the cab's rear door and sits them in the back.
-- Yields until they're in.
function Passengers.board(npc: Model, car: Model)
	local chassis = car.PrimaryPart
	local seat = car:FindFirstChild("PassengerSeat") :: Seat?
	if not npc.Parent or not chassis or not seat then
		return
	end
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = false
	root:SetNetworkOwner(nil)
	-- To the rear door on whichever side of the cab they're on.
	local side = if (chassis.CFrame:PointToObjectSpace(root.Position)).X >= 0 then 1 else -1
	local door = (chassis.CFrame * CFrame.new(side * (chassis.Size.X / 2 + 1.5), 0, 3)).Position
	Passengers.walkTo(npc, door, 3)
	-- Riding along: weightless and not bumping the cab around.
	for _, descendant in npc:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Massless = true
			descendant.CanCollide = false
		end
	end
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	seat:Sit(humanoid)
end

-- Gets the passenger out of `car` on the side nearest `kerb` and stands them
-- there facing `toward`. Yields a moment.
function Passengers.getOut(npc: Model, car: Model?, kerb: Vector3, toward: Vector3)
	if not npc.Parent then
		return
	end
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid.Sit = false
	task.wait(0.15)
	local chassis = car and car.PrimaryPart
	if chassis then
		local side = if chassis.CFrame:PointToObjectSpace(kerb).X >= 0 then 1 else -1
		local out = (chassis.CFrame * CFrame.new(side * (chassis.Size.X / 2 + 2), 1, 3)).Position
		npc:PivotTo(CFrame.lookAt(out, Vector3.new(toward.X, out.Y, toward.Z)))
	end
	for _, descendant in npc:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Massless = false
			descendant.CanCollide = descendant.Name == "HumanoidRootPart" or descendant.Name:find("Torso") ~= nil
		end
	end
	root:SetNetworkOwner(nil)
end

-- Where someone dropped at `standing` (on the sidewalk, `stop` being the
-- kerb lane beside it) walks off to: into the buildings.
function Passengers.awayFrom(standing: Vector3, stop: Vector3, distance: number?): Vector3
	return standing + (flat(standing) - flat(stop)).Unit * (distance or 10)
end

-- Out of the cab, off toward the buildings, and gone. Doesn't yield.
function Passengers.letOut(npc: Model?, car: Model?, standing: Vector3, stop: Vector3, speed: number?)
	if not npc or not npc.Parent then
		return
	end
	task.spawn(function()
		local away = Passengers.awayFrom(standing, stop)
		Passengers.getOut(npc, car, standing, away)
		local humanoid = npc:FindFirstChildOfClass("Humanoid")
		if humanoid and speed then
			humanoid.WalkSpeed = speed
		end
		Passengers.walkTo(npc, away, 5)
		npc:Destroy()
	end)
end

return Passengers
