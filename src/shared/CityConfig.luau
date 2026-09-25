-- Fictional wrapper for the game's setting. Nothing here names a real place,
-- gang or person -- Marrow Heights and everyone in it are invented, on
-- purpose, so the story can go as dark as it wants without being about anyone
-- real.

local CityConfig = {}

CityConfig.GAME_TITLE = "Cold Fare"

-- The district the whole game takes place in, and the short name locals use
-- for it in dialogue/signage.
CityConfig.DISTRICT_NAME = "Marrow Heights"
CityConfig.DISTRICT_NICKNAME = "The Marrow"

-- The in-game gig app the player drives for (rides + deliveries, like the
-- real Uber/Uber Eats split, under one fictional brand).
CityConfig.APP_NAME = "GigLine"

-- Layout of the opening strip (OpeningSetBuilder) that both it and anything
-- spawning a car onto the road (CarSpawner) need to agree on. The road runs
-- along -Z from the steam grate at the start.
CityConfig.ROAD_WIDTH = 24
CityConfig.ROAD_LENGTH = 320
CityConfig.SIDEWALK_WIDTH = 10
CityConfig.GRATE_POSITION = Vector3.new(0, 1, 4)
-- Y is high enough that the car's wheels (see CarBuilder) clear the road
-- surface and settle onto it under gravity, instead of spawning clipped into it.
CityConfig.CAR_SPAWN_CFRAME = CFrame.new(0, 3.6, -6) * CFrame.Angles(0, math.pi, 0)

return CityConfig
