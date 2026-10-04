local Players = game:GetService("Players")

-- Roblox auto-spawns a player's character the moment they join by default,
-- which in Studio's local Play test can happen almost immediately -- well
-- before any of the building below finishes (InsertService:LoadAsset for
-- the taxi/traffic meshes in particular can take real time). With nothing
-- built yet -- no road, no IntroSpawn -- that character has nothing to land
-- on and falls straight through the world. Turning auto-load off here,
-- before anything else runs, and only back on once the world is fully
-- built (see the bottom of this file) is what actually closes that gap; the
-- client-side loading screen (ReplicatedFirst/LoadingScreen.client.luau)
-- covers the wait visually.
Players.CharacterAutoLoads = false

local OpeningSetBuilder = require(script.Parent.OpeningSetBuilder)
local TaxiOfficeBuilder = require(script.Parent.TaxiOfficeBuilder)
local PedestrianSpawner = require(script.Parent.PedestrianSpawner)
local TrafficSpawner = require(script.Parent.TrafficSpawner)

-- OpeningSetBuilder builds IntersectionBuilder's cross streets/traffic
-- lights itself (see its own build()), so TrafficSpawner -- which reads
-- those lights every frame -- is safe to start right after it.
OpeningSetBuilder.build()
TaxiOfficeBuilder.build()
PedestrianSpawner.build()
TrafficSpawner.build()

-- The world is fully built now -- safe to let characters spawn. Anyone who
-- connected while auto-load was off (the common case in Studio, where the
-- test player is already in Players:GetPlayers() by this point) needs their
-- character loaded manually; CharacterAutoLoads = true alone only covers
-- players who join *after* this line.
Players.CharacterAutoLoads = true
for _, player in Players:GetPlayers() do
	if not player.Character then
		player:LoadCharacter()
	end
end
