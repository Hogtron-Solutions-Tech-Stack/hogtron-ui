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
  add({ key = "hud", path = "HUD.layout", title = "HUD", mover = G("HogHealsHUDAnchor"), how = "click" })
  local tracker = G("HogHealsQuestTracker")
  add({ key = "tracker", path = "Quests.tracker", title = "Quest tracker", mover = tracker, saver = tracker and tracker.header, how = "gear" })
  local meter = G("HogHealsMeterFrame")
  add({ key = "meter", path = "Meter", title = "Meter", mover = meter, saver = meter and meter.header, how = "gear" })
  for unit, name in pairs(EM.UNITS) do
    add({ key = "unit:" .. unit, path = "Units." .. unit, title = EM.UNIT_LABEL[unit], mover = G(name), how = "gear" })
  end
  add({ key = "infobar", path = "Skin.infobar", title = "Info bar", mover = G("HogUIInfoBar"), how = "gear" })
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
  if t.mover.IsShown and t.mover:IsShown() then b:Show() else b:Hide() end
  return b
end

function EM.SetUnlocked(unlocked)
  if unlocked then
    local n = 0
    for _, t in ipairs(EM.Targets()) do
      if t.how == "gear" then gear(t) else attachClick(t) end
      n = n + 1
    end
    EM.count = n
    if not EM.hinted then
      EM.hinted = true
      HH:Print("edit mode: click a cyan box, or the gear on a frame, for its settings and centring.")
    end
  else
    for _, b in pairs(EM.cogs) do b:Hide() end
    local P = HH.Panel
    if P and P.compact and P.frame and P.frame:IsShown() then P.frame:Hide() end
  end
  EM.unlocked = unlocked and true or false
end

HH:RegisterModule("EditMode", { SetLocked = function(_, isLocked) EM.SetUnlocked(not isLocked) end })
