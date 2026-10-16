-- Ordinary fares: Free Play, the mode on the menu that's just the job --
-- driving the city, taking whoever Dispatch sends (the story is its own
-- mode -- see StoryService). Each player has at most one fare at a time,
-- which goes:
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
-- or turn down, in Free Play only (the player's "Busy" attribute says
-- whether they're on one: "fare").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))
local FareConfig = require(Shared:WaitForChild("FareConfig"))
local Conversations = require(Shared:WaitForChild("Conversations"))
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
	conversation: string,
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
		conversation = fare.conversation,
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

type Spot = { standing: Vector3, stop: Vector3 }

-- Every sidewalk spot outside an ordinary building (not a taxi rank, club
-- queue, park wall...), on any avenue.
local ordinarySpots: { { x: number, index: number, side: number } } = {}
for _, avenue in CityConfig.AVENUES do
	for index = CityConfig.FIRST_SLOT, CityConfig.LAST_SLOT do
		for side = -1, 1, 2 do
			if not CityConfig.isCrossSlot(index) and not CityConfig.lotAt(index, side, avenue.x) then
				table.insert(ordinarySpots, { x = avenue.x, index = index, side = side })
			end
		end
	end
end

local function toSpot(x: number, index: number, side: number, along: number?): Spot
	local standing, stop = FareConfig.kerbSpot(x, index, side, along)
	return { standing = standing, stop = stop }
end

-- Where a passenger going to `destination` (see Conversations) could be let
-- out: outside the named place / any place of that kind, or any ordinary
-- spot on that avenue and stretch -- or anywhere at all.
local function destinationSpots(destination): { Spot }
	local spots = {}
	if destination and (destination.lot or destination.kind) then
		for _, lot in CityConfig.LOTS do
			if (destination.lot == nil or lot.name == destination.lot) and (destination.kind == nil or lot.kind == destination.kind) then
				table.insert(spots, toSpot(lot.x, lot.index + math.floor(((lot.span or 1) - 1) / 2), lot.side))
			end
		end
		return spots
	end
	for _, s in ordinarySpots do
		if destination then
			if destination.avenue and destination.avenue ~= s.x then
				continue
			end
			if destination.slots and (s.index < destination.slots[1] or s.index > destination.slots[2]) then
				continue
			end
		end
		table.insert(spots, toSpot(s.x, s.index, s.side, math.random(-8, 8)))
	end
	return spots
end

-- A few of `list`, at random.
local function sample<T>(list: { T }, count: number): { T }
	if #list <= count then
		return list
	end
	local copy = table.clone(list)
	local result = {}
	for _ = 1, count do
		table.insert(result, table.remove(copy, math.random(1, #copy)))
	end
	return result
end

-- Someone this player hasn't driven yet (and once they've driven everyone,
-- the round starts over).
local function nextConversation(player: Player)
	local heard = PlayerData.getHeard(player)
	local fresh = {}
	for _, conversation in Conversations.LIST do
		if not table.find(heard, conversation.id) then
			table.insert(fresh, conversation)
		end
	end
	if #fresh == 0 then
		PlayerData.clearHeard(player)
		fresh = Conversations.LIST
	end
	return pick(fresh)
end

-- An ordinary fare: someone new, picked up not too far from where the cab
-- is now, going far enough that what they've got to say fills the ride --
-- the drive is sized to the conversation, at an ordinary pace through
-- lights and turns (DRIVE_SPEED).
local DRIVE_SPEED = 36
local MIN_LENGTH, MAX_LENGTH = 900, 2600

local function streetFare(player: Player, state: PlayerState): Fare
	state.nextId += 1
	local fare: Fare = { id = `street{state.nextId}`, kind = "street", stage = "offered" } :: any
	local conversation = nextConversation(player)

	local car = carOf(player)
	local from = if car and car.PrimaryPart then car.PrimaryPart.Position else Vector3.zero
	local nearby = {}
	for _, s in ordinarySpots do
		local spot = toSpot(s.x, s.index, s.side)
		local distance = (flat(spot.stop) - flat(from)).Magnitude
		if distance > 60 and distance < 500 then
			table.insert(nearby, s)
		end
	end
	local p = if #nearby > 0 then pick(nearby) else pick(ordinarySpots)
	local pickup = toSpot(p.x, p.index, p.side, math.random(-8, 8))

	local target = math.clamp(Conversations.talkSeconds(conversation) * DRIVE_SPEED, MIN_LENGTH, MAX_LENGTH)
	local best, bestLength, bestMiss = nil, 0, math.huge
	for _, spot in sample(destinationSpots(conversation.destination), 40) do
		if (flat(spot.stop) - flat(pickup.stop)).Magnitude < 200 then
			continue
		end
		local _, length = Routing.route(pickup.stop, spot.stop)
		local miss = math.abs(length - target)
		if miss < bestMiss then
			best, bestLength, bestMiss = spot, length, miss
		end
	end
	if not best then
		best = toSpot(CityConfig.MAIN_AVENUE_X, CityConfig.LAST_SLOT, 1)
		local _, length = Routing.route(pickup.stop, best.stop)
		bestLength = length
	end

	fare.conversation = conversation.id
	fare.passenger = conversation.name
	fare.pickup, fare.pickupStanding = pickup.stop, pickup.standing
	fare.pickupName = Routing.placeName(pickup.stop)
	fare.dropoff, fare.dropoffStanding = best.stop, best.standing
	fare.dropoffName = Routing.placeName(best.stop)
	fare.routeLength = bestLength
	fare.price = FareConfig.price(bestLength)
	fare.tip = math.random(1, 6)
	fare.look = { skin = pick(SKIN_TONES), shirt = pick(CLOTHES), pants = pick(CLOTHES) }
	return fare
end

local function canOffer(player: Player, state: PlayerState): boolean
	return player.Parent ~= nil
		and states[player] == state
		and not state.fare
		and not state.offer
		and player:GetAttribute("Busy") == nil
		and player:GetAttribute("GameMode") == "free"
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
	PlayerData.markHeard(player, fare.conversation)
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

-- The shift starts (in Free Play, straight to the cab -- see IntroCutscene):
-- Dispatch starts offering fares.
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
