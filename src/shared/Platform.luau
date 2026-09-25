-- Client-side helpers for phones, tablets, consoles and desktop: which kind of
-- input the player is using right now, a UI scale that suits the screen, and
-- hint text that names the right button for that input.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Platform = {}

export type Input = "Keyboard" | "Touch" | "Gamepad"

local function inputFromType(inputType: Enum.UserInputType): Input?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif inputType.Name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	elseif
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseWheel
	then
		return "Keyboard"
	end
	return nil
end

local current: Input
if GuiService:IsTenFootInterface() then
	current = "Gamepad"
elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
	current = "Touch"
else
	current = "Keyboard"
end

local changedEvent = Instance.new("BindableEvent")
-- Fires with the new Input when the player switches between keyboard/mouse,
-- touch and gamepad.
Platform.changed = changedEvent.Event

UserInputService.LastInputTypeChanged:Connect(function(inputType)
	local input = inputFromType(inputType)
	if input and input ~= current then
		current = input
		changedEvent:Fire(input)
	end
end)

function Platform.input(): Input
	return current
end

-- On a console (or a TV) everything is drawn bigger, since it's read from a
-- distance; on small screens it shrinks to fit. Desktop is never enlarged.
function Platform.uiScale(): number
	local camera = workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	if GuiService:IsTenFootInterface() then
		return math.clamp(size.Y / 800, 1, 1.4)
	end
	return math.clamp(math.min(size.X / 900, size.Y / 560), 0.5, 1)
end

-- Returns a full-screen frame to build a ScreenGui's contents inside instead of
-- the ScreenGui itself. Everything in it is laid out in the same pixel sizes as
-- before, but scaled to suit the screen (see uiScale).
function Platform.scaledRoot(gui: ScreenGui): Frame
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0

	local scale = Instance.new("UIScale")
	scale.Parent = root

	local function update()
		local s = Platform.uiScale()
		scale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	update()
	root.Parent = gui

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return root
end

-- Swaps the placeholders in tutorial and hint text for words that suit the
-- current input: {USE} is the interact prompt ("press E" / "tap the button" /
-- "press X") and {CLICK} is how you pick something ("click" / "tap" / "select"), and {PLANT} is
-- how you plant a seed.
function Platform.format(text: string): string
	local use = if current == "Touch" then "tap the button" elseif current == "Gamepad" then "press X" else "press E"
	local pick = if current == "Touch" then "tap" elseif current == "Gamepad" then "select" else "click"
	local plant = if current == "Touch" then "tap the soil" elseif current == "Gamepad" then "aim at the soil and press R2" else "click the soil"
	local result = text:gsub("{USE}", use):gsub("{CLICK}", pick):gsub("{PLANT}", plant)
	return result
end

-- A phone or tablet with no keyboard.
function Platform.isTouchDevice(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Menus (Shop/Inventory tabs, the seed shop, the hotbar) are comfortable at
-- full size on a mouse or gamepad, but eat too much of a phone's small screen
-- next to a big thumb. This is an *extra* shrink, layered on top of uiScale,
-- for exactly those panels -- not the whole HUD. `touchScale` replaces the
-- usual phone shrink, e.g. 1 (none) for buttons that must stay easy to tap.
function Platform.compactScale(touchScale: number?): number
	if Platform.isTouchDevice() then
		return touchScale or 0.8
	end
	return 1
end

-- Parents a UIScale to `gui` set to compactScale(touchScale), kept in sync as the
-- player switches input types (e.g. plugging in a keyboard on a tablet).
function Platform.applyCompactScale(gui: GuiObject, touchScale: number?)
	local scale = Instance.new("UIScale")
	scale.Name = "CompactScale"
	scale.Parent = gui
	local function update()
		-- (ScreenPanels' pop-in multiplies into this same scale while it plays.)
		local base = Platform.compactScale(touchScale)
		local pop = scale:GetAttribute("Pop")
		scale:SetAttribute("Base", base)
		scale.Scale = base * (if typeof(pop) == "number" then pop else 1)
	end
	update()
	Platform.changed:Connect(update)
end

-- With a gamepad, moves the selection cursor onto `object` so the player can
-- use it straight away (or clears it when `object` is nil).
function Platform.focus(object: GuiObject?)
	if current == "Gamepad" then
		GuiService.SelectedObject = object
	elseif object == nil then
		GuiService.SelectedObject = nil
	end
end

return Platform
