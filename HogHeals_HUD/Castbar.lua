-- Player castbar: cast/channel state machine, latency segment, spark, GCD sliver, Blizzard bar hide.
HogHealsHUD = HogHealsHUD or {}
local HHD = HogHealsHUD
local HH = HogHeals

local Castbar = { state = { casting = false, channel = false } }
HHD.Castbar = Castbar

local BLIZZ_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
  "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
  "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_ENTERING_WORLD" }

local function cfg() return HH.db.profile.hud.castbar end
local function bar() return HHD.HUD.rows.castbar end

--- 0..1 fill for the bar at time `now`. Casts fill up, channels drain.
function Castbar.Progress(state, now)
  local dur = (state.endTime or 0) - (state.startTime or 0)
  if dur <= 0 then return 0 end
  local p = (now - state.startTime) / dur
  if p < 0 then p = 0 elseif p > 1 then p = 1 end
  if state.channel then return 1 - p end
  return p
end

local function round(x, places)
  local m = 10 ^ (places or 0)
  return math.floor(x * m + 0.5) / m
end

local function setColour(b, c) b:SetStatusBarColor(c[1], c[2], c[3]) end

local function targetSuffix()
  if not cfg().showTarget then return "" end
  -- "»" is Latin-1: every Blizzard / LSM font has it. "→" is not and drew as an empty box (in game 2026-09-23).
  if UnitExists("target") and UnitName("target") then return " » " .. UnitName("target") end
  return ""
end

local function begin(state, name, texture, startMS, endMS, notInterruptible, channel)
  local b = bar()
  state.casting, state.channel = true, channel and true or false
  state.name = name
  state.startTime, state.endTime = startMS / 1000, endMS / 1000
  state.notInterruptible = notInterruptible and true or false
  local _, _, _, world = GetNetStats()
  state.latency = (world or 0) / 1000
  b.icon:SetTexture(texture)
  state.texture = texture                                   -- for /hh castdiag
  b.text:SetText(name .. targetSuffix())
  local c = cfg()
  if state.notInterruptible then setColour(b, c.uninterruptibleColor)
  elseif channel then setColour(b, c.channelColor) else setColour(b, c.castColor) end
  local dur = state.endTime - state.startTime
  if c.latency and dur > 0 and state.latency > 0 then
    b.latency:SetWidth(math.min(b:GetWidth(), b:GetWidth() * (state.latency / dur)))
    b.latency:Show()
  else
    b.latency:Hide()
  end
  b.spark:Show()
  b:SetMinMaxValues(0, 1)
  b:SetValue(channel and 1 or 0)
  b:Show()
  b:SetScript("OnUpdate", function(self) Castbar.OnUpdate(self) end)
  Castbar.OnUpdate(b)
end

local function finish(state)
  local b = bar()
  state.casting, state.channel = false, false
  b:SetScript("OnUpdate", nil)
  b.spark:Hide()
  b.latency:Hide()
  b:Hide()
end

function Castbar.OnUpdate(b)
  local state = Castbar.state
  if not state.casting then return end
  local now = GetTime()
  local p = Castbar.Progress(state, now)
  b:SetValue(p)
  local remaining = math.max(0, state.endTime - now)
  local places = cfg().precision or 1
  b.time:SetText(("%." .. places .. "f"):format(round(remaining, places)))
  local w = b:GetWidth()
  if w and w > 0 then
    b.spark:ClearAllPoints()
    b.spark:SetPoint("CENTER", b, "LEFT", w * p, 0)
  end
  if cfg().gcd and b.gcd then
    local start, dur = GetSpellCooldown(Castbar.gcdSpell or 0)
    if start and dur and dur > 0 and dur <= 1.5 then
      b.gcd:SetValue(math.min(1, (now - start) / dur)); b.gcd:Show()
    else b.gcd:Hide() end
  end
  if now >= state.endTime + 0.5 then finish(state) end
end

-- ---------------------------------------------------------------- events
local handlers = {}

function handlers.UNIT_SPELLCAST_START()
  local name, _, texture, startMS, endMS, _, _, notInterruptible = UnitCastingInfo("player")
  if not name then return end
  begin(Castbar.state, name, texture, startMS, endMS, notInterruptible, false)
end

function handlers.UNIT_SPELLCAST_DELAYED()
  local name, _, _, startMS, endMS = UnitCastingInfo("player")
  if not name or not Castbar.state.casting then return end
  Castbar.state.startTime, Castbar.state.endTime = startMS / 1000, endMS / 1000
end

function handlers.UNIT_SPELLCAST_CHANNEL_START()
  local name, _, texture, startMS, endMS, _, notInterruptible = UnitChannelInfo("player")
  if not name then return end
  begin(Castbar.state, name, texture, startMS, endMS, notInterruptible, true)
end

function handlers.UNIT_SPELLCAST_CHANNEL_UPDATE()
  local name, _, _, startMS, endMS = UnitChannelInfo("player")
  if not name or not Castbar.state.channel then return end
  Castbar.state.startTime, Castbar.state.endTime = startMS / 1000, endMS / 1000
end

function handlers.UNIT_SPELLCAST_STOP()
  if Castbar.state.casting and not Castbar.state.channel then finish(Castbar.state) end
end

function handlers.UNIT_SPELLCAST_CHANNEL_STOP()
  if Castbar.state.channel then finish(Castbar.state) end
end

local function failed(label)
  local state = Castbar.state
  if not state.casting then return end
  local b = bar()
  state.casting, state.channel = false, false
  b:SetScript("OnUpdate", nil)
  b.spark:Hide()
  b.latency:Hide()
  setColour(b, cfg().failColor)
  b.text:SetText(label)
  b:SetValue(1)
  local token = (state.failToken or 0) + 1
  state.failToken = token
  C_Timer.After(0.3, function() if state.failToken == token and not state.casting then b:Hide() end end)
end

function handlers.UNIT_SPELLCAST_INTERRUPTED() failed("Interrupted") end
function handlers.UNIT_SPELLCAST_FAILED() failed("Failed") end

function Castbar.OnEvent(_, event, unit)
  if unit and unit ~= "player" then return end
  local h = handlers[event]
  if h then
    local ok, err = pcall(h)
    if not ok then HH:LogError("castbar " .. event .. ": " .. tostring(err)) end
  end
end

--- Ours on -> Blizzard's off. Ours off (row disabled, or "hide" unticked) -> Blizzard's comes back.
-- The frame is CastingBarFrame on classic-engine clients and PlayerCastingBarFrame on modern-engine ones
-- (WoW: Forever included); looking for the old name only meant this silently did nothing there.
function Castbar.ApplyBlizzard()
  local f = _G.PlayerCastingBarFrame or _G.CastingBarFrame
  if not f then return end
  local hud = HH.db.profile.hud
  local wantHidden = cfg().hideBlizzard and hud.showCastbar ~= false
  if wantHidden then
    f:UnregisterAllEvents()
    f:Hide()
    Castbar.blizzHidden = true
  elseif Castbar.blizzHidden then
    for _, ev in ipairs(BLIZZ_EVENTS) do
      -- pcall: some clients throw on event names they do not know
      if ev:sub(1, 5) == "UNIT_" and f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, ev, "player")
      else pcall(f.RegisterEvent, f, ev) end
    end
    Castbar.blizzHidden = false
  end
end

function Castbar.Init()
  if Castbar.frame then return end
  local f = CreateFrame("Frame")
  for _, ev in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
    if f.RegisterUnitEvent then f:RegisterUnitEvent(ev, "player") else f:RegisterEvent(ev) end
  end
  f:SetScript("OnEvent", Castbar.OnEvent)
  Castbar.frame = f
  local _, class = UnitClass("player")
  local GCD_REF = { PRIEST = 139, SHAMAN = 324, PALADIN = 19740, DRUID = 774, MAGE = 1459, WARLOCK = 687 }
  Castbar.gcdSpell = GCD_REF[class]
  Castbar.ApplyBlizzard()
end

function Castbar.Refresh()
  Castbar.ApplyBlizzard()
end

--- What the last cast handed us, for the "what is that icon" question (Sean 2026-09-23).
function Castbar.Diagnose()
  local s, b = Castbar.state, HHD.HUD.rows.castbar
  local secret = type(issecretvalue) == "function" and issecretvalue(s.texture) or false
  local lines = {
    ("last cast: %s   texture=%s (%s%s)   casting=%s channel=%s"):format(tostring(s.name), tostring(s.texture), type(s.texture), secret and ", SECRET" or "", tostring(s.casting), tostring(s.channel)),
  }
  if b and b.icon then
    lines[#lines + 1] = ("icon: shown=%s size=%sx%s texture now=%s"):format(tostring(b.icon:IsShown()), tostring(b.icon:GetWidth()), tostring(b.icon:GetHeight()), tostring(b.icon.GetTexture and b.icon:GetTexture()))
  end
  return lines
end

HH:RegisterSlash("castdiag", function()
  for _, l in ipairs(Castbar.Diagnose()) do HH:Print(l) end
end, "print what the HUD cast bar was given for the last cast")
