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
  -- a page shorter than its two torn slices (a popup): the slices shrink to half the height each, so they meet
  -- instead of overlapping (an overlap draws the paper twice: a lighter band across the middle)
  local cap = math.min(Parchment.SLICE * s, h / 2)
  local cut = (cap / s) / Parchment.PAGE_H
  for _, t in ipairs({ f.pageTop, f.pageMid, f.pageBot }) do t:SetTexture(file) t:ClearAllPoints() t:Show() end
  f.pageTop:SetTexCoord(0, 1, 0, cut)
  f.pageTop:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0) f.pageTop:SetSize(w, cap)
  local midH = math.max(0.01, h - 2 * cap)
  local px = math.min(Parchment.PAGE_H - 2 * Parchment.SLICE, math.ceil((midH / s) / Parchment.EDGE_PERIOD) * Parchment.EDGE_PERIOD)
  local want = px / Parchment.PAGE_H
  f.pageMid:SetTexCoord(0, 1, cut, cut + want)
  f.pageMid:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -cap + 0.5) f.pageMid:SetSize(w, midH + 1)   -- tucked half a pixel under both caps: no hairline seam at a fractional join
  -- caps that meet (a short popup): no middle at all - squeezed to a pixel it drew the art's full width, a seam
  -- that ran past both torn edges (the level-up card's preview, 2026-11-05)
  if h - 2 * cap < 1 then f.pageMid:Hide() end
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
  --- The same slab laid by anchors on `anchor` (inset by `inset`, caps `cap` wide): it follows the anchor's size.
  function s.Fit(_, anchor, inset, cap)
    inset, cap = inset or 0, cap or 10
    local p = s.parts
    for _, t in ipairs(p) do t:ClearAllPoints() end
    p[1]:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset, -inset) p[1]:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", inset, inset) p[1]:SetWidth(cap)
    p[3]:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -inset, -inset) p[3]:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -inset, inset) p[3]:SetWidth(cap)
    p[2]:SetPoint("TOPLEFT", p[1], "TOPRIGHT", 0, 0) p[2]:SetPoint("BOTTOMRIGHT", p[3], "BOTTOMLEFT", 0, 0)
    s.fit = { inset = inset, cap = cap }
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

-- ------------------------------------------------------------------------------------------------ our own frames
-- The quest tracker, the info bar, the menu bar, bags, tooltips ... are our own frames. In the Parchment look they wear
-- plain paper (the page art's middle, inside its torn margins - a strip too thin for the tears) with a 1 px edge in the
-- rule colour, and take their colours from Parchment.Palette(); Modern keeps ink and cyan. Sean 2026-11-05: "I want
-- things like the quest menus on the side changed. I want the bars at the bottom that shows how much gold ... changed.
-- I want everything to match this paper-like theme." The look is read when a frame is built (a change needs /reload).
Parchment.PAPER = { l = 40, r = 472, t = 300, b = 700 }   -- plain paper inside the 512 x 1024 art's torn margins (px)

--- true in the Parchment look (General > Look > Style).
function Parchment.On()
  local L = HH.Look
  return L ~= nil and type(L.Parchment) == "function" and L.Parchment() == true
end

Parchment.MODERN = { text = { 0.96, 0.92, 0.86 }, title = { 0.96, 0.92, 0.86 }, muted = { 0.55, 0.55, 0.60 }, accent = { 0.13, 0.83, 0.88 },
  good = { 0.25, 0.80, 0.35 }, bad = { 0.85, 0.20, 0.20 }, warn = { 0.95, 0.65, 0.15 }, line = { 0.20, 0.20, 0.25 }, bg = { 0.07, 0.07, 0.09 },
  header = { 0.11, 0.11, 0.14 }, paper = false, page = false }

--- Named colours for our own frames in the UI's look: text, title, muted, accent, good, bad, warn, line, bg, header;
--- paper = true on the light page (Blizzard's light text must be inked), page = true in the Parchment look at all.
function Parchment.Palette()
  if not Parchment.On() then return Parchment.MODERN end
  local th = Parchment.Theme()
  if th.paper then
    return { text = th.text, title = th.title, muted = th.muted, accent = th.pick, good = th.good, bad = { 0.60, 0.10, 0.05 },
      warn = { 0.62, 0.36, 0.02 }, line = th.rule, bg = { 0.86, 0.78, 0.62 }, header = th.tag, paper = true, page = true }
  end
  return { text = th.text, title = th.title, muted = th.muted, accent = th.pick, good = th.good, bad = { 0.92, 0.38, 0.32 },
    warn = th.quest, line = th.rule, bg = { 0.16, 0.15, 0.14 }, header = th.tag, paper = false, page = true }
end

local function near(r, g, b, c) return math.abs(r - c[1]) + math.abs(g - c[2]) + math.abs(b - c[3]) < 0.02 end
Parchment.INK_LUM = 0.34
--- A Blizzard / bright colour as ink on the light page. Neutral (low saturation): bright -> the theme's ink, dim grey
--- -> its muted ink, already dark -> left. A hue (gold, red, green, a class or quality colour): kept, brought down to a
--- luminance that reads on paper. The theme's own inks come back unchanged. Pure maths.
function Parchment.InkColor(r, g, b, th)
  th = th or Parchment.THEMES.light
  if near(r, g, b, th.text) or near(r, g, b, th.muted) or near(r, g, b, th.title) then return r, g, b end
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local sat = mx > 0 and (mx - mn) / mx or 0
  local lum = 0.299 * r + 0.587 * g + 0.114 * b
  if sat < 0.25 then
    if lum >= 0.62 then return th.text[1], th.text[2], th.text[3] end
    if lum >= 0.30 then return th.muted[1], th.muted[2], th.muted[3] end
    return r, g, b
  end
  if lum <= Parchment.INK_LUM + 0.005 then return r, g, b end
  local k = Parchment.INK_LUM / lum
  return r * k, g * k, b * k
end

--- A colour as it should read in the UI's look: unchanged in Modern and on the charred page; inked on the light page.
function Parchment.Hue(r, g, b)
  if not Parchment.On() then return r, g, b end
  local th = Parchment.Theme()
  if not th.paper then return r, g, b end
  return Parchment.InkColor(r, g, b, th)
end

--- The same for an "rrggbb" colour code (the info bar's |cff codes).
function Parchment.HueHex(hex)
  if type(hex) ~= "string" or #hex ~= 6 or not Parchment.On() then return hex end
  local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
  if not (r and g and b) then return hex end
  local nr, ng, nb = Parchment.Hue(r / 255, g / 255, b / 255)
  return ("%02x%02x%02x"):format(math.floor(nr * 255 + 0.5), math.floor(ng * 255 + 0.5), math.floor(nb * 255 + 0.5))
end

--- The colour codes INSIDE a string, inked like InkColor: |cAARRGGBB and the named |cnNAME: form (a global colour).
--- Everything else (|K BNet names, |T textures, |H links, |r) is left exactly as it was. Sean 2026-11-05 in game, the
--- friends list on paper: "what is this?" - "Baddie Xo" gold, "Lvl 18" white, "Shaman" class blue on the light page;
--- a string's own colour is inked, but codes in its text override it. Pure; a second pass changes nothing.
local function hex255(v) v = math.floor(v * 255 + 0.5) if v < 0 then v = 0 elseif v > 255 then v = 255 end return v end
function Parchment.InkCodes(s, th)
  if type(s) ~= "string" or not s:find("|c", 1, true) then return s, 0 end
  th = th or Parchment.THEMES.light
  local n = 0
  local function code(r, g, b)
    local nr, ng, nb = Parchment.InkColor(r, g, b, th)
    n = n + 1
    return ("%02x%02x%02x"):format(hex255(nr), hex255(ng), hex255(nb))
  end
  s = s:gsub("|c(%x%x)(%x%x)(%x%x)(%x%x)", function(a, r, g, b)
    return "|c" .. a .. code(tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255)
  end)
  s = s:gsub("|cn([%w_]+):", function(name)
    local c = rawget(_G, name)
    local r, g, b
    if type(c) == "table" then
      if type(c.GetRGB) == "function" then
        local ok, cr, cg, cb = pcall(c.GetRGB, c)
        if ok then r, g, b = cr, cg, cb end
      elseif type(c.r) == "number" then r, g, b = c.r, c.g, c.b end
    end
    if not (type(r) == "number" and type(g) == "number" and type(b) == "number") then return nil end   -- unknown: as it was
    return "|cff" .. code(r, g, b)
  end)
  return s, n
end

--- Plain paper over a frame of w x h: a crop of the page art's middle with the frame's own aspect (never stretched).
function Parchment.PaperCoords(tex, w, h)
  local P = Parchment.PAPER
  local aw, ah = P.r - P.l, P.b - P.t
  if not (type(w) == "number" and type(h) == "number" and w > 0 and h > 0) then w, h = aw, ah end
  local cw, ch = aw, aw * h / w
  if ch > ah then ch, cw = ah, ah * w / h end
  local cx, cy = (P.l + P.r) / 2, (P.t + P.b) / 2
  tex:SetTexCoord((cx - cw / 2) / Parchment.PAGE_W, (cx + cw / 2) / Parchment.PAGE_W, (cy - ch / 2) / Parchment.PAGE_H, (cy + ch / 2) / Parchment.PAGE_H)
  return cw, ch
end

--- The backing of one of our frames, in the UI's look: Modern = an ink fill at `alpha` + 1 px edges in the line colour;
--- Parchment = plain paper (alpha at least 0.9 - ink needs solid paper under it) + 1 px edges in the rule colour.
--- Returns { bg, edges, paper = bool }; laid over `anchor` (default f). opts.edges = false: no edges.
--- opts.charred = true: the dark (charred) page even when the look is light - for frames full of Blizzard's own bright
--- text (chat, the damage meter, tooltips), which reads on it as it is.
function Parchment.Backdrop(f, alpha, anchor, opts)
  anchor, opts = anchor or f, opts or {}
  local pal = Parchment.Palette()
  local key = Parchment.ThemeKey()
  if opts.charred and pal.page then
    key = "dark"
    local th = Parchment.THEMES.dark
    pal = { page = true, line = th.rule, paper = false }
  end
  local b = { edges = {}, paper = pal.page }
  b.bg = f:CreateTexture(nil, "BACKGROUND")
  b.bg.hhOurs = true
  b.bg:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
  b.bg:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
  if pal.page then
    b.bg:SetTexture(Parchment.ART.page[key])
    local function fit() Parchment.PaperCoords(b.bg, anchor:GetWidth(), anchor:GetHeight()) end
    fit()
    if anchor.HookScript then anchor:HookScript("OnSizeChanged", fit) end
    b.bg:SetAlpha(pal.paper and math.max(0.9, alpha or 1) or (alpha or 1))
  else
    b.bg:SetColorTexture(pal.bg[1], pal.bg[2], pal.bg[3], alpha or 0.8)
  end
  if opts.edges ~= false then
    local c = pal.line
    local spec = { { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }
    for i, sp in ipairs(spec) do
      local e = f:CreateTexture(nil, "BORDER")
      e.hhOurs = true
      e:SetColorTexture(c[1], c[2], c[3], pal.page and 0.75 or 1)
      e:SetPoint(sp[1], anchor, sp[1], 0, 0)
      e:SetPoint(sp[2], anchor, sp[2], 0, 0)
      if sp[3] then e:SetWidth(sp[3]) end
      if sp[4] then e:SetHeight(sp[4]) end
      b.edges[i] = e
    end
  end
  return b
end

--- The torn page behind a big frame of ours or of Blizzard's (the world map): larger than the frame by the art's torn
--- margins (32 / 46 / 48 px of the 512-wide art, scaled), re-laid when the frame is resized, one level under it.
--- Returns the page frame. The same maths as the window skin's page (HogTron_Skin/Panels.lua Part.Page).
Parchment.MARGIN = { side = 32, top = 46, bottom = 48 }
function Parchment.PageBehind(f, alpha)
  local p = CreateFrame("Frame", nil, f)
  p.hhOurs = true
  p:SetFrameLevel(math.max(0, ((f.GetFrameLevel and f:GetFrameLevel()) or 1) - 1))
  Parchment.MakePage(p)
  for _, t in ipairs({ p.pageTop, p.pageMid, p.pageBot }) do t.hhOurs = true end
  p:SetAlpha(alpha or 1)
  local function lay()
    local w, h = f:GetWidth(), f:GetHeight()
    if not (type(w) == "number" and type(h) == "number" and w > 0 and h > 0) then return end
    local s = w / (Parchment.PAGE_W - 2 * Parchment.MARGIN.side)
    local px, pt, pb = Parchment.MARGIN.side * s, Parchment.MARGIN.top * s, Parchment.MARGIN.bottom * s
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", f, "TOPLEFT", -px, pt)
    p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", px, -pb)
    Parchment.PlacePage(p, w + 2 * px, h + pt + pb)
  end
  p.Lay = lay
  lay()
  if f.HookScript then f:HookScript("OnSizeChanged", lay) end
  return p
end
