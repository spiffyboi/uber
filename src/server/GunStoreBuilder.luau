-- Inside Ironside Arms, the gun store on Ashby Ave: the room chapter 5's
-- cutscene plays in (see StoryScenes). Like the cab office, it's a sealed
-- set under the street (CityConfig.GUNSTORE_ORIGIN, right below the shop) --
-- only ever seen through the cutscene's camera, never walked into.
--
-- One small, cluttered room: dark wood panelling, a glass display counter
-- across the middle, rifles racked on the back wall over shelves of ammo,
-- a register, hand-lettered house rules, and Abe behind the counter.
-- The customer's side (and the camera) is -Z of the counter.

local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))

local GunStoreBuilder = {}

local PANEL = Color3.fromRGB(112, 78, 50)
local UPPER_WALL = Color3.fromRGB(176, 160, 130)
local IRON = Color3.fromRGB(30, 30, 32)
local WOOD = Color3.fromRGB(96, 64, 40)

local function part(root: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = root
	return p
end

local function label(p: BasePart, face: Enum.NormalId, text: string, color: Color3, font: Enum.Font?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.4
	gui.Parent = p
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = font or Enum.Font.Oswald
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	l.Parent = gui
end

-- A rifle's silhouette, standing on its butt: stock, receiver, barrel.
local function rifle(root: Instance, base: Vector3, tint: Color3)
	part(root, "RifleStock", Vector3.new(0.35, 1.3, 0.25), CFrame.new(base + Vector3.new(0, 0.65, 0)), tint, Enum.Material.Wood)
	part(root, "RifleReceiver", Vector3.new(0.22, 1.1, 0.2), CFrame.new(base + Vector3.new(0, 1.85, 0)), IRON, Enum.Material.Metal)
	part(root, "RifleBarrel", Vector3.new(0.09, 1.9, 0.09), CFrame.new(base + Vector3.new(0, 3.35, 0)), IRON, Enum.Material.Metal)
end

-- A handgun's outline lying flat (in the display case).
local function handgun(root: Instance, at: CFrame, color: Color3)
	part(root, "CaseGunSlide", Vector3.new(0.9, 0.12, 0.22), at, color, Enum.Material.Metal)
	part(root, "CaseGunGrip", Vector3.new(0.25, 0.12, 0.5), at * CFrame.new(-0.3, 0, 0.3) * CFrame.Angles(0, math.rad(-12), 0), Color3.fromRGB(60, 40, 28), Enum.Material.Wood)
end

local function buildRoom(root: Instance)
	local o = CityConfig.GUNSTORE_ORIGIN
	local halfX, halfZ, height = 9, 8, 9

	part(root, "Floor", Vector3.new(halfX * 2, 1, halfZ * 2), CFrame.new(o), Color3.fromRGB(70, 58, 48), Enum.Material.WoodPlanks)
	part(root, "Ceiling", Vector3.new(halfX * 2, 1, halfZ * 2), CFrame.new(o + Vector3.new(0, height, 0)), Color3.fromRGB(150, 146, 136))
	-- Walls: dark wood panelling to waist height, nicotine cream above.
	local walls = {
		{ "WallBack", Vector3.new(halfX * 2, 0, 0.6), Vector3.new(0, 0, halfZ) },
		{ "WallFront", Vector3.new(halfX * 2, 0, 0.6), Vector3.new(0, 0, -halfZ) },
		{ "WallLeft", Vector3.new(0.6, 0, halfZ * 2), Vector3.new(-halfX, 0, 0) },
		{ "WallRight", Vector3.new(0.6, 0, halfZ * 2), Vector3.new(halfX, 0, 0) },
	}
	for _, w in walls do
		local size, offset = w[2], w[3]
		part(root, w[1] .. "Lower", Vector3.new(size.X, 3.5, size.Z), CFrame.new(o + offset + Vector3.new(0, 1.75, 0)), PANEL, Enum.Material.WoodPlanks)
		part(root, w[1] .. "Upper", Vector3.new(size.X, height - 3.5, size.Z), CFrame.new(o + offset + Vector3.new(0, 3.5 + (height - 3.5) / 2, 0)), UPPER_WALL)
	end

	-- Two long fluorescent fixtures, one humming over the counter.
	for _, z in { -3, 3 } do
		local tube = part(root, "Fluorescent", Vector3.new(5, 0.2, 0.8), CFrame.new(o + Vector3.new(0, height - 0.6, z)), Color3.fromRGB(235, 245, 235), Enum.Material.Neon)
		tube.CanCollide = false
		local down = Instance.new("SurfaceLight")
		down.Face = Enum.NormalId.Bottom
		down.Color = Color3.fromRGB(235, 250, 230)
		down.Brightness = 1.2
		down.Range = 16
		down.Angle = 120
		down.Parent = tube
		local fill = Instance.new("PointLight")
		fill.Color = Color3.fromRGB(255, 236, 200)
		fill.Brightness = 0.7
		fill.Range = 16
		fill.Parent = tube
	end
end

local function buildCounter(root: Instance)
	local c = CityConfig.GUNSTORE_COUNTER
	local length = 12
	-- The case: wooden base, glass sides and top, red felt inside with a
	-- row of handguns laid out on it.
	part(root, "CounterBase", Vector3.new(length, 1.6, 2.2), CFrame.new(c + Vector3.new(0, 0.8, 0)), WOOD, Enum.Material.WoodPlanks)
	part(root, "CounterFelt", Vector3.new(length - 0.4, 0.1, 1.9), CFrame.new(c + Vector3.new(0, 1.65, 0)), Color3.fromRGB(110, 20, 24), Enum.Material.Fabric)
	for i = 0, 4 do
		handgun(root, CFrame.new(c + Vector3.new(-4.4 + i * 2.1, 1.76, 0)) * CFrame.Angles(0, math.rad(8 - i * 4), 0), if i % 2 == 0 then Color3.fromRGB(40, 40, 44) else Color3.fromRGB(150, 150, 156))
	end
	local glassFront = part(root, "CounterGlass", Vector3.new(length, 1.3, 0.1), CFrame.new(c + Vector3.new(0, 2.25, -1.05)), Color3.fromRGB(200, 220, 225), Enum.Material.Glass)
	glassFront.Transparency = 0.7
	local glassTop = part(root, "CounterTop", Vector3.new(length, 0.1, 2.2), CFrame.new(c + Vector3.new(0, 2.95, 0)), Color3.fromRGB(200, 220, 225), Enum.Material.Glass)
	glassTop.Transparency = 0.65
	for _, x in { -length / 2, length / 2 } do
		part(root, "CounterPost", Vector3.new(0.15, 1.4, 2.2), CFrame.new(c + Vector3.new(x, 2.25, 0)), WOOD, Enum.Material.Wood)
	end

	-- The register at the clerk's end, and a little brass bell.
	part(root, "Register", Vector3.new(1.4, 0.9, 1.1), CFrame.new(c + Vector3.new(4.3, 3.45, 0.2)), Color3.fromRGB(60, 58, 52), Enum.Material.Metal)
	part(root, "RegisterDrawer", Vector3.new(1.5, 0.25, 1.2), CFrame.new(c + Vector3.new(4.3, 3.1, 0.2)), Color3.fromRGB(44, 42, 38), Enum.Material.Metal)
	local bell = part(root, "Bell", Vector3.new(0.35, 0.35, 0.35), CFrame.new(c + Vector3.new(-3.6, 3.15, -0.6)), Color3.fromRGB(200, 165, 70), Enum.Material.Metal)
	bell.Shape = Enum.PartType.Ball
end

local function buildBackWall(root: Instance)
	local o = CityConfig.GUNSTORE_ORIGIN
	local wallZ = o.Z + 7.55
	-- The rack: a rail along the back wall with rifles stood in it.
	part(root, "RackRail", Vector3.new(11, 0.3, 0.4), CFrame.new(o.X, o.Y + 2.2, wallZ - 0.1), WOOD, Enum.Material.Wood)
	for i = 0, 7 do
		rifle(root, Vector3.new(o.X - 5 + i * 1.4, o.Y + 0.6, wallZ - 0.25), if i % 3 == 0 then Color3.fromRGB(70, 44, 26) else Color3.fromRGB(92, 60, 36))
	end
	-- Shelves of ammunition boxes up the right-hand side of the back wall.
	local boxColors = { Color3.fromRGB(170, 40, 30), Color3.fromRGB(40, 90, 50), Color3.fromRGB(200, 170, 60), Color3.fromRGB(40, 60, 120) }
	for shelf = 0, 2 do
		local y = o.Y + 3.2 + shelf * 1.4
		part(root, "Shelf", Vector3.new(4.2, 0.15, 0.9), CFrame.new(o.X + 6.6, y, wallZ - 0.4), WOOD, Enum.Material.Wood)
		for k = 0, 4 do
			part(root, "AmmoBox", Vector3.new(0.6, 0.5, 0.5), CFrame.new(o.X + 4.9 + k * 0.82, y + 0.33, wallZ - 0.4), boxColors[(k + shelf) % #boxColors + 1], Enum.Material.SmoothPlastic)
		end
	end
	-- The house rules, hand-lettered.
	local rules = part(root, "HouseRules", Vector3.new(4.5, 2.2, 0.1), CFrame.new(o.X - 5.6, o.Y + 6.6, wallZ - 0.05), Color3.fromRGB(230, 222, 200))
	label(rules, Enum.NormalId.Front, "NO REFUNDS\nNO CREDIT\nNO QUESTIONS", Color3.fromRGB(150, 20, 20), Enum.Font.SourceSansBold)
	-- And the name, painted over the rack.
	local name = part(root, "StoreName", Vector3.new(6, 1, 0.1), CFrame.new(o.X + 0.6, o.Y + 7.4, wallZ - 0.05), Color3.fromRGB(24, 22, 20))
	label(name, Enum.NormalId.Front, "IRONSIDE ARMS  ·  EST. 1952", Color3.fromRGB(215, 190, 120))
end

-- Abe: older, cardigan, behind the counter, facing the customer. A real
-- character rig like the cab office's dispatcher, pinned in place.
local function buildClerk(root: Instance)
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = Color3.fromRGB(205, 165, 130)
	description.TorsoColor = Color3.fromRGB(104, 80, 54)
	description.LeftArmColor = Color3.fromRGB(104, 80, 54)
	description.RightArmColor = Color3.fromRGB(104, 80, 54)
	description.LeftLegColor = Color3.fromRGB(46, 44, 42)
	description.RightLegColor = Color3.fromRGB(46, 44, 42)
	local abe = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	abe.Name = "Abe"
	local humanoid = abe:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.PlatformStand = true
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local animate = abe:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	for _, descendant in abe:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end
	local hrp = abe:FindFirstChild("HumanoidRootPart") :: BasePart
	local height = humanoid.HipHeight + hrp.Size.Y / 2
	local spot = CityConfig.GUNSTORE_COUNTER + Vector3.new(1.2, 0.5 + height, 2)
	abe:PivotTo(CFrame.lookAt(spot, spot + Vector3.new(0, 0, -1)))

	-- Reading glasses on his nose and a grey moustache, so he's somebody.
	local head = abe:FindFirstChild("Head") :: BasePart?
	if head then
		local face = head.CFrame * CFrame.new(0, 0, -head.Size.Z / 2 - 0.03)
		local frame = Color3.fromRGB(20, 18, 16)
		for _, x in { -0.25, 0.25 } do
			local lens = part(abe, "GlassesLens", Vector3.new(0.34, 0.24, 0.04), face * CFrame.new(x, 0.12, 0), frame, Enum.Material.SmoothPlastic)
			lens.Transparency = 0.2
			lens.CanCollide = false
			local glass = part(abe, "GlassesGlass", Vector3.new(0.26, 0.17, 0.02), face * CFrame.new(x, 0.12, -0.02), Color3.fromRGB(200, 215, 220), Enum.Material.Glass)
			glass.Transparency = 0.5
			glass.CanCollide = false
		end
		part(abe, "GlassesBridge", Vector3.new(0.18, 0.04, 0.04), face * CFrame.new(0, 0.16, 0), frame).CanCollide = false
		part(abe, "Moustache", Vector3.new(0.5, 0.1, 0.06), face * CFrame.new(0, -0.16, 0), Color3.fromRGB(150, 146, 140), Enum.Material.Fabric).CanCollide = false
	end
	abe.Parent = root
end

function GunStoreBuilder.build()
	local folder = Instance.new("Folder")
	folder.Name = "GunStoreInterior"
	folder.Parent = workspace
	buildRoom(folder)
	buildCounter(folder)
	buildBackWall(folder)
	buildClerk(folder)
end

return GunStoreBuilder
