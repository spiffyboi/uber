-- Builds the opening strip: the wet road and sidewalks, a row of building
-- facades with lit windows and neon signage, streetlights, and the steam
-- grate the intro cutscene's cab rolls through -- the Taxi Driver-style shot
-- this whole scene is built around. Runs once at server start; nothing here
-- is per-player (every player shares the same strip, same as a real street).

local Lighting = game:GetService("Lighting")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))

local OpeningSetBuilder = {}

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- A lit or dark window: most are dark at this hour, a handful still lit, same
-- as a real block at 2am.
local function addWindows(face: BasePart, columns: number, rows: number)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Windows"
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 24
	gui.Parent = face

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / columns, -6, 1 / rows, -6)
	grid.CellPadding = UDim2.new(0, 6, 0, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = gui

	for i = 1, columns * rows do
		local lit = math.random() < 0.16
		local window = Instance.new("Frame")
		window.Name = "Window" .. i
		window.BackgroundColor3 = if lit then Color3.fromRGB(235, 200, 120) else Color3.fromRGB(10, 11, 15)
		window.BorderSizePixel = 0
		window.Parent = gui
	end
end

-- A backlit sign on a building front: a neon-coloured plate with its name on
-- it, the kind of thing that streaks across a rain-slicked windshield.
local function addSign(building: BasePart, text: string, color: Color3, position: UDim2, size: UDim2)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign_" .. text
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 36
	gui.Parent = building

	local plate = Instance.new("Frame")
	plate.BackgroundColor3 = Color3.new(0, 0, 0)
	plate.BackgroundTransparency = 0.15
	plate.Position = position
	plate.Size = size
	plate.BorderSizePixel = 0
	plate.Parent = gui

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Font = Enum.Font.Oswald
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Parent = plate

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 1.5
	light.Range = 14
	light.Parent = building
end

local function buildRoad(root: Instance)
	local road = part(
		"Road",
		Vector3.new(CityConfig.ROAD_WIDTH, 1, CityConfig.ROAD_LENGTH),
		CFrame.new(0, 0.5, -CityConfig.ROAD_LENGTH / 2 + 20),
		Color3.fromRGB(35, 35, 38),
		Enum.Material.Asphalt
	)
	-- A high reflectance on wet-looking asphalt is most of the "rain-slicked
	-- street" look before any weather FX are even added.
	road.Reflectance = 0.05
	road.Parent = root

	for side = -1, 1, 2 do
		local sidewalk = part(
			"Sidewalk",
			Vector3.new(CityConfig.SIDEWALK_WIDTH, 1.2, CityConfig.ROAD_LENGTH),
			CFrame.new(side * (CityConfig.ROAD_WIDTH / 2 + CityConfig.SIDEWALK_WIDTH / 2), 0.6, -CityConfig.ROAD_LENGTH / 2 + 20),
			Color3.fromRGB(90, 90, 92),
			Enum.Material.Concrete
		)
		sidewalk.Parent = root
	end
end

local BUILDING_COLORS = {
	Color3.fromRGB(40, 36, 34),
	Color3.fromRGB(48, 44, 46),
	Color3.fromRGB(34, 34, 40),
	Color3.fromRGB(52, 46, 40),
}

local SIGNS = {
	{ text = CityConfig.APP_NAME:upper(), color = Color3.fromRGB(50, 220, 235) },
	{ text = "OPEN 24 HRS", color = Color3.fromRGB(235, 60, 90) },
	{ text = "CHECK CASHING", color = Color3.fromRGB(240, 200, 60) },
	{ text = "MARROW LIQUOR", color = Color3.fromRGB(210, 70, 200) },
	{ text = "LAUNDRO", color = Color3.fromRGB(90, 210, 120) },
}

local function buildBuildingRow(root: Instance)
	local edge = CityConfig.ROAD_WIDTH / 2 + CityConfig.SIDEWALK_WIDTH + 3
	local spacing = 34
	local count = math.floor(CityConfig.ROAD_LENGTH / spacing)

	for side = -1, 1, 2 do
		for i = 0, count do
			local z = 20 - i * spacing
			local height = math.random(24, 58)
			local width = spacing - 4
			local depth = 20
			local x = side * (edge + depth / 2)

			local building = part(
				`Building_{side}_{i}`,
				Vector3.new(depth, height, width),
				CFrame.new(x, height / 2, z),
				BUILDING_COLORS[math.random(1, #BUILDING_COLORS)],
				Enum.Material.Concrete
			)
			building.Parent = root

			-- The face pointing at the road is the one with windows/signage;
			-- CanCollide stays on the whole block so it still blocks driving off
			-- the strip.
			local rows = math.max(3, math.floor(height / 8))
			addWindows(building, 5, rows)

			if math.random() < 0.6 then
				local sign = SIGNS[math.random(1, #SIGNS)]
				addSign(building, sign.text, sign.color, UDim2.new(0.15, 0, 0.05, 0), UDim2.new(0.7, 0, 0.12, 0))
			end
		end
	end
end

local function buildStreetlights(root: Instance)
	local edge = CityConfig.ROAD_WIDTH / 2 + 1.5
	local spacing = 40
	local count = math.floor(CityConfig.ROAD_LENGTH / spacing)

	for side = -1, 1, 2 do
		for i = 0, count do
			local z = 20 - i * spacing
			local pole = part("StreetlightPole", Vector3.new(0.8, 16, 0.8), CFrame.new(side * edge, 8, z), Color3.fromRGB(20, 20, 22), Enum.Material.Metal)
			pole.Parent = root

			local head = part("StreetlightHead", Vector3.new(2.5, 0.6, 1), CFrame.new(side * (edge - side * 1.2), 15.8, z), Color3.fromRGB(20, 20, 22), Enum.Material.Metal)
			head.Parent = root

			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 175, 90)
			light.Brightness = 2.5
			light.Range = 22
			light.Parent = head
		end
	end
end

-- The steam grate the cab rolls through at the very start of the intro --
-- the iconic Taxi Driver beat this scene opens on.
local function buildGrate(root: Instance)
	local grate = part("SteamGrate", Vector3.new(6, 0.2, 4), CFrame.new(CityConfig.GRATE_POSITION), Color3.fromRGB(15, 15, 16), Enum.Material.DiamondPlate)
	grate.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Steam"
	emitter.Color = ColorSequence.new(Color3.fromRGB(200, 200, 205))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 4),
		NumberSequenceKeypoint.new(1, 7),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(3, 5)
	emitter.Rate = 12
	emitter.Speed = NumberRange.new(1, 2)
	emitter.SpreadAngle = Vector2.new(15, 15)
	emitter.VelocityInheritance = 0
	emitter.Acceleration = Vector3.new(0, 2, 0)
	emitter.Parent = grate
end

-- Dead of night, cool and hazy -- the whole reason the neon reads the way it
-- does. Every other light in the scene (streetlamps, signs, headlights)
-- fights this darkness, which is what gives them their glow.
local function setupLighting()
	Lighting.ClockTime = 1.5
	Lighting.Brightness = 1
	Lighting.Ambient = Color3.fromRGB(18, 20, 28)
	Lighting.OutdoorAmbient = Color3.fromRGB(18, 20, 28)
	Lighting.ExposureCompensation = -0.3
	Lighting.GlobalShadows = true
	Lighting.Technology = Enum.Technology.Future

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.4
	atmosphere.Offset = 0.25
	atmosphere.Color = Color3.fromRGB(60, 65, 80)
	atmosphere.Decay = Color3.fromRGB(20, 22, 30)
	atmosphere.Glare = 0.1
	atmosphere.Haze = 2.2
	atmosphere.Parent = Lighting

	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.TintColor = Color3.fromRGB(210, 225, 235)
	colorCorrection.Contrast = 0.1
	colorCorrection.Saturation = -0.15
	colorCorrection.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 24
	bloom.Threshold = 1.4
	bloom.Parent = Lighting
end

-- Invisible, non-collide: players spawn here by default before CarSpawner
-- seats them in their own car, so nobody ever falls through the world while
-- their character loads in.
local function buildSpawn(root: Instance)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "IntroSpawn"
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = CFrame.new(CityConfig.GRATE_POSITION + Vector3.new(0, 0, 20))
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Anchored = true
	spawn.Duration = 0
	spawn.Parent = root
end

function OpeningSetBuilder.build()
	local root = Instance.new("Folder")
	root.Name = "OpeningSet"
	root.Parent = workspace

	setupLighting()
	buildRoad(root)
	buildBuildingRow(root)
	buildStreetlights(root)
	buildGrate(root)
	buildSpawn(root)

	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	return root
end

return OpeningSetBuilder
