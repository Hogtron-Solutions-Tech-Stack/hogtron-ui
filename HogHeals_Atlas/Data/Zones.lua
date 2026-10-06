-- Zones: name, continent, level range, home side, neighbours. For "Where next": which zones fit your level and how
-- far a dungeon is from where you stand (same zone < next door < same continent < across the sea).
--
-- SOURCE: the 2004-2006 game (Classic). NOT VERIFIED ON FOREVER: Blizzard may have moved ranges or opened new
-- zones; the window says so. faction: "A" / "H" = that side's home zone; nil = contested / both.
-- near = zones you walk into from this one (by name). Cities carry no level range.
local A = HogHealsAtlas
A.Data = A.Data or {}

local function z(name, continent, min, max, faction, near)
  return { name = name, continent = continent, min = min, max = max, faction = faction, near = near or {} }
end

local EK, KAL = "Eastern Kingdoms", "Kalimdor"

A.Data.Zones = {
  -- Eastern Kingdoms
  z("Elwynn Forest", EK, 1, 10, "A", { "Westfall", "Redridge Mountains", "Duskwood", "Stormwind City" }),
  z("Dun Morogh", EK, 1, 10, "A", { "Loch Modan", "Ironforge" }),
  z("Tirisfal Glades", EK, 1, 10, "H", { "Silverpine Forest", "Western Plaguelands", "Undercity" }),
  z("Westfall", EK, 10, 20, "A", { "Elwynn Forest", "Duskwood" }),
  z("Loch Modan", EK, 10, 20, "A", { "Dun Morogh", "Wetlands", "Badlands", "Searing Gorge" }),
  z("Silverpine Forest", EK, 10, 20, "H", { "Tirisfal Glades", "Hillsbrad Foothills" }),
  z("Redridge Mountains", EK, 15, 25, "A", { "Elwynn Forest", "Duskwood", "Burning Steppes" }),
  z("Duskwood", EK, 18, 30, "A", { "Westfall", "Elwynn Forest", "Redridge Mountains", "Stranglethorn Vale", "Deadwind Pass" }),
  z("Wetlands", EK, 20, 30, "A", { "Loch Modan", "Arathi Highlands", "Dun Morogh" }),
  z("Hillsbrad Foothills", EK, 20, 30, nil, { "Silverpine Forest", "Alterac Mountains", "Arathi Highlands", "The Hinterlands" }),
  z("Alterac Mountains", EK, 30, 40, nil, { "Hillsbrad Foothills", "Western Plaguelands" }),
  z("Arathi Highlands", EK, 30, 40, nil, { "Hillsbrad Foothills", "Wetlands" }),
  z("Stranglethorn Vale", EK, 30, 45, nil, { "Duskwood" }),
  z("Badlands", EK, 35, 45, nil, { "Loch Modan", "Searing Gorge" }),
  z("Swamp of Sorrows", EK, 35, 45, nil, { "Deadwind Pass", "Blasted Lands" }),
  z("The Hinterlands", EK, 40, 50, nil, { "Hillsbrad Foothills", "Western Plaguelands" }),
  z("Searing Gorge", EK, 43, 50, nil, { "Badlands", "Loch Modan", "Burning Steppes", "Blackrock Mountain" }),
  z("Blasted Lands", EK, 45, 55, nil, { "Swamp of Sorrows" }),
  z("Burning Steppes", EK, 50, 58, nil, { "Searing Gorge", "Redridge Mountains", "Blackrock Mountain" }),
  z("Western Plaguelands", EK, 51, 58, nil, { "Tirisfal Glades", "Alterac Mountains", "Eastern Plaguelands", "The Hinterlands" }),
  z("Eastern Plaguelands", EK, 53, 60, nil, { "Western Plaguelands" }),
  z("Deadwind Pass", EK, 55, 60, nil, { "Duskwood", "Swamp of Sorrows" }),
  z("Blackrock Mountain", EK, 52, 60, nil, { "Searing Gorge", "Burning Steppes" }),
  z("Stormwind City", EK, nil, nil, "A", { "Elwynn Forest" }),
  z("Ironforge", EK, nil, nil, "A", { "Dun Morogh" }),
  z("Undercity", EK, nil, nil, "H", { "Tirisfal Glades" }),
  -- Kalimdor
  z("Durotar", KAL, 1, 10, "H", { "The Barrens", "Orgrimmar" }),
  z("Mulgore", KAL, 1, 10, "H", { "The Barrens", "Thunder Bluff" }),
  z("Teldrassil", KAL, 1, 10, "A", { "Darkshore", "Darnassus" }),
  z("The Barrens", KAL, 10, 25, "H", { "Durotar", "Mulgore", "Ashenvale", "Stonetalon Mountains", "Thousand Needles", "Dustwallow Marsh" }),
  z("Darkshore", KAL, 10, 20, "A", { "Teldrassil", "Ashenvale", "Felwood" }),
  z("Stonetalon Mountains", KAL, 15, 27, nil, { "The Barrens", "Ashenvale", "Desolace" }),
  z("Ashenvale", KAL, 18, 30, nil, { "Darkshore", "The Barrens", "Stonetalon Mountains", "Felwood", "Azshara" }),
  z("Thousand Needles", KAL, 25, 35, nil, { "The Barrens", "Feralas", "Tanaris" }),
  z("Desolace", KAL, 30, 40, nil, { "Stonetalon Mountains", "Feralas" }),
  z("Dustwallow Marsh", KAL, 35, 45, nil, { "The Barrens" }),
  z("Feralas", KAL, 40, 50, nil, { "Desolace", "Thousand Needles" }),
  z("Tanaris", KAL, 40, 50, nil, { "Thousand Needles", "Un'Goro Crater" }),
  z("Azshara", KAL, 45, 55, nil, { "Ashenvale" }),
  z("Felwood", KAL, 48, 55, nil, { "Ashenvale", "Darkshore", "Winterspring", "Moonglade" }),
  z("Un'Goro Crater", KAL, 48, 55, nil, { "Tanaris", "Silithus" }),
  z("Winterspring", KAL, 55, 60, nil, { "Felwood", "Moonglade" }),
  z("Silithus", KAL, 55, 60, nil, { "Un'Goro Crater" }),
  z("Moonglade", KAL, nil, nil, nil, { "Felwood", "Winterspring" }),
  z("Orgrimmar", KAL, nil, nil, "H", { "Durotar" }),
  z("Thunder Bluff", KAL, nil, nil, "H", { "Mulgore" }),
  z("Darnassus", KAL, nil, nil, "A", { "Teldrassil" }),
}

A.Data.zoneByName = {}
for _, e in ipairs(A.Data.Zones) do A.Data.zoneByName[e.name:lower()] = e end

--- A zone entry by name (case-insensitive), or nil for one the list does not know.
function A.Data.Zone(name)
  if type(name) ~= "string" then return nil end
  return A.Data.zoneByName[name:lower()]
end
