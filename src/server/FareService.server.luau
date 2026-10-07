-- Ordinary fares: the everyday job in between the story's chapters (see
-- StoryService). Each player has at most one fare at a time, which goes:
--   pickup   -- the passenger's waiting on the sidewalk; pull up beside them
--               and stop
--   boarding -- they walk to the cab and get in the back
--   riding   -- drive them to where they're going (the client shows the
--               way and plays what they say -- see Hud)
--   arrived  -- stopped outside; they finish talking (the client says when,
--               via FareAction "finish") and get out
-- and pays (fare + tip) into the player's cash (see PlayerData).
--
-- The Dispatch app on the phone gets offered fares one at a time, to take
-- or turn down -- once the first chapter (Ray, from the intro's fare call)
-- is done, and never while a story chapter's going (the player's "Busy"
-- attribute says which they're on: "fare" or "story").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))
local FareConfig = require(Shared:WaitForChild("FareConfig"))
local Routing = require(Shared:WaitForChild("Routing"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Passengers = require(script.Parent:WaitForChild("Passengers"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local fareUpdate = remotes:WaitForChild("FareUpdate") :: RemoteEvent
local fareAction = remotes:WaitForChild("FareAction") :: RemoteEvent
local acceptJob = remotes:WaitForChild("AcceptJob") :: RemoteEvent

-- If the passenger never says they're done (the client went away, say),
-- they get out anyway after this long stopped outside.
local ARRIVED_TIMEOUT = 75
local OFFER_DELAY = 6

type Fare = {
	id: string,
	kind: string,
	passenger: string,
	pickup: Vector3,
	pickupStanding: Vector3,
	pickupName: string,
	dropoff: Vector3,
	dropoffStanding: Vector3,
	dropoffName: string,
	routeLength: number,
	price: number,
	tip: number,
	look: Passengers.Look,
	chatter: number?,
	arrival: number?,
	stage: string,
	npc: Model?,
	arrivedAt: number?,
	paid: number?,
}

type PlayerState = {
	fare: Fare?,
	offer: Fare?,
	nextId: number,
}

local states: { [Player]: PlayerState } = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function carOf(player: Player): Model?
	return workspace:FindFirstChild(player.Name .. "_Car") :: Model?
end

-- What the client gets told about a fare (no Instances, just the facts).
local function describe(fare: Fare?)
	if not fare then
		return nil
	end
	return {
		id = fare.id,
		kind = fare.kind,
		passenger = fare.passenger,
		pickup = fare.pickup,
		pickupStanding = fare.pickupStanding,
		pickupName = fare.pickupName,
		dropoff = fare.dropoff,
		dropoffStanding = fare.dropoffStanding,
		dropoffName = fare.dropoffName,
		routeLength = fare.routeLength,
		price = fare.price,
		tip = fare.tip,
		chatter = fare.chatter,
		arrival = fare.arrival,
		stage = fare.stage,
		paid = fare.paid,
	}
end

local function send(player: Player)
	local state = states[player]
	if state then
		fareUpdate:FireClient(player, { fare = describe(state.fare), offer = describe(state.offer) })
	end
end

-- ===== Fares =====

local SKIN_TONES = {
	Color3.fromRGB(185, 150, 122),
	Color3.fromRGB(140, 100, 75),
	Color3.fromRGB(225, 195, 165),
	Color3.fromRGB(90, 65, 50),
	Color3.fromRGB(205, 165, 130),
}
local CLOTHES = {
	Color3.fromRGB(70, 66, 78),
	Color3.fromRGB(96, 92, 82),
	Color3.fromRGB(120, 30, 40),
	Color3.fromRGB(40, 60, 90),
	Color3.fromRGB(150, 130, 100),
	Color3.fromRGB(30, 30, 34),
}

local function pick<T>(list: { T }): T
	return list[math.random(1, #list)]
end

-- A spot on some avenue's sidewalk, outside an ordinary building (not a
-- taxi rank, club queue, park wall...).
local function randomSpot(): (Vector3, Vector3)
	for _ = 1, 50 do
		local avenue = pick(CityConfig.AVENUES)
		local index = math.random(CityConfig.FIRST_SLOT, CityConfig.LAST_SLOT)
		local side = if math.random() < 0.5 then -1 else 1
		if not CityConfig.isCrossSlot(index) and not CityConfig.lotAt(index, side, avenue.x) then
			return FareConfig.kerbSpot(avenue.x, index, side, math.random(-8, 8))
		end
	end
	return FareConfig.kerbSpot(CityConfig.MAIN_AVENUE_X, 2, 1)
end

-- An ordinary fare: picked up not too far from where the cab is now, going
-- a decent distance.
local function streetFare(player: Player, state: PlayerState): Fare
	state.nextId += 1
	local fare: Fare = { id = `street{state.nextId}`, kind = "street", stage = "offered" } :: any
	local car = carOf(player)
	local from = if car and car.PrimaryPart then car.PrimaryPart.Position else Vector3.zero
	local standing, stop = randomSpot()
	for _ = 1, 20 do
		if (flat(stop) - flat(from)).Magnitude < 450 then
			break
		end
		standing, stop = randomSpot()
	end
	local dropStanding, dropStop = randomSpot()
	local length = 0
	for _ = 1, 30 do
		local _, l = Routing.route(stop, dropStop)
		length = l
		if l > 350 and l < 1100 then
			break
		end
		dropStanding, dropStop = randomSpot()
	end
	fare.passenger = pick(FareConfig.NAMES)
	fare.pickup, fare.pickupStanding = stop, standing
	fare.pickupName = Routing.placeName(stop)
	fare.dropoff, fare.dropoffStanding = dropStop, dropStanding
	fare.dropoffName = Routing.placeName(dropStop)
	fare.routeLength = length
	fare.price = FareConfig.price(length)
	fare.tip = math.random(0, 4)
	fare.look = { skin = pick(SKIN_TONES), shirt = pick(CLOTHES), pants = pick(CLOTHES) }
	fare.chatter = math.random(1, #FareConfig.CHATTER)
	fare.arrival = math.random(1, #FareConfig.ARRIVALS)
	return fare
end

local function canOffer(player: Player, state: PlayerState): boolean
	return player.Parent ~= nil
		and states[player] == state
		and not state.fare
		and not state.offer
		and player:GetAttribute("Busy") == nil
		and (player:GetAttribute("StoryDone") or 0) >= 1
end

local function offerLater(player: Player, delay: number)
	task.delay(delay, function()
		local state = states[player]
		if state and canOffer(player, state) then
			state.offer = streetFare(player, state)
			send(player)
		end
	end)
end

local function startFare(player: Player, state: PlayerState, fare: Fare)
	fare.stage = "pickup"
	fare.npc = Passengers.spawn(fare.passenger, fare.look, fare.pickupStanding, fare.pickup)
	state.fare = fare
	player:SetAttribute("Busy", "fare")
	send(player)
end

local function board(player: Player, fare: Fare, car: Model)
	fare.stage = "boarding"
	send(player)
	task.spawn(function()
		if fare.npc then
			Passengers.board(fare.npc, car)
		end
		local state = states[player]
		if state and state.fare == fare then
			fare.stage = "riding"
			send(player)
		end
	end)
end

local function complete(player: Player, state: PlayerState)
	local fare = state.fare
	if not fare or fare.stage ~= "arrived" then
		return
	end
	local pay = fare.price + fare.tip
	PlayerData.addCash(player, pay)
	PlayerData.increment(player, "FaresDone")
	PlayerData.increment(player, "FaresSinceStory")
	fare.paid = pay
	fare.stage = "done"
	Passengers.letOut(fare.npc, carOf(player), fare.dropoffStanding, fare.dropoff)
	fare.npc = nil
	send(player)
	state.fare = nil
	player:SetAttribute("Busy", nil)
	send(player)
end

-- ===== Watching where each cab is =====

task.spawn(function()
	while true do
		task.wait(0.2)
		for player, state in states do
			local fare = state.fare
			local car = carOf(player)
			local chassis = car and car.PrimaryPart
			if not fare or not car or not chassis then
				continue
			end
			local position = flat(chassis.Position)
			local stopped = chassis.AssemblyLinearVelocity.Magnitude < FareConfig.STOPPED_SPEED
			if fare.stage == "pickup" then
				if stopped and (position - flat(fare.pickup)).Magnitude < FareConfig.PICKUP_RADIUS then
					board(player, fare, car)
				end
			elseif fare.stage == "riding" then
				if stopped and (position - flat(fare.dropoff)).Magnitude < FareConfig.DROPOFF_RADIUS then
					fare.stage = "arrived"
					fare.arrivedAt = os.clock()
					send(player)
				end
			elseif fare.stage == "arrived" then
				if os.clock() - (fare.arrivedAt :: number) > ARRIVED_TIMEOUT then
					complete(player, state)
				end
			end
		end
	end
end)

fareAction.OnServerEvent:Connect(function(player, action, id)
	local state = states[player]
	if not state or typeof(action) ~= "string" then
		return
	end
	if action == "finish" then
		complete(player, state)
	elseif action == "accept" then
		local offer = state.offer
		if offer and not state.fare and offer.id == id and player:GetAttribute("Busy") == nil then
			state.offer = nil
			startFare(player, state, offer)
		end
	elseif action == "decline" then
		if state.offer and state.offer.id == id then
			state.offer = nil
			send(player)
			offerLater(player, 10)
		end
	elseif action == "cancel" then
		-- Giving up on the fare in hand (from the Dispatch app).
		local fare = state.fare
		if fare and (fare.stage == "pickup" or fare.stage == "riding") then
			if fare.npc then
				if fare.stage == "riding" then
					Passengers.letOut(fare.npc, carOf(player), fare.dropoffStanding, fare.dropoff)
				else
					fare.npc:Destroy()
				end
				fare.npc = nil
			end
			state.fare = nil
			player:SetAttribute("Busy", nil)
			send(player)
		end
	end
end)

-- The intro's "Fare called in": Ray (StoryService) the first time; after
-- that, Dispatch just starts offering fares.
acceptJob.OnServerEvent:Connect(function(player)
	if PlayerData.waitLoaded(player) then
		offerLater(player, 4)
	end
end)

local function onPlayerAdded(player: Player)
	if states[player] then
		return
	end
	local state: PlayerState = { fare = nil, offer = nil, nextId = 0 }
	states[player] = state
	-- A story chapter starting takes back whatever fare was on offer; one
	-- ending (or a fare finishing) means it's time for another.
	player:GetAttributeChangedSignal("Busy"):Connect(function()
		local busy = player:GetAttribute("Busy")
		if busy == "story" and state.offer then
			state.offer = nil
			send(player)
		elseif busy == nil then
			offerLater(player, OFFER_DELAY)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	local state = states[player]
	if state and state.fare and state.fare.npc then
		state.fare.npc:Destroy()
	end
	states[player] = nil
end)
