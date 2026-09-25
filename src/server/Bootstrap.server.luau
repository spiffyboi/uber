local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Everything else (CarSpawner, IntroCutscene, CarController) WaitForChild's
-- these, so it doesn't matter what order sibling Scripts in
-- ServerScriptService happen to run in.
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

-- Fired by the client once the player taps Accept on the dispatch popup at
-- the end of the intro cutscene: hands driving control of their car back to
-- them (see CarSpawner, which listens for this).
local acceptJob = Instance.new("RemoteEvent")
acceptJob.Name = "AcceptJob"
acceptJob.Parent = remotes
