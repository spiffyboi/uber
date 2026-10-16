-- What the game remembers about each player between visits: their cash and
-- how far through the story they've got. Saved to a DataStore when it
-- changes (every so often), when they leave and when the server shuts.
--
-- The save is read the moment a player joins, but nothing's applied until
-- they pick from the menu (see GameMenu and Menu.client):
--   new  -- a new story (for a tester, it replaces their saved game)
--   load -- carry on with the saved story (testers only -- see Testers)
--   free -- Free Play: fares only, no story (a tester's wallet carries over)
--   test -- a bug-testing run from any chapter, never saved (testers only)
-- Anyone who isn't a tester can start a new story or Free Play, and isn't
-- saved.
--
-- Everything lives on the player as attributes while they're in the game,
-- so the client can read it and the services (FareService, StoryService)
-- can change it:
--   Cash            -- money in hand
--   StoryDone       -- how many story chapters are finished (0 = none yet)
--   FaresSinceStory -- ordinary fares done since the last chapter finished
--   FaresDone       -- ordinary fares done, ever
--   DataLoaded      -- true once the menu's been answered (wait for this)
--   SaveState       -- "ok"; "off" when saving isn't possible here; "test"
--                      in a bug-test run; "guest" for a non-tester
-- and, for the menu, set on joining:
--   IsTester, HasSave, SaveSummary, MenuReady
-- plus the story's choices and the passengers already heard, kept in here.
--
-- In Studio, saving only works with Game Settings > Security > "Enable
-- Studio Access to API Services" switched on. Without it the game runs as
-- normal, just without saving.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StoryConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StoryConfig"))
local Testers = require(script.Parent:WaitForChild("Testers"))

local PlayerData = {}

local STORE_NAME = "UberSave_v1"
local AUTOSAVE_EVERY = 45

local TRACKED = { "Cash", "StoryDone", "FaresSinceStory", "FaresDone" }

-- What a bug-test run starts with.
local TEST_CASH = 500

-- The story was nine short chapters until 2026-10-16, when they were joined
-- up into six, about two rides each (see StoryConfig). A save from before
-- then counts the old chapters: this is where each old count lands. (Half
-- of a joined chapter done counts as not done -- it starts again from its
-- top.)
local STORY_VERSION = 2
local OLD_STORY_DONE = { [0] = 0, [1] = 0, [2] = 1, [3] = 2, [4] = 2, [5] = 3, [6] = 4, [7] = 4, [8] = 5, [9] = 6 }

local function upgrade(data: { [string]: any }): { [string]: any }
	if data.StoryVersion == STORY_VERSION then
		return data
	end
	local upgraded = table.clone(data)
	upgraded.StoryDone = OLD_STORY_DONE[tonumber(data.StoryDone) or 0] or 0
	upgraded.StoryVersion = STORY_VERSION
	return upgraded
end

-- Progress made while saving wasn't switched on yet: offered as the saved
-- game when there isn't a real one. The game's creator was last seen
-- (2026-10-07, read off a running test) with $543.90, all of the story
-- there was then done (having told Vance about the house, and bought the
-- pistol) and six ordinary fares behind them.
local RESTORED: { [number]: { [string]: any } } = {
	[308989604] = {
		StoryVersion = STORY_VERSION,
		Cash = 543.9,
		StoryDone = 5,
		FaresSinceStory = 0,
		FaresDone = 6,
		choices = { toldVance = true, hasPistol = true },
	},
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
	saved: { [string]: any }?, -- what was read on joining, if anything
	readable: boolean, -- whether the DataStore could be read at all
	begun: boolean, -- the menu's been answered
	choices: { [string]: any },
	heard: { string }, -- ordinary fares' conversations already had (see Conversations)
	dirty: boolean,
	canSave: boolean,
}
local records: { [Player]: Record } = {}

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

local function snapshot(player: Player, record: Record)
	local data = { choices = record.choices, heard = record.heard, StoryVersion = STORY_VERSION }
	for _, name in TRACKED do
		data[name] = player:GetAttribute(name) or 0
	end
	return data
end

function PlayerData.save(player: Player)
	local record = records[player]
	if not record or not record.begun or not record.canSave or not store then
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

-- "Chapter 4 of 6 done (Wrong Colours) · $294.92", for the menu's Load
-- Game button.
local function summarise(data): string
	local done = tonumber(data.StoryDone) or 0
	local cash = tonumber(data.Cash) or 0
	local chapter = StoryConfig.CHAPTERS[done]
	local story = if done == 0
		then "Story not started"
		else `Chapter {done} of {#StoryConfig.CHAPTERS} done ({if chapter then chapter.title else "?"})`
	return story .. " · $" .. string.format("%.2f", cash)
end

-- On joining: read the save, and tell the menu what's on offer.
local function read(player: Player)
	local record: Record = {
		saved = nil,
		readable = false,
		begun = false,
		choices = {},
		heard = {},
		dirty = false,
		canSave = false,
	}
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
	record.readable = ok
	if typeof(data) ~= "table" then
		data = RESTORED[player.UserId]
	end
	if typeof(data) == "table" then
		data = upgrade(data)
	end
	record.saved = data

	local tester = Testers.isTester(player)
	player:SetAttribute("IsTester", tester)
	player:SetAttribute("HasSave", tester and data ~= nil)
	player:SetAttribute("SaveSummary", if data then summarise(data) else "")
	player:SetAttribute("MenuReady", true)
end

local function apply(player: Player, record: Record, data)
	for _, name in TRACKED do
		player:SetAttribute(name, tonumber(data[name]) or 0)
	end
	record.choices = if typeof(data.choices) == "table" then table.clone(data.choices) else {}
	record.heard = {}
	if typeof(data.heard) == "table" then
		for _, id in data.heard do
			if typeof(id) == "string" then
				table.insert(record.heard, id)
			end
		end
	end
end

-- The menu's been answered (see GameMenu): set the player up for `mode`.
-- Returns whether that was allowed.
function PlayerData.begin(player: Player, mode: string, options: { chapter: number?, toldVance: boolean? }?): boolean
	local record = records[player]
	if not record or record.begun then
		return false
	end
	local tester = Testers.isTester(player)
	local opts = options or {}

	if mode == "new" then
		apply(player, record, {})
		record.canSave = tester and record.readable
		record.dirty = record.canSave
	elseif mode == "load" then
		if not tester or not record.saved then
			return false
		end
		apply(player, record, record.saved)
		record.canSave = record.readable
	elseif mode == "free" then
		-- Fares only. A tester's wallet (and everything else) carries over
		-- from their saved game, and what they earn is saved back to it.
		apply(player, record, if tester and record.saved then record.saved else {})
		record.canSave = tester and record.readable
	elseif mode == "test" then
		local chapter = math.floor(tonumber(opts.chapter) or 0)
		if not tester or chapter < 1 or chapter > #StoryConfig.CHAPTERS then
			return false
		end
		-- Everything before `chapter` done -- including anything bought
		-- along the way -- and `chapter` itself next.
		local choices = { toldVance = opts.toldVance == true }
		for index = 1, chapter - 1 do
			for _, step in StoryConfig.CHAPTERS[index].steps do
				if step.type == "purchase" then
					choices["has" .. step.item] = true
				end
			end
		end
		apply(player, record, {
			Cash = TEST_CASH,
			StoryDone = chapter - 1,
			FaresSinceStory = 0,
			FaresDone = 0,
			choices = choices,
		})
		record.canSave = false
		player:SetAttribute("TestChapter", chapter)
	else
		return false
	end

	record.begun = true
	for _, name in TRACKED do
		player:GetAttributeChangedSignal(name):Connect(function()
			record.dirty = true
		end)
	end
	local state = "off"
	if mode == "test" then
		state = "test"
	elseif not tester then
		state = "guest"
	elseif record.readable then
		state = "ok"
	end
	player:SetAttribute("SaveState", state)
	player:SetAttribute("GameMode", mode)
	player:SetAttribute("DataLoaded", true)
	if record.canSave and mode == "new" then
		-- The old save's gone from now on.
		task.spawn(PlayerData.save, player)
	end
	return true
end

-- Waits until `player` has picked from the menu and been set up. False if
-- they left first.
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

-- The ordinary fares' conversations this player's already had.
function PlayerData.getHeard(player: Player): { string }
	local record = records[player]
	return if record then record.heard else {}
end

function PlayerData.markHeard(player: Player, id: string)
	local record = records[player]
	if record and not table.find(record.heard, id) then
		table.insert(record.heard, id)
		record.dirty = true
	end
end

-- Everyone's been heard: start the round again.
function PlayerData.clearHeard(player: Player)
	local record = records[player]
	if record then
		table.clear(record.heard)
		record.dirty = true
	end
end

Players.PlayerAdded:Connect(read)
for _, player in Players:GetPlayers() do
	if not records[player] then
		task.spawn(read, player)
	end
end

Players.PlayerRemoving:Connect(function(player)
	PlayerData.save(player)
	records[player] = nil
end)

game:BindToClose(function()
	local pending = 0
	for player, record in records do
		if record.canSave and record.begun then
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
			if record.dirty and record.canSave and record.begun then
				task.spawn(PlayerData.save, player)
			end
		end
	end
end)

return PlayerData
