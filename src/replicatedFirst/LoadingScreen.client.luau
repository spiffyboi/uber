-- Runs from ReplicatedFirst, so it's up before almost anything else has
-- loaded or replicated -- exactly the tool for covering a loading gap, not
-- StarterPlayerScripts (too late) or waiting on the character (which is
-- itself gated on the world being ready, see GameStartup.server.luau).
--
-- In ordinary play this is mostly invisible insurance now that
-- GameStartup holds character spawning off until the world (road,
-- IntroSpawn, the player's own car) actually finishes building -- but it's
-- what covers that wait visually instead of a black-or-falling void, and it
-- still matters for however long InsertService:LoadAsset (the taxi mesh,
-- several traffic meshes) actually takes.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Parent = player:WaitForChild("PlayerGui")

local background = Instance.new("Frame")
background.Name = "Background"
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.new(0, 0, 0)
background.BorderSizePixel = 0
background.Parent = gui

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(0.8, 0, 0, 40)
title.Position = UDim2.new(0.5, 0, 0.55, 0)
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Font = Enum.Font.Oswald
title.TextSize = 28
title.TextColor3 = Color3.fromRGB(225, 225, 230)
title.Text = "MARROW HEIGHTS"
title.Parent = background

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Size = UDim2.new(0.8, 0, 0, 26)
subtitle.Position = UDim2.new(0.5, 0, 0.63, 0)
subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
subtitle.Font = Enum.Font.SourceSans
subtitle.TextSize = 18
subtitle.TextColor3 = Color3.fromRGB(160, 160, 170)
subtitle.Text = "Loading..."
subtitle.Parent = background

ReplicatedFirst:RemoveDefaultLoadingScreen()

-- Waits for the same things IntroCutscene.client.luau itself waits for
-- before it does anything visible (character, then the player's own car).
-- By the time both exist, IntroCutscene's own opaque fade Frame is already
-- up (it's created and set opaque before anything else in its `run()`), so
-- destroying this screen here hands off to that fade with no gap or flicker
-- in between -- never revealing a half-built world.
local character = player.Character or player.CharacterAdded:Wait()
workspace:WaitForChild(player.Name .. "_Car", 120)

gui:Destroy()
