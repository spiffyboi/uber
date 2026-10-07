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

-- ===== Ordinary fares =====
-- What the Dispatch app offers in between the story's chapters (the first
-- fare, Ray, is the story's -- see StoryConfig): a random passenger and a
-- couple of lines of conversation each.

FareConfig.NAMES = { "Denise", "Marcus", "Teresa", "Sal", "Andre", "Lucia", "Frank", "Nina", "Dev", "Rosa", "Eli", "Carmen" }

FareConfig.CHATTER = {
	{
		{ at = 0, speaker = "PASSENGER", text = "Hey. Thanks for stopping -- three cabs went right past me." },
		{ at = 0.4, speaker = "PASSENGER", text = "Double shift at the hospital. My feet are done." },
		{ at = 0.8, speaker = "PASSENGER", text = "Anywhere round here's fine. Thank you, really." },
	},
	{
		{ at = 0, speaker = "PASSENGER", text = "You got a radio in here? No? That's alright. Quiet's nice." },
		{ at = 0.5, speaker = "PASSENGER", text = "Used to drive one of these myself. Nine years. Don't miss it." },
	},
	{
		{ at = 0, speaker = "PASSENGER", text = "Quick as you can, I'm late. Not your fault. Nothing's ever your fault, right?" },
		{ at = 0.6, speaker = "PASSENGER", text = "Sorry. Long night. Long year, honestly." },
	},
	{
		{ at = 0, speaker = "PASSENGER", text = "Is the deli on the corner there still open? Best egg sandwich in The Marrow." },
		{ at = 0.45, speaker = "PASSENGER", text = "My grandfather drove a cab. Said you learn more about a city from the back seat than from any newspaper." },
	},
	{
		{ at = 0, speaker = "PASSENGER", text = "Evening. Don't mind me, I'll just watch the lights go by." },
		{ at = 0.7, speaker = "PASSENGER", text = "Pretty, this time of night. You'd almost forget." },
	},
}

FareConfig.ARRIVALS = {
	{ { speaker = "PASSENGER", text = "This is good. Take care of yourself." } },
	{ { speaker = "PASSENGER", text = "Here's fine. Keep the change." } },
	{ { speaker = "PASSENGER", text = "Thanks. Get home safe, alright?" } },
}

return FareConfig
