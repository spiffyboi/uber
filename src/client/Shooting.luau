-- The player pulling the trigger themselves (chapter 9 in the flat,
-- chapter 10 at the depot): the driver's own view down the pistol, hands
-- shaking -- the aim swims -- and a click (or E, or Space) fires. Every shot
-- is a bang and a muzzle flash; a hit puts up a hitmarker.
--
-- Two ways it can go:
--   scripted (`shots`) -- what each shot does is the scene's, in order,
--       whatever's under the sights: the story decides, not the aim
--       (chapter 9: the second one goes into Teddy). `markers` says which
--       shots count as hits. If the player doesn't fire, the gun goes off
--       on its own after a moment -- the hands are shaking that badly.
--   real (`real`) -- the mouse moves the aim (on top of the shaking), and
--       only shots that are on the target hit. `real.hits` of them drops
--       him; `real.timeLimit` seconds to do it. Returns whether they did.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Cutscene = require(script.Parent.Cutscene)
local Screen = require(script.Parent.Screen)
local StoryScenes = require(script.Parent.StoryScenes)

local Shooting = {}

local player = Players.LocalPlayer

local FIRE_KEYS = { [Enum.KeyCode.E] = true, [Enum.KeyCode.Space] = true, [Enum.KeyCode.ButtonR2] = true }
local MOUSE_SENSITIVITY = 0.0032 -- radians of aim per pixel the mouse moves
local AIM_RANGE = 0.7 -- how far (radians) the mouse can take the aim off where it started

-- The crosshair, a word on what to do, and a clock.
local function overlay(): (ScreenGui, TextLabel, TextLabel, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShootingOverlay"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 11
	gui.Parent = player:WaitForChild("PlayerGui")
	local ring = Instance.new("Frame")
	ring.Name = "Crosshair"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(22, 22)
	ring.BackgroundTransparency = 1
	ring.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.35
	stroke.Thickness = 1.5
	stroke.Parent = ring
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(3, 3)
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.BorderSizePixel = 0
	dot.Parent = ring
	local hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 0.85, 0)
	hint.Size = UDim2.fromOffset(600, 30)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamBold
	hint.TextSize = 20
	hint.TextColor3 = Color3.fromRGB(240, 236, 225)
	hint.TextStrokeTransparency = 0.4
	hint.Text = "CLICK TO FIRE"
	hint.Parent = gui
	local clock = hint:Clone()
	clock.Name = "Clock"
	clock.AnchorPoint = Vector2.new(0.5, 0)
	clock.Position = UDim2.new(0.5, 0, 0.14, 0)
	clock.TextSize = 34
	clock.TextColor3 = Color3.fromRGB(235, 80, 90)
	clock.Text = ""
	clock.Parent = gui
	-- The hitmarker: an X of four short strokes round the centre.
	local marker = Instance.new("Frame")
	marker.Name = "Hitmarker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.Size = UDim2.fromOffset(44, 44)
	marker.BackgroundTransparency = 1
	marker.Visible = false
	marker.Parent = gui
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		local stroke2 = Instance.new("Frame")
		stroke2.AnchorPoint = Vector2.new(0.5, 0.5)
		stroke2.Position = UDim2.new(0.5, math.cos(a) * 13, 0.5, math.sin(a) * 13)
		stroke2.Size = UDim2.fromOffset(12, 3)
		stroke2.Rotation = 45 + i * 90
		stroke2.BackgroundColor3 = Color3.new(1, 1, 1)
		stroke2.BorderSizePixel = 0
		stroke2.Parent = marker
	end
	return gui, hint, clock, marker
end

local function showMarker(marker: Frame, final: boolean)
	marker.Visible = true
	for _, s in marker:GetChildren() do
		if s:IsA("Frame") then
			s.BackgroundColor3 = if final then Color3.fromRGB(235, 60, 70) else Color3.new(1, 1, 1)
			s.BackgroundTransparency = 0
			TweenService:Create(s, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		end
	end
	marker.Size = UDim2.fromOffset(52, 52)
	TweenService:Create(marker, TweenInfo.new(0.15), { Size = UDim2.fromOffset(44, 44) }):Play()
end

-- `opts`:
--   eye()      -- where the driver's eyes are
--   target()   -- what they're aiming at (where the aim starts, in real mode)
--   shake      -- how badly the hands shake (1 = badly)
--   fov        -- the camera's
--   shots, markers, patience  -- scripted (see the top)
--   real = { hitAt(), radius, hits, timeLimit, onHit(n), onMiss() }
-- Yields until it's over. Returns true unless real mode ran out of time.
function Shooting.run(opts): boolean
	local kit = StoryScenes.kit
	local shake = opts.shake or 1
	local real = opts.real
	local pistol = kit.makePistol()
	local hand = Instance.new("Part")
	hand.Name = "ShootingHand"
	hand.Size = Vector3.new(0.34, 0.5, 0.36)
	local skin = kit.partOf(player.Character, "RightHand")
	hand.Color = if skin then skin.Color else Color3.fromRGB(204, 142, 105)
	hand.Anchored = true
	hand.CanCollide = false
	hand.CanQuery = false
	hand.CastShadow = false
	hand.Parent = workspace
	local gui, hint, clock, marker = overlay()

	-- Where the mouse has taken the aim (real mode), from a start a little
	-- off the target, so it has to be found.
	local yaw, pitch = if real then 0.16 else 0, if real then 0.05 else 0
	local base = CFrame.lookAt(opts.eye(), opts.target())
	local kick = 0
	local started = os.clock()
	local function aim(): CFrame
		local t = os.clock() - started
		local a = math.rad(if real then 1.6 else 2.4) * shake
		local wander = CFrame.Angles(
			math.noise(t * 0.9, 1) * a + math.noise(t * 7, 2) * a * 0.3 + kick,
			math.noise(t * 0.8, 3) * a + math.noise(t * 6, 4) * a * 0.3,
			math.noise(t * 0.5, 5) * a * 0.4
		)
		if real then
			return CFrame.new(opts.eye()) * base.Rotation * CFrame.Angles(0, -yaw, 0) * CFrame.Angles(-pitch, 0, 0) * wander
		end
		return CFrame.lookAt(opts.eye(), opts.target()) * wander
	end
	Cutscene.shot(function()
		return aim()
	end, opts.fov or 55)
	-- The pistol held out in front, low and to the right, pointing down the
	-- aim, the hand round its grip.
	local connection = RunService.RenderStepped:Connect(function(dt)
		kick = math.max(0, kick - dt * 0.6)
		local view = aim()
		local recoil = CFrame.new(0, kick * 1.5, kick * 2) * CFrame.Angles(kick * 3, 0, 0)
		local at = view * CFrame.new(0.42, -0.42, -1.45) * recoil
		kit.placePistol(pistol, at)
		hand.CFrame = at * CFrame.new(0, -0.36, 0.28) * CFrame.Angles(math.rad(-16), 0, 0)
	end)

	local wantFire = false
	local inputs = {}
	table.insert(inputs, UserInputService.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch or FIRE_KEYS[i.KeyCode] then
			wantFire = true
		end
	end))
	local mouseWas = UserInputService.MouseBehavior
	if real then
		hint.Text = "AIM WITH THE MOUSE  ·  CLICK TO FIRE"
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		table.insert(inputs, UserInputService.InputChanged:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseMovement then
				yaw = math.clamp(yaw + i.Delta.X * MOUSE_SENSITIVITY, -AIM_RANGE, AIM_RANGE)
				pitch = math.clamp(pitch + i.Delta.Y * MOUSE_SENSITIVITY, -AIM_RANGE, AIM_RANGE)
			end
		end))
	end

	local function bang()
		kit.muzzleFlash((pistol.CFrame * CFrame.new(0, 0.02, -0.7)).Position)
		Screen.flash(Color3.new(1, 1, 1), 0.3, 0.15)
		kick = math.rad(5)
	end

	local result = true
	if real then
		-- Real: hits only where the aim is.
		local hits = 0
		local deadline = os.clock() + (real.timeLimit or 8)
		local nextAllowed = os.clock() + 0.3
		-- In Studio only, for testing the way through: the workspace attribute
		-- DebugAutoAim puts the aim on him and fires.
		local autoAim = RunService:IsStudio() and workspace:GetAttribute("DebugAutoAim") == true
		while hits < (real.hits or 3) do
			local left = deadline - os.clock()
			if left <= 0 then
				result = false
				break
			end
			if autoAim then
				base = CFrame.lookAt(opts.eye(), real.hitAt())
				yaw, pitch = 0, 0
				shake = 0
				if os.clock() >= nextAllowed then
					wantFire = true
				end
			end
			clock.Text = string.format("%.1f", left)
			if wantFire and os.clock() >= nextAllowed then
				wantFire = false
				nextAllowed = os.clock() + 0.32
				hint.Text = ""
				bang()
				-- On him? The aim's line passing close enough to his middle.
				local view = aim()
				local to = real.hitAt() - view.Position
				local along = to:Dot(view.LookVector)
				local miss = (to - view.LookVector * along).Magnitude
				if along > 0 and miss <= (real.radius or 1.3) then
					hits += 1
					showMarker(marker, hits >= (real.hits or 3))
					if real.onHit then
						task.spawn(real.onHit, hits)
					end
				elseif real.onMiss then
					task.spawn(real.onMiss)
				end
			end
			wantFire = false
			RunService.RenderStepped:Wait()
		end
		clock.Text = ""
	else
		-- Scripted: the story's shots, in order.
		local fired = 0
		local nextAllowed = os.clock() + 0.5
		local waitingSince = os.clock()
		while fired < #opts.shots do
			local patient = os.clock() - waitingSince > (opts.patience or 3.2)
			if (wantFire or patient) and os.clock() >= nextAllowed then
				wantFire = false
				fired += 1
				hint.Text = ""
				bang()
				if opts.markers and opts.markers[fired] then
					showMarker(marker, fired == #opts.shots)
				end
				task.spawn(opts.shots[fired])
				nextAllowed = os.clock() + 0.42
				waitingSince = os.clock()
			end
			RunService.RenderStepped:Wait()
		end
	end
	task.wait(0.8)
	for _, c in inputs do
		c:Disconnect()
	end
	UserInputService.MouseBehavior = mouseWas
	connection:Disconnect()
	pistol:Destroy()
	hand:Destroy()
	gui:Destroy()
	return result
end

return Shooting
