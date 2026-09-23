-- HogHeals nameplates: restyle Blizzard's plates, mark quest mobs, highlight the target and aggro.
--
-- We never replace Blizzard's plate (its base frame is protected; replacing it is Plater-sized and the secret-value
-- rules make most of that moot). We decorate plate.UnitFrame, whose structure was MEASURED on the Forever beta
-- (2026-09-18: healthBar, name, HealthBarsContainer, CastBarsContainer, AurasFrame, RaidTargetFrame, ...):
--   look      flat bar texture, dark backing, 1 px outline, name font, health text
--   colours   class colour for enemy players, reaction colour for NPCs, grey when tapped by someone else;
--             Blizzard re-colours the bar on its own updates, so SetStatusBarColor is hooked and our colour re-applied
--   highlight outline colour by priority: aggro on you (red) > your target (cyan) > quest mob (amber);
--             optional fade of every plate that is not your target
--   quest     "!" icon + progress ("3/8") beside quest mobs (QuestMobs.lua)
-- Health on this client can be SECRET in combat: text goes through UnitHealthPercent / format / AbbreviateNumbers,
-- never through our own arithmetic.
HogHealsPlates = HogHealsPlates or {}
local HHP = HogHealsPlates
local HH = HogHeals

local Plates = { active = {}, samples = {} }
HHP.Plates = Plates

local FLAT = "Interface\\Buttons\\WHITE8X8"
local QUEST_ART = "Interface\\AddOns\\HogHeals\\Media\\quest_open"
local LINE = { 0.05, 0.05, 0.06 }

local function cfg() return HH.db.profile.plates end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function bool(v) if isSecret(v) then return nil end return v and true or false end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
end

-- ------------------------------------------------------------------------------------------------ frames
--- Blizzard's UnitFrame for a nameplate unit (nil for forbidden / missing plates).
function Plates.FrameFor(unit)
  if type(C_NamePlate) ~= "table" then return nil, "no C_NamePlate" end
  local plate = call(C_NamePlate.GetNamePlateForUnit, unit)
  if type(plate) ~= "table" then return nil, "GetNamePlateForUnit(" .. tostring(unit) .. ")=" .. type(plate) end
  if plate.IsForbidden and call(plate.IsForbidden, plate) then return nil, "plate forbidden" end
  local uf = plate.UnitFrame
  if type(uf) ~= "table" then return nil, "no plate.UnitFrame" end
  if uf.IsForbidden and call(uf.IsForbidden, uf) then return nil, "UnitFrame forbidden" end
  return uf, plate
end

local function healthBar(uf)
  return uf.healthBar or (type(uf.HealthBarsContainer) == "table" and uf.HealthBarsContainer.healthBar) or nil
end

local function fontPath()
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  local p = LSM and call(LSM.Fetch, LSM, "font", cfg().font or "Friz Quadrata TT")
  return p or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

local function setFont(fs, size)
  if fs and fs.SetFont then call(fs.SetFont, fs, fontPath(), size, "OUTLINE") end
end

--- Add our pieces to a UnitFrame once. Plates are recycled between units, so everything unit-specific lives in
-- Update, not here.
function Plates.Skin(uf)
  if uf.hh then return uf.hh end
  local hh = {}
  uf.hh = hh
  local hb = healthBar(uf)
  hh.bar = hb
  local anchor = hb or uf
  hh.overlay = CreateFrame("Frame", nil, uf)
  hh.overlay:SetAllPoints(anchor)
  hh.overlay:SetFrameLevel(((anchor.GetFrameLevel and anchor:GetFrameLevel()) or 1) + 5)
  hh.edges = {}
  local spec = { { "TOPLEFT", "TOPRIGHT", -1, 1, 1, 1, nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", -1, -1, 1, -1, nil, 1 },
    { "TOPLEFT", "BOTTOMLEFT", -1, 1, -1, -1, 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 1, 1, -1, 1, nil } }
  for i, s in ipairs(spec) do
    local e = hh.overlay:CreateTexture(nil, "OVERLAY")
    e:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)
    e:SetPoint(s[1], anchor, s[1], s[3], s[4])
    e:SetPoint(s[2], anchor, s[2], s[5], s[6])
    if s[7] then e:SetWidth(s[7]) end
    if s[8] then e:SetHeight(s[8]) end
    e:Hide()
    hh.edges[i] = e
  end
  hh.health = hh.overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hh.health:SetPoint("CENTER", anchor, "CENTER", 0, 0)
  -- Quest badge on the LEFT of the bar: the right side belongs to Blizzard's level badge (in-game 2026-09-22 our
  -- icon sat on top of it). Art = HogHeals/Media/quest_open.tga (dev/icons/build_icons.py). If the client refuses
  -- the file (SetTexture returns false), fall back to a drawn amber square + "!" glyph: the GossipFrame icon we used
  -- first never rendered on Forever, so a missing texture must never mean a missing marker.
  hh.questFrame = CreateFrame("Frame", nil, uf)
  hh.questFrame:SetFrameLevel(hh.overlay:GetFrameLevel() + 1)
  hh.questFrame:SetSize(16, 16)
  hh.questFrame:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
  hh.quest = hh.questFrame:CreateTexture(nil, "ARTWORK")
  hh.quest:SetAllPoints(hh.questFrame)
  local okArt = hh.quest:SetTexture(QUEST_ART)
  hh.questDrawn = (okArt == false)
  hh.questEdge = hh.questFrame:CreateTexture(nil, "BACKGROUND")
  hh.questEdge:SetPoint("TOPLEFT", hh.questFrame, "TOPLEFT", -1, 1)
  hh.questEdge:SetPoint("BOTTOMRIGHT", hh.questFrame, "BOTTOMRIGHT", 1, -1)
  hh.questEdge:SetColorTexture(0.05, 0.05, 0.06, 1)
  hh.questGlyph = hh.questFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hh.questGlyph:SetPoint("CENTER", hh.questFrame, "CENTER", 0, 0)
  hh.questGlyph:SetText("!")
  hh.questGlyph:SetTextColor(0.07, 0.07, 0.09)
  if hh.questDrawn then hh.quest:SetColorTexture(0.95, 0.65, 0.15, 1) else hh.questEdge:Hide() hh.questGlyph:Hide() end
  hh.progress = hh.questFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hh.progress:SetPoint("RIGHT", hh.questFrame, "LEFT", -3, 0)
  hh.progress:SetJustifyH("RIGHT")
  hh.progress:SetTextColor(0.95, 0.65, 0.15)
  hh.questFrame:Hide()
  if hb then
    hh.bg = hb:CreateTexture(nil, "BACKGROUND")
    hh.bg:SetAllPoints(hb)
    hh.bg:SetColorTexture(0.06, 0.06, 0.08, 0.85)
    hh.bg:Hide()
    if type(hooksecurefunc) == "function" and hb.SetStatusBarColor then
      -- Blizzard recolours on its own schedule; put ours back right after. hh.lock stops our own call recursing.
      local ok = pcall(hooksecurefunc, hb, "SetStatusBarColor", function()
        if not hh.lock and hh.unit then Plates.Color(uf) end
      end)
      hh.hooked = ok
    end
  end
  return hh
end

-- ------------------------------------------------------------------------------------------------ pieces
-- Class tokens remembered by GUID / name: identity can be hidden in combat on this client.
Plates.classByGUID, Plates.classByName = {}, {}
function Plates.ClassOf(unit)
  local _, class = call(UnitClass, unit)
  if isSecret(class) or type(class) ~= "string" then class = nil end
  local guid, name = call(UnitGUID, unit), call(UnitName, unit)
  if isSecret(guid) or type(guid) ~= "string" then guid = nil end
  if isSecret(name) or type(name) ~= "string" then name = nil end
  if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
    if guid then Plates.classByGUID[guid] = class end
    if name then Plates.classByName[name] = class end
    return class
  end
  return (guid and Plates.classByGUID[guid]) or (name and Plates.classByName[name]) or nil
end

--- Player name on the plate in class colour (Sean 2026-09-23: "make friendly name tags the colour of their class").
-- Friendly players by default (their plates are name-only), hostile players too when nameClass = "all". Blizzard
-- repaints the name on its own updates; a SetTextColor hook puts the class colour back.
function Plates.ColorName(uf)
  local hh, d = uf.hh, cfg()
  if not hh or not hh.unit or not uf.name or not uf.name.SetTextColor then return nil end
  local mode = d.nameClass or "friendly"
  if mode == "none" then return nil end
  local unit = hh.unit
  if not bool(call(UnitIsPlayer, unit)) then return nil end
  local friendly = bool(call(UnitIsFriend, "player", unit))
  if friendly == nil then local r = num(call(UnitReaction, unit, "player")) friendly = r ~= nil and r >= 5 end
  if mode == "friendly" and not friendly then return nil end
  local class = Plates.ClassOf(unit)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if not c then return nil end
  -- Blizzard paints nameplate names with SetVertexColor (CompactUnitFrame), not SetTextColor: set and hook both
  hh.nameLock = true
  call(uf.name.SetTextColor, uf.name, c.r, c.g, c.b)
  call(uf.name.SetVertexColor, uf.name, c.r, c.g, c.b)
  hh.nameLock = false
  hh.nameClass = class
  if not hh.nameHooked and type(hooksecurefunc) == "function" then
    hh.nameHooked = true
    for _, m in ipairs({ "SetTextColor", "SetVertexColor" }) do
      if type(uf.name[m]) == "function" then
        pcall(hooksecurefunc, uf.name, m, function()
          if not hh.nameLock and hh.unit and hh.nameClass then Plates.ColorName(uf) end
        end)
      end
    end
  end
  return class
end

function Plates.ColorFor(unit)
  local d = cfg()
  if d.classColors ~= false and bool(call(UnitIsPlayer, unit)) then
    local _, class = call(UnitClass, unit)
    local c = type(class) == "string" and not isSecret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
  end
  if bool(call(UnitIsTapDenied, unit)) then return 0.5, 0.5, 0.5 end
  if d.reactionColors ~= false then
    local r = num(call(UnitReaction, unit, "player"))
    if r then
      if r <= 2 then return 0.85, 0.20, 0.20
      elseif r == 3 then return 0.90, 0.45, 0.10
      elseif r == 4 then return 0.95, 0.80, 0.20 end
      return 0.25, 0.80, 0.35
    end
  end
  return nil
end

function Plates.Color(uf)
  local hh, d = uf.hh, cfg()
  if not hh or not hh.bar or not hh.unit or d.enabled == false then return end
  local r, g, b = Plates.ColorFor(hh.unit)
  if hh.questInfo and d.quest.tint then r, g, b = d.quest.color[1], d.quest.color[2], d.quest.color[3] end
  if not r then return end
  hh.lock = true
  call(hh.bar.SetStatusBarColor, hh.bar, r, g, b)
  hh.lock = false
end

--- Health text without doing sums on a value that may be secret.
function Plates.HealthText(unit, mode)
  if mode == "none" then return "" end
  if mode == "percent" then
    if type(UnitHealthPercent) == "function" then
      local curve = type(CurveConstants) == "table" and CurveConstants.ScaleTo100 or nil
      local v = call(UnitHealthPercent, unit, true, curve)
      if v ~= nil then
        if curve then return string.format("%.0f%%", v) end
        if num(v) then return string.format("%.0f%%", v * 100) end
      end
    end
    local h, m = call(UnitHealth, unit), call(UnitHealthMax, unit)
    if num(h) and num(m) and m > 0 then return string.format("%.0f%%", h / m * 100) end
  end
  local h = call(UnitHealth, unit)
  if h == nil then return "" end
  local s = call(AbbreviateNumbers, h)
  if s ~= nil then return s end
  return tostring(h)
end

function Plates.UpdateHealth(uf)
  local hh, d = uf.hh, cfg()
  if not hh or not hh.unit then return end
  if d.enabled == false or d.healthText == "none" or hh.nameOnly then hh.health:Hide() return end
  setFont(hh.health, math.max(7, (d.fontSize or 10) - 1))
  hh.health:SetText(Plates.HealthText(hh.unit, d.healthText or "percent"))
  hh.health:Show()
end

function Plates.UpdateQuest(uf)
  local hh, d = uf.hh, cfg()
  if not hh or not hh.unit then return end
  local q = d.quest
  local info = (q.icon or q.highlight or q.tint) and HHP.QuestMobs.Check(hh.unit) or nil
  hh.questInfo = info
  if info and q.icon then
    local s = q.iconSize or 16
    local c = q.color or { 0.95, 0.65, 0.15 }
    hh.questFrame:SetSize(s, s)
    if hh.questDrawn then
      hh.quest:SetColorTexture(c[1], c[2], c[3], 1)
      if hh.questGlyph.SetFont then call(hh.questGlyph.SetFont, hh.questGlyph, fontPath(), math.max(8, s - 2), "") end
    end
    hh.progress:SetText((q.progress and info.progress) or "")
    hh.progress:SetTextColor(c[1], c[2], c[3])
    setFont(hh.progress, math.max(7, (d.fontSize or 10) - 1))
    hh.questFrame:Show()
  else
    hh.questFrame:Hide()
  end
end

--- Outline colour by priority, fade for non-targets. Returns the reason it chose (tests read it).
function Plates.UpdateHighlight(uf)
  local hh, d = uf.hh, cfg()
  if not hh or not hh.unit then return end
  if hh.nameOnly then for _, e in ipairs(hh.edges) do e:Hide() end uf:SetAlpha(1) return "nameonly" end
  local unit = hh.unit
  local isTarget = bool(call(UnitIsUnit, unit, "target")) or false
  local threat = num(call(UnitThreatSituation, "player", unit))
  local color, why, thick
  if d.aggro.warn and threat and threat >= 2 then color, why, thick = d.aggro.color, "aggro", 2
  elseif d.target.highlight and isTarget then color, why, thick = d.target.color, "target", 2
  elseif d.quest.highlight and hh.questInfo then color, why, thick = d.quest.color, "quest", 1
  elseif d.enabled ~= false and d.border ~= false then color, why, thick = LINE, "plain", 1 end
  for i, e in ipairs(hh.edges) do
    if color then
      e:SetColorTexture(color[1], color[2], color[3], 1)
      if i <= 2 then e:SetHeight(thick) else e:SetWidth(thick) end
      e:Show()
    else
      e:Hide()
    end
  end
  local hasTarget = bool(call(UnitExists, "target")) or false
  if d.target.fadeOthers and hasTarget and not isTarget then uf:SetAlpha(d.target.otherAlpha or 0.6) else uf:SetAlpha(1) end
  hh.why = why
  return why
end

function Plates.ApplyLook(uf)
  local hh, d = uf.hh, cfg()
  if not hh then return end
  if d.enabled == false then
    if hh.bg then hh.bg:Hide() end
    return
  end
  if hh.bar then
    call(hh.bar.SetStatusBarTexture, hh.bar, FLAT)
    hh.bg:Show()
  end
  if uf.name then setFont(uf.name, d.fontSize or 10) end
  Plates.SkinCastbar(uf)
end

--- Blizzard's cast bar on the plate (a StatusBar under the health bar), flattened once: our texture, dark backing,
-- 1 px outline, name font. Found under several names across client generations; missing = nothing to do.
function Plates.SkinCastbar(uf)
  local hh, d = uf.hh, cfg()
  if not hh or hh.castSkinned or d.castbar == false then return nil end
  local cb = rawget(uf, "castBar") or rawget(uf, "CastBar")
  local container = rawget(uf, "CastBarsContainer")
  if not cb and type(container) == "table" then cb = rawget(container, "castBar") or rawget(container, "CastBar") end
  if type(cb) ~= "table" or not cb.SetStatusBarTexture then return nil end
  hh.castSkinned, hh.castBar = true, cb
  call(cb.SetStatusBarTexture, cb, FLAT)
  for _, k in ipairs({ "Border", "Background", "TextBorder", "Flash" }) do
    local r = rawget(cb, k)
    if type(r) == "table" and r.SetAlpha then call(r.SetAlpha, r, 0) end
  end
  hh.castBg = cb:CreateTexture(nil, "BACKGROUND")
  hh.castBg:SetAllPoints(cb)
  hh.castBg:SetColorTexture(0.06, 0.06, 0.08, 0.85)
  hh.castEdges = {}
  local spec = { { "TOPLEFT", "TOPRIGHT", -1, 1, 1, 1, nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", -1, -1, 1, -1, nil, 1 },
    { "TOPLEFT", "BOTTOMLEFT", -1, 1, -1, -1, 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 1, 1, -1, 1, nil } }
  for i, s in ipairs(spec) do
    local e = cb:CreateTexture(nil, "OVERLAY")
    e:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)
    e:SetPoint(s[1], cb, s[1], s[3], s[4])
    e:SetPoint(s[2], cb, s[2], s[5], s[6])
    if s[7] then e:SetWidth(s[7]) end
    if s[8] then e:SetHeight(s[8]) end
    hh.castEdges[i] = e
  end
  local text = rawget(cb, "Text") or rawget(cb, "text")
  if type(text) == "table" then setFont(text, math.max(7, (d.fontSize or 10) - 1)) end
  return cb
end

--- Friendly plates as names only (Sean 2026-09-23: "remove the health bars"): the bar, its backing / outline /
-- health text, the level and classification badges hidden; the class-coloured name stays. Blizzard shows the
-- bar again when it recycles the plate, so this runs on every update. Off = full plate.
function Plates.FriendlyLook(uf)
  local hh, d = uf.hh, cfg()
  if not hh or not hh.unit then return nil end
  local unit = hh.unit
  local friendly = bool(call(UnitIsFriend, "player", unit))
  if friendly == nil then local r = num(call(UnitReaction, unit, "player")) friendly = r ~= nil and r >= 5 end
  local nameOnly = friendly and d.friendlyNameOnly ~= false
  hh.nameOnly = nameOnly
  local pieces = { hh.bar, hh.bg, hh.health, hh.castBar, rawget(uf, "LevelFrame"), rawget(uf, "ClassificationFrame"), rawget(uf, "HealthBarsContainer") }
  for _, p in ipairs(pieces) do
    if type(p) == "table" and p.SetShown then
      if nameOnly then call(p.Hide, p) elseif p == hh.bar or p == rawget(uf, "HealthBarsContainer") then call(p.Show, p) end
    end
  end
  for _, e in ipairs(hh.edges or {}) do if nameOnly then e:Hide() end end
  if nameOnly and hh.questFrame then hh.questFrame:Hide() end
  -- name-only plates carry the name in a bigger font (Sean: "match my own font above my head")
  if uf.name then
    setFont(uf.name, nameOnly and (d.friendlyNameSize or 14) or (d.fontSize or 10))
    -- width 0 = "as wide as the text": the bigger font had "Benjamin Neta..." cut at Blizzard's width (2026-09-23)
    if nameOnly then call(uf.name.SetWidth, uf.name, 0) if uf.name.SetWordWrap then call(uf.name.SetWordWrap, uf.name, false) end end
  end
  -- keep the bar hidden when Blizzard shows it on plate reuse
  if hh.bar and not hh.barHideHooked and type(hooksecurefunc) == "function" then
    hh.barHideHooked = true
    pcall(hooksecurefunc, hh.bar, "Show", function(self) if hh.nameOnly and hh.unit then call(self.Hide, self) end end)
  end
  return nameOnly
end

--- Level badge (and the classification / level-diff badges next to it): off by default, kept off through
-- Blizzard's re-shows (in game 2026-09-23 "(20)" stayed on name-only plates); the option brings it back on plates
-- that are not name-only.
function Plates.ApplyLevel(uf)
  local hh, d = uf.hh, cfg()
  if not hh then return end
  local want = d.showLevel == true and not hh.nameOnly
  for _, k in ipairs({ "LevelFrame", "ClassificationFrame", "PlayerLevelDiffFrame" }) do
    local fr = rawget(uf, k)
    if type(fr) == "table" and fr.Hide then
      if want then call(fr.Show, fr) else call(fr.Hide, fr) end
      if not fr.hhLevelHooked and type(hooksecurefunc) == "function" then
        fr.hhLevelHooked = true
        pcall(hooksecurefunc, fr, "Show", function(self)
          local dd = cfg()
          if dd.enabled ~= false and (dd.showLevel ~= true or (uf.hh and uf.hh.nameOnly)) then call(self.Hide, self) end
        end)
      end
    end
  end
end

function Plates.Update(uf)
  Plates.ApplyLook(uf)
  Plates.Color(uf)
  Plates.ColorName(uf)
  Plates.FriendlyLook(uf)
  Plates.ApplyLevel(uf)
  Plates.UpdateHealth(uf)
  Plates.UpdateQuest(uf)
  Plates.UpdateHighlight(uf)
end

-- ------------------------------------------------------------------------------------------------ lifecycle
local function sample(unit, uf)
  if #Plates.samples >= 4 or bool(call(UnitIsPlayer, unit)) ~= false then return end
  local lines = HHP.QuestMobs.TooltipLines(unit)
  local shown = {}
  for i, l in ipairs(lines or {}) do
    if i > 8 then break end
    shown[#shown + 1] = tostring(l.type) .. ":" .. l.text
  end
  local info = uf.hh.questInfo
  Plates.samples[#Plates.samples + 1] = {
    name = tostring(call(UnitName, unit)), tooltip = lines and table.concat(shown, " | ") or "no C_TooltipInfo",
    quest = info and ((info.source or "?") .. " " .. tostring(info.progress)) or "no",
    hooked = uf.hh.hooked and true or false, bar = uf.hh.bar and true or false,
  }
  local g = HH.db and HH.db.global
  if g then
    g.diag = g.diag or {}
    g.diag.plates = { samples = Plates.samples, tooltipLineEnum = (Enum and Enum.TooltipDataLineType) and tostring(Enum.TooltipDataLineType.QuestObjective) or "nil" }
  end
end

Plates.skips = {}
function Plates.Added(unit)
  local uf, why = Plates.FrameFor(unit)
  if not uf then
    why = type(why) == "string" and why:gsub("nameplate%d+", "nameplateN") or "?"
    Plates.skips[why] = (Plates.skips[why] or 0) + 1
    return
  end
  Plates.Skin(uf)
  uf.hh.unit = unit
  Plates.active[unit] = uf
  Plates.Update(uf)
  pcall(sample, unit, uf)
end

function Plates.Removed(unit)
  local uf = Plates.active[unit]
  Plates.active[unit] = nil
  if uf and uf.hh then
    uf.hh.unit, uf.hh.questInfo, uf.hh.nameClass = nil, nil, nil
    uf.hh.questFrame:Hide()
    uf:SetAlpha(1)
  end
end

function Plates.ForEach(fn)
  for _, uf in pairs(Plates.active) do fn(uf) end
end

--- Pick up plates that already exist (enable after a /reload in the open world).
function Plates.Scan()
  if type(C_NamePlate) ~= "table" then return end
  local plates = call(C_NamePlate.GetNamePlates)
  if type(plates) ~= "table" then return end
  for _, plate in ipairs(plates) do
    local unit = plate.unitToken or plate.namePlateUnitToken or (plate.UnitFrame and (plate.UnitFrame.unit or plate.UnitFrame.displayedUnit))
    if type(unit) == "string" and not isSecret(unit) then Plates.Added(unit) end
  end
end

function Plates.Refresh()
  Plates.ApplyCVars()
  HHP.QuestMobs.Invalidate()
  Plates.ForEach(Plates.Update)
end

local questPending = false
local function questChanged()
  HHP.QuestMobs.Invalidate()
  if questPending then return end
  questPending = true
  local function run()
    questPending = false
    Plates.ForEach(function(uf) Plates.UpdateQuest(uf) Plates.UpdateHighlight(uf) Plates.Color(uf) end)
  end
  if C_Timer and C_Timer.After then C_Timer.After(0.2, run) else run() end
end

local EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED", "UNIT_THREAT_SITUATION_UPDATE",
  "UNIT_THREAT_LIST_UPDATE", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_FACTION", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED",
  "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_ENTERING_WORLD" }

function Plates.OnEvent(_, e, unit)
  if e == "NAME_PLATE_UNIT_ADDED" then Plates.Added(unit)
  elseif e == "NAME_PLATE_UNIT_REMOVED" then Plates.Removed(unit)
  elseif e == "PLAYER_TARGET_CHANGED" then Plates.ForEach(Plates.UpdateHighlight)
  elseif e == "UNIT_THREAT_SITUATION_UPDATE" or e == "UNIT_THREAT_LIST_UPDATE" then
    local uf = unit and Plates.active[unit]
    if uf then Plates.UpdateHighlight(uf) elseif unit == "player" or not unit then Plates.ForEach(Plates.UpdateHighlight) end
  elseif e == "UNIT_HEALTH" or e == "UNIT_MAXHEALTH" then
    local uf = unit and Plates.active[unit]
    if uf then Plates.UpdateHealth(uf) end
  elseif e == "UNIT_FACTION" then
    local uf = unit and Plates.active[unit]
    if uf then Plates.Color(uf) Plates.FriendlyLook(uf) Plates.UpdateHighlight(uf) end
  elseif e == "PLAYER_ENTERING_WORLD" then Plates.Scan()
  else questChanged() end
end

local Module = {}
HHP.module = Module

--- Blizzard's own class-colour switches for nameplates (they colour name-only friendly plates natively).
function Plates.ApplyCVars()
  local d = cfg()
  if type(SetCVar) ~= "function" then return end
  local on = (d.nameClass or "friendly") ~= "none"
  pcall(SetCVar, "ShowClassColorInFriendlyNameplate", on and "1" or "0")
  pcall(SetCVar, "ShowClassColorInNameplate", (d.classColors ~= false) and "1" or "0")
  -- One size at every distance (Sean 2026-09-23: far plates looked like a different font - the client shrinks
  -- them to 80 % with distance, grows the target to 120 % and fades far ones). Client settings, so they persist.
  if d.uniformScale ~= false then
    for k, v in pairs({ nameplateMinScale = "1", nameplateMaxScale = "1", nameplateGlobalScale = "1",
      nameplateMinAlpha = "1", nameplateMaxAlpha = "1", nameplateLargerScale = "1" }) do pcall(SetCVar, k, v) end
    pcall(SetCVar, "nameplateSelectedScale", tostring(d.targetScale or 1))
  end
  -- How far plates reach. Past this the small blue names over far players are drawn by the engine itself (the
  -- "unit names" setting) and no addon can colour or size them (Sean 2026-09-23). The client clamps the value.
  if d.maxDistance then pcall(SetCVar, "nameplateMaxDistance", tostring(d.maxDistance)) end
end

function Module:OnEnable()
  Plates.ApplyCVars()
  local ev = CreateFrame("Frame")
  Module.unknown = {}
  for _, e in ipairs(EVENTS) do
    if not pcall(ev.RegisterEvent, ev, e) then Module.unknown[#Module.unknown + 1] = e end
  end
  Plates.seen = {}
  ev:SetScript("OnEvent", function(self, e, ...)
    Plates.seen[e] = (Plates.seen[e] or 0) + 1
    local ok, err = xpcall(Plates.OnEvent, HH.Trace, self, e, ...)
    if not ok and err ~= Plates.lastError then Plates.lastError = err HH:LogError("plates " .. tostring(e) .. ": " .. tostring(err)) end
  end)
  Module.events = ev
  Plates.Scan()
end

function Module:OnProfileChanged() Plates.Refresh() end

function Module:GetOptions()
  if HHP.Options and HHP.Options.Build then return HHP.Options.Build() end
end

HH:RegisterModule("Plates", Module)
--- Everything needed to tell "no plates on screen" from "plates we fail to pick up".
function Plates.Diagnose()
  local out = {}
  out[#out + 1] = ("module enabled: %s   unknown events: %s"):format(tostring(Module.events ~= nil), table.concat(Module.unknown or {}, ",") ~= "" and table.concat(Module.unknown, ",") or "none")
  local seen = Plates.seen or {}
  out[#out + 1] = ("events seen: ADDED=%d REMOVED=%d TARGET=%d QUEST_LOG=%d"):format(seen.NAME_PLATE_UNIT_ADDED or 0, seen.NAME_PLATE_UNIT_REMOVED or 0, seen.PLAYER_TARGET_CHANGED or 0, seen.QUEST_LOG_UPDATE or 0)
  local cvar = function(n) local ok, v = pcall(GetCVar, n) return ok and tostring(v) or "?" end
  out[#out + 1] = ("cvars: nameplateShowEnemies=%s nameplateShowAll=%s nameplateShowFriends=%s"):format(cvar("nameplateShowEnemies"), cvar("nameplateShowAll"), cvar("nameplateShowFriends"))
  out[#out + 1] = ("distance: nameplateMaxDistance=%s (names further out are the engine's unit names: UnitNameFriendlyPlayerName=%s, not plates) scale min/max=%s/%s"):format(
    cvar("nameplateMaxDistance"), cvar("UnitNameFriendlyPlayerName"), cvar("nameplateMinScale"), cvar("nameplateMaxScale"))
  local plates = type(C_NamePlate) == "table" and call(C_NamePlate.GetNamePlates) or nil
  out[#out + 1] = ("on screen now (GetNamePlates): %s"):format(type(plates) == "table" and #plates or tostring(plates))
  for i, plate in ipairs(type(plates) == "table" and plates or {}) do
    if i > 5 then break end
    local unit = plate.unitToken or plate.namePlateUnitToken or (type(plate.UnitFrame) == "table" and (plate.UnitFrame.unit or plate.UnitFrame.displayedUnit))
    local uf, why = Plates.FrameFor(unit)
    local nm = uf and rawget(uf, "name")
    local nameInfo = ""
    if type(nm) == "table" then
      local _, _, _, _, size = call(nm.GetFont, nm)
      nameInfo = (" name w=%s pts=%s font=%s"):format(tostring(call(nm.GetWidth, nm)), tostring(call(nm.GetNumPoints, nm)), tostring(size))
    end
    out[#out + 1] = ("  #%d unit=%s name=%s -> %s%s"):format(i, tostring(unit), tostring(unit and call(UnitName, unit)), uf and ("ok, skinned=" .. tostring(uf.hh ~= nil) .. " nameOnly=" .. tostring(uf.hh and uf.hh.nameOnly)) or tostring(why), nameInfo)
  end
  local sk = {}
  for k, v in pairs(Plates.skips or {}) do sk[#sk + 1] = k .. " x" .. v end
  out[#out + 1] = "skipped: " .. (#sk > 0 and table.concat(sk, "; ") or "none")
  return out
end

HH:RegisterSlash("platediag", function()
  local ok, lines = pcall(Plates.Diagnose)
  if not ok then HH:Print("platediag failed: " .. tostring(lines)) return end
  for _, l in ipairs(lines) do HH:Print(l) end
  Plates.Scan()
  local n = 0
  for _ in pairs(Plates.active) do n = n + 1 end
  HH:Print(("after rescan: %d active, %d sampled (details in diag.plates)"):format(n, #Plates.samples))
  for _, s in ipairs(Plates.samples) do HH:Print(("  %s: quest=%s tooltip=%s"):format(s.name, s.quest, s.tooltip)) end
  local g = HH.db and HH.db.global
  if g then g.diag = g.diag or {} g.diag.platesDiagnose = lines end
end, "print what the nameplate module sees")
