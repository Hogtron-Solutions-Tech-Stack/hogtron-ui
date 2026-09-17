-- Mana pacing: fight timer, burn-rate EMA from mana samples, OOM ETA, projection at a target fight length.
-- Uses only UnitPower sampling — never the combat log (Forever API safety).
HogHealsHUD = HogHealsHUD or {}
local HHD = HogHealsHUD
local HH = HogHeals

local Pacing = { state = nil }
HHD.Pacing = Pacing

local ALPHA = 0.2

local function cfg() return HH.db.profile.hud.pacing end
local function info() return HHD.HUD.rows.info end

function Pacing.NewState(mana, t)
  return { startMana = mana, mana = mana, lastMana = mana, startT = t, lastT = t, burn = 0, samples = 0, elapsed = 0, inCombat = false }
end

--- Feed one sample. burn = EMA of positive net mana loss per second.
function Pacing.Step(state, mana, t)
  local dt = t - state.lastT
  if dt <= 0 then return state end
  local loss = math.max(0, (state.lastMana - mana) / dt)
  if state.samples == 0 then state.burn = loss
  else state.burn = state.burn + ALPHA * (loss - state.burn) end
  state.samples = state.samples + 1
  state.lastMana, state.mana = mana, mana
  state.lastT = t
  state.elapsed = t - state.startT
  return state
end

--- Seconds until out of mana at the current burn, or nil when not burning.
function Pacing.Eta(state)
  if not state or state.burn <= 0 then return nil end
  return state.mana / state.burn
end

--- Projected mana when the fight reaches targetLength seconds (clamped at 0).
function Pacing.Project(state, targetLength)
  local remaining = math.max(0, (targetLength or 0) - state.elapsed)
  return math.max(0, state.mana - state.burn * remaining)
end

function Pacing.Fmt(seconds)
  seconds = math.max(0, math.floor(seconds + 0.5))
  return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

function Pacing.Colour(eta)
  if not eta then return "normal" end
  local c = cfg()
  if eta < (c.red or 20) then return "red" end
  if eta < (c.amber or 60) then return "amber" end
  return "normal"
end

local COLOURS = { normal = { 0.96, 0.92, 0.86 }, amber = { 0.95, 0.65, 0.15 }, red = { 0.85, 0.2, 0.2 } }

local function render()
  local state = Pacing.state
  local i = info()
  if not state or not i then return end
  local eta = Pacing.Eta(state)
  local parts = { "OOM " .. (eta and Pacing.Fmt(eta) or "∞"), Pacing.Fmt(state.elapsed) }
  local c = cfg()
  if c.showProjection and c.targetLength and c.targetLength > 0 and UnitPowerMax("player", 0) > 0 then
    local pct = math.floor(Pacing.Project(state, c.targetLength) / UnitPowerMax("player", 0) * 100 + 0.5)
    parts[#parts + 1] = ("at %s: %d%%"):format(Pacing.Fmt(c.targetLength), pct)
  end
  i.left:SetText(table.concat(parts, " · "))
  local col = COLOURS[Pacing.Colour(eta)]
  i.left:SetTextColor(col[1], col[2], col[3])
end

function Pacing.Tick()
  local state = Pacing.state
  if not state or not state.inCombat or not cfg().enabled then return end
  Pacing.Step(state, UnitPower("player", 0), GetTime())
  render()
end

local function clearLater()
  local token = (Pacing.clearToken or 0) + 1
  Pacing.clearToken = token
  C_Timer.After(10, function()
    if Pacing.clearToken == token and Pacing.state and not Pacing.state.inCombat then
      local i = info()
      if i then i.left:SetText("") end
    end
  end)
end

function Pacing.OnEvent(_, event)
  if event == "PLAYER_REGEN_DISABLED" then
    Pacing.state = Pacing.NewState(UnitPower("player", 0), GetTime())
    Pacing.state.inCombat = true
    if Pacing.ticker then Pacing.ticker:Cancel() end
    Pacing.ticker = C_Timer.NewTicker(1, Pacing.Tick)
    render()
  elseif event == "PLAYER_REGEN_ENABLED" then
    if Pacing.state then
      Pacing.Step(Pacing.state, UnitPower("player", 0), GetTime())
      Pacing.state.inCombat = false
      render()
    end
    if Pacing.ticker then Pacing.ticker:Cancel(); Pacing.ticker = nil end
    clearLater()
  end
end

function Pacing.Init()
  if Pacing.frame then return end
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_REGEN_DISABLED")
  f:RegisterEvent("PLAYER_REGEN_ENABLED")
  f:SetScript("OnEvent", Pacing.OnEvent)
  Pacing.frame = f
end

function Pacing.Refresh() if Pacing.state then render() end end
