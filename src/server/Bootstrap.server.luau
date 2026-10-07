local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Everything else (CarSpawner, IntroCutscene, CarController) WaitForChild's
-- these, so it doesn't matter what order sibling Scripts in
-- ServerScriptService happen to run in.
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

-- Fired by the client once the player taps Accept on the dispatch popup at
-- the end of the intro cutscene. Doesn't unlock driving by itself -- that's
-- the ignition key's job now (a physical ProximityPrompt on the car itself,
-- see CarBuilder/CarSpawner -- fires straight into the seat server-side, no
-- remote needed for that one) -- this is just the narrative beat that ends
-- the cutscene and hands the dash screen over to CarSystems.
local acceptJob = Instance.new("RemoteEvent")
acceptJob.Name = "AcceptJob"
acceptJob.Parent = remotes

-- Fired by the client (CarSystems) as part of the space-bar exit sequence,
-- if the engine happened to be running -- turns it back off (re-Disables
-- the DriveSeat) so the car sits there properly parked/off once the player
-- gets out, the same as it started.
local stopEngine = Instance.new("RemoteEvent")
stopEngine.Name = "StopEngine"
stopEngine.Parent = remotes

-- Fares (see FareService): the server tells the client where its fare
-- stands -- the job, its passenger, whether they're aboard, what it paid,
-- and any new job on offer -- whenever any of that changes.
local fareUpdate = Instance.new("RemoteEvent")
fareUpdate.Name = "FareUpdate"
fareUpdate.Parent = remotes

-- And the client asks things of it: take or turn down the job on offer, or
-- say the passenger's finished talking and is ready to get out.
local fareAction = Instance.new("RemoteEvent")
fareAction.Name = "FareAction"
fareAction.Parent = remotes

-- The story (see StoryService): the server says which chapter and step the
-- player's on and how it's going; the client asks to start a chapter, says
-- when everyone's finished talking, and passes on the player's choices.
local storyUpdate = Instance.new("RemoteEvent")
storyUpdate.Name = "StoryUpdate"
storyUpdate.Parent = remotes

local storyAction = Instance.new("RemoteEvent")
storyAction.Name = "StoryAction"
storyAction.Parent = remotes
