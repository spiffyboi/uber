local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

-- Carried over from Brew a Potion! as a starting point -- the funnel steps
-- below (JOINED/STARTED_GAME/TUTORIAL_FIRST) and the "gold" naming in the
-- economy-flow calls further down are that game's, not this one's. Rename/add
-- funnel steps to match this game's own onboarding, and swap "gold" for
-- whatever this game's currency is called before relying on the Economy page.
--
-- What players do, for Creator Hub > Analytics: the onboarding funnel (how far a
-- new player gets through their first session, and where they stop) and every
-- currency earned or spent (the Economy page). Roblox only counts each funnel
-- step once per player, so logging a step again (a second save, a replayed
-- tutorial) is harmless. Every call is wrapped: analytics must never break play.
local Analytics = {}

-- The funnel's steps, in order. The tutorial's own steps (TutorialScript) come
-- after these, then TUTORIAL_DONE once Binks' last line is finished.
Analytics.JOINED = 1
Analytics.STARTED_GAME = 2
Analytics.TUTORIAL_FIRST = 3

local function try(what: string, fn: () -> ())
	local ok, problem = pcall(fn)
	if not ok then
		warn(`[Analytics] {what} failed: {problem}`)
	end
end

function Analytics.onboarding(player: Player, step: number, name: string)
	try("onboarding step", function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
	end)
end

-- Gold moves are added up and sent as one event per kind every FLUSH_SECONDS, rather
-- than one per harvest: a busy farm (workers picking and selling all day) earns gold
-- many times a minute, and Roblox limits how many analytics events a server may send.
local FLUSH_SECONDS = 30

type Pending = { amount: number, balance: number }
-- player -> "Source|Gameplay|Sell potions" -> running total
local pending: { [Player]: { [string]: Pending } } = {}

local function queue(player: Player, flow: string, amount: number, balance: number, transaction: string, sku: string?)
	if amount <= 0 then
		return
	end
	local byKey = pending[player]
	if not byKey then
		byKey = {}
		pending[player] = byKey
	end
	local key = `{flow}|{transaction}|{sku or ""}`
	local entry = byKey[key]
	if entry then
		entry.amount += amount
		entry.balance = balance
	else
		byKey[key] = { amount = amount, balance = balance }
	end
end

local function flush(player: Player)
	local byKey = pending[player]
	pending[player] = nil
	if not byKey then
		return
	end
	for key, entry in byKey do
		local flow, transaction, sku = string.match(key, "^(%a+)|(%a+)|(.*)$")
		if flow and transaction then
			try("gold event", function()
				AnalyticsService:LogEconomyEvent(
					player,
					if flow == "Source" then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink,
					"Gold",
					entry.amount,
					entry.balance,
					transaction,
					if sku ~= "" then sku else nil
				)
			end)
		end
	end
end

task.spawn(function()
	while true do
		task.wait(FLUSH_SECONDS)
		for player in pending do
			flush(player)
		end
	end
end)
Players.PlayerRemoving:Connect(flush)

-- Gold coming in. `transaction` is an Enum.AnalyticsEconomyTransactionType name
-- ("Gameplay", "Shop", "TimedReward"...); `sku` names what it was for.
function Analytics.goldIn(player: Player, amount: number, balance: number, transaction: string, sku: string?)
	queue(player, "Source", amount, balance, transaction, sku)
end

-- Gold going out (see goldIn).
function Analytics.goldOut(player: Player, amount: number, balance: number, transaction: string, sku: string?)
	queue(player, "Sink", amount, balance, transaction, sku)
end

function Analytics.custom(player: Player, name: string, value: number?)
	try("custom event", function()
		AnalyticsService:LogCustomEvent(player, name, value or 1)
	end)
end

local function onJoined(player: Player)
	Analytics.onboarding(player, Analytics.JOINED, "Joined")
end
Players.PlayerAdded:Connect(onJoined)
for _, player in Players:GetPlayers() do
	task.spawn(onJoined, player)
end

return Analytics
