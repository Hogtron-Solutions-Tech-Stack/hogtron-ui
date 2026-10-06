-- Session: how this sitting is going - time played, experience and gold gained, XP an hour, how long to the next
-- level at the pace you are actually making. One table every module can read (info bar datatexts, the quest
-- tracker's GO line, Where next). Sean 2026-10-06, from the Forever Companion clip: "an overview of your current
-- session and XP gained per hour".
--
-- Pace = the last 15 minutes when there are at least 5 minutes of them, else the whole session: a dinner break
-- should not make "lvl in 38m" say three hours. Secret-safe: UnitXP / GetMoney can come back opaque on a
-- restricted client - then Stats().hidden says so and the texts show "-", nothing is compared.
local HH = HogHeals

local S = { xp = 0, gold = 0, window = {}, WINDOW = 900, MIN_RECENT = 300, MIN_RATE_SECS = 60 }
HH.Session = S

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a = pcall(f, ...)
  if ok then return a end
end
local function now() return (type(GetTime) == "function" and GetTime()) or 0 end

local function readXP()
  return num(call(rawget(_G, "UnitXP"), "player")), num(call(rawget(_G, "UnitXPMax"), "player")), num(call(rawget(_G, "UnitLevel"), "player"))
end

--- Start (or restart) the count from this moment.
function S.Reset()
  S.start = now()
  S.xp, S.gold = 0, 0
  S.window = {}
  S.levels = 0
  local xp, max, lvl = readXP()
  S.lastXP, S.lastMax, S.lastLevel = xp, max, lvl
  S.lastMoney = num(call(rawget(_G, "GetMoney")))
  S.hidden = nil
  if rawget(_G, "UnitXP") and xp == nil then S.hidden = "experience is hidden on this client" end
  S.window[1] = { t = S.start, xp = 0 }
  return S
end

local function push()
  local t = now()
  local w = S.window
  w[#w + 1] = { t = t, xp = S.xp }
  -- keep ~20 minutes of samples; the rate reads the oldest inside the window
  while #w > 2 and (t - w[1].t) > S.WINDOW + 300 do table.remove(w, 1) end
end

--- Experience changed (PLAYER_XP_UPDATE / PLAYER_LEVEL_UP). Pure given the readings; returns the xp gained.
function S.OnXP()
  local xp, max, lvl = readXP()
  if xp == nil or max == nil then
    if rawget(_G, "UnitXP") then S.hidden = "experience is hidden on this client" end
    return 0
  end
  S.hidden = nil
  local gained = 0
  if S.lastXP == nil then
    -- first readable value: the baseline, nothing gained yet
  elseif lvl and S.lastLevel and lvl > S.lastLevel then
    -- levelled: the rest of the old bar, any whole bars between, then the new bar's start
    gained = math.max(0, (S.lastMax or 0) - S.lastXP) + xp
    S.levels = (S.levels or 0) + (lvl - S.lastLevel)
  else
    gained = math.max(0, xp - S.lastXP)
  end
  S.lastXP, S.lastMax, S.lastLevel = xp, max, lvl
  if gained > 0 then
    S.xp = S.xp + gained
    push()
  end
  return gained
end

function S.OnMoney()
  local m = num(call(rawget(_G, "GetMoney")))
  if m == nil then return end
  if S.lastMoney then S.gold = S.gold + (m - S.lastMoney) end
  S.lastMoney = m
end

--- XP an hour over the last WINDOW seconds, nil without MIN_RECENT seconds of samples.
function S.RecentRate()
  local w, t = S.window, now()
  local oldest
  for i = 1, #w do
    if t - w[i].t <= S.WINDOW then oldest = w[i] break end
  end
  if not oldest then return nil end
  local dt = t - oldest.t
  if dt < S.MIN_RECENT then return nil end
  return (S.xp - oldest.xp) / dt * 3600
end

--- Everything the UI shows. rate = xp/hour used for the ETA (recent pace, else the session's), rateSource =
-- "recent" | "session" | nil; toLevel = seconds to the next level at that pace, nil when it cannot be told.
function S.Stats()
  if not S.start then S.Reset() end
  local t = now()
  local secs = math.max(0, t - S.start)
  local out = { seconds = secs, xp = S.xp, gold = S.gold, levels = S.levels or 0, hidden = S.hidden }
  out.sessionRate = secs >= S.MIN_RATE_SECS and S.xp / secs * 3600 or nil
  out.goldPerHour = secs >= S.MIN_RATE_SECS and S.gold / secs * 3600 or nil
  local recent = S.RecentRate()
  if recent and recent > 0 then out.rate, out.rateSource = recent, "recent"
  elseif out.sessionRate and out.sessionRate > 0 then out.rate, out.rateSource = out.sessionRate, "session" end
  local xp, max, lvl = readXP()
  out.level, out.xpNow, out.xpMax = lvl, xp, max
  if xp and max and max > 0 then
    out.remaining = math.max(0, max - xp)
    out.percent = xp / max * 100
    if out.rate and out.rate > 0 then out.toLevel = out.remaining / out.rate * 3600 end
  end
  return out
end

--- "1h 12m" / "38m" / "<1m"
function S.FormatTime(secs)
  if type(secs) ~= "number" or secs < 0 then return "-" end
  if secs < 60 then return "<1m" end
  local h, m = math.floor(secs / 3600), math.floor((secs % 3600) / 60)
  if h > 0 then return ("%dh %dm"):format(h, m) end
  return ("%dm"):format(m)
end

--- "4.2k" / "812" / "1.3m"
function S.FormatNumber(n)
  if type(n) ~= "number" then return "-" end
  if n >= 1e6 then return ("%.1fm"):format(n / 1e6) end
  if n >= 1e4 then return ("%.0fk"):format(n / 1e3) end
  if n >= 1e3 then return ("%.1fk"):format(n / 1e3) end
  return ("%d"):format(n)
end

--- Copper -> "12g 34s"
function S.FormatMoney(copper)
  if type(copper) ~= "number" then return "-" end
  local sign = copper < 0 and "-" or ""
  copper = math.abs(math.floor(copper + 0.5))
  local g, s = math.floor(copper / 10000), math.floor(copper / 100) % 100
  if g > 0 then return ("%s%dg %ds"):format(sign, g, s) end
  if s > 0 then return ("%s%ds %dc"):format(sign, s, copper % 100) end
  return ("%s%dc"):format(sign, copper)
end

--- Chat lines for /hh session.
function S.Lines()
  local st = S.Stats()
  local out = {}
  if st.hidden then out[#out + 1] = "session: " .. st.hidden .. "; time and gold still count." end
  out[#out + 1] = ("session: %s played, %s xp (%s), %s gold%s"):format(S.FormatTime(st.seconds), S.FormatNumber(st.xp),
    st.levels > 0 and (st.levels .. " level" .. (st.levels > 1 and "s" or "")) or "no level yet", S.FormatMoney(st.gold),
    st.goldPerHour and (" (" .. S.FormatMoney(st.goldPerHour) .. "/h)") or "")
  if st.rate then
    out[#out + 1] = ("pace: %s xp/h (%s)%s"):format(S.FormatNumber(st.rate), st.rateSource == "recent" and "last 15 min" or "whole session",
      st.toLevel and (("; level %d in %s"):format((st.level or 0) + 1, S.FormatTime(st.toLevel))) or "")
  else
    out[#out + 1] = "pace: not enough yet (a minute of play and some experience)."
  end
  return out
end

-- ------------------------------------------------------------------------------------------------ wiring
function S.Init()
  if S.frame then return S.frame end
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_MONEY" }) do
    pcall(f.RegisterEvent, f, e)   -- a client that lacks an event name throws
  end
  f:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_ENTERING_WORLD" then
      if not S.start then S.Reset() else S.OnXP() S.OnMoney() end
    elseif e == "PLAYER_MONEY" then S.OnMoney()
    else S.OnXP() end
  end)
  S.frame = f
  if not S.start then S.Reset() end
  return f
end

HH:RegisterSlash("session", function(rest)
  rest = (rest or ""):lower()
  if rest == "reset" then S.Reset() HH:Print("session: count restarted.") return end
  for _, l in ipairs(S.Lines()) do HH:Print(l) end
end, "this sitting: time, xp, gold, xp/hour, time to the next level (/hh session reset)")

S.Init()
