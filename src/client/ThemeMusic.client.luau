-- The main theme ("Marrow Night", draft 1): four stems that start together and
-- loop, so the music can react to the game:
--   lead    -- the saxophone and its long tape-style echoes
--   pad     -- strings
--   rhythm  -- upright bass and the taxi-meter tick
--   dread   -- low tremolo strings and timpani; silent until the night turns
--              (a storm, a story chapter, or ThemeDread set on the player)
--
-- Also the death motif, as stingers on request: set the player's "ThemeStinger"
-- attribute to "death" or "omen" (see below).
--
-- Plays from the main menu on, and ducks under the story's cutscenes (the
-- Letterbox bars from Cutscene.luau). The intro cutscene's own SCORE_ID in
-- IntroCutscene.client is left alone so the two never play at once.
--
-- The stems aren't on Roblox yet: audio has to be uploaded from the Creator
-- Hub, which Claude can't do. Until then, in Studio only, it plays the same
-- files from Studio's own content folder (see STUDIO_LOCAL); for everyone else
-- it stays silent until UPLOADED has real ids.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- Fill these in with the uploaded audio ids ("rbxassetid://<number>").
local UPLOADED = {
	lead = "rbxassetid://0",
	pad = "rbxassetid://0",
	rhythm = "rbxassetid://0",
	dread = "rbxassetid://0",
}

-- Studio only: files copied into <Studio>/content/sounds/uber/. They vanish when
-- Studio updates, and they never work for anyone else, so none of this can ship.
local STUDIO_LOCAL = {
	lead = "rbxasset://sounds/uber/stem_lead_with_echo.wav",
	pad = "rbxasset://sounds/uber/stem_pad.wav",
	rhythm = "rbxasset://sounds/uber/stem_bass_and_tick.wav",
	dread = "rbxasset://sounds/uber/stem_dread_layer.wav",
}

-- The death motif ("The Last Fare" and its quieter, unresolved "Omen"): one-shot
-- stingers, played on request. Same arrangement as the stems above.
local UPLOADED_STINGERS = {
	death = "rbxassetid://0",
	omen = "rbxassetid://0",
	-- "Rear-View", the cue for chapter 8's mirror visions (uploaded by the
	-- user 2026-10-20; checked live: loads, 73.5 s).
	vision = "rbxassetid://102323812048675",
}
local STUDIO_LOCAL_STINGERS = {
	death = "rbxasset://sounds/uber/UberDeath_LastFare.wav",
	omen = "rbxasset://sounds/uber/UberDeath_Omen.wav",
}
-- How far the looping score drops while each stinger plays, and for how long
-- (the motif itself is ~17 s and ~8 s; the rest is echo tail).
local STINGER_DUCK = {
	death = { factor = 0.12, hold = 20 },
	omen = { factor = 0.12, hold = 22 },
	-- The vision's cue plays right through (73.5 s, see StoryScenes.vision),
	-- the score held down under it the whole time; "fade" (below) cuts it
	-- short if the chapter's left.
	vision = { factor = 0.1, hold = 74 },
}
local STINGER_VOLUME = 0.9

local MASTER_VOLUME = 0.55
local CUTSCENE_DUCK = 0.3
local STEMS = { "lead", "pad", "rhythm", "dread" }

local function resolve(stem: string): string?
	local uploaded = UPLOADED[stem]
	if uploaded ~= "rbxassetid://0" then
		return uploaded
	end
	if RunService:IsStudio() then
		return STUDIO_LOCAL[stem]
	end
	return nil
end

local function resolveStinger(kind: string): string?
	local uploaded = UPLOADED_STINGERS[kind]
	if uploaded ~= "rbxassetid://0" then
		return uploaded
	end
	if RunService:IsStudio() then
		return STUDIO_LOCAL_STINGERS[kind]
	end
	return nil
end

-- The menu is up between the loading screen and the player's choice.
while not player:GetAttribute("LoadingScreenDone") do
	player:GetAttributeChangedSignal("LoadingScreenDone"):Wait()
end

local group = Instance.new("SoundGroup")
group.Name = "Score"
group.Volume = MASTER_VOLUME
group.Parent = SoundService

local sounds: { [string]: Sound } = {}
for _, stem in STEMS do
	local id = resolve(stem)
	if not id then
		group:Destroy()
		for _, s in sounds do
			s:Destroy()
		end
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "Theme_" .. stem
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = if stem == "dread" then 0 else 1
	sound.SoundGroup = group
	sound.Parent = SoundService
	sounds[stem] = sound
end

-- Wait for every stem to load, so they can all start on the same frame and
-- stay in step.
local startedWaiting = os.clock()
local loaded = true
for stem, sound in sounds do
	while not sound.IsLoaded and os.clock() - startedWaiting < 20 do
		task.wait(0.1)
	end
	if not sound.IsLoaded or sound.TimeLength <= 0 then
		loaded = false
		warn(`[ThemeMusic] couldn't load the {stem} stem ({sound.SoundId})`)
	end
end
if not loaded then
	group:Destroy()
	for _, sound in sounds do
		sound:Destroy()
	end
	return
end

for _, sound in sounds do
	sound.TimePosition = 0
end
for _, sound in sounds do
	sound:Play()
end
if RunService:IsStudio() and UPLOADED.lead == "rbxassetid://0" then
	print("[ThemeMusic] playing the theme from Studio's local files (not uploaded yet)")
end

-- Duck under the story's cutscenes. Cutscene.luau only creates its Letterbox
-- gui once the intro is over, so this has to wait for it to turn up.
local playerGui = player:WaitForChild("PlayerGui")
local cutsceneFactor = 1
local stingerFactor = 1
local function applyGroupVolume(seconds: number)
	TweenService:Create(group, TweenInfo.new(seconds, Enum.EasingStyle.Sine), {
		Volume = MASTER_VOLUME * cutsceneFactor * stingerFactor,
	}):Play()
end
local function watchLetterbox(letterbox: ScreenGui)
	local function updateDuck()
		cutsceneFactor = if letterbox.Enabled then CUTSCENE_DUCK else 1
		applyGroupVolume(1.2)
	end
	letterbox:GetPropertyChangedSignal("Enabled"):Connect(updateDuck)
	updateDuck()
end
local existing = playerGui:FindFirstChild("Letterbox")
if existing and existing:IsA("ScreenGui") then
	watchLetterbox(existing)
end
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "Letterbox" and child:IsA("ScreenGui") then
		watchLetterbox(child)
	end
end)

-- The death motif. Anything can ask for it by setting the "ThemeStinger" attribute
-- on the player to "death" (a death on screen: the meter stops, bells fall home
-- to the tonic) or "omen" (a warning, the same three notes left hanging). Add a
-- suffix after a colon so setting it twice in a row still registers, e.g.
-- "death:1", "death:2". The loop underneath ducks while it plays.
local stingerGroup = Instance.new("SoundGroup")
stingerGroup.Name = "ScoreStinger"
stingerGroup.Volume = STINGER_VOLUME
stingerGroup.Parent = SoundService

-- Fetched now, so a stinger starts the moment it's asked for: fetched only
-- when asked, the vision's cue took over 8 s to start (checked live) -- and
-- a vision lasts about 12.
task.spawn(function()
	local preload = {}
	for kind in STINGER_DUCK do
		local id = resolveStinger(kind)
		if id then
			local s = Instance.new("Sound")
			s.SoundId = id
			table.insert(preload, s)
		end
	end
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync(preload)
	end)
	for _, s in preload do
		s:Destroy()
	end
end)

local stingerToken = 0
local currentStinger: Sound? = nil
local function fadeOutStinger(old: Sound)
	TweenService:Create(old, TweenInfo.new(0.8), { Volume = 0 }):Play()
	task.delay(0.9, function()
		old:Destroy()
	end)
end
local function playStinger(kind: string)
	local id = resolveStinger(kind)
	local duck = STINGER_DUCK[kind]
	if not id or not duck then
		return
	end
	stingerToken += 1
	local token = stingerToken
	local sound = Instance.new("Sound")
	sound.Name = "Stinger_" .. kind
	sound.SoundId = id
	sound.Volume = 1
	sound.SoundGroup = stingerGroup
	sound.Parent = SoundService
	local waited = os.clock()
	while not sound.IsLoaded and os.clock() - waited < 10 do
		task.wait(0.1)
	end
	if not sound.IsLoaded then
		warn(`[ThemeMusic] couldn't load the {kind} stinger ({id})`)
		sound:Destroy()
		return
	end
	-- Only one stinger at a time: a newer one takes over from the one playing.
	if token ~= stingerToken then
		sound:Destroy()
		return
	end
	if currentStinger and currentStinger.Parent then
		fadeOutStinger(currentStinger)
	end
	currentStinger = sound
	stingerFactor = duck.factor
	applyGroupVolume(0.6)
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(duck.hold, function()
		-- A newer stinger takes over the ducking.
		if token == stingerToken then
			stingerFactor = 1
			applyGroupVolume(4)
		end
	end)
end

-- "fade" (as "fade:<n>"): the stinger playing slips away over a few seconds,
-- and the score comes back up -- for a cue longer than its moment (the
-- vision's).
local function fadeStinger()
	stingerToken += 1
	local sound = currentStinger
	currentStinger = nil
	if sound and sound.Parent then
		TweenService:Create(sound, TweenInfo.new(4), { Volume = 0 }):Play()
		task.delay(4.2, function()
			sound:Destroy()
		end)
	end
	stingerFactor = 1
	applyGroupVolume(5)
end

local function onStingerAttribute()
	local value = player:GetAttribute("ThemeStinger")
	if typeof(value) ~= "string" then
		return
	end
	local kind = string.match(value, "^(%a+)")
	if kind == "fade" then
		fadeStinger()
	elseif kind then
		task.spawn(playStinger, kind)
	end
end
player:GetAttributeChangedSignal("ThemeStinger"):Connect(onStingerAttribute)
onStingerAttribute()

-- How dark the night is right now, 0 to 1. Anything can raise it by setting the
-- "ThemeDread" attribute on the player; a storm and the story's chapters raise it too.
local function dreadTarget(): number
	local value = 0
	local manual = player:GetAttribute("ThemeDread")
	if typeof(manual) == "number" then
		value = manual
	end
	local rain = workspace:GetAttribute("Rain")
	if typeof(rain) == "number" then
		value = math.max(value, 0.25 * rain)
	end
	if workspace:GetAttribute("Storm") == true then
		value = math.max(value, 0.4)
	end
	if player:GetAttribute("Busy") == "story" then
		value = math.max(value, 0.25)
	end
	return math.clamp(value, 0, 1)
end

local current = 0
task.spawn(function()
	while sounds.dread.Parent do
		current += (dreadTarget() - current) * 0.15
		sounds.dread.Volume = current
		-- A little less meter tick as the dread comes up.
		sounds.rhythm.Volume = 1 - 0.35 * current
		task.wait(0.25)
	end
end)
