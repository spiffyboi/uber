-- Painted detail on building walls: window grids, storefront bands, signs.
--
-- Everything on one wall goes into ONE SurfaceGui. Separate SurfaceGuis on
-- the same face of the same part have no defined draw order, so they
-- z-fight -- this is what made the building windows/signs flicker as the
-- camera moved (each building used to stack three: windows, storefront,
-- sign). Layering inside a single gui uses ZIndex instead, which is stable.

local Facade = {}

local LIT_WINDOW = Color3.fromRGB(235, 200, 120)
local DARK_WINDOW = Color3.fromRGB(12, 13, 18)

-- The face of a block-row building that looks onto its street. Buildings are
-- laid out in a street-relative frame (see DistrictBuilder) where the street
-- runs along Z, so for the side -1 row that's the +X ("Right") face.
function Facade.roadFace(side: number): Enum.NormalId
	return if side == -1 then Enum.NormalId.Right else Enum.NormalId.Left
end

-- How far away (studs) wall detail stops being drawn. Measured live, these
-- surfaces were costing about a fifth of every frame on the old, much
-- smaller street; beyond this the night haze has mostly swallowed them
-- anyway. Distant skyline towers pass a larger value of their own.
Facade.DEFAULT_MAX_DISTANCE = 420

-- The single SurfaceGui for `face` of `part`, created on first use.
function Facade.gui(part: BasePart, face: Enum.NormalId, maxDistance: number?): SurfaceGui
	local name = "Facade_" .. face.Name
	local existing = part:FindFirstChild(name)
	if existing then
		return existing :: SurfaceGui
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Unlit: lit windows and signs should glow at night regardless of how
	-- dark the street lighting around them is.
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or Facade.DEFAULT_MAX_DISTANCE
	gui.Parent = part
	return gui
end

-- Only the lit windows of a grid, each placed directly (no layout object,
-- no dark windows): for the towers seen from a distance, where a dark
-- window on a dark wall is invisible anyway. A fraction of the objects a
-- full grid costs.
function Facade.litWindows(gui: SurfaceGui, columns: number, rows: number, litChance: number)
	local cellW, cellH = 0.94 / columns, 1 / rows
	for row = 0, rows - 1 do
		for col = 0, columns - 1 do
			if math.random() < litChance then
				local window = Instance.new("Frame")
				window.BackgroundColor3 = LIT_WINDOW
				window.BorderSizePixel = 0
				window.Position = UDim2.fromScale(0.03 + (col + 0.22) * cellW, (row + 0.22) * cellH)
				window.Size = UDim2.fromScale(cellW * 0.56, cellH * 0.56)
				window.Parent = gui
			end
		end
	end
end

-- Share of unlit windows drawn at all: as faint dark glass, enough to hint
-- at the grid. The rest of the unlit ones are left as bare wall -- at night,
-- in the haze, a dark window on a dark wall barely shows, and drawing every
-- one was most of the ~110,000 objects the city cost every player to load
-- (confirmed live: loading it all starved Roblox's own chat of time and it
-- failed to start).
-- (Cut from 0.22 when the city tripled in size: measured live, ~28,000
-- window frames, and Studio's test play running out of memory.)
local UNLIT_SHARE = 0.1

-- A grid of windows, some lit. `top`/`bottom` are fractions of the wall's
-- height (0 = top edge) to confine the grid, e.g. above a storefront. Each
-- window takes a bit over half its share of the wall each way, with real
-- wall between: full-share cells read as giant glowing slabs.
function Facade.windows(gui: SurfaceGui, columns: number, rows: number, litChance: number, top: number?, bottom: number?)
	local topFraction = top or 0
	local bottomFraction = bottom or 1
	local cellW = 0.94 / columns
	local cellH = (bottomFraction - topFraction) / rows
	for row = 0, rows - 1 do
		for col = 0, columns - 1 do
			local roll = math.random()
			local color = if roll < litChance then LIT_WINDOW elseif roll < litChance + UNLIT_SHARE then DARK_WINDOW else nil
			if color then
				local window = Instance.new("Frame")
				window.BackgroundColor3 = color
				window.BorderSizePixel = 0
				window.Position = UDim2.fromScale(0.03 + (col + 0.2) * cellW, topFraction + (row + 0.22) * cellH)
				window.Size = UDim2.fromScale(cellW * 0.6, cellH * 0.56)
				window.ZIndex = 1
				window.Parent = gui
			end
		end
	end
end

-- Text on a dark plate, e.g. a shop or club sign.
function Facade.sign(gui: SurfaceGui, text: string, color: Color3, position: UDim2, size: UDim2, zIndex: number?, font: Enum.Font?): Frame
	local plate = Instance.new("Frame")
	plate.Name = "Sign"
	plate.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
	plate.BackgroundTransparency = 0.1
	plate.BorderSizePixel = 0
	plate.Position = position
	plate.Size = size
	plate.ZIndex = zIndex or 3
	plate.Parent = gui

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.92, 0, 0.84, 0)
	label.Position = UDim2.new(0.04, 0, 0.08, 0)
	label.Font = font or Enum.Font.Oswald
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.ZIndex = plate.ZIndex
	label.Parent = plate
	return plate
end

-- A whole-part text label (for a dedicated sign board part's own face).
function Facade.boardText(part: BasePart, face: Enum.NormalId, text: string, color: Color3, background: Color3?, font: Enum.Font?)
	local gui = Facade.gui(part, face)
	local label = Instance.new("TextLabel")
	label.BackgroundColor3 = background or Color3.fromRGB(8, 8, 10)
	label.BackgroundTransparency = if background then 0 else 1
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = font or Enum.Font.Oswald
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.PaddingTop = UDim.new(0.1, 0)
	padding.PaddingBottom = UDim.new(0.1, 0)
	padding.Parent = label
	return label
end

return Facade
