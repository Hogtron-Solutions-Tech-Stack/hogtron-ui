-- Polestar (github.com/fitzforge/polestar, GPL-3.0-only): WoW: Forever's leveling-guide addon - guide steps, a
-- walking-route arrow, quest markers from its own quest database, gear advice, quality-of-life chores. Sean 2026-11-06:
-- "look at the polestar addon and implement that into hogtron UI", then picked "work alongside it": when Polestar is
-- installed, HogTron UI shows what Polestar knows in its own frames and stands aside where both would do the same job.
--
-- No Polestar code or data is copied (HogTron UI is MIT; docs/superpowers/research/polestar.md). Only its global
-- namespace `Polestar` is read, and every read is a pcall that may fail: its message bus (Polestar.On), its settings
-- (Polestar.Get / Polestar.Set - Set tells Polestar itself, SETTING_CHANGED), the guide engine (Polestar.Engine:
-- GetGuide, GetStepIndex, GetStepCount, GetStepView, GetWaypoint) and the event that toggles its guide window.
--
-- profile.interop.polestar: enabled (master) + one switch per area Polestar leads while it runs:
--   guide  the tracker's top row is Polestar's current step (GUIDE) instead of GO's pick
--   arrow  GO stops pointing the game's arrow while Polestar guides; the HogTron beam follows Polestar's target
--          (Polestar's own "Blizzard waypoint" switch puts its target on the game's arrow - switched on once for it)
local HH = HogHeals

local PS = { handles = {}, counts = {} }
HH.Polestar = PS

PS.ADDON = "Polestar"
-- the bus messages HogTron UI listens to (Polestar/Core/Engine.lua fires them)
PS.MESSAGES = { "GUIDE_CHANGED", "STEP_CHANGED", "STEP_UPDATED", "WAYPOINT_CHANGED" }
-- goal states that are not "what to do now" (Polestar's goal view: done | na | skipped | current | ...)
PS.CLOSED = { done = true, na = true, skipped = true }

local function g(name) return rawget(_G, name) end
local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c = pcall(f, ...)
  if ok then return a, b, c end
  return nil
end

local function cfg()
  local p = HH.db and HH.db.profile
  local i = p and p.interop
  return type(i) == "table" and type(i.polestar) == "table" and i.polestar or {}
end

--- Polestar's namespace (its global), or nil.
function PS.NS()
  local ns = g("Polestar")
  return type(ns) == "table" and ns or nil
end

--- Polestar is loaded (the client says so and its namespace is there).
function PS.Loaded()
  local f = (type(C_AddOns) == "table" and C_AddOns.IsAddOnLoaded) or g("IsAddOnLoaded")
  local ok, loaded = pcall(f or function() end, PS.ADDON)
  return ok and loaded == true and PS.NS() ~= nil
end

--- Polestar runs and leads `area` (switched on unless the player switched it off).
function PS.Leads(area)
  local c = cfg()
  if c.enabled == false or (area and c[area] == false) then return false end
  return PS.Loaded()
end

--- One of Polestar's settings ("nav.blizzardWaypoint"), or nil.
function PS.Get(key)
  local ns = PS.NS()
  if not ns then return nil end
  return (try(ns.Get, key))          -- (a false setting stays false: no `and / or` here)
end

--- Change one of Polestar's settings through Polestar (it hears SETTING_CHANGED and applies it). true when it took.
function PS.Set(key, value)
  local ns = PS.NS()
  if not ns or type(ns.Set) ~= "function" then return false end
  return (pcall(ns.Set, key, value))
end

function PS.Engine()
  local ns = PS.NS()
  local e = ns and ns.Engine
  return type(e) == "table" and e or nil
end

--- A guide runs and it has somewhere for you to go: Polestar is pointing the way.
function PS.Guiding()
  local e = PS.Engine()
  if not e then return false end
  return try(e.GetGuide) ~= nil and try(e.GetWaypoint) ~= nil
end

--- The current step, for the tracker / beam: { index, count, title, goal, progress, guide } (nil without a guide).
--- title = the step's own title; goal = the first goal still open ("Kill 8 Plainstriders"); progress = "3/8".
function PS.Step()
  local e = PS.Engine()
  if not e then return nil end
  local guide = try(e.GetGuide)
  if guide == nil then return nil end
  local i = try(e.GetStepIndex)
  if type(i) ~= "number" then return nil end
  local view = try(e.GetStepView, i)
  if type(view) ~= "table" then return nil end
  local out = { index = i, count = try(e.GetStepCount) }
  if type(view.title) == "string" and view.title ~= "" then out.title = view.title end
  if type(guide) == "table" and type(guide.title) == "string" then out.guide = guide.title end
  for _, gv in ipairs(type(view.goals) == "table" and view.goals or {}) do
    if type(gv) == "table" and not PS.CLOSED[gv.status] and type(gv.text) == "string" and gv.text ~= "" then
      out.goal = gv.text
      local pr = gv.progress
      if type(pr) == "table" and type(pr.cur) == "number" and type(pr.max) == "number" then out.progress = ("%d/%d"):format(pr.cur, pr.max) end
      break
    end
  end
  if not out.title and not out.goal then return nil end
  return out
end

--- Polestar's guide window on / off (its own TOGGLE_FRAME message). true when it was asked.
function PS.ToggleGuide()
  local ns = PS.NS()
  if not ns or type(ns.Fire) ~= "function" then return false end
  return (pcall(ns.Fire, "TOGGLE_FRAME"))
end

-- ------------------------------------------------------------------------------------------------ listening
PS.listeners = {}

--- Something of ours that wants to hear Polestar's guide move (the tracker, the beam): fn(msg, ...).
function PS.Listen(fn) PS.listeners[#PS.listeners + 1] = fn end

local function relay(msg)
  return function(...)
    PS.counts[msg] = (PS.counts[msg] or 0) + 1
    for _, fn in ipairs(PS.listeners) do pcall(fn, msg, ...) end
  end
end

--- Subscribe to Polestar's bus once it is there (it loads after us: "HogTronUI" < "Polestar"). true when hooked.
function PS.Hook()
  if PS.hooked then return true end
  if not PS.Loaded() then return false end
  local ns = PS.NS()
  if type(ns.On) ~= "function" then return false end
  for _, msg in ipairs(PS.MESSAGES) do
    local ok, h = pcall(ns.On, msg, relay(msg))
    if ok then PS.handles[msg] = h end
  end
  PS.hooked = true
  PS.EnsureWaypoint()
  return true
end

--- arrow: Polestar puts its target on the game's arrow only with its "Blizzard waypoint" switch on (off by default) -
--- without it the HogTron beam has nothing to follow. Switched on ONCE (the player may turn it off again in Polestar).
function PS.EnsureWaypoint()
  if not PS.Leads("arrow") then return false end
  local gl = HH.db and HH.db.global
  if type(gl) ~= "table" or gl.polestarWaypointOn then return false end
  gl.polestarWaypointOn = true
  if PS.Get("nav.blizzardWaypoint") == true then return false end
  if PS.Set("nav.blizzardWaypoint", true) then
    HH:Print("Polestar: its \"Blizzard waypoint\" is on now, so the HogTron beam follows Polestar's arrow (Polestar options > Nav to change it).")
    return true
  end
  return false
end

-- ------------------------------------------------------------------------------------------------ diag
--- /hh polestardiag lines; also saved to HogTronUIDB.global.diag.polestar.
function PS.Diagnose()
  local ns = PS.NS()
  local step = PS.Step()
  local d = {
    loaded = PS.Loaded(), hooked = PS.hooked and true or false, guiding = PS.Guiding(),
    leads = { guide = PS.Leads("guide"), arrow = PS.Leads("arrow") },
    blizzardWaypoint = PS.Get("nav.blizzardWaypoint"), counts = PS.counts,
    engine = PS.Engine() ~= nil, step = step,
  }
  local gl = HH.db and HH.db.global
  if type(gl) == "table" then
    gl.diag = type(gl.diag) == "table" and gl.diag or {}
    gl.diag.polestar = d
  end
  local out = {}
  out[#out + 1] = ("polestar: %s, %s, engine %s, guiding %s"):format(d.loaded and "loaded" or (ns and "namespace only" or "not installed"),
    d.hooked and "listening" or "not listening", d.engine and "yes" or "no", d.guiding and "yes" or "no")
  out[#out + 1] = ("  leads: guide %s, arrow %s   Polestar's Blizzard waypoint: %s"):format(tostring(d.leads.guide), tostring(d.leads.arrow), tostring(d.blizzardWaypoint))
  if step then
    out[#out + 1] = ("  step %s/%s: %s - %s %s"):format(tostring(step.index), tostring(step.count), tostring(step.title), tostring(step.goal), step.progress or "")
  end
  local heard = {}
  for _, msg in ipairs(PS.MESSAGES) do heard[#heard + 1] = ("%s %d"):format(msg, PS.counts[msg] or 0) end
  out[#out + 1] = "  heard: " .. table.concat(heard, ", ")
  return out
end

HH:RegisterSlash("polestardiag", function()
  local ok, lines = pcall(PS.Diagnose)
  if not ok then HH:Print("polestardiag failed: " .. tostring(lines)) return end
  for _, l in ipairs(lines) do HH:Print(l) end
end, "what HogTron UI reads from Polestar (loaded, listening, the guide step, who points the arrow)")

-- Polestar loads after us: hook at login, and once more a moment later (a slow load)
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  PS.Hook()
  if C_Timer and C_Timer.After then C_Timer.After(2, PS.Hook) end
end)
PS.events = ev
