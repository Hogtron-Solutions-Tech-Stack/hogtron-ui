-- Name text, truncated, class-coloured.
local HHF = HogHealsFrames
local HH = HogHeals

local E = { Events = { "UNIT_NAME_UPDATE", "GROUP_ROSTER_UPDATE" } }

function E.Update(button, unit)
  local ap = HH.db.profile.frames.appearance
  local name = UnitName(unit) or UNKNOWN or "?"
  local n = ap.nameLength or 8
  if HHF.Compat.IsSecret(name) then
    -- May not measure or cut a secret string: let the font string clip it to the button instead.
    button.name:SetWidth(math.max(10, (button:GetWidth() or 0) - 6))
    if button.name.SetWordWrap then button.name:SetWordWrap(false) end
  elseif n > 0 and #name > n then name = name:sub(1, n) end
  button.name:SetText(name)
  local _, class = UnitClass(unit)
  local c = class and RAID_CLASS_COLORS[class]
  if ap.healthMode == "class" or not c then
    button.name:SetTextColor(0.96, 0.92, 0.86)
  else
    button.name:SetTextColor(c.r, c.g, c.b)
  end
  button.name:Show()
end

function E.Hide(button) button.name:Hide() end

HHF.UnitButton.RegisterElement("name", E)
