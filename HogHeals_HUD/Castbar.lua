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

--- Internal cast names / placeholder art made presentable (in game 2026-09-23: opening a chest showed
-- "Opening - No Text" with the WoW-logo temp icon). " - No Text" is dropped from any name; "Opening" gets a
-- chest icon; the temp icon (file 136235) becomes a plain gear.
Castbar.TEMP_ICON = 136235
Castbar.OPEN_ICON = "Interface\\Icons\\INV_Box_01"
Castbar.GENERIC_ICON = "Interface\\Icons\\Trade_Engineering"
function Castbar.Pretty(name, texture)
  if type(name) == "string" then
    name = name:gsub("%s*%-%s*No Text$", "")
    if name:match("^Opening") then return "Opening", Castbar.OPEN_ICON end
  end
  if texture == Castbar.TEMP_ICON or texture == "Interface\\Icons\\Temp" then texture = Castbar.GENERIC_ICON end
  return name, texture
end

local function begin(state, name, texture, startMS, endMS, notInterruptible, channel, spellID, isTradeSkill, forceTheme)
  local b = bar()
  name, texture = Castbar.Pretty(name, texture)
  state.casting, state.channel = true, channel and true or false
  if not forceTheme then state.preview = nil end   -- a real cast ends a theme preview (PreviewThemes stops on it)
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
  -- the cast's theme (CastThemes.lua), read off the client; never in place of the can't-interrupt grey
  local T = HHD.CastThemes
  if T then
    local key, why = forceTheme, forceTheme and "preview" or nil
    if not key then
      local _, class = UnitClass("player")
      key, why = T.Resolve(name, spellID, isTradeSkill, class)
    end
    state.theme, state.themeWhy, state.spellID = key, why, spellID
    if state.notInterruptible then T.Clear(b) else T.Apply(b, key, state.startTime) end
  end
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
  if HHD.CastThemes then HHD.CastThemes.Clear(b) end
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
  if HHD.CastThemes then HHD.CastThemes.Tick(b, p, now) end
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
  local name, _, texture, startMS, endMS, isTradeSkill, _, notInterruptible, spellID = UnitCastingInfo("player")
  if not name then return end
  begin(Castbar.state, name, texture, startMS, endMS, notInterruptible, false, spellID, isTradeSkill)
end

function handlers.UNIT_SPELLCAST_DELAYED()
  local name, _, _, startMS, endMS = UnitCastingInfo("player")
  if not name or not Castbar.state.casting then return end
  Castbar.state.startTime, Castbar.state.endTime = startMS / 1000, endMS / 1000
end

function handlers.UNIT_SPELLCAST_CHANNEL_START()
  local name, _, texture, startMS, endMS, isTradeSkill, notInterruptible, spellID = UnitChannelInfo("player")
  if not name then return end
  begin(Castbar.state, name, texture, startMS, endMS, notInterruptible, true, spellID, isTradeSkill)
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
  if HHD.CastThemes then HHD.CastThemes.Clear(b) end
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
  if HHD.CastThemes then lines[#lines + 1] = HHD.CastThemes.Line(s) .. ("   spell id=%s"):format(tostring(s.spellID)) end
  if b and b.icon then
    lines[#lines + 1] = ("icon: shown=%s size=%sx%s texture now=%s"):format(tostring(b.icon:IsShown()), tostring(b.icon:GetWidth()), tostring(b.icon:GetHeight()), tostring(b.icon.GetTexture and b.icon:GetTexture()))
  end
  return lines
end

--- Every theme on the HUD cast bar in turn, 2 s each (options button, /hh casttheme preview). A fake cast: no spell.
function Castbar.PreviewThemes()
  local T = HHD.CastThemes
  if not T then return end
  local samples = { holy = "Flash Heal", fire = "Fireball", frost = "Frostbolt", arcane = "Arcane Missiles", shadow = "Mind Flay",
    nature = "Lightning Bolt", earth = "Mining", herb = "Herb Gathering", leather = "Skinning", water = "Fishing",
    gold = "Opening", craft = "Linen Bandage", aim = "Aimed Shot" }
  local function step(i)
    local key = T.ORDER[i]
    if not key or Castbar.state.casting and not Castbar.state.preview then
      if Castbar.state.preview then finish(Castbar.state) Castbar.state.preview = nil end
      return
    end
    local now = GetTime()
    begin(Castbar.state, samples[key] .. "  (preview)", "Interface\\Icons\\INV_Misc_QuestionMark", now * 1000, (now + 1.9) * 1000, false, key == "water", nil, nil, key)
    Castbar.state.preview = true
    C_Timer.After(2, function() step(i + 1) end)
  end
  step(1)
end

HH:RegisterSlash("casttheme", function(rest)
  local o = HH.db.profile.hud.castbar.themes
  local w = (rest or ""):lower():match("^%s*(%a*)")
  if w == "on" or w == "off" then o.enabled = w == "on" HH:Print("cast bar themes: " .. w) return end
  if w == "preview" then Castbar.PreviewThemes() return end
  HH:Print(HHD.CastThemes.Line(Castbar.state))
  HH:Print("usage: /hh casttheme on|off|preview")
end, "cast bar themes (holy, fire, frost, mining...): on, off, preview")

HH:RegisterSlash("castdiag", function()
  for _, l in ipairs(Castbar.Diagnose()) do HH:Print(l) end
end, "print what the HUD cast bar was given for the last cast")
