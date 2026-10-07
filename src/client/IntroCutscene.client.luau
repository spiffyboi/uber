-- The opening, once per session: the player walks into the Marrow Cab Co.
-- dispatch office and gets put on graveyard shift (Stage 0, see
-- TaxiOfficeBuilder), which cuts to steam off a grate, a parked cab at 2am,
-- then a slow creep forward through the rain-streaked windshield while a
-- couple of lines of narration set the mood (Stages A/B) -- built after the
-- opening of Scorsese's Taxi Driver, in mood and shot structure only: the
-- office dialogue below is original, written for this game's own characters,
-- not a transcript of that film's. The player's story starts them as a
-- Marrow Cab Co. driver, not a GigLine one (that turn comes later), so this
-- ends on the two-way radio crackling with a fare call, not an app
-- notification, and hands control of the car to the player once they
-- answer it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CityConfig = require(Shared:WaitForChild("CityConfig"))
local UiKit = require(Shared:WaitForChild("UiKit"))
local CarSystems = require(script.Parent.CarSystems)
local DashScreenInput = require(script.Parent.DashScreenInput)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local acceptJobRemote = remotes:WaitForChild("AcceptJob")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Ambient rain/city bed and the score cue for the drive -- open slots, same
-- as Brew a Potion!'s MusicPlayer: fill in real uploaded/Creator Store ids
-- later, the scene works (silently) without them meanwhile.
local AMBIENCE_ID = "rbxassetid://0"
local SCORE_ID = "rbxassetid://0"

local MONOLOGUE = {
	"Been driving The Marrow six nights a week for a year now.",
	"Everybody in this city's going somewhere. Nobody wants to look at the driver.",
	"Radio's about to squawk. It always does.",
}

-- Stage 0's hiring scene, in the Marrow Cab Co. office (see TaxiOfficeBuilder).
-- Original dialogue for this game's own dispatcher and player character --
-- written to land in the same weary, no-nonsense register as the film this
-- scene pays homage to, not copied from it.
local OFFICE_DIALOGUE = {
	{ speaker = "DISPATCHER", text = "You're late." },
	{ speaker = "", text = "Bus never came. Walked it." },
	{ speaker = "DISPATCHER", text = "Walked into the right place, then -- we're short a car on graveyard." },
	{ speaker = "DISPATCHER", text = "Six nights a week. You drive The Marrow, you drive it careful. Cars don't always come back the way they left." },
	{ speaker = "DISPATCHER", text = "You good working nights? Every night?" },
	{ speaker = "", text = "Anywhere. Anytime." },
	{ speaker = "DISPATCHER", text = "Marrow don't take a day off for the holidays either." },
	{ speaker = "", text = "Anywhere. Anytime." },
	{ speaker = "", text = "I'll bring it back." },
	{ speaker = "DISPATCHER", text = "That's what the last guy said. Keys are on the board -- take Twelve, she runs a little rich but she runs." },
}

local function waitForCar(): (Model, BasePart, VehicleSeat)
	local car = workspace:WaitForChild(player.Name .. "_Car") :: Model
	local chassis = car:WaitForChild("Chassis") :: BasePart
	local seat = car:WaitForChild("DriveSeat") :: VehicleSeat
	return car, chassis, seat
end

-- The player is seated in the car from the moment their character spawns
-- (see CarSpawner), well before the camera ever cuts to third person on
-- them -- this game never actually shows them from outside. Left visible,
-- the driver's own head/torso sat directly in the dash camera's view,
-- blocking the GPS unit and the rest of the interior. LocalTransparencyModifier
-- is a render-only override (this client only, no effect on the character's
-- real Transparency or on how other players see it), so it's the right tool
-- here rather than touching BasePart.Transparency itself.
--
-- A one-time set isn't enough: confirmed live that the engine's own default
-- camera/control modules (PlayerModule -- the same system that fades your
-- own head out in first person) actively manage this exact property on the
-- LocalPlayer's own character every frame regardless of CameraType, and
-- stomp a single assignment back to 0 within a frame or two. Reasserting it
-- every RenderStepped, in the same connection already confirmed (via the
-- driving camera) to win that race, is what actually keeps it hidden.
local function hideCharacterLocally(character: Model): () -> ()
	return function()
		for _, descendant in character:GetDescendants() do
			if descendant:IsA("BasePart") then
				(descendant :: BasePart).LocalTransparencyModifier = 1
			end
		end
	end
end

local function playAmbience(id: string, volume: number, looped: boolean): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Looped = looped
	sound.Parent = SoundService
	if id ~= "rbxassetid://0" then
		sound:Play()
	end
	return sound
end

-- ===== Letterbox bars =====

local function buildLetterbox(gui: ScreenGui): (Frame, Frame)
	local top = Instance.new("Frame")
	top.Name = "LetterboxTop"
	top.BackgroundColor3 = Color3.new(0, 0, 0)
	top.BorderSizePixel = 0
	top.Size = UDim2.new(1, 0, 0, 0)
	top.Position = UDim2.new(0, 0, 0, 0)
	top.ZIndex = 10
	top.Parent = gui

	local bottom = Instance.new("Frame")
	bottom.Name = "LetterboxBottom"
	bottom.BackgroundColor3 = Color3.new(0, 0, 0)
	bottom.BorderSizePixel = 0
	bottom.Size = UDim2.new(1, 0, 0, 0)
	bottom.Position = UDim2.new(0, 0, 1, 0)
	bottom.AnchorPoint = Vector2.new(0, 1)
	bottom.ZIndex = 10
	bottom.Parent = gui

	return top, bottom
end

local function setLetterbox(top: Frame, bottom: Frame, fraction: number, duration: number)
	local size = UDim2.new(1, 0, fraction, 0)
	TweenService:Create(top, TweenInfo.new(duration, Enum.EasingStyle.Sine), { Size = size }):Play()
	TweenService:Create(bottom, TweenInfo.new(duration, Enum.EasingStyle.Sine), { Size = size }):Play()
end

-- ===== Fade to/from black =====

local function buildFade(gui: ScreenGui): Frame
	local fade = Instance.new("Frame")
	fade.Name = "Fade"
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BorderSizePixel = 0
	fade.Size = UDim2.new(1, 0, 1, 0)
	fade.ZIndex = 20
	fade.Parent = gui
	return fade
end

-- ===== Rain, streaked across the screen in front of the camera =====

local function buildRain(): (BasePart, () -> ())
	local rig = Instance.new("Part")
	rig.Name = "RainRig"
	rig.Size = Vector3.new(1, 1, 1)
	rig.Transparency = 1
	rig.CanCollide = false
	rig.Anchored = true
	rig.Parent = workspace.CurrentCamera

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(180, 195, 210))
	emitter.Size = NumberSequence.new(0.15)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	emitter.Lifetime = NumberRange.new(0.4, 0.6)
	emitter.Rate = 200
	emitter.Speed = NumberRange.new(28, 32)
	emitter.SpreadAngle = Vector2.new(4, 4)
	emitter.Rotation = NumberRange.new(75, 80)
	emitter.RotSpeed = NumberRange.new(0, 0)
	emitter.Parent = rig

	local connection = RunService.RenderStepped:Connect(function()
		rig.CFrame = camera.CFrame * CFrame.new(0, 1.5, -5) * CFrame.Angles(math.rad(80), 0, 0)
	end)

	return rig, function()
		connection:Disconnect()
		rig:Destroy()
	end
end

-- ===== Subtitles =====

local function buildSubtitle(gui: ScreenGui): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Subtitle"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.8, 0, 0, 60)
	label.Position = UDim2.new(0.5, 0, 0.78, 0)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Font = UiKit.FONT
	label.TextSize = 26
	label.TextColor3 = Color3.fromRGB(225, 225, 230)
	label.TextTransparency = 1
	label.TextWrapped = true
	label.Text = ""
	label.ZIndex = 10
	UiKit.outlineText(label, 3)
	label.Parent = gui
	return label
end

-- UIStroke (the outline UiKit.outlineText adds) has its own independent
-- Transparency, not tied to the TextLabel's own TextTransparency -- tweening
-- just the label left a fully-opaque outline of every faded line ghosted
-- into every later shot for the rest of the session (confirmed live: visible,
-- readable outline text from a scene several stages back still onscreen deep
-- into the driving view). Every fade needs to carry the stroke along with it.
local function setTextVisibility(label: TextLabel, transparency: number)
	label.TextTransparency = transparency
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = transparency
	end
end

local function tweenTextVisibility(label: TextLabel, transparency: number, duration: number)
	TweenService:Create(label, TweenInfo.new(duration), { TextTransparency = transparency }):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(duration), { Transparency = transparency }):Play()
	end
end

local function typeLine(label: TextLabel, text: string)
	setTextVisibility(label, 0)
	label.Text = ""
	for i = 1, #text do
		label.Text = text:sub(1, i)
		task.wait(0.028)
	end
	task.wait(1.1)
	tweenTextVisibility(label, 1, 0.3)
	task.wait(0.4)
end

-- A small caption above the subtitle naming who's speaking, for the office
-- scene's back-and-forth (the narration monologue in Stages A/B never needs
-- one -- it's all the player's own head, hence the blank `speaker` there).
local function buildSpeakerTag(gui: ScreenGui): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "SpeakerTag"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.8, 0, 0, 22)
	label.Position = UDim2.new(0.5, 0, 0.735, 0)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Font = UiKit.FONT
	label.TextSize = 15
	label.TextColor3 = UiKit.STYLES.gold.fill
	label.TextTransparency = 1
	label.Text = ""
	label.ZIndex = 10
	UiKit.outlineText(label, 2)
	label.Parent = gui
	return label
end

local function typeDialogueLine(subtitle: TextLabel, speakerTag: TextLabel, line: { speaker: string, text: string })
	speakerTag.Text = line.speaker
	setTextVisibility(speakerTag, if line.speaker == "" then 1 else 0)
	typeLine(subtitle, line.text)
	setTextVisibility(speakerTag, 1)
end

-- ===== Fare notification, on the dash's own GPS screen =====
-- Lives on the physical GpsScreen SurfaceGui CarBuilder mounts on the dash,
-- not a flat 2D overlay -- most of this car's own UI is meant to end up
-- here over time, not just this one fare call. Styled gold, not cyan --
-- UiKit reserves cyan for GigLine's own accent (see UiKit.STYLES), and the
-- player isn't driving for GigLine yet.

local function showFareOnGpsScreen(gpsUnit: BasePart, gpsScreen: SurfaceGui, onAccept: () -> ())
	local panel = Instance.new("Frame")
	panel.Name = "FarePanel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
	panel.BorderSizePixel = 0
	panel.Parent = gpsScreen

	-- Font sizes bumped across the board (and the button made taller, which
	-- also grows its own text since UiKit.button auto-scales to fill its
	-- height) per direct user feedback that this panel was hard to read --
	-- the GpsUnit itself also grew this pass (0.9x0.6 -> 1.7x1.05 studs), so
	-- these are now sized to actually take advantage of that extra room
	-- rather than leaving the same small text floating in a bigger panel.
	local appLabel = UiKit.body(panel, CityConfig.TAXI_COMPANY_NAME:upper(), 28, UiKit.STYLES.gold.fill)
	appLabel.Position = UDim2.new(0, 14, 0, 10)
	appLabel.Size = UDim2.new(1, -28, 0, 30)
	appLabel.TextXAlignment = Enum.TextXAlignment.Left

	local title = UiKit.label(panel, "Fare called in", 34, 1.5)
	title.Position = UDim2.new(0, 14, 0, 44)
	title.Size = UDim2.new(1, -28, 0, 40)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local detail = UiKit.body(panel, "4 min away · The Marrow", 24, Color3.fromRGB(190, 195, 205))
	detail.Position = UDim2.new(0, 14, 0, 88)
	detail.Size = UDim2.new(1, -28, 0, 30)
	detail.TextXAlignment = Enum.TextXAlignment.Left

	local acceptButton = UiKit.button(panel, "Accept", "", "10-4", UiKit.STYLES.gold, UDim2.new(1, -28, 0, 64))
	acceptButton.Position = UDim2.new(0, 14, 1, -74)

	-- Two paths to the same click (see DashScreenInput for why Roblox's own
	-- SurfaceGui input can't reach this screen from the driver's seat), so
	-- a flag guards against both firing.
	local acceptFired = false
	local dashClick: RBXScriptConnection
	local function accept()
		if acceptFired then
			return
		end
		acceptFired = true
		dashClick:Disconnect()
		onAccept()
		panel:Destroy()
	end
	dashClick = DashScreenInput.onClick(gpsUnit, gpsScreen, acceptButton, accept)
	acceptButton.MouseButton1Click:Connect(accept)
end

-- ===== The sequence =====

local function run()
	-- Not until the loading screen's finished: it holds until the city, the
	-- cab and this office are all actually loaded, and fades to black to
	-- hand over -- starting before that is how the opening used to get
	-- lost behind things still loading in.
	while not player:GetAttribute("LoadingScreenDone") do
		player:GetAttributeChangedSignal("LoadingScreenDone"):Wait()
	end

	local character = player.Character or player.CharacterAdded:Wait()
	local car, chassis, seat = waitForCar()
	local gpsUnit = car:WaitForChild("GpsUnit") :: BasePart
	local gpsScreen = gpsUnit:WaitForChild("GpsScreen") :: SurfaceGui

	-- Handed to CarSystems below so it can stop this (and restore the
	-- character's real transparency) when the player actually gets out of
	-- the car -- this connection is what's been keeping them invisible the
	-- whole time, so leaving it running forever would leave them invisible
	-- even standing outside on the sidewalk.
	local hideConnection = RunService.RenderStepped:Connect(hideCharacterLocally(character))

	-- The default nameplate/health billboard isn't a BasePart, so
	-- LocalTransparencyModifier above never touched it -- confirmed live it
	-- was floating in the middle of the dash view, right where the (now
	-- invisible) head still sits, since the camera parks essentially at the
	-- driver's own head position. A one-time property set holds fine here
	-- (unlike LocalTransparencyModifier, nothing else fights this one).
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	camera.CameraType = Enum.CameraType.Scriptable
	-- Roblox's own camera handling can flip CameraType back to Custom once,
	-- when the character is put into the car's seat -- confirmed live that
	-- when the seating landed after this point, the whole office scene played
	-- from a third-person shot of the parked taxi instead. The change signal
	-- fires before the next frame renders, so snapping it straight back
	-- keeps the shot without a visible jump.
	local cameraGuard = camera:GetPropertyChangedSignal("CameraType"):Connect(function()
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "IntroCutscene"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	-- Engine default is Global, which orders every descendant by its own
	-- absolute ZIndex rather than always drawing children above their own
	-- parent -- under that, DispatchPopup's ZIndex-15 background painted over
	-- its own (default ZIndex-1) text/button children, hiding them entirely.
	-- Sibling restores "children always draw above their parent" so UiKit's
	-- panel/label/button helpers (none of which set a child ZIndex) work as
	-- they assume.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	local fade = buildFade(gui)
	local top, bottom = buildLetterbox(gui)
	local subtitle = buildSubtitle(gui)
	local speakerTag = buildSpeakerTag(gui)

	local ambience = playAmbience(AMBIENCE_ID, 0.4, true)
	local score = playAmbience(SCORE_ID, 0.5, false)

	-- Stage 0: the hiring scene, in the office (see TaxiOfficeBuilder/
	-- CityConfig's OFFICE_* points). Four setups, not one continuous shot --
	-- a wide two-shot from the door, a push to a tighter angle across the
	-- desk for the opening beats, a closer over-the-desk angle for the
	-- nights/holidays back-and-forth, then a hard cut in close on the
	-- pegboard for the keys beat -- the way an actual scene would cut
	-- rather than dolly the whole way through.
	local doorCam = CFrame.lookAt(CityConfig.OFFICE_DOOR_POSITION + Vector3.new(0, 3.4, 0), CityConfig.OFFICE_DESK_POSITION + Vector3.new(0, 3, 0))
	local deskCam = CFrame.lookAt(CityConfig.OFFICE_DESK_POSITION + Vector3.new(0, 3.2, -3.5), CityConfig.OFFICE_DESK_POSITION + Vector3.new(0, 3, 1.2))
	local leanCam = CFrame.lookAt(CityConfig.OFFICE_DESK_POSITION + Vector3.new(-1.2, 2.9, -1.6), CityConfig.OFFICE_DESK_POSITION + Vector3.new(0, 3.4, 1.6))
	local closeCam = CFrame.lookAt(CityConfig.OFFICE_DESK_POSITION + Vector3.new(1.6, 3.6, -1.2), CityConfig.OFFICE_DESK_POSITION + Vector3.new(2.6, 3.2, 1.1))
	camera.CFrame = doorCam

	-- Lighting.Brightness/ExposureCompensation are global -- shared with the
	-- night street scene, which wants them dark and moody. TaxiOfficeBuilder's
	-- own fixtures alone couldn't overcome that global underexposure (still
	-- read as dark per direct user feedback even after doubling the fixture
	-- count/brightness); since the office and the street are never on screen
	-- at the same time, boosting these two specifically for the office scene
	-- and reverting them right before Stage A's street cut (once the screen's
	-- already faded to black, so the change itself is never visible) gets a
	-- genuinely bright office without touching the street's own mood at all.
	local officeOriginalBrightness = Lighting.Brightness
	local officeOriginalExposure = Lighting.ExposureCompensation
	local officeOriginalAmbient = Lighting.Ambient
	local officeOriginalOutdoorAmbient = Lighting.OutdoorAmbient
	-- Toned back down (2026-10-04) now that the room itself is painted light
	-- and has real ceiling lights (see TaxiOfficeBuilder) -- at the old
	-- values the close-up shots blew out to flat white. The street's
	-- Atmosphere haze is switched off for the office too: lit up by the
	-- boosted brightness, it read as thick white fog across every close shot.
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local officeOriginalDensity = atmosphere and atmosphere.Density
	if atmosphere then
		atmosphere.Density = 0
	end
	Lighting.Brightness = 2
	Lighting.ExposureCompensation = 0
	Lighting.Ambient = Color3.fromRGB(172, 166, 154)
	Lighting.OutdoorAmbient = Color3.fromRGB(172, 166, 154)

	TweenService:Create(fade, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
	setLetterbox(top, bottom, 0.09, 1.4)
	task.wait(1.4)

	TweenService:Create(camera, TweenInfo.new(2.6, Enum.EasingStyle.Sine), { CFrame = deskCam }):Play()
	task.wait(2.6)
	for i = 1, 4 do
		typeDialogueLine(subtitle, speakerTag, OFFICE_DIALOGUE[i])
	end

	camera.CFrame = leanCam
	task.wait(0.3)
	for i = 5, 8 do
		typeDialogueLine(subtitle, speakerTag, OFFICE_DIALOGUE[i])
	end

	camera.CFrame = closeCam
	task.wait(0.3)
	for i = 9, #OFFICE_DIALOGUE do
		typeDialogueLine(subtitle, speakerTag, OFFICE_DIALOGUE[i])
	end
	task.wait(0.6)

	TweenService:Create(fade, TweenInfo.new(0.6), { BackgroundTransparency = 0 }):Play()
	task.wait(0.6)

	-- Screen is fully black now -- safe to put the street's own darker
	-- Lighting back before Stage A ever becomes visible.
	Lighting.Brightness = officeOriginalBrightness
	Lighting.ExposureCompensation = officeOriginalExposure
	Lighting.Ambient = officeOriginalAmbient
	Lighting.OutdoorAmbient = officeOriginalOutdoorAmbient
	if atmosphere then
		atmosphere.Density = officeOriginalDensity
	end

	-- Stage A: a low, static shot on the grate, pushing slowly toward the
	-- parked car through the rising steam. The car (see CarBuilder/CityConfig)
	-- faces -Z, into the city, so a camera further up +Z at the default
	-- (unrotated) orientation -- which looks down -Z -- is already looking
	-- straight down the car's length toward its headlights and the city
	-- beyond; no extra rotation needed.
	local grateStart = CFrame.new(CityConfig.GRATE_POSITION + Vector3.new(0, 1.5, 14))
	local grateEnd = CFrame.new(CityConfig.GRATE_POSITION + Vector3.new(0, 1.8, 6))
	camera.CFrame = grateStart
	local rainRig, stopRain = buildRain()

	TweenService:Create(fade, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(camera, TweenInfo.new(4, Enum.EasingStyle.Sine), { CFrame = grateEnd }):Play()
	task.wait(4)

	-- Stage B: cut to the windshield, a slow creep forward that never
	-- actually goes anywhere -- the car stays parked (seat still Disabled)
	-- until the player accepts the job. No extra rotation here either: the
	-- camera should face the same way the chassis already does, which (now
	-- that the car faces -Z) drifts further into the city, not away from it.
	local driftDistance = 0
	local driving = true
	task.spawn(function()
		-- `driving` is checked right after waking from the wait, before
		-- writing to the camera -- not just at the top of the loop. Checking
		-- only at the top meant a `driving = false` set while this was
		-- suspended in Heartbeat:Wait() didn't cancel the write already in
		-- flight: it would still land, one frame late, and stomp on whatever
		-- camera cut ends this stage (the GPS screen cut, below). Racing an
		-- extra Heartbeat:Wait() on the outside to "wait it out" didn't
		-- reliably win either, since resumption order between two coroutines
		-- both waiting on the same event isn't guaranteed -- this is the
		-- actual fix, not a timing workaround.
		while true do
			local dt = RunService.Heartbeat:Wait()
			if not driving then
				break
			end
			driftDistance = math.min(driftDistance + dt * 3.5, 22)
			camera.CFrame = chassis.CFrame * CFrame.new(0, 2.6, -1.5 - driftDistance)
		end
	end)

	task.wait(0.6)
	for _, line in MONOLOGUE do
		typeLine(subtitle, line)
	end

	-- Cut to the dash: the fare call shows up on the GPS unit itself, not a
	-- floating screen overlay, so the camera needs to actually be looking at
	-- it. Framed from the chassis (reliable) but aimed at gpsUnit.Position
	-- read live, rather than a second guessed offset -- one guessed offset
	-- (gpsUnit's own placement on the dash, see CarBuilder) is enough.
	driving = false
	-- Square-on and close (2026-10-04): since the screen moved off to the
	-- right of the wheel, the old eye-position framing saw it small and at an
	-- angle. 1.2 studs out from the screen's own Front face (local -Z, which
	-- points back at the driver) keeps the camera inside the cabin.
	local gpsCam = CFrame.lookAt((gpsUnit.CFrame * CFrame.new(0, 0, -1.2)).Position, gpsUnit.Position, gpsUnit.CFrame.UpVector)
	camera.CFrame = gpsCam
	task.wait(0.4)

	-- Accepting the fare no longer unlocks driving by itself (see
	-- CarSystems/StartEngine) -- it's purely the narrative beat that ends
	-- the cutscene now, so the local flag below is all this needs to know
	-- the player's tapped it, no server round-trip to wait on.
	local accepted = false
	showFareOnGpsScreen(gpsUnit, gpsScreen, function()
		accepted = true
		acceptJobRemote:FireServer()
	end)

	repeat
		task.wait(0.1)
	until accepted

	stopRain()
	setLetterbox(top, bottom, 0, 0.5)
	tweenTextVisibility(subtitle, 1, 0.3)

	task.wait(0.6)
	-- The whole cutscene GUI's job ends here -- nothing after this point ever
	-- touches `gui`/`subtitle`/`speakerTag` again, so destroying it outright
	-- (rather than just fading it) is what actually gets rid of it, stroke
	-- included, instead of leaving an invisible-but-still-there Subtitle
	-- object sitting in PlayerGui for the rest of the session.
	gui:Destroy()

	-- The cutscene's own job ends here -- everything about actually being in
	-- the car for the rest of the session (the driver's-eye camera, A/D
	-- look-around while parked, the ignition, the dash screen's
	-- interactivity) belongs to CarSystems from this point on, not this
	-- script. Camera stays Scriptable (never handed back to Custom/
	-- third-person); CarSystems takes over writing to it every frame
	-- starting now.
	cameraGuard:Disconnect()
	CarSystems.start(car, chassis, seat, gpsScreen, character, hideConnection)
	-- The phone, minimap and navigation (see Hud) come up from here on, and
	-- getting back in the cab later is CarReentry's job.
	player:SetAttribute("IntroDone", true)

	if ambience.SoundId ~= "rbxassetid://0" then
		TweenService:Create(ambience, TweenInfo.new(2), { Volume = 0 }):Play()
	end
end

run()
