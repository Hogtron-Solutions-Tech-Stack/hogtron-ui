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

function Part.Apply()
  local d = Skin.cfg().tooltips
  if not d or d.enabled == false then return end
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
        if Skin.cfg().enabled ~= false and Skin.cfg().tooltips.anchorCursor and tt.SetOwner then
          Skin.call(tt.SetOwner, tt, parent, "ANCHOR_CURSOR")
        end
      end)
    end
  end
end

Skin.Register(Part)
