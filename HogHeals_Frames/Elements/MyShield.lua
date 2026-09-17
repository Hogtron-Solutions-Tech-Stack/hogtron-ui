-- My shield on the unit (PW:S / Earth Shield cast by me) + Weakened Soul countdown.
local HHF = HogHealsFrames
local HH = HogHeals

local E = { Events = { "UNIT_AURA" }, Ticker = 1 }

local function findAura(unit, filter, names, mineOnly)
  local i = 1
  while true do
    local name, icon, count, _, _, expires, source = HHF.Compat.UnitAura(unit, i, filter)
    if not name then return nil end
    if names[name] and (not mineOnly or source == "player") then
      return { name = name, icon = icon, count = count, expires = expires or 0 }
    end
    i = i + 1
    if i > 40 then return nil end
  end
end

local WS = {}

function E.Update(button, unit)
  local _, class = UnitClass("player")
  local shields = {}
  for _, s in ipairs(HH.ShieldSpells(class)) do shields[s] = true end
  WS[HH.WEAKENED_SOUL] = true

  local shield = next(shields) and findAura(unit, "HELPFUL", shields, true) or nil
  if shield then
    button.shieldIcon:SetTexture(shield.icon)
    button.shieldIcon:Show()
  else
    button.shieldIcon:Hide()
  end

  local ws = (class == "PRIEST") and findAura(unit, "HARMFUL", WS, false) or nil
  if ws and ws.expires > 0 then
    local left = math.max(0, math.ceil(ws.expires - GetTime()))
    button.shieldText:SetText(tostring(left))
    button.shieldText:Show()
  else
    button.shieldText:Hide()
  end
end

function E.Hide(button)
  button.shieldIcon:Hide()
  button.shieldText:Hide()
end

HHF.UnitButton.RegisterElement("myShield", E)
