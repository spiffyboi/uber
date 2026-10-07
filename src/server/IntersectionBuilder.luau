-- Dresses every intersection in the grid (see StreetGrid): zebra crossings
-- on each street meeting it, a white stop line across each approach, a
-- traffic signal for each approach on a mast arm reaching out over its
-- lanes (where a driver actually looks), and street-name blades on the
-- corner. The signals show whatever StreetGrid.signalState says, which is
-- the same thing TrafficSpawner's cars obey.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))
local StreetGrid = require(Shared:WaitForChild("StreetGrid"))
local BuildPacer = require(script.Parent.BuildPacer)

local IntersectionBuilder = {}

local ROAD_TOP = 1

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function paint(parent: Instance, name: string, size: Vector3, position: Vector3)
	local p = part(parent, name, size, CFrame.new(position), Color3.fromRGB(210, 210, 200))
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

-- Lens colours lit and unlit (unlit is the same glass, dark).
local LENSES = {
	{ key = "red", lit = Color3.fromRGB(255, 45, 40), dark = Color3.fromRGB(60, 16, 14), y = 1 },
	{ key = "yellow", lit = Color3.fromRGB(255, 190, 40), dark = Color3.fromRGB(60, 46, 12), y = 0 },
	{ key = "green", lit = Color3.fromRGB(40, 235, 120), dark = Color3.fromRGB(12, 54, 30), y = -1 },
}

type Head = { node: StreetGrid.Node, axis: string, lenses: { [string]: BasePart }, shown: string? }
local heads: { Head } = {}

local function streetSign(parent: Instance, cframe: CFrame, text: string)
	local blade = part(parent, "StreetSign", Vector3.new(5, 0.8, 0.12), cframe, Color3.fromRGB(20, 90, 60))
	blade.CanCollide = false
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0.4
		gui.MaxDistance = 250
		gui.Parent = blade
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.Oswald
		label.Text = text:upper()
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextScaled = true
		label.Parent = gui
	end
end

-- A signal for traffic arriving at `node` heading `heading`: a pole on the
-- far right-hand corner, an arm out over the approach's lanes, and the
-- lamp hanging from it facing the oncoming cars.
local function buildSignal(parent: Instance, node: StreetGrid.Node, heading: Vector3, farSideOpen: boolean)
	local axis = StreetGrid.axisOf(heading)
	local right = StreetGrid.rightOf(heading)
	local approachHalfWidth = if axis == "avenue" then CityConfig.ROAD_WIDTH / 2 else CityConfig.CROSS_STREET_WIDTH / 2
	local otherHalfWidth = if axis == "avenue" then CityConfig.CROSS_STREET_WIDTH / 2 else CityConfig.ROAD_WIDTH / 2
	-- Past the far crosswalk if there's a street on the far side; on the
	-- sidewalk right behind the junction if it's a T.
	local along = if farSideOpen then otherHalfWidth + 8 else otherHalfWidth + 3
	local poleOut = approachHalfWidth + 2.5
	local base = node.position + heading * along + right * poleOut

	local metal = Color3.fromRGB(28, 30, 32)
	local poleHeight = 17
	part(parent, "SignalPole", Vector3.new(0.7, poleHeight, 0.7), CFrame.new(base + Vector3.new(0, ROAD_TOP + poleHeight / 2, 0)), metal)

	-- The arm reaches back over the lanes to about the middle of them.
	local armLength = poleOut - approachHalfWidth / 2
	local armY = ROAD_TOP + poleHeight - 0.6
	local armMid = base - right * (armLength / 2) + Vector3.new(0, armY, 0)
	part(parent, "SignalArm", Vector3.new(0.4, 0.4, armLength), CFrame.lookAt(armMid, armMid + right), metal)

	-- Facing back toward the cars it's for.
	local headCenter = base - right * armLength + Vector3.new(0, armY - 2.4, 0)
	local facing = CFrame.lookAt(headCenter, headCenter - heading)
	part(parent, "SignalHanger", Vector3.new(0.2, 0.8, 0.2), CFrame.new(headCenter + Vector3.new(0, 2.2, 0)), metal)
	part(parent, "SignalBackplate", Vector3.new(2.3, 4.2, 0.1), facing * CFrame.new(0, 0, 0.55), Color3.fromRGB(14, 14, 16))
	part(parent, "SignalHousing", Vector3.new(1.4, 3.6, 1), facing, Color3.fromRGB(30, 30, 20))

	local lenses = {}
	for _, lens in LENSES do
		local bulb = part(parent, "Lens_" .. lens.key, Vector3.new(0.2, 0.95, 0.95), facing * CFrame.new(0, lens.y * 1.12, -0.52) * CFrame.Angles(0, math.rad(90), 0), lens.dark)
		bulb.Shape = Enum.PartType.Cylinder
		bulb.CanCollide = false
		bulb.CastShadow = false
		local visor = part(parent, "Visor", Vector3.new(1.1, 0.1, 0.5), facing * CFrame.new(0, lens.y * 1.12 + 0.52, -0.75), Color3.fromRGB(30, 30, 20))
		visor.CanCollide = false
		visor.CastShadow = false
		lenses[lens.key] = bulb
	end
	table.insert(heads, { node = node, axis = axis, lenses = lenses })
	return base
end

-- Zebra stripes across a street meeting the junction. `center` is the
-- middle of the crossing, `across` the unit direction to walk it,
-- `width` the street's width.
local function crosswalk(parent: Instance, center: Vector3, across: Vector3, width: number)
	local along = Vector3.yAxis:Cross(across)
	local count = math.floor(width / 3.5)
	for k = 0, count - 1 do
		local offset = (k - (count - 1) / 2) * 3.5
		local p = center + across * offset + Vector3.new(0, ROAD_TOP + 0.03, 0)
		local stripe = paint(parent, "Crosswalk", Vector3.new(1.6, 0.05, 4.5), p)
		stripe.CFrame = CFrame.lookAt(p, p + along)
	end
end

local function compass(heading: Vector3): string
	if heading.X > 0.5 then
		return "E"
	elseif heading.X < -0.5 then
		return "W"
	end
	return if heading.Z > 0 then "N" else "S"
end

local function buildIntersection(parent: Instance, node: StreetGrid.Node)
	local folder = Instance.new("Folder")
	folder.Name = "Intersection_" .. node.key
	folder.Parent = parent

	local exits = StreetGrid.exits(node)
	local open: { [string]: boolean } = {}
	for _, exit in exits do
		open[compass(exit.heading)] = true
	end

	for _, exit in exits do
		local axis = StreetGrid.axisOf(exit.heading)
		local width = if axis == "avenue" then CityConfig.ROAD_WIDTH else CityConfig.CROSS_STREET_WIDTH
		local otherHalf = if axis == "avenue" then CityConfig.CROSS_STREET_WIDTH / 2 else CityConfig.ROAD_WIDTH / 2
		local right = StreetGrid.rightOf(exit.heading)
		crosswalk(folder, node.position + exit.heading * (otherHalf + 3.5), right, width)

		if node.hasSignals then
			-- The approach that arrives along this street (driving the other
			-- way, toward the node): its stop line, and its signal across the
			-- junction.
			local inbound = -exit.heading
			local inboundRight = StreetGrid.rightOf(inbound)
			local stopAt = node.position + exit.heading * (StreetGrid.stopDistance(axis) - 0.5) + inboundRight * (width / 4)
			local line = paint(folder, "StopLine", Vector3.new(width / 2 - 1, 0.05, 0.8), stopAt + Vector3.new(0, ROAD_TOP + 0.03, 0))
			line.CFrame = CFrame.lookAt(line.Position, line.Position + inbound)

			local farOpen = open[compass(inbound)] == true
			local poleBase = buildSignal(folder, node, inbound, farOpen)

			-- Street names on the avenue approaches' poles: each blade runs
			-- parallel to the street it names, reaching in toward the
			-- junction.
			if axis == "avenue" then
				local signAt = poleBase + Vector3.new(0, ROAD_TOP + 9.5, 0)
				local toNode = node.position - poleBase
				local alongAvenue = Vector3.new(0, 0, math.sign(toNode.Z))
				local alongCross = Vector3.new(math.sign(toNode.X), 0, 0)
				streetSign(folder, CFrame.fromMatrix(signAt + alongAvenue * 2.6, Vector3.zAxis, Vector3.yAxis), CityConfig.AVENUES[node.i].name)
				streetSign(folder, CFrame.fromMatrix(signAt + Vector3.new(0, -0.9, 0) + alongCross * 2.6, Vector3.xAxis, Vector3.yAxis), CityConfig.CROSS_STREETS[node.j].name)
			end
		end
	end
end

-- Repaints each signal's lit lens when its state changes (only then, so
-- nothing is sent to players between changes).
local function startSignalLoop()
	task.spawn(function()
		while true do
			for _, head in heads do
				local state = StreetGrid.signalState(head.node, head.axis)
				if state ~= head.shown then
					head.shown = state
					for _, lens in LENSES do
						local bulb = head.lenses[lens.key]
						local isLit = lens.key == state
						bulb.Color = if isLit then lens.lit else lens.dark
						bulb.Material = if isLit then Enum.Material.Neon else Enum.Material.SmoothPlastic
					end
				end
			end
			task.wait(0.2)
		end
	end)
end

function IntersectionBuilder.build(root: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Intersections"
	folder.Parent = root
	for _, node in StreetGrid.allNodes() do
		BuildPacer.breathe()
		buildIntersection(folder, node)
	end
	startSignalLoop()
end

return IntersectionBuilder
