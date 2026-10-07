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
}

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

local choices: { [string]: any } = {}
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

local function say(line)
	Screen.say(line.speaker, line.text, SPEAKER_COLORS[line.speaker])
end

local function applies(entry): boolean
	return StoryConfig.applies(entry, choices)
end

local function setObjective(value: string?)
	Screen.setObjective("story", value)
end

-- ===== The Story app =====

local announced = 0

local function refreshStory()
	local done = player:GetAttribute("StoryDone") or 0
	local faresSince = player:GetAttribute("FaresSinceStory") or 0
	local entries = {}
	local readyIndex = nil
	for index, chapter in StoryConfig.CHAPTERS do
		local status, need = StoryConfig.status(index, done, faresSince)
		if status == "ready" then
			readyIndex = index
		end
		table.insert(entries, {
			index = index,
			title = chapter.title,
			blurb = chapter.blurb,
			status = status,
			need = need,
		})
	end
	Phone.setStory(StoryConfig.PART_TITLE, entries, run and run.chapter, done >= #StoryConfig.CHAPTERS, player:GetAttribute("Busy") == "fare")

	-- A chapter that's just come ready: a text about it, and a nudge.
	local chapter = readyIndex and StoryConfig.CHAPTERS[readyIndex]
	if chapter and not chapter.startsFromIntro and not run then
		if announced ~= readyIndex then
			announced = readyIndex
			local t = chapter.unlockText
			if t then
				Phone.addMessage(t.from, t.text)
			end
		end
		Screen.setObjective("storyReady", `Story: "{chapter.title}" is ready -- press P, open Story`)
	else
		Screen.setObjective("storyReady", nil)
	end
end

for _, name in { "StoryDone", "FaresSinceStory", "Busy" } do
	player:GetAttributeChangedSignal(name):Connect(refreshStory)
end

Phone.onStoryStart(function(index)
	storyAction:FireServer("start", index)
	Phone.setOpen(false)
end)
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
local function playRide(token: number, step)
	lineToken += 1
	local mine = lineToken
	local lines = {}
	for _, line in step.lines or {} do
		if applies(line) then
			table.insert(lines, line)
		end
	end
	local texts = table.clone(step.texts or {})
	task.spawn(function()
		local index = 1
		local function arrived()
			return arrivedToken == token
		end
		while mine == lineToken and (index <= #lines or not arrived()) do
			local p = progress()
			for i = #texts, 1, -1 do
				if p >= texts[i].at or arrived() then
					Phone.addMessage(texts[i].from, texts[i].text)
					table.remove(texts, i)
				end
			end
			local line = lines[index]
			if line and (arrived() or p >= line.at) and (not arrived() or line.late or line.at <= p) then
				say(line)
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
	elseif kind == "ride" then
		if phase == "riding" then
			local what = cargo or aboard or "them"
			local verb = if cargo and not aboard then "Deliver" else "Drop off"
			Navigation.setTarget(step.spot.stop, `{verb} {if cargo and not aboard then cargo else what}`, RED)
			if step.timeLimit then
				setObjective(`Get {what} to {step.spot.name} -- don't let them catch you`)
			elseif cargo and not aboard then
				setObjective(`Take {cargo} to {step.spot.name}`)
			else
				setObjective(`Take {what} to {step.spot.name}`)
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
			Screen.flash(RED, 0.35, 1.5)
			setObjective("Don't move.")
			playLines(r.token, step.lines)
		elseif phase == "robbed" then
			meterOn = false
			Screen.setMeter("")
			aboard = nil
			Screen.flash(RED, 0.5, 2)
			setObjective(`Robbed. {nameOf("tommy")} took your cash and ran.`)
			if (r.amount or 0) > 0 then
				Screen.showMoney(-r.amount)
				Phone.addEarning("Robbed on Ember St", -r.amount)
			end
		end
	elseif kind == "errand" then
		if phase == "waiting" then
			Navigation.setTarget(nil)
			setObjective(step.objective or `Wait for {aboard or "them"}`)
			Screen.setTimer(r.deadline, Color3.fromRGB(240, 236, 225))
		elseif phase == "gunfire" then
			Screen.setTimer(nil)
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
			aboard = nil
			if (r.amount or 0) > 0 then
				Screen.showMoney(r.amount)
				Phone.addEarning(step.note or chapterOf(r).title, r.amount)
			end
		end
	elseif kind == "ending" then
		if phase == "ending" then
			stopEverything()
			Screen.titleCard(StoryConfig.PART_TITLE:upper(), step.title, step.subtitle, 5)
		end
	end
end

function handleUpdate(data)
	choices = data.choices or choices
	local r = data.run
	local previous = run
	run = r

	if not r then
		if previous then
			-- The chapter's over: finished, or given up.
			stopEverything()
			local chapter = chapterOf(previous)
			if (player:GetAttribute("StoryDone") or 0) >= previous.chapter and previous.chapter < #StoryConfig.CHAPTERS then
				Screen.titleCard(`CHAPTER {previous.chapter} COMPLETE`, chapter.title:upper(), "The next chapter unlocks after more fares.", 3)
			end
		end
		refreshStory()
		return
	end

	if not previous or previous.chapter ~= r.chapter then
		-- A chapter starting.
		stopEverything()
		local chapter = chapterOf(r)
		Screen.titleCard(`CHAPTER {r.chapter}`, chapter.title:upper(), chapter.blurb, 3.5)
		refreshStory()
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
