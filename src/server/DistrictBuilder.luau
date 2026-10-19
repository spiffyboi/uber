-- Everything built on the city blocks: the named places on the avenues (see
-- CityConfig.LOTS -- taxi ranks, rows of delis and bodegas, nightclubs with a
-- queue outside, old cinemas, apartment towers, parks), ordinary buildings
-- along every other stretch of every street, taller towers filling the
-- middle of each block, and a ring of distant towers round the edge of the
-- grid so the city doesn't just stop.
--
-- Street-relative coordinates: everything placed on a street is written as
-- if that street ran along Z through X = 0 (the way the original single
-- strip did), and `FRAME` moves it to the street it actually belongs on --
-- a sideways shift for the other avenues, a quarter turn for cross streets.
-- A lot on `side` s has its street wall at X = s * EDGE. `out` measures
-- from that wall toward the road (over the sidewalk); `depth` measures from
-- it away from the road, into the block.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))
local Facade = require(script.Parent.Facade)
local CarBuilder = require(script.Parent.CarBuilder)
local BuildPacer = require(script.Parent.BuildPacer)

local DistrictBuilder = {}

local AVENUE_EDGE = CityConfig.BUILDING_EDGE
local CROSS_EDGE = CityConfig.CROSS_BUILDING_EDGE
local SIDEWALK_TOP = 1.2
local STEAM_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

-- Depth of an ordinary street-wall building.
local ROW_DEPTH = 20

-- The street frame currently being built on, and where its building line
-- sits (avenues have a wider sidewalk than cross streets).
local FRAME = CFrame.identity
local EDGE = AVENUE_EDGE

local function avenueFrame(x: number): CFrame
	return CFrame.new(x, 0, 0)
end

-- A quarter turn: street-relative Z runs along world -X, and street-relative
-- X (the side) along world Z. So a street-relative z of -worldX lands at
-- worldX, and side 1 is the +Z side of the street.
local function crossFrame(z: number): CFrame
	return CFrame.new(0, 0, z) * CFrame.Angles(0, -math.pi / 2, 0)
end

-- ===== Small helpers =====

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = FRAME * cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Small set dressing: never collides or casts a shadow, which keeps the
-- physics and lighting work for hundreds of fruit, bulbs and rails down.
local function detail(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function cylinder(parent: Instance, name: string, diameter: number, height: number, center: Vector3, color: Color3, material: Enum.Material?): Part
	local p = part(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, name: string, diameter: number, center: Vector3, color: Color3, material: Enum.Material?): Part
	local p = part(parent, name, Vector3.new(diameter, diameter, diameter), CFrame.new(center), color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

-- Street-relative point for a lot on `side`: `out` studs from the street
-- wall toward the road (negative = into the lot), at height `y`, at `z`.
local function at(side: number, out: number, y: number, z: number): Vector3
	return Vector3.new(side * (EDGE - out), y, z)
end

local function pick<T>(list: { T }): T
	return list[math.random(1, #list)]
end

-- ===== What's already standing where =====
-- World-space XZ rectangles taken up by lots and buildings, so later passes
-- (cross-street rows, block-middle towers) fill round them instead of
-- through them.

type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }
local taken: { Rect } = {}

local function rectFromCorners(points: { Vector3 }): Rect
	local rect = { minX = math.huge, maxX = -math.huge, minZ = math.huge, maxZ = -math.huge }
	for _, p in points do
		rect.minX = math.min(rect.minX, p.X)
		rect.maxX = math.max(rect.maxX, p.X)
		rect.minZ = math.min(rect.minZ, p.Z)
		rect.maxZ = math.max(rect.maxZ, p.Z)
	end
	return rect
end

-- A street-relative rectangle, in world space under the current FRAME.
local function streetRect(x1: number, x2: number, z1: number, z2: number): Rect
	return rectFromCorners({
		FRAME * Vector3.new(x1, 0, z1),
		FRAME * Vector3.new(x1, 0, z2),
		FRAME * Vector3.new(x2, 0, z1),
		FRAME * Vector3.new(x2, 0, z2),
	})
end

local function isFree(rect: Rect): boolean
	for _, other in taken do
		if rect.minX < other.maxX - 0.5 and rect.maxX > other.minX + 0.5 and rect.minZ < other.maxZ - 0.5 and rect.maxZ > other.minZ + 0.5 then
			return false
		end
	end
	return true
end

local function take(rect: Rect)
	table.insert(taken, rect)
end

-- ===== People =====

local SKIN_TONES = {
	Color3.fromRGB(185, 150, 122),
	Color3.fromRGB(140, 100, 75),
	Color3.fromRGB(225, 195, 165),
	Color3.fromRGB(90, 65, 50),
	Color3.fromRGB(205, 165, 130),
}

local NIGHT_OUT_COLORS = {
	Color3.fromRGB(150, 20, 40),
	Color3.fromRGB(25, 120, 130),
	Color3.fromRGB(230, 225, 215),
	Color3.fromRGB(20, 20, 24),
	Color3.fromRGB(110, 40, 150),
	Color3.fromRGB(200, 160, 50),
	Color3.fromRGB(40, 60, 140),
}

local function describePerson(shirt: Color3, pants: Color3, widthScale: number?, heightScale: number?): HumanoidDescription
	local d = Instance.new("HumanoidDescription")
	d.HeadColor = pick(SKIN_TONES)
	d.TorsoColor = shirt
	d.LeftArmColor = shirt
	d.RightArmColor = shirt
	d.LeftLegColor = pants
	d.RightLegColor = pants
	d.WidthScale = widthScale or 1
	d.HeightScale = heightScale or 1
	return d
end

-- A standing NPC, feet on the ground at `groundCFrame` (street-relative
-- position on the ground, rotation = which way they face). Built off the
-- main thread since creating a rig from a description yields, so the frame
-- is captured now rather than read when it finishes.
local function person(parent: Instance, name: string, groundCFrame: CFrame, description: HumanoidDescription)
	local frame = FRAME
	task.spawn(function()
		local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		model.Name = name
		local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		-- Nobody here ever moves: no humanoid physics state to keep updating.
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
		local animate = model:FindFirstChild("Animate")
		if animate then
			animate:Destroy()
		end
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
		local rootHeight = humanoid.HipHeight + root.Size.Y / 2
		model:PivotTo(frame * (groundCFrame + Vector3.new(0, rootHeight, 0)))
		-- Every part pinned where it stands, and the rigging that only a
		-- moving body needs (joints, rig attachments, scaling records)
		-- thrown away: a fresh rig is ~220 objects, most of them that, and
		-- with dozens of these standing about it added up.
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanTouch = false
			elseif
				descendant:IsA("JointInstance")
				or descendant:IsA("Attachment")
				or descendant:IsA("ValueBase")
				or descendant:IsA("Constraint")
				or descendant:IsA("NoCollisionConstraint")
				or descendant:IsA("BaseWrap")
				or descendant:IsA("WrapTarget")
			then
				-- (Constraint and the wrap objects too: newer rigs come with
				-- a ball-socket and an animation constraint per joint, and a
				-- layered-clothing wrap target per body part -- measured
				-- live, ~7,000 objects across the city's queues.)
				descendant:Destroy()
			end
		end
		model.Parent = parent
	end)
end

-- ===== Rooftop / facade extras =====

-- A classic wooden rooftop water tank on legs, sitting on `roofCenter`.
function DistrictBuilder.addWaterTower(parent: Instance, roofCenter: Vector3)
	local base = roofCenter + Vector3.new(math.random(-4, 4), 0, math.random(-6, 6))
	local legColor = Color3.fromRGB(30, 30, 32)
	for _, corner in { Vector3.new(1.8, 0, 1.8), Vector3.new(-1.8, 0, 1.8), Vector3.new(1.8, 0, -1.8), Vector3.new(-1.8, 0, -1.8) } do
		detail(part(parent, "WaterTowerLeg", Vector3.new(0.4, 4, 0.4), CFrame.new(base + corner + Vector3.new(0, 2, 0)), legColor))
	end
	local tankBottom = base.Y + 4
	cylinder(parent, "WaterTowerTank", 5.5, 5.5, Vector3.new(base.X, tankBottom + 2.75, base.Z), Color3.fromRGB(96, 72, 52), Enum.Material.WoodPlanks)
	local roofColor = Color3.fromRGB(42, 42, 44)
	for i, diameter in { 5.9, 3.6 } do
		detail(cylinder(parent, "WaterTowerRoof", diameter, 0.7, Vector3.new(base.X, tankBottom + 5.5 + (i - 0.5) * 0.7, base.Z), roofColor))
	end
end

-- Iron fire escape zig-zagging up the street face of a building on `side`,
-- centred near street-relative `z`, `height` tall.
function DistrictBuilder.addFireEscape(parent: Instance, z: number, height: number, side: number)
	local color = Color3.fromRGB(28, 28, 30)
	z += math.random(-5, 5)
	local top = height - 5
	local flip = 1
	for y = 11, top, 6 do
		detail(part(parent, "FireEscape", Vector3.new(2.2, 0.15, 8), CFrame.new(at(side, 1.1, y, z)), color))
		detail(part(parent, "FireEscape", Vector3.new(0.12, 0.12, 8), CFrame.new(at(side, 2.15, y + 2.4, z)), color))
		if y + 6 <= top then
			local from = at(side, 1.4, y, z + 3 * flip)
			local to = at(side, 1.4, y + 6, z - 3 * flip)
			detail(part(parent, "FireEscape", Vector3.new(0.6, 0.12, (to - from).Magnitude), CFrame.lookAt((from + to) / 2, to), color))
			flip = -flip
		end
	end
end

-- ===== Ordinary buildings =====

local BUILDING_COLORS = {
	Color3.fromRGB(40, 36, 34),
	Color3.fromRGB(48, 44, 46),
	Color3.fromRGB(34, 34, 40),
	Color3.fromRGB(52, 46, 40),
	Color3.fromRGB(62, 44, 38),
}

-- Ground-floor businesses on ordinary buildings.
local SHOP_TYPES = {
	{ name = "MARROW DINER", awning = Color3.fromRGB(165, 35, 35), display = Color3.fromRGB(235, 150, 70) },
	{ name = "MARROW LIQUOR", awning = Color3.fromRGB(120, 35, 115), display = Color3.fromRGB(210, 70, 200) },
	{ name = "CHECK CASHING", awning = Color3.fromRGB(140, 110, 20), display = Color3.fromRGB(240, 200, 60) },
	{ name = "LAUNDRO", awning = Color3.fromRGB(25, 100, 70), display = Color3.fromRGB(90, 210, 120) },
	{ name = "BODEGA", awning = Color3.fromRGB(35, 80, 125), display = Color3.fromRGB(90, 180, 235) },
	{ name = "PAWN & TRADE", awning = Color3.fromRGB(95, 90, 40), display = Color3.fromRGB(215, 205, 110) },
	{ name = CityConfig.APP_NAME:upper() .. " KIOSK", awning = Color3.fromRGB(15, 110, 120), display = Color3.fromRGB(50, 220, 235) },
	{ name = "OPEN 24 HRS", awning = Color3.fromRGB(150, 40, 60), display = Color3.fromRGB(235, 60, 90) },
	{ name = "HARDWARE", awning = Color3.fromRGB(70, 75, 80), display = Color3.fromRGB(230, 210, 150) },
	{ name = "BARBER", awning = Color3.fromRGB(30, 50, 120), display = Color3.fromRGB(240, 90, 90) },
	{ name = "CHINESE TAKE OUT", awning = Color3.fromRGB(170, 30, 30), display = Color3.fromRGB(250, 200, 80) },
	{ name = "BAR & GRILL", awning = Color3.fromRGB(60, 35, 25), display = Color3.fromRGB(240, 120, 60) },
}

-- A ground-floor storefront band painted over the bottom of the facade: an
-- awning with the shop's name, a door, and a lit display window.
local function addStorefront(gui: SurfaceGui, shop, buildingHeight: number)
	local bandHeight = 9
	local fraction = math.min(1, bandHeight / buildingHeight)

	local band = Instance.new("Frame")
	band.Name = "Band"
	band.BackgroundColor3 = Color3.fromRGB(18, 16, 15)
	band.BorderSizePixel = 0
	band.Size = UDim2.new(1, 0, fraction, 0)
	band.Position = UDim2.new(0, 0, 1 - fraction, 0)
	band.ZIndex = 2
	band.Parent = gui

	local awning = Instance.new("TextLabel")
	awning.Name = "Awning"
	awning.BackgroundColor3 = shop.awning
	awning.BorderSizePixel = 0
	awning.Size = UDim2.new(1, 0, 0.24, 0)
	awning.Font = Enum.Font.Oswald
	awning.Text = shop.name
	awning.TextColor3 = Color3.fromRGB(245, 240, 225)
	awning.TextScaled = true
	awning.Parent = band

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

-- One ordinary street-wall building on `side` of the current street,
-- `width` along it, its street wall centred on `z`. Skipped (returns false)
-- if anything's already standing there.
local function buildRowBuilding(parent: Instance, side: number, z: number, width: number, height: number?): boolean
	local x1, x2 = side * EDGE, side * (EDGE + ROW_DEPTH)
	local rect = streetRect(x1, x2, z - width / 2, z + width / 2)
	if not isFree(rect) then
		return false
	end
	take(rect)
	BuildPacer.breathe()

	local h = height or math.random(24, 58)
	local building = part(parent, "Building", Vector3.new(ROW_DEPTH, h, width), CFrame.new(side * (EDGE + ROW_DEPTH / 2), h / 2, z), pick(BUILDING_COLORS), Enum.Material.Concrete)

	local gui = Facade.gui(building, Facade.roadFace(side))
	Facade.windows(gui, math.clamp(math.floor(width / 6), 3, 6), math.max(3, math.floor(h / 8)), 0.18)
	addStorefront(gui, pick(SHOP_TYPES), h)
	if math.random() < 0.4 then
		local sign = pick(SHOP_TYPES)
		Facade.sign(gui, sign.name, sign.display, UDim2.new(0.15, 0, 0.35, 0), UDim2.new(0.7, 0, 0.1, 0))
	end

	if h > 30 and math.random() < 0.3 then
		DistrictBuilder.addFireEscape(parent, z, h, side)
	end
	if math.random() < 0.3 then
		DistrictBuilder.addWaterTower(parent, Vector3.new(side * (EDGE + ROW_DEPTH / 2), h, z))
	end
	return true
end

-- Fills street-relative [zFrom, zTo] (zFrom > zTo) on `side` with ordinary
-- buildings of mixed widths, stepping past anything already standing.
local function fillRow(parent: Instance, side: number, zFrom: number, zTo: number)
	local z = zFrom
	while z - 12 >= zTo do
		local width = math.min(math.random(24, 36), z - zTo)
		if width < 12 then
			break
		end
		if buildRowBuilding(parent, side, z - width / 2, width - 1) then
			z -= width
		else
			z -= 4
		end
	end
end

-- ===== Taxi ranks =====

local function buildTaxiRank(parent: Instance, lot, isPlayersRank: boolean)
	local s = lot.side
	local near, far = CityConfig.lotZRange(lot)
	local z = (near + far) / 2
	local innerX = CityConfig.ROAD_WIDTH / 2
	local outerX = EDGE + 20

	-- At road height (top face Y=1, same as the road), spanning the
	-- sidewalk's footprint as a driveway -- the sidewalk is left out here
	-- for exactly this (see OpeningSetBuilder).
	part(parent, "TaxiRank", Vector3.new(outerX - innerX, 1, near - far), CFrame.new(s * (innerX + outerX) / 2, 0.5, z), Color3.fromRGB(38, 36, 34), Enum.Material.Asphalt)
	-- A wall across the back, so the pad doesn't open onto the middle of the
	-- block.
	part(parent, "RankBackWall", Vector3.new(1, 10, near - far), CFrame.new(s * (outerX + 0.5), 5, z), Color3.fromRGB(58, 50, 46), Enum.Material.Brick)

	-- Bay lines running along Z, either side of each cab-width bay; the
	-- first bay is where the player's own cab parks (CAR_SPAWN_CFRAME).
	for k = 0, 3 do
		detail(part(parent, "RankBayLine", Vector3.new(0.15, 0.05, 18), CFrame.new(s * (innerX + 4 + k * 8), 1.03, near - 10), Color3.fromRGB(225, 195, 60)))
	end
	local painted = detail(part(parent, "RankPaint", Vector3.new(6, 0.05, 2.2), CFrame.new(s * (innerX + 4), 1.03, near - 21), Color3.fromRGB(38, 36, 34)))
	painted.Transparency = 1
	Facade.boardText(painted, Enum.NormalId.Top, "TAXI", Color3.fromRGB(225, 195, 60))

	-- Sign on a pole at the back corner, clear of the driveway.
	local signX = s * (outerX - 1.5)
	local signZ = near - 1.5
	part(parent, "TaxiRankSignPole", Vector3.new(0.3, 6, 0.3), CFrame.new(signX, 4, signZ), Color3.fromRGB(40, 40, 44))
	local sign = part(parent, "TaxiRankSign", Vector3.new(0.15, 2, 3), CFrame.new(signX - s * 0.25, 6, signZ) * CFrame.Angles(0, s * math.rad(90), 0), Color3.fromRGB(225, 195, 60))
	Facade.boardText(sign, Enum.NormalId.Front, "TAXI STAND", Color3.fromRGB(20, 20, 24), nil, Enum.Font.SourceSansBold)

	-- A little dispatch booth at the far back corner.
	local boothCenter = Vector3.new(s * (outerX - 3), 1 + 2.4, far + 3.5)
	local booth = part(parent, "DispatchBooth", Vector3.new(4.5, 4.8, 4.5), CFrame.new(boothCenter), Color3.fromRGB(215, 190, 70))
	part(parent, "DispatchBoothRoof", Vector3.new(5.2, 0.3, 5.2), CFrame.new(boothCenter + Vector3.new(0, 2.55, 0)), Color3.fromRGB(30, 30, 32))
	local window = detail(part(parent, "DispatchBoothWindow", Vector3.new(0.1, 1.8, 3), CFrame.new(boothCenter + Vector3.new(-s * 2.27, 0.6, 0)), Color3.fromRGB(240, 210, 140), Enum.Material.Neon))
	window.Transparency = 0.2
	Facade.boardText(booth, Facade.roadFace(s), CityConfig.TAXI_COMPANY_NAME:upper(), Color3.fromRGB(25, 25, 28))

	-- Other drivers' cabs waiting their turn. Not in the player's own rank,
	-- which needs its bays and exit clear. Facing the way the near lanes'
	-- traffic flows (outbound -Z on side 1, inbound +Z on side -1).
	if not isPlayersRank then
		local yaw = if s == 1 then 0 else math.pi
		for _, bay in { 0, 2 } do
			local cab = CarBuilder.buildParkedTaxi(Vector3.new(s * (innerX + 8 + bay * 8), 1, near - 9), yaw)
			cab:PivotTo(FRAME * cab:GetPivot())
			cab.Parent = parent
		end
	end
end

-- ===== Shops: delis, bodegas and their neighbours =====

local SHOPS = {
	{ name = "MARROW DELI", sub = "HEROES  ·  COLD CUTS  ·  COFFEE", awning = Color3.fromRGB(28, 95, 50), window = "OPEN", produce = true },
	{ name = "CORNER BODEGA", sub = "GROCERY  ·  LOTTO  ·  ATM", awning = Color3.fromRGB(165, 40, 35), window = "COLD BEER", produce = true },
	{ name = "SLICE CITY", sub = "PIZZA BY THE SLICE", awning = Color3.fromRGB(200, 115, 30), window = "OPEN LATE" },
	{ name = "SUDS LAUNDROMAT", sub = "WASH  ·  DRY  ·  FOLD", awning = Color3.fromRGB(40, 90, 150), window = "OPEN 24 HRS" },
	{ name = "24 HR DELI & GROCERY", sub = "HOT FOOD  ·  BEER  ·  COLD DRINKS", awning = Color3.fromRGB(30, 110, 60), window = "OPEN", produce = true },
	{ name = "PAWN & LOAN", sub = "WE BUY GOLD", awning = Color3.fromRGB(110, 100, 40), closed = true },
	{ name = "LUCKY STAR BODEGA", sub = "SANDWICHES  ·  LOTTO  ·  SNACKS", awning = Color3.fromRGB(150, 30, 90), window = "ATM", produce = true },
	{ name = "NOODLE HOUSE", sub = "TAKE OUT  ·  DELIVERY", awning = Color3.fromRGB(180, 50, 40), window = "OPEN" },
	{ name = "MARROW LIQUORS", sub = "WINE  ·  SPIRITS", awning = Color3.fromRGB(90, 30, 110), window = "OPEN" },
	{ name = "ALL-NITE PHARMACY", sub = "OPEN 24 HOURS", awning = Color3.fromRGB(30, 120, 120), window = "RX" },
	{ name = "SHOE REPAIR", sub = "KEYS CUT  ·  WHILE U WAIT", awning = Color3.fromRGB(80, 60, 45), closed = true },
	{ name = "AVENUE DELI", sub = "BREAKFAST ALL NIGHT", awning = Color3.fromRGB(25, 70, 120), window = "OPEN", produce = true },
	{ name = "CORNER COFFEE SHOP", sub = "EGGS  ·  BURGERS  ·  PIE", awning = Color3.fromRGB(150, 110, 40), window = "OPEN" },
	{ name = "GOLDEN BAGELS", sub = "FRESH ALL NIGHT", awning = Color3.fromRGB(180, 140, 40), window = "HOT", produce = true },
	{ name = "RECORD EXCHANGE", sub = "BUY  ·  SELL  ·  TRADE", awning = Color3.fromRGB(40, 40, 45), closed = true },
	{ name = "NIGHT OWL BODEGA", sub = "COFFEE  ·  CIGS  ·  LOTTO", awning = Color3.fromRGB(110, 30, 40), window = "OPEN", produce = true },
}
local shopCursor = 0

local BRICK_COLORS = {
	Color3.fromRGB(96, 48, 40),
	Color3.fromRGB(78, 58, 48),
	Color3.fromRGB(110, 70, 52),
	Color3.fromRGB(70, 66, 64),
}

local FRUIT_COLORS = {
	Color3.fromRGB(200, 40, 35),
	Color3.fromRGB(235, 140, 30),
	Color3.fromRGB(235, 210, 60),
	Color3.fromRGB(90, 160, 50),
}

-- A tiered crate stand of fruit under the awning, deli/bodega style. The
-- fruit on each tier is two long rows of balls rather than one part per
-- fruit, which reads the same from the street at a tenth of the parts.
local function buildProduceStand(parent: Instance, s: number, z: number, width: number)
	local crateColor = Color3.fromRGB(120, 85, 50)
	for tier = 0, 1 do
		local out = 1.6 - tier * 0.7
		local height = 1.6 + tier * 0.7
		local crate = part(parent, "ProduceCrate", Vector3.new(1.4, height, width), CFrame.new(at(s, out, SIDEWALK_TOP + height / 2, z)), crateColor, Enum.Material.WoodPlanks)
		crate.CanCollide = tier == 0
		local segments = 3
		for row = 0, 1 do
			for k = 0, segments - 1 do
				local segmentWidth = width / segments
				-- A cylinder's length runs along its own X: turned to lie
				-- along the street.
				local fruit = detail(part(parent, "Fruit", Vector3.new(segmentWidth - 0.1, 0.45, 0.45), CFrame.new(at(s, out - 0.35 + row * 0.6, SIDEWALK_TOP + height + 0.2, z - width / 2 + segmentWidth * (k + 0.5))) * CFrame.Angles(0, math.pi / 2, 0), FRUIT_COLORS[(k + tier + row) % #FRUIT_COLORS + 1], Enum.Material.Pebble))
				fruit.Shape = Enum.PartType.Cylinder
			end
		end
	end
end

-- One narrow shopfront: a few storeys of brick with a real awning, a lit
-- window and door at street level, and a sign board.
local function buildShopfront(parent: Instance, s: number, zCenter: number, width: number, shop)
	local roadFace = Facade.roadFace(s)
	local height = math.random(15, 26)
	local depth = 18
	local building = part(parent, "Shop_" .. shop.name, Vector3.new(depth, height, width - 0.4), CFrame.new(at(s, -depth / 2, height / 2, zCenter)), pick(BRICK_COLORS), Enum.Material.Brick)

	local gui = Facade.gui(building, roadFace)
	Facade.windows(gui, 2, math.max(1, math.floor((height - 11) / 5)), 0.25, 0, 1 - 11.5 / height)

	local storeHeight = 7
	if shop.closed then
		-- Shutter pulled down for the night.
		detail(part(parent, "Shutter", Vector3.new(0.2, storeHeight, width - 1), CFrame.new(at(s, 0.1, SIDEWALK_TOP + storeHeight / 2, zCenter)), Color3.fromRGB(95, 95, 100), Enum.Material.DiamondPlate))
	else
		local windowWidth = width * 0.55
		local window = detail(part(parent, "ShopWindow", Vector3.new(0.2, 4.6, windowWidth), CFrame.new(at(s, 0.1, SIDEWALK_TOP + 0.6 + 2.3, zCenter + width * 0.15)), Color3.fromRGB(175, 150, 105), Enum.Material.Neon))
		window.Transparency = 0.25
		if shop.window then
			local label = Facade.boardText(window, roadFace, shop.window, Color3.fromRGB(255, 60, 70))
			label.Size = UDim2.fromScale(0.5, 0.3)
			label.Position = UDim2.fromScale(0.45, 0.08)
		end
		detail(part(parent, "ShopDoor", Vector3.new(0.2, 6.5, 2.2), CFrame.new(at(s, 0.1, SIDEWALK_TOP + 3.25, zCenter - width * 0.32)), Color3.fromRGB(25, 25, 28)))
	end

	-- Sloped fabric awning, outer edge lower, with the shop's tagline on the
	-- hanging valance and its name on a board above.
	local tilt = math.rad(22)
	local awningY = SIDEWALK_TOP + storeHeight + 0.9
	detail(part(parent, "Awning", Vector3.new(3.2, 0.2, width - 0.6), CFrame.new(at(s, 1.6, awningY, zCenter)) * CFrame.Angles(0, 0, s * tilt), shop.awning, Enum.Material.Fabric))
	local valanceOut = 1.6 + 1.6 * math.cos(tilt)
	local valanceY = awningY - 1.6 * math.sin(tilt) - 0.55
	local valance = detail(part(parent, "Valance", Vector3.new(0.15, 1.1, width - 0.6), CFrame.new(at(s, valanceOut, valanceY, zCenter)), shop.awning, Enum.Material.Fabric))
	Facade.boardText(valance, roadFace, shop.sub, Color3.fromRGB(245, 240, 225))

	local board = detail(part(parent, "ShopSign", Vector3.new(0.25, 2.2, width - 1.2), CFrame.new(at(s, 0.15, awningY + 2.2, zCenter)), Color3.fromRGB(15, 15, 18)))
	Facade.boardText(board, roadFace, shop.name, Color3.fromRGB(250, 235, 190), Color3.fromRGB(15, 15, 18))

	if shop.produce then
		buildProduceStand(parent, s, zCenter + width * 0.15, math.min(width * 0.55, 4))
	end
end

local function buildShops(parent: Instance, lot)
	local near, far = CityConfig.lotZRange(lot)
	local total = (near - far) - 4
	local count = 3
	local width = total / count
	for k = 0, count - 1 do
		shopCursor = shopCursor % #SHOPS + 1
		buildShopfront(parent, lot.side, near - 2 - width * k - width / 2, width, SHOPS[shopCursor])
	end
end

-- ===== The gun store =====
-- Ironside Arms (chapter 7): one wide, low brick shopfront, display windows
-- behind iron bars, a steel grille over the door and a red neon GUNS in the
-- window. Its inside is built separately, under the street (see
-- GunStoreBuilder).

local function buildGunStore(parent: Instance, lot)
	local s = lot.side
	local roadFace = Facade.roadFace(s)
	local near, far = CityConfig.lotZRange(lot)
	local zCenter = (near + far) / 2
	local width = (near - far) - 4
	local depth, height = 18, 22

	local building = part(parent, "GunStore_" .. lot.name, Vector3.new(depth, height, width), CFrame.new(at(s, -depth / 2, height / 2, zCenter)), Color3.fromRGB(74, 50, 42), Enum.Material.Brick)
	local gui = Facade.gui(building, roadFace)
	Facade.windows(gui, 4, 2, 0.15, 0, 1 - 12 / height)

	local storeHeight = 7
	local iron = Color3.fromRGB(26, 26, 28)
	-- Two display windows, either side of the door, lit low and warm, with
	-- bars in front.
	for _, offset in { -width * 0.27, width * 0.22 } do
		local windowWidth = width * 0.34
		local window = detail(part(parent, "DisplayWindow", Vector3.new(0.2, 4.4, windowWidth), CFrame.new(at(s, 0.1, SIDEWALK_TOP + 0.8 + 2.2, zCenter + offset)), Color3.fromRGB(150, 110, 70), Enum.Material.Neon))
		window.Transparency = 0.35
		local bars = math.floor(windowWidth / 0.9)
		for b = 0, bars do
			detail(part(parent, "WindowBar", Vector3.new(0.15, 4.8, 0.15), CFrame.new(at(s, 0.45, SIDEWALK_TOP + 0.8 + 2.2, zCenter + offset - windowWidth / 2 + b * (windowWidth / bars))), iron, Enum.Material.Metal))
		end
		detail(part(parent, "WindowBarRail", Vector3.new(0.15, 0.15, windowWidth), CFrame.new(at(s, 0.45, SIDEWALK_TOP + 0.9, zCenter + offset)), iron, Enum.Material.Metal))
		detail(part(parent, "WindowBarRail", Vector3.new(0.15, 0.15, windowWidth), CFrame.new(at(s, 0.45, SIDEWALK_TOP + 5.1, zCenter + offset)), iron, Enum.Material.Metal))
	end
	-- "GUNS" in red neon in the left window.
	local neon = detail(part(parent, "GunsNeon", Vector3.new(0.1, 1.2, 3.6), CFrame.new(at(s, 0.25, SIDEWALK_TOP + 3.4, zCenter - width * 0.27)), Color3.fromRGB(10, 8, 8)))
	neon.Transparency = 1
	Facade.boardText(neon, roadFace, "GUNS", Color3.fromRGB(255, 50, 50), nil, Enum.Font.GothamBlack)

	-- The door, behind a steel grille.
	local doorZ = zCenter - width * 0.02
	detail(part(parent, "StoreDoor", Vector3.new(0.2, 6.5, 2.4), CFrame.new(at(s, 0.1, SIDEWALK_TOP + 3.25, doorZ)), Color3.fromRGB(40, 30, 24)))
	local grille = detail(part(parent, "DoorGrille", Vector3.new(0.12, 6.6, 2.6), CFrame.new(at(s, 0.3, SIDEWALK_TOP + 3.3, doorZ)), iron, Enum.Material.DiamondPlate))
	grille.Transparency = 0.45

	-- The sign: name on a long dark board, and what they sell under it.
	local signY = SIDEWALK_TOP + storeHeight + 1.6
	local board = detail(part(parent, "StoreSign", Vector3.new(0.3, 2.6, width - 2), CFrame.new(at(s, 0.2, signY, zCenter)), Color3.fromRGB(14, 14, 16)))
	Facade.boardText(board, roadFace, lot.name, Color3.fromRGB(235, 225, 200), Color3.fromRGB(14, 14, 16), Enum.Font.GothamBlack)
	local strip = detail(part(parent, "StoreSignStrip", Vector3.new(0.25, 0.9, width - 2), CFrame.new(at(s, 0.2, signY - 1.85, zCenter)), Color3.fromRGB(120, 20, 20)))
	Facade.boardText(strip, roadFace, "GUNS  ·  AMMO  ·  PAWN  ·  REPAIRS", Color3.fromRGB(245, 235, 220))
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 120, 90)
	glow.Brightness = 1.2
	glow.Range = 14
	glow.Parent = strip
end

-- ===== The funeral chapel =====
-- Larkin & Sons on Calloway (chapter 9): pale stone, low and plain, a pair
-- of tall arched windows glowing amber either side of double doors, a
-- carriage lamp at each side of the steps, and the name in quiet capitals.
-- Nothing on it says which faith; it's for whoever needs it.
local function buildChapel(parent: Instance, lot)
	local s = lot.side
	local roadFace = Facade.roadFace(s)
	local near, far = CityConfig.lotZRange(lot)
	local zCenter = (near + far) / 2
	local width = (near - far) - 4
	local depth, height = 18, 16
	local stone = Color3.fromRGB(150, 144, 132)
	local trim = Color3.fromRGB(110, 104, 96)

	part(parent, "Chapel_" .. lot.name, Vector3.new(depth, height, width), CFrame.new(at(s, -depth / 2, height / 2, zCenter)), stone, Enum.Material.Limestone)
	-- A low pitched front: a gable over the doors.
	detail(part(parent, "ChapelGable", Vector3.new(1, 3, width * 0.5), CFrame.new(at(s, 0.3, height + 1.5, zCenter)), trim, Enum.Material.Limestone))
	detail(part(parent, "ChapelCornice", Vector3.new(1.2, 0.6, width), CFrame.new(at(s, 0.4, height - 0.3, zCenter)), trim, Enum.Material.Limestone))

	-- Steps up to the doors.
	for i = 0, 2 do
		detail(part(parent, "ChapelStep", Vector3.new(2.4 - i * 0.8, 0.4, 7), CFrame.new(at(s, 1.2 - i * 0.4, SIDEWALK_TOP + 0.2 + i * 0.4, zCenter)), trim, Enum.Material.Limestone))
	end
	-- The doors: dark wood, a lit transom above them.
	local doorTop = SIDEWALK_TOP + 1.2 + 6.4
	for _, dz in { -1.3, 1.3 } do
		detail(part(parent, "ChapelDoor", Vector3.new(0.3, 6.4, 2.5), CFrame.new(at(s, 0.15, SIDEWALK_TOP + 1.2 + 3.2, zCenter + dz)), Color3.fromRGB(56, 36, 24), Enum.Material.Wood))
	end
	local transom = detail(part(parent, "ChapelTransom", Vector3.new(0.2, 1.2, 5.2), CFrame.new(at(s, 0.12, doorTop + 0.7, zCenter)), Color3.fromRGB(255, 196, 120), Enum.Material.Neon))
	transom.Transparency = 0.2
	-- A wreath on each door.
	for _, dz in { -1.3, 1.3 } do
		local wreath = detail(part(parent, "Wreath", Vector3.new(0.3, 1.4, 1.4), CFrame.new(at(s, 0.45, SIDEWALK_TOP + 1.2 + 4.2, zCenter + dz)), Color3.fromRGB(30, 60, 34), Enum.Material.Grass))
		wreath.Shape = Enum.PartType.Cylinder
	end

	-- Two tall windows, warm light behind coloured glass.
	for _, dz in { -width * 0.3, width * 0.3 } do
		local window = detail(part(parent, "ChapelWindow", Vector3.new(0.2, 8, 3.2), CFrame.new(at(s, 0.12, SIDEWALK_TOP + 6, zCenter + dz)), Color3.fromRGB(230, 160, 80), Enum.Material.Neon))
		window.Transparency = 0.35
		detail(part(parent, "WindowMullion", Vector3.new(0.3, 8.2, 0.2), CFrame.new(at(s, 0.25, SIDEWALK_TOP + 6, zCenter + dz)), trim, Enum.Material.Limestone))
		detail(part(parent, "WindowTransom", Vector3.new(0.3, 0.2, 3.4), CFrame.new(at(s, 0.25, SIDEWALK_TOP + 7.4, zCenter + dz)), trim, Enum.Material.Limestone))
	end

	-- Carriage lamps either side of the steps.
	for _, dz in { -4.6, 4.6 } do
		detail(part(parent, "LampBracket", Vector3.new(0.8, 0.2, 0.2), CFrame.new(at(s, 0.4, SIDEWALK_TOP + 6.2, zCenter + dz)), Color3.fromRGB(26, 26, 28), Enum.Material.Metal))
		local lamp = detail(part(parent, "CarriageLamp", Vector3.new(0.7, 1.1, 0.7), CFrame.new(at(s, 0.75, SIDEWALK_TOP + 5.6, zCenter + dz)), Color3.fromRGB(255, 214, 150), Enum.Material.Neon))
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 200, 140)
		light.Brightness = 1.1
		light.Range = 14
		light.Parent = lamp
	end

	-- The name over the doors.
	local board = detail(part(parent, "ChapelSign", Vector3.new(0.25, 1.2, width * 0.7), CFrame.new(at(s, 0.35, doorTop + 2.4, zCenter)), Color3.fromRGB(40, 38, 36)))
	Facade.boardText(board, roadFace, lot.name .. "  ·  FUNERAL CHAPEL", Color3.fromRGB(225, 210, 175), Color3.fromRGB(40, 38, 36), Enum.Font.Garamond)
end

-- ===== The bus depot (chapter 10) =====
-- Down by the wharf, the edge of the city: a paved forecourt off the
-- sidewalk with the upstate bus waiting in it side-on to the street, a
-- shelter and bench at the kerb, and the ticket hall across the back with
-- the depot's name over it. The bus is hollow, with seats, and its road-side
-- windows are clear, so whoever's sat in it can be seen from the street
-- (see CityConfig.DEPOT_BUS for where it is).

local function buildBusDepot(parent: Instance, lot)
	local s = lot.side
	local roadFace = Facade.roadFace(s)
	local near, far = CityConfig.lotZRange(lot)
	local zCenter = (near + far) / 2
	local length = near - far
	local depth = 22
	-- World-space pieces (the bus) go through this: part() works in the
	-- street's frame.
	local function worldPart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
		return part(parent, name, size, FRAME:Inverse() * cframe, color, material)
	end

	-- The forecourt, level with the sidewalk.
	part(parent, "DepotForecourt", Vector3.new(depth, SIDEWALK_TOP, length), CFrame.new(at(s, -depth / 2, SIDEWALK_TOP / 2, zCenter)), Color3.fromRGB(74, 72, 70), Enum.Material.Concrete)
	for k = -2, 2 do
		detail(part(parent, "BayLine", Vector3.new(depth - 6, 0.05, 0.3), CFrame.new(at(s, -depth / 2 + 1, SIDEWALK_TOP + 0.03, zCenter + k * 7)), Color3.fromRGB(225, 200, 70)))
	end

	-- The ticket hall across the back.
	local hallDepth, hallHeight = 9, 15
	local hall = part(parent, "DepotHall", Vector3.new(hallDepth, hallHeight, length - 2), CFrame.new(at(s, -depth + hallDepth / 2, SIDEWALK_TOP + hallHeight / 2, zCenter)), Color3.fromRGB(150, 140, 120), Enum.Material.Brick)
	local gui = Facade.gui(hall, roadFace)
	Facade.windows(gui, 8, 3, 0.75, 0.15, 0.55)
	local board = detail(part(parent, "DepotSign", Vector3.new(0.4, 2.6, length * 0.6), CFrame.new(at(s, -depth + hallDepth + 0.3, SIDEWALK_TOP + hallHeight - 2.4, zCenter)), Color3.fromRGB(26, 50, 90)))
	Facade.boardText(board, roadFace, lot.name .. "  ·  INTERCITY & UPSTATE", Color3.fromRGB(240, 230, 200), Color3.fromRGB(26, 50, 90), Enum.Font.GothamBold)
	for _, dz in { -4, 4 } do
		local doorway = detail(part(parent, "HallDoors", Vector3.new(0.2, 6, 4), CFrame.new(at(s, -depth + hallDepth + 0.12, SIDEWALK_TOP + 3, zCenter + dz)), Color3.fromRGB(255, 226, 170), Enum.Material.Neon))
		doorway.Transparency = 0.3
	end

	-- A low wall closing the forecourt off at either end.
	for _, z in { near - 0.5, far + 0.5 } do
		part(parent, "DepotEndWall", Vector3.new(depth - hallDepth, 3, 1), CFrame.new(at(s, -(depth - hallDepth) / 2, SIDEWALK_TOP + 1.5, z)), Color3.fromRGB(120, 112, 100), Enum.Material.Brick)
	end

	-- The shelter at the kerb: a roof on posts, a bench, the timetable.
	local shelterZ = zCenter + length * 0.3
	local kerbOut = CityConfig.SIDEWALK_WIDTH + 3 - 2.5
	for _, dz in { -3, 3 } do
		detail(part(parent, "ShelterPost", Vector3.new(0.25, 7, 0.25), CFrame.new(at(s, kerbOut - 1, SIDEWALK_TOP + 3.5, shelterZ + dz)), Color3.fromRGB(40, 60, 80), Enum.Material.Metal))
	end
	detail(part(parent, "ShelterRoof", Vector3.new(3.4, 0.3, 7.4), CFrame.new(at(s, kerbOut, SIDEWALK_TOP + 7.1, shelterZ)), Color3.fromRGB(40, 60, 80), Enum.Material.Metal))
	local back = detail(part(parent, "ShelterBack", Vector3.new(0.15, 4.5, 6.4), CFrame.new(at(s, kerbOut - 1.6, SIDEWALK_TOP + 3, shelterZ)), Color3.fromRGB(180, 200, 210), Enum.Material.Glass))
	back.Transparency = 0.5
	detail(part(parent, "ShelterBench", Vector3.new(1.2, 0.3, 5), CFrame.new(at(s, kerbOut - 0.9, SIDEWALK_TOP + 1.6, shelterZ)), Color3.fromRGB(96, 66, 42), Enum.Material.Wood))
	local timetable = detail(part(parent, "Timetable", Vector3.new(0.2, 1.6, 1.2), CFrame.new(at(s, kerbOut - 1.7, SIDEWALK_TOP + 4.6, shelterZ + 2.2)), Color3.fromRGB(240, 236, 226)))
	Facade.boardText(timetable, roadFace, "UPSTATE 7:00", Color3.fromRGB(26, 26, 30), Color3.fromRGB(240, 236, 226))

	-- The bus.
	local bus = CityConfig.DEPOT_BUS
	local size = CityConfig.DEPOT_BUS_SIZE
	local floorY = bus.Position.Y
	local groundY = SIDEWALK_TOP
	local cream = Color3.fromRGB(226, 218, 196)
	local blue = Color3.fromRGB(40, 70, 130)
	local function busPart(name: string, partSize: Vector3, offset: Vector3, color: Color3, material: Enum.Material?): Part
		return worldPart(name, partSize, bus * CFrame.new(offset), color, material)
	end
	local lowerTop = 2.2 -- the body below the windows, above the floor
	local windowTop = lowerTop + 3.1
	local roofTop = windowTop + 0.9
	-- Lower body, down to just above the road.
	busPart("BusSkirt", Vector3.new(size.X, floorY - groundY - 0.4, size.Z), Vector3.new(0, -(floorY - groundY) / 2 + 0.2, 0), blue, Enum.Material.SmoothPlastic)
	for _, x in { -size.X / 2 + 0.15, size.X / 2 - 0.15 } do
		busPart("BusSide", Vector3.new(0.3, lowerTop, size.Z), Vector3.new(x, lowerTop / 2, 0), cream, Enum.Material.SmoothPlastic)
		busPart("BusStripe", Vector3.new(0.35, 0.4, size.Z), Vector3.new(x, lowerTop - 0.3, 0), blue, Enum.Material.SmoothPlastic)
		-- Window pillars, and clear glass between them.
		for k = 0, 6 do
			local z = -size.Z / 2 + 1 + k * ((size.Z - 2) / 6)
			busPart("BusPillar", Vector3.new(0.3, windowTop - lowerTop, 0.5), Vector3.new(x, (lowerTop + windowTop) / 2, z), cream, Enum.Material.SmoothPlastic)
		end
		-- (Plain and nearly clear: as Glass it washed out whoever was sat
		-- behind it.)
		local glass = busPart("BusWindows", Vector3.new(0.1, windowTop - lowerTop, size.Z - 1), Vector3.new(x, (lowerTop + windowTop) / 2, 0), Color3.fromRGB(150, 170, 180), Enum.Material.SmoothPlastic)
		glass.Transparency = 0.88
		glass.CanCollide = false
	end
	busPart("BusFloor", Vector3.new(size.X, 0.3, size.Z), Vector3.new(0, -0.15, 0), Color3.fromRGB(60, 60, 64), Enum.Material.SmoothPlastic)
	busPart("BusRoof", Vector3.new(size.X, roofTop - windowTop, size.Z), Vector3.new(0, (windowTop + roofTop) / 2, 0), cream, Enum.Material.SmoothPlastic)
	-- The ends: the windshield at the front (-Z), the engine at the back.
	busPart("BusFront", Vector3.new(size.X, lowerTop, 0.4), Vector3.new(0, lowerTop / 2, -size.Z / 2 + 0.2), cream, Enum.Material.SmoothPlastic)
	local windshield = busPart("BusWindshield", Vector3.new(size.X - 0.6, windowTop - lowerTop, 0.2), Vector3.new(0, (lowerTop + windowTop) / 2, -size.Z / 2 + 0.1), Color3.fromRGB(40, 50, 60), Enum.Material.Glass)
	windshield.Transparency = 0.4
	busPart("BusBack", Vector3.new(size.X, roofTop, 0.4), Vector3.new(0, roofTop / 2, size.Z / 2 - 0.2), cream, Enum.Material.SmoothPlastic)
	local destination = busPart("BusDestination", Vector3.new(size.X - 2, 0.7, 0.15), Vector3.new(0, windowTop + 0.45, -size.Z / 2 - 0.05), Color3.fromRGB(255, 170, 40), Enum.Material.Neon)
	Facade.boardText(destination, Enum.NormalId.Front, "UPSTATE EXPRESS", Color3.fromRGB(30, 20, 10), Color3.fromRGB(255, 170, 40), Enum.Font.GothamBold)
	-- Wheels.
	for _, z in { -size.Z / 2 + 5, size.Z / 2 - 6 } do
		for _, x in { -size.X / 2 + 0.3, size.X / 2 - 0.3 } do
			local wheel = worldPart("BusWheel", Vector3.new(1.2, 3.2, 3.2), bus * CFrame.new(x, groundY + 1.6 - floorY, z), Color3.fromRGB(20, 20, 22), Enum.Material.Rubber)
			wheel.Shape = Enum.PartType.Cylinder
		end
	end
	-- Seats down both sides inside, and a light along the ceiling.
	for k = 0, 6 do
		local z = -size.Z / 2 + 3.5 + k * 3.8
		for _, x in { -2.6, 2.6 } do
			busPart("BusSeat", Vector3.new(2.6, 0.5, 1.6), Vector3.new(x, 1.3, z), Color3.fromRGB(60, 50, 110), Enum.Material.Fabric)
			busPart("BusSeatBack", Vector3.new(2.6, 2.2, 0.35), Vector3.new(x, 2.3, z + 0.85), Color3.fromRGB(60, 50, 110), Enum.Material.Fabric)
		end
	end
	local strip = busPart("BusLight", Vector3.new(0.6, 0.15, size.Z - 4), Vector3.new(0, windowTop + 0.35, 0), Color3.fromRGB(240, 240, 220), Enum.Material.Neon)
	strip.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(240, 236, 210)
	light.Brightness = 1.2
	light.Range = 18
	light.Parent = strip
end

-- ===== Nightclubs =====

local CLUB_PALETTES = {
	{ main = Color3.fromRGB(255, 40, 170), accent = Color3.fromRGB(40, 220, 255) },
	{ main = Color3.fromRGB(60, 140, 255), accent = Color3.fromRGB(255, 70, 70) },
	{ main = Color3.fromRGB(170, 70, 255), accent = Color3.fromRGB(255, 200, 60) },
	{ main = Color3.fromRGB(40, 230, 150), accent = Color3.fromRGB(255, 60, 200) },
}
local clubCursor = 0

local function buildNightclub(parent: Instance, lot)
	local s = lot.side
	local roadFace = Facade.roadFace(s)
	local near, far = CityConfig.lotZRange(lot)
	local zCenter = (near + far) / 2
	local width = (near - far) - 4
	local depth, height = 22, 34
	clubCursor = clubCursor % #CLUB_PALETTES + 1
	local palette = CLUB_PALETTES[clubCursor]

	local building = part(parent, "Nightclub_" .. lot.name, Vector3.new(depth, height, width), CFrame.new(at(s, -depth / 2, height / 2, zCenter)), Color3.fromRGB(24, 20, 28), Enum.Material.Brick)
	local gui = Facade.gui(building, roadFace)
	Facade.windows(gui, 5, 3, 0.1, 0, 1 - 19 / height)

	-- Neon: two tall corner tubes and a band across the front.
	local main = palette.main
	for _, cornerZ in { near - 2.2, far + 2.2 } do
		detail(part(parent, "NeonTube", Vector3.new(0.3, height - 3, 0.3), CFrame.new(at(s, 0.2, (height - 3) / 2 + 1.5, cornerZ)), main, Enum.Material.Neon))
	end
	detail(part(parent, "NeonBand", Vector3.new(0.3, 0.3, width - 1), CFrame.new(at(s, 0.2, 12.5, zCenter)), palette.accent, Enum.Material.Neon))

	-- The name, big, framed in neon.
	local signY = 17
	local sign = detail(part(parent, "ClubSign", Vector3.new(0.6, 4.2, 20), CFrame.new(at(s, 0.4, signY, zCenter)), Color3.fromRGB(10, 8, 12)))
	Facade.boardText(sign, roadFace, lot.name, main, Color3.fromRGB(10, 8, 12), Enum.Font.GothamBlack)
	for _, dy in { 2.2, -2.2 } do
		detail(part(parent, "ClubSignNeon", Vector3.new(0.3, 0.25, 20.4), CFrame.new(at(s, 0.75, signY + dy, zCenter)), main, Enum.Material.Neon))
	end

	-- Entrance at the near end, under a canopy lit from beneath.
	local doorZ = near - 5
	detail(part(parent, "ClubDoor", Vector3.new(0.3, 7, 3.2), CFrame.new(at(s, 0.15, SIDEWALK_TOP + 3.5, doorZ)), Color3.fromRGB(90, 10, 25)))
	local canopy = detail(part(parent, "ClubCanopy", Vector3.new(4.5, 0.35, 6.5), CFrame.new(at(s, 2.25, SIDEWALK_TOP + 7.6, doorZ)), Color3.fromRGB(12, 10, 14)))
	detail(part(parent, "ClubCanopyNeon", Vector3.new(0.2, 0.2, 6.5), CFrame.new(at(s, 4.5, SIDEWALK_TOP + 7.4, doorZ)), main, Enum.Material.Neon))
	local wash = Instance.new("PointLight")
	wash.Color = main
	wash.Brightness = 2
	wash.Range = 18
	wash.Parent = canopy

	-- Velvet rope line along the sidewalk, and the queue waiting behind it.
	local queueLength = 8
	local spacing = 2.4
	local gold = Color3.fromRGB(200, 170, 70)
	local ropeOut = 2.8
	local firstPostZ = doorZ - 2.5
	for i = 0, queueLength do
		local postZ = firstPostZ - i * spacing
		detail(cylinder(parent, "Stanchion", 0.22, 3, at(s, ropeOut, SIDEWALK_TOP + 1.5, postZ), gold))
		detail(ball(parent, "StanchionTop", 0.38, at(s, ropeOut, SIDEWALK_TOP + 3.05, postZ), gold))
	end
	detail(part(parent, "VelvetRope", Vector3.new(0.14, 0.14, spacing * queueLength), CFrame.new(at(s, ropeOut, SIDEWALK_TOP + 2.55, firstPostZ - spacing * queueLength / 2)), Color3.fromRGB(150, 10, 35), Enum.Material.Fabric))
	for i = 1, queueLength do
		local position = at(s, 1.4, SIDEWALK_TOP, firstPostZ - 0.8 - (i - 1) * spacing)
		local lookTarget = position + Vector3.new(math.random(-6, 6) / 10, 0, 1)
		if math.random() < 0.2 then
			lookTarget = position + Vector3.new(-s, 0, 0)
		end
		person(parent, "ClubQueue", CFrame.lookAt(position, lookTarget), describePerson(pick(NIGHT_OUT_COLORS), pick(NIGHT_OUT_COLORS)))
	end

	-- The bouncer, beside the door, watching the line.
	local bouncerPos = at(s, 1.8, SIDEWALK_TOP, doorZ + 2.4)
	person(parent, "Bouncer", CFrame.lookAt(bouncerPos, bouncerPos + Vector3.new(-s * 0.6, 0, -1)), describePerson(Color3.fromRGB(15, 15, 17), Color3.fromRGB(15, 15, 17), 1.3, 1.1))
	part(parent, "GuestListStand", Vector3.new(0.7, 3.2, 0.7), CFrame.new(at(s, 2.6, SIDEWALK_TOP + 1.6, doorZ + 1.2)), Color3.fromRGB(20, 18, 22))
end

-- ===== Cinemas =====

local FEATURES = {
	"NOW SHOWING\nNIGHT FARE  ·  THE LONG SHIFT\nMIDNIGHT SHOW",
	"NOW SHOWING\nDEAD OF NIGHT  ·  RAIN CITY\nLATE SHOW 1 AM",
	"TONIGHT\nNEON SAINTS  ·  LAST TRAIN OUT\nALL NIGHT DOUBLE BILL",
	"NOW SHOWING\nTHE BACK SEAT  ·  GRAVEYARD SHIFT\nMIDNIGHT SHOW",
}
local featureCursor = 0

local function buildCinema(parent: Instance, lot)
	local s = lot.side
	local roadFace = Facade.roadFace(s)
	local near, far = CityConfig.lotZRange(lot)
	local zCenter = (near + far) / 2
	local width = (near - far) - 4
	local depth, height = 24, 32

	local building = part(parent, "Cinema_" .. lot.name, Vector3.new(depth, height, width), CFrame.new(at(s, -depth / 2, height / 2, zCenter)), Color3.fromRGB(88, 34, 30), Enum.Material.Brick)
	local gui = Facade.gui(building, roadFace)
	Facade.windows(gui, 6, 3, 0.15, 0, 1 - 17 / height)

	-- The marquee box over the sidewalk, ringed with bulbs and lit beneath.
	-- The bulbs are long Neon strips rather than one part per bulb.
	local marqueeY = 10.5
	local marquee = detail(part(parent, "Marquee", Vector3.new(5, 3.2, 22), CFrame.new(at(s, 2.5, marqueeY, zCenter)), Color3.fromRGB(30, 26, 26)))
	featureCursor = featureCursor % #FEATURES + 1
	Facade.boardText(marquee, roadFace, FEATURES[featureCursor], Color3.fromRGB(20, 20, 22), Color3.fromRGB(245, 235, 205), Enum.Font.Oswald)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		Facade.boardText(marquee, face, lot.name, Color3.fromRGB(255, 220, 120), nil, Enum.Font.Oswald)
	end
	local bulbColor = Color3.fromRGB(255, 225, 160)
	for _, dy in { 1.75, -1.75 } do
		detail(part(parent, "MarqueeBulbs", Vector3.new(0.3, 0.3, 21), CFrame.new(at(s, 5.05, marqueeY + dy, zCenter)), bulbColor, Enum.Material.Neon))
	end
	local under = Instance.new("SurfaceLight")
	under.Face = Enum.NormalId.Bottom
	under.Color = Color3.fromRGB(255, 220, 160)
	under.Brightness = 2
	under.Range = 14
	under.Angle = 120
	under.Parent = marquee

	-- Tall vertical blade sign at the near corner, readable from up and
	-- down the street.
	local blade = detail(part(parent, "BladeSign", Vector3.new(3.4, 16, 0.6), CFrame.new(at(s, 1.7, 22, near - 4)), Color3.fromRGB(25, 20, 20)))
	local letterList = {}
	for letter in lot.name:gsub("^THE ", ""):gmatch(".") do
		table.insert(letterList, letter)
	end
	local letters = table.concat(letterList, "\n")
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		Facade.boardText(blade, face, letters, Color3.fromRGB(255, 200, 80), Color3.fromRGB(25, 20, 20), Enum.Font.Oswald)
	end
	detail(part(parent, "BladeNeon", Vector3.new(0.25, 16, 0.7), CFrame.new(at(s, 3.45, 22, near - 4)), Color3.fromRGB(255, 120, 40), Enum.Material.Neon))

	-- Ticket booth, glass doors, poster cases.
	local booth = part(parent, "TicketBooth", Vector3.new(2.4, 3, 2.4), CFrame.new(at(s, 1.8, SIDEWALK_TOP + 1.5, zCenter)), Color3.fromRGB(200, 160, 90), Enum.Material.Neon)
	booth.Transparency = 0.35
	part(parent, "TicketBoothCap", Vector3.new(2.8, 0.3, 2.8), CFrame.new(at(s, 1.8, SIDEWALK_TOP + 3.15, zCenter)), Color3.fromRGB(120, 30, 30))
	detail(part(parent, "CinemaDoors", Vector3.new(0.2, 6.5, 9), CFrame.new(at(s, 0.1, SIDEWALK_TOP + 3.25, zCenter)), Color3.fromRGB(30, 28, 30)))
	for k, text in { "COMING\nSOON", "MIDNIGHT\nDOUBLE\nFEATURE" } do
		local poster = detail(part(parent, "PosterCase", Vector3.new(0.2, 4.2, 2.8), CFrame.new(at(s, 0.1, SIDEWALK_TOP + 3.5, zCenter + (if k == 1 then 8 else -8))), Color3.fromRGB(120, 25, 25)))
		Facade.boardText(poster, roadFace, text, Color3.fromRGB(250, 235, 200), Color3.fromRGB(120, 25, 25))
	end
end

-- ===== Apartment towers =====

local TOWER_COLORS = {
	Color3.fromRGB(150, 140, 125),
	Color3.fromRGB(120, 95, 80),
	Color3.fromRGB(96, 96, 102),
	Color3.fromRGB(165, 155, 138),
}

-- Lit window grids on a tower section's three street-visible faces.
local function towerWindows(section: BasePart, roadFace: Enum.NormalId, lobbyHeight: number)
	local size = section.Size
	local faces = {
		{ face = roadFace, width = size.Z },
		{ face = Enum.NormalId.Front, width = size.X },
		{ face = Enum.NormalId.Back, width = size.X },
	}
	for _, info in faces do
		local gui = Facade.gui(section, info.face, 900)
		local rows = math.floor((size.Y - lobbyHeight) / 5)
		local bottom = if lobbyHeight > 0 then 1 - lobbyHeight / size.Y else 1
		Facade.windows(gui, math.floor(info.width / 3.4), rows, 0.24, 0, bottom)
	end
end

local function buildHighrise(parent: Instance, lot)
	local s = lot.side
	local roadFace = Facade.roadFace(s)
	local near, far = CityConfig.lotZRange(lot)
	local zCenter = (near + far) / 2
	local width = (near - far) - 4
	local depth = 26
	local height = math.random(110, 165)
	local baseHeight = math.floor(height * 0.62)
	local color = pick(TOWER_COLORS)
	local lobbyHeight = 10

	local base = part(parent, "Tower_" .. lot.name, Vector3.new(depth, baseHeight, width), CFrame.new(at(s, -depth / 2, baseHeight / 2, zCenter)), color, Enum.Material.Concrete)
	towerWindows(base, roadFace, lobbyHeight)
	local upperHeight = height - baseHeight
	local upper = part(parent, "TowerUpper", Vector3.new(depth - 6, upperHeight, width - 6), CFrame.new(at(s, -depth / 2, baseHeight + upperHeight / 2, zCenter)), color, Enum.Material.Concrete)
	towerWindows(upper, roadFace, 0)

	-- Lobby: warm lit glass across the ground floor.
	local gui = Facade.gui(base, roadFace)
	local lobby = Instance.new("Frame")
	lobby.Name = "Lobby"
	lobby.BackgroundColor3 = Color3.fromRGB(30, 26, 22)
	lobby.BorderSizePixel = 0
	lobby.Position = UDim2.new(0, 0, 1 - lobbyHeight / baseHeight, 0)
	lobby.Size = UDim2.new(1, 0, lobbyHeight / baseHeight, 0)
	lobby.ZIndex = 2
	lobby.Parent = gui
	local glass = Instance.new("Frame")
	glass.BackgroundColor3 = Color3.fromRGB(225, 185, 115)
	glass.BorderSizePixel = 0
	glass.Position = UDim2.fromScale(0.1, 0.15)
	glass.Size = UDim2.fromScale(0.8, 0.85)
	glass.Parent = lobby

	-- Doorman canopy out to the kerb, on brass poles, the building's name
	-- along its edges.
	local canopyLength = (EDGE - CityConfig.ROAD_WIDTH / 2) - 1.5
	local green = Color3.fromRGB(25, 62, 42)
	local canopyY = SIDEWALK_TOP + 8.3
	detail(part(parent, "TowerCanopy", Vector3.new(canopyLength, 0.5, 6), CFrame.new(at(s, canopyLength / 2, canopyY, zCenter)), green, Enum.Material.Fabric))
	local endValance = detail(part(parent, "TowerCanopyEnd", Vector3.new(0.12, 1.2, 6), CFrame.new(at(s, canopyLength, canopyY - 0.7, zCenter)), green, Enum.Material.Fabric))
	Facade.boardText(endValance, roadFace, lot.name, Color3.fromRGB(235, 225, 190))
	for _, sideZ in { -3.06, 3.06 } do
		local valance = detail(part(parent, "TowerCanopySide", Vector3.new(canopyLength, 1, 0.12), CFrame.new(at(s, canopyLength / 2, canopyY - 0.7, zCenter + sideZ)), green, Enum.Material.Fabric))
		Facade.boardText(valance, if sideZ < 0 then Enum.NormalId.Front else Enum.NormalId.Back, lot.name, Color3.fromRGB(235, 225, 190))
		cylinder(parent, "CanopyPole", 0.3, canopyY - SIDEWALK_TOP, at(s, canopyLength - 0.3, (canopyY + SIDEWALK_TOP) / 2, zCenter + sideZ * 0.9), Color3.fromRGB(190, 160, 80))
	end

	-- Roof: a water tank, a lit crown round the top, a mast with an aircraft
	-- beacon (kept at opposite ends of the roof so they can't overlap).
	DistrictBuilder.addWaterTower(parent, at(s, -depth / 2, height, zCenter + 6))
	local crownColor = Color3.fromRGB(255, 220, 150)
	local topY = height - 0.6
	local upperCenter = at(s, -depth / 2, topY, zCenter)
	local ux, uz = (depth - 6) / 2, (width - 6) / 2
	for _, strip in {
		{ Vector3.new(ux * 2 + 0.3, 0.4, 0.3), Vector3.new(0, 0, uz) },
		{ Vector3.new(ux * 2 + 0.3, 0.4, 0.3), Vector3.new(0, 0, -uz) },
		{ Vector3.new(0.3, 0.4, uz * 2 + 0.3), Vector3.new(ux, 0, 0) },
		{ Vector3.new(0.3, 0.4, uz * 2 + 0.3), Vector3.new(-ux, 0, 0) },
	} do
		detail(part(parent, "TowerCrown", strip[1], CFrame.new(upperCenter + strip[2]), crownColor, Enum.Material.Neon))
	end
	detail(part(parent, "TowerMast", Vector3.new(0.4, 12, 0.4), CFrame.new(at(s, -depth / 2, height + 6, zCenter - 8)), Color3.fromRGB(40, 40, 44)))
	detail(ball(parent, "TowerBeacon", 0.9, at(s, -depth / 2, height + 12.3, zCenter - 8), Color3.fromRGB(255, 30, 30), Enum.Material.Neon))
end

-- ===== Parks =====

local function buildPark(parent: Instance, lot)
	local s = lot.side
	local near, far = CityConfig.lotZRange(lot)
	-- Inset from both ends so it stops short of the cross streets' own
	-- sidewalks rather than overlapping them.
	local zNear, zFar = near - 6, far + 6
	local length = zNear - zFar
	local depth = 100

	-- Local park coordinates: u = studs into the park from the street wall,
	-- v = studs along it from the near end.
	local function P(u: number, y: number, v: number): Vector3
		return Vector3.new(s * (EDGE + u), y, zNear - v)
	end

	local folder = parent

	part(folder, "ParkGround", Vector3.new(depth, 1.2, length), CFrame.new(P(depth / 2, 0.6, length / 2)), Color3.fromRGB(48, 86, 44), Enum.Material.Grass)

	-- Low stone wall along the avenue with two gates, plus the two ends.
	local stone = Color3.fromRGB(112, 106, 96)
	local wallTop = SIDEWALK_TOP + 2.4
	local function wallAlongV(v1: number, v2: number)
		part(folder, "ParkWall", Vector3.new(1.2, 2.4, v2 - v1), CFrame.new(P(0.6, SIDEWALK_TOP + 1.2, (v1 + v2) / 2)), stone, Enum.Material.Slate)
		detail(part(folder, "ParkWallCap", Vector3.new(1.6, 0.3, v2 - v1), CFrame.new(P(0.6, wallTop + 0.15, (v1 + v2) / 2)), Color3.fromRGB(135, 130, 120), Enum.Material.Slate))
	end
	local function wallAlongU(v: number, u1: number, u2: number)
		part(folder, "ParkWall", Vector3.new(u2 - u1, 2.4, 1.2), CFrame.new(P((u1 + u2) / 2, SIDEWALK_TOP + 1.2, v)), stone, Enum.Material.Slate)
	end
	local gates = { { 18, 26 }, { 60, 68 } }
	wallAlongV(0, gates[1][1])
	wallAlongV(gates[1][2], gates[2][1])
	wallAlongV(gates[2][2], length)
	for _, v in { 0.6, length - 0.6 } do
		wallAlongU(v, 0, 8)
		wallAlongU(v, 15, depth)
	end
	-- A tall hedge closes off the back of the park.
	part(folder, "ParkHedge", Vector3.new(2.5, 6, length), CFrame.new(P(depth - 1.25, SIDEWALK_TOP + 3, length / 2)), Color3.fromRGB(30, 62, 34), Enum.Material.Grass)

	-- Gate pillars with lamp globes, and the park's name by the main gate.
	for _, gate in gates do
		for _, v in gate do
			part(folder, "GatePillar", Vector3.new(1.8, 4.6, 1.8), CFrame.new(P(0.6, SIDEWALK_TOP + 2.3, v)), stone, Enum.Material.Slate)
			detail(ball(folder, "GateGlobe", 1, P(0.6, SIDEWALK_TOP + 5.1, v), Color3.fromRGB(255, 230, 175), Enum.Material.Neon))
		end
	end
	local plaque = detail(part(folder, "ParkPlaque", Vector3.new(0.2, 1.4, 5), CFrame.new(P(-0.1, SIDEWALK_TOP + 1.4, gates[1][1] - 4)), Color3.fromRGB(25, 62, 42)))
	Facade.boardText(plaque, Facade.roadFace(s), lot.name, Color3.fromRGB(235, 225, 190), Color3.fromRGB(25, 62, 42))

	-- Paths: from each gate to a central fountain plaza, and a loop round
	-- the pond. Remembered as sample points so trees stay off them.
	local pathColor = Color3.fromRGB(150, 140, 120)
	local keepClear: { { u: number, v: number, r: number } } = {}
	local function path(u1: number, v1: number, u2: number, v2: number, width: number?)
		local a, b = P(u1, SIDEWALK_TOP + 0.03, v1), P(u2, SIDEWALK_TOP + 0.03, v2)
		detail(part(folder, "ParkPath", Vector3.new(width or 4, 0.06, (b - a).Magnitude + 2), CFrame.lookAt((a + b) / 2, b), pathColor, Enum.Material.Pebble))
		local steps = math.ceil((b - a).Magnitude / 4)
		for i = 0, steps do
			local t = i / steps
			table.insert(keepClear, { u = u1 + (u2 - u1) * t, v = v1 + (v2 - v1) * t, r = 3.5 })
		end
	end

	local plazaU, plazaV = 40, length / 2
	local pondU, pondV = 72, length / 2
	path(0, 22, plazaU, plazaV)
	path(0, 64, plazaU, plazaV)
	path(11.5, 0, plazaU, plazaV)
	path(11.5, length, plazaU, plazaV)
	path(plazaU, plazaV, pondU - 19, pondV)
	local loopPoints = {}
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		table.insert(loopPoints, { pondU + math.cos(a) * 19, pondV + math.sin(a) * 23 })
	end
	for i = 1, #loopPoints do
		local p1, p2 = loopPoints[i], loopPoints[i % #loopPoints + 1]
		path(p1[1], p1[2], p2[1], p2[2], 3.5)
	end

	-- Fountain plaza.
	detail(cylinder(folder, "Plaza", 20, 0.08, P(plazaU, SIDEWALK_TOP + 0.04, plazaV), Color3.fromRGB(160, 150, 132), Enum.Material.Concrete))
	table.insert(keepClear, { u = plazaU, v = plazaV, r = 12 })
	cylinder(folder, "FountainBasin", 9, 1.2, P(plazaU, SIDEWALK_TOP + 0.6, plazaV), stone, Enum.Material.Slate)
	local water = detail(cylinder(folder, "FountainWater", 8.2, 0.2, P(plazaU, SIDEWALK_TOP + 1.05, plazaV), Color3.fromRGB(40, 72, 92)))
	water.Reflectance = 0.35
	cylinder(folder, "FountainColumn", 1.2, 3, P(plazaU, SIDEWALK_TOP + 2.5, plazaV), stone, Enum.Material.Slate)
	cylinder(folder, "FountainBowl", 3.6, 0.5, P(plazaU, SIDEWALK_TOP + 4.1, plazaV), stone, Enum.Material.Slate)
	local top = detail(ball(folder, "FountainTop", 0.8, P(plazaU, SIDEWALK_TOP + 4.7, plazaV), stone, Enum.Material.Slate))
	local spray = Instance.new("ParticleEmitter")
	spray.Texture = STEAM_TEXTURE
	spray.Color = ColorSequence.new(Color3.fromRGB(210, 225, 235))
	spray.Size = NumberSequence.new(0.35, 0.8)
	spray.Transparency = NumberSequence.new(0.35, 1)
	spray.Lifetime = NumberRange.new(0.7, 1)
	spray.Rate = 35
	spray.Speed = NumberRange.new(4, 5)
	spray.SpreadAngle = Vector2.new(25, 25)
	spray.Acceleration = Vector3.new(0, -12, 0)
	spray.Parent = top

	-- The pond, with rocks round its edge, and a rocky outcrop nearby.
	local pond = detail(part(folder, "Pond", Vector3.new(0.3, 30, 38), CFrame.new(P(pondU, SIDEWALK_TOP - 0.1, pondV)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(32, 58, 72)))
	pond.Shape = Enum.PartType.Cylinder
	pond.Reflectance = 0.35
	table.insert(keepClear, { u = pondU, v = pondV, r = 24 })
	local rockColor = Color3.fromRGB(92, 92, 98)
	for i = 0, 13 do
		local a = i / 14 * math.pi * 2
		local size = math.random(14, 28) / 10
		detail(part(folder, "PondRock", Vector3.new(size, size * 0.6, size * 1.2), CFrame.new(P(pondU + math.cos(a) * 15.2, SIDEWALK_TOP + 0.2, pondV + math.sin(a) * 19.2)) * CFrame.Angles(0, math.random() * math.pi, math.rad(math.random(-15, 15))), rockColor, Enum.Material.Slate))
	end
	for i = 1, 4 do
		local rock = part(folder, "Outcrop", Vector3.new(math.random(6, 10), math.random(3, 5), math.random(5, 9)), CFrame.new(P(20 + math.random(-4, 4), SIDEWALK_TOP + 1, length - 16 + math.random(-4, 4))) * CFrame.Angles(math.rad(math.random(-12, 12)), math.random() * math.pi, math.rad(math.random(-12, 12))), rockColor, Enum.Material.Slate)
		rock.Name = "Outcrop" .. i
	end
	table.insert(keepClear, { u = 20, v = length - 16, r = 9 })

	-- Benches along the gate paths.
	local benchWood = Color3.fromRGB(92, 66, 42)
	local iron = Color3.fromRGB(28, 44, 34)
	local function bench(u: number, v: number, facingU: number, facingV: number)
		local origin = P(u, SIDEWALK_TOP, v)
		local facing = Vector3.new(s * facingU, 0, -facingV).Unit
		local frame = CFrame.lookAt(origin, origin + facing)
		part(folder, "BenchSeat", Vector3.new(4, 0.2, 1.4), frame * CFrame.new(0, 1.4, 0), benchWood, Enum.Material.WoodPlanks)
		detail(part(folder, "BenchBack", Vector3.new(4, 1.1, 0.2), frame * CFrame.new(0, 2.2, 0.75) * CFrame.Angles(math.rad(-12), 0, 0), benchWood, Enum.Material.WoodPlanks))
		for _, x in { -1.8, 1.8 } do
			detail(part(folder, "BenchLeg", Vector3.new(0.2, 1.4, 1.4), frame * CFrame.new(x, 0.7, 0), iron))
		end
		table.insert(keepClear, { u = u, v = v, r = 3 })
	end
	for _, spot in { { 10, 26, 0, -1 }, { 22, 31, -1, 0.4 }, { 10, 60, 0, 1 }, { 22, 56, -1, -0.4 }, { 26, 14, 0.6, -1 }, { 26, 76, 0.6, 1 }, { plazaU - 12, plazaV, 1, 0 }, { plazaU, plazaV - 12, 0, 1 }, { plazaU, plazaV + 12, 0, -1 } } do
		bench(spot[1], spot[2], spot[3], spot[4])
	end

	-- Old-style lamp posts; only some actually cast light, to keep the light
	-- count down -- the globes all glow either way.
	local lampSpots = { { 6, 22 }, { 6, 64 }, { 20, 33 }, { 20, 54 }, { 30, plazaV - 9 }, { 30, plazaV + 9 }, { 50, plazaV - 9 }, { 50, plazaV + 9 }, { pondU, pondV - 25 }, { pondU, pondV + 25 } }
	for i, spot in lampSpots do
		part(folder, "LampPost", Vector3.new(0.35, 8, 0.35), CFrame.new(P(spot[1], SIDEWALK_TOP + 4, spot[2])), Color3.fromRGB(28, 44, 34))
		local globe = detail(ball(folder, "LampGlobe", 1.1, P(spot[1], SIDEWALK_TOP + 8.4, spot[2]), Color3.fromRGB(255, 228, 170), Enum.Material.Neon))
		if i % 3 == 1 then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 215, 150)
			light.Brightness = 1.2
			light.Range = 18
			light.Parent = globe
		end
		table.insert(keepClear, { u = spot[1], v = spot[2], r = 2 })
	end

	-- Trees: scattered, keeping off the paths, plaza, pond and each other,
	-- plus a dense row along the back hedge.
	local trunkColor = Color3.fromRGB(70, 52, 38)
	local leafColors = { Color3.fromRGB(40, 80, 40), Color3.fromRGB(55, 95, 45), Color3.fromRGB(35, 70, 38), Color3.fromRGB(70, 100, 50) }
	local trees: { { u: number, v: number } } = {}
	local function tree(u: number, v: number)
		local height = math.random(6, 10)
		cylinder(folder, "TreeTrunk", math.random(8, 11) / 10, height, P(u, SIDEWALK_TOP + height / 2, v), trunkColor, Enum.Material.Wood)
		for i = 1, 2 do
			local leaves = detail(ball(folder, "TreeLeaves", math.random(60, 100) / 10, P(u + math.random(-15, 15) / 10, SIDEWALK_TOP + height + math.random(-5, 15) / 10, v + math.random(-15, 15) / 10), pick(leafColors), Enum.Material.Grass))
			leaves.Name = "TreeLeaves" .. i
		end
		table.insert(trees, { u = u, v = v })
	end
	local function isClear(u: number, v: number): boolean
		for _, zone in keepClear do
			if (zone.u - u) ^ 2 + (zone.v - v) ^ 2 < (zone.r + 2.5) ^ 2 then
				return false
			end
		end
		for _, t in trees do
			if (t.u - u) ^ 2 + (t.v - v) ^ 2 < 36 then
				return false
			end
		end
		return true
	end
	local placed, attempts = 0, 0
	while placed < 45 and attempts < 1500 do
		attempts += 1
		local u, v = math.random(5, depth - 8), math.random(5, math.floor(length) - 5)
		if isClear(u, v) then
			tree(u, v)
			placed += 1
		end
	end
	for v = 4, length - 4, 8 do
		if isClear(depth - 5, v) then
			tree(depth - 5, v)
		end
	end

	-- A hot dog cart on the sidewalk by the main gate, and its vendor.
	local cartV = gates[1][1] - 9
	local cartCenter = P(-4.5, SIDEWALK_TOP + 2, cartV)
	local cart = part(folder, "HotDogCart", Vector3.new(2.2, 2.2, 3.6), CFrame.new(cartCenter), Color3.fromRGB(185, 185, 190))
	Facade.boardText(cart, Facade.roadFace(s), "HOT DOGS  ·  PRETZELS  ·  SODA", Color3.fromRGB(200, 30, 30), Color3.fromRGB(240, 240, 235))
	for _, dz in { -1.2, 1.2 } do
		-- Cylinders run along X by default: a disc facing the road.
		local wheel = detail(part(folder, "CartWheel", Vector3.new(0.3, 1.4, 1.4), CFrame.new(cartCenter + Vector3.new(-s * 1.15, -1.1, dz)), Color3.fromRGB(25, 25, 28)))
		wheel.Shape = Enum.PartType.Cylinder
	end
	detail(part(folder, "UmbrellaPole", Vector3.new(0.15, 4, 0.15), CFrame.new(cartCenter + Vector3.new(0, 3, 0)), Color3.fromRGB(60, 60, 64)))
	detail(cylinder(folder, "Umbrella", 5.5, 0.25, cartCenter + Vector3.new(0, 5, 0), Color3.fromRGB(235, 185, 40), Enum.Material.Fabric))
	local vendorPos = P(-2.4, SIDEWALK_TOP, cartV)
	person(folder, "HotDogVendor", CFrame.lookAt(vendorPos, vendorPos + Vector3.new(-s, 0, 0)), describePerson(Color3.fromRGB(235, 235, 230), Color3.fromRGB(50, 55, 60)))
end

-- ===== Placing it all =====

-- How deep into the block each kind of lot reaches from its street wall
-- (so the passes after it know to leave that space alone).
local LOT_DEPTH = {
	taxiRank = 21,
	shops = 18,
	gunStore = 18,
	chapel = 18,
	nightclub = 22,
	cinema = 24,
	highrise = 26,
	park = 100,
	busDepot = 22,
}

local function buildLots(parent: Instance)
	local firstRank = true
	for _, lot in CityConfig.LOTS do
		BuildPacer.breathe()
		FRAME = avenueFrame(lot.x)
		EDGE = AVENUE_EDGE
		local model = Instance.new("Model")
		model.Name = lot.name or lot.kind
		model.Parent = parent

		if lot.kind == "taxiRank" then
			buildTaxiRank(model, lot, firstRank)
			firstRank = false
		elseif lot.kind == "shops" then
			buildShops(model, lot)
		elseif lot.kind == "gunStore" then
			buildGunStore(model, lot)
		elseif lot.kind == "chapel" then
			buildChapel(model, lot)
		elseif lot.kind == "nightclub" then
			buildNightclub(model, lot)
		elseif lot.kind == "cinema" then
			buildCinema(model, lot)
		elseif lot.kind == "highrise" then
			buildHighrise(model, lot)
		elseif lot.kind == "park" then
			buildPark(model, lot)
		elseif lot.kind == "busDepot" then
			buildBusDepot(model, lot)
		end

		local near, far = CityConfig.lotZRange(lot)
		local reach = EDGE + (LOT_DEPTH[lot.kind] or ROW_DEPTH)
		take(streetRect(lot.side * EDGE, lot.side * reach, far, near))
	end
	FRAME = CFrame.identity
end

-- Ordinary buildings in every avenue slot nobody else has taken. The
-- outward-facing sides of the two outer avenues have no cross streets
-- coming off them, so those rows run straight past the cross-street slots
-- too, closing the grid in.
local function buildAvenueRows(parent: Instance)
	EDGE = AVENUE_EDGE
	for a, avenue in CityConfig.AVENUES do
		FRAME = avenueFrame(avenue.x)
		local folder = Instance.new("Folder")
		folder.Name = avenue.name
		folder.Parent = parent
		for side = -1, 1, 2 do
			local outward = (a == 1 and side == -1) or (a == #CityConfig.AVENUES and side == 1)
			local first = if outward then CityConfig.FIRST_SLOT - 1 else CityConfig.FIRST_SLOT
			local last = if outward then CityConfig.LAST_SLOT + 1 else CityConfig.LAST_SLOT
			for index = first, last do
				if not outward and CityConfig.isCrossSlot(index) then
					continue
				end
				if CityConfig.lotAt(index, side, avenue.x) then
					continue
				end
				buildRowBuilding(folder, side, CityConfig.blockZ(index), CityConfig.BLOCK_SPACING - 4)
			end
		end
	end
	FRAME = CFrame.identity
end

-- Ordinary buildings along both sides of every cross street, between the
-- avenues' own corner buildings. The outer side of the first and last cross
-- street runs the whole width of the grid instead, closing it in.
local function buildCrossRows(parent: Instance)
	EDGE = CROSS_EDGE
	local avenueReach = AVENUE_EDGE + ROW_DEPTH
	for c, street in CityConfig.CROSS_STREETS do
		FRAME = crossFrame(street.z)
		local folder = Instance.new("Folder")
		folder.Name = street.name
		folder.Parent = parent
		for side = -1, 1, 2 do
			-- Side 1 is the +Z side (see crossFrame).
			local outward = (c == 1 and side == 1) or (c == #CityConfig.CROSS_STREETS and side == -1)
			if outward then
				local reach = CityConfig.GRID_RIGHT_X + avenueReach
				fillRow(folder, side, reach, -reach)
			else
				for a = 1, #CityConfig.AVENUES - 1 do
					local leftX = CityConfig.AVENUES[a].x + avenueReach
					local rightX = CityConfig.AVENUES[a + 1].x - avenueReach
					-- Street-relative z is -worldX.
					fillRow(folder, side, -leftX, -rightX)
				end
			end
		end
	end
	FRAME = CFrame.identity
	EDGE = AVENUE_EDGE
end

local ALL_SIDES = { Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Front, Enum.NormalId.Back }

-- A plain tall block with a scatter of lit windows on the given sides.
local function backdropTower(parent: Instance, name: string, center: Vector3, size: Vector3, collide: boolean, maxDistance: number, faces: { Enum.NormalId })
	local tower = Instance.new("Part")
	tower.Name = name
	tower.Size = size
	tower.CFrame = CFrame.new(center)
	tower.Color = Color3.fromRGB(math.random(22, 34), math.random(22, 32), math.random(26, 38))
	tower.Material = Enum.Material.Concrete
	tower.Anchored = true
	tower.CanCollide = collide
	tower.CanTouch = false
	tower.CanQuery = collide
	tower.Parent = parent
	BuildPacer.breathe()
	for _, face in faces do
		local width = if face == Enum.NormalId.Left or face == Enum.NormalId.Right then size.Z else size.X
		local gui = Facade.gui(tower, face, maxDistance)
		Facade.litWindows(gui, math.max(2, math.floor(width / 6)), math.max(3, math.floor(size.Y / 8)), 0.12)
	end
end

-- Taller towers filling the middle of every block, behind the street walls:
-- they're what you see over the rooftops, and through any gap (a park, a
-- taxi rank, an alley) instead of an empty lot.
local function buildBlockMiddles(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "BlockMiddles"
	folder.Parent = parent
	local avenueReach = AVENUE_EDGE + ROW_DEPTH
	local crossReach = CROSS_EDGE + ROW_DEPTH
	for a = 1, #CityConfig.AVENUES - 1 do
		local left = CityConfig.AVENUES[a].x + avenueReach
		local right = CityConfig.AVENUES[a + 1].x - avenueReach
		for c = 1, #CityConfig.CROSS_STREETS - 1 do
			local top = CityConfig.CROSS_STREETS[c].z - crossReach
			local bottom = CityConfig.CROSS_STREETS[c + 1].z + crossReach
			local depth = top - bottom - 1
			if depth < 10 then
				continue
			end
			local x = left
			while x + 20 <= right do
				local width = math.min(math.random(26, 42), right - x)
				local rect = { minX = x + 0.5, maxX = x + width - 0.5, minZ = bottom + 0.5, maxZ = top - 0.5 }
				if isFree(rect) then
					take(rect)
					local height = math.random(50, 150)
					backdropTower(folder, "BlockTower", Vector3.new(x + width / 2, height / 2, (top + bottom) / 2), Vector3.new(width - 1, height, depth), true, 900, ALL_SIDES)
					x += width
				else
					x += 6
				end
			end
		end
	end
end

-- A ring of towers outside the grid, so the city carries on into the haze
-- in every direction. Not reachable (the grid's outer street walls close it
-- in), so nothing collides.
local function buildSkyline(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Skyline"
	folder.Parent = parent
	local inner = 20 + AVENUE_EDGE + ROW_DEPTH
	local left = CityConfig.GRID_LEFT_X - inner
	local right = CityConfig.GRID_RIGHT_X + inner
	local top = CityConfig.GRID_TOP_Z + CROSS_EDGE + ROW_DEPTH + 20
	local bottom = CityConfig.GRID_BOTTOM_Z - CROSS_EDGE - ROW_DEPTH - 20

	-- Only the side facing into the city gets windows; nobody sees the rest.
	local function fillStrip(x1: number, x2: number, z1: number, z2: number, alongX: boolean, face: Enum.NormalId)
		local cursor = if alongX then x1 else z1
		local finish = if alongX then x2 else z2
		while cursor < finish do
			local width = math.random(30, 48)
			local height = math.random(60, 200)
			local center, size
			if alongX then
				center = Vector3.new(cursor + width / 2, height / 2, (z1 + z2) / 2)
				size = Vector3.new(width - 3, height, z2 - z1)
			else
				center = Vector3.new((x1 + x2) / 2, height / 2, cursor + width / 2)
				size = Vector3.new(x2 - x1, height, width - 3)
			end
			backdropTower(folder, "SkylineTower", center, size, false, 1600, { face })
			cursor += width
		end
	end

	fillStrip(left - 60, left, bottom - 60, top + 60, false, Enum.NormalId.Right)
	fillStrip(right, right + 60, bottom - 60, top + 60, false, Enum.NormalId.Left)
	fillStrip(left, right, top, top + 60, true, Enum.NormalId.Front)
	fillStrip(left, right, bottom - 60, bottom, true, Enum.NormalId.Back)
end

-- ===== Entry point =====

function DistrictBuilder.build(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "District"
	folder.Parent = parent

	local lots = Instance.new("Folder")
	lots.Name = "Places"
	lots.Parent = folder
	buildLots(lots)

	local rows = Instance.new("Folder")
	rows.Name = "Buildings"
	rows.Parent = folder
	buildAvenueRows(rows)
	buildCrossRows(rows)

	buildBlockMiddles(folder)
	buildSkyline(folder)
end

return DistrictBuilder
