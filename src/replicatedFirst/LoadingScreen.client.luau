-- The loading screen: the back seat of a cab at night. Rain on the
-- windshield, the city's lights smeared across it, the partition, and up in
-- the rear-view mirror the driver's eyes -- the player's own avatar, looking
-- back at the passenger. The game's title over it all.
--
-- Runs from ReplicatedFirst, so it's up before almost anything else has
-- loaded, and stays up until everything the opening cutscene needs is
-- genuinely ready: the game's assets, the city (the server builds it at
-- startup -- see GameStartup), the player's character and cab, the office
-- the cutscene opens in, and the frame rate settled after all of that
-- arrives. The cutscene waits for this screen to finish (the
-- "LoadingScreenDone" attribute on the player) -- it used to start while
-- things were still loading in, and the start of it was lost.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local MIN_SHOW_TIME = 5 -- seconds: long enough to read as a title card
local MAX_WAIT = 60 -- never hold a player here forever

local startedAt = os.clock()

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local function frame(parent: Instance, name: string, color: Color3, position: UDim2, size: UDim2, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Position = position
	f.Size = size
	f.Parent = parent
	return f
end

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function gradient(parent: Instance, colors: ColorSequence, rotation: number, transparency: NumberSequence?)
	local g = Instance.new("UIGradient")
	g.Color = colors
	g.Rotation = rotation
	if transparency then
		g.Transparency = transparency
	end
	g.Parent = parent
end

local root = frame(gui, "Scene", Color3.new(0, 0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
root.ClipsDescendants = true

-- ===== Through the windshield: the night street, out of focus =====

local street = frame(root, "Street", Color3.new(1, 1, 1), UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.8))
gradient(street, ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(6, 8, 18)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(20, 18, 36)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(46, 24, 34)),
}), 90)

-- Smeared lights: shop signs, streetlamps, tail lights. They drift past
-- slowly, as if the cab's rolling down the avenue.
local BOKEH_COLORS = {
	Color3.fromRGB(255, 170, 80),
	Color3.fromRGB(255, 60, 150),
	Color3.fromRGB(60, 210, 255),
	Color3.fromRGB(255, 60, 50),
	Color3.fromRGB(255, 230, 180),
	Color3.fromRGB(150, 90, 255),
}
type Light = { frame: Frame, x: number, y: number, speed: number }
local lights: { Light } = {}
for _ = 1, 46 do
	local size = math.random(14, 90)
	local y = 0.3 + math.random() * 0.45
	local bokeh = frame(street, "Light", BOKEH_COLORS[math.random(1, #BOKEH_COLORS)], UDim2.fromScale(0, y), UDim2.fromOffset(size, size), 0.45 + math.random() * 0.4)
	bokeh.AnchorPoint = Vector2.new(0.5, 0.5)
	corner(bokeh, UDim.new(1, 0))
	gradient(bokeh, ColorSequence.new(Color3.new(1, 1, 1)), 0, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(1, 0.1),
	}))
	table.insert(lights, { frame = bokeh, x = math.random(), y = y, speed = 0.006 + (y - 0.3) * 0.05 })
end

-- Rain running down the glass.
type Drop = { frame: Frame, x: number, y: number, speed: number }
local drops: { Drop } = {}
for _ = 1, 70 do
	local length = math.random(10, 46)
	local drop = frame(street, "Rain", Color3.fromRGB(190, 205, 225), UDim2.fromScale(0, 0), UDim2.fromOffset(1, length), 0.55 + math.random() * 0.35)
	table.insert(drops, { frame = drop, x = math.random(), y = math.random(), speed = 0.05 + math.random() * 0.25 })
end
for _ = 1, 40 do
	local size = math.random(2, 5)
	local bead = frame(street, "Bead", Color3.fromRGB(200, 215, 235), UDim2.fromScale(math.random(), math.random() * 0.8), UDim2.fromOffset(size, size), 0.5 + math.random() * 0.3)
	corner(bead, UDim.new(1, 0))
end

-- ===== The cab around you =====

local cabColor = Color3.fromRGB(10, 9, 10)

-- Roof lining.
local roof = frame(root, "Roof", cabColor, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.13))
gradient(roof, ColorSequence.new(Color3.fromRGB(24, 22, 22), Color3.fromRGB(8, 7, 8)), 90)
local roofEdge = frame(root, "RoofEdge", cabColor, UDim2.new(0, -40, 0.1, 0), UDim2.new(1, 80, 0.08, 0))
corner(roofEdge, UDim.new(0.5, 0))

-- Windshield pillars, leaning in.
for _, side in { -1, 1 } do
	local pillar = frame(root, "Pillar", cabColor, UDim2.fromScale(if side == -1 then -0.02 else 0.94, -0.1), UDim2.fromScale(0.08, 1.1))
	pillar.Rotation = side * -9
end

-- Dashboard, far side of the partition.
local dash = frame(root, "Dash", Color3.fromRGB(14, 12, 12), UDim2.new(-0.1, 0, 0.66, 0), UDim2.new(1.2, 0, 0.5, 0))
corner(dash, UDim.new(0.12, 0))
gradient(dash, ColorSequence.new(Color3.fromRGB(34, 28, 26), Color3.fromRGB(6, 5, 5)), 90)
-- The meter's red digits glowing on the dash.
local meter = Instance.new("TextLabel")
meter.Name = "Meter"
meter.BackgroundColor3 = Color3.fromRGB(20, 6, 6)
meter.BorderSizePixel = 0
meter.AnchorPoint = Vector2.new(0.5, 0)
meter.Position = UDim2.fromScale(0.56, 0.6905)
meter.Size = UDim2.fromScale(0.09, 0.04)
meter.Font = Enum.Font.Code
meter.TextScaled = true
meter.Text = "$ 2.50"
meter.TextColor3 = Color3.fromRGB(255, 60, 40)
meter.Parent = root
corner(meter, UDim.new(0.15, 0))

-- The two front headrests, seen from behind -- the driver's on the left.
for _, spec in { { x = 0.27, w = 0.2 }, { x = 0.73, w = 0.18 } } do
	local seatBack = frame(root, "SeatBack", Color3.fromRGB(16, 13, 12), UDim2.fromScale(spec.x, 0.84), UDim2.fromScale(spec.w * 1.5, 0.4))
	seatBack.AnchorPoint = Vector2.new(0.5, 0)
	corner(seatBack, UDim.new(0.2, 0))
	local headrest = frame(root, "Headrest", Color3.fromRGB(20, 16, 15), UDim2.fromScale(spec.x, 0.7), UDim2.fromScale(spec.w * 0.75, 0.17))
	headrest.AnchorPoint = Vector2.new(0.5, 0)
	corner(headrest, UDim.new(0.3, 0))
	gradient(headrest, ColorSequence.new(Color3.fromRGB(46, 38, 34), Color3.fromRGB(10, 8, 8)), 90)
end

-- The scratched plexiglass partition between you and the driver.
local partition = frame(root, "Partition", Color3.fromRGB(150, 165, 180), UDim2.fromScale(0, 0.2), UDim2.fromScale(1, 0.8), 0.93)
gradient(partition, ColorSequence.new(Color3.new(1, 1, 1)), 35, NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.42, 1),
	NumberSequenceKeypoint.new(0.47, 0.55),
	NumberSequenceKeypoint.new(0.52, 1),
	NumberSequenceKeypoint.new(0.7, 1),
	NumberSequenceKeypoint.new(0.73, 0.7),
	NumberSequenceKeypoint.new(1, 1),
}))
local partitionFrame = frame(root, "PartitionRail", Color3.fromRGB(28, 28, 30), UDim2.fromScale(0, 0.2), UDim2.new(1, 0, 0, 5))
partitionFrame.BackgroundTransparency = 0.2

-- The driver's hack licence, taped to the partition.
local licence = frame(root, "Licence", Color3.fromRGB(226, 220, 196), UDim2.fromScale(0.06, 0.53), UDim2.fromScale(0.15, 0.12))
licence.Rotation = -3
corner(licence, UDim.new(0.04, 0))
local licenceAspect = Instance.new("UIAspectRatioConstraint")
licenceAspect.AspectRatio = 1.6
licenceAspect.Parent = licence
local licencePhoto = Instance.new("ImageLabel")
licencePhoto.Name = "Photo"
licencePhoto.BackgroundColor3 = Color3.fromRGB(180, 175, 160)
licencePhoto.BorderSizePixel = 0
licencePhoto.Position = UDim2.fromScale(0.06, 0.22)
licencePhoto.Size = UDim2.fromScale(0.3, 0.68)
licencePhoto.Image = `rbxthumb://type=AvatarHeadShot&id={math.max(player.UserId, 1)}&w=150&h=150`
licencePhoto.Parent = licence
local licenceText = Instance.new("TextLabel")
licenceText.BackgroundTransparency = 1
licenceText.Position = UDim2.fromScale(0.4, 0.22)
licenceText.Size = UDim2.fromScale(0.56, 0.68)
licenceText.Font = Enum.Font.Code
licenceText.TextScaled = true
licenceText.TextXAlignment = Enum.TextXAlignment.Left
licenceText.TextYAlignment = Enum.TextYAlignment.Top
licenceText.TextColor3 = Color3.fromRGB(30, 30, 34)
licenceText.Text = `{player.DisplayName:upper()}\nHACK NO. {string.format("%05d", math.abs(player.UserId) % 100000)}\nNIGHT SHIFT`
licenceText.Parent = licence
local licenceHeader = Instance.new("TextLabel")
licenceHeader.BackgroundColor3 = Color3.fromRGB(40, 70, 120)
licenceHeader.BorderSizePixel = 0
licenceHeader.Size = UDim2.fromScale(1, 0.16)
licenceHeader.Font = Enum.Font.SourceSansBold
licenceHeader.TextScaled = true
licenceHeader.TextColor3 = Color3.new(1, 1, 1)
licenceHeader.Text = "MARROW CAB CO.  ·  DRIVER"
licenceHeader.Parent = licence

-- ===== The rear-view mirror, and who's in it =====

local mirrorStem = frame(root, "MirrorStem", Color3.fromRGB(20, 20, 22), UDim2.fromScale(0.5, 0.06), UDim2.new(0, 10, 0.08, 0))
mirrorStem.AnchorPoint = Vector2.new(0.5, 0)

local mirror = frame(root, "Mirror", Color3.fromRGB(18, 18, 20), UDim2.fromScale(0.5, 0.125), UDim2.fromScale(0.34, 0.1))
mirror.AnchorPoint = Vector2.new(0.5, 0)
corner(mirror, UDim.new(0.22, 0))
local mirrorAspect = Instance.new("UIAspectRatioConstraint")
mirrorAspect.AspectRatio = 3.1
mirrorAspect.Parent = mirror

-- A CanvasGroup rather than a clipping Frame: the mirror sways (see
-- below), and an ordinary Frame stops clipping what's inside it once it's
-- rotated -- confirmed live, the reflection spilled out over the mirror.
local glass = Instance.new("CanvasGroup")
glass.Name = "Glass"
glass.BackgroundColor3 = Color3.fromRGB(40, 36, 34)
glass.BorderSizePixel = 0
glass.Position = UDim2.fromScale(0.035, 0.11)
glass.Size = UDim2.fromScale(0.93, 0.78)
glass.Parent = mirror
corner(glass, UDim.new(0.2, 0))

-- The player's own avatar, mirrored left-to-right (it's a mirror), lit
-- warm and low like the inside of a cab at night. Drawn as a square about
-- twice the width of the glass, centred on the eyes, so the glass's narrow
-- strip crops it to the band across them. A negative ImageRectSize flips
-- it.
local eyes = Instance.new("ImageLabel")
eyes.Name = "DriversEyes"
eyes.BackgroundTransparency = 1
eyes.AnchorPoint = Vector2.new(0.5, 0.53)
eyes.Position = UDim2.fromScale(0.5, 0.5)
eyes.Size = UDim2.fromScale(1.9, 1.9)
eyes.SizeConstraint = Enum.SizeConstraint.RelativeXX
eyes.Image = `rbxthumb://type=AvatarHeadShot&id={math.max(player.UserId, 1)}&w=420&h=420`
eyes.ImageRectOffset = Vector2.new(420, 0)
eyes.ImageRectSize = Vector2.new(-420, 420)
eyes.ImageColor3 = Color3.fromRGB(215, 190, 165)
eyes.Parent = glass

-- Glass sheen and a dark edge, so it reads as a reflection, not a photo.
local sheen = frame(glass, "Sheen", Color3.new(1, 1, 1), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), 0)
gradient(sheen, ColorSequence.new(Color3.fromRGB(255, 255, 255)), 20, NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.82),
	NumberSequenceKeypoint.new(0.3, 1),
	NumberSequenceKeypoint.new(0.62, 1),
	NumberSequenceKeypoint.new(0.68, 0.9),
	NumberSequenceKeypoint.new(1, 1),
}))
local vignette = frame(glass, "Vignette", Color3.new(0, 0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), 0)
gradient(vignette, ColorSequence.new(Color3.new(0, 0, 0)), 0, NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.15),
	NumberSequenceKeypoint.new(0.18, 0.85),
	NumberSequenceKeypoint.new(0.82, 0.85),
	NumberSequenceKeypoint.new(1, 0.15),
}))

-- ===== Title and progress =====

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.43)
title.Size = UDim2.fromScale(0.6, 0.2)
title.Font = Enum.Font.GothamBlack
title.TextScaled = true
title.Text = "UBER"
title.TextColor3 = Color3.fromRGB(250, 240, 220)
title.TextTransparency = 1
title.Parent = root
local titleStroke = Instance.new("UIStroke")
titleStroke.Color = Color3.fromRGB(255, 120, 60)
titleStroke.Thickness = 2
titleStroke.Transparency = 1
titleStroke.Parent = title
local titleSize = Instance.new("UITextSizeConstraint")
titleSize.MaxTextSize = 150
titleSize.Parent = title

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.BackgroundTransparency = 1
subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
subtitle.Position = UDim2.fromScale(0.5, 0.545)
subtitle.Size = UDim2.fromScale(0.6, 0.04)
subtitle.Font = Enum.Font.Oswald
subtitle.TextScaled = true
subtitle.Text = "M A R R O W   H E I G H T S   ·   N I G H T   S H I F T"
subtitle.TextColor3 = Color3.fromRGB(210, 200, 185)
subtitle.TextTransparency = 1
subtitle.Parent = root

local status = Instance.new("TextLabel")
status.Name = "Status"
status.BackgroundTransparency = 1
status.AnchorPoint = Vector2.new(0.5, 1)
status.Position = UDim2.fromScale(0.5, 0.955)
status.Size = UDim2.fromScale(0.5, 0.03)
status.Font = Enum.Font.Oswald
status.TextScaled = true
status.Text = "Warming up the engine"
status.TextColor3 = Color3.fromRGB(190, 185, 175)
status.Parent = root

local barBack = frame(root, "ProgressBack", Color3.fromRGB(40, 36, 34), UDim2.fromScale(0.5, 0.97), UDim2.fromScale(0.3, 0.006))
barBack.AnchorPoint = Vector2.new(0.5, 0)
corner(barBack, UDim.new(1, 0))
local bar = frame(barBack, "Progress", Color3.fromRGB(240, 190, 60), UDim2.fromScale(0, 0), UDim2.fromScale(0, 1))
corner(bar, UDim.new(1, 0))

-- Black over everything, for fading in and out.
local fade = frame(gui, "Fade", Color3.new(0, 0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))

TweenService:Create(fade, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
task.delay(0.6, function()
	TweenService:Create(title, TweenInfo.new(1.6), { TextTransparency = 0 }):Play()
	TweenService:Create(titleStroke, TweenInfo.new(1.6), { Transparency = 0.6 }):Play()
	TweenService:Create(subtitle, TweenInfo.new(2), { TextTransparency = 0.15 }):Play()
end)

-- ===== Motion =====

local animation = RunService.RenderStepped:Connect(function(dt)
	for _, light in lights do
		light.x -= light.speed * dt
		if light.x < -0.1 then
			light.x += 1.2
		end
		light.frame.Position = UDim2.fromScale(light.x, light.y)
	end
	for _, drop in drops do
		drop.y += drop.speed * dt
		if drop.y > 0.85 then
			drop.y = -0.05
			drop.x = math.random()
		end
		drop.frame.Position = UDim2.fromScale(drop.x, drop.y)
	end
	-- The mirror trembles a little on the stem as the cab rolls.
	local t = os.clock()
	mirror.Rotation = math.sin(t * 1.3) * 0.6 + math.sin(t * 7.1) * 0.15
	meter.Text = string.format("$ %.2f", 2.5 + math.floor((t - startedAt) / 3) * 0.5)
end)

-- ===== Waiting for everything =====

local progress = 0
local function setProgress(fraction: number, text: string)
	progress = math.max(progress, fraction)
	status.Text = text
	TweenService:Create(bar, TweenInfo.new(0.4), { Size = UDim2.fromScale(progress, 1) }):Play()
end

local function timedOut(): boolean
	return os.clock() - startedAt > MAX_WAIT
end

setProgress(0.05, "Warming up the engine")
if not game:IsLoaded() then
	game.Loaded:Wait()
end

setProgress(0.2, "Building the city")
while not workspace:GetAttribute("WorldReady") and not timedOut() do
	task.wait(0.1)
end

setProgress(0.45, "Finding your cab")
local character = player.Character or player.CharacterAdded:Wait()
local car = workspace:WaitForChild(player.Name .. "_Car", 30)

setProgress(0.6, "Clocking in")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))
pcall(function()
	player:RequestStreamAroundAsync(CityConfig.OFFICE_ORIGIN, 15)
end)
local office = workspace:WaitForChild("TaxiOffice", 15)
local toPreload = {}
for _, thing in { car, office, character } do
	if thing then
		table.insert(toPreload, thing)
	end
end
pcall(function()
	ContentProvider:PreloadAsync(toPreload)
end)

-- Everything arriving at once makes the first moments choppy: wait for
-- the frame rate to settle (or a few seconds, whichever comes first).
setProgress(0.85, "Rain's coming down")
local settleStart = os.clock()
local smooth = 0
while os.clock() - settleStart < 6 and not timedOut() do
	local dt = RunService.RenderStepped:Wait()
	if dt < 1 / 25 then
		smooth += dt
		if smooth > 0.6 then
			break
		end
	else
		smooth = 0
	end
end

local remaining = MIN_SHOW_TIME - (os.clock() - startedAt)
if remaining > 0 then
	task.wait(remaining)
end
setProgress(1, "Your shift starts now")
task.wait(0.8)

-- Fade to black and hand over to the cutscene, which opens on black.
TweenService:Create(fade, TweenInfo.new(0.9), { BackgroundTransparency = 0 }):Play()
task.wait(1)
player:SetAttribute("LoadingScreenDone", true)
local playerGui = player:WaitForChild("PlayerGui")
local waited = 0
while not playerGui:FindFirstChild("IntroCutscene") and waited < 5 do
	waited += task.wait(0.05)
end
task.wait(0.1)
animation:Disconnect()
gui:Destroy()
