-- Faces for the cutscene doubles of the player (and anyone else): an
-- expression by name, eased into place.
--
-- A double is a clone of the player's character, so it has whatever face
-- their avatar has, frozen at the moment it was copied -- with an animated
-- (dynamic) head, that's usually its mood animation's smirk, at a funeral.
-- So the face is set for the scene instead:
--   an animated head (one with FaceControls): its face controls, eased over
--     `time` (nothing animates a double's face, so they stay where put);
--   an old flat face (a "face" decal): the decal hidden, and a simple face
--     drawn over it in the same spirit -- eyes, brows, mouth.
--
--   Faces.set(model, "fear")         -- quickly
--   Faces.set(model, "dazed", 1.5)   -- over a second and a half

local TweenService = game:GetService("TweenService")

local Faces = {}

-- Every control an expression below uses. Setting a face sets all of these
-- (to 0 if the expression doesn't mention it), so nothing is left over from
-- the one before -- or from the avatar's smirk.
local CONTROLS = {
	"JawDrop",
	"LeftEyeUpperLidRaiser", "RightEyeUpperLidRaiser",
	"LeftInnerBrowRaiser", "RightInnerBrowRaiser",
	"LeftOuterBrowRaiser", "RightOuterBrowRaiser",
	"LeftBrowLowerer", "RightBrowLowerer",
	"Corrugator",
	"LeftEyeClosed", "RightEyeClosed",
	"LeftLipCornerDown", "RightLipCornerDown",
	"LeftLipStretcher", "RightLipStretcher",
	"LeftLipCornerPuller", "RightLipCornerPuller",
	"LeftUpperLipRaiser", "RightUpperLipRaiser",
	"LeftNoseWrinkler", "RightNoseWrinkler",
	"LeftCheekRaiser", "RightCheekRaiser",
	"ChinRaiser",
	"EyesLookDown",
}

-- Each side's pair set together: `both("InnerBrowRaiser", 0.8)`.
local function both(name: string, value: number, into: { [string]: number }?): { [string]: number }
	local t = into or {}
	t["Left" .. name] = value
	t["Right" .. name] = value
	return t
end

local function face(parts: { { any } }): { [string]: number }
	local t = {}
	for _, p in parts do
		if p[3] == "single" then
			t[p[1]] = p[2]
		else
			both(p[1], p[2], t)
		end
	end
	return t
end

-- (Tuned on a classic-style animated head, where the eyelids don't widen and
-- the brows move only a little: the mouth and the eyes closing carry most
-- of it, so the numbers are strong.)
Faces.EXPRESSIONS = {
	neutral = {},
	-- Quiet and low: Ray's goodbye.
	sombre = face({ { "InnerBrowRaiser", 0.6 }, { "LipCornerDown", 0.5 }, { "EyeClosed", 0.15 } }),
	worried = face({
		{ "InnerBrowRaiser", 0.8 }, { "Corrugator", 0.4, "single" }, { "LipStretcher", 0.4 }, { "LipCornerDown", 0.3 },
	}),
	-- Holding it in, and not managing: the funeral.
	grief = face({
		{ "InnerBrowRaiser", 1 }, { "Corrugator", 0.4, "single" }, { "LipCornerDown", 0.85 },
		{ "EyeClosed", 0.35 }, { "ChinRaiser", 0.5, "single" },
	}),
	-- It's just happened.
	shock = face({
		{ "InnerBrowRaiser", 1 }, { "OuterBrowRaiser", 1 }, { "EyeUpperLidRaiser", 1 },
		{ "JawDrop", 0.7, "single" },
	}),
	fear = face({
		{ "InnerBrowRaiser", 1 }, { "OuterBrowRaiser", 0.5 }, { "Corrugator", 0.6, "single" }, { "EyeUpperLidRaiser", 1 },
		{ "LipStretcher", 0.9 }, { "JawDrop", 0.55, "single" }, { "LipCornerDown", 0.4 },
	}),
	pain = face({
		{ "BrowLowerer", 0.9 }, { "Corrugator", 0.7, "single" }, { "EyeClosed", 0.6 },
		{ "UpperLipRaiser", 0.6 }, { "LipStretcher", 0.7 }, { "NoseWrinkler", 0.5 }, { "JawDrop", 0.2, "single" },
	}),
	-- Going: the eyes half shut, the jaw loose.
	dazed = face({
		{ "EyeClosed", 0.6 }, { "JawDrop", 0.3, "single" }, { "InnerBrowRaiser", 0.4 }, { "EyesLookDown", 0.3, "single" },
	}),
	fainting = face({ { "EyeClosed", 1 }, { "JawDrop", 0.25, "single" } }),
}

-- ===== Old flat faces: drawn =====

local INK = Color3.fromRGB(20, 18, 18)

local function stroke(parent: Instance, name: string, size: UDim2, position: UDim2, rotation: number?, round: boolean?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.Position = position
	f.Rotation = rotation or 0
	f.BackgroundColor3 = INK
	f.BorderSizePixel = 0
	f.Parent = parent
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = f
	end
	return f
end

-- The values of an expression, by control (0 where it says nothing).
local function valueOf(expression: { [string]: number }, name: string): number
	return expression[name] or 0
end

local function drawFace(head: BasePart, expression: { [string]: number })
	local decal = head:FindFirstChild("face")
	if decal and decal:IsA("Decal") then
		decal.Transparency = 1
	end
	local old = head:FindFirstChild("DrawnFace")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "DrawnFace"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 120
	gui.LightInfluence = 1
	gui.Parent = head
	local canvas = Instance.new("Frame")
	canvas.BackgroundTransparency = 1
	-- The face sits in the middle of the head's front.
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.52)
	canvas.Size = UDim2.fromScale(0.8, 0.8)
	canvas.Parent = gui
	local v = function(name)
		return valueOf(expression, name)
	end
	for _, side in { "Left", "Right" } do
		-- (The character's left is the viewer's right.)
		local x = if side == "Left" then 0.68 else 0.32
		local open = math.clamp(1 - v(side .. "EyeClosed") + v(side .. "EyeUpperLidRaiser") * 0.5, 0.08, 1.5)
		stroke(canvas, side .. "Eye", UDim2.fromScale(0.1, 0.2 * open), UDim2.fromScale(x, 0.42), 0, true)
		local raise = (v(side .. "InnerBrowRaiser") + v(side .. "OuterBrowRaiser")) * 0.05 - v(side .. "BrowLowerer") * 0.06
		-- Inner end up (worry) tilts the brow one way; lowered (pain, anger) the other.
		local tilt = (v(side .. "InnerBrowRaiser") - v(side .. "OuterBrowRaiser") * 0.5 - v(side .. "BrowLowerer")) * 22
		stroke(canvas, side .. "Brow", UDim2.fromScale(0.2, 0.035), UDim2.fromScale(x, 0.25 - raise), if side == "Left" then tilt else -tilt, true)
	end
	-- The mouth: wider for a stretched mouth, taller for an open jaw, and
	-- dropped at the corners for a frown (two short strokes angled down).
	local open = v("JawDrop")
	local wide = 0.22 + (v("LeftLipStretcher") + v("RightLipStretcher")) * 0.06
	if open > 0.1 then
		stroke(canvas, "Mouth", UDim2.fromScale(wide * 0.8, 0.04 + open * 0.22), UDim2.fromScale(0.5, 0.74), 0, true)
	else
		stroke(canvas, "Mouth", UDim2.fromScale(wide, 0.035), UDim2.fromScale(0.5, 0.74), 0, true)
		local down = (v("LeftLipCornerDown") + v("RightLipCornerDown")) / 2
		if down > 0.1 then
			stroke(canvas, "CornerL", UDim2.fromScale(0.07, 0.035), UDim2.fromScale(0.5 + wide / 2 + 0.02, 0.765), 35 * down, true)
			stroke(canvas, "CornerR", UDim2.fromScale(0.07, 0.035), UDim2.fromScale(0.5 - wide / 2 - 0.02, 0.765), -35 * down, true)
		end
	end
end

-- ===== Setting a face =====

local running: { [Instance]: Tween } = {}

function Faces.set(model: Model?, name: string, time: number?)
	if not model then
		return
	end
	local expression = Faces.EXPRESSIONS[name]
	local head = model:FindFirstChild("Head") :: BasePart?
	if not expression or not head then
		return
	end
	local controls = head:FindFirstChildOfClass("FaceControls")
	if controls then
		local goal = {}
		for _, control in CONTROLS do
			goal[control] = expression[control] or 0
		end
		local previous = running[controls]
		if previous then
			previous:Cancel()
		end
		if not time or time <= 0 then
			for control, value in goal do
				pcall(function()
					(controls :: any)[control] = value
				end)
			end
			running[controls] = nil
			return
		end
		local tween = TweenService:Create(controls, TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goal)
		running[controls] = tween
		tween.Completed:Once(function()
			if running[controls] == tween then
				running[controls] = nil
			end
		end)
		tween:Play()
	elseif head:FindFirstChild("face") or head:FindFirstChild("DrawnFace") then
		drawFace(head, expression)
	end
end

return Faces
