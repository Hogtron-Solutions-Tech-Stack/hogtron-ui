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

--- Where the fill stands for progress p (0..1). With the icon inside the bar the fill starts at the icon's right edge,
-- so no progress hides under it: p = 0 reaches the icon's edge, p = 1 the bar's end. The theme art and the spark follow
-- the same number. Without an inside icon: p itself.
function Castbar.Fill(b, p)
  local c = cfg()
  if c.iconInside == false or c.icon == false or not b or not b.icon then return p end
  local w = b.GetWidth and b:GetWidth()
  local iw = b.icon.GetWidth and b.icon:GetWidth()
  if type(w) ~= "number" or type(iw) ~= "number" or w <= 0 or iw <= 0 or iw >= w then return p end
  local inset = iw / w
  return inset + (1 - inset) * p
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
  state.aura = nil                                          -- a real cast replaces the eating / drinking bar
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
    -- a spell with its own OpenArt strip: that strip, its school's colours (2026-10-17 pilot)
    local spellArt, spellTheme
    if not forceTheme and T.SpellArt then spellArt, spellTheme = T.SpellArt(name) end
    if spellArt and not key then key, why = spellTheme, "spell art" end
    state.theme, state.themeWhy, state.spellID, state.spellArt = key, why, spellID, spellArt
    if state.notInterruptible then T.Clear(b) else T.Apply(b, key, state.startTime, spellArt) end
    Castbar.NoteArt(name, key, why, spellArt)
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
  b:SetValue(Castbar.Fill(b, channel and 1 or 0))
  b:Show()
  b:SetScript("OnUpdate", function(self) Castbar.OnUpdate(self) end)
  Castbar.OnUpdate(b)
end

--- What the last cast drew, saved (diag.castArt) so a /reload tells which strip the client really loaded.
function Castbar.NoteArt(name, key, why, spellArt)
  local g = HH.db and HH.db.global
  local T = HHD.CastThemes
  if not g or not T then return end
  g.diag = g.diag or {}
  local a = T.active or {}
  g.diag.castArt = { at = date and date("%Y-%m-%d %H:%M:%S") or "?", name = (type(name) == "string" and not HH.IsSecret(name)) and name or "?",
    theme = tostring(key), why = tostring(why), wanted = spellArt or "school", drew = a.art or "none", mode = a.mode or "-",
    missing = T.MissingText() }
end

local function finish(state)
  local b = bar()
  state.casting, state.channel, state.aura = false, false, nil
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
  local p = Castbar.Fill(b, Castbar.Progress(state, now))
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
  local state = Castbar.state
  if state.casting and not state.channel and not state.aura then finish(state) Castbar.CheckRefresh() end
end

function handlers.UNIT_SPELLCAST_CHANNEL_STOP()
  if Castbar.state.channel then finish(Castbar.state) Castbar.CheckRefresh() end
end

local function failed(label)
  local state = Castbar.state
  if not state.casting or state.aura then return end        -- a refused cast while eating is not the food failing
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

-- ---------------------------------------------------------------- eating and drinking (Sean 2026-10-18)
-- "I want to make drinking and eat cast bars": on Classic-rules clients food and drink are no cast at all but a buff
-- you sit with ("Food", "Drink", "Food & Drink"). While one is on the player the bar shows it as a cast filling up over
-- the buff's duration, in its own strip (the Food / Drink rows of CastThemes.SPELL_ART). Plain values only: a secret
-- name or time shows nothing, and diag.refreshBar records what the client handed over. A real cast always wins;
-- standing up (the buff ends) clears the bar.
Castbar.REFRESH = { ["Food"] = "food", ["Drink"] = "drink", ["Food & Drink"] = "both" }

local function plainStr(v) if type(v) == "string" and not HH.IsSecret(v) then return v end end
local function plainNum(v) if type(v) == "number" and not HH.IsSecret(v) then return v end end

--- One helpful aura on the player through whichever reader this client has: name, icon, duration, expires, spell id,
-- reader name. Nothing past the last aura.
function Castbar.PlayerBuff(i)
  local C = rawget(_G, "C_UnitAuras")
  if type(C) == "table" and type(C.GetAuraDataByIndex) == "function" then
    local ok, a = pcall(C.GetAuraDataByIndex, "player", i, "HELPFUL")
    if not ok or type(a) ~= "table" then return nil end
    return a.name, a.icon, a.duration, a.expirationTime, a.spellId, "C_UnitAuras"
  end
  local UA = rawget(_G, "UnitAura")
  if type(UA) ~= "function" then return nil end
  local ok, name, icon, _, _, duration, expires, _, _, _, spellID = pcall(UA, "player", i, "HELPFUL")
  if not ok or type(name) == "nil" then return nil end
  return name, icon, duration, expires, spellID, "UnitAura"
end

--- The eating / drinking buff on the player now: { label, name, icon, startTime, endTime, spellID, reader } or nil,
-- and why. Eating and drinking at once is one bar, "Food & Drink", running to the later of the two.
function Castbar.ReadRefresh()
  local found, why, kinds = nil, "none", {}
  for i = 1, 40 do
    local name, icon, duration, expires, spellID, reader = Castbar.PlayerBuff(i)
    if not reader then break end
    local n = plainStr(name)
    local kind = n and Castbar.REFRESH[n]
    if kind then
      local dur, exp = plainNum(duration), plainNum(expires)
      if not (dur and exp) then
        why = "times hidden or missing (" .. reader .. ")"
      elseif dur > 0 then
        kinds[kind] = true
        if not found or exp > found.endTime then
          found = { name = n, icon = icon, startTime = exp - dur, endTime = exp, spellID = plainNum(spellID), reader = reader }
        end
      end
    end
  end
  if not found then return nil, why end
  found.label = (kinds.both or (kinds.food and kinds.drink)) and "Food & Drink" or found.name
  return found, "shown"
end

--- What the last eating / drinking check saw (only when a food or drink buff was there), for /hh castdiag.
function Castbar.NoteRefresh(r, why)
  if not r and why == "none" then return end
  local g = HH.db and HH.db.global
  if not g then return end
  g.diag = g.diag or {}
  g.diag.refreshBar = { at = date and date("%Y-%m-%d %H:%M:%S") or "?", why = why, label = r and r.label or "-",
    reader = r and r.reader or "-", duration = r and (r.endTime - r.startTime) or 0 }
end

--- Show, move or clear the eating / drinking bar (UNIT_AURA on the player, and after a real cast ends).
function Castbar.CheckRefresh()
  local state = Castbar.state
  if cfg().refresh == false then
    if state.aura then finish(state) end
    return
  end
  if state.casting and not state.aura then return end                -- a real cast (or a preview) wins
  if not state.aura and InCombatLockdown and InCombatLockdown() then return end   -- nobody sits down to eat mid-fight
  local r, why = Castbar.ReadRefresh()
  Castbar.NoteRefresh(r, why)
  if not r then
    if state.aura then finish(state) end
    return
  end
  local cur = state.aura
  if cur and cur.endTime == r.endTime and cur.label == r.label then return end   -- the same buff: keep going
  begin(state, r.label, r.icon, r.startTime * 1000, r.endTime * 1000, false, false, r.spellID, nil)
  state.aura = r
  local b = bar()
  b.text:SetText(r.label)                                            -- no "» target": you are sitting down
  b.latency:Hide()
end

handlers.UNIT_AURA = function() Castbar.CheckRefresh() end

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
  if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, "UNIT_AURA", "player") else pcall(f.RegisterEvent, f, "UNIT_AURA") end
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
  local rb = HH.db and HH.db.global and HH.db.global.diag and HH.db.global.diag.refreshBar
  lines[#lines + 1] = rb and ("eating / drinking (last seen %s): %s - %s, %ss, reader %s"):format(tostring(rb.at), tostring(rb.label),
    tostring(rb.why), tostring(rb.duration), tostring(rb.reader)) or "eating / drinking: no food or drink buff seen yet"
  if b and b.icon then
    lines[#lines + 1] = ("icon: shown=%s size=%sx%s texture now=%s"):format(tostring(b.icon:IsShown()), tostring(b.icon:GetWidth()), tostring(b.icon:GetHeight()), tostring(b.icon.GetTexture and b.icon:GetTexture()))
  end
  return lines
end

--- The icon a preview cast shows (Sean 2026-10-14 in game: the preview showed a question mark). Your own spell's
-- icon when you know the sample spell (the client answers by name), else the theme's usual icon; never the
-- question mark.
Castbar.PREVIEW_ICONS = {
  holy = "Interface\\Icons\\Spell_Holy_FlashHeal", fire = "Interface\\Icons\\Spell_Fire_FlameBolt", frost = "Interface\\Icons\\Spell_Frost_FrostBolt02", arcane = "Interface\\Icons\\Spell_Nature_StarFall",
  shadow = "Interface\\Icons\\Spell_Shadow_SiphonMana", nature = "Interface\\Icons\\Spell_Nature_Lightning", earth = "Interface\\Icons\\Trade_Mining", herb = "Interface\\Icons\\Trade_Herbalism",
  leather = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", water = "Interface\\Icons\\Trade_Fishing", gold = "Interface\\Icons\\INV_Box_01", craft = "Interface\\Icons\\INV_Misc_Bandage_15",
  aim = "Interface\\Icons\\INV_Spear_07",
}
function Castbar.PreviewIcon(name, key)
  local C = rawget(_G, "C_Spell")
  local get = type(C) == "table" and C.GetSpellTexture or rawget(_G, "GetSpellTexture")
  if type(get) == "function" then
    local ok, tex = pcall(get, name)
    local secret = type(issecretvalue) == "function" and issecretvalue(tex)
    if ok and tex ~= nil and not secret and tex ~= "" then return tex end
  end
  return Castbar.PREVIEW_ICONS[key] or Castbar.GENERIC_ICON
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
    begin(Castbar.state, samples[key] .. "  (preview)", Castbar.PreviewIcon(samples[key], key), now * 1000, (now + 1.9) * 1000,
      false, key == "water", nil, nil, key)
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
