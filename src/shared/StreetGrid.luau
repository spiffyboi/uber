-- The street grid as a network: one node per intersection (avenue i meets
-- cross street j), joined along the avenues and cross streets. Shared by
-- IntersectionBuilder (which builds the crossings and traffic signals at
-- each node) and TrafficSpawner (whose cars drive node to node and stop for
-- those signals), so the two always agree on where the stop lines are and
-- what colour each light is showing.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))

local StreetGrid = {}

-- How far from an intersection's centre the stop line sits, for traffic
-- arriving along an avenue (the cross street's half width plus the
-- crosswalk) and along a cross street (the avenue's half width plus the
-- crosswalk).
StreetGrid.AVENUE_STOP = CityConfig.CROSS_STREET_WIDTH / 2 + 7
StreetGrid.CROSS_STOP = CityConfig.ROAD_WIDTH / 2 + 7

-- One signal cycle, in seconds: avenue green, yellow, a moment of red both
-- ways, then the same for the cross street. Avenues get the longer green.
local AVENUE_GREEN = 12
local AVENUE_YELLOW = 3
local CROSS_GREEN = 9
local CROSS_YELLOW = 3
local ALL_RED = 1.5
StreetGrid.CYCLE = AVENUE_GREEN + AVENUE_YELLOW + ALL_RED + CROSS_GREEN + CROSS_YELLOW + ALL_RED

export type Node = {
	i: number,
	j: number,
	key: string,
	position: Vector3,
	hasSignals: boolean,
	offset: number,
}

local nodes: { { Node } } = {}
for i, avenue in CityConfig.AVENUES do
	nodes[i] = {}
	for j, street in CityConfig.CROSS_STREETS do
		local outerAvenue = i == 1 or i == #CityConfig.AVENUES
		local outerStreet = j == 1 or j == #CityConfig.CROSS_STREETS
		nodes[i][j] = {
			i = i,
			j = j,
			key = `{i},{j}`,
			position = Vector3.new(avenue.x, 0, street.z),
			-- The four corners of the grid are just bends, with nothing to
			-- give way to; everywhere else gets signals.
			hasSignals = not (outerAvenue and outerStreet),
			-- Staggered so the whole city doesn't change colour at once.
			offset = ((i * 7 + j * 11) % 6) * (StreetGrid.CYCLE / 6),
		}
	end
end

function StreetGrid.node(i: number, j: number): Node?
	return nodes[i] and nodes[i][j]
end

function StreetGrid.allNodes(): { Node }
	local list = {}
	for i = 1, #nodes do
		for j = 1, #nodes[i] do
			table.insert(list, nodes[i][j])
		end
	end
	return list
end

-- "avenue" if travelling along `heading` means driving an avenue (along Z),
-- "cross" for a cross street (along X).
function StreetGrid.axisOf(heading: Vector3): string
	return if math.abs(heading.Z) > math.abs(heading.X) then "avenue" else "cross"
end

-- The four compass directions out of a node, as unit headings, and which
-- neighbouring node each one leads to.
local DIRECTIONS = {
	{ di = 0, dj = -1, heading = Vector3.new(0, 0, 1) }, -- toward the grid's top (+Z)
	{ di = 0, dj = 1, heading = Vector3.new(0, 0, -1) },
	{ di = -1, dj = 0, heading = Vector3.new(-1, 0, 0) },
	{ di = 1, dj = 0, heading = Vector3.new(1, 0, 0) },
}

-- Every street leaving `node`: the node at its far end and the heading to
-- drive it.
function StreetGrid.exits(node: Node): { { node: Node, heading: Vector3 } }
	local list = {}
	for _, direction in DIRECTIONS do
		local other = StreetGrid.node(node.i + direction.di, node.j + direction.dj)
		if other then
			table.insert(list, { node = other, heading = direction.heading })
		end
	end
	return list
end

-- The driver's right, for a car heading `heading` (traffic keeps right).
function StreetGrid.rightOf(heading: Vector3): Vector3
	return heading:Cross(Vector3.yAxis)
end

function StreetGrid.laneOffsets(axis: string): { number }
	return if axis == "avenue" then CityConfig.AVENUE_LANE_OFFSETS else CityConfig.CROSS_LANE_OFFSETS
end

function StreetGrid.stopDistance(axis: string): number
	return if axis == "avenue" then StreetGrid.AVENUE_STOP else StreetGrid.CROSS_STOP
end

-- "green", "yellow" or "red": what the signal at `node` shows traffic
-- travelling along `axis`.
function StreetGrid.signalState(node: Node, axis: string): string
	if not node.hasSignals then
		return "green"
	end
	local t = (workspace:GetServerTimeNow() + node.offset) % StreetGrid.CYCLE
	local avenueState
	if t < AVENUE_GREEN then
		avenueState = "green"
	elseif t < AVENUE_GREEN + AVENUE_YELLOW then
		avenueState = "yellow"
	else
		avenueState = "red"
	end
	if axis == "avenue" then
		return avenueState
	end
	local crossStart = AVENUE_GREEN + AVENUE_YELLOW + ALL_RED
	if t >= crossStart and t < crossStart + CROSS_GREEN then
		return "green"
	elseif t >= crossStart + CROSS_GREEN and t < crossStart + CROSS_GREEN + CROSS_YELLOW then
		return "yellow"
	end
	return "red"
end

return StreetGrid
