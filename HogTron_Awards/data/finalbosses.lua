-- HogTron Awards: which boss kill ends a run. Boss names as the client reports them in ENCOUNTER_END / BOSS_KILL
-- (enUS). Classic dungeons and raids plus the TBC raids; anything missing ends by LFG_COMPLETION_REWARD or by hand
-- (/hh awards end). Instances where every boss must die (no single last boss) list them under `all`.
-- The old game's lists, not measured on WoW: Forever - Forever's new dungeons (Ruins of Lordaeron, Dalaran, ...) are
-- not here yet: their boss names are unknown until someone runs them with /hh awards probe on.
HogTronAwards = HogTronAwards or {}
local A = HogTronAwards

A.FINAL = {
  -- dungeons
  ["Ragefire Chasm"] = { all = { "Oggleflint", "Taragaman the Hungerer", "Jergosh the Invoker", "Bazzalan" } },
  ["Wailing Caverns"] = { "Mutanus the Devourer" },
  ["The Deadmines"] = { "Edwin VanCleef" },
  ["Shadowfang Keep"] = { "Archmage Arugal" },
  ["Blackfathom Deeps"] = { "Aku'mai" },
  ["The Stockade"] = { all = { "Targorr the Dread", "Kam Deepfury", "Hamhock", "Bazil Thredd", "Dextren Ward" } },
  ["Gnomeregan"] = { "Mekgineer Thermaplugg" },
  ["Razorfen Kraul"] = { "Charlga Razorflank" },
  ["Scarlet Monastery"] = { "Bloodmage Thalnos", "Arcanist Doan", "Herod", "High Inquisitor Whitemane" },
  ["Razorfen Downs"] = { "Amnennar the Coldbringer" },
  ["Uldaman"] = { "Archaedas" },
  ["Zul'Farrak"] = { "Chief Ukorz Sandscalp" },
  ["Maraudon"] = { "Princess Theradras" },
  ["Sunken Temple"] = { "Shade of Eranikus" },
  ["The Temple of Atal'Hakkar"] = { "Shade of Eranikus" },
  ["Blackrock Depths"] = { "Emperor Dagran Thaurissan" },
  ["Blackrock Spire"] = { "Overlord Wyrmthalak", "General Drakkisath" },
  ["Dire Maul"] = { "Alzzin the Wildshaper", "Prince Tortheldrin", "King Gordok" },
  ["Scholomance"] = { "Darkmaster Gandling" },
  ["Stratholme"] = { "Baron Rivendare", "Balnazzar" },
  -- raids
  ["Molten Core"] = { "Ragnaros" },
  ["Onyxia's Lair"] = { "Onyxia" },
  ["Blackwing Lair"] = { "Nefarian" },
  ["Zul'Gurub"] = { "Hakkar" },
  ["Ruins of Ahn'Qiraj"] = { "Ossirian the Unscarred" },
  ["Ahn'Qiraj Temple"] = { "C'Thun" },
  ["Temple of Ahn'Qiraj"] = { "C'Thun" },
  ["Naxxramas"] = { "Kel'Thuzad" },
  ["Karazhan"] = { "Prince Malchezaar" },
  ["Gruul's Lair"] = { "Gruul the Dragonkiller" },
  ["Magtheridon's Lair"] = { "Magtheridon" },
  ["Serpentshrine Cavern"] = { "Lady Vashj" },
  ["Tempest Keep"] = { "Kael'thas Sunstrider" },
  ["The Eye"] = { "Kael'thas Sunstrider" },
  ["Hyjal Summit"] = { "Archimonde" },
  ["Black Temple"] = { "Illidan Stormrage" },
  ["Zul'Aman"] = { "Zul'jin" },
  ["Sunwell Plateau"] = { "Kil'jaeden" },
}

--- Does killing `boss` in `instance` end the run? killed = set of bosses down this run (for `all` instances).
function A.IsFinalKill(instance, boss, killed)
  local spec = A.FINAL[instance or ""]
  if not spec or type(boss) ~= "string" then return false end
  if spec.all then
    for _, b in ipairs(spec.all) do if b ~= boss and not (killed and killed[b]) then return false end end
    for _, b in ipairs(spec.all) do if b == boss then return true end end
    return false
  end
  for _, b in ipairs(spec) do if b == boss then return true end end
  return false
end
