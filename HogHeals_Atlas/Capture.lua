-- Capture: the discovery engine and the loot log. Watches bosses die and loot appear inside instances and files
-- each drop under its boss. No drawing here.
--
-- How a drop finds its boss, most trusted first:
--   1. the corpse being looted is a boss we know by name (name learned from target / mouseover, no combat log)
--   2. an encounter ended in the last 30 s (ENCOUNTER_END)
--   3. neither: filed under "Trash and chests"
--
-- Measured on Forever 2026-09-28 (outdoors): LOOT_OPENED fires, GetLootSlotLink gives a plain link,
-- GetLootSourceInfo gives the corpse's GUID with the npc id in it. Not measured: the same inside an instance, and
-- ENCOUNTER_END for 5-man bosses. Anything secret is skipped and counted, never compared.
local A = HogHealsAtlas
local HH = HogHeals

local Capture = { WINDOW = 30, RUN_CAP = 20, DROP_CAP = 80, recent = {}, skipped = {} }
A.Capture = Capture

local EVENTS = { "ENCOUNTER_END", "LOOT_OPENED", "START_LOOT_ROLL", "CHAT_MSG_LOOT", "PLAYER_TARGET_CHANGED",
  "UPDATE_MOUSEOVER_UNIT", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GET_ITEM_INFO_RECEIVED",
  "EJ_LOOT_DATA_RECIEVED" }

local function clock() return (type(GetTime) == "function" and GetTime()) or 0 end
local function skip(why) Capture.skipped[why] = (Capture.skipped[why] or 0) + 1 end

function Capture.NpcFromGUID(guid)
  guid = A.str(guid)
  if not guid then return nil end
  local id = guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  return id and tonumber(id) or nil
end

--- Where am I: dungeon name + instance id when inside a dungeon or raid, else nil.
function Capture.Instance()
  local name, kind, _, _, _, _, _, inst = A.call(rawget(_G, "GetInstanceInfo"))
  kind = A.str(kind)
  if kind ~= "party" and kind ~= "raid" then return nil end
  return A.str(name), A.num(inst), kind
end

-- ------------------------------------------------------------------------------------------------ loot log
local function currentRun(name, inst)
  local db = A.Store.db()
  local run = db.runs[1]
  if run and run.open and run.inst == inst and run.name == name then return run end
  if run then run.open = nil end
  run = { name = name or "?", inst = inst, start = A.now(), open = true, drops = {}, killed = {} }
  table.insert(db.runs, 1, run)
  while #db.runs > Capture.RUN_CAP do table.remove(db.runs) end
  return run
end

function Capture.CloseRun()
  local run = A.Store.db().runs[1]
  if run and run.open then
    run.open = nil
    run.stop = A.now()
    -- a run with nothing in it is noise
    if #run.drops == 0 then table.remove(A.Store.db().runs, 1) end
  end
end

local function logDrop(run, id, boss, who)
  if #run.drops >= Capture.DROP_CAP then return end
  run.drops[#run.drops + 1] = { id = id, boss = boss, who = who, at = A.now() }
end

local function wishAlert(id, boss, link)
  if A.cfg().wishAlerts == false or not A.Gear or not A.Gear.IsWished(id) then return end
  HH:Print(("Wishlist: %s dropped from %s."):format(link or ("item " .. id), boss))
  local play = rawget(_G, "PlaySound")
  if type(play) == "function" then pcall(play, 8959) end   -- raid warning sound
end

-- ------------------------------------------------------------------------------------------------ filing a drop
--- File one drop. key = what makes this sighting unique (corpse + item), so reopening a corpse counts once.
function Capture.File(link, sourceGUID, who, src)
  local name, inst = Capture.Instance()
  if not name and not inst then skip("outside an instance") return false end
  if A.isSecret(link) then skip("secret link") return false end
  local id = A.ItemIDFromLink(link)
  if not id then skip("no item id") return false end
  local info = A.ItemInfo(id)
  local quality = info and info.quality
  if not quality then
    quality = A.num(A.call(A.fn("C_Item.GetItemQualityByID"), id))
  end
  if quality and quality < (A.cfg().minQuality or 2) then skip("below quality") return false end

  local npc = Capture.NpcFromGUID(sourceGUID)
  local npcName = npc and A.Store.NpcName(npc)
  local boss, dkey
  if npcName then
    local d = A.Data.FindBoss(npcName, inst)
    if d then boss, dkey = npcName, d.key end
    if not boss then
      local known = A.Store.db().bosses
      local k = A.Store.DungeonKey(name, inst)
      if k and known[k] and known[k][npcName] then boss, dkey = npcName, k end
    end
  end
  local last = Capture.lastBoss
  if not boss and last and (clock() - last.t) <= Capture.WINDOW then boss, dkey = last.name, last.dungeon end
  if not boss then boss = A.Store.TRASH end
  dkey = dkey or A.Store.DungeonKey(name, inst, boss ~= A.Store.TRASH and boss or nil)
  if not dkey then skip("no dungeon") return false end

  local key = tostring(A.str(sourceGUID) or who or "?") .. ":" .. id
  local t = clock()
  if Capture.recent[key] and (t - Capture.recent[key]) < 300 then return false end
  Capture.recent[key] = t
  -- the same item seen in the loot window and again in chat a moment later is one drop
  local soft = "item:" .. id
  if src == "group" and Capture.recent[soft] and (t - Capture.recent[soft]) < 15 then return false end
  Capture.recent[soft] = t

  if boss ~= A.Store.TRASH then A.Store.AddBoss(dkey, boss, { npc = npc, src = "seen" }) end
  local fresh = A.Store.Record(dkey, boss, id, src or "seen")
  local run = currentRun(name, inst)
  logDrop(run, id, boss, who)
  -- loot on a boss's corpse means the boss is dead, whether or not the client said so
  if boss ~= A.Store.TRASH then run.killed = run.killed or {} run.killed[boss] = true end
  if fresh and src ~= "group" and A.Share then A.Share.Send(dkey, boss, id) end
  if A.Tracker then A.Tracker.RefreshSoon() end
  wishAlert(id, boss, A.str(link))
  Capture.filed = (Capture.filed or 0) + 1
  if A.Window and A.Window.Refresh then A.Window.Refresh() end
  return true, dkey, boss, id
end

-- ------------------------------------------------------------------------------------------------ events
local function learn(unit)
  if not Capture.Instance() then return end
  if A.plain(A.call(rawget(_G, "UnitIsPlayer"), unit)) == true then return end
  local npc = Capture.NpcFromGUID(A.call(UnitGUID, unit))
  local name = A.str(A.call(UnitName, unit))
  if npc and name then A.Store.LearnNpc(npc, name) end
end

function Capture.OnLootOpened()
  local count = A.num(A.call(rawget(_G, "GetNumLootItems"))) or 0
  local slotType, slotLink, sourceInfo = rawget(_G, "GetLootSlotType"), rawget(_G, "GetLootSlotLink"), rawget(_G, "GetLootSourceInfo")
  for slot = 1, count do
    local kind = A.num(A.call(slotType, slot))
    if kind == nil or kind == 1 then   -- 1 = item; nil when the client has no such call: try the link anyway
      local link = A.call(slotLink, slot)
      if A.isSecret(link) then
        skip("secret link")
      elseif link ~= nil then
        local guid = A.call(sourceInfo, slot)
        Capture.File(link, guid, "me", "seen")
      end
    end
  end
end

function Capture.OnEvent(_, e, a1, a2, a3, a4, a5)
  if A.cfg().enabled == false then return end
  if e == "ENCOUNTER_END" then
    -- (encounterID, name, difficulty, size, success)
    local name, inst = Capture.Instance()
    local boss = A.str(a2)
    if (name or inst) and boss and A.num(a5) ~= 0 then
      local dkey = A.Store.DungeonKey(name, inst, boss)
      if dkey then
        A.Store.AddBoss(dkey, boss, { enc = A.num(a1), src = "seen" })
        Capture.lastBoss = { name = boss, dungeon = dkey, t = clock() }
        local run = currentRun(name, inst)
        run.killed = run.killed or {}
        run.killed[boss] = true
        if A.Tracker then A.Tracker.RefreshSoon() end
      end
    end
  elseif e == "LOOT_OPENED" then
    Capture.OnLootOpened()
  elseif e == "START_LOOT_ROLL" then
    local link = A.call(rawget(_G, "GetLootRollItemLink"), a1)
    if A.isSecret(link) then skip("secret link") elseif link ~= nil then Capture.File(link, nil, "roll:" .. tostring(A.num(a1) or "?"), "seen") end
  elseif e == "CHAT_MSG_LOOT" then
    if A.isSecret(a1) then skip("secret chat") return end
    local msg = A.str(a1)
    if msg and msg:find("item:", 1, true) then
      local mine = msg:find("^You ") ~= nil
      -- my own drops came through the loot window already; chat adds what the others picked up
      local link = msg:match("(|c.-|Hitem:.-|h.-|h|r)") or msg
      if not mine then Capture.File(link, nil, A.str(a2) or A.str(a5) or "group", "group") end
    end
  elseif e == "PLAYER_TARGET_CHANGED" then
    learn("target")
  elseif e == "UPDATE_MOUSEOVER_UNIT" then
    learn("mouseover")
  elseif e == "PLAYER_ENTERING_WORLD" or e == "ZONE_CHANGED_NEW_AREA" then
    local name, inst = Capture.Instance()
    if name or inst then currentRun(name, inst) else Capture.CloseRun() end
    if A.DungeonQuests and A.Window and A.Window.Refresh then A.Window.Refresh() end
  elseif e == "GET_ITEM_INFO_RECEIVED" then
    local id = A.num(a1)
    if id and A.pending[id] then
      A.pending[id] = nil
      if A.Window and A.Window.RefreshSoon then A.Window.RefreshSoon() end
    end
  elseif e == "EJ_LOOT_DATA_RECIEVED" then
    A.Journal.OnLootData()
  end
end

function Capture.Start()
  if Capture.frame then return end
  local f = CreateFrame("Frame")
  Capture.unknown = {}
  for _, e in ipairs(EVENTS) do
    if not pcall(f.RegisterEvent, f, e) then Capture.unknown[#Capture.unknown + 1] = e end
  end
  f:SetScript("OnEvent", function(...)
    local ok, err = pcall(Capture.OnEvent, ...)
    if not ok then HH:LogError("atlas capture: " .. tostring(err)) end
  end)
  Capture.frame = f
end

function Capture.Report()
  local parts = {}
  for k, v in pairs(Capture.skipped) do parts[#parts + 1] = k .. " x" .. v end
  table.sort(parts)
  local name, inst = Capture.Instance()
  return {
    ("capture: filed %d this session, in instance: %s (%s)"):format(Capture.filed or 0, tostring(name), tostring(inst)),
    "  skipped: " .. (#parts > 0 and table.concat(parts, "; ") or "none"),
    "  unknown events: " .. ((Capture.unknown and #Capture.unknown > 0) and table.concat(Capture.unknown, ",") or "none"),
  }
end
