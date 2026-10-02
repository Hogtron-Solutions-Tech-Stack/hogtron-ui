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
  end
  HH:SafeCall(HHQ.MapSkin, "Apply")
  HH:SafeCall(HHQ.WorldMap, "Apply")
  HH:SafeCall(HHQ.Buttons, "Apply")
  HHQ.Pins.Start()
  -- position + quest data are not ready at login on every client: probe a few seconds in
  if C_Timer and C_Timer.After then C_Timer.After(5, function() HH:SafeCall(Module, "WriteProbe") end) end
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
