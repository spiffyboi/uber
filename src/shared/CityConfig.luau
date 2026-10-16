-- Fictional wrapper for the game's setting. Nothing here names a real place,
-- gang or person -- Marrow Heights and everyone in it are invented, on
-- purpose, so the story can go as dark as it wants without being about anyone
-- real.

local CityConfig = {}

CityConfig.GAME_TITLE = "Uber"

-- The district the whole game takes place in, and the short name locals use
-- for it in dialogue/signage.
CityConfig.DISTRICT_NAME = "Marrow Heights"
CityConfig.DISTRICT_NICKNAME = "The Marrow"

-- The in-game gig app the player drives for (rides + deliveries, like the
-- real Uber/Uber Eats split, under one fictional brand). Not who the player
-- starts out driving for, though -- see TAXI_COMPANY_NAME below -- GigLine
-- only enters the story once the player's arc turns from cab driver to gig
-- driver.
CityConfig.APP_NAME = "GigLine"

-- The taxi company the player starts the story driving for, before that
-- turn to GigLine. Old-school two-way radio dispatch, not an app -- see the
-- intro cutscene's dispatch call and CarBuilder's cab livery.
CityConfig.TAXI_COMPANY_NAME = "Marrow Cab Co."

-- Street dimensions that everything building or driving on the streets
-- (OpeningSetBuilder, DistrictBuilder, CarSpawner, TrafficSpawner) needs to
-- agree on. Avenues are four lanes wide (two each direction), with room for
-- real two-way traffic to pass. The steam grate the intro opens on sits on
-- Marrow St, near the top of the grid.
CityConfig.LANE_WIDTH = 11
CityConfig.ROAD_WIDTH = CityConfig.LANE_WIDTH * 4
CityConfig.SIDEWALK_WIDTH = 12
CityConfig.GRATE_POSITION = Vector3.new(0, 1, 4)

-- Building slots along every avenue are BLOCK_SPACING long, numbered from
-- BLOCK_ORIGIN_Z down -Z. Some slots are cross streets instead.
CityConfig.BLOCK_SPACING = 34
CityConfig.BLOCK_ORIGIN_Z = 20

-- The Z coordinate (world space) of the given block index's centreline.
function CityConfig.blockZ(index: number): number
	return CityConfig.BLOCK_ORIGIN_Z - index * CityConfig.BLOCK_SPACING
end

-- ===== The street grid =====
-- Five four-lane avenues running along Z, joined by two-lane cross streets
-- running along X. The first and last cross streets are the edge of the
-- grid, so every street connects at both ends and traffic can circle.
-- Marrow St (X = 0) is the original strip, where the intro takes place.
-- (Grown from three avenues and ten cross streets so a fare can be a proper
-- drive across town -- about 1200 by 1600 studs now.)
CityConfig.AVENUES = {
	{ x = -600, name = "Greaves Ave" },
	{ x = -300, name = "Ashby Ave" },
	{ x = 0, name = "Marrow St" },
	{ x = 300, name = "Calloway Ave" },
	{ x = 600, name = "Dunmore Ave" },
}
CityConfig.MAIN_AVENUE_X = 0

-- A cross street takes up one whole block slot: 22 studs of road and an
-- 8-stud sidewalk each side (34 = BLOCK_SPACING).
CityConfig.CROSS_STREET_WIDTH = 22
CityConfig.CROSS_SIDEWALK_WIDTH = 6
-- Where buildings start on a cross street, from its centreline.
CityConfig.CROSS_BUILDING_EDGE = CityConfig.BLOCK_SPACING / 2
CityConfig.CROSS_STREETS = {
	{ index = -1, name = "Harrow St" },
	{ index = 3, name = "Delano Ave" },
	{ index = 6, name = "Kesting St" },
	{ index = 10, name = "Orchard Ave" },
	{ index = 13, name = "Vail St" },
	{ index = 17, name = "Tolland St" },
	{ index = 20, name = "Linden Ave" },
	{ index = 24, name = "Quarry St" },
	{ index = 27, name = "Marsh Ave" },
	{ index = 30, name = "Ember St" },
	{ index = 34, name = "Foundry St" },
	{ index = 37, name = "Mercer Ave" },
	{ index = 41, name = "Cutler St" },
	{ index = 44, name = "Brine St" },
	{ index = 47, name = "Wharf St" },
}
CityConfig.CROSS_STREET_INDEX = {}
for _, street in CityConfig.CROSS_STREETS do
	street.z = CityConfig.blockZ(street.index)
	CityConfig.CROSS_STREET_INDEX[street.index] = street
end

-- The grid's extent: avenues run from the first cross street to the last,
-- cross streets from the first avenue to the last.
CityConfig.GRID_TOP_Z = CityConfig.CROSS_STREETS[1].z
CityConfig.GRID_BOTTOM_Z = CityConfig.CROSS_STREETS[#CityConfig.CROSS_STREETS].z
CityConfig.GRID_LEFT_X = CityConfig.AVENUES[1].x
CityConfig.GRID_RIGHT_X = CityConfig.AVENUES[#CityConfig.AVENUES].x
CityConfig.FIRST_SLOT = CityConfig.CROSS_STREETS[1].index + 1
CityConfig.LAST_SLOT = CityConfig.CROSS_STREETS[#CityConfig.CROSS_STREETS].index - 1

function CityConfig.isCrossSlot(index: number): boolean
	return CityConfig.CROSS_STREET_INDEX[index] ~= nil
end

-- Lane centres either side of a street's centreline, measured toward the
-- driver's right (traffic drives on the right).
CityConfig.AVENUE_LANE_OFFSETS = { CityConfig.LANE_WIDTH * 0.5, CityConfig.LANE_WIDTH * 1.5 }
CityConfig.CROSS_LANE_OFFSETS = { CityConfig.CROSS_STREET_WIDTH / 4 }

-- The taxi rank: a pull-in bay the player's cab actually starts parked in,
-- off the driving lanes entirely -- it used to spawn straight into the
-- inner outbound lane, which put a "parked" car directly in the middle of
-- what's now live two-way traffic. Reuses the same "skip this building
-- block" trick IntersectionBuilder's cross streets already use (see
-- OpeningSetBuilder.buildBuildingRow), just for one more block, on one side
-- only -- the far side still gets its usual building.
CityConfig.TAXI_RANK_BLOCK_INDEX = 1
CityConfig.TAXI_RANK_SIDE = 1 -- +X, the same side the outbound lanes are on
CityConfig.TAXI_RANK_Z = CityConfig.blockZ(CityConfig.TAXI_RANK_BLOCK_INDEX)
-- Spans from the road's own edge (so there's a driveway straight off the
-- travel lanes, cutting across the sidewalk) out to roughly where a
-- building's far wall would have sat, had one been built in this slot.
CityConfig.TAXI_RANK_X_NEAR = CityConfig.ROAD_WIDTH / 2
CityConfig.TAXI_RANK_X_FAR = CityConfig.ROAD_WIDTH / 2 + CityConfig.SIDEWALK_WIDTH + 3 + 20
-- Matches BLOCK_SPACING (the same length a building would take up in this
-- slot) rather than a smaller hand-picked number -- confirmed live that a
-- shorter pad here left an unpaved, un-collidable gap between the pad's own
-- Z edges and the next block's buildings on either side (buildBuildingRow
-- tiles buildings edge-to-edge on BLOCK_SPACING centres). A car driving
-- straight off the pad in either direction fell through that gap into the
-- void and was destroyed outright (confirmed: the whole car Model vanished
-- from workspace after ~3 seconds of held throttle, and the player's
-- humanoid respawned with no car left to sit in at all). Spanning the full
-- block closes that gap at the source.
CityConfig.TAXI_RANK_LENGTH = CityConfig.BLOCK_SPACING

-- Where a block's street wall starts: past the road, the sidewalk and a
-- 3-stud setback. Ordinary buildings are 20 deep from here.
CityConfig.BUILDING_EDGE = CityConfig.ROAD_WIDTH / 2 + CityConfig.SIDEWALK_WIDTH + 3

-- Named places along the avenues, each taking the block slot (avenue x,
-- index, side) an ordinary building would otherwise fill -- see
-- DistrictBuilder. `span` lets one place take several consecutive blocks
-- (the parks). The first taxiRank is the player's own (TAXI_RANK_* above
-- must match it). `x` defaults to Marrow St.
CityConfig.LOTS = {
	{ index = 1, side = 1, kind = "taxiRank" },
	-- Marrow St, the original strip.
	{ index = 2, side = -1, kind = "shops" },
	{ index = 4, side = 1, kind = "nightclub", name = "VELVET" },
	{ index = 5, side = -1, kind = "shops" },
	{ index = 5, side = 1, kind = "cinema", name = "RIALTO" },
	{ index = 7, side = -1, kind = "park", span = 3, name = "MARROW PARK" },
	{ index = 7, side = 1, kind = "highrise", name = "THE ARDSLEY" },
	{ index = 8, side = 1, kind = "highrise", name = "HALCYON HOUSE" },
	{ index = 9, side = 1, kind = "highrise", name = "THE BELLMORE" },
	{ index = 11, side = -1, kind = "taxiRank" },
	{ index = 11, side = 1, kind = "shops" },
	{ index = 12, side = -1, kind = "highrise", name = "MARROW TOWERS" },
	{ index = 14, side = 1, kind = "nightclub", name = "THE BASEMENT" },
	{ index = 15, side = -1, kind = "shops" },
	-- Marrow St, further down.
	{ index = 16, side = 1, kind = "shops" },
	{ index = 18, side = 1, kind = "nightclub", name = "NEON ROOM" },
	{ index = 19, side = -1, kind = "cinema", name = "STARLITE" },
	{ index = 21, side = 1, kind = "highrise", name = "THE WINTHROP" },
	{ index = 22, side = -1, kind = "taxiRank" },
	{ index = 23, side = 1, kind = "shops" },
	{ index = 25, side = -1, kind = "highrise", name = "MERIDIAN HOUSE" },
	{ index = 26, side = 1, kind = "shops" },
	{ index = 28, side = -1, kind = "nightclub", name = "AFTERHOURS" },
	{ index = 29, side = 1, kind = "shops" },
	-- Calloway Ave, the east avenue.
	{ x = 300, index = 1, side = -1, kind = "shops" },
	{ x = 300, index = 4, side = 1, kind = "highrise", name = "THE ASHFORD" },
	{ x = 300, index = 7, side = -1, kind = "nightclub", name = "CLUB MIRAGE" },
	{ x = 300, index = 9, side = 1, kind = "shops" },
	{ x = 300, index = 12, side = -1, kind = "taxiRank" },
	{ x = 300, index = 14, side = 1, kind = "shops" },
	{ x = 300, index = 18, side = -1, kind = "highrise", name = "KINGSLEY COURT" },
	{ x = 300, index = 21, side = 1, kind = "cinema", name = "THE GRAND" },
	{ x = 300, index = 22, side = -1, kind = "shops" },
	{ x = 300, index = 25, side = -1, kind = "highrise", name = "THE HOLLIS" },
	{ x = 300, index = 28, side = 1, kind = "nightclub", name = "STATIC" },
	-- Ashby Ave, the west avenue.
	{ x = -300, index = 2, side = 1, kind = "nightclub", name = "HALO" },
	{ x = -300, index = 5, side = -1, kind = "shops" },
	{ x = -300, index = 8, side = 1, kind = "highrise", name = "LANGFORD TOWER" },
	{ x = -300, index = 9, side = -1, kind = "shops" },
	{ x = -300, index = 12, side = 1, kind = "shops" },
	{ x = -300, index = 15, side = -1, kind = "taxiRank" },
	{ x = -300, index = 16, side = 1, kind = "highrise", name = "THE COLBURN" },
	{ x = -300, index = 19, side = -1, kind = "shops" },
	{ x = -300, index = 21, side = 1, kind = "park", span = 3, name = "ASHBY SQUARE" },
	{ x = -300, index = 26, side = -1, kind = "cinema", name = "MAJESTIC" },
	{ x = -300, index = 29, side = 1, kind = "shops" },
	-- Further south, past Ember St: the older, rougher end of the Marrow,
	-- down toward the wharf.
	{ index = 32, side = 1, kind = "nightclub", name = "CRIMSON" },
	{ index = 35, side = -1, kind = "highrise", name = "THE STANDISH" },
	{ index = 39, side = 1, kind = "shops" },
	{ index = 43, side = -1, kind = "cinema", name = "BIJOU" },
	{ index = 46, side = 1, kind = "shops" },
	{ x = 300, index = 31, side = 1, kind = "shops" },
	{ x = 300, index = 33, side = 1, kind = "chapel", name = "LARKIN & SONS" },
	{ x = 300, index = 35, side = -1, kind = "highrise", name = "QUARRY HOUSES" },
	{ x = 300, index = 39, side = 1, kind = "shops" },
	{ x = 300, index = 42, side = -1, kind = "nightclub", name = "THE FURNACE" },
	{ x = 300, index = 46, side = 1, kind = "shops" },
	{ x = -300, index = 32, side = -1, kind = "gunStore", name = "IRONSIDE ARMS" },
	{ x = -300, index = 36, side = 1, kind = "highrise", name = "ASHBY HOUSES" },
	{ x = -300, index = 40, side = -1, kind = "nightclub", name = "MOONGLOW" },
	{ x = -300, index = 45, side = 1, kind = "shops" },
	-- Greaves Ave, the far west avenue.
	{ x = -600, index = 4, side = 1, kind = "highrise", name = "THE PALISADE" },
	{ x = -600, index = 9, side = -1, kind = "nightclub", name = "COPPER ROOM" },
	{ x = -600, index = 14, side = 1, kind = "shops" },
	{ x = -600, index = 18, side = -1, kind = "park", span = 2, name = "GREAVES PARK" },
	{ x = -600, index = 22, side = 1, kind = "cinema", name = "THE LYRIC" },
	{ x = -600, index = 28, side = -1, kind = "taxiRank" },
	{ x = -600, index = 33, side = 1, kind = "highrise", name = "ROWAN HOUSES" },
	{ x = -600, index = 39, side = -1, kind = "shops" },
	{ x = -600, index = 45, side = 1, kind = "nightclub", name = "THE PIT" },
	-- Dunmore Ave, the far east avenue.
	{ x = 600, index = 2, side = -1, kind = "shops" },
	{ x = 600, index = 8, side = 1, kind = "highrise", name = "THE CLAREMONT" },
	{ x = 600, index = 12, side = -1, kind = "nightclub", name = "VOLTAGE" },
	{ x = 600, index = 16, side = 1, kind = "shops" },
	{ x = 600, index = 21, side = -1, kind = "cinema", name = "THE EMBASSY" },
	{ x = 600, index = 26, side = 1, kind = "highrise", name = "DUNMORE COURT" },
	{ x = 600, index = 31, side = -1, kind = "park", span = 2, name = "PIER PARK" },
	{ x = 600, index = 36, side = 1, kind = "taxiRank" },
	{ x = 600, index = 40, side = -1, kind = "shops" },
	{ x = 600, index = 45, side = 1, kind = "highrise", name = "HARBOR VIEW" },
}
for _, lot in CityConfig.LOTS do
	lot.x = lot.x or CityConfig.MAIN_AVENUE_X
end

-- The lot covering block `index` on `side` of the avenue at `x` (Marrow St
-- if left out), if any.
function CityConfig.lotAt(index: number, side: number, x: number?)
	local avenueX = x or CityConfig.MAIN_AVENUE_X
	for _, lot in CityConfig.LOTS do
		local span = lot.span or 1
		if lot.x == avenueX and lot.side == side and index >= lot.index and index < lot.index + span then
			return lot
		end
	end
	return nil
end

-- Which block slot world `z` falls in.
function CityConfig.slotAt(z: number): number
	return math.floor((CityConfig.BLOCK_ORIGIN_Z - z) / CityConfig.BLOCK_SPACING + 0.5)
end

-- Z range {near, far} (near > far, since the strip runs along -Z) a lot
-- covers, edge to edge.
function CityConfig.lotZRange(lot): (number, number)
	local half = CityConfig.BLOCK_SPACING / 2
	local near = CityConfig.blockZ(lot.index) + half
	local far = CityConfig.blockZ(lot.index + (lot.span or 1) - 1) - half
	return near, far
end

-- Y is high enough that the car's wheels (see CarBuilder) clear the ground
-- surface and settle onto it under gravity, instead of spawning clipped into
-- it. No yaw here: the car's local -Z front (headlights/windshield, see
-- CarBuilder) stays world -Z, i.e. facing into the city, same direction the
-- grate establishing shot and the windshield POV drift both already look --
-- parked facing the same way traffic actually flows, not nosed in sideways.
-- Parked on the road side of the rank, toward its back (+Z) end: the next
-- block's building starts at X = ROAD_WIDTH/2 + SIDEWALK_WIDTH + 3, so a car
-- this close to the kerb has a clear run straight ahead past that building's
-- corner and only a short nudge left to reach the outbound lanes. Parked in
-- the middle of the rank (where it used to be), its nose sat ~12 studs from
-- that building's wall -- confirmed live that pressing W drove it straight
-- into the wall and pinned it there, which is what read as "the car can't
-- pull out onto the road".
CityConfig.CAR_SPAWN_CFRAME = CFrame.new(
	CityConfig.TAXI_RANK_X_NEAR + 8,
	3.6,
	CityConfig.TAXI_RANK_Z + CityConfig.TAXI_RANK_LENGTH / 2 - 9
)

-- The Marrow Cab Co. dispatch office -- where the intro cutscene now opens,
-- before it ever cuts to the street/grate. Nothing ever physically walks
-- between it and the street (the whole opening is one scripted camera
-- sequence), so it's a sealed room tucked underneath the city, right below
-- the player's taxi rank: clear of the grid at any size, and always close to
-- the player, so the client already has it loaded when the cutscene starts
-- (the place streams the world in around the player). TaxiOfficeBuilder and
-- IntroCutscene both key off these same points so the camera's entrance/desk
-- shots always line up with whatever the room actually looks like.
CityConfig.OFFICE_ORIGIN = Vector3.new(30, -120, 0)
CityConfig.OFFICE_DOOR_POSITION = CityConfig.OFFICE_ORIGIN + Vector3.new(0, 0, -7)
CityConfig.OFFICE_DESK_POSITION = CityConfig.OFFICE_ORIGIN + Vector3.new(0, 0, 5.5)

-- Inside Ironside Arms, the gun store on Ashby Ave (chapter 7's cutscene --
-- see GunStoreBuilder and StoryScenes). The same trick as the office: a
-- sealed room under the street, right below the shop itself, so it's
-- already streamed in when the cab pulls up outside. The counter runs
-- along X; the clerk stands on its +Z side, the customer (the camera) on
-- the -Z side.
CityConfig.GUNSTORE_ORIGIN = Vector3.new(-345, -70, CityConfig.blockZ(32))
CityConfig.GUNSTORE_COUNTER = CityConfig.GUNSTORE_ORIGIN + Vector3.new(0, 0, 2)

-- Inside Larkin & Sons, the funeral chapel on Calloway Ave (chapter 9 -- see
-- ChapelBuilder and StoryScenes): again a sealed room right under the
-- building. The origin is the middle of the floor; the doors are at the -Z
-- end, the casket at the +Z end, the aisle down X = 0.
CityConfig.CHAPEL_ORIGIN = Vector3.new(345, -70, CityConfig.blockZ(33))

return CityConfig
