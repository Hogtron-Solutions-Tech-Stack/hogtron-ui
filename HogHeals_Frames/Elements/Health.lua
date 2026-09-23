-- Health bar: value, colour (class | deficit | custom), state text, health-threshold fade.
local HHF = HogHealsFrames
local HH = HogHeals

local E = { Events = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_FLAGS", "PLAYER_FLAGS_CHANGED", "UNIT_HEALTH_FREQUENT" } }

local function deficitColor(pct)
  -- green (1.0) -> yellow (0.5) -> red (0.0)
  local r = math.min(1, (1 - pct) * 2)
  local g = math.min(1, pct * 2)
  return r, g, 0
end

function E.Update(button, unit)
  local d = HH.db.profile.frames
  local ap = d.appearance
  local hp, max = UnitHealth(unit), UnitHealthMax(unit)
  -- Secret values: the bar still fills (widgets accept secrets) but we may not divide or compare, so
  -- anything driven by a percentage (deficit colour, numbers, threshold fade) is skipped: pct == nil.
  local secret = HHF.Compat.IsSecret(hp) or HHF.Compat.IsSecret(max)
  local pct
  if not secret then
    if max <= 0 then max = 1 end
    pct = hp / max
  end
  button.health:SetMinMaxValues(0, max)
  button.health:SetValue(hp)

  -- colour
  local class = HHF.Compat.ClassOf(unit)   -- remembered: stays the class colour in combat (identity can be secret)
  local mode = ap.healthMode or "class"
  if mode == "deficit" and pct then
    button.health:SetStatusBarColor(deficitColor(pct))
  elseif mode == "custom" then
    local c = ap.healthColor or { 0.25, 0.8, 0.35 }
    button.health:SetStatusBarColor(c[1], c[2], c[3])
  else
    local c = class and RAID_CLASS_COLORS[class]
    if c then button.health:SetStatusBarColor(c.r, c.g, c.b) else button.health:SetStatusBarColor(0.6, 0.6, 0.6) end
  end
  -- dispel "color" style owns the bar colour while a dispellable debuff is up
  if button.dispelColored and button.dispelColor then
    button.health:SetStatusBarColor(button.dispelColor[1], button.dispelColor[2], button.dispelColor[3])
  end
  button.health.bg:SetColorTexture(0.15, 0.15, 0.17, 0.8)

  -- state text beats numbers
  local text
  if not UnitIsConnected(unit) then text = PLAYER_OFFLINE or "Offline"
  elseif UnitIsGhost(unit) then text = "Ghost"
  elseif UnitIsDead(unit) then text = DEAD or "Dead"
  elseif UnitIsAFK(unit) then text = AFK or "AFK"
  else
    local tm = pct and (ap.healthText or "deficit") or "none"
    if tm == "percent" then text = ("%d%%"):format(math.floor(pct * 100 + 0.5))
    elseif tm == "deficit" then
      local def = max - hp
      text = def > 0 and ("-" .. (def >= 1000 and ("%.1fk"):format(def / 1000) or tostring(def))) or ""
    else text = "" end
  end
  button.healthText:SetText(text)
  if text ~= "" then button.healthText:Show() else button.healthText:Hide() end
  button.healthDead = UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit)
  if button.healthDead then button.health:SetValue(0) end

  -- health-threshold fade (Danders pattern)
  local hf = d.healthFade
  local alpha = 1
  if pct and hf and hf.enabled and not button.healthDead and pct * 100 > (hf.above or 90) then alpha = hf.alpha or 0.5 end
  HHF.UnitButton.SetAlphaReason(button, "healthFade", alpha)
end

function E.Hide(button) end

HHF.UnitButton.RegisterElement("health", E)
