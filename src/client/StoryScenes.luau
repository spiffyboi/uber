-- The story's cutscenes, shot inside and around the player's own cab
-- wherever it's parked (see Cutscene for the camera, bars and HUD):
--
--   gunstore -- chapter 7, inside Ironside Arms (a set under the street,
--               see GunStoreBuilder): Abe, the counter, a pistol on the
--               glass.
--   stash    -- chapter 7, back in the cab: the pistol goes behind the
--               driver's door panel.
--   holdup   -- chapter 8, by the pier: a gun at the back of the driver's
--               head; close-ups on the two faces, cut against inserts of
--               his hand creeping down to the door. One shot, the frame
--               white, then black. (After the end of Dog Day Afternoon.)
--   window   -- chapter 4, at the kerb on Quarry St: Dez, the lit window,
--               and what he says about the man behind it.
--   funeral  -- chapter 9, Gil's funeral (a set under Larkin & Sons): his
--               daughter at the piano, the driver shaking, going down.
--   alley    -- chapter 9, mid-fare: a glance down a side street at Dez.
--   robbery -- chapter 2, the dead end down by the wharf. Outside, the cab
--              under the lights as the engine dies; over Tommy's shoulder
--              as the knife comes up to the driver's neck; on the driver;
--              on Tommy; then outside again as he sprints off.
--   contact -- chapter 3, outside Voltage. Dez leans forward with the
--              money, takes the player's phone, types his own number into
--              it (close up on the screen), hands it back -- and the
--              player's phone opens on Contacts with him in it. Then
--              outside, watching him walk away.
--
-- Everything added here (the knife, the phone, the raised arm) is only on
-- this player's screen. Shots are placed relative to the driver's seat, so
-- they work wherever the cab stopped.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Joints = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Joints"))

local Cutscene = require(script.Parent.Cutscene)
local CarSystems = require(script.Parent.CarSystems)
local Screen = require(script.Parent.Screen)
local Phone = require(script.Parent.Phone)

local StoryScenes = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local RED = Color3.fromRGB(225, 70, 80)

-- ===== Finding things =====

-- The cab's "Cabin" point (see CarBuilder): where the driver's seat used
-- to be, before it was lowered so the driver's head cleared the roof. All
-- the shots below are measured from it.
local function seatCFrame(): CFrame
	local car = workspace:FindFirstChild(player.Name .. "_Car")
	local chassis = car and car.PrimaryPart
	local cabin = chassis and chassis:FindFirstChild("Cabin") :: Attachment?
	if cabin then
		return cabin.WorldCFrame
	end
	local seat = car and car:FindFirstChild("DriveSeat") :: BasePart?
	return if seat then seat.CFrame else CFrame.new()
end

-- A point relative to the cabin: +x toward the passenger side, +y up, +z
-- toward the back of the cab. (Measured live from there: the roof's ~3.8
-- up, the doors ~2 either side, the wheel ~2 ahead; the driver's head
-- about (0, 2.4, 0.2), the back-seat passenger's about (1.1, 2.5, 3).)
local function fromSeat(x: number, y: number, z: number): Vector3
	return (seatCFrame() * CFrame.new(x, y, z)).Position
end

local function passenger(name: string): Model?
	return workspace:FindFirstChild("Passenger_" .. name) :: Model?
end

local function partOf(model: Model?, name: string): BasePart?
	return model and model:FindFirstChild(name) :: BasePart?
end

-- Where the driver's head is -- or, if they're somehow not sat where they
-- should be, where it would be (so a shot never swings off after them).
local function driverHead(): Vector3
	local expected = fromSeat(0, 2.45, 0.2)
	local head = partOf(player.Character, "Head")
	if head and (head.Position - expected).Magnitude < 1.5 then
		return head.Position
	end
	return expected
end

local function headOf(model: Model?, fallback: Vector3): Vector3
	local head = partOf(model, "Head")
	return if head then head.Position else fallback
end

-- ===== Shots =====

local lastSeen: { [string]: any } = {}

-- Waits (a second and a half at most) for `who` to be out of the cab, and
-- notes which side of it they got out on, for the "away" shot.
local function waitUntilOut(who: Model?)
	lastSeen.away, lastSeen.side = nil, nil
	local started = os.clock()
	while os.clock() - started < 1.5 do
		local root = partOf(who, "HumanoidRootPart")
		if not root or not root.Parent then
			break
		end
		local x = seatCFrame():PointToObjectSpace(root.Position).X
		if math.abs(x) > 2.4 then
			lastSeen.side = math.sign(x)
			break
		end
		task.wait()
	end
end

local function shot(name: string, who: Model?)
	local interior = name ~= "outside" and name ~= "away"
	CarSystems.setDriverVisible(interior)
	if name == "outside" then
		-- From up the street, in front of the cab and off to the driver's
		-- side, slowly closing in.
		Cutscene.dolly(function()
			return CFrame.lookAt(fromSeat(-15, 3.5, -30), fromSeat(0.5, 1.2, 1.5))
		end, function()
			return CFrame.lookAt(fromSeat(-9, 2.6, -18), fromSeat(0.5, 1.4, 1.5))
		end, 7, 50)
	elseif name == "knife" then
		-- From the back seat, past the passenger's left shoulder (clear of
		-- their head, which sits behind the front passenger seat), at the
		-- back of the driver's neck.
		Cutscene.look(function()
			return fromSeat(-0.3, 3.0, 4.2)
		end, function()
			return driverHead() + Vector3.new(0, -0.5, 0)
		end, 50)
	elseif name == "driver" then
		-- On the driver, level with them, from the passenger seat beside.
		Cutscene.look(function()
			return fromSeat(1.8, 2.6, -1.4)
		end, function()
			return driverHead()
		end, 50)
	elseif name == "back" then
		-- From the front passenger seat, turned round to whoever's in the
		-- back.
		Cutscene.look(function()
			return fromSeat(1.5, 2.9, 0.6)
		end, function()
			return headOf(who, fromSeat(1.1, 2.5, 3))
		end, 52)
	elseif name == "away" then
		-- Outside, on the sidewalk side of the cab, a few steps out from
		-- the back door, watching whoever's just got out go -- whichever
		-- way they head. (Which side that is was worked out once they were
		-- out -- see waitUntilOut.)
		local side = lastSeen.side or 1
		Cutscene.look(function()
			return fromSeat(side * 6.5, 3.6, 2)
		end, function()
			local root = partOf(who, "HumanoidRootPart")
			if root and root.Parent then
				lastSeen.away = root.Position
			end
			return lastSeen.away or fromSeat(side * 2, 2, 3)
		end, 60)
	end
end

-- ===== Props and poses (this screen only) =====

-- Hides (or shows again) someone's body on this screen only.
local function setHidden(model: Model?, hidden: boolean)
	if not model then
		return
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "PlayersPhone" then
			part.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

-- Holds one of `model`'s arms out in front of them every frame until the
-- returned function's called: its shoulder (and a little of the elbow)
-- turned with Motor6D.Transform, which nothing else is driving on these
-- passengers.
local function raiseArm(model: Model?, side: string, lift: number): () -> ()
	local upper = partOf(model, side .. "UpperArm")
	local lower = partOf(model, side .. "LowerArm")
	local shoulder = upper and upper:FindFirstChild(side .. "Shoulder") :: Motor6D?
	local elbow = lower and lower:FindFirstChild(side .. "Elbow") :: Motor6D?
	if not shoulder then
		return function() end
	end
	local connection = RunService.Stepped:Connect(function()
		if shoulder.Parent then
			shoulder.Transform = CFrame.Angles(math.rad(lift), 0, 0)
		end
		if elbow and elbow.Parent then
			elbow.Transform = CFrame.Angles(math.rad(25), 0, 0)
		end
	end)
	return function()
		connection:Disconnect()
		if shoulder.Parent then
			shoulder.Transform = CFrame.new()
		end
		if elbow and elbow.Parent then
			elbow.Transform = CFrame.new()
		end
	end
end

local function weldTo(part: BasePart, to: BasePart, offset: CFrame)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CFrame = to.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = to
	weld.Part1 = part
	weld.Parent = part
end

-- A kitchen knife in `model`'s left fist (the hand nearer the driver, from
-- the back seat behind the front passenger), pointing on down the arm.
local function giveKnife(model: Model?)
	local hand = partOf(model, "LeftHand")
	if not hand or not model then
		return
	end
	local handle = Instance.new("Part")
	handle.Name = "Knife"
	handle.Size = Vector3.new(0.16, 0.5, 0.2)
	handle.Color = Color3.fromRGB(40, 28, 22)
	handle.Material = Enum.Material.Wood
	weldTo(handle, hand, CFrame.new(0, -0.3, 0))
	handle.Parent = model
	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = Vector3.new(0.05, 0.9, 0.2)
	blade.Color = Color3.fromRGB(200, 204, 210)
	blade.Material = Enum.Material.Metal
	blade.Reflectance = 0.3
	weldTo(blade, hand, CFrame.new(0, -0.98, 0.02))
	blade.Parent = model
end

-- The player's phone in Dez's hands, its screen showing a new contact
-- being typed in. Returns the phone and a function that types it.
local function phoneInHands(model: Model?, contact): (BasePart?, () -> ())
	local torso = partOf(model, "UpperTorso")
	if not torso or not model then
		return nil, function() end
	end
	local phone = Instance.new("Part")
	phone.Name = "PlayersPhone"
	phone.Size = Vector3.new(0.45, 0.85, 0.06)
	phone.Color = Color3.fromRGB(14, 14, 18)
	phone.Material = Enum.Material.SmoothPlastic
	-- Held out in front of his chest, screen turned back toward his face
	-- (and tipped up to it).
	weldTo(phone, torso, CFrame.new(0.25, 0.15, -1.05) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(math.rad(35), 0, 0))
	phone.Parent = model

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(225, 425)
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.Parent = phone
	local screen = Instance.new("Frame")
	screen.Size = UDim2.fromScale(1, 1)
	screen.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
	screen.BorderSizePixel = 0
	screen.Parent = gui
	local function label(y: number, size: number, color: Color3, text: string): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(16, y)
		l.Size = UDim2.new(1, -32, 0, size + 8)
		l.Font = Enum.Font.GothamBold
		l.TextSize = size
		l.TextColor3 = color
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = text
		l.Parent = screen
		return l
	end
	label(30, 18, Color3.fromRGB(150, 152, 165), "NEW CONTACT")
	label(80, 14, Color3.fromRGB(150, 152, 165), "Name")
	local nameField = label(100, 34, Color3.new(1, 1, 1), "")
	label(170, 14, Color3.fromRGB(150, 152, 165), "Number")
	local numberField = label(190, 30, Color3.new(1, 1, 1), "")
	local saved = label(300, 24, Color3.fromRGB(52, 199, 89), "")

	local function typeIt()
		for i = 1, #contact.name do
			nameField.Text = contact.name:sub(1, i) .. "|"
			task.wait(0.28)
		end
		nameField.Text = contact.name
		for i = 1, #contact.number do
			numberField.Text = contact.number:sub(1, i) .. "|"
			task.wait(0.16)
		end
		numberField.Text = contact.number
		task.wait(0.3)
		saved.Text = "✓ Saved"
	end
	return phone, typeIt
end

-- ===== The robbery =====

local robbery = { arm = nil :: (() -> ())? }

-- Plays the robbery up to the money being handed over. `say(line)` says a
-- line (and yields until it's done); `stillOn()` is false if the chapter's
-- ended under it.
function StoryScenes.robbery(lines, say: (any) -> (), stillOn: () -> boolean)
	local tommy = passenger("Tommy")
	Cutscene.begin()
	local current = nil
	for _, line in lines do
		if not stillOn() then
			break
		end
		if line.shot ~= current then
			current = line.shot
			if line.shot == "knife" and not robbery.arm then
				giveKnife(tommy)
				-- Forward and a little up: toward the driver's neck.
				robbery.arm = raiseArm(tommy, "Left", 110)
				Screen.flash(RED, 0.4, 1.4)
			end
			shot(if line.shot == "tommy" then "back" else line.shot, tommy)
		end
		say(line)
	end
end

-- He's taken it and he's gone: outside, watching him run, then back to
-- the road.
function StoryScenes.robberyEscape(stillOn: () -> boolean)
	local tommy = passenger("Tommy")
	if robbery.arm then
		robbery.arm()
		robbery.arm = nil
	end
	waitUntilOut(tommy)
	shot("away", tommy)
	task.wait(4.5)
	Cutscene.finish()
end

-- ===== Dez's number =====

local contactScene = { arm = nil :: (() -> ())?, phone = nil :: BasePart? }

-- Up to Dez handing the phone back; the player's own phone then opens on
-- Contacts with him in it (`showContacts` does that).
function StoryScenes.contact(step, say: (any) -> (), stillOn: () -> boolean, showContacts: () -> ())
	local dez = passenger("Dez")
	Cutscene.begin()
	local current = nil
	local typing = nil
	for _, line in step.lines do
		if not stillOn() then
			break
		end
		if line.typing and not contactScene.phone then
			local phone, typeIt = phoneInHands(dez, step.contact)
			contactScene.phone = phone
			contactScene.arm = raiseArm(dez, "Right", 60)
			typing = task.spawn(typeIt)
		end
		if line.shot ~= current then
			current = line.shot
			if line.shot == "phone" and contactScene.phone then
				local phone = contactScene.phone
				CarSystems.setDriverVisible(false)
				-- Square on to the screen and the right way up (its own up),
				-- from where his eyes are -- him hidden for this one shot, as
				-- the camera's practically in his face.
				setHidden(dez, true)
				Cutscene.shot(function()
					local eye = (phone.CFrame * CFrame.new(0, 0, -1.5)).Position
					return CFrame.lookAt(eye, phone.Position, phone.CFrame.UpVector)
				end, 45)
			elseif line.shot == "dez" then
				setHidden(dez, false)
				shot("back", dez)
			else
				shot(line.shot, dez)
			end
		end
		say(line)
	end
	-- Handed back.
	setHidden(dez, false)
	if contactScene.arm then
		contactScene.arm()
		contactScene.arm = nil
	end
	if contactScene.phone then
		contactScene.phone:Destroy()
		contactScene.phone = nil
	end
	if typing then
		task.cancel(typing)
	end
	if stillOn() then
		shot("driver", dez)
		showContacts()
	end
end

-- Whoever just got out (`name`), walking off; then back to the road.
function StoryScenes.walkAway(name: string)
	waitUntilOut(passenger(name))
	shot("away", passenger(name))
	task.wait(4)
	Cutscene.finish()
end

-- ===== The pistol =====

-- A plain, compact pistol built from parts, pointing along its own -Z.
-- Returns its body (the slide), which everything else is welded to.
local function makePistol(): BasePart
	local steel = Color3.fromRGB(36, 36, 40)
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		p.CFrame = offset
		return p
	end
	local slide = piece("Pistol", Vector3.new(0.2, 0.26, 1), CFrame.new(), steel, Enum.Material.Metal)
	slide.Anchored = true
	slide.Reflectance = 0.15
	local parts = {
		piece("PistolFrame", Vector3.new(0.18, 0.14, 0.8), CFrame.new(0, -0.18, 0.05), steel, Enum.Material.Metal),
		piece("PistolGrip", Vector3.new(0.18, 0.6, 0.3), CFrame.new(0, -0.45, 0.32) * CFrame.Angles(math.rad(-16), 0, 0), Color3.fromRGB(58, 40, 28), Enum.Material.Wood),
		piece("PistolGuard", Vector3.new(0.05, 0.2, 0.32), CFrame.new(0, -0.32, -0.08), steel, Enum.Material.Metal),
		piece("PistolMuzzle", Vector3.new(0.12, 0.12, 0.1), CFrame.new(0, 0.02, -0.52), Color3.fromRGB(12, 12, 14), Enum.Material.Metal),
	}
	for _, p in parts do
		p.CFrame = slide.CFrame * p.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = slide
		weld.Part1 = p
		weld.Parent = p
		p.Parent = slide
	end
	slide.Parent = workspace
	return slide
end

-- Moves an anchored pistol (with everything welded to it) to `cframe`.
local function placePistol(pistol: BasePart, cframe: CFrame)
	pistol.CFrame = cframe
end

-- Puts `pistol` in `model`'s left hand, pointing on down the arm.
local function pistolInHand(model: Model?): BasePart?
	local hand = partOf(model, "LeftHand")
	if not hand or not model then
		return nil
	end
	local pistol = makePistol()
	-- The hand's -Y runs down the fingers: point the barrel that way.
	pistol.CFrame = hand.CFrame * CFrame.new(0, -0.35, -0.05) * CFrame.Angles(math.rad(90), 0, 0)
	pistol.Anchored = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = pistol
	weld.Parent = pistol
	pistol.Parent = model
	return pistol
end

-- Smoothly carries an anchored part from `from()` to `to()` over `time`.
local function glide(target: BasePart, from: () -> CFrame, to: () -> CFrame, time: number)
	task.spawn(function()
		local started = os.clock()
		while target.Parent do
			local alpha = math.clamp((os.clock() - started) / time, 0, 1)
			alpha = alpha * alpha * (3 - 2 * alpha)
			target.CFrame = from():Lerp(to(), alpha)
			if alpha >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
	end)
end

-- Where the pistol sits in the driver's door pocket: low on the door
-- panel, under the window crank, right by where their left hand rests,
-- standing upright, side on to the driver, muzzle forward. (Found by
-- trying cameras live -- the driver's left hand sits at about
-- (-1.6, 0.3, -0.75), the door panel ~2 to the left.)
local function doorPocket(): CFrame
	return seatCFrame() * CFrame.new(-1.85, 0.75, -0.6)
end

-- An insert on that pocket: the door panel, the crank, the gun. Taken
-- from where the driver's sitting, so they're hidden for it -- anywhere
-- else in that footwell, their own arm or shoulder fills the frame
-- (confirmed live, twice).
local function doorShot()
	CarSystems.setDriverVisible(false)
	Cutscene.look(function()
		return fromSeat(-0.5, 1.7, 0.4)
	end, function()
		return doorPocket().Position
	end, 50)
end

-- ===== The gun store (chapter 7) =====

local Lighting = game:GetService("Lighting")
local CityConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("CityConfig"))

-- The store's under the street with the night's lighting outside: brighten
-- things for the inside shots, the same as the cab office in the intro
-- does, and put it all back after.
local savedLighting = nil
-- (`ambient`: the room's own fill light, if not the gun store's.)
local function storeLighting(on: boolean, ambient: Color3?, brightness: number?)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if on and not savedLighting then
		savedLighting = {
			Brightness = Lighting.Brightness,
			ExposureCompensation = Lighting.ExposureCompensation,
			Ambient = Lighting.Ambient,
			OutdoorAmbient = Lighting.OutdoorAmbient,
			Density = atmosphere and atmosphere.Density,
		}
		Lighting.Brightness = brightness or 1.5
		Lighting.ExposureCompensation = 0
		Lighting.Ambient = ambient or Color3.fromRGB(88, 80, 70)
		Lighting.OutdoorAmbient = ambient or Color3.fromRGB(88, 80, 70)
		if atmosphere then
			atmosphere.Density = 0
		end
	elseif not on and savedLighting then
		Lighting.Brightness = savedLighting.Brightness
		Lighting.ExposureCompensation = savedLighting.ExposureCompensation
		Lighting.Ambient = savedLighting.Ambient
		Lighting.OutdoorAmbient = savedLighting.OutdoorAmbient
		if atmosphere and savedLighting.Density then
			atmosphere.Density = savedLighting.Density
		end
		savedLighting = nil
	end
end

local store = { pistol = nil :: BasePart? }

local function abeHead(): Vector3
	local interior = workspace:FindFirstChild("GunStoreInterior")
	local abe = interior and interior:FindFirstChild("Abe")
	return headOf(abe, CityConfig.GUNSTORE_COUNTER + Vector3.new(1.2, 5.2, 2))
end

local function storeShot(name: string)
	local o, c = CityConfig.GUNSTORE_ORIGIN, CityConfig.GUNSTORE_COUNTER
	if name == "inside" then
		-- Just inside the door: the room, the counter, Abe behind it.
		Cutscene.dolly(function()
			return CFrame.lookAt(o + Vector3.new(-3, 5.4, -7.2), c + Vector3.new(0.5, 3.6, 1.6))
		end, function()
			return CFrame.lookAt(o + Vector3.new(-2, 5.2, -5.6), c + Vector3.new(0.8, 3.8, 1.6))
		end, 6, 60)
	elseif name == "abe" then
		Cutscene.look(function()
			return c + Vector3.new(-0.7, 5.0, -2.3)
		end, abeHead, 45)
	elseif name == "pov" then
		-- What the driver sees, across the counter.
		Cutscene.look(function()
			return c + Vector3.new(0.2, 5.1, -2.8)
		end, function()
			return abeHead() + Vector3.new(0, -0.4, 0)
		end, 55)
	elseif name == "counter" then
		-- Down on the glass, at whatever Abe's laid on it.
		Cutscene.look(function()
			return c + Vector3.new(1.0, 4.8, -2.3)
		end, function()
			return if store.pistol then store.pistol.Position else c + Vector3.new(0.2, 3.1, -0.2)
		end, 40)
	end
end

-- Abe, the counter, the pistol. Leaves the cutscene running (on black) for
-- the money changing hands and the next scene.
function StoryScenes.gunstore(step, say: (any) -> (), stillOn: () -> boolean)
	Cutscene.begin()
	Cutscene.black(true, 0.5)
	task.wait(0.6)
	storeLighting(true)
	CarSystems.setDriverVisible(false)
	local current = nil
	for i, line in step.lines do
		if not stillOn() then
			break
		end
		if line.action == "layGun" and not store.pistol then
			store.pistol = makePistol()
			placePistol(store.pistol, CFrame.new(CityConfig.GUNSTORE_COUNTER + Vector3.new(0.2, 3.12, -0.2)) * CFrame.Angles(0, math.rad(65), math.rad(90)))
		end
		if line.shot ~= current then
			current = line.shot
			storeShot(line.shot)
		end
		if i == 1 then
			Cutscene.black(false, 0.8)
		end
		say(line)
	end
	-- Out the door, to black.
	Cutscene.black(true, 0.6)
	task.wait(0.7)
	if store.pistol then
		store.pistol:Destroy()
		store.pistol = nil
	end
	storeLighting(false)
end

-- Back in the cab: the pistol goes in behind the door panel.
function StoryScenes.stash(step, say: (any) -> (), stillOn: () -> boolean)
	Cutscene.begin()
	storeLighting(false)
	-- Just above the pocket, out of the top of the shot, then slid down
	-- into it.
	local function abovePocket(): CFrame
		return seatCFrame() * CFrame.new(-1.85, 1.85, -0.5)
	end
	local pistol = makePistol()
	placePistol(pistol, abovePocket())
	local current = nil
	for i, line in step.lines do
		if not stillOn() then
			break
		end
		if line.shot ~= current then
			current = line.shot
			if line.shot == "door" then
				doorShot()
			else
				shot(line.shot)
			end
		end
		if line.action == "stash" then
			glide(pistol, abovePocket, doorPocket, 1.4)
		end
		if i == 1 then
			Cutscene.black(false, 0.8)
		end
		say(line)
	end
	pistol:Destroy()
	Cutscene.finish()
end

-- ===== The hold-up (chapter 8) =====
-- Staged after the end of Sidney Lumet's Dog Day Afternoon (from the clip
-- the user sent): tight close-ups on the two faces, cut back and forth, and
-- in between them inserts of the driver's left hand easing off the wheel
-- and down to the gun in the door -- the cuts quickening as it gets there.
-- One shot: the whole frame goes white, then black. Nothing shown of what
-- it does. Cold blue light in the cab throughout.

local holdup = {
	arm = nil :: (() -> ())?,
	theirs = nil :: BasePart?,
	mine = nil :: BasePart?,
	driverArm = nil :: (() -> ())?,
	light = nil :: BasePart?,
	insert = nil :: (() -> ())?,
}

-- The driver's left arm, from on the wheel (reach 0) down to the gun in
-- the door pocket (reach 1): shoulder and elbow turned every frame with
-- Motor6D.Transform, moving steadily toward wherever it was last told.
-- (Poses found live: they put the hand at about (-1.23, 1.44, -1.32) from
-- the cabin, on the wheel's rim, and (-1.76, 0.9, -0.68), at the pocket.)
local WHEEL_SHOULDER = CFrame.Angles(math.rad(40), math.rad(20), math.rad(30))
local WHEEL_ELBOW = CFrame.Angles(math.rad(75), 0, 0)
local POCKET_SHOULDER = CFrame.Angles(math.rad(10), math.rad(40), math.rad(20))
local POCKET_ELBOW = CFrame.Angles(math.rad(90), 0, 0)

-- Returns `setReach(to, seconds)`, `getReach()`, and a function that lets
-- the arm go.
local function driverArm(): ((number, number) -> (), () -> number, () -> ())
	local current, target, speed = 0, 0, 1
	local function setReach(to: number, seconds: number)
		target = to
		speed = math.abs(to - current) / math.max(seconds, 0.05)
	end
	local function getReach(): number
		return current
	end
	local character = player.Character
	local upper = partOf(character, "LeftUpperArm")
	local lower = partOf(character, "LeftLowerArm")
	local shoulder = upper and upper:FindFirstChild("LeftShoulder") :: Motor6D?
	local elbow = lower and lower:FindFirstChild("LeftElbow") :: Motor6D?
	local connection = RunService.Stepped:Connect(function(_, dt)
		current += math.clamp(target - current, -speed * dt, speed * dt)
		if shoulder and elbow then
			shoulder.Transform = WHEEL_SHOULDER:Lerp(POCKET_SHOULDER, current)
			elbow.Transform = WHEEL_ELBOW:Lerp(POCKET_ELBOW, current)
		end
	end)
	local function release()
		connection:Disconnect()
		if shoulder and shoulder.Parent then
			shoulder.Transform = CFrame.new()
		end
		if elbow and elbow.Parent then
			elbow.Transform = CFrame.new()
		end
	end
	return setReach, getReach, release
end

-- The driver's real arm is too big for an insert this close: from every
-- angle tried live (six of them) their sleeve filled the frame. So the hand
-- shots hide the driver and use a stand-in -- a sleeve and a hand, a size
-- smaller -- on the same path, from the wheel down to the gun. (Positions
-- from the cabin, like `fromSeat`.)
local INSERT_FROM = Vector3.new(-1.25, 1.45, -1.3)
local INSERT_TO = Vector3.new(-1.8, 1.0, -0.5)
-- (The elbow's out toward the door, so the sleeve runs off the top-left of
-- the frame rather than at the camera.)
local INSERT_ELBOW = Vector3.new(-2.0, 1.9, -0.1)

-- Puts the stand-in arm in, following `getReach()`; returns a function that
-- takes it away.
local function insertArm(getReach: () -> number): () -> ()
	local skin = partOf(player.Character, "LeftHand")
	local function piece(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = workspace
		return p
	end
	local hand = piece("InsertHand", Vector3.new(0.34, 0.42, 0.22), if skin then skin.Color else Color3.fromRGB(204, 142, 105), Enum.Material.SmoothPlastic)
	local sleeve = piece("InsertSleeve", Vector3.new(0.4, 1.3, 0.4), Color3.fromRGB(64, 58, 46), Enum.Material.Fabric)
	local connection = RunService.RenderStepped:Connect(function()
		local cabin = seatCFrame()
		local at = cabin * INSERT_FROM:Lerp(INSERT_TO, getReach())
		local up = (cabin * INSERT_ELBOW - at).Unit
		-- Fingers down toward the gun, the back of the hand to the cab.
		local cframe = CFrame.lookAt(at, at - cabin.RightVector, up)
		hand.CFrame = cframe
		sleeve.CFrame = cframe * CFrame.new(0, 0.21 + 0.65, 0)
	end)
	return function()
		connection:Disconnect()
		hand:Destroy()
		sleeve:Destroy()
	end
end

-- A cold blue light up by the roof, over the front seats.
local function moodLight(on: boolean)
	if on and not holdup.light then
		local part = Instance.new("Part")
		part.Name = "HoldupLight"
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CFrame = seatCFrame() * CFrame.new(0.6, 3.3, 0.6)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(120, 150, 255)
		light.Brightness = 1.4
		light.Range = 8
		light.Parent = part
		part.Parent = workspace
		holdup.light = part
	elseif not on and holdup.light then
		holdup.light:Destroy()
		holdup.light = nil
	end
end

-- The driver's turned round to the back seat, the pistol in front of them
-- pointing at the passenger's face. Where the camera is, and the gun.
local function aimFrom(gil: Model?): (Vector3, Vector3)
	local eye = fromSeat(0.45, 2.75, 0.7)
	return eye, headOf(gil, fromSeat(1.1, 2.5, 3))
end

local function muzzleFlash(at: Vector3)
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.5, 0.5, 0.5)
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 220, 140)
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CastShadow = false
	flash.Position = at
	local light = Instance.new("PointLight")
	light.Color = flash.Color
	light.Brightness = 10
	light.Range = 16
	light.Parent = flash
	flash.Parent = workspace
	task.delay(0.08, function()
		flash:Destroy()
	end)
end

local function holdupShot(name: string, gil: Model?)
	if name == "outside" then
		shot("outside")
	elseif name == "gun" then
		-- Gil's view, over the driver's shoulder: the gun at the back of his
		-- head.
		shot("knife", gil)
	elseif name == "driver" then
		-- Close on the driver's face, from just in front of them. (Any
		-- narrower than this and a head this size is all the frame is --
		-- seen in the first recording.)
		CarSystems.setDriverVisible(true)
		Cutscene.look(function()
			return fromSeat(0.55, 2.6, -1.5)
		end, driverHead, 58)
	elseif name == "gil" then
		-- Close on Gil's face, from the front passenger seat's shoulder.
		CarSystems.setDriverVisible(true)
		Cutscene.look(function()
			return fromSeat(0.5, 2.7, 1.4)
		end, function()
			return headOf(gil, fromSeat(1.1, 2.4, 3.1))
		end, 58)
	elseif name == "hand" then
		-- Looking down at the door pocket from about where the driver's
		-- chest is (they're hidden for it): the gun in it, and the
		-- stand-in hand coming down onto it.
		CarSystems.setDriverVisible(false)
		Cutscene.look(function()
			return fromSeat(-0.55, 1.65, 0.1)
		end, function()
			return fromSeat(-1.75, 0.85, -0.65)
		end, 55)
	elseif name == "fire" then
		-- Turned round, gun up, on Gil's face: the driver's own view, the
		-- pistol in the foreground with a little light on it so it reads.
		CarSystems.setDriverVisible(false)
		local mine = holdup.mine or makePistol()
		holdup.mine = mine
		if not mine:FindFirstChildOfClass("PointLight") then
			local glint = Instance.new("PointLight")
			glint.Color = Color3.fromRGB(255, 236, 210)
			glint.Brightness = 2
			glint.Range = 2.5
			glint.Parent = mine
		end
		local eye, face = aimFrom(gil)
		local look = CFrame.lookAt(eye, face)
		placePistol(mine, CFrame.lookAt((look * CFrame.new(-0.3, -0.38, -1.25)).Position, face))
		Cutscene.look(function()
			return eye
		end, function()
			return face
		end, 50)
	elseif name == "aftermath" then
		-- Outside: the cab, small and still by the railings, drawing away.
		CarSystems.setDriverVisible(false)
		Cutscene.dolly(function()
			return CFrame.lookAt(fromSeat(-22, 8.5, -30), fromSeat(0, 1.5, 1))
		end, function()
			return CFrame.lookAt(fromSeat(-28, 11, -40), fromSeat(0, 1.5, 1))
		end, 9, 45)
	end
end

function StoryScenes.holdup(step, say: (any) -> (), stillOn: () -> boolean)
	local gil = passenger("Gil")
	setHidden(gil, false)
	Cutscene.begin()
	moodLight(true)
	-- The pistol, in the door pocket where it went in chapter 7.
	holdup.mine = holdup.mine or makePistol()
	placePistol(holdup.mine :: BasePart, doorPocket())
	local setReach, getReach, release = driverArm()
	holdup.driverArm = release
	local current = nil
	local fromBlack = false
	for _, line in step.lines do
		if not stillOn() then
			break
		end
		if line.action == "raiseGun" and not holdup.theirs then
			holdup.theirs = pistolInHand(gil)
			holdup.arm = raiseArm(gil, "Left", 100)
		end
		if line.shot ~= current then
			current = line.shot
			if line.shot == "hand" and not holdup.insert then
				holdup.insert = insertArm(getReach)
			elseif line.shot ~= "hand" and holdup.insert then
				holdup.insert()
				holdup.insert = nil
			end
			holdupShot(line.shot, gil)
			if fromBlack then
				fromBlack = false
				Cutscene.black(false, 1.2)
			end
		end
		-- How long this one's on screen: a beat's as long as it says; a line
		-- about as long as it takes to say (see Screen.say).
		local length = line.beat or (2 + #(line.text or "") * 0.045)
		if line.reach then
			setReach(line.reach, length)
		end
		if line.action == "fire" then
			-- He gets two words out. Then the frame goes white, and black,
			-- and stays black. Silence.
			task.spawn(say, line)
			task.wait(0.9)
			local mine = holdup.mine :: BasePart
			muzzleFlash((mine.CFrame * CFrame.new(0, 0.02, -0.65)).Position)
			Screen.hush()
			Screen.flash(Color3.new(1, 1, 1), 1, 0.4)
			task.wait(0.12)
			Cutscene.black(true, 0)
			if holdup.arm then
				holdup.arm()
				holdup.arm = nil
			end
			setHidden(gil, true)
			if holdup.theirs then
				holdup.theirs:Destroy()
				holdup.theirs = nil
			end
			mine:Destroy()
			holdup.mine = nil
			release()
			holdup.driverArm = nil
			task.wait(2.5)
			fromBlack = true
		elseif line.beat then
			task.wait(line.beat)
		else
			say(line)
		end
	end
	for _, undo in { holdup.driverArm, holdup.insert } do
		if undo then
			undo()
		end
	end
	holdup.driverArm, holdup.insert = nil, nil
	if holdup.theirs then
		holdup.theirs:Destroy()
		holdup.theirs = nil
	end
	moodLight(false)
	Cutscene.finish()
end

-- ===== The window (chapter 4) =====
-- At the kerb on Quarry St, before Dez goes in: he has the driver look up at
-- a lit window on the building across the sidewalk, a man moving about
-- behind it, and talks about him. The window's put on the building wall on
-- the cab's kerb side, wherever the cab's stopped: a warm lamp-lit pane
-- with curtains either side and his silhouette crossing it. It stays up
-- while Dez is inside -- the shots flash in it, and then the lamp goes out
-- (see windowGunfire).

local window = { parts = nil :: { BasePart }?, figure = nil :: Model?, light = nil :: PointLight?, pane = nil :: BasePart?, connection = nil :: RBXScriptConnection? }

local function clearWindow()
	if window.connection then
		window.connection:Disconnect()
	end
	for _, p in window.parts or {} do
		p:Destroy()
	end
	if window.figure then
		window.figure:Destroy()
	end
	window.parts, window.figure, window.light, window.pane, window.connection = nil, nil, nil, nil, nil
end

-- Puts the window up on the wall beside the cab: returns its middle (or
-- nil if there's no wall within reach).
local function putUpWindow(): Vector3?
	clearWindow()
	local cabin = seatCFrame()
	local car = workspace:FindFirstChild(player.Name .. "_Car")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { car, player.Character, workspace:FindFirstChild("WeatherRig") }
	-- Third floor: about 16 up from the road, toward the kerb (+X is the
	-- passenger side, which is the kerb side).
	local origin = (cabin * CFrame.new(2, 16, 1)).Position
	local hit = workspace:Raycast(origin, cabin.RightVector * 60, params)
	if not hit then
		return nil
	end
	local normal = hit.Normal
	local face = CFrame.lookAt(hit.Position + normal * 0.08, hit.Position + normal * 2)
	local parts = {}
	local function piece(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cframe
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = workspace
		table.insert(parts, p)
		return p
	end
	-- (A part's front is its -Z: the face looks out, away from the wall.)
	local pane = piece("LitWindow", Vector3.new(4.2, 5, 0.1), face, Color3.fromRGB(255, 196, 120), Enum.Material.Neon)
	pane.Transparency = 0.1
	piece("WindowFrame", Vector3.new(4.8, 0.3, 0.3), face * CFrame.new(0, 2.65, -0.1), Color3.fromRGB(40, 34, 30), Enum.Material.Wood)
	piece("WindowFrame", Vector3.new(4.8, 0.3, 0.3), face * CFrame.new(0, -2.65, -0.1), Color3.fromRGB(40, 34, 30), Enum.Material.Wood)
	piece("WindowSill", Vector3.new(5, 0.25, 0.6), face * CFrame.new(0, -2.9, -0.3), Color3.fromRGB(70, 64, 58), Enum.Material.Concrete)
	for _, x in { -1.75, 1.75 } do
		piece("Curtain", Vector3.new(0.9, 5, 0.06), face * CFrame.new(x, 0, -0.06), Color3.fromRGB(150, 60, 50), Enum.Material.Fabric).Transparency = 0.15
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 120)
	light.Brightness = 1.5
	light.Range = 16
	light.Parent = pane

	-- His silhouette: head and shoulders against the lamp, a little in
	-- front of the pane, drifting back and forth across it.
	local figure = Instance.new("Model")
	figure.Name = "WindowFigure"
	local shadow = Color3.fromRGB(14, 12, 12)
	local head = Instance.new("Part")
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.1, 1.1, 0.05)
	local body = Instance.new("Part")
	body.Size = Vector3.new(2, 2.6, 0.05)
	for _, p in { head, body } do
		p.Color = shadow
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = false
		p.Parent = figure
	end
	figure.Parent = workspace
	local started = os.clock()
	window.connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		-- Wanders, stops a while in the middle (as if looking out), wanders.
		local x = math.sin(t * 0.45) * 1.3 * (0.4 + 0.6 * math.abs(math.sin(t * 0.17)))
		local at = face * CFrame.new(x, -0.6, -0.03)
		body.CFrame = at * CFrame.new(0, -0.9, 0)
		head.CFrame = at * CFrame.new(0, 1.05, 0)
	end)
	window.parts, window.figure, window.light, window.pane = parts, figure, light, pane
	return pane.Position
end

function StoryScenes.window(step, say: (any) -> (), stillOn: () -> boolean)
	local dez = passenger("Dez")
	local windowAt = putUpWindow()
	Cutscene.begin()
	local current = nil
	for _, line in step.lines do
		if not stillOn() then
			break
		end
		if line.shot ~= current then
			current = line.shot
			if line.shot == "kerb" then
				-- From across the road: the cab at the kerb under the lamp-lit
				-- window.
				CarSystems.setDriverVisible(false)
				Cutscene.dolly(function()
					return CFrame.lookAt(fromSeat(-16, 3, -10), fromSeat(4, 7, 1))
				end, function()
					return CFrame.lookAt(fromSeat(-13, 2.6, -7), fromSeat(4, 7.5, 1))
				end, 8, 55)
			elseif line.shot == "driver" then
				-- On the driver: eyes front, not answering.
				CarSystems.setDriverVisible(true)
				Cutscene.look(function()
					return fromSeat(0.55, 2.6, -1.5)
				end, driverHead, 52)
			elseif line.shot == "back" then
				shot("back", dez)
			elseif line.shot == "window" then
				-- Up through the passenger window at it, from the driver's seat.
				CarSystems.setDriverVisible(false)
				Cutscene.look(function()
					return fromSeat(0.4, 2.6, 0.4)
				end, function()
					return windowAt or fromSeat(12, 16, 1)
				end, 34)
			end
		end
		if line.beat then
			task.wait(line.beat)
		else
			say(line)
		end
	end
	Cutscene.finish()
	-- The window stays up while he's inside; gone a while after anyway.
	local parts = window.parts
	task.delay(90, function()
		if window.parts == parts then
			clearWindow()
		end
	end)
end

-- The shots, upstairs: the window flashes, the figure's gone, and a moment
-- later the lamp goes out.
function StoryScenes.windowGunfire()
	if not window.pane then
		return
	end
	if window.connection then
		window.connection:Disconnect()
		window.connection = nil
	end
	local pane, light, figure = window.pane, window.light, window.figure
	task.spawn(function()
		for _ = 1, 3 do
			if pane.Parent then
				pane.Color = Color3.fromRGB(255, 250, 235)
				if light then
					light.Brightness = 8
				end
			end
			task.wait(0.06)
			if pane.Parent then
				pane.Color = Color3.fromRGB(255, 196, 120)
				if light then
					light.Brightness = 1.5
				end
			end
			task.wait(0.25 + math.random() * 0.3)
		end
		if figure then
			figure:Destroy()
			window.figure = nil
		end
		task.wait(1.5)
		if pane.Parent then
			pane.Color = Color3.fromRGB(30, 26, 24)
			pane.Material = Enum.Material.SmoothPlastic
			if light then
				light.Enabled = false
			end
		end
	end)
end

-- ===== The funeral (chapter 9) =====
-- An evening service at Larkin & Sons (the set's under the chapel -- see
-- ChapelBuilder). The driver at the back, alone in the last pew. The
-- minister says a few words; Gil's daughter Nina walks up to the piano and
-- plays. Her hands, her face, Gil's photograph -- and the driver, starting
-- to shake: his hands, a flash of the cab's empty back seat, the room
-- tilting, and he goes down in the aisle. Then the floor, and Teddy, Gil's
-- old friend, kneeling over him. Then back out in the cab, rain on the
-- glass.
--
-- The driver here is a copy of the player's own character, sat in the pew
-- (the real one's still out in the cab). Everything done to the people in
-- the room is on this screen only, and put back afterwards.

-- The piano piece and a heartbeat under the shaking. Asset ids still to be
-- found on the Creator Store and checked (never guessed): 0 = none yet.
local PIANO_MUSIC_ID = "rbxassetid://0"
local HEARTBEAT_ID = "rbxassetid://0"
local WALK_ANIMATION_ID = "rbxassetid://913402848" -- the same walk the passengers use

local ROWS = { 3.5, 0.5, -2.5, -5.5, -8.5, -11.5 } -- as ChapelBuilder.ROWS
local SEAT_TOP = 1.75

local chapel = {
	double = nil :: Model?,
	shake = 0,
	connections = {} :: { RBXScriptConnection },
	blur = nil :: BlurEffect?,
	grade = nil :: ColorCorrectionEffect?,
	music = nil :: Sound?,
	heartbeat = nil :: Sound?,
	restore = {} :: { () -> () },
}

-- A point in the chapel, from the middle of its floor.
local function inChapel(x: number, y: number, z: number): Vector3
	return CityConfig.CHAPEL_ORIGIN + Vector3.new(x, 0.5 + y, z)
end

local function chapelPerson(name: string): Model?
	local interior = workspace:FindFirstChild("ChapelInterior")
	local people = interior and interior:FindFirstChild("People")
	return people and people:FindFirstChild(name) :: Model?
end

-- Notes where `model` is and how its joints are bent, so it can all be put
-- back at the end.
local function remember(model: Model?)
	if not model then
		return
	end
	local pivot = model:GetPivot()
	local unbend = Joints.snapshot(model)
	table.insert(chapel.restore, function()
		unbend()
		if model.Parent then
			model:PivotTo(pivot)
			setHidden(model, false)
		end
	end)
end

local function bend(model: Model, joints: { [string]: CFrame })
	Joints.bend(model, joints)
end

local SIT = { LeftHip = CFrame.Angles(math.rad(90), 0, 0), RightHip = CFrame.Angles(math.rad(90), 0, 0), LeftKnee = CFrame.Angles(math.rad(-90), 0, 0), RightKnee = CFrame.Angles(math.rad(-90), 0, 0) }
local STAND = { LeftHip = CFrame.Angles(math.rad(-90), 0, 0), RightHip = CFrame.Angles(math.rad(-90), 0, 0), LeftKnee = CFrame.Angles(math.rad(90), 0, 0), RightKnee = CFrame.Angles(math.rad(90), 0, 0) }

-- How high a rig's root is over a seat it's sat on, and over the floor
-- standing (the same sums as ChapelBuilder.sitDown).
local function heights(model: Model): (number, number)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local upperLeg = model:FindFirstChild("LeftUpperLeg") :: BasePart?
	local standing = humanoid.HipHeight + root.Size.Y / 2
	local hip = if upperLeg then upperLeg.Size.Y else 1
	-- Root above hip joint, from the standing pose: standing height less
	-- the legs.
	local lowerLeg = model:FindFirstChild("LeftLowerLeg") :: BasePart?
	local foot = model:FindFirstChild("LeftFoot") :: BasePart?
	local legs = hip + (if lowerLeg then lowerLeg.Size.Y else 1) + (if foot then foot.Size.Y else 0.3)
	return standing - legs + 0.35, standing
end

-- The copy of the player's character, sat at the aisle end of the back row
-- on the left, hands on his knees.
local function makeDouble(): Model?
	local character = player.Character
	if not character then
		return nil
	end
	local was = character.Archivable
	character.Archivable = true
	local double = character:Clone()
	character.Archivable = was
	if not double then
		return nil
	end
	double.Name = "DriverDouble"
	for _, d in double:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ForceField") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Weld") and d.Name == "SeatWeld" then
			d:Destroy()
		end
	end
	local humanoid = double:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
		humanoid.EvaluateStateMachine = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	double.Parent = workspace
	local sat = heights(double)
	bend(double, SIT)
	-- Forearms forward, hands resting on the knees.
	bend(double, { LeftShoulder = CFrame.Angles(math.rad(35), 0, 0), RightShoulder = CFrame.Angles(math.rad(35), 0, 0), LeftElbow = CFrame.Angles(math.rad(40), 0, 0), RightElbow = CFrame.Angles(math.rad(40), 0, 0) })
	local spot = inChapel(-3.4, SEAT_TOP + sat, ROWS[6])
	double:PivotTo(CFrame.lookAt(spot, spot + Vector3.new(0, 0, 1)))
	double:SetAttribute("Seat", double:GetPivot())
	return double
end

local function partPos(model: Model?, name: string, fallback: Vector3): Vector3
	local p = partOf(model, name)
	return if p then p.Position else fallback
end

-- A little camera shake, growing with how badly he's shaking: slow drift
-- plus a tremor.
local function jitter(): CFrame
	local s = chapel.shake
	if s <= 0 then
		return CFrame.new()
	end
	local t = os.clock()
	local a = math.rad(1.4) * s
	return CFrame.Angles(math.noise(t * 1.3, 1) * a + math.noise(t * 9, 5) * a * 0.35, math.noise(t * 1.1, 2) * a + math.noise(t * 8, 6) * a * 0.35, math.noise(t * 0.9, 3) * a * 0.6)
end

local function chapelLook(eye: () -> Vector3, target: () -> Vector3, fov: number, roll: (() -> number)?)
	Cutscene.shot(function()
		local cf = CFrame.lookAt(eye(), target()) * jitter()
		if roll then
			cf *= CFrame.Angles(0, 0, roll())
		end
		return cf
	end, fov)
end

-- Nina gets up from the front row and walks to the piano bench (over
-- `seconds`), sits, and plays: arms out to the keys, keys going down.
local function ninaWalk(seconds: number)
	local nina = chapelPerson("Nina")
	if not nina then
		return
	end
	local sat, standing = heights(nina)
	local humanoid = nina:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local track = nil
	if animator then
		local animation = Instance.new("Animation")
		animation.AnimationId = WALK_ANIMATION_ID
		track = animator:LoadAnimation(animation)
		track.Looped = true
	end
	bend(nina, STAND)
	local path = {
		inChapel(3.3, standing, ROWS[1] + 1.3),
		inChapel(4.2, standing, 5.6),
		inChapel(6.1, standing, 7.5),
	}
	task.spawn(function()
		if track then
			track:Play(0.1, 1, 0.75)
		end
		local legs = { (path[2] - path[1]).Magnitude, (path[3] - path[2]).Magnitude }
		local total = legs[1] + legs[2]
		local started = os.clock()
		local walkTime = seconds * 0.8
		while nina.Parent do
			local d = math.clamp((os.clock() - started) / walkTime, 0, 1) * total
			local from, to, along
			if d <= legs[1] then
				from, to, along = path[1], path[2], d / legs[1]
			else
				from, to, along = path[2], path[3], (d - legs[1]) / legs[2]
			end
			local at = from:Lerp(to, along)
			nina:PivotTo(CFrame.lookAt(at, at + (to - from) * Vector3.new(1, 0, 1)))
			if d >= total then
				break
			end
			RunService.RenderStepped:Wait()
		end
		if track then
			track:Stop(0.2)
		end
		-- Sat on the bench, facing the keys.
		bend(nina, SIT)
		local seatAt = inChapel(6.9, 1.6 + sat, 7.5)
		nina:PivotTo(CFrame.lookAt(seatAt, seatAt + Vector3.new(1, 0, 0)))
	end)
end

-- Her arms out to the keys, rocking a little as she plays, and the keys
-- going down under them.
local function ninaPlays()
	local nina = chapelPerson("Nina")
	local interior = workspace:FindFirstChild("ChapelInterior")
	local piano = interior and interior:FindFirstChild("Piano")
	local keys = piano and piano:FindFirstChild("Keys")
	local joints = {}
	for _, name in { "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow" } do
		joints[name] = Joints.find(nina, name)
	end
	local keyParts = keys and keys:GetChildren() or {}
	local nextKey = 0
	table.insert(chapel.connections, RunService.Stepped:Connect(function()
		local t = os.clock()
		for side, sign in { Left = 1, Right = -1 } do
			local shoulder, elbow = joints[side .. "Shoulder"], joints[side .. "Elbow"]
			if shoulder then
				shoulder.Transform = CFrame.Angles(math.rad(62 + math.sin(t * 3 + sign) * 4), math.rad(sign * 12), 0)
			end
			if elbow then
				elbow.Transform = CFrame.Angles(math.rad(25 + math.sin(t * 4 + sign) * 6), 0, 0)
			end
		end
		if t > nextKey and #keyParts > 0 then
			nextKey = t + 0.12 + math.random() * 0.25
			local key = keyParts[math.random(1, #keyParts)] :: BasePart
			local rest = key:GetAttribute("Rest")
			if typeof(rest) == "CFrame" then
				key.CFrame = rest * CFrame.new(0, -0.05, 0)
				task.delay(0.2, function()
					key.CFrame = rest
				end)
			end
		end
	end))
end

local function playSound(id: string, volume: number, looped: boolean): Sound?
	if id == "rbxassetid://0" then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Looped = looped
	s.Parent = game:GetService("SoundService")
	s:Play()
	return s
end

-- The shaking: his body trembling in the pew (more and more), the picture
-- blurring and draining of colour, his heart going.
local function startShaking()
	local double = chapel.double
	chapel.blur = Instance.new("BlurEffect")
	chapel.blur.Size = 0
	chapel.blur.Parent = Lighting
	chapel.grade = Instance.new("ColorCorrectionEffect")
	chapel.grade.Parent = Lighting
	local shoulders = {}
	for _, name in { "LeftWrist", "RightWrist", "Neck" } do
		local joint = Joints.find(double, name)
		if joint then
			table.insert(shoulders, joint)
		end
	end
	table.insert(chapel.connections, RunService.RenderStepped:Connect(function()
		local s = chapel.shake
		local t = os.clock()
		if double and double.Parent and double:GetAttribute("Falling") ~= true then
			local seat = double:GetAttribute("Seat")
			if typeof(seat) == "CFrame" then
				local a = 0.035 * s
				double:PivotTo(seat * CFrame.new(math.noise(t * 14, 1) * a, math.noise(t * 13, 2) * a * 0.5, 0) * CFrame.Angles(math.noise(t * 2, 3) * 0.05 * s, 0, math.noise(t * 11, 4) * 0.03 * s))
			end
			for _, joint in shoulders do
				local b = math.rad(9) * s
				joint.Transform = CFrame.Angles(math.noise(t * 18, joint.Name:len()) * b, math.noise(t * 16, 7) * b, math.noise(t * 17, 8) * b)
			end
		end
		if chapel.blur then
			chapel.blur.Size = math.max(0, s - 0.35) * 18
		end
		if chapel.grade then
			chapel.grade.Saturation = -0.6 * s
			chapel.grade.Contrast = 0.25 * s
			chapel.grade.Brightness = -0.08 * s
		end
		if chapel.heartbeat then
			chapel.heartbeat.Volume = s * 0.9
			chapel.heartbeat.PlaybackSpeed = 1 + s * 0.5
		end
	end))
	chapel.heartbeat = playSound(HEARTBEAT_ID, 0, true)
end

-- He goes: out of the pew, sideways into the aisle. Over `seconds`.
local function collapse(seconds: number)
	local double = chapel.double
	if not double then
		return
	end
	double:SetAttribute("Falling", true)
	local from = double:GetPivot()
	local floorAt = inChapel(-1.5, 0.75, ROWS[6] - 0.3)
	local to = CFrame.lookAt(floorAt, floorAt + Vector3.new(0, 0, 1)) * CFrame.Angles(0, 0, math.rad(-88))
	task.spawn(function()
		local started = os.clock()
		while double.Parent do
			local a = math.clamp((os.clock() - started) / seconds, 0, 1)
			double:PivotTo(from:Lerp(to, a * a))
			if a >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
	end)
end

local function chapelShot(name: string, step, say)
	local double = chapel.double
	local function doubleHead(): Vector3
		return partPos(double, "Head", inChapel(-3.4, 4.8, ROWS[6]))
	end
	if name == "outside" then
		shot("outside")
	elseif name == "arrive" then
		-- Still on black: the camera's already in the room where the next
		-- shot starts, so the lighting has a few seconds to come up. (Cut
		-- straight in, the room stayed unlit for its first ten seconds or so
		-- -- seen in three recordings: Roblox works a room's light out
		-- around the camera, a bit at a time, once the camera gets there.)
		CarSystems.setDriverVisible(false)
		Cutscene.look(function()
			return inChapel(0.6, 6.6, -16.2)
		end, function()
			return inChapel(0, 3.6, 12)
		end, 50)
	elseif name == "back" then
		-- From the back of the room, over the last pews, down the aisle to
		-- the casket. Drifting in.
		CarSystems.setDriverVisible(false)
		Cutscene.black(false, 2)
		Cutscene.dolly(function()
			return CFrame.lookAt(inChapel(0.6, 6.6, -16.2), inChapel(0, 3.6, 12))
		end, function()
			return CFrame.lookAt(inChapel(0.4, 6.1, -14), inChapel(0, 3.6, 12))
		end, 12, 50)
	elseif name == "minister" then
		chapelLook(function()
			return inChapel(-1.8, 5.4, 6.4)
		end, function()
			return partPos(chapelPerson("Minister"), "Head", inChapel(-4, 5.6, 11.7))
		end, 32)
	elseif name == "driver" then
		-- On him, in the back pew, from just in front and to his left.
		chapelLook(function()
			return doubleHead() + Vector3.new(0.7, 0.15, 2.2)
		end, doubleHead, 40)
	elseif name == "walk" then
		chapelLook(function()
			return inChapel(-1.2, 4.6, -1.5)
		end, function()
			return partPos(chapelPerson("Nina"), "Head", inChapel(4, 3, 5))
		end, 42)
	elseif name == "keys" then
		-- Over her shoulder, down at her hands on the keys.
		chapelLook(function()
			return inChapel(6.4, 5.1, 5.8)
		end, function()
			return inChapel(8.15, 2.7, 7.6)
		end, 40)
	elseif name == "nina" then
		chapelLook(function()
			return inChapel(8.3, 3.7, 5.0)
		end, function()
			return partPos(chapelPerson("Nina"), "Head", inChapel(6.9, 3.6, 7.5))
		end, 36)
	elseif name == "photo" then
		Cutscene.dolly(function()
			return CFrame.lookAt(inChapel(-6.6, 4.7, 7.6), inChapel(-6.8, 4.7, 11.8))
		end, function()
			return CFrame.lookAt(inChapel(-6.7, 4.7, 9.6), inChapel(-6.8, 4.7, 11.8))
		end, 6, 34)
	elseif name == "hands" then
		chapelLook(function()
			local l = partPos(double, "LeftHand", inChapel(-3.8, 2.4, -10.4))
			local r = partPos(double, "RightHand", inChapel(-3, 2.4, -10.4))
			return (l + r) / 2 + Vector3.new(0.9, 1.0, 1.5)
		end, function()
			local l = partPos(double, "LeftHand", inChapel(-3.8, 2.4, -10.4))
			local r = partPos(double, "RightHand", inChapel(-3, 2.4, -10.4))
			return (l + r) / 2
		end, 38)
	elseif name == "memory" then
		-- Up out of the room: the cab's back seat, empty, the white of the
		-- flash -- and Gil's last two words.
		Screen.flash(Color3.new(1, 1, 1), 0.9, 0.5)
		Cutscene.look(function()
			return fromSeat(0.3, 2.6, 0.5)
		end, function()
			return fromSeat(1.1, 2.0, 3.0)
		end, 55)
		task.spawn(function()
			task.spawn(say, { speaker = "GIL", text = "What are you--" })
			task.wait(0.55)
			Screen.hush()
		end)
	elseif name == "pov" then
		-- His view, down the room to the piano, the room starting to tip.
		setHidden(double, true)
		chapelLook(doubleHead, function()
			return inChapel(7.6, 3.2, 7.5)
		end, 52, function()
			return chapel.shake * 0.22 + math.sin(os.clock() * 1.7) * 0.05 * chapel.shake
		end)
	elseif name == "collapse" then
		-- Still his view: dropping, rolling over onto the floor.
		setHidden(double, true)
		local from = doubleHead()
		local started = os.clock()
		collapse(step.beat or 1.4)
		Cutscene.shot(function()
			local a = math.clamp((os.clock() - started) / (step.beat or 1.4), 0, 1)
			a = a * a
			local eye = from:Lerp(inChapel(-1.4, 0.8, ROWS[6] - 0.8), a)
			local target = inChapel(7.6, 3.2, 7.5):Lerp(inChapel(-4, 0.3, 0), a)
			return CFrame.lookAt(eye, target) * CFrame.Angles(0, 0, a * math.rad(80) + 0.2) * jitter()
		end, 52)
		if chapel.music then
			-- The music goes far away.
			local muffle = Instance.new("EqualizerSoundEffect")
			muffle.HighGain = -40
			muffle.MidGain = -18
			muffle.LowGain = 0
			muffle.Parent = chapel.music
			TweenService:Create(chapel.music, TweenInfo.new(3), { Volume = 0.15 }):Play()
		end
	elseif name == "black" then
		Cutscene.black(true, 0.2)
	elseif name == "floor" then
		-- Lying in the aisle, looking up. Teddy kneeling over him.
		chapel.shake = 0.15
		setHidden(double, true)
		local teddy = chapelPerson("Teddy")
		if teddy and teddy:GetAttribute("Kneeling") ~= true then
			teddy:SetAttribute("Kneeling", true)
			local _, standing = heights(teddy)
			bend(teddy, STAND)
			bend(teddy, { Waist = CFrame.Angles(math.rad(-40), 0, 0), Neck = CFrame.Angles(math.rad(-20), 0, 0) })
			local spot = inChapel(-1.0, standing - 0.3, ROWS[6] + 0.9)
			teddy:PivotTo(CFrame.lookAt(spot, spot + Vector3.new(-0.3, 0, -1)))
		end
		if chapel.blur then
			chapel.blur.Size = 6
		end
		chapelLook(function()
			return inChapel(-1.4, 0.9, ROWS[6] - 0.6)
		end, function()
			return partPos(teddy, "Head", inChapel(-1, 5, ROWS[6] + 0.9))
		end, 55, function()
			return 0.25
		end)
		Cutscene.black(false, 1.5)
	elseif name == "cab" then
		-- Back out in the cab, at the kerb, in the rain. Hands on the wheel.
		for _, connection in chapel.connections do
			connection:Disconnect()
		end
		chapel.connections = {}
		chapel.shake = 0
		for _, effect in { chapel.blur, chapel.grade } do
			if effect then
				effect:Destroy()
			end
		end
		chapel.blur, chapel.grade = nil, nil
		storeLighting(false)
		CarSystems.setDriverVisible(true)
		Cutscene.look(function()
			return fromSeat(0.55, 2.6, -1.5)
		end, driverHead, 58)
		Cutscene.black(false, 1.5)
	end
end

local function cleanUpChapel()
	for _, connection in chapel.connections do
		connection:Disconnect()
	end
	chapel.connections = {}
	for _, thing in { chapel.blur, chapel.grade, chapel.music, chapel.heartbeat, chapel.double } do
		if thing then
			thing:Destroy()
		end
	end
	chapel.blur, chapel.grade, chapel.music, chapel.heartbeat, chapel.double = nil, nil, nil, nil, nil
	chapel.shake = 0
	for _, undo in chapel.restore do
		undo()
	end
	chapel.restore = {}
	local teddy = chapelPerson("Teddy")
	if teddy then
		teddy:SetAttribute("Kneeling", nil)
	end
	storeLighting(false)
end

function StoryScenes.funeral(step, say: (any) -> (), stillOn: () -> boolean)
	Cutscene.begin()
	for _, name in { "Nina", "Teddy" } do
		remember(chapelPerson(name))
	end
	local current = nil
	local inside = false
	for _, line in step.lines do
		if not stillOn() then
			break
		end
		if line.shot ~= "outside" and line.shot ~= "memory" and line.shot ~= "cab" and not inside then
			-- Through the doors: to black, light the room, sit him down.
			inside = true
			Cutscene.black(true, 0.6)
			task.wait(0.7)
			storeLighting(true, Color3.fromRGB(64, 56, 50), 1)
			chapel.double = makeDouble()
			if line.shot ~= "arrive" then
				Cutscene.black(false, 1.2)
			end
		end
		if line.shake then
			if chapel.shake == 0 then
				startShaking()
			end
			-- Up to the new level over the shot.
			local from, to = chapel.shake, line.shake
			local started = os.clock()
			local length = line.beat or 2
			task.spawn(function()
				while chapel.shake ~= to and os.clock() - started < length + 0.5 do
					chapel.shake = from + (to - from) * math.clamp((os.clock() - started) / length, 0, 1)
					task.wait()
				end
			end)
		end
		if line.action == "ninaWalk" then
			ninaWalk(line.beat or 4)
			task.delay((line.beat or 4) * 0.85, ninaPlays)
		elseif line.action == "music" then
			chapel.music = playSound(PIANO_MUSIC_ID, 0.7, false)
		end
		if line.shot ~= current then
			current = line.shot
			chapelShot(line.shot, line, say)
		end
		if line.beat then
			task.wait(line.beat)
		else
			say(line)
		end
	end
	cleanUpChapel()
	Cutscene.finish()
end

-- ===== The side street (chapter 9) =====
-- Halfway through an ordinary fare, passing a side street: the camera --
-- the driver's eyes -- slides off the road and down it. Dez, on his knees
-- on the sidewalk under a lamp; a man behind him with a gun out. A flash.
-- Dez goes down. And the eyes go back to the road. No bars, the HUD stays
-- up: it's a glance, not a scene. (The people were set out by the server --
-- see StoryService; what happens to them is on this screen only.)
-- `lines` (Lou's, from the ride's `alley`) are said over it, each `at` its
-- time in seconds from the start -- he never stops talking, and never sees.
function StoryScenes.alley(alley, lines, say: (any) -> ())
	local dez = workspace:FindFirstChild("Passenger_AlleyDez") :: Model?
	local man = workspace:FindFirstChild("Passenger_AlleyMan1") :: Model?
	local lou = passenger("Lou")
	local function dezHead(): Vector3
		return partPos(dez, "Head", alley.dez + Vector3.new(0, 2.2, 0))
	end
	-- Down the side street from the junction, and back up it.
	local down = alley.side
	local toStreet = -down

	local started = os.clock()
	Cutscene.begin()

	-- A key light on the three of them, from the street side, on this
	-- screen only: under just the wall lamp they were black shapes (first
	-- recording).
	local key = Instance.new("Part")
	key.Name = "AlleyKeyLight"
	key.Size = Vector3.new(0.2, 0.2, 0.2)
	key.Transparency = 1
	key.Anchored = true
	key.CanCollide = false
	key.CanQuery = false
	key.CFrame = CFrame.new(alley.dez + toStreet * 5 + Vector3.new(0, 5, 0))
	local keyLight = Instance.new("PointLight")
	keyLight.Color = Color3.fromRGB(255, 196, 140)
	keyLight.Brightness = 5
	keyLight.Range = 20
	keyLight.Parent = key
	key.Parent = workspace
	-- And a little one on Dez's face, for the close-up (his skin's dark and
	-- the night's darker: at 2.2 the key alone left him a black shape --
	-- second recording).
	local faceLight = Instance.new("PointLight")
	faceLight.Color = Color3.fromRGB(255, 214, 170)
	faceLight.Brightness = 3
	faceLight.Range = 7
	local facePart = key:Clone()
	facePart.Name = "AlleyFaceLight"
	for _, child in facePart:GetChildren() do
		child:Destroy()
	end
	facePart.CFrame = CFrame.new(alley.dez + toStreet * 2.2 + Vector3.new(0, 3, 0))
	faceLight.Parent = facePart
	facePart.Parent = key

	-- Lou, talking straight through it.
	task.spawn(function()
		for _, line in lines do
			local wait = (line.at or 0) - (os.clock() - started)
			if wait > 0 then
				task.wait(wait)
			end
			say(line)
		end
	end)

	local function fire()
		local hand = partOf(man, "RightHand")
		muzzleFlash(if hand then hand.Position + (alley.dez - hand.Position).Unit * 0.8 else alley.shooter + Vector3.new(0, 4, 0))
		Screen.flash(Color3.fromRGB(255, 240, 220), 0.35, 0.3)
		if dez then
			-- Forward, onto his face, toward the street.
			local from = dez:GetPivot()
			local to = from * CFrame.new(0, -1.1, -1.4) * CFrame.Angles(math.rad(-82), 0, 0)
			task.spawn(function()
				local fall = os.clock()
				while dez.Parent do
					local a = math.clamp((os.clock() - fall) / 0.35, 0, 1)
					dez:PivotTo(from:Lerp(to, a * a))
					if a >= 1 then
						break
					end
					RunService.RenderStepped:Wait()
				end
			end)
		end
	end

	-- 1. The glance: the driver's eyes sliding off the road, down the side
	-- street, and pushing in.
	CarSystems.setDriverVisible(false)
	local glance = os.clock()
	local baseFov = camera.FieldOfView
	Cutscene.shot(function()
		local a = math.clamp((os.clock() - glance) / 0.8, 0, 1)
		a = a * a * (3 - 2 * a)
		-- From just above and ahead of the driver's eyes, so it's out over
		-- the door rather than into it.
		local eye = fromSeat(0, 2.95, -0.5)
		local road = eye + seatCFrame().LookVector * 30
		return CFrame.lookAt(eye, road:Lerp(dezHead(), a))
	end, baseFov)
	task.spawn(function()
		while os.clock() - glance < 2.3 do
			local z = math.clamp((os.clock() - glance - 0.5) / 1.6, 0, 1)
			camera.FieldOfView = baseFov + (40 - baseFov) * z * z * (3 - 2 * z)
			RunService.RenderStepped:Wait()
		end
	end)
	task.wait(2.3)

	-- 2. From out in the side street: the lamp, Dez on his knees on the
	-- sidewalk, the two of them stood over him. (Close enough to read --
	-- from the corner they were specks.)
	local function wideEye(): Vector3
		return alley.dez + toStreet * 8 + alley.travel * 7 + Vector3.new(0, 3.6, 0)
	end
	Cutscene.look(wideEye, function()
		return alley.dez + down * 2 + Vector3.new(0, 2.4, 0)
	end, 50)
	task.wait(3)

	-- 3. Close on Dez. He's looking up the street -- at the cab.
	Cutscene.look(function()
		return dezHead() + toStreet * 3.4 + alley.travel * 0.6 + Vector3.new(0, 0.15, 0)
	end, dezHead, 38)
	task.wait(2.4)

	-- 4. The driver, frozen.
	CarSystems.setDriverVisible(true)
	Cutscene.look(function()
		return fromSeat(0.55, 2.6, -1.5)
	end, driverHead, 50)
	task.wait(1.8)

	-- 5. Over the gunman's shoulder: the gun at the back of Dez's head.
	CarSystems.setDriverVisible(false)
	Cutscene.look(function()
		local behind = (alley.shooter - alley.dez) * Vector3.new(1, 0, 1)
		local away = if behind.Magnitude > 0.1 then behind.Unit else down
		-- Back and up off his shoulder, so his head's at the edge of the
		-- frame rather than filling it.
		return alley.shooter + away * 4 + alley.travel * 2.4 + Vector3.new(0, 6.4, 0)
	end, dezHead, 40)
	task.wait(2)

	-- 6. Wide again. The flash. He goes down.
	Cutscene.look(wideEye, function()
		return alley.dez + down * 2 + Vector3.new(0, 2, 0)
	end, 50)
	task.wait(0.6)
	fire()
	task.wait(2.6)

	-- 7. Lou in the back, chatting away, none the wiser.
	shot("back", lou)
	task.wait(3.2)

	-- 8. The driver, eyes back on the road. Then back to driving.
	CarSystems.setDriverVisible(true)
	Cutscene.look(function()
		return fromSeat(0.55, 2.6, -1.5)
	end, driverHead, 52)
	-- Hold until Lou's said his last.
	local last = lines[#lines]
	local lastEnds = if last then (last.at or 0) + 2 + #(last.text or "") * 0.045 else 0
	task.wait(math.max(2.5, lastEnds - (os.clock() - started)))
	key:Destroy()
	camera.FieldOfView = baseFov
	Cutscene.finish()
end

-- Something went wrong or the chapter was abandoned mid-scene.
function StoryScenes.abort()
	for _, scene in { robbery, contactScene } do
		if scene.arm then
			scene.arm()
			scene.arm = nil
		end
	end
	if contactScene.phone then
		contactScene.phone:Destroy()
		contactScene.phone = nil
	end
	for _, undo in { holdup.arm, holdup.driverArm, holdup.insert } do
		if undo then
			undo()
		end
	end
	holdup.arm, holdup.driverArm, holdup.insert = nil, nil, nil
	for _, prop in { holdup.theirs, holdup.mine, store.pistol } do
		if prop then
			prop:Destroy()
		end
	end
	holdup.theirs, holdup.mine, store.pistol = nil, nil, nil
	moodLight(false)
	cleanUpChapel()
	clearWindow()
	storeLighting(false)
	Cutscene.finish()
end

return StoryScenes
