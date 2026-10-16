-- Owns everything about being "in the car" for the rest of the session, from
-- the moment IntroCutscene.client.luau hands off through however long the
-- player keeps driving, and finally getting out:
--   * Driving: this machine drives the car itself (the server hands it
--     network ownership once the engine's on -- see CarController), so
--     steering answers the keys with no round trip to the server. Steering
--     eases in and out instead of snapping to full lock, and turns wider
--     the faster the car is going, which is what makes a straight line
--     easy to hold.
--   * Two cameras: a chase camera behind the cab (the default whenever the
--     engine's running) and the driver's-eye view from the seat (where you
--     start, parked, with the key and dash screen in front of you). V
--     switches between them; in the chase camera, hold the right mouse
--     button to look around and scroll to zoom.
--   * The dash screen: informational (engine state and controls) --
--     starting the car is the physical ignition key's job (a
--     ProximityPrompt built in CarBuilder, wired up in CarSpawner).
--   * A small readout: speed, and which street you're on.
--   * Getting out: Space, while the car is stationary, turns the engine off
--     if it was on, fades out, drops the player on the sidewalk beside the
--     car, and hands the camera back to Roblox's own third-person one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiKit = require(Shared:WaitForChild("UiKit"))
local CityConfig = require(Shared:WaitForChild("CityConfig"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local stopEngineRemote = remotes:WaitForChild("StopEngine")

local player = Players.LocalPlayer

local CarSystems = {}

-- True from start() until the player has got out again; start() runs
-- again every time they get back in (see CarReentry).
local active = false

function CarSystems.isActive(): boolean
	return active
end

-- While a cutscene's playing (see Cutscene), it has the camera: the driving
-- camera stops moving it and stops hiding the driver's body (the cutscene
-- decides that, shot by shot), and the keys stop driving -- the cab just
-- rolls to a stop. Afterwards the driving camera eases back in from
-- wherever the cutscene left it.
local cutscene = false
local onCutsceneEnded: (() -> ())? = nil

function CarSystems.setCutscene(on: boolean)
	if cutscene == on then
		return
	end
	cutscene = on
	-- Nothing on screen but the film: no "Start Engine" prompt popping up
	-- over a close-up (seen in a recording of the hold-up), and no Roblox
	-- menu buttons in the corner.
	game:GetService("ProximityPromptService").Enabled = not on
	pcall(function()
		game:GetService("StarterGui"):SetCore("TopbarEnabled", not on)
	end)
	if not on and onCutsceneEnded then
		onCutsceneEnded()
	end
end

-- The driver's body parts, for the cutscene to show or hide.
local driverParts: { BasePart } = {}
function CarSystems.setDriverVisible(visible: boolean)
	for _, part in driverParts do
		part.LocalTransparencyModifier = if visible then 0 else 1
	end
end

-- ===== Handling =====
local MAX_SPEED = 80 -- studs/second, roughly 55mph
local REVERSE_MAX_SPEED = 22
local ACCEL = 24 -- studs/second^2 under throttle
local BRAKE = 65 -- studs/second^2 pressing against the direction of travel
local COAST = 10 -- studs/second^2 with no input
-- The turning circle widens with speed: tight enough at parking speeds to
-- get out of a taxi rank, gentle on the open road.
local TURN_RADIUS = 17 -- studs, at full lock, standing still
local TURN_RADIUS_PER_SPEED = 0.5 -- extra studs of radius per stud/second
local MAX_YAW_RATE = 1.15 -- radians/second
-- How fast the wheel turns toward full lock, and back to centre, in
-- "full locks per second". Centring is quicker, so letting go of A/D
-- straightens the car up promptly.
local STEER_IN_RATE = 2.6
local STEER_OUT_RATE = 5
local MPH_PER_STUD = 0.7

-- ===== Driver's-eye camera =====
local LOOK_YAW_SPEED = math.rad(110) -- radians/second while A or D is held
local LOOK_YAW_MAX = math.rad(100) -- clamps short of looking straight back
-- (3.4: the seat sits 1.2 lower than it used to -- see CarBuilder -- and
-- the eye stays where it was.)
local CAM_OFFSET_POS = Vector3.new(0, 3.4, 0)
-- Slightly down, toward the road over the hood.
local CAM_PITCH = math.rad(-6)
local DRIVER_FOV = 74

-- ===== Chase camera =====
local CHASE_DISTANCE = 15
local CHASE_MIN_DISTANCE = 8
local CHASE_MAX_DISTANCE = 28
local CHASE_HEIGHT_RATIO = 0.36 -- camera height per stud of distance
local CHASE_FOV = 70
local CHASE_FOV_AT_SPEED = 82
local VIEW_BLEND_TIME = 0.6

local DEFAULT_FOV = 70

-- Hides, for the driver only, the bits of the cab's own mesh that sit
-- between their eyes and the road: the sun visor across the top of the
-- windshield, the wiper arms, and the taxi meter on the dash. Found by
-- casting a fan of rays through the windshield from the driving camera
-- rather than by name, since the mesh's parts are mostly unnamed "Union"s.
-- Kept: anything very close (the steering wheel), anything large (the body
-- shell, dash and bonnet), and anything below the dash line except small
-- clutter. LocalTransparencyModifier only affects this client's own view.
-- Confirmed live: before this, the windshield filled about a third of the
-- screen; after, it fills everything above the dash.
local function windshieldClutter(car: Model, eye: CFrame): { BasePart }
	local mesh = car:FindFirstChildWhichIsA("Model")
	if not mesh then
		return {}
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { mesh }

	local hidden: { [BasePart]: boolean } = {}
	for yaw = -40, 40, 3 do
		for pitch = -4, 34, 2 do
			local direction = (eye * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)).LookVector
			-- Walk along the ray: see-through or already-hidden parts are
			-- stepped past by switching off their CanQuery for the rest of
			-- this ray (fine on these mesh parts -- none of them collide).
			local stepped: { BasePart } = {}
			for _ = 1, 10 do
				local result = workspace:Raycast(eye.Position, direction * 5, params)
				if not result then
					break
				end
				local hit = result.Instance :: BasePart
				local largest = math.max(hit.Size.X, hit.Size.Y, hit.Size.Z)
				if hit.Transparency >= 0.5 or hidden[hit] then
					hit.CanQuery = false
					table.insert(stepped, hit)
				elseif result.Distance < 1.4 or largest >= 6 then
					break
				elseif pitch >= 3 or largest < 0.7 then
					hidden[hit] = true
					hit.CanQuery = false
					table.insert(stepped, hit)
				else
					break
				end
			end
			for _, part in stepped do
				part.CanQuery = true
			end
		end
	end

	local list = {}
	for part in hidden do
		table.insert(list, part)
	end
	return list
end

-- Well above whatever priority Roblox's own default vehicle steering binds
-- Space (jump-to-eject-from-seat) at.
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 1000
local EXIT_STATIONARY_SPEED = 1 -- studs/second

local function approach(current: number, target: number, rate: number): number
	if current < target then
		return math.min(current + rate, target)
	end
	return math.max(current - rate, target)
end

-- Shortest signed difference between two angles.
local function angleDelta(from: number, to: number): number
	return (to - from + math.pi) % (2 * math.pi) - math.pi
end

-- Which street a point is on, for the readout.
local function streetAt(position: Vector3): string?
	for _, avenue in CityConfig.AVENUES do
		if math.abs(position.X - avenue.x) < CityConfig.ROAD_WIDTH / 2 + 4 then
			for _, street in CityConfig.CROSS_STREETS do
				if math.abs(position.Z - street.z) < CityConfig.CROSS_STREET_WIDTH / 2 + 2 then
					return `{avenue.name} & {street.name}`
				end
			end
			return avenue.name
		end
	end
	for _, street in CityConfig.CROSS_STREETS do
		if math.abs(position.Z - street.z) < CityConfig.CROSS_STREET_WIDTH / 2 + 4 then
			return street.name
		end
	end
	return nil
end

-- The dash's "home" screen: engine state and the controls for it.
local function buildDashHome(gpsScreen: SurfaceGui): (Frame, Frame)
	-- From the last time round, if the player's been in this cab before.
	local old = gpsScreen:FindFirstChild("DashHome")
	if old then
		old:Destroy()
	end
	local panel = Instance.new("Frame")
	panel.Name = "DashHome"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
	panel.BorderSizePixel = 0
	panel.Parent = gpsScreen

	local offView = Instance.new("Frame")
	offView.Name = "EngineOff"
	offView.Size = UDim2.fromScale(1, 1)
	offView.BackgroundTransparency = 1
	offView.Parent = panel

	local title = UiKit.label(offView, "ENGINE OFF", 46, 1.5)
	title.Position = UDim2.new(0, 16, 0, 14)
	title.Size = UDim2.new(1, -32, 0, 52)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local hint = UiKit.body(offView, "Click the key by the wheel (or press E) to start.\nA / D to look around.", 32, Color3.fromRGB(205, 210, 220))
	hint.Position = UDim2.new(0, 16, 0, 74)
	hint.Size = UDim2.new(1, -32, 1, -88)

	local onView = Instance.new("Frame")
	onView.Name = "EngineOn"
	onView.Size = UDim2.fromScale(1, 1)
	onView.BackgroundTransparency = 1
	onView.Visible = false
	onView.Parent = panel

	local onTitle = UiKit.label(onView, "ENGINE ON", 46, 1.5)
	onTitle.Position = UDim2.new(0, 16, 0, 14)
	onTitle.Size = UDim2.new(1, -32, 0, 52)
	onTitle.TextXAlignment = Enum.TextXAlignment.Left
	onTitle.TextColor3 = Color3.fromRGB(140, 210, 150)

	local onLabel = UiKit.body(onView, "W / S  drive and brake\nA / D  steer\nV  outside view\nStop, then Space to get out", 30, Color3.fromRGB(205, 210, 220))
	onLabel.Position = UDim2.new(0, 16, 0, 74)
	onLabel.Size = UDim2.new(1, -32, 1, -88)

	return offView, onView
end

-- Speed and street name, bottom left (the phone lives bottom right); a
-- controls hint along the bottom that fades after a while.
local function buildHud(): (ScreenGui, TextLabel, TextLabel, TextLabel)
	local old = player:WaitForChild("PlayerGui"):FindFirstChild("DriveHud")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "DriveHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	local speed = Instance.new("TextLabel")
	speed.Name = "Speed"
	speed.BackgroundTransparency = 1
	speed.AnchorPoint = Vector2.new(0, 1)
	speed.Position = UDim2.new(0, 24, 1, -46)
	speed.Size = UDim2.new(0, 220, 0, 44)
	speed.Font = UiKit.FONT
	speed.TextSize = 40
	speed.TextXAlignment = Enum.TextXAlignment.Left
	speed.TextColor3 = Color3.fromRGB(240, 235, 220)
	speed.Text = ""
	UiKit.outlineText(speed, 2)
	speed.Parent = gui

	local street = Instance.new("TextLabel")
	street.Name = "Street"
	street.BackgroundTransparency = 1
	street.AnchorPoint = Vector2.new(0, 1)
	street.Position = UDim2.new(0, 24, 1, -18)
	street.Size = UDim2.new(0, 420, 0, 26)
	street.Font = UiKit.FONT
	street.TextSize = 20
	street.TextXAlignment = Enum.TextXAlignment.Left
	street.TextColor3 = UiKit.STYLES.gold.fill
	street.Text = ""
	UiKit.outlineText(street, 2)
	street.Parent = gui

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -18)
	hint.Size = UDim2.new(0.7, 0, 0, 24)
	hint.Font = UiKit.FONT
	hint.TextSize = 18
	hint.TextColor3 = Color3.fromRGB(215, 218, 225)
	hint.TextTransparency = 1
	hint.Text = "V  change view   ·   hold right mouse  look around   ·   scroll  zoom   ·   stop, then Space  get out"
	UiKit.outlineText(hint, 2)
	local hintStroke = hint:FindFirstChildOfClass("UIStroke")
	if hintStroke then
		hintStroke.Transparency = 1
	end
	hint.Parent = gui

	return gui, speed, street, hint
end

local function setHintVisible(hint: TextLabel, visible: boolean, duration: number)
	local target = if visible then 0 else 1
	TweenService:Create(hint, TweenInfo.new(duration), { TextTransparency = target }):Play()
	local stroke = hint:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(duration), { Transparency = target }):Play()
	end
end

local function buildFadeGui(): (ScreenGui, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = "CarExitFade"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60
	gui.Parent = player:WaitForChild("PlayerGui")

	local fade = Instance.new("Frame")
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BorderSizePixel = 0
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundTransparency = 1
	fade.Parent = gui

	return gui, fade
end

-- `hideConnection`: the intro's own per-frame "keep the driver hidden"
-- loop, if it's still running (only the first time, straight out of the
-- intro).
function CarSystems.start(car: Model, chassis: BasePart, seat: VehicleSeat, gpsScreen: SurfaceGui, character: Model, hideConnection: RBXScriptConnection?)
	if active then
		return
	end
	active = true
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if humanoid then
		-- The nameplate would float in the middle of the driver's view.
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	local offView, onView = buildDashHome(gpsScreen)
	local hud, speedLabel, streetLabel, hintLabel = buildHud()

	local clutter = windshieldClutter(car, seat.CFrame * CFrame.new(CAM_OFFSET_POS) * CFrame.Angles(CAM_PITCH, 0, 0))

	-- The intro kept the driver's own body hidden every frame; the camera
	-- loop below takes that over.
	if hideConnection then
		hideConnection:Disconnect()
	end
	local bodyParts: { BasePart } = {}
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(bodyParts, descendant)
		end
	end
	driverParts = bodyParts

	local connections: { RBXScriptConnection } = {}
	local ignitionOn = false
	local view = "driver"
	local lookYaw = 0
	local exiting = false
	local hintShown = false

	-- Chase camera state.
	local chaseDistance = CHASE_DISTANCE
	local chaseYaw = 0
	local orbitYaw = 0
	local orbiting = false
	local smoothFocus = chassis.Position
	local blendFrom: CFrame? = nil
	local blendStart = 0

	-- Driving state.
	local steer = 0
	local yawRate = 0

	-- Toward the driver's door: this car's driver sits toward the cabin's
	-- -X side (confirmed live), so that's the side the exit pan and the
	-- drop-off point both use.
	local EXIT_LOOK_YAW = math.rad(85)

	local function setView(newView: string)
		if newView == view then
			return
		end
		blendFrom = camera.CFrame
		blendStart = os.clock()
		view = newView
		orbitYaw = 0
		if view == "chase" then
			local look = chassis.CFrame.LookVector
			chaseYaw = math.atan2(-look.X, -look.Z)
			smoothFocus = chassis.Position
		end
		local hideInside = view == "driver"
		for _, part in clutter do
			part.LocalTransparencyModifier = if hideInside then 1 else 0
		end
	end
	for _, part in clutter do
		part.LocalTransparencyModifier = 1
	end

	-- Coming back from a cutscene: ease from its last shot back to this
	-- view, with the windshield clutter put back how this view wants it.
	onCutsceneEnded = function()
		blendFrom = camera.CFrame
		blendStart = os.clock()
		for _, part in clutter do
			part.LocalTransparencyModifier = if view == "driver" then 1 else 0
		end
	end

	-- The server (see CarSpawner's ignition-prompt/StopEngine handlers) is
	-- the actual authority on whether the engine's running -- watching
	-- `seat.Disabled` rather than trusting a click/keypress locally means
	-- this stays correct even if that ever changes some other way.
	local function setIgnition(on: boolean)
		local wasOn = ignitionOn
		ignitionOn = on
		if not exiting then
			lookYaw = 0
		end
		offView.Visible = not on
		onView.Visible = on
		steer = 0
		yawRate = 0
		if on and not wasOn and not exiting then
			-- Driving defaults to the outside view.
			setView("chase")
			if not hintShown then
				hintShown = true
				setHintVisible(hintLabel, true, 0.5)
				task.delay(9, function()
					setHintVisible(hintLabel, false, 1.5)
				end)
			end
		end
	end
	setIgnition(not seat.Disabled)
	table.insert(connections, seat:GetPropertyChangedSignal("Disabled"):Connect(function()
		setIgnition(not seat.Disabled)
	end))

	-- This file is the one and only place W/A/S/D (and the arrow keys) get
	-- turned into anything, for both looking around parked and driving --
	-- relying on any default Roblox vehicle handling was confirmed live to
	-- come out backwards. Keys are read as "held right now" each frame
	-- rather than tracked press by press, so a key already down when the
	-- engine starts still counts (confirmed live: a W pressed a moment
	-- after the ignition was missed, and the cab sat there with it held).
	-- Ignored while typing in chat.
	local function isHeld(a: Enum.KeyCode, b: Enum.KeyCode): boolean
		if UserInputService:GetFocusedTextBox() then
			return false
		end
		return UserInputService:IsKeyDown(a) or UserInputService:IsKeyDown(b)
	end
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.V and not exiting then
			setView(if view == "chase" then "driver" else "chase")
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 and view == "chase" then
			orbiting = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			orbiting = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end))
	table.insert(connections, UserInputService.InputChanged:Connect(function(input, processed)
		if view ~= "chase" then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement and orbiting then
			orbitYaw -= input.Delta.X * 0.006
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			chaseDistance = math.clamp(chaseDistance - input.Position.Z * 2, CHASE_MIN_DISTANCE, CHASE_MAX_DISTANCE)
		end
	end))

	-- ===== Driving =====
	-- Runs just before each physics step. Only while this machine actually
	-- owns the car's physics (ReceiveAge is 0 for parts simulated locally);
	-- until the server hands ownership over, anything set here would just
	-- be overwritten.
	table.insert(connections, RunService.PreSimulation:Connect(function(dt)
		if not ignitionOn or exiting or chassis.Anchored or chassis.ReceiveAge > 0 then
			return
		end

		local throttle = 0
		local steerInput = 0
		if not cutscene then
			if isHeld(Enum.KeyCode.W, Enum.KeyCode.Up) then
				throttle += 1
			end
			if isHeld(Enum.KeyCode.S, Enum.KeyCode.Down) then
				throttle -= 1
			end
			if isHeld(Enum.KeyCode.A, Enum.KeyCode.Left) then
				steerInput -= 1
			end
			if isHeld(Enum.KeyCode.D, Enum.KeyCode.Right) then
				steerInput += 1
			end
		end

		local forward = chassis.CFrame.LookVector
		local velocity = chassis.AssemblyLinearVelocity
		local speed = velocity:Dot(forward)

		-- W accelerates; S brakes while rolling forward and only starts
		-- reversing once stopped (and the mirror of that in reverse).
		-- Letting off both coasts down gently.
		if throttle > 0 then
			if speed < -0.5 then
				speed = approach(speed, 0, BRAKE * dt)
			else
				speed = approach(speed, MAX_SPEED, ACCEL * dt)
			end
		elseif throttle < 0 then
			if speed > 0.5 then
				speed = approach(speed, 0, BRAKE * dt)
			else
				speed = approach(speed, -REVERSE_MAX_SPEED, ACCEL * dt)
			end
		else
			speed = approach(speed, 0, COAST * dt)
		end

		-- The wheel eases toward where the keys say, rather than snapping
		-- to full lock the moment A or D goes down.
		local rate = if math.abs(steerInput) > math.abs(steer) and math.sign(steerInput) ~= -math.sign(steer) then STEER_IN_RATE else STEER_OUT_RATE
		steer = approach(steer, steerInput, rate * dt)

		-- Turning circle (a simple bicycle model): only turns while moving,
		-- steers the right way round in reverse, and widens with speed.
		local radius = TURN_RADIUS + math.abs(speed) * TURN_RADIUS_PER_SPEED
		local targetYaw = math.clamp(-steer * speed / radius, -MAX_YAW_RATE, MAX_YAW_RATE)
		yawRate += (targetYaw - yawRate) * math.min(1, dt * 12)

		-- Keep whatever vertical velocity gravity/bumps already gave it;
		-- only the driving direction is being set here.
		chassis.AssemblyLinearVelocity = forward * speed + Vector3.new(0, velocity.Y, 0)
		chassis.AssemblyAngularVelocity = Vector3.new(0, yawRate, 0)
	end))

	-- ===== Camera =====
	local occlusion = RaycastParams.new()
	occlusion.FilterType = Enum.RaycastFilterType.Exclude
	occlusion.FilterDescendantsInstances = { car, character }

	local function driverCFrame(): CFrame
		return seat.CFrame * CFrame.new(CAM_OFFSET_POS) * CFrame.Angles(CAM_PITCH, lookYaw, 0)
	end

	local function chaseCFrame(dt: number, speed: number): CFrame
		local look = chassis.CFrame.LookVector
		local carYaw = math.atan2(-look.X, -look.Z)
		chaseYaw += angleDelta(chaseYaw, carYaw) * (1 - math.exp(-dt * 4.5))
		if not orbiting and math.abs(speed) > 4 then
			orbitYaw *= math.exp(-dt * 1.5)
		end
		smoothFocus = smoothFocus:Lerp(chassis.Position, 1 - math.exp(-dt * 22))

		local rotation = CFrame.Angles(0, chaseYaw + orbitYaw, 0)
		local back = -rotation.LookVector
		local focus = smoothFocus + Vector3.new(0, 2.5, 0)
		local wanted = focus + back * chaseDistance + Vector3.new(0, chaseDistance * CHASE_HEIGHT_RATIO, 0)
		-- Pull in in front of anything between the cab and the camera.
		local result = workspace:Raycast(focus, wanted - focus, occlusion)
		if result then
			wanted = result.Position + (focus - wanted).Unit * 0.6
		end
		return CFrame.lookAt(wanted, focus - back * 5 + Vector3.new(0, 0.5, 0))
	end

	local renderConnection = RunService.RenderStepped:Connect(function(dt)
		if not chassis.Parent then
			return
		end
		local speed = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector)

		if cutscene then
			speedLabel.Text = ""
			return
		end

		if exiting then
			lookYaw = math.clamp(lookYaw + math.sign(EXIT_LOOK_YAW - lookYaw) * LOOK_YAW_SPEED * dt, -LOOK_YAW_MAX, LOOK_YAW_MAX)
		elseif ignitionOn then
			lookYaw = 0
		else
			-- Parked: A/D look around (from the seat), or turn the camera
			-- round the cab (outside).
			local turn = 0
			if isHeld(Enum.KeyCode.A, Enum.KeyCode.Left) then
				turn += 1
			end
			if isHeld(Enum.KeyCode.D, Enum.KeyCode.Right) then
				turn -= 1
			end
			if view == "driver" then
				lookYaw = math.clamp(lookYaw + turn * LOOK_YAW_SPEED * dt, -LOOK_YAW_MAX, LOOK_YAW_MAX)
			else
				orbitYaw += turn * LOOK_YAW_SPEED * dt
			end
		end

		-- Roblox's own camera handling can flip this back to Custom (seen
		-- when the character is re-seated).
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end

		local target
		if view == "driver" then
			target = driverCFrame()
			camera.FieldOfView = DRIVER_FOV
		else
			target = chaseCFrame(dt, speed)
			camera.FieldOfView = CHASE_FOV + (CHASE_FOV_AT_SPEED - CHASE_FOV) * math.clamp(math.abs(speed) / MAX_SPEED, 0, 1)
		end
		if blendFrom then
			local alpha = math.clamp((os.clock() - blendStart) / VIEW_BLEND_TIME, 0, 1)
			alpha = alpha * alpha * (3 - 2 * alpha)
			target = blendFrom:Lerp(target, alpha)
			if alpha >= 1 then
				blendFrom = nil
			end
		end
		camera.CFrame = target

		-- The driver's own body stays hidden in both views: from inside the
		-- camera sits in their head, and from outside their head pokes up
		-- through the cab's roof (the seat sits as high as this tall wagon
		-- allows -- confirmed live). Set every frame, since Roblox's own
		-- camera scripts also manage this property.
		for _, part in bodyParts do
			part.LocalTransparencyModifier = 1
		end

		if ignitionOn then
			speedLabel.Text = `{math.floor(math.abs(speed) * MPH_PER_STUD + 0.5)} MPH`
		else
			speedLabel.Text = ""
		end
		streetLabel.Text = streetAt(chassis.Position) or ""
	end)

	-- Space: get out, if the car isn't moving. Kept on ContextActionService
	-- at high priority, always Sinking -- so the engine's own default "jump
	-- ejects you from any seat" behaviour can never fire out from under
	-- this sequence, moving or not.
	local function handleExit(_actionName: string, inputState: Enum.UserInputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		if exiting or cutscene or chassis.AssemblyLinearVelocity.Magnitude > EXIT_STATIONARY_SPEED then
			return Enum.ContextActionResult.Sink
		end

		exiting = true
		if not seat.Disabled then
			stopEngineRemote:FireServer()
		end

		task.spawn(function()
			if view == "driver" then
				-- Turn toward the door first.
				local waited = 0
				while math.abs(lookYaw - EXIT_LOOK_YAW) > math.rad(4) and waited < 1.5 do
					waited += task.wait()
				end
				task.wait(0.15)
			end

			local fadeGui, fade = buildFadeGui()
			TweenService:Create(fade, TweenInfo.new(0.35), { BackgroundTransparency = 0 }):Play()
			task.wait(0.4)

			renderConnection:Disconnect()
			for _, connection in connections do
				connection:Disconnect()
			end
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			hud:Destroy()
			for _, part in bodyParts do
				part.LocalTransparencyModifier = 0
			end
			if humanoid then
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
			end
			for _, part in clutter do
				part.LocalTransparencyModifier = 0
			end
			camera.FieldOfView = DEFAULT_FOV

			-- Unseat first, then move -- PivotTo while still welded into the
			-- seat just fights the seat weld instead of actually relocating
			-- anything.
			if humanoid then
				humanoid.Sit = false
			end
			local dropOff = chassis.CFrame * CFrame.new(-(chassis.Size.X / 2 + 3), -(chassis.Size.Y / 2) + 3, 0.5)
			character:PivotTo(dropOff)

			camera.CameraType = Enum.CameraType.Custom
			if humanoid then
				camera.CameraSubject = humanoid
			end

			task.wait(0.1)
			TweenService:Create(fade, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
			task.wait(0.5)
			fadeGui:Destroy()

			ContextActionService:UnbindAction("CarSystemsExit")
			active = false
		end)

		return Enum.ContextActionResult.Sink
	end
	ContextActionService:BindActionAtPriority("CarSystemsExit", handleExit, false, ACTION_PRIORITY, Enum.KeyCode.Space)
end

return CarSystems
