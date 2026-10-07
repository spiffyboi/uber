-- Hands each player's cab to that player's own machine to drive.
--
-- The driving itself (throttle, brakes, steering) runs on the driver's
-- client, in CarSystems: a car driven from the server only reacts to a key
-- press once it has travelled to the server and the result has come back,
-- which in a real game means steering a beat late -- the main reason it was
-- so hard to hold a straight line. Giving the driver "network ownership" of
-- the car means their own machine simulates it, with no delay.
--
-- What stays here, on the server: the parking brake. The chassis is
-- frictionless (see CarBuilder), so a car with the engine off or nobody in
-- the seat is anchored outright -- a softer brake still let the parked cab
-- get shoved across the rank during the intro (confirmed live).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local function driverOf(seat: VehicleSeat): Player?
	local occupant = seat.Occupant
	return occupant and Players:GetPlayerFromCharacter(occupant.Parent)
end

RunService.Heartbeat:Connect(function()
	for _, car in CollectionService:GetTagged("PlayerCar") do
		local chassis = (car :: Model).PrimaryPart
		local seat = car:FindFirstChild("DriveSeat") :: VehicleSeat?
		if not chassis then
			continue
		end

		local driver = seat and not seat.Disabled and driverOf(seat)
		if not driver then
			if not chassis.Anchored then
				chassis.Anchored = true
			end
			continue
		end
		if chassis.Anchored then
			chassis.Anchored = false
		end
		if chassis:GetNetworkOwner() ~= driver then
			chassis:SetNetworkOwner(driver)
		end
	end
end)
