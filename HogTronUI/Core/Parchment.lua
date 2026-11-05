-- Parchment: the quest dialog's page (HogTron_Quests/Dialog.lua) as a part any window can wear. Sean 2026-11-05, on
-- the Training window: "I don't like this menu at all. I think we should design the menu to look like the dialogue
-- menu for quests." Same art (HogTronUI/Media/dialog_*.tga, ours), the same two themes (light parchment / charred
-- dark), the same ink colours and the game's own Friz Quadrata; the theme follows Quests > Dialog > Theme when that
-- module is loaded, else light. Dialog.lua keeps its own copy of the page code for now (it has its own layout
-- machine); this is the small shared surface for every other window (Training first).
local HH = HogHeals

local Parchment = {}
HH.Parchment = Parchment

local MEDIA = "Interface\\AddOns\\HogTronUI\\Media\\"
Parchment.MEDIA = MEDIA
Parchment.ART = { page = { light = MEDIA .. "dialog_page_light", dark = MEDIA .. "dialog_page_dark" }, ring = MEDIA .. "dialog_ring",
  rule = MEDIA .. "dialog_rule", round = MEDIA .. "dialog_round", line = MEDIA .. "dialog_round_line" }
Parchment.PAGE_W, Parchment.PAGE_H, Parchment.SLICE = 512, 1024, 160   -- the page texture, the height of its torn slices
Parchment.EDGE_PERIOD = 176                                             -- the art's side edges repeat every 176 px
Parchment.TEAR = 46                                                     -- the torn bottom edge rises this far (of 1024)

Parchment.THEMES = {
  light = { text = { 0.22, 0.14, 0.07 }, title = { 0.17, 0.10, 0.04 }, muted = { 0.44, 0.34, 0.22 }, rule = { 0.36, 0.24, 0.12 },
    tag = { 0.36, 0.24, 0.12, 0.16 }, tile = { 0.36, 0.24, 0.12, 0.09 }, hover = { 0.36, 0.24, 0.12, 0.18 }, pick = { 0.72, 0.48, 0.12 },
    button = { 0.30, 0.21, 0.13, 0.92 }, buttonText = { 0.96, 0.91, 0.82 }, outline = { 0.36, 0.24, 0.12, 0.60 },
    key = { 0.12, 0.08, 0.05, 0.88 }, keyText = { 0.96, 0.92, 0.84 }, quest = { 0.62, 0.36, 0.02 },
    good = { 0.08, 0.42, 0.02 }, paper = true },
  dark = { text = { 0.86, 0.82, 0.75 }, title = { 0.96, 0.92, 0.84 }, muted = { 0.60, 0.56, 0.50 }, rule = { 0.78, 0.72, 0.62 },
    tag = { 1, 1, 1, 0.08 }, tile = { 1, 1, 1, 0.05 }, hover = { 1, 1, 1, 0.10 }, pick = { 0.88, 0.66, 0.28 },
    button = { 0.22, 0.21, 0.20, 0.95 }, buttonText = { 0.95, 0.91, 0.84 }, outline = { 0.75, 0.70, 0.62, 0.45 },
    key = { 0.04, 0.04, 0.04, 0.92 }, keyText = { 0.92, 0.90, 0.86 }, quest = { 0.95, 0.70, 0.20 },
    good = { 0.45, 0.85, 0.45 }, paper = false },
}
local LEGACY = { parchment = "light", ink = "dark" }

local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a = pcall(f, ...)
  if ok then return a end
end

--- "light" | "dark": the quest dialog's choice when Quests is loaded (Quests > Dialog > Theme), else light.
function Parchment.ThemeKey()
  local p = HH.db and HH.db.profile
  local q = p and p.quests
  local k = type(q) == "table" and type(q.dialog) == "table" and q.dialog.theme or nil
  k = LEGACY[k] or k
  return Parchment.THEMES[k] and k or "light"
end
function Parchment.Theme() return Parchment.THEMES[Parchment.ThemeKey()] end

--- The page font: the game's own Friz Quadrata (what the dialog uses) at `size`, no shadow (ink on paper casts none).
function Parchment.Font(fontString, size)
  local path = rawget(_G, "STANDARD_TEXT_FONT") or "Fonts\\FRIZQT__.TTF"
  local p = HH.db and HH.db.profile
  local q = p and p.quests
  if type(q) == "table" and type(q.dialog) == "table" and q.dialog.font == "hogtron" and HH.Look and HH.Look.Font then
    path = call(HH.Look.Font) or path
  end
  if fontString.SetFont then pcall(fontString.SetFont, fontString, path, size, "") end
  if fontString.SetShadowOffset then fontString:SetShadowOffset(0, 0) end
end

--- A font string on the page: left / top justified, in the theme's ink unless a colour is given.
function Parchment.Text(parent, template, size, color)
  local t = parent:CreateFontString(nil, "OVERLAY", template or "HogTronFontHighlight")
  t:SetJustifyH("LEFT")
  if t.SetJustifyV then t:SetJustifyV("TOP") end
  if t.SetWordWrap then t:SetWordWrap(false) end
  Parchment.Font(t, size or 14)
  local c = color or Parchment.Theme().text
  t:SetTextColor(c[1], c[2], c[3])
  return t
end

function Parchment.Tint(t, c, a) t:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1) end

--- The three page slices on a frame (BACKGROUND). Place them with Parchment.PlacePage(f, w, h).
function Parchment.MakePage(f)
  f.pageTop = f:CreateTexture(nil, "BACKGROUND")
  f.pageMid = f:CreateTexture(nil, "BACKGROUND")
  f.pageBot = f:CreateTexture(nil, "BACKGROUND")
  return f
end

--- Lay the page art over w x h: torn top, a cropped (never squashed) middle, torn bottom. Returns the two caps' height.
function Parchment.PlacePage(f, w, h)
  local file = Parchment.ART.page[Parchment.ThemeKey()]
  local s = w / Parchment.PAGE_W
  local cap = Parchment.SLICE * s
  local cut = Parchment.SLICE / Parchment.PAGE_H
  for _, t in ipairs({ f.pageTop, f.pageMid, f.pageBot }) do t:SetTexture(file) t:ClearAllPoints() t:Show() end
  f.pageTop:SetTexCoord(0, 1, 0, cut)
  f.pageTop:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0) f.pageTop:SetSize(w, cap)
  local midH = math.max(0.01, h - 2 * cap)
  local px = math.min(Parchment.PAGE_H - 2 * Parchment.SLICE, math.ceil((midH / s) / Parchment.EDGE_PERIOD) * Parchment.EDGE_PERIOD)
  local want = px / Parchment.PAGE_H
  f.pageMid:SetTexCoord(0, 1, cut, cut + want)
  f.pageMid:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -cap) f.pageMid:SetSize(w, midH)
  f.pageBot:SetTexCoord(0, 1, 1 - cut, 1)
  f.pageBot:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(h - cap)) f.pageBot:SetSize(w, cap)
  return 2 * cap
end

--- A rounded shape that keeps its corners at any width: left cap, stretched middle, right cap of one 64 px texture.
function Parchment.Slab(parent, layer, file, sub)
  local s = { parts = {} }
  for i = 1, 3 do
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(file or Parchment.ART.round)
    s.parts[i] = t
  end
  s.parts[1]:SetTexCoord(0, 0.5, 0, 1)
  s.parts[2]:SetTexCoord(0.49, 0.51, 0, 1)
  s.parts[3]:SetTexCoord(0.5, 1, 0, 1)
  function s.Place(_, anchor, x, y, w, h)
    local cap = math.min(h / 2, w / 2)
    local p = s.parts
    for _, t in ipairs(p) do t:ClearAllPoints() end
    p[1]:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y) p[1]:SetSize(cap, h)
    p[2]:SetPoint("TOPLEFT", anchor, "TOPLEFT", x + cap, y) p[2]:SetSize(math.max(0.01, w - 2 * cap), h)
    p[3]:SetPoint("TOPLEFT", anchor, "TOPLEFT", x + w - cap, y) p[3]:SetSize(cap, h)
    s.box = { x = x, y = y, w = w, h = h }
  end
  function s.Color(_, c, a) for _, t in ipairs(s.parts) do Parchment.Tint(t, c, a) end s.color = { c[1], c[2], c[3], a or c[4] or 1 } end
  function s.Show() for _, t in ipairs(s.parts) do t:Show() end s.shown = true end
  function s.Hide() for _, t in ipairs(s.parts) do t:Hide() end s.shown = false end
  return s
end

--- The class circle (the game's own art) inside the bronze ring, for a page about the player.
function Parchment.ClassPortrait(tex, class)
  local coords = rawget(_G, "CLASS_ICON_TCOORDS")
  local c = type(coords) == "table" and type(class) == "string" and coords[class] or nil
  if c and tex.SetTexture then
    if tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles") ~= false then
      if tex.SetTexCoord then tex:SetTexCoord(c[1], c[2], c[3], c[4]) end
      return true
    end
  end
  tex:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
  if tex.SetTexCoord then tex:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  return false
end
