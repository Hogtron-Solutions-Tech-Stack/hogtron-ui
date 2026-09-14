-- Raid target marker (skull, cross, ...).
local HHF = HogHealsFrames

local E = { Events = { "RAID_TARGET_UPDATE" } }

-- Texture atlas is 4x4; index 1..8 occupies the top two rows.
local function coords(index)
  local col = (index - 1) % 4
  local row = math.floor((index - 1) / 4)
  return col * 0.25, col * 0.25 + 0.25, row * 0.25, row * 0.25 + 0.25
end

function E.Update(button, unit)
  local index = GetRaidTargetIndex(unit)
  if index and index >= 1 and index <= 8 then
    button.raidIcon:SetTexCoord(coords(index))
    button.raidIcon.index = index
    button.raidIcon:Show()
  else
    button.raidIcon.index = nil
    button.raidIcon:Hide()
  end
end

function E.Hide(button) button.raidIcon:Hide() end

HHF.UnitButton.RegisterElement("raidIcon", E)
