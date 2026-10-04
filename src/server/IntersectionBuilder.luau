-- Cross streets at a couple of points along the opening strip -- the rest of
-- the strip is one continuous block of buildings with no way through, which
-- read as a movie backlot rather than an actual grid of city blocks. Each
-- intersection gets a real perpendicular street (not just a painted gap),
-- a crosswalk, four pole-mounted traffic signals that actually cycle, and
-- street-name signage at the corners. Traffic (see TrafficSpawner) only
-- ever drives the main road, so the cross streets themselves are dressing,
-- not a driveable grid -- but the signals it reads are these same ones.

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))

local IntersectionBuilder = {}

local CROSS_STREET_NAMES = { "Delano Ave", "Kesting St" }

-- One shared signal cycle for every intersection in the scene -- they all
-- switch in lockstep. Real asynchronous timing across intersections would
-- need per-intersection state and a lot more traffic-AI complexity (yielding
-- at conflicting lights, etc.) for very little visible payoff at this scope;
-- a single shared phase still gives real stop-and-go traffic without that.
local MAIN_GREEN_TIME = 8
local MAIN_YELLOW_TIME = 2
local CROSS_GREEN_TIME = 8
local CROSS_YELLOW_TIME = 2
local CYCLE_TIME = MAIN_GREEN_TIME + MAIN_YELLOW_TIME + CROSS_GREEN_TIME + CROSS_YELLOW_TIME

local cycleStart = os.clock()

-- "green" | "yellow" | "red", read by TrafficSpawner for the main road, and
-- by this module's own signal-head repaint loop for both roads.
local function mainRoadState(): string
	local t = (os.clock() - cycleStart) % CYCLE_TIME
	if t < MAIN_GREEN_TIME then
		return "green"
	elseif t < MAIN_GREEN_TIME + MAIN_YELLOW_TIME then
		return "yellow"
	else
		return "red"
	end
end

local function crossStreetState(): string
	local t = (os.clock() - cycleStart) % CYCLE_TIME
	local crossStart = MAIN_GREEN_TIME + MAIN_YELLOW_TIME
	if t < crossStart then
		return "red"
	elseif t < crossStart + CROSS_GREEN_TIME then
		return "green"
	else
		return "yellow"
	end
end

-- Read by TrafficSpawner: which state the main-road signal nearest `z`
-- currently shows, so a car approaching that intersection knows whether to
-- keep going or slow to a stop at the line.
function IntersectionBuilder.getMainRoadState(): string
	return mainRoadState()
end

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

-- A single red/yellow/green lens stack, mounted on `pole` facing `facing`
-- (a unit -Z-relative look direction achieved via the pole's own CFrame), and
-- registered so the repaint loop below can keep its lit lens in sync with
-- whichever `stateFn` it was built to watch (mainRoadState or
-- crossStreetState -- different corners of the same intersection watch
-- different roads).
local signalHeads: { { lenses: { red: BasePart, yellow: BasePart, green: BasePart }, stateFn: () -> string } } = {}

-- `groundPosition`'s Y is ignored -- the pole always plants its own base at
-- Y=0 and builds upward, so every call site only has to know the ground
-- (X, Z) spot to stand it on, not the pole's own half-height math.
local function buildSignalHead(root: Instance, groundPosition: Vector3, facing: CFrame, stateFn: () -> string)
	local POLE_HEIGHT = 11
	local base = Vector3.new(groundPosition.X, 0, groundPosition.Z)

	local pole = part("SignalPole", Vector3.new(0.6, POLE_HEIGHT, 0.6), CFrame.new(base + Vector3.new(0, POLE_HEIGHT / 2, 0)) * facing, Color3.fromRGB(25, 25, 28), Enum.Material.SmoothPlastic)
	pole.Parent = root

	local housing = part("SignalHousing", Vector3.new(0.9, 2.4, 0.7), CFrame.new(base + Vector3.new(0, POLE_HEIGHT - 1.5, 0)) * facing, Color3.fromRGB(15, 15, 17), Enum.Material.SmoothPlastic)
	housing.Parent = root

	local lenses = {}
	local order = { { key = "red", color = Color3.fromRGB(230, 40, 40), y = 0.75 }, { key = "yellow", color = Color3.fromRGB(235, 195, 40), y = 0 }, { key = "green", color = Color3.fromRGB(50, 210, 90), y = -0.75 } }
	for _, lens in order do
		local bulb = Instance.new("Part")
		bulb.Name = "Lens_" .. lens.key
		bulb.Shape = Enum.PartType.Ball
		bulb.Size = Vector3.new(0.45, 0.45, 0.45)
		bulb.Color = lens.color
		bulb.Material = Enum.Material.SmoothPlastic
		bulb.CanCollide = false
		bulb.Anchored = true
		bulb.CFrame = housing.CFrame * CFrame.new(0, lens.y, -0.4)
		bulb.Parent = root
		lenses[lens.key] = bulb
	end

	table.insert(signalHeads, { lenses = lenses, stateFn = stateFn })
end

-- Repaints every signal head's lit lens (Neon + a short-range glow while
-- active, plain SmoothPlastic and dark while not) to match its own state
-- function. One shared loop for every head in the scene rather than a
-- per-head loop, since they're all just reading the same couple of clocks.
local function startSignalLoop()
	task.spawn(function()
		while true do
			for _, head in signalHeads do
				local active = head.stateFn()
				for key, bulb in head.lenses do
					local isLit = key == active
					bulb.Material = if isLit then Enum.Material.Neon else Enum.Material.SmoothPlastic
					local light = bulb:FindFirstChildOfClass("PointLight")
					if isLit and not light then
						light = Instance.new("PointLight")
						light.Range = 8
						light.Brightness = 1.2
						light.Parent = bulb
					end
					if light then
						light.Enabled = isLit
						light.Color = bulb.Color
					end
				end
			end
			task.wait(0.25)
		end
	end)
end

-- White zebra-stripe crosswalk across `width` studs of road, centred on
-- `center`, striping along `axis` ("x" for a crossing that runs along X --
-- i.e. painted across a road that runs along Z -- or "z" for the reverse).
local function buildCrosswalk(root: Instance, center: Vector3, width: number, axis: "x" | "z")
	local stripeCount = math.floor(width / 3)
	for i = 0, stripeCount - 1 do
		local offset = -width / 2 + 1.5 + i * 3
		local size = if axis == "x" then Vector3.new(1.2, 0.05, 4) else Vector3.new(4, 0.05, 1.2)
		-- Road/CrossStreet slabs are 1 stud thick centred at Y=0.5 (top face
		-- at Y=1) -- stripes sit just above that top face, not at Y=0.53
		-- (which would bury them inside the asphalt, invisible).
		local pos = if axis == "x" then center + Vector3.new(offset, 1.03, 0) else center + Vector3.new(0, 1.03, offset)
		local stripe = part("CrosswalkStripe", size, CFrame.new(pos), Color3.fromRGB(210, 210, 200), Enum.Material.SmoothPlastic)
		stripe.CanCollide = false
		stripe.Parent = root
	end
end

-- A small green NYC-style street-name blade, mounted just under a signal
-- pole's housing so each corner reads which two streets actually cross here.
local function buildStreetSign(root: Instance, position: Vector3, facing: CFrame, text: string)
	local blade = part("StreetSign", Vector3.new(3.2, 0.6, 0.1), CFrame.new(position) * facing, Color3.fromRGB(20, 90, 60), Enum.Material.SmoothPlastic)
	blade.Parent = root

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 40
	gui.Parent = blade

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Font = Enum.Font.Oswald
	label.Text = text:upper()
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Parent = gui
end

local function buildIntersection(root: Instance, z: number, crossName: string)
	local halfMain = CityConfig.ROAD_WIDTH / 2
	local halfCross = CityConfig.CROSS_STREET_WIDTH / 2

	-- The cross street itself: a perpendicular strip of asphalt punched
	-- through the building row (see OpeningSetBuilder.buildBuildingRow,
	-- which leaves this exact block index empty), plus its own short
	-- sidewalks and kerb-to-kerb crosswalks on both roads.
	local crossRoad = part(
		"CrossStreet",
		Vector3.new(CityConfig.CROSS_STREET_HALF_LENGTH * 2 + CityConfig.ROAD_WIDTH, 1, CityConfig.CROSS_STREET_WIDTH),
		CFrame.new(0, 0.5, z),
		Color3.fromRGB(35, 35, 38),
		Enum.Material.Asphalt
	)
	crossRoad.Parent = root

	-- Sidewalks flanking the cross street's own two outward stubs (west and
	-- east of the main road), one on each side of it -- the same pattern
	-- buildRoad uses for the main road's own sidewalks, just rotated: a
	-- stub's length runs along X here instead of Z.
	local stubLength = CityConfig.CROSS_STREET_HALF_LENGTH - halfMain
	for stubSide = -1, 1, 2 do
		local stubCenterX = stubSide * (halfMain + stubLength / 2)
		for flank = -1, 1, 2 do
			local stub = part(
				"CrossSidewalk",
				Vector3.new(stubLength, 1.2, CityConfig.SIDEWALK_WIDTH),
				CFrame.new(stubCenterX, 0.6, z + flank * (halfCross + CityConfig.SIDEWALK_WIDTH / 2)),
				Color3.fromRGB(90, 90, 92),
				Enum.Material.Concrete
			)
			stub.Parent = root
		end
	end

	buildCrosswalk(root, Vector3.new(0, 0, z - halfCross - 3), CityConfig.ROAD_WIDTH, "x")
	buildCrosswalk(root, Vector3.new(0, 0, z + halfCross + 3), CityConfig.ROAD_WIDTH, "x")
	buildCrosswalk(root, Vector3.new(halfMain + 3, 0, z), CityConfig.CROSS_STREET_WIDTH, "z")
	buildCrosswalk(root, Vector3.new(-halfMain - 3, 0, z), CityConfig.CROSS_STREET_WIDTH, "z")

	-- Main-road signals: mounted just past the intersection on the exit
	-- side, facing back at the traffic approaching it (the standard "you see
	-- it beyond the crosswalk" placement), so TrafficSpawner's cars have
	-- something to actually be stopping for in frame, not behind them.
	buildSignalHead(root, Vector3.new(halfMain + 1.5, 0, z - halfCross - 6), CFrame.Angles(0, math.pi, 0), mainRoadState)
	buildSignalHead(root, Vector3.new(-halfMain - 1.5, 0, z + halfCross + 6), CFrame.new(), mainRoadState)

	-- Cross-street signals: decorative (no AI drives the cross street this
	-- pass) but real, cycling opposite the main road's own state.
	buildSignalHead(root, Vector3.new(halfMain + halfCross + 6, 0, halfCross + z + 1.5), CFrame.Angles(0, -math.pi / 2, 0), crossStreetState)
	buildSignalHead(root, Vector3.new(-halfMain - halfCross - 6, 0, -halfCross + z - 1.5), CFrame.Angles(0, math.pi / 2, 0), crossStreetState)

	buildStreetSign(root, Vector3.new(halfMain + 2.5, 8.4, z - halfCross - 6), CFrame.Angles(0, math.pi, 0), CityConfig.DISTRICT_NICKNAME .. " St")
	buildStreetSign(root, Vector3.new(halfMain + 2.2, 7.6, z - halfCross - 6), CFrame.Angles(0, math.pi, 0), crossName)
end

function IntersectionBuilder.build(root: Instance)
	for i, z in CityConfig.INTERSECTION_Z do
		buildIntersection(root, z, CROSS_STREET_NAMES[i] or "Side St")
	end
	startSignalLoop()
end

return IntersectionBuilder
