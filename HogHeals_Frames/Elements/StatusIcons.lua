-- Status icon slot (top-left): ready check > resurrection > summon > leader/assist.
local HHF = HogHealsFrames

local E = { Events = { "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED", "INCOMING_RESURRECT_CHANGED",
                       "INCOMING_SUMMON_CHANGED", "PARTY_LEADER_CHANGED", "GROUP_ROSTER_UPDATE" } }

local TEX = {
  readyCheckWaiting = "Interface\\RaidFrame\\ReadyCheck-Waiting",
  readyCheckReady   = "Interface\\RaidFrame\\ReadyCheck-Ready",
  readyCheckNotReady= "Interface\\RaidFrame\\ReadyCheck-NotReady",
  res    = "Interface\\RaidFrame\\Raid-Icon-Rez",
  summon = "Interface\\RaidFrame\\Raid-Icon-SummonPending",
  leader = "Interface\\GroupFrame\\UI-Group-LeaderIcon",
  assist = "Interface\\GroupFrame\\UI-Group-AssistantIcon",
}

local function summonPending(unit)
  if C_IncomingSummon and C_IncomingSummon.HasIncomingSummon then return C_IncomingSummon.HasIncomingSummon(unit) end
  return false
end

function E.Update(button, unit)
  local kind, tex
  local rc = GetReadyCheckStatus and GetReadyCheckStatus(unit)
  if rc then
    kind = "readyCheck"
    tex = rc == "ready" and TEX.readyCheckReady or rc == "notready" and TEX.readyCheckNotReady or TEX.readyCheckWaiting
  elseif UnitHasIncomingResurrection(unit) then
    kind, tex = "res", TEX.res
  elseif summonPending(unit) then
    kind, tex = "summon", TEX.summon
  elseif UnitIsGroupLeader(unit) then
    kind, tex = "leader", TEX.leader
  elseif UnitIsGroupAssistant and UnitIsGroupAssistant(unit) then
    kind, tex = "assist", TEX.assist
  end
  button.statusIcon.kind = kind
  if kind then
    button.statusIcon:SetTexture(tex)
    button.statusIcon:Show()
  else
    button.statusIcon:Hide()
  end
end

function E.Hide(button) button.statusIcon:Hide() end

HHF.UnitButton.RegisterElement("statusIcons", E)
