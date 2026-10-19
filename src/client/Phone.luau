-- The player's phone, tucked away in the bottom right of the screen: press P
-- (or click it) to pull it up. Five apps:
--   Messages -- texts from dispatch and everyone else
--   Dispatch -- the ordinary fare you're on, and new ones to take or turn
--               down
--   Story    -- the story's chapters, part by part: which are done, which
--               is on, which is next
--   Wallet   -- your cash and tonight's earnings
--   Map      -- the whole city, with your route
-- New texts flash up beside it while it's put away, and badge its icon.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local MapView = require(script.Parent.MapView)

local Phone = {}

local player = Players.LocalPlayer

local WIDTH, HEIGHT = 280, 540
local BEZEL = 10
local PEEK = 58 -- how much shows while it's put away
local SCREEN_W, SCREEN_H = WIDTH - BEZEL * 2, HEIGHT - BEZEL * 2
local FONT = Enum.Font.Gotham
local FONT_BOLD = Enum.Font.GothamBold
local TEXT = Color3.fromRGB(236, 236, 240)
local SUBTLE = Color3.fromRGB(150, 152, 165)
local CARD = Color3.fromRGB(30, 31, 40)
local GOLD = Color3.fromRGB(240, 186, 52)
local GREEN = Color3.fromRGB(52, 199, 89)
local RED = Color3.fromRGB(225, 70, 80)

local APPS = {
	{ id = "messages", name = "Messages", icon = "💬", color = GREEN },
	{ id = "dispatch", name = "Dispatch", icon = "🚕", color = GOLD },
	{ id = "story", name = "Story", icon = "📖", color = RED },
	{ id = "wallet", name = "Wallet", icon = "💵", color = Color3.fromRGB(38, 160, 140) },
	{ id = "map", name = "Map", icon = "🗺️", color = Color3.fromRGB(60, 120, 230) },
	{ id = "contacts", name = "Contacts", icon = "👤", color = Color3.fromRGB(110, 110, 130) },
}

-- ===== Little builders =====

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function round(parent: Instance, radius: number)
	new("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function text(parent: Instance, value: string, size: number, color: Color3?, bold: boolean?, props: { [string]: any }?): TextLabel
	local label = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = if bold then FONT_BOLD else FONT,
		TextSize = size,
		TextColor3 = color or TEXT,
		Text = value,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
	}, parent)
	for key, v in props or {} do
		label[key] = v
	end
	return label
end

local function button(parent: Instance, label: string, color: Color3, props: { [string]: any }): TextButton
	local b = new("TextButton", {
		BackgroundColor3 = color,
		AutoButtonColor = true,
		Font = FONT_BOLD,
		TextSize = 16,
		TextColor3 = Color3.new(1, 1, 1),
		Text = label,
	}, parent)
	for key, v in props do
		b[key] = v
	end
	round(b, 10)
	return b
end

local function badge(parent: Instance, position: UDim2): TextLabel
	local b = text(parent, "", 12, Color3.new(1, 1, 1), true, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(235, 60, 50),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Visible = false,
		ZIndex = 20,
	})
	round(b, 10)
	return b
end

local function money(amount: number): string
	return string.format("$%.2f", amount)
end

-- ===== The phone itself =====

local gui = new("ScreenGui", {
	Name = "Phone",
	ResetOnSpawn = false,
	DisplayOrder = 20,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = false,
}, player:WaitForChild("PlayerGui"))

local OPEN_POSITION = UDim2.new(1, -24, 1, -16)
local CLOSED_POSITION = UDim2.new(1, -24, 1, HEIGHT - PEEK)

local body = new("Frame", {
	Name = "Body",
	AnchorPoint = Vector2.new(1, 1),
	Position = CLOSED_POSITION,
	Size = UDim2.fromOffset(WIDTH, HEIGHT),
	BackgroundColor3 = Color3.fromRGB(12, 12, 14),
}, gui)
round(body, 34)
new("UIStroke", { Color = Color3.fromRGB(70, 70, 80), Thickness = 2 }, body)

local screen = new("Frame", {
	Name = "Screen",
	Position = UDim2.fromOffset(BEZEL, BEZEL),
	Size = UDim2.fromOffset(SCREEN_W, SCREEN_H),
	BackgroundColor3 = Color3.fromRGB(18, 18, 26),
	ClipsDescendants = true,
}, body)
round(screen, 26)
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(42, 30, 70), Color3.fromRGB(12, 16, 32)),
	Rotation = 90,
}, screen)

-- Status bar: the time, and signal.
local statusBar = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, ZIndex = 5 }, screen)
local clockLabel = text(statusBar, "1:30 AM", 14, TEXT, true, {
	Position = UDim2.fromOffset(20, 7),
	Size = UDim2.fromOffset(100, 18),
	ZIndex = 5,
})
text(statusBar, "MARROW CELL  ▂▄▆", 11, SUBTLE, true, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -18, 0, 9),
	Size = UDim2.fromOffset(130, 16),
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 5,
})

-- The bit that shows while it's put away: a strip under the status bar
-- (covering whatever app was left open) with a hint on it.
local peekHint = text(body, "P  ·  PHONE", 13, SUBTLE, true, {
	Position = UDim2.fromOffset(BEZEL, BEZEL + 26),
	Size = UDim2.new(1, -BEZEL * 2, 0, PEEK - BEZEL - 26),
	BackgroundTransparency = 0,
	BackgroundColor3 = Color3.fromRGB(14, 14, 20),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	ZIndex = 6,
})
local peekBadge = badge(body, UDim2.new(1, -16, 0, 14))

-- Pop-up for new texts while the phone's away.
local toast = new("Frame", {
	Name = "Toast",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -24, 1, -(PEEK + 24)),
	Size = UDim2.fromOffset(WIDTH, 64),
	BackgroundColor3 = Color3.fromRGB(28, 28, 36),
	BackgroundTransparency = 0.05,
	Visible = false,
}, gui)
round(toast, 14)
new("UIStroke", { Color = Color3.fromRGB(80, 80, 95), Thickness = 1 }, toast)
local toastFrom = text(toast, "", 13, GREEN, true, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 16) })
local toastText = text(toast, "", 13, TEXT, false, {
	Position = UDim2.fromOffset(14, 26),
	Size = UDim2.new(1, -28, 0, 32),
	TextTruncate = Enum.TextTruncate.AtEnd,
})

-- ===== Home screen =====

local home = new("Frame", { Name = "Home", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, screen)
local bigClock = text(home, "1:30", 54, TEXT, true, {
	Position = UDim2.fromOffset(0, 54),
	Size = UDim2.new(1, 0, 0, 60),
	TextXAlignment = Enum.TextXAlignment.Center,
})
text(home, "The Marrow · night shift", 14, SUBTLE, false, {
	Position = UDim2.fromOffset(0, 116),
	Size = UDim2.new(1, 0, 0, 18),
	TextXAlignment = Enum.TextXAlignment.Center,
})
local cashHome = text(home, "$0.00", 18, GOLD, true, {
	Position = UDim2.fromOffset(0, 138),
	Size = UDim2.new(1, 0, 0, 22),
	TextXAlignment = Enum.TextXAlignment.Center,
})

local appBadges: { [string]: TextLabel } = {}
local openApp: (string) -> ()

for i, app in APPS do
	local col = (i - 1) % 3
	local row = math.floor((i - 1) / 3)
	local x = 22 + col * 82
	local y = 200 + row * 104
	local tile = new("TextButton", {
		Name = app.id,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(66, 66),
		BackgroundColor3 = app.color,
		AutoButtonColor = true,
		Text = app.icon,
		TextSize = 32,
		Font = FONT,
	}, home)
	round(tile, 18)
	text(home, app.name, 13, TEXT, false, {
		Position = UDim2.fromOffset(x - 12, y + 70),
		Size = UDim2.fromOffset(90, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	appBadges[app.id] = badge(tile, UDim2.new(1, -4, 0, 4))
	tile.Activated:Connect(function()
		openApp(app.id)
	end)
end

-- ===== App screens =====

local pages: { [string]: Frame } = {}
local function page(id: string, title: string): Frame
	local p = new("Frame", {
		Name = id,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(16, 16, 22),
		Visible = false,
		ZIndex = 2,
	}, screen)
	local back = new("TextButton", {
		Position = UDim2.fromOffset(10, 32),
		Size = UDim2.fromOffset(70, 30),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(90, 170, 255),
		Text = "‹ Home",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	}, p)
	back.Activated:Connect(function()
		openApp("home")
	end)
	text(p, title, 17, TEXT, true, {
		Position = UDim2.fromOffset(0, 37),
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
	})
	pages[id] = p
	return p
end

local function scroller(parent: Instance): ScrollingFrame
	local s = new("ScrollingFrame", {
		Position = UDim2.fromOffset(10, 70),
		Size = UDim2.new(1, -20, 1, -80),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 3,
	}, parent)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, s)
	return s
end

local function card(parent: Instance, order: number): Frame
	local c = new("Frame", {
		Size = UDim2.new(1, -4, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = CARD,
		LayoutOrder = order,
		ZIndex = 3,
	}, parent)
	round(c, 12)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
	}, c)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, c)
	return c
end

local function line(parent: Instance, value: string, size: number, color: Color3?, bold: boolean?, order: number): TextLabel
	return text(parent, value, size, color, bold, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		ZIndex = 3,
	})
end

-- Messages.
local messagesPage = page("messages", "Messages")
local messageList = scroller(messagesPage)
local messageCount = 0
local unreadMessages = 0

-- Dispatch.
local dispatchPage = page("dispatch", "Dispatch")
local dispatchList = scroller(dispatchPage)
local acceptHandler: ((string) -> ())? = nil
local declineHandler: ((string) -> ())? = nil
local currentJob = nil
local currentOffer = nil
local cancelFareHandler: (() -> ())? = nil
local dispatchIdle = { "No fares right now.", "Dispatch will text you when one comes in." }

-- Story.
local storyPage = page("story", "Story")
local storyList = scroller(storyPage)
local storyStartHandler: ((number) -> ())? = nil
local storyQuitHandler: (() -> ())? = nil
local storyReady = false

-- Contacts.
local contactsPage = page("contacts", "Contacts")
local contactsList = scroller(contactsPage)

-- Wallet.
local walletPage = page("wallet", "Wallet")
text(walletPage, "Cash", 14, SUBTLE, false, {
	Position = UDim2.fromOffset(0, 80),
	Size = UDim2.new(1, 0, 0, 18),
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 3,
})
local cashBig = text(walletPage, "$0.00", 40, GOLD, true, {
	Position = UDim2.fromOffset(0, 100),
	Size = UDim2.new(1, 0, 0, 46),
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 3,
})
local saveLabel = text(walletPage, "", 12, SUBTLE, false, {
	Position = UDim2.fromOffset(10, 148),
	Size = UDim2.new(1, -20, 0, 16),
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 3,
})
local earningsList = scroller(walletPage)
earningsList.Position = UDim2.fromOffset(10, 172)
earningsList.Size = UDim2.new(1, -20, 1, -182)
local earningsCount = 0
line(earningsList, "Tonight", 14, SUBTLE, true, 0)

-- Map.
local mapPage = page("map", "Map")
local mapHolder = new("Frame", {
	Position = UDim2.fromOffset(5, 74),
	Size = UDim2.fromOffset(SCREEN_W - 10, SCREEN_W - 10),
	BackgroundTransparency = 1,
	ZIndex = 3,
}, mapPage)
local phoneMap = MapView.new(mapHolder, { size = SCREEN_W - 10, scale = 0.2 })
round(phoneMap.container, 12)
local mapCaption = text(mapPage, "", 13, SUBTLE, false, {
	Position = UDim2.fromOffset(12, 74 + SCREEN_W),
	Size = UDim2.new(1, -24, 0, 60),
	ZIndex = 3,
})

-- ===== Opening and closing =====

local isOpen = false
local showing = "home"
local peekButton: TextButton

function openApp(id: string)
	showing = id
	home.Visible = id == "home"
	for pageId, p in pages do
		p.Visible = pageId == id
	end
	if id == "messages" then
		unreadMessages = 0
		appBadges.messages.Visible = false
	end
	Phone.refreshBadges()
end

function Phone.refreshBadges()
	appBadges.messages.Text = tostring(unreadMessages)
	appBadges.messages.Visible = unreadMessages > 0
	appBadges.dispatch.Text = "1"
	appBadges.dispatch.Visible = currentOffer ~= nil
	appBadges.story.Text = "!"
	appBadges.story.Visible = storyReady
	local total = unreadMessages + (if currentOffer then 1 else 0) + (if storyReady then 1 else 0)
	peekBadge.Text = tostring(total)
	peekBadge.Visible = total > 0 and not isOpen
end

function Phone.setOpen(open: boolean)
	isOpen = open
	TweenService:Create(body, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = if open then OPEN_POSITION else CLOSED_POSITION,
	}):Play()
	peekHint.Visible = not open
	peekButton.Visible = not open
	if open then
		toast.Visible = false
		if showing == "messages" then
			unreadMessages = 0
		end
	end
	Phone.refreshBadges()
end

function Phone.toggle()
	Phone.setOpen(not isOpen)
end

function Phone.isOpen(): boolean
	return isOpen
end

-- Clicking the phone while it's put away pulls it up. (Hidden while it's
-- open, or it would sit over the top of the screen's own buttons.)
peekButton = new("TextButton", {
	Size = UDim2.new(1, 0, 0, PEEK),
	BackgroundTransparency = 1,
	Text = "",
	ZIndex = 30,
}, body)
peekButton.Activated:Connect(function()
	if not isOpen then
		Phone.setOpen(true)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not gui.Enabled or UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == Enum.KeyCode.P then
		Phone.toggle()
	end
end)

-- ===== What goes on it =====

-- The time on the phone: 1:30 AM when the shift starts, then running at the
-- real clock's pace.
local shiftStart = os.clock()
local startMinutes = 90
local function showTime()
	local minutes = startMinutes + math.floor((os.clock() - shiftStart) / 60)
	local hour = math.floor(minutes / 60) % 24
	local minute = minutes % 60
	local shown = hour % 12
	if shown == 0 then
		shown = 12
	end
	local suffix = if hour < 12 then "AM" else "PM"
	clockLabel.Text = string.format("%d:%02d %s", shown, minute, suffix)
	bigClock.Text = string.format("%d:%02d", shown, minute)
end

-- The story moving the clock on (chapter 9 is a Friday evening, chapter 10
-- a Saturday morning): from `hour`:`minute` (24-hour), running on from
-- there.
function Phone.setClock(hour: number, minute: number)
	startMinutes = hour * 60 + minute
	shiftStart = os.clock()
	showTime()
end

-- What it says now, e.g. "8:41 PM" (for the lock screen in a cutscene).
function Phone.timeText(): string
	return clockLabel.Text
end

task.spawn(function()
	while true do
		showTime()
		task.wait(5)
	end
end)

function Phone.show()
	gui.Enabled = true
end

function Phone.addMessage(from: string, message: string)
	messageCount += 1
	local c = card(messageList, -messageCount)
	line(c, from, 14, GREEN, true, 1)
	line(c, message, 14, TEXT, false, 2)
	line(c, clockLabel.Text, 11, SUBTLE, false, 3)
	if not (isOpen and showing == "messages") then
		unreadMessages += 1
	end
	if not isOpen then
		toastFrom.Text = "💬  " .. from
		toastText.Text = message
		toast.Visible = true
		local shownFor = messageCount
		task.delay(6, function()
			if messageCount == shownFor then
				toast.Visible = false
			end
		end)
	end
	Phone.refreshBadges()
end

local function redrawDispatch()
	for _, child in dispatchList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	if currentJob then
		local c = card(dispatchList, 1)
		line(c, "CURRENT FARE", 12, GOLD, true, 1)
		line(c, currentJob.passenger, 18, TEXT, true, 2)
		line(c, "From  " .. currentJob.pickupName, 13, TEXT, false, 3)
		line(c, "To  " .. currentJob.dropoffName, 13, TEXT, false, 4)
		line(c, "Fare  " .. money(currentJob.price) .. (if currentJob.tip > 0 then "  (+ tip)" else ""), 13, TEXT, false, 5)
		local status = ({
			pickup = "Waiting for you. Pull up beside them and stop.",
			boarding = "Getting in...",
			riding = "On board. Follow the arrows.",
			arrived = "You're here. Let them out.",
		})[currentJob.stage] or ""
		line(c, status, 13, SUBTLE, false, 6)
		if currentJob.stage == "pickup" or currentJob.stage == "riding" then
			local giveUp = button(c, "Give up this fare", Color3.fromRGB(70, 70, 82), {
				Size = UDim2.new(1, 0, 0, 32),
				TextSize = 14,
				LayoutOrder = 7,
				ZIndex = 4,
			})
			giveUp.Activated:Connect(function()
				if cancelFareHandler then
					cancelFareHandler()
				end
			end)
		end
	end
	if currentOffer then
		local offer = currentOffer
		local c = card(dispatchList, 2)
		line(c, "NEW FARE", 12, GREEN, true, 1)
		line(c, offer.passenger, 18, TEXT, true, 2)
		line(c, "From  " .. offer.pickupName, 13, TEXT, false, 3)
		line(c, "To  " .. offer.dropoffName, 13, TEXT, false, 4)
		line(c, "Pays about  " .. money(offer.price), 13, TEXT, false, 5)
		local row = new("Frame", {
			Size = UDim2.new(1, 0, 0, 38),
			BackgroundTransparency = 1,
			LayoutOrder = 6,
			ZIndex = 3,
		}, c)
		local accept = button(row, "Accept", Color3.fromRGB(40, 150, 70), {
			Size = UDim2.new(0.5, -4, 1, 0),
			ZIndex = 4,
		})
		local decline = button(row, "Decline", Color3.fromRGB(70, 70, 82), {
			Position = UDim2.new(0.5, 4, 0, 0),
			Size = UDim2.new(0.5, -4, 1, 0),
			ZIndex = 4,
		})
		accept.Activated:Connect(function()
			if acceptHandler then
				acceptHandler(offer.id)
			end
		end)
		decline.Activated:Connect(function()
			if declineHandler then
				declineHandler(offer.id)
			end
		end)
	end
	if not currentJob and not currentOffer then
		local c = card(dispatchList, 3)
		line(c, dispatchIdle[1], 15, TEXT, true, 1)
		line(c, dispatchIdle[2], 13, SUBTLE, false, 2)
	end
	Phone.refreshBadges()
end

function Phone.setJob(fare)
	currentJob = fare
	redrawDispatch()
end

function Phone.setOffer(offer)
	currentOffer = offer
	redrawDispatch()
end

function Phone.onAccept(handler: (string) -> ())
	acceptHandler = handler
end

function Phone.onDecline(handler: (string) -> ())
	declineHandler = handler
end

function Phone.onCancelFare(handler: () -> ())
	cancelFareHandler = handler
end

-- The Story app. `entries` is every chapter in order: {index, part (its
-- title), title, blurb, status ("done"/"ready"/"hidden")}; `active` the one
-- being played, if any; `finished` once there's nothing left to play.
export type StoryEntry = { index: number, part: string, title: string, blurb: string, status: string }

local storyNote: string? = nil

function Phone.setStory(entries: { StoryEntry }, active: number?, finished: boolean)
	for _, child in storyList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	storyReady = false
	if storyNote then
		-- Free Play: no story here.
		local c = card(storyList, 0)
		line(c, "FREE PLAY", 11, RED, true, 1)
		line(c, storyNote, 13, TEXT, false, 2)
		Phone.refreshBadges()
		return
	end
	local order = 0
	local lastPart = nil
	for _, entry in entries do
		if entry.part ~= lastPart then
			lastPart = entry.part
			order += 1
			local header = card(storyList, order)
			header.BackgroundTransparency = 1
			line(header, entry.part:upper(), 13, RED, true, 1)
		end
		order += 1
		local c = card(storyList, order)
		line(c, `CHAPTER {entry.index}`, 11, if entry.status == "hidden" then SUBTLE else RED, true, 1)
		if entry.status == "hidden" then
			line(c, "???", 16, SUBTLE, true, 2)
			continue
		end
		line(c, entry.title, 17, TEXT, true, 2)
		line(c, entry.blurb, 13, SUBTLE, false, 3)
		if entry.status == "done" then
			line(c, "✓  Done", 13, GREEN, true, 4)
		elseif active == entry.index then
			line(c, "In progress. Follow the red arrows.", 13, TEXT, false, 4)
			local quit = button(c, "Give up (start again later)", Color3.fromRGB(70, 70, 82), {
				Size = UDim2.new(1, 0, 0, 32),
				TextSize = 14,
				LayoutOrder = 5,
				ZIndex = 4,
			})
			quit.Activated:Connect(function()
				if storyQuitHandler then
					storyQuitHandler()
				end
			end)
		elseif entry.status == "ready" then
			storyReady = active == nil
			line(c, "Up next -- starts on its own, or:", 12, SUBTLE, false, 4)
			local start = button(c, "Start now", RED, {
				Size = UDim2.new(1, 0, 0, 36),
				LayoutOrder = 5,
				ZIndex = 4,
			})
			start.Activated:Connect(function()
				if storyStartHandler then
					storyStartHandler(entry.index)
				end
			end)
		end
	end
	if finished then
		local c = card(storyList, order + 1)
		line(c, "MORE TO COME", 11, RED, true, 1)
		line(c, "That's the story so far. The next part's on its way -- in the meantime, Free Play's on the main menu.", 13, TEXT, false, 2)
	end
	Phone.refreshBadges()
end

-- In Free Play, the Story app just says so.
function Phone.setStoryNote(note: string?)
	storyNote = note
end

-- What Dispatch says with no fare on: a heading and a line under it.
function Phone.setDispatchIdle(heading: string, detail: string)
	dispatchIdle = { heading, detail }
	redrawDispatch()
end

function Phone.onStoryStart(handler: (number) -> ())
	storyStartHandler = handler
end

function Phone.onStoryQuit(handler: () -> ())
	storyQuitHandler = handler
end

function Phone.openApp(id: string)
	openApp(id)
end

-- The Contacts app: {name, number, note}; `highlight` (a name) gets a
-- "NEW" tag.
function Phone.setContacts(contacts: { { name: string, number: string, note: string? } }, highlight: string?)
	for _, child in contactsList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, contact in contacts do
		local c = card(contactsList, i)
		if contact.name == highlight then
			line(c, "NEW", 11, RED, true, 0)
			c.BackgroundColor3 = Color3.fromRGB(48, 30, 36)
		end
		line(c, contact.name, 17, TEXT, true, 1)
		line(c, contact.number, 14, SUBTLE, false, 2)
		if contact.note then
			line(c, contact.note, 12, SUBTLE, false, 3)
		end
	end
end

function Phone.setSaveState(state: string?)
	saveLabel.Text = if state == "ok"
		then "Progress saves automatically"
		elseif state == "off" then "Saving is off in this session"
		elseif state == "test" then "Bug test -- nothing is saved"
		elseif state == "guest" then "This game isn't saved"
		else ""
end

function Phone.setCash(amount: number)
	cashBig.Text = money(amount)
	cashHome.Text = money(amount)
end

function Phone.addEarning(description: string, amount: number)
	earningsCount += 1
	local c = card(earningsList, earningsCount)
	if amount >= 0 then
		line(c, "+" .. money(amount), 16, GOLD, true, 1)
	else
		line(c, "-" .. money(-amount), 16, RED, true, 1)
	end
	line(c, description, 13, TEXT, false, 2)
end

-- Keeps the Map app centred on the player and showing the route.
function Phone.updateMap(focus: Vector3, look: Vector3)
	if isOpen and showing == "map" then
		phoneMap:update(focus, look)
	end
end

function Phone.setMapRoute(points: { Vector3 }?, target: Vector3?, caption: string?, color: Color3?)
	phoneMap:setRoute(points, color)
	phoneMap:setTarget(target, color)
	mapCaption.Text = caption or "No destination set."
end

redrawDispatch()

return Phone
