-- The cab driving itself, for a cutscene (chapter 9's monologue, chapter
-- 10's Ray at the wheel): along a path the server worked out (see
-- StoryService's drivePath -- the route to somewhere, in the right-hand
-- lane), on this screen only, smoothly -- pulling away, easing round the
-- corners, slowing to a stop at the end. The server puts the real cab where
-- this one stops once the scene's over.
--
-- `jam`: a queue of traffic stopped ahead at the end of the path, brake
-- lights on, which the cab pulls up behind -- and which moves off again
-- when told (jamMoves).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SelfDrive = {}

local player = Players.LocalPlayer

export type Drive = {
	stop: () -> (),
	steer: () -> number, -- -1 (hard left) .. 1 (hard right), smoothed
	speed: () -> number, -- studs a second
	finished: () -> boolean,
	jamMoves: () -> (),
	heading: () -> Vector3,
}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- How far along (0..1) at time `t` (0..1): speeding up over the first
-- `a`, steady, slowing to a stop over the last `d`.
local function profile(t: number, a: number, d: number): number
	local top = 1 / (1 - a / 2 - d / 2)
	if t < a then
		return top * t * t / (2 * a)
	elseif t < 1 - d then
		return top * (a / 2 + (t - a))
	end
	local u = 1 - t
	return 1 - top * u * u / (2 * d)
end

local PAINTS = {
	Color3.fromRGB(22, 22, 26),
	Color3.fromRGB(150, 152, 158),
	Color3.fromRGB(100, 22, 28),
	Color3.fromRGB(26, 44, 86),
	Color3.fromRGB(205, 202, 192),
}
local CAB_YELLOW = Color3.fromRGB(255, 176, 0)

-- A stopped car in the queue: the traffic's own cab model, repainted, its
-- brake lights on.
local function jamCar(at: CFrame, paint: Color3): Model?
	local assets = ReplicatedStorage:FindFirstChild("CityAssets")
	local template = assets and assets:FindFirstChild("TaxiLite") :: Model?
	if not template or not template.PrimaryPart then
		return nil
	end
	local car = template:Clone()
	car.Name = "JamCar"
	local _, extents = template:GetBoundingBox()
	local groundY = -template.PrimaryPart.Position.Y
	for _, part in car:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			local c = part.Color
			if math.abs(c.R - CAB_YELLOW.R) < 0.12 and math.abs(c.G - CAB_YELLOW.G) < 0.12 and math.abs(c.B - CAB_YELLOW.B) < 0.15 then
				part.Color = paint
			end
		elseif part:IsA("Decal") or part:IsA("SurfaceGui") or part:IsA("BillboardGui") then
			part:Destroy()
		end
	end
	for _, side in { -1, 1 } do
		local tail = Instance.new("Part")
		tail.Name = "BrakeLight"
		tail.Size = Vector3.new(0.6, 0.6, 0.12)
		tail.Color = Color3.fromRGB(255, 30, 24)
		tail.Material = Enum.Material.Neon
		tail.Anchored = true
		tail.CanCollide = false
		tail.CanQuery = false
		tail.CFrame = car.PrimaryPart.CFrame * CFrame.new(side * extents.X * 0.4, groundY + 2.6, extents.Z / 2 + 0.05)
		tail.Parent = car
		local glow = Instance.new("SurfaceLight")
		glow.Face = Enum.NormalId.Back
		glow.Color = tail.Color
		glow.Brightness = 3
		glow.Range = 8
		glow.Parent = tail
	end
	car:PivotTo(at)
	car.Parent = workspace
	return car
end

-- Starts the drive: `path` = { points, y, jam } from the server, covered
-- in `seconds`. `riders`: models (Ray, the driver's double) kept where they
-- are relative to the driver's seat as the cab moves.
function SelfDrive.start(path, seconds: number, riders: { Model }?): Drive
	local car = workspace:FindFirstChild(player.Name .. "_Car") :: Model?
	local chassis = car and car.PrimaryPart
	local points = path.points
	local nothing: Drive = {
		stop = function() end,
		steer = function()
			return 0
		end,
		speed = function()
			return 0
		end,
		finished = function()
			return true
		end,
		jamMoves = function() end,
		heading = function()
			return Vector3.zAxis
		end,
	}
	if not car or not chassis or #points < 2 then
		return nothing
	end
	local carOffset = chassis.CFrame:Inverse() * car:GetPivot()
	-- The dash screen says what the engine's doing ("ENGINE OFF", as far as
	-- the game knows); not while it's driving itself.
	local gps = car:FindFirstChild("GpsUnit")
	local gpsScreen = gps and gps:FindFirstChildOfClass("SurfaceGui")
	if gpsScreen then
		gpsScreen.Enabled = false
	end
	local seat = car:FindFirstChild("DriveSeat") :: BasePart?
	-- Riders, relative to the seat.
	local riderOffsets = {}
	for _, rider in riders or {} do
		if seat then
			riderOffsets[rider] = seat.CFrame:Inverse() * rider:GetPivot()
		end
	end
	local character = player.Character
	local characterOffset = if seat and character then seat.CFrame:Inverse() * character:GetPivot() else nil

	-- Distance along the path to each point.
	local along = { 0 }
	for i = 2, #points do
		along[i] = along[i - 1] + (points[i] - points[i - 1]).Magnitude
	end
	local total = along[#along]
	local function pointAt(s: number): Vector3
		s = math.clamp(s, 0, total)
		for i = 2, #points do
			if s <= along[i] or i == #points then
				local length = along[i] - along[i - 1]
				local f = if length > 0 then (s - along[i - 1]) / length else 0
				return points[i - 1]:Lerp(points[i], math.clamp(f, 0, 1))
			end
		end
		return points[#points]
	end
	local lastDir = flat(points[#points] - points[#points - 1]).Unit

	-- The queue ahead, past the end of the path.
	local jam: { Model } = {}
	if path.jam then
		local finish = points[#points]
		-- Sat on the road (top at 1): the template's root is its own height
		-- above the ground.
		local assets = ReplicatedStorage:FindFirstChild("CityAssets")
		local template = assets and assets:FindFirstChild("TaxiLite") :: Model?
		local rootY = 1 + (if template and template.PrimaryPart then template.PrimaryPart.Position.Y else 2.2)
		for k = 1, 3 do
			local at = finish + lastDir * (10.5 + (k - 1) * 10)
			local base = Vector3.new(at.X, rootY, at.Z)
			local c = jamCar(CFrame.lookAt(base, base + lastDir), PAINTS[(k % #PAINTS) + 1])
			if c then
				table.insert(jam, c)
			end
		end
	end

	local started = os.clock()
	local heading = flat(points[2] - points[1]).Unit
	local steer = 0
	local speed = 0
	local lastS = 0
	local done = false
	local connection = RunService.RenderStepped:Connect(function(dt)
		local t = math.clamp((os.clock() - started) / seconds, 0, 1)
		local s = profile(t, 0.12, 0.28) * total
		speed = (s - lastS) / math.max(dt, 1e-3)
		lastS = s
		local pos = pointAt(s)
		-- Facing a little way ahead along the path, so the corners are
		-- turned into rather than snapped round.
		local ahead = pointAt(s + 8)
		local want = flat(ahead - pos)
		if want.Magnitude < 0.5 then
			want = lastDir
		end
		local before = heading
		heading = heading:Lerp(want.Unit, math.clamp(dt * 5, 0, 1)).Unit
		local turn = math.atan2(before:Cross(heading).Y, before:Dot(heading))
		local rate = turn / math.max(dt, 1e-3)
		steer += (math.clamp(-rate * 1.6, -1, 1) - steer) * math.clamp(dt * 4, 0, 1)
		local at = Vector3.new(pos.X, path.y, pos.Z)
		local chassisAt = CFrame.lookAt(at, at + heading)
		car:PivotTo(chassisAt * carOffset)
		if seat then
			for rider, offset in riderOffsets do
				if rider.Parent then
					rider:PivotTo(seat.CFrame * offset)
				end
			end
			if characterOffset and character and character.Parent then
				character:PivotTo(seat.CFrame * characterOffset)
			end
		end
		if t >= 1 then
			done = true
		end
	end)

	local drive: Drive = {
		stop = function()
			connection:Disconnect()
			if gpsScreen then
				gpsScreen.Enabled = true
			end
			for _, c in jam do
				c:Destroy()
			end
			jam = {}
		end,
		steer = function()
			return steer
		end,
		speed = function()
			return speed
		end,
		finished = function()
			return done
		end,
		jamMoves = function()
			-- The lights change: brake lights off, and they pull away and
			-- out of sight.
			local cars = jam
			jam = {}
			task.spawn(function()
				local origins = {}
				for i, c in cars do
					origins[i] = c:GetPivot()
					for _, part in c:GetDescendants() do
						if part.Name == "BrakeLight" then
							part:Destroy()
						end
					end
				end
				local t0 = os.clock()
				while os.clock() - t0 < 5 do
					local t = os.clock() - t0
					for i, c in cars do
						local go = math.max(0, t - (i - 1) * 0.4)
						if c.Parent then
							c:PivotTo(origins[i] + lastDir * (4 * go * go))
						end
					end
					RunService.RenderStepped:Wait()
				end
				for _, c in cars do
					c:Destroy()
				end
			end)
		end,
		heading = function()
			return heading
		end,
	}
	return drive
end

return SelfDrive
