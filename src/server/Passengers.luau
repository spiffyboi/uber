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
	-- Arrives on a player's screen in one piece, not a limb at a time.
	npc.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.WalkSpeed = 8
	-- Stood waiting (pinned in place), a humanoid decides it's falling over
	-- -- confirmed live: in the FallingDown state the whole wait, and the
	-- moment it was let go to walk to the cab it toppled flat on the road.
	-- These people never need to fall over.
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	local height = standingHeight(npc)
	npc:PivotTo(CFrame.lookAt(standing + Vector3.new(0, height, 0), Vector3.new(facing.X, standing.Y + height, facing.Z)))
	root.Anchored = true
	npc.Parent = workspace
	return npc
end

-- Stands `npc` (pinned in place) on the ground at `spot`'s position,
-- facing the way `spot` does -- for putting people where a scene needs them.
function Passengers.place(npc: Model, spot: CFrame)
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	root.Anchored = true
	npc:PivotTo(spot + Vector3.new(0, standingHeight(npc), 0))
end

-- How the passenger's root sits relative to the back seat. (Measured live
-- from a passenger the seat itself had sat down: root a bit above the
-- cushion, facing the way the cab does.)
local SEATED_OFFSET = CFrame.new(0, 1.55, 0)

-- The sitting pose that comes with the passenger's own rig (its Animate
-- script lists it, under "sit"), playing for as long as they ride.
local function sitPose(npc: Model): AnimationTrack?
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local animate = npc:FindFirstChild("Animate")
	local sit = animate and animate:FindFirstChild("sit")
	local animation = sit and sit:FindFirstChildOfClass("Animation")
	if not animator or not animation then
		return nil
	end
	local track = animator:LoadAnimation(animation)
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	track:Play(0)
	return track
end

local riding: { [Model]: { weld: WeldConstraint, pose: AnimationTrack? } } = {}

-- Walks the passenger to the cab's rear door and puts them in the back.
-- Yields until they're in.
--
-- Not with Seat:Sit: a running cab is simulated by the driver's own
-- machine, and a server-run passenger sat in its seat that way kept
-- falling out onto the road (reported, every pickup with the engine on).
-- Instead they're held in place: their body's own physics switched off
-- (PlatformStand), welded straight to the seat, weightless and not
-- touching anything, in the sitting pose.
-- `instant`: straight into the seat from wherever they are, no walk (they
-- got in during a cutscene).
function Passengers.board(npc: Model, car: Model, instant: boolean?)
	local chassis = car.PrimaryPart
	local seat = car:FindFirstChild("PassengerSeat") :: BasePart?
	if not npc.Parent or not chassis or not seat then
		return
	end
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	if not instant then
		root.Anchored = false
		root:SetNetworkOwner(nil)
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
		-- To the rear door on whichever side of the cab they're on.
		local side = if (chassis.CFrame:PointToObjectSpace(root.Position)).X >= 0 then 1 else -1
		local door = (chassis.CFrame * CFrame.new(side * (chassis.Size.X / 2 + 1.5), 0, 3)).Position
		Passengers.walkTo(npc, door, 3)
		if not npc.Parent or not seat.Parent then
			return
		end
	end

	-- In.
	root.Anchored = true
	humanoid.PlatformStand = true
	for _, descendant in npc:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Massless = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	npc:PivotTo(seat.CFrame * SEATED_OFFSET)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "PassengerWeld"
	weld.Part0 = seat
	weld.Part1 = root
	weld.Parent = root
	root.Anchored = false
	riding[npc] = { weld = weld, pose = sitPose(npc) }
	npc.Destroying:Once(function()
		riding[npc] = nil
	end)
end

-- Is `npc` in the back of a cab right now?
function Passengers.isAboard(npc: Model?): boolean
	return npc ~= nil and riding[npc] ~= nil
end

-- Gets the passenger out of `car` on the side nearest `kerb` and stands them
-- there facing `toward`. Yields a moment.
--
-- Careful order: while they're sitting, the passenger is welded into the
-- cab, and a running cab is simulated by the driver's own machine (see
-- CarController) -- so moving them while that weld still exists over there
-- drags the whole cab round with them (confirmed: the cab spun to face the
-- sidewalk at every drop-off). So: cut the seat weld here first, freeze them
-- in place as a separate thing, give that a moment to reach the driver's
-- machine, and only then move them out.
function Passengers.getOut(npc: Model, car: Model?, kerb: Vector3, toward: Vector3)
	if not npc.Parent then
		return
	end
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	local ride = riding[npc]
	riding[npc] = nil
	if ride then
		ride.weld:Destroy()
		if ride.pose then
			ride.pose:Stop(0.2)
		end
	end
	root.Anchored = true
	task.wait(0.3)
	if not npc.Parent then
		return
	end
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
	humanoid.PlatformStand = false
	root.Anchored = false
	root:SetNetworkOwner(nil)
	humanoid:ChangeState(Enum.HumanoidStateType.Running)
end

-- Where someone dropped at `standing` (on the sidewalk, `stop` being the
-- kerb lane beside it) walks off to: into the buildings.
function Passengers.awayFrom(standing: Vector3, stop: Vector3, distance: number?): Vector3
	return standing + (flat(standing) - flat(stop)).Unit * (distance or 10)
end

-- Which way along the sidewalk from `standing` has more room before
-- anything's in the way (the avenues run along Z), and how much. `ignore`
-- is left out of the check (the person themselves, the cab).
function Passengers.clearWay(standing: Vector3, ignore: { Instance }): (Vector3, number)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local best, bestDistance = Vector3.zAxis, -1
	for _, direction in { Vector3.zAxis, -Vector3.zAxis } do
		local hit = workspace:Raycast(standing + Vector3.new(0, 2.5, 0), direction * 80, params)
		local distance = if hit then hit.Distance else 80
		if distance > bestDistance then
			best, bestDistance = direction, distance
		end
	end
	return best, bestDistance
end

-- Out of the cab, off up the sidewalk whichever way is clear, and gone.
-- Doesn't yield. (They used to head straight for the building behind
-- them, which read as walking into a wall.)
function Passengers.letOut(npc: Model?, car: Model?, standing: Vector3, stop: Vector3, speed: number?)
	if not npc or not npc.Parent then
		return
	end
	task.spawn(function()
		local way, room = Passengers.clearWay(standing, { npc, car :: Instance })
		Passengers.getOut(npc, car, standing, standing + way * 10)
		local humanoid = npc:FindFirstChildOfClass("Humanoid")
		if humanoid and speed then
			humanoid.WalkSpeed = speed
		end
		Passengers.walkTo(npc, standing, 1.5)
		local distance = math.clamp(room - 3, 6, 60)
		Passengers.walkTo(npc, standing + way * distance, distance / (if humanoid then humanoid.WalkSpeed else 8) + 1)
		npc:Destroy()
	end)
end

return Passengers
