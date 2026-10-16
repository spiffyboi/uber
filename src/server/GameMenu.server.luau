-- The menu's answer (see Menu.client): New Game, Load Game or a Bug Test
-- from a chosen chapter. PlayerData does the setting up, and turns down
-- anything a player isn't allowed (see Testers).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local menuChoice = remotes:WaitForChild("MenuChoice") :: RemoteEvent

menuChoice.OnServerEvent:Connect(function(player, mode, options)
	if typeof(mode) ~= "string" then
		return
	end
	local clean = {}
	if typeof(options) == "table" then
		clean.chapter = if typeof(options.chapter) == "number" then options.chapter else nil
		clean.toldVance = options.toldVance == true
	end
	if not PlayerData.begin(player, mode, clean) then
		-- Not allowed (or already answered): say so, and the menu stays up.
		player:SetAttribute("MenuRefused", (player:GetAttribute("MenuRefused") or 0) + 1)
	end
end)
