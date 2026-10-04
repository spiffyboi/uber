-- Builds the opening strip: the wet road and sidewalks, a row of building
-- facades with lit windows and neon signage, streetlights, and the steam
-- grate the intro cutscene's cab rolls through -- the Taxi Driver-style shot
-- this whole scene is built around. Runs once at server start; nothing here
-- is per-player (every player shares the same strip, same as a real street).

local Lighting = game:GetService("Lighting")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))
local IntersectionBuilder = require(script.Parent.IntersectionBuilder)

local OpeningSetBuilder = {}

-- Roblox's own built-in smoke texture (ships with the client under
-- content/textures/particles). A ParticleEmitter with no Texture set falls
-- back to the default *sparkle* star, which at steam sizes (up to 7 studs)
-- rendered as big starburst flares over the street.
local STEAM_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

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
local function addWindows(building: BasePart, roadFace: Enum.NormalId, columns: number, rows: number)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Windows"
	gui.Face = roadFace
	gui.PixelsPerStud = 24
	gui.Parent = building

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
local function addSign(building: BasePart, roadFace: Enum.NormalId, text: string, color: Color3, position: UDim2, size: UDim2)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign_" .. text
	gui.Face = roadFace
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

-- Two-way lane markings: a solid double-yellow median down the centre
-- (CityConfig's lane layout puts outbound traffic on +X, inbound on -X, so
-- the true centreline is X=0), and a dashed white line between the two
-- lanes on each side. Skips straight through the intersections rather than
-- tracking around them -- crosswalk paint (IntersectionBuilder) sits on top
-- and reads as the road surface changing there, same as a real intersection.
local function buildLaneMarkings(root: Instance)
	local startZ = 20
	local endZ = -CityConfig.ROAD_LENGTH + 20

	for _, gap in { -0.15, 0.15 } do
		local median = part(
			"LaneMedian",
			Vector3.new(0.15, 0.05, CityConfig.ROAD_LENGTH),
			CFrame.new(gap, 1.03, (startZ + endZ) / 2),
			Color3.fromRGB(225, 195, 60),
			Enum.Material.SmoothPlastic
		)
		median.CanCollide = false
		median.Parent = root
	end

	for _, laneX in { CityConfig.LANE_WIDTH, -CityConfig.LANE_WIDTH } do
		local z = startZ
		while z > endZ do
			local dash = part(
				"LaneDash",
				Vector3.new(0.12, 0.05, 4),
				CFrame.new(laneX, 1.03, z),
				Color3.fromRGB(210, 210, 200),
				Enum.Material.SmoothPlastic
			)
			dash.CanCollide = false
			dash.Parent = root
			z -= 8
		end
	end
end

local function buildSidewalkSegment(root: Instance, side: number, zFrom: number, zTo: number)
	local length = zFrom - zTo
	if length <= 0 then
		return
	end
	local sidewalk = part(
		"Sidewalk",
		Vector3.new(CityConfig.SIDEWALK_WIDTH, 1.2, length),
		CFrame.new(side * (CityConfig.ROAD_WIDTH / 2 + CityConfig.SIDEWALK_WIDTH / 2), 0.6, (zFrom + zTo) / 2),
		Color3.fromRGB(90, 90, 92),
		Enum.Material.Concrete
	)
	sidewalk.Parent = root
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
	-- street" look before any weather FX are even added. (Briefly tested at
	-- 0 while chasing the "sparkle at the street cut" report -- turned out
	-- not to be the actual cause, see clearLeftoverEffects below -- restored
	-- once the real source was found.)
	road.Reflectance = 0.05
	road.Parent = root

	local sidewalkStartZ = 20
	local sidewalkEndZ = 20 - CityConfig.ROAD_LENGTH

	for side = -1, 1, 2 do
		if side == CityConfig.TAXI_RANK_SIDE then
			-- Left open across the taxi rank's own Z span -- the rank's pad
			-- (see buildTaxiRank) already provides the ground there, at road
			-- height rather than the sidewalk's slightly higher one, so it's
			-- meant to read as a driveway cut through the sidewalk, not a
			-- kerb blocking it. Confirmed live this was a real, solid kerb
			-- the whole time: a full-length, CanCollide Sidewalk slab used
			-- to run straight through the rank's footprint here with no gap
			-- at all, so a car could never actually cross from the rank onto
			-- the road no matter how it was steered -- it wasn't a driving
			-- problem, it was a wall nobody could see.
			local rankNearZ = CityConfig.TAXI_RANK_Z + CityConfig.TAXI_RANK_LENGTH / 2
			local rankFarZ = CityConfig.TAXI_RANK_Z - CityConfig.TAXI_RANK_LENGTH / 2
			buildSidewalkSegment(root, side, sidewalkStartZ, rankNearZ)
			buildSidewalkSegment(root, side, rankFarZ, sidewalkEndZ)
		else
			buildSidewalkSegment(root, side, sidewalkStartZ, sidewalkEndZ)
		end
	end

	buildLaneMarkings(root)
end

-- An invisible catch-all under the whole strip, well above Roblox's own
-- FallenPartsDestroyHeight (-500 by default) but comfortably below every
-- driving/walking surface in the scene. Confirmed live that a car driven off
-- the (previously too-short) taxi rank pad fell clean through open air and
-- was destroyed outright once it crossed that height -- the whole PlayerCar
-- Model vanished from workspace, and since this project has no PlayerModule
-- to hand the camera back to a default view on respawn, CarSystems' last
-- Scriptable camera CFrame was simply left frozen forever, which is what
-- actually read as "the camera stays in the same place" even though the car
-- itself really had moved right up until that fall. Widening the taxi rank
-- pad (see CityConfig) and cutting the sidewalk gap above close the specific
-- hole that caused this, but a floor this size is cheap insurance against
-- any other gap in this hand-placed geometry doing the same thing later.
local function buildSafetyFloor(root: Instance)
	local floor = part(
		"SafetyFloor",
		Vector3.new(240, 2, CityConfig.ROAD_LENGTH + 80),
		CFrame.new(0, -6, -CityConfig.ROAD_LENGTH / 2 + 20),
		Color3.fromRGB(10, 10, 10),
		Enum.Material.SmoothPlastic
	)
	floor.Transparency = 1
	floor.Parent = root
end

local BUILDING_COLORS = {
	Color3.fromRGB(40, 36, 34),
	Color3.fromRGB(48, 44, 46),
	Color3.fromRGB(34, 34, 40),
	Color3.fromRGB(52, 46, 40),
}

-- Real, distinct ground-floor businesses instead of a sign floating on a
-- blank wall -- every building gets one of these now (see addStorefront),
-- not just the 60% that used to roll a sign at all.
local SHOP_TYPES = {
	{ name = "MARROW DINER", awning = Color3.fromRGB(165, 35, 35), display = Color3.fromRGB(235, 150, 70) },
	{ name = "MARROW LIQUOR", awning = Color3.fromRGB(120, 35, 115), display = Color3.fromRGB(210, 70, 200) },
	{ name = "CHECK CASHING", awning = Color3.fromRGB(140, 110, 20), display = Color3.fromRGB(240, 200, 60) },
	{ name = "LAUNDRO", awning = Color3.fromRGB(25, 100, 70), display = Color3.fromRGB(90, 210, 120) },
	{ name = "BODEGA", awning = Color3.fromRGB(35, 80, 125), display = Color3.fromRGB(90, 180, 235) },
	{ name = "PAWN & TRADE", awning = Color3.fromRGB(95, 90, 40), display = Color3.fromRGB(215, 205, 110) },
	{ name = CityConfig.APP_NAME:upper() .. " KIOSK", awning = Color3.fromRGB(15, 110, 120), display = Color3.fromRGB(50, 220, 235) },
	{ name = "OPEN 24 HRS", awning = Color3.fromRGB(150, 40, 60), display = Color3.fromRGB(235, 60, 90) },
}

-- A ground-floor storefront band layered over whatever addWindows already
-- drew there: an awning with the shop's own name, a door, and a lit display
-- window. Deliberately flat colour panels, no PointLight of its own -- with
-- one on every building along the strip (see buildBuildingRow) that's ~18
-- more lights, and the "sparkle" investigation above already showed how
-- easily a scene like this one turns a pile of close bright lights into a
-- visible artifact; the awning/display colours read as "lit" on their own,
-- the same trick addWindows already uses for lit windows.
local function addStorefront(building: BasePart, roadFace: Enum.NormalId, shop: { name: string, awning: Color3, display: Color3 }, buildingHeight: number)
	local bandHeight = 9
	local fraction = math.min(1, bandHeight / buildingHeight)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Storefront"
	gui.Face = roadFace
	gui.PixelsPerStud = 32
	gui.Parent = building

	local band = Instance.new("Frame")
	band.Name = "Band"
	band.BackgroundColor3 = Color3.fromRGB(18, 16, 15)
	band.BorderSizePixel = 0
	band.Size = UDim2.new(1, 0, fraction, 0)
	band.Position = UDim2.new(0, 0, 1 - fraction, 0)
	band.Parent = gui

	local awning = Instance.new("Frame")
	awning.Name = "Awning"
	awning.BackgroundColor3 = shop.awning
	awning.BorderSizePixel = 0
	awning.Size = UDim2.new(1, 0, 0.24, 0)
	awning.Parent = band

	local awningLabel = Instance.new("TextLabel")
	awningLabel.BackgroundTransparency = 1
	awningLabel.Size = UDim2.new(0.92, 0, 1, 0)
	awningLabel.Position = UDim2.new(0.04, 0, 0, 0)
	awningLabel.Font = Enum.Font.Oswald
	awningLabel.Text = shop.name
	awningLabel.TextColor3 = Color3.fromRGB(245, 240, 225)
	awningLabel.TextScaled = true
	awningLabel.Parent = awning

	local door = Instance.new("Frame")
	door.Name = "Door"
	door.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	door.BorderSizePixel = 0
	door.Size = UDim2.new(0.16, 0, 0.6, 0)
	door.Position = UDim2.new(0.42, 0, 0.3, 0)
	door.Parent = band

	local display = Instance.new("Frame")
	display.Name = "Display"
	display.BackgroundColor3 = shop.display
	display.BackgroundTransparency = 0.3
	display.BorderSizePixel = 0
	display.Size = UDim2.new(0.3, 0, 0.5, 0)
	display.Position = UDim2.new(0.08, 0, 0.34, 0)
	display.Parent = band
end

local function buildBuildingRow(root: Instance)
	local edge = CityConfig.ROAD_WIDTH / 2 + CityConfig.SIDEWALK_WIDTH + 3
	local spacing = CityConfig.BLOCK_SPACING
	local count = math.floor(CityConfig.ROAD_LENGTH / spacing)
	local intersectionIndices = {}
	for _, index in CityConfig.INTERSECTION_BLOCK_INDICES do
		intersectionIndices[index] = true
	end

	for side = -1, 1, 2 do
		-- Buildings sit offset along X with no yaw of their own (see `part`),
		-- so local axes match world axes: a side=-1 (west) building's road-
		-- facing wall is its +X ("Right") face, and a side=1 (east) building's
		-- is its -X ("Left") face. Getting this wrong doesn't error -- the
		-- SurfaceGuis just end up on the far end-cap nobody driving down the
		-- street ever sees, which is what silently happened here before.
		local roadFace = if side == -1 then Enum.NormalId.Right else Enum.NormalId.Left

		for i = 0, count do
			-- Skipped entirely at the block indices IntersectionBuilder turns
			-- into real cross streets -- otherwise a building would sit right
			-- on top of (or straddling) the intersection it's supposed to
			-- leave open. The taxi rank (see buildTaxiRank) only takes up one
			-- side of its own block, so the far side still gets a building.
			if intersectionIndices[i] then
				continue
			end
			if i == CityConfig.TAXI_RANK_BLOCK_INDEX and side == CityConfig.TAXI_RANK_SIDE then
				continue
			end

			local z = CityConfig.blockZ(i)
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

			-- CanCollide stays on the whole block so it still blocks driving
			-- off the strip.
			local rows = math.max(3, math.floor(height / 8))
			addWindows(building, roadFace, 5, rows)
			addStorefront(building, roadFace, SHOP_TYPES[math.random(1, #SHOP_TYPES)], height)

			if math.random() < 0.5 then
				local sign = SHOP_TYPES[math.random(1, #SHOP_TYPES)]
				addSign(building, roadFace, sign.name, sign.display, UDim2.new(0.15, 0, 0.35, 0), UDim2.new(0.7, 0, 0.1, 0))
			end
		end
	end
end

-- A pull-in bay the player's cab actually starts parked in, off the driving
-- lanes entirely -- see CityConfig.TAXI_RANK_* for why (it used to spawn
-- straight into a live traffic lane). A driveway apron across the sidewalk,
-- a paved lot in the gap buildBuildingRow leaves for it, two marked parking
-- bays, and a sign.
local function buildTaxiRank(root: Instance)
	local nearX = CityConfig.TAXI_RANK_X_NEAR
	local farX = CityConfig.TAXI_RANK_X_FAR
	local z = CityConfig.TAXI_RANK_Z
	local centerX = (nearX + farX) / 2

	-- At road height (top face Y=1, same as buildRoad's own Road part), not
	-- the sidewalk's slightly higher one -- it spans across/over the
	-- sidewalk's own footprint here, reading as a driveway cut through it
	-- rather than a second, mismatched ground plane.
	local pad = part(
		"TaxiRank",
		Vector3.new(farX - nearX, 1, CityConfig.TAXI_RANK_LENGTH),
		CFrame.new(centerX, 0.5, z),
		Color3.fromRGB(38, 36, 34),
		Enum.Material.Asphalt
	)
	pad.Parent = root

	-- Two marked parking-bay outlines, side by side along Z.
	for _, bayZ in { z - 5, z + 5 } do
		local outline = part(
			"RankBayLine",
			Vector3.new(farX - nearX - 6, 0.05, 0.15),
			CFrame.new(centerX, 1.03, bayZ),
			Color3.fromRGB(225, 195, 60),
			Enum.Material.SmoothPlastic
		)
		outline.CanCollide = false
		outline.Parent = root
	end

	-- At the back corner by the building line, on a pole -- it used to float
	-- unsupported at head height right on the rank's exit, where a car
	-- pulling out would clip it.
	local signX = farX - 1.5
	local signZ = z + CityConfig.TAXI_RANK_LENGTH / 2 - 1.5
	local signPole = part("TaxiRankSignPole", Vector3.new(0.3, 6, 0.3), CFrame.new(signX, 4, signZ), Color3.fromRGB(40, 40, 44), Enum.Material.SmoothPlastic)
	signPole.Parent = root
	local sign = part("TaxiRankSign", Vector3.new(0.15, 2, 3), CFrame.new(signX - 0.25, 6, signZ) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(225, 195, 60), Enum.Material.SmoothPlastic)
	sign.Parent = root

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 40
	gui.Parent = sign

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.9, 0, 0.9, 0)
	label.Position = UDim2.new(0.05, 0, 0.05, 0)
	label.Font = Enum.Font.SourceSansBold
	label.Text = "TAXI STAND"
	label.TextColor3 = Color3.fromRGB(20, 20, 24)
	label.TextWrapped = true
	label.TextScaled = true
	label.Parent = gui
end

-- {z, side} of each shelter -- picked by hand rather than another spacing
-- loop, spread out along the strip and clear of the intersections (see
-- CityConfig.INTERSECTION_Z, -82/-184) and the grate/spawn area near z=20.
local BUS_STOP_SPOTS = {
	{ z = -40, side = 1 },
	{ z = -150, side = -1 },
	{ z = -260, side = 1 },
}

local function buildBusStop(root: Instance, z: number, side: number)
	-- Toward the building side of the (now 12-wide) sidewalk, not the kerb --
	-- streetlights already own the kerb line (edge = ROAD_WIDTH/2 + 1.5).
	local x = side * (CityConfig.ROAD_WIDTH / 2 + CityConfig.SIDEWALK_WIDTH - 2.5)
	local facing = if side == -1 then CFrame.Angles(0, math.pi / 2, 0) else CFrame.Angles(0, -math.pi / 2, 0)

	local backPanel = part("BusShelterBack", Vector3.new(0.15, 7, 8), CFrame.new(x, 3.5, z) * facing, Color3.fromRGB(60, 65, 75), Enum.Material.SmoothPlastic)
	backPanel.Transparency = 0.25
	backPanel.Parent = root

	local roof = part("BusShelterRoof", Vector3.new(3.5, 0.2, 8.4), CFrame.new(x - side * 1.7, 7, z) * facing, Color3.fromRGB(35, 35, 40), Enum.Material.SmoothPlastic)
	roof.Parent = root

	for _, endZ in { -3.5, 3.5 } do
		local sidePanel = part("BusShelterSide", Vector3.new(3.4, 6.6, 0.12), CFrame.new(x - side * 1.7, 3.4, z + endZ) * facing, Color3.fromRGB(60, 65, 75), Enum.Material.SmoothPlastic)
		sidePanel.Transparency = 0.35
		sidePanel.Parent = root
	end

	local bench = part("BusShelterBench", Vector3.new(3, 1.1, 1.4), CFrame.new(x - side * 1.6, 1.4, z) * facing, Color3.fromRGB(40, 38, 36), Enum.Material.WoodPlanks)
	bench.Parent = root

	local pole = part("BusStopPole", Vector3.new(0.35, 7.5, 0.35), CFrame.new(x - side * 3.7, 3.75, z), Color3.fromRGB(40, 90, 150), Enum.Material.SmoothPlastic)
	pole.Parent = root

	local sign = part("BusStopSign", Vector3.new(0.1, 1.6, 1.4), CFrame.new(x - side * 3.7, 7, z) * facing, Color3.fromRGB(40, 90, 150), Enum.Material.SmoothPlastic)
	sign.Parent = root

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 60
	gui.Parent = sign

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Font = Enum.Font.SourceSansBold
	label.Text = "BUS"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Parent = gui
end

local function buildBusStops(root: Instance)
	for _, spot in BUS_STOP_SPOTS do
		buildBusStop(root, spot.z, spot.side)
	end
end

-- True inside the taxi rank's own Z span on its own side -- kept clear of
-- clutter (hydrants, cans) so nothing about the pull-out fix above (the
-- widened pad, the sidewalk gap) gets visually or physically crowded again.
local function inTaxiRankGap(side: number, z: number): boolean
	if side ~= CityConfig.TAXI_RANK_SIDE then
		return false
	end
	local half = CityConfig.TAXI_RANK_LENGTH / 2
	return z < CityConfig.TAXI_RANK_Z + half and z > CityConfig.TAXI_RANK_Z - half
end

-- A fire hydrant, right at the kerb -- a small, common bit of street reading
-- that so far only had lampposts and signage on it.
local function buildHydrant(root: Instance, x: number, z: number)
	local base = part("HydrantBase", Vector3.new(0.9, 1.4, 0.9), CFrame.new(x, 0.7, z), Color3.fromRGB(150, 35, 35), Enum.Material.SmoothPlastic)
	base.Parent = root

	local cap = part("HydrantCap", Vector3.new(0.5, 0.35, 0.5), CFrame.new(x, 1.55, z), Color3.fromRGB(170, 45, 45), Enum.Material.SmoothPlastic)
	cap.Parent = root

	for _, side in { -1, 1 } do
		local nozzle = part("HydrantNozzle", Vector3.new(0.35, 0.35, 0.35), CFrame.new(x + side * 0.5, 0.9, z), Color3.fromRGB(150, 35, 35), Enum.Material.SmoothPlastic)
		nozzle.Parent = root
	end
end

-- A curbside trash can, toward the building line rather than the kerb --
-- same band pedestrians (PedestrianSpawner) already walk, so it reads as
-- something they'd actually walk past.
local function buildTrashCan(root: Instance, x: number, z: number)
	local can = part("TrashCan", Vector3.new(1.3, 2.2, 1.3), CFrame.new(x, 1.1, z), Color3.fromRGB(45, 48, 45), Enum.Material.DiamondPlate)
	can.Parent = root

	local lid = part("TrashCanLid", Vector3.new(1.4, 0.15, 1.4), CFrame.new(x, 2.28, z), Color3.fromRGB(35, 38, 35), Enum.Material.Metal)
	lid.Parent = root
end

-- A second, smaller steam grate -- purely atmospheric, the same Taxi Driver
-- beat the opening grate establishes, echoed a couple more times along the
-- strip instead of only ever appearing once at the very start.
local function buildStreetVent(root: Instance, x: number, z: number)
	local grate = part("StreetVent", Vector3.new(3, 0.15, 2.5), CFrame.new(x, 1.05, z), Color3.fromRGB(15, 15, 16), Enum.Material.DiamondPlate)
	grate.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = STEAM_TEXTURE
	emitter.Color = ColorSequence.new(Color3.fromRGB(200, 200, 205))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.5, 2.5),
		NumberSequenceKeypoint.new(1, 4.5),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(2.5, 4)
	emitter.Rate = 8
	emitter.Speed = NumberRange.new(0.8, 1.6)
	emitter.SpreadAngle = Vector2.new(12, 12)
	emitter.VelocityInheritance = 0
	emitter.Acceleration = Vector3.new(0, 1.6, 0)
	emitter.Parent = grate
end

local STREET_VENT_Z = { -96, -218 }

local function buildStreetProps(root: Instance)
	local kerbX = CityConfig.ROAD_WIDTH / 2 + 0.6
	local innerX = CityConfig.ROAD_WIDTH / 2 + CityConfig.SIDEWALK_WIDTH - 1.8
	local spacing = 34

	for side = -1, 1, 2 do
		local count = math.floor(CityConfig.ROAD_LENGTH / spacing)
		for i = 0, count do
			local z = 14 - i * spacing
			if inTaxiRankGap(side, z) then
				continue
			end
			if i % 2 == 0 then
				buildHydrant(root, side * kerbX, z)
			else
				buildTrashCan(root, side * innerX, z + 4)
			end
		end
	end

	for _, z in STREET_VENT_Z do
		buildStreetVent(root, 0, z)
	end
end

-- Small rectangular plates, NYC-parking-sign style, mounted low on a handful
-- of streetlight poles -- flavour/atmosphere, not functionally enforced by
-- TrafficSpawner (which only reacts to the actual traffic lights).
local STREET_SIGN_TEXTS = { "SPEED LIMIT 25", "NO STANDING", "TAXI STAND", "DON'T BLOCK BOX" }

local function addPoleSign(root: Instance, pole: BasePart, side: number)
	-- Offset toward the road side of the pole (the opposite of `side`, which
	-- points away from the road -- see buildStreetlights), so the plate faces
	-- traffic/pedestrians instead of the building wall behind it.
	local plate = part(
		"PoleSign",
		Vector3.new(0.06, 1.6, 1.4),
		pole.CFrame * CFrame.new(-side * 0.45, 3, 0) * CFrame.Angles(0, if side == -1 then -math.pi / 2 else math.pi / 2, 0),
		Color3.fromRGB(235, 235, 230),
		Enum.Material.SmoothPlastic
	)
	plate.Parent = root

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 50
	gui.Parent = plate

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.9, 0, 0.9, 0)
	label.Position = UDim2.new(0.05, 0, 0.05, 0)
	label.Font = Enum.Font.SourceSansBold
	label.Text = STREET_SIGN_TEXTS[math.random(1, #STREET_SIGN_TEXTS)]
	label.TextColor3 = Color3.fromRGB(15, 15, 20)
	label.TextWrapped = true
	label.TextScaled = true
	label.Parent = gui
end

local function buildStreetlights(root: Instance)
	local edge = CityConfig.ROAD_WIDTH / 2 + 1.5
	local spacing = 40
	local count = math.floor(CityConfig.ROAD_LENGTH / spacing)

	for side = -1, 1, 2 do
		for i = 0, count do
			local z = 20 - i * spacing
			-- Not across the taxi rank's driveway: a pole on the kerb line
			-- there sits exactly where a car pulling out of the rank turns.
			if inTaxiRankGap(side, z) then
				continue
			end
			-- Metal carries a strong, tight specular response in Roblox's
			-- renderer -- confirmed live this (not Bloom, not the leftover
			-- effects rig, both independently ruled out by disabling them
			-- entirely with the flares unchanged) was the actual "sparkle"
			-- mechanism: a bright PointLight this close to a glossy Metal
			-- surface renders as a sharp specular hotspot regardless of any
			-- Lighting post-effect. Switched to SmoothPlastic, which has a
			-- much softer/duller specular response, so the pole/head still
			-- catch light without throwing it back as a hard glint.
			local pole = part("StreetlightPole", Vector3.new(0.8, 16, 0.8), CFrame.new(side * edge, 8, z), Color3.fromRGB(20, 20, 22), Enum.Material.SmoothPlastic)
			pole.Parent = root

			local head = part("StreetlightHead", Vector3.new(2.5, 0.6, 1), CFrame.new(side * (edge - side * 1.2), 15.8, z), Color3.fromRGB(20, 20, 22), Enum.Material.SmoothPlastic)
			head.Parent = root

			-- A downward SpotLight rather than a PointLight: it throws a real
			-- sodium-orange pool onto the road below without lighting up the
			-- pole/head themselves, which is what used to make close
			-- streetlights glint (the old PointLight had to be cut to 0.8
			-- brightness, range 10 to stop that -- too dim to light the road).
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Bottom
			light.Color = Color3.fromRGB(255, 175, 90)
			light.Brightness = 2.5
			light.Range = 22
			light.Angle = 110
			light.Parent = head

			if math.random() < 0.4 then
				addPoleSign(root, pole, side)
			end
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
	emitter.Texture = STEAM_TEXTURE
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

-- This project was scaffolded from an earlier game's (Brew a Potion!'s)
-- reusable modules, which came with their own default Lighting rig still
-- sitting in place -- a full-strength BloomEffect (Intensity 1, Size 24,
-- Threshold 2 -- Roblox's literal engine defaults, never touched), a second
-- Atmosphere, and an active SunRaysEffect. Every earlier pass at the
-- "sparkle at the street cut" report was only ever tuning *our own* Bloom
-- below -- confirmed live in Studio that this untouched leftover set was
-- stacked on top of it the entire time, at full engine-default strength,
-- and was the actual dominant source of the starburst flares (a bright,
-- close light rendered as a sharp multi-point burst is a known Bloom/
-- SunRays artifact on small very-bright points, not a soft glow -- no
-- amount of tuning *our* effect instances was ever going to fix a second,
-- untouched set still running at full strength beside them). Cleared before
-- building our own set below, rather than tuned in place, since nothing
-- else in the game should be depending on this scaffold's specific values.
local function clearLeftoverEffects()
	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end
end

-- Dead of night, cool and hazy -- the whole reason the neon reads the way it
-- does. Every other light in the scene (streetlamps, signs, headlights)
-- fights this darkness, which is what gives them their glow.
local function setupLighting()
	clearLeftoverEffects()

	Lighting.ClockTime = 1.5
	Lighting.Brightness = 1
	-- Raised (2026-10-04): at (18,20,28) / -0.3 exposure the road itself was
	-- invisible from the driver's seat and a character on foot was a black
	-- silhouette -- too dark to actually drive or walk. Still a cold, blue
	-- night, just a readable one.
	Lighting.Ambient = Color3.fromRGB(48, 52, 66)
	Lighting.OutdoorAmbient = Color3.fromRGB(70, 76, 96)
	Lighting.ExposureCompensation = 0
	Lighting.GlobalShadows = true

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

	-- `Size` (spatial spread of the flare), not just `Intensity`, was the
	-- real culprit for the stray "sparkle at the spawn point" report: at 24
	-- it was wide enough that even a streetlight/the grate's steam 20+ studs
	-- away, directly down the spawn's own sightline toward the grate, threw
	-- a visible star flare into frame from spawn. Shrunk down and the
	-- threshold raised so only genuinely bright, close sources (headlights,
	-- signs up close) still bloom.
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.25
	bloom.Size = 8
	bloom.Threshold = 1.8
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
	buildSafetyFloor(root)
	buildRoad(root)
	buildBuildingRow(root)
	buildTaxiRank(root)
	IntersectionBuilder.build(root)
	buildStreetlights(root)
	buildBusStops(root)
	buildStreetProps(root)
	buildGrate(root)
	buildSpawn(root)

	-- The Rojo/Studio default scaffold's own Baseplate and SpawnLocation --
	-- leftovers from the very first place build, never actually part of this
	-- scene. IntroSpawn (see buildSpawn above) is the only spawn point this
	-- game should ever use.
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	local defaultSpawn = workspace:FindFirstChild("SpawnLocation")
	if defaultSpawn then
		defaultSpawn:Destroy()
	end

	return root
end

return OpeningSetBuilder
