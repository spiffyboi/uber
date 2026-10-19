-- Flashes of what's happened, cut into chapter 9's drive for a second at a
-- time (see LateScenes' friday): Nina at the piano; Dez on his knees in the
-- side street, the flash; Teddy bending over him on the chapel floor; Gil in
-- the back seat, the gun up, the flash.
--
-- Each is a still picture -- a little set in a ViewportFrame laid over the
-- screen -- rather than the camera jumping to the real places: a camera
-- jumping somewhere new sees it unlit for its first few seconds (Roblox
-- lights a place a bit at a time around the camera -- see the chapel), and
-- these are on screen for a second. They're staged from the real things:
-- the chapel's own room and people, the player's own cab, the people
-- recoloured as who they were.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))
local StoryConfig = require(Shared:WaitForChild("StoryConfig"))
local Joints = require(Shared:WaitForChild("Joints"))
local Screen = require(script.Parent.Screen)
local StoryScenes = require(script.Parent.StoryScenes)

local Flashbacks = {}

local player = Players.LocalPlayer

local gui: ScreenGui? = nil
local frames: { [string]: ViewportFrame } = {}
local staging: Folder? = nil

-- (As ChapelBuilder.ROWS.)
local ROWS = { 3.5, 0.5, -2.5, -5.5, -8.5, -11.5 }

local function inChapel(x: number, y: number, z: number): Vector3
	return CityConfig.CHAPEL_ORIGIN + Vector3.new(x, 0.5 + y, z)
end

local function chapelPerson(name: string): Model?
	local interior = workspace:FindFirstChild("ChapelInterior")
	local people = interior and interior:FindFirstChild("People")
	return people and people:FindFirstChild(name) :: Model?
end

-- `model` in `look`'s colours (who someone is, in this game, is their
-- colours -- see Passengers.spawn).
local function recolour(model: Model, look)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			if part.Name == "Head" then
				part.Color = look.skin
			elseif part.Name:find("Leg") or part.Name:find("Foot") then
				part.Color = look.pants
			else
				part.Color = look.shirt
			end
		end
	end
end

-- A copy of `source` (a rig), bent into a pose out of sight -- its joints
-- given a moment to put the limbs where the bends say -- then frozen, so it
-- can be moved about whole. `bends` is applied in order.
local function posed(source: Model?, bends: { { [string]: CFrame } }): Model?
	if not source then
		return nil
	end
	local was = source.Archivable
	source.Archivable = true
	local copy = source:Clone()
	source.Archivable = was
	if not copy then
		return nil
	end
	for _, d in copy:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.CanCollide = false
			d.CanQuery = false
			d.LocalTransparencyModifier = 0
		end
	end
	copy:PivotTo(CFrame.new(0, 1500, 0))
	copy.Parent = staging
	for _, b in bends do
		Joints.bend(copy, b)
	end
	return copy
end

local function freezeInto(model: Model, parent: Instance, at: CFrame)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	model:PivotTo(at)
	model.Parent = parent
end

local function newFrame(name: string, ambient: Color3, light: Color3, direction: Vector3): (ViewportFrame, Model)
	local frame = Instance.new("ViewportFrame")
	frame.Name = name
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BorderSizePixel = 0
	frame.Ambient = ambient
	frame.LightColor = light
	frame.LightDirection = direction
	frame.Visible = false
	-- A memory: cooler and paler than life.
	frame.ImageColor3 = Color3.fromRGB(225, 228, 238)
	frame.Parent = gui
	local world = Instance.new("WorldModel")
	world.Parent = frame
	local cam = Instance.new("Camera")
	cam.Parent = frame
	frame.CurrentCamera = cam
	frames[name] = frame
	return frame, world
end

-- The chapel's room (without its people), copied into a picture.
local function chapelRoom(world: WorldModel)
	local interior = workspace:FindFirstChild("ChapelInterior")
	if not interior then
		return
	end
	for _, child in interior:GetChildren() do
		if child.Name ~= "People" then
			child.Archivable = true
			local copy = child:Clone()
			if copy then
				copy.Parent = world
			end
		end
	end
end

-- Up out of the pews (the chapel's people are all sat down).
local STAND = { LeftHip = CFrame.Angles(math.rad(-90), 0, 0), RightHip = CFrame.Angles(math.rad(-90), 0, 0), LeftKnee = CFrame.Angles(math.rad(90), 0, 0), RightKnee = CFrame.Angles(math.rad(90), 0, 0) }

-- How high a sat rig's root is above what it's sat on (see ChapelBuilder).
local function satHeight(model: Model): number
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local upperLeg = model:FindFirstChild("LeftUpperLeg") :: BasePart?
	local lowerLeg = model:FindFirstChild("LeftLowerLeg") :: BasePart?
	local foot = model:FindFirstChild("LeftFoot") :: BasePart?
	local standing = humanoid.HipHeight + root.Size.Y / 2
	local legs = (if upperLeg then upperLeg.Size.Y else 1) + (if lowerLeg then lowerLeg.Size.Y else 1) + (if foot then foot.Size.Y else 0.3)
	return standing - legs + 0.35, standing
end

-- Builds all four (a couple of frames' work). Safe to call again.
function Flashbacks.prepare()
	if gui then
		return
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "Flashbacks"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	-- Over the world, under the letterbox bars and the subtitles.
	gui.DisplayOrder = 8
	gui.Parent = player:WaitForChild("PlayerGui")
	staging = Instance.new("Folder")
	staging.Name = "FlashbackStaging"
	staging.Parent = workspace

	-- Nina at the piano: her arms out to the keys, from the end of the
	-- piano, the lamp on her face.
	local ninaFrame, ninaWorld = newFrame("nina", Color3.fromRGB(120, 96, 74), Color3.fromRGB(255, 214, 160), Vector3.new(-0.6, -1, 0.3))
	chapelRoom(ninaWorld)
	local nina = posed(chapelPerson("Nina"), {
		{ LeftShoulder = CFrame.Angles(math.rad(62), math.rad(12), 0), RightShoulder = CFrame.Angles(math.rad(62), math.rad(-12), 0) },
		{ LeftElbow = CFrame.Angles(math.rad(25), 0, 0), RightElbow = CFrame.Angles(math.rad(25), 0, 0) },
	})

	-- Teddy, bent over the camera on the chapel floor.
	local teddyFrame, teddyWorld = newFrame("teddy", Color3.fromRGB(110, 92, 76), Color3.fromRGB(255, 220, 170), Vector3.new(0.2, -1, 0.4))
	chapelRoom(teddyWorld)
	local teddy = posed(chapelPerson("Teddy"), { STAND, { Waist = CFrame.Angles(math.rad(-40), 0, 0), Neck = CFrame.Angles(math.rad(-20), 0, 0) } })

	-- Dez on his knees under a lamp; the man behind him, arm out; the flash.
	local dezFrame, dezWorld = newFrame("dez", Color3.fromRGB(70, 60, 54), Color3.fromRGB(255, 180, 110), Vector3.new(0.5, -1, -0.4))
	local dez = posed(chapelPerson("Mourner3"), { STAND, { LeftKnee = CFrame.Angles(math.rad(-90), 0, 0), RightKnee = CFrame.Angles(math.rad(-90), 0, 0), LeftShoulder = CFrame.Angles(math.rad(-20), 0, math.rad(-10)), RightShoulder = CFrame.Angles(math.rad(-20), 0, math.rad(10)) } })
	local shooter = posed(chapelPerson("Mourner4"), { STAND, { RightShoulder = CFrame.Angles(math.rad(75), 0, 0) } })

	-- Gil in the back of the cab, from the driver turned round, the gun
	-- between them.
	local gilFrame, gilWorld = newFrame("gil", Color3.fromRGB(40, 46, 78), Color3.fromRGB(110, 128, 200), Vector3.new(0.3, -1, -0.5))
	local gil = posed(chapelPerson("Mourner5"), {})

	-- (The bends take a moment to come through.)
	for _ = 1, 3 do
		RunService.Heartbeat:Wait()
	end

	-- Nina, on the bench.
	if nina then
		local sat = satHeight(nina)
		local seatAt = inChapel(6.9, 1.6 + sat, 7.5)
		freezeInto(nina, ninaWorld, CFrame.lookAt(seatAt, seatAt + Vector3.new(1, 0, 0)))
		local head = (nina:FindFirstChild("Head") :: BasePart).Position
		local cam = ninaFrame.CurrentCamera :: Camera
		-- Back along the wall from the end of the piano: her, the keys,
		-- the lamp. (Any nearer and her head filled the frame.)
		cam.FieldOfView = 55
		cam.CFrame = CFrame.lookAt(inChapel(9.2, 4.6, 2.2), head - Vector3.new(0, 0.6, 0))
	end

	-- Teddy, kneeling over where the driver lay; looking up at him.
	if teddy then
		local _, standing = satHeight(teddy)
		local spot = inChapel(-1.0, standing - 0.3, ROWS[6] + 0.9)
		freezeInto(teddy, teddyWorld, CFrame.lookAt(spot, spot + Vector3.new(-0.3, 0, -1)))
		local head = (teddy:FindFirstChild("Head") :: BasePart).Position
		local cam = teddyFrame.CurrentCamera :: Camera
		cam.FieldOfView = 55
		cam.CFrame = CFrame.lookAt(inChapel(-1.4, 0.9, ROWS[6] - 0.6), head) * CFrame.Angles(0, 0, 0.25)
	end

	-- The side street: a wall, the pavement, a lamp; them.
	do
		local o = Vector3.new(0, 0, 0)
		local function block(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material)
			local p = Instance.new("Part")
			p.Size = size
			p.CFrame = cf
			p.Color = color
			p.Material = material
			p.Anchored = true
			p.Parent = dezWorld
			return p
		end
		block(Vector3.new(40, 1, 40), CFrame.new(o + Vector3.new(0, -0.5, 0)), Color3.fromRGB(46, 44, 42), Enum.Material.Asphalt)
		block(Vector3.new(1, 18, 40), CFrame.new(o + Vector3.new(-6, 9, 0)), Color3.fromRGB(86, 46, 38), Enum.Material.Brick)
		block(Vector3.new(6, 4, 3), CFrame.new(o + Vector3.new(-4, 2, -9)), Color3.fromRGB(34, 60, 44), Enum.Material.Metal)
		local lamp = block(Vector3.new(0.8, 0.4, 0.8), CFrame.new(o + Vector3.new(-5.2, 10, 1)), Color3.fromRGB(255, 170, 90), Enum.Material.Neon)
		lamp.Name = "Lamp"
		if dez then
			local _, standing = satHeight(dez)
			local lowerLeg = dez:FindFirstChild("LeftLowerLeg") :: BasePart?
			local drop = if lowerLeg then lowerLeg.Size.Y + 0.3 else 1.6
			local at = o + Vector3.new(-2.5, standing - drop, 0)
			freezeInto(dez, dezWorld, CFrame.lookAt(at, at + Vector3.new(1, 0, 0)))
			recolour(dez, StoryConfig.CHARACTERS.dez.look)
		end
		if shooter then
			local _, standing = satHeight(shooter)
			local at = o + Vector3.new(-4.6, standing, -0.6)
			freezeInto(shooter, dezWorld, CFrame.lookAt(at, o + Vector3.new(-2.5, standing - 1.2, 0)))
			recolour(shooter, StoryConfig.CHARACTERS.alleyman.look)
			local hand = shooter:FindFirstChild("RightHand") :: BasePart?
			if hand then
				local flash = block(Vector3.new(0.9, 0.9, 0.9), CFrame.new(hand.Position + (hand.CFrame.UpVector * -0.8)), Color3.fromRGB(255, 220, 140), Enum.Material.Neon)
				flash.Shape = Enum.PartType.Ball
			end
		end
		local cam = dezFrame.CurrentCamera :: Camera
		-- From the side, so the man behind him isn't hidden by him.
		cam.FieldOfView = 50
		cam.CFrame = CFrame.lookAt(o + Vector3.new(1.5, 3.6, 9), o + Vector3.new(-3.6, 2.4, -0.3))
	end

	-- The cab: the player's own, copied as it stands, Gil sat in the back.
	do
		local car = workspace:FindFirstChild(player.Name .. "_Car") :: Model?
		local kit = StoryScenes.kit
		if car and gil then
			car.Archivable = true
			local copy = car:Clone()
			if copy then
				for _, d in copy:GetDescendants() do
					if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
						d:Destroy()
					elseif d:IsA("BasePart") then
						d.Anchored = true
						d.LocalTransparencyModifier = 0
					end
				end
				copy.Parent = gilWorld
			end
			local seat = car:FindFirstChild("PassengerSeat") :: BasePart?
			if seat then
				local sat = satHeight(gil)
				local top = seat.CFrame * CFrame.new(0, seat.Size.Y / 2 + sat, 0)
				freezeInto(gil, gilWorld, top)
				recolour(gil, StoryConfig.CHARACTERS.gil.look)
			end
			local head = (gil:FindFirstChild("Head") :: BasePart).Position
			-- From the front seats, turned round: him, and the gun between
			-- (nearer, and his head filled it).
			local eye = kit.fromSeat(0.3, 2.85, -0.3)
			local cam = gilFrame.CurrentCamera :: Camera
			cam.FieldOfView = 58
			cam.CFrame = CFrame.lookAt(eye, head)
			-- The driver's pistol in the foreground, and its flash.
			local pistol = kit.makePistol()
			local look = CFrame.lookAt(eye, head)
			pistol.CFrame = CFrame.lookAt((look * CFrame.new(-0.3, -0.38, -1.25)).Position, head)
			pistol.Parent = gilWorld
			local flash = Instance.new("Part")
			flash.Shape = Enum.PartType.Ball
			flash.Size = Vector3.new(0.6, 0.6, 0.6)
			flash.Material = Enum.Material.Neon
			flash.Color = Color3.fromRGB(255, 226, 150)
			flash.Anchored = true
			flash.CFrame = pistol.CFrame * CFrame.new(0, 0.02, -0.75)
			flash.Parent = gilWorld
		end
	end

	staging:Destroy()
	staging = nil
end

-- Shows flash `name` for `seconds` (yields): a cut to white, the picture,
-- drifting in a little, and gone.
function Flashbacks.show(name: string, seconds: number)
	local frame = frames[name]
	if not frame then
		task.wait(seconds)
		return
	end
	local cam = frame.CurrentCamera :: Camera
	local from = cam.CFrame
	local fov = cam.FieldOfView
	Screen.flash(Color3.new(1, 1, 1), 0.85, 0.35)
	frame.Visible = true
	local started = os.clock()
	while os.clock() - started < seconds do
		local a = (os.clock() - started) / seconds
		cam.CFrame = from * CFrame.new(0, 0, -0.6 * a)
		cam.FieldOfView = fov - 2 * a
		RunService.RenderStepped:Wait()
	end
	cam.CFrame = from
	cam.FieldOfView = fov
	frame.Visible = false
	Screen.flash(Color3.new(1, 1, 1), 0.5, 0.25)
end

function Flashbacks.clear()
	if gui then
		gui:Destroy()
		gui = nil
	end
	frames = {}
	if staging then
		staging:Destroy()
		staging = nil
	end
end

return Flashbacks
