-- Shortest driving route between any two points in the city, along the
-- street grid (see StreetGrid). Used by the client's navigation (the arrows
-- on the road, the minimap's route line) and by the server's fares (the
-- quoted price is the route length).
--
-- A point anywhere in the city is first snapped onto its nearest stretch of
-- street; the route then runs from there to whichever end of that stretch
-- gets there quicker, junction to junction, and onto the stretch the
-- destination sits on. Turn rules and one-way streets don't exist here, so
-- this is simply the shortest way through the grid.

local StreetGrid = require(script.Parent.StreetGrid)

local Routing = {}

type Node = StreetGrid.Node
type Stretch = { a: Node, b: Node }

-- Every stretch of street between two neighbouring junctions, once each.
local stretches: { Stretch } = {}
for _, node in StreetGrid.allNodes() do
	for _, exit in StreetGrid.exits(node) do
		if exit.node.i > node.i or exit.node.j > node.j then
			table.insert(stretches, { a = node, b = exit.node })
		end
	end
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- The nearest point on the nearest stretch of street to `position`.
function Routing.locate(position: Vector3): (Stretch, Vector3)
	local p = flat(position)
	local best: Stretch? = nil
	local bestPoint = p
	local bestDistance = math.huge
	for _, stretch in stretches do
		local a, b = stretch.a.position, stretch.b.position
		local along = b - a
		local t = math.clamp((p - a):Dot(along) / along:Dot(along), 0, 1)
		local point = a + along * t
		local distance = (p - point).Magnitude
		if distance < bestDistance then
			best, bestPoint, bestDistance = stretch, point, distance
		end
	end
	return best :: Stretch, bestPoint
end

-- The route from `from` to `to`, as points along the centrelines of the
-- streets (snapped start, each junction passed through, snapped end), and
-- its length in studs.
function Routing.route(from: Vector3, to: Vector3): ({ Vector3 }, number)
	local startStretch, startPoint = Routing.locate(from)
	local endStretch, endPoint = Routing.locate(to)
	if startStretch == endStretch then
		return { startPoint, endPoint }, (endPoint - startPoint).Magnitude
	end

	-- Dijkstra from both ends of the starting stretch. Thirty junctions, so
	-- a plain scan for the nearest unvisited one is plenty fast.
	local distance: { [Node]: number } = {}
	local previous: { [Node]: Node } = {}
	local visited: { [Node]: boolean } = {}
	distance[startStretch.a] = (startStretch.a.position - startPoint).Magnitude
	distance[startStretch.b] = (startStretch.b.position - startPoint).Magnitude
	while true do
		local current: Node? = nil
		for node, d in distance do
			if not visited[node] and (current == nil or d < distance[current :: Node]) then
				current = node
			end
		end
		if current == nil then
			break
		end
		visited[current] = true
		for _, exit in StreetGrid.exits(current) do
			local d = distance[current] + (exit.node.position - current.position).Magnitude
			if distance[exit.node] == nil or d < distance[exit.node] then
				distance[exit.node] = d
				previous[exit.node] = current
			end
		end
	end

	local lastNode = endStretch.a
	local costA = (distance[endStretch.a] or math.huge) + (endStretch.a.position - endPoint).Magnitude
	local costB = (distance[endStretch.b] or math.huge) + (endStretch.b.position - endPoint).Magnitude
	if costB < costA then
		lastNode = endStretch.b
	end

	local nodes = {}
	local node: Node? = lastNode
	while node do
		table.insert(nodes, 1, node)
		node = previous[node]
	end
	local points = { startPoint }
	for _, n in nodes do
		table.insert(points, n.position)
	end
	table.insert(points, endPoint)
	return points, math.min(costA, costB)
end

-- Length of a route made of `points`.
function Routing.length(points: { Vector3 }): number
	local total = 0
	for i = 2, #points do
		total += (points[i] - points[i - 1]).Magnitude
	end
	return total
end

-- A short written name for where `position` is, like "Marrow St & Vail St"
-- or "Ashby Ave near Linden Ave", for fare cards and texts.
function Routing.placeName(position: Vector3): string
	local CityConfig = require(script.Parent.CityConfig)
	local nearestCross, crossDistance = nil, math.huge
	for _, street in CityConfig.CROSS_STREETS do
		local d = math.abs(position.Z - street.z)
		if d < crossDistance then
			nearestCross, crossDistance = street, d
		end
	end
	local nearestAvenue, avenueDistance = nil, math.huge
	for _, avenue in CityConfig.AVENUES do
		local d = math.abs(position.X - avenue.x)
		if d < avenueDistance then
			nearestAvenue, avenueDistance = avenue, d
		end
	end
	if avenueDistance < crossDistance or avenueDistance < 40 then
		if crossDistance < 30 then
			return `{nearestAvenue.name} & {nearestCross.name}`
		end
		return `{nearestAvenue.name} near {nearestCross.name}`
	end
	return `{nearestCross.name} near {nearestAvenue.name}`
end

return Routing
