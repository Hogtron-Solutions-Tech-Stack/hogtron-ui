-- Attunements and keys: what lets you into a dungeon or raid, and the steps to it.
--
-- SOURCES
--   Classic raids / keys: quest and item ids as the 2004-2006 game had them (cross-checked against the public
--   Perpetua guild addon's list for WoW Classic: Forever, github.com/damndionic360/Perpetua, Data.lua). The ids are
--   what the client is asked about: C_QuestLog.IsQuestFlaggedCompleted(id) / GetItemCount(id).
--   Forever's new dungeons: chains seen on screen in play (the Attune addon's graph, Horde side, 2026-10-08 clip) -
--   TITLES ONLY, no ids, partial = true. A title is matched against YOUR quest log (active / ready); a finished
--   step can only be told when the game hands us an id. NOT VERIFIED beyond what the screen showed.
--
-- Shape: { key, name, group = "raid" | "key" | "dungeon", how = one line, dungeon = Atlas dungeon key when there is
--   one, any = true when ONE done step is enough (Onyxia: either side's quest, or the amulet), partial, unverified,
--   steps = { { title, quest = id | { A = id, H = id }, item = id, side = "A" | "H", kind = "quest" | "item" |
--   "kill" | "level", where = "zone", level = n } } in order.
local A = HogHealsAtlas
A.Data = A.Data or {}

A.Data.Attunements = {
  -- ---------------------------------------------------------------------------------------------------- raids
  { key = "ony", name = "Onyxia's Lair", group = "raid", how = "Drakefire Amulet (each side's own chain)", any = true,
    steps = { { title = "Drakefire Amulet", quest = { A = 6502, H = 6602 }, kind = "quest", where = "Burning Steppes / Dustwallow" },
      { title = "Drakefire Amulet (in your bags)", item = 16309, kind = "item" } } },
  { key = "mc", name = "Molten Core", group = "raid", how = "Attunement to the Core (Lothos Riftwaker, Blackrock Mountain)",
    steps = { { title = "Attunement to the Core", quest = 7848, kind = "quest", where = "Blackrock Depths" } } },
  { key = "bwl", name = "Blackwing Lair", group = "raid", how = "Blackhand's Command (Upper Blackrock Spire)",
    steps = { { title = "Blackhand's Command", quest = 7761, kind = "quest", where = "Upper Blackrock Spire" } } },
  { key = "naxx", name = "Naxxramas", group = "raid", how = "The Dread Citadel - Argent Dawn standing (Light's Hope Chapel)", any = true,
    steps = { { title = "The Dread Citadel - Naxxramas (Honored)", quest = 9121, kind = "quest", where = "Light's Hope Chapel" },
      { title = "The Dread Citadel - Naxxramas (Revered)", quest = 9122, kind = "quest", where = "Light's Hope Chapel" },
      { title = "The Dread Citadel - Naxxramas (Exalted)", quest = 9123, kind = "quest", where = "Light's Hope Chapel" } } },
  -- ---------------------------------------------------------------------------------------------------- keys
  { key = "ubrs", name = "Upper Blackrock Spire", group = "key", dungeon = "ubrs", how = "Seal of Ascension (one in the group)", any = true,
    steps = { { title = "Seal of Ascension", quest = 4743, kind = "quest", where = "Lower Blackrock Spire" },
      { title = "Seal of Ascension (in your bags)", item = 12344, kind = "item" } } },
  { key = "scholo", name = "Scholomance", group = "key", dungeon = "scholo", how = "Skeleton Key", any = true,
    steps = { { title = "The Key to Scholomance", quest = { A = 5505, H = 5511 }, kind = "quest", where = "Western Plaguelands" },
      { title = "Skeleton Key (in your bags)", item = 13704, kind = "item" } } },
  { key = "strat", name = "Stratholme", group = "key", dungeon = "strat_live", how = "Key to the City (the side gate; the front is open)",
    steps = { { title = "Key to the City (in your bags)", item = 12382, kind = "item", where = "Stratholme, Magistrate Barthilas" } } },
  { key = "brd", name = "Blackrock Depths", group = "key", dungeon = "brd", how = "Shadowforge Key (the inner doors)",
    steps = { { title = "Shadowforge Key (in your bags)", item = 11000, kind = "item", where = "Blackrock Depths, Dark Keeper" } } },
  { key = "dm", name = "Dire Maul", group = "key", dungeon = "dm_n", how = "Crescent Key (West and North)",
    steps = { { title = "Crescent Key (in your bags)", item = 18249, kind = "item", where = "Dire Maul East, Pusillin" } } },
  { key = "mcrunes", name = "Molten Core runes", group = "key", how = "Aqual or Eternal Quintessence (dousing the runes)", any = true,
    steps = { { title = "Aqual Quintessence (in your bags)", item = 17333, kind = "item", where = "Duke Hydraxis, Azshara" },
      { title = "Eternal Quintessence (in your bags)", item = 22754, kind = "item" } } },
  -- ---------------------------------------------------------------------------------------------------- Forever
  { key = "dalaran", name = "City of Dalaran", group = "dungeon", dungeon = "dalaran", partial = true, unverified = true,
    how = "Dungeon quest chain (28-32). Seen on Forever, Horde side; the graph was cut off on screen - this is the part that showed.",
    steps = { { title = "Source of Power", kind = "quest", side = "H", where = "Undercity" },
      { title = "The Grave Knight", kind = "quest", side = "H", where = "Hillsbrad Foothills" },
      { title = "Cracked Sentry Core", kind = "item", where = "City of Dalaran" },
      { title = "Atrexis the Grave Knight", kind = "kill", where = "City of Dalaran" } } },
}
