-- Aggro border: red when the unit has threat status >= 2 (tanking / high threat).
local HHF = HogHealsFrames

local E = { Events = { "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE" } }

function E.Update(button, unit)
  local status = UnitThreatSituation(unit) or 0
  if status >= 2 then
    button.aggroBorder:SetColorTexture(0.85, 0.2, 0.2, 0.8)
    button.aggroBorder:Show()
  elseif status == 1 then
    button.aggroBorder:SetColorTexture(0.95, 0.65, 0.15, 0.6)
    button.aggroBorder:Show()
  else
    button.aggroBorder:Hide()
  end
end

function E.Hide(button) button.aggroBorder:Hide() end

HHF.UnitButton.RegisterElement("aggro", E)
