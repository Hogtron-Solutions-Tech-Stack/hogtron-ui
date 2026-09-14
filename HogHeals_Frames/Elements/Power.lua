-- Power bar (thin, bottom). healerOnly => only mana users show it.
local HHF = HogHealsFrames
local HH = HogHeals

local E = { Events = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_POWER_FREQUENT" } }

local POWER_COLORS = {
  MANA = { 0.13, 0.55, 0.95 }, RAGE = { 0.85, 0.2, 0.2 }, ENERGY = { 0.95, 0.85, 0.25 }, FOCUS = { 0.95, 0.5, 0.25 },
}

function E.Update(button, unit)
  local ap = HH.db.profile.frames.appearance
  local _, ptype = UnitPowerType(unit)
  if ap.powerHealerOnly and ptype ~= "MANA" then
    button.power:Hide()
    return
  end
  local cur, max = UnitPower(unit), UnitPowerMax(unit)
  if max <= 0 then max = 1 end
  button.power:SetMinMaxValues(0, max)
  button.power:SetValue(cur)
  local c = POWER_COLORS[ptype] or POWER_COLORS.MANA
  button.power:SetStatusBarColor(c[1], c[2], c[3])
  button.power:Show()
end

function E.Hide(button) button.power:Hide() end

HHF.UnitButton.RegisterElement("power", E)
