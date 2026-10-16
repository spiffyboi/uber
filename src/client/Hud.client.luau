-- Everything on screen once the shift starts (after the intro):
--   * the minimap, top right, north up, with your route
--   * your cash, under it
--   * the phone (see Phone), bottom right
-- and the ordinary fares on this side: the server (FareService) says where
-- a fare's got to; this points the way (Navigation), shows the objective,
-- the meter and what the passenger says (Screen), and tells the server when
-- they've said their piece and are ready to get out. (The story's chapters
-- are Story.client's.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FareConfig = require(Shared:WaitForChild("FareConfig"))
local Conversations = require(Shared:WaitForChild("Conversations"))
local Phone = require(script.Parent.Phone)
local MapView = require(script.Parent.MapView)
local Navigation = require(script.Parent.Navigation)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local fareUpdate = remotes:WaitForChild("FareUpdate") :: RemoteEvent
local fareAction = remotes:WaitForChild("FareAction") :: RemoteEvent

local player = Players.LocalPlayer

local GOLD = Color3.fromRGB(255, 196, 60)
local GREEN = Color3.fromRGB(90, 220, 120)

-- Fare updates can arrive before the HUD's ready: hold on to the latest.
local pending = nil
local ready = false
local handleUpdate: (any) -> ()
fareUpdate.OnClientEvent:Connect(function(data)
	if ready then
		handleUpdate(data)
	else
		pending = data
	end
end)

while not player:GetAttribute("IntroDone") do
	player:GetAttributeChangedSignal("IntroDone"):Wait()
end

local Screen = require(script.Parent.Screen)

-- ===== Screen furniture =====

local gui = Instance.new("ScreenGui")
gui.Name = "Hud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.Parent = player:WaitForChild("PlayerGui")

-- Minimap, with a rim.
local MINIMAP_SIZE = 210
local minimapFrame = Instance.new("Frame")
minimapFrame.Name = "Minimap"
minimapFrame.AnchorPoint = Vector2.new(1, 0)
minimapFrame.Position = UDim2.new(1, -16, 0, 12)
minimapFrame.Size = UDim2.fromOffset(MINIMAP_SIZE, MINIMAP_SIZE)
minimapFrame.BackgroundTransparency = 1
minimapFrame.Parent = gui
local minimap = MapView.new(minimapFrame, { size = MINIMAP_SIZE, scale = 0.42 })
local rimCorner = Instance.new("UICorner")
rimCorner.CornerRadius = UDim.new(0, 10)
rimCorner.Parent = minimap.container
local rim = Instance.new("UIStroke")
rim.Color = Color3.fromRGB(20, 20, 24)
rim.Thickness = 4
rim.Parent = minimap.container

local cashLabel = Screen.outlined(gui, 26, GOLD, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 12 + MINIMAP_SIZE + 6),
	Size = UDim2.fromOffset(MINIMAP_SIZE, 30),
	TextXAlignment = Enum.TextXAlignment.Center,
})

local function updateCash()
	local cash = player:GetAttribute("Cash") or 0
	cashLabel.Text = string.format("$%.2f", cash)
	Phone.setCash(cash)
end
player:GetAttributeChangedSignal("Cash"):Connect(updateCash)
updateCash()

local function updateSaveState()
	Phone.setSaveState(player:GetAttribute("SaveState"))
end

-- A bug test says so in the corner the whole time, so nobody mistakes it
-- for their real game.
if player:GetAttribute("GameMode") == "test" then
	Screen.outlined(gui, 18, Color3.fromRGB(255, 120, 90), {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.fromOffset(300, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = `BUG TEST · chapter {player:GetAttribute("TestChapter") or "?"} · not saved`,
	})
end
player:GetAttributeChangedSignal("SaveState"):Connect(updateSaveState)
updateSaveState()

-- ===== Fares =====

local current = nil -- the fare as last heard from the server
local rideToken = 0 -- bumped whenever a ride's dialogue should stop
local arrivedFlag = false

-- How far through the ride (0 to 1), by what's left of the route. Zero
-- until the first route's been worked out, a moment after setting off --
-- an empty route would otherwise read as already there.
local function progress(fare): number
	local route, remaining = Navigation.getRoute()
	if #route == 0 or fare.routeLength <= 0 then
		return 0
	end
	return math.clamp(1 - remaining / fare.routeLength, 0, 1)
end

local function speakerName(fare, speaker: string): string
	if speaker == "PASSENGER" then
		return fare.passenger:upper()
	end
	return speaker
end

-- Plays a ride's conversation (see Conversations): each line once the cab's
-- far enough along, spread evenly over the ride, then -- once it's pulled up
-- outside -- anything not said yet and the goodbye, and then lets the server
-- know they're getting out.
local function runRide(fare)
	rideToken += 1
	local token = rideToken
	arrivedFlag = false
	local conversation = Conversations.BY_ID[fare.conversation]
	local lines = if conversation then conversation.lines else {}
	local goodbye = if conversation then conversation.goodbye else {}
	task.spawn(function()
		local index = 1
		while token == rideToken and index <= #lines do
			local line = lines[index]
			if arrivedFlag or progress(fare) >= Conversations.lineAt(index, #lines) then
				Screen.say(speakerName(fare, line.speaker), line.text)
				index += 1
			else
				task.wait(0.25)
			end
		end
		while token == rideToken and not arrivedFlag do
			task.wait(0.25)
		end
		if token ~= rideToken then
			return
		end
		for _, line in goodbye do
			if token ~= rideToken then
				return
			end
			Screen.say(speakerName(fare, line.speaker), line.text)
		end
		if token == rideToken then
			fareAction:FireServer("finish")
		end
	end)
end

local function setObjective(value: string?)
	Screen.setObjective("fare", value)
end

local lastOfferId = nil

function handleUpdate(data)
	local fare = data.fare
	local previous = current
	current = fare

	if data.offer and data.offer.id ~= lastOfferId then
		lastOfferId = data.offer.id
		Phone.addMessage("Dispatch", `New fare: {data.offer.passenger} at {data.offer.pickupName}. Open Dispatch to take it.`)
	end
	Phone.setOffer(data.offer)

	if not fare then
		Phone.setJob(nil)
		if previous then
			-- The fare's over (or given up): stop pointing at it.
			rideToken += 1
			Navigation.setTarget(nil)
			Screen.setMeter("")
		end
		setObjective(if data.offer then "New fare on your phone -- press P" else nil)
		return
	end

	Phone.setJob(fare)
	local isNew = previous == nil or previous.id ~= fare.id
	local stageChanged = isNew or previous.stage ~= fare.stage

	if isNew and fare.stage == "pickup" then
		Phone.addMessage("Dispatch", `{fare.passenger} is waiting at {fare.pickupName}.`)
	end
	if not stageChanged then
		return
	end

	if fare.stage == "pickup" then
		Navigation.setTarget(fare.pickup, "Pick up " .. fare.passenger, GOLD)
		setObjective(`Pick up {fare.passenger} -- {fare.pickupName}`)
		Screen.setMeter("")
	elseif fare.stage == "boarding" then
		setObjective(`{fare.passenger} is getting in...`)
	elseif fare.stage == "riding" then
		Navigation.setTarget(fare.dropoff, "Drop off " .. fare.passenger, GREEN)
		setObjective(`Take {fare.passenger} to {fare.dropoffName}`)
		if previous == nil or previous.stage ~= "riding" then
			runRide(fare)
		end
	elseif fare.stage == "arrived" then
		arrivedFlag = true
		Navigation.setTarget(nil)
		setObjective(`Stopped outside. {fare.passenger}'s getting out...`)
	elseif fare.stage == "done" then
		rideToken += 1
		Navigation.setTarget(nil)
		Screen.setMeter("")
		if fare.paid then
			Screen.showMoney(fare.paid)
			Phone.addEarning(`{fare.passenger} -- {fare.dropoffName}`, fare.paid)
		end
	end
end

-- The meter, ticking up as the ride goes (it lands exactly on the quoted
-- fare on arrival).
RunService.Heartbeat:Connect(function()
	if current and (current.stage == "riding" or current.stage == "arrived") then
		local shown = FareConfig.BASE_FARE + current.routeLength * FareConfig.RATE_PER_STUD * (if current.stage == "arrived" then 1 else progress(current))
		Screen.setMeter(string.format("METER  $%.2f", shown))
	end
end)

-- Minimap and phone map follow the player and the camera.
Navigation.RouteChanged:Connect(function()
	local route = Navigation.getRoute()
	local target = Navigation.getTarget()
	local label, color = Navigation.getLabel()
	minimap:setRoute(route, color)
	minimap:setTarget(target, color)
	Phone.setMapRoute(route, target, if target then label else nil, color)
end)
RunService.RenderStepped:Connect(function()
	local origin = Navigation.origin()
	if origin then
		local look = workspace.CurrentCamera.CFrame.LookVector
		minimap:update(origin, look)
		Phone.updateMap(origin, look)
	end
end)

Phone.onAccept(function(id)
	fareAction:FireServer("accept", id)
end)
Phone.onDecline(function(id)
	fareAction:FireServer("decline", id)
end)
Phone.onCancelFare(function()
	fareAction:FireServer("cancel")
end)

Phone.addMessage("Mom", "Did you eat anything today? Call me when your shift's over. Love you.")
Phone.show()
-- Free Play is all fares; in the story, the next chapter says what to do.
if player:GetAttribute("GameMode") == "free" then
	Screen.setObjective("idle", "Cruise the city -- Dispatch will text you")
	Phone.setDispatchIdle("No fares right now.", "Dispatch will text you when one comes in.")
else
	Phone.setDispatchIdle("No fares in the story.", "Ordinary fares are in Free Play, on the main menu.")
end
ready = true
if pending then
	handleUpdate(pending)
	pending = nil
end
