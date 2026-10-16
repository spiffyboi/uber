-- Who gets the menu's Load Game and Bug Test options. Everyone else can
-- only start a new game, and isn't saved (there'd be nothing to load it
-- with).
--
-- By Roblox user id, so changing a username doesn't change who's on the
-- list (looked up from the usernames on 2026-10-07).

local Testers = {}

local IDS = {
	[308989604] = "Secret_Scripter",
	[1481921271] = "LukasTheLazyBoi",
}

function Testers.isTester(player: Player): boolean
	return IDS[player.UserId] ~= nil
end

return Testers
