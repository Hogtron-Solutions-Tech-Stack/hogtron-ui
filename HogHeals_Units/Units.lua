-- HogUI unit frames: player, target, target-of-target, pet, focus.
--
-- Same panel language as the rest of HogUI (ink body, 1 px outline, flat bars): a class / reaction coloured health
-- bar, a thin power bar under it, name and level on top, health and power text on the right. Blizzard's own frames
-- are hidden while ours are on (ours on = theirs off; they come back with a /reload after the option is turned off).
--
-- Secure: each frame is a SecureUnitButton (left click targets, right click opens the unit menu) and target / pet /
-- focus / target-of-target show and hide through RegisterUnitWatch, so combat never blocks them. Everything the
-- client may hide behind a SECRET value (health, power, level in combat...) is fed straight to a widget or through
-- format / AbbreviateNumbers, never through our own arithmetic or a boolean test.
--
-- Lessons already paid for on this client (2026-09-22): set the bar texture BEFORE anything anchors to the fill
-- (a bar built the other way round collapsed to 0x0); a unit's class can be unreadable in combat, so remember it.
HogHealsUnits = HogHealsUnits or {}
local HHU = HogHealsUnits
local HH = HogHeals

local Units = { frames = {}, order = { "player", "target", "targettarget", "pet", "focus" } }
HHU.Units = Units

local FLAT = "Interface\\Buttons\\WHITE8X8"
local CREAM = { 0.96, 0.92, 0.86 }
local CYAN = { 0.13, 0.83, 0.88 }
local INK = { 0.07, 0.07, 0.09 }
local GREY = { 0.55, 0.55, 0.60 }
local LINE = { 0.20, 0.20, 0.25 }
local RED = { 0.85, 0.20, 0.20 }

Units.LABEL = { player = "Player", target = "Target", targettarget = "Target of target", pet = "Pet", focus = "Focus" }
Units.GLOBAL_NAME = { player = "HogUIPlayer", target = "HogUITarget", targettarget = "HogUITargetOfTarget", pet = "HogUIPet", focus = "HogUIFocus" }

local POWER_FALLBACK = {
  MANA = { 0.00, 0.55, 1.00 }, RAGE = { 1.00, 0.10, 0.10 }, FOCUS = { 1.00, 0.50, 0.25 }, ENERGY = { 1.00, 1.00, 0.00 },
  RUNIC_POWER = { 0.00, 0.82, 1.00 }, COMBO_POINTS = { 1.00, 0.96, 0.41 },
}

local function cfg() return HH.db.profile.units end
local function ucfg(unit) return HH.db.profile.units[unit] end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function str(v) if type(v) == "string" and not isSecret(v) then return v end end
local function bool(v) if isSecret(v) then return nil end return v and true or false end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(f, ...)
  if ok then return a, b, c, d end
end

local function media(kind, name, fallback)
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  local p = LSM and call(LSM.Fetch, LSM, kind, name)
  return p or fallback
end
local function fontPath() return media("font", cfg().font or "Friz Quadrata TT", STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF") end
local function barTexture() return media("statusbar", cfg().texture or "Solid", FLAT) end

-- ------------------------------------------------------------------------------------------------ class memory
Units.classByGUID, Units.classByName = {}, {}

--- Class token, remembered while the client hides it (identity can be secret in combat).
function Units.ClassOf(unit)
  local _, class = call(UnitClass, unit)
  class = str(class)
  local guid, name = str(call(UnitGUID, unit)), str(call(UnitName, unit))
  if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
    if guid then Units.classByGUID[guid] = class end
    if name then Units.classByName[name] = class end
    return class
  end
  return (guid and Units.classByGUID[guid]) or (name and Units.classByName[name]) or nil
end

-- ------------------------------------------------------------------------------------------------ colours
function Units.HealthColor(unit)
  local d = cfg()
  if d.classColors ~= false and bool(call(UnitIsPlayer, unit)) then
    local class = Units.ClassOf(unit)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
  end
  if bool(call(UnitIsTapDenied, unit)) then return 0.5, 0.5, 0.5 end
  if d.reactionColors ~= false and unit ~= "player" then
    local r = num(call(UnitReaction, unit, "player"))
    if r then
      if r <= 2 then return 0.85, 0.20, 0.20
      elseif r == 3 then return 0.90, 0.45, 0.10
      elseif r == 4 then return 0.95, 0.80, 0.20 end
      return 0.25, 0.80, 0.35
    end
  end
  local c = d.healthColor or { 0.25, 0.80, 0.35 }
  return c[1], c[2], c[3]
end

function Units.PowerColor(unit)
  local _, token = call(UnitPowerType, unit)
  token = str(token) or "MANA"
  local pbc = rawget(_G, "PowerBarColor")
  local c = type(pbc) == "table" and pbc[token]
  if type(c) == "table" and c.r then return c.r, c.g, c.b end
  local f = POWER_FALLBACK[token] or POWER_FALLBACK.MANA
  return f[1], f[2], f[3]
end

-- ------------------------------------------------------------------------------------------------ text
local function abbreviate(v)
  if v == nil then return "" end
  local s = call(AbbreviateNumbers, v)
  if s ~= nil then return tostring(s) end
  local n = num(v)
  if n then
    if n >= 1e6 then return ("%.1fm"):format(n / 1e6) elseif n >= 1e3 then return ("%.1fk"):format(n / 1e3) end
    return ("%d"):format(n)
  end
  return tostring(v)
end

local function percentText(unit, hp, max)
  if type(UnitHealthPercent) == "function" then
    local curve = type(CurveConstants) == "table" and CurveConstants.ScaleTo100 or nil
    local v = call(UnitHealthPercent, unit, true, curve)
    if v ~= nil then
      if curve then return string.format("%.0f%%", v) end
      local n = num(v)
      if n then return string.format("%.0f%%", n * 100) end
    end
  end
  local h, m = num(hp), num(max)
  if h and m and m > 0 then return string.format("%.0f%%", h / m * 100) end
  return nil
end

--- Health text without arithmetic on a value that may be secret. mode: percent | current | current-max |
-- current-percent | none. State words (Dead / Ghost / Offline) win.
function Units.HealthText(unit, mode)
  if mode == "none" then return "" end
  if bool(call(UnitIsGhost, unit)) then return "Ghost" end
  if bool(call(UnitIsDead, unit)) then return "Dead" end
  if bool(call(UnitIsConnected, unit)) == false then return "Offline" end
  local hp, max = call(UnitHealth, unit), call(UnitHealthMax, unit)
  if hp == nil then return "" end
  local pct = percentText(unit, hp, max)
  if mode == "percent" then return pct or abbreviate(hp)
  elseif mode == "current" then return abbreviate(hp)
  elseif mode == "current-max" then return abbreviate(hp) .. " / " .. abbreviate(max)
  elseif mode == "current-percent" then return abbreviate(hp) .. (pct and ("  " .. pct) or "") end
  return abbreviate(hp)
end

function Units.PowerText(unit, mode)
  if mode == "none" then return "" end
  local p, max = call(UnitPower, unit), call(UnitPowerMax, unit)
  if p == nil then return "" end
  local m = num(max)
  if m and m <= 0 then return "" end
  if tostring(max) == "0" or tostring(p) == "0" and tostring(max) == "0" then return "" end
  if mode == "current" then return abbreviate(p) end
  return abbreviate(p) .. " / " .. abbreviate(max)
end

function Units.LevelText(unit)
  local lvl = call(UnitLevel, unit)
  if lvl == nil then return "" end
  local n = num(lvl)
  local text = (n and n < 0) and "??" or tostring(lvl)
  local class = str(call(UnitClassification, unit))
  if class == "elite" then text = text .. "+"
  elseif class == "rareelite" then text = text .. "R+"
  elseif class == "rare" then text = text .. "R"
  elseif class == "worldboss" then text = "Boss" end
  return text, n
end

-- ------------------------------------------------------------------------------------------------ frame build
local function solid(parent, layer, c, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  return t
end

local function text(parent, c, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetTextColor(c[1], c[2], c[3])
  if justify then fs:SetJustifyH(justify) end
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end

local function setFont(fs, size, outline)
  if fs and fs.SetFont then call(fs.SetFont, fs, fontPath(), size, outline or "OUTLINE") end
end

local function outline(parent, anchor)
  local edges = {}
  local spec = { { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }
  for i, sp in ipairs(spec) do
    local e = solid(parent, "BORDER", LINE)
    e:SetPoint(sp[1], anchor, sp[1], 0, 0)
    e:SetPoint(sp[2], anchor, sp[2], 0, 0)
    if sp[3] then e:SetWidth(sp[3]) end
    if sp[4] then e:SetHeight(sp[4]) end
    edges[i] = e
  end
  return edges
end

local function savePosition(f)
  local point, _, _, x, y = f:GetPoint(1)
  if point then
    local d = ucfg(f.unit)
    d.point, d.x, d.y = point, x, y
  end
end

function Units.Build(unit)
  if Units.frames[unit] then return Units.frames[unit] end
  local d = ucfg(unit)
  local f = CreateFrame("Button", Units.GLOBAL_NAME[unit], UIParent, "SecureUnitButtonTemplate")
  f.unit = unit
  f:SetAttribute("unit", unit)
  f:SetAttribute("*type1", "target")
  f:SetAttribute("*type2", "togglemenu")
  if f.RegisterForClicks then f:RegisterForClicks("AnyUp") end   -- like Blizzard's unit frames; down+up would fire twice
  f:SetSize(d.width or 240, d.height or 42)
  f:SetPoint(d.point or "BOTTOM", UIParent, d.point or "BOTTOM", d.x or 0, d.y or 230)
  f:SetFrameStrata("MEDIUM")
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f.bg = solid(f, "BACKGROUND", INK, 0.6)
  f.bg:SetAllPoints(f)
  f.edges = outline(f, f)

  -- health: texture FIRST (see header), then anchors
  f.health = CreateFrame("StatusBar", nil, f)
  f.health:SetStatusBarTexture(barTexture())
  f.health:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  f.health:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, (d.powerHeight or 8) + 2)
  f.health:SetMinMaxValues(0, 1)
  f.health:SetValue(1)
  f.health:SetFrameLevel(f:GetFrameLevel() + 1)
  f.health.bg = solid(f.health, "BACKGROUND", { 0.13, 0.13, 0.16 }, 0.9)
  f.health.bg:SetAllPoints(f.health)

  f.power = CreateFrame("StatusBar", nil, f)
  f.power:SetStatusBarTexture(barTexture())
  f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -1)
  f.power:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  f.power:SetMinMaxValues(0, 1)
  f.power:SetValue(1)
  f.power:SetFrameLevel(f:GetFrameLevel() + 1)
  f.power.bg = solid(f.power, "BACKGROUND", { 0.13, 0.13, 0.16 }, 0.9)
  f.power.bg:SetAllPoints(f.power)

  -- text lives on an overlay above both bars
  f.overlay = CreateFrame("Frame", nil, f)
  f.overlay:SetAllPoints(f)
  f.overlay:SetFrameLevel(f:GetFrameLevel() + 5)
  f.name = text(f.overlay, CREAM, "LEFT")
  f.name:SetPoint("TOPLEFT", f.health, "TOPLEFT", 5, -3)
  f.level = text(f.overlay, CREAM, "RIGHT")
  f.level:SetPoint("TOPRIGHT", f.health, "TOPRIGHT", -5, -3)
  f.name:SetPoint("RIGHT", f.level, "LEFT", -4, 0)
  f.healthText = text(f.overlay, CREAM, "RIGHT")
  f.healthText:SetPoint("BOTTOMRIGHT", f.health, "BOTTOMRIGHT", -5, 3)
  f.powerText = text(f.overlay, CREAM, "RIGHT")
  f.powerText:SetPoint("RIGHT", f.power, "RIGHT", -4, 0)
  f.status = text(f.overlay, CYAN, "LEFT")          -- player: "zz" resting (cyan) / "+" combat (red)
  f.status:SetPoint("BOTTOMLEFT", f.health, "BOTTOMLEFT", 5, 3)
  f.raidIcon = f.overlay:CreateTexture(nil, "OVERLAY")
  f.raidIcon:SetSize(16, 16)
  f.raidIcon:SetPoint("CENTER", f, "TOP", 0, 0)
  f.raidIcon:Hide()

  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self)
    if HH.db.profile.locked then return end   -- one switch for everything: /hh unlock
    if InCombatLockdown and InCombatLockdown() then return end
    self:StartMoving()
  end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePosition(self) end)
  f:SetScript("OnEnter", function(self)
    if not GameTooltip or not cfg().tooltips then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    call(GameTooltip.SetUnit, GameTooltip, self.unit)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  if unit ~= "player" and type(RegisterUnitWatch) == "function" then call(RegisterUnitWatch, f) end
  Units.frames[unit] = f
  Units.ApplyLook(f)
  return f
end

--- Size, font, texture, anchor from the profile (out of combat: secure frames may not be resized in combat).
function Units.ApplyLook(f)
  local d, g = ucfg(f.unit), cfg()
  HH:RunOutOfCombat(function()
    f:SetSize(d.width or 240, d.height or 42)
    f:ClearAllPoints()
    f:SetPoint(d.point or "BOTTOM", UIParent, d.point or "BOTTOM", d.x or 0, d.y or 230)
    if d.enabled == false then
      if f.unit ~= "player" then call(UnregisterUnitWatch, f) end
      f:Hide()
    elseif f.unit == "player" then
      f:Show()
    elseif type(RegisterUnitWatch) == "function" then
      call(RegisterUnitWatch, f)
    end
  end)
  local ph = d.powerHeight or 8
  f.health:ClearAllPoints()
  f.health:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  f.health:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, (d.showPower ~= false and ph or 0) + 2)
  if d.showPower == false then f.power:Hide() else f.power:Show() end
  f.health:SetStatusBarTexture(barTexture())
  f.power:SetStatusBarTexture(barTexture())
  f.bg:SetColorTexture(INK[1], INK[2], INK[3], g.backgroundAlpha or 0.6)
  local size = d.fontSize or g.fontSize or 12
  setFont(f.name, size)
  setFont(f.level, size)
  setFont(f.healthText, size)
  setFont(f.powerText, math.max(7, size - 3))
  setFont(f.status, size)
  Units.LayoutText(f)
  if HHU.Auras and HHU.Auras.Layout then HHU.Auras.Layout(f) end
  if Units.PlaceCastbar then Units.PlaceCastbar(f) end
end

--- Text placement. Full frames: name top-left, level top-right, health text bottom-right, power text on the
-- power bar. Frames under COMPACT_HEIGHT (target-of-target, pet): one row - name left, health text right, no
-- level, no power text. In game 2026-09-23 the 28 px ToT frame had all four fighting for two rows.
Units.COMPACT_HEIGHT = 34
function Units.LayoutText(f)
  local d = ucfg(f.unit)
  local compact = (d.height or 42) < Units.COMPACT_HEIGHT
  f.compact = compact
  f.name:ClearAllPoints()
  f.level:ClearAllPoints()
  f.healthText:ClearAllPoints()
  if compact then
    f.healthText:SetPoint("RIGHT", f.health, "RIGHT", -4, 0)
    f.name:SetPoint("LEFT", f.health, "LEFT", 4, 0)
    f.name:SetPoint("RIGHT", f.healthText, "LEFT", -4, 0)
    f.level:SetPoint("TOPRIGHT", f.health, "TOPRIGHT", -4, -2)
    f.level:Hide()
    f.powerText:Hide()
    f.status:Hide()
  else
    f.level:SetPoint("TOPRIGHT", f.health, "TOPRIGHT", -5, -3)
    f.name:SetPoint("TOPLEFT", f.health, "TOPLEFT", 5, -3)
    f.name:SetPoint("RIGHT", f.level, "LEFT", -4, 0)
    f.healthText:SetPoint("BOTTOMRIGHT", f.health, "BOTTOMRIGHT", -5, 3)
    if d.showLevel ~= false then f.level:Show() end
    f.powerText:Show()
    f.status:Show()
  end
end

-- ------------------------------------------------------------------------------------------------ updates
function Units.UpdateHealth(f)
  local unit = f.unit
  local hp, max = call(UnitHealth, unit), call(UnitHealthMax, unit)
  if max == nil then return end
  local m = num(max)
  if m and m <= 0 then max = 1 end
  f.health:SetMinMaxValues(0, max)
  f.health:SetValue(hp or 0)
  f.health:SetStatusBarColor(Units.HealthColor(unit))
  f.healthText:SetText(Units.HealthText(unit, cfg().healthText or "current-percent"))
end

function Units.UpdatePower(f)
  local unit = f.unit
  if ucfg(unit).showPower == false then return end
  local p, max = call(UnitPower, unit), call(UnitPowerMax, unit)
  if max == nil then return end
  local m = num(max)
  if m and m <= 0 then f.power:SetMinMaxValues(0, 1) f.power:SetValue(0) f.powerText:SetText("") return end
  f.power:SetMinMaxValues(0, max)
  f.power:SetValue(p or 0)
  f.power:SetStatusBarColor(Units.PowerColor(unit))
  f.powerText:SetText(Units.PowerText(unit, cfg().powerText or "current-max"))
end

function Units.UpdateInfo(f)
  local unit, d = f.unit, ucfg(f.unit)
  local name = str(call(UnitName, unit)) or (call(UnitName, unit) ~= nil and "?" or "")
  f.name:SetText(d.showName ~= false and name or "")
  if d.showLevel ~= false then
    local lvl, n = Units.LevelText(unit)
    f.level:SetText(lvl)
    local c = n and type(GetQuestDifficultyColor) == "function" and call(GetQuestDifficultyColor, n)
    if type(c) == "table" and c.r then f.level:SetTextColor(c.r, c.g, c.b) else f.level:SetTextColor(CREAM[1], CREAM[2], CREAM[3]) end
  else
    f.level:SetText("")
  end
  -- raid target icon
  local idx = num(call(GetRaidTargetIndex, unit))
  if idx and idx > 0 and type(SetRaidTargetIconTexture) == "function" then
    f.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    call(SetRaidTargetIconTexture, f.raidIcon, idx)
    f.raidIcon:Show()
  else
    f.raidIcon:Hide()
  end
end

function Units.UpdateStatus(f)
  if f.unit ~= "player" then f.status:SetText("") return end
  if bool(call(UnitAffectingCombat, "player")) or (InCombatLockdown and InCombatLockdown()) then
    f.status:SetText("+")
    f.status:SetTextColor(RED[1], RED[2], RED[3])
  elseif bool(call(IsResting)) then
    f.status:SetText("zz")
    f.status:SetTextColor(CYAN[1], CYAN[2], CYAN[3])
  else
    f.status:SetText("")
  end
end

function Units.UpdateAll(f)
  if ucfg(f.unit).enabled == false then return end
  Units.UpdateHealth(f)
  Units.UpdatePower(f)
  Units.UpdateInfo(f)
  Units.UpdateStatus(f)
  if HHU.Auras and HHU.Auras.Update then HHU.Auras.Update(f) end
end

function Units.ForEach(fn)
  for _, unit in ipairs(Units.order) do
    local f = Units.frames[unit]
    if f then fn(f) end
  end
end

-- ------------------------------------------------------------------------------------------------ Blizzard's frames
local hiddenParent
local function banish(f)
  if type(f) ~= "table" then return false end
  hiddenParent = hiddenParent or _G.HogHealsHiddenParent
  if not hiddenParent then
    hiddenParent = CreateFrame("Frame", "HogHealsHiddenParent", UIParent)
    hiddenParent:Hide()
  end
  if f.UnregisterAllEvents then call(f.UnregisterAllEvents, f) end
  call(f.Hide, f)
  call(f.SetParent, f, hiddenParent)
  if not f.hhBanishHooked and type(hooksecurefunc) == "function" then
    f.hhBanishHooked = true
    pcall(hooksecurefunc, f, "Show", function(self)
      if cfg().enabled == false or cfg().hideBlizzard == false then return end
      call(self.Hide, self)
    end)
  end
  return true
end

Units.BLIZZARD = {
  player = { "PlayerFrame" }, target = { "TargetFrame" }, targettarget = { "TargetFrameToT" }, pet = { "PetFrame" }, focus = { "FocusFrame", "FocusFrameToT" },
}

--- Blizzard's target / focus cast bars are children of the frames we hide: adopt them first (they read cast timings
-- the client may keep secret, so re-using them beats rebuilding them).
Units.SPELLBAR = { target = "TargetFrameSpellBar", focus = "FocusFrameSpellBar" }

function Units.AdoptCastbar(f)
  local name = Units.SPELLBAR[f.unit]
  local sb = name and rawget(_G, name)
  if not sb or f.castbar then return f.castbar end
  call(sb.SetParent, sb, f)
  f.castbar = sb
  if sb.SetStatusBarTexture then call(sb.SetStatusBarTexture, sb, FLAT) end
  for _, k in ipairs({ "Border", "BorderShield", "Flash", "Background", "TextBorder" }) do
    local r = rawget(sb, k) or rawget(_G, name .. k)
    if type(r) == "table" and r.SetAlpha then call(r.SetAlpha, r, 0) end
  end
  if not sb.hhBg then
    sb.hhBg = solid(sb, "BACKGROUND", INK, 0.85)
    sb.hhBg:SetPoint("TOPLEFT", sb, "TOPLEFT", -1, 1)
    sb.hhBg:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 1, -1)
    sb.hhEdges = outline(sb, sb.hhBg)
  end
  -- Blizzard re-anchors its spell bar on every cast; put it back under ours each time
  if not sb.hhAnchorHooked and type(hooksecurefunc) == "function" and sb.SetPoint then
    sb.hhAnchorHooked = true
    pcall(hooksecurefunc, sb, "SetPoint", function(self)
      if self.hhPlacing then return end
      Units.PlaceCastbar(f)
    end)
  end
  Units.PlaceCastbar(f)
  return sb
end

function Units.PlaceCastbar(f)
  local sb = f.castbar
  if not sb then return end
  local d = ucfg(f.unit)
  if d.castbar == false then call(sb.Hide, sb) return end
  sb.hhPlacing = true
  call(sb.ClearAllPoints, sb)
  call(sb.SetPoint, sb, "BOTTOMLEFT", f, "TOPLEFT", 0, 6)
  call(sb.SetPoint, sb, "BOTTOMRIGHT", f, "TOPRIGHT", 0, 6)
  call(sb.SetHeight, sb, d.castbarHeight or 16)
  sb.hhPlacing = false
end

function Units.HideBlizzard()
  if cfg().enabled == false or cfg().hideBlizzard == false then return end
  HH:RunOutOfCombat(function()
    Units.ForEach(Units.AdoptCastbar)
    for _, names in pairs(Units.BLIZZARD) do
      for _, n in ipairs(names) do banish(rawget(_G, n)) end
    end
  end)
end

-- ------------------------------------------------------------------------------------------------ events
local UNIT_EVENTS = {
  UNIT_HEALTH = "health", UNIT_MAXHEALTH = "health", UNIT_HEAL_PREDICTION = "health",
  UNIT_POWER_UPDATE = "power", UNIT_MAXPOWER = "power", UNIT_DISPLAYPOWER = "power", UNIT_POWER_FREQUENT = "power",
  UNIT_NAME_UPDATE = "info", UNIT_LEVEL = "info", UNIT_FACTION = "info", UNIT_CLASSIFICATION_CHANGED = "info", UNIT_FLAGS = "health",
  UNIT_CONNECTION = "health", UNIT_AURA = "auras",
}
local OTHER_EVENTS = { "PLAYER_TARGET_CHANGED", "UNIT_TARGET", "UNIT_PET", "PLAYER_FOCUS_CHANGED", "PLAYER_ENTERING_WORLD",
  "RAID_TARGET_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING", "GROUP_ROSTER_UPDATE" }

local function refresh(unit)
  local f = Units.frames[unit]
  if f and ucfg(unit).enabled ~= false then Units.UpdateAll(f) end
end

function Units.OnEvent(_, e, arg1)
  local kind = UNIT_EVENTS[e]
  if kind then
    local f = type(arg1) == "string" and Units.frames[arg1]
    if not f or ucfg(arg1).enabled == false then return end
    if kind == "health" then Units.UpdateHealth(f)
    elseif kind == "power" then Units.UpdatePower(f)
    elseif kind == "info" then Units.UpdateInfo(f) Units.UpdateHealth(f)
    elseif kind == "auras" and HHU.Auras then HHU.Auras.Update(f) end
    return
  end
  if e == "PLAYER_TARGET_CHANGED" then refresh("target") refresh("targettarget")
  elseif e == "UNIT_TARGET" then if arg1 == "target" then refresh("targettarget") end
  elseif e == "UNIT_PET" then if arg1 == "player" then refresh("pet") end
  elseif e == "PLAYER_FOCUS_CHANGED" then refresh("focus")
  elseif e == "RAID_TARGET_UPDATE" then Units.ForEach(Units.UpdateInfo)
  elseif e == "PLAYER_REGEN_DISABLED" or e == "PLAYER_REGEN_ENABLED" or e == "PLAYER_UPDATE_RESTING" then
    local p = Units.frames.player
    if p then Units.UpdateStatus(p) end
  elseif e == "PLAYER_ENTERING_WORLD" or e == "GROUP_ROSTER_UPDATE" then
    Units.HideBlizzard()
    Units.ForEach(Units.UpdateAll)
  end
end

-- ------------------------------------------------------------------------------------------------ lifecycle
local Module = {}
HHU.module = Module

function Module:OnEnable()
  if cfg().enabled == false then return end
  for _, unit in ipairs(Units.order) do Units.Build(unit) end
  Units.HideBlizzard()
  local ev = CreateFrame("Frame")
  Module.unknown = {}
  for e in pairs(UNIT_EVENTS) do if not pcall(ev.RegisterEvent, ev, e) then Module.unknown[#Module.unknown + 1] = e end end
  for _, e in ipairs(OTHER_EVENTS) do if not pcall(ev.RegisterEvent, ev, e) then Module.unknown[#Module.unknown + 1] = e end end
  ev:SetScript("OnEvent", function(self, e, ...)
    local ok, err = xpcall(Units.OnEvent, HH.Trace, self, e, ...)
    if not ok and err ~= Units.lastError then Units.lastError = err HH:LogError("units " .. tostring(e) .. ": " .. tostring(err)) end
  end)
  Module.events = ev
  -- target-of-target gets no unit events of its own: poll it while it is shown
  if C_Timer and C_Timer.NewTicker then
    Module.ticker = C_Timer.NewTicker(0.5, function()
      local f = Units.frames.targettarget
      if f and f:IsShown() and ucfg("targettarget").enabled ~= false then
        local ok, err = xpcall(Units.UpdateAll, HH.Trace, f)
        if not ok and err ~= Units.lastError then Units.lastError = err HH:LogError("units tot: " .. tostring(err)) end
      end
    end)
  end
  Units.ForEach(Units.UpdateAll)
end

function Module:OnProfileChanged() Units.Refresh() end

--- /hh unlock: every frame force-shown with a "drag: <unit>" label, unit watch paused (a target frame with no
-- target would otherwise be invisible and undraggable); /hh lock restores the watch and hides the labels.
function Module:SetLocked(locked)
  Units.ForEach(function(f)
    if not f.dragHint then
      f.dragHint = f.overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      f.dragHint:SetPoint("CENTER", f, "CENTER", 0, 0)
      f.dragHint:SetTextColor(CYAN[1], CYAN[2], CYAN[3])
      f.dragHint:SetText("drag: " .. (Units.LABEL[f.unit] or f.unit):lower())
      setFont(f.dragHint, 12)
      f.dragHint:Hide()
    end
    HH:RunOutOfCombat(function()
      if locked then
        f.dragHint:Hide()
        if f.unit ~= "player" and ucfg(f.unit).enabled ~= false then
          call(RegisterUnitWatch, f)
          if not (call(UnitExists, f.unit)) then f:Hide() end
        end
      else
        f.dragHint:Show()
        if f.unit ~= "player" then call(UnregisterUnitWatch, f) end
        if ucfg(f.unit).enabled ~= false then f:Show() end
      end
    end)
  end)
end

function Units.Refresh()
  if cfg().enabled == false then Units.ForEach(function(f) f:Hide() end) return end
  for _, unit in ipairs(Units.order) do Units.Build(unit) end
  Units.HideBlizzard()
  Units.ForEach(function(f) Units.ApplyLook(f) Units.UpdateAll(f) end)
end

function Module:GetOptions()
  if HHU.Options and HHU.Options.Build then return HHU.Options.Build() end
end

HH:RegisterModule("Units", Module)

HH:RegisterSlash("units", function(arg)
  arg = (arg or ""):lower()
  if arg == "lock" then HH:SetLocked(true)
  elseif arg == "unlock" then HH:SetLocked(false)
  elseif arg == "reset" then
    for _, unit in ipairs(Units.order) do
      local d, def = ucfg(unit), HH.defaults.profile.units[unit]
      d.point, d.x, d.y = def.point, def.x, def.y
    end
    Units.Refresh()
    HH:Print("Unit frame positions reset.")
  else
    HH:Print("/hh units lock | unlock | reset")
  end
end, "unit frames: lock | unlock | reset positions")
