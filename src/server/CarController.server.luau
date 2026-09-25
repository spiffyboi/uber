-- Arcade driving: reads each occupied, unlocked car's VehicleSeat.Throttle/
-- Steer every frame and drives the chassis directly by velocity, rather than
-- rigging real wheel suspension. Good enough to be fun and controllable now;
-- swapping in HingeConstraint-driven wheels later wouldn't need anything
-- outside this file to change, since CarBuilder's wheels are already
-- separate parts.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local MAX_SPEED = 85 -- studs/second, roughly 60mph
local ACCEL = 60 -- studs/second^2
local REVERSE_FRACTION = 0.45 -- reverse tops out slower than forward
local TURN_RATE = 2.2 -- radians/second at full lock and full speed

RunService.Heartbeat:Connect(function(dt: number)
	for _, car in CollectionService:GetTagged("PlayerCar") do
		local chassis = (car :: Model).PrimaryPart
		local seat = car:FindFirstChild("DriveSeat") :: VehicleSeat?
		if not chassis or not seat or seat.Disabled or seat.Occupant == nil then
			continue
		end

		local forward = chassis.CFrame.LookVector
		local velocity = chassis.AssemblyLinearVelocity
		local currentSpeed = velocity:Dot(forward)

		local topSpeed = if seat.Throttle < 0 then MAX_SPEED * REVERSE_FRACTION else MAX_SPEED
		local targetSpeed = seat.Throttle * topSpeed
		local delta = math.clamp(targetSpeed - currentSpeed, -ACCEL * dt, ACCEL * dt)
		local speed = currentSpeed + delta

		-- Keep whatever vertical velocity gravity/bumps already gave it; only
		-- the horizontal (driving) component is being overridden here.
		chassis.AssemblyLinearVelocity = forward * speed + Vector3.new(0, velocity.Y, 0)

		local speedFraction = math.clamp(math.abs(speed) / MAX_SPEED, 0.2, 1)
		chassis.AssemblyAngularVelocity = Vector3.new(0, -seat.Steer * TURN_RATE * speedFraction, 0)
	end
end)
