-- Twelve floors up in Quarry Houses: Vance's mother's flat, where chapter
-- 9's cutscene happens (see LateScenes' flat), and the stairwell the
-- driver and Teddy run down after. Like the chapel, sealed sets under the
-- street (CityConfig.FLAT_ORIGIN, STAIRS_ORIGIN), only ever seen through the
-- cutscene's camera.
--
-- The flat: an old lady's front room. Patterned wallpaper, a brown carpet,
-- a three-piece suite with lace on the arms, a standard lamp, a television,
-- a carriage clock -- and on the sideboard against the back wall, in a
-- silver frame, the family photograph: her, and her son Vance, and his two
-- children. A window over the city; the kitchen through a door on the
-- right. The front door's at the back left, where the camera comes in.
--
-- No people: whoever's in the scene is put here by StoryService (the
-- `cast` of a scene step) and moved on the player's screen.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))
local StoryConfig = require(Shared:WaitForChild("StoryConfig"))

local FlatBuilder = {}

local HALF_X, HALF_Z, HEIGHT = 9, 7, 9
local WALLPAPER = Color3.fromRGB(150, 128, 96)
local SKIRTING = Color3.fromRGB(70, 50, 36)
local WOOD = Color3.fromRGB(86, 58, 38)

local o = CityConfig.FLAT_ORIGIN
local FLOOR = o.Y + 0.5

local function at(x: number, y: number, z: number): Vector3
	return Vector3.new(o.X + x, FLOOR + y, o.Z + z)
end

local function part(root: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = root
	return p
end

local function glow(p: BasePart, color: Color3, brightness: number, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = p
end

-- A wall along X or Z with a doorway cut in it (`door` = { from, to } along
-- the wall, in the wall's own run), built as the pieces either side and a
-- lintel above.
local function wall(root: Instance, name: string, from: Vector3, to: Vector3, door: { number }?)
	local along = to - from
	local length = along.Magnitude
	local dir = along.Unit
	local function piece(a: number, b: number, y0: number, y1: number)
		if b - a <= 0.01 or y1 - y0 <= 0.01 then
			return
		end
		local mid = from + dir * ((a + b) / 2)
		local size = if math.abs(dir.X) > 0.5 then Vector3.new(b - a, y1 - y0, 0.6) else Vector3.new(0.6, y1 - y0, b - a)
		part(root, name, size, CFrame.new(Vector3.new(mid.X, FLOOR + (y0 + y1) / 2, mid.Z)), WALLPAPER, Enum.Material.Fabric)
		-- The skirting board along the bottom.
		if y0 == 0 then
			local skirtSize = if math.abs(dir.X) > 0.5 then Vector3.new(b - a, 0.5, 0.7) else Vector3.new(0.7, 0.5, b - a)
			part(root, name .. "Skirting", skirtSize, CFrame.new(Vector3.new(mid.X, FLOOR + 0.25, mid.Z)), SKIRTING, Enum.Material.Wood)
		end
	end
	if door then
		piece(0, door[1], 0, HEIGHT)
		piece(door[2], length, 0, HEIGHT)
		piece(door[1], door[2], 7, HEIGHT)
	else
		piece(0, length, 0, HEIGHT)
	end
end

local function buildRoom(root: Instance)
	part(root, "Floor", Vector3.new(HALF_X * 2 + 1, 1, HALF_Z * 2 + 1), CFrame.new(o), Color3.fromRGB(96, 70, 52), Enum.Material.Carpet)
	part(root, "Ceiling", Vector3.new(HALF_X * 2 + 1, 1, HALF_Z * 2 + 1), CFrame.new(at(0, HEIGHT + 0.5, 0)), Color3.fromRGB(196, 188, 170))
	-- Front wall (-Z): the front door near the -X end.
	wall(root, "WallFront", Vector3.new(o.X - HALF_X, 0, o.Z - HALF_Z), Vector3.new(o.X + HALF_X, 0, o.Z - HALF_Z), { 2.5, 6.5 })
	wall(root, "WallBack", Vector3.new(o.X - HALF_X, 0, o.Z + HALF_Z), Vector3.new(o.X + HALF_X, 0, o.Z + HALF_Z), nil)
	-- Right wall (+X): the kitchen door, middle.
	wall(root, "WallRight", Vector3.new(o.X + HALF_X, 0, o.Z - HALF_Z), Vector3.new(o.X + HALF_X, 0, o.Z + HALF_Z), { 5.2, 8.8 })
	-- Left wall (-X): the window, built separately below.
	wall(root, "WallLeft", Vector3.new(o.X - HALF_X, 0, o.Z - HALF_Z), Vector3.new(o.X - HALF_X, 0, o.Z - 3), nil)
	wall(root, "WallLeft", Vector3.new(o.X - HALF_X, 0, o.Z + 3), Vector3.new(o.X - HALF_X, 0, o.Z + HALF_Z), nil)
	part(root, "WallLeftLow", Vector3.new(0.6, 3, 6), CFrame.new(at(-HALF_X, 1.5, 0)), WALLPAPER, Enum.Material.Fabric)
	part(root, "WallLeftHigh", Vector3.new(0.6, 2, 6), CFrame.new(at(-HALF_X, HEIGHT - 1, 0)), WALLPAPER, Enum.Material.Fabric)

	-- The window: the city at night, twelve floors down -- a dark pane with
	-- lit specks -- and net curtains.
	local night = part(root, "Night", Vector3.new(0.2, 4, 6), CFrame.new(at(-HALF_X - 0.6, 5, 0)), Color3.fromRGB(14, 16, 26), Enum.Material.SmoothPlastic)
	local random = Random.new(12)
	for _ = 1, 26 do
		local speck = part(root, "CityLight", Vector3.new(0.1, 0.12, 0.12), CFrame.new(night.Position + Vector3.new(0.12, random:NextNumber(-1.8, 0.6), random:NextNumber(-2.8, 2.8))), if random:NextNumber() < 0.7 then Color3.fromRGB(255, 210, 140) else Color3.fromRGB(150, 200, 255), Enum.Material.Neon)
		speck.Name = "CityLight"
	end
	part(root, "Sill", Vector3.new(0.9, 0.25, 6.6), CFrame.new(at(-HALF_X + 0.3, 3.05, 0)), Color3.fromRGB(220, 214, 200), Enum.Material.Wood)
	for _, dz in { -2.2, 2.2 } do
		local curtain = part(root, "NetCurtain", Vector3.new(0.1, 4.2, 1.8), CFrame.new(at(-HALF_X + 0.45, 5.05, dz)), Color3.fromRGB(236, 230, 214), Enum.Material.Fabric)
		curtain.Transparency = 0.3
	end

	-- The front door, standing open into the hallway (dark), and the
	-- kitchen beyond its door (a strip light, tiles).
	part(root, "FrontDoor", Vector3.new(0.25, 7, 3.9), CFrame.new(at(-HALF_X + 2.5 + 0.2, 3.5, -HALF_Z - 1.95)) * CFrame.Angles(0, math.rad(-10), 0), Color3.fromRGB(110, 40, 34), Enum.Material.Wood)
	part(root, "Hallway", Vector3.new(6, 9, 0.4), CFrame.new(at(-4.5, 4.5, -HALF_Z - 5)), Color3.fromRGB(40, 38, 36), Enum.Material.Concrete)
	part(root, "HallFloor", Vector3.new(6, 1, 5), CFrame.new(at(-4.5, -0.5, -HALF_Z - 2.5)), Color3.fromRGB(70, 66, 60), Enum.Material.Concrete)
	part(root, "Kitchen", Vector3.new(0.4, 9, 8), CFrame.new(at(HALF_X + 5, 4.5, 0)), Color3.fromRGB(206, 212, 200), Enum.Material.Marble)
	part(root, "KitchenFloor", Vector3.new(5, 1, 8), CFrame.new(at(HALF_X + 2.6, -0.5, 0)), Color3.fromRGB(180, 176, 160), Enum.Material.Marble)
	local strip = part(root, "KitchenLight", Vector3.new(2.6, 0.2, 0.4), CFrame.new(at(HALF_X + 3, 8.6, 0)), Color3.fromRGB(230, 240, 255), Enum.Material.Neon)
	glow(strip, Color3.fromRGB(220, 235, 255), 0.8, 10)
end

-- The front room's things.
local function buildFurniture(root: Instance)
	-- A big rug.
	part(root, "Rug", Vector3.new(9, 0.06, 7), CFrame.new(at(-0.5, 0.03, -0.5)), Color3.fromRGB(120, 40, 36), Enum.Material.Fabric)
	-- The settee under the window wall, facing the television, and an
	-- armchair; lace antimacassars on their backs.
	local sofa = Color3.fromRGB(96, 110, 70)
	part(root, "SofaSeat", Vector3.new(2.4, 1.5, 6), CFrame.new(at(-6.7, 0.75, 0)), sofa, Enum.Material.Fabric)
	part(root, "SofaBack", Vector3.new(0.9, 2.8, 6), CFrame.new(at(-7.9, 1.4, 0)), sofa, Enum.Material.Fabric)
	for _, dz in { -3.2, 3.2 } do
		part(root, "SofaArm", Vector3.new(2.6, 2.1, 0.6), CFrame.new(at(-6.8, 1.05, dz)), sofa, Enum.Material.Fabric)
	end
	part(root, "Lace", Vector3.new(0.95, 0.9, 1.4), CFrame.new(at(-7.85, 2.5, 1.2)), Color3.fromRGB(240, 236, 226), Enum.Material.Fabric)
	part(root, "Lace", Vector3.new(0.95, 0.9, 1.4), CFrame.new(at(-7.85, 2.5, -1.2)), Color3.fromRGB(240, 236, 226), Enum.Material.Fabric)
	part(root, "ArmchairSeat", Vector3.new(2.6, 1.5, 2.6), CFrame.new(at(-2.5, 0.75, -4.6)) * CFrame.Angles(0, math.rad(30), 0), sofa, Enum.Material.Fabric)
	part(root, "ArmchairBack", Vector3.new(2.6, 2.8, 0.8), CFrame.new(at(-2.9, 1.4, -5.5)) * CFrame.Angles(0, math.rad(30), 0), sofa, Enum.Material.Fabric)
	-- A coffee table with a doily and a fruit bowl.
	part(root, "CoffeeTable", Vector3.new(2.2, 0.2, 3.6), CFrame.new(at(-3.4, 1.4, 0)), WOOD, Enum.Material.Wood)
	for _, dx in { -0.9, 0.9 } do
		for _, dz in { -1.6, 1.6 } do
			part(root, "TableLeg", Vector3.new(0.15, 1.3, 0.15), CFrame.new(at(-3.4 + dx, 0.65, dz)), WOOD, Enum.Material.Wood)
		end
	end
	local bowl = part(root, "FruitBowl", Vector3.new(0.4, 1.2, 1.2), CFrame.new(at(-3.4, 1.7, 0.6)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 196, 186), Enum.Material.Glass)
	bowl.Shape = Enum.PartType.Cylinder
	-- The television on a stand by the kitchen wall, off.
	part(root, "TvStand", Vector3.new(2, 1.6, 3), CFrame.new(at(7.6, 0.8, -4)), WOOD, Enum.Material.Wood)
	part(root, "Television", Vector3.new(2.2, 2.2, 2.8), CFrame.new(at(7.6, 2.7, -4)), Color3.fromRGB(60, 50, 40), Enum.Material.Wood)
	part(root, "Screen", Vector3.new(0.1, 1.6, 2.1), CFrame.new(at(6.48, 2.75, -4)), Color3.fromRGB(26, 30, 30), Enum.Material.Glass)
	-- A standard lamp in the corner: the room's warm light.
	part(root, "LampStand", Vector3.new(0.2, 5.4, 0.2), CFrame.new(at(-7.6, 2.7, 5.6)), Color3.fromRGB(160, 130, 70), Enum.Material.Metal)
	local shade = part(root, "LampShade", Vector3.new(1.4, 1.2, 1.4), CFrame.new(at(-7.6, 5.8, 5.6)), Color3.fromRGB(240, 200, 140), Enum.Material.Neon)
	shade.Transparency = 0.15
	glow(shade, Color3.fromRGB(255, 200, 140), 1.4, 18)
	-- And a ceiling light, low.
	local bulb = part(root, "CeilingShade", Vector3.new(1.6, 0.6, 1.6), CFrame.new(at(0, HEIGHT - 0.6, 0)), Color3.fromRGB(250, 226, 180), Enum.Material.Neon)
	bulb.Transparency = 0.25
	glow(bulb, Color3.fromRGB(255, 220, 170), 0.9, 20)
	-- Pictures on the walls: little framed landscapes, a crucifix, a
	-- calendar from the butcher's.
	local frames = {
		{ at(-3, 6, HALF_Z - 0.35), Vector3.new(1.6, 1.2, 0.1), Color3.fromRGB(120, 140, 90) },
		{ at(-6, 5.5, HALF_Z - 0.35), Vector3.new(1, 1.4, 0.1), Color3.fromRGB(110, 120, 150) },
		{ at(5.5, 5.8, HALF_Z - 0.35), Vector3.new(1.2, 1.6, 0.1), Color3.fromRGB(210, 190, 150) },
	}
	for _, f in frames do
		part(root, "PictureFrame", f[2] + Vector3.new(0.25, 0.25, 0), CFrame.new(f[1]), Color3.fromRGB(150, 120, 60), Enum.Material.Wood)
		part(root, "Picture", f[2], CFrame.new(f[1] - Vector3.new(0, 0, 0.07)), f[3])
	end
	part(root, "Crucifix", Vector3.new(0.12, 1.1, 0.08), CFrame.new(at(1.5, 7.2, HALF_Z - 0.35)), Color3.fromRGB(80, 60, 40), Enum.Material.Wood)
	part(root, "Crucifix", Vector3.new(0.6, 0.12, 0.08), CFrame.new(at(1.5, 7.45, HALF_Z - 0.35)), Color3.fromRGB(80, 60, 40), Enum.Material.Wood)
	-- Birthday cards stood up along the window sill: it's her birthday.
	for i = 1, 5 do
		local card = part(root, "BirthdayCard", Vector3.new(0.05, 0.6, 0.45), CFrame.new(at(-HALF_X + 0.45, 3.45, -2.4 + i * 0.85)) * CFrame.Angles(0, 0, math.rad(-8)), ({ Color3.fromRGB(230, 150, 170), Color3.fromRGB(150, 190, 230), Color3.fromRGB(240, 220, 120), Color3.fromRGB(180, 220, 160), Color3.fromRGB(240, 236, 226) })[i])
		card.Name = "BirthdayCard"
	end
end

-- The sideboard against the back wall, and on it the family photograph in a
-- silver frame: Vance's mother in the middle, Vance stood behind her, his
-- two children either side. Flat-painted shapes, like Gil's photograph at
-- the chapel (see ChapelBuilder: a ViewportFrame on a part never drew).
local function buildSideboard(root: Instance)
	part(root, "Sideboard", Vector3.new(6, 2.8, 1.6), CFrame.new(at(3, 1.4, HALF_Z - 1.1)), WOOD, Enum.Material.Wood)
	part(root, "SideboardTop", Vector3.new(6.3, 0.15, 1.8), CFrame.new(at(3, 2.87, HALF_Z - 1.1)), Color3.fromRGB(100, 70, 46), Enum.Material.Wood)
	part(root, "Doily", Vector3.new(2.2, 0.03, 1.2), CFrame.new(at(3, 2.96, HALF_Z - 1.1)), Color3.fromRGB(240, 236, 226), Enum.Material.Fabric)
	-- A carriage clock, a vase of carnations.
	part(root, "Clock", Vector3.new(0.7, 0.9, 0.45), CFrame.new(at(5.2, 3.4, HALF_Z - 1.1)), Color3.fromRGB(190, 160, 80), Enum.Material.Metal)
	part(root, "Vase", Vector3.new(0.5, 1, 0.5), CFrame.new(at(1, 3.45, HALF_Z - 1.1)), Color3.fromRGB(60, 90, 130), Enum.Material.Glass)
	for i = 1, 5 do
		local bloom = part(root, "Carnation", Vector3.new(0.35, 0.35, 0.35), CFrame.new(at(1 + (i - 3) * 0.16, 4.1 + (i % 2) * 0.2, HALF_Z - 1.1 + ((i % 3) - 1) * 0.12)), Color3.fromRGB(220, 60, 90))
		bloom.Shape = Enum.PartType.Ball
	end

	-- The photograph, propped up, tipped back a little.
	local photoAt = CFrame.new(at(3, 3.95, HALF_Z - 1.3)) * CFrame.Angles(math.rad(8), math.pi, 0)
	part(root, "PhotoFrame", Vector3.new(2.3, 1.85, 0.12), photoAt, Color3.fromRGB(196, 198, 204), Enum.Material.Metal).Reflectance = 0.2
	local photo = part(root, "FamilyPhoto", Vector3.new(2.0, 1.55, 0.05), photoAt * CFrame.new(0, 0, 0.07), Color3.fromRGB(40, 40, 44))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 120
	gui.LightInfluence = 0.2
	gui.Brightness = 1.1
	gui.Parent = photo
	local function shape(name: string, color: Color3, size: UDim2, position: UDim2, round: number?)
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = size
		f.Position = position
		if round then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(round, 0)
			corner.Parent = f
		end
		f.Parent = gui
	end
	-- A studio's mottled blue, then the four of them.
	shape("Backdrop", Color3.fromRGB(110, 130, 160), UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5))
	local vance = StoryConfig.CHARACTERS.vance.look
	-- Vance, standing at the back.
	shape("VanceBody", vance.shirt, UDim2.fromScale(0.3, 0.42), UDim2.fromScale(0.5, 0.62), 0.2)
	shape("VanceHead", vance.skin, UDim2.fromScale(0.16, 0.26), UDim2.fromScale(0.5, 0.3), 0.2)
	shape("VanceHair", Color3.fromRGB(40, 32, 28), UDim2.fromScale(0.17, 0.07), UDim2.fromScale(0.5, 0.19), 0.4)
	-- His mother, sat in front of him, grey-haired, in her good blue dress.
	shape("MotherBody", Color3.fromRGB(70, 90, 140), UDim2.fromScale(0.3, 0.34), UDim2.fromScale(0.5, 0.86), 0.25)
	shape("MotherHead", vance.skin, UDim2.fromScale(0.15, 0.23), UDim2.fromScale(0.5, 0.6), 0.25)
	shape("MotherHair", Color3.fromRGB(200, 200, 204), UDim2.fromScale(0.17, 0.08), UDim2.fromScale(0.5, 0.5), 0.5)
	-- The two children either side.
	for _, x in { 0.24, 0.76 } do
		shape("ChildBody", if x < 0.5 then Color3.fromRGB(180, 50, 60) else Color3.fromRGB(230, 200, 90), UDim2.fromScale(0.17, 0.26), UDim2.fromScale(x, 0.9), 0.25)
		shape("ChildHead", vance.skin, UDim2.fromScale(0.11, 0.17), UDim2.fromScale(x, 0.7), 0.3)
		shape("ChildHair", Color3.fromRGB(40, 32, 28), UDim2.fromScale(0.12, 0.05), UDim2.fromScale(x, 0.62), 0.5)
	end
	-- Faces: two dots and a smile each, the way you'd sketch a snapshot.
	for _, face in { { 0.5, 0.3, 0.16 }, { 0.5, 0.6, 0.15 }, { 0.24, 0.7, 0.11 }, { 0.76, 0.7, 0.11 } } do
		for _, dx in { -0.22, 0.22 } do
			shape("Eye", Color3.fromRGB(20, 18, 18), UDim2.fromScale(0.012, 0.02), UDim2.fromScale(face[1] + dx * face[3], face[2] - 0.02), 1)
		end
		shape("Smile", Color3.fromRGB(80, 40, 36), UDim2.fromScale(face[3] * 0.35, 0.012), UDim2.fromScale(face[1], face[2] + 0.05), 1)
	end
end

-- The stairwell: three flights down, concrete, a caged bulb on each
-- landing, the floor number painted on the wall. Each flight drops 9 studs
-- along +Z, the next one back along -Z, and so on.
local function buildStairs(root: Instance)
	local s = CityConfig.STAIRS_ORIGIN
	local concrete = Color3.fromRGB(150, 148, 140)
	local paint = Color3.fromRGB(140, 160, 150)
	local levels = 3
	local rise = 9
	local run = 12
	for level = 0, levels do
		local y = s.Y + 0.5 - level * rise
		-- Landings at either end.
		local z0 = if level % 2 == 0 then s.Z - 3 else s.Z + run + 3
		part(root, "Landing", Vector3.new(8, 1, 5), CFrame.new(Vector3.new(s.X, y - 0.5, z0)), concrete, Enum.Material.Concrete)
		local bulb = part(root, "CagedBulb", Vector3.new(0.6, 0.6, 0.6), CFrame.new(Vector3.new(s.X - 3.6, y + 7.5, z0)), Color3.fromRGB(255, 226, 170), Enum.Material.Neon)
		glow(bulb, Color3.fromRGB(255, 214, 150), 1.4, 16)
		local number = part(root, "FloorNumber", Vector3.new(0.1, 2, 2), CFrame.new(Vector3.new(s.X - 4.1, y + 4, z0)), paint)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Right
		gui.PixelsPerStud = 60
		gui.LightInfluence = 0.6
		gui.Parent = number
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Font = Enum.Font.GothamBlack
		l.TextScaled = true
		l.TextColor3 = Color3.fromRGB(230, 226, 210)
		l.Text = tostring(12 - level)
		l.Parent = gui
		if level < levels then
			-- The flight down to the next landing, one part per step.
			local steps = 12
			for k = 0, steps - 1 do
				local t = (k + 0.5) / steps
				local z = if level % 2 == 0 then s.Z - 0.5 + t * run else s.Z + run + 0.5 - t * run
				local x = if level % 2 == 0 then s.X - 2 else s.X + 2
				part(root, "Step", Vector3.new(3.8, rise / steps, run / steps + 0.05), CFrame.new(Vector3.new(x, y - (k + 0.5) * rise / steps - rise / steps / 2, z)), concrete, Enum.Material.Concrete)
			end
			-- The handrail down the middle.
			part(root, "Handrail", Vector3.new(0.2, 0.2, math.sqrt(run * run + rise * rise)), CFrame.lookAt(Vector3.new(s.X, y + 2.6, if level % 2 == 0 then s.Z - 0.5 else s.Z + run + 0.5), Vector3.new(s.X, y + 2.6 - rise, if level % 2 == 0 then s.Z + run - 0.5 else s.Z + 0.5)), Color3.fromRGB(150, 40, 36), Enum.Material.Metal)
		end
	end
	-- The shaft's walls, floor to top.
	local bottom = s.Y - levels * rise - 1
	local tall = levels * rise + 12
	for _, w in { { Vector3.new(-4.3, 0, run / 2), Vector3.new(0.6, tall, run + 12) }, { Vector3.new(4.3, 0, run / 2), Vector3.new(0.6, tall, run + 12) }, { Vector3.new(0, 0, -5.8), Vector3.new(9, tall, 0.6) }, { Vector3.new(0, 0, run + 5.8), Vector3.new(9, tall, 0.6) } } do
		part(root, "ShaftWall", w[2], CFrame.new(Vector3.new(s.X, bottom + tall / 2, s.Z) + w[1]), paint, Enum.Material.Concrete)
	end
end

function FlatBuilder.build()
	-- Always sent to every player in full (see ChapelBuilder): a long way
	-- under the cab, and the scene cuts straight in.
	local model = Instance.new("Model")
	model.Name = "FlatInterior"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = workspace
	buildRoom(model)
	buildFurniture(model)
	buildSideboard(model)
	buildStairs(model)
end

-- Where people stand in the flat, for the scene's cast and cameras (see
-- StoryService and LateScenes): ground points, and which way they face.
function FlatBuilder.spot(name: string): CFrame
	local spots = {
		-- Teddy at the sideboard, looking at the photograph.
		photo = CFrame.lookAt(at(3, 0, HALF_Z - 3.1), at(3, 0, HALF_Z)),
		-- The man, in the kitchen doorway, out of sight of the front door.
		kitchen = CFrame.lookAt(at(HALF_X + 1.6, 0, 1), at(0, 0, 1)),
	}
	return spots[name]
end

return FlatBuilder
