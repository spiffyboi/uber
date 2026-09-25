-- The chunky cartoon toolkit (bright fills, thick dark outlines, white outlined
-- text, emoji icons) shared by the UIs built after the menu. MenuUI and
-- TitleScreen carry their own copies of these helpers, and this matches them.

local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local UiKit = {}

-- Carried over from Brew a Potion!'s toolkit for the button/panel/text
-- *mechanics* (decorate, polish, fitText, etc.), but restyled below: Cold
-- Fare is a noir driving drama, not a bright cartoon farm, so the font and
-- palette are its own -- a condensed sans for a dispatch-app/HUD feel, and a
-- dark, neon-on-asphalt palette instead of candy colours.
UiKit.FONT = Enum.Font.Oswald
UiKit.TEXT_OUTLINE = Color3.fromRGB(10, 10, 12)
-- Every text outline in the game (UI and world signs) is drawn at its requested
-- thickness times this, so the whole game's outline weight is tuned here.
UiKit.TEXT_OUTLINE_SCALE = 0.75

export type Style = { fill: Color3, outline: Color3 }

UiKit.STYLES = {
	-- GigLine's own accent (the app's UI, waypoint markers, "Accept" prompts).
	cyan = { fill = Color3.fromRGB(45, 195, 210), outline = Color3.fromRGB(10, 55, 60) },
	-- Fares, tips, cash-in-hand.
	gold = { fill = Color3.fromRGB(200, 175, 90), outline = Color3.fromRGB(75, 62, 25) },
	-- Warnings, danger, anything gang-related surfacing in the UI.
	red = { fill = Color3.fromRGB(190, 55, 55), outline = Color3.fromRGB(70, 15, 15) },
	orange = { fill = Color3.fromRGB(205, 120, 45), outline = Color3.fromRGB(80, 45, 15) },
	green = { fill = Color3.fromRGB(80, 150, 70), outline = Color3.fromRGB(28, 55, 24) },
	purple = { fill = Color3.fromRGB(120, 85, 155), outline = Color3.fromRGB(45, 30, 60) },
	gray = { fill = Color3.fromRGB(60, 62, 70), outline = Color3.fromRGB(20, 21, 26) },
	panel = { fill = Color3.fromRGB(18, 19, 24), outline = Color3.fromRGB(5, 5, 8) },
	card = { fill = Color3.fromRGB(28, 30, 38), outline = Color3.fromRGB(8, 9, 13) },
} :: { [string]: Style }

function UiKit.outlineText(label: Instance, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = UiKit.TEXT_OUTLINE
	stroke.Thickness = thickness * UiKit.TEXT_OUTLINE_SCALE
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
end

-- The uploaded currency icon, drawn wherever 💰 appears in UI text (see
-- UiKit.watchCurrency). A plain asset id, same convention as UiKit.isImageIcon.
UiKit.CURRENCY_ICON = "136896700934944"

-- ===== The currency icon inside text =====
-- Roblox can't draw an image inside a TextLabel's text, so a watched label that
-- contains 💰 hides its own text and is drawn instead as a row (or wrapped rows)
-- of small text pieces with the currency image between them, sized the way the
-- label itself would size its text. The label keeps its real Text, so code can
-- keep setting label.Text as normal: the drawing follows it.

local COIN = "💰"
local MEASURE_BOX = Vector2.new(100000, 100000)

type CoinToken = { kind: string, plain: string, rich: string }
type CoinEntry = { key: string?, pending: boolean, hidden: boolean, savedText: number, savedStroke: number }

local coinEntries: { [TextLabel]: CoinEntry } = setmetatable({}, { __mode = "k" }) :: any

-- Splits text into pieces of words (breaking only after spaces, when wrapping),
-- currency icons and line breaks. For rich text, each piece carries the tags
-- open around it, so a <font color> still colours just its own words.
local function coinTokens(text: string, rich: boolean, wrap: boolean): { CoinToken }
	local tokens: { CoinToken } = {}
	local open: { string } = {}
	local current = ""
	local function flush()
		if current == "" then
			return
		end
		local wrapped = current
		if rich and #open > 0 then
			local closing = ""
			for index = #open, 1, -1 do
				closing ..= `</{string.match(open[index], "^<(%w+)") or "font"}>`
			end
			wrapped = table.concat(open) .. current .. closing
		end
		table.insert(tokens, { kind = "text", plain = current, rich = wrapped })
		current = ""
	end

	local index = 1
	while index <= #text do
		local char = string.sub(text, index, index)
		local tagEnd = if rich and char == "<" then string.find(text, ">", index, true) else nil
		if tagEnd then
			flush()
			local tag = string.sub(text, index, tagEnd)
			if string.sub(tag, 2, 2) == "/" then
				table.remove(open)
			elseif string.sub(tag, -2) ~= "/>" then
				table.insert(open, tag)
			end
			index = tagEnd + 1
		elseif string.sub(text, index, index + #COIN - 1) == COIN then
			flush()
			table.insert(tokens, { kind = "icon", plain = "", rich = "" })
			index += #COIN
		elseif char == "\n" then
			flush()
			table.insert(tokens, { kind = "break", plain = "", rich = "" })
			index += 1
		else
			current ..= char
			index += 1
			if wrap and char == " " and string.sub(text, index, index) ~= " " then
				flush()
			end
		end
	end
	flush()
	return tokens
end

-- How much every UIScale above (and on) `gui` enlarges it: its AbsoluteSize
-- divided by this is in the same units as the offsets of its children.
local function totalScale(gui: Instance): number
	local product = 1
	local node: Instance? = gui
	while node and not node:IsA("LayerCollector") do
		local scale = node:FindFirstChildOfClass("UIScale")
		if scale then
			product *= scale.Scale
		end
		node = node.Parent
	end
	return product
end

type CoinRow = { tokens: { number }, width: number }

-- Lays the tokens out at text size `size`: the rows, and each token's width.
local function coinLayout(tokens: { CoinToken }, size: number, font: Enum.Font, wrap: boolean, maxWidth: number): ({ CoinRow }, { number }, number)
	local iconEdge = math.floor(size * 1.1 + 0.5)
	local widths: { number } = {}
	for index, token in tokens do
		if token.kind == "text" then
			widths[index] = TextService:GetTextSize(token.plain, size, font, MEASURE_BOX).X
		elseif token.kind == "icon" then
			widths[index] = iconEdge
		else
			widths[index] = 0
		end
	end
	local rows: { CoinRow } = { { tokens = {}, width = 0 } }
	for index, token in tokens do
		local row = rows[#rows]
		if token.kind == "break" then
			table.insert(rows, { tokens = {}, width = 0 })
		elseif wrap and #row.tokens > 0 and row.width + widths[index] > maxWidth then
			table.insert(rows, { tokens = { index }, width = widths[index] })
		else
			table.insert(row.tokens, index)
			row.width += widths[index]
		end
	end
	local lineHeight = TextService:GetTextSize("Ag", size, font, MEASURE_BOX).Y
	return rows, widths, math.max(lineHeight, iconEdge)
end

local function coinFits(tokens: { CoinToken }, size: number, font: Enum.Font, wrap: boolean, width: number, height: number): boolean
	local rows, _, rowHeight = coinLayout(tokens, size, font, wrap, width)
	for _, row in rows do
		if row.width > width + 0.5 then
			return false
		end
	end
	return #rows * rowHeight <= height + 0.5
end

local function showOwnText(label: TextLabel, entry: CoinEntry)
	local line = label:FindFirstChild("CoinLine")
	if line then
		line:Destroy()
	end
	if entry.hidden then
		entry.hidden = false
		label.TextTransparency = entry.savedText
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = entry.savedStroke
		end
	end
end

local function renderCoins(label: TextLabel, entry: CoinEntry)
	local text = label.Text
	if not string.find(text, COIN, 1, true) then
		entry.key = nil
		showOwnText(label, entry)
		return
	end
	local scale = totalScale(label)
	local width = math.floor(label.AbsoluteSize.X / scale + 0.5)
	local height = math.floor(label.AbsoluteSize.Y / scale + 0.5)
	if width <= 1 or height <= 1 then
		-- Not laid out yet (unparented or not sized): try again once it is.
		return
	end
	local constraint = label:FindFirstChildOfClass("UITextSizeConstraint")
	local key = table.concat({
		text, tostring(width), tostring(height), tostring(label.TextColor3), label.Font.Name,
		label.TextXAlignment.Name, label.TextYAlignment.Name, tostring(label.TextWrapped),
		tostring(label.TextScaled), tostring(label.TextSize), tostring(label.RichText),
		tostring(constraint and constraint.MaxTextSize),
	}, "|")
	if key == entry.key then
		return
	end
	entry.key = key

	local wrap = label.TextWrapped
	local font = if label.Font == Enum.Font.Unknown then UiKit.FONT else label.Font
	local tokens = coinTokens(text, label.RichText, wrap)

	-- The text size the label would use: TextScaled grows it to fill the box (up to
	-- its UITextSizeConstraint), otherwise its own TextSize, shrunk if it overflows.
	local low = math.max(6, if constraint then constraint.MinTextSize else 6)
	local high = if label.TextScaled then (if constraint then constraint.MaxTextSize else 100) else label.TextSize
	local size = low
	if coinFits(tokens, high, font, wrap, width, height) then
		size = high
	else
		while low <= high do
			local middle = math.floor((low + high) / 2)
			if coinFits(tokens, middle, font, wrap, width, height) then
				size = middle
				low = middle + 1
			else
				high = middle - 1
			end
		end
	end
	local rows, widths, rowHeight = coinLayout(tokens, size, font, wrap, width)

	local old = label:FindFirstChild("CoinLine")
	if old then
		old:Destroy()
	end
	local line = Instance.new("Frame")
	line.Name = "CoinLine"
	line.BackgroundTransparency = 1
	line.Size = UDim2.fromScale(1, 1)
	line.ZIndex = label.ZIndex

	local stroke = label:FindFirstChildOfClass("UIStroke")
	if not entry.hidden then
		entry.hidden = true
		entry.savedText = label.TextTransparency
		entry.savedStroke = if stroke then stroke.Transparency else 0
	end

	local totalHeight = #rows * rowHeight
	local top = if label.TextYAlignment == Enum.TextYAlignment.Top then 0
		elseif label.TextYAlignment == Enum.TextYAlignment.Bottom then height - totalHeight
		else (height - totalHeight) / 2
	local iconEdge = math.floor(size * 1.1 + 0.5)
	local shadowOffset = math.max(1, math.floor(iconEdge / 14 + 0.5))
	local imageId = UiKit.iconImageId(UiKit.CURRENCY_ICON)

	for rowIndex, row in rows do
		local x = if label.TextXAlignment == Enum.TextXAlignment.Right then width - row.width
			elseif label.TextXAlignment == Enum.TextXAlignment.Center then (width - row.width) / 2
			else 0
		local y = top + (rowIndex - 1) * rowHeight
		for _, tokenIndex in row.tokens do
			local token = tokens[tokenIndex]
			local tokenWidth = widths[tokenIndex]
			if token.kind == "text" then
				local piece = Instance.new("TextLabel")
				piece.BackgroundTransparency = 1
				piece.Position = UDim2.fromOffset(x, y)
				piece.Size = UDim2.fromOffset(tokenWidth + 2, rowHeight)
				piece.Font = font
				piece.TextSize = size
				piece.TextColor3 = label.TextColor3
				piece.TextTransparency = entry.savedText
				piece.TextXAlignment = Enum.TextXAlignment.Left
				piece.TextYAlignment = Enum.TextYAlignment.Center
				piece.RichText = label.RichText
				piece.Text = token.rich
				piece.ZIndex = label.ZIndex
				if stroke then
					local copy = stroke:Clone()
					copy.Transparency = entry.savedStroke
					copy.Parent = piece
				end
				piece.Parent = line
			elseif token.kind == "icon" then
				local iconTop = y + (rowHeight - iconEdge) / 2
				local shadow = Instance.new("ImageLabel")
				shadow.BackgroundTransparency = 1
				shadow.Position = UDim2.fromOffset(x + shadowOffset, iconTop + shadowOffset)
				shadow.Size = UDim2.fromOffset(iconEdge, iconEdge)
				shadow.Image = imageId
				shadow.ImageColor3 = Color3.new(0, 0, 0)
				shadow.ImageTransparency = 0.5
				shadow.ScaleType = Enum.ScaleType.Fit
				shadow.ZIndex = label.ZIndex
				shadow.Parent = line
				local icon = Instance.new("ImageLabel")
				icon.BackgroundTransparency = 1
				icon.Position = UDim2.fromOffset(x, iconTop)
				icon.Size = UDim2.fromOffset(iconEdge, iconEdge)
				icon.Image = imageId
				icon.ScaleType = Enum.ScaleType.Fit
				icon.ZIndex = label.ZIndex
				icon.Parent = line
			end
			x += tokenWidth
		end
	end

	label.TextTransparency = 1
	if stroke then
		stroke.Transparency = 1
	end
	line.Parent = label
end

-- Makes `label` draw the currency image for every 💰 in its text, now and
-- whenever its text changes later. Safe to call more than once.
function UiKit.watchCurrency(label: TextLabel)
	if coinEntries[label] then
		return
	end
	local entry: CoinEntry = { key = nil, pending = false, hidden = false, savedText = 0, savedStroke = 0 }
	coinEntries[label] = entry
	local function schedule()
		if entry.pending then
			return
		end
		entry.pending = true
		task.defer(function()
			entry.pending = false
			if label.Parent then
				renderCoins(label, entry)
			end
		end)
	end
	for _, property in {
		"Text", "TextColor3", "Font", "TextXAlignment", "TextYAlignment", "TextWrapped",
		"TextScaled", "TextSize", "RichText", "AbsoluteSize",
	} do
		label:GetPropertyChangedSignal(property):Connect(schedule)
	end
	label.ChildAdded:Connect(function(child)
		if child:IsA("UITextSizeConstraint") then
			schedule()
		end
	end)
	schedule()
end

function UiKit.label(parent: Instance, text: string, textSize: number, outlineThickness: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = UiKit.FONT
	label.Text = text
	label.TextSize = textSize
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = parent
	if outlineThickness > 0 then
		UiKit.outlineText(label, outlineThickness)
	end
	if string.find(text, COIN, 1, true) then
		UiKit.watchCurrency(label)
	end
	return label
end

-- Small wrapped text, top-left aligned, for descriptions.
function UiKit.body(parent: Instance, text: string, size: number, color: Color3?): TextLabel
	local label = UiKit.label(parent, text, size, 1.5)
	label.TextColor3 = color or Color3.fromRGB(215, 220, 240)
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	return label
end

-- Shrinks text to fit its box (up to maxSize) so long labels don't overflow.
function UiKit.fitText(label: TextLabel, maxSize: number)
	label.TextScaled = true
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxSize
	constraint.Parent = label
end

-- Fill colour, rounded corners, a thick dark border and a soft top-to-bottom
-- shine, on any frame or button. (Don't put text directly on a decorated
-- object: the shine would tint it. Put text in a child label.)
function UiKit.decorate(gui: GuiObject, style: Style, cornerRadius: number, strokeThickness: number)
	gui.BackgroundColor3 = style.fill
	gui.BackgroundTransparency = 0
	gui.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, cornerRadius)
	corner.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = style.outline
	stroke.Thickness = strokeThickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = gui

	local shine = Instance.new("UIGradient")
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(185, 185, 185))
	shine.Rotation = 90
	shine.Parent = gui
end

-- Re-colours something already decorated. (A polished button keeps its black
-- outline whatever colour it turns: see UiKit.polish.)
function UiKit.applyStyle(gui: GuiObject, style: Style)
	gui.BackgroundColor3 = style.fill
	local stroke = gui:FindFirstChildOfClass("UIStroke")
	if stroke and not gui:GetAttribute("Polished") then
		stroke.Color = style.outline
	end
end

-- How far below its text a button's text shadow sits, and how see-through it is.
-- (Solid, outline and all: a faded outline made the shadow look smaller than the text.)
local TEXT_SHADOW_DROP = 2
local TEXT_SHADOW_FADE = 0

-- A dark copy of `label` a couple of pixels straight below it (same font, size and
-- outline), kept in step with it as its text, size, position and fading change.
function UiKit.addTextShadow(label: TextLabel)
	local parent = label.Parent
	if not parent or label:GetAttribute("HasTextShadow") or label:GetAttribute("IsTextShadow") then
		return
	end
	-- (Text with a currency icon drawn into it keeps just its own outline, and text in a
	-- list or grid is skipped: the shadow would take a slot in the layout of its own.)
	if label:FindFirstChildWhichIsA("ImageLabel") or parent:FindFirstChildWhichIsA("UIGridStyleLayout") then
		return
	end
	label:SetAttribute("HasTextShadow", true)
	local shadow = label:Clone()
	shadow.Name = label.Name .. "Shadow"
	shadow:SetAttribute("HasTextShadow", nil)
	shadow:SetAttribute("IsTextShadow", true)
	for _, child in shadow:GetChildren() do
		if not (child:IsA("UIStroke") or child:IsA("UITextSizeConstraint")) then
			child:Destroy()
		end
	end
	for _, tag in shadow:GetTags() do
		shadow:RemoveTag(tag)
	end
	shadow.TextColor3 = Color3.new(0, 0, 0)
	shadow.TextStrokeColor3 = Color3.new(0, 0, 0)
	shadow.RichText = false
	local shadowStroke = shadow:FindFirstChildOfClass("UIStroke")
	if shadowStroke then
		shadowStroke.Color = Color3.new(0, 0, 0)
	end
	local labelStroke = label:FindFirstChildOfClass("UIStroke")
	-- (The text's size limits are often changed after it's made, e.g. a bigger button,
	-- so the shadow keeps copying them; otherwise it's drawn smaller, hidden behind.)
	local shadowLimit = shadow:FindFirstChildOfClass("UITextSizeConstraint")
	local function syncLimit()
		local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
		if limit and not shadowLimit then
			shadowLimit = Instance.new("UITextSizeConstraint")
			shadowLimit.Parent = shadow
		end
		if shadowLimit then
			shadowLimit.MaxTextSize = if limit then limit.MaxTextSize else 100
			shadowLimit.MinTextSize = if limit then limit.MinTextSize else 1
		end
	end

	local function fade(transparency: number): number
		return transparency + (1 - transparency) * TEXT_SHADOW_FADE
	end
	local function sync()
		shadow.Text = label.Text
		shadow.TextSize = label.TextSize
		shadow.TextScaled = label.TextScaled
		shadow.TextXAlignment = label.TextXAlignment
		shadow.TextYAlignment = label.TextYAlignment
		shadow.AnchorPoint = label.AnchorPoint
		shadow.Size = label.Size
		shadow.Position = label.Position + UDim2.fromOffset(0, TEXT_SHADOW_DROP)
		shadow.Visible = label.Visible
		shadow.ZIndex = label.ZIndex - 1
		shadow.TextTransparency = fade(label.TextTransparency)
		shadow.TextStrokeTransparency = fade(label.TextStrokeTransparency)
		shadow.Font = label.Font
		shadow.TextWrapped = label.TextWrapped
		shadow.LineHeight = label.LineHeight
		-- (Rich text is copied without its colour tags, so the shadow stays black.)
		if label.RichText then
			shadow.Text = string.gsub(label.Text, "<[^>]->", "")
		end
		if shadowStroke and labelStroke then
			shadowStroke.Thickness = labelStroke.Thickness
			shadowStroke.Transparency = fade(labelStroke.Transparency)
		end
		syncLimit()
	end
	-- Drawn just under the label: the label goes up a layer (floating text is drawn by
	-- layer, not by which came first), and the shadow goes in first, then the label again
	-- after it.
	label.ZIndex += 1
	sync()
	shadow.Parent = parent
	label.Parent = nil
	label.Parent = parent

	label.Changed:Connect(sync)
	if labelStroke then
		labelStroke.Changed:Connect(sync)
	end
	local function watchLimit(child: Instance)
		if child:IsA("UITextSizeConstraint") then
			child.Changed:Connect(syncLimit)
			syncLimit()
		end
	end
	for _, child in label:GetChildren() do
		watchLimit(child)
	end
	label.ChildAdded:Connect(watchLimit)
	label.Destroying:Connect(function()
		shadow:Destroy()
	end)
	label:GetPropertyChangedSignal("Parent"):Connect(function()
		if label.Parent == nil then
			shadow.Parent = nil
		elseif shadow.Parent ~= label.Parent then
			shadow.Parent = label.Parent
		end
	end)
end

-- The finishing touches every button gets: a black outline that deepens towards the
-- bottom, a soft white shine across its top half, and a slight drop shadow under its
-- text (`label`, if it has one).
function UiKit.polish(button: GuiObject, label: TextLabel?)
	if button:GetAttribute("Polished") then
		return
	end
	button:SetAttribute("Polished", true)

	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Color3.new(1, 1, 1)
		local deepen = Instance.new("UIGradient")
		deepen.Color = ColorSequence.new(Color3.fromRGB(62, 62, 70), Color3.fromRGB(6, 6, 8))
		deepen.Rotation = 90
		deepen.Parent = stroke
	end

	local corner = button:FindFirstChildOfClass("UICorner")
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BorderSizePixel = 0
	shine.Position = UDim2.fromOffset(3, 3)
	shine.Size = UDim2.new(1, -6, 0.5, -3)
	shine.ZIndex = 1
	local fadeDown = Instance.new("UIGradient")
	fadeDown.Transparency = NumberSequence.new(0.62, 0.92)
	fadeDown.Rotation = 90
	fadeDown.Parent = shine
	local shineCorner = Instance.new("UICorner")
	shineCorner.CornerRadius = UDim.new(0, math.max((if corner then corner.CornerRadius.Offset else 12) - 3, 2))
	shineCorner.Parent = shine
	shine.Parent = button
	-- (Gone whenever the button's own background is, e.g. a folded sidebar tab.)
	local function syncShine()
		shine.BackgroundTransparency = button.BackgroundTransparency
	end
	syncShine()
	button:GetPropertyChangedSignal("BackgroundTransparency"):Connect(syncShine)
	-- (Everything already on the button goes back on after it, so it draws on top.)
	for _, child in button:GetChildren() do
		if child ~= shine and child:IsA("GuiObject") then
			child.Parent = nil
			child.Parent = button
		end
	end

	if label then
		UiKit.addTextShadow(label)
	end
end

local SCALE_TWEEN = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function tweenScale(button: GuiObject, target: number)
	local scale = button:FindFirstChildOfClass("UIScale")
	if scale then
		TweenService:Create(scale, SCALE_TWEEN, { Scale = target }):Play()
	end
end

-- Icons are usually a short emoji string ("🛒"), but can also be a Roblox
-- image asset -- a plain numeric id, or a full "rbxassetid://..." -- for a
-- custom icon someone uploaded themselves. This tells which.
function UiKit.isImageIcon(icon: string): boolean
	return icon:match("^rbxassetid://%d+$") ~= nil or icon:match("^%d+$") ~= nil
end

-- Normalises an image icon (a plain id or already-full uri) into the
-- "rbxassetid://..." form Image/ImageLabel.Image expects.
function UiKit.iconImageId(icon: string): string
	if icon:match("^rbxassetid://") then
		return icon
	end
	return `rbxassetid://{icon}`
end

-- A soft black silhouette of an image icon, offset behind it, so the icon
-- still reads clearly floating with no panel behind it (see
-- UiKit.collapsible). ImageColor3 multiplies the image's own colours, so
-- black flattens it to a solid shadow while keeping its alpha -- the
-- silhouette matches the icon's actual outline, not just a solid square.
function UiKit.addIconShadow(parent: Instance, imageId: string, size: UDim2, position: UDim2): ImageLabel
	local shadow = Instance.new("ImageLabel")
	shadow.Name = "IconShadow"
	shadow.BackgroundTransparency = 1
	shadow.Size = size
	shadow.Position = position + UDim2.fromOffset(3, 3)
	shadow.Image = imageId
	shadow.ImageColor3 = Color3.new(0, 0, 0)
	shadow.ImageTransparency = 0.5
	shadow.ScaleType = Enum.ScaleType.Fit
	shadow.ZIndex = 0
	shadow.Parent = parent
	return shadow
end

-- An icon on the left, outlined label text on the right, with hover/press
-- feedback. Returns the button plus its icon (a TextLabel for an emoji, an
-- ImageLabel for an uploaded icon -- see UiKit.isImageIcon) and text labels.
function UiKit.button(
	parent: Instance,
	name: string,
	icon: string,
	text: string,
	style: Style,
	size: UDim2
): (TextButton, GuiObject, TextLabel)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.Text = ""
	button.AutoButtonColor = false
	UiKit.decorate(button, style, 14, 3)
	button.Parent = parent

	local scale = Instance.new("UIScale")
	scale.Parent = button

	local iconLabel: GuiObject
	if UiKit.isImageIcon(icon) then
		local imageId = UiKit.iconImageId(icon)
		-- A square, vertically-centred box (rather than the emoji icon's
		-- stretched-to-the-button's-full-height one) so an uploaded image
		-- reads centred instead of pinned to the top of a tall button.
		local iconEdge = math.clamp(size.Y.Offset - 10, 28, 46)
		local iconSize = UDim2.fromOffset(iconEdge, iconEdge)
		local iconPosition = UDim2.new(0, 6, 0.5, -iconEdge / 2)
		UiKit.addIconShadow(button, imageId, iconSize, iconPosition)

		local image = Instance.new("ImageLabel")
		image.Name = "Icon"
		image.BackgroundTransparency = 1
		image.Size = iconSize
		image.Position = iconPosition
		image.Image = imageId
		image.ScaleType = Enum.ScaleType.Fit
		image.ZIndex = 1
		image.Parent = button
		iconLabel = image
	else
		local label = Instance.new("TextLabel")
		label.Name = "Icon"
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(0, 34, 1, 0)
		label.Position = UDim2.new(0, 6, 0, 0)
		label.Font = UiKit.FONT
		label.Text = icon
		label.TextSize = 24
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Parent = button
		iconLabel = label
	end

	local textLabel = UiKit.label(button, text, 22, 2.5)
	textLabel.Name = "Label"
	textLabel.Size = UDim2.new(1, -46, 1, -8)
	textLabel.Position = UDim2.new(0, 40, 0, 4)
	UiKit.fitText(textLabel, 22)
	UiKit.polish(button, textLabel)

	button.MouseEnter:Connect(function()
		tweenScale(button, 1.05)
	end)
	button.MouseLeave:Connect(function()
		tweenScale(button, 1)
	end)
	button.MouseButton1Down:Connect(function()
		tweenScale(button, 0.94)
	end)
	button.MouseButton1Up:Connect(function()
		tweenScale(button, 1.05)
	end)

	return button, iconLabel, textLabel
end

-- A close button: a coloured square with a white X on it. The X is drawn from two
-- crossed bars (with a dark outline behind them) instead of being a letter, so it
-- always shows. `size` must be in pixels (UDim2.fromOffset).
function UiKit.closeButton(parent: Instance, name: string, style: Style, size: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.Text = ""
	button.AutoButtonColor = false
	UiKit.decorate(button, style, 12, 3)
	button.Parent = parent
	UiKit.polish(button)

	-- The X sits in its own frame, which swells a little when hovered (the button
	-- itself does not move, so it stays put in its corner). Given an explicit ZIndex
	-- above the button's own fill so it always draws on top of it.
	local cross = Instance.new("Frame")
	cross.Name = "Cross"
	cross.AnchorPoint = Vector2.new(0.5, 0.5)
	cross.Position = UDim2.fromScale(0.5, 0.5)
	cross.Size = UDim2.fromScale(1, 1)
	cross.BackgroundTransparency = 1
	cross.ZIndex = 2
	cross.Parent = button
	local scale = Instance.new("UIScale")
	scale.Parent = cross

	-- Bold and big enough to read even at a small button size.
	local length = math.min(size.X.Offset, size.Y.Offset) * 0.72
	local thickness = length * 0.32
	local bars: { Frame } = {}
	-- Dark bars first (a little bigger), then the white ones on top.
	for _, layer in { { color = UiKit.TEXT_OUTLINE, grow = 5 }, { color = Color3.new(1, 1, 1), grow = 0 } } do
		for _, rotation in { 45, -45 } do
			local bar = Instance.new("Frame")
			bar.Name = "Bar"
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromScale(0.5, 0.5)
			bar.Size = UDim2.fromOffset(length + layer.grow, thickness + layer.grow)
			bar.Rotation = rotation
			bar.BackgroundColor3 = layer.color
			bar.BorderSizePixel = 0
			bar.ZIndex = 3
			bar.Parent = cross
			local round = Instance.new("UICorner")
			round.CornerRadius = UDim.new(0, 3)
			round.Parent = bar
			table.insert(bars, bar)
		end
	end

	-- In a ScreenGui that layers by ZIndex across the whole screen (Global), a
	-- button given a high ZIndex would draw its red fill over a lower-numbered X,
	-- so the X always stays a step or two above the button's own ZIndex.
	local function raiseCross()
		cross.ZIndex = button.ZIndex + 1
		for _, bar in bars do
			bar.ZIndex = button.ZIndex + 2
		end
	end
	raiseCross()
	button:GetPropertyChangedSignal("ZIndex"):Connect(raiseCross)

	button.MouseEnter:Connect(function()
		tweenScale(cross, 1.15)
	end)
	button.MouseLeave:Connect(function()
		tweenScale(cross, 1)
	end)
	button.MouseButton1Down:Connect(function()
		tweenScale(cross, 0.85)
	end)
	button.MouseButton1Up:Connect(function()
		tweenScale(cross, 1.15)
	end)
	return button
end

local COLLAPSE_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Shrinks a button (built by UiKit.button, or a matching local copy -- an
-- `icon` label on the left, a text `label` to its right) down to a small
-- square showing just its icon, expanding back out to `expandedSize`
-- (revealing the label) while hovered. Which way it grows falls out of the
-- button's own AnchorPoint/the list layout it sits in -- a left-anchored
-- sidebar button grows rightward, a right-anchored one grows leftward -- so
-- there's nothing to configure here.
-- The label is hidden outright while collapsed, not just clipped: at the
-- collapsed width its own box is only a few pixels wide, and TextScaled
-- shrinks the font to fit that rather than disappearing, leaving a tiny
-- flyspeck of text rather than nothing.
-- The icon itself is built left-aligned and modestly sized (for the expanded
-- pill layout), which reads off-centre and small once the button's collapsed
-- down to a square around just it -- so both its position and size are
-- tweened too, between that left-aligned spot and a much bigger, centred fit
-- in the collapsed square, in step with the button's own resize.
-- Collapsed, the button's own coloured pill (fill, outline) is hidden too --
-- just the icon floats on its own -- and fades back in on hover, giving the
-- label somewhere to sit.
function UiKit.collapsible(button: GuiObject, icon: GuiObject, label: GuiObject, expandedSize: UDim2, collapsedSize: UDim2)
	button.ClipsDescendants = true
	button.Size = collapsedSize
	button.BackgroundTransparency = 1
	label.Visible = false
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 1
	end

	local expandedIconPosition = icon.Position
	local expandedIconSize = icon.Size

	-- The icon's shadow (see UiKit.addIconShadow), if it has one, is kept the
	-- same constant offset behind the icon at every size, rather than tweened
	-- to its own fixed points -- simplest way to keep it glued on exactly
	-- through the resize. Read before icon.Position/Size below are overwritten.
	local shadow = button:FindFirstChild("IconShadow") :: GuiObject?
	local shadowOffset = if shadow then shadow.Position - expandedIconPosition else nil

	local margin = 4
	local collapsedIconSize = UDim2.fromOffset(collapsedSize.X.Offset - margin * 2, collapsedSize.Y.Offset - margin * 2)
	local collapsedIconPosition = UDim2.fromOffset(margin, margin)
	icon.Position = collapsedIconPosition
	icon.Size = collapsedIconSize
	if shadow then
		shadow.Position = collapsedIconPosition + (shadowOffset :: UDim2)
		shadow.Size = collapsedIconSize
	end

	local function expand()
		label.Visible = true
		TweenService:Create(button, COLLAPSE_TWEEN, { Size = expandedSize, BackgroundTransparency = 0 }):Play()
		if stroke then
			TweenService:Create(stroke, COLLAPSE_TWEEN, { Transparency = 0 }):Play()
		end
		TweenService:Create(icon, COLLAPSE_TWEEN, { Position = expandedIconPosition, Size = expandedIconSize }):Play()
		if shadow then
			TweenService:Create(shadow, COLLAPSE_TWEEN, {
				Position = expandedIconPosition + (shadowOffset :: UDim2),
				Size = expandedIconSize,
			}):Play()
		end
	end
	local function collapse()
		label.Visible = false
		TweenService:Create(button, COLLAPSE_TWEEN, { Size = collapsedSize, BackgroundTransparency = 1 }):Play()
		if stroke then
			TweenService:Create(stroke, COLLAPSE_TWEEN, { Transparency = 1 }):Play()
		end
		TweenService:Create(icon, COLLAPSE_TWEEN, { Position = collapsedIconPosition, Size = collapsedIconSize }):Play()
		if shadow then
			TweenService:Create(shadow, COLLAPSE_TWEEN, {
				Position = collapsedIconPosition + (shadowOffset :: UDim2),
				Size = collapsedIconSize,
			}):Play()
		end
	end

	-- A phone has no hover: a tap fires MouseEnter and often never MouseLeave, which
	-- would leave the button stuck open. So there it opens while a finger is held on
	-- it instead, and closes when that finger lifts (wherever it has slid to).
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	button.MouseEnter:Connect(function()
		if not touchOnly then
			expand()
		end
	end)
	button.MouseLeave:Connect(function()
		if not touchOnly then
			collapse()
		end
	end)
	button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		expand()
		local watch
		watch = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
			if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
				watch:Disconnect()
				collapse()
			end
		end)
	end)
end

-- A scrolling column of cards.
-- A UIListLayout sorts its children by NAME unless told otherwise, which puts
-- every list in alphabetical order. This makes it use LayoutOrder instead, and
-- gives each child added to `container` the next number, so things appear in
-- the order the code adds them.
function UiKit.keepInsertOrder(container: Instance, layout: UIListLayout)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	local nextOrder = 0
	container.ChildAdded:Connect(function(child)
		if child:IsA("GuiObject") then
			nextOrder += 1
			child.LayoutOrder = nextOrder
		end
	end)
end

function UiKit.list(parent: Instance, position: UDim2, size: UDim2): ScrollingFrame
	local list = Instance.new("ScrollingFrame")
	list.Position = position
	list.Size = size
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = Color3.fromRGB(150, 155, 190)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = list
	UiKit.keepInsertOrder(list, layout)
	return list
end

-- A volume-style slider: a dark rounded track with a green fill and a round knob,
-- dragged with the mouse or a finger. Calls `onChange` with the new fraction (0 to 1)
-- as it moves. Returns the track, and a function that sets the fraction without
-- calling `onChange`.
function UiKit.slider(parent: Instance, position: UDim2, size: UDim2, fraction: number, onChange: (number) -> ()): (Frame, (number) -> ())
	local track = Instance.new("Frame")
	track.Name = "Slider"
	track.Position = position
	track.Size = size
	-- (The same dark track and outline as the level badge's XP bar.)
	track.BackgroundColor3 = Color3.fromRGB(20, 22, 38)
	track.BorderSizePixel = 0
	track.Active = true
	track.Parent = parent
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track
	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = UiKit.STYLES.panel.outline
	trackStroke.Thickness = 3
	trackStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	trackStroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = UiKit.STYLES.green.fill
	fill.BorderSizePixel = 0
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	-- (RelativeYY: both scales are of the track's height, so the knob stays round.)
	knob.Size = UDim2.new(1, 10, 1, 10)
	knob.SizeConstraint = Enum.SizeConstraint.RelativeYY
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	knob.Parent = track
	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob
	local knobStroke = Instance.new("UIStroke")
	knobStroke.Color = UiKit.TEXT_OUTLINE
	knobStroke.Thickness = 2
	knobStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	knobStroke.Parent = knob

	local current = math.clamp(fraction, 0, 1)
	local function show(value: number)
		current = math.clamp(value, 0, 1)
		fill.Size = UDim2.fromScale(current, 1)
		knob.Position = UDim2.fromScale(current, 0.5)
	end
	show(current)

	local function setFromInput(inputPosition: Vector3)
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end
		show((inputPosition.X - track.AbsolutePosition.X) / width)
		onChange(current)
	end

	local dragging = false
	track.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			dragging = true
			setFromInput(input.Position)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromInput(input.Position)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	return track, show
end

return UiKit
