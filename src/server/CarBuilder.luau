-- Builds one player's car: a Marrow Cab Co. taxi, since the player's story
-- starts them as a cab driver, not a gig driver -- see CityConfig's
-- TAXI_COMPANY_NAME. GigLine's own branding (a personal car, no livery)
-- belongs to a later stage of the story, once the player's arc turns from
-- cab driver to gig driver, and isn't built here yet.
--
-- The visible body is a free Creator Store mesh (a checker-cab-styled "1966
-- Fletcher Holiday (TAXI)", a fictional make/model, not a real licensed car),
-- loaded at runtime by asset id via InsertService -- not pasted into the
-- place file by hand -- so the actual mesh data stays out of source control
-- and this stays reproducible from a clean `rojo build` the same as
-- everything else here; only the numeric id below is checked in.
--
-- That mesh is a ~850-part display model with no drivable rig of its own
-- (no VehicleSeat, no wheel joints) and no guarantee its own parts are
-- welded to each other. So it isn't simulated as-is: every one of its parts
-- gets welded onto a single invisible physics chassis (the actual thing
-- CarController pushes around) while it's still sitting in its correct,
-- as-loaded arrangement -- WeldConstraint captures whatever relative
-- position two parts have at the moment it's created, so this doesn't need
-- to know the mesh's internal layout or pivot at all, just that everything
-- is where it visually belongs before the welds go on.

local InsertService = game:GetService("InsertService")
local CollectionService = game:GetService("CollectionService")

local TAXI_MESH_ASSET_ID = 12342470926

local CarBuilder = {}

local cachedTemplate: Model? = nil

-- Loads the mesh once per server and keeps the template around (parented
-- nowhere, just held onto) for every later CarBuilder.build() to clone from,
-- instead of hitting InsertService again for every player.
local function getTaxiMeshTemplate(): Model
	if cachedTemplate then
		return cachedTemplate
	end

	local container = InsertService:LoadAsset(TAXI_MESH_ASSET_ID)
	local mesh = container:FindFirstChildWhichIsA("Model")
	assert(mesh, "TAXI_MESH_ASSET_ID's asset didn't contain a Model as expected")
	mesh.Parent = nil
	container:Destroy()

	cachedTemplate = mesh
	return mesh
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

-- Welds every part of the (already correctly positioned) mesh onto the
-- chassis, and strips out everything that would make an ~850-part welded
-- assembly expensive or risky to simulate: no individual physics/collision
-- per part, no mass, no touching-events. Only the invisible chassis itself
-- collides and carries weight.
local function rigMeshToChassis(mesh: Instance, chassis: BasePart)
	for _, descendant in mesh:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Massless = true
			-- The mesh's glass is 60% opaque blue-grey; at night that left the
			-- view out of the windshield almost black.
			if descendant.Transparency > 0.3 and descendant.Transparency < 0.8 then
				descendant.Transparency = 0.85
			end
			if descendant ~= chassis then
				weld(chassis, descendant)
			end
		end
	end
end

-- `cframe` is where the driver's seat (and so the car) starts out.
function CarBuilder.build(ownerName: string, cframe: CFrame): Model
	local model = Instance.new("Model")
	model.Name = ownerName .. "_Car"

	local mesh = getTaxiMeshTemplate():Clone()
	local _, meshSize = mesh:GetBoundingBox()
	-- The mesh's own front (grille/headlights) sits at its local +Z, not -Z
	-- like everything else in this game assumes (see CityConfig) -- confirmed
	-- by playtest, the car was driving/facing backwards without this extra
	-- turn. Only the visual mesh needs it; the invisible chassis below stays
	-- aligned with `cframe` as-is, since that's what actually has to match
	-- CarController's and the street's own -Z-is-forward convention.
	mesh:PivotTo(cframe * CFrame.Angles(0, math.pi, 0))
	mesh.Parent = model

	-- The real physics body: invisible, sized to the mesh's own footprint so
	-- collision roughly matches what's actually on screen, and low enough
	-- (half the mesh height, dropped a little) to sit near the wheels rather
	-- than float at windshield height.
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(meshSize.X * 0.9, meshSize.Y * 0.5, meshSize.Z * 0.95)
	chassis.Transparency = 1
	chassis.CFrame = cframe * CFrame.new(0, -meshSize.Y * 0.18, 0)
	chassis.CanCollide = true
	chassis.Anchored = false
	-- Frictionless: this is a flat box sliding on the road, not a car on
	-- wheels, and CarController sets its velocity outright every frame.
	-- Confirmed live that with normal friction the box dragged away almost
	-- all of each frame's acceleration (Throttle held at 1, speed stuck
	-- around 1-2 studs/s). The high FrictionWeight makes this side win
	-- Roblox's weighted average against whatever the ground uses. Without
	-- friction nothing holds a parked car still, so CarController anchors it
	-- whenever the engine is off.
	chassis.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1)
	chassis.Parent = model
	model.PrimaryPart = chassis

	rigMeshToChassis(mesh, chassis)

	-- Four invisible ball "wheels" that the car actually rides on, holding the
	-- chassis box half a stud off the road. A flat box can't climb anything:
	-- confirmed live it stopped dead against the 0.2-stud sidewalk lip at the
	-- end of the taxi rank. A sphere meeting a step lower than its radius gets
	-- pushed up and over it instead. The half-stud drop also puts the mesh's
	-- own tyres on the road surface, where the bare chassis box had them sunk
	-- ~0.5 studs into it.
	local half = chassis.Size / 2
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			local wheel = Instance.new("Part")
			wheel.Name = "WheelContact"
			wheel.Shape = Enum.PartType.Ball
			wheel.Size = Vector3.new(1.2, 1.2, 1.2)
			wheel.Transparency = 1
			wheel.CanCollide = true
			wheel.Massless = true
			wheel.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1)
			wheel.CFrame = chassis.CFrame * CFrame.new(x * (half.X - 0.6), -half.Y + 0.1, z * (half.Z - 1.4))
			wheel.Parent = model
			weld(chassis, wheel)
		end
	end

	-- Working headlights/taillight -- the mesh's own lenses are just painted
	-- geometry, not real light sources. Positioned off the chassis's own
	-- half-extents (see CityConfig: front is local -Z, back is local +Z)
	-- rather than the mesh's, since those are the numbers this code actually
	-- knows for certain.
	local halfLength = chassis.Size.Z / 2
	for _, side in { -1, 1 } do
		local headlight = Instance.new("Part")
		headlight.Name = "Headlight"
		headlight.Shape = Enum.PartType.Ball
		headlight.Size = Vector3.new(0.4, 0.4, 0.4)
		headlight.Transparency = 1
		headlight.CanCollide = false
		headlight.Massless = true
		-- Just ahead of the bumper, so the mesh's own hood/bumper geometry
		-- can't sit in front of the light.
		headlight.CFrame = chassis.CFrame * CFrame.new(side * 2, 0.3, -halfLength - 0.6)
		headlight.Parent = model
		weld(chassis, headlight)

		local spot = Instance.new("SpotLight")
		spot.Color = Color3.fromRGB(255, 250, 235)
		spot.Brightness = 3.5
		spot.Range = 60
		spot.Shadows = false
		spot.Angle = 50
		spot.Face = Enum.NormalId.Front
		spot.Parent = headlight
	end

	local taillight = Instance.new("Part")
	taillight.Name = "TaillightGlow"
	taillight.Size = Vector3.new(0.2, 0.2, 0.2)
	taillight.Transparency = 1
	taillight.CanCollide = false
	taillight.Massless = true
	taillight.CFrame = chassis.CFrame * CFrame.new(0, 0.3, halfLength)
	taillight.Parent = model
	weld(chassis, taillight)
	local taillightGlow = Instance.new("PointLight")
	taillightGlow.Color = Color3.fromRGB(255, 60, 60)
	-- Sits right against the mesh's own glossy rear bumper/body -- confirmed
	-- live in Studio (ruling out Bloom and a leftover Lighting effects rig
	-- first, both independently) that a bright PointLight this close to a
	-- glossy surface renders as a sharp specular starburst regardless of any
	-- post-effect; this was the other half of the "sparkle at the street
	-- cut" report; the streetlight (see OpeningSetBuilder) was the rest.
	taillightGlow.Brightness = 0.6
	taillightGlow.Range = 5
	taillightGlow.Parent = taillight

	-- Measured against the mesh's actual bounding box in a playtest: a seat
	-- at the chassis's own centre height (which chassis.Size.Y/2, and even
	-- +0.3 above centre, both sat well above) put the seated player's head
	-- up near the roofline on this mesh's tall wagon body -- the player
	-- looked like they were sticking out of the roof, not sitting inside.
	-- Level with chassis centre (no Y offset at all) reads as properly
	-- inside the cabin instead.
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriveSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.MaxSpeed = 0 -- movement is driven by CarController, not the seat's own physics
	seat.CFrame = chassis.CFrame * CFrame.new(0, -0.2, 0.5)
	seat.Transparency = 1
	-- Like every other part welded onto the chassis, only the chassis
	-- itself collides.
	seat.CanCollide = false
	-- The engine's own speedometer/throttle overlay reads as a dated default
	-- HUD next to this game's own cinematic camera work; CarController's
	-- velocity math doesn't use it for anything either.
	seat.HeadsUpDisplay = false
	-- Locked until the intro cutscene's dispatch call is accepted (see
	-- CarSpawner), so the player can't drive off mid-cinematic.
	seat.Disabled = true
	seat.Parent = model
	weld(chassis, seat)

	-- The dash-mounted GPS unit: a physical screen the driver can actually
	-- see, since fare notifications (and most of the car's own UI going
	-- forward) live on it now instead of floating as a flat 2D overlay.
	-- Mounted at the base of the windshield, like a suction-cup GPS unit,
	-- rather than tucked into the radio slot (the user's annotated screenshot
	-- showed that position read as unreadably tiny). A 180 yaw so its Front
	-- face (where the SurfaceGui renders) points back toward the driver, and
	-- pitched down toward the driver's eye line.
	local gpsUnit = Instance.new("Part")
	gpsUnit.Name = "GpsUnit"
	gpsUnit.Size = Vector3.new(1.3, 0.8, 0.12)
	gpsUnit.Color = Color3.fromRGB(18, 18, 20)
	gpsUnit.Material = Enum.Material.SmoothPlastic
	gpsUnit.CanCollide = false
	gpsUnit.Massless = true
	-- Moved again (2026-10-04): centred on the windshield, the 1.7-stud
	-- screen covered most of the driver's view of the road. On the dash just
	-- right of the wheel it stays readable without blocking the windshield --
	-- checked live from the driving camera.
	gpsUnit.CFrame = seat.CFrame * CFrame.new(0.9, 1.5, -1.6) * CFrame.Angles(math.rad(-25), math.pi, 0)
	gpsUnit.Parent = model
	weld(chassis, gpsUnit)

	local gpsMount = Instance.new("Part")
	gpsMount.Name = "GpsMount"
	gpsMount.Size = Vector3.new(0.15, 0.7, 0.15)
	gpsMount.Color = Color3.fromRGB(18, 18, 20)
	gpsMount.Material = Enum.Material.SmoothPlastic
	gpsMount.CanCollide = false
	gpsMount.Massless = true
	gpsMount.CFrame = gpsUnit.CFrame * CFrame.new(0, -0.55, 0.05)
	gpsMount.Parent = model
	weld(chassis, gpsMount)

	local gpsScreen = Instance.new("SurfaceGui")
	gpsScreen.Name = "GpsScreen"
	gpsScreen.Face = Enum.NormalId.Front
	-- `PixelsPerStud` alone does nothing without this -- confirmed live that
	-- `SizingMode` was still its default (`FixedSize`, an 800x600 canvas
	-- with zero relation to the part's own physical size), so `PixelsPerStud`
	-- was silently being ignored this entire time. An 800x600 canvas (4:3)
	-- stretched non-uniformly onto this part's actual face (1.7x1.05 studs,
	-- a much wider ~1.6:1) is exactly what was distorting the Accept button
	-- into the stretched bar shape reported live -- this is very likely the
	-- real cause of "the accept fare button can't be pressed" too, not just
	-- a cosmetic issue. `PixelsPerStud` sizing makes the canvas match the
	-- part's own aspect ratio, so everything renders (and hit-tests) as
	-- actually laid out, not stretched to fit an unrelated fixed canvas.
	gpsScreen.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	-- Keeps the canvas at ~442x272 px (the size the fare/dash panels are laid
	-- out for) on the smaller screen.
	gpsScreen.PixelsPerStud = 340
	gpsScreen.LightInfluence = 0
	gpsScreen.ResetOnSpawn = false
	gpsScreen.Parent = gpsUnit

	-- The ignition: a physical key near the steering column, not a button on
	-- the GPS screen -- the user specifically asked to hover the mouse over
	-- the key itself and get a start prompt there, not on the dash display.
	-- ProximityPrompt covers exactly this (a hover/look prompt, and
	-- ClickablePrompt means a mouse click activates it directly, no holding
	-- a key required) without hand-building hover detection + a BillboardGui
	-- from scratch. CarSpawner listens for `Triggered` server-side --
	-- ProximityPrompt fires that on the server on its own, no remote needed.
	local ignitionKey = Instance.new("Part")
	ignitionKey.Name = "IgnitionKey"
	ignitionKey.Size = Vector3.new(0.12, 0.3, 0.12)
	ignitionKey.Color = Color3.fromRGB(180, 175, 150)
	ignitionKey.Material = Enum.Material.Metal
	ignitionKey.CanCollide = false
	ignitionKey.Massless = true
	-- Confirmed live via `camera:WorldToViewportPoint` against the driving
	-- camera's own formula (seat + (0, 2.1, 0), 10 down): the first guess
	-- here (0.35 up, 0.7 forward) projected to screen Y 2256 -- more than
	-- three screen-heights below frame, nowhere near visible -- close/low
	-- offsets blow up in perspective at this distance from the camera. This
	-- offset lands at screen (438, 471) against a ~1506x710 viewport, close
	-- to where the wheel's own hub actually reads on screen.
	ignitionKey.CFrame = seat.CFrame * CFrame.new(-0.35, 1.9, -0.8) * CFrame.Angles(0, 0, math.rad(20))
	ignitionKey.Parent = model
	weld(chassis, ignitionKey)

	local ignitionPrompt = Instance.new("ProximityPrompt")
	ignitionPrompt.Name = "IgnitionPrompt"
	ignitionPrompt.ActionText = "Start Engine"
	ignitionPrompt.ObjectText = "Ignition"
	ignitionPrompt.HoldDuration = 0
	ignitionPrompt.ClickablePrompt = true
	ignitionPrompt.RequiresLineOfSight = false
	ignitionPrompt.MaxActivationDistance = 8
	ignitionPrompt.Parent = ignitionKey

	-- CarController finds every player car this way, so it doesn't need to
	-- know anything about how or where CarSpawner keeps track of them.
	CollectionService:AddTag(model, "PlayerCar")

	return model
end

return CarBuilder
