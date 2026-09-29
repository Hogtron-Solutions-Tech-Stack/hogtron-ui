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

--- One instance: its encounters and their loot. Returns bosses found, items found.
local function scanInstance(jid, name, out)
  A.call(g("EJ_SelectInstance"), jid)
  A.call(g("EJ_ResetLootFilter"))
  A.call(A.fn("C_EncounterJournal.ResetSlotFilter"))
  local bosses, items = 0, 0
  local dkey
  for i = 1, Journal.MAX_ENCOUNTERS do
    local bname, _, encID = A.call(g("EJ_GetEncounterInfoByIndex"), i, jid)
    bname, encID = A.str(bname), A.num(encID)
    if not bname then break end
    dkey = A.Store.DungeonKey(name, nil, bname) or dkey
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

local function ms()
  local f = rawget(_G, "debugprofilestop")
  if type(f) == "function" then local ok, v = pcall(f) if ok and type(v) == "number" then return v end end
  return ((type(GetTime) == "function" and GetTime()) or 0) * 1000
end
Journal.ms = ms

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
        listed = res.listed, ms = res.ms,
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
  if (res.listed or 0) == 0 then return done("journal is there but lists no dungeons") end
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
  for i = 1, math.min(#(r.lines or {}), 8) do out[#out + 1] = "  " .. r.lines[i] end
  return out
end
