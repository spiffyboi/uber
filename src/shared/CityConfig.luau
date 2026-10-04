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

-- Layout of the opening strip (OpeningSetBuilder) that both it and anything
-- spawning a car onto the road (CarSpawner, TrafficSpawner) need to agree on.
-- The road runs along -Z from the steam grate at the start. Four lanes wide
-- (two each direction) rather than the original single-strip two-lane road --
-- widened for real two-way traffic (see TrafficSpawner) with room to actually
-- pass, not just a taxi-width strip.
CityConfig.LANE_WIDTH = 11
CityConfig.ROAD_WIDTH = CityConfig.LANE_WIDTH * 4
CityConfig.ROAD_LENGTH = 320
CityConfig.SIDEWALK_WIDTH = 12
CityConfig.GRATE_POSITION = Vector3.new(0, 1, 4)

-- Lane centres, X-offset from the road's own centreline. Roblox's forward
-- convention (an unrotated CFrame's LookVector is -Z, RightVector is +X)
-- makes "drive on the right" work out to: traffic facing -Z (outbound, same
-- direction the whole opening cutscene already drives) belongs on the +X
-- half: traffic facing +Z (inbound, yawed 180) belongs on the -X half, since
-- its own RightVector is -X once turned around.
CityConfig.OUTBOUND_LANE_X = { CityConfig.LANE_WIDTH * 0.5, CityConfig.LANE_WIDTH * 1.5 }
CityConfig.INBOUND_LANE_X = { -CityConfig.LANE_WIDTH * 0.5, -CityConfig.LANE_WIDTH * 1.5 }

-- Building row spacing (OpeningSetBuilder.buildBuildingRow) and which block
-- slots become real cross-street intersections (IntersectionBuilder) instead
-- of another building -- shared here so both files, plus TrafficSpawner's
-- traffic-light lookups, agree on where the intersections actually are.
CityConfig.BLOCK_SPACING = 34
CityConfig.BLOCK_ORIGIN_Z = 20
CityConfig.INTERSECTION_BLOCK_INDICES = { 3, 6 }
CityConfig.CROSS_STREET_WIDTH = 22
CityConfig.CROSS_STREET_HALF_LENGTH = 50

-- The Z coordinate (world space) of the given block index's centreline, the
-- same formula OpeningSetBuilder.buildBuildingRow places buildings with.
function CityConfig.blockZ(index: number): number
	return CityConfig.BLOCK_ORIGIN_Z - index * CityConfig.BLOCK_SPACING
end

-- World-space Z of every cross-street intersection, in block order.
CityConfig.INTERSECTION_Z = {}
for _, index in CityConfig.INTERSECTION_BLOCK_INDICES do
	table.insert(CityConfig.INTERSECTION_Z, CityConfig.blockZ(index))
end

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
-- before it ever cuts to the street/grate. Built well clear of the street
-- strip's own footprint (see ROAD_WIDTH/SIDEWALK_WIDTH/building depth above)
-- so the two sets never overlap; nothing ever physically walks between them,
-- since the whole opening is one continuous scripted camera sequence, so
-- there's no need for them to be adjacent. TaxiOfficeBuilder and
-- IntroCutscene both key off these same points so the camera's entrance/desk
-- shots always line up with whatever the room actually looks like.
CityConfig.OFFICE_ORIGIN = Vector3.new(400, 5, 0)
CityConfig.OFFICE_DOOR_POSITION = CityConfig.OFFICE_ORIGIN + Vector3.new(0, 0, -7)
CityConfig.OFFICE_DESK_POSITION = CityConfig.OFFICE_ORIGIN + Vector3.new(0, 0, 5.5)

return CityConfig
