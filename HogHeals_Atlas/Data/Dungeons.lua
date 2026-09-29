-- Starting list of dungeons: name, where, who, level range, bosses in the usual kill order.
--
-- SOURCE: the 2004-2006 game (Classic). NOT VERIFIED ON FOREVER: Blizzard changed loot, added dungeons, and may
-- have moved level ranges. The game's own answers replace these wherever it gives them (Levels.lua reads Group
-- Finder, Journal.lua reads the dungeon journal, Capture.lua learns bosses as they die). Entries with
-- unverified = true are new in Forever; their boss lists are empty until seen in play.
--
-- inst = instance map id (8th return of GetInstanceInfo). Several dungeons share one id (the Scarlet Monastery
-- wings, Blackrock Spire, Dire Maul, Stratholme): a drop is filed by boss name first, by id second.
-- faction: "A" / "H" = only that side can reach it in the old world; nil = both.
local A = HogHealsAtlas

A.Data = A.Data or {}

A.Data.Dungeons = {
  { key = "rfc", name = "Ragefire Chasm", inst = 389, min = 13, max = 18, enter = 8, zone = "Orgrimmar", continent = "Kalimdor", faction = "H",
    where = "Inside Orgrimmar, Cleft of Shadow.",
    bosses = { "Oggleflint", "Taragaman the Hungerer", "Jergosh the Invoker", "Bazzalan" } },
  { key = "wc", name = "Wailing Caverns", inst = 43, min = 17, max = 24, enter = 10, zone = "The Barrens", continent = "Kalimdor",
    where = "The Barrens, cave above the oasis south-west of the Crossroads.",
    bosses = { "Lady Anacondra", "Lord Cobrahn", "Kresh", "Lord Pythas", "Skum", "Lord Serpentis", "Verdan the Everliving", "Mutanus the Devourer" },
    rares = { "Deviate Faerie Dragon" } },
  { key = "vc", name = "The Deadmines", inst = 36, min = 17, max = 26, enter = 10, zone = "Westfall", continent = "Eastern Kingdoms", faction = "A",
    where = "Westfall, Moonbrook, through the barn into the mine.",
    bosses = { "Rhahk'Zor", "Sneed's Shredder", "Gilnid", "Mr. Smite", "Cookie", "Captain Greenskin", "Edwin VanCleef" },
    rares = { "Miner Johnson" } },
  { key = "sfk", name = "Shadowfang Keep", inst = 33, min = 22, max = 30, enter = 14, zone = "Silverpine Forest", continent = "Eastern Kingdoms", faction = "H",
    where = "Silverpine Forest, south of the Sepulcher, near Pyrewood Village.",
    bosses = { "Rethilgore", "Razorclaw the Butcher", "Baron Silverlaine", "Commander Springvale", "Odo the Blindwatcher", "Fenrus the Devourer", "Wolf Master Nandos", "Archmage Arugal" } },
  { key = "bfd", name = "Blackfathom Deeps", inst = 48, min = 24, max = 32, enter = 15, zone = "Ashenvale", continent = "Kalimdor",
    where = "Ashenvale, Zoram Strand on the west coast.",
    bosses = { "Ghamoo-ra", "Lady Sarevess", "Gelihast", "Lorgus Jett", "Baron Aquanis", "Twilight Lord Kelris", "Old Serra'kis", "Aku'mai" } },
  { key = "stocks", name = "The Stockade", inst = 34, min = 24, max = 32, enter = 15, zone = "Stormwind City", continent = "Eastern Kingdoms", faction = "A",
    where = "Inside Stormwind, the Mage Quarter side of the canals.",
    bosses = { "Targorr the Dread", "Kam Deepfury", "Hamhock", "Bazil Thredd", "Dextren Ward" },
    rares = { "Bruegal Ironknuckle" } },
  { key = "gnomer", name = "Gnomeregan", inst = 90, min = 29, max = 38, enter = 19, zone = "Dun Morogh", continent = "Eastern Kingdoms", faction = "A",
    where = "Dun Morogh, west of Kharanos. Horde arrive by the teleporter in Booty Bay.",
    bosses = { "Grubbis", "Viscous Fallout", "Electrocutioner 6000", "Crowd Pummeler 9-60", "Mekgineer Thermaplugg" },
    rares = { "Dark Iron Ambassador" } },
  { key = "rfk", name = "Razorfen Kraul", inst = 47, min = 29, max = 38, enter = 17, zone = "The Barrens", continent = "Kalimdor",
    where = "Southern Barrens, at the border with Thousand Needles.",
    bosses = { "Roogug", "Aggem Thorncurse", "Death Speaker Jargba", "Overlord Ramtusk", "Agathelos the Raging", "Charlga Razorflank" },
    rares = { "Earthcaller Halmgar", "Blind Hunter" } },
  { key = "sm_gy", name = "Scarlet Monastery: Graveyard", inst = 189, min = 28, max = 38, enter = 20, zone = "Tirisfal Glades", continent = "Eastern Kingdoms",
    where = "Tirisfal Glades, north-east corner. First door on the left.",
    bosses = { "Interrogator Vishas", "Bloodmage Thalnos" },
    rares = { "Azshir the Sleepless", "Fallen Champion", "Ironspine" } },
  { key = "sm_lib", name = "Scarlet Monastery: Library", inst = 189, min = 29, max = 39, enter = 20, zone = "Tirisfal Glades", continent = "Eastern Kingdoms",
    where = "Tirisfal Glades, north-east corner.",
    bosses = { "Houndmaster Loksey", "Arcanist Doan" } },
  { key = "sm_arm", name = "Scarlet Monastery: Armory", inst = 189, min = 32, max = 42, enter = 20, zone = "Tirisfal Glades", continent = "Eastern Kingdoms",
    where = "Tirisfal Glades, north-east corner. Needs The Scarlet Key.",
    bosses = { "Herod" } },
  { key = "sm_cath", name = "Scarlet Monastery: Cathedral", inst = 189, min = 35, max = 45, enter = 20, zone = "Tirisfal Glades", continent = "Eastern Kingdoms",
    where = "Tirisfal Glades, north-east corner. Needs The Scarlet Key.",
    bosses = { "High Inquisitor Fairbanks", "Scarlet Commander Mograine", "High Inquisitor Whitemane" } },
  { key = "rfd", name = "Razorfen Downs", inst = 129, min = 37, max = 46, enter = 25, zone = "The Barrens", continent = "Kalimdor",
    where = "Southern Barrens, east of Razorfen Kraul.",
    bosses = { "Tuten'kash", "Mordresh Fire Eye", "Glutton", "Amnennar the Coldbringer" },
    rares = { "Ragglesnout" } },
  { key = "ulda", name = "Uldaman", inst = 70, min = 41, max = 51, enter = 30, zone = "Badlands", continent = "Eastern Kingdoms",
    where = "Badlands, north edge; back door further east.",
    bosses = { "Revelosh", "Baelog", "Eric \"The Swift\"", "Olaf", "Ironaya", "Obsidian Sentinel", "Ancient Stone Keeper", "Galgann Firehammer", "Grimlok", "Archaedas" } },
  { key = "zf", name = "Zul'Farrak", inst = 209, min = 44, max = 54, enter = 35, zone = "Tanaris", continent = "Kalimdor",
    where = "Tanaris, north-west corner.",
    bosses = { "Antu'sul", "Theka the Martyr", "Witch Doctor Zum'rah", "Nekrum Gutchewer", "Shadowpriest Sezz'ziz", "Sergeant Bly", "Hydromancer Velratha", "Gahz'rilla", "Ruuzlu", "Chief Ukorz Sandscalp" } },
  { key = "mara", name = "Maraudon", inst = 349, min = 46, max = 55, enter = 30, zone = "Desolace", continent = "Kalimdor",
    where = "Desolace, Valley of Spears. Orange and purple wings meet at the inner waterfall.",
    bosses = { "Noxxion", "Razorlash", "Lord Vyletongue", "Celebras the Cursed", "Landslide", "Tinkerer Gizlock", "Rotgrip", "Princess Theradras" },
    rares = { "Meshlok the Harvester" } },
  { key = "st", name = "Sunken Temple", inst = 109, min = 50, max = 56, enter = 35, zone = "Swamp of Sorrows", continent = "Eastern Kingdoms",
    where = "Swamp of Sorrows, under the lake in the middle (Temple of Atal'Hakkar).",
    bosses = { "Atal'alarion", "Dreamscythe", "Weaver", "Jammal'an the Prophet", "Ogom the Wretched", "Morphaz", "Hazzas", "Avatar of Hakkar", "Shade of Eranikus" } },
  { key = "brd", name = "Blackrock Depths", inst = 230, min = 52, max = 60, enter = 40, zone = "Blackrock Mountain", continent = "Eastern Kingdoms",
    where = "Blackrock Mountain, down the chain to the lowest level.",
    bosses = { "High Interrogator Gerstahn", "Lord Roccor", "Houndmaster Grebmar", "Ring of Law", "Pyromancer Loregrain", "Lord Incendius", "Warder Stilgiss", "Fineous Darkvire", "Bael'Gar", "General Angerforge", "Golem Lord Argelmach", "Hurley Blackbreath", "Phalanx", "Ribbly Screwspigot", "Plugger Spazzring", "Ambassador Flamelash", "The Seven", "Magmus", "Emperor Dagran Thaurissan", "Princess Moira Bronzebeard" } },
  { key = "lbrs", name = "Lower Blackrock Spire", inst = 229, min = 55, max = 60, enter = 45, zone = "Blackrock Mountain", continent = "Eastern Kingdoms",
    where = "Blackrock Mountain, upper ring, the balcony door.",
    bosses = { "Highlord Omokk", "Shadow Hunter Vosh'gajin", "War Master Voone", "Mother Smolderweb", "Urok Doomhowl", "Quartermaster Zigris", "Halycon", "Gizrul the Slavener", "Overlord Wyrmthalak" } },
  { key = "ubrs", name = "Upper Blackrock Spire", inst = 229, min = 55, max = 60, enter = 45, zone = "Blackrock Mountain", continent = "Eastern Kingdoms", size = 10,
    where = "Blackrock Mountain, same door as the lower spire. Needs the Seal of Ascension.",
    bosses = { "Pyroguard Emberseer", "Solakar Flamewreath", "Goraluk Anvilcrack", "Warchief Rend Blackhand", "Gyth", "The Beast", "General Drakkisath" },
    rares = { "Jed Runewatcher" } },
  { key = "dm_e", name = "Dire Maul: East", inst = 429, min = 55, max = 60, enter = 45, zone = "Feralas", continent = "Kalimdor",
    where = "Feralas, centre of the zone. East wing.",
    bosses = { "Pusillin", "Zevrim Thornhoof", "Hydrospawn", "Lethtendris", "Alzzin the Wildshaper" } },
  { key = "dm_w", name = "Dire Maul: West", inst = 429, min = 57, max = 60, enter = 45, zone = "Feralas", continent = "Kalimdor",
    where = "Feralas, centre of the zone. West wing, needs the Crescent Key.",
    bosses = { "Tendris Warpwood", "Illyanna Ravenoak", "Magister Kalendris", "Immol'thar", "Prince Tortheldrin" },
    rares = { "Tsu'zee" } },
  { key = "dm_n", name = "Dire Maul: North", inst = 429, min = 57, max = 60, enter = 45, zone = "Feralas", continent = "Kalimdor",
    where = "Feralas, centre of the zone. North wing, needs the Crescent Key.",
    bosses = { "Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik", "Captain Kromcrush", "Cho'Rush the Observer", "King Gordok" } },
  { key = "strat_live", name = "Stratholme: Live", inst = 329, min = 58, max = 60, enter = 45, zone = "Eastern Plaguelands", continent = "Eastern Kingdoms",
    where = "Eastern Plaguelands, north-west. Main gate.",
    bosses = { "Hearthsinger Forresten", "The Unforgiven", "Timmy the Cruel", "Malor the Zealous", "Cannon Master Willey", "Archivist Galford", "Balnazzar" },
    rares = { "Skul" } },
  { key = "strat_ud", name = "Stratholme: Undead", inst = 329, min = 58, max = 60, enter = 45, zone = "Eastern Plaguelands", continent = "Eastern Kingdoms",
    where = "Eastern Plaguelands, north. Service gate, needs the Key to the City.",
    bosses = { "Magistrate Barthilas", "Nerub'enkan", "Baroness Anastari", "Maleki the Pallid", "Ramstein the Gorger", "Baron Rivendare" },
    rares = { "Stonespine" } },
  { key = "scholo", name = "Scholomance", inst = 289, min = 58, max = 60, enter = 45, zone = "Western Plaguelands", continent = "Eastern Kingdoms",
    where = "Western Plaguelands, Caer Darrow island. Needs the Skeleton Key.",
    bosses = { "Kirtonos the Herald", "Jandice Barov", "Rattlegore", "Marduk Blackpool", "Vectus", "Ras Frostwhisper", "Instructor Malicia", "Doctor Theolen Krastinov", "Lorekeeper Polkelt", "The Ravenian", "Lord Alexei Barov", "Lady Illucia Barov", "Darkmaster Gandling" } },

  -- New in Forever. Level ranges from Group Finder as players reported them; bosses unknown until seen.
  { key = "lordaeron", name = "Ruins of Lordaeron", inst = 2999, min = 17, max = 21, enter = 11, zone = "Tirisfal Glades", continent = "Eastern Kingdoms", faction = "H",
    where = "Tirisfal Glades. New in Forever.", unverified = true, bosses = {} },
  { key = "dalaran", name = "Dalaran", min = 25, max = 30, enter = 20, zone = "Alterac Mountains", continent = "Eastern Kingdoms", faction = "A",
    where = "New in Forever. Not open in beta when this list was written.", unverified = true, bosses = {} },
}

A.Data.byKey, A.Data.byInst, A.Data.byName = {}, {}, {}
for _, d in ipairs(A.Data.Dungeons) do
  A.Data.byKey[d.key] = d
  A.Data.byName[d.name:lower()] = d
  if d.inst then
    A.Data.byInst[d.inst] = A.Data.byInst[d.inst] or {}
    table.insert(A.Data.byInst[d.inst], d)
  end
end

--- Dungeon + index for a boss name (exact, case-blind). Rares count.
function A.Data.FindBoss(name, inst)
  if type(name) ~= "string" then return nil end
  local want = name:lower()
  local pool = (inst and A.Data.byInst[inst]) or A.Data.Dungeons
  for _, d in ipairs(pool) do
    for i, b in ipairs(d.bosses) do if b:lower() == want then return d, i, b end end
    for _, b in ipairs(d.rares or {}) do if b:lower() == want then return d, 0, b end end
  end
  if inst then return A.Data.FindBoss(name, nil) end
end
