-- Inside Larkin & Sons, the funeral chapel on Calloway: the room chapter 6's
-- cutscene plays in (see StoryScenes' funeral). Like the gun store, it's a
-- sealed set under the street (CityConfig.CHAPEL_ORIGIN, right below the
-- chapel), only ever seen through the cutscene's camera.
--
-- A plain, warm room for an evening service: dark wood below, cream walls,
-- six rows of pews either side of a red aisle runner, a low platform at the
-- front with the casket on its stand, flowers, candles, Gil's photograph on
-- an easel, a lectern -- and an upright piano against the right-hand wall.
-- Coloured glass panels light the front wall.
--
-- The people are real character rigs, pinned in place: the mourners sat in
-- the pews, the minister at the lectern, Nina (Gil's daughter) in the front
-- row waiting to play, and Teddy, Gil's old friend, a couple of rows in
-- front of where the player will sit. Everything they do in the scene
-- (Nina walking up and playing, Teddy kneeling by the player) is moved on
-- the player's own screen by StoryScenes; this only sets them out.
--
-- Doors at -Z, the front at +Z, the aisle down X = 0 (see CityConfig).

local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))
local StoryConfig = require(Shared:WaitForChild("StoryConfig"))
local Joints = require(Shared:WaitForChild("Joints"))

local ChapelBuilder = {}

local HALF_X, HALF_Z, HEIGHT = 11, 17, 14
local DAIS_FROM, DAIS_HEIGHT = 9.5, 0.8
-- Pew rows (Z of each seat's middle), front to back, and the seat height.
ChapelBuilder.ROWS = { 3.5, 0.5, -2.5, -5.5, -8.5, -11.5 }
local SEAT_TOP = 1.75

local DARK_WOOD = Color3.fromRGB(70, 46, 30)
local PEW_WOOD = Color3.fromRGB(96, 62, 38)
local PLASTER = Color3.fromRGB(196, 184, 160)
local BRASS = Color3.fromRGB(190, 158, 80)

local o = CityConfig.CHAPEL_ORIGIN
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

local function label(p: BasePart, face: Enum.NormalId, text: string, color: Color3, font: Enum.Font?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0.6
	gui.Parent = p
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = font or Enum.Font.Garamond
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	l.Parent = gui
end

-- ===== The room =====

local function buildRoom(root: Instance)
	part(root, "Floor", Vector3.new(HALF_X * 2, 1, HALF_Z * 2), CFrame.new(o), Color3.fromRGB(64, 46, 34), Enum.Material.WoodPlanks)
	part(root, "Ceiling", Vector3.new(HALF_X * 2, 1, HALF_Z * 2), CFrame.new(at(0, HEIGHT, 0)), Color3.fromRGB(120, 108, 92), Enum.Material.Wood)
	for z = -HALF_Z + 3, HALF_Z - 3, 5 do
		part(root, "Beam", Vector3.new(HALF_X * 2, 0.8, 0.8), CFrame.new(at(0, HEIGHT - 0.9, z)), DARK_WOOD, Enum.Material.Wood)
	end
	local walls = {
		{ "WallBack", Vector3.new(HALF_X * 2, 0, 0.6), Vector3.new(0, 0, -HALF_Z) },
		{ "WallFront", Vector3.new(HALF_X * 2, 0, 0.6), Vector3.new(0, 0, HALF_Z) },
		{ "WallLeft", Vector3.new(0.6, 0, HALF_Z * 2), Vector3.new(-HALF_X, 0, 0) },
		{ "WallRight", Vector3.new(0.6, 0, HALF_Z * 2), Vector3.new(HALF_X, 0, 0) },
	}
	for _, w in walls do
		local size, offset = w[2], w[3]
		part(root, w[1] .. "Lower", Vector3.new(size.X, 4, size.Z), CFrame.new(at(offset.X, 2, offset.Z)), DARK_WOOD, Enum.Material.WoodPlanks)
		part(root, w[1] .. "Upper", Vector3.new(size.X, HEIGHT - 4, size.Z), CFrame.new(at(offset.X, 4 + (HEIGHT - 4) / 2, offset.Z)), PLASTER)
	end
	-- The aisle runner.
	part(root, "Runner", Vector3.new(3.4, 0.06, HALF_Z * 2 - 2), CFrame.new(at(0, 0.03, -1)), Color3.fromRGB(110, 24, 28), Enum.Material.Fabric)

	-- Wall sconces down both sides, low and warm.
	for _, x in { -HALF_X + 0.5, HALF_X - 0.5 } do
		for z = -12, 8, 10 do
			local sconce = part(root, "Sconce", Vector3.new(0.4, 0.8, 0.6), CFrame.new(at(x, 7, z)), Color3.fromRGB(255, 214, 160), Enum.Material.Neon)
			glow(sconce, Color3.fromRGB(255, 196, 130), 0.9, 14)
		end
	end
	-- The doors at the back (we're inside now, so they're closed).
	for _, dx in { -1.4, 1.4 } do
		part(root, "Door", Vector3.new(2.6, 7, 0.3), CFrame.new(at(dx, 3.5, -HALF_Z + 0.4)), Color3.fromRGB(56, 36, 24), Enum.Material.Wood)
	end
end

-- Coloured glass on the front wall, lit from behind: three tall panels.
local function buildGlass(root: Instance)
	local colours = { Color3.fromRGB(40, 70, 150), Color3.fromRGB(190, 130, 50), Color3.fromRGB(130, 30, 40) }
	for i, x in { -5, 0, 5 } do
		local c = colours[(i % 3) + 1]
		local pane = part(root, "Glass", Vector3.new(3, 7, 0.2), CFrame.new(at(x, 7.5, HALF_Z - 0.4)), c, Enum.Material.Neon)
		pane.Transparency = 0.35
		for _, y in { 5.5, 7.5, 9.5 } do
			part(root, "Leading", Vector3.new(3.1, 0.12, 0.25), CFrame.new(at(x, y, HALF_Z - 0.45)), Color3.fromRGB(30, 30, 32), Enum.Material.Metal)
		end
		part(root, "Leading", Vector3.new(0.12, 7, 0.25), CFrame.new(at(x, 7.5, HALF_Z - 0.45)), Color3.fromRGB(30, 30, 32), Enum.Material.Metal)
	end
end

-- ===== Pews =====

local function pew(root: Instance, xCenter: number, z: number)
	local length = 7
	part(root, "PewSeat", Vector3.new(length, 0.3, 1.5), CFrame.new(at(xCenter, SEAT_TOP - 0.15, z)), PEW_WOOD, Enum.Material.Wood)
	part(root, "PewBack", Vector3.new(length, 2.2, 0.3), CFrame.new(at(xCenter, SEAT_TOP + 1.0, z - 0.85)) * CFrame.Angles(math.rad(-8), 0, 0), PEW_WOOD, Enum.Material.Wood)
	for _, dx in { -length / 2, length / 2 } do
		part(root, "PewEnd", Vector3.new(0.3, 3.4, 1.9), CFrame.new(at(xCenter + dx, 1.7, z - 0.2)), DARK_WOOD, Enum.Material.Wood)
	end
	-- The front of the seat down to the floor, so legs in the row behind
	-- don't show through.
	part(root, "PewFront", Vector3.new(length, SEAT_TOP - 0.3, 0.2), CFrame.new(at(xCenter, (SEAT_TOP - 0.3) / 2, z + 0.65)), DARK_WOOD, Enum.Material.Wood)
end

local function buildPews(root: Instance)
	for _, z in ChapelBuilder.ROWS do
		pew(root, -6, z)
		pew(root, 6, z)
	end
end

-- ===== The front =====

local function buildFront(root: Instance)
	local daisDepth = HALF_Z - DAIS_FROM
	part(root, "Dais", Vector3.new(HALF_X * 2 - 1, DAIS_HEIGHT, daisDepth), CFrame.new(at(0, DAIS_HEIGHT / 2, DAIS_FROM + daisDepth / 2)), Color3.fromRGB(84, 58, 40), Enum.Material.WoodPlanks)
	local d = DAIS_HEIGHT

	-- The casket, side-on to the room, on a draped stand.
	part(root, "CasketStand", Vector3.new(6.6, 1.6, 2.4), CFrame.new(at(0, d + 0.8, 13.5)), Color3.fromRGB(40, 30, 34), Enum.Material.Fabric)
	part(root, "Casket", Vector3.new(7, 1.8, 2.6), CFrame.new(at(0, d + 2.5, 13.5)), Color3.fromRGB(58, 30, 22), Enum.Material.Wood).Reflectance = 0.12
	part(root, "CasketLid", Vector3.new(7.1, 0.35, 2.7), CFrame.new(at(0, d + 3.55, 13.5)), Color3.fromRGB(66, 34, 24), Enum.Material.Wood).Reflectance = 0.12
	for _, x in { -2.6, 0, 2.6 } do
		part(root, "Handle", Vector3.new(1.2, 0.15, 0.15), CFrame.new(at(x, d + 2.4, 12.15)), BRASS, Enum.Material.Metal)
	end
	-- A spray of flowers on the lid.
	local random = Random.new(9)
	local flowerColours = { Color3.fromRGB(240, 238, 230), Color3.fromRGB(200, 40, 50), Color3.fromRGB(240, 238, 230), Color3.fromRGB(235, 190, 200) }
	for i = 1, 26 do
		local f = part(root, "Flower", Vector3.new(0.5, 0.5, 0.5), CFrame.new(at(random:NextNumber(-1.6, 1.6), d + 3.9 + random:NextNumber(0, 0.4), 13.5 + random:NextNumber(-0.7, 0.7))), flowerColours[(i % #flowerColours) + 1], Enum.Material.SmoothPlastic)
		f.Shape = Enum.PartType.Ball
	end
	for i = 1, 14 do
		local leaf = part(root, "Leaf", Vector3.new(0.9, 0.12, 0.4), CFrame.new(at(random:NextNumber(-2.2, 2.2), d + 3.8, 13.5 + random:NextNumber(-0.9, 0.9))) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0), Color3.fromRGB(40, 80, 40), Enum.Material.Grass)
		leaf.Name = "Leaf" .. i
	end

	-- Tall candle stands either end of the casket.
	for _, x in { -4.6, 4.6 } do
		part(root, "CandleStand", Vector3.new(0.3, 4.2, 0.3), CFrame.new(at(x, d + 2.1, 13.5)), BRASS, Enum.Material.Metal)
		part(root, "Candle", Vector3.new(0.35, 1.1, 0.35), CFrame.new(at(x, d + 4.75, 13.5)), Color3.fromRGB(240, 232, 210), Enum.Material.SmoothPlastic)
		local flame = part(root, "Flame", Vector3.new(0.18, 0.35, 0.18), CFrame.new(at(x, d + 5.5, 13.5)), Color3.fromRGB(255, 200, 110), Enum.Material.Neon)
		glow(flame, Color3.fromRGB(255, 180, 100), 1.6, 12)
	end
	-- Banks of flowers at the foot of the stand.
	for i = 1, 30 do
		local f = part(root, "FloorFlower", Vector3.new(0.6, 0.6, 0.6), CFrame.new(at(random:NextNumber(-3.5, 3.5), d + 0.3 + random:NextNumber(0, 0.6), 11.6 + random:NextNumber(-0.4, 0.4))), flowerColours[(i % #flowerColours) + 1])
		f.Shape = Enum.PartType.Ball
	end

	-- The lectern, front left.
	part(root, "Lectern", Vector3.new(1.6, 3.4, 1.2), CFrame.new(at(-4, d + 1.7, 10.6)), DARK_WOOD, Enum.Material.Wood)
	part(root, "LecternTop", Vector3.new(1.9, 0.2, 1.4), CFrame.new(at(-4, d + 3.5, 10.5)) * CFrame.Angles(math.rad(-15), 0, 0), DARK_WOOD, Enum.Material.Wood)
	local lamp = part(root, "LecternLamp", Vector3.new(0.6, 0.15, 0.25), CFrame.new(at(-4, d + 3.75, 10.9)), Color3.fromRGB(255, 226, 170), Enum.Material.Neon)
	glow(lamp, Color3.fromRGB(255, 220, 160), 0.8, 6)
end

-- Gil's photograph on an easel, front left of the casket: a flat, painted
-- head-and-shoulders portrait in his own colours, so it's him. (It was a
-- little 3D portrait -- a ViewportFrame with a rig in it -- but those never
-- drew on a part's surface: confirmed live, the photo stayed black while a
-- plain label on the same surface showed fine.)
local function buildPhoto(root: Instance)
	local d = DAIS_HEIGHT
	local base = at(-6.8, d, 11.8)
	for _, dx in { -0.8, 0.8 } do
		part(root, "EaselLeg", Vector3.new(0.15, 5.2, 0.15), CFrame.new(base + Vector3.new(dx, 2.6, 0.25)) * CFrame.Angles(math.rad(-6), 0, 0), DARK_WOOD, Enum.Material.Wood)
	end
	part(root, "EaselBack", Vector3.new(0.15, 5, 0.15), CFrame.new(base + Vector3.new(0, 2.5, 0.9)) * CFrame.Angles(math.rad(18), 0, 0), DARK_WOOD, Enum.Material.Wood)
	local frame = part(root, "PhotoFrame", Vector3.new(2.6, 3.2, 0.2), CFrame.new(base + Vector3.new(0, 3.9, 0)), Color3.fromRGB(150, 120, 60), Enum.Material.Wood)
	local photo = part(root, "Photo", Vector3.new(2.2, 2.8, 0.05), CFrame.new(base + Vector3.new(0, 3.9, -0.12)), Color3.fromRGB(40, 40, 44))

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	-- Lit from itself, not the room: by the room's candles alone it came
	-- out murky.
	gui.LightInfluence = 0.15
	gui.Brightness = 1.1
	gui.Parent = photo
	local look = StoryConfig.CHARACTERS.gil.look
	local function shape(name: string, color: Color3, size: UDim2, position: UDim2, round: number?): Frame
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
		return f
	end
	-- A studio backdrop, his shoulders and collar, his head, his face.
	shape("Backdrop", Color3.fromRGB(122, 134, 150), UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5))
	shape("Shoulders", look.shirt, UDim2.fromScale(0.86, 0.34), UDim2.fromScale(0.5, 0.86), 0.18)
	shape("Collar", Color3.fromRGB(222, 218, 206), UDim2.fromScale(0.2, 0.1), UDim2.fromScale(0.5, 0.7), 0.3)
	shape("Head", look.skin, UDim2.fromScale(0.5, 0.4), UDim2.fromScale(0.5, 0.42), 0.16)
	shape("Hair", Color3.fromRGB(58, 46, 38), UDim2.fromScale(0.52, 0.09), UDim2.fromScale(0.5, 0.24), 0.4)
	for _, x in { 0.41, 0.59 } do
		shape("Eye", Color3.fromRGB(20, 18, 18), UDim2.fromScale(0.05, 0.06), UDim2.fromScale(x, 0.4), 1)
	end
	shape("Mouth", Color3.fromRGB(70, 40, 36), UDim2.fromScale(0.16, 0.02), UDim2.fromScale(0.5, 0.52), 1)

	-- A small plate under it.
	local plate = part(root, "Nameplate", Vector3.new(2.2, 0.45, 0.05), CFrame.new(base + Vector3.new(0, 2.05, -0.1)), Color3.fromRGB(190, 160, 90), Enum.Material.Metal)
	label(plate, Enum.NormalId.Front, "GIL  ·  BELOVED FATHER", Color3.fromRGB(40, 30, 20))
	frame.Name = "PhotoFrame"
end

-- The upright piano against the right-hand wall, keyboard facing the
-- aisle (-X), with its bench. The keys are separate parts so the scene can
-- press them.
local function buildPiano(root: Instance)
	local piano = Instance.new("Model")
	piano.Name = "Piano"
	piano.Parent = root
	local black = Color3.fromRGB(22, 18, 18)
	part(piano, "PianoBody", Vector3.new(1.8, 4.4, 5.2), CFrame.new(at(9.6, 2.2, 7.5)), black, Enum.Material.SmoothPlastic).Reflectance = 0.15
	part(piano, "PianoShelf", Vector3.new(1, 0.3, 4.6), CFrame.new(at(8.25, 2.45, 7.5)), black, Enum.Material.SmoothPlastic).Reflectance = 0.15
	part(piano, "PianoFallboard", Vector3.new(0.15, 0.6, 4.6), CFrame.new(at(8.75, 2.95, 7.5)), black, Enum.Material.SmoothPlastic)
	part(piano, "PianoLeg", Vector3.new(0.3, 2.3, 0.3), CFrame.new(at(7.9, 1.15, 5.4)), black)
	part(piano, "PianoLeg", Vector3.new(0.3, 2.3, 0.3), CFrame.new(at(7.9, 1.15, 9.6)), black)
	-- Sheet music on the stand.
	part(piano, "SheetMusic", Vector3.new(0.05, 0.9, 1.4), CFrame.new(at(8.7, 3.6, 7.5)) * CFrame.Angles(0, 0, math.rad(-12)), Color3.fromRGB(240, 236, 222))
	-- The keys, along Z: white ones across the shelf, black ones between.
	local keys = Instance.new("Folder")
	keys.Name = "Keys"
	keys.Parent = piano
	local count = 22
	local span = 4.4
	for i = 0, count - 1 do
		local z = 7.5 - span / 2 + (i + 0.5) * (span / count)
		local key = part(keys, "Key", Vector3.new(0.7, 0.08, span / count - 0.02), CFrame.new(at(8.15, 2.64, z)), Color3.fromRGB(240, 236, 226))
		key:SetAttribute("Rest", key.CFrame)
		if i % 7 ~= 2 and i % 7 ~= 6 and i < count - 1 then
			local sharp = part(keys, "Key", Vector3.new(0.42, 0.1, 0.11), CFrame.new(at(8.35, 2.72, z + span / count / 2)), Color3.fromRGB(16, 16, 18))
			sharp:SetAttribute("Rest", sharp.CFrame)
		end
	end
	-- The bench.
	part(root, "PianoBench", Vector3.new(1.3, 0.3, 2.4), CFrame.new(at(6.9, 1.45, 7.5)), black, Enum.Material.SmoothPlastic)
	for _, dz in { -1, 1 } do
		part(root, "BenchLeg", Vector3.new(1.1, 1.3, 0.2), CFrame.new(at(6.9, 0.65, 7.5 + dz)), black)
	end
	local reading = part(piano, "PianoLamp", Vector3.new(0.5, 0.2, 0.5), CFrame.new(at(9.2, 4.55, 6)), Color3.fromRGB(255, 226, 170), Enum.Material.Neon)
	glow(reading, Color3.fromRGB(255, 214, 150), 1, 8)
end

-- ===== People =====

-- A character rig in `look` colours, pinned, with no scripts of its own.
local function rig(name: string, skin: Color3, shirt: Color3, pants: Color3): Model
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = skin
	description.TorsoColor = shirt
	description.LeftArmColor = shirt
	description.RightArmColor = shirt
	description.LeftLegColor = pants
	description.RightLegColor = pants
	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	model.Name = name
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.PlatformStand = true
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	-- Only the root's pinned: the rest hangs off it on the rig's own joints,
	-- so bending a joint (sitting down, or anything the scene does) moves
	-- the limb. (Anchor a limb and its joint does nothing.)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = descendant.Name == "HumanoidRootPart"
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
	return model
end

-- Bends a rig's legs at the hips and knees into a sitting pose (through the
-- joints' C0, so everyone sees it), and returns how high its root sits above
-- whatever it's sat on.
function ChapelBuilder.sitDown(model: Model): number
	-- How far the root's centre is above the hip joints, measured standing
	-- (the hips don't move relative to the root when the legs bend).
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local upperLeg = model:FindFirstChild("LeftUpperLeg") :: BasePart?
	local hipDrop = if upperLeg then (root.Position.Y - (upperLeg.Position.Y + upperLeg.Size.Y / 2)) else 1
	Joints.bend(model, {
		LeftHip = CFrame.Angles(math.rad(90), 0, 0),
		RightHip = CFrame.Angles(math.rad(90), 0, 0),
		LeftKnee = CFrame.Angles(math.rad(-90), 0, 0),
		RightKnee = CFrame.Angles(math.rad(-90), 0, 0),
	})
	-- Sat on a seat, the hip joints are about half a thigh's thickness up.
	return hipDrop + 0.35
end

-- Sits `model` on a pew seat at (x, z), facing the front.
local function seat(model: Model, x: number, z: number)
	local height = ChapelBuilder.sitDown(model)
	local spot = at(x, SEAT_TOP + height, z)
	model:PivotTo(CFrame.lookAt(spot, spot + Vector3.new(0, 0, 1)))
end

local MOURNERS = {
	-- { x, row, skin, clothes }
	{ -3.2, 1, Color3.fromRGB(225, 195, 165), Color3.fromRGB(30, 28, 30) }, -- Gil's widow, front row by the aisle
	{ -5, 1, Color3.fromRGB(205, 165, 130), Color3.fromRGB(40, 40, 46) },
	{ 5.8, 1, Color3.fromRGB(140, 100, 75), Color3.fromRGB(28, 28, 32) },
	{ -7.5, 2, Color3.fromRGB(185, 150, 122), Color3.fromRGB(46, 40, 38) },
	{ -4.4, 2, Color3.fromRGB(225, 195, 165), Color3.fromRGB(24, 24, 28) },
	{ 3.6, 2, Color3.fromRGB(90, 65, 50), Color3.fromRGB(34, 34, 40) },
	{ 7.2, 2, Color3.fromRGB(205, 165, 130), Color3.fromRGB(50, 44, 40) },
	{ -6.2, 3, Color3.fromRGB(140, 100, 75), Color3.fromRGB(30, 30, 34) },
	{ 4.8, 3, Color3.fromRGB(225, 195, 165), Color3.fromRGB(36, 32, 30) },
	{ 8, 4, Color3.fromRGB(185, 150, 122), Color3.fromRGB(28, 26, 26) },
	{ -8.2, 4, Color3.fromRGB(205, 165, 130), Color3.fromRGB(44, 44, 48) },
}

local function buildPeople(root: Instance)
	local people = Instance.new("Folder")
	people.Name = "People"
	people.Parent = root
	for i, m in MOURNERS do
		local mourner = rig("Mourner" .. i, m[3], m[4], Color3.fromRGB(22, 22, 26))
		seat(mourner, m[1], ChapelBuilder.ROWS[m[2]])
		mourner.Parent = people
	end

	-- Teddy: Gil's oldest friend, two rows in front of the back row, on the
	-- left by the aisle (the player sits in the back row, left, by the
	-- aisle).
	local teddy = rig("Teddy", Color3.fromRGB(196, 150, 118), Color3.fromRGB(58, 52, 46), Color3.fromRGB(30, 30, 34))
	seat(teddy, -3.4, ChapelBuilder.ROWS[5])
	teddy.Parent = people

	-- Nina, Gil's daughter: a child, front row on the right by the aisle,
	-- until she gets up to play.
	local ninaLook = StoryConfig.CHARACTERS.nina.look
	local nina = rig("Nina", ninaLook.skin, ninaLook.shirt, ninaLook.pants)
	nina:ScaleTo(0.72)
	seat(nina, 3.3, ChapelBuilder.ROWS[1])
	nina.Parent = people

	-- The minister, at the lectern, facing the room.
	local minister = rig("Minister", Color3.fromRGB(150, 110, 85), Color3.fromRGB(26, 26, 30), Color3.fromRGB(26, 26, 30))
	local mRoot = minister:FindFirstChild("HumanoidRootPart") :: BasePart
	local mHumanoid = minister:FindFirstChildOfClass("Humanoid") :: Humanoid
	local height = mHumanoid.HipHeight + mRoot.Size.Y / 2
	local spot = at(-4, DAIS_HEIGHT + height, 11.7)
	minister:PivotTo(CFrame.lookAt(spot, spot + Vector3.new(0, 0, -1)))
	minister.Parent = people
end

function ChapelBuilder.build()
	-- A model that's always sent to every player in full, wherever they
	-- are: the place streams the world in around the player, and this room's
	-- a good way below the cab -- as a plain folder its lamps (and Gil's
	-- photo) turned up ten seconds into the scene (seen twice in recordings).
	local folder = Instance.new("Model")
	folder.Name = "ChapelInterior"
	folder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	folder.Parent = workspace
	buildRoom(folder)
	buildGlass(folder)
	buildPews(folder)
	buildFront(folder)
	buildPhoto(folder)
	buildPiano(folder)
	buildPeople(folder)
end

-- Where things are, for the scene's cameras (see StoryScenes).
ChapelBuilder.SEAT_TOP = SEAT_TOP
ChapelBuilder.DAIS_HEIGHT = DAIS_HEIGHT

return ChapelBuilder
