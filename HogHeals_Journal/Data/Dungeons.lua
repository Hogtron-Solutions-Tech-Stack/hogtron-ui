-- Hand-written healer notes per dungeon. ONE dungeon ships in 0.1 (Wailing Caverns) as the proof of concept.
--
-- SOURCE: the 2004-2006 game as the authors remember playing it. Written by hand for this MIT addon; no text,
-- table or file was copied from Wowhead, the Encounter Journal, or any other addon. NOT VERIFIED ON FOREVER:
-- Blizzard may have changed a boss, a cast, a quest or a level range. The window labels every page "old game,
-- hand-written" until a run on Forever confirms it. Fix what play proves wrong; do not add from memory alone.
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

J.Data.Dungeons[#J.Data.Dungeons + 1] = {
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
