-- The story (see StoryConfig): runs a chapter's steps in order for whoever's
-- playing it -- people waiting on the sidewalk, getting in, getting out,
-- paying, robbing you, choosing for you -- and tells their client
-- (Story.client) where it's got to, which shows it: the way there, what's
-- said, the choices.
--
-- Chapters are started from the Story app once they unlock; the first (Ray)
-- starts from the intro's fare call. While one's going, the player's
-- "Busy" attribute is "story" and Dispatch stops offering fares (see
-- FareService). Finishing one saves straight away.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FareConfig = require(Shared:WaitForChild("FareConfig"))
local StoryConfig = require(Shared:WaitForChild("StoryConfig"))
local Routing = require(Shared:WaitForChild("Routing"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Passengers = require(script.Parent:WaitForChild("Passengers"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local storyUpdate = remotes:WaitForChild("StoryUpdate") :: RemoteEvent
local storyAction = remotes:WaitForChild("StoryAction") :: RemoteEvent
local acceptJob = remotes:WaitForChild("AcceptJob") :: RemoteEvent

-- How long a stop waits on the client to say everyone's finished talking
-- before getting on with it anyway (the client went away, say).
local TALK_TIMEOUT = 75

type Run = {
	chapter: number,
	step: number,
	token: number,
	phase: string,
	npc: Model?, -- whoever's riding along
	waiting: Model?, -- someone waiting at the next stop
	prop: BasePart?,
	lastSpot: any?,
	rideLength: number,
	deadline: number?,
	amount: number?,
	continued: number?, -- the token the client last said "done" for
	chose: any?,
}

local runs: { [Player]: Run } = {}
local nextToken = 0

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function carOf(player: Player): Model?
	return workspace:FindFirstChild(player.Name .. "_Car") :: Model?
end

local function choicesOf(player: Player): { [string]: any }
	local choices = {}
	for _, chapter in StoryConfig.CHAPTERS do
		for _, step in chapter.steps do
			if step.type == "choice" then
				choices[step.key] = PlayerData.getChoice(player, step.key)
			end
		end
	end
	return choices
end

local function send(player: Player)
	local run = runs[player]
	storyUpdate:FireClient(player, {
		choices = choicesOf(player),
		run = run and {
			chapter = run.chapter,
			step = run.step,
			token = run.token,
			phase = run.phase,
			rideLength = run.rideLength,
			deadline = run.deadline,
			amount = run.amount,
		},
	})
end

local function setPhase(player: Player, run: Run, phase: string)
	run.phase = phase
	send(player)
end

local function alive(player: Player, run: Run): boolean
	return runs[player] == run and player.Parent ~= nil
end

-- Waits for the cab to be stopped within `radius` of `point`. False if the
-- chapter ended (or the player left) first.
local function waitStoppedNear(player: Player, run: Run, point: Vector3, radius: number, giveUpAt: number?): boolean
	while alive(player, run) do
		local car = carOf(player)
		local chassis = car and car.PrimaryPart
		if chassis then
			local stopped = chassis.AssemblyLinearVelocity.Magnitude < FareConfig.STOPPED_SPEED
			if stopped and (flat(chassis.Position) - flat(point)).Magnitude < radius then
				return true
			end
		end
		if giveUpAt and workspace:GetServerTimeNow() > giveUpAt then
			return false
		end
		task.wait(0.2)
	end
	return false
end

-- Waits for the client to say it's finished with this step (everyone's
-- said their piece).
local function waitContinue(player: Player, run: Run, timeout: number?)
	local started = os.clock()
	while alive(player, run) and run.continued ~= run.token do
		if os.clock() - started > (timeout or TALK_TIMEOUT) then
			break
		end
		task.wait(0.1)
	end
end

local function spawnCharacter(who: string, place): Model
	local character = StoryConfig.CHARACTERS[who]
	return Passengers.spawn(character.name, character.look, place.standing, place.stop)
end

-- A holdall sitting on the sidewalk.
local function spawnBag(place): BasePart
	local bag = Instance.new("Part")
	bag.Name = "StoryBag"
	bag.Size = Vector3.new(2.6, 1.3, 1.3)
	bag.Color = Color3.fromRGB(28, 28, 32)
	bag.Material = Enum.Material.Fabric
	bag.Anchored = true
	bag.CanCollide = false
	bag.CFrame = CFrame.new(place.standing + Vector3.new(0, -0.55, 0))
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1.2, 0.5, 0.15)
	handle.Color = bag.Color
	handle.Material = Enum.Material.Fabric
	handle.Anchored = true
	handle.CanCollide = false
	handle.CFrame = bag.CFrame * CFrame.new(0, 0.85, 0)
	handle.Parent = bag
	bag.Parent = workspace
	return bag
end

-- Muzzle flashes from a doorway: bursts of light, nothing else.
local function gunfire(at: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = "Gunfire"
	folder.Parent = workspace
	local flash = Instance.new("Part")
	flash.Size = Vector3.new(0.8, 0.8, 0.8)
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 200, 120)
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CastShadow = false
	flash.Transparency = 1
	flash.Parent = folder
	local light = Instance.new("PointLight")
	light.Color = flash.Color
	light.Range = 26
	light.Brightness = 0
	light.Parent = flash
	task.spawn(function()
		for _ = 1, 9 do
			flash.Position = at + Vector3.new(math.random(-3, 3), 3 + math.random() * 2, math.random(-3, 3))
			flash.Transparency = 0
			light.Brightness = 8
			task.wait(0.06)
			flash.Transparency = 1
			light.Brightness = 0
			task.wait(0.12 + math.random() * 0.35)
		end
		folder:Destroy()
	end)
end

local function cleanUp(run: Run)
	for _, thing in { run.npc, run.waiting, run.prop } do
		if thing then
			(thing :: Instance):Destroy()
		end
	end
	run.npc, run.waiting, run.prop = nil, nil, nil
end

-- ===== Steps =====

local handlers: { [string]: (Player, Run, any) -> () } = {}

function handlers.text(player, run)
	setPhase(player, run, "text")
	task.wait(1.2)
end

function handlers.pickup(player, run, step)
	run.npc = spawnCharacter(step.who, step.spot)
	setPhase(player, run, "waiting")
	if not waitStoppedNear(player, run, step.spot.stop, FareConfig.PICKUP_RADIUS) then
		return
	end
	setPhase(player, run, "boarding")
	local car = carOf(player)
	if car and run.npc then
		Passengers.board(run.npc, car)
	end
end

function handlers.ride(player, run, step)
	local car = carOf(player)
	local from = if car and car.PrimaryPart then car.PrimaryPart.Position else step.spot.stop
	local _, length = Routing.route(from, step.spot.stop)
	run.rideLength = length
	run.lastSpot = step.spot
	-- Whoever's meeting the cab at the other end is already there waiting.
	local chapter = StoryConfig.CHAPTERS[run.chapter]
	local nextStep = chapter.steps[run.step + 1]
	if nextStep and nextStep.type == "handoff" then
		run.waiting = spawnCharacter(nextStep.who, nextStep.spot)
	end
	while alive(player, run) do
		run.deadline = if step.timeLimit then workspace:GetServerTimeNow() + step.timeLimit else nil
		setPhase(player, run, "riding")
		if waitStoppedNear(player, run, step.spot.stop, FareConfig.DROPOFF_RADIUS, run.deadline) then
			break
		end
		if not alive(player, run) then
			return
		end
		-- Out of time: say so, and go again.
		run.deadline = nil
		setPhase(player, run, "failed")
		task.wait(3)
	end
	run.deadline = nil
	setPhase(player, run, "arrived")
	waitContinue(player, run)
end

function handlers.talk(player, run)
	setPhase(player, run, "talk")
	waitContinue(player, run)
end

function handlers.choice(player, run, step)
	run.chose = nil
	setPhase(player, run, "choosing")
	while alive(player, run) and run.chose == nil do
		task.wait(0.1)
	end
	if run.chose ~= nil then
		local option = step.options[run.chose]
		PlayerData.setChoice(player, step.key, option.value)
	end
end

function handlers.robbery(player, run, step)
	setPhase(player, run, "threat")
	waitContinue(player, run)
	if not alive(player, run) then
		return
	end
	local taken = math.min(step.take, player:GetAttribute("Cash") or 0)
	PlayerData.addCash(player, -taken)
	run.amount = taken
	setPhase(player, run, "robbed")
	local place = run.lastSpot
	if run.npc and place then
		Passengers.letOut(run.npc, carOf(player), place.standing, place.stop, 20)
		run.npc = nil
	end
	task.wait(2)
end

function handlers.errand(player, run, step)
	local place = run.lastSpot
	local npc = run.npc
	if not place or not npc then
		return
	end
	local car = carOf(player)
	local door = Passengers.awayFrom(place.standing, place.stop, 8)
	Passengers.getOut(npc, car, place.standing, door)
	run.deadline = workspace:GetServerTimeNow() + step.seconds
	setPhase(player, run, "waiting")
	Passengers.walkTo(npc, door, 4)
	npc.Parent = nil
	local shotsAt = run.deadline - 4
	while alive(player, run) and workspace:GetServerTimeNow() < (if step.gunfire then shotsAt else run.deadline) do
		task.wait(0.2)
	end
	if step.gunfire and alive(player, run) then
		setPhase(player, run, "gunfire")
		gunfire(door + (flat(place.standing) - flat(place.stop)).Unit * 6)
		task.wait(4)
	end
	if not alive(player, run) then
		return
	end
	-- Back out, and in.
	run.deadline = nil
	setPhase(player, run, "returning")
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.WalkSpeed = if step.gunfire then 20 else 10
	npc.Parent = workspace
	car = carOf(player)
	if car then
		Passengers.board(npc, car)
	end
end

function handlers.collect(player, run, step)
	run.prop = spawnBag(step.spot)
	setPhase(player, run, "waiting")
	if not waitStoppedNear(player, run, step.spot.stop, FareConfig.PICKUP_RADIUS) then
		return
	end
	if run.prop then
		run.prop:Destroy()
		run.prop = nil
	end
	setPhase(player, run, "collected")
	task.wait(1.5)
end

function handlers.handoff(player, run, step)
	local npc = run.waiting or spawnCharacter(step.who, step.spot)
	run.waiting = npc
	setPhase(player, run, "talk")
	waitContinue(player, run)
	run.waiting = nil
	task.spawn(function()
		local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.Anchored = false
			root:SetNetworkOwner(nil)
		end
		Passengers.walkTo(npc, Passengers.awayFrom(step.spot.standing, step.spot.stop, 10), 5)
		npc:Destroy()
	end)
end

function handlers.dropoff(player, run, step)
	local pay = if step.pay == "meter" then FareConfig.price(run.rideLength) else step.pay
	pay += step.tip or 0
	local place = run.lastSpot
	if run.npc and place then
		Passengers.letOut(run.npc, carOf(player), place.standing, place.stop)
		run.npc = nil
	end
	PlayerData.addCash(player, pay)
	run.amount = pay
	setPhase(player, run, "paid")
	task.wait(1.5)
end

function handlers.ending(player, run)
	setPhase(player, run, "ending")
	task.wait(7)
end

-- ===== Chapters =====

local function finish(player: Player, run: Run, completed: boolean)
	if runs[player] ~= run then
		return
	end
	cleanUp(run)
	runs[player] = nil
	if completed then
		player:SetAttribute("StoryDone", run.chapter)
		player:SetAttribute("FaresSinceStory", 0)
		task.spawn(PlayerData.save, player)
	end
	player:SetAttribute("Busy", nil)
	send(player)
end

local function startChapter(player: Player, index: number)
	if runs[player] or player:GetAttribute("Busy") then
		return
	end
	local chapter = StoryConfig.CHAPTERS[index]
	if not chapter then
		return
	end
	local status = StoryConfig.status(index, player:GetAttribute("StoryDone") or 0, player:GetAttribute("FaresSinceStory") or 0)
	if status ~= "ready" then
		return
	end
	local run: Run = {
		chapter = index,
		step = 0,
		token = 0,
		phase = "",
		rideLength = 0,
	}
	runs[player] = run
	player:SetAttribute("Busy", "story")
	task.spawn(function()
		for stepIndex, step in chapter.steps do
			if not alive(player, run) then
				return
			end
			if not StoryConfig.applies(step, choicesOf(player)) then
				continue
			end
			nextToken += 1
			run.step = stepIndex
			run.token = nextToken
			run.amount = nil
			local ok, err = pcall(handlers[step.type], player, run, step)
			if not ok then
				warn(`StoryService: chapter {index} step {stepIndex} ({step.type}) failed: {err}`)
			end
		end
		finish(player, run, alive(player, run))
	end)
end

storyAction.OnServerEvent:Connect(function(player, action, value)
	if typeof(action) ~= "string" then
		return
	end
	local run = runs[player]
	if action == "start" and typeof(value) == "number" then
		startChapter(player, value)
	elseif action == "continue" and run and value == run.token then
		run.continued = value
	elseif action == "choose" and run and typeof(value) == "number" and run.phase == "choosing" then
		local step = StoryConfig.CHAPTERS[run.chapter].steps[run.step]
		if step.type == "choice" and step.options[value] then
			run.chose = value
		end
	elseif action == "quit" and run then
		-- Walking away from a chapter: it starts again from the top next time.
		finish(player, run, false)
	end
end)

-- The intro's "Fare called in" is accepted: that's Ray, the first chapter
-- -- if it hasn't been done before.
acceptJob.OnServerEvent:Connect(function(player)
	if not PlayerData.waitLoaded(player) then
		return
	end
	if (player:GetAttribute("StoryDone") or 0) == 0 then
		startChapter(player, 1)
	end
end)

local function onPlayerAdded(player: Player)
	task.spawn(function()
		if PlayerData.waitLoaded(player) then
			send(player)
		end
	end)
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	local run = runs[player]
	if run then
		cleanUp(run)
		runs[player] = nil
	end
end)
