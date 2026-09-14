-- Range fade. Polled (Ticker) because there is no range event.
local HHF = HogHealsFrames
local HH = HogHeals

local E = { Events = {}, Ticker = 0.25 }

local function inRange(unit)
  if unit == "player" or UnitIsUnit(unit, "player") then return true end
  local LRC = LibStub and LibStub("LibRangeCheck-3.0", true)
  if LRC and LRC.GetRange then
    local min, max = LRC:GetRange(unit)
    if min ~= nil then return (max ~= nil and max <= 40) or (min <= 40 and max ~= nil) end
  end
  local r, checked = UnitInRange(unit)
  if checked then return r end
  return true
end

function E.Update(button, unit)
  local ap = HH.db.profile.frames.appearance
  local alpha = inRange(unit) and 1 or (ap.outOfRangeAlpha or 0.4)
  HHF.UnitButton.SetAlphaReason(button, "range", alpha)
end

function E.Hide(button) HHF.UnitButton.SetAlphaReason(button, "range", 1) end

HHF.UnitButton.RegisterElement("range", E)
