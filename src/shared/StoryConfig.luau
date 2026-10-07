-- The story: chapters that come in between the ordinary fares, in which an
-- ordinary cab driver gets pulled, a ride at a time, into the war between
-- the Marrow's two crews:
--   the Kesting crew -- Kesting St, everything from Harrow down to Linden
--                       (green); the player's way in is Dez
--   the Quarry crew  -- Quarry St, everything south of Linden (maroon);
--                       Vance does their talking
-- Both crews, everyone in them and everything they say are made up for
-- this game.
--
-- Story chapters are kept apart from ordinary fares: they're started from
-- the Story app on the phone once they unlock (so many ordinary fares after
-- the chapter before), nothing else is offered while one's on, and they're
-- marked in red rather than Dispatch gold.
--
-- Each chapter is a list of steps, run in order by StoryService on the
-- server and shown by Story.client:
--   text     -- a text arrives on the phone ({from, text})
--   pickup   -- someone's waiting at `spot`; pull up beside them and stop
--   ride     -- drive whoever's aboard (or whatever's in the trunk) to
--               `spot`. `lines` are said along the way (`at` = how far
--               through, 0..1; `late` ones are said before arriving ends
--               the step, even if the cab gets there early), `arrival` once
--               stopped. `texts` arrive on the phone along the way.
--               `timeLimit` makes it a race (run out and it starts over).
--   talk     -- lines said while stopped
--   choice   -- the player picks what to say; remembered as `key`
--   robbery  -- the passenger takes `take` dollars and runs
--   errand   -- the passenger gets out, goes inside, comes back after
--               `seconds` and gets back in (`gunfire` = it goes badly)
--   collect  -- stop at `spot` to pick something up (no passenger)
--   handoff  -- stop at `spot` and hand it to someone waiting there
--   dropoff  -- the passenger gets out and pays: `pay` dollars, or the
--               meter for the last ride (`pay = "meter"`) plus `tip`
--   ending   -- a title card ({title, subtitle})
-- Any step (or line) with `when = {choice = key, is = value}` only happens
-- if that's what was chosen.
--
-- All dialogue is original to this game.

local CityConfig = require(script.Parent.CityConfig)
local FareConfig = require(script.Parent.FareConfig)

local StoryConfig = {}

StoryConfig.PART_TITLE = "Part One: Night Shift"
StoryConfig.COLOR = Color3.fromRGB(225, 70, 80)

-- ===== People =====

StoryConfig.CHARACTERS = {
	ray = {
		name = "Ray",
		look = { skin = Color3.fromRGB(140, 100, 75), shirt = Color3.fromRGB(52, 70, 56), pants = Color3.fromRGB(40, 40, 48) },
	},
	tommy = {
		name = "Tommy",
		look = { skin = Color3.fromRGB(225, 195, 165), shirt = Color3.fromRGB(96, 96, 100), pants = Color3.fromRGB(34, 36, 44) },
	},
	dez = {
		name = "Dez",
		look = { skin = Color3.fromRGB(90, 65, 50), shirt = Color3.fromRGB(40, 104, 60), pants = Color3.fromRGB(22, 22, 26) },
	},
	vance = {
		name = "Vance",
		look = { skin = Color3.fromRGB(205, 165, 130), shirt = Color3.fromRGB(118, 26, 36), pants = Color3.fromRGB(30, 30, 34) },
	},
	runner = {
		name = "Runner",
		look = { skin = Color3.fromRGB(185, 150, 122), shirt = Color3.fromRGB(40, 104, 60), pants = Color3.fromRGB(60, 56, 50) },
	},
}

-- ===== Places =====

local function spot(name: string, x: number, index: number, side: number, along: number?)
	local standing, stop = FareConfig.kerbSpot(x, index, side, along)
	return { name = name, standing = standing, stop = stop }
end

local ASHBY, MARROW, CALLOWAY = -300, CityConfig.MAIN_AVENUE_X, 300

local PLACES = {
	halcyon = spot("Halcyon House, Marrow St", MARROW, 8, 1, -6),
	rayHome = spot("Ashby Ave, across from the Majestic", ASHBY, 26, 1),
	parkGate = spot("Marrow Park, Marrow St", MARROW, 7, -1, 4),
	emberEnd = spot("Calloway Ave, down by Ember St", CALLOWAY, 29, -1),
	velvet = spot("the Velvet, Marrow St", MARROW, 4, 1),
	ashbyHouse = spot("Ashby Ave at Kesting St", ASHBY, 5, -1),
	mirage = spot("Club Mirage, Calloway Ave", CALLOWAY, 7, -1),
	hollis = spot("The Hollis, Calloway Ave", CALLOWAY, 25, -1),
	quarryCorner = spot("Marrow St at Quarry St", MARROW, 23, 1),
	towers = spot("Marrow Towers, Marrow St", MARROW, 12, -1),
	langford = spot("Langford Tower, Ashby Ave", ASHBY, 8, 1),
	bellmore = spot("The Bellmore, Marrow St", MARROW, 9, 1),
	quarryCalloway = spot("Calloway Ave at Quarry St", CALLOWAY, 23, 1),
	halo = spot("Halo, Ashby Ave", ASHBY, 2, 1),
}
StoryConfig.PLACES = PLACES

local TOLD = { choice = "toldVance", is = true }
local KEPT_QUIET = { choice = "toldVance", is = false }

-- ===== Chapters =====

StoryConfig.CHAPTERS = {
	-- 1. Ray: the first fare of the night, called in at the end of the
	-- intro. Small talk most of the way; the last stretch is where it turns.
	{
		id = "ray",
		title = "First Fare",
		blurb = "Ray, from Halcyon House to Ashby Ave.",
		unlockAfter = 0,
		startsFromIntro = true,
		steps = {
			{ type = "text", from = "Dispatch", text = "Your fare's waiting outside Halcyon House on Marrow St. Name's Ray. Going to Ashby Ave." },
			{ type = "pickup", who = "ray", spot = PLACES.halcyon },
			{
				type = "ride",
				spot = PLACES.rayHome,
				meter = true,
				lines = {
					{ at = 0, speaker = "RAY", text = "Evening. Ashby Avenue, down by the Majestic, if you know it." },
					{ at = 0, speaker = "YOU", text = "I know it." },
					{ at = 0.12, speaker = "RAY", text = "Rain finally quit, huh? All week it's been coming down sideways." },
					{ at = 0.2, speaker = "YOU", text = "City looks cleaner wet." },
					{ at = 0.27, speaker = "RAY", text = "Ha. From in here, maybe." },
					{ at = 0.36, speaker = "RAY", text = "My little girl's got her school play Friday. She's a tree. Practised all week -- just stands in the kitchen with her arms up." },
					{ at = 0.46, speaker = "RAY", text = "Best tree you ever saw, I'm telling you." },
					{ at = 0.6, speaker = "RAY", text = "We're getting out after that. Me, her, her mother. Her aunt's got room upstate.", late = true },
					{ at = 0.68, speaker = "RAY", text = "Last spring the crews on Kesting got into it over a corner. Shooting out of cars in the middle of the afternoon.", late = true },
					{ at = 0.78, speaker = "RAY", text = "My boy was walking home from the bodega. Nineteen. Never ran with anybody. Wrong block, that's all.", late = true },
					{ at = 0.86, speaker = "YOU", text = "...I'm sorry.", late = true },
					{ at = 0.92, speaker = "RAY", text = "Yeah. Everybody's sorry.", late = true },
				},
				arrival = {
					{ speaker = "RAY", text = "This is me. Keep the change." },
					{ speaker = "RAY", text = "And drive careful round here, alright? This city don't care who you are." },
				},
			},
			{ type = "dropoff", pay = "meter", tip = 10, note = "Ray -- Ashby Ave" },
			{ type = "text", from = "Dispatch", text = "Ray's home. Good first ride. Open Dispatch on your phone when you want the next one." },
		},
	},

	-- 2. Tommy: a kid from the park who wants the dark end of Calloway.
	{
		id = "robbed",
		title = "Last Stop",
		blurb = "A late pickup at Marrow Park, going somewhere nobody goes.",
		unlockAfter = 1,
		unlockText = { from = "Dispatch", text = "Late one for you if you want it. Kid called from the payphone at Marrow Park. Wants the far end of Calloway. Your call -- it's in your Story app." },
		steps = {
			{ type = "pickup", who = "tommy", spot = PLACES.parkGate },
			{
				type = "ride",
				spot = PLACES.emberEnd,
				meter = true,
				lines = {
					{ at = 0, speaker = "TOMMY", text = "Calloway. All the way down, past the warehouses." },
					{ at = 0.05, speaker = "YOU", text = "Ember Street? Not much down there this time of night." },
					{ at = 0.12, speaker = "TOMMY", text = "That's kind of the point." },
					{ at = 0.25, speaker = "TOMMY", text = "You like this? Driving round all night, people throwing up in your back seat?" },
					{ at = 0.34, speaker = "YOU", text = "It pays. Mostly." },
					{ at = 0.42, speaker = "TOMMY", text = "Mostly. Ha. Everything's mostly." },
					{ at = 0.58, speaker = "TOMMY", text = "My mom drove nights. Laundry van for the hospital. Twenty-two years.", late = true },
					{ at = 0.68, speaker = "TOMMY", text = "Know what she's got to show for it? A bad back and me.", late = true },
					{ at = 0.8, speaker = "TOMMY", text = "...Up here. Pull in by the fence.", late = true },
				},
				arrival = {
					{ speaker = "TOMMY", text = "Kill the engine." },
					{ speaker = "YOU", text = "Meter says--" },
					{ speaker = "TOMMY", text = "I know what the meter says." },
				},
			},
			{
				type = "robbery",
				take = 40,
				lines = {
					{ speaker = "TOMMY", text = "Don't turn round. Don't make it a thing. Cash box. All of it." },
					{ speaker = "YOU", text = "Easy. Easy. It's yours." },
					{ speaker = "TOMMY", text = "...Sorry, man. I swear I'm sorry." },
				},
			},
			{ type = "text", from = "Dispatch", text = "Heard on the radio somebody rolled a cab down on Ember. That you? You alright? No shame in calling it a night." },
			{ type = "text", from = "Mom", text = "Just saw something on the news about a robbery. Tell me you're okay." },
		},
	},

	-- 3. Dez: the Kesting crew fixes what happened. Now you owe them.
	{
		id = "favours",
		title = "Favours",
		blurb = "Someone on Kesting wants to make Ember St right.",
		unlockAfter = 1,
		unlockText = { from = "Unknown number", text = "Heard about Ember St. That's not how things go on our streets. Come by the Velvet on Marrow St. I'll find you." },
		steps = {
			{ type = "pickup", who = "dez", spot = PLACES.velvet },
			{
				type = "ride",
				spot = PLACES.ashbyHouse,
				lines = {
					{ at = 0, speaker = "DEZ", text = "You're the one got rolled on Ember. Relax. I'm not here to rob you too." },
					{ at = 0.04, speaker = "DEZ", text = "Ashby. Corner of Kesting." },
					{ at = 0.12, speaker = "YOU", text = "Who are you?" },
					{ at = 0.2, speaker = "DEZ", text = "Dez. People round here know me. Now you do too." },
					{ at = 0.33, speaker = "DEZ", text = "Kid who took your money. Tommy. Runs little jobs for the Quarry crew, trying to get noticed." },
					{ at = 0.48, speaker = "DEZ", text = "He picked you up on our side of Linden. What happens on our side, we answer for." },
					{ at = 0.62, speaker = "YOU", text = "I didn't ask anybody to answer for anything.", late = true },
					{ at = 0.72, speaker = "DEZ", text = "You didn't have to. That's how it works.", late = true },
				},
				arrival = {
					{ speaker = "DEZ", text = "Wait here. Engine running. Couple of minutes." },
				},
			},
			{ type = "errand", seconds = 18, objective = "Wait for Dez. Keep the engine running." },
			{ type = "talk", lines = { { speaker = "DEZ", text = "Alright. Club Mirage, over on Calloway." } } },
			{
				type = "ride",
				spot = PLACES.mirage,
				lines = {
					{ at = 0, speaker = "DEZ", text = "You didn't ask what I was doing in there." },
					{ at = 0.1, speaker = "YOU", text = "Not my business." },
					{ at = 0.2, speaker = "DEZ", text = "See, that. That's a good answer. Most people don't know they got a good answer in them." },
					{ at = 0.38, speaker = "DEZ", text = "Kesting runs from Harrow down to Linden. Quarry's got everything south. Every corner in between, somebody's bleeding over it." },
					{ at = 0.55, speaker = "DEZ", text = "A cab goes everywhere. Nobody looks twice at a cab." },
					{ at = 0.7, speaker = "DEZ", text = "Tommy won't be doing that again, by the way. To anybody.", late = true },
					{ at = 0.8, speaker = "YOU", text = "What does that mean?", late = true },
					{ at = 0.86, speaker = "DEZ", text = "Means you're welcome.", late = true },
				},
				arrival = {
					{ speaker = "DEZ", text = "Your forty back. And a little extra, for the trouble." },
					{ speaker = "DEZ", text = "My number's in your phone now. When I call, you pick up." },
					{ speaker = "YOU", text = "And if I don't?" },
					{ speaker = "DEZ", text = "...Everybody picks up." },
				},
			},
			{ type = "dropoff", pay = 100, note = "Dez -- your $40 back, and then some" },
			{ type = "text", from = "Dez", text = "This is Dez. Save it." },
		},
	},

	-- 4. Vance: the other side wants to know who the yellow cab works for.
	{
		id = "colours",
		title = "Wrong Colours",
		blurb = "A fare at The Hollis asked for your cab by number.",
		unlockAfter = 2,
		unlockText = { from = "Dispatch", text = "Pickup at The Hollis, Calloway Ave. Fella asked for your cab by number. You're popular tonight. It's in your Story app." },
		steps = {
			{ type = "pickup", who = "vance", spot = PLACES.hollis },
			{
				type = "ride",
				spot = PLACES.quarryCorner,
				meter = true,
				lines = {
					{ at = 0, speaker = "VANCE", text = "Marrow Street, on the Quarry corner. And loosen your grip, driver. You're strangling that wheel." },
					{ at = 0.14, speaker = "VANCE", text = "Nice cab. Clean. Smells like the Velvet, though." },
					{ at = 0.24, speaker = "YOU", text = "I pick up all kinds." },
					{ at = 0.34, speaker = "VANCE", text = "Sure you do. Couple nights back you picked up Dez's kind. Sat outside a house on Ashby for him with the engine running." },
					{ at = 0.48, speaker = "VANCE", text = "People see things. A yellow cab's like a lighthouse round here." },
					{ at = 0.6, speaker = "VANCE", text = "That kid Tommy was one of ours. He's in the hospital now. Eating through a straw.", late = true },
					{ at = 0.72, speaker = "VANCE", text = "That's Kesting saying sorry on your behalf. Hope you feel looked after.", late = true },
				},
				arrival = {
					{ speaker = "VANCE", text = "Don't unlock the doors yet." },
					{ speaker = "VANCE", text = "That house on Ashby. Where Dez went in. Which corner? You drove him. You know." },
				},
			},
			{
				type = "choice",
				key = "toldVance",
				prompt = "Vance is waiting for an answer.",
				options = {
					{ text = "\"Ashby and Kesting. The corner house.\"", value = true },
					{ text = "\"I just drive. I don't remember faces, or houses.\"", value = false },
				},
			},
			{
				type = "talk",
				when = TOLD,
				lines = {
					{ speaker = "VANCE", text = "See? Easy. Nobody ever has to know you said a word." },
					{ speaker = "VANCE", text = "Here. Something extra for the gas." },
				},
			},
			{
				type = "talk",
				when = KEPT_QUIET,
				lines = {
					{ speaker = "VANCE", text = "...Loyal. To a guy who'd trade you for a parking space." },
					{ speaker = "VANCE", text = "We'll talk again, driver. Keep the change. Buy yourself some sense." },
				},
			},
			{ type = "dropoff", when = TOLD, pay = "meter", tip = 80, note = "Vance -- something extra" },
			{ type = "dropoff", when = KEPT_QUIET, pay = "meter", tip = 0, note = "Vance -- Quarry corner" },
			{ type = "text", when = KEPT_QUIET, from = "Dez", text = "Heard Quarry had a word with you. Heard you kept your mouth shut. I don't forget things like that." },
		},
	},

	-- 5. The bag: not a fare, a delivery. You don't open it.
	{
		id = "bag",
		title = "The Bag",
		blurb = "Dez has a delivery. Don't open it.",
		unlockAfter = 2,
		unlockText = { from = "Dez", text = "Got work for you. Not a fare -- a delivery. Bag by the door at Marrow Towers, goes to Langford Tower on Ashby. Don't open it. Story app." },
		steps = {
			{
				type = "text",
				when = TOLD,
				from = "Dez",
				text = "Funny thing. Quarry hit the house on Ashby last night. Knew the door, knew the night. Somebody told them. Wasn't you, right?",
			},
			{ type = "collect", spot = PLACES.towers, prop = "bag", label = "Pick up the bag" },
			{
				type = "ride",
				spot = PLACES.langford,
				cargo = "the bag",
				lines = {
					{ at = 0.1, speaker = "YOU", text = "Don't look in the bag. Just drive." },
					{ at = 0.5, speaker = "YOU", text = "...Heavy, for clothes." },
					{ at = 0.85, speaker = "YOU", text = "Who are you kidding.", late = true },
				},
				texts = {
					{ at = 0.3, from = "Unknown number", text = "Nice bag." },
					{ at = 0.62, from = "Unknown number", text = "Yellow cab, roof light on, heading to Ashby. We see you, driver." },
				},
			},
			{
				type = "handoff",
				who = "runner",
				spot = PLACES.langford,
				lines = {
					{ speaker = "RUNNER", text = "That's it? ...Alright. It's all there." },
					{ speaker = "RUNNER", text = "Dez says you're the real thing. Don't let it go to your head." },
				},
			},
			{ type = "dropoff", pay = 150, note = "Dez -- a delivery" },
			{ type = "text", from = "Dez", text = "Got it. Money's in your hand. You're good at this, you know that? Better than you want to be." },
		},
	},

	-- 6. Quarry St: the war, from the driver's seat.
	{
		id = "crossfire",
		title = "Crossfire",
		blurb = "Dez needs a ride to the wrong side of Linden.",
		unlockAfter = 2,
		unlockText = { from = "Dez", text = "Need a ride tonight. Just me. The Bellmore, Marrow St. Don't be late." },
		steps = {
			{ type = "pickup", who = "dez", spot = PLACES.bellmore },
			{
				type = "ride",
				spot = PLACES.quarryCalloway,
				lines = {
					{ at = 0, speaker = "DEZ", text = "Calloway. Down by Quarry." },
					{ at = 0.06, speaker = "YOU", text = "That's their side." },
					{ at = 0.12, speaker = "DEZ", text = "Yeah. It is." },
					{ at = 0.26, speaker = "DEZ", text = "They found Tommy this morning. Behind the laundromat on Vail. Somebody decided the hospital wasn't enough." },
					{ at = 0.4, speaker = "YOU", text = "Your people?" },
					{ at = 0.48, speaker = "DEZ", text = "Does it matter? Quarry thinks so. So tonight it's my people." },
					{ at = 0.6, speaker = "DEZ", text = "They knew about the house on Ashby. Knew the door. You and me both know how.", late = true, when = TOLD },
					{ at = 0.6, speaker = "DEZ", text = "You kept quiet for me once. I need you quiet again.", late = true, when = KEPT_QUIET },
					{ at = 0.72, speaker = "DEZ", text = "I'm stepping out for two minutes. Engine stays running. When I get back in, you drive.", late = true },
				},
				arrival = {
					{ speaker = "DEZ", text = "Two minutes." },
				},
			},
			{ type = "errand", seconds = 12, gunfire = true, objective = "Wait for Dez. Keep the engine running." },
			{ type = "talk", lines = { { speaker = "DEZ", text = "GO! DRIVE! DRIVE!" } } },
			{
				type = "ride",
				spot = PLACES.halo,
				timeLimit = 75,
				lines = {
					{ at = 0.08, speaker = "DEZ", text = "Don't stop for the lights. Don't stop for nothing." },
					{ at = 0.3, speaker = "DEZ", text = "Ashby. Halo. They got a back room." },
					{ at = 0.48, speaker = "YOU", text = "You're bleeding." },
					{ at = 0.56, speaker = "DEZ", text = "I know I'm bleeding. Drive." },
				},
				arrival = {
					{ speaker = "DEZ", text = "...Good. That's good. You did good." },
					{ speaker = "DEZ", text = "You were never on Quarry Street tonight. You hear me? Never." },
				},
				failText = "They caught up with you. Try again -- get Dez to Halo in time.",
			},
			{ type = "dropoff", pay = 250, note = "Dez -- Quarry St" },
			{ type = "ending", title = "END OF PART ONE", subtitle = "The Marrow will remember your cab." },
			{ type = "text", from = "Ray", text = "Saw the news. Shooting on Quarry St, and somebody saw a yellow cab drive off from it. Tell me that wasn't you." },
			{ type = "text", from = "Dispatch", text = "Cops came by the garage asking about your cab. I told them I don't know nothing. Lay low for a while." },
			{ type = "text", from = "Mom", text = "Are you okay? Please call me." },
		},
	},
}

-- Does `entry` (a step or line) apply, given what's been chosen?
function StoryConfig.applies(entry, choices: { [string]: any }): boolean
	local when = entry.when
	if not when then
		return true
	end
	return choices[when.choice] == when.is
end

-- Where each chapter stands for a player who's finished `done` chapters and
-- done `faresSince` ordinary fares since: "done", "ready", "locked" (with
-- how many fares to go) or "hidden" (further on than that).
function StoryConfig.status(index: number, done: number, faresSince: number): (string, number)
	if index <= done then
		return "done", 0
	elseif index == done + 1 then
		local need = StoryConfig.CHAPTERS[index].unlockAfter - faresSince
		if need <= 0 then
			return "ready", 0
		end
		return "locked", need
	end
	return "hidden", 0
end

return StoryConfig
