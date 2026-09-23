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
  "PLAYER_LEVEL_UP", "ZONE_CHANGED_INDOORS" }

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
  ev:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_ENTERING_WORLD" then HHQ.Tracker.ApplyBlizzard() HH:SafeCall(HHQ.MapSkin, "Apply") end
    if e == "ZONE_CHANGED" or e == "ZONE_CHANGED_NEW_AREA" or e == "PLAYER_ENTERING_WORLD" then HH:SafeCall(HHQ.MapSkin, "UpdateZone") end
    HHQ.Tracker.Schedule()
  end)
  Module.events = ev
  if HH.db.profile.quests.tracker.enabled ~= false then
    HHQ.Tracker.ApplyBlizzard()
    HHQ.Tracker.Show()
  end
  HH:SafeCall(HHQ.MapSkin, "Apply")
  HHQ.Pins.Start()
  -- position + quest data are not ready at login on every client: probe a few seconds in
  if C_Timer and C_Timer.After then C_Timer.After(5, function() HH:SafeCall(Module, "WriteProbe") end) end
end

function Module:OnProfileChanged()
  HHQ.Tracker.Refresh()
  HHQ.Pins.Refresh()
  HH:SafeCall(HHQ.MapSkin, "Refresh")
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
