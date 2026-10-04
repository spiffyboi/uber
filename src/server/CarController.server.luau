-- Arcade driving: reads each occupied, unlocked car's VehicleSeat.Throttle/
-- Steer every frame and drives the chassis directly by velocity, rather than
-- rigging real wheel suspension.
--
-- W accelerates; S brakes while rolling forward and only starts reversing
-- once the car has actually stopped (and the mirror of that in reverse).
-- Letting off both coasts down gently instead of slamming to a halt.
--
-- Steering uses a fixed turning circle (a simple bicycle model): the car only
-- turns while it's actually moving, turns tighter at parking speeds than the
-- old speed-scaled yaw rate allowed, and steers the right way round in
-- reverse. The old model spun the car in place even when stopped, and at low
-- speed turned so slowly it couldn't get its nose out of the taxi rank.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local MAX_SPEED = 85 -- studs/second, roughly 60mph
local REVERSE_MAX_SPEED = 25
local ACCEL = 28 -- studs/second^2 under throttle
local BRAKE = 70 -- studs/second^2 when pressing against the direction of travel
local COAST = 12 -- studs/second^2 with no input
local TURN_RADIUS = 16 -- studs, at full lock
local MAX_YAW_RATE = 1.6 -- radians/second, so high-speed steering stays sane

local function approach(current: number, target: number, rate: number): number
	if current < target then
		return math.min(current + rate, target)
	end
	return math.max(current - rate, target)
end

RunService.Heartbeat:Connect(function(dt: number)
	for _, car in CollectionService:GetTagged("PlayerCar") do
		local chassis = (car :: Model).PrimaryPart
		local seat = car:FindFirstChild("DriveSeat") :: VehicleSeat?
		if not chassis then
			continue
		end

		-- Parking brake: the chassis is frictionless (see CarBuilder), so a
		-- car with the engine off is anchored outright. A softer brake that
		-- only decelerated it still let the car get shoved ~6 studs across
		-- the rank during the intro (confirmed live -- it ended up tilted with
		-- its back wheels up on the kerb before the player ever drove it).
		if not seat or seat.Disabled or seat.Occupant == nil then
			if not chassis.Anchored then
				chassis.Anchored = true
			end
			continue
		end
		if chassis.Anchored then
			chassis.Anchored = false
			-- This script drives the car from the server, so the server has to
			-- own its physics -- a client owner's own simulation would
			-- overwrite every velocity set here.
			chassis:SetNetworkOwner(nil)
		end

		local forward = chassis.CFrame.LookVector
		local velocity = chassis.AssemblyLinearVelocity
		local speed = velocity:Dot(forward)
		local throttle = seat.Throttle

		if throttle > 0 then
			if speed < -0.5 then
				speed = approach(speed, 0, BRAKE * dt)
			else
				speed = approach(speed, MAX_SPEED, ACCEL * dt)
			end
		elseif throttle < 0 then
			if speed > 0.5 then
				speed = approach(speed, 0, BRAKE * dt)
			else
				speed = approach(speed, -REVERSE_MAX_SPEED, ACCEL * dt)
			end
		else
			speed = approach(speed, 0, COAST * dt)
		end

		-- Keep whatever vertical velocity gravity/bumps already gave it; only
		-- the horizontal (driving) component is being overridden here.
		chassis.AssemblyLinearVelocity = forward * speed + Vector3.new(0, velocity.Y, 0)

		local yawRate = math.clamp(-seat.Steer * speed / TURN_RADIUS, -MAX_YAW_RATE, MAX_YAW_RATE)
		chassis.AssemblyAngularVelocity = Vector3.new(0, yawRate, 0)
	end
end)
