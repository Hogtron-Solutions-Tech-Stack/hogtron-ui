-- Mana bar + five-second rule + tick spark (FiveSecondRule pattern, pure state machine).
HogHealsHUD = HogHealsHUD or {}
local HHD = HogHealsHUD
local HH = HogHeals

local Mana = {}
HHD.Mana = Mana

local FSR = 5
local TICK = 2

local function cfg() return HH.db.profile.hud.mana end
local function row() return HHD.HUD.rows.mana end

function Mana.NewState(mana, t)
  return { lastMana = mana, t = t, fsrEnd = nil, lastTick = nil, nextTick = nil }
end

--- A successful cast: if it cost mana, the five-second rule starts.
function Mana.OnCast(state, mana, t)
  -- Secret mana cannot be compared, so the cost is invisible: treat every successful cast as a spend.
  if HH.IsSecret(mana) or HH.IsSecret(state.lastMana) or mana < state.lastMana then
    state.fsrEnd = t + FSR
    state.lastTick, state.nextTick = nil, nil
  end
  state.lastMana = mana
end

--- Observe a mana reading. Returns "tick" when a regen tick was detected outside the FSR window.
function Mana.Observe(state, mana, t)
  local ev
  if HH.IsSecret(mana) or HH.IsSecret(state.lastMana) then
    -- No way to see a regen tick in a secret number; the FSR window still runs off cast events.
    state.lastMana, state.t = mana, t
    return nil
  end
  if mana > state.lastMana then
    local inFsr = state.fsrEnd and t < state.fsrEnd
    if not inFsr then
      ev = "tick"
      state.lastTick, state.nextTick = t, t + TICK
    end
  end
  state.lastMana = mana
  state.t = t
  return ev
end

function Mana.Reset()
  Mana.state = Mana.NewState(UnitPower("player", 0), GetTime())
end

local function isMana()
  local _, ptype = UnitPowerType("player")
  return ptype == "MANA"
end

function Mana.Update()
  local r = row()
  if not r or not r.enabled then return end
  if not isMana() then r:Hide() return end
  local cur, max = UnitPower("player", 0), UnitPowerMax("player", 0)
  local secret = HH.IsSecret(cur) or HH.IsSecret(max)
  if not secret and max <= 0 then max = 1 end
  r:SetMinMaxValues(0, max)
  r:SetValue(cur)
  r:SetStatusBarColor(0.13, 0.55, 0.95)
  local mode = cfg().textMode or "cur"
  if mode == "cur" then r.text:SetText(("%d / %d"):format(cur, max))
  elseif mode == "percent" and secret then r.text:SetText(("%d / %d"):format(cur, max))  -- no division on secrets
  elseif mode == "percent" then r.text:SetText(("%d%%"):format(math.floor(cur / max * 100 + 0.5)))
  else r.text:SetText("") end
  r:Show()
end

function Mana.OnUpdate(r)
  local state = Mana.state
  if not state then return end
  local now = GetTime()
  local w = r:GetWidth()
  -- FSR drain overlay
  if state.fsrEnd and now < state.fsrEnd then
    local frac = (state.fsrEnd - now) / FSR
    r.fsr:SetWidth(math.max(0.001, w * frac))
    r.fsr:Show()
    if cfg().showFsrText then r.fsrText:SetText(("%.1f"):format(state.fsrEnd - now)); r.fsrText:Show() else r.fsrText:Hide() end
    r.tick:Hide()
    return
  end
  r.fsr:Hide()
  r.fsrText:Hide()
  -- tick spark
  if cfg().showTicks and state.lastTick and state.nextTick then
    while now > state.nextTick + 0.25 do
      state.lastTick, state.nextTick = state.nextTick, state.nextTick + TICK
    end
    local frac = (now - state.lastTick) / (state.nextTick - state.lastTick)
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    r.tick:ClearAllPoints()
    r.tick:SetPoint("LEFT", r, "LEFT", w * frac, 0)
    r.tick:Show()
  else
    r.tick:Hide()
  end
end

function Mana.OnEvent(_, event, unit, _, spellId)
  if unit and unit ~= "player" then return end
  local ok, err = pcall(function()
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
      Mana.OnCast(Mana.state, UnitPower("player", 0), GetTime())
      local r = row()
      if Mana.state.fsrEnd and r then r.fsr:Show() end
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
      Mana.Observe(Mana.state, UnitPower("player", 0), GetTime())
      Mana.Update()
    elseif event == "PLAYER_ENTERING_WORLD" then
      Mana.Reset(); Mana.Update()
    end
  end)
  if not ok then HH:LogError("mana " .. event .. ": " .. tostring(err)) end
end

function Mana.Init()
  if Mana.frame then return end
  Mana.Reset()
  local f = CreateFrame("Frame")
  for _, ev in ipairs({ "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_SPELLCAST_SUCCEEDED" }) do
    if f.RegisterUnitEvent then f:RegisterUnitEvent(ev, "player") else f:RegisterEvent(ev) end
  end
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:SetScript("OnEvent", Mana.OnEvent)
  Mana.frame = f
  local r = row()
  if r then
    r:SetScript("OnUpdate", function(self) Mana.OnUpdate(self) end)
    r.fsr:SetColorTexture(cfg().fsrColor[1], cfg().fsrColor[2], cfg().fsrColor[3], 0.35)
    r.tick:SetColorTexture(cfg().tickColor[1], cfg().tickColor[2], cfg().tickColor[3], 0.9)
  end
  Mana.Update()
end

function Mana.Refresh()
  local r = row()
  if r then
    r.fsr:SetColorTexture(cfg().fsrColor[1], cfg().fsrColor[2], cfg().fsrColor[3], 0.35)
    r.tick:SetColorTexture(cfg().tickColor[1], cfg().tickColor[2], cfg().tickColor[3], 0.9)
  end
  Mana.Update()
end
