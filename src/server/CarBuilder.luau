-- Builds one player's car: a worn sedan, not a branded cab -- this is
-- someone's own car they drive for GigLine, the way a real Uber/Uber Eats
-- driver does. Simple box-and-cylinder shapes for now; a real mesh can
-- replace the body part later without touching the seat/wheel rig below it.

local CollectionService = game:GetService("CollectionService")

local CAR_COLORS = {
	Color3.fromRGB(35, 45, 38), -- worn dark green
	Color3.fromRGB(50, 38, 36), -- oxblood
	Color3.fromRGB(30, 32, 36), -- near-black grey
	Color3.fromRGB(60, 55, 40), -- faded tan
}

local CarBuilder = {}

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

local function wheel(model: Model, chassis: BasePart, offset: Vector3, name: string)
	local w = Instance.new("Part")
	w.Name = name
	w.Shape = Enum.PartType.Cylinder
	w.Size = Vector3.new(1.6, 3, 3)
	w.Color = Color3.fromRGB(15, 15, 15)
	w.Material = Enum.Material.SmoothPlastic
	w.CFrame = chassis.CFrame * CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(90))
	w.Parent = model
	weld(chassis, w)
end

-- `cframe` is where the driver's seat (and so the car) starts out.
function CarBuilder.build(ownerName: string, cframe: CFrame): Model
	local model = Instance.new("Model")
	model.Name = ownerName .. "_Car"

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(6.5, 1.6, 14)
	chassis.Color = CAR_COLORS[math.random(1, #CAR_COLORS)]
	chassis.Material = Enum.Material.Metal
	chassis.CFrame = cframe
	chassis.Anchored = false
	chassis.Parent = model
	model.PrimaryPart = chassis

	local cabin = Instance.new("Part")
	cabin.Name = "Cabin"
	cabin.Size = Vector3.new(5.6, 2.6, 8)
	cabin.Color = chassis.Color
	cabin.Material = Enum.Material.Metal
	cabin.CFrame = chassis.CFrame * CFrame.new(0, 2.1, -0.5)
	cabin.Parent = model
	weld(chassis, cabin)

	-- Roblox parts face "front" along their own local -Z; the chassis's
	-- LookVector (and so the direction the car actually drives) is that same
	-- local -Z transformed by its CFrame. Everything front-facing below (the
	-- windshield, headlights) sits at negative local Z for that reason; the
	-- taillight, at the back, sits at positive Z.
	local windshield = Instance.new("Part")
	windshield.Name = "Windshield"
	windshield.Size = Vector3.new(5.4, 2.2, 0.2)
	windshield.Color = Color3.fromRGB(140, 170, 180)
	windshield.Material = Enum.Material.Glass
	windshield.Transparency = 0.35
	windshield.CFrame = chassis.CFrame * CFrame.new(0, 2.2, -3.6) * CFrame.Angles(math.rad(20), 0, 0)
	windshield.Parent = model
	weld(chassis, windshield)

	local headlightL = Instance.new("Part")
	headlightL.Name = "HeadlightL"
	headlightL.Shape = Enum.PartType.Ball
	headlightL.Size = Vector3.new(0.8, 0.8, 0.8)
	headlightL.Color = Color3.fromRGB(255, 250, 230)
	headlightL.Material = Enum.Material.Neon
	headlightL.CFrame = chassis.CFrame * CFrame.new(-2, 0.2, -7)
	headlightL.Parent = model
	weld(chassis, headlightL)
	local spotL = Instance.new("SpotLight")
	spotL.Color = Color3.fromRGB(255, 250, 235)
	spotL.Brightness = 3
	spotL.Range = 40
	spotL.Angle = 50
	spotL.Face = Enum.NormalId.Front
	spotL.Parent = headlightL

	local headlightR = headlightL:Clone()
	headlightR.Name = "HeadlightR"
	headlightR.CFrame = chassis.CFrame * CFrame.new(2, 0.2, -7)
	headlightR.Parent = model
	weld(chassis, headlightR)

	local taillight = Instance.new("Part")
	taillight.Name = "Taillight"
	taillight.Size = Vector3.new(5, 0.6, 0.2)
	taillight.Color = Color3.fromRGB(200, 30, 30)
	taillight.Material = Enum.Material.Neon
	taillight.CFrame = chassis.CFrame * CFrame.new(0, 0.3, 7)
	taillight.Parent = model
	weld(chassis, taillight)

	wheel(model, chassis, Vector3.new(-3.4, -0.9, -4.5), "WheelFL")
	wheel(model, chassis, Vector3.new(3.4, -0.9, -4.5), "WheelFR")
	wheel(model, chassis, Vector3.new(-3.4, -0.9, 4.5), "WheelBL")
	wheel(model, chassis, Vector3.new(3.4, -0.9, 4.5), "WheelBR")

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriveSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.MaxSpeed = 0 -- movement is driven by CarController, not the seat's own physics
	seat.CFrame = chassis.CFrame * CFrame.new(0, 1.2, 0.5)
	seat.Transparency = 1
	-- Locked until the intro cutscene's dispatch call is accepted (see
	-- CarSpawner), so the player can't drive off mid-cinematic.
	seat.Disabled = true
	seat.Parent = model
	weld(chassis, seat)

	-- CarController finds every player car this way, so it doesn't need to
	-- know anything about how or where CarSpawner keeps track of them.
	CollectionService:AddTag(model, "PlayerCar")

	return model
end

return CarBuilder
