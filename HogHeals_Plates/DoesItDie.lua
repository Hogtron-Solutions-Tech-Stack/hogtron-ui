-- DoesItDie: will my DoT finish this mob before it runs out? A skull on the plate when it will (move on), a red X
-- pulsing when the DoT is about to drop and the mob will outlive it (reapply). Sean 2026-10-06, from the "Top 5
-- Forever addons" clip (#5 DoesItDie): "lets you know if your dot needs to be reapplied, or if it will finish off
-- the mob and move on to the next one... in real time".
--
-- Time to die = the mob's health slope over the last few seconds (UNIT_HEALTH samples), nothing fancier. My DoTs =
-- HARMFUL|PLAYER auras with a duration. Both are read on events and kept per unit; a half-second ticker only
-- compares cached numbers and pulses the mark, so an idle screen costs nothing.
--
-- Secret-safe: on a client that hides enemy health in combat (Forever can), the samples never arrive as numbers;
-- the mark stays off and /hh platediag says why. Self-wired like the plate cast bar: hooks on Plates.UpdateHealth /
-- Reset / Diagnose, all guarded.
HogHealsPlates = HogHealsPlates or {}
local HHP = HogHealsPlates
local HH = HogHeals
local Plates = HHP.Plates

local D = { samples = {}, dots = {}, state = {}, marks = {}, KEEP = 8, MIN_SPAN = 1.0 }
HHP.DoesItDie = D

local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local CROSS = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local GREEN, RED, CREAM = { 0.25, 0.80, 0.35 }, { 0.90, 0.25, 0.25 }, { 0.96, 0.92, 0.86 }

local function cfg() local pr = HH.db and HH.db.profile return (pr and pr.plates and pr.plates.die) or {} end   -- nil-safe: read at file load too
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d2, e, g, h = pcall(f, ...)
  if ok then return a, b, c, d2, e, g, h end
end
local function now() return (type(GetTime) == "function" and GetTime()) or 0 end

-- ------------------------------------------------------------------------------------------------ health slope
--- Remember the unit's health now. Returns the sample or nil (secret / unknown health -> D.secret counts it).
function D.Record(unit)
  if not unit then return nil end
  local hp = call(UnitHealth, unit)
  if hp == nil then return nil end
  if isSecret(hp) then D.secret = (D.secret or 0) + 1 return nil end
  if type(hp) ~= "number" then return nil end
  local t = now()
  local s = D.samples[unit]
  if not s then s = {} D.samples[unit] = s end
  s[#s + 1] = { t = t, hp = hp }
  while #s > 1 and (t - s[1].t) > D.KEEP do table.remove(s, 1) end
  return s[#s]
end

--- Seconds until the unit's health reaches 0 at the pace of the last KEEP seconds; nil when it is not dropping or
-- there is not MIN_SPAN of data yet. Pure over the samples: D.Slope(samples, now) for the tests.
function D.Slope(s, t)
  if not s or #s < 2 then return nil end
  local first, last = s[1], s[#s]
  local span = last.t - first.t
  if span < D.MIN_SPAN then return nil end
  local perSec = (first.hp - last.hp) / span
  if perSec <= 0 then return nil end
  return last.hp / perSec, perSec
end

function D.TimeToDie(unit)
  return D.Slope(D.samples[unit], now())
end

-- ------------------------------------------------------------------------------------------------ my DoTs
local function auraAt(unit, i)
  local get = type(C_UnitAuras) == "table" and C_UnitAuras.GetAuraDataByIndex
  if type(get) == "function" then
    local a = call(get, unit, i, "HARMFUL|PLAYER")
    if type(a) ~= "table" then return nil end
    return a.name, a.icon, a.duration, a.expirationTime
  end
  if type(UnitAura) ~= "function" then return nil end
  local name, icon, _, _, duration, expires = call(UnitAura, unit, i, "HARMFUL|PLAYER")
  if name == nil then return nil end
  return name, icon, duration, expires
end

--- Re-read my DoTs on the unit: { { name, icon, expires, duration } } with plain numbers only; kept per unit.
function D.ReadDots(unit)
  local out = {}
  for i = 1, 40 do
    local name, icon, duration, expires = auraAt(unit, i)
    if name == nil and icon == nil then break end
    local dur, exp = num(duration), num(expires)
    if dur and exp and dur > 0 then out[#out + 1] = { name = (not isSecret(name)) and name or "?", icon = icon, expires = exp, duration = dur } end
  end
  D.dots[unit] = out
  return out
end

--- Seconds left on the DoT of mine that ends FIRST (the one to reapply), and that DoT. nil without DoTs.
function D.Remaining(unit, t)
  t = t or now()
  local best, dot
  for _, a in ipairs(D.dots[unit] or {}) do
    local r = a.expires - t
    if r > 0 and (not best or r < best) then best, dot = r, a end
  end
  return best, dot
end

-- ------------------------------------------------------------------------------------------------ verdict
--- "dies" (the DoT outlives the mob: move on) | "reapply" (DoT ends first and soon) | "running" | nil (no DoT /
-- no reading). Pure given ttd, remaining and the settings: D.Verdict(ttd, remaining, c).
function D.Verdict(ttd, remaining, c)
  if not remaining then return nil end
  if not ttd then return "running" end
  local margin = c.margin or 0.1
  if ttd <= remaining * (1 - margin) then return "dies" end
  if remaining <= (c.reapplyAt or 3) then return "reapply" end
  return "running"
end

function D.State(unit, t)
  t = t or now()
  local remaining, dot = D.Remaining(unit, t)
  local ttd = D.TimeToDie(unit)
  local v = D.Verdict(ttd, remaining, cfg())
  local st = v and { verdict = v, ttd = ttd, remaining = remaining, dot = dot } or nil
  D.state[unit] = st
  return st
end

-- ------------------------------------------------------------------------------------------------ marks
local function mark(uf)
  local hh = uf.hh
  if not hh then return nil end
  if hh.die then return hh.die end
  local parent = hh.overlay or uf
  local f = CreateFrame("Frame", nil, parent)
  f:SetFrameLevel(((parent.GetFrameLevel and parent:GetFrameLevel()) or 1) + 3)
  f.icon = f:CreateTexture(nil, "OVERLAY")
  f.icon:SetAllPoints(f)
  f.time = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.time:SetPoint("TOP", f, "BOTTOM", 0, -1)
  f:Hide()
  hh.die = f
  D.marks[uf] = f
  return f
end

--- Paint a mark frame from a state (plate or target frame). Pure-ish: no API reads.
function D.Paint(f, st, size, pulseOn)
  if not f then return end
  if not st or st.verdict == "running" or st.verdict == nil then f:Hide() return end
  local c = cfg()
  f:SetSize(size, size)
  if st.verdict == "dies" then
    f.icon:SetTexture(SKULL)
    f.icon:SetVertexColor(1, 1, 1)
    f:SetAlpha(1)
    f.time:SetText(c.showTime ~= false and st.ttd and ("%.0fs"):format(st.ttd) or "")
    f.time:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
  else
    f.icon:SetTexture(CROSS)
    f:SetAlpha(pulseOn and 1 or 0.45)
    f.time:SetText(c.showTime ~= false and st.remaining and ("%.0fs"):format(st.remaining) or "")
    f.time:SetTextColor(RED[1], RED[2], RED[3])
  end
  f:Show()
end

function D.Place(uf)
  local hh = uf.hh
  local f = hh and hh.die
  if not f then return end
  local anchor = hh.bar or uf
  f:ClearAllPoints()
  f:SetPoint("LEFT", anchor, "RIGHT", (cfg().gap or 4), 0)
end

--- Repaint every active plate's mark (and the target frame's) from cached numbers.
function D.Tick()
  local c = cfg()
  if c.enabled == false or not Plates then return end
  local t = now()
  D.pulse = not D.pulse
  local any = false
  for unit, uf in pairs(Plates.active or {}) do
    if uf.hh and (D.dots[unit] and #D.dots[unit] > 0) then
      local st = D.State(unit, t)
      local f = mark(uf)
      if f then D.Place(uf) D.Paint(f, st, c.size or 18, D.pulse) end
      if st then any = true end
    elseif uf.hh and uf.hh.die then
      uf.hh.die:Hide()
      D.state[unit] = nil
    end
  end
  D.TargetMark(t)
  D.anyShown = any
end

--- The same mark on our target frame (HogTron UI Units), when that addon is loaded and the option is on.
function D.TargetMark(t)
  local c = cfg()
  local U = rawget(_G, "HogHealsUnits")
  local frames = type(U) == "table" and U.Units and U.Units.frames
  local f = type(frames) == "table" and frames.target
  if not f or c.target == false then if D.targetMark then D.targetMark:Hide() end return end
  if not D.targetMark then
    local parent = f.overlay or f
    local m = CreateFrame("Frame", nil, parent)
    m:SetFrameLevel(((parent.GetFrameLevel and parent:GetFrameLevel()) or 1) + 3)
    m.icon = m:CreateTexture(nil, "OVERLAY")
    m.icon:SetAllPoints(m)
    m.time = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    m.time:SetPoint("RIGHT", m, "LEFT", -3, 0)
    m:SetPoint("RIGHT", f.health or f, "RIGHT", -4, 0)
    m:Hide()
    D.targetMark = m
  end
  if not (D.dots.target and #D.dots.target > 0) then D.targetMark:Hide() return end
  D.Paint(D.targetMark, D.State("target", t), (c.size or 18) + 2, D.pulse)
end

-- ------------------------------------------------------------------------------------------------ events
local function forget(unit)
  D.samples[unit], D.dots[unit], D.state[unit] = nil, nil, nil
end

function D.OnEvent(_, e, unit)
  if cfg().enabled == false then return end
  if e == "UNIT_AURA" then
    if type(unit) == "string" and (unit:find("^nameplate") or unit == "target") then D.ReadDots(unit) end
  elseif e == "PLAYER_TARGET_CHANGED" then
    forget("target")
    if call(UnitExists, "target") then D.ReadDots("target") D.Record("target") end
  elseif e == "UNIT_HEALTH" or e == "UNIT_HEALTH_FREQUENT" then
    if unit == "target" then D.Record("target") end
  elseif e == "NAME_PLATE_UNIT_REMOVED" then
    forget(unit)
  elseif e == "NAME_PLATE_UNIT_ADDED" then
    forget(unit)
    D.ReadDots(unit)
    D.Record(unit)
  end
end

function D.Start()
  if D.frame then return end
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "UNIT_AURA", "PLAYER_TARGET_CHANGED", "UNIT_HEALTH", "NAME_PLATE_UNIT_REMOVED", "NAME_PLATE_UNIT_ADDED" }) do
    pcall(f.RegisterEvent, f, e)
  end
  f:SetScript("OnEvent", D.OnEvent)
  D.frame = f
  if C_Timer and C_Timer.NewTicker then D.ticker = C_Timer.NewTicker(0.5, D.Tick) end
end

function D.DiagLine()
  local n = 0
  for _ in pairs(D.dots) do n = n + 1 end
  return ("does it die: %s; units with my DoTs: %d; marks shown: %s; secret health readings: %d%s"):format(
    cfg().enabled == false and "off" or "on", n, tostring(D.anyShown or false), D.secret or 0,
    (D.secret or 0) > 0 and " (this client hides enemy health here: no time-to-die)" or "")
end

-- self-wiring onto the plates, every hook guarded (Plates.lua differs between branches)
if type(Plates) == "table" and type(hooksecurefunc) == "function" then
  if type(Plates.UpdateHealth) == "function" then
    hooksecurefunc(Plates, "UpdateHealth", function(uf) local hh = uf and uf.hh if hh and hh.unit then pcall(D.Record, hh.unit) end end)
  end
  if type(Plates.Reset) == "function" then
    hooksecurefunc(Plates, "Reset", function(uf) if uf and uf.hh and uf.hh.die then uf.hh.die:Hide() end end)
  end
  if type(Plates.Diagnose) == "function" then
    local orig = Plates.Diagnose
    Plates.Diagnose = function(...)
      local lines = orig(...)
      if type(lines) == "table" then lines[#lines + 1] = D.DiagLine() end
      return lines
    end
  end
end

D.Start()
