-- In-game widget for the Click-cast tab: the 5x5 slot grid, the spell picker (right-click a slot), the rank dropdown
-- and the "Resurrect if dead" checkbox. Draws ONLY from ClickGrid.ViewModel(); every click calls a ClickGrid action
-- and redraws. Hosted by the options window (Core/Panel.lua) through an option with hhAttach.
-- Plain insecure frames: this edits saved data; ClickGrid writes the secure attributes (out of combat).
HogHealsFrames = HogHealsFrames or {}
local HHF = HogHealsFrames
local HH = HogHeals

local UI = {}
HHF.ClickGridUI = UI

local CREAM, CYAN, GREY, AMBER = { 0.96, 0.92, 0.86 }, { 0.13, 0.83, 0.88 }, { 0.45, 0.45, 0.5 }, { 0.96, 0.65, 0.14 }
local RAISED, LINE, WELL = { 0.11, 0.11, 0.14 }, { 0.20, 0.20, 0.25 }, { 0.05, 0.05, 0.065 }
local LABEL_W, HEAD_H, CELL_H, GAP, EDITOR_H, PICK_ROWS, ROW_H = 78, 20, 40, 4, 112, 12, 20

local function solid(parent, layer, c, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  return t
end

local function box(f, fill, border)
  f.fill = f.fill or solid(f, "BACKGROUND", fill)
  f.fill:SetAllPoints(f)
  f.fill:SetColorTexture(fill[1], fill[2], fill[3], 1)
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

local function edge(f, c) for _, e in ipairs(f.edges or {}) do e:SetColorTexture(c[1], c[2], c[3], 1) end end

local function text(parent, template, c, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  c = c or CREAM
  fs:SetTextColor(c[1], c[2], c[3])
  if justify then fs:SetJustifyH(justify) end
  return fs
end

local function flat(parent, w, h, label)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  box(b, RAISED, LINE)
  b.label = text(b)
  b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.label:SetText(label or "")
  b:SetScript("OnEnter", function() edge(b, CYAN) end)
  b:SetScript("OnLeave", function() edge(b, LINE) end)
  return b
end

local function changed()
  local P = HH.Panel
  if P and P.frame and P.frame:IsShown() and P.Refresh then P.Refresh() else UI.Update() end
end

-- ------------------------------------------------------------------------------------------------ build
local function buildCell(parent)
  local c = CreateFrame("Button", nil, parent)
  box(c, RAISED, LINE)
  if c.RegisterForClicks then c:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  c.icon = c:CreateTexture(nil, "ARTWORK")
  c.icon:SetSize(30, 30)
  c.icon:SetPoint("LEFT", c, "LEFT", 5, 0)
  c.name = text(c, "GameFontHighlightSmall", CREAM, "LEFT")
  c.name:SetPoint("TOPLEFT", c, "TOPLEFT", 40, -6)
  c.name:SetPoint("RIGHT", c, "RIGHT", -4, 0)
  c.sub = text(c, "GameFontDisableSmall", GREY, "LEFT")
  c.sub:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 40, 6)
  c.sub:SetPoint("RIGHT", c, "RIGHT", -4, 0)
  c.rez = text(c, "GameFontHighlightSmall", CYAN, "RIGHT")
  c.rez:SetPoint("TOPRIGHT", c, "TOPRIGHT", -4, -4)
  c:SetScript("OnClick", function(self, mouse)
    local G = HHF.ClickGrid
    if G.controlledBy == "Clique" then return end
    if mouse == "RightButton" or self.empty then G.OpenPicker(self.key) else G.Select(self.key) end
    changed()
  end)
  c:SetScript("OnEnter", function(self)
    edge(self, CYAN)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(HHF.ClickGrid.SlotLabel(self.key), CYAN[1], CYAN[2], CYAN[3])
    GameTooltip:AddLine(self.macro or "Right-click to pick a spell.", CREAM[1], CREAM[2], CREAM[3], true)
    GameTooltip:Show()
  end)
  c:SetScript("OnLeave", function(self) edge(self, self.isSelected and CYAN or LINE); if GameTooltip then GameTooltip:Hide() end end)
  return c
end

local function buildEditor(parent)
  local e = CreateFrame("Frame", nil, parent)
  box(e, WELL, LINE)
  e.title = text(e, "GameFontNormalSmall", CYAN, "LEFT")
  e.title:SetPoint("TOPLEFT", e, "TOPLEFT", 10, -8)
  e.rankLabel = text(e, "GameFontHighlightSmall", GREY, "LEFT")
  e.rankLabel:SetPoint("TOPLEFT", e, "TOPLEFT", 10, -28)
  e.rankLabel:SetText("Rank")
  e.rank = flat(e, 220, 22)
  e.rank:SetPoint("TOPLEFT", e, "TOPLEFT", 10, -44)
  e.rank.label:ClearAllPoints()
  e.rank.label:SetPoint("LEFT", e.rank, "LEFT", 8, 0)
  e.rank.arrow = text(e.rank, "GameFontHighlightSmall", CYAN)
  e.rank.arrow:SetPoint("RIGHT", e.rank, "RIGHT", -8, 0)
  e.rank.arrow:SetText("v")
  e.rank:SetScript("OnClick", function()
    local G = HHF.ClickGrid
    if G.ui.rankMenuFor then G.CloseMenus() else G.OpenRankMenu(e.key) end
    changed()
  end)
  e.rezBtn = CreateFrame("Button", nil, e)
  e.rezBtn:SetSize(260, 20)
  e.rezBtn:SetPoint("TOPLEFT", e, "TOPLEFT", 250, -45)
  e.rezBox = CreateFrame("Frame", nil, e.rezBtn)
  e.rezBox:SetSize(16, 16)
  e.rezBox:SetPoint("LEFT", e.rezBtn, "LEFT", 0, 0)
  box(e.rezBox, RAISED, LINE)
  e.rezTick = solid(e.rezBox, "ARTWORK", CYAN)
  e.rezTick:SetPoint("TOPLEFT", e.rezBox, "TOPLEFT", 3, -3)
  e.rezTick:SetPoint("BOTTOMRIGHT", e.rezBox, "BOTTOMRIGHT", -3, 3)
  e.rezText = text(e.rezBtn, "GameFontHighlightSmall", CREAM, "LEFT")
  e.rezText:SetPoint("LEFT", e.rezBox, "RIGHT", 8, 0)
  e.rezBtn:SetScript("OnClick", function()
    HHF.ClickGrid.SetRez(e.key, not e.rezOn)
    changed()
  end)
  e.macro = text(e, "GameFontDisableSmall", GREY, "LEFT")
  e.macro:SetPoint("TOPLEFT", e, "TOPLEFT", 10, -76)
  e.macro:SetPoint("RIGHT", e, "RIGHT", -10, 0)
  e.change = flat(e, 110, 22, "Change spell")
  e.change:SetPoint("TOPRIGHT", e, "TOPRIGHT", -10, -6)
  e.change:SetScript("OnClick", function() HHF.ClickGrid.OpenPicker(e.key); changed() end)
  e.clear = flat(e, 90, 22, "Clear slot")
  e.clear:SetPoint("RIGHT", e.change, "LEFT", -6, 0)
  e.clear:SetScript("OnClick", function() HHF.ClickGrid.Clear(e.key); changed() end)
  return e
end

local function popup(name)
  local m = CreateFrame("Frame", name, UIParent)
  m:SetFrameStrata("FULLSCREEN_DIALOG")
  box(m, RAISED, CYAN)
  m.rows = {}
  m:Hide()
  return m
end

local function popupRow(m, i)
  local it = m.rows[i]
  if it then return it end
  it = CreateFrame("Button", nil, m)
  it:SetHeight(ROW_H)
  it.bg = solid(it, "BACKGROUND", CYAN, 0.18)
  it.bg:SetAllPoints(it)
  it.bg:Hide()
  it.icon = it:CreateTexture(nil, "ARTWORK")
  it.icon:SetSize(16, 16)
  it.icon:SetPoint("LEFT", it, "LEFT", 6, 0)
  it.label = text(it, "GameFontHighlightSmall", CREAM, "LEFT")
  it.label:SetPoint("LEFT", it, "LEFT", 28, 0)
  it.sub = text(it, "GameFontDisableSmall", GREY, "RIGHT")
  it.sub:SetPoint("RIGHT", it, "RIGHT", -8, 0)
  it:SetScript("OnEnter", function(self) self.bg:Show() end)
  it:SetScript("OnLeave", function(self) self.bg:Hide() end)
  m.rows[i] = it
  return it
end

function UI.Build()
  if UI.frame then return UI.frame end
  local f = CreateFrame("Frame", "HogHealsClickGrid", UIParent)
  f:Hide()
  f.colHeads, f.rowHeads, f.cells = {}, {}, {}
  for i = 1, 5 do
    f.colHeads[i] = text(f, "GameFontNormalSmall", CYAN, "CENTER")
    f.rowHeads[i] = text(f, "GameFontHighlightSmall", CREAM, "LEFT")
    f.cells[i] = {}
    for j = 1, 5 do f.cells[i][j] = buildCell(f) end
  end
  f.blocked = text(f, "GameFontNormal", AMBER, "CENTER")
  f.editor = buildEditor(f)
  UI.picker = popup("HogHealsClickGridPicker")
  UI.picker.title = text(UI.picker, "GameFontNormalSmall", CYAN, "LEFT")
  UI.picker.title:SetPoint("TOPLEFT", UI.picker, "TOPLEFT", 8, -6)
  UI.picker:EnableMouseWheel(true)
  UI.picker:SetScript("OnMouseWheel", function(_, delta)
    local G = HHF.ClickGrid
    G.ui.pickerOffset = math.max(0, (G.ui.pickerOffset or 0) - delta * 3)
    UI.Update()
  end)
  UI.rankMenu = popup("HogHealsClickGridRankMenu")
  -- Popups live on UIParent (the options page scrolls and would clip them); they hide with the grid. The open/closed
  -- STATE stays in ClickGrid.ui: every options rebuild hides and re-attaches the grid, and must not close the picker.
  f:SetScript("OnHide", function() UI.HidePopups() end)
  UI.frame = f
  return f
end

--- Size for a given width (the options window asks before placing the next row).
function UI.Height(vm)
  vm = vm or HHF.ClickGrid.ViewModel()
  return HEAD_H + 5 * (CELL_H + GAP) + (vm.editor and (EDITOR_H + GAP) or 0)
end

--- Panel hook: put the widget inside an options row; returns the row height.
function UI.Attach(row, width)
  local f = UI.Build()
  f:SetParent(row)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  f.width = width or 640
  f:SetSize(f.width, 10)
  f:Show()
  return UI.Update()
end

-- ------------------------------------------------------------------------------------------------ draw
function UI.Update()
  local f = UI.frame
  if not f then return 0 end
  local G = HHF.ClickGrid
  local vm = G.ViewModel()
  UI.lastVM = vm
  local width = f.width or 640
  local top = 0                         -- the Clique notice is the tab's own description row, above the grid
  f.blocked:ClearAllPoints()
  f.blocked:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -6)
  f.blocked:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  f.blocked:SetText("")
  local cellW = math.floor((width - LABEL_W - GAP * 5) / 5)
  for j, col in ipairs(vm.columns) do
    local h = f.colHeads[j]
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", f, "TOPLEFT", LABEL_W + GAP + (j - 1) * (cellW + GAP), -top)
    h:SetWidth(cellW)
    h:SetText(col.label)
  end
  for i, row in ipairs(vm.rows) do
    local y = top + HEAD_H + (i - 1) * (CELL_H + GAP)
    local rh = f.rowHeads[i]
    rh:ClearAllPoints()
    rh:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(y + 13))
    rh:SetText(row.label)
    for j, cell in ipairs(row.cells) do
      local c = f.cells[i][j]
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", f, "TOPLEFT", LABEL_W + GAP + (j - 1) * (cellW + GAP), -y)
      c:SetSize(cellW, CELL_H)
      c.key, c.empty, c.macro, c.isSelected = cell.key, cell.empty, cell.macro, cell.selected
      if cell.empty then
        c.icon:Hide()
        c.name:SetText(cell.fallback and ("|cff737380(" .. cell.fallback .. ")|r") or "")
        c.sub:SetText("")
        c.rez:SetText("")
      else
        c.icon:SetTexture(cell.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        c.icon:Show()
        c.name:SetText(cell.spell or "?")
        c.sub:SetText(cell.rankText or "")
        c.rez:SetText(cell.rezActive and "+rez" or "")
      end
      c:SetAlpha((vm.disabled or (not cell.empty and not cell.known)) and 0.45 or 1)
      edge(c, cell.selected and CYAN or LINE)
    end
  end
  local h = top + HEAD_H + 5 * (CELL_H + GAP)
  local e = f.editor
  if vm.editor then
    local ed = vm.editor
    e:ClearAllPoints()
    e:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -h)
    e:SetSize(width, EDITOR_H)
    e.key, e.rezOn = ed.key, ed.rez
    e.title:SetText(ed.title)
    e.rank.label:SetText(ed.rankLabel)
    if ed.rez then e.rezTick:Show() else e.rezTick:Hide() end
    e.rezText:SetText(ed.rezSpell and ("Resurrect if dead (" .. ed.rezSpell .. ", out of combat)")
      or "Resurrect if dead (no rez spell learned yet: skipped)")
    e.macro:SetText(ed.macro and ("Macro: " .. ed.macro) or "Not castable yet: spell or rank not learned.")
    e:Show()
    h = h + GAP + EDITOR_H
  else
    e:Hide()
  end
  UI.DrawPicker(vm)
  UI.DrawRankMenu(vm)
  f:SetHeight(h)
  return h
end

local function cellFor(key)
  for i = 1, 5 do for j = 1, 5 do
    local c = UI.frame.cells[i][j]
    if c.key == key then return c end
  end end
end

function UI.DrawPicker(vm)
  local m = UI.picker
  for _, it in ipairs(m.rows) do it:Hide() end
  if not vm.picker then m:Hide() return end
  local p = vm.picker
  m.title:SetText(p.title)
  local list = { { name = nil, label = "(empty: clear this slot)" } }
  for _, e in ipairs(p.entries) do list[#list + 1] = { name = e.name, label = e.name, icon = e.icon, sub = e.rankText } end
  local offset = math.min(p.offset or 0, math.max(0, #list - PICK_ROWS))
  local shown = math.min(PICK_ROWS, #list - offset)
  for i = 1, shown do
    local d = list[offset + i]
    local it = popupRow(m, i)
    it:ClearAllPoints()
    it:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -22 - (i - 1) * ROW_H)
    it:SetWidth(278)
    it.label:SetText(d.label)
    it.sub:SetText(d.sub or "")
    if d.icon then it.icon:SetTexture(d.icon); it.icon:Show() else it.icon:Hide() end
    it:SetScript("OnClick", function() HHF.ClickGrid.Pick(p.key, d.name); changed() end)
    it:Show()
  end
  m:SetSize(280, 24 + shown * ROW_H + 2)
  m:ClearAllPoints()
  local c = cellFor(p.key)
  if c then m:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 0, -2) else m:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
  m:Show()
end

function UI.DrawRankMenu(vm)
  local m = UI.rankMenu
  for _, it in ipairs(m.rows) do it:Hide() end
  if not vm.rankMenu then m:Hide() return end
  local r = vm.rankMenu
  for i, e in ipairs(r.entries) do
    local it = popupRow(m, i)
    it:ClearAllPoints()
    it:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -1 - (i - 1) * ROW_H)
    it:SetWidth(258)
    it.icon:Hide()
    it.label:SetText(e.label)
    local c = (e.key == r.current) and CYAN or CREAM
    it.label:SetTextColor(c[1], c[2], c[3])
    it.sub:SetText("")
    it:SetScript("OnClick", function() HHF.ClickGrid.SetRank(r.key, e.key); changed() end)
    it:Show()
  end
  m:SetSize(260, #r.entries * ROW_H + 2)
  m:ClearAllPoints()
  m:SetPoint("TOPLEFT", UI.frame.editor.rank, "BOTTOMLEFT", 0, -2)
  m:Show()
end

--- Hide the floating popups (options window closed / tab left).
function UI.HidePopups()
  if UI.picker then UI.picker:Hide() end
  if UI.rankMenu then UI.rankMenu:Hide() end
end
