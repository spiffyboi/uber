-- What the game remembers about each player between visits: their cash and
-- how far through the story they've got. Saved to a DataStore when it
-- changes (every so often), when they leave and when the server shuts.
--
-- Everything lives on the player as attributes while they're in the game,
-- so the client can read it and the services (FareService, StoryService)
-- can change it:
--   Cash            -- money in hand
--   StoryDone       -- how many story chapters are finished (0 = none yet)
--   FaresSinceStory -- ordinary fares done since the last chapter finished
--   FaresDone       -- ordinary fares done, ever
--   DataLoaded      -- true once the save's been read (wait for this)
--   SaveState       -- "ok", or "off" when saving isn't possible here
-- plus the story's choices, kept in here (see getChoice/setChoice).
--
-- In Studio, saving only works with Game Settings > Security > "Enable
-- Studio Access to API Services" switched on. Without it the game runs as
-- normal, just without saving (SaveState = "off", shown on the phone).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local PlayerData = {}

local STORE_NAME = "UberSave_v1"
local AUTOSAVE_EVERY = 45

local TRACKED = { "Cash", "StoryDone", "FaresSinceStory", "FaresDone" }

-- Progress made before saving existed, put back the first time the save is
-- read (only when there's no save yet). The game's creator had about $80
-- and Ray's ride done when saving went in.
local RESTORED: { [number]: { [string]: any } } = {
	[308989604] = { Cash = 80, StoryDone = 1, FaresSinceStory = 1, FaresDone = 2 },
}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	end
end

type Record = {
	choices: { [string]: any },
	dirty: boolean,
	canSave: boolean,
}
local records: { [Player]: Record } = {}

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

local function snapshot(player: Player, record: Record)
	local data = { choices = record.choices }
	for _, name in TRACKED do
		data[name] = player:GetAttribute(name) or 0
	end
	return data
end

function PlayerData.save(player: Player)
	local record = records[player]
	if not record or not record.canSave or not store then
		return
	end
	local data = snapshot(player, record)
	record.dirty = false
	for attempt = 1, 2 do
		local ok, err = pcall(function()
			(store :: DataStore):SetAsync(keyFor(player), data, { player.UserId })
		end)
		if ok then
			return
		end
		warn(`PlayerData: couldn't save {player.Name} (attempt {attempt}): {err}`)
		task.wait(1)
	end
	record.dirty = true
end

local function load(player: Player)
	local record: Record = { choices = {}, dirty = false, canSave = false }
	records[player] = record

	local data = nil
	local ok, err = false, "no DataStore"
	if store then
		ok, err = pcall(function()
			data = (store :: DataStore):GetAsync(keyFor(player))
		end)
	end
	if not ok then
		-- Can't read it, so don't write over it either: play on unsaved.
		warn(`PlayerData: saving is off for {player.Name}: {err}`)
	end
	record.canSave = ok
	if ok and data == nil then
		data = RESTORED[player.UserId]
		record.dirty = data ~= nil
	end
	data = data or {}

	for _, name in TRACKED do
		player:SetAttribute(name, tonumber(data[name]) or 0)
	end
	if typeof(data.choices) == "table" then
		record.choices = data.choices
	end
	for _, name in TRACKED do
		player:GetAttributeChangedSignal(name):Connect(function()
			record.dirty = true
		end)
	end
	player:SetAttribute("SaveState", if ok then "ok" else "off")
	player:SetAttribute("DataLoaded", true)
end

-- Waits until `player`'s save has been read. False if they left first.
function PlayerData.waitLoaded(player: Player): boolean
	while player.Parent and not player:GetAttribute("DataLoaded") do
		player:GetAttributeChangedSignal("DataLoaded"):Wait()
	end
	return player.Parent ~= nil
end

function PlayerData.addCash(player: Player, amount: number)
	local cash = (player:GetAttribute("Cash") or 0) + amount
	player:SetAttribute("Cash", math.max(0, math.floor(cash * 100 + 0.5) / 100))
end

function PlayerData.increment(player: Player, name: string, by: number?)
	player:SetAttribute(name, (player:GetAttribute(name) or 0) + (by or 1))
end

function PlayerData.getChoice(player: Player, key: string): any
	local record = records[player]
	return record and record.choices[key]
end

function PlayerData.setChoice(player: Player, key: string, value: any)
	local record = records[player]
	if record then
		record.choices[key] = value
		record.dirty = true
	end
end

Players.PlayerAdded:Connect(load)
for _, player in Players:GetPlayers() do
	if not records[player] then
		task.spawn(load, player)
	end
end

Players.PlayerRemoving:Connect(function(player)
	PlayerData.save(player)
	records[player] = nil
end)

game:BindToClose(function()
	local pending = 0
	for player, record in records do
		if record.canSave then
			pending += 1
			task.spawn(function()
				PlayerData.save(player)
				pending -= 1
			end)
		end
	end
	local waited = 0
	while pending > 0 and waited < 20 do
		waited += task.wait(0.2)
	end
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_EVERY)
		for player, record in records do
			if record.dirty and record.canSave then
				task.spawn(PlayerData.save, player)
			end
		end
	end
end)

return PlayerData
