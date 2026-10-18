-- EditMode: /hh unlock works like Blizzard's Edit Mode. Sean 2026-10-06: "if I click on something in the unlock screen I
-- should be able to resize or get options to adjust from there" + "a centering option, vertically or horizontally".
--
-- While unlocked:
--   * a plain drag box (action bars, party / raid frame anchor, HUD anchor): click it (no drag) -> its settings
--   * a frame that does something when clicked (unit frames target, the tracker header folds, the info bar opens bags,
--     the menu bar opens windows) gets a small gear in its corner instead -> its settings
-- The settings open in the options window in compact form beside the frame: only that frame's section (scale, size,
-- buttons, rows ... whatever its options already are), plus Position: Center horizontally / vertically / full settings.
--
-- Sean 2026-10-18: "easily change the size of the cast bar, the manabar, different things ... add all of that to HH
-- unlock". Each HUD bar (cast bar, swing timer, mana bar, info line) is its own box now - click it for ITS size, drag
-- it to move the whole strip - and every frame with a size has a cyan grip in its corner: drag it to resize (right =
-- wider, down = taller; action bars scale). The HUD strip itself has a gear (its bars' boxes cover it).
--
-- Centering moves the frame onto the screen's centre line and then runs the frame's OWN drag-stop handler, so it is
-- saved exactly the way a drag would save it. Every handler here saves point / x / y and lays out with the same point
-- on both sides, so CENTER-on-CENTER round-trips.
local HH = HogHeals

local EM = { cogs = {}, attached = {}, byFrame = {} }
HH.EditMode = EM

local CYAN, INK = { 0.13, 0.83, 0.88 }, { 0.07, 0.07, 0.09 }
local GEAR = "Interface\\Icons\\INV_Misc_Gear_01"

local function G(name) return rawget(_G, name) end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
end
local function locked() return not (HH.db and HH.db.profile and HH.db.profile.locked == false) end

-- the HUD strip's bars, each its own box in edit mode (the info line's height lives in the strip's layout section)
EM.HUD_ROWS = { { name = "castbar", path = "HUD.castbar", title = "Cast bar" }, { name = "swing", path = "HUD.swing", title = "Swing timer" },
  { name = "mana", path = "HUD.mana", title = "Mana bar" }, { name = "info", path = "HUD.layout", title = "Info line" } }

-- unit frame globals (Units.GLOBAL_NAME) -> their options section
EM.UNITS = { player = "HogUIPlayer", target = "HogUITarget", targettarget = "HogUITargetOfTarget", pet = "HogUIPet", focus = "HogUIFocus" }
EM.UNIT_LABEL = { player = "Player frame", target = "Target frame", targettarget = "Target of target", pet = "Pet frame", focus = "Focus frame" }

--- Everything editable right now: { key, path, title, mover, saver, how = "click" | "gear" }. Only frames that exist.
function EM.Targets()
  local out = {}
  local function add(t) if t.mover then out[#out + 1] = t end end
  local B = G("HogHealsBars")
  if type(B) == "table" and B.Bars and B.Bars.bars then
    for n, bar in pairs(B.Bars.bars) do
      if bar.handle then
        local title = type(n) == "number" and ("Action bar %d"):format(n) or (n == "pet" and "Pet bar") or (n == "stance" and "Stance bar") or tostring(n)
        add({ key = "bar:" .. tostring(n), path = "Bars.bar" .. tostring(n), title = title, mover = bar, saver = bar.handle, clickFrame = bar.handle, how = "click" })
      end
    end
  end
  add({ key = "frames", path = "Frames.layout", title = "Party / raid frames", mover = G("HogHealsAnchor"), how = "click" })
  local hudAnchor = G("HogHealsHUDAnchor")
  -- shown in unlock by the HUD module itself (which may run after us): its gear is shown regardless
  add({ key = "hud", path = "HUD.layout", title = "HUD", mover = hudAnchor, how = "gear", alwaysShown = true })
  local HHD = G("HogHealsHUD")
  local rows = type(HHD) == "table" and type(HHD.HUD) == "table" and HHD.HUD.rows or nil
  if type(rows) == "table" and hudAnchor then
    for _, r in ipairs(EM.HUD_ROWS) do
      local row = rows[r.name]
      if type(row) == "table" and row.enabled then
        -- a detached bar moves on its own (its box drags the bar, Center centres the bar); else the whole strip
        add({ key = "hud:" .. r.name, path = r.path, title = row.detached and (r.title .. " (on its own)") or r.title,
          mover = row.detached and row or hudAnchor, frame = row, how = "box" })
      end
    end
  end
  add({ key = "xp", path = "HUD.xp", title = "Experience bar", mover = G("HogHealsXPBar"), how = "gear" })
  local tracker = G("HogHealsQuestTracker")
  add({ key = "tracker", path = "Quests.tracker", title = "Quest tracker", mover = tracker, saver = tracker and tracker.header, how = "gear" })
  local meter = G("HogHealsMeterFrame")
  add({ key = "meter", path = "Meter", title = "Meter", mover = meter, saver = meter and meter.header, how = "gear" })
  for unit, name in pairs(EM.UNITS) do
    add({ key = "unit:" .. unit, path = "Units." .. unit, title = EM.UNIT_LABEL[unit], mover = G(name), how = "gear" })
  end
  add({ key = "infobar", path = "Skin.infobar", title = "Info bar", mover = G("HogUIInfoBar"), how = "gear" })
  add({ key = "tooltip", path = "Skin.tooltips", title = "Tooltips", mover = G("HogHealsTooltipAnchor"), how = "gear" })
  add({ key = "micro", path = "Skin.micro", title = "Menu bar", mover = G("HogHealsMicroBar"), how = "gear" })
  table.sort(out, function(a, b) return a.key < b.key end)
  return out
end

--- The options group at "Top.sub" in the live options table, or nil.
function EM.Find(path)
  local ok, node = pcall(HH.OptionsTable)
  if not ok or type(node) ~= "table" then return nil end
  for seg in path:gmatch("[^%.]+") do
    node = type(node.args) == "table" and node.args[seg] or nil
    if type(node) ~= "table" then return nil end
  end
  return node
end

-- ------------------------------------------------------------------------------------------------ centring
--- Move the target's frame onto the screen's centre line (axis "h" = left-right, "v" = up-down) and save it with the
-- frame's own drag-stop handler. Returns true, or false + why.
function EM.Center(t, axis)
  if InCombatLockdown and InCombatLockdown() then return false, "not in combat" end
  local f = t and t.mover
  if not f then return false, "no frame" end
  local cx, cy = call(f.GetCenter, f)
  local ux, uy = UIParent:GetCenter()
  local fs, us = call(f.GetEffectiveScale, f) or 1, UIParent:GetEffectiveScale() or 1
  if type(cx) ~= "number" or type(ux) ~= "number" or fs == 0 then return false, "the frame is not placed yet" end
  local r = us / fs                                   -- UIParent units -> this frame's units
  local dx, dy = cx - ux * r, cy - uy * r
  if axis == "h" then dx = 0 elseif axis == "v" then dy = 0 else dx, dy = 0, 0 end
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", dx, dy)
  local saver = t.saver or f
  local stop = saver.GetScript and saver:GetScript("OnDragStop")
  if type(stop) == "function" then
    local ok, err = pcall(stop, saver)
    if not ok then HH:LogError("edit mode centre " .. t.key .. ": " .. tostring(err)) return false, "could not save" end
  end
  EM.lastCenter = { key = t.key, axis = axis, x = dx, y = dy }
  return true
end

-- ------------------------------------------------------------------------------------------------ the popup
--- An options source for the compact window: the target's own section, with Position on top.
function EM.Source(t)
  return function()
    local g = EM.Find(t.path)
    local args = {
      hhPosition = { type = "group", inline = true, order = 0, name = "Position", args = {
        centerH = { type = "execute", order = 1, name = "Center horizontally", func = function()
          local ok, why = EM.Center(t, "h") if not ok then HH:Print("edit: " .. tostring(why)) end end },
        centerV = { type = "execute", order = 2, name = "Center vertically", func = function()
          local ok, why = EM.Center(t, "v") if not ok then HH:Print("edit: " .. tostring(why)) end end },
        full = { type = "execute", order = 3, name = "All settings", func = function() EM.OpenFull(t.path) end },
      } },
    }
    if g then for k, v in pairs(g.args or {}) do args[k] = v end end
    return { type = "group", args = { edit = { type = "group", order = 1, name = t.title, handler = g and g.handler, args = args } } }
  end
end

function EM.Open(t)
  if not t then return false end
  if not EM.Find(t.path) then HH:Print(("edit: no settings found for %s (%s)"):format(t.title, t.path)) end
  local P = HH.Panel
  if not P or not P.Open then return false end
  P.Open(EM.Source(t), { compact = true, anchor = t.mover, title = t.title, actions = P.ActionsFor and P.ActionsFor(t.key) or nil })
  EM.current = t
  return true
end

--- The full options window on the target's section ("Bars.bar2" -> Bars tab, bar2 sub-tab).
function EM.OpenFull(path)
  local P = HH.Panel
  if not P then return end
  local top, sub = path:match("^([^%.]+)%.?(.*)$")
  P.selected, P.selectedTab = top, (sub ~= "" and sub or nil)
  P.Open()
end

-- ------------------------------------------------------------------------------------------------ sizes
local function prof() return HH.db and HH.db.profile end
local function num(v, d) if type(v) == "number" then return v end return d end
local function hudRefresh() local H = G("HogHealsHUD") if type(H) == "table" and H.HUD and H.HUD.Refresh then pcall(H.HUD.Refresh) end end
local function unitsRefresh() local U = G("HogHealsUnits") if type(U) == "table" and U.Units and U.Units.Refresh then HH:RunOutOfCombat(U.Units.Refresh) end end
local function barsApply() local B = G("HogHealsBars") if type(B) == "table" and B.Bars and B.Bars.Apply then HH:RunOutOfCombat(B.Bars.Apply, "edit resize") end end
EM.ROW_HEIGHT = { castbar = "castbarHeight", swing = "swingHeight", mana = "manaHeight", info = "infoHeight" }

--- What dragging a target's grip changes: { w = dim, h = dim, s = dim, apply = fn } (dim = get / set / min / max /
-- step / factor), or nil when it has no size. factor 2 = the frame grows both ways from its centre, so the grip keeps
-- up with the cursor.
function EM.ResizeFor(t)
  local p = prof()
  if not p or not t then return nil end
  local key = t.key
  local hud = p.hud
  local row = key:match("^hud:(.+)$")
  if row and type(hud) == "table" then
    local spec = { apply = hudRefresh }
    local sub = hud[row]
    if row ~= "info" and type(sub) == "table" then
      spec.w = { get = function() local w = num(sub.width, 0) return w > 0 and w or num(hud.width, 300) end,
        set = function(v) sub.width = v end, min = 60, max = 800, step = 2, factor = 2 }
    end
    local hk = EM.ROW_HEIGHT[row]
    spec.h = { get = function() return num(hud[hk], 12) end, set = function(v) hud[hk] = v end, min = 4, max = 40, step = 1 }
    return spec
  end
  if key == "xp" and type(hud) == "table" and type(hud.xp) == "table" then
    local x = hud.xp
    return { apply = hudRefresh,
      w = { get = function() local w = num(x.width, 0) if w > 0 then return w end local f = G("HogHealsXPBar") return num(f and call(f.GetWidth, f), 1000) end,
        set = function(v) x.width = v end, min = 100, max = 2000, step = 10, factor = 2 },
      h = { get = function() return num(x.height, 10) end, set = function(v) x.height = v end, min = 4, max = 30, step = 1 } }
  end
  local unit = key:match("^unit:(.+)$")
  if unit and type(p.units) == "table" and type(p.units[unit]) == "table" then
    local u = p.units[unit]
    return { apply = unitsRefresh,
      w = { get = function() return num(u.width, 200) end, set = function(v) u.width = v end, min = 80, max = 500, step = 5, factor = 2 },
      h = { get = function() return num(u.height, 40) end, set = function(v) u.height = v end, min = 16, max = 120, step = 1 } }
  end
  if key == "frames" then
    -- party / raid cells: the layout of the group size you are in now (solo shares party's by default), the same table
    -- and the same re-apply the Frames options use (ApplyProfile queues itself in combat)
    local F = G("HogHealsFrames")
    local mod = type(F) == "table" and F.module or nil
    local function lay() return mod and mod.LayoutFor and mod:LayoutFor() or nil end
    if type(lay()) ~= "table" then return nil end
    local function relayout() if mod.ApplyProfile then pcall(mod.ApplyProfile, mod, mod.bucket) end end
    return { apply = relayout,
      w = { get = function() return num(lay().width, 90) end, set = function(v) lay().width = v end, min = 40, max = 300, step = 1 },
      h = { get = function() return num(lay().height, 60) end, set = function(v) lay().height = v end, min = 12, max = 80, step = 1 } }
  end
  local bar = key:match("^bar:(.+)$")
  if bar and type(p.bars) == "table" and type(p.bars.list) == "table" then
    local bd = p.bars.list[tonumber(bar) or bar]
    if type(bd) == "table" then
      return { apply = barsApply, s = { get = function() return num(bd.scale, 1) end, set = function(v) bd.scale = v end, min = 0.5, max = 2, step = 0.05 } }
    end
  end
  return nil
end

local function cursor()
  local x, y = call(G("GetCursorPosition"))
  local sc = num(UIParent.GetEffectiveScale and UIParent:GetEffectiveScale(), 1)
  if sc == 0 then sc = 1 end
  return num(x, 0) / sc, num(y, 0) / sc
end

local function snap(v, d)
  v = math.max(d.min, math.min(d.max, v))
  local st = d.step or 1
  return math.floor(v / st + 0.5) * st
end

--- Start a resize from the cursor (the grip's mouse-down). Out of combat only (bars and unit frames are secure).
function EM.BeginResize(t)
  if not t or not t.resize then return false end
  if InCombatLockdown and InCombatLockdown() then HH:Print("edit: not in combat") return false end
  local R = t.resize
  local x, y = cursor()
  local ref = t.box or t.clickFrame or t.mover
  EM.resizing = { t = t, x = x, y = y, w = R.w and R.w.get(), h = R.h and R.h.get(), s = R.s and R.s.get(),
    ref = math.max(1, num(ref and call(ref.GetWidth, ref), 100)) }
  EM.driver = EM.driver or CreateFrame("Frame")
  EM.driver:SetScript("OnUpdate", function()
    local r = EM.resizing
    if not r then return end
    local cx, cy = cursor()
    EM.ResizeStep(cx - r.x, cy - r.y)
  end)
  return true
end

--- The cursor moved dx right / dy up since the grip was grabbed: right = wider, down = taller, right = bigger scale.
-- Applies only a change (snapped to the setting's step, inside its range). Returns true when something changed.
function EM.ResizeStep(dx, dy)
  local r = EM.resizing
  if not r then return false end
  local R, changed = r.t.resize, false
  if R.w and r.w then local v = snap(r.w + dx * (R.w.factor or 1), R.w) if v ~= R.w.get() then R.w.set(v) changed = true end end
  if R.h and r.h then local v = snap(r.h - dy, R.h) if v ~= R.h.get() then R.h.set(v) changed = true end end
  if R.s and r.s then local v = snap(r.s * (r.ref + dx) / r.ref, R.s) if math.abs(v - R.s.get()) > 1e-6 then R.s.set(v) changed = true end end
  if changed and R.apply then R.apply() end
  return changed
end

function EM.EndResize()
  local r = EM.resizing
  if EM.driver then EM.driver:SetScript("OnUpdate", nil) end
  EM.resizing = nil
  if not r then return false end
  EM.lastResize = r.t.key
  -- an open settings panel for this frame: reopened so its sliders show the new numbers
  local P = HH.Panel
  if EM.current == r.t and P and P.compact and P.frame and P.frame:IsShown() then EM.Open(r.t) end
  return true
end

EM.grips = {}
local function grip(t, onFrame)
  local g = EM.grips[t.key]
  if not g then
    g = CreateFrame("Frame", nil, UIParent)
    g:SetSize(12, 12)
    g:SetFrameStrata("DIALOG")
    g:EnableMouse(true)
    g.edge = g:CreateTexture(nil, "BACKGROUND")
    g.edge:SetAllPoints(g)
    g.edge:SetColorTexture(INK[1], INK[2], INK[3], 1)
    g.fill = g:CreateTexture(nil, "ARTWORK")
    g.fill:SetPoint("TOPLEFT", g, "TOPLEFT", 2, -2)
    g.fill:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -2, 2)
    g.fill:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 1)
    g:SetScript("OnMouseDown", function(self, button) if button == "LeftButton" then EM.BeginResize(self.target) end end)
    g:SetScript("OnMouseUp", function() EM.EndResize() end)
    g:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine((self.target and self.target.title or "?") .. ": drag to resize")
      GameTooltip:Show()
    end)
    g:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    EM.grips[t.key] = g
  end
  g.target = t
  g:ClearAllPoints()
  g:SetPoint("CENTER", onFrame, "BOTTOMRIGHT", 0, 0)
  g:Show()
  return g
end

EM.boxes = {}
--- A click / drag box over a frame that has no box of its own (the HUD's bars): click = its settings, drag = move the
-- frame it belongs to (through that frame's own drag handlers, so it saves the same way).
local function box(t)
  local b = EM.boxes[t.key]
  if not b then
    b = CreateFrame("Frame", nil, UIParent)
    b:SetFrameStrata("HIGH")
    b:EnableMouse(true)
    if b.RegisterForDrag then b:RegisterForDrag("LeftButton") end
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(b)
    b.bg:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.22)
    b.label = b:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
    b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
    local function relay(self, script)
      local d = self.target and self.target.mover
      local f = d and d.GetScript and d:GetScript(script)
      if type(f) == "function" then pcall(f, d) end
    end
    b:SetScript("OnDragStart", function(self) self.hhDragged = true relay(self, "OnDragStart") end)
    b:SetScript("OnDragStop", function(self) relay(self, "OnDragStop") end)
    b:SetScript("OnMouseUp", function(self, button)
      if locked() then return end
      if self.hhDragged then self.hhDragged = nil return end
      if button == "LeftButton" or button == "RightButton" then EM.Open(self.target) end
    end)
    EM.boxes[t.key] = b
  end
  b.target = t
  b.label:SetText(t.title)
  b:ClearAllPoints()
  b:SetAllPoints(t.frame)
  b:Show()
  t.box = b
  return b
end

-- ------------------------------------------------------------------------------------------------ click + gears
local function attachClick(t)
  local f = t.clickFrame or t.mover
  EM.byFrame[f] = t
  -- say what a click does (Sean 2026-10-06: "what cyan block on the action bar?")
  if f.label and f.label.SetText then f.label:SetText(t.title .. "  -  drag, or click for settings") end
  if EM.attached[f] or not f.HookScript then return end
  EM.attached[f] = true
  f:HookScript("OnDragStart", function(self) self.hhDragged = true end)
  f:HookScript("OnMouseUp", function(self, button)
    if locked() then return end
    if self.hhDragged then self.hhDragged = nil return end
    if button == "LeftButton" or button == "RightButton" then EM.Open(EM.byFrame[self]) end
  end)
end

local function gear(t)
  local b = EM.cogs[t.key]
  if not b then
    b = CreateFrame("Button", nil, UIParent)
    b:SetSize(18, 18)
    b:SetFrameStrata("DIALOG")
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
    b.bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
    b.bg:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.icon:SetTexture(GEAR)
    if b.icon.SetTexCoord then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    b:SetScript("OnClick", function(self) EM.Open(self.target) end)
    b:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine((self.target and self.target.title or "?") .. ": settings")
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    EM.cogs[t.key] = b
  end
  b.target = t
  b:ClearAllPoints()
  b:SetPoint("TOPRIGHT", t.mover, "TOPRIGHT", 6, 6)
  if t.alwaysShown or (t.mover.IsShown and t.mover:IsShown()) then b:Show() else b:Hide() end
  return b
end

function EM.SetUnlocked(unlocked)
  if unlocked then
    local n = 0
    local live = {}
    for _, t in ipairs(EM.Targets()) do
      if t.how == "gear" then gear(t) elseif t.how == "box" then box(t) else attachClick(t) end
      live[t.key] = true
      t.resize = EM.ResizeFor(t)
      if t.resize then grip(t, t.box or t.clickFrame or t.mover) elseif EM.grips[t.key] then EM.grips[t.key]:Hide() end
      n = n + 1
    end
    -- a bar switched off since the last unlock: its box and grip go
    for key, g in pairs(EM.grips) do if not live[key] then g:Hide() end end
    for key, b in pairs(EM.boxes) do if not live[key] then b:Hide() end end
    EM.count = n
    if not EM.hinted then
      EM.hinted = true
      HH:Print("edit mode: click a cyan box, or the gear on a frame, for its settings and centring; drag a corner grip to resize.")
    end
  else
    for _, b in pairs(EM.cogs) do b:Hide() end
    for _, b in pairs(EM.boxes) do b:Hide() end
    for _, g in pairs(EM.grips) do g:Hide() end
    EM.EndResize()
    local P = HH.Panel
    if P and P.compact and P.frame and P.frame:IsShown() then P.frame:Hide() end
  end
  EM.unlocked = unlocked and true or false
end

HH:RegisterModule("EditMode", { SetLocked = function(_, isLocked) EM.SetUnlocked(not isLocked) end })
