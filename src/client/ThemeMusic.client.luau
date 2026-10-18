-- The main theme ("Marrow Night", draft 1): four stems that start together and
-- loop, so the music can react to the game:
--   lead    -- the saxophone and its long tape-style echoes
--   pad     -- strings
--   rhythm  -- upright bass and the taxi-meter tick
--   dread   -- low tremolo strings and timpani; silent until the night turns
--              (a storm, a story chapter, or ThemeDread set on the player)
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
local function watchLetterbox(letterbox: ScreenGui)
	local function updateDuck()
		local target = if letterbox.Enabled then CUTSCENE_DUCK else 1
		TweenService:Create(group, TweenInfo.new(1.2, Enum.EasingStyle.Sine), { Volume = MASTER_VOLUME * target }):Play()
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
