-- The story on this side (see StoryConfig for the chapters and StoryService
-- for running them): keeps the phone's Story app up to date, texts when a
-- new chapter unlocks, and plays whatever step the server says the chapter
-- is on -- the red arrows to the next stop, what's said on the way, the
-- choices, the chapter cards -- telling the server when each conversation's
-- done.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FareConfig = require(Shared:WaitForChild("FareConfig"))
local StoryConfig = require(Shared:WaitForChild("StoryConfig"))
local Phone = require(script.Parent.Phone)
local Navigation = require(script.Parent.Navigation)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local storyUpdate = remotes:WaitForChild("StoryUpdate") :: RemoteEvent
local storyAction = remotes:WaitForChild("StoryAction") :: RemoteEvent

local player = Players.LocalPlayer

local RED = StoryConfig.COLOR

local SPEAKER_COLORS = {
	YOU = Color3.fromRGB(150, 200, 255),
	RAY = Color3.fromRGB(255, 196, 60),
	TOMMY = Color3.fromRGB(200, 200, 205),
	DEZ = Color3.fromRGB(90, 210, 120),
	RUNNER = Color3.fromRGB(90, 210, 120),
	VANCE = Color3.fromRGB(235, 80, 90),
	MINISTER = Color3.fromRGB(215, 205, 185),
	TEDDY = Color3.fromRGB(215, 190, 150),
	LOU = Color3.fromRGB(240, 220, 170),
	CALDER = Color3.fromRGB(170, 192, 220),
	JUNE = Color3.fromRGB(236, 172, 190),
	OKAFOR = Color3.fromRGB(206, 186, 140),
	MAN = Color3.fromRGB(200, 90, 96),
}

-- True while something (the side-street glimpse) has the screen and a
-- ride's conversation should wait.
local holdLines = false

-- Updates can arrive before the screen's ready (the first chapter starts
-- the moment the intro's call is accepted): keep them all, in order.
local pending = {}
local ready = false
local handleUpdate: (any) -> ()
storyUpdate.OnClientEvent:Connect(function(data)
	if ready then
		handleUpdate(data)
	else
		table.insert(pending, data)
	end
end)

while not player:GetAttribute("IntroDone") do
	player:GetAttributeChangedSignal("IntroDone"):Wait()
end

local Screen = require(script.Parent.Screen)
local Cutscene = require(script.Parent.Cutscene)
local StoryScenes = require(script.Parent.StoryScenes)
-- (Adds chapters 9 and 10's scenes to StoryScenes.)
require(script.Parent.LateScenes)

local choices: { [string]: any } = {}
-- Choices made on this screen (on the move, in a ride -- see playRide),
-- which win over an update from the server that hadn't heard of them yet.
local chosenHere: { [string]: any } = {}
local routeShown: { [number]: boolean } = {} -- askFirst rides told where to go
local run = nil -- the chapter being played, as last heard from the server
local seen: { [string]: boolean } = {}
local lineToken = 0
local arrivedToken: number? = nil
local aboard: string? = nil -- who's in the back
local cargo: string? = nil -- what's in the trunk
local meterOn = false

local function chapterOf(r)
	return StoryConfig.CHAPTERS[r.chapter]
end

local function stepOf(r)
	return chapterOf(r).steps[r.step]
end

local function nameOf(who: string): string
	local character = StoryConfig.CHARACTERS[who]
	return if character then character.name else who
end

-- ("{name}" in a line is the player's own name -- Dez, in the alley.)
local function say(line)
	local text = string.gsub(line.text or "", "{name}", (string.gsub(player.DisplayName, "%%", "%%%%")))
	Screen.say(line.speaker, text, SPEAKER_COLORS[line.speaker])
end

local function applies(entry): boolean
	return StoryConfig.applies(entry, choices)
end

-- For testing in Studio only: plays a story cutscene again on demand, with
-- whoever's in the back as the cast -- fire PlayerGui.DebugScene with the
-- chapter's number and the scene step's number (or with a made-up step, to
-- try out a shot or two). Nothing in the game fires it, and it isn't there
-- outside Studio.
if RunService:IsStudio() then
	local debugScene = Instance.new("BindableEvent")
	debugScene.Name = "DebugScene"
	debugScene.Parent = player:WaitForChild("PlayerGui")
	debugScene.Event:Connect(function(chapterIndex: any, stepIndex: number?)
		local step = if type(chapterIndex) == "table" then chapterIndex else StoryConfig.CHAPTERS[chapterIndex].steps[stepIndex]
		StoryScenes[step.scene](step, function(line)
			if applies(line) then
				say(line)
			end
		end, function()
			return true
		end, run)
	end)
end

local function setObjective(value: string?)
	Screen.setObjective("story", value)
end

-- ===== The Story app =====

local announced = 0

local freePlay = player:GetAttribute("GameMode") == "free"
if freePlay then
	Phone.setStoryNote("This is Free Play: just fares. The story's on the main menu.")
end

local function partTitle(chapter): string
	return StoryConfig.PARTS[StoryConfig.partOf(chapter)] or ""
end

local function refreshStory()
	local done = player:GetAttribute("StoryDone") or 0
	local entries = {}
	local readyIndex = nil
	for index, chapter in StoryConfig.CHAPTERS do
		local status = StoryConfig.status(index, done)
		if status == "ready" then
			readyIndex = index
		end
		table.insert(entries, {
			index = index,
			part = partTitle(chapter),
			title = chapter.title,
			blurb = chapter.blurb,
			status = status,
		})
	end
	Phone.setStory(entries, run and run.chapter, done >= #StoryConfig.CHAPTERS)
	if freePlay then
		return
	end

	-- The next chapter's on its way (it starts by itself shortly -- see
	-- StoryService): a text about it, and a word on screen.
	local chapter = readyIndex and StoryConfig.CHAPTERS[readyIndex]
	if chapter and not chapter.startsFromIntro and not run then
		if announced ~= readyIndex then
			announced = readyIndex
			local t = chapter.unlockText
			if t then
				Phone.addMessage(t.from, t.text)
			end
		end
		Screen.setObjective("storyReady", `Up next: "{chapter.title}"`)
	elseif not chapter and not run and done >= #StoryConfig.CHAPTERS then
		Screen.setObjective("storyReady", "That's the story so far -- more to come.")
	else
		Screen.setObjective("storyReady", nil)
	end
end

for _, name in { "StoryDone", "Busy" } do
	player:GetAttributeChangedSignal(name):Connect(refreshStory)
end

Phone.onStoryStart(function(index)
	storyAction:FireServer("start", index)
	Phone.setOpen(false)
end)

-- ===== Contacts =====
-- Mom and Dispatch from the start; whoever the story's put in the phone
-- since (Dez, from chapter 3 -- see the contact cutscene).

local function refreshContacts(highlight: string?)
	local contacts = {
		{ name = "Dispatch", number = "555-0100", note = "Marrow Cab Co." },
		{ name = "Mom", number = "555-0112" },
	}
	local done = player:GetAttribute("StoryDone") or 0
	for index, chapter in StoryConfig.CHAPTERS do
		for _, step in chapter.steps do
			if step.contact and (index <= done or step.contact.name == highlight) then
				table.insert(contacts, 1, step.contact)
			end
		end
	end
	Phone.setContacts(contacts, highlight)
end
refreshContacts()
player:GetAttributeChangedSignal("StoryDone"):Connect(function()
	refreshContacts()
end)

-- Mid-cutscene: the player's own phone pulled up, open on Contacts with the
-- new name at the top, then put away again.
local function showNewContact(name: string)
	local phoneGui = player.PlayerGui:FindFirstChild("Phone")
	if phoneGui then
		phoneGui.Enabled = true
	end
	refreshContacts(name)
	Phone.openApp("contacts")
	Phone.setOpen(true)
	task.wait(3.5)
	Phone.setOpen(false)
	task.wait(0.3)
	Phone.openApp("home")
	if phoneGui and Cutscene.isPlaying() then
		phoneGui.Enabled = false
	end
end
Phone.onStoryQuit(function()
	storyAction:FireServer("quit")
end)

-- ===== Playing a step =====

-- How far through the current ride (0 to 1), by what's left of the route.
local function progress(): number
	local route, remaining = Navigation.getRoute()
	if not run or #route == 0 or (run.rideLength or 0) <= 0 then
		return 0
	end
	return math.clamp(1 - remaining / run.rideLength, 0, 1)
end

local function continueStep(token: number)
	if run and run.token == token then
		storyAction:FireServer("continue", token)
	end
end

-- The way to a ride's stop, and what to do there.
local function showRoute(step)
	local what = cargo or aboard or "them"
	local verb = if cargo and not aboard then "Deliver" else "Drop off"
	if step.type == "drive" then
		Navigation.setTarget(step.spot.stop, step.spot.name, RED)
		setObjective(`Drive to {step.spot.name}`)
		return
	end
	Navigation.setTarget(step.spot.stop, `{verb} {if cargo and not aboard then cargo else what}`, RED)
	if step.timeLimit then
		setObjective(`Get {what} to {step.spot.name} -- don't let them catch you`)
	elseif cargo and not aboard then
		setObjective(`Take {cargo} to {step.spot.name}`)
	else
		setObjective(`Take {what} to {step.spot.name}`)
	end
end

-- A choice in the middle of a ride (one of its lines -- see StoryConfig):
-- picked with the number keys, still driving.
local function chooseOnTheMove(token: number, index: number, choice)
	local texts = {}
	for _, option in choice.options do
		table.insert(texts, option.text)
	end
	local picked = Screen.choose(choice.prompt, texts)
	local value = choice.options[picked].value
	choices[choice.key] = value
	chosenHere[choice.key] = value
	if run and run.token == token then
		storyAction:FireServer("rideChoice", { line = index, option = picked })
	end
end

-- Lines said while stopped, then "done".
local function playLines(token: number, lines)
	lineToken += 1
	local mine = lineToken
	task.spawn(function()
		for _, line in lines do
			if mine ~= lineToken then
				return
			end
			if applies(line) then
				say(line)
			end
		end
		if mine == lineToken then
			continueStep(token)
		end
	end)
end

-- A ride's conversation: each line once the cab's far enough along (texts
-- too), then -- once it's stopped at the other end -- anything not said yet
-- and the arrival lines, then "done".
-- (Whether a line applies is decided as it comes up, not at the start: a
-- choice made earlier in the same ride can decide it.) A `vision` (chapter
-- 8's mirror) plays once the cab's that far along -- or on arrival, if it
-- got there first -- with the talk held while it's on.
local function playRide(token: number, step)
	lineToken += 1
	local mine = lineToken
	local lines = step.lines or {}
	local texts = table.clone(step.texts or {})
	local vision = step.vision
	task.spawn(function()
		local index = 1
		local function arrived()
			return arrivedToken == token
		end
		while mine == lineToken and (index <= #lines or not arrived() or vision) do
			while holdLines and mine == lineToken do
				task.wait(0.1)
			end
			local p = progress()
			for i = #texts, 1, -1 do
				if p >= texts[i].at or arrived() then
					Phone.addMessage(texts[i].from, texts[i].text)
					table.remove(texts, i)
				end
			end
			local line = lines[index]
			-- (Not till what comes before it's been said.)
			if vision and (arrived() or (p >= vision.at and (not line or line.at >= vision.at))) then
				local v = vision
				vision = nil
				holdLines = true
				Screen.hush()
				StoryScenes.vision(v, function(l)
					if applies(l) then
						say(l)
					end
				end, function()
					return mine == lineToken
				end)
				holdLines = false
			elseif line and not applies(line) then
				index += 1
			elseif line and (arrived() or p >= line.at) and (not arrived() or line.late or line.at <= p) then
				if line.choice then
					chooseOnTheMove(token, index, line.choice)
				else
					say(line)
				end
				if line.showRoute and not routeShown[token] and not arrived() then
					routeShown[token] = true
					showRoute(step)
				end
				index += 1
			elseif line and arrived() then
				-- Got there before an early line came up: skip it.
				index += 1
			else
				task.wait(0.25)
			end
		end
		if mine ~= lineToken then
			return
		end
		for _, line in step.arrival or {} do
			if mine ~= lineToken then
				return
			end
			if applies(line) then
				say(line)
			end
		end
		if mine == lineToken then
			continueStep(token)
		end
	end)
end

local function stopEverything()
	lineToken += 1
	Screen.hush()
	Navigation.setTarget(nil)
	setObjective(nil)
	Screen.setTimer(nil)
	Screen.setMeter("")
	meterOn = false
	aboard, cargo = nil, nil
end

local function onStep(r, step, phase: string)
	local kind = step.type
	if kind == "text" then
		Phone.addMessage(step.from, step.text)
	elseif kind == "pickup" then
		local name = nameOf(step.who)
		if phase == "waiting" then
			Navigation.setTarget(step.spot.stop, "Pick up " .. name, RED)
			setObjective(`Pick up {name} -- {step.spot.name}`)
		elseif phase == "boarding" then
			Navigation.setTarget(nil)
			setObjective(`{name} is getting in...`)
			aboard = name
		end
	elseif kind == "ride" or kind == "drive" then
		if phase == "riding" then
			if step.askFirst and not routeShown[r.token] then
				-- Nowhere to go till they've said where (see playRide).
				Navigation.setTarget(nil)
				setObjective(`Where to? Ask {aboard or "them"}.`)
			else
				showRoute(step)
			end
			meterOn = step.meter == true
			if not seen[r.token .. ":rideStarted"] then
				seen[r.token .. ":rideStarted"] = true
				arrivedToken = nil
				playRide(r.token, step)
			end
		elseif phase == "failed" then
			Screen.flash(RED, 0.45, 1.2)
			setObjective(step.failText or "Too slow. Try again.")
		elseif phase == "arrived" then
			arrivedToken = r.token
			Navigation.setTarget(nil)
			setObjective("Stopped outside.")
			if meterOn then
				-- The meter stops on the full fare and stays there until paid.
				meterOn = false
				Screen.setMeter(string.format("METER  $%.2f", FareConfig.price(r.rideLength or 0)))
			end
		end
	elseif kind == "talk" or kind == "handoff" then
		if phase == "talk" then
			if kind == "handoff" then
				setObjective(`Hand over {cargo or "the bag"}`)
				cargo = nil
			end
			playLines(r.token, step.lines)
		end
	elseif kind == "choice" then
		if phase == "choosing" then
			setObjective("Choose what to say")
			task.spawn(function()
				local texts = {}
				for _, option in step.options do
					table.insert(texts, option.text)
				end
				local picked = Screen.choose(step.prompt, texts)
				choices[step.key] = step.options[picked].value
				if run and run.token == r.token then
					storyAction:FireServer("choose", picked)
				end
			end)
		end
	elseif kind == "robbery" then
		if phase == "threat" then
			-- The robbery cutscene (see StoryScenes), then "done".
			setObjective("Don't move.")
			lineToken += 1
			local token = r.token
			task.spawn(function()
				StoryScenes.robbery(step.lines, function(line)
					if applies(line) then
						say(line)
					end
				end, function()
					return run ~= nil and run.token == token
				end)
				continueStep(token)
			end)
		elseif phase == "robbed" then
			meterOn = false
			Screen.setMeter("")
			aboard = nil
			Screen.flash(RED, 0.5, 2)
			setObjective(`Robbed. {nameOf("tommy")} took your cash and ran. Start the engine again (E).`)
			if (r.amount or 0) > 0 then
				Screen.showMoney(-r.amount)
				Phone.addEarning("Robbed down by the wharf", -r.amount)
			end
			task.spawn(StoryScenes.robberyEscape)
		end
	elseif kind == "scene" then
		if phase == "playing" and step.scene == "contact" then
			lineToken += 1
			local token = r.token
			task.spawn(function()
				StoryScenes.contact(step, function(line)
					if applies(line) then
						say(line)
					end
				end, function()
					return run ~= nil and run.token == token
				end, function()
					showNewContact(step.contact.name)
				end)
				continueStep(token)
			end)
		elseif phase == "playing" and StoryScenes[step.scene] then
			-- The gun store, the pistol going in the door, the hold-up:
			-- see StoryScenes.
			setObjective(nil)
			Navigation.setTarget(nil)
			lineToken += 1
			local token = r.token
			task.spawn(function()
				-- If a scene breaks, put the screen back and carry on, rather
				-- than leave the player stuck in it (seen once: frozen at
				-- Ray's front step).
				local ok, err = pcall(StoryScenes[step.scene], step, function(line)
					if applies(line) then
						say(line)
					end
				end, function()
					return run ~= nil and run.token == token
				end, r)
				if not ok then
					warn(`Story: the {step.scene} scene broke: {err}`)
					StoryScenes.abort()
				end
				continueStep(token)
			end)
		end
	elseif kind == "goInside" then
		if phase == "goingIn" then
			Navigation.setTarget(nil)
			setObjective(`{aboard or "They"} goes inside.`)
		end
	elseif kind == "lookout" then
		-- Waiting outside (chapter 9): phone calls that ring out, a man
		-- going in, and then the choice that isn't one.
		local token = r.token
		if phase == "waiting" then
			Navigation.setTarget(nil)
			setObjective(step.objective)
			for _, call in step.calls or {} do
				task.delay(call.at, function()
					if run and run.token == token then
						Phone.addMessage(call.from, "Incoming call...")
						task.wait(7)
						if run and run.token == token then
							Phone.addMessage(call.from, "Missed call")
						end
					end
				end)
			end
		elseif phase == "prompt" then
			setObjective(step.prompt)
			task.spawn(function()
				Screen.choose("A man just went in after Teddy.", { step.prompt })
				continueStep(token)
			end)
		end
	elseif kind == "walk" then
		-- On foot (chapter 10): the edges of the picture closing in, until
		-- he's gone far enough, or long enough.
		if phase == "walking" then
			setObjective(nil)
			Navigation.setTarget(nil)
			local token = r.token
			if StoryScenes.state.shotDown then
				-- Never got up (see LateScenes' depot): nothing to walk.
				continueStep(token)
				return
			end
			task.spawn(function()
				local gui = Instance.new("ScreenGui")
				gui.Name = "Closing"
				gui.IgnoreGuiInset = true
				gui.ResetOnSpawn = false
				gui.DisplayOrder = 8
				gui.Parent = player:WaitForChild("PlayerGui")
				local edges = {}
				for _, edge in { { 0, 90 }, { 1, 270 }, { 2, 0 }, { 3, 180 } } do
					local f = Instance.new("Frame")
					f.BackgroundColor3 = Color3.new(0, 0, 0)
					f.BorderSizePixel = 0
					local vertical = edge[1] < 2
					f.Size = if vertical then UDim2.fromScale(1, 0.5) else UDim2.fromScale(0.5, 1)
					f.Position = if edge[1] == 0 then UDim2.fromScale(0, 0) elseif edge[1] == 1 then UDim2.fromScale(0, 0.5) elseif edge[1] == 2 then UDim2.fromScale(0, 0) else UDim2.fromScale(0.5, 0)
					f.Parent = gui
					local g = Instance.new("UIGradient")
					g.Rotation = edge[2]
					g.Transparency = NumberSequence.new(0, 1)
					g.Parent = f
					table.insert(edges, g)
				end
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local from = if root then root.Position else Vector3.zero
				local started = os.clock()
				local seconds = step.seconds or 14
				while run and run.token == token do
					local t = (os.clock() - started) / seconds
					local moved = if root then (root.Position - from).Magnitude else 0
					local closing = math.clamp(math.max(t, moved / 30), 0, 1)
					for _, g in edges do
						g.Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 0.2 - 0.2 * closing),
							NumberSequenceKeypoint.new(math.clamp(0.25 + closing * 0.6, 0, 0.99), 1),
							NumberSequenceKeypoint.new(1, 1),
						})
					end
					if closing >= 1 then
						break
					end
					task.wait()
				end
				continueStep(token)
				task.wait(1.5)
				gui:Destroy()
			end)
		end
	elseif kind == "purchase" then
		if phase == "bought" and (r.amount or 0) > 0 then
			Screen.showMoney(-r.amount)
			Phone.addEarning(step.note or step.item, -r.amount)
		end
	elseif kind == "errand" then
		if phase == "waiting" then
			Navigation.setTarget(nil)
			setObjective(step.objective or `Wait for {aboard or "them"}`)
			Screen.setTimer(r.deadline, Color3.fromRGB(240, 236, 225))
		elseif phase == "gunfire" then
			Screen.setTimer(nil)
			-- Chapter 4: up in the lit window Dez was talking about.
			StoryScenes.windowGunfire()
			task.spawn(function()
				for _ = 1, 4 do
					Screen.flash(Color3.fromRGB(255, 230, 190), 0.25, 0.25)
					task.wait(0.35 + math.random() * 0.4)
				end
			end)
			setObjective("Gunshots.")
			task.spawn(Screen.say, "", "(Gunshots, from inside. Then shouting.)", Color3.new(1, 1, 1))
		elseif phase == "returning" then
			Screen.setTimer(nil)
			setObjective(`{aboard or "They"}'s coming back...`)
		end
	elseif kind == "collect" then
		if phase == "waiting" then
			Navigation.setTarget(step.spot.stop, step.label or "Pick up", RED)
			setObjective(`{step.label or "Pick it up"} -- {step.spot.name}`)
		elseif phase == "collected" then
			Navigation.setTarget(nil)
			cargo = "the bag"
			setObjective("The bag's in the trunk.")
		end
	elseif kind == "dropoff" then
		if phase == "paid" then
			meterOn = false
			Screen.setMeter("")
			local leaving = aboard
			aboard = nil
			if (r.amount or 0) > 0 then
				Screen.showMoney(r.amount)
				Phone.addEarning(step.note or chapterOf(r).title, r.amount)
			end
			if step.contact then
				-- Her card, into the phone.
				task.spawn(showNewContact, step.contact.name)
			end
			if step.outro == "walkAway" and Cutscene.isPlaying() and leaving then
				task.spawn(StoryScenes.walkAway, leaving)
			elseif step.outro == "tower" or step.outro == "vanish" then
				-- Chapter 7's Teddy at the foot of the tower; chapter 8's
				-- Okafor, gone along the railings (see StoryScenes). The
				-- chapter waits for it.
				local token = r.token
				task.spawn(function()
					StoryScenes[step.outro](leaving)
					continueStep(token)
				end)
			end
		end
	elseif kind == "ending" then
		if phase == "ending" then
			stopEverything()
			Screen.titleCard(partTitle(chapterOf(r)):upper(), step.title, step.subtitle, 5)
		end
	end
end

function handleUpdate(data)
	choices = data.choices or choices
	for key, value in chosenHere do
		choices[key] = value
	end
	local r = data.run
	local previous = run
	run = r

	if not r then
		if previous then
			-- The chapter's over: finished, or given up.
			stopEverything()
			local chapter = chapterOf(previous)
			local completed = (player:GetAttribute("StoryDone") or 0) >= previous.chapter
			if not completed and Cutscene.isPlaying() then
				-- Given up mid-cutscene.
				StoryScenes.abort()
			end
			-- (A chapter that ends on its own card -- the end of a part --
			-- doesn't need this one too.)
			local endsOnCard = false
			for _, step in chapter.steps do
				endsOnCard = endsOnCard or step.type == "ending"
			end
			if completed then
				-- Whatever the chapter's last scene left on screen, put back
				-- (chapter 10 ends on black).
				StoryScenes.chapterEnded()
			end
			if completed and not endsOnCard then
				Screen.titleCard(`CHAPTER {previous.chapter} COMPLETE`, chapter.title:upper(), "The story carries on in a moment.", 3)
			end
		end
		refreshStory()
		return
	end

	if not previous or previous.chapter ~= r.chapter then
		-- A chapter starting.
		stopEverything()
		local chapter = chapterOf(r)
		table.clear(StoryScenes.state)
		-- (Chapter 8 ends in the morning; chapter 10 is one; any other
		-- chapter's at night.) And the phone's clock, for the ones that say
		-- what time it is.
		StoryScenes.endMorning()
		if chapter.morning then
			StoryScenes.kit.setMorning(true)
		end
		if chapter.clock then
			Phone.setClock(chapter.clock[1], chapter.clock[2])
		end
		Screen.titleCard(`{partTitle(chapter):upper()}  ·  CHAPTER {r.chapter}`, chapter.title:upper(), chapter.blurb, 3.5)
		refreshStory()
	end

	-- Chapter 9's side street: once the server's set it out ahead, wait for
	-- the cab to reach the junction, then the glimpse (see StoryScenes).
	-- It always plays: at the junction if the cab gets there, or anyway if
	-- it's gone past, or hasn't arrived after a while (stopped, or another
	-- way round) -- the shots are set by the side street, not the cab.
	if r.alley and not seen[r.token .. ":alley"] then
		seen[r.token .. ":alley"] = true
		local token, alley = r.token, r.alley
		local alleyStep = stepOf(r)
		task.spawn(function()
			local placed = os.clock()
			while run and run.token == token do
				local car = workspace:FindFirstChild(player.Name .. "_Car")
				local chassis = car and (car :: Model).PrimaryPart
				local due = os.clock() - placed > 15
				if chassis then
					local offset = alley.corner - chassis.Position
					local ahead = offset:Dot(alley.travel)
					local across = (offset - alley.travel * ahead) * Vector3.new(1, 0, 1)
					-- A little before the junction, so the look's out of the side
					-- window and ahead, not straight through the door.
					due = due or (ahead < 35 and across.Magnitude < 30)
				end
				if due then
					holdLines = true
					Screen.hush()
					StoryScenes.alley(alley, (alleyStep.alley or {}).lines or {}, function(line)
						if applies(line) then
							say(line)
						end
					end)
					holdLines = false
					return
				end
				task.wait()
			end
		end)
	end

	-- A morning chapter stays morning, however it got started (seen once:
	-- chapter 10 straight on from chapter 9 came up at night).
	if chapterOf(r).morning and not game:GetService("Lighting"):GetAttribute("Morning") then
		StoryScenes.kit.setMorning(true)
	end

	if r.deadline and r.phase == "riding" then
		Screen.setTimer(r.deadline, RED)
	elseif r.phase ~= "waiting" then
		Screen.setTimer(nil)
	end

	-- Each phase of each step is played once (a ride that's started over
	-- against the clock comes back as "riding" with a new deadline).
	local key = `{r.token}:{r.phase}:{r.deadline or ""}`
	if seen[key] then
		return
	end
	seen[key] = true
	onStep(r, stepOf(r), r.phase)
end

-- The meter, ticking up on the story's paying rides.
RunService.Heartbeat:Connect(function()
	if meterOn and run then
		Screen.setMeter(string.format("METER  $%.2f", FareConfig.BASE_FARE + (run.rideLength or 0) * FareConfig.RATE_PER_STUD * progress()))
	end
end)

ready = true
refreshStory()
for _, data in pending do
	handleUpdate(data)
end
pending = {}
