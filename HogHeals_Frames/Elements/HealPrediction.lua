-- Incoming heals overlay: mine / others / all, overheal marker. Native API on TBC+, LibHealComm on Era.
local HHF = HogHealsFrames
local HH = HogHeals

local E = { Events = { "UNIT_HEAL_PREDICTION", "UNIT_HEALTH", "UNIT_MAXHEALTH" }, Ticker = 0.5 }

local function incoming(unit)
  local mine, all = 0, 0
  if HHF.Compat.hasNativeIncoming and type(UnitGetIncomingHeals) == "function" then
    mine = UnitGetIncomingHeals(unit, "player") or 0
    all = UnitGetIncomingHeals(unit) or 0
  else
    local HC = LibStub and LibStub("LibHealComm-4.0", true)
    if HC then
      local guid = UnitGUID(unit)
      local me = UnitGUID("player")
      if guid then
        all = HC:GetHealAmount(guid, HC.ALL_HEALS) or 0
        mine = HC:GetHealAmount(guid, HC.ALL_HEALS, nil, me) or 0
        local mod = HC.GetHealModifier and HC:GetHealModifier(guid) or 1
        all, mine = all * mod, mine * mod
      end
    end
  end
  return mine, math.max(0, all - mine), all
end

local function anySecret(...)
  for i = 1, select("#", ...) do if HHF.Compat.IsSecret((select(i, ...))) then return true end end
  return false
end

function E.Update(button, unit)
  local cfg = HH.db.profile.frames.healPrediction
  -- Forever beta measured: UnitGetIncomingHeals AND UnitHealth are SECRET (no maths allowed). This overlay is all
  -- maths (missing = max - hp, width = shown / max), so with a secret input it steps aside instead of throwing on
  -- every health event in combat. A secret-safe overlay needs a client-drawn bar (follow-up, not done).
  local hp, max = UnitHealth(unit), UnitHealthMax(unit)
  -- plain assignment, never `x and f() or nil`: that tests the RESULT for truth, and testing a secret throws
  local rawMine, rawAll
  if HHF.Compat.hasNativeIncoming and type(UnitGetIncomingHeals) == "function" then
    rawMine = UnitGetIncomingHeals(unit, "player")
    rawAll = UnitGetIncomingHeals(unit)
  end
  if anySecret(hp, max, rawMine, rawAll) then
    button.healPred.overheal = false
    button.healPred:Hide()
    return
  end
  local mine, others, all = incoming(unit)
  local amount = (cfg.show == "mine") and mine or (cfg.show == "others") and others or all
  if amount <= 0 or max <= 0 or UnitIsDeadOrGhost(unit) then
    button.healPred.overheal = false
    button.healPred:Hide()
    return
  end
  local missing = math.max(0, max - hp)
  button.healPred.overheal = amount > missing
  local shown = math.min(amount, missing)
  local width = button.health:GetWidth()
  if not width or width == 0 then width = button:GetWidth() end
  button.healPred:SetWidth(width * (shown / max))
  if button.healPred.overheal and cfg.overheal then
    button.healPred:SetColorTexture(0.95, 0.65, 0.15, 0.6)
  else
    button.healPred:SetColorTexture(0.25, 0.8, 0.35, 0.5)
  end
  if shown > 0 then button.healPred:Show() else button.healPred:Hide() end
end

function E.Hide(button) button.healPred:Hide() end

HHF.UnitButton.RegisterElement("healPrediction", E)
