-- Story cutscenes: takes the camera off the driving camera (CarSystems)
-- for a run of shots, with black bars top and bottom and everything else on
-- screen (minimap, phone, speedometer, objective) put away -- only the
-- subtitles stay. Each shot is a function from seconds-into-the-shot to a
-- camera CFrame, worked out every frame, so a shot can follow the cab or
-- the people in it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CarSystems = require(script.Parent.CarSystems)
local Screen = require(script.Parent.Screen)

local Cutscene = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local BAR_HEIGHT = 0.11 -- of the screen, each
local HIDDEN_GUIS = { "Hud", "DriveHud", "Phone" }

local gui = Instance.new("ScreenGui")
gui.Name = "Letterbox"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 9
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function bar(anchorY: number): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0, anchorY)
	f.Position = UDim2.fromScale(0, anchorY)
	f.Size = UDim2.fromScale(1, 0)
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.Parent = gui
	return f
end
local topBar = bar(0)
local bottomBar = bar(1)

-- For cuts to and from black (under the subtitles, which are another gui).
local blackout = Instance.new("Frame")
blackout.Name = "Black"
blackout.Size = UDim2.fromScale(1, 1)
blackout.BackgroundColor3 = Color3.new(0, 0, 0)
blackout.BackgroundTransparency = 1
blackout.BorderSizePixel = 0
blackout.ZIndex = 5
blackout.Parent = gui

local playing = false
local shotFn: ((number) -> CFrame)? = nil
local shotStart = 0
local shotFov = 60
local connection: RBXScriptConnection? = nil

function Cutscene.isPlaying(): boolean
	return playing
end

-- `subtle` (the side-street glimpse): no bars and the HUD left up -- the
-- camera just turns, as if it's the driver's own eyes.
function Cutscene.begin(subtle: boolean?)
	if playing then
		return
	end
	playing = true
	CarSystems.setCutscene(true)
	gui.Enabled = true
	if not subtle then
		Screen.setCinematic(true)
		local playerGui = player:WaitForChild("PlayerGui")
		for _, name in HIDDEN_GUIS do
			local g = playerGui:FindFirstChild(name)
			if g and g:IsA("ScreenGui") then
				g.Enabled = false
			end
		end
		for _, b in { topBar, bottomBar } do
			TweenService:Create(b, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(1, BAR_HEIGHT) }):Play()
		end
	end
	camera.CameraType = Enum.CameraType.Scriptable
	connection = RunService.RenderStepped:Connect(function()
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		if shotFn then
			local ok, cframe = pcall(shotFn, os.clock() - shotStart)
			if ok and cframe then
				camera.CFrame = cframe
			end
			camera.FieldOfView = shotFov
		end
	end)
end

-- Cuts to a new shot. `fn(t)` gives the camera at `t` seconds in.
function Cutscene.shot(fn: (number) -> CFrame, fov: number?)
	shotFn = fn
	shotStart = os.clock()
	shotFov = fov or 60
end

-- A shot moving smoothly from one camera to another over `duration`, each
-- given as a function so it can follow something that's moving.
function Cutscene.dolly(from: () -> CFrame, to: () -> CFrame, duration: number, fov: number?)
	Cutscene.shot(function(t)
		local alpha = math.clamp(t / duration, 0, 1)
		alpha = alpha * alpha * (3 - 2 * alpha)
		return from():Lerp(to(), alpha)
	end, fov)
end

-- A camera at `eye` looking at `target` (both functions, for the same
-- reason), held still.
function Cutscene.look(eye: () -> Vector3, target: () -> Vector3, fov: number?)
	Cutscene.shot(function()
		return CFrame.lookAt(eye(), target())
	end, fov)
end

-- To black (`on`) or back from it, over `time` seconds (0 = a hard cut).
-- Doesn't yield.
function Cutscene.black(on: boolean, time: number?)
	local target = if on then 0 else 1
	if not time or time <= 0 then
		blackout.BackgroundTransparency = target
	else
		TweenService:Create(blackout, TweenInfo.new(time), { BackgroundTransparency = target }):Play()
	end
end

function Cutscene.finish()
	if not playing then
		return
	end
	playing = false
	shotFn = nil
	Cutscene.black(false, 0.5)
	if connection then
		connection:Disconnect()
		connection = nil
	end
	for _, b in { topBar, bottomBar } do
		TweenService:Create(b, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(1, 0) }):Play()
	end
	task.delay(0.55, function()
		if not playing then
			gui.Enabled = false
		end
	end)
	local playerGui = player:WaitForChild("PlayerGui")
	for _, name in HIDDEN_GUIS do
		local g = playerGui:FindFirstChild(name)
		if g and g:IsA("ScreenGui") then
			g.Enabled = true
		end
	end
	Screen.setCinematic(false)
	CarSystems.setDriverVisible(false)
	CarSystems.setCutscene(false)
end

return Cutscene
