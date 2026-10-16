-- The city's weather: it's always night in the Marrow, but not always the
-- same night. Every few minutes the sky moves on to something else -- clear,
-- overcast, drizzle, rain, now and then a storm -- easing from one to the
-- next rather than snapping, and the streets stay wet for a while after the
-- rain stops. It runs the same in every chapter and in Free Play.
--
-- All this does is keep a few numbers up to date on workspace attributes;
-- what they look like (the rain, the haze, the wet roads, the lightning) is
-- Weather.client's job:
--   WeatherName  -- the state it's in or heading for, by name
--   Rain         -- 0 (none) .. 1 (pouring)
--   Overcast     -- 0 (clear sky) .. 1 (low, heavy cloud)
--   Wetness      -- 0 (dry) .. 1 (soaked); rises in rain, dries off slowly
--   Storm        -- true while there's lightning about
--
-- For testing: set the workspace attribute WeatherForce to one of the
-- state names below and the weather heads straight there and stays.

local WEATHERS = {
	clear = { rain = 0, overcast = 0.1, weight = 30 },
	overcast = { rain = 0, overcast = 0.7, weight = 25 },
	drizzle = { rain = 0.3, overcast = 0.75, weight = 20 },
	rain = { rain = 0.7, overcast = 0.9, weight = 17 },
	storm = { rain = 1, overcast = 1, weight = 8, storm = true },
}
local ORDER = { "clear", "overcast", "drizzle", "rain", "storm" }

-- How long a spell of weather lasts, in seconds, before the next one.
local MIN_SPELL, MAX_SPELL = 240, 480
-- How fast things ease toward the new weather, per second (so a full change
-- takes about a minute).
local CHANGE_RATE = 1 / 60
-- Wetness: how fast it soaks up in full rain, and how fast it dries.
local SOAK_RATE = 1 / 40
local DRY_RATE = 1 / 200

local function pick(previous: string?): string
	local total = 0
	for _, name in ORDER do
		if name ~= previous then
			total += WEATHERS[name].weight
		end
	end
	local roll = math.random() * total
	for _, name in ORDER do
		if name ~= previous then
			roll -= WEATHERS[name].weight
			if roll <= 0 then
				return name
			end
		end
	end
	return "clear"
end

local function approach(value: number, target: number, step: number): number
	if value < target then
		return math.min(value + step, target)
	end
	return math.max(value - step, target)
end

local current = pick(nil)
local rain = WEATHERS[current].rain
local overcast = WEATHERS[current].overcast
local wetness = rain
local spellEnds = os.clock() + math.random(MIN_SPELL, MAX_SPELL)

local function publish()
	workspace:SetAttribute("WeatherName", current)
	workspace:SetAttribute("Rain", math.floor(rain * 1000 + 0.5) / 1000)
	workspace:SetAttribute("Overcast", math.floor(overcast * 1000 + 0.5) / 1000)
	workspace:SetAttribute("Wetness", math.floor(wetness * 1000 + 0.5) / 1000)
	workspace:SetAttribute("Storm", WEATHERS[current].storm == true and rain > 0.6)
end
publish()

local STEP = 0.5
while true do
	task.wait(STEP)
	local forced = workspace:GetAttribute("WeatherForce")
	if type(forced) == "string" and WEATHERS[forced] then
		current = forced
		spellEnds = os.clock() + MAX_SPELL
	elseif os.clock() > spellEnds then
		current = pick(current)
		spellEnds = os.clock() + math.random(MIN_SPELL, MAX_SPELL)
	end
	local target = WEATHERS[current]
	rain = approach(rain, target.rain, CHANGE_RATE * STEP)
	overcast = approach(overcast, target.overcast, CHANGE_RATE * STEP)
	if rain > 0.05 then
		wetness = math.min(1, wetness + rain * SOAK_RATE * STEP)
	else
		wetness = math.max(0, wetness - DRY_RATE * STEP)
	end
	publish()
end
