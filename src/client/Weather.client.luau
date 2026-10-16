-- What the weather looks like (WeatherService decides what it is, on the
-- workspace attributes Rain / Overcast / Wetness / Storm):
--   rain     -- streaks falling all round the camera, with a gap over the
--               player's own cab so none of it falls through the roof onto
--               the seats (particles don't stop at roofs), and splashes
--               where it lands
--   sky      -- haze thickening and the colour draining out as it clouds
--               over and rains; low cloud
--   streets  -- the roads and sidewalks darken when wet and take a sheen,
--               and puddles show up on the asphalt
--   storm    -- every so often, lightning
-- None of it runs while the camera's down in one of the sealed sets under
-- the street (the cab office, the gun store, the chapel): those scenes light
-- themselves, and it never rains indoors.
--
-- All of this is on this screen only.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- The dry night, as OpeningSetBuilder sets it up. (Kept here rather than
-- read off Lighting at start-up, since the intro's office lights the world
-- its own way while it's on.)
local DRY = {
	density = 0.4,
	haze = 2.2,
	color = Color3.fromRGB(60, 65, 80),
	outdoor = Color3.fromRGB(70, 76, 96),
	saturation = -0.15,
}
local WET = {
	density = 0.55,
	haze = 3.4,
	color = Color3.fromRGB(66, 70, 80),
	outdoor = Color3.fromRGB(56, 61, 78),
	saturation = -0.3,
}

-- Below this the camera's in one of the sets under the street.
local UNDERGROUND_Y = -15

-- ===== Rain =====

local RIG_SIZE = 150 -- studs across, centred on the cab (or the camera)
local HOLE = 16 -- the gap left over the cab
local RAIN_HEIGHT = 32
local GROUND_Y = 1.05 -- road top

local rig = Instance.new("Folder")
rig.Name = "WeatherRig"
rig.Parent = workspace

-- Four slabs round a square hole: { offset from the centre, size }.
local half, holeHalf = RIG_SIZE / 2, HOLE / 2
local strip = (half - holeHalf)
local SLABS = {
	{ Vector3.new(0, 0, -(holeHalf + strip / 2)), Vector3.new(RIG_SIZE, 1, strip) },
	{ Vector3.new(0, 0, holeHalf + strip / 2), Vector3.new(RIG_SIZE, 1, strip) },
	{ Vector3.new(-(holeHalf + strip / 2), 0, 0), Vector3.new(strip, 1, HOLE) },
	{ Vector3.new(holeHalf + strip / 2, 0, 0), Vector3.new(strip, 1, HOLE) },
}

local function slab(name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = rig
	return p
end

local drops: { ParticleEmitter } = {}
local splashes: { ParticleEmitter } = {}
local rainParts: { { part: BasePart, offset: Vector3 } } = {}
local splashParts: { { part: BasePart, offset: Vector3 } } = {}

for i, s in SLABS do
	local sky = slab("RainSky" .. i, s[2])
	local drop = Instance.new("ParticleEmitter")
	drop.Name = "Drops"
	drop.Texture = "rbxasset://textures/particles/smoke_main.dds"
	drop.Shape = Enum.ParticleEmitterShape.Box
	drop.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	drop.EmissionDirection = Enum.NormalId.Bottom
	drop.Orientation = Enum.ParticleOrientation.VelocityParallel
	drop.Speed = NumberRange.new(95, 115)
	drop.Lifetime = NumberRange.new(0.38, 0.42)
	drop.Size = NumberSequence.new(0.12)
	drop.Squash = NumberSequence.new(2.6)
	drop.Color = ColorSequence.new(Color3.fromRGB(190, 205, 225))
	drop.Transparency = NumberSequence.new(0.45)
	drop.LightEmission = 0.15
	drop.LightInfluence = 0.7
	drop.Acceleration = Vector3.new(4, 0, 2)
	drop.Rate = 0
	drop.Parent = sky
	table.insert(drops, drop)
	table.insert(rainParts, { part = sky, offset = s[1] + Vector3.new(0, RAIN_HEIGHT, 0) })

	local floor = slab("RainSplash" .. i, Vector3.new(s[2].X, 0.1, s[2].Z))
	local splash = Instance.new("ParticleEmitter")
	splash.Name = "Splashes"
	splash.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	splash.Shape = Enum.ParticleEmitterShape.Box
	splash.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	splash.EmissionDirection = Enum.NormalId.Top
	splash.Speed = NumberRange.new(2, 4)
	splash.SpreadAngle = Vector2.new(50, 50)
	splash.Lifetime = NumberRange.new(0.12, 0.2)
	splash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.08), NumberSequenceKeypoint.new(1, 0.3) })
	splash.Color = ColorSequence.new(Color3.fromRGB(200, 212, 230))
	splash.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	splash.LightInfluence = 0.8
	splash.Rate = 0
	splash.Parent = floor
	table.insert(splashes, splash)
	table.insert(splashParts, { part = floor, offset = s[1] })
end

-- Where the rain's centred: on the cab when the camera's anywhere near it
-- (so the hole's over the roof), otherwise on the camera.
local function rainCentre(): Vector3
	local car = workspace:FindFirstChild(player.Name .. "_Car")
	local chassis = car and (car :: Model).PrimaryPart
	local cam = camera.CFrame.Position
	if chassis and (chassis.Position - cam).Magnitude < 60 then
		return Vector3.new(chassis.Position.X, GROUND_Y, chassis.Position.Z)
	end
	return Vector3.new(cam.X, GROUND_Y, cam.Z)
end

-- ===== Sound =====
-- The rain's hiss and the thunder. Asset ids still to be found on the
-- Creator Store and checked (never guessed): 0 = none yet.
local RAIN_SOUND_ID = "rbxassetid://0"
local THUNDER_SOUND_ID = "rbxassetid://0"

local rainSound: Sound? = nil
if RAIN_SOUND_ID ~= "rbxassetid://0" then
	rainSound = Instance.new("Sound")
	rainSound.Name = "Rain"
	rainSound.SoundId = RAIN_SOUND_ID
	rainSound.Looped = true
	rainSound.Volume = 0
	rainSound.Parent = game:GetService("SoundService")
	rainSound:Play()
end

local function thunder(delay: number)
	if THUNDER_SOUND_ID == "rbxassetid://0" then
		return
	end
	task.delay(delay, function()
		local s = Instance.new("Sound")
		s.SoundId = THUNDER_SOUND_ID
		s.Volume = 0.6
		s.PlaybackSpeed = 0.9 + math.random() * 0.2
		s.Parent = game:GetService("SoundService")
		s:Play()
		s.Ended:Once(function()
			s:Destroy()
		end)
	end)
end

-- ===== Sky =====

local clouds = Instance.new("Clouds")
clouds.Color = Color3.fromRGB(38, 42, 52)
clouds.Cover = 0
clouds.Density = 0
clouds.Parent = workspace:WaitForChild("Terrain")

local flashUntil = 0
local nextLightning = os.clock() + 8

local function lightning()
	-- A double flicker, then (a moment later, as if from a way off) the
	-- thunder.
	task.spawn(function()
		for _, length in { 0.07, 0.05 } do
			flashUntil = os.clock() + length
			task.wait(length + 0.08)
		end
	end)
	thunder(1 + math.random() * 2.5)
end

-- ===== Wet streets =====

local surfaces: { { part: BasePart, color: Color3 } } = {}
local function gatherSurfaces()
	local set = workspace:WaitForChild("OpeningSet", 60)
	if not set then
		return
	end
	for _, p in set:GetChildren() do
		if p:IsA("BasePart") and (p.Name:match("^Avenue_") or p.Name:match("^Street_") or p.Name == "Sidewalk" or p.Name == "Ground") then
			table.insert(surfaces, { part = p, color = p.Color })
		end
	end
end
task.spawn(gatherSurfaces)

-- Puddles: flat dark discs scattered over the avenues and cross streets,
-- only seen once it's wet enough.
local puddles: { BasePart } = {}
local function buildPuddles()
	local CityConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("CityConfig"))
	local folder = Instance.new("Folder")
	folder.Name = "Puddles"
	folder.Parent = rig
	local random = Random.new(1947)
	local function puddle(x: number, z: number)
		local blobs = random:NextInteger(1, 3)
		local size = random:NextNumber(3, 7)
		for _ = 1, blobs do
			local p = Instance.new("Part")
			p.Name = "Puddle"
			p.Shape = Enum.PartType.Cylinder
			local d = size * random:NextNumber(0.6, 1)
			p.Size = Vector3.new(0.04, d, d)
			p.CFrame = CFrame.new(x + random:NextNumber(-size, size) * 0.5, GROUND_Y - 0.03, z + random:NextNumber(-size, size) * 0.5) * CFrame.Angles(0, 0, math.rad(90))
			p.Color = Color3.fromRGB(16, 18, 24)
			p.Material = Enum.Material.Glass
			p.Reflectance = 0.5
			p.Transparency = 1
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Parent = folder
			table.insert(puddles, p)
		end
	end
	local top, bottom = CityConfig.GRID_TOP_Z, CityConfig.GRID_BOTTOM_Z
	local roadHalf = CityConfig.ROAD_WIDTH / 2 - 3
	for _, avenue in CityConfig.AVENUES do
		for _ = 1, 40 do
			puddle(avenue.x + random:NextNumber(-roadHalf, roadHalf), random:NextNumber(math.min(top, bottom), math.max(top, bottom)))
		end
	end
	local avenues = CityConfig.AVENUES
	for _, street in CityConfig.CROSS_STREETS do
		for _ = 1, 4 do
			local a = random:NextInteger(1, #avenues - 1)
			local x = random:NextNumber(avenues[a].x + CityConfig.ROAD_WIDTH / 2 + 6, avenues[a + 1].x - CityConfig.ROAD_WIDTH / 2 - 6)
			puddle(x, street.z + random:NextNumber(-CityConfig.CROSS_STREET_WIDTH / 2 + 3, CityConfig.CROSS_STREET_WIDTH / 2 - 3))
		end
	end
end
task.spawn(buildPuddles)

-- ===== Every frame =====

local atmosphere: Atmosphere? = nil
local colorCorrection: ColorCorrectionEffect? = nil
local shownWetness = -1

local function number(name: string): number
	return tonumber(workspace:GetAttribute(name)) or 0
end

RunService.RenderStepped:Connect(function()
	local rain, overcast, wetness = number("Rain"), number("Overcast"), number("Wetness")
	local underground = camera.CFrame.Position.Y < UNDERGROUND_Y

	-- Rain.
	local centre = rainCentre()
	for _, r in rainParts do
		r.part.CFrame = CFrame.new(centre + r.offset)
	end
	for _, r in splashParts do
		r.part.CFrame = CFrame.new(centre + r.offset)
	end
	local strength = if underground then 0 else rain
	for _, drop in drops do
		drop.Rate = strength * 900
	end
	for _, splash in splashes do
		splash.Rate = strength * 260
	end
	if rainSound then
		rainSound.Volume = if underground then 0 else rain * 0.5
	end

	if underground then
		return
	end

	-- Sky.
	atmosphere = atmosphere or Lighting:FindFirstChildOfClass("Atmosphere")
	colorCorrection = colorCorrection or Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	local grey = math.clamp(overcast * 0.4 + rain * 0.6, 0, 1)
	if atmosphere then
		atmosphere.Density = DRY.density + (WET.density - DRY.density) * grey
		atmosphere.Haze = DRY.haze + (WET.haze - DRY.haze) * grey
		atmosphere.Color = DRY.color:Lerp(WET.color, grey)
	end
	if colorCorrection then
		colorCorrection.Saturation = DRY.saturation + (WET.saturation - DRY.saturation) * grey
	end
	clouds.Cover = 0.25 + overcast * 0.6
	clouds.Density = 0.15 + overcast * 0.55

	-- Lightning.
	if workspace:GetAttribute("Storm") == true and os.clock() > nextLightning then
		nextLightning = os.clock() + 7 + math.random() * 14
		lightning()
	end
	if os.clock() < flashUntil then
		Lighting.OutdoorAmbient = Color3.fromRGB(190, 200, 230)
	else
		Lighting.OutdoorAmbient = DRY.outdoor:Lerp(WET.outdoor, grey)
	end

	-- Wet streets (only redone when it's changed enough to see).
	if math.abs(wetness - shownWetness) > 0.02 then
		shownWetness = wetness
		for _, s in surfaces do
			s.part.Color = s.color:Lerp(Color3.new(s.color.R * 0.55, s.color.G * 0.58, s.color.B * 0.65), wetness)
			s.part.Reflectance = 0.18 * wetness
		end
		local puddleShow = math.clamp((wetness - 0.3) / 0.5, 0, 1)
		for _, p in puddles do
			p.Transparency = 1 - puddleShow * 0.85
		end
	end
end)
