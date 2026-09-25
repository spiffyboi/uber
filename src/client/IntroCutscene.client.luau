-- The opening shot, once per session: steam off a grate, a parked car at
-- 2am, then a slow creep forward through the rain-streaked windshield while
-- a couple of lines of narration set the mood -- built after the opening of
-- Scorsese's Taxi Driver, though nothing in it is that film's footage,
-- music or dialogue. Ends on GigLine's dispatch call buzzing in, and handing
-- control of the car to the player once they accept it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))
local UiKit = require(Shared:WaitForChild("UiKit"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local acceptJobRemote = remotes:WaitForChild("AcceptJob")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Ambient rain/city bed and the score cue for the drive -- open slots, same
-- as Brew a Potion!'s MusicPlayer: fill in real uploaded/Creator Store ids
-- later, the scene works (silently) without them meanwhile.
local AMBIENCE_ID = "rbxassetid://0"
local SCORE_ID = "rbxassetid://0"

local MONOLOGUE = {
	"Been driving The Marrow six nights a week for a year now.",
	"Everybody in this city's going somewhere. Nobody wants to look at the driver.",
	"Phone's about to ring. It always rings.",
}

local function waitForCar(): (Model, BasePart, VehicleSeat)
	local car = workspace:WaitForChild(player.Name .. "_Car") :: Model
	local chassis = car:WaitForChild("Chassis") :: BasePart
	local seat = car:WaitForChild("DriveSeat") :: VehicleSeat
	return car, chassis, seat
end

local function playAmbience(id: string, volume: number, looped: boolean): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Looped = looped
	sound.Parent = SoundService
	if id ~= "rbxassetid://0" then
		sound:Play()
	end
	return sound
end

-- ===== Letterbox bars =====

local function buildLetterbox(gui: ScreenGui): (Frame, Frame)
	local top = Instance.new("Frame")
	top.Name = "LetterboxTop"
	top.BackgroundColor3 = Color3.new(0, 0, 0)
	top.BorderSizePixel = 0
	top.Size = UDim2.new(1, 0, 0, 0)
	top.Position = UDim2.new(0, 0, 0, 0)
	top.ZIndex = 10
	top.Parent = gui

	local bottom = Instance.new("Frame")
	bottom.Name = "LetterboxBottom"
	bottom.BackgroundColor3 = Color3.new(0, 0, 0)
	bottom.BorderSizePixel = 0
	bottom.Size = UDim2.new(1, 0, 0, 0)
	bottom.Position = UDim2.new(0, 0, 1, 0)
	bottom.AnchorPoint = Vector2.new(0, 1)
	bottom.ZIndex = 10
	bottom.Parent = gui

	return top, bottom
end

local function setLetterbox(top: Frame, bottom: Frame, fraction: number, duration: number)
	local size = UDim2.new(1, 0, fraction, 0)
	TweenService:Create(top, TweenInfo.new(duration, Enum.EasingStyle.Sine), { Size = size }):Play()
	TweenService:Create(bottom, TweenInfo.new(duration, Enum.EasingStyle.Sine), { Size = size }):Play()
end

-- ===== Fade to/from black =====

local function buildFade(gui: ScreenGui): Frame
	local fade = Instance.new("Frame")
	fade.Name = "Fade"
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BorderSizePixel = 0
	fade.Size = UDim2.new(1, 0, 1, 0)
	fade.ZIndex = 20
	fade.Parent = gui
	return fade
end

-- ===== Rain, streaked across the screen in front of the camera =====

local function buildRain(): (BasePart, () -> ())
	local rig = Instance.new("Part")
	rig.Name = "RainRig"
	rig.Size = Vector3.new(1, 1, 1)
	rig.Transparency = 1
	rig.CanCollide = false
	rig.Anchored = true
	rig.Parent = workspace.CurrentCamera

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(180, 195, 210))
	emitter.Size = NumberSequence.new(0.15)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	emitter.Lifetime = NumberRange.new(0.4, 0.6)
	emitter.Rate = 200
	emitter.Speed = NumberRange.new(28, 32)
	emitter.SpreadAngle = Vector2.new(4, 4)
	emitter.Rotation = NumberRange.new(75, 80)
	emitter.RotSpeed = NumberRange.new(0, 0)
	emitter.Parent = rig

	local connection = RunService.RenderStepped:Connect(function()
		rig.CFrame = camera.CFrame * CFrame.new(0, 1.5, -5) * CFrame.Angles(math.rad(80), 0, 0)
	end)

	return rig, function()
		connection:Disconnect()
		rig:Destroy()
	end
end

-- ===== Subtitles =====

local function buildSubtitle(gui: ScreenGui): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Subtitle"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.8, 0, 0, 60)
	label.Position = UDim2.new(0.5, 0, 0.78, 0)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Font = UiKit.FONT
	label.TextSize = 26
	label.TextColor3 = Color3.fromRGB(225, 225, 230)
	label.TextTransparency = 1
	label.TextWrapped = true
	label.Text = ""
	label.ZIndex = 10
	UiKit.outlineText(label, 3)
	label.Parent = gui
	return label
end

local function typeLine(label: TextLabel, text: string)
	label.TextTransparency = 0
	label.Text = ""
	for i = 1, #text do
		label.Text = text:sub(1, i)
		task.wait(0.028)
	end
	task.wait(1.1)
	TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	task.wait(0.4)
end

-- ===== Dispatch call popup =====

local function showDispatchPopup(gui: ScreenGui, onAccept: () -> ())
	local panel = Instance.new("Frame")
	panel.Name = "DispatchPopup"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, 20)
	panel.Size = UDim2.fromOffset(420, 150)
	panel.ZIndex = 15
	UiKit.decorate(panel, UiKit.STYLES.panel, 6, 2)
	panel.Parent = gui

	local appLabel = UiKit.body(panel, CityConfig.APP_NAME:upper(), 16, UiKit.STYLES.cyan.fill)
	appLabel.Position = UDim2.new(0, 16, 0, 10)
	appLabel.Size = UDim2.new(1, -32, 0, 20)
	appLabel.TextXAlignment = Enum.TextXAlignment.Left

	local title = UiKit.label(panel, "New request nearby", 22, 2)
	title.Position = UDim2.new(0, 16, 0, 32)
	title.Size = UDim2.new(1, -32, 0, 30)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local detail = UiKit.body(panel, "Pickup: 4 min away · The Marrow", 16, Color3.fromRGB(190, 195, 205))
	detail.Position = UDim2.new(0, 16, 0, 64)
	detail.Size = UDim2.new(1, -32, 0, 20)
	detail.TextXAlignment = Enum.TextXAlignment.Left

	local acceptButton = UiKit.button(panel, "Accept", "", "ACCEPT", UiKit.STYLES.cyan, UDim2.fromOffset(388, 44))
	acceptButton.Position = UDim2.new(0, 16, 1, -56)

	TweenService:Create(panel, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 1, -20) }):Play()

	acceptButton.MouseButton1Click:Once(function()
		onAccept()
		local tween = TweenService:Create(panel, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 1, 20) })
		tween:Play()
		tween.Completed:Wait()
		panel:Destroy()
	end)
end

-- ===== The sequence =====

local function run()
	local character = player.Character or player.CharacterAdded:Wait()
	local _car, chassis, _seat = waitForCar()

	camera.CameraType = Enum.CameraType.Scriptable

	local gui = Instance.new("ScreenGui")
	gui.Name = "IntroCutscene"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = player:WaitForChild("PlayerGui")

	local fade = buildFade(gui)
	local top, bottom = buildLetterbox(gui)
	local subtitle = buildSubtitle(gui)
	local rainRig, stopRain = buildRain()

	local ambience = playAmbience(AMBIENCE_ID, 0.4, true)
	local score = playAmbience(SCORE_ID, 0.5, false)

	-- Stage A: a low, static shot on the grate, pushing slowly toward the
	-- parked car through the rising steam. The car (see CarBuilder/CityConfig)
	-- faces +Z, back toward the grate/spawn, so a camera further up +Z at the
	-- default (unrotated) orientation -- which looks down -Z -- is already
	-- looking straight at its headlights; no extra rotation needed.
	local grateStart = CFrame.new(CityConfig.GRATE_POSITION + Vector3.new(0, 1.5, 14))
	local grateEnd = CFrame.new(CityConfig.GRATE_POSITION + Vector3.new(0, 1.8, 6))
	camera.CFrame = grateStart

	TweenService:Create(fade, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
	setLetterbox(top, bottom, 0.09, 1.4)
	TweenService:Create(camera, TweenInfo.new(4, Enum.EasingStyle.Sine), { CFrame = grateEnd }):Play()
	task.wait(4)

	-- Stage B: cut to the windshield, a slow creep forward that never
	-- actually goes anywhere -- the car stays parked (seat still Disabled)
	-- until the player accepts the job. No extra rotation here either: the
	-- camera should face the same way the chassis already does.
	local driftDistance = 0
	local driving = true
	task.spawn(function()
		while driving do
			driftDistance = math.min(driftDistance + RunService.Heartbeat:Wait() * 3.5, 22)
			camera.CFrame = chassis.CFrame * CFrame.new(0, 2.6, -1.5 - driftDistance)
		end
	end)

	task.wait(0.6)
	for _, line in MONOLOGUE do
		typeLine(subtitle, line)
	end

	task.wait(1)
	showDispatchPopup(gui, function()
		driving = false
		acceptJobRemote:FireServer()
	end)

	-- Wait for the popup's Accept before handing control back.
	repeat
		task.wait(0.1)
	until not driving

	stopRain()
	setLetterbox(top, bottom, 0, 0.5)
	TweenService:Create(subtitle, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()

	task.wait(0.6)
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = character:FindFirstChild("Humanoid")

	task.wait(1)
	top:Destroy()
	bottom:Destroy()
	fade:Destroy()

	if ambience.SoundId ~= "rbxassetid://0" then
		TweenService:Create(ambience, TweenInfo.new(2), { Volume = 0 }):Play()
	end
end

run()
