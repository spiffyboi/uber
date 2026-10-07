-- Getting back in the cab. The "Get in" prompt at the driver's door seats
-- the player server-side (see CarSpawner); this notices them landing in
-- their own driver's seat and hands over to CarSystems again -- the same
-- driver's-eye view, ignition key and controls as straight after the intro.
-- (The very first time, straight out of the intro, IntroCutscene starts
-- CarSystems itself; "IntroDone" keeps this out of the way until then.)

local Players = game:GetService("Players")

local CarSystems = require(script.Parent.CarSystems)

local player = Players.LocalPlayer

local function watch(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Seated:Connect(function(isSeated, seatPart)
		if not isSeated or not player:GetAttribute("IntroDone") or CarSystems.isActive() then
			return
		end
		local car = workspace:FindFirstChild(player.Name .. "_Car")
		if not car or seatPart ~= car:FindFirstChild("DriveSeat") then
			return
		end
		local chassis = car:FindFirstChild("Chassis") :: BasePart
		local gpsScreen = car:FindFirstChild("GpsUnit") and car.GpsUnit:FindFirstChild("GpsScreen")
		if chassis and gpsScreen then
			CarSystems.start(car, chassis, seatPart :: VehicleSeat, gpsScreen :: SurfaceGui, character, nil)
		end
	end)
end

if player.Character then
	watch(player.Character)
end
player.CharacterAdded:Connect(watch)
