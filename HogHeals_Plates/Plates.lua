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
--   target    a soft light around the target's bar (9-slice of Media/target_glow.tga) that locks on when you
--             pick the target and then breathes slowly; one OnUpdate driver, running only while a glow is lit
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
local GLOW_ART = "Interface\\AddOns\\HogHeals\\Media\\target_glow"
local LINE = { 0.05, 0.05, 0.06 }
local TARGET_COLOR = { 0.13, 0.83, 0.88 }

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
  local p = HogHeals.Look.Font(cfg().font)
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
  hh.health = hh.overlay:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  hh.health:SetPoint("CENTER", anchor, "CENTER", 0, 0)
  -- Target mark (Sean 2026-09-23: no box, no arrows, no magnify). hh.arrows stays an empty table for the code paths
  -- that iterate it.
  hh.arrows = {}
  Plates.MakeGlow(uf, anchor)
  Plates.MakeBrackets(uf, anchor)
  -- Level: right of the bar, clear of the target brackets (they reach gap + thick = 5 px out)
  hh.level = hh.overlay:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  hh.level:SetPoint("LEFT", anchor, "RIGHT", 9, 0)
  hh.level:SetJustifyH("LEFT")
  hh.level:Hide()
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
  hh.questGlyph = hh.questFrame:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  hh.questGlyph:SetPoint("CENTER", hh.questFrame, "CENTER", 0, 0)
  hh.questGlyph:SetText("!")
  hh.questGlyph:SetTextColor(0.07, 0.07, 0.09)
  if hh.questDrawn then hh.quest:SetColorTexture(0.95, 0.65, 0.15, 1) else hh.questEdge:Hide() hh.questGlyph:Hide() end
  hh.progress = hh.questFrame:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
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
  setFont(hh.health, math.max(7, (d.fontSize or 13) - 2))
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

-- ------------------------------------------------------------------------------------------------ target glow
-- Sean 2026-09-24 on the first glow (three stacked flat rectangles): "looks terrible ... that light blue outline".
-- Stacked flat boxes read as hard bands, not light. Now: one soft white texture (dev/icons/build_glow.py, radial
-- fall-off) cut into a 9-slice hugging the bar - four quadrants for rounded corners, the centre row / column
-- stretched for the edges - so the bar edge is the brightest line and the light fades out evenly on every side.
-- Additive blend = it reads as light on the ground, not paint. Animated: it LOCKS ON when you pick the target (starts
-- wide and faint, snaps in to the bar in 0.3 s) and then breathes slowly (brightness, plus a slight tighten).
-- Corners: texcoord quadrants; edges: the middle texel pair (31|32 of 64, symmetric) stretched along the bar.
local C0, C1 = 31.5 / 64, 32.5 / 64
local GLOW_SLICES = {   -- { piece point, bar point, [second piece point, second bar point], l, r, t, b, kind }
  { "BOTTOMRIGHT", "TOPLEFT", nil, nil, 0, 0.5, 0, 0.5, "corner" },
  { "BOTTOMLEFT", "TOPRIGHT", nil, nil, 0.5, 1, 0, 0.5, "corner" },
  { "TOPRIGHT", "BOTTOMLEFT", nil, nil, 0, 0.5, 0.5, 1, "corner" },
  { "TOPLEFT", "BOTTOMRIGHT", nil, nil, 0.5, 1, 0.5, 1, "corner" },
  { "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT", "TOPRIGHT", C0, C1, 0, 0.5, "h" },       -- above the bar
  { "TOPLEFT", "BOTTOMLEFT", "TOPRIGHT", "BOTTOMRIGHT", C0, C1, 0.5, 1, "h" },       -- below
  { "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT", 0, 0.5, C0, C1, "w" },       -- left
  { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", 0.5, 1, C0, C1, "w" },       -- right
}
Plates.GLOW_SLICES = GLOW_SLICES

-- Motion. t = seconds since the plate became the target. Returns (spread multiplier, alpha 0..1).
Plates.GLOW = { lockOn = 0.3, from = 2.2, period = 2.4, low = 0.55, shrink = 0.12, intensity = 0.8, still = 0.85 }
function Plates.GlowAt(t, animate)
  local G = Plates.GLOW
  if not animate then return 1, G.still end
  t = math.max(0, t or 0)
  if t < G.lockOn then
    local p = t / G.lockOn
    local ease = 1 - (1 - p) ^ 3                            -- fast in, soft landing
    return G.from + (1 - G.from) * ease, math.min(1, p / 0.35)
  end
  local u = ((t - G.lockOn) % G.period) / G.period
  local w = (1 - math.cos(2 * math.pi * u)) / 2            -- 0 at the top of a breath, 1 halfway through
  return 1 - G.shrink * w, 1 - (1 - G.low) * w
end

--- Eight textures on the UnitFrame (BACKGROUND, so the bar's own frame and the name draw over them).
function Plates.MakeGlow(uf, anchor)
  local hh = uf.hh
  hh.glows = {}
  local refused = false
  for i, s in ipairs(GLOW_SLICES) do
    local g = uf:CreateTexture(nil, "BACKGROUND", nil, -7)
    if g:SetTexture(GLOW_ART) == false then refused = true end
    call(g.SetTexCoord, g, s[5], s[6], s[7], s[8])
    call(g.SetBlendMode, g, "ADD")
    -- fractional sizes while it breathes: no 1 px stepping (APIs of the modern engine; absent = no-op)
    call(g.SetSnapToPixelGrid, g, false)
    call(g.SetTexelSnappingBias, g, 0)
    g:SetPoint(s[1], anchor, s[2], 0, 0)
    if s[3] then g:SetPoint(s[3], anchor, s[4], 0, 0) end
    g.hhKind = s[9]
    g:Hide()
    hh.glows[i] = g
  end
  hh.glow = hh.glows[1]
  hh.glowArt = refused and "refused" or "ok"
  Plates.glowArt = hh.glowArt
end

--- Size + colour of a lit glow at time t (see GlowAt); still = the resting look, no motion.
function Plates.PaintGlow(uf, t, still)
  local hh, d = uf.hh, cfg()
  if not hh or not hh.glows then return end
  local s, a = Plates.GlowAt(t, not still and d.target.animate ~= false)
  local R = math.max(1, (d.target.glowSize or 9) * s)
  local tc = d.target.color or TARGET_COLOR
  local alpha = a * Plates.GLOW.intensity
  for _, g in ipairs(hh.glows) do
    if g.hhKind == "corner" then g:SetSize(R, R) elseif g.hhKind == "h" then g:SetHeight(R) else g:SetWidth(R) end
    g:SetVertexColor(tc[1], tc[2], tc[3], alpha)
  end
  hh.glowSpread, hh.glowAlpha = R, alpha
end

-- One driver for every lit glow (normally just the target): OnUpdate only while something is lit and animated,
-- hidden otherwise, so an idle plate costs nothing. A paint error stops the animation (logged once) rather than
-- throwing every frame; the glow stays up, just still.
Plates.lit = {}
function Plates.GlowDriver()
  if Plates.driver then return Plates.driver end
  local f = CreateFrame("Frame")
  f:Hide()
  f:SetScript("OnUpdate", function(self)
    local now = GetTime()
    for uf in pairs(Plates.lit) do
      local ok, err = xpcall(Plates.PaintGlow, HH.Trace or tostring, uf, now - ((uf.hh and uf.hh.glowT0) or now))
      if not ok then
        Plates.glowStopped = tostring(err)
        HH:LogError("plates glow: " .. tostring(err))
        self:Hide()
        return
      end
    end
  end)
  Plates.driver = f
  return f
end

function Plates.Light(uf, on)
  local hh = uf.hh
  if not hh or not hh.glows then return end
  local animate = cfg().target.animate ~= false and not Plates.glowStopped
  if on then
    if not hh.lit then
      hh.lit = true
      hh.glowT0 = GetTime and GetTime() or 0
      Plates.lit[uf] = true
      for _, g in ipairs(hh.glows) do g:Show() end
      Plates.NoteTarget(uf)
      Plates.PaintGlow(uf, 0, not animate)
    elseif not animate then
      Plates.PaintGlow(uf, 0, true)     -- still glow: colour / size changes land now (animated: the driver repaints)
    end
  elseif hh.lit then
    hh.lit = false
    Plates.lit[uf] = nil
    for _, g in ipairs(hh.glows) do g:Hide() end
  end
  if next(Plates.lit) ~= nil and animate then Plates.GlowDriver():Show()
  elseif Plates.driver then Plates.driver:Hide() end
end

-- ------------------------------------------------------------------------------------------------ Blizzard's borders
-- In game 2026-09-28: a thin yellow line hugged the bar of a plain (non-quest) target with our quest outline already
-- off - so it is Blizzard's, not ours. The plate draws its own border / selection pieces on the health bar and on
-- HealthBarsContainer; ours is the dark 1 px edge. They are found by key name (border / select / highlight) instead
-- of a fixed list, because the names differ per client generation, and only their alpha is touched: no re-parenting,
-- no fields written on them (that taints Blizzard's secret handling, 2026-09-26).
local BORDER_WORDS = { "border", "select", "highlight" }
local function borderish(key)
  if type(key) ~= "string" then return false end
  local k = key:lower()
  for _, w in ipairs(BORDER_WORDS) do if k:find(w, 1, true) then return true end end
  return false
end

--- Every border-like piece Blizzard hangs on the bar and its container: { { label, region }, ... }.
function Plates.BlizzBorders(uf)
  local out, seen = {}, {}
  local function scan(owner, label)
    if type(owner) ~= "table" or seen[owner] then return end
    seen[owner] = true
    for k, v in pairs(owner) do
      if borderish(k) and type(v) == "table" and not seen[v] and type(v.SetAlpha) == "function" then
        seen[v] = true
        out[#out + 1] = { label .. "." .. k, v }
      end
    end
  end
  scan(uf.hh and uf.hh.bar, "healthBar")
  scan(rawget(uf, "HealthBarsContainer"), "HealthBarsContainer")
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end

--- Blizzard's art on the bar, off while we restyle. One pass decides for every piece, so the two options can never
-- undo each other:
--   plates.flatBar (default on)      every piece of Blizzard art on the health bar and its container - backing,
--                                    border, overlays, named or not (Sean 2026-09-28, a pale bar showing behind the
--                                    red at both ends: "I just want a plain, flat color for their health bar")
--   plates.hideBorders (default on)  with flatBar off: only the border / selection pieces, found by key name
-- Kept always: the fill, our own dark backing, the heal / absorb pieces (information, not decoration). Alpha only;
-- the alpha a piece had when first seen is remembered and put back when it is no longer wanted hidden.
function Plates.QuietArt(uf)
  local hh, d = uf.hh, cfg()
  if not hh then return end
  local on = d.enabled ~= false
  local flat = on and d.flatBar ~= false and hh.bar ~= nil
  local borders = on and d.hideBorders ~= false
  hh.artAlpha = hh.artAlpha or {}
  local want, names = {}, {}
  if borders or flat then
    for _, p in ipairs(Plates.BlizzBorders(uf)) do want[p[2]] = true names[#names + 1] = p[1] end
  end
  if flat then
    local keep = { [hh.bar] = true }
    if hh.bg then keep[hh.bg] = true end
    local fill = call(hh.bar.GetStatusBarTexture, hh.bar)
    if type(fill) == "table" then keep[fill] = true end
    for k, v in pairs(uf) do
      if type(k) == "string" and type(v) == "table" then
        local lk = k:lower()
        if lk:find("heal", 1, true) or lk:find("absorb", 1, true) then keep[v] = true end
      end
    end
    local function sweep(owner)
      if type(owner) ~= "table" then return end
      local list = {}
      if type(owner.GetRegions) == "function" then for _, r in ipairs({ owner:GetRegions() }) do list[#list + 1] = r end end
      if type(owner.GetChildren) == "function" then for _, r in ipairs({ owner:GetChildren() }) do list[#list + 1] = r end end
      for _, r in ipairs(list) do
        if type(r) == "table" and type(r.SetAlpha) == "function" then
          if keep[r] then want[r] = nil else want[r] = true end
        end
      end
    end
    sweep(hh.bar)
    sweep(rawget(uf, "HealthBarsContainer"))
    for r in pairs(keep) do want[r] = nil end
  end
  for r, was in pairs(hh.artAlpha) do
    if not want[r] then call(r.SetAlpha, r, was) hh.artAlpha[r] = nil end
  end
  local n = 0
  for r in pairs(want) do
    if hh.artAlpha[r] == nil then hh.artAlpha[r] = num(call(r.GetAlpha, r)) or 1 end
    call(r.SetAlpha, r, 0)
    n = n + 1
  end
  hh.flatCount, Plates.flatCount = n, n
  Plates.bordersFound = table.concat(names, ",")
  return n
end

--- What is drawn on the bar and its container, named or not: for the disk read when a line we cannot name shows up.
function Plates.DescribeBar(uf)
  local out = {}
  local function one(owner, label)
    if type(owner) ~= "table" then return end
    local named = {}
    for k, v in pairs(owner) do if type(k) == "string" and type(v) == "table" then named[v] = k end end
    local function line(kind, r)
      if type(r) ~= "table" or #out >= 40 then return end
      local cr, cg, cb, ca = call(r.GetVertexColor, r)
      out[#out + 1] = ("%s %s key=%s type=%s shown=%s alpha=%s atlas=%s tex=%s colour=%s,%s,%s,%s"):format(label, kind,
        tostring(named[r]), tostring(call(r.GetObjectType, r)), tostring(call(r.IsShown, r)), tostring(call(r.GetAlpha, r)),
        tostring(call(r.GetAtlas, r)), tostring(call(r.GetTexture, r)), tostring(cr), tostring(cg), tostring(cb), tostring(ca))
    end
    if type(owner.GetRegions) == "function" then for _, r in ipairs({ owner:GetRegions() }) do line("region", r) end end
    if type(owner.GetChildren) == "function" then for _, r in ipairs({ owner:GetChildren() }) do line("child", r) end end
  end
  one(uf.hh and uf.hh.bar, "healthBar")
  one(rawget(uf, "HealthBarsContainer"), "HealthBarsContainer")
  return out
end

-- ------------------------------------------------------------------------------------------------ target brackets
-- Sean 2026-09-28 on the glow: "it is blurry". Picked: four hard corners hugging the bar. Flat colour textures (no
-- art file, so nothing to filter or stretch), whole-pixel sizes, on the overlay so they draw over the bar. The arms
-- never meet: a closed box around the bar is what he turned down on 2026-09-23.
Plates.BRACKET = { gap = 3, size = 10, thick = 2 }
local BRACKET_CORNERS = { { "TOPLEFT", -1, 1 }, { "TOPRIGHT", 1, 1 }, { "BOTTOMLEFT", -1, -1 }, { "BOTTOMRIGHT", 1, -1 } }

function Plates.MakeBrackets(uf, anchor)
  local hh = uf.hh
  hh.brackets = {}
  for _, c in ipairs(BRACKET_CORNERS) do
    for arm = 1, 2 do   -- 1 = the horizontal arm, 2 = the vertical arm
      local t = hh.overlay:CreateTexture(nil, "OVERLAY", nil, 2)
      t:SetColorTexture(TARGET_COLOR[1], TARGET_COLOR[2], TARGET_COLOR[3], 1)
      t.hhCorner, t.hhArm, t.hhAnchor = c, arm, anchor
      t:Hide()
      hh.brackets[#hh.brackets + 1] = t
    end
  end
  return hh.brackets
end

local function whole(v, low) return math.max(low or 0, math.floor((num(v) or 0) + 0.5)) end

--- Show / hide the corners; sizes and colour are re-read on every call, so option changes land at once.
function Plates.Bracket(uf, on, color)
  local hh, d = uf.hh, cfg()
  if not hh or not hh.brackets then return end
  if not on then
    if hh.bracketed then for _, t in ipairs(hh.brackets) do t:Hide() end end
    hh.bracketed = false
    return
  end
  local B, t = Plates.BRACKET, d.target
  local gap, thick = whole(t.bracketGap or B.gap, 0), whole(t.bracketThick or B.thick, 1)
  local armH = whole(t.bracketSize or B.size, thick + 1)
  -- the vertical arms stop short of each other whatever the bar height: at least 2 px of air between them
  local barH = whole(d.barHeight or 14, 1)
  local armV = math.max(thick + 1, math.min(armH, math.floor((barH + 2 * (gap + thick)) / 2) - 1))
  local out = gap + thick
  color = color or TARGET_COLOR
  for _, tex in ipairs(hh.brackets) do
    local c = tex.hhCorner
    tex:ClearAllPoints()
    tex:SetPoint(c[1], tex.hhAnchor, c[1], c[2] * out, c[3] * out)
    if tex.hhArm == 1 then tex:SetSize(armH, thick) else tex:SetSize(thick, armV) end
    tex:SetColorTexture(color[1], color[2], color[3], 1)
    tex:Show()
  end
  -- first time lit on this unit: write what Blizzard is drawing on the plate to diag.plateTarget
  if not hh.bracketed then pcall(Plates.NoteTarget, uf) end
  hh.bracketed, hh.bracketArmH, hh.bracketArmV, hh.bracketOut = true, armH, armV, out
end

-- Blizzard's own marks on a plate (measured children, 2026-09-18). In game 2026-09-24 a thin yellow box sat a few px
-- outside the target's bar on top of our marks - not ours, source unproven. NoteTarget writes what is showing on the
-- target plate to diag.plateTarget so the next SavedVariables read names it.
local BLIZZ_PIECES = { "selectionHighlight", "aggroHighlight", "aggroHighlightAdditive", "aggroHighlightBase", "aggroFlash",
  "SoftTargetFrame", "overAbsorbGlow" }
function Plates.BlizzPieces(uf)
  local out = {}
  local function one(label, r)
    if type(r) ~= "table" or not r.IsShown then return end
    local shown = call(r.IsShown, r)
    local vis = call(r.IsVisible, r)
    local a = call(r.GetAlpha, r)
    local cr, cg, cb, ca = call(r.GetVertexColor, r)
    out[#out + 1] = ("%s shown=%s visible=%s alpha=%s colour=%s,%s,%s,%s"):format(label, tostring(shown), tostring(vis),
      tostring(a), tostring(cr), tostring(cg), tostring(cb), tostring(ca))
  end
  for _, k in ipairs(BLIZZ_PIECES) do one(k, rawget(uf, k)) end
  local hb = uf.hh and uf.hh.bar
  if type(hb) == "table" then one("healthBar.border", rawget(hb, "border")) one("healthBar.selectedBorder", rawget(hb, "selectedBorder")) end
  local hc = rawget(uf, "HealthBarsContainer")
  if type(hc) == "table" then one("HealthBarsContainer.border", rawget(hc, "border")) end
  return out
end

function Plates.NoteTarget(uf)
  local g = HH.db and HH.db.global
  if not g then return end
  local ok, pieces = pcall(Plates.BlizzPieces, uf)
  g.diag = g.diag or {}
  local okBar, bar = pcall(Plates.DescribeBar, uf)
  g.diag.plateTarget = { at = date and date("%H:%M:%S") or "?", glowArt = uf.hh.glowArt, pieces = ok and pieces or { tostring(pieces) },
    bordersHidden = Plates.bordersFound or "", bar = okBar and bar or { tostring(bar) } }
end

--- Blizzard's selection highlight goes quiet while our target mark is on (two marks fighting on one plate).
function Plates.QuietBlizzard(uf, quiet)
  local sh = rawget(uf, "selectionHighlight")
  if type(sh) ~= "table" or not sh.SetAlpha then return end
  if quiet then call(sh.SetAlpha, sh, 0) uf.hh.blizzQuiet = true
  elseif uf.hh.blizzQuiet then call(sh.SetAlpha, sh, 1) uf.hh.blizzQuiet = nil end
end

--- Target / aggro / quest marks. Outline colour by priority: aggro on you (red, thick) beats a quest mob (amber)
-- beats plain. The target is marked by style (target.style): "brackets" (default) - four hard corners around the
-- bar, "glow" - the animated light around the bar,
-- "scale" - the whole plate magnified, "outline" (the old cyan box), "none". Aggro and target combine.
-- Returns the reason it chose (tests read it): aggro > target > quest > plain.
function Plates.UpdateHighlight(uf)
  local hh, d = uf.hh, cfg()
  if not hh or not hh.unit then return end
  local function marks(show, color) Plates.Light(uf, show == "glow") Plates.Bracket(uf, show == "brackets", color) end
  local unit = hh.unit
  local isTarget = bool(call(UnitIsUnit, unit, "target")) or false
  local style = d.target.highlight ~= false and (d.target.style or "brackets") or "none"
  if style == "arrows" then style = "brackets" end   -- older profiles
  -- magnify only when asked (Sean 2026-09-23: "don't like ... making it slightly bigger")
  local grow = (isTarget and style == "scale") and (d.target.scale or 1.25) or 1
  if uf.SetScale and hh.scale ~= grow then hh.scale = grow call(uf.SetScale, uf, grow) end
  if hh.nameOnly then for _, e in ipairs(hh.edges) do e:Hide() end marks(nil) Plates.QuietBlizzard(uf, false) uf:SetAlpha(1) return "nameonly" end
  local threat = num(call(UnitThreatSituation, "player", unit))
  local tc = d.target.color or TARGET_COLOR
  local glowing = isTarget and style == "glow"
  local color, why, thick
  if d.aggro.warn and threat and threat >= 2 then color, why, thick = d.aggro.color, "aggro", 2
  elseif isTarget and style == "outline" then color, why, thick = tc, "target", 2
  -- the target's glow owns its edge: an amber line inside cyan light read as clutter (2026-09-24); the ! badge
  -- beside the bar still says "quest mob"
  -- off by default (Sean 2026-09-28: "that yellow outline ... remove for a cleaner look"); the ! badge marks quest mobs
  elseif d.quest.highlight and hh.questInfo and not glowing then color, why, thick = d.quest.color, "quest", 1
  elseif d.enabled ~= false and d.border ~= false then color, why, thick = LINE, "plain", 1 end
  if isTarget and why ~= "aggro" then why = "target" end
  for i, e in ipairs(hh.edges) do
    if color then
      e:SetColorTexture(color[1], color[2], color[3], 1)
      if i <= 2 then e:SetHeight(thick) else e:SetWidth(thick) end
      e:Show()
    else
      e:Hide()
    end
  end
  marks(isTarget and (style == "glow" or style == "brackets") and style or nil, tc)
  Plates.QuietBlizzard(uf, isTarget and style ~= "none" and d.target.hideBlizzard ~= false)
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
    call(hh.bar.SetStatusBarTexture, hh.bar, HogHeals.Look.Bar())
    hh.bg:Show()
    -- bar height (Sean 2026-09-23: "make the health bar bigger"); width comes from the nameplateHorizontalScale cvar
    if d.barHeight then call(hh.bar.SetHeight, hh.bar, d.barHeight) end
  end
  if uf.name then
    setFont(uf.name, d.fontSize or 13)
    -- width 0 = as wide as the text: "Ferocious Grizzled Be..." was Blizzard's fixed name width (2026-09-23);
    -- and centred over the bar: with width 0 it hung off Blizzard's left anchor (in game, "Mottled Worg")
    call(uf.name.ClearAllPoints, uf.name)
    call(uf.name.SetPoint, uf.name, "BOTTOM", hh.bar or uf, "TOP", 0, 3)
    if uf.name.SetJustifyH then call(uf.name.SetJustifyH, uf.name, "CENTER") end
    call(uf.name.SetWidth, uf.name, 0)
    if uf.name.SetWordWrap then call(uf.name.SetWordWrap, uf.name, false) end
  end
  -- the cast bar is ours now (Castbar.lua); SkinCastbar stays for profiles that turn the HogTron UI bar off
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
  call(cb.SetStatusBarTexture, cb, HogHeals.Look.Bar())
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
  -- anything you can attack is never name-only, whatever the friend / reaction calls said (belt and braces, 2026-09-23)
  if bool(call(UnitCanAttack, "player", unit)) == true then friendly = false end
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
    setFont(uf.name, nameOnly and (d.friendlyNameSize or 14) or (d.fontSize or 13))
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

--- The unit's level as text ("12", "12+" elite, "12R" rare, "??" skull, "Boss"), the plain number when the client
-- lets us read it, and whether the level came back secret (then: drawn, never compared).
function Plates.LevelText(unit)
  local lvl = call(UnitLevel, unit)
  if lvl == nil then return "", nil, false end
  local n = num(lvl)
  local text = (n and n < 0) and "??" or tostring(lvl)
  local class = call(UnitClassification, unit)
  if isSecret(class) or type(class) ~= "string" then class = nil end
  if class == "elite" then text = text .. "+"
  elseif class == "rareelite" then text = text .. "R+"
  elseif class == "rare" then text = text .. "R"
  elseif class == "worldboss" then text = "Boss" end
  return text, n, isSecret(lvl)
end

local CREAM = { 0.96, 0.92, 0.86 }
--- Colour for a level against yours: the client's own difficulty colours when it has them, else the classic steps.
function Plates.LevelColor(n)
  if not n then return CREAM[1], CREAM[2], CREAM[3] end
  if n < 0 then return 0.85, 0.20, 0.20 end
  local f = rawget(_G, "GetCreatureDifficultyColor") or rawget(_G, "GetQuestDifficultyColor")
  local c = type(f) == "function" and call(f, n) or nil
  if type(c) == "table" and num(c.r) and num(c.g) and num(c.b) then return c.r, c.g, c.b end
  local me = num(call(UnitLevel, "player"))
  if not me then return CREAM[1], CREAM[2], CREAM[3] end
  local diff = n - me
  if diff >= 5 then return 0.85, 0.20, 0.20
  elseif diff >= 3 then return 1.00, 0.50, 0.25
  elseif diff >= -2 then return 1.00, 0.82, 0.00
  elseif diff >= -8 then return 0.25, 0.75, 0.25 end
  return 0.55, 0.55, 0.55
end

--- Level next to the bar (Sean 2026-09-28: "I need the npc level next to their health bar"): our own text to the
-- right of the bar, coloured by difficulty. Blizzard's level / classification / level-diff badges stay hidden while
-- we restyle (kept off through Blizzard's re-shows; in game 2026-09-23 "(20)" stayed on name-only plates) - two
-- level marks on one plate would be clutter. Never on name-only plates.
function Plates.ApplyLevel(uf)
  local hh, d = uf.hh, cfg()
  if not hh then return end
  local ours = d.enabled ~= false
  for _, k in ipairs({ "LevelFrame", "ClassificationFrame", "PlayerLevelDiffFrame" }) do
    local fr = rawget(uf, k)
    if type(fr) == "table" and fr.Hide then
      if ours then call(fr.Hide, fr) else call(fr.Show, fr) end
      if not fr.hhLevelHooked and type(hooksecurefunc) == "function" then
        fr.hhLevelHooked = true
        pcall(hooksecurefunc, fr, "Show", function(self)
          if cfg().enabled ~= false then call(self.Hide, self) end
        end)
      end
    end
  end
  if not hh.level then return end
  if not ours or d.showLevel == false or hh.nameOnly or not hh.unit then hh.level:Hide() return end
  local text, n, secret = Plates.LevelText(hh.unit)
  setFont(hh.level, math.max(7, (d.fontSize or 13) - 2))
  hh.level:SetText(text)
  hh.level:SetTextColor(Plates.LevelColor(n))
  hh.level:Show()
  hh.levelSecret = secret
  Plates.levelSeen = { secret = secret, plain = n ~= nil }
end

--- Each piece on its own: one throwing (a secret in combat) must not leave the plate half-dressed - in game
-- 2026-09-23 a recycled plate kept the previous friendly occupant's hidden bar and big font (picture 2).
local function piece(label, fn, uf)
  local ok, err = xpcall(fn, HH.Trace or tostring, uf)
  if not ok then
    local first = tostring(err):match("^[^%c]*") or tostring(err)
    if first ~= Plates.lastPieceError then
      Plates.lastPieceError = first
      HH:Print("nameplate " .. label .. ": " .. first)
    end
    HH:LogError("plates " .. label .. ": " .. tostring(err))
  end
  return ok
end

function Plates.Update(uf)
  piece("look", Plates.ApplyLook, uf)
  piece("bar art", Plates.QuietArt, uf)
  piece("colour", Plates.Color, uf)
  piece("name colour", Plates.ColorName, uf)
  piece("friendly", Plates.FriendlyLook, uf)
  piece("level", Plates.ApplyLevel, uf)
  piece("health", Plates.UpdateHealth, uf)
  piece("quest", Plates.UpdateQuest, uf)
  piece("highlight", Plates.UpdateHighlight, uf)
end

--- Back to a full plate the moment a unit leaves it: Blizzard recycles plates, and the next occupant must not
-- inherit name-only (hidden bar), the big friendly font, a class colour or a target mark.
function Plates.Reset(uf)
  local hh, d = uf.hh, cfg()
  if not hh then return end
  hh.nameOnly, hh.nameClass, hh.questInfo, hh.why = false, nil, nil, nil
  for _, p in ipairs({ hh.bar, hh.bg, rawget(uf, "HealthBarsContainer") }) do
    if type(p) == "table" and p.Show then call(p.Show, p) end
  end
  if hh.health then hh.health:Hide() end
  Plates.Light(uf, false)
  Plates.Bracket(uf, false)
  if hh.level then hh.level:Hide() end
  Plates.QuietBlizzard(uf, false)
  if hh.questFrame then hh.questFrame:Hide() end
  if uf.name then setFont(uf.name, d.fontSize or 13) end
  if uf.SetScale and hh.scale ~= 1 then hh.scale = 1 call(uf.SetScale, uf, 1) end
  uf:SetAlpha(1)
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
    uf.hh.unit = nil
    pcall(Plates.Reset, uf)
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
  -- plate width: the client sizes the plate from these; the bar follows (Sean 2026-09-23: "health bar bigger")
  if d.widthScale then pcall(SetCVar, "nameplateHorizontalScale", tostring(d.widthScale)) end
  -- Friendly pets with a plate wear our font; without one the engine prints its own small blue name over them, which
  -- no addon can size or colour (Sean 2026-10-08: "their pet names are different than their nameplates").
  for _, k in ipairs({ "nameplateShowFriendlyPets", "nameplateShowFriendlyMinions", "nameplateShowFriendlyGuardians" }) do
    pcall(SetCVar, k, d.friendlyPets ~= false and "1" or "0")
  end
  pcall(SetCVar, "nameplateShowFriendlyTotems", d.friendlyTotems and "1" or "0")
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
  if cvar("nameplateShowEnemies") == "0" then out[#out + 1] = "ENEMY NAMEPLATES ARE OFF (the V key toggles them) - what you see over heads are the engine's unit names, not plates" end
  if cvar("nameplateShowFriends") == "0" then out[#out + 1] = "friendly nameplates are off (Shift-V toggles them)" end
  out[#out + 1] = ("friendly pets / minions / guardians: plates %s (cvars pets=%s minions=%s guardians=%s totems=%s); one with no plate shows the engine's own blue name, not ours"):format(
    cfg().friendlyPets ~= false and "on" or "off", cvar("nameplateShowFriendlyPets"), cvar("nameplateShowFriendlyMinions"), cvar("nameplateShowFriendlyGuardians"), cvar("nameplateShowFriendlyTotems"))
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
  local tgt
  for _, uf in pairs(Plates.active) do if uf.hh and uf.hh.lit then tgt = uf end end
  local braced
  for _, uf in pairs(Plates.active) do if uf.hh and uf.hh.bracketed then braced = uf end end
  out[#out + 1] = ("flat bar: %s, blizzard art pieces hidden on the last plate: %s"):format(tostring(cfg().flatBar ~= false), tostring(Plates.flatCount))
  out[#out + 1] = ("blizzard bar borders hidden: %s"):format(tostring(Plates.bordersFound or "none found"))
  out[#out + 1] = ("target mark: style=%s brackets=%s arms=%sx%s"):format(tostring(cfg().target.style), tostring(braced ~= nil),
    tostring(braced and braced.hh.bracketArmH), tostring(braced and braced.hh.bracketArmV))
  local ls = Plates.levelSeen
  out[#out + 1] = ("level text: shown=%s last level secret=%s readable=%s"):format(tostring(cfg().showLevel ~= false), tostring(ls and ls.secret), tostring(ls and ls.plain))
  out[#out + 1] = ("target glow: art=%s lit=%s driver=%s stopped=%s"):format(tostring(Plates.glowArt), tostring(tgt ~= nil),
    tostring(Plates.driver and call(Plates.driver.IsShown, Plates.driver)), tostring(Plates.glowStopped or "no"))
  if tgt then for _, l in ipairs(Plates.BlizzPieces(tgt)) do out[#out + 1] = "  blizzard " .. l end end
  local sk = {}
  for k, v in pairs(Plates.skips or {}) do sk[#sk + 1] = k .. " x" .. v end
  out[#out + 1] = "skipped: " .. (#sk > 0 and table.concat(sk, "; ") or "none")
  return out
end

--- Why is / isn't my target a quest mob: its tooltip lines with types, both detectors' answers, the open objectives.
function Plates.QuestMobReport(unit)
  unit = unit or "target"
  local QM = HHP.QuestMobs
  local out = {}
  if not bool(call(UnitExists, unit)) then out[1] = "no target" return out end
  out[#out + 1] = ("target: %s  player=%s  guid=%s"):format(tostring(call(UnitName, unit)), tostring(call(UnitIsPlayer, unit)), tostring(call(UnitGUID, unit)))
  local lines = QM.TooltipLines(unit)
  if not lines then out[#out + 1] = "tooltip: no C_TooltipInfo data"
  else
    for i, l in ipairs(lines) do if i <= 10 then out[#out + 1] = ("  line %d type=%s: %s"):format(i, tostring(l.type), l.text) end end
  end
  local e = Enum and Enum.TooltipDataLineType
  out[#out + 1] = ("line types: QuestObjective=%s QuestTitle=%s QuestPlayer=%s"):format(tostring(e and e.QuestObjective), tostring(e and e.QuestTitle), tostring(e and e.QuestPlayer))
  local fromLines = QM.FromLines(lines, nil)
  out[#out + 1] = "from tooltip: " .. (fromLines and (tostring(fromLines.progress) .. " " .. tostring(fromLines.title)) or "nil")
  local HHQ = rawget(_G, "HogHealsQuests")
  local Data = type(HHQ) == "table" and HHQ.Data
  if Data and Data.OpenObjectives then
    local ok, open = pcall(Data.OpenObjectives)
    local keys = {}
    if ok and type(open) == "table" then for k in pairs(open) do keys[#keys + 1] = k end end
    table.sort(keys)
    out[#out + 1] = ("open objective names (%d): %s"):format(#keys, table.concat(keys, " | "):sub(1, 400))
    local byName = ok and QM.FromName(call(UnitName, unit), open)
    out[#out + 1] = "from name: " .. (byName and (tostring(byName.progress) .. " " .. tostring(byName.title)) or "nil")
  else
    out[#out + 1] = "quest log data: HogHeals_Quests not loaded"
  end
  QM.Invalidate()
  local info = QM.Check(unit)
  out[#out + 1] = "Check() now: " .. (info and (tostring(info.source) .. " " .. tostring(info.progress)) or "nil")
  return out
end

HH:RegisterSlash("questmob", function()
  local ok, lines = pcall(Plates.QuestMobReport, "target")
  if not ok then HH:Print("questmob failed: " .. tostring(lines)) return end
  for _, l in ipairs(lines) do HH:Print(l) end
end, "why my target is / is not marked as a quest mob")

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
