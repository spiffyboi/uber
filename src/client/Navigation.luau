-- Turn-by-turn guidance to wherever the player's headed (a fare's pickup,
-- then its drop-off): glowing chevrons painted down the road ahead along
-- the route, and a tall column of light standing at the destination with a
-- label and the distance to it. Everything here is local to this player's
-- screen. The route itself (see Routing) is shared with the minimap.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Routing = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Routing"))
local CityConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CityConfig"))

local Navigation = {}

local player = Players.LocalPlayer

local ARROW_SPACING = 14
local ARROW_REACH = 260 -- how far ahead along the route arrows are drawn
local ARROW_COUNT = math.floor(ARROW_REACH / ARROW_SPACING)
local ROUTE_REFRESH = 0.4
local ROAD_TOP = 1

local folder = Instance.new("Folder")
folder.Name = "Navigation"
folder.Parent = workspace

local target: Vector3? = nil
local targetColor = Color3.fromRGB(255, 196, 60)
local route: { Vector3 } = {}
local routeLength = 0
local sinceRefresh = math.huge
local changed = Instance.new("BindableEvent")
Navigation.RouteChanged = changed.Event

local function makePart(size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = folder
	return p
end

-- The chevrons: two short glowing bars each, in a "^" pointing the way.
type Chevron = { left: Part, right: Part }
local chevrons: { Chevron } = {}
for i = 1, ARROW_COUNT do
	chevrons[i] = {
		left = makePart(Vector3.new(0.7, 0.08, 3.2), targetColor),
		right = makePart(Vector3.new(0.7, 0.08, 3.2), targetColor),
	}
	chevrons[i].left.Transparency = 1
	chevrons[i].right.Transparency = 1
end

-- The column of light at the destination, with a label over it.
local beacon = makePart(Vector3.new(80, 3, 3), targetColor)
beacon.Shape = Enum.PartType.Cylinder
beacon.Transparency = 1
local ring = makePart(Vector3.new(0.2, 9, 9), targetColor)
ring.Shape = Enum.PartType.Cylinder
ring.Transparency = 1
local labelGui = Instance.new("BillboardGui")
labelGui.Size = UDim2.fromOffset(220, 56)
labelGui.StudsOffsetWorldSpace = Vector3.new(0, 14, 0)
labelGui.AlwaysOnTop = true
labelGui.LightInfluence = 0
labelGui.MaxDistance = 2000
labelGui.Enabled = false
labelGui.Adornee = ring
labelGui.Parent = folder
local labelTitle = Instance.new("TextLabel")
labelTitle.BackgroundTransparency = 1
labelTitle.Size = UDim2.new(1, 0, 0.6, 0)
labelTitle.Font = Enum.Font.GothamBold
labelTitle.TextScaled = true
labelTitle.TextColor3 = Color3.new(1, 1, 1)
labelTitle.TextStrokeTransparency = 0.3
labelTitle.Parent = labelGui
local labelDistance = Instance.new("TextLabel")
labelDistance.BackgroundTransparency = 1
labelDistance.Position = UDim2.fromScale(0, 0.6)
labelDistance.Size = UDim2.new(1, 0, 0.4, 0)
labelDistance.Font = Enum.Font.Gotham
labelDistance.TextScaled = true
labelDistance.TextColor3 = Color3.fromRGB(230, 230, 230)
labelDistance.TextStrokeTransparency = 0.3
labelDistance.Parent = labelGui

-- Where the player is: their cab if they're driving it, otherwise them.
function Navigation.origin(): Vector3?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if seat then
		return seat.Position
	end
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

-- Guide the player to `position` (nil to stop). `label` is what the column
-- of light says ("Pick up Ray").
function Navigation.setTarget(position: Vector3?, label: string?, color: Color3?)
	target = position
	-- The old route led somewhere else: drop it, and work out the new one
	-- straight away.
	route = {}
	routeLength = 0
	sinceRefresh = math.huge
	targetColor = color or Color3.fromRGB(255, 196, 60)
	for _, chevron in chevrons do
		chevron.left.Color = targetColor
		chevron.right.Color = targetColor
	end
	beacon.Color = targetColor
	ring.Color = targetColor
	labelTitle.Text = label or ""
	if position then
		beacon.CFrame = CFrame.new(position + Vector3.new(0, 40, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ring.CFrame = CFrame.new(position.X, ROAD_TOP + 0.12, position.Z) * CFrame.Angles(0, 0, math.rad(90))
		beacon.Transparency = 0.6
		ring.Transparency = 0.35
		labelGui.Enabled = true
	else
		beacon.Transparency = 1
		ring.Transparency = 1
		labelGui.Enabled = false
		for _, chevron in chevrons do
			chevron.left.Transparency = 1
			chevron.right.Transparency = 1
		end
		changed:Fire()
	end
end

function Navigation.getRoute(): ({ Vector3 }, number)
	return route, routeLength
end

function Navigation.getTarget(): Vector3?
	return target
end

-- What the column of light says, and its colour.
function Navigation.getLabel(): (string, Color3)
	return labelTitle.Text, targetColor
end

-- Lays the chevrons along the route, starting a little ahead of the player,
-- in the lane on the right of the direction of travel.
local function placeChevrons()
	local placed = 0
	if #route >= 2 then
		local walked = 0
		local nextAt = 10
		for i = 2, #route do
			local a, b = route[i - 1], route[i]
			local stretch = (b - a).Magnitude
			if stretch < 0.01 then
				continue
			end
			local along = (b - a).Unit
			local right = along:Cross(Vector3.yAxis)
			local onAvenue = math.abs(along.Z) > math.abs(along.X)
			local laneOffset = if onAvenue then CityConfig.LANE_WIDTH else CityConfig.CROSS_STREET_WIDTH / 4
			while nextAt <= walked + stretch and placed < ARROW_COUNT and nextAt <= ARROW_REACH do
				local point = a + along * (nextAt - walked) + right * laneOffset
				local base = CFrame.lookAt(Vector3.new(point.X, ROAD_TOP + 0.08, point.Z), Vector3.new(point.X, ROAD_TOP + 0.08, point.Z) + along)
				placed += 1
				local chevron = chevrons[placed]
				chevron.left.CFrame = base * CFrame.new(-0.85, 0, 0.7) * CFrame.Angles(0, math.rad(-35), 0)
				chevron.right.CFrame = base * CFrame.new(0.85, 0, 0.7) * CFrame.Angles(0, math.rad(35), 0)
				chevron.left.Transparency = 0.15
				chevron.right.Transparency = 0.15
				nextAt += ARROW_SPACING
			end
			walked += stretch
		end
	end
	for i = placed + 1, ARROW_COUNT do
		chevrons[i].left.Transparency = 1
		chevrons[i].right.Transparency = 1
	end
end

RunService.Heartbeat:Connect(function(dt)
	if not target then
		return
	end
	local from = Navigation.origin()
	if not from then
		return
	end
	sinceRefresh += dt
	if sinceRefresh >= ROUTE_REFRESH then
		sinceRefresh = 0
		local points, length = Routing.route(from, target)
		route = points
		routeLength = length
		placeChevrons()
		changed:Fire()
	end
	local distance = (Vector3.new(target.X, 0, target.Z) - Vector3.new(from.X, 0, from.Z)).Magnitude
	labelDistance.Text = if distance < 1000 then `{math.floor(distance)} studs` else string.format("%.1fk studs", distance / 1000)
	-- Fade the column out once you're right there.
	beacon.Transparency = if distance < 30 then 0.85 else 0.6
end)

return Navigation
