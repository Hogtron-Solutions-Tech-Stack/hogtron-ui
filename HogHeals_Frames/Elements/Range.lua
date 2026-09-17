-- Range fade. Polled (Ticker) because there is no range event.
local HHF = HogHealsFrames
local HH = HogHeals

local E = { Events = {}, Ticker = 0.25 }

local function inRange(unit)
  if unit == "player" or UnitIsUnit(unit, "player") then return true end
  local LRC = LibStub and LibStub("LibRangeCheck-3.0", true)
  if LRC and LRC.GetRange then
    local min, max = LRC:GetRange(unit)
    -- max == nil means "beyond the furthest checker" (out of range); otherwise max is the upper bound.
    if min ~= nil then return max ~= nil and max <= 40 end
  end
  local r, checked = UnitInRange(unit)
  -- Restricted clients answer with SECRET booleans: `if checked` itself throws. Hand the secret back untouched.
  if HHF.Compat.IsSecret(r) or HHF.Compat.IsSecret(checked) then return r, true end
  if checked then return r end
  return true
end

function E.Update(button, unit)
  local ap = HH.db.profile.frames.appearance
  local r, secret = inRange(unit)
  if secret then
    -- We may not branch on it, but the widget may: the client resolves the secret inside SetAlphaFromBoolean.
    if button.SetAlphaFromBoolean then
      button._secretRange = true
      button:SetAlphaFromBoolean(r, 1, ap.outOfRangeAlpha or 0.4)
    end
    return
  end
  button._secretRange = nil
  local alpha = r and 1 or (ap.outOfRangeAlpha or 0.4)
  HHF.UnitButton.SetAlphaReason(button, "range", alpha)
end

function E.Hide(button) HHF.UnitButton.SetAlphaReason(button, "range", 1) end

HHF.UnitButton.RegisterElement("range", E)
