-- CastThemes: the cast bar takes on what you are casting - holy gold, fire, frost, arcane, shadow, nature - and the
-- gathering casts too (mining = earth, herbs = green, skinning = leather, fishing = water, opening a chest = gold,
-- crafting = bronze). Sean 2026-10-14, from the WoW Forever add-on clip (#2 Opulent Casting Bars): "a more holy look
-- for holy spells, an earthy look for when you're mining... a skin for virtually every magic school".
--
-- No spell table typed in from memory (the Atlas rule: never write game data from memory). The theme is read off the
-- client, in this order:
--   1. the cast's name for the gathering casts (Mining, Smelting, Herb Gathering, Skinning, Fishing, Opening,
--      Disenchant), then UnitCastingInfo's isTradeSkill for any other profession cast = craft;
--   2. the spell's own description (C_Spell.GetSpellDescription / GetSpellDescription): the earliest
--      "<School> damage" wins ("...causes 14 to 23 Fire damage" = fire); a heal ("Heals a friendly target...") is
--      the class's healing school (priest / paladin holy, shaman / druid nature);
--   3. the class's main school (mage arcane, warlock shadow, priest / paladin holy, shaman / druid nature, hunter aim);
--   4. else none: the bar keeps your own cast / channel colours.
-- A description can arrive empty the first time a spell is seen; only a real answer is cached, so the next cast asks
-- again. A secret spell id or text is never touched (falls through to the class).
--
-- The look, HogTron-flat (no ornate frames, our own target_glow.tga for every light): the fill in the theme colour, a
-- soft glow behind the bar that breathes, the spark tinted, a few motes off the fill's head (fire rises fast, frost
-- sinks, arcane and shadow swirl, mining dust falls). A cast you cannot interrupt keeps its grey; a failed cast still
-- flashes red. Castbar.lua calls Apply at the start, Tick on every frame of the cast, Clear at the end.
HogHealsHUD = HogHealsHUD or {}
local HHD = HogHealsHUD
local HH = HogHeals

local T = { cache = {}, seen = {} }
HHD.CastThemes = T

local GLOW = "Interface\\AddOns\\HogTronUI\\Media\\target_glow"
local MAX_MOTES = 8

local function cfg()
  local hud = HH.db and HH.db.profile and HH.db.profile.hud
  return (hud and hud.castbar and hud.castbar.themes) or {}
end
local function g(name) local f = rawget(_G, name) if type(f) == "function" then return f end end
local function fn(tbl, name) if type(tbl) == "table" and type(tbl[name]) == "function" then return tbl[name] end end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function str(v) if type(v) == "string" and not isSecret(v) then return v end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
end

-- ------------------------------------------------------------------------------------------------ themes
-- motes: n = how many; rise = px per second up (negative = sinks / falls); drift = sideways wander px; size px;
-- swirl = wander in circles instead of side to side
T.THEMES = {
  -- fills stay at or below the default cyan's brightness (luminance 0.65) so the cream text reads on them from the
  -- first frame (the text also sits over the dark, empty part of the bar); the glow and motes carry the bright light
  holy    = { name = "Holy",      fill = { 0.80, 0.62, 0.30 }, glow = { 1.00, 0.95, 0.80 }, motes = { n = 5, rise = 18, drift = 4, size = 5 } },
  fire    = { name = "Fire",      fill = { 1.00, 0.42, 0.10 }, glow = { 1.00, 0.50, 0.15 }, motes = { n = 6, rise = 30, drift = 5, size = 5 } },
  frost   = { name = "Frost",     fill = { 0.36, 0.66, 0.86 }, glow = { 0.70, 0.92, 1.00 }, motes = { n = 5, rise = -10, drift = 5, size = 4 } },
  arcane  = { name = "Arcane",    fill = { 0.72, 0.42, 1.00 }, glow = { 0.82, 0.58, 1.00 }, motes = { n = 5, rise = 12, drift = 8, size = 4, swirl = true } },
  shadow  = { name = "Shadow",    fill = { 0.52, 0.24, 0.80 }, glow = { 0.58, 0.28, 0.90 }, motes = { n = 5, rise = 8, drift = 9, size = 5, swirl = true } },
  nature  = { name = "Nature",    fill = { 0.25, 0.68, 0.25 }, glow = { 0.45, 0.95, 0.45 }, motes = { n = 5, rise = 14, drift = 6, size = 4 } },
  earth   = { name = "Mining",    fill = { 0.55, 0.45, 0.36 }, glow = { 0.85, 0.66, 0.42 }, motes = { n = 6, rise = -16, drift = 7, size = 3 } },
  herb    = { name = "Herbalism", fill = { 0.48, 0.64, 0.16 }, glow = { 0.66, 0.90, 0.30 }, motes = { n = 5, rise = 10, drift = 7, size = 4 } },
  leather = { name = "Skinning",  fill = { 0.58, 0.38, 0.24 }, glow = { 0.75, 0.52, 0.34 }, motes = { n = 3, rise = -6, drift = 4, size = 3 } },
  water   = { name = "Fishing",   fill = { 0.15, 0.45, 0.85 }, glow = { 0.35, 0.65, 1.00 }, motes = { n = 5, rise = 10, drift = 3, size = 4 } },
  gold    = { name = "Opening",   fill = { 0.86, 0.55, 0.10 }, glow = { 1.00, 0.78, 0.25 }, motes = { n = 4, rise = 14, drift = 6, size = 4 } },
  craft   = { name = "Crafting",  fill = { 0.78, 0.52, 0.22 }, glow = { 0.92, 0.70, 0.40 }, motes = { n = 3, rise = 8, drift = 5, size = 3 } },
  aim     = { name = "Aimed",     fill = { 0.70, 0.62, 0.42 }, glow = { 0.95, 0.85, 0.62 }, motes = { n = 0 } },
}
-- art: one 512x64 strip per theme, HogHeals/Media/cast_<key>.tga, repeated along the FILLED part of the bar and
-- scrolled toward the spark. { blend, px per second }: ADD = light (the schools, fishing, sparks), BLEND = matter
-- (mining grit, herbs, leather). Sean 2026-10-14: "higher quality cast bar animations" - the strips are the slot for
-- that art (procedural placeholders from dev/icons/build_cast_art.py until the OpenArt set replaces them, same names).
-- A strip the client cannot load = no art layer for that theme, the rest of the look stays.
-- third value = the strip's strength (OpenArt set 2026-10-15: holy / frost / aim are near-white, so they are held back
-- or the label drowns); under an ADD strip the flat fill is dimmed to ART_FILL so the strip carries the light.
T.ART = { holy = { "ADD", 30, 0.7 }, fire = { "ADD", 55, 0.95 }, frost = { "ADD", 20, 0.6 }, arcane = { "ADD", 35, 0.9 },
  shadow = { "ADD", 25, 0.95 }, nature = { "ADD", 25, 0.85 }, earth = { "BLEND", 15, 0.95 }, herb = { "BLEND", 18, 0.9 },
  leather = { "BLEND", 10, 0.9 }, water = { "ADD", 30, 0.8 }, gold = { "ADD", 25, 0.8 }, craft = { "ADD", 30, 0.85 },
  aim = { "ADD", 90, 0.5 } }
T.ART_FILL = 0.5
local ART_DIR = "Interface\\AddOns\\HogTronUI\\Media\\cast_"
local STRIP_W, STRIP_H = 512, 64
T.artMissing = {}

T.ORDER = { "holy", "fire", "frost", "arcane", "shadow", "nature", "earth", "herb", "leather", "water", "gold", "craft", "aim" }
T.SCHOOLS = { "Holy", "Fire", "Frost", "Arcane", "Shadow", "Nature" }
T.CLASS_SCHOOL = { PRIEST = "holy", PALADIN = "holy", MAGE = "arcane", WARLOCK = "shadow", SHAMAN = "nature", DRUID = "nature", HUNTER = "aim" }
T.CLASS_HEAL = { PRIEST = "holy", PALADIN = "holy", SHAMAN = "nature", DRUID = "nature" }
-- cast names (English client) for the gathering / utility casts; matched at the start of the name
T.CAST_NAMES = { { "^Mining", "earth" }, { "^Smelting", "earth" }, { "^Herb Gathering", "herb" }, { "^Skinning", "leather" },
  { "^Fishing", "water" }, { "^Opening", "gold" }, { "^Disenchant", "arcane" } }

--- Pure: a spell description -> theme key, or nil. The earliest "<School> damage" wins; a heal maps through the class.
function T.FromDescription(text, class)
  text = str(text)
  if not text or text == "" then return nil end
  local best, at
  for _, w in ipairs(T.SCHOOLS) do
    local i = text:find(w .. " damage", 1, true)
    if i and (not at or i < at) then best, at = w:lower(), i end
  end
  if best then return best end
  local low = text:lower()
  if (low:find("^heals ") or low:find("heals ", 1, true) or low:find("healing", 1, true)) and T.CLASS_HEAL[class] then return T.CLASS_HEAL[class] end
  return nil
end

function T.Description(spellID)
  local C = rawget(_G, "C_Spell")
  local d = fn(C, "GetSpellDescription") and call(C.GetSpellDescription, spellID) or nil
  if not str(d) or d == "" then d = call(g("GetSpellDescription"), spellID) end
  return str(d)
end

--- Theme key for a cast + where it came from ("cast name" | "trade skill" | "description" | "class" | "none").
function T.Resolve(name, spellID, isTradeSkill, class)
  name = str(name)
  if name then
    for _, pair in ipairs(T.CAST_NAMES) do if name:find(pair[1]) then return pair[2], "cast name" end end
  end
  if isTradeSkill == true or isTradeSkill == 1 then return "craft", "trade skill" end
  spellID = num(spellID)
  if spellID then
    local hit = T.cache[spellID]
    if hit then return hit, "description" end
    local th = T.FromDescription(T.Description(spellID), class)
    if th then T.cache[spellID] = th return th, "description" end
  end
  local d = class and T.CLASS_SCHOOL[class]
  if d then return d, "class" end
  return nil, "none"
end

-- ------------------------------------------------------------------------------------------------ the look
local function glowTexture(parent, layer, sub)
  local t = parent:CreateTexture(nil, layer, nil, sub)
  local ok = t:SetTexture(GLOW)
  if ok == false then t:SetColorTexture(1, 1, 1, 0.3) end
  if t.SetBlendMode then t:SetBlendMode("ADD") end
  t:Hide()
  return t
end

function T.Build(b)
  if T.layers and T.layers.bar == b then return T.layers end
  local L = { bar = b, motes = {} }
  L.glow = glowTexture(b, "BACKGROUND", -2)
  L.glow:SetPoint("TOPLEFT", b, "TOPLEFT", -12, 9)
  L.glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 12, -9)
  for i = 1, MAX_MOTES do L.motes[i] = glowTexture(b, "OVERLAY", 3) end
  L.art = b:CreateTexture(nil, "ARTWORK", nil, 3)       -- above the fill, under the text / spark / latency
  L.art:Hide()
  T.layers = L
  return L
end

--- Pure: mote i of n at t seconds, for a fill head at x = head px on a bar `height` tall. -> x, y (from the bar's
-- left / centre) and alpha. Each mote loops every 1 / speed seconds, born at the head, fading as it goes.
function T.Mote(t, i, n, m, head, height)
  local speed = 0.9
  local life = ((t or 0) * speed + (i - 1) / math.max(1, n)) % 1
  local wobble = math.sin((t or 0) * 2.3 + i * 1.7)
  local x = head - life * 16 + (m.swirl and math.cos((t or 0) * 3 + i) or wobble) * (m.drift or 0) * 0.6
  local y = (m.rise or 0) * life + (m.swirl and math.sin((t or 0) * 3 + i) * (m.drift or 0) * 0.5 or 0)
  y = math.max(-(height or 18), math.min(height or 18, y))
  local alpha = (1 - life) * math.min(1, life * 6)
  return x, y, alpha
end

--- Pure: tex coords for the art strip on a fill `width` px wide on a bar `height` px tall, t seconds in, scrolling at
-- `speed` px/s toward the spark. One strip repeat is STRIP_W * height / STRIP_H px wide on screen (the strip keeps its
-- shape at any bar height); u beyond 1 wraps (the strip is loaded with REPEAT).
function T.ArtCoords(t, width, height, speed)
  local rep = STRIP_W * math.max(1, height or 18) / STRIP_H
  -- only the FRACTION of a repeat: the strip tiles, so whole repeats look the same - and the client rejects coords far
  -- out ("TexCoord out of range", Sean 2026-10-17: the swing art passes GetTime(), the PC's uptime, as t)
  local u0 = -((((t or 0) * (speed or 0)) / rep) % 1)
  return u0, u0 + math.max(0, width or 0) / rep
end

--- Start a themed cast on bar b. key = theme key (nil = plain). Returns true when a theme is on.
function T.Apply(b, key, startTime)
  local th = key and T.THEMES[key]
  local o = cfg()
  if not th or o.enabled == false then T.Clear(b) return false end
  local L = T.Build(b)
  T.active = { key = key, start = startTime or (type(GetTime) == "function" and GetTime()) or 0 }
  b:SetStatusBarColor(th.fill[1], th.fill[2], th.fill[3])
  if o.glow ~= false then
    L.glow:SetVertexColor(th.glow[1], th.glow[2], th.glow[3], 0.5 * (o.intensity or 0.8))
    L.glow:Show()
  else L.glow:Hide() end
  if b.spark and b.spark.SetVertexColor then
    b.spark:SetVertexColor(math.min(1, th.glow[1] + 0.2), math.min(1, th.glow[2] + 0.2), math.min(1, th.glow[3] + 0.2), 1)
  end
  local art = T.ART[key]
  L.art:Hide()
  L.artOn = false
  if o.art ~= false and art and not T.artMissing[key] then
    local ok = L.art:SetTexture(ART_DIR .. key, "REPEAT", "CLAMP")
    if ok == false then
      T.artMissing[key] = true
    else
      if L.art.SetBlendMode then L.art:SetBlendMode(art[1]) end
      L.art:SetVertexColor(1, 1, 1, math.min(1, (art[3] or 0.9) * (0.55 + 0.45 * (o.intensity or 0.8))))   -- the label must still read on it
      if art[1] == "ADD" then b:SetStatusBarColor(th.fill[1] * T.ART_FILL, th.fill[2] * T.ART_FILL, th.fill[3] * T.ART_FILL) end
      L.art:ClearAllPoints()
      L.art:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
      L.art:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
      L.art:SetWidth(0.01)
      L.art:Show()
      L.artOn = true
    end
  end
  for i, mt in ipairs(L.motes) do
    mt:SetSize(th.motes.size or 4, th.motes.size or 4)
    mt:SetVertexColor(th.glow[1], th.glow[2], th.glow[3], 0)
    if o.motes ~= false and i <= (th.motes.n or 0) then mt:Show() else mt:Hide() end
  end
  T.seen[key] = (T.seen[key] or 0) + 1
  return true
end

--- Every frame of a themed cast: the glow breathes, the motes move with the fill's head (p = 0..1 fill).
function T.Tick(b, p, now)
  local a = T.active
  local L = T.layers
  if not a or not L or L.bar ~= b then return end
  local th = T.THEMES[a.key]
  local o = cfg()
  local t = (now or 0) - a.start
  if o.glow ~= false then
    local breath = 0.5 + 0.5 * math.sin(t * 2 * math.pi / 1.8)
    L.glow:SetVertexColor(th.glow[1], th.glow[2], th.glow[3], (o.intensity or 0.8) * (0.35 + 0.25 * breath))
  end
  local w = num(b:GetWidth()) or 0
  local h = num(b:GetHeight()) or 0
  if h <= 0 then h = 18 end
  local head = w * math.max(0, math.min(1, p or 0))
  if L.artOn then
    local u0, u1 = T.ArtCoords(t, head, h, T.ART[a.key][2])
    L.art:SetWidth(math.max(0.01, head))
    L.art:SetTexCoord(u0, u1, 0, 1)
  end
  T.lastTick = { t = t, head = head }
  if o.motes == false then return end
  local n = th.motes.n or 0
  for i = 1, n do
    local mt = L.motes[i]
    if mt then
      local x, y, alpha = T.Mote(t, i, n, th.motes, head, h)
      mt:ClearAllPoints()
      mt:SetPoint("CENTER", b, "LEFT", x, y)
      mt:SetVertexColor(th.glow[1], th.glow[2], th.glow[3], alpha * (o.intensity or 0.8))
    end
  end
  T.lastTick = { t = t, head = head }
end

--- End of a cast (or a plain one): every layer off, the spark back to white.
function T.Clear(b)
  T.active = nil
  local L = T.layers
  if L then
    L.glow:Hide()
    for _, mt in ipairs(L.motes) do mt:Hide() end
    if L.art then L.art:Hide() end
    L.artOn = false
  end
  if b and b.spark and b.spark.SetVertexColor then b.spark:SetVertexColor(1, 1, 1, 1) end
end

function T.Line(state)
  local o = cfg()
  return ("theme: %s (from %s)%s"):format(tostring(state and state.theme or "none"), tostring(state and state.themeWhy or "-"),
    o.enabled == false and " - themes are off" or "")
end
