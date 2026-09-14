-- Dispel request over addon messages (Cell Request_Dispel pattern). API-safe: no aura/combat data.
-- Sender: /hh dispelme  (macro it). Receiver: the sender's frame glows for a few seconds.
HogHealsFrames = HogHealsFrames or {}
local HHF = HogHealsFrames
local HH = HogHeals

local RequestDispel = { PREFIX = "HHREQ", DURATION = 5, registered = false }
HHF.RequestDispel = RequestDispel

local E = { Events = {} }

local function stripRealm(name)
  return (name or ""):match("^([^%-]+)") or name
end

local function buttonForName(name)
  for _, b in ipairs(HHF.UnitButton.All()) do
    if b.unit and b:IsShown() and UnitName(b.unit) == name then return b end
  end
end

local function showGlow(button, kind)
  button.requestGlow.kind = kind
  button.requestGlow:Show()
  local token = (button.requestGlow.token or 0) + 1
  button.requestGlow.token = token
  C_Timer.After(RequestDispel.DURATION, function()
    if button.requestGlow.token == token then
      button.requestGlow.kind = nil
      button.requestGlow:Hide()
    end
  end)
end

function RequestDispel.OnMessage(prefix, msg, channel, sender)
  if prefix ~= RequestDispel.PREFIX then return end
  if HH.db.profile.frames.indicators.requestGlow == false then return end
  local kind = (msg == "D") and "dispel" or (msg:sub(1, 2) == "S:" and "spell") or nil
  if not kind then return end
  local button = buttonForName(stripRealm(sender))
  if not button then return end
  showGlow(button, kind)
end

function RequestDispel.Send(kind)
  local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY") or nil
  if not channel then HH:Print("Not in a group.") return false end
  local payload = kind == "dispel" and "D" or kind
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(RequestDispel.PREFIX, payload, channel)
  elseif SendAddonMessage then
    SendAddonMessage(RequestDispel.PREFIX, payload, channel)
  end
  return true
end

function RequestDispel.Init()
  if RequestDispel.registered then return end
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(RequestDispel.PREFIX)
  elseif RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(RequestDispel.PREFIX)
  end
  HH:RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, msg, channel, sender)
    RequestDispel.OnMessage(prefix, msg, channel, sender)
  end)
  RequestDispel.registered = true
end

function E.Update(button, unit)
  if not button.requestGlow.kind then button.requestGlow:Hide() end
end

function E.Hide(button) button.requestGlow:Hide() end

HHF.UnitButton.RegisterElement("requestGlow", E)

HH:RegisterSlash("dispelme", function() RequestDispel.Send("dispel") end, "ask healers for a dispel (macro this)")
