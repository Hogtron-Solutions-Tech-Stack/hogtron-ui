-- AoE-heal scope highlight while hovering a frame.
-- Prayer of Healing / Tranquility = the hovered unit's party (subgroup in a raid).
-- Chain Heal: addons cannot read unit-to-unit distance inside instances, so the
-- hovered unit's subgroup is used as the proximity proxy (documented deviation).
local HHF = HogHealsFrames
local HH = HogHeals

local E = { Events = {} }
local active = false

local function subgroupOf(unit)
  local n = unit and unit:match("^raid(%d+)$")
  if not n then return nil end
  local _, _, sub = GetRaidRosterInfo(tonumber(n))
  return sub
end

local function isPartyScope(unit)
  return unit == "player" or unit:match("^party%d$") ~= nil or unit:match("^hhtest") ~= nil
end

local function setGlows(predicate)
  for _, b in ipairs(HHF.UnitButton.All()) do
    if b.unit and predicate(b.unit) then b.aoeGlow:Show() else b.aoeGlow:Hide() end
  end
end

function E.OnEnter(button)
  local unit = button.unit
  if not unit then return end
  local class = HHF.Compat.ClassOf("player")
  local aoe = HH.AOE_HEAL[class]
  if not aoe then return end
  active = true
  local sub = subgroupOf(unit)
  if sub then
    setGlows(function(u) return subgroupOf(u) == sub end)
  elseif isPartyScope(unit) then
    setGlows(function(u) return isPartyScope(u) end)
  end
end

function E.OnLeave(button)
  if not active then return end
  active = false
  setGlows(function() return false end)
end

function E.Update(button, unit)
  if not active then button.aoeGlow:Hide() end
end

function E.Hide(button) button.aoeGlow:Hide() end

HHF.UnitButton.RegisterElement("aoeHealing", E)
