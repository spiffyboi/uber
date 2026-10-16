-- The main menu, between the loading screen and the game: the title over a
-- slow drift across the night city, and
--   NEW STORY      -- the opening, then the story from the start (for a
--                     tester with a saved story, this replaces it -- asked
--                     first)
--   CONTINUE STORY -- carry on from the saved story, straight to the cab
--   FREE PLAY      -- no story, just fares
--   BUG TEST       -- start at any chapter, with nothing saved
-- Continue Story and Bug Test only show for the testers (see the server's
-- Testers list); the server checks again either way (see GameMenu).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))
local StoryConfig = require(Shared:WaitForChild("StoryConfig"))
local UiKit = require(Shared:WaitForChild("UiKit"))

local menuChoice = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MenuChoice") :: RemoteEvent

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local GOLD = Color3.fromRGB(255, 196, 60)
local RED = Color3.fromRGB(225, 70, 80)
local TEXT = Color3.fromRGB(240, 236, 225)
local SUBTLE = Color3.fromRGB(160, 160, 170)

local function waitFor(attribute: string)
	while not player:GetAttribute(attribute) do
		player:GetAttributeChangedSignal(attribute):Wait()
	end
end

waitFor("LoadingScreenDone")
waitFor("MenuReady")

-- ===== Building it =====

local gui = Instance.new("ScreenGui")
gui.Name = "MainMenu"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 120
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- Darker down the left, where the words are.
local shade = Instance.new("Frame")
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BorderSizePixel = 0
shade.Parent = gui
local gradient = Instance.new("UIGradient")
gradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.1),
	NumberSequenceKeypoint.new(0.45, 0.45),
	NumberSequenceKeypoint.new(1, 0.85),
})
gradient.Parent = shade

local function text(parent: Instance, value: string, size: number, color: Color3, props: { [string]: any }?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = UiKit.FONT
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = value
	for key, v in props or {} do
		(label :: any)[key] = v
	end
	label.Parent = parent
	return label
end

local column = Instance.new("Frame")
column.Name = "Column"
column.AnchorPoint = Vector2.new(0, 0.5)
column.Position = UDim2.new(0, 70, 0.5, 0)
column.Size = UDim2.fromOffset(420, 520)
column.BackgroundTransparency = 1
column.Parent = gui

local title = text(column, CityConfig.GAME_TITLE:upper(), 110, GOLD, {
	Size = UDim2.new(1, 0, 0, 110),
	Font = Enum.Font.GothamBlack,
})
UiKit.outlineText(title, 3)
text(column, `{CityConfig.DISTRICT_NAME}  ·  Night Shift`, 24, SUBTLE, {
	Position = UDim2.fromOffset(4, 112),
	Size = UDim2.new(1, 0, 0, 30),
})

-- The page of buttons on show; swapped for the confirm and bug-test pages.
local pages: { [string]: Frame } = {}
local function page(name: string): Frame
	local p = Instance.new("Frame")
	p.Name = name
	p.Position = UDim2.fromOffset(0, 170)
	p.Size = UDim2.new(1, 0, 1, -170)
	p.BackgroundTransparency = 1
	p.Visible = false
	p.Parent = column
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = p
	pages[name] = p
	return p
end

local function show(name: string)
	for pageName, p in pages do
		p.Visible = pageName == name
	end
end

local busy = false

local function button(parent: Instance, label: string, order: number, color: Color3?, height: number?): TextButton
	local b = Instance.new("TextButton")
	b.Name = label
	b.LayoutOrder = order
	b.Size = UDim2.new(1, 0, 0, height or 54)
	b.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	b.BackgroundTransparency = 0.15
	b.AutoButtonColor = true
	b.Font = UiKit.FONT
	b.TextSize = 26
	b.TextColor3 = TEXT
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.Text = "   " .. label
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color or GOLD
	stroke.Thickness = 2
	stroke.Parent = b
	b.Parent = parent
	return b
end

local function note(parent: Instance, value: string, order: number, color: Color3?): TextLabel
	return text(parent, value, 17, color or SUBTLE, {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		Font = Enum.Font.Gotham,
	})
end

local tester = player:GetAttribute("IsTester") == true
local hasSave = player:GetAttribute("HasSave") == true
local summary = player:GetAttribute("SaveSummary") or ""

local status = note(column, "", 99, RED)
status.Position = UDim2.new(0, 0, 1, 10)
status.AnchorPoint = Vector2.new(0, 0)

-- ===== Choosing =====

local function choose(mode: string, options: { [string]: any }?)
	if busy then
		return
	end
	busy = true
	status.TextColor3 = SUBTLE
	status.Text = "Starting..."
	menuChoice:FireServer(mode, options)
end

-- Refused (shouldn't happen from these buttons, but the server has the
-- final say): back to the menu.
player:GetAttributeChangedSignal("MenuRefused"):Connect(function()
	busy = false
	status.TextColor3 = RED
	status.Text = "That isn't available. Try another option."
end)

-- Main page.
local main = page("Main")
local newButton = button(main, "NEW STORY", 1)
newButton.Activated:Connect(function()
	if tester and hasSave then
		show("Confirm")
	else
		choose("new")
	end
end)
if tester then
	local loadButton = button(main, "CONTINUE STORY", 2)
	if hasSave then
		loadButton.Activated:Connect(function()
			choose("load")
		end)
		note(main, summary, 3)
	else
		loadButton.TextColor3 = SUBTLE
		loadButton.AutoButtonColor = false
		note(main, "No saved story yet.", 3)
	end
end
button(main, "FREE PLAY", 4, Color3.fromRGB(90, 200, 120)).Activated:Connect(function()
	choose("free")
end)
note(main, "Just the job: drive the city and take fares.", 5)
if tester then
	local testButton = button(main, "BUG TEST", 6, RED)
	testButton.Activated:Connect(function()
		show("Test")
	end)
end

-- Starting new over a saved game.
local confirm = page("Confirm")
note(confirm, "Start the story again? Your saved story will be replaced:", 1, TEXT)
note(confirm, summary, 2, GOLD)
button(confirm, "START NEW STORY", 3, RED).Activated:Connect(function()
	choose("new")
end)
button(confirm, "BACK", 4, SUBTLE).Activated:Connect(function()
	show("Main")
end)

-- Bug test: pick a chapter.
local test = page("Test")
-- Packed tighter than the main page, so all six chapters and Back fit on a
-- small screen.
local layout = test:FindFirstChildOfClass("UIListLayout") :: UIListLayout
layout.Padding = UDim.new(0, 4)
test.Position = UDim2.fromOffset(0, 150)
test.Size = UDim2.new(1, 0, 1, -150)
note(test, "BUG TEST -- start at a chapter (earlier ones count as done, $500 in hand, nothing saved).", 1, TEXT)
local toldVance = false
local toggle = button(test, "", 2, SUBTLE, 34)
toggle.TextSize = 18
local function refreshToggle()
	toggle.Text = `   Told Vance about the house (chapters 3-6): {if toldVance then "YES" else "NO"}`
end
refreshToggle()
toggle.Activated:Connect(function()
	toldVance = not toldVance
	refreshToggle()
end)
-- The chapters, two to a row.
local grid = Instance.new("Frame")
grid.Name = "Chapters"
grid.LayoutOrder = 3
grid.Size = UDim2.new(1, 0, 0, 0)
grid.AutomaticSize = Enum.AutomaticSize.Y
grid.BackgroundTransparency = 1
grid.Parent = test
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0.5, -3, 0, 34)
gridLayout.CellPadding = UDim2.fromOffset(6, 4)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid
for index, chapter in StoryConfig.CHAPTERS do
	local b = button(grid, `{index}. {chapter.title}`, index, GOLD, 34)
	b.TextSize = 19
	-- A long title shrinks to fit its half of the row.
	b.TextScaled = true
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = 19
	fit.Parent = b
	b.Activated:Connect(function()
		choose("test", { chapter = index, toldVance = toldVance })
	end)
end
button(test, "BACK", 20, SUBTLE, 34).Activated:Connect(function()
	show("Main")
end)

show("Main")

-- ===== Behind it: a slow drift up and down Marrow St at night =====
-- Kept over the road (the street walls start 37 studs either side of the
-- centreline -- further out, the camera ends up inside a building).

camera.CameraType = Enum.CameraType.Scriptable
local started = os.clock()
local drift = RunService.RenderStepped:Connect(function()
	local t = os.clock() - started
	local z = -190 + 170 * math.cos(t * 0.015)
	local eye = Vector3.new(4 + math.sin(t * 0.07) * 6, 34, z)
	camera.CFrame = CFrame.lookAt(eye, Vector3.new(-8, 14, z - 140))
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
end)

-- Fade in from the loading screen's black.
local black = Instance.new("Frame")
black.Size = UDim2.fromScale(1, 1)
black.BackgroundColor3 = Color3.new(0, 0, 0)
black.BorderSizePixel = 0
black.ZIndex = 50
black.Parent = gui
TweenService:Create(black, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()

-- ===== Leaving =====
-- Once the server's set the game up: to black, and hand over to the intro
-- (see IntroCutscene), which starts on black too.

waitFor("GameMode")
TweenService:Create(black, TweenInfo.new(0.6), { BackgroundTransparency = 0 }):Play()
task.wait(0.7)
drift:Disconnect()
-- The intro waits for this before touching the camera.
player:SetAttribute("MenuClosed", true)
local playerGui = player:WaitForChild("PlayerGui")
local waited = 0
while not playerGui:FindFirstChild("IntroCutscene") and waited < 3 do
	waited += task.wait()
end
task.wait(0.1)
gui:Destroy()
