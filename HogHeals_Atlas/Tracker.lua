-- Tracker: the small on-screen panel while you are inside a dungeon. Three things, top to bottom:
--   bosses     the kill order, ticked off as they die this run
--   quests     your dungeon quests with progress (ready to hand in first)
--   wanted     wishlist items that drop here, with their boss
-- Shows itself when you walk in, hides when you leave. /hh dungeon toggles it; drag the title to move it.
local A = HogHealsAtlas
local HH = HogHeals

local Tracker = { ROWS = 22, WIDTH = 250, ROW_H = 16 }
A.Tracker = Tracker

local C = A.COLORS

--- The dungeon to show: the one you stand in, or nil.
function Tracker.Here()
  local name, inst = A.Capture.Instance()
  if not name and not inst then return nil end
  local run = A.Store.db().runs[1]
  local killed = (run and run.open and run.killed) or {}
  -- a boss already dead tells the wing apart (Scarlet Monastery, Dire Maul: several dungeons, one instance id)
  local dkey
  for boss in pairs(killed) do
    local d = A.Data.FindBoss(boss, inst)
    if d then dkey = d.key break end
  end
  dkey = dkey or A.Store.DungeonKey(name, inst)
  return dkey, killed, name
end

--- Rows for the panel. Pure: everything it needs comes in. quests = DungeonQuests rows.
function Tracker.Rows(dkey, killed, quests)
  local rows = {}
  local d = dkey and A.Store.Dungeon(dkey)
  if not d then return rows end
  killed = killed or {}
  local bosses = A.Store.Bosses(dkey)
  local total, dead = 0, 0
  for _, b in ipairs(bosses) do
    if not b.trash and not b.rare then
      total = total + 1
      if killed[b.name] then dead = dead + 1 end
    end
  end
  rows[#rows + 1] = { header = true, text = "Bosses", right = total > 0 and ("%d / %d"):format(dead, total) or "" }
  for _, b in ipairs(bosses) do
    if not b.trash then
      local done = killed[b.name] == true
      -- a rare that is not up is not a task: listed only once it died
      if not b.rare or done then
        rows[#rows + 1] = { text = b.name, right = done and "done" or "", color = done and C.grey or C.cream,
          rightColor = C.green, boss = b.name }
      end
    end
  end
  if total == 0 then rows[#rows + 1] = { text = "None known yet: they appear as they die.", color = C.grey } end

  local mine = {}
  for _, q in ipairs(quests or {}) do if q.state ~= "none" then mine[#mine + 1] = q end end
  if #mine > 0 then
    rows[#rows + 1] = { header = true, text = "Quests", right = tostring(#mine) }
    for _, q in ipairs(mine) do
      local ready = q.state == "ready"
      rows[#rows + 1] = { text = q.title, right = ready and "ready" or (q.progress or ""), color = C.cream,
        rightColor = ready and C.green or C.amber }
      if not ready then
        for _, o in ipairs(q.objectives or {}) do
          if not o.done then rows[#rows + 1] = { text = o.text or "", indent = 10, color = C.grey } end
        end
      end
    end
  end

  local wanted = {}
  for _, w in ipairs(A.Gear.WishRows()) do
    if not w.have then
      for _, s in ipairs(A.Store.SourceOf(w.id) or {}) do
        if s.dungeon == dkey then wanted[#wanted + 1] = { id = w.id, boss = s.boss } break end
      end
    end
  end
  if #wanted > 0 then
    rows[#rows + 1] = { header = true, text = "Wanted here", right = tostring(#wanted) }
    for _, w in ipairs(wanted) do
      local info = A.ItemInfo(w.id)
      rows[#rows + 1] = { text = info and info.name or ("item " .. w.id), right = w.boss, item = w.id,
        color = info and info.quality and { A.QualityColor(info.quality) } or C.grey, rightColor = killed[w.boss] and C.grey or C.cream }
    end
  end
  return rows, dead, total
end

local function build()
  if Tracker.frame then return Tracker.frame end
  local d = A.cfg()
  local f = CreateFrame("Frame", "HogUIAtlasTracker", UIParent)
  Tracker.frame = f
  f:SetSize(Tracker.WIDTH, 40)
  local t = d.tracker
  f:SetPoint(t.point or "RIGHT", UIParent, t.point or "RIGHT", t.x or -40, t.y or 120)
  f:SetFrameStrata("LOW")
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  local bar = CreateFrame("Button", nil, f)
  bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  bar:SetHeight(20)
  bar.bg = A.solid(bar, "BACKGROUND", C.panel, 0.9)
  bar.bg:SetAllPoints(bar)
  bar.rule = A.solid(bar, "ARTWORK", C.cyan)
  bar.rule:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
  bar.rule:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  bar.rule:SetHeight(1)
  bar:RegisterForDrag("LeftButton")
  bar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  bar:SetScript("OnDragStart", function() f:StartMoving() end)
  bar:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local point, _, _, x, y = f:GetPoint(1)
    local c = A.cfg().tracker
    if type(point) == "string" then c.point, c.x, c.y = point, x or 0, y or 0 end
  end)
  -- click the title: the full window, on this dungeon
  bar:SetScript("OnClick", function()
    local dkey = Tracker.Here()
    if dkey then A.Window.dungeon, A.Window.boss = dkey, nil end
    A.Window.Show("dungeons")
  end)
  f.title = A.text(bar, C.cream, "LEFT")
  f.title:SetPoint("LEFT", bar, "LEFT", 6, 0)
  f.title:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
  Tracker.list = A.List.New(f, { width = Tracker.WIDTH, rowHeight = Tracker.ROW_H, rows = Tracker.ROWS,
    onClick = function(row, btn) if row.item then A.Window.ItemClick(row.item, btn) end end })
  Tracker.list.frame:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -20)
  f:Hide()
  return f
end

--- Show / hide / repaint for where you are now. force = true shows it even when the option is off (the slash).
function Tracker.Refresh(force)
  local dkey, killed = Tracker.Here()
  local c = A.cfg()
  local want = dkey ~= nil and (force or Tracker.forced or c.tracker.enabled ~= false) and not Tracker.dismissed
  if not want then
    if Tracker.frame then Tracker.frame:Hide() end
    return false
  end
  local f = build()
  local d = A.Store.Dungeon(dkey)
  local min, max = d.min, d.max
  if A.Data.byKey[dkey] then min, max = A.Levels.For(d) end
  f.title:SetText(d.name .. ((min and max) and ("   %d-%d"):format(min, max) or ""))
  local rows = Tracker.Rows(dkey, killed, (A.DungeonQuests.For(dkey)))
  Tracker.list:SetData(rows)
  local shown = math.min(#rows, Tracker.ROWS)
  Tracker.list.frame:SetHeight(math.max(1, shown) * Tracker.ROW_H)
  f:SetHeight(20 + math.max(1, shown) * Tracker.ROW_H)
  f:Show()
  return true
end

--- Several events in one frame, one repaint.
function Tracker.RefreshSoon()
  if Tracker.pending then return end
  Tracker.pending = true
  local function run() Tracker.pending = false Tracker.Refresh() end
  if C_Timer and C_Timer.After then C_Timer.After(0.3, run) else run() end
end

function Tracker.Toggle()
  if Tracker.frame and Tracker.frame:IsShown() then
    Tracker.dismissed, Tracker.forced = true, false
    Tracker.frame:Hide()
    return false
  end
  Tracker.dismissed, Tracker.forced = false, true
  if not Tracker.Refresh(true) then HH:Print("The dungeon tracker shows inside a dungeon. You are not in one.") end
  return true
end

--- Walking in or out: a fresh run forgets that you closed the panel last time.
function Tracker.OnZone()
  if not Tracker.Here() then Tracker.dismissed, Tracker.forced = false, false end
  Tracker.RefreshSoon()
end

function Tracker.Start()
  if Tracker.events then return end
  local f = CreateFrame("Frame")
  Tracker.events = f
  for _, e in ipairs({ "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do pcall(f.RegisterEvent, f, e) end
  f:SetScript("OnEvent", function(_, e)
    local ok, err
    if e == "QUEST_LOG_UPDATE" then
      A.DungeonQuests.Invalidate()
      if Tracker.frame and Tracker.frame:IsShown() then ok, err = pcall(Tracker.RefreshSoon) else ok = true end
    else
      ok, err = pcall(Tracker.OnZone)
    end
    if not ok then HH:LogError("atlas tracker: " .. tostring(err)) end
  end)
end
