-- AtlasProbe: what does this client offer a dungeon loot guide? Measured, not assumed, before HogTron UI Atlas is built.
--
-- At login it writes HogHealsDB.global.diag.atlas: API presence (Group Finder, Encounter Journal, loot, item,
-- addon-message, tooltip functions), every Group Finder activity with its level range, instance info, and whether
-- the addon-message prefix registers. While the session runs it appends one line per loot / encounter / roll /
-- loot-chat / target event (capped per event and in total) so a single dungeon boss tells us which events fire,
-- what they carry, and which values are secret. Read it off disk after a /reload pair; /hh atlasdiag prints the
-- short version in chat.
--
-- Rules: COMBAT_LOG_EVENT_UNFILTERED is never registered (a FORBIDDEN action on this client - the popup with the
-- Disable button); every RegisterEvent is pcall'd (unknown events throw here); no value that might be secret is
-- ever compared, tested or given to arithmetic - everything goes through describe(), which names secrets and
-- moves on.
local ADDON, ns = ...
local HH = HogHeals

local Probe = { PER_EVENT = 6, TOTAL = 80, counts = {} }
HH.AtlasProbe = Probe

-- Dotted paths read off _G. "nil" in the result means the function is not there on this client.
Probe.API = {
  -- Group Finder (the level ranges)
  "C_LFGList", "C_LFGList.GetAvailableCategories", "C_LFGList.GetLfgCategoryInfo", "C_LFGList.GetAvailableActivities",
  "C_LFGList.GetActivityInfoTable", "C_LFGList.GetActivityInfo", "C_LFGList.GetAvailableActivityGroups",
  "C_LFGList.GetActivityGroupInfo", "C_LFGInfo", "C_LFGInfo.GetDungeonInfo", "GetLFGDungeonInfo", "GetNumRandomDungeons",
  "LFGListFrame", "LFGMicroButton", "LFDMicroButton", "PVEFrame",
  -- Encounter Journal (players say there is none; confirm)
  "EJ_GetInstanceInfo", "EJ_GetEncounterInfo", "EJ_GetNumLoot", "EJ_SelectInstance", "EJ_GetInstanceForMap",
  "C_EncounterJournal", "C_EncounterJournal.GetEncountersOnMap", "C_EncounterJournal.GetLootInfo", "C_AdventureJournal",
  "EncounterJournal", "C_EncounterInfo",
  -- loot
  "GetNumLootItems", "GetLootSlotInfo", "GetLootSlotLink", "GetLootSlotType", "GetLootSourceInfo", "GetLootRollItemLink",
  "GetLootRollItemInfo", "GetLootMethod", "GetLootThreshold", "C_LootHistory", "C_LootHistory.GetItem", "LootFrame",
  "C_Loot", "C_Loot.GetLootSlotType",
  -- items
  "GetItemInfo", "GetItemInfoInstant", "C_Item", "C_Item.GetItemInfo", "C_Item.GetItemInfoInstant",
  "C_Item.RequestLoadItemDataByID", "C_Item.GetItemIconByID", "C_Item.GetItemQualityByID", "C_Item.GetItemNameByID",
  "C_Item.IsItemDataCachedByID", "Item", "Item.CreateFromItemID", "GetItemQualityColor", "ITEM_QUALITY_COLORS",
  -- sharing
  "C_ChatInfo", "C_ChatInfo.RegisterAddonMessagePrefix", "C_ChatInfo.SendAddonMessage",
  "C_ChatInfo.IsAddonMessagePrefixRegistered", "SendAddonMessage", "RegisterAddonMessagePrefix",
  "ChatEdit_InsertLink", "DressUpItemLink", "DressUpLink",
  -- tooltips
  "TooltipDataProcessor", "TooltipDataProcessor.AddTooltipPostCall", "Enum.TooltipDataType", "Enum.TooltipDataType.Item",
  "GameTooltip.SetHyperlink", "GameTooltip.GetItem", "C_TooltipInfo.GetHyperlink", "C_TooltipInfo.GetItemByID",
  "ItemRefTooltip",
  -- where am I / what did I target
  "GetInstanceInfo", "IsInInstance", "C_Map.GetBestMapForUnit", "C_Map.GetMapInfo", "GetRealZoneText",
  "GetDungeonDifficultyID", "UnitGUID", "UnitClassification", "UnitLevel", "UnitName", "UnitCreatureType",
  "UnitIsPlayer", "issecretvalue", "IsInGuild",
}

-- Registered on one frame; each in pcall. COMBAT_LOG_EVENT_UNFILTERED is deliberately absent.
Probe.EVENTS = {
  "ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL", "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
  "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED", "LOOT_ITEM_AVAILABLE",
  "START_LOOT_ROLL", "LOOT_ROLLS_COMPLETE", "LOOT_HISTORY_UPDATE_ENCOUNTER", "LOOT_ITEM_ROLL_WON", "SHOW_LOOT_TOAST",
  "CHAT_MSG_LOOT", "CHAT_MSG_ADDON",
  "LFG_LIST_AVAILABILITY_UPDATE", "GET_ITEM_INFO_RECEIVED", "UPDATE_INSTANCE_INFO", "PLAYER_TARGET_CHANGED",
}

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) or false end

--- True only for a plain, non-secret truthy value.
local function truthy(v)
  if isSecret(v) then return false end
  return v and true or false
end

--- Short, safe text for any value. Secrets are named, never touched.
local function describe(v, depth)
  if isSecret(v) then return "SECRET(" .. type(v) .. ")" end
  local t = type(v)
  if t == "string" then
    if #v > 90 then v = v:sub(1, 90) .. "..." end
    return '"' .. v .. '"'
  elseif t == "number" or t == "boolean" or t == "nil" then
    return tostring(v)
  elseif t == "table" then
    depth = depth or 0
    if depth >= 1 then return "table" end
    local parts, n = {}, 0
    for k, val in pairs(v) do
      n = n + 1
      if n <= 14 then parts[#parts + 1] = tostring(k) .. "=" .. describe(val, depth + 1) end
    end
    table.sort(parts)
    return "table{" .. table.concat(parts, " ") .. (n > 14 and (" +" .. (n - 14)) or "") .. "}"
  end
  return t
end
Probe.describe = describe

local function describeArgs(...)
  local n = select("#", ...)
  if n == 0 then return "(no args)" end
  local parts = {}
  for i = 1, n do parts[i] = describe((select(i, ...))) end
  return table.concat(parts, " ")
end

local function pack(ok, ...) return ok, { n = select("#", ...), ... } end

--- Every return of fn(...), described. "nil fn" when fn is missing, "ERR ..." when it throws.
local function call(fn, ...)
  if type(fn) ~= "function" then return "nil fn" end
  local ok, r = pack(pcall(fn, ...))
  if not ok then return "ERR " .. tostring(r[1]):sub(1, 80) end
  if r.n == 0 then return "(nothing)" end
  local parts = {}
  for i = 1, r.n do parts[i] = describe(r[i]) end
  return table.concat(parts, " | ")
end

--- First return of fn(...), or nil when fn is missing or throws.
local function raw(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if ok then return v end
  return nil
end

local function typeAt(path)
  local ok, t = pcall(function()
    local v = _G
    for part in path:gmatch("[^%.]+") do
      if type(v) ~= "table" then return "nil" end
      v = v[part]
    end
    return type(v)
  end)
  return ok and t or ("ERR " .. tostring(t):sub(1, 40))
end

--- "Creature-0-3134-36-14-644-00001A2B3C" -> "644". Anything else (players, secrets) -> "nil".
local function npcFromGUID(guid)
  if type(guid) ~= "string" or isSecret(guid) then return "nil" end
  return guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") or "nil"
end
Probe.npcFromGUID = npcFromGUID

local function itemIDFromLink(link)
  if type(link) ~= "string" or isSecret(link) then return "nil" end
  return link:match("|Hitem:(%d+)") or "nil"
end
Probe.itemIDFromLink = itemIDFromLink

local function instanceTag()
  local ok, r = pack(pcall(GetInstanceInfo))
  if not ok then return "inst=ERR" end
  return "inst=" .. describe(r[2]) .. ":" .. describe(r[8]) .. ":" .. describe(r[1])
end

local function diagTable()
  local g = HH.db and HH.db.global
  if not g then return nil end
  g.diag = g.diag or {}
  g.diag.atlas = g.diag.atlas or {}
  return g.diag.atlas
end

-- ---------- snapshots ----------

--- Group Finder: every category, every activity with its level range. Re-run on LFG_LIST_AVAILABILITY_UPDATE and
-- from /hh atlasdiag because the list may only arrive once the Group Finder has been opened.
function Probe.SnapshotLFG(a)
  local L = C_LFGList
  local out = {}
  a.lfg = out
  if type(L) ~= "table" then out.status = "C_LFGList nil" return end
  local okC, cats = pcall(L.GetAvailableCategories)
  if not okC then out.status = "GetAvailableCategories ERR " .. tostring(cats):sub(1, 80) return end
  if type(cats) ~= "table" then out.status = "categories=" .. describe(cats) return end
  out.categories, out.activities = {}, {}
  local total = 0
  for ci = 1, #cats do
    local cat = cats[ci]
    local name = "?"
    if type(L.GetLfgCategoryInfo) == "function" then
      local ok, info = pcall(L.GetLfgCategoryInfo, cat)
      if ok and type(info) == "table" then name = describe(info.name) elseif ok then name = describe(info) end
    end
    local okA, acts = pcall(L.GetAvailableActivities, cat)
    local n = (okA and type(acts) == "table") and #acts or 0
    out.categories[#out.categories + 1] = describe(cat) .. ":" .. name .. ":" .. n
    if okA and type(acts) == "table" then
      for ai = 1, #acts do
        local actID = acts[ai]
        if total >= 120 then break end
        if type(L.GetActivityInfoTable) == "function" then
          local ok, info = pcall(L.GetActivityInfoTable, actID)
          if ok and type(info) == "table" then
            if not out.activityFields then
              local f = {}
              for k, v in pairs(info) do f[#f + 1] = tostring(k) .. "=" .. type(v) end
              table.sort(f)
              out.activityFields = table.concat(f, ",")
            end
            total = total + 1
            out.activities[total] = describe(cat) .. ":" .. describe(actID) .. ":" .. describe(info.fullName or info.shortName)
              .. ":" .. describe(info.minLevel) .. "-" .. describe(info.maxLevel)
          elseif not ok and not out.activityErr then
            out.activityErr = tostring(info):sub(1, 80)
          end
        elseif not out.activityInfoLegacy then
          -- older shape: fullName, shortName, categoryID, groupID, itemLevel, filters, minLevel, maxPlayers, ...
          out.activityInfoLegacy = call(L.GetActivityInfo, actID)
        end
      end
    end
  end
  out.status = #cats .. " categories, " .. total .. " activities"
end

function Probe.Snapshot()
  local a = diagTable()
  if not a then return end
  a.at = date and date("%Y-%m-%d %H:%M:%S") or ""
  a.build = call(GetBuildInfo)
  a.api = {}
  for _, p in ipairs(Probe.API) do a.api[p] = typeAt(p) end
  local c = {}
  a.calls = c
  c.instance = call(GetInstanceInfo)
  c.inInstance = call(IsInInstance)
  c.bestMap = call(C_Map and C_Map.GetBestMapForUnit, "player")
  c.lootMethod = call(GetLootMethod)
  c.itemInfo_2589 = call(GetItemInfo, 2589)
  c.cItemInfo_2589 = call(C_Item and C_Item.GetItemInfo, 2589)
  c.cItemInstant_2589 = call(C_Item and C_Item.GetItemInfoInstant, 2589)
  c.tooltipItemEnum = describe(Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item)
  c.prefix = call(C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix, "HHATL")
  c.prefixRegistered = call(C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered, "HHATL")
  c.inGuild = call(IsInGuild)
  Probe.SnapshotLFG(a)
end

-- ---------- events ----------

local handlers = {}

local function lootLines(event)
  local n = raw(GetNumLootItems)
  local parts = { event, "n=" .. describe(n), instanceTag() }
  if type(n) == "number" and not isSecret(n) then
    for i = 1, math.min(n, 6) do
      local link = raw(GetLootSlotLink, i)
      local okS, src = pack(pcall(GetLootSourceInfo, i))
      local srcText = okS and (src.n > 0 and describe(src[1]) .. " x" .. describe(src[2]) .. (src.n > 2 and (" +" .. ((src.n - 2) / 2)) or "") or "(nothing)")
        or ("ERR " .. tostring(src[1]):sub(1, 60))
      parts[#parts + 1] = ("slot%d type=%s link=%s itemID=%s src=%s npc=%s info=%s"):format(i,
        call(GetLootSlotType, i), describe(link), itemIDFromLink(link), srcText, npcFromGUID(okS and src[1] or nil),
        call(GetLootSlotInfo, i))
    end
  end
  return table.concat(parts, " ")
end
handlers.LOOT_OPENED = function(...) return lootLines("LOOT_OPENED " .. describeArgs(...)) end
handlers.LOOT_READY = function(...) return lootLines("LOOT_READY " .. describeArgs(...)) end

handlers.START_LOOT_ROLL = function(rollID, ...)
  local link = raw(GetLootRollItemLink, rollID)
  return ("START_LOOT_ROLL %s %s link=%s itemID=%s info=%s %s"):format(describe(rollID), describeArgs(...), describe(link),
    itemIDFromLink(link), call(GetLootRollItemInfo, rollID), instanceTag())
end

handlers.CHAT_MSG_LOOT = function(msg, sender, ...)
  local hasLink = "nil"
  if type(msg) == "string" and not isSecret(msg) then hasLink = tostring(msg:find("|Hitem:", 1, true) ~= nil) end
  return ("CHAT_MSG_LOOT msg=%s hasItemLink=%s sender=%s %s"):format(describe(msg), hasLink, describe(sender), instanceTag())
end

handlers.CHAT_MSG_ADDON = function(prefix, ...)
  if type(prefix) ~= "string" or isSecret(prefix) or prefix ~= "HHATL" then return nil end   -- other addons' traffic is not ours to log
  return "CHAT_MSG_ADDON " .. describe(prefix) .. " " .. describeArgs(...)
end

handlers.LFG_LIST_AVAILABILITY_UPDATE = function()
  local a = diagTable()
  if a then Probe.SnapshotLFG(a) return "LFG_LIST_AVAILABILITY_UPDATE " .. tostring(a.lfg and a.lfg.status) end
end

handlers.PLAYER_TARGET_CHANGED = function()
  local inInst = raw(IsInInstance)
  if isSecret(inInst) then return "PLAYER_TARGET_CHANGED IsInInstance=SECRET" end
  if not inInst then return nil end
  if not truthy(raw(UnitExists, "target")) then return nil end
  local isPlayer = raw(UnitIsPlayer, "target")
  if isSecret(isPlayer) then return "PLAYER_TARGET_CHANGED UnitIsPlayer=SECRET" end
  if isPlayer then return nil end
  local guid = raw(UnitGUID, "target")
  return ("PLAYER_TARGET_CHANGED guid=%s npc=%s name=%s class=%s level=%s type=%s %s"):format(describe(guid), npcFromGUID(guid),
    describe(raw(UnitName, "target")), describe(raw(UnitClassification, "target")), describe(raw(UnitLevel, "target")),
    describe(raw(UnitCreatureType, "target")), instanceTag())
end

function Probe.OnEvent(event, ...)
  local a = diagTable()
  if not a then return end
  a.fired = a.fired or {}
  a.fired[event] = (a.fired[event] or 0) + 1
  local h = handlers[event]
  local line
  if h then line = h(...) else line = event .. " " .. describeArgs(...) .. " " .. instanceTag() end
  if not line then return end
  Probe.counts[event] = (Probe.counts[event] or 0) + 1
  if Probe.counts[event] > Probe.PER_EVENT then return end
  a.log = a.log or {}
  if #a.log >= Probe.TOTAL then return end
  a.log[#a.log + 1] = ("%.1f %s"):format(GetTime(), line)
end

function Probe:OnEnable()
  local a = diagTable()
  if not a then return end
  local frame = Probe.frame or CreateFrame("Frame", "HogHealsAtlasProbe")
  Probe.frame = frame
  frame:SetScript("OnEvent", function(_, event, ...)
    local ok, err = pcall(Probe.OnEvent, event, ...)
    if not ok then HH:LogError("AtlasProbe " .. tostring(err)) end
  end)
  local registered, failed = {}, {}
  for _, e in ipairs(Probe.EVENTS) do
    local ok, err = pcall(frame.RegisterEvent, frame, e)
    if ok then registered[#registered + 1] = e else failed[#failed + 1] = e .. " (" .. tostring(err):sub(1, 60) .. ")" end
  end
  a.events = { registered = table.concat(registered, ","), failed = table.concat(failed, ",") }
  Probe.Snapshot()
  -- the Group Finder list can arrive a few seconds after login
  if C_Timer and C_Timer.After then C_Timer.After(5, function() local t = diagTable() if t then pcall(Probe.SnapshotLFG, t) end end) end
end

-- ---------- /hh atlasdiag ----------

function Probe.Report()
  local a = diagTable()
  if not a or not a.api then HH:Print("AtlasProbe: nothing recorded yet.") return end
  Probe.SnapshotLFG(a)
  local api = a.api
  HH:Print("AtlasProbe " .. tostring(a.at))
  HH:Print("  Group Finder: " .. tostring(a.lfg and a.lfg.status))
  local acts = a.lfg and a.lfg.activities or {}
  for i = 1, math.min(#acts, 5) do HH:Print("    " .. acts[i]) end
  HH:Print(("  Encounter Journal: EJ_GetInstanceInfo=%s C_EncounterJournal=%s"):format(tostring(api["EJ_GetInstanceInfo"]), tostring(api["C_EncounterJournal"])))
  HH:Print(("  loot: GetLootSourceInfo=%s GetLootSlotLink=%s | share: SendAddonMessage=%s prefix=%s | tooltip: TooltipDataProcessor=%s"):format(
    tostring(api["GetLootSourceInfo"]), tostring(api["GetLootSlotLink"]), tostring(api["C_ChatInfo.SendAddonMessage"]),
    tostring(a.calls and a.calls.prefix), tostring(api["TooltipDataProcessor"])))
  HH:Print("  events registered: " .. tostring(a.events and a.events.registered))
  if a.events and a.events.failed ~= "" then HH:Print("  events FAILED: " .. a.events.failed) end
  local fired = {}
  for e, n in pairs(a.fired or {}) do fired[#fired + 1] = e .. "=" .. tostring(n) end
  table.sort(fired)
  HH:Print("  fired: " .. (#fired > 0 and table.concat(fired, " ") or "nothing yet"))
  local log = a.log or {}
  HH:Print(("  log: %d lines (last 3)"):format(#log))
  for i = math.max(1, #log - 2), #log do HH:Print("    " .. (log[i]:gsub("|", "||"))) end
end

HH:RegisterModule("AtlasProbe", Probe)
HH:RegisterSlash("atlasdiag", function() Probe.Report() end, "what this client offers a dungeon loot guide (Group Finder ranges, loot events, addon messages)")
