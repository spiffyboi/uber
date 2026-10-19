-- The cutscenes of chapters 9 and 10, added to StoryScenes (which plays a
-- scene step by its `scene` name -- see Story.client):
--
--   friday     -- chapter 9 opens on the phone's lock screen: Friday, 8:41
--                 PM. Then the camera's where the driver's wing mirror is,
--                 looking back at him through the side window as the cab
--                 drives itself through the rain (see SelfDrive), his hands
--                 turning the wheel, and he talks: about not sleeping, about
--                 not getting out. Flashes of all of it in between (see
--                 Flashbacks). Then he's stuck in traffic.
--   flat       -- chapter 9, Quarry Houses: the gun out of the door; in the
--                 front door of the twelfth-floor flat, Teddy at the family
--                 photograph, a man coming out of the kitchen behind him with
--                 a knife. The player shoots (see Shooting): three in the man,
--                 one in Teddy. Footsteps above. Down the stairs, out, into
--                 the cab.
--   teddyDies  -- chapter 9, by Greaves Park: the wound, pressing on it, the
--                 tape, and the long pull back to the whole city.
--   phoneCall  -- chapter 9's end: Ray, on the phone.
--   frontStep  -- chapter 10, Ray's front step at half six: coffee, the
--                 cloth, Danny, the keys.
--   rayDrives  -- chapter 10: Ray at the wheel, the driver beside him, to
--                 the depot.
--   depot      -- chapter 10: the girl at the bus window; a man walking up
--                 the road, slowed right down; the shots; out of the door
--                 onto the pavement; the player shoots back.
--   collapse   -- chapter 10's end: his hand, his shoulder, the ground.
--
-- Everything moved here -- the people, the cab when it drives -- is moved
-- on this screen only; the server puts the things that matter where they
-- end up (see StoryService).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))
local StoryConfig = require(Shared:WaitForChild("StoryConfig"))
local Joints = require(Shared:WaitForChild("Joints"))

local Cutscene = require(script.Parent.Cutscene)
local CarSystems = require(script.Parent.CarSystems)
local Screen = require(script.Parent.Screen)
local Phone = require(script.Parent.Phone)
local StoryScenes = require(script.Parent.StoryScenes)
local SelfDrive = require(script.Parent.SelfDrive)
local Flashbacks = require(script.Parent.Flashbacks)
local Shooting = require(script.Parent.Shooting)

local kit = StoryScenes.kit
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local WALK_ANIMATION_ID = "rbxassetid://913402848" -- the passengers' walk
local BLOOD = Color3.fromRGB(96, 18, 20)

-- What these scenes have put out, so it can all be taken away: `scene`
-- for things that go when a scene ends, `chapter` for things that run on
-- through the chapter's later scenes (Teddy's wound; Ray and the driver's
-- double in chapter 10).
local held = {
	scene = {} :: { any },
	chapter = {} :: { any },
}

local function keep(list: { any }, thing: any): any
	table.insert(list, thing)
	return thing
end

local function release(list: { any })
	for i = #list, 1, -1 do
		local thing = list[i]
		if typeof(thing) == "Instance" then
			thing:Destroy()
		elseif typeof(thing) == "RBXScriptConnection" then
			thing:Disconnect()
		elseif type(thing) == "function" then
			pcall(thing)
		elseif type(thing) == "table" and thing.stop then
			pcall(thing.stop)
		end
		list[i] = nil
	end
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = workspace
	return p
end

-- Someone the server's just put out for a scene (see StoryService's cast),
-- once they've arrived on this screen whole: the world streams in, and a
-- scene that went ahead without them broke (seen live: Ray at his front
-- step, a moment after he was spawned). Waits a few seconds at most.
local function arrived(name: string): Model?
	local started = os.clock()
	while os.clock() - started < 6 do
		local model = workspace:FindFirstChild("Passenger_" .. name) :: Model?
		if model and model:FindFirstChild("HumanoidRootPart") and model:FindFirstChild("Head") and model:FindFirstChild("LeftUpperLeg") and model:FindFirstChild("LeftLowerLeg") and model:FindFirstChild("LeftFoot") then
			return model
		end
		task.wait(0.1)
	end
	return workspace:FindFirstChild("Passenger_" .. name) :: Model?
end

local function head(model: Model?, fallback: Vector3): Vector3
	return kit.headOf(model, fallback)
end

local function partPos(model: Model?, name: string, fallback: Vector3): Vector3
	local p = kit.partOf(model, name)
	return if p then p.Position else fallback
end

-- A joint's per-frame Transform held to whatever `value()` says, until the
-- returned function's called.
local function hold(model: Model?, joint: string, value: () -> CFrame): () -> ()
	local j = Joints.find(model, joint) :: any
	if not j then
		return function() end
	end
	local connection = RunService.Stepped:Connect(function()
		if j.Parent then
			j.Transform = value()
		end
	end)
	return function()
		connection:Disconnect()
		if j.Parent then
			j.Transform = CFrame.new()
		end
	end
end

-- A copy of the player's own character, standing (pinned by its root), to
-- be moved about in a scene while the real one sits in the cab.
local function copyOfPlayer(): Model?
	local character = player.Character
	if not character then
		return nil
	end
	local was = character.Archivable
	character.Archivable = true
	local double = character:Clone()
	character.Archivable = was
	if not double then
		return nil
	end
	double.Name = "DriverDouble"
	for _, d in double:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ForceField") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Weld") and d.Name == "SeatWeld" then
			d:Destroy()
		end
	end
	local humanoid = double:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
		humanoid.EvaluateStateMachine = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	double.Parent = workspace
	return double
end

-- Keeps the player's own body out of sight, every frame, while a double
-- stands in for them (in chapter 10 they were seen twice over: sat in the
-- cab and on the step -- reported). Returns the connection; disconnect it
-- (and show them again) when the scene's done with the double.
local function keepPlayerHidden(): RBXScriptConnection
	return RunService.RenderStepped:Connect(function()
		local character = player.Character
		if character then
			for _, p in character:GetDescendants() do
				if p:IsA("BasePart") then
					p.LocalTransparencyModifier = 1
				end
			end
		end
	end)
end

-- Hides the traffic (see TrafficVisuals) within `radius` of `center`, on
-- this screen, every frame, until the returned function's called -- then
-- shows it all again.
local function hideTrafficNear(center: Vector3, radius: number): () -> ()
	local hidden: { [Instance]: boolean } = {}
	local function show(car: Instance, visible: boolean)
		for _, p in car:GetDescendants() do
			if p:IsA("BasePart") then
				p.LocalTransparencyModifier = if visible then 0 else 1
			end
		end
	end
	local connection = RunService.RenderStepped:Connect(function()
		local folder = workspace:FindFirstChild("TrafficVisuals")
		if not folder then
			return
		end
		-- (Only touching a car's parts as it comes in or goes out of range.)
		for _, car in folder:GetChildren() do
			local anchor = if car:IsA("Model") then car.PrimaryPart or car:FindFirstChildWhichIsA("BasePart") else nil
			local near = anchor ~= nil and (anchor.Position - center).Magnitude < radius
			if near and not hidden[car] then
				hidden[car] = true
				show(car, false)
			elseif not near and hidden[car] then
				hidden[car] = nil
				show(car, true)
			end
		end
	end)
	return function()
		connection:Disconnect()
		for car in hidden do
			if car.Parent then
				show(car, true)
			end
		end
	end
end

-- How high `model`'s root sits above a seat it's sat on, and above the
-- ground standing.
local function heights(model: Model): (number, number)
	return kit.heights(model)
end

-- Walks a pinned rig along `points` (ground positions) over `seconds`,
-- legs going. Doesn't yield. `speed` scales the stride (a hurry, a crawl).
local function walk(model: Model?, points: { Vector3 }, seconds: number, speed: number?): RBXScriptConnection?
	if not model or #points < 2 then
		return nil
	end
	local _, standing = heights(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local track = nil
	if animator then
		local animation = Instance.new("Animation")
		animation.AnimationId = WALK_ANIMATION_ID
		track = animator:LoadAnimation(animation)
		track.Looped = true
		track:Play(0.1, 1, speed or 1)
	end
	local lengths, total = {}, 0
	for i = 2, #points do
		lengths[i] = (flat(points[i]) - flat(points[i - 1])).Magnitude
		total += lengths[i]
	end
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local d = math.clamp((os.clock() - started) / seconds, 0, 1) * total
		local walked = 0
		for i = 2, #points do
			if d <= walked + lengths[i] or i == #points then
				local a = points[i - 1]
				local b = points[i]
				local f = if lengths[i] > 0 then math.clamp((d - walked) / lengths[i], 0, 1) else 1
				local at = a:Lerp(b, f) + Vector3.new(0, standing, 0)
				local dir = flat(b - a)
				if dir.Magnitude > 0.05 and model.Parent then
					model:PivotTo(CFrame.lookAt(at, at + dir))
				end
				break
			end
			walked += lengths[i]
		end
		if d >= total then
			connection:Disconnect()
			if track then
				track:Stop(0.2)
			end
		end
	end)
	return connection
end

-- A rig's arms on a steering wheel, turning it with `steer()` (-1 .. 1).
local function armsOnWheel(model: Model?, steer: () -> number): () -> ()
	local undo = {}
	local function turn(sign: number): CFrame
		return CFrame.Angles(0, 0, steer() * 0.35 * sign)
	end
	table.insert(undo, hold(model, "LeftShoulder", function()
		return kit.WHEEL_SHOULDER * turn(1)
	end))
	table.insert(undo, hold(model, "LeftElbow", function()
		return kit.WHEEL_ELBOW
	end))
	table.insert(undo, hold(model, "RightShoulder", function()
		return CFrame.Angles(math.rad(40), math.rad(-20), math.rad(-30)) * turn(1)
	end))
	table.insert(undo, hold(model, "RightElbow", function()
		return kit.WHEEL_ELBOW
	end))
	return function()
		for _, fn in undo do
			fn()
		end
	end
end

-- A dark stain on `on` (a body part), `size` across, at `offset` from it.
local function stain(on: BasePart?, size: Vector3, offset: CFrame): BasePart?
	if not on then
		return nil
	end
	local p = part("Stain", size, on.CFrame * offset, BLOOD, Enum.Material.SmoothPlastic)
	kit.weldTo(p, on, offset)
	p.Parent = on.Parent
	return p
end

-- Something held in `model`'s `side` hand (a knife, a pistol, a cup...).
local function inHand(model: Model?, side: string, thing: BasePart, offset: CFrame): BasePart?
	local hand = kit.partOf(model, side .. "Hand")
	if not hand then
		thing:Destroy()
		return nil
	end
	kit.weldTo(thing, hand, offset)
	thing.Parent = model
	return thing
end

local function knife(): BasePart
	local handle = part("Knife", Vector3.new(0.18, 0.5, 0.22), CFrame.new(), Color3.fromRGB(30, 24, 20), Enum.Material.Wood)
	local blade = part("Blade", Vector3.new(0.05, 1.1, 0.24), CFrame.new(0, -0.8, 0.02), Color3.fromRGB(200, 204, 210), Enum.Material.Metal)
	blade.Reflectance = 0.3
	kit.weldTo(blade, handle, CFrame.new(0, -0.8, 0.02))
	blade.Parent = handle
	return handle
end

-- A pistol for someone to hold (welded, not the anchored scene prop).
local function heldPistol(): BasePart
	local pistol = kit.makePistol()
	pistol.Anchored = false
	return pistol
end

-- Down onto the ground, over `seconds`: tipped back (or forward) flat.
local function fall(model: Model?, seconds: number, forward: boolean?)
	if not model then
		return
	end
	local from = model:GetPivot()
	local _, standing = heights(model)
	local to = from * CFrame.new(0, -standing + 0.6, if forward then -1.6 else 1.6) * CFrame.Angles(math.rad(if forward then -86 else 86), 0, 0)
	task.spawn(function()
		local started = os.clock()
		while model.Parent do
			local a = math.clamp((os.clock() - started) / seconds, 0, 1)
			model:PivotTo(from:Lerp(to, a * a))
			if a >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
	end)
end

-- A jolt: knocked back a little and straight back up.
local function jolt(model: Model?, amount: number)
	if not model then
		return
	end
	local from = model:GetPivot()
	model:PivotTo(from * CFrame.new(0, 0, amount) * CFrame.Angles(math.rad(-8), 0, 0))
	task.delay(0.12, function()
		if model.Parent then
			model:PivotTo(from)
		end
	end)
end

-- The camera on a few keyframes (each { t, eye(), target() }), easing
-- between them.
local function keyframes(frames, fov: number)
	Cutscene.shot(function(t)
		local i = 1
		while i < #frames and t > frames[i + 1].t do
			i += 1
		end
		local a, b = frames[i], frames[math.min(i + 1, #frames)]
		local f = if b.t > a.t then math.clamp((t - a.t) / (b.t - a.t), 0, 1) else 1
		f = f * f * (3 - 2 * f)
		local eye = a.eye():Lerp(b.eye(), f)
		local target = a.target():Lerp(b.target(), f)
		return CFrame.lookAt(eye, target)
	end, fov)
end

-- Says a line, or holds a beat. (In Studio only, for checking shots: set
-- the workspace attribute DebugHoldShot to a shot's name and the scene
-- waits on it until it's changed.)
local studio = RunService:IsStudio()
local function play(line, say)
	if studio and line.shot then
		while workspace:GetAttribute("DebugHoldShot") == line.shot do
			task.wait(0.1)
		end
	end
	if line.text then
		say(line)
	else
		task.wait(line.beat or 1.5)
	end
end

local function sceneEnded()
	release(held.scene)
end

table.insert(StoryScenes.onAbort, function()
	release(held.scene)
	release(held.chapter)
	kit.storeLighting(false)
	Flashbacks.clear()
	CarSystems.setDriverVisible(false)
end)

-- =====================================================================
-- Chapter 9
-- =====================================================================

-- The phone's lock screen, close up: the time, the day, what's waiting.
local function lockScreen(day: string, notes: { { string } }): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "LockScreen"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.new(0, 0, 0)
	back.BorderSizePixel = 0
	back.Parent = gui
	local phone = Instance.new("Frame")
	phone.Name = "Phone"
	phone.AnchorPoint = Vector2.new(0.5, 0.5)
	phone.Position = UDim2.fromScale(0.5, 0.5)
	phone.Size = UDim2.fromScale(0.3, 0.92)
	phone.BackgroundColor3 = Color3.fromRGB(16, 18, 30)
	phone.BorderSizePixel = 0
	phone.Parent = back
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 0.5
	aspect.Parent = phone
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.06, 0)
	corner.Parent = phone
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(40, 44, 80), Color3.fromRGB(10, 10, 18))
	gradient.Rotation = 90
	gradient.Parent = phone
	local function label(text: string, y: number, h: number, size: number, bold: boolean, transparency: number?): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.08, y)
		l.Size = UDim2.fromScale(0.84, h)
		l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
		l.TextScaled = true
		l.TextColor3 = Color3.fromRGB(240, 240, 248)
		l.TextTransparency = transparency or 0
		l.Text = text
		l.Parent = phone
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = size
		limit.Parent = l
		return l
	end
	local time = Phone.timeText():gsub(" [AP]M", "")
	label(day, 0.1, 0.05, 26, false, 0.1)
	label(time, 0.15, 0.13, 110, true)
	for i, note in notes do
		local card = Instance.new("Frame")
		card.Position = UDim2.fromScale(0.06, 0.36 + (i - 1) * 0.13)
		card.Size = UDim2.fromScale(0.88, 0.115)
		card.BackgroundColor3 = Color3.fromRGB(230, 232, 240)
		card.BackgroundTransparency = 0.82
		card.BorderSizePixel = 0
		card.Parent = phone
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.18, 0)
		c.Parent = card
		local from = Instance.new("TextLabel")
		from.BackgroundTransparency = 1
		from.Position = UDim2.fromScale(0.05, 0.08)
		from.Size = UDim2.fromScale(0.9, 0.3)
		from.Font = Enum.Font.GothamBold
		from.TextScaled = true
		from.TextXAlignment = Enum.TextXAlignment.Left
		from.TextColor3 = Color3.fromRGB(245, 245, 250)
		from.Text = note[1]
		from.Parent = card
		local body = from:Clone()
		body.Font = Enum.Font.Gotham
		body.Position = UDim2.fromScale(0.05, 0.42)
		body.Size = UDim2.fromScale(0.9, 0.5)
		body.TextWrapped = true
		body.TextColor3 = Color3.fromRGB(215, 215, 225)
		body.Text = note[2]
		body.Parent = card
	end
	return gui
end

local function fridayShot(name: string)
	CarSystems.setDriverVisible(true)
	if name == "wing" then
		-- Out on the driver's wing mirror, looking back along the cab at
		-- him through the side window, the street sliding past behind.
		-- (Out past the door pillar: nearer in, it cut the picture in two.)
		Cutscene.look(function()
			return kit.fromSeat(-3.1, 2.4, -1.9)
		end, function()
			return kit.fromSeat(-0.3, 2.45, 0.2)
		end, 44)
	elseif name == "wheel" then
		-- His hands on the wheel, from the seat beside him.
		Cutscene.look(function()
			return kit.fromSeat(1.0, 2.75, -0.1)
		end, function()
			return kit.fromSeat(-0.6, 1.7, -1.4)
		end, 50)
	elseif name == "road" then
		-- Over his shoulder from the back seat, out through the windshield.
		Cutscene.look(function()
			return kit.fromSeat(1.5, 3.1, 2.0)
		end, function()
			return kit.fromSeat(-0.2, 2.2, -14)
		end, 62)
	elseif name == "jam" then
		-- Behind and above the cab: the queue of brake lights ahead.
		Cutscene.look(function()
			return kit.fromSeat(4, 6.5, 13)
		end, function()
			return kit.fromSeat(0, 2.2, -26)
		end, 50)
	end
end

function StoryScenes.friday(step, say: (any) -> (), stillOn: () -> boolean, r)
	Cutscene.begin()
	local lock = keep(held.scene, lockScreen("Friday", {
		{ "Ray", "Six o'clock, St. Brigid's hall. Front row's for family but I saved you a seat." },
		{ "Det. Calder", "Friday. The old man you drove. He's called Teddy. Don't go anywhere with him." },
		{ "Mom", "Missed call (2)" },
	}))
	fridayShot("wing")
	Flashbacks.prepare()
	local path = r and r.path
	local drive = nil
	if path then
		drive = keep(held.scene, SelfDrive.start(path, (step.drive and step.drive.seconds) or 38))
	end
	keep(held.scene, armsOnWheel(player.Character, function()
		return if drive then drive.steer() else 0
	end))
	local current = nil
	for _, line in step.lines do
		if not stillOn() then
			break
		end
		if line.flash then
			Flashbacks.show(line.flash, 1.15)
			continue
		end
		if line.shot == "phone" then
			task.wait(line.beat or 4)
			local back = lock:FindFirstChild("Back") :: Frame
			TweenService:Create(back, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
			for _, d in back:GetDescendants() do
				if d:IsA("Frame") then
					TweenService:Create(d, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
				elseif d:IsA("TextLabel") then
					TweenService:Create(d, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
				end
			end
			task.wait(0.8)
			lock.Enabled = false
			continue
		end
		if line.shot ~= current then
			current = line.shot
			fridayShot(line.shot)
		end
		if line.action == "jamMoves" and drive then
			drive.jamMoves()
		end
		play(line, say)
	end
	sceneEnded()
	Flashbacks.clear()
	Cutscene.finish()
end

-- ===== The flat =====

local function inFlat(x: number, y: number, z: number): Vector3
	return CityConfig.FLAT_ORIGIN + Vector3.new(x, 0.5 + y, z)
end

local DOORWAY_EYE = Vector3.new(-4.5, 5.2, -7.9)
-- The flat's half-width (as FlatBuilder's HALF_X): the kitchen door's in
-- the wall there.
local HALF_FLAT_X = 9

-- An arm held out at `lift` degrees, every frame (any kind of joint -- see
-- Joints). Returns the function that lets it go.
local function raise(model: Model?, side: string, lift: number): () -> ()
	local shoulder = hold(model, side .. "Shoulder", function()
		return CFrame.Angles(math.rad(lift), 0, 0)
	end)
	local elbow = hold(model, side .. "Elbow", function()
		return CFrame.Angles(math.rad(25), 0, 0)
	end)
	return function()
		shoulder()
		elbow()
	end
end

function StoryScenes.flat(step, say: (any) -> (), stillOn: () -> boolean, r)
	local place = StoryConfig.PLACES.quarryHouses
	local toKerb = flat(place.standing - place.stop).Unit
	local forward = Vector3.yAxis:Cross(toKerb)
	local door = place.standing + toKerb * 9
	local teddy = arrived("Teddy")
	local man = arrived("KnifeMan")
	Cutscene.begin()
	local current = nil
	local inside = false
	local pistol: BasePart? = nil
	local double: Model? = nil
	for _, line in step.lines do
		if not stillOn() then
			break
		end
		if line.shot ~= current then
			current = line.shot
			local shot = line.shot
			if shot == "pocket" then
				-- The gun out of the door pocket.
				CarSystems.setDriverVisible(false)
				pistol = keep(held.scene, kit.makePistol())
				kit.placePistol(pistol :: BasePart, kit.doorPocket())
				Cutscene.look(function()
					return kit.fromSeat(-0.5, 1.7, 0.4)
				end, function()
					return kit.doorPocket().Position
				end, 50)
			elseif shot == "lobby" then
				-- Out of the cab and across the sidewalk to the tower's door,
				-- the gun down by his side. From the road behind.
				if pistol then
					pistol:Destroy()
				end
				double = keep(held.scene, copyOfPlayer())
				if double then
					-- (Barrel down the fingers, grip in the palm.)
					inHand(double, "Right", heldPistol(), CFrame.new(0, -0.35, 0.05) * CFrame.Angles(math.rad(-90), 0, 0))
					local _, standing = heights(double)
					local start = place.standing + forward * 1.5
					double:PivotTo(CFrame.lookAt(start + Vector3.new(0, standing, 0), door + Vector3.new(0, standing, 0)))
					keep(held.scene, walk(double, { start, door }, 3.2, 1.2))
				end
				Cutscene.look(function()
					return place.stop - toKerb * 12 - forward * 12 + Vector3.new(0, 4, 0)
				end, function()
					return door + Vector3.new(0, 3, 0)
				end, 50)
			elseif shot == "black" then
				-- Up the stairs: on black, with the camera already in the room so
				-- its light has come up by the time we see it (see the chapel).
				Cutscene.black(true, 0.5)
				task.wait(0.55)
				if double then
					double:Destroy()
					double = nil
				end
				kit.storeLighting(true, Color3.fromRGB(72, 62, 54), 1.1)
				inside = true
				Cutscene.look(function()
					return CityConfig.FLAT_ORIGIN + DOORWAY_EYE
				end, function()
					return inFlat(3, 4, 4.5)
				end, 55)
			elseif shot == "doorway" then
				Cutscene.look(function()
					return CityConfig.FLAT_ORIGIN + DOORWAY_EYE
				end, function()
					return inFlat(3, 3.6, 3.6)
				end, 55)
				Cutscene.black(false, 1.2)
			elseif shot == "photo" then
				-- From beside his shoulder (from behind him, he was in the way).
				Cutscene.dolly(function()
					return CFrame.lookAt(inFlat(4.9, 4.6, 4.2), inFlat(3, 3.95, 5.7))
				end, function()
					return CFrame.lookAt(inFlat(4.4, 4.4, 4.7), inFlat(3, 3.95, 5.7))
				end, 4, 34)
			elseif shot == "teddy" then
				-- In front of his face, whichever way it's turned (from a
				-- fixed spot it caught the back of his head).
				Cutscene.look(function()
					local h = kit.partOf(teddy, "Head")
					if h then
						return (h.CFrame * CFrame.new(-0.6, 0.15, -2.4)).Position
					end
					return inFlat(0.9, 5.0, 5.6)
				end, function()
					return head(teddy, inFlat(3, 5, 3.9))
				end, 42)
			elseif shot == "kitchen" then
				Cutscene.look(function()
					return inFlat(-4, 4.6, -1)
				end, function()
					return inFlat(6, 3.4, 1.8)
				end, 52)
			elseif shot == "after" then
				Cutscene.look(function()
					return inFlat(-2.5, 4.2, -5.5)
				end, function()
					return inFlat(3, 2, 2.6)
				end, 55)
			elseif shot == "stairs" then
				-- Down the stairwell at a run, from his own eyes.
				local s = CityConfig.STAIRS_ORIGIN
				local y0 = s.Y + 0.5
				local route = {
					{ t = 0, eye = Vector3.new(s.X - 2, y0 + 5, s.Z - 3) },
					{ t = 1.5, eye = Vector3.new(s.X - 2, y0 - 4, s.Z + 13) },
					{ t = 2.0, eye = Vector3.new(s.X + 2, y0 - 4, s.Z + 14) },
					{ t = 3.5, eye = Vector3.new(s.X + 2, y0 - 13, s.Z - 1) },
					{ t = 4.0, eye = Vector3.new(s.X - 2, y0 - 13, s.Z - 2) },
					{ t = 5.5, eye = Vector3.new(s.X - 2, y0 - 22, s.Z + 13) },
				}
				Cutscene.shot(function(t)
					local i = 1
					while i < #route - 1 and t > route[i + 1].t do
						i += 1
					end
					local a, b = route[i], route[i + 1]
					local f = math.clamp((t - a.t) / (b.t - a.t), 0, 1)
					local eye = a.eye:Lerp(b.eye, f) + Vector3.new(0, math.abs(math.sin(t * 11)) * 0.35, 0)
					local ahead = b.eye + (b.eye - a.eye).Unit * 3 + Vector3.new(0, -2, 0)
					return CFrame.lookAt(eye, ahead) * CFrame.Angles(0, 0, math.sin(t * 5.5) * 0.05)
				end, 64)
			elseif shot == "street" then
				-- Out of the door and across the sidewalk to the cab: Teddy
				-- holding his shoulder, the driver round to his own door.
				kit.storeLighting(false)
				inside = false
				double = keep(held.scene, copyOfPlayer())
				local backDoor = place.standing - toKerb * 2 + forward * -1.5
				if teddy then
					local _, standing = heights(teddy)
					teddy:PivotTo(CFrame.lookAt(door + Vector3.new(0, standing, 0), backDoor + Vector3.new(0, standing, 0)))
					keep(held.scene, walk(teddy, { door, backDoor }, 2.6, 1.3))
				end
				if double then
					local _, standing = heights(double)
					local around = place.stop + forward * 5.5
					double:PivotTo(CFrame.lookAt(door + Vector3.new(0, standing, 0) - forward * 1.5, around + Vector3.new(0, standing, 0)))
					keep(held.scene, walk(double, { door - forward * 1.5, place.standing + forward * 3, around, place.stop + forward * 2 - toKerb * 3 }, 3.6, 1.5))
				end
				Cutscene.look(function()
					return place.stop - toKerb * 14 - forward * 10 + Vector3.new(0, 4.5, 0)
				end, function()
					return place.standing + Vector3.new(0, 3, 0)
				end, 50)
				task.delay(line.beat and line.beat - 0.7 or 3.8, function()
					Cutscene.black(true, 0.6)
				end)
			end
		end

		if line.action == "drawGun" and pistol then
			-- His hand comes down and it's gone, up out of the shot.
			task.delay(1.0, function()
				if pistol and pistol.Parent then
					kit.glide(pistol, kit.doorPocket, function()
						return kit.seatCFrame() * CFrame.new(-1.3, 2.6, -0.3)
					end, 0.8)
				end
			end)
		elseif line.action == "manComes" and man then
			-- Out of the kitchen and across the carpet, a knife held low.
			inHand(man, "Right", knife(), CFrame.new(0, -0.2, 0) * CFrame.Angles(math.rad(90), 0, 0))
			keep(held.scene, walk(man, { inFlat(HALF_FLAT_X + 1.6, 0, 1), inFlat(3.4, 0, 2.1) }, 4.2, 0.6))
		end

		if line.shot == "doorway" and line.speaker == "MAN" then
			-- He's seen. Teddy turns his head; the knife comes up.
			keep(held.scene, hold(teddy, "Neck", function()
				return CFrame.Angles(0, math.rad(55), 0)
			end))
			keep(held.scene, raise(man, "Right", 115))
		end

		if line.action == "shoot" then
			local manDown = false
			Shooting.run({
				eye = function()
					return CityConfig.FLAT_ORIGIN + DOORWAY_EYE + Vector3.new(0.2, -0.2, 1.2)
				end,
				target = function()
					return partPos(man, "UpperTorso", inFlat(3.4, 3, 2.1))
				end,
				shake = 1.1,
				fov = 50,
				-- (The second shot's the one that goes into Teddy: no marker.)
				markers = { [1] = true, [3] = true, [4] = true },
				shots = {
					function()
						jolt(man, 0.4)
					end,
					-- The second one goes past him, into Teddy's shoulder.
					function()
						jolt(teddy, 0.3)
						if teddy then
							keep(held.chapter, stain(kit.partOf(teddy, "RightUpperArm"), Vector3.new(0.7, 0.8, 0.75), CFrame.new(0, 0.35, 0)))
							keep(held.chapter, stain(kit.partOf(teddy, "UpperTorso"), Vector3.new(0.7, 0.8, 0.2), CFrame.new(0.55, 0.35, -0.5)))
							keep(held.scene, hold(teddy, "LeftShoulder", function()
								return CFrame.Angles(math.rad(80), math.rad(-40), math.rad(30))
							end))
						end
					end,
					function()
						jolt(man, 0.5)
					end,
					function()
						if not manDown then
							manDown = true
							fall(man, 0.55)
						end
					end,
				},
			})
		elseif line.shot ~= "aim" then
			play(line, say)
		end
	end
	if inside then
		kit.storeLighting(false)
	end
	sceneEnded()
	Cutscene.finish()
end

-- ===== Teddy, by the park =====

local function cassette(): BasePart
	local tape = part("Cassette", Vector3.new(0.75, 0.48, 0.12), CFrame.new(), Color3.fromRGB(26, 26, 30))
	local labelGui = Instance.new("SurfaceGui")
	labelGui.Face = Enum.NormalId.Front
	labelGui.CanvasSize = Vector2.new(150, 96)
	labelGui.LightInfluence = 0.5
	labelGui.Parent = tape
	-- (Labelled both sides: whichever way his hand holds it.)
	task.defer(function()
		local back = labelGui:Clone()
		back.Face = Enum.NormalId.Back
		back.Parent = tape
	end)
	local sticker = Instance.new("TextLabel")
	sticker.Position = UDim2.fromScale(0.08, 0.1)
	sticker.Size = UDim2.fromScale(0.84, 0.42)
	sticker.BackgroundColor3 = Color3.fromRGB(236, 230, 210)
	sticker.BorderSizePixel = 0
	sticker.Font = Enum.Font.PermanentMarker
	sticker.TextScaled = true
	sticker.TextColor3 = Color3.fromRGB(30, 30, 90)
	sticker.Text = "V. -- TUES"
	sticker.Parent = labelGui
	for _, x in { 0.32, 0.68 } do
		local spool = Instance.new("Frame")
		spool.AnchorPoint = Vector2.new(0.5, 0.5)
		spool.Position = UDim2.fromScale(x, 0.74)
		spool.Size = UDim2.fromOffset(20, 20)
		spool.BackgroundColor3 = Color3.fromRGB(200, 196, 186)
		spool.BorderSizePixel = 0
		spool.Parent = labelGui
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = spool
	end
	return tape
end

function StoryScenes.teddyDies(step, say: (any) -> (), stillOn: () -> boolean, r)
	local teddy = kit.backSeat() or arrived("Teddy")
	Cutscene.begin()
	kit.cabLight(true)
	local current = nil
	local hand: BasePart? = nil
	local tape: BasePart? = nil
	local function shoulder(): Vector3
		return partPos(teddy, "RightUpperArm", kit.fromSeat(1.6, 2.2, 3))
	end
	for _, line in step.lines do
		if not stillOn() then
			break
		end
		if line.shot ~= current then
			current = line.shot
			local shot = line.shot
			if shot == "outside" then
				CarSystems.setDriverVisible(false)
				Cutscene.dolly(function()
					return CFrame.lookAt(kit.fromSeat(-12, 4.5, -18), kit.fromSeat(0.5, 1.5, 1.5))
				end, function()
					return CFrame.lookAt(kit.fromSeat(-8, 3.6, -12), kit.fromSeat(0.5, 1.5, 1.5))
				end, 6, 45)
			elseif shot == "back" then
				kit.shot("back", teddy)
			elseif shot == "driver" then
				kit.shot("driver", teddy)
			elseif shot == "wound" or shot == "press" then
				CarSystems.setDriverVisible(false)
				Cutscene.look(function()
					return kit.fromSeat(0.45, 2.7, 1.6)
				end, shoulder, if shot == "wound" then 30 else 38)
			elseif shot == "tape" then
				-- Close on the tape in his hand, from the front seats' side.
				CarSystems.setDriverVisible(false)
				local function at(): Vector3
					return if tape then tape.Position else kit.fromSeat(0.8, 2, 2.4)
				end
				Cutscene.look(function()
					local from = kit.fromSeat(0.6, 2.6, 0.9)
					return at() + (from - at()).Unit * 1.5
				end, at, 40)
			elseif shot == "pullout" then
				-- From his face, back to the two of them, out of the cab, and up
				-- and up over the whole city.
				CarSystems.setDriverVisible(true)
				keyframes({
					{ t = 0, eye = function()
						return kit.fromSeat(0.9, 2.6, 2.0)
					end, target = function()
						return head(teddy, kit.fromSeat(1.1, 2.4, 3))
					end },
					{ t = 4, eye = function()
						return kit.fromSeat(1.5, 2.9, -0.5)
					end, target = function()
						return kit.fromSeat(0.5, 2.3, 1.6)
					end },
					{ t = 8, eye = function()
						return kit.fromSeat(-7, 6, -7)
					end, target = function()
						return kit.fromSeat(0.4, 1.5, 0.8)
					end },
					{ t = 17, eye = function()
						return kit.fromSeat(-70, 170, -90)
					end, target = function()
						return kit.fromSeat(0, 0, 0)
					end },
				}, 52)
			end
		end
		if line.action == "blood" and teddy then
			keep(held.chapter, stain(kit.partOf(teddy, "UpperTorso"), Vector3.new(1.3, 1.2, 0.25), CFrame.new(0.3, 0.1, -0.5)))
		elseif line.action == "press" then
			-- A hand on it, pressing; red to the wrist.
			hand = keep(held.scene, part("PressingHand", Vector3.new(0.34, 0.42, 0.24), CFrame.new(), BLOOD))
			local sleeve = keep(held.scene, part("PressingSleeve", Vector3.new(0.42, 1.3, 0.42), CFrame.new(), Color3.fromRGB(64, 58, 46), Enum.Material.Fabric))
			local pressing = hand :: BasePart
			keep(held.scene, RunService.RenderStepped:Connect(function()
				-- On the front of his shoulder, the arm reaching back to it from
				-- the front seats.
				local front = kit.seatCFrame().LookVector
				local at = shoulder() + front * 0.55 + Vector3.new(0, 0.1 + math.sin(os.clock() * 3) * 0.03, 0)
				local cf = CFrame.lookAt(at, at + front)
				pressing.CFrame = cf
				sleeve.CFrame = cf * CFrame.new(0, 0, -0.85) * CFrame.Angles(math.rad(90), 0, 0)
			end))
		elseif line.action == "tape" and teddy then
			if hand then
				hand:Destroy()
				hand = nil
			end
			-- Held up between the seats, its label to the driver. (In his
			-- hand it ended up down in the seat, out of the shot.)
			keep(held.scene, raise(teddy, "Left", 55))
			tape = keep(held.scene, cassette())
			local held_ = tape :: BasePart
			keep(held.scene, RunService.RenderStepped:Connect(function()
				local at = kit.fromSeat(0.95, 2.35, 1.9)
				held_.CFrame = CFrame.lookAt(at, kit.fromSeat(0.7, 2.6, 0.7)) * CFrame.Angles(0, math.pi, 0)
			end))
		elseif line.action == "dies" and teddy then
			if tape then
				tape:Destroy()
				tape = nil
			end
			release(held.scene)
			-- His head goes over; that's all.
			keep(held.chapter, hold(teddy, "Neck", function()
				return CFrame.Angles(math.rad(-30), 0, math.rad(-25))
			end))
		end
		play(line, say)
	end
	sceneEnded()
	kit.cabLight(false)
	-- (Left running: the phone rings next, over the same picture.)
end

-- ===== Ray rings =====

local function callCard(name: string): (ScreenGui, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "CallCard"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.fromScale(0.5, 0.14)
	card.Size = UDim2.fromOffset(300, 74)
	card.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	card.BackgroundTransparency = 0.1
	card.BorderSizePixel = 0
	card.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 16)
	c.Parent = card
	local who = Instance.new("TextLabel")
	who.BackgroundTransparency = 1
	who.Position = UDim2.fromOffset(18, 10)
	who.Size = UDim2.new(1, -36, 0, 30)
	who.Font = Enum.Font.GothamBold
	who.TextSize = 24
	who.TextXAlignment = Enum.TextXAlignment.Left
	who.TextColor3 = Color3.fromRGB(240, 240, 248)
	who.Text = name
	who.Parent = card
	local status = who:Clone()
	status.Position = UDim2.fromOffset(18, 40)
	status.Size = UDim2.new(1, -36, 0, 24)
	status.Font = Enum.Font.Gotham
	status.TextSize = 18
	status.TextColor3 = Color3.fromRGB(52, 199, 89)
	status.Text = "calling..."
	status.Parent = card
	return gui, status
end

function StoryScenes.phoneCall(step, say: (any) -> (), stillOn: () -> boolean, r)
	Cutscene.begin()
	local gui, status = callCard(step.caller or "Unknown")
	keep(held.scene, gui)
	local answered = 0
	keep(held.scene, RunService.RenderStepped:Connect(function()
		if answered > 0 then
			local s = math.floor(os.clock() - answered)
			status.Text = string.format("%02d:%02d", s // 60, s % 60)
		else
			status.TextTransparency = 0.5 + math.sin(os.clock() * 8) * 0.5
		end
	end))
	local current = nil
	for _, line in step.lines do
		if not stillOn() then
			break
		end
		if line.shot ~= current then
			current = line.shot
			if line.shot == "ringing" or line.shot == "call" then
				kit.shot("driver")
				if line.shot == "call" and answered == 0 then
					answered = os.clock()
					status.TextTransparency = 0
				end
			elseif line.shot == "hangup" then
				answered = -1
				status.Text = "Call ended"
				status.TextTransparency = 0
				status.TextColor3 = Color3.fromRGB(200, 200, 210)
				CarSystems.setDriverVisible(false)
				Cutscene.dolly(function()
					return CFrame.lookAt(kit.fromSeat(-5, 3.2, -6), kit.fromSeat(0.3, 2, 0.5))
				end, function()
					return CFrame.lookAt(kit.fromSeat(-12, 6, -16), kit.fromSeat(0.3, 1.6, 0.5))
				end, line.beat or 4, 50)
			end
		end
		play(line, say)
	end
	sceneEnded()
	Cutscene.finish()
end

-- =====================================================================
-- Chapter 10
-- =====================================================================

-- Ray and the driver's double, for all three of the chapter's opening
-- scenes.
local saturday = {
	ray = nil :: Model?,
	double = nil :: Model?,
}

local function rayOf(): Model?
	return saturday.ray or arrived("Ray")
end

-- His front step: where the stoop is, which way's the road.
local function frontStep()
	local place = StoryConfig.PLACES.rayHome
	local toKerb = flat(place.standing - place.stop).Unit
	local along = Vector3.yAxis:Cross(toKerb)
	-- The building's front is BUILDING_EDGE out from the avenue's middle;
	-- the stop is LANE_WIDTH * 1.5.
	local wall = place.stop + toKerb * (CityConfig.BUILDING_EDGE - CityConfig.LANE_WIDTH * 1.5)
	local stoop = Vector3.new(wall.X, 1.2, wall.Z) - toKerb * 1.2
	return place, toKerb, along, stoop
end

local function sitOn(model: Model?, top: Vector3, facing: Vector3)
	if not model then
		return
	end
	local sat = heights(model)
	local at = top + Vector3.new(0, sat, 0)
	model:PivotTo(CFrame.lookAt(at, at + facing))
end

local function cup(): BasePart
	local c = part("Cup", Vector3.new(0.5, 0.42, 0.42), CFrame.new(), Color3.fromRGB(240, 238, 232))
	c.Shape = Enum.PartType.Cylinder
	return c
end

function StoryScenes.frontStep(step, say: (any) -> (), stillOn: () -> boolean, r)
	local place, toKerb, along, stoop = frontStep()
	local road = -toKerb
	Cutscene.begin()
	CarSystems.setDriverVisible(false)
	keep(held.chapter, keepPlayerHidden())
	-- The stoop, and his front door behind it; a suitcase.
	keep(held.chapter, part("Stoop", Vector3.new(2.4, 1, 5), CFrame.lookAt(stoop + Vector3.new(0, 0.5, 0), stoop + Vector3.new(0, 0.5, 0) + road), Color3.fromRGB(140, 134, 124), Enum.Material.Concrete))
	keep(held.chapter, part("FrontDoor", Vector3.new(3.4, 7, 0.3), CFrame.lookAt(stoop + toKerb * 1.3 + Vector3.new(0, 4.7, 0), stoop + toKerb * 1.3 + Vector3.new(0, 4.7, 0) + road), Color3.fromRGB(60, 80, 70), Enum.Material.Wood))
	keep(held.chapter, part("Suitcase", Vector3.new(1.2, 1.8, 2.4), CFrame.lookAt(stoop - along * 3.4 + road * 0.4 + Vector3.new(0, 0.9, 0), stoop - along * 3.4 + road * 1.4 + Vector3.new(0, 0.9, 0)), Color3.fromRGB(120, 60, 40), Enum.Material.Leather))
	local top = stoop + Vector3.new(0, 1, 0)
	local ray = rayOf()
	saturday.ray = ray
	if ray then
		Joints.bend(ray, kit.SIT)
		-- Hands down on his knees (held, not bent: they'll be on the wheel
		-- next). (Held out further, their hands loomed at the camera.)
		for _, name in { "LeftShoulder", "RightShoulder" } do
			keep(held.chapter, hold(ray, name, function()
				return CFrame.Angles(math.rad(12), 0, 0)
			end))
		end
		for _, name in { "LeftElbow", "RightElbow" } do
			keep(held.chapter, hold(ray, name, function()
				return CFrame.Angles(math.rad(45), 0, 0)
			end))
		end
		sitOn(ray, top - along * 1.2, road)
		keep(held.chapter, inHand(ray, "Right", cup(), CFrame.new(0, -0.35, -0.1)))
	end
	local double = copyOfPlayer()
	saturday.double = double
	if double then
		keep(held.chapter, double)
		Joints.bend(double, kit.SIT)
		Joints.bend(double, { LeftShoulder = CFrame.Angles(math.rad(12), 0, 0), RightShoulder = CFrame.Angles(math.rad(12), 0, 0), LeftElbow = CFrame.Angles(math.rad(45), 0, 0), RightElbow = CFrame.Angles(math.rad(45), 0, 0) })
		sitOn(double, top + along * 1.2, road)
		-- Teddy's blood still in the creases of his hands.
		for _, name in { "LeftHand", "RightHand" } do
			local h = kit.partOf(double, name)
			if h then
				h.Color = h.Color:Lerp(BLOOD, 0.45)
			end
		end
	end
	local function rayHead(): Vector3
		return head(ray, top - along * 1.2 + Vector3.new(0, 2.5, 0))
	end
	local function youHead(): Vector3
		return head(double, top + along * 1.2 + Vector3.new(0, 2.5, 0))
	end
	local cloth: BasePart? = nil
	local current = nil
	for _, line in step.lines do
		if not stillOn() then
			break
		end
		if line.shot ~= current then
			current = line.shot
			local shot = line.shot
			if shot == "arrive" then
				Cutscene.dolly(function()
					return CFrame.lookAt(place.stop + road * 14 + along * 12 + Vector3.new(0, 4, 0), top + Vector3.new(0, 1.6, 0))
				end, function()
					return CFrame.lookAt(place.stop + road * 10 + along * 7 + Vector3.new(0, 3.5, 0), top + Vector3.new(0, 1.6, 0))
				end, 6, 45)
			elseif shot == "step" then
				Cutscene.look(function()
					return top + road * 6 + along * 1.5 + Vector3.new(0, 2.4, 0)
				end, function()
					return top + Vector3.new(0, 1.7, 0)
				end, 48)
			elseif shot == "ray" then
				Cutscene.look(function()
					return youHead() + road * 2.8 + (rayHead() - youHead()) * 0.2 + Vector3.new(0, 0.1, 0)
				end, rayHead, 44)
			elseif shot == "you" then
				Cutscene.look(function()
					return rayHead() + road * 2.8 + (youHead() - rayHead()) * 0.2 + Vector3.new(0, 0.1, 0)
				end, youHead, 44)
			elseif shot == "cloth" or shot == "keys" then
				Cutscene.look(function()
					return top + road * 3.2 + Vector3.new(0, 2.6, 0)
				end, function()
					return partPos(ray, "RightHand", top + Vector3.new(0, 1.5, 0))
				end, 40)
			elseif shot == "hands" then
				Cutscene.look(function()
					return partPos(double, "RightHand", top) + road * 1.5 + Vector3.new(0, 1.1, 0)
				end, function()
					return (partPos(double, "RightHand", top) + partPos(double, "LeftHand", top)) / 2
				end, 40)
			end
		end
		if line.action == "cloth" and ray then
			keep(held.scene, raise(ray, "Right", 65))
			cloth = keep(held.chapter, inHand(ray, "Right", part("Cloth", Vector3.new(0.7, 0.08, 0.9), CFrame.new(), Color3.fromRGB(236, 232, 220), Enum.Material.Fabric), CFrame.new(0, -0.3, 0)))
		elseif line.action == "wipe" and double then
			release(held.scene)
			if cloth then
				cloth:Destroy()
			end
			-- The cloth between his hands, working at them.
			local wiping = keep(held.scene, part("Cloth", Vector3.new(0.7, 0.08, 0.9), CFrame.new(), Color3.fromRGB(236, 232, 220), Enum.Material.Fabric))
			keep(held.scene, RunService.RenderStepped:Connect(function()
				local mid = (partPos(double, "RightHand", top) + partPos(double, "LeftHand", top)) / 2
				wiping.CFrame = CFrame.new(mid + along * math.sin(os.clock() * 5) * 0.25) * CFrame.Angles(0, os.clock() * 0.5, 0.3)
			end))
			task.delay(line.beat or 3, function()
				-- A little of it comes off. Not all.
				for _, name in { "LeftHand", "RightHand" } do
					local h = kit.partOf(double, name)
					local skin = kit.partOf(player.Character, name)
					if h and skin then
						h.Color = skin.Color:Lerp(BLOOD, 0.2)
					end
				end
			end)
		elseif line.action == "keys" and ray then
			release(held.scene)
			keep(held.scene, raise(ray, "Right", 60))
			keep(held.scene, inHand(ray, "Right", part("Keys", Vector3.new(0.3, 0.06, 0.6), CFrame.new(), Color3.fromRGB(200, 190, 150), Enum.Material.Metal), CFrame.new(0, -0.3, 0)))
		end
		play(line, say)
	end
	release(held.scene)
	-- (Left running into the drive.)
end

-- ===== Ray drives =====

-- Where the two of them sit across the front of the cab (from the player's
-- own seat, which is in the middle): Ray at the wheel, the driver beside.
local RAY_X = -0.75
local BESIDE_X = 1.15

function StoryScenes.rayDrives(step, say: (any) -> (), stillOn: () -> boolean, r)
	Cutscene.begin()
	Cutscene.black(true, 0.6)
	task.wait(0.65)
	CarSystems.setDriverVisible(false)
	-- Off the step: the stoop and the rest packed away; the two of them in
	-- the cab, Ray at the wheel.
	release(held.chapter)
	keep(held.chapter, keepPlayerHidden())
	local ray = rayOf()
	local double = copyOfPlayer()
	saturday.double = double
	if double then
		keep(held.chapter, double)
		Joints.bend(double, kit.SIT)
	end
	local car = workspace:FindFirstChild(player.Name .. "_Car")
	local seat = car and car:FindFirstChild("DriveSeat") :: BasePart?
	-- Sat as high as the player's own body sits in that seat (placed by the
	-- rigs' own sums they sank into the seats, slumped -- reported).
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local sitting = if seat and root then seat.CFrame:PointToObjectSpace(root.Position) else Vector3.new(0, 2, 0)
	local function seatAt(x: number, model: Model?)
		if not seat or not model then
			return
		end
		model:PivotTo(seat.CFrame * CFrame.new(x, sitting.Y + 0.15, sitting.Z))
	end
	-- Ray at the wheel (it's left of the cab's middle, where the player's own
	-- seat is), the driver beside him. (At 1.95 the driver sat half out of
	-- the passenger door -- seen in a capture.)
	seatAt(RAY_X, ray)
	seatAt(BESIDE_X, double)
	local path = r and r.path
	local riders = {}
	for _, m in { ray, double } do
		if m then
			table.insert(riders, m)
		end
	end
	local drive = nil
	if path then
		drive = keep(held.chapter, SelfDrive.start(path, (step.drive and step.drive.seconds) or 50, riders))
	end
	keep(held.chapter, armsOnWheel(ray, function()
		return if drive then drive.steer() else 0
	end))
	local function rayHead(): Vector3
		return head(ray, kit.fromSeat(RAY_X, 2.45, 0.2))
	end
	local function youHead(): Vector3
		return head(double, kit.fromSeat(BESIDE_X, 2.45, 0.2))
	end
	local current = nil
	local first = true
	for _, line in step.lines do
		if not stillOn() then
			break
		end
		if line.shot ~= current then
			current = line.shot
			local shot = line.shot
			if shot == "rayWheel" then
				-- (Between the two of them, so the driver's not in the way.)
				Cutscene.look(function()
					return kit.fromSeat(0.25, 2.85, -1.9)
				end, rayHead, 60)
			elseif shot == "you" then
				Cutscene.look(function()
					return kit.fromSeat(0.15, 2.85, -1.9)
				end, youHead, 60)
			elseif shot == "twoShot" then
				Cutscene.look(function()
					return kit.fromSeat(0.95, 3.0, 2.8)
				end, function()
					return kit.fromSeat(0.95, 2.4, -1)
				end, 62)
			elseif shot == "street" then
				Cutscene.look(function()
					return kit.fromSeat(-9, 4, -20)
				end, function()
					return kit.fromSeat(0.5, 1.8, 0)
				end, 52)
			end
			if first then
				first = false
				Cutscene.black(false, 1.2)
			end
		end
		play(line, say)
	end
	-- Pulled up by the bus. (Left running into the depot.)
	while drive and not drive.finished() and stillOn() do
		task.wait(0.1)
	end
	if drive then
		-- Stopped where it is; the server puts the real cab there.
		drive.stop()
	end
end

-- ===== The depot =====

-- The slow motion: the picture drained and heavy, everything moved by hand
-- slowed right down.
local function slowLook(on: boolean)
	if on then
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "SlowMotion"
		grade.Saturation = -0.35
		grade.Contrast = 0.2
		grade.Parent = Lighting
		local blur = Instance.new("BlurEffect")
		blur.Name = "SlowMotionBlur"
		blur.Size = 3
		blur.Parent = Lighting
		keep(held.scene, grade)
		keep(held.scene, blur)
	else
		for _, name in { "SlowMotion", "SlowMotionBlur" } do
			local e = Lighting:FindFirstChild(name)
			if e then
				e:Destroy()
			end
		end
	end
end

-- The depot (chapter 10). The girl at the bus window. Then, slowed right
-- down, a man running round the corner from Wharf St, a pistol coming up;
-- four shots through the windscreen -- a flash and a bang each -- and Ray
-- goes over. Normal speed again: the driver ducks, falls out of his door
-- onto the pavement, and crouches round to the back of the cab. The man
-- comes on round the front, down the kerb side, looking for him -- and it's
-- the player's to shoot: real aim, three hits, eight seconds (see
-- Shooting). Too slow, and the man fires first: black, and the chapter's
-- end (StoryScenes.state.shotDown -- see the walk and collapse).
function StoryScenes.depot(step, say: (any) -> (), stillOn: () -> boolean, r)
	local place = StoryConfig.PLACES.depot
	local toKerb = flat(place.standing - place.stop).Unit
	local forward = Vector3.yAxis:Cross(toKerb)
	local ground = place.standing.Y
	local function onGround(v: Vector3): Vector3
		return Vector3.new(v.X, ground, v.Z)
	end
	local ray = rayOf()
	local double = saturday.double
	local girl = arrived("Rosie")
	local gunman = arrived("Gunman")
	StoryScenes.state.shotDown = nil
	Cutscene.begin()
	keep(held.chapter, keepPlayerHidden())
	-- No passing traffic in it (a car queued behind the cab filled one shot).
	keep(held.chapter, hideTrafficNear(place.stop, 90))
	local slow = 1
	local gun: BasePart? = nil
	local moving: RBXScriptConnection? = nil
	-- The girl waving at the window; Ray waving back.
	local wavePhase = 0
	keep(held.chapter, RunService.Heartbeat:Connect(function(dt)
		wavePhase += dt * slow
	end))
	if girl then
		keep(held.chapter, hold(girl, "RightShoulder", function()
			return CFrame.Angles(math.rad(150), 0, math.sin(wavePhase * 7) * 0.45)
		end))
	end
	local rayWave = nil
	local function gunmanAt(): Vector3
		return partPos(gunman, "UpperTorso", place.stop + forward * 20)
	end
	local function rayHead(): Vector3
		return head(ray, kit.fromSeat(RAY_X, 2.45, 0.2))
	end
	local function youHead(): Vector3
		return head(double, kit.fromSeat(BESIDE_X, 2.45, 0.2))
	end
	-- His way: from round the corner on Wharf St, past the end of the depot,
	-- up the pavement toward the front of the cab; later on round the kerb
	-- side toward its back.
	local gunStart = if gunman then onGround(gunman:GetPivot().Position) else onGround(place.standing + forward * 40 + toKerb * 34)
	local ahead = (gunStart - place.standing):Dot(forward)
	local corner = onGround(place.standing + toKerb * 3 + forward * ahead)
	local frontOfCab = onGround(place.standing + forward * 12 - toKerb * 1.5)
	-- (On the pavement edge, clear of the cab's side.)
	local besideCab = onGround(place.standing + forward * 1.5 - toKerb * 1.5)
	local nearBack = onGround(place.standing - forward * 4 - toKerb * 1.5)
	-- Where the driver ends up: crouched behind the cab's back bumper, at
	-- the kerb-side corner. (The cab's about 15 long and 6 wide, its middle
	-- at the stop: nearer in, the camera was inside its bodywork.)
	local hiding = onGround(place.stop - forward * 8.4 + toKerb * 2.2)
	local hideEye = hiding + Vector3.new(0, 2.4, 0) + toKerb * 0.9
	local function move(points: { Vector3 }, seconds: number, stride: number)
		if moving then
			moving:Disconnect()
		end
		moving = walk(gunman, points, seconds, stride)
		keep(held.chapter, moving)
	end
	local current = nil
	local fellOut = false
	for _, line in step.lines do
		if not stillOn() or StoryScenes.state.shotDown then
			break
		end
		if line.shot ~= current then
			current = line.shot
			local shot = line.shot
			if shot == "window" then
				-- Close on her at the bus window, from the forecourt.
				local bus = CityConfig.DEPOT_BUS
				Cutscene.look(function()
					-- Square on to the middle of her pane (a little further back
					-- along the bus, a window pillar was in the way).
					local h = head(girl, bus.Position + Vector3.new(0, 4, 0))
					return h - bus.RightVector * 3.6 - bus.LookVector * 1.3 + Vector3.new(0, -0.2, 0)
				end, function()
					return head(girl, bus.Position + Vector3.new(0, 4, 0))
				end, 40)
			elseif shot == "ray" or shot == "slowRay" then
				if not rayWave and ray then
					rayWave = keep(held.chapter, hold(ray, "RightShoulder", function()
						return CFrame.Angles(math.rad(120), 0, math.sin(wavePhase * 6) * 0.35)
					end))
				end
				-- (From between the two of them, well forward: nearer, his head
				-- filled the frame; further over, the driver's did.)
				Cutscene.look(function()
					return kit.fromSeat(0.25, 2.85, -1.9)
				end, rayHead, if shot == "slowRay" then 48 else 56)
			elseif shot == "corner" then
				-- Low on the pavement just ahead of the cab, up the street: the
				-- corner of the depot, and him coming round it. (From inside the
				-- cab, the windscreen pillar was in the way.)
				Cutscene.look(function()
					return onGround(place.standing + forward * 7 - toKerb * 1) + Vector3.new(0, 1.5, 0)
				end, gunmanAt, 40)
			elseif shot == "slowGun" then
				-- Low, just ahead of him and off to his side, wherever he's got
				-- to: the gun coming up. (From a fixed spot, if he'd already
				-- reached it, it looked up into the sky.)
				Cutscene.look(function()
					local body = gunmanAt()
					local toCab = flat(kit.fromSeat(0.9, 0, 0) - body)
					toCab = if toCab.Magnitude > 0.1 then toCab.Unit else -forward
					local side = Vector3.yAxis:Cross(toCab)
					return body + toCab * 4.2 + side * 1.8 + Vector3.new(0, -0.9, 0)
				end, function()
					return partPos(gunman, "RightHand", gunmanAt())
				end, 46)
			elseif shot == "slowYou" then
				Cutscene.look(function()
					return kit.fromSeat(0.15, 2.8, -1.85)
				end, youHead, 44)
			elseif shot == "fire" then
				-- From the kerb ahead, across the windscreen: the flashes, the
				-- glass, Ray.
				Cutscene.look(function()
					return kit.fromSeat(3.4, 3.0, -7.2)
				end, function()
					return kit.fromSeat(-0.2, 2.5, -1.4)
				end, 44)
			elseif shot == "duck" then
				-- His own eyes, going down below the dash. Normal speed again.
				-- (And the girl's gone from the window: her mother's pulled her
				-- down.)
				slow = 1
				slowLook(false)
				if girl then
					kit.setHidden(girl, true)
				end
				local started = os.clock()
				Cutscene.shot(function()
					local a = math.clamp((os.clock() - started) / 0.4, 0, 1)
					local eye = kit.fromSeat(BESIDE_X, 2.45, 0.1):Lerp(kit.fromSeat(BESIDE_X - 0.2, 1.0, -0.4), a)
					return CFrame.lookAt(eye, eye + kit.seatCFrame().LookVector * 3 + Vector3.new(0, -1.2 * a, 0)) * CFrame.Angles(0, 0, a * 0.3)
				end, 62)
			elseif shot == "fall" then
				-- The passenger door, from the back of the cab, low: out, and
				-- down onto the pavement.
				Cutscene.look(function()
					return kit.fromSeat(5.5, 1.3, 5.5)
				end, function()
					return kit.fromSeat(2.6, 0.8, -0.2)
				end, 50)
			elseif shot == "crouch" then
				-- Crouched, along the side of the cab to the back of it.
				Cutscene.look(function()
					return hiding - forward * 5 + toKerb * 2.5 + Vector3.new(0, 1.6, 0)
				end, function()
					return partPos(double, "UpperTorso", hiding + Vector3.new(0, 1.5, 0))
				end, 50)
			elseif shot == "peek" then
				-- Round the back corner, along the kerb side: him, coming.
				if double then
					kit.setHidden(double, true)
				end
				Cutscene.look(function()
					return hideEye
				end, gunmanAt, 50)
			elseif shot == "silence" then
				-- Up high: the cab, the man down on the pavement, the bus. Quiet.
				-- Her window empty -- her mother's pulled her down.
				if girl then
					kit.setHidden(girl, true)
				end
				Cutscene.dolly(function()
					return CFrame.lookAt(kit.fromSeat(-12, 12, 14), kit.fromSeat(1, 0, -5))
				end, function()
					return CFrame.lookAt(kit.fromSeat(-16, 20, 20), kit.fromSeat(1, 0, -5))
				end, line.beat or 4.5, 50)
			end
		end

		if line.action == "runs" and gunman then
			-- Round the corner at a run -- and from the first step, slowed.
			slow = 0.3
			slowLook(true)
			move({ gunStart, corner, frontOfCab }, 12, 0.6)
		elseif line.action == "gunUp" and gunman then
			-- The pistol out and up, pointing the right way: down his arm.
			gun = keep(held.chapter, inHand(gunman, "Right", heldPistol(), CFrame.new(0, -0.35, 0.05) * CFrame.Angles(math.rad(-90), 0, 0)))
			local raised = os.clock()
			keep(held.chapter, hold(gunman, "RightShoulder", function()
				return CFrame.Angles(math.rad(math.clamp((os.clock() - raised) / 2.4, 0, 1) * 90), 0, 0)
			end))
		elseif line.action == "fire" then
			-- Four shots into the windscreen, slowed: a flash and a bang each.
			-- The glass stars; Ray goes over.
			task.spawn(function()
				for k = 1, 4 do
					if gun then
						kit.muzzleFlash((gun.CFrame * CFrame.new(0, 0.02, -0.7)).Position, 0.55)
					end
					Screen.flash(Color3.fromRGB(255, 240, 220), 0.25, 0.25)
					local hit = kit.fromSeat(-0.4 + (k - 2.5) * 0.35, 2.7 + ((k % 2) - 0.5) * 0.4, -1.95)
					keep(held.chapter, part("Crack", Vector3.new(0.9, 0.06, 0.06), CFrame.new(hit) * CFrame.Angles(0, 0, k), Color3.fromRGB(230, 236, 240), Enum.Material.Glass))
					keep(held.chapter, part("Crack", Vector3.new(0.06, 0.8, 0.06), CFrame.new(hit) * CFrame.Angles(0, 0, -k * 0.7), Color3.fromRGB(230, 236, 240), Enum.Material.Glass))
					if k == 2 and ray then
						if rayWave then
							rayWave()
						end
						keep(held.chapter, hold(ray, "Waist", function()
							return CFrame.Angles(math.rad(-38), 0, math.rad(8))
						end))
						keep(held.chapter, hold(ray, "Neck", function()
							return CFrame.Angles(math.rad(-30), 0, math.rad(12))
						end))
					end
					task.wait(0.6)
				end
			end)
		elseif line.action == "fallOut" then
			fellOut = true
			-- The player's own body out of the cab too, behind it (it's
			-- theirs to walk, after), kept hidden till then.
			CarSystems.getOut(CFrame.lookAt(hiding + Vector3.new(0, 3, 0), hiding + Vector3.new(0, 3, 0) + forward))
			if double then
				local from = double:GetPivot()
				local out = onGround(place.standing - toKerb * 2.2 + forward * 0.3)
				local lying = CFrame.lookAt(out + Vector3.new(0, 0.7, 0), out + Vector3.new(0, 0.7, 0) + forward) * CFrame.Angles(math.rad(80), 0, 0)
				local started = os.clock()
				local c
				c = RunService.RenderStepped:Connect(function()
					local a = math.clamp((os.clock() - started) / 0.7, 0, 1)
					if double.Parent then
						double:PivotTo(from:Lerp(lying, a * a))
					end
					if a >= 1 then
						c:Disconnect()
					end
				end)
				keep(held.scene, c)
			end
		elseif line.action == "crouch" and double then
			-- Up into a crouch, and along to the back corner.
			release(held.scene)
			local lower = kit.partOf(double, "LeftLowerLeg")
			local foot = kit.partOf(double, "LeftFoot")
			local sat = heights(double)
			local crouchHeight = (if lower then lower.Size.Y else 1.2) + (if foot then foot.Size.Y else 0.3) + sat - 0.2
			keep(held.chapter, hold(double, "Waist", function()
				return CFrame.Angles(math.rad(-30), 0, 0)
			end))
			local from = onGround(place.standing - toKerb * 2.2 + forward * 0.3)
			local started = os.clock()
			local c
			c = RunService.RenderStepped:Connect(function()
				local a = math.clamp((os.clock() - started) / 2.6, 0, 1)
				local at = from:Lerp(hiding, a * a * (3 - 2 * a)) + Vector3.new(0, crouchHeight, 0)
				if double.Parent then
					double:PivotTo(CFrame.lookAt(at, at - forward))
				end
				if a >= 1 then
					c:Disconnect()
				end
			end)
			keep(held.scene, c)
		elseif line.action == "comes" and gunman then
			-- Round the front of the cab and down its kerb side, toward the
			-- back of it, looking.
			move({ onGround(gunman:GetPivot().Position), besideCab, nearBack }, 11, 0.7)
		end

		if line.action == "shoot" then
			if double then
				kit.setHidden(double, true)
			end

			local dropped = Shooting.run({
				eye = function()
					return hideEye
				end,
				target = gunmanAt,
				shake = 1.1,
				fov = 52,
				real = {
					hitAt = gunmanAt,
					radius = 1.4,
					hits = 3,
					timeLimit = 8,
					onHit = function(n)

						if n >= 3 then
							if moving then
								moving:Disconnect()
							end
							fall(gunman, 0.6)
						else
							jolt(gunman, 0.45)
						end
					end,
				},
			})
			if not dropped then
				-- He got there first.
				if moving then
					moving:Disconnect()
				end
				StoryScenes.state.shotDown = true
				Cutscene.look(function()
					return hideEye
				end, gunmanAt, 50)
				if gunman then
					local raised = os.clock()
					keep(held.chapter, hold(gunman, "RightShoulder", function()
						return CFrame.Angles(math.rad(math.clamp((os.clock() - raised) / 0.3, 0, 1) * 90), 0, 0)
					end))
				end
				task.wait(0.45)
				if gun then
					kit.muzzleFlash((gun.CFrame * CFrame.new(0, 0.02, -0.7)).Position)
				end
				Screen.flash(Color3.new(1, 1, 1), 1, 0.6)
				-- Down onto the pavement, and black.
				local started = os.clock()
				local facing = (gunmanAt() - hideEye) * Vector3.new(1, 0, 1)
				facing = if facing.Magnitude > 0.1 then facing.Unit else forward
				Cutscene.shot(function()
					local a = math.clamp((os.clock() - started) / 1.2, 0, 1)
					a = a * a
					local at = hideEye:Lerp(hideEye - Vector3.new(0, 2.2, 0), a)
					return CFrame.lookAt(at, at + facing + Vector3.new(0, -0.3 + a * 0.6, 0)) * CFrame.Angles(0, 0, a * math.rad(80))
				end, 55)
				task.wait(0.9)
				Cutscene.black(true, 0.8)
				task.wait(2.5)
			end

		elseif line.shot ~= "aim" then
			play(line, say)
		end
	end
	slowLook(false)
	release(held.scene)
	if StoryScenes.state.shotDown then
		-- Left on black, for the end (see collapse, and the end of the
		-- chapter).
		return
	end
	-- The double's done; the player's own body, behind the cab, is theirs.
	if double then
		double:Destroy()
	end
	saturday.double = nil
	release(held.chapter)
	if fellOut and player.Character then
		kit.setHidden(player.Character, false)
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	Cutscene.finish()
	camera.CameraType = Enum.CameraType.Custom
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

-- ===== The end of chapter 10 =====

local fallen = { double = nil :: Model?, props = nil :: { BasePart }?, facing = nil :: Vector3? }

function StoryScenes.collapse(step, say: (any) -> (), stillOn: () -> boolean, r)
	if StoryScenes.state.shotDown then
		-- He never got up from behind the cab: it's black already. Hold it.
		Cutscene.begin()
		Cutscene.black(true, 0)
		task.wait(1)
		return
	end
	local character = player.Character
	local double = copyOfPlayer()
	fallen.double = double
	if character then
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and double then
			double:PivotTo(root.CFrame)
		end
	end
	Cutscene.begin()
	if character then
		kit.setHidden(character, true)
	end
	local function eye(): Vector3
		return partPos(double, "Head", Vector3.zero) + Vector3.new(0, 0.2, 0)
	end
	local current = nil
	for _, line in step.lines do
		if not stillOn() then
			break
		end
		if line.shot ~= current then
			current = line.shot
			local shot = line.shot
			if shot == "hand" then
				-- Looking down at his own right hand, held up, palm up. Red.
				-- (A hand made for the shot, not the double's: on an avatar the
				-- shirt's pattern covers the arm and the hand, and the blood
				-- didn't show.)
				if double then
					for _, p in double:GetDescendants() do
						if p:IsA("BasePart") then
							p.LocalTransparencyModifier = 1
						end
					end
				end
				local from = eye()
				local facing = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
				local root = kit.partOf(double, "HumanoidRootPart")
				if root then
					facing = root.CFrame.LookVector * Vector3.new(1, 0, 1)
				end
				facing = if facing.Magnitude > 0.1 then facing.Unit else Vector3.zAxis
				local at = from + facing * 1.95 + Vector3.new(0, -1.2, 0)
				-- Palm up, tipped toward his eyes.
				local palm = CFrame.lookAt(at, at + facing) * CFrame.Angles(math.rad(28), 0, 0)
				local skinPart = kit.partOf(double, "RightHand")
				local skin = if skinPart then skinPart.Color else Color3.fromRGB(204, 142, 105)
				local SLEEVE = Color3.fromRGB(42, 46, 56)
				local bits = {}
				local function bit(size: Vector3, offset: CFrame, color: Color3)
					table.insert(bits, keep(held.chapter, part("BloodyHand", size, palm * offset, color)))
				end
				bit(Vector3.new(0.7, 0.16, 0.8), CFrame.new(), skin)
				for i = 0, 3 do
					bit(Vector3.new(0.15, 0.13, 0.48), CFrame.new(-0.27 + i * 0.18, 0.03, -0.6) * CFrame.Angles(math.rad(18), 0, 0), skin)
				end
				bit(Vector3.new(0.16, 0.14, 0.45), CFrame.new(0.43, 0.04, -0.12) * CFrame.Angles(0, math.rad(-35), 0), skin)
				bit(Vector3.new(0.78, 0.55, 0.9), CFrame.new(0, -0.08, 0.84), SLEEVE)
				-- The blood: across the palm, and down two of the fingers.
				bit(Vector3.new(0.52, 0.02, 0.62), CFrame.new(-0.04, 0.085, -0.02), BLOOD)
				bit(Vector3.new(0.13, 0.02, 0.3), CFrame.new(-0.09, 0.105, -0.5) * CFrame.Angles(math.rad(18), 0, 0), BLOOD)
				bit(Vector3.new(0.13, 0.02, 0.22), CFrame.new(0.09, 0.105, -0.45) * CFrame.Angles(math.rad(18), 0, 0), BLOOD)
				fallen.props = bits
				fallen.facing = facing
				Cutscene.shot(function(t)
					local sway = CFrame.Angles(math.noise(t * 0.7, 1) * 0.04, math.noise(t * 0.6, 2) * 0.04, math.noise(t * 0.5, 3) * 0.03)
					return CFrame.lookAt(from, at) * sway
				end, 50)
			elseif shot == "shoulder" then
				-- And his shoulder: dark, spreading, through his shirt. Seen
				-- close, from in front of him; his face out of the top of the
				-- shot, the cab beside him. (From his own eyes, the shoulder was
				-- too close to read; from his left, the cab's in the way.)
				for _, b in fallen.props or {} do
					b:Destroy()
				end
				fallen.props = nil
				if double then
					for _, p in double:GetDescendants() do
						if p:IsA("BasePart") then
							p.LocalTransparencyModifier = 0
						end
					end
					-- Thin, so they lie on his shirt like a soak, not stand off
					-- it like boxes: the front of his chest by the shoulder, the
					-- front of his arm, and over the top of the shoulder.
					local torso = kit.partOf(double, "UpperTorso")
					local arm = kit.partOf(double, "LeftUpperArm")
					if torso then
						local s = torso.Size
						keep(held.chapter, stain(torso, Vector3.new(s.X * 0.3, s.Y * 0.45, 0.04), CFrame.new(-s.X * 0.3, s.Y * 0.2, -s.Z / 2 - 0.01)))
						keep(held.chapter, stain(torso, Vector3.new(s.X * 0.14, s.Y * 0.3, 0.04), CFrame.new(-s.X * 0.22, -s.Y * 0.1, -s.Z / 2 - 0.01)))
					end
					if arm then
						local s = arm.Size
						keep(held.chapter, stain(arm, Vector3.new(s.X * 0.75, s.Y * 0.45, 0.04), CFrame.new(-s.X * 0.05, s.Y * 0.2, -s.Z / 2 - 0.01)))
						keep(held.chapter, stain(arm, Vector3.new(s.X * 0.8, 0.04, s.Z * 0.7), CFrame.new(0, s.Y / 2 + 0.01, -s.Z * 0.1)))
					end
				end
				local root = kit.partOf(double, "HumanoidRootPart")
				local base = if root then root.CFrame else CFrame.lookAt(eye(), eye() + (fallen.facing or Vector3.zAxis))
				local shoulderAt = partPos(double, "LeftUpperArm", base.Position) + Vector3.new(0, 0.25, 0)
				local towardChest = (partPos(double, "UpperTorso", shoulderAt) - shoulderAt) * Vector3.new(1, 0, 1)
				local look = shoulderAt + towardChest * 0.35 - Vector3.new(0, 0.35, 0)
				local from = look + base.LookVector * 3.4 + base.RightVector * 0.3 + Vector3.new(0, 0.1, 0)
				Cutscene.shot(function(t)
					local sway = CFrame.Angles(math.noise(t * 0.7, 4) * 0.02, math.noise(t * 0.6, 5) * 0.02, 0)
					return CFrame.lookAt(from, look) * sway
				end, 40)
			elseif shot == "fall" then
				for _, b in fallen.props or {} do
					b:Destroy()
				end
				fallen.props = nil
				-- Down from his own eyes again: not his head, or his hair.
				if double then
					for _, p in double:GetDescendants() do
						if p:IsA("BasePart") and (p.Name == "Head" or p:FindFirstAncestorOfClass("Accessory")) then
							p.LocalTransparencyModifier = 1
						end
					end
				end
				local from = eye()
				local started = os.clock()
				local length = line.beat or 2
				-- The way he was facing (the camera's just been looking back at
				-- him).
				local facing = fallen.facing or camera.CFrame.LookVector * Vector3.new(1, 0, 1)
				facing = if facing.Magnitude > 0.1 then facing.Unit else Vector3.zAxis
				if double then
					fall(double, length * 0.8, true)
				end
				Cutscene.shot(function()
					local a = math.clamp((os.clock() - started) / length, 0, 1)
					a = a * a
					local at = from:Lerp(from + Vector3.new(0, -4.2, 0) + facing * 0.5, a)
					return CFrame.lookAt(at, at + facing + Vector3.new(0, -0.4 - a, 0)) * CFrame.Angles(0, 0, a * math.rad(70))
				end, 55)
			elseif shot == "black" then
				Cutscene.black(true, 1.2)
			end
		end
		play(line, say)
	end
	-- Left on black, for the end card; put right when the chapter ends (see
	-- onChapterEnd below).
end

-- When a chapter ends on a scene still showing (chapter 10's black): the
-- player back on their feet where they fell.
table.insert(StoryScenes.onChapterEnd, function()
	if fallen.double then
		fallen.double:Destroy()
		fallen.double = nil
	end
	release(held.chapter)
	release(held.scene)
	saturday.ray, saturday.double = nil, nil
	local character = player.Character
	if character then
		kit.setHidden(character, false)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and not humanoid.SeatPart then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = humanoid
		end
	end
end)

return {}
