-- Owns everything about being "in the car" for the rest of the session, from
-- the moment IntroCutscene.client.luau hands off through however long the
-- player keeps driving, and finally getting out. Everything here keys off
-- one piece of state -- the ignition:
--   * The driver's-eye camera: locked forward while actually driving, free
--     to pan left/right off A/D while parked.
--   * WASD driving: this file now drives `seat.Throttle`/`seat.Steer`
--     directly from its own held-key tracking -- see the long comment above
--     `heldDrive` below for why relying on any default/implicit Roblox
--     behaviour turned out to be the wrong call entirely (confirmed W/S
--     came out backwards and fighting the camera when left implicit).
--   * The dash screen's interactivity: informational only now (fare calls,
--     texts) -- starting the car is the physical ignition key's job (a
--     ProximityPrompt built in CarBuilder, wired up in CarSpawner), per the
--     user's own request.
--   * Getting out: Space, while the car is stationary, turns the engine off
--     if it was on, pans the camera toward the driver's door, fades out,
--     drops the player on the sidewalk beside the car, and hands the camera
--     back to Roblox's own default third-person one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiKit = require(Shared:WaitForChild("UiKit"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local stopEngineRemote = remotes:WaitForChild("StopEngine")

local player = Players.LocalPlayer

local CarSystems = {}

local LOOK_YAW_SPEED = math.rad(110) -- radians/second while A or D is held
local LOOK_YAW_MAX = math.rad(100) -- clamps short of looking straight back
local CAM_OFFSET_POS = Vector3.new(0, 2.1, 0)
-- Slightly down, toward the road over the hood -- a positive pitch here
-- tilted the view up, filling the top third of the screen with headliner.
local CAM_PITCH = math.rad(-6)

-- Well above whatever priority Roblox's own default vehicle steering binds
-- Space (jump-to-eject-from-seat) at.
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 1000
local EXIT_STATIONARY_SPEED = 1 -- studs/second

-- The dash's "home" screen: purely informational now (see the file header --
-- starting the car is the physical key's job). Both views live under one
-- panel the whole time; whatever shows fare calls/texts later belongs here
-- too.
local function buildDashHome(gpsScreen: SurfaceGui): (Frame, Frame)
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

	local onLabel = UiKit.body(onView, "W / S  drive and brake\nA / D  steer\nStop, then Space to get out", 32, Color3.fromRGB(205, 210, 220))
	onLabel.Position = UDim2.new(0, 16, 0, 74)
	onLabel.Size = UDim2.new(1, -32, 1, -88)

	return offView, onView
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

function CarSystems.start(car: Model, chassis: BasePart, seat: VehicleSeat, gpsScreen: SurfaceGui, character: Model, hideConnection: RBXScriptConnection)
	local camera = workspace.CurrentCamera
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local ignitionPrompt = car:WaitForChild("IgnitionKey"):WaitForChild("IgnitionPrompt") :: ProximityPrompt

	local offView, onView = buildDashHome(gpsScreen)

	local ignitionOn = false
	local lookYaw = 0
	local exiting = false
	-- Toward the driver's door: this car's driver sits/wheel reads toward
	-- the cabin's -X side (confirmed live via screenshot -- the wheel sits
	-- left-of-centre in the dead-forward shot), so that's the side the exit
	-- pan and the drop-off point both use.
	local EXIT_LOOK_YAW = math.rad(85)

	-- The server (see CarSpawner's ignition-prompt/StopEngine handlers) is
	-- the actual authority on whether the engine's running -- watching
	-- `seat.Disabled` rather than trusting a click/keypress locally means
	-- this stays correct even if that ever changes some other way. The
	-- prompt is also disabled server-side the moment it's triggered (see
	-- CarSpawner) -- this client-side toggle is a second, redundant path to
	-- the same end, kept because it's the one that reacts if `Disabled` ever
	-- changes some other way.
	local function setIgnition(on: boolean)
		ignitionOn = on
		if not exiting then
			lookYaw = 0
		end
		offView.Visible = not on
		onView.Visible = on
		ignitionPrompt.Enabled = not on
		seat.Throttle = 0
		seat.Steer = 0
	end
	setIgnition(not seat.Disabled)
	seat:GetPropertyChangedSignal("Disabled"):Connect(function()
		setIgnition(not seat.Disabled)
	end)

	-- This file now drives Throttle/Steer directly, every frame, rather than
	-- trusting any default/implicit Roblox behaviour to translate WASD for
	-- an occupied VehicleSeat. Confirmed live in real play that leaving it
	-- implicit produced W/S backwards (S drove forward) and read as "the
	-- camera moving" rather than the car accelerating -- this project has no
	-- `PlayerModule` at all (see the git history/memory for that finding),
	-- so whatever *was* translating WASD into Throttle wasn't anything this
	-- game controls or can rely on being consistent. Being fully explicit
	-- here removes that guesswork entirely: this is now the one and only
	-- place W/A/S/D get turned into anything, for both looking around
	-- parked and actually driving.
	local held: { [Enum.KeyCode]: boolean } = {}
	local DRIVE_KEYS = {
		[Enum.KeyCode.W] = true,
		[Enum.KeyCode.A] = true,
		[Enum.KeyCode.S] = true,
		[Enum.KeyCode.D] = true,
	}
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if DRIVE_KEYS[input.KeyCode] then
			held[input.KeyCode] = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if DRIVE_KEYS[input.KeyCode] then
			held[input.KeyCode] = nil
		end
	end)

	local renderConnection: RBXScriptConnection
	renderConnection = RunService.RenderStepped:Connect(function(dt)
		if not chassis.Parent then
			return
		end

		if exiting then
			lookYaw = math.clamp(lookYaw + math.sign(EXIT_LOOK_YAW - lookYaw) * LOOK_YAW_SPEED * dt, -LOOK_YAW_MAX, LOOK_YAW_MAX)
		elseif ignitionOn then
			-- Driving: W/S is Throttle (+1 forward, -1 reverse -- the
			-- convention CarController's own forward-speed math already
			-- assumes), A/D is Steer (-1 left, +1 right -- what
			-- CarController's `-Steer` turn-rate math assumes). Camera stays
			-- locked forward; A/D means steering now, not looking.
			lookYaw = 0
			local throttle = 0
			if held[Enum.KeyCode.W] then
				throttle += 1
			end
			if held[Enum.KeyCode.S] then
				throttle -= 1
			end
			seat.Throttle = throttle

			local steer = 0
			if held[Enum.KeyCode.A] then
				steer -= 1
			end
			if held[Enum.KeyCode.D] then
				steer += 1
			end
			seat.Steer = steer
		else
			-- Parked: A/D pans the camera, holding wherever released (not
			-- spring-back). W/S do nothing while parked -- there's nothing
			-- to accelerate.
			if held[Enum.KeyCode.A] then
				lookYaw = math.clamp(lookYaw + LOOK_YAW_SPEED * dt, -LOOK_YAW_MAX, LOOK_YAW_MAX)
			elseif held[Enum.KeyCode.D] then
				lookYaw = math.clamp(lookYaw - LOOK_YAW_SPEED * dt, -LOOK_YAW_MAX, LOOK_YAW_MAX)
			end
		end

		-- Roblox's own camera handling can flip this back to Custom (seen when
		-- the character is re-seated), which would leave the view following
		-- the seat from outside instead of from the driver's eye.
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		camera.CFrame = seat.CFrame * CFrame.new(CAM_OFFSET_POS) * CFrame.Angles(CAM_PITCH, lookYaw, 0)
	end)

	-- Space: get out, if the car isn't moving. Kept on ContextActionService
	-- (not Controls, and not UserInputService) at high priority, and always
	-- Sink -- this needs to win even while driving (Controls enabled, for
	-- WASD), so the engine's own default "jump ejects you from any seat"
	-- behaviour can never fire out from under this sequence, moving or not.
	local function handleExit(_actionName: string, inputState: Enum.UserInputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		if exiting or chassis.AssemblyLinearVelocity.Magnitude > EXIT_STATIONARY_SPEED then
			return Enum.ContextActionResult.Sink
		end

		exiting = true
		if not seat.Disabled then
			stopEngineRemote:FireServer()
		end

		task.spawn(function()
			local waited = 0
			while math.abs(lookYaw - EXIT_LOOK_YAW) > math.rad(4) and waited < 1.5 do
				waited += task.wait()
			end
			task.wait(0.15)

			local fadeGui, fade = buildFadeGui()
			TweenService:Create(fade, TweenInfo.new(0.35), { BackgroundTransparency = 0 }):Play()
			task.wait(0.4)

			renderConnection:Disconnect()
			hideConnection:Disconnect()
			for _, descendant in character:GetDescendants() do
				if descendant:IsA("BasePart") then
					(descendant :: BasePart).LocalTransparencyModifier = 0
				end
			end
			if humanoid then
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
			end

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
		end)

		return Enum.ContextActionResult.Sink
	end
	ContextActionService:BindActionAtPriority("CarSystemsExit", handleExit, false, ACTION_PRIORITY, Enum.KeyCode.Space)
end

return CarSystems
