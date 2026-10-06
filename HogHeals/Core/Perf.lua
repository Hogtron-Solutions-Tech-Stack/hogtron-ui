-- /hh perf: how much CPU and memory each HogTron UI piece costs, measured in game.
--
-- Zero cost when off: nothing is wrapped until you start a measurement. `start` walks every HogTron UI module namespace
-- (HogHealsFrames, HogHealsQuests, ...) up to 3 tables deep and swaps each function for a timed wrapper
-- (debugprofilestop before / after); `stop` puts every original back. Callers that look a function up at call time
-- (event handlers, tickers, element updates - all of ours) get measured; a reference someone captured earlier just
-- keeps calling the original, unmeasured and unharmed.
-- Report: calls, total ms, ms per second of the window, worst single call; plus each addon's memory
-- (GetAddOnMemoryUsage) and the frame rate. Last report kept in diag.perf.
local ADDON, ns = ...
local HH = HogHeals

local Perf = { on = false, entries = {}, patched = {} }
HH.Perf = Perf

Perf.NAMESPACES = { "HogHealsFrames", "HogHealsHUD", "HogHealsMeter", "HogHealsQuests", "HogHealsPlates", "HogHealsChat",
  "HogHealsUnits", "HogHealsSkin" }
Perf.ADDONS = { "HogHeals", "HogHeals_Frames", "HogHeals_HUD", "HogHeals_Meter", "HogHeals_Quests", "HogHeals_Plates",
  "HogHeals_Chat", "HogHeals_Units", "HogHeals_Skin" }

local function now() return type(debugprofilestop) == "function" and debugprofilestop() or 0 end

--- A widget, not a plain table: never walk into frames (real ones carry userdata at [0]).
local function isWidget(t)
  return rawget(t, 0) ~= nil or type(rawget(t, "GetObjectType")) == "function" or rawget(t, "_kind") ~= nil
end

local function finish(e, t0, ...)
  local dt = now() - t0
  e.calls = e.calls + 1
  e.ms = e.ms + dt
  if dt > e.max then e.max = dt end
  return ...
end

local function wrap(name, fn)
  local e = Perf.entries[name] or { name = name, calls = 0, ms = 0, max = 0 }
  Perf.entries[name] = e
  return function(...)
    return finish(e, now(), fn(...))
  end
end

local function walk(tbl, path, depth, seen)
  if depth > 3 or seen[tbl] then return end
  seen[tbl] = true
  for k, v in pairs(tbl) do
    if type(k) == "string" then
      if type(v) == "function" then
        local name = path .. "." .. k
        local w = wrap(name, v)
        Perf.patched[#Perf.patched + 1] = { tbl = tbl, key = k, orig = v }
        rawset(tbl, k, w)
      elseif type(v) == "table" and not isWidget(v) then
        walk(v, path .. "." .. k, depth + 1, seen)
      end
    end
  end
end

function Perf.Start()
  if Perf.on then Perf.Stop() end
  wipe(Perf.entries)
  wipe(Perf.patched)
  local seen = {}
  for _, ns in ipairs(Perf.NAMESPACES) do
    local t = rawget(_G, ns)
    if type(t) == "table" then walk(t, ns:gsub("^HogHeals", ""), 1, seen) end
  end
  Perf.on, Perf.started = true, GetTime and GetTime() or 0
  return #Perf.patched
end

function Perf.Stop()
  for i = #Perf.patched, 1, -1 do
    local p = Perf.patched[i]
    rawset(p.tbl, p.key, p.orig)
  end
  wipe(Perf.patched)
  Perf.on = false
end

--- Memory per HogTron UI addon, KB. UpdateAddOnMemoryUsage walks every addon - only called on demand.
function Perf.Memory()
  local out, total = {}, 0
  if type(UpdateAddOnMemoryUsage) == "function" then pcall(UpdateAddOnMemoryUsage) end
  local get = rawget(_G, "GetAddOnMemoryUsage") or (type(C_AddOns) == "table" and C_AddOns.GetAddOnMemoryUsage)
  for _, a in ipairs(Perf.ADDONS) do
    if type(get) == "function" then
      local ok, kb = pcall(get, a)
      -- an addon that is not loaded reports 0 and is left out
      if ok and type(kb) == "number" and kb > 0 then out[#out + 1] = { name = a, kb = kb } total = total + kb end
    end
  end
  table.sort(out, function(x, y) return x.kb > y.kb end)
  return out, total
end

--- Top entries by total time. Returns rows + the window length in seconds.
function Perf.Report(limit)
  local rows = {}
  for _, e in pairs(Perf.entries) do if e.calls > 0 then rows[#rows + 1] = e end end
  table.sort(rows, function(a, b) return a.ms > b.ms end)
  local secs = math.max(0.001, (GetTime and GetTime() or 0) - (Perf.started or 0))
  local out = {}
  for i = 1, math.min(limit or 12, #rows) do out[i] = rows[i] end
  local total = 0
  for _, e in ipairs(rows) do total = total + e.ms end
  return out, secs, total
end

function Perf.Print()
  local rows, secs, total = Perf.Report(10)
  local mem, memTotal = Perf.Memory()
  local fps = type(GetFramerate) == "function" and GetFramerate() or 0
  HH:Print(("perf: %.0f s window, HogTron UI total %.2f ms (%.3f ms per second = %.2f%% of one 60 fps frame budget), %.0f fps now")
    :format(secs, total, total / secs, (total / secs) / (1000 / 60) * 100, fps))
  for _, e in ipairs(rows) do
    HH:Print(("  %-38s %6d calls %8.2f ms  %.3f ms/s  worst %.2f ms"):format(e.name, e.calls, e.ms, e.ms / secs, e.max))
  end
  local parts = {}
  for _, m in ipairs(mem) do parts[#parts + 1] = ("%s %.0f KB"):format(m.name:gsub("^HogHeals_?", ""):gsub("^$", "core"), m.kb) end
  HH:Print(("memory: %.0f KB total  (%s)"):format(memTotal, table.concat(parts, ", ")))
  local g = HH.db and HH.db.global
  if g then
    g.diag = g.diag or {}
    local saved = { at = date and date("%Y-%m-%d %H:%M:%S") or "", seconds = secs, totalMs = total, fps = fps, memoryKB = memTotal, top = {} }
    for i, e in ipairs(rows) do saved.top[i] = ("%s calls=%d ms=%.2f worst=%.2f"):format(e.name, e.calls, e.ms, e.max) end
    g.diag.perf = saved
  end
end

HH:RegisterSlash("perf", function(arg)
  arg = (arg or ""):lower()
  if arg == "stop" then
    if Perf.on then Perf.Print() end
    Perf.Stop()
    HH:Print("perf: stopped, everything unwrapped.")
  elseif arg == "" and Perf.on then
    Perf.Print()
  else
    local secs = tonumber(arg) or 60
    local n = Perf.Start()
    HH:Print(("perf: measuring %d functions for %d s - play normally (fight, walk, open bags). Report prints itself."):format(n, secs))
    if C_Timer and C_Timer.After then
      Perf.token = (Perf.token or 0) + 1
      local token = Perf.token
      C_Timer.After(secs, function()
        if Perf.on and Perf.token == token then Perf.Print() Perf.Stop() end
      end)
    end
  end
end, "measure CPU + memory of every HogTron UI part: /hh perf [seconds] | /hh perf (report now) | /hh perf stop")
