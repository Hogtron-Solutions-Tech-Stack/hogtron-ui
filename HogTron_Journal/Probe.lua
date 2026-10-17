-- Probe: what does this client's Encounter Journal API offer? Measured, never assumed; written to
-- HogHealsDB.global.journal_probe at login (+8 s) and on /hh journal probe, so the answer is on disk for the next
-- read even if nobody pastes it.
--
-- Known so far (Atlas sweep, 2026-09-29, Forever 1.60.1): the functions exist, EJ_GetTierInfo(1) throws
-- "Invalid index", the list is empty, and ids 1..1500 asked by EJ_GetInstanceInfo all answered nothing. This probe
-- also asks the OLD journal ids of the classic dungeons by name (Deadmines 63, Wailing Caverns 240 ...) in case
-- Forever's data is keyed like retail's. A verdict line says which of three worlds we are in.
local J = HogHealsJournal
local HH = HogHeals

local Probe = {}
J.Probe = Probe

Probe.FUNCS = {
  "EJ_GetNumTiers", "EJ_GetCurrentTier", "EJ_GetTierInfo", "EJ_SelectTier", "EJ_GetInstanceByIndex", "EJ_SelectInstance",
  "EJ_GetInstanceInfo", "EJ_GetEncounterInfoByIndex", "EJ_GetEncounterInfo", "EJ_SelectEncounter", "EJ_GetSectionInfo",
  "EJ_GetCreatureInfo", "EJ_GetInstanceForMap", "EJ_GetNumLoot", "EJ_InstanceIsRaid",
  "C_EncounterJournal.GetSectionInfo", "C_EncounterJournal.GetEncountersOnMap", "C_EncounterJournal.GetLootInfoByIndex",
  "C_EncounterJournal.GetInstanceForGameMap", "C_EncounterJournal.IsEncounterComplete", "C_EncounterJournal.GetDungeonEntrancesForMap",
  "C_AdventureJournal.GetNumAvailableSuggestions", "C_LFGList.GetAvailableActivities",
}
-- retail's journal ids for the old dungeons: a direct question, not a sweep
Probe.OLD_IDS = { { 63, "The Deadmines" }, { 240, "Wailing Caverns" }, { 226, "Ragefire Chasm" }, { 64, "Shadowfang Keep" },
  { 238, "The Stockade" }, { 227, "Blackfathom Deeps" }, { 231, "Gnomeregan" }, { 234, "Razorfen Kraul" }, { 316, "Scarlet Monastery" },
  { 233, "Razorfen Downs" }, { 239, "Uldaman" }, { 241, "Zul'Farrak" }, { 232, "Maraudon" }, { 237, "Sunken Temple" },
  { 228, "Blackrock Depths" }, { 229, "Lower Blackrock Spire" }, { 230, "Dire Maul" }, { 236, "Stratholme" }, { 246, "Scholomance" } }

local function describe(v)
  if J.isSecret(v) then return "SECRET(" .. type(v) .. ")" end
  if type(v) == "string" then return '"' .. (#v > 40 and (v:sub(1, 40) .. "...") or v) .. '"' end
  return tostring(v)
end
Probe.describe = describe

--- Call fn(...) and render every return as one string; errors and silence are words, never throws.
local function raw(fn, ...)
  if type(fn) ~= "function" then return "nil fn" end
  local function pack(ok, ...) return ok, select("#", ...), { ... } end
  local ok, n, r = pack(pcall(fn, ...))
  if not ok then return "ERR " .. tostring(r[1]):sub(1, 80) end
  if n == 0 then return "(nothing)" end
  local parts = {}
  for i = 1, math.min(n, 10) do parts[i] = describe(r[i]) end
  return table.concat(parts, " | ")
end
Probe.raw = raw

--- Measure. Returns the table that is also written to HogHealsDB.global.journal_probe.
function Probe.Run(reason)
  local p = { at = J.now(), reason = reason or "manual", fns = {}, present = 0, oldIds = {} }
  local _, build, _, toc = J.call(rawget(_G, "GetBuildInfo"))
  p.build, p.toc = J.str(build) or "?", J.num(toc) or 0
  for _, name in ipairs(Probe.FUNCS) do
    local f = J.fn(name)
    p.fns[name] = f and "function" or "nil"
    if f then p.present = p.present + 1 end
  end
  local inCombat = J.plain(J.call(rawget(_G, "InCombatLockdown"))) == true
  if p.present > 0 and not inCombat then
    p.tiers = raw(J.fn("EJ_GetNumTiers"))
    p.currentTier = raw(J.fn("EJ_GetCurrentTier"))
    p.tier1 = raw(J.fn("EJ_GetTierInfo"), 1)
    J.call(J.fn("EJ_SelectTier"), 1)
    p.listedDungeon1 = raw(J.fn("EJ_GetInstanceByIndex"), 1, false)
    p.listedRaid1 = raw(J.fn("EJ_GetInstanceByIndex"), 1, true)
    p.instance1 = raw(J.fn("EJ_GetInstanceInfo"), 1)
    local answered = 0
    for _, pair in ipairs(Probe.OLD_IDS) do
      local name = J.str((J.call(J.fn("EJ_GetInstanceInfo"), pair[1])))
      local line = raw(J.fn("EJ_GetInstanceInfo"), pair[1])
      if name and name ~= "" then
        answered = answered + 1
        J.call(J.fn("EJ_SelectInstance"), pair[1])
        line = line .. " ; boss1=" .. raw(J.fn("EJ_GetEncounterInfoByIndex"), 1, pair[1])
      end
      p.oldIds[#p.oldIds + 1] = ("%d %s -> %s"):format(pair[1], pair[2], line)
    end
    p.oldIdsAnswered = answered
    local map = J.call(J.fn("C_Map.GetBestMapForUnit"), "player")
    p.bestMap = describe(map)
    p.instanceForMap = raw(J.fn("EJ_GetInstanceForMap"), J.num(map) or 0)
    p.encountersOnMap = raw(J.fn("C_EncounterJournal.GetEncountersOnMap"), J.num(map) or 0)
  elseif inCombat then
    p.skipped = "in combat: the journal was not asked"
  end
  local w = J.Where()
  p.where = w and ("%s inst=%s name=%s%s"):format(w.kind, tostring(w.inst), tostring(w.name), w.secret and " (SECRET parts)" or "") or "not in an instance"
  p.whereRaw = raw(rawget(_G, "GetInstanceInfo"))
  -- the verdict the implementation branches on
  if p.present == 0 then
    p.verdict = "NO EJ API: no EJ_* / C_EncounterJournal function exists. Shipped tables only."
  elseif (p.oldIdsAnswered or 0) > 0 then
    p.verdict = ("EJ ANSWERS: %d of %d old dungeon ids returned a name. The journal can be read on this client."):format(p.oldIdsAnswered, #Probe.OLD_IDS)
  elseif p.skipped then
    p.verdict = "EJ present, not asked (combat). Run /hh journal probe out of combat."
  else
    p.verdict = ("EJ PRESENT BUT EMPTY: %d functions exist, no tier, no listed instance, no old id answers. Shipped tables only."):format(p.present)
  end
  Probe.last = p
  local g = HH.db and HH.db.global
  if g then g.journal_probe = p end
  return p
end

--- Chat lines for /hh journal probe (short: the full table is in the saved file).
function Probe.Report()
  local p = Probe.last or (HH.db and HH.db.global and HH.db.global.journal_probe)
  if not p then return { "journal probe: not run yet" } end
  local out = {
    ("journal probe (%s, build %s toc %s): %s"):format(tostring(p.at), tostring(p.build), tostring(p.toc), tostring(p.verdict)),
    ("  functions present: %d/%d; tiers=%s; tier1=%s; listed dungeon 1=%s"):format(p.present or 0, #Probe.FUNCS, tostring(p.tiers), tostring(p.tier1), tostring(p.listedDungeon1)),
    ("  instance 1=%s; old ids answered=%s; where=%s"):format(tostring(p.instance1), tostring(p.oldIdsAnswered), tostring(p.where)),
    "  full table: SavedVariables HogHeals.lua -> HogHealsDB.global.journal_probe (written at logout / reload)",
  }
  return out
end
