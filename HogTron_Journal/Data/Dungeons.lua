-- Hand-written healer notes per dungeon, lowest level first.
--
-- SOURCE: the 2004-2006 game as the authors remember playing it. Written by hand for this MIT addon; no text,
-- table or file was copied from Wowhead, the Encounter Journal, or any other addon. NOT VERIFIED ON FOREVER:
-- Blizzard may have changed a boss, a cast, a quest or a level range. The window labels every page "old game,
-- hand-written" until a run on Forever confirms it. Fix what play proves wrong; do not add from memory alone.
--
-- Forever's Group Finder (read 2026-10-09, diag.atlas.lfg) also lists four dungeons the old game never had:
-- Excavation Site: Wetlands, Ruins of Lordaeron, City of Dalaran, Hall of Thanes. Nobody here has run them, so
-- they have NO page: the window says "no data for this dungeon yet" inside them. Write those from play only.
--
-- Schema (checked by tests/test_journal.py):
--   dungeon  key, name, inst (8th return of GetInstanceInfo), levels, where, bosses{}, quests{}, trash{} (optional)
--   boss     name, summary, optional (rare / event), damage = { tank = none|low|moderate|heavy, group = same },
--            casts{}, healer{} (free tips, one line each)
--   cast     name; and any of:
--              dispel = magic|curse|disease|poison   (a debuff a healer can remove - the school decides who can)
--              shield = tank|target|group            (put the shield up BEFORE this lands)
--              kick   = 1 (must) | 2 (nice)           (interrupt priority)
--              hits   = tank|target|group            (who the damage lands on)
--              cc     = true                          (sleep / fear / stun)
--              note   = one line
--   quest    title, side (A|H|nil), class (nil|PRIEST...), order, goal, giver, inside (giver in the cave),
--            turnin, turninInside, prereq, next, note
local J = HogHealsJournal
J.Data = J.Data or {}
J.Data.Dungeons = J.Data.Dungeons or {}
J.Data.SOURCE = "old game, hand-written - not verified on Forever"

local function cast(t) return t end
local D = J.Data.Dungeons

-- ================================================================================================ Ragefire Chasm
D[#D + 1] = {
  key = "rfc", name = "Ragefire Chasm", inst = 389, levels = "13-18",
  where = "Inside Orgrimmar, the Cleft of Shadow.",
  summary = "Horde's first dungeon. Short, four bosses, mostly melee. The two casters at the end are a warlock (curse + fire DoT) and a rogue (poison): the first dungeon where cleansing matters.",
  bosses = {
    { name = "Oggleflint",
      summary = "A trogg chieftain. Melee with a cleave.",
      damage = { tank = "moderate", group = "low" },
      casts = {
        cast{ name = "Cleave", hits = "tank", note = "Hits whoever stands next to the tank too. Melee spread out behind him." },
      },
      healer = { "Tank heals only. Anyone else taking damage is standing in the cleave." } },
    { name = "Taragaman the Hungerer",
      summary = "A felguard in the lava room. Fire around himself and a punch that sends the tank flying.",
      damage = { tank = "moderate", group = "moderate" },
      casts = {
        cast{ name = "Fire Nova", hits = "group", shield = "group", note = "Fire damage to everyone close to him. Ranged and the healer stay out of it." },
        cast{ name = "Uppercut", hits = "tank", note = "Knocks the tank back. He can walk toward the group for a moment: be ready to heal whoever he swings at next." },
      },
      healer = { "Stand at max range: the nova is the only thing that should hurt you in here.", "Melee take nova damage on top of swings - a group heal after each one." } },
    { name = "Jergosh the Invoker",
      summary = "The Searing Blade warlock. Curses and burns.",
      damage = { tank = "low", group = "low" },
      casts = {
        cast{ name = "Immolate", dispel = "magic", hits = "target", note = "A fire damage-over-time. Dispel it off the tank; others can be healed through it." },
        cast{ name = "Curse of Weakness", dispel = "curse", hits = "tank", note = "Lowers the tank's damage. Only a Mage or Druid can remove it - not deadly if nobody can." },
      },
      healer = { "Easy fight if you keep Immolate off the tank. Save mana for Bazzalan after." } },
    { name = "Bazzalan",
      summary = "The Searing Blade rogue. Poisons and hits hard for his level.",
      damage = { tank = "moderate", group = "low" },
      casts = {
        cast{ name = "Poison", dispel = "poison", hits = "tank", note = "A nature damage-over-time stacking on the tank. Cure it when you have the spare globals." },
        cast{ name = "Sinister Strike", hits = "tank" },
      },
      healer = { "Last boss. The poison plus his melee is the most tank damage in the place: keep the tank topped, cure between heals." } },
  },
  trash = {
    { name = "Searing Blade warlocks and cultists", casts = {
        cast{ name = "Immolate", dispel = "magic", hits = "target" },
        cast{ name = "Shadow Bolt", hits = "target", kick = 2 } } },
    { name = "Ragefire troggs and shamans", casts = {
        cast{ name = "Healing Wave", kick = 1, note = "Trogg shamans heal each other. Kick or kill them first." } } },
  },
  quests = {
    { title = "Slaying the Beast", order = 1, side = "H", goal = "Kill Taragaman the Hungerer and bring back his heart.",
      giver = "Neeru Fireblade, Orgrimmar (Cleft of Shadow)", turnin = "Neeru Fireblade, Orgrimmar" },
    { title = "Hidden Enemies", order = 2, side = "H", goal = "Kill Bazzalan and Jergosh the Invoker.",
      giver = "Thrall, Orgrimmar (Grommash Hold)", turnin = "Thrall, Orgrimmar",
      prereq = "The earlier Hidden Enemies steps from Thrall (the Burning Blade in Durotar).",
      note = "The two bosses at the end of the dungeon. Everyone in the group usually has it." },
    { title = "Testing an Enemy's Strength", order = 3, side = "H", goal = "Kill 8 Ragefire Troggs and 8 Searing Blade Cultists.",
      giver = "Rahauro, Thunder Bluff (Elder Rise)", turnin = "Rahauro, Thunder Bluff" },
    { title = "The Power to Destroy...", order = 4, side = "H", goal = "Bring back the two Searing Blade spellbooks the cultists carry.",
      giver = "Varimathras, Undercity (Royal Quarter)", turnin = "Varimathras, Undercity" },
    { title = "Searching for the Lost Satchel", order = 5, side = "H", goal = "Find Maur Grimtotem's remains inside the chasm.",
      giver = "Rahauro, Thunder Bluff (Elder Rise)", turnin = "Maur Grimtotem's remains, inside the dungeon", turninInside = true,
      next = "Returning the Lost Satchel" },
    { title = "Returning the Lost Satchel", order = 6, side = "H", goal = "Bring the satchel back.",
      giver = "Maur Grimtotem's remains, inside the dungeon", inside = true, turnin = "Rahauro, Thunder Bluff",
      prereq = "Searching for the Lost Satchel" },
  },
}

-- ================================================================================================ Wailing Caverns
D[#D + 1] = {
  key = "wc", name = "Wailing Caverns", inst = 43, levels = "17-24",
  where = "The Barrens, the cave above the oasis south-west of the Crossroads.",
  summary = "Druids of the Fang and their deviate beasts. Nature school all the way: Sleep (magic) on a healer or tank, poisons, lightning. The four Fang lords open the Naralex escort at the end.",
  bosses = {
    { name = "Lady Anacondra",
      summary = "First of the four Fang lords. A caster who puts people to Sleep and bolts the rest.",
      damage = { tank = "moderate", group = "low" },
      casts = {
        cast{ name = "Sleep", dispel = "magic", cc = true, hits = "target", note = "A sleeping tank means she turns on the next person - dispel the tank first, anyone else can wait it out." },
        cast{ name = "Lightning Bolt", hits = "target", kick = 2, shield = "target" },
        cast{ name = "Thorns", note = "A buff on herself that hurts the melee hitting her. Purge or Dispel Magic takes it off." },
      },
      healer = { "Stand back out of melee: Thorns punishes melee, not you.", "Keep a shield on whoever she last bolted; she repeats targets." } },
    { name = "Lord Cobrahn",
      summary = "Fang lord who poisons and, when low, turns into a serpent that hits harder.",
      damage = { tank = "heavy", group = "low" },
      casts = {
        cast{ name = "Poison", dispel = "poison", hits = "tank", note = "A nature damage-over-time. Cure it off the tank; off others only when you have spare mana." },
        cast{ name = "Druid's Slumber", dispel = "magic", cc = true, hits = "target" },
        cast{ name = "Lightning Bolt", hits = "target", kick = 2 },
        cast{ name = "Serpent Form", note = "At low health. Melee damage goes up: bigger heals on the tank until he dies." },
      },
      healer = { "Save mana before Serpent Form: the last third of the fight costs the most." } },
    { name = "Kresh",
      summary = "A giant turtle in the pool. Melee only.",
      damage = { tank = "moderate", group = "none" },
      casts = {},
      healer = { "Tank and spank. Drink after, not before." } },
    { name = "Lord Pythas",
      summary = "Fang lord with the full druid kit: Sleep, lightning, a thunderclap and a self-heal.",
      damage = { tank = "moderate", group = "low" },
      casts = {
        cast{ name = "Sleep", dispel = "magic", cc = true, hits = "target" },
        cast{ name = "Healing Touch", kick = 1, note = "Heals himself for a lot. Any kick stops the fight dragging on." },
        cast{ name = "Thunderclap", hits = "group", note = "Only hits people near him." },
        cast{ name = "Lightning Bolt", hits = "target", kick = 2, shield = "target" },
      },
      healer = { "Ask the melee for kicks on Healing Touch before the pull.", "Stand at range: Thunderclap is melee-range." } },
    { name = "Skum",
      summary = "A thunder lizard that chains lightning through the group.",
      damage = { tank = "moderate", group = "moderate" },
      casts = {
        cast{ name = "Chained Bolt", hits = "group", shield = "group", note = "Bounces between people standing close. Spread out and it stops bouncing." },
      },
      healer = { "Group damage comes in bursts - have a group heal or two ready, not just tank heals." } },
    { name = "Lord Serpentis",
      summary = "Fourth Fang lord. Sleep, lightning, and a self-heal to kick.",
      damage = { tank = "moderate", group = "low" },
      casts = {
        cast{ name = "Sleep", dispel = "magic", cc = true, hits = "target" },
        cast{ name = "Healing Touch", kick = 1 },
        cast{ name = "Lightning Bolt", hits = "target", kick = 2, shield = "target" },
      },
      healer = { "Killing him finishes the four lords: the escort at the entrance can start after this." } },
    { name = "Verdan the Everliving",
      summary = "A huge treant, optional, up the ramp past Serpentis. The hardest hitter in the place.",
      optional = true,
      damage = { tank = "heavy", group = "low" },
      casts = {
        cast{ name = "Grasping Vines", hits = "group", note = "Knocks back and roots everyone close to him." },
      },
      healer = { "Big heals queued up before each swing lands - he hits like a boss ten levels up.", "Heal from max range so the vines do not root you next to him." } },
    { name = "Mutanus the Devourer",
      summary = "The end of the Naralex escort. Fears people and cracks the whole group with thunder.",
      optional = true,
      damage = { tank = "moderate", group = "moderate" },
      casts = {
        cast{ name = "Terrify", dispel = "magic", cc = true, hits = "target", note = "A fear. Off the tank first; a feared tank drops threat onto you." },
        cast{ name = "Thundercrack", hits = "group", shield = "group" },
      },
      healer = { "Starts when the Disciple of Naralex wakes him, after all four lords are dead. Nobody can be dead or drinking when the escort ends.", "Waves of deviates come during the escort: heal through them with the cheap heals, keep the big ones for Mutanus." } },
    { name = "Deviate Faerie Dragon",
      summary = "Rare spawn. A small dragon that breathes fire in a cone.",
      optional = true,
      damage = { tank = "moderate", group = "low" },
      casts = {
        cast{ name = "Dragon's Breath", hits = "tank", note = "A frontal cone: only the tank should be in front of it." },
      },
      healer = {} },
  },
  trash = {
    { name = "Druids of the Fang", casts = {
        cast{ name = "Sleep", dispel = "magic", cc = true, hits = "target" },
        cast{ name = "Healing Touch", kick = 1 },
        cast{ name = "Serpent Form", note = "Turns into a snake and melees harder." } } },
    { name = "Deviate vipers and adders", casts = {
        cast{ name = "Poison", dispel = "poison", hits = "tank" } } },
  },
  quests = {
    { title = "Deviate Hides", order = 1, goal = "Collect 20 Deviate Hides from the beasts in the caverns.",
      giver = "Nalpak, in the cave above the instance door", inside = true, turnin = "Nalpak, same spot", turninInside = true },
    { title = "Deviate Eradication", order = 2, goal = "Kill 7 Deviate Ravagers, 7 Deviate Vipers, 7 Deviate Shamblers and 7 Deviate Dreadfangs inside.",
      giver = "Ebru, in the cave above the instance door", inside = true, turnin = "Ebru, same spot", turninInside = true },
    { title = "Trouble at the Docks", order = 3, goal = "Bring back the 99-Year-Old Port. Mad Magglish hides in the first caves inside the instance.",
      giver = "Crane Operator Bigglefuzz, Ratchet docks", turnin = "Crane Operator Bigglefuzz, Ratchet" },
    { title = "Smart Drinks", order = 4, goal = "Collect 6 Wailing Essence from the deviate creatures.",
      giver = "Mebok Mizzyrix, Ratchet", turnin = "Mebok Mizzyrix, Ratchet" },
    { title = "Serpentbloom", order = 5, side = "H", goal = "Pick 10 Serpentbloom. The plants grow inside the instance and need no herbalism.",
      giver = "Apothecary Zamah, Thunder Bluff (Spirit Rise)", turnin = "Apothecary Zamah, Thunder Bluff" },
    { title = "Leaders of the Fang", order = 6, side = "H", goal = "Bring the gems carried by Lady Anacondra, Lord Cobrahn, Lord Pythas and Lord Serpentis.",
      giver = "Nara Wildmane, Thunder Bluff (Elder Rise)", turnin = "Nara Wildmane, Thunder Bluff",
      note = "Pick it up before the run: all four lords drop their gem only for people on the quest." },
    { title = "The Glowing Shard", order = 7, goal = "Starts from the shard Mutanus drops at the end of the escort.",
      giver = "The Glowing Shard (drops from Mutanus the Devourer)", inside = true, turnin = "Falla Sagewind, on the hilltop above the cave entrance",
      next = "In Nightmares - Hamuul Runetotem in Thunder Bluff (Horde) or Fandral Staghelm in Darnassus (Alliance)",
      note = "Only drops when the escort finishes, so keep the Disciple of Naralex alive." },
  },
}

-- ================================================================================================ The Deadmines
D[#D + 1] = {
  key = "vc", name = "The Deadmines", inst = 36, levels = "17-26",
  where = "Westfall, Moonbrook: through the barn into the mine.",
  summary = "The Defias Brotherhood's mine and shipyard. Mostly physical damage with two things a healer must plan for: Mr. Smite's stomp stuns the whole group (you included), and VanCleef brings friends.",
  bosses = {
    { name = "Rhahk'Zor",
      summary = "The ogre at the first door. Melee only, slow and hard.",
      damage = { tank = "moderate", group = "none" },
      casts = {
        cast{ name = "Slam", hits = "tank", note = "A big single hit. Have a heal landing when it does." },
      },
      healer = { "Tank-only fight. Open with a shield and keep one heal ahead of his swings." } },
    { name = "Sneed's Shredder",
      summary = "A goblin shredder; when it dies, Sneed climbs out and fights on foot.",
      damage = { tank = "moderate", group = "low" },
      casts = {
        cast{ name = "Terrify", dispel = "magic", cc = true, hits = "target", note = "Sneed (on foot) fears. Off the tank first." },
        cast{ name = "Distracting Pain", hits = "tank", note = "The shredder's hit that also drops threat for a moment: the tank may lose him briefly." },
      },
      healer = { "Two fights in one - do not drink between the shredder dying and Sneed jumping out." } },
    { name = "Gilnid",
      summary = "The goblin smelter. Throws molten metal and heals himself.",
      damage = { tank = "low", group = "moderate" },
      casts = {
        cast{ name = "Molten Metal", hits = "target", shield = "target", note = "Fire damage on a random person - often the healer." },
        cast{ name = "Melt Ore", hits = "group", note = "Fire damage to people near him. Ranged stand back." },
      },
      healer = { "You will be targeted. A shield on yourself first, then the tank." } },
    { name = "Mr. Smite",
      summary = "The ship's first mate. Stuns everyone on deck twice and swaps to bigger weapons each time.",
      damage = { tank = "heavy", group = "low" },
      casts = {
        cast{ name = "Smite Stomp", hits = "group", cc = true, shield = "tank", note = "At two-thirds and one-third health: everyone on the deck is stunned, you too. The tank takes free hits meanwhile - shield the tank BEFORE each stomp." },
        cast{ name = "Smite Slam", hits = "tank" },
      },
      healer = { "Heal the tank to full as he nears each threshold: you will be stunned and unable to cast for a few seconds.", "After the second stomp he hits hardest of anything in here." } },
    { name = "Cookie",
      summary = "A murloc cook in the galley. Easy.",
      damage = { tank = "low", group = "none" },
      casts = {},
      healer = { "Nothing to do but not pull the deck trash with him." } },
    { name = "Captain Greenskin",
      summary = "Pirate captain on the ship with his crew around him.",
      damage = { tank = "moderate", group = "low" },
      casts = {
        cast{ name = "Cleave", hits = "tank", note = "Hits anyone beside the tank too." },
      },
      healer = { "He pulls with his crew: the adds die first, then he is a tank-and-spank." } },
    { name = "Edwin VanCleef",
      summary = "The Defias leader on the top deck. Calls two Blackguards to help as he loses health.",
      damage = { tank = "heavy", group = "moderate" },
      casts = {
        cast{ name = "Cleave", hits = "tank" },
        cast{ name = "VanCleef's Allies", hits = "group", note = "Two Defias Blackguards join at three-quarters and again at half health. They run at whoever has threat - often you. Stand near the tank, not behind the group." },
      },
      healer = { "Save mana for the adds: the worst damage is the Blackguards on a non-tank.", "A shield on yourself when the adds spawn buys the tank time to pick them up." } },
  },
  trash = {
    { name = "Defias Pillagers, Evokers and Wizards", casts = {
        cast{ name = "Fireball", hits = "target", kick = 2 },
        cast{ name = "Polymorph", dispel = "magic", cc = true, hits = "target", note = "Wizards sheep someone. Dispel it off the tank; a sheep heals itself." },
        cast{ name = "Fire Shield", note = "Evokers shield themselves; Purge or Dispel Magic strips it." } } },
    { name = "Goblin engineers", casts = {
        cast{ name = "Mortar", hits = "group", note = "Fire damage on an area: move out of it." } } },
  },
  quests = {
    { title = "Red Silk Bandanas", order = 1, side = "A", goal = "Collect 11 Red Silk Bandanas from the Defias inside the mines.",
      giver = "Scout Riell, Sentinel Hill", turnin = "Scout Riell, Sentinel Hill" },
    { title = "Collecting Memories", order = 2, side = "A", goal = "Collect 4 Miners' Union Cards from the miners.",
      giver = "Wilder Thistlenettle, Stormwind (Dwarven District)", turnin = "Wilder Thistlenettle, Stormwind" },
    { title = "Oh Brother. . .", order = 3, side = "A", goal = "Bring back Foreman Thistlenettle's badge. He stands near the entrance.",
      giver = "Wilder Thistlenettle, Stormwind (Dwarven District)", turnin = "Wilder Thistlenettle, Stormwind" },
    { title = "Underground Assault", order = 4, side = "A", goal = "Bring back the gnomish key piece from Sneed's Shredder.",
      giver = "Shoni the Shilent, Stormwind (Dwarven District)", turnin = "Shoni the Shilent, Stormwind" },
    { title = "The Defias Brotherhood", order = 5, side = "A", goal = "Kill Edwin VanCleef and bring back his head.",
      giver = "Gryan Stoutmantle, Sentinel Hill", turnin = "Gryan Stoutmantle, Sentinel Hill",
      prereq = "The whole Defias Brotherhood chain in Westfall from Gryan Stoutmantle (several steps).",
      next = "The Unsent Letter (from the letter VanCleef drops)" },
    { title = "The Unsent Letter", order = 6, side = "A", goal = "Starts from An Unsent Letter dropped by VanCleef.",
      giver = "An Unsent Letter (drops from Edwin VanCleef)", inside = true, turnin = "Baros Alexston, Stormwind (City Hall)",
      next = "Bazil Thredd - The Stockade" },
    { title = "The Test of Righteousness", order = 7, side = "A", class = "PALADIN", goal = "Jordan's Smithing Hammer: in a crate inside the mines, on the way to the ship.",
      giver = "Jordan Stilwell, Ironforge", turnin = "Jordan Stilwell, Ironforge",
      note = "One of four pieces for the Paladin's Verigan's Fist." },
  },
}

-- ================================================================================================ Shadowfang Keep
D[#D + 1] = {
  key = "sfk", name = "Shadowfang Keep", inst = 33, levels = "22-30",
  where = "Silverpine Forest, south of the Sepulcher, beside Pyrewood Village.",
  summary = "Arugal's worgen keep. Two things a healer must own here: Silverlaine's Veil of Shadow (a curse that nearly stops healing on the tank) and Arugal's Curse (turns a player into a worgen). Bring a decurser or expect a long night.",
  bosses = {
    { name = "Rethilgore",
      summary = "The jailer in the first room. Drains the life of one person.",
      damage = { tank = "moderate", group = "low" },
      casts = {
        cast{ name = "Soul Drain", hits = "target", kick = 2, note = "A channel that drains one person's health. Kick it or heal through it." },
      },
      healer = { "Killing him frees Deathstalker Adamant or Sorcerer Ashcrombe, who opens the courtyard door." } },
    { name = "Razorclaw the Butcher",
      summary = "The worgen butcher in the kitchen.",
      damage = { tank = "heavy", group = "none" },
      casts = {
        cast{ name = "Butcher Drain", hits = "tank", note = "A bleed on the tank that cannot be dispelled. Heal through." },
      },
      healer = { "A tank fight with a bleed on top: keep a heal-over-time up and never let the tank sit low." } },
    { name = "Baron Silverlaine",
      summary = "The ghost of the keep's lord, in the first tower.",
      damage = { tank = "moderate", group = "low" },
      casts = {
        cast{ name = "Veil of Shadow", dispel = "curse", hits = "tank", note = "Cuts healing on the tank by three-quarters. A Mage or Druid MUST decurse it. Without one: pre-shield, keep every heal-over-time up, and hope." },
      },
      healer = { "Tell the decurser before the pull: Veil of Shadow off the tank immediately.", "No decurser in the group: shield the tank before each swing and ask for a cooldown." } },
    { name = "Commander Springvale",
      summary = "A paladin ghost. Heals himself and stuns.",
      damage = { tank = "moderate", group = "low" },
      casts = {
        cast{ name = "Holy Light", kick = 1, note = "A big self-heal. Must be kicked." },
        cast{ name = "Hammer of Justice", cc = true, hits = "target", note = "A stun, usually on the tank." },
        cast{ name = "Devotion Aura", note = "Armour for himself; the fight takes longer, no danger." },
      },
      healer = { "Ask for kicks on Holy Light before the pull." } },
    { name = "Odo the Blindwatcher",
      summary = "A huge worgen with two wolves, in the courtyard tower.",
      damage = { tank = "heavy", group = "low" },
      casts = {
        cast{ name = "Howling Rage", hits = "tank", note = "An enrage on himself: he hits much harder for a while. Purge or Dispel Magic takes it off; otherwise big heals until it ends." },
      },
      healer = { "Kill the wolves first; they chew whoever they like.", "Have a shield and a big heal ready for Howling Rage." } },
    { name = "Fenrus the Devourer",
      summary = "Arugal's pet wolf. His death spawns the Sons of Arugal.",
      damage = { tank = "moderate", group = "low" },
      casts = {
        cast{ name = "Toxic Saliva", dispel = "poison", hits = "tank", note = "A poison damage-over-time. Cure it off the tank." },
      },
      healer = { "When he dies, Arugal appears and four Sons of Arugal spawn: do not drink, heal the group through their shadow bolts." } },
    { name = "Wolf Master Nandos",
      summary = "Worgen pack master. Calls wolves.",
      damage = { tank = "moderate", group = "moderate" },
      casts = {
        cast{ name = "Call Wolves", hits = "group", note = "Wolves spawn and run at random people, often the healer. Stand by the tank." },
      },
      healer = { "The wolves are the fight. A shield on yourself first." } },
    { name = "Archmage Arugal",
      summary = "The final boss at the top. Teleports around the room, curses a player into a worgen, and bolts.",
      damage = { tank = "moderate", group = "moderate" },
      casts = {
        cast{ name = "Arugal's Curse", dispel = "curse", cc = true, hits = "target", note = "Turns a player into a worgen that attacks the group. Decurse it. Without a decurser, the group off-tanks their friend until it wears off." },
        cast{ name = "Void Bolt", hits = "target", kick = 1, shield = "target", note = "A heavy shadow bolt. Kick it when he is in range; otherwise shield whoever he faces." },
        cast{ name = "Thundershock", hits = "group", note = "Arcane damage and a knockback to everyone near him. Stay off the stairs." },
        cast{ name = "Shadow Port", note = "He teleports around the room every so often: melee chase, ranged keep hitting." },
      },
      healer = { "Stand where a knockback does not throw you off the walkway.", "Void Bolt is the damage: kick it or shield the target. The curse is a decurser's job, not yours." } },
  },
  trash = {
    { name = "Shadowfang Darksouls and Moonwalkers", casts = {
        cast{ name = "Befuddlement", dispel = "magic", cc = true, hits = "target", note = "A short confusion. Dispel off the tank." },
        cast{ name = "Anti-Magic Shield", note = "Moonwalkers go spell-immune for a moment; melee only." } } },
    { name = "Wailing Guardsmen and Bleak Worgs", casts = {
        cast{ name = "Screams of the Past", dispel = "magic", hits = "group", note = "A silence on everyone near them. Dispel yourself first, then the other casters." },
        cast{ name = "Wavering Will", dispel = "magic", hits = "target", note = "Lowers stats. Dispel when idle." } } },
    { name = "Sons of Arugal", casts = {
        cast{ name = "Arugal's Gift", hits = "target", kick = 2, note = "Shadow damage. They wander the halls after Fenrus dies." } } },
  },
  quests = {
    { title = "Deathstalkers in Shadowfang", order = 1, side = "H", goal = "Find Deathstalker Adamant (in a cell past Rethilgore) and Deathstalker Vincent (dead, just inside the gate).",
      giver = "High Executor Hadrec, the Sepulcher", turnin = "High Executor Hadrec, the Sepulcher" },
    { title = "The Book of Ur", order = 2, side = "H", goal = "Take the Book of Ur from the shelf in the library, past Baron Silverlaine.",
      giver = "Keeper Bel'dugur, Undercity (Apothecarium)", turnin = "Keeper Bel'dugur, Undercity" },
    { title = "Arugal Must Die", order = 3, side = "H", goal = "Kill Archmage Arugal and bring back his head.",
      giver = "Dalar Dawnweaver, the Sepulcher", turnin = "Dalar Dawnweaver, the Sepulcher" },
    { title = "The Orb of Soran'ruk", order = 4, class = "WARLOCK", goal = "3 Soran'ruk Fragments from the Shadowfang Darksouls and Moonwalkers here, plus a large fragment from the Twilight acolytes in Blackfathom Deeps.",
      giver = "Your warlock trainer's quest line (Horde: Takar the Seer; Alliance: Gakin the Darkbinder, Stormwind)", turnin = "The same warlock" },
  },
}
