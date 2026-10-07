-- A drawn map of the street grid, centred on the player, north up: used for
-- the minimap in the top right and the Map app on the phone. Shows the
-- streets, the parks, the route to wherever you're headed and the
-- destination, with an arrow in the middle turning to the way you face.
--
-- North up rather than turning with the camera, on purpose: a turning map
-- needs its rotated contents clipped to the minimap's edge, and the only
-- thing that does that (a CanvasGroup) falls back to not clipping at all on
-- lower graphics settings -- confirmed live, the whole city spilled out
-- over the top right of the screen. Unrotated, ClipsDescendants works
-- everywhere; and every street here runs north-south or east-west, so the
-- route is drawn from plain unrotated bars too.

local CityConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("CityConfig"))

local MapView = {}
MapView.__index = MapView

-- The world area the map covers.
local MIN_X, MAX_X = CityConfig.GRID_LEFT_X - 140, CityConfig.GRID_RIGHT_X + 140
local MIN_Z, MAX_Z = CityConfig.GRID_BOTTOM_Z - 120, CityConfig.GRID_TOP_Z + 120

local BLOCK_COLOR = Color3.fromRGB(34, 34, 40)
local STREET_COLOR = Color3.fromRGB(92, 94, 104)
local MAIN_STREET_COLOR = Color3.fromRGB(120, 116, 104)
local PARK_COLOR = Color3.fromRGB(40, 78, 46)
local ROUTE_COLOR = Color3.fromRGB(255, 196, 60)

export type Options = {
	size: number, -- pixels square
	scale: number, -- pixels per stud
}

local function rect(parent: Instance, color: Color3, x: number, y: number, w: number, h: number, z: number?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

function MapView.new(parent: Instance, options: Options)
	local self = setmetatable({}, MapView)
	self.options = options
	local scale = options.scale

	local container = Instance.new("Frame")
	container.Name = "Map"
	container.Size = UDim2.fromOffset(options.size, options.size)
	container.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.Parent = parent
	self.container = container

	-- The whole city, slid about so the player's spot sits in the middle.
	local world = Instance.new("Frame")
	world.Name = "World"
	world.BackgroundColor3 = BLOCK_COLOR
	world.BorderSizePixel = 0
	world.Size = UDim2.fromOffset((MAX_X - MIN_X) * scale, (MAX_Z - MIN_Z) * scale)
	world.Parent = container
	self.world = world

	local function toMap(x: number, z: number): (number, number)
		return (x - MIN_X) * scale, (MAX_Z - z) * scale
	end
	self.toMap = toMap

	-- Parks.
	for _, lot in CityConfig.LOTS do
		if lot.kind == "park" then
			local near, far = CityConfig.lotZRange(lot)
			local edge = lot.x + lot.side * CityConfig.BUILDING_EDGE
			local x1, x2 = edge, edge + lot.side * 100
			local px, py = toMap(math.min(x1, x2), near)
			rect(world, PARK_COLOR, px, py, 100 * scale, (near - far) * scale, 2)
		end
	end

	-- Streets.
	local roadW = math.max(3, CityConfig.ROAD_WIDTH * scale)
	local crossW = math.max(2, CityConfig.CROSS_STREET_WIDTH * scale)
	local top, bottom = CityConfig.GRID_TOP_Z + 11, CityConfig.GRID_BOTTOM_Z - 11
	for _, street in CityConfig.CROSS_STREETS do
		local px, py = toMap(CityConfig.GRID_LEFT_X, street.z)
		rect(world, STREET_COLOR, px, py - crossW / 2, (CityConfig.GRID_RIGHT_X - CityConfig.GRID_LEFT_X) * scale, crossW, 3)
	end
	for _, avenue in CityConfig.AVENUES do
		local px, py = toMap(avenue.x, top)
		local color = if avenue.x == CityConfig.MAIN_AVENUE_X then MAIN_STREET_COLOR else STREET_COLOR
		rect(world, color, px - roadW / 2, py, roadW, (top - bottom) * scale, 3)
	end

	self.routeBars = {}

	local target = Instance.new("Frame")
	target.Name = "Target"
	target.AnchorPoint = Vector2.new(0.5, 0.5)
	target.Size = UDim2.fromOffset(12, 12)
	target.BackgroundColor3 = ROUTE_COLOR
	target.BorderSizePixel = 0
	target.Visible = false
	target.ZIndex = 6
	local targetCorner = Instance.new("UICorner")
	targetCorner.CornerRadius = UDim.new(1, 0)
	targetCorner.Parent = target
	local targetStroke = Instance.new("UIStroke")
	targetStroke.Color = Color3.new(0, 0, 0)
	targetStroke.Thickness = 2
	targetStroke.Parent = target
	target.Parent = world
	self.target = target

	-- You: an arrowhead in the middle, turning to the way you're facing.
	local marker = Instance.new("TextLabel")
	marker.Name = "You"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.Size = UDim2.fromOffset(22, 22)
	marker.BackgroundTransparency = 1
	marker.Font = Enum.Font.GothamBold
	marker.TextSize = 20
	marker.Text = "▲"
	marker.TextColor3 = Color3.fromRGB(80, 200, 255)
	marker.TextStrokeTransparency = 0
	marker.ZIndex = 10
	marker.Parent = container
	self.marker = marker

	local north = Instance.new("TextLabel")
	north.Name = "North"
	north.AnchorPoint = Vector2.new(0.5, 0)
	north.Position = UDim2.new(0.5, 0, 0, 3)
	north.Size = UDim2.fromOffset(18, 16)
	north.BackgroundTransparency = 1
	north.Font = Enum.Font.GothamBold
	north.TextSize = 13
	north.TextColor3 = Color3.fromRGB(240, 90, 80)
	north.TextStrokeTransparency = 0.3
	north.Text = "N"
	north.ZIndex = 11
	north.Parent = container

	return self
end

-- Redraws the route (only needed when it changes), in `color` (gold for
-- fares, red for the story).
function MapView:setRoute(points: { Vector3 }?, color: Color3?)
	local bars = self.routeBars
	local count = 0
	local thickness = 4
	if points then
		for i = 2, #points do
			local x1, y1 = self.toMap(points[i - 1].X, points[i - 1].Z)
			local x2, y2 = self.toMap(points[i].X, points[i].Z)
			if math.abs(x2 - x1) < 0.5 and math.abs(y2 - y1) < 0.5 then
				continue
			end
			count += 1
			local bar = bars[count]
			if not bar then
				bar = Instance.new("Frame")
				bar.BackgroundColor3 = ROUTE_COLOR
				bar.BorderSizePixel = 0
				bar.ZIndex = 5
				bar.Parent = self.world
				bars[count] = bar
			end
			-- Every stretch runs north-south or east-west: a plain box
			-- covering it, thickened across.
			bar.Visible = true
			bar.BackgroundColor3 = color or ROUTE_COLOR
			bar.Position = UDim2.fromOffset(math.min(x1, x2) - thickness / 2, math.min(y1, y2) - thickness / 2)
			bar.Size = UDim2.fromOffset(math.abs(x2 - x1) + thickness, math.abs(y2 - y1) + thickness)
		end
	end
	for i = count + 1, #bars do
		bars[i].Visible = false
	end
end

function MapView:setTarget(position: Vector3?, color: Color3?)
	if position then
		local x, y = self.toMap(position.X, position.Z)
		self.target.Position = UDim2.fromOffset(x, y)
		self.target.BackgroundColor3 = color or ROUTE_COLOR
		self.target.Visible = true
	else
		self.target.Visible = false
	end
end

-- Centres the map on `focus`, the arrow pointing along `look`.
function MapView:update(focus: Vector3, look: Vector3)
	local fx, fy = self.toMap(focus.X, focus.Z)
	local half = self.options.size / 2
	self.world.Position = UDim2.fromOffset(half - fx, half - fy)
	-- On the map, +x is east and +y is south (world -Z). The arrow's
	-- glyph points up (north) unturned.
	self.marker.Rotation = math.deg(math.atan2(-look.Z, look.X)) + 90
end

return MapView
