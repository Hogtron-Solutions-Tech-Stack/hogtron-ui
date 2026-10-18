-- HogHeals options window. Renders the same AceConfig-style options table the Ace dialog used, with our own
-- flat widgets. No AceGUI: nothing shared with other addons to restyle or to break, and nothing that depends
-- on FrameXML helpers a client may have dropped (WoW: Forever beta lost SetDesaturation).
--
-- Supported option fields: type (group|toggle|range|select|execute|input|color|header|description), name, desc,
-- order, get, set, func, values, min/max/step, hidden, disabled, multiline, hasAlpha, inline, width = "full".
-- name / desc / values / hidden / disabled may be functions.
-- A "description" with hhAttach = function(row, width) -> height hosts a module's own widget in that row (the
-- Frames click-cast grid). The Ace fallback dialog shows the description text instead.
local ADDON, ns = ...
local HH = HogHeals

local Panel = { usesAceGUI = false, controls = {}, nav = {}, tabs = {} }
local navPool, tabPool = {}, {}   -- every button ever made; Panel.nav / Panel.tabs list only the visible ones
HH.Panel = Panel

local P = ns and ns.palette or {}
local INK, CREAM, CYAN, GREY = P.ink or { 0.07, 0.07, 0.09 }, P.cream or { 0.96, 0.92, 0.86 }, P.cyan or { 0.13, 0.83, 0.88 }, P.grey or { 0.45, 0.45, 0.5 }
local RAISED = { 0.11, 0.11, 0.14 }
local LINE = { 0.20, 0.20, 0.25 }

local W, H, SIDEBAR, TITLE, PAD = 860, 580, 170, 40, 16
local COLS, GUTTER = 2, 18
local CW, CH = 400, 460   -- compact window (edit mode: one frame's settings beside the frame)
local MIN_W, MIN_H, MIN_CW, MIN_CH = 600, 400, 320, 260
local TAB_H, FOOTER_H = 26, 30

-- Sean 2026-10-08 in game (the compact window from the tray): "the menu is cut off ... the user should be able to
-- resize this window, or any window". Sizes live in the account-wide db (HH.db.global.panel: w/h for the full
-- window, cw/ch for the compact one); the tab row wraps instead of running off the edge; a grip bottom-right.
local function saved()
  local g = HH.db and HH.db.global
  if not g then return {} end
  g.panel = g.panel or {}
  return g.panel
end

--- Width and height for the current mode (saved, else the defaults), never under the minimums.
function Panel.Size()
  local s = saved()
  if Panel.compact then return math.max(MIN_CW, s.cw or CW), math.max(MIN_CH, s.ch or CH) end
  return math.max(MIN_W, s.w or W), math.max(MIN_H, s.h or H)
end

--- The width the content column(s) get for the current mode.
function Panel.ContentWidth()
  local w = Panel.Size()
  if Panel.compact then return w - PAD * 2 - 8 end
  return w - SIDEBAR - PAD * 2 - 8
end

--- Remember the window's size for this mode (after a resize) and lay the inside out again.
function Panel.SaveSize(w, h)
  local s = saved()
  if Panel.compact then s.cw, s.ch = math.max(MIN_CW, w), math.max(MIN_CH, h) else s.w, s.h = math.max(MIN_W, w), math.max(MIN_H, h) end
  Panel.Relayout()
end

function Panel.ResetSize()
  local s = saved()
  if Panel.compact then s.cw, s.ch = nil, nil else s.w, s.h = nil, nil end
  Panel.Relayout()
end

--- Apply the current size to the frame and its parts (same position), then repaint.
function Panel.Relayout()
  local f = Panel.frame
  if not f then return end
  local w, h = Panel.Size()
  f:SetSize(w, h)
  f.content:SetWidth(Panel.ContentWidth())
  Panel.cols = (Panel.compact or Panel.ContentWidth() < 560) and 1 or nil
  Panel.Refresh()
end

-- ------------------------------------------------------------------------------------------------ helpers
local function solid(parent, layer, c, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  return t
end

--- Flat fill + 1px border from plain textures (no BackdropTemplate, which differs between client generations).
local function skin(f, fill, border, alpha)
  f.fill = f.fill or solid(f, "BACKGROUND", fill, alpha)
  f.fill:SetAllPoints(f)
  f.fill:SetColorTexture(fill[1], fill[2], fill[3], alpha or 1)
  if border then
    f.edges = f.edges or {}
    local spec = { { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }
    for i, s in ipairs(spec) do
      local e = f.edges[i] or solid(f, "BORDER", border)
      f.edges[i] = e
      e:ClearAllPoints()
      e:SetPoint(s[1], f, s[1], 0, 0)
      e:SetPoint(s[2], f, s[2], 0, 0)
      if s[3] then e:SetWidth(s[3]) end
      if s[4] then e:SetHeight(s[4]) end
      e:SetColorTexture(border[1], border[2], border[3], 1)
    end
  end
end

local function setBorder(f, c)
  for _, e in ipairs(f.edges or {}) do e:SetColorTexture(c[1], c[2], c[3], 1) end
end

local function text(parent, template, c, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "HogTronFontHighlight")
  c = c or CREAM
  fs:SetTextColor(c[1], c[2], c[3])
  if justify then fs:SetJustifyH(justify) end
  return fs
end

--- Resolve a possibly-functional option field. Errors are logged, never fatal: one bad option must not blank the page.
-- AceConfig convention: a field may be a METHOD NAME (string) looked up on the group's `handler` object, inherited
-- down the tree. AceDBOptions' profile page is built that way (values = "ListProfiles", func = "Reset", ...).
-- Not supporting it crashed the Profiles tab on the beta (Panel.lua:437 pairs on a string).
local function methodOf(x, info)
  local h = info and info.handler
  if type(x) == "string" and type(h) == "table" and type(h[x]) == "function" then
    return function(i, ...) return h[x](h, i, ...) end
  end
  return x
end

-- Text fields (name, desc) are NEVER resolved as methods: a label that happens to equal a method name must not
-- call it (test caught "Reset" firing five times).
local function passOrLog(ok, ...)
  if not ok then HH:LogError("options: " .. tostring((...))) return nil end
  return ...   -- every value, nils included ({ pcall() } + unpack stops at the first nil)
end
local function val(x, info, ...)
  if type(x) ~= "function" then return x end
  return passOrLog(pcall(x, info, ...))
end

--- Method-capable fields only: get, values, hidden, disabled.
local function valM(x, info, ...)
  return val(methodOf(x, info), info, ...)
end

local function call(fn, info, ...)
  fn = methodOf(fn, info)
  if type(fn) ~= "function" then return end
  local ok, err = pcall(fn, info, ...)
  if not ok then HH:LogError("options: " .. tostring(err)) end
end

local function sortedArgs(group)
  local out = {}
  for key, opt in pairs(group.args or {}) do out[#out + 1] = { key = key, opt = opt } end
  table.sort(out, function(a, b)
    local oa, ob = tonumber(a.opt.order) or 100, tonumber(b.opt.order) or 100
    if oa ~= ob then return oa < ob end
    return tostring(a.key) < tostring(b.key)
  end)
  return out
end

local function mkInfo(path, opt, handler)
  local info = { option = opt, arg = opt.arg, type = opt.type, handler = opt.handler or handler }
  for part in path:gmatch("[^%.]+") do info[#info + 1] = part end
  return info
end

local function tooltip(owner, opt, info)
  owner:SetScript("OnEnter", function(self)
    if self.hover then self.hover(true) end
    local d = val(opt.desc, info)
    if not d or d == "" or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(tostring(val(opt.name, info) or ""), CYAN[1], CYAN[2], CYAN[3])
    GameTooltip:AddLine(tostring(d), CREAM[1], CREAM[2], CREAM[3], true)
    GameTooltip:Show()
  end)
  owner:SetScript("OnLeave", function(self)
    if self.hover then self.hover(false) end
    if GameTooltip then GameTooltip:Hide() end
  end)
end

-- ------------------------------------------------------------------------------------------------ window
local function flatButton(parent, w, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  skin(b, RAISED, LINE)
  b.label = text(b, "HogTronFontSmall", CREAM)
  b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.hover = function(on) if not b.off then setBorder(b, on and CYAN or LINE) end end
  b:SetScript("OnEnter", function() b.hover(true) end)
  b:SetScript("OnLeave", function() b.hover(false) end)
  return b
end


-- ------------------------------------------------------------------------------------------------ painted look
-- The options window in the HogTron art set (OpenArt, Sean 2026-10-14 night: "redo our own menus and make them really
-- nice"): a slate background tile, a brass frame (9-slice: one corner art mirrored, edge strips repeated), the title
-- banner (3-slice: its pointed caps keep their shape at any width) and a slate sidebar with a brass rail. Every piece
-- anchors to the window's corners, so the resize grip still works. look.menus = "flat" puts the old flat panel back.
local ART = "Interface\\AddOns\\HogTronUI\\Media\\"
local CORNER, EDGE, CAP = 34, 12, 0.07   -- corner px, edge strip px, banner cap share of the art's width

local function artTex(parent, layer, sub, file, wrapH, wrapV)
  local t = parent:CreateTexture(nil, layer, nil, sub)
  local ok = t:SetTexture(ART .. file, wrapH, wrapV)
  return t, ok ~= false
end

function Panel.MenuArt() return not (HH.db and HH.db.profile and HH.db.profile.look and HH.db.profile.look.menus == "flat") end

function Panel.BuildArt(f)
  if f.art then return f.art end
  local A, ok, all = {}, true, true
  A.bg, ok = artTex(f, "BACKGROUND", 1, "menu_bg", "REPEAT", "REPEAT") all = all and ok
  A.bg:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
  A.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
  A.side, ok = artTex(f.side, "BACKGROUND", 1, "menu_side") all = all and ok
  A.side:SetAllPoints(f.side)
  -- banner: left cap, stretched middle, right cap
  A.head = {}
  for i = 1, 3 do A.head[i], ok = artTex(f.bar, "BACKGROUND", 2, "menu_header") all = all and ok end
  A.head[1]:SetTexCoord(0, CAP, 0, 1)
  A.head[2]:SetTexCoord(CAP, 1 - CAP, 0, 1)
  A.head[3]:SetTexCoord(1 - CAP, 1, 0, 1)
  -- frame: four corners (one art, mirrored by tex coords) and four repeated edge strips, over the edges of the window
  local holder = CreateFrame("Frame", nil, f)
  holder:SetAllPoints(f)
  holder:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
  if holder.EnableMouse then holder:EnableMouse(false) end
  A.holder = holder
  A.corners = {}
  local spec = { { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 }, { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 } }
  for i, sp in ipairs(spec) do
    local t
    t, ok = artTex(holder, "OVERLAY", 2, "menu_corner") all = all and ok
    t:SetSize(CORNER, CORNER)
    t:SetPoint(sp[1], f, sp[1], 0, 0)
    t:SetTexCoord(sp[2], sp[3], sp[4], sp[5])
    A.corners[i] = t
  end
  A.edges = {}
  local top
  top, ok = artTex(holder, "OVERLAY", 1, "menu_edge_h", "REPEAT", "CLAMP") all = all and ok
  top:SetPoint("TOPLEFT", f, "TOPLEFT", CORNER, 0) top:SetPoint("TOPRIGHT", f, "TOPRIGHT", -CORNER, 0) top:SetHeight(EDGE)
  local bottom
  bottom, ok = artTex(holder, "OVERLAY", 1, "menu_edge_h", "REPEAT", "CLAMP") all = all and ok
  bottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", CORNER, 0) bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -CORNER, 0) bottom:SetHeight(EDGE)
  local left
  left, ok = artTex(holder, "OVERLAY", 1, "menu_edge_v", "CLAMP", "REPEAT") all = all and ok
  left:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -CORNER) left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, CORNER) left:SetWidth(EDGE)
  local right
  right, ok = artTex(holder, "OVERLAY", 1, "menu_edge_v", "CLAMP", "REPEAT") all = all and ok
  right:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -CORNER) right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, CORNER) right:SetWidth(EDGE)
  A.edges = { top, bottom, left, right }
  A.loaded = all
  f.art = A
  return A
end

--- Size-dependent bits: the banner's caps keep the art's proportions, tiles repeat at their own size.
function Panel.LayoutArt(f)
  local A = f.art
  if not A then return end
  local w, h = f:GetWidth() or W, f:GetHeight() or H
  local bh = f.bar:GetHeight() or TITLE
  local cap = math.floor(bh * (1024 * CAP / 128) + 0.5)
  A.head[1]:ClearAllPoints() A.head[1]:SetPoint("TOPLEFT", f.bar, "TOPLEFT", 0, 0) A.head[1]:SetSize(cap, bh)
  A.head[3]:ClearAllPoints() A.head[3]:SetPoint("TOPRIGHT", f.bar, "TOPRIGHT", 0, 0) A.head[3]:SetSize(cap, bh)
  A.head[2]:ClearAllPoints() A.head[2]:SetPoint("TOPLEFT", f.bar, "TOPLEFT", cap, 0) A.head[2]:SetPoint("BOTTOMRIGHT", f.bar, "BOTTOMRIGHT", -cap, 0)
  A.bg:SetTexCoord(0, (w - 8) / 256, 0, (h - 8) / 256)
  A.edges[1]:SetTexCoord(0, (w - 2 * CORNER) / (256 * EDGE / 32), 0, 1)
  A.edges[2]:SetTexCoord(0, (w - 2 * CORNER) / (256 * EDGE / 32), 1, 0)
  A.edges[3]:SetTexCoord(0, 1, 0, (h - 2 * CORNER) / (256 * EDGE / 32))
  A.edges[4]:SetTexCoord(1, 0, 0, (h - 2 * CORNER) / (256 * EDGE / 32))
end

-- Close button. Sean 2026-10-15: the x sat inside the title bar next to the brass corner - "I'd rather it be all the way
-- in the corner or have it be matching with the gold". Painted: a brass button ON the top-right corner ornament,
-- above the frame art. Flat: the plain button in the title bar, as before.
local BRASS, BRASS_RIM, BRASS_HI = { 0.52, 0.38, 0.16 }, { 0.86, 0.70, 0.38 }, { 1.0, 0.86, 0.52 }
function Panel.StyleClose(f, on)
  local c = f.close
  c:ClearAllPoints()
  if on then
    -- a child of the frame-art layer: drawn after (over) the corner ornament on any stacking rule
    local holder = f.art and f.art.holder
    if holder then c:SetParent(holder) end
    c:SetSize(22, 22)
    c:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    if holder and holder.GetFrameLevel and c.SetFrameLevel then c:SetFrameLevel((holder:GetFrameLevel() or 1) + 5) end
    c.fill:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], 1)
    setBorder(c, BRASS_RIM)
    c.label:SetTextColor(0.10, 0.07, 0.03)
    c.hover = function(over) setBorder(c, over and BRASS_HI or BRASS_RIM) end
  else
    c:SetParent(f.bar)
    c:SetSize(24, 24)
    c:SetPoint("RIGHT", f.bar, "RIGHT", -8, 0)
    c.fill:SetColorTexture(RAISED[1], RAISED[2], RAISED[3], 1)
    setBorder(c, LINE)
    c.label:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
    c.hover = function(over) if not c.off then setBorder(c, over and CYAN or LINE) end end
  end
  c.brass = on and true or false
end

--- Painted or flat, now. Flat = the plain fills that were there before (and the fallback if the art did not load).
function Panel.ApplyArt(f)
  f = f or Panel.frame
  if not f then return end
  local want = Panel.MenuArt()
  local A = want and Panel.BuildArt(f) or f.art
  local on = want and A and A.loaded
  local function vis(t, show) if t then if show then t:Show() else t:Hide() end end end
  if A then
    vis(A.bg, on) vis(A.side, on)
    for _, t in ipairs(A.head) do vis(t, on) end
    if A.holder then vis(A.holder, on) end
  end
  vis(f.fill, true)
  if f.bar and f.bar.fill then vis(f.bar.fill, not on) end
  if f.side and f.side.fill then vis(f.side.fill, not on) end
  vis(f.accent, not on)
  for _, e in ipairs(f.edges or {}) do vis(e, not on) end
  Panel.artOn = on and true or false
  -- the brass corners are CORNER px: the title and the close button step inside them (in a flat window they sit at PAD)
  if f.titleHog and f.bar then f.titleHog:ClearAllPoints() f.titleHog:SetPoint("LEFT", f.bar, "LEFT", on and (CORNER + 6) or PAD, 0) end
  if f.close and f.bar then Panel.StyleClose(f, on) end
  if on then Panel.LayoutArt(f) end
end

local function build()
  if Panel.frame then return Panel.frame end
  local f = CreateFrame("Frame", "HogHealsPanel", UIParent)
  f:SetSize(W, H)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  skin(f, INK, LINE, 0.97)
  f:Hide()
  if type(UISpecialFrames) == "table" then tinsert(UISpecialFrames, "HogHealsPanel") end   -- Esc closes

  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
  bar:SetHeight(TITLE)
  skin(bar, RAISED)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() f:StartMoving() end)
  bar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
  f.accent = solid(bar, "ARTWORK", CYAN)
  f.accent:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
  f.accent:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  f.accent:SetHeight(2)

  -- Two-tone wordmark (brand rule): HOG in cream, HEALS in cyan.
  f.titleHog = text(bar, "HogTronFontNormalLarge", CREAM)
  f.titleHog:SetPoint("LEFT", bar, "LEFT", PAD, 0)
  f.titleHog:SetText("HOG")
  f.titleHeals = text(bar, "HogTronFontNormalLarge", CYAN)
  f.titleHeals:SetPoint("LEFT", f.titleHog, "RIGHT", 0, 0)
  f.titleHeals:SetText("TRON UI")
  -- light warm grey: the old GREY vanished on the painted banner (Sean 2026-10-15, "vdev" unreadable in game)
  f.version = text(bar, "HogTronFontSmall", { 0.80, 0.76, 0.70 })
  f.version:SetPoint("LEFT", f.titleHeals, "RIGHT", 10, -1)
  f.version:SetText("v" .. tostring(HH.version or "dev"))

  local close = flatButton(bar, 24, 24)
  close:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
  close.label:SetText("x")
  close:SetScript("OnClick", function() f:Hide() end)
  f.close = close

  local side = CreateFrame("Frame", nil, f)
  side:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
  side:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
  side:SetWidth(SIDEBAR)
  skin(side, { 0.09, 0.09, 0.115 })
  f.side = side
  f.bar = bar
  Panel.ApplyArt(f)
  if f.HookScript then f:HookScript("OnSizeChanged", function(self) if Panel.artOn then Panel.LayoutArt(self) end end) end

  local tabbar = CreateFrame("Frame", nil, f)
  tabbar:SetPoint("TOPLEFT", side, "TOPRIGHT", PAD, -10)
  tabbar:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
  tabbar:SetHeight(28)
  f.tabbar = tabbar

  local scroll = CreateFrame("ScrollFrame", nil, f)
  scroll:SetPoint("TOPLEFT", tabbar, "BOTTOMLEFT", 0, -10)
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = self:GetVerticalScrollRange() or 0
    local cur = (self:GetVerticalScroll() or 0) - delta * 40
    if cur < 0 then cur = 0 elseif cur > max then cur = max end
    self:SetVerticalScroll(cur)
  end)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(W - SIDEBAR - PAD * 2 - 8, 10)   -- 8 px shy of the viewport: the right column was being clipped
  scroll:SetScrollChild(content)
  f.scroll, f.content = scroll, content

  -- a footer for a module's quick actions in the compact window (Test 5 / Test 25 / Stop for the frames, ...)
  local footer = CreateFrame("Frame", nil, f)
  footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 6)
  footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 6)
  footer:SetHeight(FOOTER_H)
  footer.buttons = {}
  footer:Hide()
  f.footer = footer

  -- the resize grip: drag the corner, the size is kept for this mode
  if f.SetResizable then f:SetResizable(true) end
  if f.SetResizeBounds then pcall(f.SetResizeBounds, f, MIN_CW, MIN_CH) elseif f.SetMinResize then pcall(f.SetMinResize, f, MIN_CW, MIN_CH) end
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  grip:SetFrameLevel(f:GetFrameLevel() + 5)
  grip.tex = grip:CreateTexture(nil, "OVERLAY")
  grip.tex:SetAllPoints(grip)
  if grip.tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up") == false then
    grip.tex:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.9)
  else
    grip.tex:SetVertexColor(CYAN[1], CYAN[2], CYAN[3])
  end
  grip:SetScript("OnMouseDown", function() Panel.sizing = true if f.StartSizing then f:StartSizing("BOTTOMRIGHT") end end)
  grip:SetScript("OnMouseUp", function()
    Panel.sizing = nil
    if f.StopMovingOrSizing then f:StopMovingOrSizing() end
    local w, h = f:GetSize()
    if type(w) == "number" and type(h) == "number" then Panel.SaveSize(w, h) end
  end)
  grip:SetScript("OnEnter", function()
    if not GameTooltip then return end
    GameTooltip:SetOwner(grip, "ANCHOR_LEFT")
    GameTooltip:AddLine("Drag to resize", 0.96, 0.92, 0.86)
    GameTooltip:AddLine("Right-click: back to the default size", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  grip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  grip:SetScript("OnClick", function(_, button) if button == "RightButton" then Panel.ResetSize() end end)
  f.grip = grip

  f:SetScript("OnHide", function() if Panel.menu then Panel.menu:Hide() end end)
  Panel.frame = f
  return f
end

-- ------------------------------------------------------------------------------------------------ pooling
-- Pages are rebuilt after every change (options add/remove rows dynamically). Frames cannot be destroyed in WoW,
-- so rows are recycled per kind instead of leaking a new set on every click.
local pool, live = {}, {}
local function acquire(kind, make)
  local p = pool[kind]
  local row = p and table.remove(p)
  if not row then row = make(); row.kind = kind end
  row:Show()
  live[#live + 1] = row
  return row
end
local function releaseAll()
  for _, row in ipairs(live) do
    row:Hide()
    row:ClearAllPoints()
    pool[row.kind] = pool[row.kind] or {}
    table.insert(pool[row.kind], row)
  end
  live = {}
  Panel.controls = {}
end

-- ------------------------------------------------------------------------------------------------ dropdown menu
local function menu()
  if Panel.menu then return Panel.menu end
  local m = CreateFrame("Frame", "HogHealsPanelMenu", UIParent)
  m:SetFrameStrata("FULLSCREEN_DIALOG")
  skin(m, RAISED, CYAN)
  m.items = {}
  m:Hide()
  Panel.menu = m
  return m
end

local function openMenu(anchor, entries, current, onPick)
  local m = menu()
  if m:IsShown() and m.owner == anchor then m:Hide() return end
  m.owner = anchor
  for _, it in ipairs(m.items) do it:Hide() end
  local w = math.max(anchor:GetWidth() or 160, 160)
  for i, e in ipairs(entries) do
    local it = m.items[i]
    if not it then
      it = CreateFrame("Button", nil, m)
      it:SetHeight(20)
      it.bg = solid(it, "BACKGROUND", CYAN, 0.18)
      it.bg:SetAllPoints(it)
      it.bg:Hide()
      it.label = text(it, "HogTronFontSmall", CREAM, "LEFT")
      it.label:SetPoint("LEFT", it, "LEFT", 8, 0)
      it:SetScript("OnEnter", function(self) self.bg:Show() end)
      it:SetScript("OnLeave", function(self) self.bg:Hide() end)
      m.items[i] = it
    end
    it:ClearAllPoints()
    it:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -1 - (i - 1) * 20)
    it:SetWidth(w - 2)
    it.label:SetText(e.label)
    local c = (e.key == current) and CYAN or CREAM
    it.label:SetTextColor(c[1], c[2], c[3])
    it:SetScript("OnClick", function() m:Hide(); onPick(e.key) end)
    it:Show()
  end
  m:SetSize(w, #entries * 20 + 2)
  m:ClearAllPoints()
  m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  m:Show()
end

-- ------------------------------------------------------------------------------------------------ controls
-- Each maker returns a row frame; each filler binds it to one option and returns the row height.
local function rowFrame() return CreateFrame("Frame", nil, Panel.frame.content) end

local function labelOn(row)
  row.label = row.label or text(row, "HogTronFontSmall", CREAM, "LEFT")
  return row.label
end

--- Every option label wraps inside its own column and the row grows to fit (Sean 2026-10-17, in game: a long label
-- ran straight across the next column - "Lock position (otherwise drag the header to move it; /hh unlock..." over
-- "Watch new quests"). Returns the label's height in px (one line = 14).
local LINE_H = 14
local function wrapLabel(fs, width)
  if not fs then return LINE_H end
  if fs.SetWordWrap then fs:SetWordWrap(true) end
  if fs.SetJustifyV then fs:SetJustifyV("TOP") end
  fs:SetWidth(math.max(24, width or 0))
  local h = fs.GetStringHeight and fs:GetStringHeight()
  if type(h) ~= "number" or h <= 0 then h = LINE_H end
  return math.ceil(h)
end
Panel.WrapLabel = wrapLabel

local function dim(row, off)
  row:SetAlpha(off and 0.4 or 1)
end

local makers, fillers = {}, {}

makers.header = function()
  local r = rowFrame()
  r.text = text(r, "HogTronFontNormalSmall", CYAN, "LEFT")
  r.text:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 6)
  r.rule = solid(r, "ARTWORK", LINE)
  r.rule:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
  r.rule:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
  r.rule:SetHeight(1)
  return r
end
fillers.header = function(r, opt, info)
  r.text:SetText(tostring(val(opt.name, info) or ""):upper())
  return 30
end

makers.description = function()
  local r = rowFrame()
  r.text = text(r, "HogTronFontSmall", { 0.78, 0.75, 0.70 }, "LEFT")
  r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -2)
  r.text:SetPoint("RIGHT", r, "RIGHT", 0, 0)
  if r.text.SetJustifyV then r.text:SetJustifyV("TOP") end
  if r.text.SetWordWrap then r.text:SetWordWrap(true) end
  return r
end
fillers.description = function(r, opt, info, width)
  r.text:SetWidth(width)
  r.text:SetText(tostring(val(opt.name, info) or ""))
  return math.max(18, (r.text:GetStringHeight() or 14) + 8)
end

makers.toggle = function()
  local r = rowFrame()
  r.button = CreateFrame("Button", nil, r)
  r.button:SetAllPoints(r)
  r.box = CreateFrame("Frame", nil, r)
  r.box:SetSize(16, 16)
  r.box:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -5)
  skin(r.box, RAISED, LINE)
  r.tick = solid(r.box, "ARTWORK", CYAN)
  r.tick:SetPoint("TOPLEFT", r.box, "TOPLEFT", 3, -3)
  r.tick:SetPoint("BOTTOMRIGHT", r.box, "BOTTOMRIGHT", -3, 3)
  labelOn(r):SetPoint("TOPLEFT", r.box, "TOPRIGHT", 8, -1)
  r.button.hover = function(on) setBorder(r.box, on and CYAN or LINE) end
  return r
end
fillers.toggle = function(r, opt, info, width, off)
  r.label:SetText(tostring(val(opt.name, info) or ""))
  local lh = wrapLabel(r.label, (width or 200) - 24)
  r.checked = valM(opt.get, info) and true or false
  if r.checked then r.tick:Show() else r.tick:Hide() end
  tooltip(r.button, opt, info)
  r.button:SetScript("OnClick", function()
    if off then return end
    call(opt.set, info, not r.checked)
    Panel.Refresh()
  end)
  return math.max(26, lh + 12)
end

makers.execute = function()
  local r = rowFrame()
  r.button = flatButton(r, 10, 24)
  r.button:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -2)
  r.button:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -2)
  return r
end
fillers.execute = function(r, opt, info, width, off)
  r.button.label:SetText(tostring(val(opt.name, info) or ""))
  if r.button.label.SetJustifyH then r.button.label:SetJustifyH("CENTER") end
  local bh = math.max(24, wrapLabel(r.button.label, (width or 200) - 16) + 10)
  r.button:SetHeight(bh)
  r.button.off = off
  tooltip(r.button, opt, info)
  r.button:SetScript("OnClick", function()
    if off then return end
    call(opt.func, info)
    Panel.Refresh()
  end)
  return bh + 8
end

makers.range = function()
  local r = rowFrame()
  labelOn(r):SetPoint("TOPLEFT", r, "TOPLEFT", 0, -2)
  r.valueText = text(r, "HogTronFontSmall", CYAN, "RIGHT")
  r.valueText:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -2)
  local s = CreateFrame("Slider", nil, r)
  s:SetOrientation("HORIZONTAL")
  s:SetHeight(14)
  s:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -20)
  s:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -20)
  s.track = solid(s, "BACKGROUND", LINE)
  s.track:SetPoint("LEFT", s, "LEFT", 0, 0)
  s.track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
  s.track:SetHeight(4)
  local thumb = s:CreateTexture(nil, "OVERLAY")
  thumb:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 1)
  thumb:SetSize(8, 14)
  s:SetThumbTexture(thumb)
  r.slider = s
  return r
end
local function snap(v, min, max, step)
  if step and step > 0 then v = math.floor((v - min) / step + 0.5) * step + min end
  if v < min then v = min elseif v > max then v = max end
  return v
end
local function fmtNum(v, step)
  if step and step < 1 then return (step < 0.1 and "%.2f" or "%.1f"):format(v) end
  return tostring(math.floor(v + 0.5))
end
fillers.range = function(r, opt, info, width, off)
  local min, max, step = tonumber(opt.min) or 0, tonumber(opt.max) or 100, tonumber(opt.step) or 1
  r.label:SetText(tostring(val(opt.name, info) or ""))
  local lh = wrapLabel(r.label, (width or 200) - 52)     -- room for the value on the right
  local s = r.slider
  s:ClearAllPoints()
  s:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -(lh + 6))
  s:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -(lh + 6))
  s:SetScript("OnValueChanged", nil)
  s:SetMinMaxValues(min, max)
  if s.SetValueStep then s:SetValueStep(step) end
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  local got = valM(opt.get, info)          -- a getter may return nothing at all; tonumber() with zero args throws
  local cur = tonumber(got) or min
  s:SetValue(cur)
  r.valueText:SetText(fmtNum(cur, step))
  if s.EnableMouse then s:EnableMouse(not off) end
  tooltip(s, opt, info)
  -- No page rebuild while dragging (it would recycle the slider under the cursor); rebuild on release.
  s:SetScript("OnValueChanged", function(self, v, user)
    local nv = snap(tonumber(v) or min, min, max, step)
    if nv == r.last then return end
    r.last = nv
    r.valueText:SetText(fmtNum(nv, step))
    if user ~= false then call(opt.set, info, nv) end
  end)
  r.last = cur
  s:SetScript("OnMouseUp", function() Panel.Refresh() end)
  return lh + 30
end

makers.select = function()
  local r = rowFrame()
  labelOn(r):SetPoint("TOPLEFT", r, "TOPLEFT", 0, -2)
  r.button = flatButton(r, 10, 22)
  r.button:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -18)
  r.button:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -18)
  r.button.label:ClearAllPoints()
  r.button.label:SetPoint("LEFT", r.button, "LEFT", 8, 0)
  r.button.arrow = text(r.button, "HogTronFontSmall", CYAN)
  r.button.arrow:SetPoint("RIGHT", r.button, "RIGHT", -8, 0)
  r.button.arrow:SetText("v")
  return r
end
fillers.select = function(r, opt, info, width, off)
  r.label:SetText(tostring(val(opt.name, info) or ""))
  local lh = wrapLabel(r.label, width or 200)
  r.button:ClearAllPoints()
  r.button:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -(lh + 4))
  r.button:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -(lh + 4))
  local values = valM(opt.values, info)
  if type(values) ~= "table" then values = {} end
  local cur = valM(opt.get, info)
  local entries = {}
  for k, v in pairs(values) do entries[#entries + 1] = { key = k, label = tostring(v) } end
  table.sort(entries, function(a, b) return a.label < b.label end)
  r.button.label:SetText(values[cur] ~= nil and tostring(values[cur]) or (cur ~= nil and tostring(cur) or "-"))
  r.button.off = off
  tooltip(r.button, opt, info)
  r.button:SetScript("OnClick", function(self)
    if off then return end
    openMenu(self, entries, cur, function(key) call(opt.set, info, key); Panel.Refresh() end)
  end)
  return lh + 32
end

makers.input = function()
  local r = rowFrame()
  labelOn(r):SetPoint("TOPLEFT", r, "TOPLEFT", 0, -2)
  r.well = CreateFrame("Frame", nil, r)
  r.well:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -18)
  r.well:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 6)
  skin(r.well, { 0.05, 0.05, 0.065 }, LINE)
  local e = CreateFrame("EditBox", nil, r.well)
  e:SetPoint("TOPLEFT", r.well, "TOPLEFT", 6, -4)
  e:SetPoint("BOTTOMRIGHT", r.well, "BOTTOMRIGHT", -6, 4)
  e:SetAutoFocus(false)
  if e.SetFontObject then e:SetFontObject("HogTronFontSmall") end
  e:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
  e:SetScript("OnEditFocusGained", function() setBorder(r.well, CYAN) end)
  e:SetScript("OnEditFocusLost", function() setBorder(r.well, LINE) end)
  r.edit = e
  r.apply = flatButton(r, 60, 18)
  r.apply:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 2)
  r.apply.label:SetText("Apply")
  return r
end
fillers.input = function(r, opt, info, width, off)
  local multi = opt.multiline and true or false
  r.label:SetText(tostring(val(opt.name, info) or ""))
  local lh = wrapLabel(r.label, (width or 200) - (multi and 68 or 0))
  r.well:ClearAllPoints()
  r.well:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -(lh + 4))
  r.well:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 6)
  local e = r.edit
  e:SetMultiLine(multi)
  e:SetText(tostring(valM(opt.get, info) or ""))
  if e.SetCursorPosition then e:SetCursorPosition(0) end
  if e.EnableMouse then e:EnableMouse(not off) end
  local function commit()
    call(opt.set, info, e:GetText() or "")
    e:ClearFocus()
    Panel.Refresh()
  end
  e:SetScript("OnEnterPressed", (not multi) and commit or nil)     -- Enter is a newline in a multiline box
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); Panel.Refresh() end)
  if multi then r.apply:Show(); r.apply:SetScript("OnClick", commit) else r.apply:Hide() end
  tooltip(r.well, opt, info)
  return (multi and 110 or 48) + (lh - LINE_H)
end

makers.color = function()
  local r = rowFrame()
  r.button = CreateFrame("Button", nil, r)
  r.button:SetAllPoints(r)
  r.box = CreateFrame("Frame", nil, r)
  r.box:SetSize(28, 16)
  r.box:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -5)
  skin(r.box, RAISED, LINE)
  r.swatch = solid(r.box, "ARTWORK", CYAN)
  r.swatch:SetPoint("TOPLEFT", r.box, "TOPLEFT", 1, -1)
  r.swatch:SetPoint("BOTTOMRIGHT", r.box, "BOTTOMRIGHT", -1, 1)
  labelOn(r):SetPoint("TOPLEFT", r.box, "TOPRIGHT", 8, -1)
  r.button.hover = function(on) setBorder(r.box, on and CYAN or LINE) end
  return r
end
--- Open the game's colour picker. The entry point changed between client generations; support both.
local function pickColor(cr, cg, cb, ca, hasAlpha, apply)
  local cp = ColorPickerFrame
  if not cp then return end
  local function read()
    local nr, ng, nb = cp:GetColorRGB()
    local na = ca
    if hasAlpha then
      if cp.GetColorAlpha then na = cp:GetColorAlpha()
      elseif OpacitySliderFrame then na = 1 - OpacitySliderFrame:GetValue() end
    end
    apply(nr, ng, nb, na)
  end
  local function cancel() apply(cr, cg, cb, ca) end
  if cp.SetupColorPickerAndShow then
    cp:SetupColorPickerAndShow({ r = cr, g = cg, b = cb, opacity = ca, hasOpacity = hasAlpha, swatchFunc = read, opacityFunc = read, cancelFunc = cancel })
  else
    cp.func, cp.opacityFunc, cp.cancelFunc, cp.hasOpacity, cp.opacity = read, read, cancel, hasAlpha, 1 - (ca or 1)
    cp:SetColorRGB(cr, cg, cb)
    cp:Hide(); cp:Show()
  end
end
fillers.color = function(r, opt, info, width, off)
  r.label:SetText(tostring(val(opt.name, info) or ""))
  local lh = wrapLabel(r.label, (width or 200) - 36)
  local cr, cg, cb, ca = valM(opt.get, info)
  cr, cg, cb, ca = tonumber(cr) or 1, tonumber(cg) or 1, tonumber(cb) or 1, tonumber(ca) or 1
  r.swatch:SetColorTexture(cr, cg, cb, 1)
  tooltip(r.button, opt, info)
  r.button:SetScript("OnClick", function()
    if off then return end
    pickColor(cr, cg, cb, ca, opt.hasAlpha and true or false, function(nr, ng, nb, na)
      call(opt.set, info, nr, ng, nb, na)
      r.swatch:SetColorTexture(nr, ng, nb, 1)
    end)
  end)
  return math.max(26, lh + 12)
end

makers.widget = function() return rowFrame() end
fillers.widget = function(r, opt, info, width)
  local h = opt.hhAttach(r, width, info)
  return tonumber(h) or 26
end

local FULL_WIDTH = { header = true, description = true, widget = true }

-- ------------------------------------------------------------------------------------------------ layout
local function place(args, path, y, handler)
  local content = Panel.frame.content
  local total = content:GetWidth() or (W - SIDEBAR - PAD * 2 - 8)
  local cols = Panel.cols or COLS
  local colW = (total - GUTTER * (cols - 1)) / cols
  local col, rowH = 0, 0
  local function newline()
    if col > 0 then y = y + rowH + 6; col, rowH = 0, 0 end
  end
  for _, a in ipairs(args) do
    local opt, p = a.opt, (path ~= "" and (path .. ".") or "") .. a.key
    local info = mkInfo(p, opt, handler)
    if not valM(opt.hidden, info) then
      if opt.type == "group" then
        -- A group nested below tab level (inline or not) is flattened in place under its own heading.
        newline()
        local h = acquire("header", makers.header)
        h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        h:SetWidth(total)
        local hh = fillers.header(h, opt, info)
        h:SetHeight(hh)
        y = y + hh + 6
        y = place(sortedArgs(opt), p, y, opt.handler or handler)
      elseif fillers[opt.type] then
        local kind = (type(opt.hhAttach) == "function") and "widget" or opt.type
        local full = FULL_WIDTH[kind] or opt.width == "full" or opt.multiline
        if full then newline() end
        local row = acquire(kind, makers[kind])
        local w = full and total or colW
        row:SetPoint("TOPLEFT", content, "TOPLEFT", full and 0 or col * (colW + GUTTER), -y)
        row:SetWidth(w)
        local off = valM(opt.disabled, info) and true or false
        local ok, h = pcall(fillers[kind], row, opt, info, w, off)
        if not ok then HH:LogError("options " .. p .. ": " .. tostring(h)); h = 26 end
        row:SetHeight(h)
        dim(row, off)
        Panel.controls[p] = row
        if full then
          y = y + h + 6
        else
          rowH = math.max(rowH, h)
          col = col + 1
          if col >= cols then newline() end
        end
      end
    end
  end
  newline()
  return y
end

local function navButton(i)
  local b = navPool[i]
  if b then return b end
  b = CreateFrame("Button", nil, Panel.frame.side)
  b:SetHeight(30)
  b:SetPoint("TOPLEFT", Panel.frame.side, "TOPLEFT", 0, -10 - (i - 1) * 32)
  b:SetPoint("RIGHT", Panel.frame.side, "RIGHT", 0, 0)
  b.bg = solid(b, "BACKGROUND", CYAN, 0.12)
  b.bg:SetAllPoints(b)
  b.mark = solid(b, "ARTWORK", CYAN)
  b.mark:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  b.mark:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  b.mark:SetWidth(3)
  b.label = text(b, "HogTronFontHighlight", CREAM, "LEFT")
  b.label:SetPoint("LEFT", b, "LEFT", PAD, 0)
  b:SetScript("OnClick", function(self) Panel.Select(self.key) end)
  navPool[i] = b
  return b
end

local function tabButton(i)
  local b = tabPool[i]
  if b then return b end
  b = CreateFrame("Button", nil, Panel.frame.tabbar)
  b:SetHeight(26)
  b.label = text(b, "HogTronFontSmall", CREAM)
  b.label:SetPoint("CENTER", b, "CENTER", 0, 1)
  b.mark = solid(b, "ARTWORK", CYAN)
  b.mark:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  b.mark:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  b.mark:SetHeight(2)
  b:SetScript("OnClick", function(self) Panel.SelectTab(self.key) end)
  tabPool[i] = b
  return b
end

local function visibleGroups(group, path)
  local out = {}
  for _, a in ipairs(sortedArgs(group)) do
    if a.opt.type == "group" and not a.opt.inline then
      local p = (path ~= "" and (path .. ".") or "") .. a.key
      if not valM(a.opt.hidden, mkInfo(p, a.opt)) then out[#out + 1] = a end
    end
  end
  return out
end

local function plainArgs(group)
  local out = {}
  for _, a in ipairs(sortedArgs(group)) do
    if a.opt.type ~= "group" or a.opt.inline then out[#out + 1] = a end
  end
  return out
end

--- Rebuild the whole window from the options table. Cheap (a few dozen rows) and always correct.
function Panel.Refresh()
  local f = Panel.frame
  if not f or not f:IsShown() then return end
  if Panel.menu then Panel.menu:Hide() end
  local ok, root = pcall(Panel.source or HH.OptionsTable)
  if not ok or type(root) ~= "table" then HH:LogError("options table: " .. tostring(root)) return end
  releaseAll()

  local tops = visibleGroups(root, "")
  local current
  for _, a in ipairs(tops) do if a.key == Panel.selected then current = a end end
  current = current or tops[1]
  Panel.selected = current and current.key or nil
  for _, b in ipairs(navPool) do b:Hide() end
  Panel.nav = {}
  for i, a in ipairs(tops) do
    local b = navButton(i)
    Panel.nav[i] = b
    b.key = a.key
    b.label:SetText(tostring(val(a.opt.name, mkInfo(a.key, a.opt)) or a.key))
    local on = a.key == Panel.selected
    if on then b.bg:Show(); b.mark:Show() else b.bg:Hide(); b.mark:Hide() end
    local c = on and CYAN or CREAM
    b.label:SetTextColor(c[1], c[2], c[3])
    b:Show()
  end

  local y = 0
  local subs = current and visibleGroups(current.opt, current.key) or {}
  local tab
  for _, a in ipairs(subs) do if a.key == Panel.selectedTab then tab = a end end
  tab = tab or subs[1]
  Panel.selectedTab = tab and tab.key or nil
  for _, b in ipairs(tabPool) do b:Hide() end
  Panel.tabs = {}
  local x, rowN = 0, 0
  local avail = Panel.ContentWidth() + 8
  for i, a in ipairs(subs) do
    local b = tabButton(i)
    Panel.tabs[i] = b
    b.key = a.key
    local label = tostring(val(a.opt.name, mkInfo(current.key .. "." .. a.key, a.opt)) or a.key)
    b.label:SetText(label)
    local w = math.max(70, (b.label:GetStringWidth() or (#label * 7)) + 24)
    if x > 0 and x + w > avail then x, rowN = 0, rowN + 1 end   -- the row is full: the next tab starts a new one
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f.tabbar, "TOPLEFT", x, -rowN * (TAB_H + 2))
    b:SetWidth(w)
    b.row = rowN
    x = x + w + 4
    local on = a.key == Panel.selectedTab
    if on then b.mark:Show() else b.mark:Hide() end
    local c = on and CYAN or GREY
    b.label:SetTextColor(c[1], c[2], c[3])
    b:Show()
  end
  Panel.tabRows = #subs > 0 and rowN + 1 or 0
  -- a page without tabs gets no empty tab row above it (Sean 2026-10-16: the setup guide had a band of nothing on top)
  f.tabbar:SetHeight(Panel.tabRows > 0 and math.max(TAB_H, Panel.tabRows * (TAB_H + 2) - 2) or 1)

  if current then
    local h1 = current.opt.handler or root.handler
    y = place(plainArgs(current.opt), current.key, y, h1)
    if tab then y = place(sortedArgs(tab.opt), current.key .. "." .. tab.key, y, tab.opt.handler or h1) end
  end
  f.content:SetHeight(math.max(10, y + PAD))
  local max = f.scroll:GetVerticalScrollRange() or 0
  if (f.scroll:GetVerticalScroll() or 0) > max then f.scroll:SetVerticalScroll(max) end
end

function Panel.Select(key)
  if key ~= Panel.selected then Panel.selectedTab = nil end
  Panel.selected = key
  if Panel.frame then Panel.frame.scroll:SetVerticalScroll(0) end
  Panel.Refresh()
end

function Panel.SelectTab(key)
  Panel.selectedTab = key
  if Panel.frame then Panel.frame.scroll:SetVerticalScroll(0) end
  Panel.Refresh()
end

--- Full window (sidebar, two columns, centred) or compact (one section, one column, beside a frame: edit mode).
-- opts = { compact = true, anchor = frame, title = "Action bar 2" }
--- Which side of a frame the compact window goes on: the side facing the middle of the screen, on the axis the
-- frame is further from the middle on (a bar along the bottom -> above it; a bar on the right edge -> left of it;
-- a unit frame left of centre -> right of it). Sean 2026-10-08: "should not open over the bars ... open towards the
-- center". The other axis is the fallback when there is no room; nil = no idea (no centre), caller centres it.
-- cx, cy = the frame's centre; aw, ah = its size; sw, sh = the screen; cw, ch = the window's size.
function Panel.Side(cx, cy, aw, ah, sw, sh, cw, ch)
  if type(cx) ~= "number" or type(cy) ~= "number" then return nil end
  aw, ah = aw or 0, ah or 0
  sw, sh = sw or 1920, sh or 1080
  cw, ch = cw or CW, ch or CH
  local dx, dy = sw / 2 - cx, sh / 2 - cy
  local h = dx >= 0 and "right" or "left"
  local v = dy >= 0 and "above" or "below"
  local roomH = dx >= 0 and (sw - (cx + aw / 2)) or (cx - aw / 2)
  local roomV = dy >= 0 and (sh - (cy + ah / 2)) or (cy - ah / 2)
  local first, second = h, v
  local roomFirst, roomSecond = roomH, roomV
  if math.abs(dy) / sh >= math.abs(dx) / sw then first, second, roomFirst, roomSecond = v, h, roomV, roomH end
  local need = { above = ch + 12, below = ch + 12, left = cw + 12, right = cw + 12 }
  if roomFirst >= need[first] then return first end
  if roomSecond >= need[second] then return second end
  return roomFirst >= roomSecond and first or second
end

function Panel.Layout(opts)
  local f = Panel.frame
  opts = opts or {}
  local was = Panel.compact
  Panel.compact = opts.compact and true or false
  f.tabbar:ClearAllPoints()
  Panel.actions = opts.actions
  if Panel.compact then
    f:SetSize(Panel.Size())
    f.side:Hide()
    f.tabbar:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(TITLE + 10))
    f.content:SetWidth(Panel.ContentWidth())
    Panel.cols = 1
    f.version:SetText(opts.title or "")
    f:ClearAllPoints()
    local a = opts.anchor
    local side
    if a and a.GetCenter then
      local ok, cx, cy = pcall(a.GetCenter, a)
      local s = (a.GetEffectiveScale and a:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
      local sw = (type(GetScreenWidth) == "function" and GetScreenWidth()) or 1920
      local sh = (type(GetScreenHeight) == "function" and GetScreenHeight()) or 1080
      if ok and type(cx) == "number" and type(cy) == "number" then
        local aw = (a.GetWidth and a:GetWidth() or 0) * s
        local ah = (a.GetHeight and a:GetHeight() or 0) * s
        side = Panel.Side(cx * s, cy * s, aw, ah, sw, sh)
      end
    end
    Panel.side = side
    if side == "above" then f:SetPoint("BOTTOM", a, "TOP", 0, 12)
    elseif side == "below" then f:SetPoint("TOP", a, "BOTTOM", 0, -12)
    elseif side == "right" then f:SetPoint("LEFT", a, "RIGHT", 12, 0)
    elseif side == "left" then f:SetPoint("RIGHT", a, "LEFT", -12, 0)
    else f:SetPoint("CENTER", UIParent, "CENTER", 0, 20) end
  else
    f:SetSize(Panel.Size())
    f.side:Show()
    f.tabbar:SetPoint("TOPLEFT", f.side, "TOPRIGHT", PAD, -10)
    f.content:SetWidth(Panel.ContentWidth())
    Panel.cols = Panel.ContentWidth() < 560 and 1 or nil
    f.version:SetText("v" .. tostring(HH.version or "dev"))
    if was then f:ClearAllPoints() f:SetPoint("CENTER", UIParent, "CENTER", 0, 20) end
  end
  f.tabbar:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
  if f.SetResizeBounds then pcall(f.SetResizeBounds, f, Panel.compact and MIN_CW or MIN_W, Panel.compact and MIN_CH or MIN_H)
  elseif f.SetMinResize then pcall(f.SetMinResize, f, Panel.compact and MIN_CW or MIN_W, Panel.compact and MIN_CH or MIN_H) end
  Panel.LayoutFooter()
end

--- Quick actions for a module's compact window (its footer), by the key the tray / edit mode uses. Sean 2026-10-08:
-- "there should just be a test button built right into here" (the party / raid frames).
function Panel.ActionsFor(key)
  local acts = {}
  if key == "frames" then
    local F = rawget(_G, "HogHealsFrames")
    local TM = type(F) == "table" and F.TestMode or nil
    if TM and TM.Start then
      acts[#acts + 1] = { text = "Test 5", func = function() TM.Start(5) end }
      acts[#acts + 1] = { text = "Test 25", func = function() TM.Start(25) end }
      acts[#acts + 1] = { text = "Stop test", func = function() if TM.Stop then TM.Stop() end end }
    end
  elseif key == "bars" then
    acts[#acts + 1] = { text = "Key binds", func = function() HH:SlashCommand("bind") end }
  elseif key == "units" or key == "hud" or key == "menu" or key == "tips" or key == "tooltip" or key == "infobar" or key == "xp" then
    acts[#acts + 1] = { text = function() return HH.db.profile.locked and "Unlock to drag" or "Lock" end,
      func = function() HH:SlashCommand(HH.db.profile.locked and "unlock" or "lock") end }
  end
  return #acts > 0 and acts or nil
end

--- The compact window's footer: one flat button per action ({ text, func }); none = no footer, the scroll runs to
-- the bottom edge.
function Panel.LayoutFooter()
  local f = Panel.frame
  local acts = Panel.compact and Panel.actions or nil
  f.scroll:ClearAllPoints()
  f.scroll:SetPoint("TOPLEFT", f.tabbar, "BOTTOMLEFT", 0, -10)
  if not acts or #acts == 0 then
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
    f.footer:Hide()
    for _, b in ipairs(f.footer.buttons) do b:Hide() end
    return 0
  end
  f.scroll:SetPoint("BOTTOMRIGHT", f.footer, "TOPRIGHT", 0, 6)
  local w = Panel.Size()
  local n = #acts
  local bw = math.floor((w - PAD * 2 - 6 * (n - 1)) / n)
  for i, a in ipairs(acts) do
    local b = f.footer.buttons[i]
    if not b then
      b = flatButton(f.footer, bw, FOOTER_H - 6)
      f.footer.buttons[i] = b
    end
    b:SetSize(bw, FOOTER_H - 6)
    b:ClearAllPoints()
    b:SetPoint("LEFT", f.footer, "LEFT", (i - 1) * (bw + 6), 0)
    b.label:SetText(tostring(type(a.text) == "function" and a.text() or a.text))
    b:SetScript("OnClick", function()
      local ok, err = pcall(a.func)
      if not ok then HH:LogError("panel action " .. tostring(a.text) .. ": " .. tostring(err)) end
      Panel.LayoutFooter()   -- a label can change with the state (Lock / Unlock)
    end)
    b:Show()
  end
  for i = n + 1, #f.footer.buttons do f.footer.buttons[i]:Hide() end
  f.footer:Show()
  return n
end

--- Open the window. source = optional function returning an options table (defaults to the live HogHeals one);
-- opts = Panel.Layout's (compact edit-mode form).
function Panel.Open(source, opts)
  Panel.source = source
  local f = build()
  Panel.Layout(opts)
  f:Show()
  Panel.Refresh()
  return f
end

function Panel.Toggle()
  if Panel.frame and Panel.frame:IsShown() then Panel.frame:Hide() else Panel.Open() end
end
