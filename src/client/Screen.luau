-- The words on screen during the shift, shared by ordinary fares (Hud) and
-- the story (Story.client):
--   * what you're meant to be doing right now, top centre
--   * what people say, as subtitles
--   * the meter, bottom left over the speedometer
--   * money in and out ("+$37.35" floating up)
--   * a countdown, under the objective
--   * the story's chapter cards, and its choices

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UiKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiKit"))

local Screen = {}

local player = Players.LocalPlayer

local GOLD = Color3.fromRGB(255, 196, 60)
local RED = Color3.fromRGB(235, 70, 70)

local gui = Instance.new("ScreenGui")
gui.Name = "Captions"
gui.ResetOnSpawn = false
gui.DisplayOrder = 11
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function outlined(parent: Instance, size: number, color: Color3, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = UiKit.FONT
	label.TextSize = size
	label.TextColor3 = color
	label.Text = ""
	for key, value in props do
		(label :: any)[key] = value
	end
	UiKit.outlineText(label, 2)
	label.Parent = parent
	return label
end
Screen.outlined = outlined

local objective = outlined(gui, 22, Color3.fromRGB(240, 236, 225), {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.new(0.5, 0, 0, 28),
	TextWrapped = true,
})

local timer = outlined(gui, 30, GOLD, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 40),
	Size = UDim2.fromOffset(200, 34),
	Font = Enum.Font.Code,
})

local meter = outlined(gui, 26, Color3.fromRGB(255, 90, 70), {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 24, 1, -92),
	Size = UDim2.fromOffset(260, 30),
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.Code,
})

local speakerTag = outlined(gui, 16, UiKit.STYLES.gold.fill, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -128),
	Size = UDim2.new(0.6, 0, 0, 20),
})
local subtitle = outlined(gui, 24, Color3.fromRGB(235, 235, 240), {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 1, -126),
	Size = UDim2.new(0.6, 0, 0, 60),
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
})

-- ===== Objective =====
-- Story and fare each set their own; the story's wins, then the fare's,
-- then a nudge that a story chapter's waiting, then whatever's set for when
-- nothing's going on.

local objectives: { [string]: string? } = {}
local ORDER = { "story", "fare", "storyReady", "idle" }

local function refreshObjective()
	for _, owner in ORDER do
		local value = objectives[owner]
		if value and value ~= "" then
			objective.Text = value
			return
		end
	end
	objective.Text = ""
end

function Screen.setObjective(owner: string, value: string?)
	objectives[owner] = value
	refreshObjective()
end

-- During a cutscene (see Cutscene): only the subtitles, money and cards.
function Screen.setCinematic(on: boolean)
	objective.Visible = not on
	timer.Visible = not on
	meter.Visible = not on
end

-- ===== Talking =====

local sayToken = 0

-- Types out a line under the speaker's name, holds it long enough to read,
-- then clears it. Yields until it's gone.
function Screen.say(speaker: string, line: string, color: Color3?)
	sayToken += 1
	local token = sayToken
	-- For testing only: a "DebugSlowTalk" attribute on the player (set by
	-- hand) holds every line that many times longer, so a cutscene's shots
	-- can be looked at properly. Nothing in the game sets it.
	local hold = tonumber(player:GetAttribute("DebugSlowTalk")) or 1
	speakerTag.Text = speaker
	speakerTag.TextColor3 = color or UiKit.STYLES.gold.fill
	subtitle.Text = ""
	for i = 1, #line do
		if token ~= sayToken then
			return
		end
		subtitle.Text = line:sub(1, i)
		task.wait(0.025)
	end
	task.wait((1.6 + #line * 0.02) * hold)
	if token == sayToken then
		subtitle.Text = ""
		speakerTag.Text = ""
	end
	task.wait(0.35)
end

function Screen.hush()
	sayToken += 1
	subtitle.Text = ""
	speakerTag.Text = ""
end

-- ===== Money, meter, timer =====

function Screen.setMeter(value: string)
	meter.Text = value
end

-- "+$37.35" (or "-$40.00" in red), floating up and fading.
function Screen.showMoney(amount: number)
	local label = outlined(gui, 44, if amount >= 0 then GOLD else RED, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(300, 56),
		Text = string.format("%s$%.2f", if amount >= 0 then "+" else "-", math.abs(amount)),
	})
	TweenService:Create(label, TweenInfo.new(2.5, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(0.5, 0.3), TextTransparency = 1 }):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(2.5), { Transparency = 1 }):Play()
	end
	task.delay(2.6, function()
		label:Destroy()
	end)
end

-- A countdown to `deadline` (server time) under the objective; nil hides it.
local timerToken = 0
function Screen.setTimer(deadline: number?, color: Color3?)
	timerToken += 1
	local token = timerToken
	timer.Text = ""
	if not deadline then
		return
	end
	timer.TextColor3 = color or GOLD
	task.spawn(function()
		while token == timerToken do
			local left = math.max(0, deadline - workspace:GetServerTimeNow())
			timer.Text = string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60))
			timer.TextColor3 = if left < 10 then RED else (color or GOLD)
			if left <= 0 then
				break
			end
			task.wait(0.2)
		end
	end)
end

-- ===== Flashes and cards =====

local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.new(1, 1, 1)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.ZIndex = 1
flash.Parent = gui

-- The whole screen briefly washed in `color`.
function Screen.flash(color: Color3, strength: number?, duration: number?)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 1 - (strength or 0.5)
	TweenService:Create(flash, TweenInfo.new(duration or 0.8, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
end

local card = Instance.new("Frame")
card.Name = "ChapterCard"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.36)
card.Size = UDim2.fromOffset(640, 130)
card.BackgroundTransparency = 1
card.Visible = false
card.ZIndex = 5
card.Parent = gui
local cardKicker = outlined(card, 18, RED, { Size = UDim2.new(1, 0, 0, 24), ZIndex = 5 })
local cardTitle = outlined(card, 54, Color3.fromRGB(245, 240, 230), {
	Position = UDim2.fromOffset(0, 26),
	Size = UDim2.new(1, 0, 0, 62),
	Font = Enum.Font.GothamBlack,
	ZIndex = 5,
	-- Shrinks to fit a long title (chapter 5's) rather than running off
	-- the edges of the card.
	TextScaled = true,
})
do
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = 54
	fit.Parent = cardTitle
end
local cardSubtitle = outlined(card, 18, Color3.fromRGB(200, 200, 205), {
	Position = UDim2.fromOffset(0, 92),
	Size = UDim2.new(1, 0, 0, 24),
	ZIndex = 5,
})

local function fadeCard(transparency: number, time: number)
	for _, label in { cardKicker, cardTitle, cardSubtitle } do
		TweenService:Create(label, TweenInfo.new(time), { TextTransparency = transparency }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(time), { Transparency = transparency }):Play()
		end
	end
end

-- "CHAPTER 2 / LAST STOP / ...", faded in over the action and out again.
-- Doesn't yield.
local cardToken = 0
function Screen.titleCard(kicker: string, title: string, subtitleText: string?, hold: number?)
	cardToken += 1
	local token = cardToken
	cardKicker.Text = kicker
	cardTitle.Text = title
	cardSubtitle.Text = subtitleText or ""
	fadeCard(1, 0)
	card.Visible = true
	fadeCard(0, 0.8)
	task.delay(0.8 + (hold or 3.5), function()
		if token ~= cardToken then
			return
		end
		fadeCard(1, 1.2)
		task.delay(1.2, function()
			if token == cardToken then
				card.Visible = false
			end
		end)
	end)
end

-- ===== Choices =====

local choiceFrame = Instance.new("Frame")
choiceFrame.Name = "Choice"
choiceFrame.AnchorPoint = Vector2.new(0.5, 1)
choiceFrame.Position = UDim2.new(0.5, 0, 1, -150)
choiceFrame.Size = UDim2.fromOffset(560, 0)
choiceFrame.AutomaticSize = Enum.AutomaticSize.Y
choiceFrame.BackgroundTransparency = 1
choiceFrame.Visible = false
choiceFrame.ZIndex = 6
choiceFrame.Parent = gui
local choiceLayout = Instance.new("UIListLayout")
choiceLayout.Padding = UDim.new(0, 8)
choiceLayout.SortOrder = Enum.SortOrder.LayoutOrder
choiceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
choiceLayout.Parent = choiceFrame

-- Puts up `prompt` and a button per option (also keys 1, 2, ...) and
-- yields until one's picked. Returns its number.
function Screen.choose(prompt: string, options: { string }): number
	for _, child in choiceFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local header = outlined(choiceFrame, 20, RED, {
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = 0,
		ZIndex = 6,
		Text = prompt,
	})
	header.Name = "Prompt"
	local picked: number? = nil
	for i, option in options do
		local b = Instance.new("TextButton")
		b.Name = "Option" .. i
		b.Size = UDim2.new(1, 0, 0, 46)
		b.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
		b.BackgroundTransparency = 0.1
		b.AutoButtonColor = true
		b.Font = UiKit.FONT
		b.TextSize = 19
		b.TextColor3 = Color3.fromRGB(240, 236, 225)
		b.TextWrapped = true
		b.Text = `{i}   {option}`
		b.LayoutOrder = i
		b.ZIndex = 6
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = b
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = RED
		stroke.Thickness = 1.5
		stroke.Parent = b
		b.Activated:Connect(function()
			picked = picked or i
		end)
		b.Parent = choiceFrame
	end
	local keys = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }
	local connection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		for i = 1, #options do
			if input.KeyCode == keys[i] then
				picked = picked or i
			end
		end
	end)
	choiceFrame.Visible = true
	while not picked do
		task.wait()
	end
	connection:Disconnect()
	choiceFrame.Visible = false
	return picked :: number
end

return Screen
