-- HogHeals Quests module: wires the tracker and the minimap pins to quest events, registers options, writes a probe
-- of this client's quest API to the diag log (diag.quests) so the first in-game session tells us which path runs.
HogHealsQuests = HogHealsQuests or {}
local HHQ = HogHealsQuests
local HH = HogHeals

local Module = {}
HHQ.module = Module

-- Every one of these is pcall-registered: the Forever beta THROWS on events it does not know.
local EVENTS = { "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_WATCH_UPDATE", "UNIT_QUEST_LOG_CHANGED",
  "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED",
  "PLAYER_LEVEL_UP", "ZONE_CHANGED_INDOORS", "ADDON_LOADED" }

-- Quest OFFERS (the "!" over an NPC you have not talked to yet). Sean 2026-10-01: the minimap shows one right in
-- front of him, the world map does not. The minimap "!" is the client's own NPC blip - no addon can read where it is.
-- The world map could show offers only if this client exposes them; modern clients do through C_QuestLine
-- (GetAvailableQuestLines(mapID) -> x, y per available quest after RequestQuestLinesForMap) or C_QuestOffer, and
-- Blizzard's map draws them through a pin pool whose template name says so. This records which of those exist
-- here; the next in-game /hh questdiag answers "buildable from the client, or needs a quest-giver database".
local OFFER_APIS = { "C_QuestOffer", "C_QuestLine", "C_TaskQuest", "C_AreaPoiInfo", "C_Minimap", "C_QuestHub", "C_QuestInfoSystem" }
local OFFER_CVARS = { "questPOI", "showTrivialQuests", "trivialQuests", "minimapTrackingShowAll", "showQuestTrackingTooltips" }

function Module.OffersProbe()
  local out = {}
  local apis = {}
  for _, name in ipairs(OFFER_APIS) do
    local t = rawget(_G, name)
    if type(t) == "table" then
      local keys = {}
      for k in pairs(t) do keys[#keys + 1] = tostring(k) end
      table.sort(keys)
      apis[#apis + 1] = name .. "{" .. table.concat(keys, " ") .. "}"
    else
      apis[#apis + 1] = name .. "=nil"
    end
  end
  out.apis = table.concat(apis, " ; ")
  local cv = {}
  for _, c in ipairs(OFFER_CVARS) do
    local ok, v = pcall(GetCVar, c)
    cv[#cv + 1] = c .. "=" .. tostring(ok and v or "err")
  end
  out.cvars = table.concat(cv, ",")
  -- what Blizzard's own map draws: the pin pools are keyed by template name (filled once the map has been opened)
  local wm = rawget(_G, "WorldMapFrame")
  local pools = {}
  if type(wm) == "table" and type(rawget(wm, "pinPools")) == "table" then
    for k in pairs(wm.pinPools) do pools[#pools + 1] = tostring(k) end
    table.sort(pools)
  end
  out.pinPools = #pools > 0 and table.concat(pools, ",") or "none (open the map once, then /hh questdiag again)"
  out.mapOpenID = (type(wm) == "table" and wm.GetMapID) and tostring(select(2, pcall(wm.GetMapID, wm))) or "nil"
  -- minimap tracking types (the client's "Low level quests" / "Trivial quests" filters live here)
  local tr = {}
  if type(C_Minimap) == "table" and type(C_Minimap.GetNumTrackingTypes) == "function" then
    local okN, n = pcall(C_Minimap.GetNumTrackingTypes)
    for i = 1, (okN and tonumber(n)) or 0 do
      local ok, a, b, c = pcall(C_Minimap.GetTrackingInfo, i)
      if ok then
        if type(a) == "table" then tr[#tr + 1] = tostring(a.name) .. ":" .. tostring(a.active)
        else tr[#tr + 1] = tostring(a) .. ":" .. tostring(c) end
      end
    end
  end
  out.tracking = table.concat(tr, ",")
  -- per-map counts for the player's map: every candidate source of "available quest" positions
  local mapID = type(C_Map) == "table" and type(C_Map.GetBestMapForUnit) == "function" and select(2, pcall(C_Map.GetBestMapForUnit, "player")) or nil
  out.mapID = tostring(mapID)
  if type(mapID) == "number" then
    local counts = {}
    local function count(label, fn, ...)
      if type(fn) ~= "function" then counts[#counts + 1] = label .. "=nil" return end
      local ok, r = pcall(fn, ...)
      if not ok then counts[#counts + 1] = label .. "=err:" .. tostring(r):sub(1, 60) return end
      if type(r) ~= "table" then counts[#counts + 1] = label .. "=" .. type(r) return end
      local keys = {}
      local first = r[1]
      if type(first) == "table" then for k in pairs(first) do keys[#keys + 1] = tostring(k) end table.sort(keys) end
      counts[#counts + 1] = label .. "=" .. #r .. (#keys > 0 and ("[" .. table.concat(keys, " ") .. "]") or "")
    end
    if type(C_QuestLine) == "table" then
      pcall(C_QuestLine.RequestQuestLinesForMap, mapID)   -- async: the second questdiag sees the answer
      count("questLines", C_QuestLine.GetAvailableQuestLines, mapID)
    else counts[#counts + 1] = "questLines=nil" end
    count("questOffers", type(C_QuestOffer) == "table" and C_QuestOffer.GetQuestOfferMapInfo or nil, mapID)
    count("taskQuests", type(C_TaskQuest) == "table" and C_TaskQuest.GetQuestsForPlayerByMapID or nil, mapID)
    count("areaPOIs", type(C_AreaPoiInfo) == "table" and C_AreaPoiInfo.GetAreaPOIForMap or nil, mapID)
    count("questsOnMap", type(C_QuestLog) == "table" and C_QuestLog.GetQuestsOnMap or nil, mapID)
    count("questHubs", type(C_QuestHub) == "table" and C_QuestHub.GetQuestHubsForMap or nil, mapID)
    out.counts = table.concat(counts, " ; ")
  end
  return out
end

function Module.WriteProbe()
  local g = HH.db and HH.db.global
  if not g then return end
  g.diag = g.diag or {}
  local ok, data = pcall(HHQ.Data.Probe)
  local ok2, pins = pcall(HHQ.Pins.Probe)
  g.diag.quests = {
    at = date and date("%Y-%m-%d %H:%M:%S") or "",
    data = ok and data or ("probe failed: " .. tostring(data)),
    minimap = ok2 and pins or ("probe failed: " .. tostring(pins)),
    map = (function() local ok3, m = pcall(HHQ.MapSkin.Probe) return ok3 and m or ("probe failed: " .. tostring(m)) end)(),
    mapMissing = table.concat(HHQ.MapSkin.missing or {}, ","),
    worldMap = (function() local ok4, m = pcall(HHQ.WorldMap.Probe) return ok4 and m or ("probe failed: " .. tostring(m)) end)(),
    buttons = (function() local ok5, m = pcall(HHQ.Buttons.Probe) return ok5 and m or ("probe failed: " .. tostring(m)) end)(),
    offers = (function() local ok6, m = pcall(Module.OffersProbe) return ok6 and m or ("probe failed: " .. tostring(m)) end)(),
    unknownEvents = table.concat(Module.unknown or {}, ","),
  }
end

function Module:OnEnable()
  local ev = CreateFrame("Frame")
  Module.unknown = {}
  for _, e in ipairs(EVENTS) do
    local ok = pcall(ev.RegisterEvent, ev, e)
    if not ok then Module.unknown[#Module.unknown + 1] = e end
  end
  ev:SetScript("OnEvent", function(_, e, arg1, arg2)
    if e == "QUEST_ACCEPTED" and HH.db.profile.quests.tracker.autoTrack ~= false then
      -- classic passes (questLogIndex, questID), modern (questID); the log may lag the event by a frame
      local id = (type(arg2) == "number" and arg2) or (type(arg1) == "number" and arg1) or nil
      local index = type(arg2) == "number" and arg1 or nil
      if id then
        local function watch() pcall(HHQ.Data.SetWatched, { id = id, index = index }, true) HHQ.Tracker.Schedule() end
        if C_Timer and C_Timer.After then C_Timer.After(0.5, watch) else watch() end
      end
    end
    if e == "ADDON_LOADED" then
      -- Blizzard's tracker is a load-on-demand addon that can arrive after us: hide it the moment it exists
      if type(arg1) == "string" and arg1:find("ObjectiveTracker") then HHQ.Tracker.ApplyBlizzard() end
      return
    end
    if e == "PLAYER_ENTERING_WORLD" then
      if C_Timer and C_Timer.After then C_Timer.After(3, function() HHQ.Tracker.ApplyBlizzard() end) end HHQ.Tracker.ApplyBlizzard() HH:SafeCall(HHQ.MapSkin, "Apply") HH:SafeCall(HHQ.Buttons, "Apply") end
    if e == "ZONE_CHANGED" or e == "ZONE_CHANGED_NEW_AREA" or e == "PLAYER_ENTERING_WORLD" then HH:SafeCall(HHQ.MapSkin, "UpdateZone") end
    HHQ.Tracker.Schedule()
  end)
  Module.events = ev
  if HH.db.profile.quests.tracker.enabled ~= false then
    HHQ.Tracker.ApplyBlizzard()
    HHQ.Tracker.Show()
    pcall(HHQ.Tracker.SetUnlocked, HH.db.profile.locked == false)
  end
  HH:SafeCall(HHQ.MapSkin, "Apply")
  HH:SafeCall(HHQ.WorldMap, "Apply")
  HH:SafeCall(HHQ.Buttons, "Apply")
  HHQ.Pins.Start()
  HH:SafeCall(HHQ.Auto, "Start")
  HH:SafeCall(HHQ.Announce, "Start")
  HH:SafeCall(HHQ.Tooltip, "Start")
  -- position + quest data are not ready at login on every client: probe a few seconds in
  if C_Timer and C_Timer.After then C_Timer.After(5, function() HH:SafeCall(Module, "WriteProbe") end) end
end

--- /hh unlock | lock: the tracker shows its resize grip and cyan edges while unlocked.
function Module:SetLocked(locked)
  -- plain pcall: SafeCall would pass the Tracker table as the first argument (dot-style function)
  local ok, err = pcall(HHQ.Tracker.SetUnlocked, not locked)
  if not ok then HH:LogError("tracker SetUnlocked: " .. tostring(err)) end
end

function Module:OnProfileChanged()
  HHQ.Tracker.Refresh()
  HHQ.Pins.Refresh()
  HH:SafeCall(HHQ.MapSkin, "Refresh")
  HH:SafeCall(HHQ.WorldMap, "Refresh")
  HH:SafeCall(HHQ.Buttons, "Refresh")
end

function Module:GetOptions()
  if HHQ.Options and HHQ.Options.Build then return HHQ.Options.Build() end
end

HH:RegisterModule("Quests", Module)

HH:RegisterSlash("quests", function() HHQ.Tracker.Toggle() end, "show / hide the quest tracker")
HH:RegisterSlash("questdiag", function()
  Module.WriteProbe()
  local q = HH.db.global.diag.quests
  local d = type(q.data) == "table" and q.data or {}
  local m = type(q.minimap) == "table" and q.minimap or {}
  HH:Print(("quests: %s | paths: %s"):format(tostring(d.quests), tostring(d.paths)))
  HH:Print(("minimap: map %s pos %s size %s radius %s points %s"):format(tostring(m.mapID), tostring(m.pos), tostring(m.size), tostring(m.radius), tostring(m.points)))
  if HHQ.Pins.why then HH:Print("pins: " .. HHQ.Pins.why) end
  local o = type(q.offers) == "table" and q.offers or {}
  HH:Print(("offers: map %s | %s"):format(tostring(o.mapID), tostring(o.counts or o.apis)))
  HH:Print("offer pins: " .. tostring(o.pinPools))
end, "print what the quest tracker / minimap can read on this client")
HH:RegisterSlash("buttons", function(rest)
  local D = HHQ.Buttons
  if type(rest) == "string" and rest:lower():find("^list") then
    local names = D.Names()
    HH:Print(("addon buttons: %d collected%s"):format(#names, #names > 0 and (" - " .. table.concat(names, ", ")) or ""))
    if D.skipped and #D.skipped > 0 then HH:Print("left alone: " .. table.concat(D.skipped, ", ")) end
    return
  end
  if HH.db.profile.quests.buttons.enabled == false then HH:Print("Addon buttons are off (Quests > Minimap > Addon buttons).") return end
  D.Toggle()
end, "open / close the addon-button drawer; 'buttons list' prints what was found")
