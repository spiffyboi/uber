-- Draws the city's traffic. The server moves one invisible box per car (see
-- TrafficSpawner); this draws a car on each box, here on the player's own
-- machine, so none of it ever has to be sent over the network.
--
-- Two levels of detail. Within DETAIL_DISTANCE of the camera a car is the
-- full lightweight cab (~200 parts); further out it's a simple ~11-part
-- stand-in (body, cabin, wheels, glowing lights) -- at that distance, at
-- night, in the haze, the two read the same. Measured live: drawing every
-- car as the full cab cost about a third of every frame on the bigger map
-- (21 fps with them, 34 without). Detailed cabs are pooled and handed from
-- car to car as they come and go, rather than one built per car.
--
-- Everything is anchored and moved in one batch per frame (BulkMoveTo),
-- which keeps the physics engine out of it entirely.
--
-- The boxes' positions arrive in bursts, not exactly evenly spaced.
-- Snapping a car to each one as it lands makes traffic stutter, so cars are
-- drawn a tenth of a second in the past, smoothly in between the two
-- updates either side of that moment.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local template = ReplicatedStorage:WaitForChild("CityAssets", math.huge):WaitForChild("TaxiLite") :: Model
-- The model can arrive a moment before its parts do (confirmed live: its
-- PrimaryPart was still unset when this first ran, and nothing drew).
template:WaitForChild("Root")
while not template.PrimaryPart do
	template:GetPropertyChangedSignal("PrimaryPart"):Wait()
end

local DRAW_DISTANCE = 480
local DETAIL_DISTANCE = 80
local DETAIL_HYSTERESIS = 10
local INTERPOLATION_DELAY = 0.1
local MAX_SAMPLES = 8

-- Not everything on the road is a cab: most cars get one of these instead
-- of the yellow, with the cab livery stripped off.
local CAB_YELLOW = Color3.fromRGB(255, 176, 0)
local PAINTS = {
	Color3.fromRGB(22, 22, 26),
	Color3.fromRGB(150, 152, 158),
	Color3.fromRGB(100, 22, 28),
	Color3.fromRGB(26, 44, 86),
	Color3.fromRGB(38, 64, 48),
	Color3.fromRGB(205, 202, 192),
	Color3.fromRGB(70, 50, 40),
}
local CAB_SHARE = 40 -- percent of traffic that stays a yellow cab
local GLASS = Color3.fromRGB(15, 18, 24)
local TYRES = Color3.fromRGB(18, 18, 20)
local HEADLIGHT = Color3.fromRGB(255, 240, 205)
local TAILLIGHT = Color3.fromRGB(255, 35, 30)

local folder = Instance.new("Folder")
folder.Name = "TrafficVisuals"
folder.Parent = workspace

local rootTemplate = template.PrimaryPart :: BasePart
local _, extents = template:GetBoundingBox()

-- A drawable car: its parts and where each sits relative to the box.
type Body = { model: Model, parts: { BasePart }, offsets: { CFrame } }

local function makePart(model: Model, size: Vector3, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- Glowing head and tail lights, on either kind of car. Offsets are from
-- the box centre; the car's front is -Z.
local groundY = -rootTemplate.Position.Y
local function addLights(model: Model, parts: { BasePart }, offsets: { CFrame })
	for _, side in { -1, 1 } do
		local head = makePart(model, Vector3.new(0.9, 0.45, 0.12), HEADLIGHT, Enum.Material.Neon)
		table.insert(parts, head)
		table.insert(offsets, CFrame.new(side * extents.X * 0.33, groundY + 2.3, -extents.Z / 2 - 0.02))
		local tail = makePart(model, Vector3.new(0.5, 0.7, 0.12), TAILLIGHT, Enum.Material.Neon)
		table.insert(parts, tail)
		table.insert(offsets, CFrame.new(side * extents.X * 0.4, groundY + 2.6, extents.Z / 2 + 0.02))
	end
end

-- The far-away stand-in: a station-wagon shape in the car's paint.
local function buildSimple(paint: Color3, isCab: boolean): Body
	local model = Instance.new("Model")
	model.Name = "TrafficCar"
	local parts, offsets = {}, {}
	local function add(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?)
		table.insert(parts, makePart(model, size, color, material))
		table.insert(offsets, offset)
	end
	local w, l = extents.X, extents.Z
	add(Vector3.new(w * 0.9, 1, l * 0.74), CFrame.new(0, groundY + 0.5, 0), TYRES)
	add(Vector3.new(w * 0.96, 2.6, l * 0.97), CFrame.new(0, groundY + 2.1, 0), paint)
	add(Vector3.new(w * 0.88, 2.3, l * 0.6), CFrame.new(0, groundY + 4.55, l * 0.1), GLASS)
	add(Vector3.new(w * 0.9, 0.25, l * 0.62), CFrame.new(0, groundY + 5.8, l * 0.1), paint)
	if isCab then
		add(Vector3.new(1.8, 0.6, 0.8), CFrame.new(0, groundY + 6.25, -l * 0.05), Color3.fromRGB(255, 235, 170), Enum.Material.Neon)
	end
	addLights(model, parts, offsets)
	return { model = model, parts = parts, offsets = offsets }
end

-- The detailed cab, in yellow or repainted (with the cab livery off).
local function buildDetailed(isCab: boolean): Body
	local model = template:Clone()
	model.Name = "TrafficCar"
	local root = model.PrimaryPart :: BasePart
	local parts, offsets = {}, {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= root then
			table.insert(parts, descendant)
			table.insert(offsets, root.CFrame:ToObjectSpace(descendant.CFrame))
			descendant.CastShadow = false
		elseif not isCab and descendant:IsA("Decal") then
			descendant:Destroy()
		end
	end
	root:Destroy()
	addLights(model, parts, offsets)
	return { model = model, parts = parts, offsets = offsets }
end

local function repaint(body: Body, paint: Color3)
	for _, part in body.parts do
		if part:GetAttribute("Body") then
			part.Color = paint
		end
	end
end

-- Detailed cabs, kept between uses: one pool still in cab livery, one
-- for everything else.
local pools: { [boolean]: { Body } } = { [true] = {}, [false] = {} }
local function takeDetailed(isCab: boolean, paint: Color3): Body
	local body = table.remove(pools[isCab]) or buildDetailed(isCab)
	if not isCab then
		repaint(body, paint)
	end
	return body
end
local function giveBack(isCab: boolean, body: Body)
	body.model.Parent = nil
	table.insert(pools[isCab], body)
end

type Sample = { t: number, cframe: CFrame }
type Car = {
	box: BasePart,
	isCab: boolean,
	paint: Color3,
	simple: Body,
	detailed: Body?,
	samples: { Sample },
	shown: string, -- "none", "simple" or "detailed"
	connection: RBXScriptConnection,
}

local cars: { [BasePart]: Car } = {}

local function attach(box: Instance)
	if not box:IsA("BasePart") or cars[box] then
		return
	end
	local roll = box:GetAttribute("Paint") or 1
	local isCab = roll <= CAB_SHARE
	local paint = if isCab then CAB_YELLOW else PAINTS[roll % #PAINTS + 1]

	local car: Car
	car = {
		box = box,
		isCab = isCab,
		paint = paint,
		simple = buildSimple(paint, isCab),
		detailed = nil,
		samples = { { t = os.clock(), cframe = box.CFrame } },
		shown = "none",
		connection = box:GetPropertyChangedSignal("CFrame"):Connect(function()
			local samples = car.samples
			table.insert(samples, { t = os.clock(), cframe = box.CFrame })
			if #samples > MAX_SAMPLES then
				table.remove(samples, 1)
			end
		end),
	}
	cars[box] = car
end

local function detach(box: Instance)
	local car = cars[box :: BasePart]
	if car then
		car.connection:Disconnect()
		car.simple.model:Destroy()
		if car.detailed then
			giveBack(car.isCab, car.detailed)
		end
		cars[box :: BasePart] = nil
	end
end

for _, box in CollectionService:GetTagged("TrafficCar") do
	attach(box)
end
CollectionService:GetInstanceAddedSignal("TrafficCar"):Connect(attach)
CollectionService:GetInstanceRemovedSignal("TrafficCar"):Connect(detach)

local function sampleAt(samples: { Sample }, t: number): CFrame
	local count = #samples
	if t <= samples[1].t then
		return samples[1].cframe
	end
	for k = count, 2, -1 do
		local a, b = samples[k - 1], samples[k]
		if t >= a.t then
			if t >= b.t then
				return b.cframe
			end
			local alpha = (t - a.t) / math.max(b.t - a.t, 1e-4)
			return a.cframe:Lerp(b.cframe, alpha)
		end
	end
	return samples[count].cframe
end

local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

RunService.RenderStepped:Connect(function()
	local eye = workspace.CurrentCamera.CFrame.Position
	local renderTime = os.clock() - INTERPOLATION_DELAY
	table.clear(moveParts)
	table.clear(moveFrames)

	for box, car in cars do
		local distance = (box.Position - eye).Magnitude
		local wanted
		if distance > DRAW_DISTANCE then
			wanted = "none"
		elseif distance < DETAIL_DISTANCE or (car.shown == "detailed" and distance < DETAIL_DISTANCE + DETAIL_HYSTERESIS) then
			wanted = "detailed"
		else
			wanted = "simple"
		end

		if wanted ~= car.shown then
			if car.shown == "detailed" and car.detailed then
				giveBack(car.isCab, car.detailed)
				car.detailed = nil
			elseif car.shown == "simple" then
				car.simple.model.Parent = nil
			end
			if wanted == "detailed" then
				car.detailed = takeDetailed(car.isCab, car.paint)
			end
			car.shown = wanted
		end

		local body = if wanted == "detailed" then car.detailed elseif wanted == "simple" then car.simple else nil
		if body then
			local frame = sampleAt(car.samples, renderTime)
			for i, part in body.parts do
				table.insert(moveParts, part)
				table.insert(moveFrames, frame * body.offsets[i])
			end
			if body.model.Parent ~= folder then
				body.model.Parent = folder
			end
		end
	end

	workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
end)
