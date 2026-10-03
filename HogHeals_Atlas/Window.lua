-- Window: the Atlas window. Five tabs, all built from List columns.
--   Dungeons   dungeon list (level coloured) -> bosses -> Loot / Quests / Guide
--   Upgrades   per gear slot: better items, ranked for your role, with where they drop
--   Sets       saved gear sets: pieces, where each drops, score against what you wear
--   Wishlist   items you want; a chat line when one drops
--   Loot log   what dropped in your last dungeon runs
--
-- Item rows everywhere: hover = tooltip, shift-click = link in chat, ctrl-click = dressing room,
-- right-click = wishlist on / off, alt-click = into the selected set.
local A = HogHealsAtlas
local HH = HogHeals

local Window = { tab = "dungeons", detail = "loot", setIndex = 1, runIndex = 1 }
A.Window = Window

local C = A.COLORS
local W, H = 900, 560
local PAD, TOP = 10, 58
local ROW = 18
local BODY_ROWS = 26

local TABS = { { "dungeons", "Dungeons" }, { "upgrades", "Upgrades" }, { "sets", "Sets" }, { "wish", "Wishlist" }, { "log", "Loot log" } }
local DETAILS = { { "loot", "Loot" }, { "quests", "Quests" }, { "guide", "Guide" } }
local BADGE = { seen = "seen", group = "group", journal = "journal", reported = "reported" }
local BADGE_COLOR = { seen = C.green, group = C.green, journal = C.cyan, reported = C.grey }

-- ------------------------------------------------------------------------------------------------ item helpers
function Window.ItemTooltip(owner, id, extra)
  local tip = rawget(_G, "GameTooltip")
  if type(tip) ~= "table" or not tip.SetOwner then return end
  tip:SetOwner(owner, "ANCHOR_RIGHT")
  if tip.SetHyperlink then pcall(tip.SetHyperlink, tip, "item:" .. id) end
  if extra and tip.AddLine then tip:AddLine(extra, C.grey[1], C.grey[2], C.grey[3], true) end
  if tip.AddLine then tip:AddLine("Shift: link  Ctrl: try on  Right: wishlist  Alt: into set", 0.5, 0.5, 0.55) end
  if tip.Show then tip:Show() end
end

function Window.TextTooltip(owner, body)
  local tip = rawget(_G, "GameTooltip")
  if type(tip) ~= "table" or not tip.SetOwner then return end
  tip:SetOwner(owner, "ANCHOR_RIGHT")
  if tip.ClearLines then tip:ClearLines() end
  if tip.AddLine then tip:AddLine(body, C.cream[1], C.cream[2], C.cream[3], true) end
  if tip.Show then tip:Show() end
end

local function down(name) local f = rawget(_G, name) return type(f) == "function" and f() and true or false end

function Window.ItemClick(id, button)
  if not id then return end
  local info = A.ItemInfo(id)
  local link = info and info.link
  if button == "RightButton" then
    local on = A.Gear.ToggleWish(id)
    HH:Print(("%s %s your wishlist."):format(link or ("item " .. id), on and "added to" or "removed from"))
    Window.Refresh()
  elseif down("IsShiftKeyDown") then
    local insert = rawget(_G, "ChatEdit_InsertLink")
    if link and type(insert) == "function" then pcall(insert, link) end
  elseif down("IsControlKeyDown") then
    local dress = rawget(_G, "DressUpItemLink") or rawget(_G, "DressUpLink")
    if link and type(dress) == "function" then pcall(dress, link) end
  elseif down("IsAltKeyDown") then
    local sets = A.Gear.Sets()
    if #sets == 0 then A.Gear.NewSet(nil) Window.setIndex = 1 end
    local ok, where = A.Gear.SetItem(Window.setIndex, id)
    if ok then
      HH:Print(("%s -> set \"%s\" (%s)."):format(link or ("item " .. id), A.Gear.Sets()[Window.setIndex].name, A.Gear.SLOT_NAME[where] or "?"))
    else
      HH:Print("Could not add to the set: " .. tostring(where))
    end
    Window.Refresh()
  end
end

--- A list row for an item. extra fields are copied onto the row.
function Window.ItemRow(id, extra)
  local info = A.ItemInfo(id)
  local row = { item = id }
  if info and info.name then
    row.text = info.name
    row.color = { A.QualityColor(info.quality) }
    row.icon = info.icon
  else
    row.text = ("item %d (asking the server...)"):format(id)
    row.color = C.grey
    row.icon = info and info.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
  end
  if A.Gear.IsWished(id) then row.text = "* " .. row.text end
  for k, v in pairs(extra or {}) do row[k] = v end
  return row
end

-- ------------------------------------------------------------------------------------------------ rows per pane
function Window.DungeonRows()
  local L = A.playerLevel()
  local faction = A.playerFaction()
  local rows = {}
  for _, e in ipairs(A.Levels.List(L, A.cfg().forMeNow)) do
    local d = e.dungeon
    local c = A.COLORS[e.band] or C.cream
    local other = d.faction and faction and d.faction ~= faction
    local q = A.DungeonQuests.Summary(d.key)
    rows[#rows + 1] = { key = d.key, text = d.name .. (d.unverified and " (new)" or ""), right = ("%d-%d"):format(e.min, e.max),
      color = c, rightColor = c, selected = Window.dungeon == d.key,
      tip = (q and ("Quests in your log: " .. q .. ". ") or "") .. (other and "Other faction's side of the world. " or "") .. (d.where or "") }
  end
  if not A.cfg().forMeNow then
    for _, d in ipairs(A.Store.ExtraDungeons()) do
      rows[#rows + 1] = { key = d.key, text = d.name .. " (found)", right = "?", color = C.cream, selected = Window.dungeon == d.key,
        tip = "Not in the shipped list: found in play or in the game's journal." }
    end
  end
  return rows
end

function Window.BossRows()
  local rows = {}
  if not Window.dungeon then return rows end
  rows[#rows + 1] = { all = true, text = "All bosses", right = "", color = C.cyan, selected = Window.boss == nil }
  for _, b in ipairs(A.Store.Bosses(Window.dungeon)) do
    local label = b.name
    if b.rare then label = label .. " (rare)" elseif b.found then label = label .. " (found)" end
    rows[#rows + 1] = { boss = b.name, text = label, right = b.items > 0 and tostring(b.items) or "", selected = Window.boss == b.name,
      color = (b.items > 0) and C.cream or C.grey, rightColor = C.cyan }
  end
  return rows
end

function Window.LootRows()
  local rows = {}
  if not Window.dungeon then return rows end
  local function bossLoot(name)
    local list = A.Store.GetBossLoot(Window.dungeon, name)
    if #list == 0 then return end
    if not Window.boss then rows[#rows + 1] = { header = true, text = name } end
    for _, e in ipairs(list) do
      local tag = BADGE[e.src] or e.src
      if e.n and e.n > 1 then tag = tag .. " x" .. e.n end
      local ok, cmp = pcall(A.Gear.Compare, e.id)
      local mid, midColor
      if ok and cmp and not cmp.worn and cmp.usable and cmp.delta then
        if cmp.delta > 0 then
          mid, midColor = ("+%.1f"):format(cmp.delta) .. (cmp.later and (" at " .. cmp.later) or ""), cmp.later and C.amber or C.green
        end
      elseif ok and cmp and cmp.worn then
        mid, midColor = "worn", C.grey
      end
      rows[#rows + 1] = Window.ItemRow(e.id, { right = tag, rightColor = BADGE_COLOR[e.src] or C.grey, mid = mid, midColor = midColor })
    end
  end
  if Window.boss then bossLoot(Window.boss) else
    for _, b in ipairs(A.Store.Bosses(Window.dungeon)) do bossLoot(b.name) end
  end
  return rows
end

function Window.QuestRows()
  local rows = {}
  if not Window.dungeon then return rows end
  local list, haveLog = A.DungeonQuests.For(Window.dungeon)
  local stateColor = { ready = C.green, active = C.amber, none = C.grey }
  local stateText = { ready = "ready to hand in", active = "in your log", none = "" }
  for _, q in ipairs(list) do
    local right = stateText[q.state]
    if q.state == "active" and q.progress then right = q.progress .. " done" end
    rows[#rows + 1] = { text = q.title .. (q.listed and "" or " (from your log)"), right = right,
      color = q.state == "none" and C.grey or C.cream, rightColor = stateColor[q.state], quest = q.quest,
      tip = q.listed and "From the old game's quest list. Not verified on Forever." or "The game files this quest under this dungeon." }
    if q.state == "active" then
      for _, o in ipairs(q.objectives or {}) do
        rows[#rows + 1] = { text = o.text or "", indent = 14, color = o.done and C.green or C.grey }
      end
    end
  end
  if not haveLog then
    rows[#rows + 1] = { text = "" }
    rows[#rows + 1] = { text = "Turn on HogUI Quests to see your progress here.", color = C.grey }
  end
  return rows
end

local function wrap(textValue, width)
  local lines, line = {}, ""
  for word in tostring(textValue):gmatch("%S+") do
    if #line + #word + 1 > width and line ~= "" then lines[#lines + 1] = line line = word
    else line = (line == "" and word) or (line .. " " .. word) end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end
Window.wrap = wrap

function Window.GuideRows()
  local rows = {}
  local d = Window.dungeon and A.Store.Dungeon(Window.dungeon)
  if not d then return rows end
  local L = A.playerLevel()
  local min, max, source = d.min, d.max, "list"
  if A.Data.byKey[d.key] then min, max, source = A.Levels.For(d) end
  local function pair(k, v, c) rows[#rows + 1] = { text = k, right = v, rightColor = c or C.cream, color = C.grey } end
  rows[#rows + 1] = { header = true, text = d.name }
  if min and max then
    local r, g, b, band = A.Levels.Colour(L, min, max)
    local say = { red = "too low for you", orange = "hard at your level", green = "right for your level", grey = "you outgrew it" }
    pair("Levels", ("%d-%d  (%s)"):format(min, max, say[band] or "?"), { r, g, b })
    pair("Level range from", source == "game" and "the game" or "the old game's list")
  end
  if d.enter then pair("You can enter from level", tostring(d.enter)) end
  if d.size then pair("Group size", tostring(d.size)) end
  if d.zone then pair("Entrance", d.zone .. (d.continent and (", " .. d.continent) or "")) end
  if d.faction then pair("Home side", d.faction == "H" and "Horde" or "Alliance") end
  local bosses = A.Store.Bosses(d.key)
  pair("Bosses", tostring(#bosses))
  local items = 0
  for _, b in ipairs(bosses) do items = items + b.items end
  pair("Drops known", tostring(items), items > 0 and C.cyan or C.grey)
  if items > 0 then
    local n, best = A.Gear.CountUpgrades(A.Store.DungeonItems(d.key))
    pair("Upgrades for you here", n > 0 and ("%d  (best +%.1f)"):format(n, best) or "none", n > 0 and C.green or C.grey)
  end
  local q, active, ready = A.DungeonQuests.Summary(d.key)
  pair("Quests in your log", q or "none", (ready or 0) > 0 and C.green or C.cream)
  if d.where then
    rows[#rows + 1] = { text = "" }
    rows[#rows + 1] = { header = true, text = "How to get there" }
    for _, l in ipairs(wrap(d.where, 60)) do rows[#rows + 1] = { text = l } end
  end
  rows[#rows + 1] = { text = "" }
  rows[#rows + 1] = { header = true, text = "Kill order" }
  local n = 0
  for _, b in ipairs(bosses) do
    if not b.trash then
      n = n + 1
      rows[#rows + 1] = { text = ("%d. %s%s"):format(n, b.name, b.rare and " (rare, not always there)" or ""), color = b.rare and C.grey or C.cream }
    end
  end
  if n == 0 then rows[#rows + 1] = { text = "No bosses known yet. They appear here as you kill them.", color = C.grey } end
  rows[#rows + 1] = { text = "" }
  local note = d.unverified and "New in Forever: everything here is learned in play."
    or "Names and levels are from the old game. Forever may differ; what the game itself reports wins."
  for _, l in ipairs(wrap(note, 60)) do rows[#rows + 1] = { text = l, color = C.grey } end
  return rows
end

function Window.UpgradeRows()
  local list, unknown = A.Gear.UpgradeRows({ role = A.Stats.Role() })
  local rows = {}
  for _, u in ipairs(list) do
    if u.header then
      local cur = u.current and u.current.info and u.current.info.name or "empty"
      rows[#rows + 1] = { header = true, text = ("%s   -   now: %s"):format(u.text, cur), right = ("score %.1f"):format(u.score) }
    else
      local right = ("+%.1f"):format(u.delta)
      if u.later then right = right .. ("  at %d"):format(u.later) end
      local st = A.Stats.Text(u.stats, 3)
      rows[#rows + 1] = Window.ItemRow(u.id, { right = right, rightColor = u.later and C.amber or C.green, indent = 10,
        mid = (u.source or "source unknown") .. (st ~= "" and ("   |   " .. st) or ""),
        midColor = u.where == "bag" and C.green or C.grey,
        tip = (u.source or "source unknown") .. "\n" .. A.Stats.Text(u.stats, 8) })
    end
  end
  return rows, unknown
end

function Window.SetListRows()
  local rows = {}
  for i, s in ipairs(A.Gear.Sets()) do
    local sum = A.Gear.SetSummary(i)
    rows[#rows + 1] = { index = i, text = s.name, right = ("%d pc"):format(sum.pieces), selected = Window.setIndex == i }
  end
  return rows
end

function Window.SetRows()
  local rows = {}
  local sum = A.Gear.SetSummary(Window.setIndex)
  if not sum then return rows end
  rows[#rows + 1] = { header = true, text = sum.name, right = ("score %.1f"):format(sum.score) }
  rows[#rows + 1] = { text = "Finishing it is worth (empty slots keep what you wear)", right = ("%+.1f"):format(sum.gain), color = C.grey,
    rightColor = sum.gain >= 0 and C.green or C.red }
  rows[#rows + 1] = { text = "Pieces you already own", right = ("%d of %d"):format(sum.owned, sum.pieces), color = C.grey }
  local lines = A.Stats.Lines(sum.stats, 84)
  if #lines == 0 then lines = { "No stats known yet." } end
  for _, l in ipairs(lines) do rows[#rows + 1] = { text = l, color = C.cream } end
  rows[#rows + 1] = { text = "" }
  for _, r in ipairs(sum.rows) do
    if r.id then
      rows[#rows + 1] = Window.ItemRow(r.id, { right = r.have and "owned" or (r.source or "source unknown"),
        rightColor = r.have and C.green or C.grey, setSlot = r.slot, tip = r.slotName, mid = r.slotName, midColor = C.cyan })
    else
      rows[#rows + 1] = { text = r.worn and ("(keeps " .. r.worn .. ")") or "(empty)", color = C.grey, setSlot = r.slot,
        mid = r.slotName, midColor = C.grey, indent = 18 }
    end
  end
  return rows
end

function Window.WishRows()
  local rows = {}
  for _, w in ipairs(A.Gear.WishRows()) do
    rows[#rows + 1] = Window.ItemRow(w.id, { right = w.have and "you have it" or w.source, rightColor = w.have and C.green or C.grey,
      mid = A.Stats.Text(A.Stats.Of(w.id), 4) })
  end
  return rows
end

function Window.RunRows()
  local rows = {}
  for i, r in ipairs(A.Store.db().runs) do
    rows[#rows + 1] = { index = i, text = r.name, right = r.start or "", selected = Window.runIndex == i,
      color = r.open and C.green or C.cream }
  end
  return rows
end

function Window.DropRows()
  local rows = {}
  local run = A.Store.db().runs[Window.runIndex]
  if not run then return rows end
  local last
  for _, d in ipairs(run.drops) do
    if d.boss ~= last then rows[#rows + 1] = { header = true, text = d.boss } last = d.boss end
    local who = d.who
    if who == "me" or (type(who) == "string" and who:find("^roll:")) then who = "" end
    rows[#rows + 1] = Window.ItemRow(d.id, { right = who or "", indent = 10 })
  end
  return rows
end

-- ------------------------------------------------------------------------------------------------ build
local function pane(f, name)
  local p = CreateFrame("Frame", nil, f)
  p:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -TOP)
  p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD + 18)
  p:Hide()
  Window.panes[name] = p
  return p
end

local function column(parent, x, width, rows, onClick, y, midX)
  local l = A.List.New(parent, { width = width, rowHeight = ROW, rows = rows, onClick = onClick, midX = midX })
  l.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y or 0)
  return l
end

local function itemClick(d, btn) if d.item then Window.ItemClick(d.item, btn) end end

function Window.Build()
  if Window.frame then return Window.frame end
  local d = A.cfg()
  local f = CreateFrame("Frame", "HogUIAtlasWindow", UIParent)
  Window.frame = f
  f:SetSize(W, H)
  f:SetPoint(d.point or "CENTER", UIParent, d.point or "CENTER", d.x or 0, d.y or 0)
  f:SetScale(d.scale or 1)
  f:SetFrameStrata("HIGH")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f.bg = A.solid(f, "BACKGROUND", C.ink, 0.96)
  f.bg:SetAllPoints(f)
  local spec = { { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }
  for _, sp in ipairs(spec) do
    local e = A.solid(f, "BORDER", C.line)
    e:SetPoint(sp[1], f, sp[1], 0, 0)
    e:SetPoint(sp[2], f, sp[2], 0, 0)
    if sp[3] then e:SetWidth(sp[3]) end
    if sp[4] then e:SetHeight(sp[4]) end
  end
  local special = rawget(_G, "UISpecialFrames")
  if type(special) == "table" then special[#special + 1] = "HogUIAtlasWindow" end   -- Escape closes it

  -- title bar: drag handle, two-tone wordmark, close
  local bar = CreateFrame("Button", nil, f)
  bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  bar:SetHeight(26)
  bar.bg = A.solid(bar, "BACKGROUND", C.panel)
  bar.bg:SetAllPoints(bar)
  bar.rule = A.solid(bar, "ARTWORK", C.cyan)
  bar.rule:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
  bar.rule:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  bar.rule:SetHeight(1)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() f:StartMoving() end)
  bar:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local point, _, _, x, y = f:GetPoint(1)
    local c = A.cfg()
    if type(point) == "string" then c.point, c.x, c.y = point, x or 0, y or 0 end
  end)
  f.title = A.text(bar, C.cream, "LEFT", "GameFontNormal")
  f.title:SetPoint("LEFT", bar, "LEFT", PAD, 0)
  f.title:SetText("|cffF5EBDCHOG|r|cff21D4E0UI|r  |cffF5EBDCATLAS|r")
  f.close = A.button(bar, "x", 24, 20, function() f:Hide() end)
  f.close:SetPoint("RIGHT", bar, "RIGHT", -4, 0)

  -- tabs
  Window.tabButtons = {}
  for i, t in ipairs(TABS) do
    local b = A.button(f, t[2], 100, 22, function() Window.SetTab(t[1]) end)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (i - 1) * 104, -31)
    Window.tabButtons[t[1]] = b
  end
  f.status = A.text(f, C.grey, "LEFT")
  f.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 8)
  f.status:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 8)

  Window.panes = {}
  Window.lists = {}

  -- Dungeons
  local p = pane(f, "dungeons")
  Window.forMe = A.button(p, "For my level", 110, 20, function()
    local c = A.cfg()
    c.forMeNow = not c.forMeNow
    Window.Refresh()
  end)
  Window.forMe:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  Window.scan = A.button(p, "Read game journal", 130, 20, function()
    local r = A.Journal.Scan("button")
    HH:Print(A.Journal.Report()[1])
    if r.instances > 0 then Window.Refresh() end
  end)
  Window.scan:SetPoint("TOPLEFT", p, "TOPLEFT", 116, 0)
  Window.lists.dungeons = column(p, 0, 250, BODY_ROWS - 2, function(row)
    Window.dungeon, Window.boss = row.key, nil
    Window.lists.bosses.offset, Window.lists.detail.offset = 0, 0
    Window.Refresh()
  end, -24)
  Window.lists.bosses = column(p, 256, 220, BODY_ROWS - 2, function(row)
    Window.boss = row.boss
    Window.lists.detail.offset = 0
    if Window.detail ~= "loot" then Window.detail = "loot" end
    Window.Refresh()
  end, -24)
  Window.detailButtons = {}
  for i, t in ipairs(DETAILS) do
    local b = A.button(p, t[2], 80, 20, function() Window.detail = t[1] Window.lists.detail.offset = 0 Window.Refresh() end)
    b:SetPoint("TOPLEFT", p, "TOPLEFT", 482 + (i - 1) * 84, 0)
    Window.detailButtons[t[1]] = b
  end
  Window.lists.detail = column(p, 482, 398, BODY_ROWS - 2, itemClick, -24, 255)

  -- Upgrades
  p = pane(f, "upgrades")
  Window.roleButtons = {}
  -- Sean 2026-10-01: "tough to see what your default is" - Auto is the default and says what it resolved to
  -- ("Auto: healer"); it is wider and the first tab, the role it stands for is the only other one lit, dimly.
  local roles = { "auto", "healer", "caster", "melee", "ranged", "tank" }
  for i, r in ipairs(roles) do
    local w = r == "auto" and 118 or 80
    local b = A.button(p, r == "auto" and "Auto" or (r:sub(1, 1):upper() .. r:sub(2)), w, 20, function() A.SetRole(r) Window.Refresh() end)
    b:SetPoint("TOPLEFT", p, "TOPLEFT", r == "auto" and 0 or (118 + 10 + (i - 2) * 84), 0)
    Window.roleButtons[r] = b
  end
  Window.lists.upgrades = column(p, 0, 880, BODY_ROWS - 2, itemClick, -24, 300)

  -- Sets
  p = pane(f, "sets")
  local function newSet(from)
    local set, idx = A.Gear.NewSet(nil, from)
    if set then Window.setIndex = idx else HH:Print(tostring(idx)) end
    Window.Refresh()
  end
  local b1 = A.button(p, "New from what I wear", 150, 20, function() newSet("equipped") end)
  b1:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  local b2 = A.button(p, "New empty", 90, 20, function() newSet(nil) end)
  b2:SetPoint("TOPLEFT", p, "TOPLEFT", 156, 0)
  local b3 = A.button(p, "Delete set", 90, 20, function()
    if A.Gear.DeleteSet(Window.setIndex) then Window.setIndex = math.max(1, Window.setIndex - 1) end
    Window.Refresh()
  end)
  b3:SetPoint("TOPLEFT", p, "TOPLEFT", 252, 0)
  Window.lists.setList = column(p, 0, 250, BODY_ROWS - 2, function(row) Window.setIndex = row.index Window.Refresh() end, -24)
  Window.lists.set = column(p, 256, 624, BODY_ROWS - 2, function(row, btn)
    -- right-click a piece: take it out of the set (the wishlist is one tab over)
    if btn == "RightButton" and row.setSlot then A.Gear.ClearSlot(Window.setIndex, row.setSlot) Window.Refresh()
    elseif row.item then Window.ItemClick(row.item, btn) end
  end, -24, 270)

  -- Wishlist
  p = pane(f, "wish")
  Window.lists.wish = column(p, 0, 880, BODY_ROWS, itemClick, nil, 300)

  -- Loot log
  p = pane(f, "log")
  Window.lists.runs = column(p, 0, 300, BODY_ROWS, function(row) Window.runIndex = row.index Window.lists.drops.offset = 0 Window.Refresh() end)
  Window.lists.drops = column(p, 306, 574, BODY_ROWS, itemClick)

  f:Hide()
  return f
end

-- ------------------------------------------------------------------------------------------------ paint
local EMPTY = {
  loot = "No drops known for this yet.\n\nThey fill in three ways: the game's own journal (button above the dungeon list), drops you or your group see in the dungeon, and the curated file.",
  upgrades = "No upgrades found among the items Atlas knows.\n\nAtlas can only rank items it has a source for: read the game journal on the Dungeons tab, or run a dungeon.",
  sets = "No sets yet. 'New from what I wear' saves your current gear as a set.\nAlt-click any item in Atlas to put it in the selected set.",
  wish = "Your wishlist is empty.\n\nRight-click any item in Atlas to add it. You get a chat line when it drops.",
  log = "No dungeon runs recorded yet.",
  drops = "Nothing dropped in this run (green quality and better is recorded).",
}

function Window.Refresh()
  local f = Window.frame
  if not f or not f:IsShown() then return end
  for name, p in pairs(Window.panes) do if name == Window.tab then p:Show() else p:Hide() end end
  for name, b in pairs(Window.tabButtons) do b:SetOn(name == Window.tab) end
  local status = ""
  local L = Window.lists
  if Window.tab == "dungeons" then
    Window.forMe:SetOn(A.cfg().forMeNow)
    for name, b in pairs(Window.detailButtons) do b:SetOn(name == Window.detail) end
    local rows = Window.DungeonRows()
    if not Window.dungeon and rows[1] then
      -- open on the dungeon you stand in, else the first one right for your level
      local name, inst = A.Capture.Instance()
      local here = (name or inst) and A.Store.DungeonKey(name, inst)
      Window.dungeon = here
      if not here then
        for _, r in ipairs(A.Levels.List(A.playerLevel(), true)) do Window.dungeon = r.dungeon.key break end
      end
      Window.dungeon = Window.dungeon or rows[1].key
      rows = Window.DungeonRows()
    end
    L.dungeons:SetData(rows, "No dungeon fits your level. Turn off 'For my level'.")
    L.bosses:SetData(Window.BossRows())
    if Window.detail == "quests" then L.detail:SetData(Window.QuestRows(), "No quests known for this dungeon.")
    elseif Window.detail == "guide" then L.detail:SetData(Window.GuideRows())
    else L.detail:SetData(Window.LootRows(), EMPTY.loot) end
    local jr = A.Journal.last
    status = ("%d dungeons, %d drops known. Red too low, orange hard, green right, grey outgrown. +N = better than what you wear.%s"):format(
      #rows, A.Store.db().count, jr and ("  Journal: " .. tostring(jr.status) .. ".") or "")
  elseif Window.tab == "upgrades" then
    local role = A.Role()
    local effective = A.Stats.Role()
    for name, b in pairs(Window.roleButtons) do
      b:SetOn(name == role)
      if name == "auto" then b.label:SetText(role == "auto" and ("Auto: " .. effective) or "Auto") end
      if role == "auto" and name == effective then b.label:SetTextColor(0.13 * 0.7 + 0.3, 0.83 * 0.7 + 0.3, 0.88 * 0.7 + 0.3) end   -- the role Auto picked, dim cyan
    end
    local rows, unknown = Window.UpgradeRows()
    L.upgrades:SetData(rows, EMPTY.upgrades)
    status = ("Scored for: %s%s. Number = points better than what you wear. Amber = needs a higher level.%s"):format(
      A.Stats.Role(), A.Role() == "auto" and " (auto, by class)" or "",
      (unknown or 0) > 0 and ("  %d items still loading."):format(unknown) or "")
  elseif Window.tab == "sets" then
    local sets = A.Gear.Sets()
    if Window.setIndex > #sets then Window.setIndex = math.max(1, #sets) end
    L.setList:SetData(Window.SetListRows(), "No sets.")
    L.set:SetData(Window.SetRows(), EMPTY.sets)
    status = "Alt-click an item anywhere in Atlas to add it to the selected set. Right-click a piece here to remove it."
  elseif Window.tab == "wish" then
    L.wish:SetData(Window.WishRows(), EMPTY.wish)
    status = "Right-click an item to take it off the list."
  elseif Window.tab == "log" then
    local runs = A.Store.db().runs
    if Window.runIndex > #runs then Window.runIndex = math.max(1, #runs) end
    L.runs:SetData(Window.RunRows(), EMPTY.log)
    L.drops:SetData(#runs > 0 and Window.DropRows() or {}, #runs > 0 and EMPTY.drops or "")
    status = "Last 20 dungeon runs. Green = the run you are in."
  end
  f.status:SetText(status)
end

--- Item data arrives in bursts: one repaint a moment later instead of one per item.
function Window.RefreshSoon()
  if Window.pendingRefresh then return end
  Window.pendingRefresh = true
  local function run() Window.pendingRefresh = false Window.Refresh() end
  if C_Timer and C_Timer.After then C_Timer.After(0.5, run) else run() end
end

function Window.SetTab(tab)
  for _, t in ipairs(TABS) do if t[1] == tab then Window.tab = tab end end
  Window.Refresh()
end

function Window.Show(tab)
  local f = Window.Build()
  f:Show()
  if tab then Window.SetTab(tab) else Window.Refresh() end
end

function Window.Toggle(tab)
  local f = Window.Build()
  if f:IsShown() and (not tab or tab == Window.tab) then f:Hide() else Window.Show(tab) end
end
