-- Window: the journal frame. Standalone (not inside the Group Finder, so Blizzard UI changes do not break it).
--   left pane    the bosses of the dungeon (or the quests, or the list of dungeons when none is chosen)
--   right pane   the detail of the selected row: dispels, pre-shields, interrupts, damage load, healer tips
--   bottom       tabs: Bosses | Quests, and a footer that says where the data comes from
-- Every string uses a HogTronFont object (Core/Look.lua), so the Look switch restyles it and the strict-font client
-- never sees a font string without a font.
local J = HogHealsJournal
local HH = HogHeals

local Window = { tab = "bosses", boss = 1, quest = 1 }
J.Window = Window

local C = J.COLORS
local W, H = 760, 470
local TOP, PAD = 30, 10
local LEFT_W = 230
local LEFT_ROWS, LEFT_ROW_H = 20, 19
local RIGHT_ROWS, RIGHT_ROW_H = 24, 15
local TABS = { { "bosses", "Bosses" }, { "quests", "Quests" } }

local function fs(parent, color, justify, template)
  local t = parent:CreateFontString(nil, "OVERLAY", template or "HogTronFontSmall")
  t:SetTextColor(color[1], color[2], color[3])
  t:SetJustifyH(justify or "LEFT")
  if t.SetWordWrap then t:SetWordWrap(false) end
  return t
end

local function tex(parent, layer, color, alpha)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(color[1], color[2], color[3], alpha or 1)
  return t
end

-- ------------------------------------------------------------------------------------------------ build
function Window.Build()
  if Window.frame then return Window.frame end
  local f = CreateFrame("Frame", "HogTronUIJournal", UIParent)
  f:SetSize(W, H)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f:SetScale(J.cfg().scale or 1)

  f.bg = tex(f, "BACKGROUND", C.ink, 0.94)
  f.bg:SetAllPoints(f)
  f.rule = tex(f, "ARTWORK", C.cyan)
  f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -TOP + 6)
  f.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -TOP + 6)
  f.rule:SetHeight(1)
  f.title = fs(f, C.cream, "LEFT", "HogTronFontNormal")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -7)
  f.title:SetText("|cffF5EBDCHOG|r|cff21D4E0TRON UI|r  JOURNAL")
  f.sub = fs(f, C.grey, "RIGHT")
  f.sub:SetPoint("TOPRIGHT", f, "TOPRIGHT", -34, -9)
  f.sub:SetText("")

  f.close = CreateFrame("Button", nil, f)
  f.close:SetSize(24, 20)
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -3)
  f.close.label = fs(f.close, C.cream, "CENTER")
  f.close.label:SetPoint("CENTER", f.close, "CENTER", 0, 0)
  f.close.label:SetText("x")
  f.close:SetScript("OnClick", function() f:Hide() end)

  -- left pane
  f.leftBg = tex(f, "BORDER", C.panel, 0.9)
  f.leftBg:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -TOP - 4)
  f.leftBg:SetSize(LEFT_W, LEFT_ROWS * LEFT_ROW_H + 8)
  f.left = {}
  for i = 1, LEFT_ROWS do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(LEFT_W - 8, LEFT_ROW_H)
    b:SetPoint("TOPLEFT", f.leftBg, "TOPLEFT", 4, -4 - (i - 1) * LEFT_ROW_H)
    b.sel = tex(b, "BACKGROUND", C.cyan, 0.18)
    b.sel:SetAllPoints(b)
    b.sel:Hide()
    b.label = fs(b, C.cream, "LEFT")
    b.label:SetPoint("LEFT", b, "LEFT", 6, 0)
    b.label:SetPoint("RIGHT", b, "RIGHT", -52, 0)
    b.right = fs(b, C.grey, "RIGHT")
    b.right:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    b.right:SetWidth(46)
    b:SetScript("OnClick", function() Window.ClickLeft(i) end)
    b:Hide()
    f.left[i] = b
  end

  -- right pane
  f.rightBg = tex(f, "BORDER", C.panel, 0.6)
  f.rightBg:SetPoint("TOPLEFT", f.leftBg, "TOPRIGHT", PAD, 0)
  f.rightBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 34)
  f.right = {}
  for i = 1, RIGHT_ROWS do
    local t = fs(f, C.cream, "LEFT")
    t:SetPoint("TOPLEFT", f.rightBg, "TOPLEFT", 8, -8 - (i - 1) * RIGHT_ROW_H)
    t:SetPoint("RIGHT", f.rightBg, "RIGHT", -8, 0)
    t:Hide()
    f.right[i] = t
  end

  -- tabs + footer
  f.tabs = {}
  for n, tab in ipairs(TABS) do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(90, 20)
    b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD + (n - 1) * 96, 8)
    b.bg = tex(b, "BACKGROUND", C.panel, 0.9)
    b.bg:SetAllPoints(b)
    b.line = tex(b, "ARTWORK", C.cyan)
    b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    b.line:SetHeight(2)
    b.label = fs(b, C.cream, "CENTER")
    b.label:SetPoint("CENTER", b, "CENTER", 0, 1)
    b.label:SetText(tab[2])
    b:SetScript("OnClick", function() Window.SetTab(tab[1]) end)
    f.tabs[tab[1]] = b
  end
  f.footer = fs(f, C.grey, "RIGHT")
  f.footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 11)
  f.footer:SetPoint("LEFT", f, "LEFT", PAD + #TABS * 96 + 10, 0)
  f.footer:SetText("")

  local special = rawget(_G, "UISpecialFrames")
  if type(special) == "table" then special[#special + 1] = "HogTronUIJournal" end
  f:Hide()
  Window.frame = f
  return f
end

-- ------------------------------------------------------------------------------------------------ rows
--- Left-pane rows for the current state. Pure given the state: used by the tests through Window.leftRows.
function Window.LeftRows()
  local rows = {}
  local d = Window.dungeon
  if not d then
    for _, dd in ipairs(J.Dungeons()) do
      rows[#rows + 1] = { kind = "dungeon", key = dd.key, text = dd.name, right = dd.levels or "", color = C.cream }
    end
    if #rows == 0 then rows[1] = { kind = "none", text = "No dungeons shipped yet.", color = C.grey } end
    return rows
  end
  if Window.tab == "quests" then
    local qrows = J.QuestRows(d)
    Window.questRows = qrows
    for i, r in ipairs(qrows) do
      local color = r.state == "ready" and C.green or r.state == "active" and C.amber or r.state == "other" and C.grey or C.cream
      rows[#rows + 1] = { kind = "quest", index = i, text = r.title, right = r.progress or (r.state == "ready" and "ready" or r.state == "other" and "other side" or ""),
        color = color, selected = Window.quest == i }
    end
    if #rows == 0 then rows[1] = { kind = "none", text = "No quests listed for this dungeon.", color = C.grey } end
    return rows
  end
  for i, b in ipairs(d.bosses or {}) do
    rows[#rows + 1] = { kind = "boss", index = i, text = b.name, right = b.optional and "opt" or "", color = b.optional and C.grey or C.cream, selected = Window.boss == i }
  end
  for i, t in ipairs(d.trash or {}) do
    rows[#rows + 1] = { kind = "trash", index = i, text = t.name, right = "trash", color = C.grey, selected = Window.boss == #d.bosses + i }
  end
  if #rows == 0 then rows[1] = { kind = "none", text = "No bosses written for this dungeon yet.", color = C.grey } end
  return rows
end

--- Right-pane rows for the current state.
function Window.RightRows()
  local d = Window.dungeon
  if not d then
    local out = { { text = "Pick a dungeon on the left.", color = C.cream, head = true } }
    local where = J.Where()
    if where then
      out[#out + 1] = { text = "", color = C.cream }
      for _, l in ipairs(J.Wrap(("You are in %s (id %s): no data for this dungeon yet. It opens again by itself when a page is written for it."):format(
        tostring(where.name or "an instance"), tostring(where.inst or "?")), 64)) do out[#out + 1] = { text = l, color = C.amber } end
    end
    for _, l in ipairs(J.Compat.Degraded()) do
      out[#out + 1] = { text = "", color = C.cream }
      for _, w in ipairs(J.Wrap(l, 64)) do out[#out + 1] = { text = w, color = C.grey } end
    end
    return out
  end
  if Window.tab == "quests" then
    local r = (Window.questRows or J.QuestRows(d))[Window.quest or 1]
    if not r then return { { text = "No quest selected.", color = C.grey } } end
    return J.QuestLines(r.quest, r.state)
  end
  local n = #(d.bosses or {})
  local idx = Window.boss or 1
  local b = idx <= n and d.bosses[idx] or (d.trash or {})[idx - n]
  if not b then
    local out = { { text = d.name, color = C.cyan, head = true } }
    for _, l in ipairs(J.Wrap(d.summary or "", 64)) do out[#out + 1] = { text = l, color = C.cream } end
    return out
  end
  return J.BossLines(b, J.playerClass())
end

-- ------------------------------------------------------------------------------------------------ paint
function Window.Refresh()
  local f = Window.frame
  if not f or not f:IsShown() then return end
  local d = Window.dungeon
  f.sub:SetText(d and ("%s  %s"):format(d.name, d.levels or "") or "")
  local left = Window.LeftRows()
  Window.leftRows = left
  for i, b in ipairs(f.left) do
    local r = left[i]
    if r then
      b.label:SetText(r.text) b.label:SetTextColor(r.color[1], r.color[2], r.color[3])
      b.right:SetText(r.right or "")
      if r.selected then b.sel:Show() else b.sel:Hide() end
      b:Show()
    else b:Hide() end
  end
  local right = Window.RightRows()
  Window.rightRows = right
  for i, t in ipairs(f.right) do
    local r = right[i]
    if r then
      t:SetText(r.text) t:SetTextColor(r.color[1], r.color[2], r.color[3]) t:Show()
    else t:Hide() end
  end
  Window.rightOverflow = #right > #f.right and (#right - #f.right) or 0
  for key, b in pairs(f.tabs) do
    if key == Window.tab and d then b.line:Show() b.label:SetTextColor(C.cyan[1], C.cyan[2], C.cyan[3])
    else b.line:Hide() b.label:SetTextColor(C.grey[1], C.grey[2], C.grey[3]) end
  end
  f.footer:SetText(d and (J.Data.SOURCE .. "  |  /hh journal") or ("%d dungeon%s written  |  /hh journal <name>"):format(#J.Dungeons(), #J.Dungeons() == 1 and "" or "s"))
end

-- ------------------------------------------------------------------------------------------------ actions
function Window.ClickLeft(i)
  local r = Window.leftRows and Window.leftRows[i]
  if not r then return end
  if r.kind == "dungeon" then Window.SetDungeon(r.key)
  elseif r.kind == "boss" then Window.boss = r.index
  elseif r.kind == "trash" then Window.boss = #(Window.dungeon.bosses or {}) + r.index
  elseif r.kind == "quest" then Window.quest = r.index end
  Window.Refresh()
end

function Window.SetTab(tab)
  Window.tab = tab
  Window.Refresh()
end

--- Choose the dungeon: a key, a name, an instance id, or a dungeon table. nil = the list of dungeons.
function Window.SetDungeon(what)
  local d = type(what) == "table" and what or (what ~= nil and J.Dungeon(what) or nil)
  if d ~= Window.dungeon then Window.boss, Window.quest = 1, 1 end
  Window.dungeon = d
  Window.Refresh()
  return d
end

--- Open on the current dungeon when it is known, else on what was given, else on the list.
function Window.Show(what)
  local f = Window.Build()
  f:SetScale(J.cfg().scale or 1)
  f:Show()
  if what ~= nil then Window.SetDungeon(what)
  elseif not Window.dungeon then
    local d = J.Current()
    Window.SetDungeon(d)
  else Window.Refresh() end
  return f
end

function Window.Toggle(what)
  local f = Window.Build()
  if f:IsShown() and what == nil then f:Hide() return false end
  Window.Show(what)
  return true
end
