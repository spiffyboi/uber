-- Builds the Marrow Cab Co. dispatch office: the room the intro cutscene now
-- opens in, before it ever cuts to the street/grate (see CityConfig's
-- OFFICE_ORIGIN/OFFICE_DOOR_POSITION/OFFICE_DESK_POSITION, which this and
-- IntroCutscene both key off). One small room, one dispatcher, one desk --
-- nothing here needs to hold up to being walked around, since the whole
-- opening is a scripted camera sequence, not something the player actually
-- walks through.

local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))

local TaxiOfficeBuilder = {}

-- Light, institutional colours (nicotine-cream walls, pale ceiling) rather
-- than dark browns: confirmed live that the room still read as dark with the
-- cutscene's own Lighting boost fully applied, because the old palette
-- (walls 58,52,46, ceiling 35,33,30) simply had almost nothing to reflect.
local WALL_COLOR = Color3.fromRGB(196, 186, 160)
local TRIM_COLOR = Color3.fromRGB(70, 64, 56)
local DESK_COLOR = Color3.fromRGB(122, 92, 62)

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

-- The room: floor, ceiling, three solid walls and a fourth (south, where the
-- door is) split into two jambs either side of the doorway the camera enters
-- through.
local function buildRoom(root: Instance)
	local origin = CityConfig.OFFICE_ORIGIN
	local halfWidth, halfDepth, height = 8, 8, 9

	part("Floor", Vector3.new(halfWidth * 2, 1, halfDepth * 2), CFrame.new(origin), Color3.fromRGB(140, 118, 90), Enum.Material.WoodPlanks).Parent = root
	part("Ceiling", Vector3.new(halfWidth * 2, 1, halfDepth * 2), CFrame.new(origin + Vector3.new(0, height, 0)), Color3.fromRGB(220, 216, 205)).Parent = root

	part("WallNorth", Vector3.new(halfWidth * 2, height, 0.6), CFrame.new(origin + Vector3.new(0, height / 2, halfDepth)), WALL_COLOR).Parent = root
	part("WallEast", Vector3.new(0.6, height, halfDepth * 2), CFrame.new(origin + Vector3.new(halfWidth, height / 2, 0)), WALL_COLOR).Parent = root
	part("WallWest", Vector3.new(0.6, height, halfDepth * 2), CFrame.new(origin + Vector3.new(-halfWidth, height / 2, 0)), WALL_COLOR).Parent = root

	-- South wall, split around a doorway centred on OFFICE_DOOR_POSITION.
	local doorWidth = 4
	local jambWidth = (halfWidth * 2 - doorWidth) / 2
	for _, side in { -1, 1 } do
		local jamb = part(
			"WallSouth",
			Vector3.new(jambWidth, height, 0.6),
			CFrame.new(origin + Vector3.new(side * (doorWidth / 2 + jambWidth / 2), height / 2, -halfDepth)),
			WALL_COLOR
		)
		jamb.Parent = root
	end
	part("DoorHeader", Vector3.new(doorWidth, 1.5, 0.6), CFrame.new(origin + Vector3.new(0, height - 0.75, -halfDepth)), WALL_COLOR).Parent = root

	-- Long fluorescent tube panels, each throwing a wide SurfaceLight straight
	-- down plus a PointLight to fill the walls -- an office lit like an
	-- office, not a single bulb.
	for _, z in { -5, 0, 5 } do
		local panel = part("CeilingFixture", Vector3.new(1.2, 0.2, 4), CFrame.new(origin + Vector3.new(0, height - 0.6, z)), Color3.fromRGB(245, 245, 235), Enum.Material.Neon)
		panel.CanCollide = false
		panel.Parent = root

		local down = Instance.new("SurfaceLight")
		down.Face = Enum.NormalId.Bottom
		down.Color = Color3.fromRGB(255, 248, 228)
		down.Brightness = 1
		down.Range = 16
		down.Angle = 120
		down.Parent = panel

		local fill = Instance.new("PointLight")
		fill.Color = Color3.fromRGB(255, 240, 210)
		fill.Brightness = 0.6
		fill.Range = 18
		fill.Parent = panel
	end
end

-- The desk, the dispatcher's chair and lamp, and the pegboard of spare cab
-- keys behind them -- what the camera pushes toward, and what the "10-4"
-- beat at the end of the scene actually hands the player.
local function buildDesk(root: Instance)
	local desk = CityConfig.OFFICE_DESK_POSITION

	local deskTop = part("DeskTop", Vector3.new(6, 0.3, 2.6), CFrame.new(desk + Vector3.new(0, 2.2, 0)), DESK_COLOR, Enum.Material.WoodPlanks)
	deskTop.Parent = root
	part("DeskFront", Vector3.new(6, 2.1, 2.4), CFrame.new(desk + Vector3.new(0, 1.05, 0.05)), DESK_COLOR, Enum.Material.WoodPlanks).Parent = root

	local lampBase = part("LampBase", Vector3.new(0.6, 0.15, 0.6), CFrame.new(desk + Vector3.new(-2.2, 2.42, -0.6)), TRIM_COLOR, Enum.Material.Metal)
	lampBase.Parent = root
	local lampStem = part("LampStem", Vector3.new(0.15, 0.6, 0.15), CFrame.new(desk + Vector3.new(-2.2, 2.7, -0.6)), TRIM_COLOR, Enum.Material.Metal)
	lampStem.Parent = root
	-- An opaque parchment shade, not a glowing one -- it's the small bulb
	-- inside it (below) that actually reads as the light source, so the
	-- shade itself doesn't blow out into a flat glowing slab.
	local lampShade = part("LampShade", Vector3.new(0.9, 0.45, 0.9), CFrame.new(desk + Vector3.new(-2.2, 3.05, -0.6)), Color3.fromRGB(210, 185, 130), Enum.Material.SmoothPlastic)
	lampShade.Shape = Enum.PartType.Cylinder
	lampShade.CFrame = lampShade.CFrame * CFrame.Angles(0, 0, math.rad(90))
	lampShade.Parent = root
	-- A sphere, not a cube -- it nests inside the shade's round silhouette
	-- cleanly instead of poking flat corners out past it from odd angles.
	local lampBulb = part("LampBulb", Vector3.new(0.3, 0.3, 0.3), CFrame.new(desk + Vector3.new(-2.2, 2.86, -0.6)), Color3.fromRGB(255, 235, 190), Enum.Material.Neon)
	lampBulb.Shape = Enum.PartType.Ball
	lampBulb.Parent = root
	local lamp = Instance.new("PointLight")
	lamp.Color = Color3.fromRGB(255, 205, 130)
	lamp.Brightness = 2.5
	lamp.Range = 14
	lamp.Parent = lampBulb

	local chairSeat = part("ChairSeat", Vector3.new(1.8, 0.3, 1.8), CFrame.new(desk + Vector3.new(0, 1.9, 1.6)), TRIM_COLOR)
	chairSeat.Parent = root
	local chairBack = part("ChairBack", Vector3.new(1.8, 2.2, 0.2), CFrame.new(desk + Vector3.new(0, 3.1, 2.4)), TRIM_COLOR)
	chairBack.Parent = root

	-- The dispatcher: a real Roblox character (R15 Humanoid), not hand-built
	-- parts -- an original NPC appearance (solid, period-muted shirt/pants
	-- colours; no catalog face/likeness), not a copy of anyone real or
	-- fictional. Anchored and posed once, in place, since nothing here ever
	-- needs him to actually move.
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = Color3.fromRGB(185, 150, 122)
	description.TorsoColor = Color3.fromRGB(96, 92, 82)
	description.LeftArmColor = Color3.fromRGB(96, 92, 82)
	description.RightArmColor = Color3.fromRGB(96, 92, 82)
	description.LeftLegColor = Color3.fromRGB(48, 45, 42)
	description.RightLegColor = Color3.fromRGB(48, 45, 42)

	local dispatcher = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	dispatcher.Name = "Dispatcher"
	dispatcher.Parent = root

	local humanoid = dispatcher:FindFirstChildOfClass("Humanoid")
	humanoid.PlatformStand = true -- holds the pose still instead of the Idle animation fighting it

	-- Motor6D.C0 turned out read-only on this rig (CreateHumanoidModelFromDescription
	-- apparently hands back joints already locked down), so this doesn't try
	-- to bend the hip/knee/shoulder into an actual sitting pose -- and
	-- doesn't need to: the desk front (above) hides everything from about
	-- the chest down anyway, standing pose or not, so the legs are never on
	-- screen either way.
	for _, descendant in dispatcher:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end

	dispatcher:PivotTo(CFrame.new(desk + Vector3.new(0, 2.55, 1.6)))

	-- The pegboard: rows of spare keys, one of which the dispatcher's about
	-- to hand over -- the physical version of the "10-4" the dispatch popup
	-- fires later in the street scene.
	local pegboard = part("Pegboard", Vector3.new(3.5, 2.5, 0.15), CFrame.new(desk + Vector3.new(2.6, 3.2, 1.1)), Color3.fromRGB(150, 118, 78), Enum.Material.Fabric)
	pegboard.Parent = root
	for row = 0, 2 do
		for col = 0, 3 do
			-- On the board's -Z face, the side the cameras look at it from --
			-- they used to hang on the back, hidden behind the board.
			local key = part(
				"SpareKey",
				Vector3.new(0.12, 0.5, 0.05),
				pegboard.CFrame * CFrame.new(-1.3 + col * 0.85, 0.8 - row * 0.8, -0.12),
				Color3.fromRGB(200, 190, 60),
				Enum.Material.Metal
			)
			key.Parent = root
		end
	end

	local plaque = Instance.new("SurfaceGui")
	plaque.Name = "Plaque"
	plaque.Face = Enum.NormalId.Front
	plaque.PixelsPerStud = 40
	plaque.Parent = part("PlaquePlate", Vector3.new(3, 1, 0.1), CFrame.new(desk + Vector3.new(-2.3, 5.2, 1.2)), Color3.fromRGB(20, 20, 22))
	plaque.Parent.Parent = root
	local plaqueLabel = Instance.new("TextLabel")
	plaqueLabel.BackgroundTransparency = 1
	plaqueLabel.Size = UDim2.fromScale(1, 1)
	plaqueLabel.Font = Enum.Font.Oswald
	plaqueLabel.Text = CityConfig.TAXI_COMPANY_NAME:upper()
	plaqueLabel.TextColor3 = Color3.fromRGB(200, 180, 120)
	plaqueLabel.TextScaled = true
	plaqueLabel.Parent = plaque
end

-- Everything that isn't the desk itself -- a bare room read as a set built
-- only for the camera to push through, not an office anyone actually works
-- in. None of this needs to be interactive, just present.
local function buildDecor(root: Instance)
	local origin = CityConfig.OFFICE_ORIGIN

	-- A window on the east wall, backlit like there's a lit street outside --
	-- venetian blinds (alternating slats) over it, half-open.
	local windowGlow = part("WindowGlow", Vector3.new(0.1, 3, 3.6), CFrame.new(origin + Vector3.new(7.9, 4.5, -2)), Color3.fromRGB(70, 90, 120), Enum.Material.Neon)
	windowGlow.Parent = root
	for i = 0, 7 do
		local slat = part(
			"BlindSlat",
			Vector3.new(0.05, 0.25, 3.6),
			CFrame.new(origin + Vector3.new(7.85, 3.15 + i * 0.4, -2)),
			Color3.fromRGB(150, 145, 130)
		)
		slat.Parent = root
	end
	part("WindowFrame", Vector3.new(0.2, 3.3, 4), CFrame.new(origin + Vector3.new(7.95, 4.5, -2)), TRIM_COLOR, Enum.Material.Metal).Parent = root

	-- A filing cabinet by the west wall -- three drawers, each with a handle.
	local cabinet = part("FilingCabinet", Vector3.new(1.6, 3.6, 2), CFrame.new(origin + Vector3.new(-6.8, 1.8, -4)), Color3.fromRGB(52, 55, 58), Enum.Material.Metal)
	cabinet.Parent = root
	for i = 0, 2 do
		local handle = part(
			"DrawerHandle",
			Vector3.new(0.1, 0.1, 0.7),
			cabinet.CFrame * CFrame.new(0.85, 1.1 - i * 1.1, 0),
			TRIM_COLOR,
			Enum.Material.Metal
		)
		handle.Parent = root
	end

	-- A wall clock, stopped (this office doesn't run on a clean schedule) --
	-- next to the company plaque above the desk.
	local clockFace = part("ClockFace", Vector3.new(0.15, 1.4, 1.4), CFrame.new(origin + Vector3.new(0, 5.4, 6.9)), Color3.fromRGB(225, 220, 205))
	clockFace.Shape = Enum.PartType.Cylinder
	clockFace.CFrame = clockFace.CFrame * CFrame.Angles(0, 0, math.rad(90))
	clockFace.Parent = root
	local clockHourHand = part("ClockHourHand", Vector3.new(0.05, 0.4, 0.06), clockFace.CFrame * CFrame.new(0.09, 0.15, -0.1) * CFrame.Angles(0, 0, math.rad(20)), TRIM_COLOR)
	clockHourHand.Parent = root
	local clockMinuteHand = part("ClockMinuteHand", Vector3.new(0.05, 0.55, 0.06), clockFace.CFrame * CFrame.new(0.09, 0.05, 0.2) * CFrame.Angles(0, 0, math.rad(-70)), TRIM_COLOR)
	clockMinuteHand.Parent = root

	-- A coat rack by the door, one coat and one hat on it -- the last
	-- dispatcher's, maybe, or a spare for whoever's cold enough to need it.
	local rackPole = part("CoatRackPole", Vector3.new(0.15, 5, 0.15), CFrame.new(origin + Vector3.new(-6.5, 2.5, -6)), TRIM_COLOR, Enum.Material.Metal)
	rackPole.Parent = root
	local rackBase = part("CoatRackBase", Vector3.new(1.4, 0.15, 1.4), CFrame.new(origin + Vector3.new(-6.5, 0.1, -6)), TRIM_COLOR, Enum.Material.Metal)
	rackBase.Parent = root
	local rackPeg = part("CoatRackPeg", Vector3.new(0.5, 0.12, 0.12), CFrame.new(origin + Vector3.new(-6.5, 4.7, -5.75)), TRIM_COLOR, Enum.Material.Metal)
	rackPeg.Parent = root
	local coat = part("Coat", Vector3.new(1.4, 2, 0.5), CFrame.new(origin + Vector3.new(-6.5, 3.6, -5.7)), Color3.fromRGB(45, 42, 55), Enum.Material.Fabric)
	coat.Parent = root
	local hat = part("SpareHat", Vector3.new(0.9, 0.35, 0.9), CFrame.new(origin + Vector3.new(-6.35, 5.05, -5.75)), Color3.fromRGB(40, 38, 42))
	hat.Parent = root

	-- A worn rug under the desk, and a wastebin beside it -- the small mess
	-- of a room someone's actually spent every graveyard shift in.
	local rug = part("Rug", Vector3.new(5, 0.05, 4), CFrame.new(origin + Vector3.new(0, 0.53, 2)), Color3.fromRGB(90, 40, 35), Enum.Material.Fabric)
	rug.Parent = root
	local wastebin = part("Wastebin", Vector3.new(0.8, 1, 0.8), CFrame.new(origin + Vector3.new(2.8, 0.5, 4)), Color3.fromRGB(60, 58, 55), Enum.Material.Metal)
	wastebin.Parent = root
end

function TaxiOfficeBuilder.build()
	local root = Instance.new("Folder")
	root.Name = "TaxiOffice"
	root.Parent = workspace

	buildRoom(root)
	buildDesk(root)
	buildDecor(root)

	return root
end

return TaxiOfficeBuilder
