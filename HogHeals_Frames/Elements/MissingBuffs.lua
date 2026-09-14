-- Missing-buff icon: the unit lacks a buff I can cast (Fort/Spirit, MotW, AI, Blessings).
local HHF = HogHealsFrames
local HH = HogHeals

local E = { Events = { "UNIT_AURA" } }

local function buffNames(unit)
  local set = {}
  local i = 1
  while true do
    local name = UnitAura(unit, i, "HELPFUL")
    if not name then break end
    set[name] = true
    i = i + 1
    if i > 40 then break end
  end
  return set
end

function E.Update(button, unit)
  local _, class = UnitClass("player")
  local list = HH.MissingBuffSpells(class)
  if #list == 0 or UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then
    button.missingBuff.spell = nil
    button.missingBuff:Hide()
    return
  end
  local have = buffNames(unit)
  local _, ptype = UnitPowerType(unit)
  for _, buff in ipairs(list) do
    local skip = buff.optional or (buff.manaOnly and ptype ~= "MANA")
    if not skip then
      local present = false
      for _, n in ipairs(buff.satisfiedBy) do if have[n] then present = true break end end
      if not present then
        button.missingBuff:SetTexture(buff.icon)
        button.missingBuff.spell = buff.name
        button.missingBuff:Show()
        return
      end
    end
  end
  button.missingBuff.spell = nil
  button.missingBuff:Hide()
end

function E.Hide(button) button.missingBuff:Hide() end

HHF.UnitButton.RegisterElement("missingBuffs", E)
