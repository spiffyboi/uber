-- Fares: what they pay, where people get picked up, and what passengers say
-- on the way. Shared by the server (FareService: passengers, pickups,
-- payment) and the client (dialogue, the meter, the phone).
--
-- All dialogue here is original to this game.

local CityConfig = require(script.Parent.CityConfig)

local FareConfig = {}

-- Pay: a flag-drop charge, then so much per stud of the route from pickup
-- to drop-off (the quoted route, so a detour doesn't pay more). Roughly:
-- a short hop across a block ~$8, the length of Marrow St ~$30.
FareConfig.BASE_FARE = 3
FareConfig.RATE_PER_STUD = 0.025

-- How close the cab has to stop (centre of the cab to the pickup/drop-off
-- point, which sits in the kerb lane) and how slow counts as stopped.
FareConfig.PICKUP_RADIUS = 18
FareConfig.DROPOFF_RADIUS = 22
FareConfig.STOPPED_SPEED = 3

function FareConfig.price(routeLength: number): number
	return math.floor((FareConfig.BASE_FARE + routeLength * FareConfig.RATE_PER_STUD) * 100 + 0.5) / 100
end

-- A pickup/drop-off spot outside block slot `index` on `side` of the avenue
-- at `x`: where the passenger stands (on the sidewalk) and where the cab
-- stops (the kerb lane beside them).
function FareConfig.kerbSpot(x: number, index: number, side: number, along: number?): (Vector3, Vector3)
	local z = CityConfig.blockZ(index) + (along or 0)
	local standing = Vector3.new(x + side * (CityConfig.ROAD_WIDTH / 2 + 4), 1.2, z)
	local stop = Vector3.new(x + side * CityConfig.LANE_WIDTH * 1.5, 1, z)
	return standing, stop
end

-- Who the ordinary fares are and what they say: see Conversations.

return FareConfig
