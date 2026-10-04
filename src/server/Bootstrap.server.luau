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
