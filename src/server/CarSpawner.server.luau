local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))
local CarBuilder = require(script.Parent.CarBuilder)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local stopEngineRemote = remotes:WaitForChild("StopEngine")

-- Top face of the road/taxi-rank pad parts (see OpeningSetBuilder).
local ROAD_SURFACE_Y = 1

local cars: { [Player]: Model } = {}
-- Spread each player's spawn out along the road's width so two players
-- joining at once don't spawn stacked inside each other.
local nextSlot = 0

-- Guards against a car that's still in `cars` but no longer actually in the
-- game -- confirmed live this can genuinely happen (a car driven off the
-- previously-too-short taxi rank pad fell out of the world and was
-- destroyed outright by Roblox's own FallenPartsDestroyHeight cleanup, see
-- OpeningSetBuilder's SafetyFloor). Without this check, onCharacterAdded
-- below would call `car:WaitForChild("DriveSeat")` on a destroyed model that
-- can never gain that child, hanging the player's respawn forever (an
-- "Infinite yield possible" warning was the only symptom, confirmed live).
-- Treating a parentless car as missing lets spawnCar build a fresh one
-- instead.
local function carFor(player: Player): Model?
	local car = cars[player]
	if car and car.Parent then
		return car
	end
	return nil
end

local function spawnCar(player: Player): Model
	local existing = cars[player]
	if existing then
		existing:Destroy()
	end

	local slot = nextSlot
	nextSlot += 1
	local cframe = CityConfig.CAR_SPAWN_CFRAME * CFrame.new(slot * 10, 0, 0)

	local car = CarBuilder.build(player.Name, cframe)
	-- Rest the car's lowest collidable point (its wheel contacts) exactly on
	-- the road surface. CAR_SPAWN_CFRAME's height left the car sunk ~0.5
	-- studs into the ground (its size comes from the mesh, so the right
	-- height can't be known ahead of time), and the physics engine's pop back
	-- out on spawn shoved it sideways across the rank -- confirmed live it
	-- came to rest 23 studs from where it was placed, rotated ~6 degrees.
	local lowest = math.huge
	for _, part in car:GetDescendants() do
		if part:IsA("BasePart") and part.CanCollide then
			lowest = math.min(lowest, part.Position.Y - part.Size.Y / 2)
		end
	end
	car:PivotTo(car:GetPivot() + Vector3.new(0, ROAD_SURFACE_Y + 0.05 - lowest, 0))
	car.Parent = workspace
	cars[player] = car

	-- The ignition: a physical key the player hovers/clicks near the
	-- steering column (see CarBuilder), not a dash-screen button -- fires
	-- straight into the seat here rather than routing through a remote,
	-- since ProximityPrompt.Triggered already fires server-side on its own.
	local seat = car:WaitForChild("DriveSeat") :: VehicleSeat
	local ignitionKey = car:WaitForChild("IgnitionKey")
	local ignitionPrompt = ignitionKey:WaitForChild("IgnitionPrompt") :: ProximityPrompt
	local enterPrompt = car:WaitForChild("DriverDoor"):WaitForChild("EnterPrompt") :: ProximityPrompt

	-- Which prompt shows when: the key only for someone in the driver's
	-- seat with the engine off (confirmed live it otherwise popped up for
	-- anyone walking past a parked cab), and "Get in" only while the seat's
	-- empty. Decided here, server-side, the moment either changes -- the
	-- user reported the key prompt staying up once the engine was running
	-- when this was left to the client alone.
	local function refreshPrompts()
		ignitionPrompt.Enabled = seat.Occupant ~= nil and seat.Disabled
		enterPrompt.Enabled = seat.Occupant == nil
	end
	seat:GetPropertyChangedSignal("Occupant"):Connect(refreshPrompts)
	seat:GetPropertyChangedSignal("Disabled"):Connect(refreshPrompts)
	refreshPrompts()

	ignitionPrompt.Triggered:Connect(function(triggeringPlayer)
		if triggeringPlayer ~= player then
			return
		end
		seat.Disabled = false
	end)

	-- Getting back in after getting out: the owner only, alive and on foot.
	enterPrompt.Triggered:Connect(function(triggeringPlayer)
		if triggeringPlayer ~= player or seat.Occupant ~= nil then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and humanoid.SeatPart == nil then
			seat:Sit(humanoid)
		end
	end)

	return car
end

local function onCharacterAdded(player: Player, character: Model)
	local car = carFor(player) or spawnCar(player)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local seat = car:WaitForChild("DriveSeat") :: VehicleSeat
	-- Sitting is locked to Disabled until the player actually starts the
	-- engine (see StartEngine below) -- Sit() still works while Disabled,
	-- it's only Throttle/Steer input that's ignored, which is exactly what
	-- keeps the car parked through the cutscene and the ignition-off state
	-- afterward (see CarSystems.luau on the client).
	seat:Sit(humanoid)
end

local handled: { [Player]: boolean } = {}

local function onPlayerAdded(player: Player)
	if handled[player] then
		return
	end
	handled[player] = true
	spawnCar(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
-- Anyone who joined before this script got going. Confirmed live: in a
-- Studio test the player can already be in the game by the time this line
-- runs (the city build at startup holds up the other server scripts), and
-- they were left standing in the street with no cab at all.
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	local car = cars[player]
	if car then
		car:Destroy()
		cars[player] = nil
	end
	handled[player] = nil
end)

-- Fired as part of CarSystems' space-bar exit sequence, so the car goes back
-- to properly parked/off (not left silently "on" with nobody in it).
stopEngineRemote.OnServerEvent:Connect(function(player)
	local car = carFor(player)
	if not car then
		return
	end
	local seat = car:FindFirstChild("DriveSeat") :: VehicleSeat?
	if seat then
		seat.Disabled = true
	end
end)
