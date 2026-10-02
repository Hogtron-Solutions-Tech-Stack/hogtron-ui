-- Quest tracker window, HogHeals style (same panel language as the meter: ink body, 1 px outline, cyan rule).
--
-- Shows watched quests; with nothing watched it falls back to every quest in the log so the window is never a
-- blank box. Left-click a title = open it in the quest log, right-click = watch / unwatch, shift-left = watch too.
-- Blizzard's tracker is hidden only once Data says this client lets us read the log (ours on = theirs off, but
-- never both off).
HogHealsQuests = HogHealsQuests or {}
local HHQ = HogHealsQuests
local HH = HogHeals

local Tracker = { lines = {}, titles = {} }
HHQ.Tracker = Tracker

local CREAM = { 0.96, 0.92, 0.86 }
local CYAN = { 0.13, 0.83, 0.88 }
local INK = { 0.07, 0.07, 0.09 }
local GREY = { 0.55, 0.55, 0.60 }
local GREEN = { 0.25, 0.80, 0.35 }
local AMBER = { 0.95, 0.65, 0.15 }
local LINE = { 0.20, 0.20, 0.25 }
local HEADER_H = 20

local function cfg() return HH.db.profile.quests.tracker end

local function solid(parent, layer, c, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  return t
end

-- Forever beta: SetText on a template-less FontString throws "Font not set". Always pass a template.
local function text(parent, c, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetTextColor(c[1], c[2], c[3])
  if justify then fs:SetJustifyH(justify) end
  return fs
end

local function applyFont(fs, size)
  local font, _, flags = fs:GetFont()
  if font and fs.SetFont then fs:SetFont(font, size, flags or "OUTLINE") end
end

--- Difficulty colour for a quest level: Blizzard's own function when the client has it, else a plain band.
function Tracker.LevelColor(level)
  if type(level) ~= "number" then return CREAM[1], CREAM[2], CREAM[3] end
  local f = rawget(_G, "GetQuestDifficultyColor")
  if type(f) == "function" then
    local ok, c = pcall(f, level)
    if ok and type(c) == "table" and c.r then return c.r, c.g, c.b end
  end
  local me = (type(UnitLevel) == "function" and UnitLevel("player")) or level
  if type(me) ~= "number" then me = level end
  local d = level - me
  if d >= 5 then return 1, 0.1, 0.1 elseif d >= 3 then return 1, 0.5, 0.25 elseif d >= -2 then return 1, 0.82, 0
  elseif d >= -7 then return 0.25, 0.75, 0.25 end
  return 0.5, 0.5, 0.5
end

-- ------------------------------------------------------------------------------------------------ selection
local function currentZone()
  for _, name in ipairs({ "GetRealZoneText", "GetZoneText" }) do
    local f = rawget(_G, name)
    if type(f) == "function" then
      local ok, z = pcall(f)
      if ok and type(z) == "string" and z ~= "" then return z end
    end
  end
end

--- Which quests to show and under what label. Pure: takes the list, returns (shown, label).
function Tracker.Select(list, mode)
  local d = cfg()
  local out = {}
  mode = mode or d.mode or "watched"
  local label = "Quests"
  if mode == "zone" then
    local z = currentZone()
    for _, q in ipairs(list) do if q.zone == z or q.watched then out[#out + 1] = q end end
    label = z or "Quests"
  elseif mode == "watched" then
    for _, q in ipairs(list) do if q.watched then out[#out + 1] = q end end
    if #out == 0 then
      for _, q in ipairs(list) do out[#out + 1] = q end
      label = "All quests"
    end
  else
    for _, q in ipairs(list) do out[#out + 1] = q end
    label = "All quests"
  end
  if d.hideCompleted then
    local keep = {}
    for _, q in ipairs(out) do if not q.complete then keep[#keep + 1] = q end end
    out = keep
  end
  -- ready-to-hand-in first: that is the next thing to do
  local ready, rest = {}, {}
  for _, q in ipairs(out) do if q.complete then ready[#ready + 1] = q else rest[#rest + 1] = q end end
  for _, q in ipairs(rest) do ready[#ready + 1] = q end
  return ready, label
end

-- ------------------------------------------------------------------------------------------------ window
local function build()
  if Tracker.frame then return Tracker.frame end
  local d = cfg()
  local f = CreateFrame("Frame", "HogHealsQuestTracker", UIParent)
  f:SetSize(d.width or 260, 60)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:SetFrameStrata("LOW")
  f.bg = solid(f, "BACKGROUND", INK, d.backgroundAlpha or 0.6)
  f.bg:SetAllPoints(f)
  f.edges = {}
  local spec = { { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }
  for i, sp in ipairs(spec) do
    local e = solid(f, "BORDER", LINE)
    e:SetPoint(sp[1], f, sp[1], 0, 0)
    e:SetPoint(sp[2], f, sp[2], 0, 0)
    if sp[3] then e:SetWidth(sp[3]) end
    if sp[4] then e:SetHeight(sp[4]) end
    f.edges[i] = e
  end

  local header = CreateFrame("Button", nil, f)
  header:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  header:SetHeight(HEADER_H)
  header.bg = solid(header, "BACKGROUND", { 0.11, 0.11, 0.14 })
  header.bg:SetAllPoints(header)
  header.rule = solid(header, "ARTWORK", CYAN)
  header.rule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
  header.rule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
  header.rule:SetHeight(1)
  header:RegisterForDrag("LeftButton")
  header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  -- Drag by the header any time (2026-09-22: "/hh unlock" first was invisible to the player); own lock option.
  header:SetScript("OnDragStart", function() if not cfg().lockPosition then f:StartMoving() end end)
  header:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local point, _, _, x, y = f:GetPoint(1)
    if point then local c = cfg() c.point, c.x, c.y = point, x, y; c.followMinimap = false end   -- dragged = detached
    Tracker.anchoredTo = "free"
    Tracker.Update()   -- the fill height depends on where the top now is
  end)
  -- Mouse wheel scrolls the list. In game 2026-10-01 the wheel over the panel zoomed the CAMERA: a frame that is
  -- not mouse-enabled does not take the wheel on this client. The panel takes the mouse now, and every title
  -- button (the thing actually under the cursor most of the time) scrolls as well.
  if f.EnableMouse then f:EnableMouse(true) end
  if f.EnableMouseWheel then f:EnableMouseWheel(true) end
  f:SetScript("OnMouseWheel", function(_, delta) Tracker.Scroll(delta) end)

  -- Resize grip, shown while /hh unlock is on: drag the bottom-right corner to set the width in place and, with
  -- fill on, where the list stops above the screen's bottom edge (fill off: the max height).
  if f.SetResizable then f:SetResizable(true) end
  if f.SetResizeBounds then pcall(f.SetResizeBounds, f, 160, 80) elseif f.SetMinResize then pcall(f.SetMinResize, f, 160, 80) end
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  grip:SetFrameLevel(f:GetFrameLevel() + 5)
  grip.tex = grip:CreateTexture(nil, "OVERLAY")
  grip.tex:SetAllPoints(grip)
  if grip.tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up") == false then
    grip.tex:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.9)
  else
    grip.tex:SetVertexColor(CYAN[1], CYAN[2], CYAN[3])
  end
  grip:SetScript("OnMouseDown", function()
    if cfg().lockPosition then return end
    Tracker.sizing = true
    if f.StartSizing then f:StartSizing("BOTTOMRIGHT") end
  end)
  grip:SetScript("OnMouseUp", function()
    if f.StopMovingOrSizing then f:StopMovingOrSizing() end
    Tracker.sizing = nil
    Tracker.TakeSize()
  end)
  grip:Hide()
  f.grip = grip
  header:SetScript("OnClick", function(_, button)
    if button == "RightButton" then Tracker.CycleMode() else Tracker.SetCollapsed(not cfg().collapsed) end
  end)
  f.header = header
  f.title = text(header, CYAN, "LEFT")
  f.title:SetPoint("LEFT", header, "LEFT", 6, 0)
  f.hint = text(header, GREY, "RIGHT")
  f.hint:SetPoint("RIGHT", header, "RIGHT", -6, 0)

  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 6, -4)
  f.body:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  f.body:SetHeight(10)
  f.body:SetScript("OnMouseWheel", function(_, delta) Tracker.Scroll(delta) end)
  if f.body.EnableMouseWheel then f.body:EnableMouseWheel(true) end

  f.empty = text(f.body, GREY, "LEFT")
  f.empty:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, 0)
  f.empty:Hide()
  Tracker.frame = f
  Tracker.Anchor()
  return f
end

--- Where the panel hangs. followMinimap (default): its top-right under the minimap box's bottom-right, `gap` px
-- down - so it never sits on the map whatever size Edit Mode gives the box (Sean 2026-10-01: "overlapping every
-- reload"), and it follows when the box is resized. Dragging the header detaches it (saved point); the option
-- puts it back.
function Tracker.Anchor()
  local f, d = Tracker.frame, cfg()
  if not f then return end
  f:ClearAllPoints()
  local under = d.followMinimap ~= false and (rawget(_G, "MinimapCluster") or rawget(_G, "Minimap")) or nil
  if type(under) == "table" then
    f:SetPoint("TOPRIGHT", under, "BOTTOMRIGHT", 0, -(d.gap or 8))
    Tracker.anchoredTo = "minimap"
  else
    f:SetPoint(d.point or "TOPRIGHT", UIParent, d.point or "TOPRIGHT", d.x or -80, d.y or -260)
    Tracker.anchoredTo = "free"
  end
end

local function titleButton(i)
  local b = Tracker.titles[i]
  if b then return b end
  local f = Tracker.frame
  b = CreateFrame("Button", nil, f.body)
  if b.EnableMouseWheel then b:EnableMouseWheel(true) end
  b:SetScript("OnMouseWheel", function(_, delta) Tracker.Scroll(delta) end)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.label = text(b, CREAM, "LEFT")
  if b.label.SetWordWrap then b.label:SetWordWrap(false) end   -- long titles wrapped into the objective (2026-09-22)
  b.label:SetPoint("LEFT", b, "LEFT", 0, 0)
  b.label:SetPoint("RIGHT", b, "RIGHT", 0, 0)
  b.hl = solid(b, "HIGHLIGHT", CYAN, 0.12)
  b.hl:SetAllPoints(b)
  b:SetScript("OnClick", function(self, button)
    local q = self.quest
    if not q then return end
    if button == "RightButton" or (IsShiftKeyDown and IsShiftKeyDown()) then
      HHQ.Data.SetWatched(q, not q.watched)
      Tracker.Schedule()
    else
      HHQ.Data.Open(q)
    end
  end)
  b:SetScript("OnEnter", function(self)
    if not GameTooltip or not self.quest then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(self.quest.title or "?")
    GameTooltip:AddLine("Left: open in quest log   Right: " .. (self.quest.watched and "stop watching" or "watch"), 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  Tracker.titles[i] = b
  return b
end

local function objLine(i)
  local fs = Tracker.lines[i]
  if fs then return fs end
  fs = text(Tracker.frame.body, CREAM, "LEFT")
  if fs.SetWordWrap then fs:SetWordWrap(false) end   -- one row each; the RIGHT anchor truncates with "..."
  Tracker.lines[i] = fs
  return fs
end

-- ------------------------------------------------------------------------------------------------ update
function Tracker.Update()
  if not Tracker.frame or Tracker.sizing then return end
  local f, d = Tracker.frame, cfg()
  local size = d.fontSize or 12
  local list = HHQ.Data.List()
  local shown, label = Tracker.Select(list)
  local done = 0
  for _, q in ipairs(list) do if q.complete then done = done + 1 end end
  f.title:SetText(("%s  %d/%d"):format(label, #shown, #list))
  f.hint:SetText(d.collapsed and "+" or "-")
  applyFont(f.title, size)
  applyFont(f.hint, size)
  f.header:SetHeight(math.max(HEADER_H, size + 8))

  for _, b in ipairs(Tracker.titles) do b:Hide() end
  for _, fs in ipairs(Tracker.lines) do fs:Hide() end
  f.empty:Hide()

  local y, ti, li = 0, 0, 0
  local maxH = Tracker.MaxHeight(f, d, size)
  local titleH, lineH = size + 6, size + 3
  local more = 0
  -- scroll position = index of the first quest drawn; clamped to the list (quests get turned in under it)
  local offset = math.max(0, math.min(Tracker.offset or 0, math.max(#shown - 1, 0)))
  Tracker.offset, Tracker.lastShown = offset, #shown
  if not d.collapsed then
    if #list == 0 then
      f.empty:SetText(HHQ.Data.Available() and "No quests in your log" or "This client does not share the quest log")
      applyFont(f.empty, size)
      f.empty:Show()
      y = lineH
    end
    for n = offset + 1, #shown do
      local q = shown[n]
      local need = titleH + (q.complete and lineH or #q.objectives * lineH) + 4
      if y + need > maxH and ti > 0 then more = #shown - n + 1 break end
      ti = ti + 1
      local b = titleButton(ti)
      b.quest = q
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -y)
      b:SetPoint("RIGHT", f.body, "RIGHT", 0, 0)
      b:SetHeight(titleH)
      local lvl = (d.showLevels ~= false and type(q.level) == "number") and ("[" .. q.level .. "] ") or ""
      b.label:SetText(lvl .. tostring(q.title))
      applyFont(b.label, size)
      if q.complete then b.label:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
      elseif q.failed then b.label:SetTextColor(0.85, 0.2, 0.2)
      else b.label:SetTextColor(Tracker.LevelColor(q.level)) end
      b:Show()
      y = y + titleH
      if q.complete then
        li = li + 1
        local fs = objLine(li)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", f.body, "TOPLEFT", 10, -y)
        fs:SetPoint("RIGHT", f.body, "RIGHT", 0, 0)
        fs:SetText("Ready to turn in")
        fs:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
        applyFont(fs, size - 1)
        fs:Show()
        y = y + lineH
      else
        for _, o in ipairs(q.objectives) do
          li = li + 1
          local fs = objLine(li)
          fs:ClearAllPoints()
          fs:SetPoint("TOPLEFT", f.body, "TOPLEFT", 10, -y)
          fs:SetPoint("RIGHT", f.body, "RIGHT", 0, 0)
          fs:SetText("- " .. tostring(o.text))
          local c = o.done and GREY or CREAM
          fs:SetTextColor(c[1], c[2], c[3])
          applyFont(fs, size - 1)
          fs:Show()
          y = y + lineH
        end
      end
      y = y + 4
    end
    -- Sean 2026-10-01: "+7 more" is not wanted - the list runs to the bottom of the screen and the wheel scrolls it.
    -- When it still does not fit (small screen, huge log) one quiet grey line says what is above / below.
    if more > 0 or offset > 0 then
      li = li + 1
      local fs = objLine(li)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -y)
      fs:SetPoint("RIGHT", f.body, "RIGHT", 0, 0)   -- 2026-09-22 in game: unanchored, this line ran off the panel
      local parts = {}
      if offset > 0 then parts[#parts + 1] = ("%d above"):format(offset) end
      if more > 0 then parts[#parts + 1] = ("%d below"):format(more) end
      fs:SetText("scroll:  " .. table.concat(parts, "  -  "))
      fs:SetTextColor(GREY[1], GREY[2], GREY[3])
      applyFont(fs, size - 1)
      fs:Show()
      y = y + lineH
    end
  end
  f.body:SetHeight(math.max(y, 1))
  f:SetSize(d.width or 260, math.max(HEADER_H, size + 8) + (d.collapsed and 0 or (y + 8)))
  f:SetScale(d.scale or 1)
  f.bg:SetColorTexture(INK[1], INK[2], INK[3], d.backgroundAlpha or 0.6)
  Tracker.shownCount, Tracker.moreCount = ti, more
end

--- The grip was let go: the panel's new width becomes the width option; its new bottom edge becomes the fill gap
-- (fill on) or the max height (fill off). Then a normal repaint.
function Tracker.TakeSize()
  local f, d = Tracker.frame, cfg()
  if not f then return end
  local w = f.GetWidth and f:GetWidth()
  if type(w) == "number" and w >= 160 then d.width = math.floor(w + 0.5) end
  local h = f.GetHeight and f:GetHeight()
  if d.fill ~= false then
    local bottom = f.GetBottom and f:GetBottom()
    if type(bottom) == "number" and bottom >= 0 then d.bottomMargin = math.floor(bottom * (d.scale or 1) + 0.5) end
  elseif type(h) == "number" and h > 80 then
    d.maxHeight = math.floor(h - math.max(HEADER_H, (d.fontSize or 12) + 8) - 8 + 0.5)
  end
  Tracker.Update()
end

--- /hh unlock: cyan edges and the resize grip; /hh lock: back to normal.
function Tracker.SetUnlocked(unlocked)
  local f = Tracker.frame
  if not f then return end
  local c = unlocked and CYAN or LINE
  for _, e in ipairs(f.edges or {}) do e:SetColorTexture(c[1], c[2], c[3], 1) end
  if f.grip then if unlocked then f.grip:Show() else f.grip:Hide() end end
  Tracker.unlocked = unlocked and true or false
end

--- Height the list may take. fill (default): from the panel's top down to the screen's bottom edge, minus the
-- bottomMargin option, in the panel's own units (GetTop is already in those). Otherwise the Max height slider.
-- A client that cannot tell us where the top is (nil / 0 before the first layout) gets the slider too.
function Tracker.MaxHeight(f, d, size)
  if d.fill ~= false then
    local top = f and f.GetTop and f:GetTop()
    if type(top) == "number" and top > 0 then
      local h = top - ((d.bottomMargin or 20) / (d.scale or 1)) - math.max(HEADER_H, size + 8) - 8
      if h >= 60 then return h end
    end
  end
  return d.maxHeight or 420
end

--- Mouse wheel: down (delta < 0) shows the next quest, up the previous. Never past either end.
function Tracker.Scroll(delta)
  if type(delta) ~= "number" or delta == 0 then return end
  local o = Tracker.offset or 0
  if delta < 0 then
    if (Tracker.moreCount or 0) == 0 then return end
    o = o + 1
  else
    if o == 0 then return end
    o = o - 1
  end
  Tracker.offset = o
  Tracker.Update()
end

--- Coalesce bursts (QUEST_LOG_UPDATE fires several times per kill) into one repaint.
function Tracker.Schedule()
  if Tracker.pending then return end
  Tracker.pending = true
  local function run() Tracker.pending = false; if Tracker.frame and Tracker.frame:IsShown() then Tracker.Update() end end
  if C_Timer and C_Timer.After then C_Timer.After(0.1, run) else run() end
end

Tracker.MODES = { watched = "Watched (all when none)", zone = "This zone + watched", all = "Every quest" }
local ORDER = { "watched", "zone", "all" }
function Tracker.CycleMode()
  local cur = cfg().mode or "watched"
  for i, m in ipairs(ORDER) do if m == cur then cfg().mode = ORDER[i % #ORDER + 1] break end end
  Tracker.Update()
end

function Tracker.SetCollapsed(v)
  cfg().collapsed = v and true or false
  Tracker.Update()
end

-- ------------------------------------------------------------------------------------------------ Blizzard's tracker
local hiddenParent
-- What we remember about Blizzard's frames lives HERE, never as fields on the frames themselves: a field written by
-- an addon on a Blizzard frame is tainted, and Edit Mode walks its system frames (the objective tracker is one)
-- inside Blizzard's own layout pass. In game 2026-09-29: "Auras cannot be accessed when secret while tainted by
-- 'HogHeals_Quests'" out of EditModeManager's anchor pass.
local hooked = setmetatable({}, { __mode = "k" })
local busy = setmetatable({}, { __mode = "k" })
Tracker.blizzHooked = hooked
-- 2026-09-22 in game: Blizzard's modern tracker ("All Objectives") was back on screen next to ours. Blizzard's
-- tracker is its own addon and can load AFTER us (Quests.lua re-applies on its ADDON_LOADED), and its manager can
-- re-show / re-parent it on updates, so every banished frame also gets hooks that put it back in the hidden parent.
local function banish(f)
  if type(f) ~= "table" then return end
  if f.UnregisterAllEvents then pcall(f.UnregisterAllEvents, f) end
  if f.Hide then pcall(f.Hide, f) end
  if f.SetParent then pcall(f.SetParent, f, hiddenParent) end
  if not hooked[f] and type(hooksecurefunc) == "function" then
    hooked[f] = true
    local function again(self)
      local d = cfg()
      if d.enabled == false or d.hideBlizzard == false or busy[self] then return end
      busy[self] = true
      if not (InCombatLockdown and InCombatLockdown()) then
        if self.GetParent and self:GetParent() ~= hiddenParent and self.SetParent then pcall(self.SetParent, self, hiddenParent) end
      end
      if self.Hide then pcall(self.Hide, self) end
      busy[self] = nil
    end
    if f.Show then pcall(hooksecurefunc, f, "Show", again) end
    if f.SetParent then pcall(hooksecurefunc, f, "SetParent", again) end
  end
end

function Tracker.ApplyBlizzard()
  local d = cfg()
  if d.enabled == false or d.hideBlizzard == false then return end
  if not HHQ.Data.Available() then return end   -- never leave the player with no tracker at all
  HH:RunOutOfCombat(function()
    hiddenParent = hiddenParent or _G.HogHealsHiddenParent
    if not hiddenParent then
      hiddenParent = CreateFrame("Frame", "HogHealsHiddenParent", UIParent)
      hiddenParent:Hide()
    end
    banish(_G.ObjectiveTrackerFrame)
    Tracker.hidBlizzard = _G.ObjectiveTrackerFrame ~= nil or _G.QuestWatchFrame ~= nil or _G.WatchFrame ~= nil
    banish(_G.QuestWatchFrame)
    banish(_G.WatchFrame)
  end)
end

function Tracker.Show()
  build():Show()
  Tracker.Update()
end

function Tracker.Hide() if Tracker.frame then Tracker.frame:Hide() end end

function Tracker.Toggle()
  local d = cfg()
  d.enabled = not (Tracker.frame and Tracker.frame:IsShown())
  if d.enabled then Tracker.ApplyBlizzard(); Tracker.Show() else Tracker.Hide() end
end

function Tracker.Refresh()
  local d = cfg()
  if d.enabled == false then Tracker.Hide() return end
  Tracker.ApplyBlizzard()
  build()
  Tracker.Anchor()
  Tracker.Show()
end
