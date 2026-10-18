-- HogTron UI Bars: our own action bars on LibActionButton-1.0 (the engine Bartender / ElvUI run on), Blizzard's hidden.
--
-- Sean 2026-10-02: "make the action bars section of HogTron UI a separate thing, kind of like Bartender: always show
-- the slots, turn them on and off, quick binding (click a button, hover a slot, hit the key)".
-- Design: docs/superpowers/specs/2026-10-02-hogui-bars-design.md. This file: the bars (frames, slot mapping,
-- paging, layout, the flat look, the Blizzard hide, dragging); bind mode lives in Bind.lua.
--
-- Secret-safe by construction: the lib owns every cooldown / count / range read; we do layout, config, bindings
-- and the look. Nothing here does arithmetic on button state.
HogHealsBars = HogHealsBars or {}
local HHB = HogHealsBars
local HH = HogHeals

local Bars = { bars = {}, found = {}, missing = {} }
HHB.Bars = Bars

local CREAM = { 0.96, 0.92, 0.86 }
local CYAN = { 0.13, 0.83, 0.88 }
local LINE = { 0.20, 0.20, 0.25 }
local INK = { 0.10, 0.10, 0.12 }
Bars.SIZE = 36            -- button size before the bar's scale
Bars.LEVEL = 30           -- frame level of our bars (Blizzard's bottom-of-screen frames sit well under it)
Bars.PAGES = 14           -- states bar 1 carries (pages 1-6, bonus 7-10, vehicle / shapeshift / override 12-14)

local function cfg() return HH.db.profile.bars end
Bars.cfg = cfg
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
end

--- The lib, if this client loaded it (stubbed in the harness; real only in game).
function Bars.Lib()
  return LibStub and LibStub("LibActionButton-1.0", true)
end

-- Which Blizzard slots each bar shows, the binding name of each slot (so every existing keybind keeps firing),
-- and Blizzard's own frame + buttons to hide. Bar 1 is paged; the rest are fixed.
Bars.SPECS = {
  [1] = { slot = 1,   bind = "ACTIONBUTTON%d",          blizzard = "ActionButton",             bar = "MainMenuBar",        paged = true, label = "Bar 1 (main, pages)" },
  [2] = { slot = 61,  bind = "MULTIACTIONBAR1BUTTON%d", blizzard = "MultiBarBottomLeftButton", bar = "MultiBarBottomLeft", label = "Bar 2 (bottom left)" },
  [3] = { slot = 49,  bind = "MULTIACTIONBAR2BUTTON%d", blizzard = "MultiBarBottomRightButton", bar = "MultiBarBottomRight", label = "Bar 3 (bottom right)" },
  [4] = { slot = 25,  bind = "MULTIACTIONBAR3BUTTON%d", blizzard = "MultiBarRightButton",      bar = "MultiBarRight",      label = "Bar 4 (right)" },
  [5] = { slot = 37,  bind = "MULTIACTIONBAR4BUTTON%d", blizzard = "MultiBarLeftButton",       bar = "MultiBarLeft",       label = "Bar 5 (right 2)" },
  [6] = { slot = 145, bind = "MULTIACTIONBAR5BUTTON%d", blizzard = "MultiBar5Button",          bar = "MultiBar5",          label = "Bar 6" },
  [7] = { slot = 157, bind = "MULTIACTIONBAR6BUTTON%d", blizzard = "MultiBar6Button",          bar = "MultiBar6",          label = "Bar 7" },
  [8] = { slot = 169, bind = "MULTIACTIONBAR7BUTTON%d", blizzard = "MultiBar7Button",          bar = "MultiBar7",          label = "Bar 8" },
}
Bars.HIDE_EXTRA = { "ActionBarUpButton", "ActionBarDownButton", "MainMenuBarPerformanceBarFrame", "MainMenuBarVehicleLeaveButton" }

--- Bar 1's page driver, built the way Blizzard builds its own (the special pages come from the client, so a client
-- that numbers them differently still gets the right ones): override, temp shapeshift, vehicle / possess, pages
-- 2-6, bonus bars 1-4 (stances / forms), else 1.
function Bars.PageDriver()
  local parts = {}
  local ov = type(GetOverrideBarIndex) == "function" and call(GetOverrideBarIndex)
  if type(ov) == "number" then parts[#parts + 1] = "[overridebar]" .. ov end
  local ts = type(GetTempShapeshiftBarIndex) == "function" and call(GetTempShapeshiftBarIndex)
  if type(ts) == "number" then parts[#parts + 1] = "[shapeshift]" .. ts end
  local vh = type(GetVehicleBarIndex) == "function" and call(GetVehicleBarIndex)
  if type(vh) == "number" then parts[#parts + 1] = "[vehicleui]" .. vh parts[#parts + 1] = "[possessbar]" .. vh end
  for i = 2, 6 do parts[#parts + 1] = ("[bar:%d]%d"):format(i, i) end
  for i = 1, 4 do parts[#parts + 1] = ("[bonusbar:%d]%d"):format(i, 6 + i) end
  parts[#parts + 1] = "1"
  return table.concat(parts, ";")
end

-- ------------------------------------------------------------------------------------------------ the look
--- The HogTron UI cell on a lib button: Blizzard's slot art off, ink backdrop + 1 px outline, trimmed icon. The
-- backdrop and outline double as the grid: shown for an empty slot only when the grid is on.
-- What you see = what you can click (Sean 2026-10-17, third report: the lower part of a bar-1 button took no hover; in
-- game diag.barsMouse said NO frame had the mouse there - not Blizzard's, not ours). The stock button template draws its
-- icon and cooldowns at its own fixed size from the top-left corner; on a button made smaller than the template they
-- hang out past the button's clickable area - you see the bottom of the icon, the mouse finds nothing. The same
-- overhang puts the cooldown swipe off the cell. Pinned to the button here, and the hit area to its very edges.
Bars.PINNED = { "icon", "cooldown", "chargeCooldown", "lossOfControlCooldown" }
function Bars.PinToButton(b)
  local n = 0
  for _, k in ipairs(Bars.PINNED) do
    local r = rawget(b, k)
    if type(r) == "table" and r.ClearAllPoints and r.SetAllPoints then
      call(r.ClearAllPoints, r)
      call(r.SetAllPoints, r, b)
      n = n + 1
    end
  end
  if b.SetHitRectInsets then call(b.SetHitRectInsets, b, 0, 0, 0, 0) end
  return n
end

--- Where bar 1's first button really is versus what it draws (for /hh barsdiag and diag.barsGeometry): rects in screen
-- px (left, right, top, bottom), hit insets, mouse on. Saved once a few seconds after login - no command needed.
function Bars.GeometryLines()
  local out = {}
  local bar = Bars.bars[1]
  local b = bar and bar.buttons and bar.buttons[1]
  if type(b) ~= "table" then return out end
  local function rect(f, label)
    if type(f) ~= "table" then out[#out + 1] = label .. ": none" return end
    local s = call(f.GetEffectiveScale, f) or 1
    local l, r, t, bo = call(f.GetLeft, f), call(f.GetRight, f), call(f.GetTop, f), call(f.GetBottom, f)
    -- frame positions can come back hidden on this client: written "S", never used (the first version did arithmetic on
    -- them, threw inside its pcall and saved nothing - 2026-10-17)
    local hiddenV = type(issecretvalue) == "function" and issecretvalue
    if hiddenV and hiddenV(s) then s = 1 end
    local function px(v)
      if hiddenV and hiddenV(v) then return "S" end
      return type(v) == "number" and ("%d"):format(math.floor(v * s + 0.5)) or "?"
    end
    out[#out + 1] = ("%s: L%s R%s T%s B%s"):format(label, px(l), px(r), px(t), px(bo))
  end
  rect(bar, "bar 1")
  rect(b, "button 1")
  rect(rawget(b, "icon"), "  its icon")
  rect(rawget(b, "cooldown"), "  its cooldown")
  -- all four (call() keeps two: Sean's save read "hit insets 0 0 nil nil")
  local okI, il, ir, it, ib = pcall(b.GetHitRectInsets or error, b)
  if not okI then il, ir, it, ib = nil, nil, nil, nil end
  out[#out + 1] = ("  hit insets %s %s %s %s, mouse %s"):format(tostring(il), tostring(ir), tostring(it), tostring(ib),
    tostring(call(b.IsMouseEnabled, b)))
  return out
end

function Bars.SaveGeometry()
  local g = HH.db and HH.db.global
  if not g then return nil end
  g.diag = g.diag or {}
  g.diag.barsGeometry = { at = date and date("%Y-%m-%d %H:%M:%S") or "?", lines = table.concat(Bars.GeometryLines(), " | ") }
  return g.diag.barsGeometry
end

function Bars.Dress(b)
  if b.hh then return b.hh end
  local hh = {}
  b.hh = hh
  for _, k in ipairs({ "NormalTexture", "SlotBackground", "SlotArt", "FloatingBG", "Border", "IconBorder", "IconOverlay", "NewActionTexture", "Flash" }) do
    local r = rawget(b, k)
    if type(r) == "table" and r.SetAlpha then call(r.SetTexture, r, nil) call(r.SetAlpha, r, 0) end
  end
  local nt = call(b.GetNormalTexture, b)
  if type(nt) == "table" then call(nt.SetTexture, nt, nil) call(nt.SetAlpha, nt, 0) end
  if type(b.icon) == "table" and b.icon.SetTexCoord then call(b.icon.SetTexCoord, b.icon, 0.08, 0.92, 0.08, 0.92) end
  Bars.PinToButton(b)
  hh.backdrop = b:CreateTexture(nil, "BACKGROUND", nil, -8)
  hh.backdrop:SetColorTexture(INK[1], INK[2], INK[3], 0.9)
  hh.backdrop:SetAllPoints(b)
  hh.edges = {}
  local spec = { { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }
  for i, sp in ipairs(spec) do
    local e = b:CreateTexture(nil, "BORDER")
    e:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)
    e:SetPoint(sp[1], b, sp[1], 0, 0)
    e:SetPoint(sp[2], b, sp[2], 0, 0)
    if sp[3] then e:SetWidth(sp[3]) end
    if sp[4] then e:SetHeight(sp[4]) end
    hh.edges[i] = e
  end
  -- hover / pressed / active marks, the pet bar's look (Extra.lua); Blizzard's pinned state art off
  if HHB.Extra and HHB.Extra.MakeMarks then HHB.Extra.MakeMarks(b) end
  return hh
end

--- Empty slot: cell drawn only with the grid on. Called from the lib's OnButtonUpdate and after every layout.
function Bars.UpdateCell(b)
  local hh = b.hh
  if not hh then return end
  local bar = b.hhBar
  local grid = bar and bar.gridOn
  if grid == nil then grid = cfg().grid ~= false end
  local has = call(b.HasAction, b)
  local show = has == true or grid
  if show then hh.backdrop:Show() for _, e in ipairs(hh.edges) do e:Show() end
  else hh.backdrop:Hide() for _, e in ipairs(hh.edges) do e:Hide() end end
  if HHB.Extra and HHB.Extra.HideStateArt then HHB.Extra.HideStateArt(b) HHB.Extra.HookChecked(b) end   -- the lib re-pins its art on every update
  -- click-through: an empty slot lets the mouse through to the world; a filled one must keep it (it casts)
  local through = bar and cfg().list[bar.n] and cfg().list[bar.n].clickThrough
  if b.EnableMouse then b:EnableMouse(not (through and has ~= true)) end
end

local function hookLib(lib)
  if Bars.hooked or type(lib.RegisterCallback) ~= "function" then return end
  Bars.hooked = true
  lib.RegisterCallback(Bars, "OnButtonCreated", function(_, b) Bars.Dress(b) end)
  lib.RegisterCallback(Bars, "OnButtonUpdate", function(_, b) if b.hhBar then Bars.UpdateCell(b) end end)
end

-- ------------------------------------------------------------------------------------------------ config
--- The lib config for one button of bar n (keyBoundTarget = Blizzard's binding name for that slot).
function Bars.ButtonConfig(n, i)
  local d, spec = cfg(), Bars.SPECS[n]
  local bd = d.list[n]
  local grid = bd.grid
  if grid == nil then grid = d.grid ~= false end
  return {
    keyBoundTarget = spec.bind:format(i),
    showGrid = grid,
    clickOnDown = HH.SecureClick and HH.SecureClick() == "AnyDown" or false,
    tooltip = "enabled",
    outOfRangeColoring = "button",
    hideElements = { macro = d.hideNames ~= false, hotkey = false, equipped = false, border = true, borderIfEmpty = true },
    cooldownCount = d.cooldownNumbers ~= false,
    text = { hotkey = { font = { size = d.hotkeySize or 10, flags = "OUTLINE" }, color = { CREAM[1], CREAM[2], CREAM[3] },
      position = { anchor = "TOPRIGHT", relAnchor = "TOPRIGHT", offsetX = -1, offsetY = -1 }, justifyH = "RIGHT" } },
  }
end

-- ------------------------------------------------------------------------------------------------ visibility / fade
-- A state driver on the bar frame decides whether it is shown; "always" has none. The pet bar prefixes its own
-- "[nopet]hide;" so it never shows without a pet, whatever the option says. Custom = the player's own macro
-- conditional ("[combat]show;hide").
Bars.VISIBILITY = { combat = "[combat]hide;show", nocombat = "[nocombat]hide;show", pet = "[nopet]hide;show", nopet = "[pet]hide;show" }
function Bars.VisibilityDriver(bd, prefix)
  local driver
  if bd.visibility == "custom" then
    driver = (type(bd.custom) == "string" and bd.custom ~= "") and bd.custom or nil
  else
    driver = Bars.VISIBILITY[bd.visibility or "always"]
  end
  if prefix then return prefix .. (driver or "show") end
  return driver
end

function Bars.ApplyVisibility(bar)
  local driver = Bars.VisibilityDriver(cfg().list[bar.n], bar.visPrefix)
  if bar.visDriver == driver then return driver end
  if bar.visDriver and type(UnregisterStateDriver) == "function" then call(UnregisterStateDriver, bar, "vis") end
  bar.visDriver = driver
  if driver then
    bar:SetAttribute("_onstate-vis", [[ if newstate == "show" then self:Show() else self:Hide() end ]])
    if type(RegisterStateDriver) == "function" then call(RegisterStateDriver, bar, "vis", driver) end
  end
  return driver
end

--- Fade: the bar sits at fadeAlpha until the mouse is over it (or one of its buttons), back after fadeDelay.
function Bars.FadeIn(bar)
  bar.fadeToken = (bar.fadeToken or 0) + 1
  bar:SetAlpha(cfg().list[bar.n].alpha or 1)
end

function Bars.FadeOut(bar)
  local bd = cfg().list[bar.n]
  if not bd.fade then return end
  bar.fadeToken = (bar.fadeToken or 0) + 1
  local token = bar.fadeToken
  local function go() if bar.fadeToken == token and cfg().list[bar.n].fade then bar:SetAlpha(bd.fadeAlpha or 0.25) end end
  if C_Timer and C_Timer.After then C_Timer.After(bd.fadeDelay or 0.5, go) else go() end
end

local function fadeHooks(bar)
  if bar.fadeHooked then return end
  bar.fadeHooked = true
  local function enter() Bars.FadeIn(bar) end
  local function leave() Bars.FadeOut(bar) end
  for _, b in ipairs(bar.buttons) do
    if b.HookScript then b:HookScript("OnEnter", enter) b:HookScript("OnLeave", leave) end
  end
end

-- ------------------------------------------------------------------------------------------------ bars
-- The cyan box you drag after /hh unlock. Sean 2026-10-06: "the action bars need to be movable in the unlock".
-- Its own frame on UIParent at DIALOG strata, laid over the bar: a bar's fade, alpha or child levels can neither hide
-- it nor take the mouse from it. The position is saved under the bar's own key (bar.n): the pet bar used to save
-- under "Pet" while its layout read "pet", so a dragged pet bar jumped back.
local function dragHandle(bar, label)
  local h = CreateFrame("Frame", nil, UIParent)
  h:SetFrameStrata("DIALOG")
  h:SetAllPoints(bar)
  h.bg = h:CreateTexture(nil, "BACKGROUND")
  h.bg:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.30)
  h.bg:SetAllPoints(h)
  h.label = h:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  h.label:SetPoint("CENTER", h, "CENTER", 0, 0)
  local name = label or (type(bar.n) == "number" and ("Bar %d"):format(bar.n)) or tostring(bar.n)
  h.label:SetText(name .. "  -  drag")
  h.label:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
  h.bar = bar
  h:EnableMouse(true)
  h:RegisterForDrag("LeftButton")
  h:SetScript("OnDragStart", function() if not InCombatLockdown() then bar:StartMoving() end end)
  h:SetScript("OnDragStop", function()
    bar:StopMovingOrSizing()
    local point, _, _, x, y = bar:GetPoint(1)
    local bd = cfg().list[bar.n]
    if point and bd then bd.point, bd.x, bd.y = point, x, y end
  end)
  h:Hide()
  return h
end
Bars.DragHandle = dragHandle

--- The bar frame and its lib buttons, once. Returns the bar (nil when the client has no such bar).
function Bars.Create(n)
  if Bars.bars[n] then return Bars.bars[n] end
  local lib, spec = Bars.Lib(), Bars.SPECS[n]
  if not lib or not spec then return nil end
  local bar = CreateFrame("Frame", "HogUIBar" .. n, UIParent, "SecureHandlerStateTemplate")
  bar.n, bar.spec, bar.buttons = n, spec, {}
  bar:SetMovable(true)
  bar:SetClampedToScreen(true)
  bar:SetFrameStrata("MEDIUM")
  -- above anything Blizzard leaves on the same strata at the bottom of the screen (its emptied main bar frame, the XP
  -- bar containers): with equal strata the higher level gets the mouse (Sean 2026-10-17: the lower half of bar 1 took
  -- no hover). Set before the buttons exist, so they are created above it.
  if bar.SetFrameLevel then bar:SetFrameLevel(Bars.LEVEL) end
  bar.hhOurs = true
  for i = 1, 12 do
    local b = lib:CreateButton(i, ("HogUIBar%dButton%d"):format(n, i), bar, Bars.ButtonConfig(n, i))
    b.hhBar = bar
    Bars.Dress(b)
    if spec.paged then
      for state = 1, Bars.PAGES do b:SetState(state, "action", (state - 1) * 12 + i) end
      b:SetState(0, "action", i)
    else
      b:SetState(0, "action", spec.slot + i - 1)
    end
    bar.buttons[i] = b
  end
  if spec.paged then
    bar:SetAttribute("_onstate-page", [[
      self:SetAttribute("state", newstate)
      control:ChildUpdate("state", newstate)
    ]])
    bar.driver = Bars.PageDriver()
    if type(RegisterStateDriver) == "function" then call(RegisterStateDriver, bar, "page", bar.driver) end
  end
  bar.handle = dragHandle(bar)
  bar.describe = function()
    local bd = cfg().list[n]
    return ("bar %d: %s slots %d-%d, %d shown, %d per row, at %s %d,%d%s"):format(n, bd.enabled == false and "OFF" or "on", spec.slot, spec.slot + 11,
      bd.buttons or 12, bd.perRow or 12, tostring(bd.point), bd.x or 0, bd.y or 0, spec.paged and (", pages: " .. tostring(bar.driver)) or "")
  end
  Bars.bars[n] = bar
  return bar
end

--- Place the buttons of one bar: rows of perRow, padding between, the bar sized to fit, scaled and faded as set.
function Bars.Layout(bar)
  local n = bar.n
  local bd = cfg().list[n]
  local count = math.max(1, math.min(#bar.buttons, bar.countOverride or bd.buttons or 12))
  local perRow = math.max(1, math.min(count, bd.perRow or 12))
  local pad, size = bd.padding or 2, Bars.SIZE
  local rows = math.ceil(count / perRow)
  bar:SetSize(perRow * size + (perRow - 1) * pad, rows * size + (rows - 1) * pad)
  bar:SetScale(bd.scale or 1)
  bar:SetAlpha(bd.fade and (bd.fadeAlpha or 0.25) or (bd.alpha or 1))
  bar:ClearAllPoints()
  bar:SetPoint(bd.point or "BOTTOM", UIParent, bd.point or "BOTTOM", bd.x or 0, bd.y or 0)
  bar.gridOn = bd.grid
  for i, b in ipairs(bar.buttons) do
    if i <= count then
      local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", bar, "TOPLEFT", col * (size + pad), -row * (size + pad))
      b:SetSize(size, size)
      if b.UpdateConfig and Bars.SPECS[n] then b:UpdateConfig(Bars.ButtonConfig(n, i)) end
      b:Show()
    else
      b:Hide()
    end
    Bars.UpdateCell(b)
  end
  fadeHooks(bar)
  Bars.ApplyVisibility(bar)
  bar.laidOut = true
  return count, perRow, rows
end

-- ------------------------------------------------------------------------------------------------ Blizzard's bars
local hider
--- A Blizzard bar frame off for good: events off, HideBase where Edit Mode owns Hide, then under a hidden parent.
local function banish(f, keepEvents)
  if type(f) ~= "table" then return false end
  if not keepEvents and f.UnregisterAllEvents then call(f.UnregisterAllEvents, f) end
  if f.HideBase then call(f.HideBase, f) elseif f.Hide then call(f.Hide, f) end
  if f.SetParent then call(f.SetParent, f, hider) end
  return true
end
Bars.Banish = banish

function Bars.HideBlizzard()
  if not hider then
    hider = CreateFrame("Frame", "HogHealsBarsHider", UIParent)
    hider:Hide()
  end
  local n = 0
  for _, spec in pairs(Bars.SPECS) do
    -- the bar frame itself, except MainMenuBar (the XP bar and other things of ours live on it)
    if spec.bar ~= "MainMenuBar" then
      local f = rawget(_G, spec.bar)
      if f then Bars.found[spec.bar] = true if banish(f) then n = n + 1 end else Bars.missing[spec.bar] = true end
    end
    for i = 1, 12 do
      local b = rawget(_G, spec.blizzard .. i)
      if b then if banish(b) then n = n + 1 end end
    end
    if rawget(_G, spec.blizzard .. "1") then Bars.found[spec.blizzard] = true else Bars.missing[spec.blizzard] = true end
  end
  for _, name in ipairs(Bars.HIDE_EXTRA) do
    local f = rawget(_G, name)
    if f then Bars.found[name] = true banish(f, true) else Bars.missing[name] = true end
  end
  Bars.hidden = n
  return n
end

-- ------------------------------------------------------------------------------------------------ the main bar's art
-- Blizzard's main bar FRAME stays (classic clients hang the XP bar, bags and menu buttons on it), but with our bars up
-- none of its own art may show: the gryphons, the slot frame and its dividers, the page arrows.
-- Sean 2026-10-17, a brand-new character: all of that drawn under our bars. Two causes. Skin's art pass yields as soon
-- as Bars is on, so nobody cleared it; and Skin only knew it as MainMenuBar.*, which WoW: Forever does not have (every
-- MainMenuBar.* path sat in skin.missing on disk; the client's Edit Mode names the bar MainActionBar). Older characters
-- looked clean only because their Edit Mode layout had "Hide Bar Art" ticked; a new character starts on Blizzard's
-- preset layout, art on.
Bars.MAIN_BARS = { "MainActionBar", "MainMenuBar" }
-- classic-era clients: named globals (the frame's other children - XP bar, bags, menu buttons - are left alone)
Bars.CLASSIC_ART = {
  "MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
  "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap", "MainMenuBarPageNumber", "MainMenuBarArtFrameBackground",
  "MainMenuMaxLevelBar0", "MainMenuMaxLevelBar1", "MainMenuMaxLevelBar2", "MainMenuMaxLevelBar3",
}
-- the newer engine keeps its art under keys of the bar; any of these marks the bar as that kind
Bars.MODERN_KEYS = { "EndCaps", "BorderArt", "ActionBarPageNumber" }
-- Blizzard methods that rebuild the art (dividers come from a pool on every layout change): our pass runs after them
Bars.MAIN_ART_HOOKS = { "UpdateDividers", "UpdateEndCaps", "UpdateSystemSettingHideBarArt", "UpdateGridLayout" }

local quieted = setmetatable({}, { __mode = "k" })   -- side tables: no fields written on Blizzard's objects
local busy = setmetatable({}, { __mode = "k" })
local hookedBars = setmetatable({}, { __mode = "k" })

local function barsOn() local d = HH.db and HH.db.profile.bars return d ~= nil and d.enabled ~= false end

--- Every return value of a method that returns a list (GetRegions / GetChildren); {} when it errors.
local function all(f, obj)
  if type(f) ~= "function" then return {} end
  local r = { pcall(f, obj) }
  if not r[1] then return {} end
  table.remove(r, 1)
  return r
end

--- One Blizzard art piece off and kept off: hidden + alpha 0; Blizzard's next Show / SetShown / SetAlpha is undone.
-- Never a secure button (an action button is never art) and never a protected frame.
local function quiet(o)
  if type(o) ~= "table" or rawget(o, "hhOurs") then return false end
  local kind = call(o.GetObjectType, o)
  if kind == "CheckButton" or call(o.IsProtected, o) then return false end
  call(o.SetAlpha, o, 0)
  call(o.Hide, o)
  if not quieted[o] and type(hooksecurefunc) == "function" then
    quieted[o] = true
    local function again(self)
      if busy[self] or not barsOn() then return end
      busy[self] = true
      call(self.SetAlpha, self, 0)
      call(self.Hide, self)
      busy[self] = nil
    end
    for _, m in ipairs({ "Show", "SetShown", "SetAlpha" }) do
      if type(o[m]) == "function" then pcall(hooksecurefunc, o, m, again) end
    end
  end
  return true
end
Bars.Quiet = quiet

--- Blizzard's main bar FRAME stays (classic clients keep the XP bar and menu buttons on it), but with its buttons gone
-- it is an empty rectangle at the bottom centre - exactly where bar 1 sits - and it must not take the mouse there.
-- Out of combat only (it may be protected); what it had is kept for the day Bars is switched off.
local mouseWas = setmetatable({}, { __mode = "k" })
function Bars.Unmouse(f)
  if type(f) ~= "table" or not f.EnableMouse then return false end
  if InCombatLockdown and InCombatLockdown() then HH:RunOutOfCombat(Bars.Unmouse, f) return false end
  if mouseWas[f] == nil then mouseWas[f] = call(f.IsMouseEnabled, f) and true or false end
  call(f.EnableMouse, f, false)
  if f.EnableMouseWheel then call(f.EnableMouseWheel, f, false) end
  Bars.unmoused = (Bars.unmoused or 0) + 1
  return true
end

--- The main bar's own art off, the frame itself left in place. Returns how many pieces it quieted.
function Bars.HideMainArt()
  local n, names, kind = 0, {}, "none"
  local function one(o, label)
    if quiet(o) then n = n + 1 if #names < 24 then names[#names + 1] = label end end
  end
  for _, name in ipairs(Bars.CLASSIC_ART) do
    local t = rawget(_G, name)
    if t ~= nil then Bars.found[name] = true kind = "classic" one(t, name) end
  end
  for _, name in ipairs(Bars.MAIN_BARS) do
    local bar = rawget(_G, name)
    if type(bar) == "table" then
      Bars.found[name] = true
      local modern = false
      for _, k in ipairs(Bars.MODERN_KEYS) do if rawget(bar, k) ~= nil then modern = true end end
      if modern then
        kind = "modern:" .. name
        -- the newer engine: what is still on the bar once its buttons went under the hider is art
        for _, k in ipairs(Bars.MODERN_KEYS) do one(rawget(bar, k), name .. "." .. k) end
        one(rawget(bar, "Background"), name .. ".Background")
        for _, r in ipairs(all(bar.GetRegions, bar)) do one(r, name .. ":" .. tostring(call(r.GetObjectType, r))) end
        for _, c in ipairs(all(bar.GetChildren, bar)) do
          one(c, name .. ">" .. tostring(call(c.GetName, c) or call(c.GetObjectType, c)))
        end
        Bars.Unmouse(bar)
        if not hookedBars[bar] and type(hooksecurefunc) == "function" then
          hookedBars[bar] = true
          for _, m in ipairs(Bars.MAIN_ART_HOOKS) do
            if type(bar[m]) == "function" then
              pcall(hooksecurefunc, bar, m, function() if barsOn() then Bars.HideMainArt() end end)
            end
          end
        end
      end
    else
      Bars.missing[name] = true
    end
  end
  Bars.mainArt = { kind = kind, count = n, names = table.concat(names, ",") }
  return n
end

-- ------------------------------------------------------------------------------------------------ who has the mouse
-- Sean 2026-10-17, for the third time: hovering the middle / lower part of a bar-1 button does nothing. Whatever holds
-- the mouse there is recorded on its own - no command to type: while the cursor is inside bar 1 and the frame the
-- client hands the mouse to is not one of our buttons, its name, parent, strata and level are counted into
-- diag.barsMouse (saved on the next /reload or logout). "nothing" = no frame takes the mouse there at all.
Bars.thieves = {}
Bars.MAX_THIEVES = 8

local function focusFrame()
  local foci = rawget(_G, "GetMouseFoci")
  if type(foci) == "function" then
    local ok, list = pcall(foci)
    return ok and type(list) == "table" and list[1] or nil
  end
  local gf = rawget(_G, "GetMouseFocus")
  if type(gf) == "function" then local ok, v = pcall(gf) return ok and v or nil end
  return nil
end

function Bars.MouseProbe()
  local bar = Bars.bars[1]
  if type(bar) ~= "table" or not call(bar.IsShown, bar) or not call(bar.IsMouseOver, bar) then return nil end
  local f = focusFrame()
  local key
  if type(f) ~= "table" then
    key = "nothing (no frame takes the mouse here)"
  elseif rawget(f, "hhBar") or f == bar then
    return "ours"
  else
    local name = call(f.GetName, f)
    local p = call(f.GetParent, f)
    local pn = type(p) == "table" and call(p.GetName, p) or nil
    key = ("%s < %s [%s L%s]%s"):format(tostring(name or ("<" .. tostring(call(f.GetObjectType, f)) .. ">")), tostring(pn or "?"),
      tostring(call(f.GetFrameStrata, f)), tostring(call(f.GetFrameLevel, f)), call(f.IsProtected, f) and " protected" or "")
  end
  if Bars.thieves[key] == nil then
    local n = 0
    for _ in pairs(Bars.thieves) do n = n + 1 end
    if n >= Bars.MAX_THIEVES then return key end
  end
  Bars.thieves[key] = (Bars.thieves[key] or 0) + 1
  local list = {}
  for k, c in pairs(Bars.thieves) do list[#list + 1] = k .. " x" .. c end
  table.sort(list)
  local g = HH.db and HH.db.global
  if g then g.diag = g.diag or {} g.diag.barsMouse = { at = date and date("%Y-%m-%d %H:%M:%S") or "?", list = table.concat(list, " | ") } end
  return key
end

function Bars.StartMouseProbe()
  if C_Timer and C_Timer.After then
    C_Timer.After(4, function()
      local ok, err = pcall(Bars.SaveGeometry)
      local g = HH.db and HH.db.global
      if not ok and g then g.diag = g.diag or {} g.diag.barsGeometry = { error = tostring(err):sub(1, 300) } end
    end)
  end
  if Bars.mouseTicker or not (C_Timer and C_Timer.NewTicker) then return end
  Bars.mouseTicker = C_Timer.NewTicker(0.25, function() pcall(Bars.MouseProbe) end)
end

-- ------------------------------------------------------------------------------------------------ build / refresh
function Bars.Build(reason)
  local lib = Bars.Lib()
  if not lib then return 0 end
  hookLib(lib)
  local built = 0
  HH:RunOutOfCombat(function()
    Bars.HideBlizzard()
    Bars.HideMainArt()
    for n = 1, 8 do
      local bd = cfg().list[n]
      local bar = Bars.bars[n]
      if bd.enabled ~= false then
        bar = bar or Bars.Create(n)
        if bar then Bars.Layout(bar) bar:Show() built = built + 1 end
      elseif bar then
        bar:Hide()
      end
    end
    if HHB.Extra and HHB.Extra.Build then
      local ok, err = pcall(HHB.Extra.Build)
      if not ok then HH:LogError("bars pet/stance: " .. tostring(err)) end
    end
    Bars.built = built
    Bars.SetUnlocked(HH.db.profile.locked == false)
  end)
  return built
end

function Bars.SetUnlocked(unlocked)
  local was = Bars.unlocked
  for _, bar in pairs(Bars.bars) do
    if bar.handle then if unlocked then bar.handle:Show() else bar.handle:Hide() end end
    -- unlocked: every bar fully visible so you can see what you are placing; locked: its own opacity / fade again
    if unlocked then bar:SetAlpha(1) elseif was and bar.laidOut then Bars.Layout(bar) end
  end
  Bars.unlocked = unlocked and true or false
  if unlocked and not was and next(Bars.bars) then HH:Print("bars: drag the cyan boxes to move a bar; /hh lock when done. /hh bars reset puts them all back.") end
end

--- Every bar back to its default place and scale (positions, not buttons or visibility).
function Bars.ResetPositions()
  local list = cfg().list
  -- the default values written in explicitly (bar-specific over "**"), not cleared: same result on every database
  local D = (HH.defaults and HH.defaults.profile and HH.defaults.profile.bars and HH.defaults.profile.bars.list) or {}
  local star = D["**"] or {}
  for k, bd in pairs(list) do
    if type(bd) == "table" then
      local d = D[k] or {}
      for _, f in ipairs({ "point", "x", "y", "scale" }) do
        local v = d[f]
        if v == nil then v = star[f] end
        bd[f] = v
      end
    end
  end
  list.Pet, list.Stances = nil, nil
  for _, bar in pairs(Bars.bars) do if bar.laidOut then Bars.Layout(bar) end end
  if Bars.unlocked then Bars.SetUnlocked(true) end
  return true
end

--- One-time move of a position saved under the old wrong keys ("Pet", "Stances") to the keys the layout reads.
function Bars.MigrateKeys()
  local list = cfg().list
  for old, new in pairs({ Pet = "pet", Stances = "stance" }) do
    local o = rawget(list, old)
    if type(o) == "table" then
      local n = list[new]
      if o.x ~= nil or o.y ~= nil then n.point, n.x, n.y = o.point or n.point or "BOTTOM", o.x, o.y end
      list[old] = nil
    end
  end
end

--- Build or refresh everything.
function Bars.Apply(reason)
  Bars.lastApply = reason
  if Bars.unavailable or cfg().enabled == false then return 0 end
  return Bars.Build(reason)
end

-- ------------------------------------------------------------------------------------------------ options (per bar)
function Bars.BarOptions()
  local O = HHB.Options
  local out = {}
  local keys = { 1, 2, 3, 4, 5, 6, 7, 8, "pet", "stance" }
  for order, n in ipairs(keys) do
    local spec = Bars.SPECS[n] or { label = (n == "pet") and "Pet bar" or "Stance / form bar" }
    local sub = function() return cfg().list[n] end
    out["bar" .. n] = { type = "group", name = spec.label, order = 10 + order, args = {
      enabled = O.toggle(sub, "enabled", "Show this bar", 1, nil, "full"),
      buttons = O.range(sub, "buttons", "Buttons", 2, 1, 12, 1, 12),
      perRow = O.range(sub, "perRow", "Buttons per row", 3, 1, 12, 1, 12),
      padding = O.range(sub, "padding", "Padding", 4, 0, 12, 1, 2),
      scale = O.range(sub, "scale", "Scale", 5, 0.5, 2, 0.05, 1),
      alpha = O.range(sub, "alpha", "Opacity", 6, 0.1, 1, 0.05, 1),
      grid = { type = "select", name = "Empty slots", order = 7, values = { inherit = "As the global setting", on = "Always shown", off = "Hidden" },
        get = function() local g = sub().grid if g == nil then return "inherit" end return g and "on" or "off" end,
        set = function(_, v) sub().grid = (v == "inherit") and nil or (v == "on") Bars.Apply("options") end },
      clickThrough = O.toggle(sub, "clickThrough", "Click-through (mouse passes to the world)", 8),
      point = { type = "select", name = "Anchor", order = 9, values = { BOTTOM = "Bottom", TOP = "Top", LEFT = "Left", RIGHT = "Right", CENTER = "Centre", BOTTOMLEFT = "Bottom left", BOTTOMRIGHT = "Bottom right", TOPLEFT = "Top left", TOPRIGHT = "Top right" },
        get = function() return sub().point or "BOTTOM" end, set = function(_, v) sub().point = v Bars.Apply("options") end },
      x = O.range(sub, "x", "X", 10, -1500, 1500, 1, 0),
      y = O.range(sub, "y", "Y", 11, -1000, 1000, 1, 0),
      visibility = { type = "select", name = "Show", order = 12, values = { always = "Always", combat = "Hide in combat", nocombat = "Hide out of combat", pet = "Hide without a pet", nopet = "Hide with a pet", custom = "Custom conditional" },
        get = function() return sub().visibility or "always" end, set = function(_, v) sub().visibility = v Bars.Apply("options") end },
      custom = { type = "input", name = "Custom conditional (e.g. [combat]show;hide)", order = 13, width = "full",
        get = function() return sub().custom or "" end, set = function(_, v) sub().custom = v Bars.Apply("options") end },
      fade = O.toggle(sub, "fade", "Fade out until the mouse is over it", 14),
      fadeAlpha = O.range(sub, "fadeAlpha", "Faded opacity", 15, 0, 1, 0.05, 0.25),
      fadeDelay = O.range(sub, "fadeDelay", "Fade delay (seconds)", 16, 0, 3, 0.1, 0.5),
    } }
    out["bar" .. n].args.fade.get = function() return sub().fade == true end
    -- the global toggle's default is "on" except for bars 6-8, so the generic toggle needs the real value
    out["bar" .. n].args.enabled.get = function() return sub().enabled ~= false end
  end
  return out
end

-- ------------------------------------------------------------------------------------------------ module
local Module = {}
HHB.module = Module

function Module:OnEnable()
  Bars.MigrateKeys()
  local d = cfg()
  if not d or d.enabled == false then return end
  if not Bars.Lib() then
    HH:LogError("bars: LibActionButton-1.0 did not load on this client; HogTron UI Bars stay off")
    Bars.unavailable = true
    return
  end
  Bars.Apply("enable")
  HH:SafeCall(HHB.Extra, "StartRefresh")   -- our own checked / usable refresh (Forever drops some of the lib's events)
  Bars.StartMouseProbe()
  local ev = CreateFrame("Frame")
  pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
  pcall(ev.RegisterEvent, ev, "UPDATE_BINDINGS")
  ev:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_ENTERING_WORLD" and not Bars.unavailable then Bars.Apply("enter") end
  end)
  Module.events = ev
end

function Module:OnProfileChanged() Bars.Apply("profile") end

function Module:GetOptions()
  if HHB.Options and HHB.Options.Build then return HHB.Options.Build() end
end

function Module:SetLocked(locked) Bars.SetUnlocked(not locked) end

HH:RegisterModule("Bars", Module)

HH:RegisterSlash("bars", function(rest)
  rest = (rest or ""):lower()
  if rest == "reset" then
    if InCombatLockdown and InCombatLockdown() then HH:Print("bars: not in combat.") return end
    Bars.ResetPositions()
    HH:Print("bars: every bar back to its default place and scale.")
    return
  end
  HH:Print("bars: /hh unlock to drag them, /hh bars reset to put them back, /hh bind to bind keys, /hh barsdiag for details.")
end, "action bars: reset (all bars back to their default place)")

--- Where each bar really is: its own scale, the scale it ends up drawn at, size and anchor (for /hh barsdiag).
function Bars.LayoutLines()
  local out = {}
  local keys = {}
  for k in pairs(Bars.bars) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    local bar = Bars.bars[k]
    local function n(f) local ok, v = pcall(f, bar) return ok and type(v) == "number" and v or 0 end
    local point, _, rel, x, y = bar:GetPoint(1)
    out[#out + 1] = ("bar %s: scale %.2f, drawn at %.2f, %dx%d, %s %s %d,%d, %s"):format(tostring(k), n(bar.GetScale), n(bar.GetEffectiveScale),
      n(bar.GetWidth), n(bar.GetHeight), tostring(point), tostring(rel), x or 0, y or 0, bar:IsShown() and "shown" or "hidden")
  end
  return out
end

HH:RegisterSlash("barsdiag", function()
  for _, l in ipairs(Bars.LayoutLines()) do HH:Print("  " .. l) end
  do local g = HH.db and HH.db.global if g then g.diag = g.diag or {} g.diag.barsLayout = Bars.LayoutLines() end end
  do
    local lab = LibStub and LibStub("LibActionButton-1.0", true)
    local miss = {}
    for e in pairs(lab and lab.unknownEvents or {}) do miss[#miss + 1] = e end
    table.sort(miss)
    HH:Print(("bars: cooldowns via %s; events this client refused: %s"):format(tostring(lab and lab.cooldownPath or "?"), #miss > 0 and table.concat(miss, ", ") or "none"))
    local g = HH.db and HH.db.global
    if g then g.diag = g.diag or {} g.diag.barsCooldown = { path = lab and lab.cooldownPath, refused = table.concat(miss, ",") } end
  end
  local f, m = {}, {}
  for k in pairs(Bars.found) do f[#f + 1] = k end
  for k in pairs(Bars.missing) do if not Bars.found[k] then m[#m + 1] = k end end
  table.sort(f) table.sort(m)
  HH:Print(("bars: lib %s; %d bars built, %d Blizzard pieces hidden; found %d, missing %d"):format(Bars.Lib() and "loaded" or "MISSING", Bars.built or 0, Bars.hidden or 0, #f, #m))
  if #m > 0 then HH:Print("  missing: " .. table.concat(m, ", ")) end
  do
    local list = {}
    for k, c in pairs(Bars.thieves or {}) do list[#list + 1] = k .. " x" .. c end
    HH:Print("bars: who had the mouse inside bar 1 (not ours): " .. (#list > 0 and table.concat(list, " | ") or "nobody so far"))
    for _, l in ipairs(Bars.GeometryLines()) do HH:Print("  " .. l) end
    pcall(Bars.SaveGeometry)
    local a = Bars.mainArt or {}
    HH:Print(("bars: Blizzard's main bar art: %s, %d pieces hidden%s"):format(tostring(a.kind or "not run"), a.count or 0,
      (a.names and a.names ~= "") and (" (" .. a.names .. ")") or ""))
    local g = HH.db and HH.db.global
    if g then g.diag = g.diag or {} g.diag.barsMainArt = { kind = a.kind, count = a.count, names = a.names } end
  end
  for n = 1, 8 do local b = Bars.bars[n] if b and b.describe then HH:Print("  " .. b.describe()) end end
  local g = HH.db and HH.db.global
  if g then g.diag = g.diag or {} g.diag.bars = { found = table.concat(f, ","), missing = table.concat(m, ","), built = Bars.built, hidden = Bars.hidden, driver = Bars.bars[1] and Bars.bars[1].driver } end
end, "what HogTron UI Bars found on this client (bars, slots, Blizzard pieces)")
