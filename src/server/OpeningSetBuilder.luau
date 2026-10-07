-- Builds the streets of Marrow Heights: the wet roads and sidewalks of the
-- whole grid (see CityConfig.AVENUES/CROSS_STREETS), lane markings,
-- streetlights, bus shelters and kerbside clutter, the steam grate the intro
-- cutscene's cab rolls through on Marrow St -- the Taxi Driver-style shot
-- this whole scene is built around -- and the night lighting. The buildings
-- and places along the streets are DistrictBuilder's; the crossings and
-- traffic signals IntersectionBuilder's. Runs once at server start; nothing
-- here is per-player.

local Lighting = game:GetService("Lighting")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))
local IntersectionBuilder = require(script.Parent.IntersectionBuilder)
local DistrictBuilder = require(script.Parent.DistrictBuilder)
local StreetGrid = require(Shared:WaitForChild("StreetGrid"))
local BuildPacer = require(script.Parent.BuildPacer)

local OpeningSetBuilder = {}

-- Roblox's own built-in smoke texture (ships with the client under
-- content/textures/particles). A ParticleEmitter with no Texture set falls
-- back to the default *sparkle* star, which at steam sizes (up to 7 studs)
-- rendered as big starburst flares over the street.
local STEAM_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local AVENUE_HALF = CityConfig.ROAD_WIDTH / 2
local CROSS_HALF = CityConfig.CROSS_STREET_WIDTH / 2
local AVENUE_EDGE = CityConfig.BUILDING_EDGE
local CROSS_EDGE = CityConfig.CROSS_BUILDING_EDGE
local GRID_TOP = CityConfig.GRID_TOP_Z
local GRID_BOTTOM = CityConfig.GRID_BOTTOM_Z
local GRID_LEFT = CityConfig.GRID_LEFT_X
local GRID_RIGHT = CityConfig.GRID_RIGHT_X

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

-- Paint and small clutter: never collides or casts a shadow.
local function detail(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

-- A box covering world X [x1, x2], Z [z1, z2] (either order).
local function slab(root: Instance, name: string, x1: number, x2: number, z1: number, z2: number, y: number, height: number, color: Color3, material: Enum.Material): Part?
	local width, length = math.abs(x2 - x1), math.abs(z2 - z1)
	if width < 0.1 or length < 0.1 then
		return nil
	end
	local p = part(name, Vector3.new(width, height, length), CFrame.new((x1 + x2) / 2, y, (z1 + z2) / 2), color, material)
	p.Parent = root
	return p
end

local ASPHALT = Color3.fromRGB(35, 35, 38)
local CONCRETE = Color3.fromRGB(90, 90, 92)

-- Is world `z` in front of any named place on that side of the avenue at
-- `x`? Kept clear of street clutter: a taxi rank's driveway has to stay
-- open, and the other places have their own frontage (club queues, produce
-- stands, canopies, the park walls).
local function lotFrontage(x: number, side: number, z: number): boolean
	return CityConfig.lotAt(CityConfig.slotAt(z), side, x) ~= nil
end

-- Is world `z` within a block's length either side of a taxi rank on that
-- side of the avenue at `x`? A cab pulling out of a rank drives straight on
-- along the sidewalk line for a moment before it turns onto the road --
-- confirmed live it ran straight into a trash can there.
local function nearRank(x: number, side: number, z: number): boolean
	for _, lot in CityConfig.LOTS do
		if lot.kind == "taxiRank" and lot.x == x and lot.side == side then
			local near, far = CityConfig.lotZRange(lot)
			if z < near + CityConfig.BLOCK_SPACING and z > far - CityConfig.BLOCK_SPACING then
				return true
			end
		end
	end
	return false
end

local function isOutward(avenueIndex: number, side: number): boolean
	return (avenueIndex == 1 and side == -1) or (avenueIndex == #CityConfig.AVENUES and side == 1)
end

-- The stretches of sidewalk along one side of an avenue, as Z ranges
-- {from, to} with from > to: between each pair of cross streets (corner to
-- corner), or one unbroken run on an outward-facing side.
local function avenueSidewalkRuns(avenueIndex: number, side: number): { { number } }
	local runs = {}
	if isOutward(avenueIndex, side) then
		table.insert(runs, { GRID_TOP + CROSS_HALF, GRID_BOTTOM - CROSS_HALF })
	else
		for c = 1, #CityConfig.CROSS_STREETS - 1 do
			table.insert(runs, { CityConfig.CROSS_STREETS[c].z - CROSS_HALF, CityConfig.CROSS_STREETS[c + 1].z + CROSS_HALF })
		end
	end
	return runs
end

-- ===== Ground, roads and sidewalks =====

-- Under everything: a dark ground slab for the middles of blocks and the
-- gaps between buildings, and an invisible catch-all floor well below it --
-- confirmed live that a car that found a gap in hand-placed geometry fell
-- clean through and was destroyed once it crossed FallenPartsDestroyHeight,
-- leaving the player with no car.
local function buildGround(root: Instance)
	local margin = 200
	local ground = slab(root, "Ground", GRID_LEFT - margin, GRID_RIGHT + margin, GRID_TOP + margin, GRID_BOTTOM - margin, 0.3, 1, Color3.fromRGB(28, 27, 26), Enum.Material.Concrete)
	if ground then
		ground.CastShadow = false
	end
	local floor = slab(root, "SafetyFloor", GRID_LEFT - margin, GRID_RIGHT + margin, GRID_TOP + margin, GRID_BOTTOM - margin, -6, 2, Color3.fromRGB(10, 10, 10), Enum.Material.SmoothPlastic)
	if floor then
		floor.Transparency = 1
	end
end

local function buildRoads(root: Instance)
	for _, avenue in CityConfig.AVENUES do
		local road = slab(root, "Avenue_" .. avenue.name, avenue.x - AVENUE_HALF, avenue.x + AVENUE_HALF, GRID_TOP + CROSS_HALF, GRID_BOTTOM - CROSS_HALF, 0.5, 1, ASPHALT, Enum.Material.Asphalt) :: Part
		-- A little reflectance on the asphalt is most of the "rain-slicked
		-- street" look before any weather FX are even added.
		road.Reflectance = 0.05
	end
	-- Cross streets stop at each avenue's kerb: overlapping the avenue's own
	-- surface at the same height would z-fight (flicker) at every junction.
	for _, street in CityConfig.CROSS_STREETS do
		for a = 1, #CityConfig.AVENUES - 1 do
			local road = slab(root, "Street_" .. street.name, CityConfig.AVENUES[a].x + AVENUE_HALF, CityConfig.AVENUES[a + 1].x - AVENUE_HALF, street.z - CROSS_HALF, street.z + CROSS_HALF, 0.5, 1, ASPHALT, Enum.Material.Asphalt) :: Part
			road.Reflectance = 0.05
		end
	end
end

local function buildSidewalks(root: Instance)
	-- Along the avenues, kerb to building line, broken at every taxi rank:
	-- the rank's pad (see DistrictBuilder) is the ground there, at road
	-- height, as a driveway -- confirmed live that a solid sidewalk slab
	-- through a rank is an invisible kerb no car can cross.
	for a, avenue in CityConfig.AVENUES do
		for side = -1, 1, 2 do
			local x1, x2 = avenue.x + side * AVENUE_HALF, avenue.x + side * AVENUE_EDGE
			local ranks = {}
			for _, lot in CityConfig.LOTS do
				if lot.kind == "taxiRank" and lot.x == avenue.x and lot.side == side then
					table.insert(ranks, lot)
				end
			end
			table.sort(ranks, function(p, q)
				return p.index < q.index
			end)
			for _, run in avenueSidewalkRuns(a, side) do
				local from = run[1]
				for _, lot in ranks do
					local near, far = CityConfig.lotZRange(lot)
					if near <= run[1] and far >= run[2] then
						slab(root, "Sidewalk", x1, x2, from, near, 0.6, 1.2, CONCRETE, Enum.Material.Concrete)
						from = far
					end
				end
				slab(root, "Sidewalk", x1, x2, from, run[2], 0.6, 1.2, CONCRETE, Enum.Material.Concrete)
			end
		end
	end

	-- Along the cross streets, between the avenues' corner sidewalks; the
	-- outer side of the first and last cross street runs the grid's width.
	for c, street in CityConfig.CROSS_STREETS do
		for side = -1, 1, 2 do
			local z1, z2 = street.z + side * CROSS_HALF, street.z + side * CROSS_EDGE
			local outward = (c == 1 and side == 1) or (c == #CityConfig.CROSS_STREETS and side == -1)
			if outward then
				slab(root, "Sidewalk", GRID_LEFT - AVENUE_EDGE, GRID_RIGHT + AVENUE_EDGE, z1, z2, 0.6, 1.2, CONCRETE, Enum.Material.Concrete)
			else
				for a = 1, #CityConfig.AVENUES - 1 do
					slab(root, "Sidewalk", CityConfig.AVENUES[a].x + AVENUE_EDGE, CityConfig.AVENUES[a + 1].x - AVENUE_EDGE, z1, z2, 0.6, 1.2, CONCRETE, Enum.Material.Concrete)
				end
			end
		end
	end
end

-- Lane paint for one stretch of street between two junctions: a double
-- yellow line down the middle, and (on the avenues) dashed white lines
-- between each direction's two lanes. `from`/`to` are the street's
-- centreline at the two stop lines.
local function paintStretch(root: Instance, from: Vector3, to: Vector3, lanes: boolean)
	BuildPacer.breathe()
	local along = (to - from).Unit
	local right = along:Cross(Vector3.yAxis)
	local length = (to - from).Magnitude
	local mid = (from + to) / 2 + Vector3.new(0, 1.03, 0)
	for _, gap in { -0.2, 0.2 } do
		local p = mid + right * gap
		detail(part("Median", Vector3.new(0.18, 0.05, length), CFrame.lookAt(p, p + along), Color3.fromRGB(225, 195, 60))).Parent = root
	end
	if lanes then
		for _, offset in { -CityConfig.LANE_WIDTH, CityConfig.LANE_WIDTH } do
			local d = 4
			while d < length - 4 do
				local p = from + along * (d + 2.5) + right * offset + Vector3.new(0, 1.03, 0)
				detail(part("LaneDash", Vector3.new(0.15, 0.05, 5), CFrame.lookAt(p, p + along), Color3.fromRGB(210, 210, 200))).Parent = root
				d += 12
			end
		end
	end
end

local function buildLaneMarkings(root: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "LaneMarkings"
	folder.Parent = root
	for i = 1, #CityConfig.AVENUES do
		for j = 1, #CityConfig.CROSS_STREETS do
			local node = StreetGrid.node(i, j) :: StreetGrid.Node
			local below = StreetGrid.node(i, j + 1)
			if below then
				paintStretch(folder, node.position + Vector3.new(0, 0, -StreetGrid.AVENUE_STOP), below.position + Vector3.new(0, 0, StreetGrid.AVENUE_STOP), true)
			end
			local beside = StreetGrid.node(i + 1, j)
			if beside then
				paintStretch(folder, node.position + Vector3.new(StreetGrid.CROSS_STOP, 0, 0), beside.position - Vector3.new(StreetGrid.CROSS_STOP, 0, 0), false)
			end
		end
	end
end

-- ===== Streetlights =====

-- Small rectangular plates, NYC-parking-sign style, mounted low on some
-- streetlight poles -- flavour, not enforced by anything.
local STREET_SIGN_TEXTS = { "SPEED LIMIT 25", "NO STANDING", "TAXI STAND", "DON'T BLOCK BOX", "NO PARKING 12AM-6AM", "ONE HOUR PARKING" }

local function addPoleSign(root: Instance, pole: BasePart, toRoad: Vector3)
	local plate = detail(part("PoleSign", Vector3.new(1.4, 1.6, 0.06), CFrame.lookAt(pole.Position + toRoad * 0.45 + Vector3.new(0, -5, 0), pole.Position + toRoad * 2 + Vector3.new(0, -5, 0)), Color3.fromRGB(235, 235, 230)))
	plate.Parent = root

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 50
	gui.MaxDistance = 120
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

-- One streetlight at `base` (the kerbside point on the ground), its head
-- reaching out over the road in direction `toRoad`.
local function streetlight(root: Instance, base: Vector3, toRoad: Vector3, lit: boolean)
	BuildPacer.breathe()
	-- SmoothPlastic, not Metal: confirmed live that Metal's tight specular
	-- response under a bright light was what threw sharp "sparkle" glints.
	local pole = part("StreetlightPole", Vector3.new(0.8, 16, 0.8), CFrame.new(base + Vector3.new(0, 8, 0)), Color3.fromRGB(20, 20, 22), Enum.Material.SmoothPlastic)
	pole.Parent = root

	local headPos = base + toRoad * 1.2 + Vector3.new(0, 15.8, 0)
	local head = part("StreetlightHead", Vector3.new(1, 0.6, 2.5), CFrame.lookAt(headPos, headPos + toRoad), Color3.fromRGB(20, 20, 22), Enum.Material.SmoothPlastic)
	head.Parent = root
	local lamp = detail(part("StreetlightLamp", Vector3.new(0.7, 0.1, 1.6), head.CFrame * CFrame.new(0, -0.33, 0), Color3.fromRGB(255, 190, 120), Enum.Material.Neon))
	lamp.Parent = root

	-- A downward SpotLight throws a sodium-orange pool onto the road and
	-- sidewalk below without lighting up the pole/head themselves (a
	-- PointLight made them glint). It has to reach: the lamp sits ~17 studs
	-- up, and at the old 22-stud range the pool barely touched the ground --
	-- the lamps read as glowing LEDs that lit nothing (user feedback). No
	-- shadows, so hundreds of them stay affordable.
	if lit then
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Color = Color3.fromRGB(255, 172, 92)
		light.Brightness = 3.2
		light.Range = 36
		light.Angle = 125
		light.Shadows = false
		light.Parent = head
	end

	if math.random() < 0.3 then
		addPoleSign(root, pole, toRoad)
	end
end

local function buildStreetlights(root: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Streetlights"
	folder.Parent = root

	for a, avenue in CityConfig.AVENUES do
		for side = -1, 1, 2 do
			local x = avenue.x + side * (AVENUE_HALF + 1.5)
			-- Starting clear of the corners, where the signal poles stand.
			for _, run in avenueSidewalkRuns(a, side) do
				local z = run[1] - 26
				while z > run[2] + 20 do
					-- Not across or just past a taxi rank's driveway, where cabs
					-- pull in and out.
					if not nearRank(avenue.x, side, z) then
						streetlight(folder, Vector3.new(x, 1.2, z), Vector3.new(-side, 0, 0), true)
					end
					z -= 44
				end
			end
		end
	end

	-- The cross streets get them a little further apart, staggered from one
	-- side of the street to the other.
	for _, street in CityConfig.CROSS_STREETS do
		for side = -1, 1, 2 do
			local z = street.z + side * (CROSS_HALF + 1.3)
			for a = 1, #CityConfig.AVENUES - 1 do
				local x = CityConfig.AVENUES[a].x + AVENUE_EDGE + (if side == 1 then 14 else 43)
				while x < CityConfig.AVENUES[a + 1].x - AVENUE_EDGE - 8 do
					streetlight(folder, Vector3.new(x, 1.2, z), Vector3.new(0, 0, -side), true)
					x += 58
				end
			end
		end
	end
end

-- ===== Kerbside clutter =====

-- Bus shelters, on the avenue sidewalks in front of ordinary buildings, and
-- not straight ahead of a taxi rank's exit.
local BUS_STOPS = {
	{ x = 0, z = -125, side = -1 },
	{ x = 0, slot = 12, side = 1 },
	{ x = 0, slot = 14, side = -1 },
	{ x = 0, slot = 21, side = -1 },
	{ x = 0, slot = 25, side = 1 },
	{ x = 300, slot = 5, side = -1 },
	{ x = 300, slot = 16, side = 1 },
	{ x = -300, slot = 11, side = 1 },
	{ x = -300, slot = 25, side = -1 },
}

local function buildBusStop(root: Instance, avenueX: number, z: number, side: number)
	-- Toward the building side of the sidewalk -- streetlights own the kerb.
	local x = avenueX + side * (AVENUE_HALF + CityConfig.SIDEWALK_WIDTH - 2.5)
	local facing = if side == -1 then CFrame.Angles(0, math.pi / 2, 0) else CFrame.Angles(0, -math.pi / 2, 0)

	local glass = Color3.fromRGB(60, 65, 75)
	local backPanel = part("BusShelterBack", Vector3.new(0.15, 7, 8), CFrame.new(x, 4.7, z) * facing, glass, Enum.Material.SmoothPlastic)
	backPanel.Transparency = 0.25
	backPanel.Parent = root
	part("BusShelterRoof", Vector3.new(3.5, 0.2, 8.4), CFrame.new(x - side * 1.7, 8.2, z) * facing, Color3.fromRGB(35, 35, 40), Enum.Material.SmoothPlastic).Parent = root
	for _, endZ in { -3.5, 3.5 } do
		local sidePanel = part("BusShelterSide", Vector3.new(3.4, 6.6, 0.12), CFrame.new(x - side * 1.7, 4.6, z + endZ) * facing, glass, Enum.Material.SmoothPlastic)
		sidePanel.Transparency = 0.35
		sidePanel.Parent = root
	end
	part("BusShelterBench", Vector3.new(3, 1.1, 1.4), CFrame.new(x - side * 1.6, 2.6, z) * facing, Color3.fromRGB(40, 38, 36), Enum.Material.WoodPlanks).Parent = root
	part("BusStopPole", Vector3.new(0.35, 7.5, 0.35), CFrame.new(x - side * 3.7, 4.95, z), Color3.fromRGB(40, 90, 150), Enum.Material.SmoothPlastic).Parent = root

	local sign = detail(part("BusStopSign", Vector3.new(0.1, 1.6, 1.4), CFrame.new(x - side * 3.7, 8.2, z) * facing, Color3.fromRGB(40, 90, 150), Enum.Material.SmoothPlastic))
	sign.Parent = root
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 60
	gui.MaxDistance = 200
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

-- A fire hydrant, right at the kerb.
local function buildHydrant(root: Instance, x: number, z: number)
	part("HydrantBase", Vector3.new(0.9, 1.4, 0.9), CFrame.new(x, 1.9, z), Color3.fromRGB(150, 35, 35), Enum.Material.SmoothPlastic).Parent = root
	detail(part("HydrantCap", Vector3.new(0.5, 0.35, 0.5), CFrame.new(x, 2.75, z), Color3.fromRGB(170, 45, 45), Enum.Material.SmoothPlastic)).Parent = root
	detail(part("HydrantNozzles", Vector3.new(1.35, 0.35, 0.35), CFrame.new(x, 2.1, z), Color3.fromRGB(150, 35, 35), Enum.Material.SmoothPlastic)).Parent = root
end

-- A trash can toward the building line, where pedestrians walk past.
local function buildTrashCan(root: Instance, x: number, z: number)
	part("TrashCan", Vector3.new(1.3, 2.2, 1.3), CFrame.new(x, 2.3, z), Color3.fromRGB(45, 48, 45), Enum.Material.DiamondPlate).Parent = root
	detail(part("TrashCanLid", Vector3.new(1.4, 0.15, 1.4), CFrame.new(x, 3.48, z), Color3.fromRGB(35, 38, 35), Enum.Material.Metal)).Parent = root
end

-- A small steam vent in the road -- the Taxi Driver beat the opening grate
-- establishes, echoed round the city instead of only appearing once.
local function buildStreetVent(root: Instance, x: number, z: number)
	local grate = detail(part("StreetVent", Vector3.new(3, 0.15, 2.5), CFrame.new(x, 1.05, z), Color3.fromRGB(15, 15, 16), Enum.Material.DiamondPlate))
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
	emitter.Rate = 6
	emitter.Speed = NumberRange.new(0.8, 1.6)
	emitter.SpreadAngle = Vector2.new(12, 12)
	emitter.VelocityInheritance = 0
	emitter.Acceleration = Vector3.new(0, 1.6, 0)
	emitter.Parent = grate
end

local STREET_VENTS = {
	Vector3.new(0, 0, -96),
	Vector3.new(0, 0, -218),
	Vector3.new(0, 0, -460),
	Vector3.new(0, 0, -700),
	Vector3.new(300, 0, -150),
	Vector3.new(300, 0, -620),
	Vector3.new(-300, 0, -300),
	Vector3.new(-300, 0, -840),
	Vector3.new(150, 0, CityConfig.blockZ(10)),
	Vector3.new(-150, 0, CityConfig.blockZ(20)),
}

local function buildStreetProps(root: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "StreetProps"
	folder.Parent = root

	for a, avenue in CityConfig.AVENUES do
		for side = -1, 1, 2 do
			local kerbX = avenue.x + side * (AVENUE_HALF + 0.6)
			local innerX = avenue.x + side * (AVENUE_HALF + CityConfig.SIDEWALK_WIDTH - 1.8)
			for _, run in avenueSidewalkRuns(a, side) do
				local z = run[1] - 14
				local k = 0
				while z > run[2] + 12 do
					BuildPacer.breathe()
					k += 1
					if not lotFrontage(avenue.x, side, z) and not nearRank(avenue.x, side, z) then
						if k % 2 == 0 then
							buildHydrant(folder, kerbX, z)
						else
							buildTrashCan(folder, innerX, z + 4)
						end
					end
					z -= 34
				end
			end
		end
	end

	for _, stop in BUS_STOPS do
		buildBusStop(folder, stop.x, stop.z or CityConfig.blockZ(stop.slot), stop.side)
	end
	for _, position in STREET_VENTS do
		buildStreetVent(folder, position.X, position.Z)
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
-- reusable modules, which came with their own default Lighting rig still in
-- place (a full-strength Bloom, a second Atmosphere, SunRays) -- confirmed
-- live as the real source of starburst flares round bright lights. Cleared
-- before building our own set below.
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
	-- Raised (2026-10-04): darker than this the road itself was invisible
	-- from the driver's seat and a character on foot was a black silhouette.
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

	-- Small and high-threshold: only genuinely bright, close sources
	-- (headlights, neon, traffic signals) bloom.
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
	buildGround(root)
	buildRoads(root)
	buildSidewalks(root)
	buildLaneMarkings(root)
	DistrictBuilder.build(root)
	IntersectionBuilder.build(root)
	buildStreetlights(root)
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
