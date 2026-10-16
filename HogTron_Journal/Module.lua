-- Module: registers Journal with the HogTron UI core, watches zone-ins, owns the slash commands. Loads last.
--
-- Auto-open: PLAYER_ENTERING_WORLD, then a short wait (GetInstanceInfo can still describe the old zone at the
-- event), then once per instance per session: open the window on the dungeon if a page exists for it, say so in
-- chat once if none does, and offer the party summary (default off).
local J = HogHealsJournal
local HH = HogHeals

local Module = {}
J.module = Module

J.seen = {}   -- instance id or name -> true once handled this session

--- The zone-in handler, split out so tests can call it. Returns what it did.
function Module.OnZone()
  local d, w = J.Current()
  if not w then return "outside" end
  local key = tostring(w.inst or w.name or "?")
  if J.seen[key] then return "seen" end
  J.seen[key] = true
  if not d then
    HH:Print(("Journal: no page for %s yet (instance %s)."):format(tostring(w.name or "this dungeon"), tostring(w.inst or "?")))
    return "no data"
  end
  local did = {}
  if J.cfg().autoOpen ~= false then
    J.Window.Show(d)
    did[#did + 1] = "opened"
  end
  local sent, why = J.SaySummary(d)
  did[#did + 1] = sent and "said" or ("summary: " .. tostring(why))
  return table.concat(did, ", ")
end

function Module:OnEnable()
  if J.cfg().enabled == false then return end
  J.Compat.Check()
  local f = CreateFrame("Frame")
  Module.events = f
  pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")
  pcall(f.RegisterEvent, f, "ZONE_CHANGED_NEW_AREA")
  f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
      J.Compat.Check()
      -- PLAYER_ENTERING_WORLD and ZONE_CHANGED_NEW_AREA both fire on a zone-in: one wait, not one per event
      if Module.pending then return end
      if C_Timer and C_Timer.After then
        Module.pending = true
        C_Timer.After(1.5, function() Module.pending = nil Module.last = Module.OnZone() end)
      else Module.last = Module.OnZone() end
    end
  end)
  -- the probe once per login, out of the way of the loading screen; the saved file then carries the answer
  local function probe() pcall(J.Probe.Run, "login") end
  if C_Timer and C_Timer.After then C_Timer.After(8, probe) else probe() end
end

function Module:OnProfileChanged()
  J.filled = nil
  if J.Window.frame then J.Window.frame:SetScale(J.cfg().scale or 1) end
  J.Window.Refresh()
end

function Module:GetOptions()
  local function toggle(key, name, order, desc)
    return { type = "toggle", name = name, order = order, desc = desc,
      get = function() return J.cfg()[key] == true end,
      set = function(_, v) J.cfg()[key] = v and true or false end }
  end
  return { type = "group", name = "Journal", args = {
    about = { type = "description", order = 0, name = "A healer's dungeon journal: every boss in the dungeon you are in - what to dispel and who can, when to shield the tank or the group, what to kick - and the quests that send you there. /hh journal. Pages are hand-written and labelled until a run on Forever confirms them." },
    open = { type = "execute", name = "Open the journal", order = 1, func = function() J.Window.Show() end },
    autoOpen = toggle("autoOpen", "Open by itself the first time you enter a dungeon (once per session)", 2),
    partySummary = toggle("partySummary", "Party chat: one summary line on zone-in, when somebody there has not heard it", 3,
      "Off by default. One line: bosses, dispel schools, must-kicks. Remembered per person per dungeon."),
    scale = { type = "range", name = "Window scale", order = 4, min = 0.6, max = 1.4, step = 0.05,
      get = function() return J.cfg().scale or 1 end,
      set = function(_, v) J.cfg().scale = v if J.Window.frame then J.Window.frame:SetScale(v) end end },
    probe = { type = "execute", name = "Probe the client's Encounter Journal", order = 5, func = function()
      J.Probe.Run("options")
      for _, l in ipairs(J.Probe.Report()) do HH:Print(l) end
    end },
  } }
end

HH:RegisterModule("Journal", Module)

local function slash(rest)
  rest = (rest or ""):lower()
  rest = rest:gsub("^%s+", ""):gsub("%s+$", "")
  if rest == "probe" then
    J.Probe.Run("slash")
    for _, l in ipairs(J.Probe.Report()) do HH:Print(l) end
    return
  end
  if rest == "list" then
    for _, d in ipairs(J.Dungeons()) do HH:Print(("  %s  %s  (%s, id %d, %d bosses, %d quests)"):format(d.key, d.name, d.levels or "?", d.inst or 0, #(d.bosses or {}), #(d.quests or {}))) end
    return
  end
  if rest == "say" then
    local d = J.Current() or J.Window.dungeon
    if not d then HH:Print("Journal: not in a dungeon with a page.") return end
    HH:Print(J.SummaryLine(d))
    return
  end
  if rest == "reset" then J.seen = {} HH:Print("Journal: the next zone-in opens again.") return end
  if rest ~= "" then
    if not J.Dungeon(rest) then HH:Print(("Journal: no page called '%s'. /hh journal list"):format(rest)) return end
    J.Window.Show(rest)
    return
  end
  J.Window.Toggle()
end

HH:RegisterSlash("journal", slash, "healer's dungeon journal: bosses, dispels, shields, kicks, quests (/hh journal <dungeon> | list | probe | say)")
HH:RegisterSlash("boss", slash, "same as /hh journal")
