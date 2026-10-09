-- Tooltips in the HogTron UI panel: Blizzard's border art off (modern NineSlice or classic backdrop), ink panel with a
-- 1 px outline behind the text, flat status bar, optional text size and cursor anchoring.
local HHS = HogHealsSkin
local Skin = HHS.Skin
local HH = HogHeals

local Part = { name = "tooltip", styled = {} }
HHS.Tooltip = Part

Part.NAMES = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "ItemRefShoppingTooltip1",
  "ItemRefShoppingTooltip2", "WorldMapTooltip", "EmbeddedItemTooltip", "FriendsTooltip", "QuickKeybindTooltip" }

local function clearBackdrop(tt)
  local ns = rawget(tt, "NineSlice")
  if type(ns) == "table" then
    if ns.SetAlpha then Skin.call(ns.SetAlpha, ns, 0) end
    Skin.KillRegions(ns)
  end
  if tt.SetBackdrop then Skin.call(tt.SetBackdrop, tt, nil) end
  if tt.SetBackdropColor then Skin.call(tt.SetBackdropColor, tt, 0, 0, 0, 0) end
  if tt.SetBackdropBorderColor then Skin.call(tt.SetBackdropBorderColor, tt, 0, 0, 0, 0) end
end

function Part.Style(tt)
  local d = Skin.cfg().tooltips
  if not tt.hh then
    clearBackdrop(tt)
    tt.hh = { panel = Skin.Panel(tt, tt, 0, d.alpha or 0.9) }
    tt:HookScript("OnShow", function(self)
      if Skin.cfg().enabled == false or Skin.cfg().tooltips.enabled == false then return end
      clearBackdrop(self)
      self.hh.panel:Show()
    end)
    local sb = rawget(_G, (tt:GetName() or "") .. "StatusBar") or rawget(tt, "StatusBar")
    if type(sb) == "table" and sb.SetStatusBarTexture then
      Skin.call(sb.SetStatusBarTexture, sb, Skin.FLAT)
      Skin.KillRegions(sb)
      sb.hhBg = Skin.Solid(sb, "BACKGROUND", { 0.13, 0.13, 0.16 }, 0.9)
      sb.hhBg:SetAllPoints(sb)
    end
    Part.styled[#Part.styled + 1] = tt:GetName() or "?"
  end
  tt.hh.panel.bg:SetColorTexture(Skin.INK[1], Skin.INK[2], Skin.INK[3], d.alpha or 0.9)
end

-- ------------------------------------------------------------------------------------------------ the anchor box
-- Sean 2026-10-08 in game: "I want to be able to move the tooltip ... when we do /hh unlock". Blizzard puts every
-- tooltip with no owner-anchor of its own at one default spot (GameTooltip_SetDefaultAnchor). We give that spot a
-- box, HogHealsTooltipAnchor: tooltips dock their BOTTOMRIGHT to it, the box drags in /hh unlock (cyan while
-- unlocked, invisible while locked, never in the way) and carries an edit-mode gear. Cursor anchoring wins over it.
function Part.Anchor()
  if Part.anchor then return Part.anchor end
  local d = Skin.cfg().tooltips
  local f = CreateFrame("Frame", "HogHealsTooltipAnchor", UIParent)
  f.hhOurs = true
  f:SetSize(d.width or 220, d.height or 90)
  f:SetFrameStrata("MEDIUM")
  f:SetPoint(d.point or "BOTTOMRIGHT", UIParent, d.point or "BOTTOMRIGHT", d.x or -40, d.y or 120)
  if f.SetMovable then f:SetMovable(true) end
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
  f:EnableMouse(false)
  f.bg = Skin.Solid(f, "BACKGROUND", Skin.CYAN, 0.2)
  f.bg:SetAllPoints(f)
  f.edges = Skin.Outline(f, f, Skin.CYAN)
  f.label = f:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  f.label:SetPoint("CENTER", f, "CENTER", 0, 0)
  f.label:SetText("Tooltips land here  -  drag")
  f.label:SetTextColor(Skin.CREAM[1], Skin.CREAM[2], Skin.CREAM[3])
  f:SetScript("OnDragStart", function(self) if HH.db.profile.locked == false and self.StartMoving then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    if self.StopMovingOrSizing then self:StopMovingOrSizing() end
    local point, _, _, x, y = self:GetPoint(1)
    if point then local c = Skin.cfg().tooltips c.point, c.x, c.y = point, x, y end
  end)
  Part.anchor = f
  Part.SetUnlocked(HH.db.profile.locked == false)
  return f
end

--- Unlocked: the box shows and drags. Locked: invisible, mouse-through (the frame stays shown for the gear).
function Part.SetUnlocked(unlocked)
  local f = Part.anchor
  if not f then return end
  f:EnableMouse(unlocked and true or false)
  f.bg:SetShown(unlocked and true or false)
  f.label:SetShown(unlocked and true or false)
  for _, e in ipairs(f.edges or {}) do e:SetShown(unlocked and true or false) end
  Part.unlocked = unlocked and true or false
end

--- Put the box back where it started and resize it from the settings.
function Part.ResetAnchor()
  local d = Skin.cfg().tooltips
  d.point, d.x, d.y = "BOTTOMRIGHT", -40, 120
  Part.PlaceAnchor()
end

function Part.PlaceAnchor()
  local f = Part.anchor
  if not f then return end
  local d = Skin.cfg().tooltips
  f:SetSize(d.width or 220, d.height or 90)
  f:ClearAllPoints()
  f:SetPoint(d.point or "BOTTOMRIGHT", UIParent, d.point or "BOTTOMRIGHT", d.x or -40, d.y or 120)
end

--- Where a default-anchored tooltip goes: the cursor (option), the box (default), or Blizzard's spot (both off).
function Part.Dock(tt, parent)
  local d = Skin.cfg().tooltips
  if not tt or not tt.SetOwner then return "none" end
  if d.anchorCursor then Skin.call(tt.SetOwner, tt, parent, "ANCHOR_CURSOR") return "cursor" end
  if d.anchor == false then return "blizzard" end
  local a = Part.Anchor()
  Skin.call(tt.SetOwner, tt, parent, "ANCHOR_NONE")
  Skin.call(tt.ClearAllPoints, tt)
  Skin.call(tt.SetPoint, tt, "BOTTOMRIGHT", a, "BOTTOMRIGHT", 0, 0)
  Part.docked = (Part.docked or 0) + 1
  return "box"
end

function Part.Apply()
  local d = Skin.cfg().tooltips
  if not d or d.enabled == false then return end
  if d.anchor ~= false then Part.Anchor() Part.PlaceAnchor() end
  if not Part.lockHooked and type(hooksecurefunc) == "function" and type(HH.SetLocked) == "function" then
    Part.lockHooked = true
    pcall(hooksecurefunc, HH, "SetLocked", function(_, locked) Part.SetUnlocked(not locked) end)
  end
  for _, n in ipairs(Part.NAMES) do
    local tt = Skin.G(n)
    if type(tt) == "table" and tt.HookScript then Part.Style(tt) end
  end
  if d.fontSize then
    for _, fo in ipairs({ "GameTooltipText", "GameTooltipTextSmall", "GameTooltipHeaderText" }) do
      local f = rawget(_G, fo)
      if type(f) == "table" and f.GetFont and f.SetFont then
        local path, _, flags = f:GetFont()
        if path then Skin.call(f.SetFont, f, path, fo == "GameTooltipHeaderText" and d.fontSize + 2 or d.fontSize, flags or "") end
      end
    end
  end
  -- Blizzard restyles the backdrop per tooltip kind; follow it
  if not Part.hooked and type(hooksecurefunc) == "function" then
    Part.hooked = true
    for _, fn in ipairs({ "SharedTooltip_SetBackdropStyle", "GameTooltip_SetBackdropStyle" }) do
      if type(rawget(_G, fn)) == "function" then
        pcall(hooksecurefunc, fn, function(tt) if type(tt) == "table" and tt.hh and Skin.cfg().enabled ~= false then clearBackdrop(tt) end end)
      end
    end
    if type(rawget(_G, "GameTooltip_SetDefaultAnchor")) == "function" then
      pcall(hooksecurefunc, "GameTooltip_SetDefaultAnchor", function(tt, parent)
        if Skin.cfg().enabled ~= false and Skin.cfg().tooltips.enabled ~= false then Part.Dock(tt, parent) end
      end)
    end
  end
end

Skin.Register(Part)
