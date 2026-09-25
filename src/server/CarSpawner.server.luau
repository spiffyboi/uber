local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))
local CarBuilder = require(script.Parent.CarBuilder)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local acceptJobRemote = remotes:WaitForChild("AcceptJob")

local cars: { [Player]: Model } = {}
-- Spread each player's spawn out along the road's width so two players
-- joining at once don't spawn stacked inside each other.
local nextSlot = 0

local function carFor(player: Player): Model?
	return cars[player]
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
	car.Parent = workspace
	cars[player] = car
	return car
end

local function onCharacterAdded(player: Player, character: Model)
	local car = carFor(player) or spawnCar(player)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local seat = car:WaitForChild("DriveSeat") :: VehicleSeat
	-- Sitting is locked to Disabled until the intro cutscene's dispatch call
	-- is accepted (see AcceptJob below); Sit() still works while Disabled,
	-- it's only Throttle/Steer input that's ignored.
	seat:Sit(humanoid)
end

Players.PlayerAdded:Connect(function(player)
	spawnCar(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local car = cars[player]
	if car then
		car:Destroy()
		cars[player] = nil
	end
end)

acceptJobRemote.OnServerEvent:Connect(function(player)
	local car = carFor(player)
	if not car then
		return
	end
	local seat = car:FindFirstChild("DriveSeat") :: VehicleSeat?
	if seat then
		seat.Disabled = false
	end
end)
