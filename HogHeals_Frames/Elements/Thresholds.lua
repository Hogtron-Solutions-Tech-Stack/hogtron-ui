-- Health threshold tick marks (e.g. 35% / 50%) on the health bar.
local HHF = HogHealsFrames
local HH = HogHeals

local E = { Events = { "UNIT_MAXHEALTH" } }

function E.Update(button, unit)
  local pcts = HH.db.profile.frames.thresholds or {}
  local width = button.health:GetWidth()
  if not width or width == 0 then width = button:GetWidth() end
  for i, pct in ipairs(pcts) do
    local tick = button.thresholds[i]
    if not tick then
      tick = button.health:CreateTexture(nil, "OVERLAY", nil, 6)
      tick:SetWidth(1)
      tick:SetColorTexture(0.96, 0.92, 0.86, 0.6)
      button.thresholds[i] = tick
    end
    tick:ClearAllPoints()
    tick:SetPoint("LEFT", button.health, "LEFT", (pct / 100) * width, 0)
    tick:SetHeight(button.health:GetHeight() > 0 and button.health:GetHeight() or button:GetHeight())
    tick:Show()
  end
  for i = #pcts + 1, #button.thresholds do button.thresholds[i]:Hide() end
end

function E.Hide(button)
  for _, t in ipairs(button.thresholds) do t:Hide() end
end

HHF.UnitButton.RegisterElement("thresholds", E)
