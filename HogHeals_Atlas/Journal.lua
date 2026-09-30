-- Journal: reads the client's own dungeon journal into the Store (source "journal").
--
-- Measured on Forever 2026-09-28: the functions EXIST (EJ_SelectInstance, EJ_GetEncounterInfo,
-- C_EncounterJournal.GetLootInfo ...). Whether they ANSWER with Forever's dungeons is not measured yet. So every
-- call is guarded, nothing is assumed, and the outcome of each scan is written to diag.atlasJournal for the next
-- read off disk. No answer = the module carries on with discovery alone.
--
-- A scan changes the journal's own selection (tier / instance / encounter), so it never runs in combat and never
-- while Blizzard's journal window is open.
local A = HogHealsAtlas
local HH = HogHeals

-- Bounds: nobody has seen what Forever's journal lists. If it lists every instance of every later expansion, a
-- scan must still cost a blink, not a freeze: a cap on instances per scan and a time budget, whichever is hit
-- first. A scan that stopped early says so and carries on from there next time.
local Journal = { MAX_INSTANCES = 60, MAX_ENCOUNTERS = 30, MAX_LOOT = 80, BUDGET_MS = 120, passes = 0, MAX_PASSES = 3 }
A.Journal = Journal

local function g(name) local f = rawget(_G, name) if type(f) == "function" then return f end end

function Journal.Available()
  return g("EJ_GetInstanceByIndex") ~= nil and g("EJ_SelectInstance") ~= nil and g("EJ_GetEncounterInfoByIndex") ~= nil
end

local function lootCount() return A.num(A.call(g("EJ_GetNumLoot"))) or 0 end

local function lootAt(i)
  local f = A.fn("C_EncounterJournal.GetLootInfoByIndex")
  if f then
    local t = A.call(f, i)
    if type(t) == "table" then return A.num(t.itemID), A.num(t.encounterID) end
    return nil
  end
  -- older shape: itemID first, encounterID second
  local id, enc = A.call(g("EJ_GetLootInfoByIndex"), i)
  return A.num(id), A.num(enc)
end

--- One instance: its encounters and their loot. Returns bosses found, items found. inst = the instance's map
-- id when the journal gave one: it files wings and renamed dungeons under the right row.
local function scanInstance(jid, name, out, inst)
  A.call(g("EJ_SelectInstance"), jid)
  A.call(g("EJ_ResetLootFilter"))
  A.call(A.fn("C_EncounterJournal.ResetSlotFilter"))
  local bosses, items = 0, 0
  local dkey
  for i = 1, Journal.MAX_ENCOUNTERS do
    local bname, _, encID = A.call(g("EJ_GetEncounterInfoByIndex"), i, jid)
    bname, encID = A.str(bname), A.num(encID)
    if not bname then break end
    dkey = A.Store.DungeonKey(name, inst, bname) or dkey
    if dkey then
      A.Store.AddBoss(dkey, bname, { enc = encID, src = "journal" })
      bosses = bosses + 1
      if encID and g("EJ_SelectEncounter") then
        A.call(g("EJ_SelectEncounter"), encID)
        for n = 1, math.min(lootCount(), Journal.MAX_LOOT) do
          local id = lootAt(n)
          if id then
            if A.Store.Record(dkey, bname, id, "journal") then items = items + 1 end
          end
        end
      end
    end
  end
  out[#out + 1] = ("%s: %d bosses, %d new items"):format(name, bosses, items)
  return bosses, items
end

Journal.ScanInstance = scanInstance

local function ms()
  local f = rawget(_G, "debugprofilestop")
  if type(f) == "function" then local ok, v = pcall(f) if ok and type(v) == "number" then return v end end
  return ((type(GetTime) == "function" and GetTime()) or 0) * 1000
end
Journal.ms = ms

-- ------------------------------------------------------------------------------------------------ asking by id
-- In game 2026-09-29 20:34: "journal is there but lists no dungeons" - EJ_GetInstanceByIndex gave nothing for any
-- tier. A list that is empty does not prove the data is: the journal can also be asked about one instance by its
-- id. So when the list is empty every id from 1 to SWEEP_MAX is asked once (EJ_GetInstanceInfo), a time-boxed
-- slice per pass, and whatever answers with a name and at least one encounter is read like a listed instance.
-- No id is assumed: the sweep finds them or finds nothing, and says which.
Journal.SWEEP_MAX = 1500
Journal.SWEEP_PASSES = 60
Journal.SWEEP_MS = 25          -- per slice: small enough not to be felt as a stutter

local function describe(v)
  if A.isSecret(v) then return "SECRET(" .. type(v) .. ")" end
  if type(v) == "string" then return '"' .. (#v > 40 and (v:sub(1, 40) .. "...") or v) .. '"' end
  return tostring(v)
end

local function raw(fn, ...)
  if type(fn) ~= "function" then return "nil fn" end
  local function pack(ok, ...) return ok, select("#", ...), { ... } end
  local ok, n, r = pack(pcall(fn, ...))
  if not ok then return "ERR " .. tostring(r[1]):sub(1, 70) end
  if n == 0 then return "(nothing)" end
  local parts = {}
  for i = 1, math.min(n, 10) do parts[i] = describe(r[i]) end
  return table.concat(parts, " | ")
end

--- What the journal says when asked the plain questions. Facts for the saved file, nothing is changed by it
-- except the journal's own tier selection.
function Journal.Probe()
  local p = { tiers = raw(g("EJ_GetNumTiers")), currentTier = raw(g("EJ_GetCurrentTier")), tier = {} }
  local n = A.num(A.call(g("EJ_GetNumTiers"))) or 0
  for t = 1, math.min(math.max(n, 1), 12) do
    local line = "info=" .. raw(g("EJ_GetTierInfo"), t)
    A.call(g("EJ_SelectTier"), t)
    line = line .. " ; dungeon1=" .. raw(g("EJ_GetInstanceByIndex"), 1, false) .. " ; raid1=" .. raw(g("EJ_GetInstanceByIndex"), 1, true)
    p.tier[t] = line
  end
  local map = A.call(A.fn("C_Map.GetBestMapForUnit"), "player")
  p.bestMap = describe(map)
  p.instanceForMap = raw(g("EJ_GetInstanceForMap"), A.num(map) or 0)
  p.encountersOnMap = raw(A.fn("C_EncounterJournal.GetEncountersOnMap"), A.num(map) or 0)
  local loaded = A.fn("C_AddOns.IsAddOnLoaded")
  p.journalAddon = raw(loaded, "Blizzard_EncounterJournal")
  p.hasInstanceInfo = type(g("EJ_GetInstanceInfo"))
  return p
end

local function writeSweep(status)
  local gl = HH.db and HH.db.global
  local s = Journal.sweep
  if not gl or not s then return end
  gl.diag = gl.diag or {}
  local hits = {}
  for i = 1, math.min(#s.hits, 60) do hits[i] = s.hits[i] end
  gl.diag.atlasSweep = { at = A.now(), status = status, askedTo = s.at - 1, of = Journal.SWEEP_MAX, passes = s.passes,
    answered = s.answered, dungeons = s.dungeons, raids = s.raids, bosses = s.bosses, items = s.items, hits = hits }
  s.status = status
end

--- One time-boxed slice of the sweep. Returns true while there is more to ask.
function Journal.SweepPass()
  local s = Journal.sweep
  if not s or s.finished then return false end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then writeSweep("waiting: in combat") return true end
  local info = g("EJ_GetInstanceInfo")
  if not info then s.finished = true writeSweep("cannot ask by id: no EJ_GetInstanceInfo") return false end
  local started = ms()
  s.passes = s.passes + 1
  while s.at <= Journal.SWEEP_MAX do
    if ms() - started > Journal.SWEEP_MS then break end
    local id = s.at
    s.at = id + 1
    local name, _, _, _, _, _, _, _, _, mapID = A.call(info, id)
    name = A.str(name)
    if name and name ~= "" then
      s.answered = s.answered + 1
      A.call(g("EJ_SelectInstance"), id)
      local isRaid = A.plain(A.call(g("EJ_InstanceIsRaid")))
      local first = A.str((A.call(g("EJ_GetEncounterInfoByIndex"), 1, id)))
      if isRaid == true then
        s.raids = s.raids + 1
      elseif first then
        s.dungeons = s.dungeons + 1
        Journal.done = Journal.done or {}
        Journal.done[id] = true
        local lines = {}
        local ok, b, n = pcall(Journal.ScanInstance, id, name, lines, A.num(mapID))
        if ok then s.bosses, s.items = s.bosses + (b or 0), s.items + (n or 0) end
        s.hits[#s.hits + 1] = ("%d:%s map=%s %s"):format(id, name, describe(mapID), ok and (lines[1] or "") or ("ERROR " .. tostring(b):sub(1, 60)))
      else
        s.hits[#s.hits + 1] = ("%d:%s (no encounters)"):format(id, name)
      end
    end
  end
  if s.at > Journal.SWEEP_MAX then
    s.finished = true
    writeSweep(s.answered == 0 and "asked every id: the journal holds no instances on this client"
      or ("done: %d instances answered, %d dungeons read"):format(s.answered, s.dungeons))
    if A.Window and A.Window.Refresh then A.Window.Refresh() end
    return false
  end
  if s.passes >= Journal.SWEEP_PASSES then
    s.finished = true
    writeSweep(("stopped at id %d after %d passes"):format(s.at - 1, s.passes))
    return false
  end
  writeSweep(("asking by id: %d of %d"):format(s.at - 1, Journal.SWEEP_MAX))
  return true
end

--- Start (or carry on) the sweep; runs itself in slices a moment apart.
function Journal.Sweep()
  if Journal.sweep and (Journal.sweep.finished or Journal.sweep.running) then return Journal.sweep end
  Journal.sweep = Journal.sweep or { at = 1, passes = 0, answered = 0, dungeons = 0, raids = 0, bosses = 0, items = 0, hits = {} }
  local s = Journal.sweep
  s.running = true
  local function step()
    local ok, more = pcall(Journal.SweepPass)
    if not ok then s.finished = true writeSweep("error: " .. tostring(more):sub(1, 80)) more = false end
    if more and C_Timer and C_Timer.After then C_Timer.After(0.2, step) else s.running = false end
  end
  step()
  return s
end

--- Read every dungeon the journal lists. Returns a result table (also written to diag).
function Journal.Scan(reason)
  local res = { at = A.now(), reason = reason or "manual", instances = 0, bosses = 0, items = 0, lines = {} }
  local function done(status)
    res.status = status
    Journal.last = res
    local gl = HH.db and HH.db.global
    if gl then
      gl.diag = gl.diag or {}
      local lines = {}
      for i = 1, math.min(#res.lines, 40) do lines[i] = res.lines[i] end
      gl.diag.atlasJournal = { at = res.at, reason = res.reason, status = status, instances = res.instances,
        listed = res.listed, ms = res.ms, probe = res.probe,
        bosses = res.bosses, items = res.items, lines = lines }
    end
    return res
  end
  if not Journal.Available() then return done("no journal functions on this client") end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return done("in combat, not scanned") end
  local ej = rawget(_G, "EncounterJournal")
  if type(ej) == "table" and ej.IsShown and A.plain(A.call(ej.IsShown, ej)) then return done("journal window open, not scanned") end

  local tiers = A.num(A.call(g("EJ_GetNumTiers"))) or 1
  local started, stopped = ms(), nil
  Journal.done = Journal.done or {}          -- journal instance ids read this session: a later scan skips them
  for tier = 1, math.max(1, math.min(tiers, 12)) do
    if stopped then break end
    if g("EJ_SelectTier") then A.call(g("EJ_SelectTier"), tier) end
    for i = 1, 200 do
      local jid, name = A.call(g("EJ_GetInstanceByIndex"), i, false)
      jid, name = A.num(jid), A.str(name)
      if not jid or not name then break end
      res.listed = (res.listed or 0) + 1
      if Journal.done[jid] and reason ~= "loot data arrived" then
        -- read before
      elseif res.instances >= Journal.MAX_INSTANCES then stopped = "instance cap" break
      elseif ms() - started > Journal.BUDGET_MS then stopped = "time budget" break
      else
      Journal.done[jid] = true
      res.instances = res.instances + 1
      local ok, b, n = pcall(scanInstance, jid, name, res.lines)
      if ok then
        res.bosses, res.items = res.bosses + (b or 0), res.items + (n or 0)
      else
        res.lines[#res.lines + 1] = name .. ": ERROR " .. tostring(b):sub(1, 80)
      end
      end
    end
  end
  res.ms = math.floor(ms() - started + 0.5)
  if (res.listed or 0) == 0 then
    local okp, probe = pcall(Journal.Probe)
    res.probe = okp and probe or ("probe failed: " .. tostring(probe))
    local s = Journal.Sweep()
    res.instances, res.bosses, res.items = s.dungeons, s.bosses, s.items
    return done("the journal's list is empty; " .. tostring(s.status or "asking by id"))
  end
  if stopped then return done("stopped early (" .. stopped .. "): scan again for the rest") end
  return done("ok")
end

--- Loot data arrives late on a cold cache: the client fires EJ_LOOT_DATA_RECIEVED, and a rescan picks it up.
-- Bounded: a few passes per session, never a loop.
function Journal.OnLootData()
  if Journal.passes >= Journal.MAX_PASSES or Journal.queued then return end
  Journal.queued = true
  local function run()
    Journal.queued = false
    Journal.passes = Journal.passes + 1
    Journal.Scan("loot data arrived")
    if A.Window and A.Window.Refresh then A.Window.Refresh() end
  end
  if C_Timer and C_Timer.After then C_Timer.After(2, run) else run() end
end

function Journal.Report()
  local r = Journal.last or (HH.db and HH.db.global and HH.db.global.diag and HH.db.global.diag.atlasJournal)
  if not r then return { "journal: not scanned yet" } end
  local out = { ("journal: %s (%s) - %d dungeons, %d bosses, %d new items"):format(tostring(r.status), tostring(r.at), r.instances or 0, r.bosses or 0, r.items or 0) }
  local s = Journal.sweep
  if s then
    out[#out + 1] = ("  by id: %s - %d answered, %d dungeons, %d bosses, %d items"):format(tostring(s.status), s.answered, s.dungeons, s.bosses, s.items)
    for i = 1, math.min(#s.hits, 5) do out[#out + 1] = "    " .. s.hits[i] end
  end
  for i = 1, math.min(#(r.lines or {}), 8) do out[#out + 1] = "  " .. r.lines[i] end
  return out
end
