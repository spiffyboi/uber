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
-- The game is the story: in Story mode (New Story / Continue on the menu)
-- the chapters run one after another, each starting a little while after
-- the last one ends. Ordinary fares are a separate mode, Free Play (see
-- FareService). Story jobs are marked in red rather than Dispatch gold.
--
-- Chapters are grouped into parts (`part`, see PARTS).
--
-- Each chapter is a list of steps, run in order by StoryService on the
-- server and shown by Story.client:
--   text     -- a text arrives on the phone ({from, text})
--   drive    -- drive yourself to `spot` (nobody aboard); `lines` are the
--               driver's own thoughts on the way, as for a ride
--   purchase -- pay `price` for `item` (remembered as a choice: has<Item>)
--   pickup   -- someone's waiting at `spot`; pull up beside them and stop
--   ride     -- drive whoever's aboard (or whatever's in the trunk) to
--               `spot`. `lines` are said along the way (`at` = how far
--               through, 0..1; `late` ones are said before arriving ends
--               the step, even if the cab gets there early), `arrival` once
--               stopped. `texts` arrive on the phone along the way.
--               `timeLimit` makes it a race (run out and it starts over).
--   talk     -- lines said while stopped
--   choice   -- the player picks what to say; remembered as `key`
--   robbery  -- the passenger takes `take` dollars and runs (a cutscene)
--   scene    -- a cutscene (`scene` names which -- see StoryScenes); its
--               lines say which `shot` they're on and any `action`.
--               `killEngine` stops the cab first; `removePassenger` takes
--               whoever's in the back away after; `keepOpen` leaves the
--               cutscene running into the next step
--   errand   -- the passenger gets out, goes inside, comes back after
--               `seconds` and gets back in (`gunfire` = it goes badly)
--   collect  -- stop at `spot` to pick something up (no passenger)
--   handoff  -- stop at `spot` and hand it to someone waiting there
--   dropoff  -- the passenger gets out and pays: `pay` dollars, or the
--               meter for the last ride (`pay = "meter"`) plus `tip`;
--               `outro` ends a cutscene with them walking off
--   ending   -- a title card ({title, subtitle})
-- Any step (or line) with `when = {choice = key, is = value}` only happens
-- if that's what was chosen.
--
-- All dialogue is original to this game.

local CityConfig = require(script.Parent.CityConfig)
local FareConfig = require(script.Parent.FareConfig)

local StoryConfig = {}

StoryConfig.PARTS = {
	"Part One: Night Shift",
	"Part Two: Iron",
}
StoryConfig.COLOR = Color3.fromRGB(225, 70, 80)

-- How long after one chapter ends the next one starts (a text arrives
-- first, saying it's coming).
StoryConfig.NEXT_CHAPTER_DELAY = 14

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
	gil = {
		name = "Gil",
		look = { skin = Color3.fromRGB(225, 195, 165), shirt = Color3.fromRGB(70, 60, 52), pants = Color3.fromRGB(28, 28, 30) },
	},
	-- Gil's daughter (chapter 9): about ten, in her good dress.
	nina = {
		name = "Nina",
		look = { skin = Color3.fromRGB(225, 195, 165), shirt = Color3.fromRGB(34, 34, 52), pants = Color3.fromRGB(34, 34, 52) },
	},
	-- A night-shift baker going home (chapter 9). Nothing to do with
	-- anything.
	lou = {
		name = "Lou",
		look = { skin = Color3.fromRGB(205, 165, 130), shirt = Color3.fromRGB(226, 222, 210), pants = Color3.fromRGB(70, 66, 60) },
	},
	-- The two men in the alley (chapter 9): dark coats, never named.
	alleyman = {
		name = "Alleyman",
		look = { skin = Color3.fromRGB(185, 150, 122), shirt = Color3.fromRGB(26, 24, 26), pants = Color3.fromRGB(20, 20, 22) },
	},
}

-- ===== Places =====

local function spot(name: string, x: number, index: number, side: number, along: number?)
	local standing, stop = FareConfig.kerbSpot(x, index, side, along)
	return { name = name, standing = standing, stop = stop }
end

local GREAVES, ASHBY, MARROW, CALLOWAY, DUNMORE = -600, -300, CityConfig.MAIN_AVENUE_X, 300, 600

-- Spread out across the city so each ride is about as long as what's said
-- on it (a stud of route for roughly every 1/36 s of talking -- see
-- Conversations.talkSeconds).
local PLACES = {
	halcyon = spot("Halcyon House, Marrow St", MARROW, 8, 1, -6),
	rayHome = spot("Greaves Ave, down by Brine St", GREAVES, 43, -1),
	parkGate = spot("Marrow Park, Marrow St", MARROW, 7, -1, 4),
	wharfEnd = spot("Calloway Ave, down by the wharf", CALLOWAY, 46, -1),
	voltage = spot("Voltage, Dunmore Ave", DUNMORE, 12, -1),
	kestingHouse = spot("Greaves Ave at Kesting St", GREAVES, 5, -1),
	claremont = spot("The Claremont, Dunmore Ave", DUNMORE, 8, 1),
	quarryHouses = spot("Quarry Houses, Calloway Ave", CALLOWAY, 35, -1),
	towers = spot("Marrow Towers, Marrow St", MARROW, 12, -1),
	rowan = spot("Rowan Houses, Greaves Ave", GREAVES, 33, 1),
	copperRoom = spot("the Copper Room, Greaves Ave", GREAVES, 9, -1),
	quarryCalloway = spot("Calloway Ave at Quarry St", CALLOWAY, 23, 1),
	halo = spot("Halo, Ashby Ave", ASHBY, 2, 1),
	ironside = spot("Ironside Arms, Ashby Ave", ASHBY, 32, -1),
	pit = spot("The Pit, Greaves Ave", GREAVES, 45, 1),
	pier = spot("Pier Park, Dunmore Ave", DUNMORE, 32, -1),
	chapel = spot("Larkin & Sons, Calloway Ave", CALLOWAY, 33, 1),
	harborView = spot("Harbor View, Dunmore Ave", DUNMORE, 45, 1),
}
StoryConfig.PLACES = PLACES

local TOLD = { choice = "toldVance", is = true }
local KEPT_QUIET = { choice = "toldVance", is = false }

-- ===== Chapters =====

StoryConfig.CHAPTERS = {
	-- 1. The first night. Ray, the first fare, called in at the end of the
	-- intro: small talk most of the way, and the last stretch is where it
	-- turns. Then Tommy, late, from the park -- who robs you at the wharf.
	{
		id = "ray",
		title = "Setting the Meter",
		blurb = "Ray, from Halcyon House to Greaves Ave. Then a late one from the park.",
		startsFromIntro = true,
		steps = {
			{ type = "text", from = "Dispatch", text = "Your fare's waiting outside Halcyon House on Marrow St. Name's Ray. Going all the way down Greaves Ave." },
			{ type = "pickup", who = "ray", spot = PLACES.halcyon },
			{
				type = "ride",
				spot = PLACES.rayHome,
				meter = true,
				lines = {
					{ at = 0, speaker = "RAY", text = "Evening. Greaves Avenue, all the way down by Brine Street, if you know it." },
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
			{ type = "dropoff", pay = "meter", tip = 10, note = "Ray -- Greaves Ave" },
			{ type = "text", from = "Dispatch", text = "Ray's home. Good first ride." },
			-- Later the same night: Tommy, a kid from the park who wants the
			-- dark end of Calloway.
			{ type = "text", from = "Dispatch", text = "Late one for you if you want it. Kid called from the payphone at Marrow Park. Wants the far end of Calloway." },
			{ type = "pickup", who = "tommy", spot = PLACES.parkGate },
			{
				type = "ride",
				spot = PLACES.wharfEnd,
				meter = true,
				lines = {
					{ at = 0, speaker = "TOMMY", text = "Calloway. All the way down, past the warehouses." },
					{ at = 0.05, speaker = "YOU", text = "The wharf? Not much down there this time of night." },
					{ at = 0.12, speaker = "TOMMY", text = "That's kind of the point." },
					{ at = 0.25, speaker = "TOMMY", text = "You like this? Driving round all night, people throwing up in your back seat?" },
					{ at = 0.34, speaker = "YOU", text = "It pays. Mostly." },
					{ at = 0.42, speaker = "TOMMY", text = "Mostly. Ha. Everything's mostly." },
					{ at = 0.58, speaker = "TOMMY", text = "My mom drove nights. Laundry van for the hospital. Twenty-two years.", late = true },
					{ at = 0.68, speaker = "TOMMY", text = "Know what she's got to show for it? A bad back and me.", late = true },
					{ at = 0.8, speaker = "TOMMY", text = "...Up here. Pull in by the fence.", late = true },
				},
			},
			-- A cutscene (see Story.client's robbery scene): the cab at the
			-- dead end, the engine dying, the knife, and Tommy gone into the
			-- dark. `shot` says which camera each line is on.
			{
				type = "robbery",
				take = 40,
				lines = {
					{ speaker = "TOMMY", text = "Kill the engine.", shot = "outside" },
					{ speaker = "YOU", text = "Meter says--", shot = "outside" },
					{ speaker = "TOMMY", text = "I know what the meter says.", shot = "knife" },
					{ speaker = "TOMMY", text = "Don't turn round. Don't make it a thing. Cash box. All of it.", shot = "knife" },
					{ speaker = "YOU", text = "Easy. Easy. It's yours.", shot = "driver" },
					{ speaker = "TOMMY", text = "...Sorry, man. I swear I'm sorry.", shot = "tommy" },
				},
			},
			{ type = "text", from = "Dispatch", text = "Heard on the radio somebody rolled a cab down by the wharf. That you? You alright? No shame in calling it a night." },
			{ type = "text", from = "Mom", text = "Just saw something on the news about a robbery. Tell me you're okay." },
		},
	},

	-- 2. Dez: the Kesting crew fixes what happened. Now you owe them.
	{
		id = "favours",
		title = "Entanglement",
		blurb = "Someone on Kesting wants to make the wharf right.",
		unlockText = { from = "Unknown number", text = "Heard about the wharf. That's not how things go on our streets. Come by Voltage on Dunmore Ave. I'll find you." },
		steps = {
			{ type = "pickup", who = "dez", spot = PLACES.voltage },
			{
				type = "ride",
				spot = PLACES.kestingHouse,
				lines = {
					{ at = 0, speaker = "DEZ", text = "You're the one got rolled down at the wharf. Relax. I'm not here to rob you too." },
					{ at = 0.04, speaker = "DEZ", text = "Greaves Avenue. Corner of Kesting." },
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
			{ type = "talk", lines = { { speaker = "DEZ", text = "Alright. Back to Voltage." } } },
			{
				type = "ride",
				spot = PLACES.voltage,
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
			},
			-- A cutscene (see Story.client's contact scene): Dez takes the
			-- player's phone, puts his number in it himself and hands it back.
			{
				type = "scene",
				scene = "contact",
				contact = { name = "Dez", number = "555-0147", note = "Kesting. When he calls, you pick up." },
				lines = {
					{ speaker = "DEZ", text = "Your forty back. And a little extra, for the trouble.", shot = "dez" },
					{ speaker = "DEZ", text = "Give me your phone.", shot = "dez" },
					{ speaker = "YOU", text = "My phone?", shot = "driver" },
					{ speaker = "DEZ", text = "I'm not gonna eat it.", shot = "dez", typing = true },
					{ speaker = "DEZ", text = "There. Now you got a friend on Kesting.", shot = "phone" },
					{ speaker = "DEZ", text = "When I call, you pick up.", shot = "dez" },
					{ speaker = "YOU", text = "And if I don't?", shot = "driver" },
					{ speaker = "DEZ", text = "...Everybody picks up.", shot = "dez" },
				},
			},
			{ type = "dropoff", pay = 100, note = "Dez -- your $40 back, and then some", outro = "walkAway" },
			{ type = "text", from = "Dez", text = "Saved you the trouble. Don't make me wait." },
		},
	},

	-- 3. Vance: the other side wants to know who the yellow cab works for.
	-- Then Dez's bag, delivered across town with Quarry watching.
	{
		id = "colours",
		title = "Both Sides Now",
		blurb = "A fare at The Claremont asked for your cab by number. Then Dez has a delivery.",
		unlockText = { from = "Dispatch", text = "Pickup at The Claremont, Dunmore Ave. Fella asked for your cab by number. You're popular tonight. It's in your Story app." },
		steps = {
			{ type = "pickup", who = "vance", spot = PLACES.claremont },
			{
				type = "ride",
				spot = PLACES.quarryHouses,
				meter = true,
				lines = {
					{ at = 0, speaker = "VANCE", text = "Quarry Houses, down on Calloway. And loosen your grip, driver. You're strangling that wheel." },
					{ at = 0.14, speaker = "VANCE", text = "Nice cab. Clean. Smells like Voltage, though." },
					{ at = 0.24, speaker = "YOU", text = "I pick up all kinds." },
					{ at = 0.34, speaker = "VANCE", text = "Sure you do. Couple nights back you picked up Dez's kind. Sat outside a house on Greaves for him with the engine running." },
					{ at = 0.48, speaker = "VANCE", text = "People see things. A yellow cab's like a lighthouse round here." },
					{ at = 0.6, speaker = "VANCE", text = "That kid Tommy was one of ours. He's in the hospital now. Eating through a straw.", late = true },
					{ at = 0.72, speaker = "VANCE", text = "That's Kesting saying sorry on your behalf. Hope you feel looked after.", late = true },
				},
				arrival = {
					{ speaker = "VANCE", text = "Don't unlock the doors yet." },
					{ speaker = "VANCE", text = "That house on Greaves. Where Dez went in. Which corner? You drove him. You know." },
				},
			},
			{
				type = "choice",
				key = "toldVance",
				prompt = "Vance is waiting for an answer.",
				options = {
					{ text = "\"Greaves and Kesting. The corner house.\"", value = true },
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
			{ type = "dropoff", when = KEPT_QUIET, pay = "meter", tip = 0, note = "Vance -- Quarry Houses" },
			{ type = "text", when = KEPT_QUIET, from = "Dez", text = "Heard Quarry had a word with you. Heard you kept your mouth shut. I don't forget things like that." },
			-- Then Dez's bag: not a fare, a delivery. You don't open it.
			{ type = "text", from = "Dez", text = "Got work for you. Not a fare -- a delivery. Bag by the door at Marrow Towers, goes to Rowan Houses on Greaves. Don't open it." },
			{
				type = "text",
				when = TOLD,
				from = "Dez",
				text = "Funny thing. Quarry hit the house on Greaves last night. Knew the door, knew the night. Somebody told them. Wasn't you, right?",
			},
			{ type = "collect", spot = PLACES.towers, prop = "bag", label = "Pick up the bag" },
			{
				type = "ride",
				spot = PLACES.rowan,
				cargo = "the bag",
				lines = {
					{ at = 0.05, speaker = "YOU", text = "Don't look in the bag. Just drive." },
					{ at = 0.18, speaker = "YOU", text = "Three weeks ago the scariest thing in this cab was a drunk with a kebab." },
					{ at = 0.4, speaker = "YOU", text = "...Heavy, for clothes." },
					{ at = 0.52, speaker = "YOU", text = "Same car behind me two lights in a row. No. Lots of cars are black." },
					{ at = 0.7, speaker = "YOU", text = "Ray said this city don't care who you are. Seems to care a lot what you carry." },
					{ at = 0.85, speaker = "YOU", text = "Who are you kidding.", late = true },
				},
				texts = {
					{ at = 0.3, from = "Unknown number", text = "Nice bag." },
					{ at = 0.62, from = "Unknown number", text = "Yellow cab, roof light on, heading to Greaves. We see you, driver." },
					{ at = 0.78, from = "Dez", text = "Don't stop for nobody. Not even if they wave." },
				},
			},
			{
				type = "handoff",
				who = "runner",
				spot = PLACES.rowan,
				lines = {
					{ speaker = "RUNNER", text = "That's it? ...Alright. It's all there." },
					{ speaker = "RUNNER", text = "Dez says you're the real thing. Don't let it go to your head." },
				},
			},
			{ type = "dropoff", pay = 150, note = "Dez -- a delivery" },
			{ type = "text", from = "Dez", text = "Got it. Money's in your hand. You're good at this, you know that? Better than you want to be." },
		},
	},

	-- 4. Quarry St: the war, from the driver's seat.
	{
		id = "crossfire",
		title = "A Sick Passenger",
		blurb = "Dez needs a ride to the wrong side of Linden.",
		unlockText = { from = "Dez", text = "Need a ride tonight. Just me. The Copper Room, Greaves Ave. Don't be late." },
		steps = {
			{ type = "pickup", who = "dez", spot = PLACES.copperRoom },
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
					{ at = 0.6, speaker = "DEZ", text = "They knew about the house on Greaves. Knew the door. You and me both know how.", late = true, when = TOLD },
					{ at = 0.6, speaker = "DEZ", text = "You kept quiet for me once. I need you quiet again.", late = true, when = KEPT_QUIET },
					{ at = 0.74, speaker = "DEZ", text = "Slow down. Pull in under the light. Here.", late = true },
				},
			},
			-- At the kerb, before he goes in (see StoryScenes' window scene):
			-- he has the driver look up at a lit window across the sidewalk,
			-- where a man's moving about, and talks -- quietly -- about him.
			-- The driver never says a word. Staged after the passenger in the
			-- back of Travis's cab in Taxi Driver; every line is this game's.
			{
				type = "scene",
				scene = "window",
				lines = {
					{ shot = "kerb", speaker = "DEZ", text = "Leave it running. The meter too. I'm good for it." },
					{ shot = "driver", beat = 1.5 },
					{ shot = "back", speaker = "DEZ", text = "Look up. Third floor. The window with the lamp in it." },
					{ shot = "window", beat = 3 },
					{ shot = "window", speaker = "DEZ", text = "See him? Walking about up there like it's his kitchen. Like nothing's ever coming up those stairs." },
					{ shot = "back", speaker = "DEZ", text = "That's Curtis. Curtis used to cut my hair. Cut my little brother's for his graduation. Wouldn't take the money." },
					{ shot = "driver", beat = 1.5 },
					{ shot = "back", speaker = "DEZ", text = "Tommy was nineteen. Curtis made one phone call and went back to his dinner." },
					{ shot = "window", speaker = "DEZ", text = "Three nights I've sat out here. He draws them curtains at half past twelve. Every night. Man thinks a curtain's a wall." },
					{ shot = "back", speaker = "DEZ", text = "You want to know what I'm going to do up there?" },
					{ shot = "driver", beat = 2.2 },
					{ shot = "back", speaker = "DEZ", text = "No. You don't. You drive a cab. Keep it that way." },
					{ shot = "back", speaker = "DEZ", text = "Somebody told Quarry where my door was. Somebody I let close. I'm going to find out who. One window at a time.", when = TOLD },
					{ shot = "back", speaker = "DEZ", text = "You kept your mouth shut for me once. People who keep their mouths shut get old round here.", when = KEPT_QUIET },
					{ shot = "driver", beat = 1.8 },
					{ shot = "back", speaker = "DEZ", text = "You scared of me?" },
					{ shot = "driver", beat = 2 },
					{ shot = "back", speaker = "DEZ", text = "Good. That's the right answer." },
					{ shot = "window", speaker = "DEZ", text = "Two minutes. If that lamp goes out before I come down, you drive anyway." },
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

	-- ===== Part Two =====

	-- 5. Iron: after Quarry Street the cab's a face people know. Abe at
	-- Ironside Arms sells the driver a pistol, and it goes in the door. Then
	-- Gil, who asked for the cab by name.
	{
		id = "iron",
		part = 2,
		title = "The First Note of a Paternal Threnody",
		blurb = "Dez says you need something for the car. Then a fare who asked for you by name.",
		unlockText = { from = "Dez", text = "Cops been round Halo asking about a yellow cab. Quarry's asking louder. Go see Abe at Ironside Arms on Ashby. Tell him I sent you." },
		steps = {
			{
				type = "drive",
				spot = PLACES.ironside,
				lines = {
					{ at = 0, speaker = "YOU", text = "Ironside Arms. Never been in a gun shop in my life." },
					{ at = 0.16, speaker = "YOU", text = "Dad kept a pistol in a shoebox. Never took it out. Said owning it was the whole point." },
					{ at = 0.34, speaker = "YOU", text = "Ray's boy didn't have one. Didn't help him either way." },
					{ at = 0.52, speaker = "YOU", text = "A month ago my biggest worry was the clutch." },
					{ at = 0.7, speaker = "YOU", text = "Just for the car. Just in case. Bet that's what everybody says.", late = true },
					{ at = 0.86, speaker = "YOU", text = "...Here goes.", late = true },
				},
			},
			-- A cutscene (see StoryScenes' gun store scene): inside, Abe,
			-- the counter, the pistol laid out on the glass.
			{
				type = "scene",
				scene = "gunstore",
				keepOpen = true,
				lines = {
					{ speaker = "ABE", text = "Bell's broke. Don't ring it twice.", shot = "inside" },
					{ speaker = "ABE", text = "You're Dez's driver. Don't look surprised -- it's a small city with big ears.", shot = "abe" },
					{ speaker = "YOU", text = "I just need something for the car.", shot = "pov" },
					{ speaker = "ABE", text = "Everybody just needs something.", shot = "abe" },
					{ speaker = "ABE", text = "There. Small, plain, does one thing. Fits in a door pocket.", shot = "counter", action = "layGun" },
					{ speaker = "ABE", text = "Two hundred. No paperwork, no names. You were never here.", shot = "abe" },
					{ speaker = "YOU", text = "...It's heavier than it looks.", shot = "counter" },
					{ speaker = "ABE", text = "They always are. Gets heavier after you use it, too.", shot = "abe" },
				},
			},
			{ type = "purchase", price = 200, item = "Pistol", note = "Ironside Arms -- a pistol" },
			-- Back in the cab: it goes behind the driver's door panel.
			{
				type = "scene",
				scene = "stash",
				lines = {
					{ speaker = "YOU", text = "Behind the door panel. Where my hand can find it without looking.", shot = "door", action = "stash" },
					{ speaker = "YOU", text = "Just in case.", shot = "driver" },
				},
			},
			-- Dez is colder from here on if you told Vance about the house: he's
			-- worked out who did.
			{ type = "text", when = KEPT_QUIET, from = "Dez", text = "Abe says you bought something. Good. Don't wave it around. It's for the night you need it." },
			{ type = "text", when = TOLD, from = "Dez", text = "Abe says you bought something. Good. Make sure you know which way to point it." },
			{ type = "text", from = "Mom", text = "You sounded different on the machine. Are you eating? Call your mother." },
			-- Then a fare who asked for the cab by name. A pier, a gun at the
			-- back of the driver's head, and the one in the door.
			{ type = "text", from = "Dispatch", text = "Fare at The Pit, Greaves Ave. Asked for you by name -- second time this month somebody's done that. I don't like it." },
			{ type = "pickup", who = "gil", spot = PLACES.pit },
			{
				type = "ride",
				spot = PLACES.pier,
				meter = true,
				lines = {
					{ at = 0, speaker = "GIL", text = "Pier Park, over on Dunmore. Take your time, driver. I'm in no hurry tonight." },
					{ at = 0.08, speaker = "YOU", text = "Long way across town." },
					{ at = 0.14, speaker = "GIL", text = "I like a long ride. You get to know a man." },
					{ at = 0.26, speaker = "GIL", text = "My little girl started piano. Can't play a note yet, but she sits there an hour every night like she's at the Grand." },
					{ at = 0.38, speaker = "YOU", text = "Sounds like a good kid." },
					{ at = 0.46, speaker = "GIL", text = "Best thing I ever did. Only thing, maybe." },
					{ at = 0.58, speaker = "GIL", text = "You hear about Quarry Street a while back? Somebody drove a shooter away in a yellow cab. Clean getaway.", late = true },
					{ at = 0.68, speaker = "YOU", text = "Lot of yellow cabs in this city.", late = true },
					{ at = 0.76, speaker = "GIL", text = "That's true. That is true.", late = true },
					-- Why Vance sent him depends on what you told Vance back in
					-- chapter 3: a loose end, or a man who protected Dez.
					{ at = 0.81, speaker = "GIL", text = "Vance says you've got a real good memory for houses. He says it like it's a compliment.", late = true, when = TOLD },
					{ at = 0.81, speaker = "GIL", text = "Vance says you've got a terrible memory. Can't even remember a house you sat outside of with the engine running.", late = true, when = KEPT_QUIET },
					{ at = 0.86, speaker = "GIL", text = "Pull in by the railings. Kill the lights.", late = true },
				},
			},
			-- A cutscene (see StoryScenes' hold-up scene).
			{
				type = "scene",
				scene = "holdup",
				killEngine = true,
				removePassenger = true,
				lines = {
					{ speaker = "GIL", text = "Engine too.", shot = "outside" },
					{ speaker = "GIL", text = "Hands on the wheel. Both of them. There you go.", shot = "gun", action = "raiseGun" },
					{ speaker = "YOU", text = "There's sixty in the box. Take it.", shot = "driver" },
					{ speaker = "GIL", text = "I'm not here for the box. Vance says hello.", shot = "gil" },
					{ speaker = "GIL", text = "You gave him Greaves without him even asking twice. A man who talks that easy talks to anybody. Vance doesn't keep loose ends.", shot = "gil", when = TOLD },
					{ speaker = "GIL", text = "He asked you nice, in the back of your own cab. You looked him in the eye and covered for Dez. Vance doesn't ask twice.", shot = "gil", when = KEPT_QUIET },
					{ speaker = "GIL", text = "Quarry Street. You sat out front with the engine running while they did my cousin on the stairs.", shot = "gun" },
					{ speaker = "YOU", text = "I didn't know what he was going in there to do.", shot = "driver" },
					{ speaker = "GIL", text = "Nobody ever knows. Look straight ahead.", shot = "gil" },
					-- From here it's faces, and in between them the driver's hand
					-- going down off the wheel to the door (`reach`: how far down
					-- it's got, 0 on the wheel to 1 on the gun) -- the cuts coming
					-- quicker as it gets there. A `beat` is a shot with nothing
					-- said, held that many seconds.
					{ beat = 1.5, shot = "driver" },
					{ speaker = "YOU", text = "Alright. Alright. One hand off the wheel. Slow. I'll get you the cash box.", shot = "driver", reach = 0.25 },
					{ beat = 1.7, shot = "hand", reach = 0.5 },
					{ beat = 1.1, shot = "gil" },
					{ beat = 1.3, shot = "hand", reach = 0.75 },
					{ speaker = "GIL", text = "Slow, I said.", shot = "gil" },
					{ beat = 0.8, shot = "driver" },
					{ beat = 0.9, shot = "hand", reach = 1 },
					{ beat = 0.5, shot = "gil" },
					{ speaker = "GIL", text = "What are you--", shot = "fire", action = "fire" },
					{ speaker = "YOU", text = "...Oh God. Oh God.", shot = "driver" },
					{ beat = 4.5, shot = "aftermath" },
				},
			},
			{ type = "text", when = KEPT_QUIET, from = "Dez", text = "Heard a shot down by the pier. Don't answer that. Don't touch nothing, don't call nobody. Somebody's coming to clean your back seat." },
			{ type = "text", when = TOLD, from = "Dez", text = "Heard a shot down by the pier. Vance sent one of his for you, in your own cab. Funny how Quarry always knows where you are. Somebody's coming to clean your back seat. Then you and me are going to talk." },
			{ type = "ending", title = "TO BE CONTINUED", subtitle = "Nobody drives out of the Marrow clean." },
			{ type = "text", from = "Ray", text = "You don't text back anymore, friend. Whatever it is, it's not too late to get out. We're leaving Friday. There's room in the car." },
		},
	},

	-- 6. The first killing, after. Gil's funeral, which he'd been told to
	-- stay away from: his daughter plays the piano, and it's too much -- he
	-- shakes, and goes down in the aisle. Then back to work, a nothing fare,
	-- and out of the corner of his eye, down a side street, Dez -- and two
	-- men -- and a flash. He drives on. Gil's gone, Dez is gone: nobody left
	-- who knows his name. He tells himself he's out.
	{
		id = "aftertherain",
		part = 2,
		title = "After the Rain",
		blurb = "Gil's people are burying him tonight.",
		unlockText = { from = "Dez", text = "Gil's people are putting him in the ground tonight. Larkin & Sons, on Calloway. You stay far away from there. I mean it." },
		steps = {
			{ type = "text", from = "Mom", text = "You haven't called in a week. I keep leaving the porch light on like you're sixteen. Call me." },
			{
				type = "drive",
				spot = PLACES.chapel,
				lines = {
					{ at = 0, speaker = "YOU", text = "Just to see. Stand at the back. Nobody in there knows my face." },
					{ at = 0.3, speaker = "YOU", text = "He talked about her the whole way across town. The piano. An hour every night." },
					{ at = 0.6, speaker = "YOU", text = "You don't get to go. You know you don't get to go." },
					{ at = 0.85, speaker = "YOU", text = "...Five minutes. Then I leave.", late = true },
				},
			},
			-- The service (see StoryScenes' funeral scene). A `beat` is a shot
			-- held that long with nothing said; `shake` is how badly the
			-- driver's shaking by then (0 to 1).
			{
				type = "scene",
				scene = "funeral",
				lines = {
					-- On black, while the room's lighting settles (see StoryScenes).
					{ shot = "arrive", speaker = "", text = "Larkin & Sons, Calloway Ave. The evening service." },
					{ shot = "arrive", beat = 2.5 },
					{ shot = "back", speaker = "MINISTER", text = "Thank you all for coming out on a night like this. Gil would've said we were out of our minds, standing about in the rain on his account." },
					{ shot = "minister", speaker = "MINISTER", text = "Twenty-two years he drove a delivery truck through this city. Never missed a birthday. Not one." },
					{ shot = "driver", beat = 2.5 },
					{ shot = "minister", speaker = "MINISTER", text = "Nina's going to play something for her dad now. She's been practising every night." },
					{ shot = "walk", beat = 5, action = "ninaWalk" },
					{ shot = "keys", beat = 4, action = "music" },
					{ shot = "nina", beat = 4 },
					{ shot = "photo", beat = 4.5 },
					{ shot = "driver", beat = 3, shake = 0.2 },
					{ shot = "hands", beat = 2.5, shake = 0.4 },
					{ shot = "memory", beat = 0.6 },
					{ shot = "driver", beat = 2.5, shake = 0.65 },
					{ shot = "keys", beat = 1.5, shake = 0.75 },
					{ shot = "pov", beat = 3, shake = 0.9 },
					{ shot = "collapse", beat = 1.6, shake = 1 },
					{ shot = "black", beat = 3 },
					{ shot = "floor", speaker = "TEDDY", text = "Hey. Hey. Easy, son -- you went down hard." },
					{ shot = "floor", speaker = "TEDDY", text = "Somebody get him a glass of water." },
					{ shot = "floor", speaker = "YOU", text = "I'm sorry. I'm so sorry." },
					{ shot = "floor", speaker = "TEDDY", text = "Nothing to be sorry for. Did you know Gil?" },
					{ shot = "floor", speaker = "YOU", text = "...I drove him once." },
					{ shot = "black", beat = 2.5 },
					{ shot = "cab", beat = 4.5 },
				},
			},
			{ type = "text", when = KEPT_QUIET, from = "Dez", text = "Somebody fainted at Gil's funeral tonight. A cab driver. Don't tell me. Go to work. Act normal." },
			{ type = "text", when = TOLD, from = "Dez", text = "Somebody fainted at Gil's funeral tonight. A cab driver. I'm not even surprised. Don't call me. I'll find you." },
			{ type = "text", from = "Dispatch", text = "Fare at The Claremont, on Dunmore. Regular job, regular money. It'll do you good." },
			{ type = "pickup", who = "lou", spot = PLACES.claremont },
			-- An ordinary fare -- except that halfway along, down a side
			-- street, he sees Dez killed (see StoryService's alley and
			-- StoryScenes' alley cutscene). Lou sees nothing and talks right
			-- over it: `alley.lines` are his, said `at` that many seconds into
			-- the cutscene.
			{
				type = "ride",
				spot = PLACES.harborView,
				meter = true,
				alley = {
					at = 0.45,
					lines = {
						{ at = 0.3, speaker = "LOU", text = "--and I tell her, you can't rush rye. You rush rye, you get a brick." },
						{ at = 5.4, speaker = "LOU", text = "Thirty years I've told her that. She still buys the sliced stuff from the supermarket. Thirty years!", when = KEPT_QUIET },
						-- If you told Vance, these aren't Quarry's men: they're his own
						-- crew, who think Dez gave up the house on Greaves -- and Dez,
						-- on his knees, gives them you. ("{name}" is the player's name.)
						{ at = 5.4, speaker = "DEZ", text = "It wasn't me! I never gave nobody Greaves -- ask the cab driver! {name}! He drove Vance! Ask him!", when = TOLD },
						{ at = 12.9, speaker = "LOU", text = "Was that a car backfiring? You don't hear that so much anymore." },
						{ at = 16.4, speaker = "LOU", text = "Anyway. Bread doesn't care what time it is. That's the whole secret." },
					},
				},
				lines = {
					{ at = 0, speaker = "LOU", text = "Harbor View, right down the bottom of Dunmore. Thanks for stopping -- nobody stops in the rain." },
					{ at = 0.06, speaker = "LOU", text = "I'm a baker. Nights. Everybody thinks the bread just turns up in the morning." },
					{ at = 0.15, speaker = "LOU", text = "Three in the morning I'm up to my elbows in rye. It's the quiet I like. Just me and the ovens." },
					{ at = 0.24, speaker = "YOU", text = "Sounds peaceful." },
					{ at = 0.3, speaker = "LOU", text = "It is, it is. You can think in a bakery. My wife says I think too much." },
					{ at = 0.37, speaker = "LOU", text = "She says, Lou, you'll knead that dough till it's dust. And I tell her--" },
					{ at = 0.66, speaker = "LOU", text = "...You alright up there? You went quiet on me." },
					{ at = 0.72, speaker = "YOU", text = "Fine. Long night." },
					{ at = 0.82, speaker = "LOU", text = "They're all long nights. That's why I like the bread.", late = true },
				},
				arrival = {
					{ speaker = "LOU", text = "Here's me. Keep the change. And get some sleep, friend -- you look like a ghost." },
				},
			},
			{ type = "dropoff", pay = "meter", tip = 6, note = "Lou -- Harbor View" },
			{
				type = "talk",
				lines = {
					{ speaker = "YOU", text = "That was Dez. Down that street. That was Dez." },
					{ speaker = "YOU", text = "Gil. Now Dez. Everybody who ever got in this cab and knew my name." },
					{ speaker = "YOU", text = "So that's it, then. Nobody left to call. Nobody left to owe." },
					{ speaker = "YOU", text = "It's over. I'm out." },
				},
			},
			{ type = "text", from = "Dispatch", text = "Quiet night. Head in whenever you like." },
		},
	},
}

-- Which part a chapter's in (Part One unless it says).
function StoryConfig.partOf(chapter): number
	return chapter.part or 1
end

-- Does `entry` (a step or line) apply, given what's been chosen?
function StoryConfig.applies(entry, choices: { [string]: any }): boolean
	local when = entry.when
	if not when then
		return true
	end
	return choices[when.choice] == when.is
end

-- Where each chapter stands for a player who's finished `done` chapters:
-- "done", "ready" (the next one) or "hidden" (further on than that).
function StoryConfig.status(index: number, done: number): string
	if index <= done then
		return "done"
	elseif index == done + 1 then
		return "ready"
	end
	return "hidden"
end

return StoryConfig
