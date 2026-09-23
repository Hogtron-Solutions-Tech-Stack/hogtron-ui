-- Action bars: Blizzard's bar art (gryphons, end caps, page-number art, stance/pet bar art) cleared; every action,
-- pet, stance and bonus button flattened (Skin.IconButton). The buttons stay Blizzard's secure buttons.
local HHS = HogHealsSkin
local Skin = HHS.Skin
local HH = HogHeals

local Part = { name = "actionbars", buttons = {} }
HHS.ActionBars = Part

--- Hide a frame and keep it hidden (Blizzard's layout code may Show it again).
function Skin.HideFrame(f)
  if type(f) ~= "table" or not f.Hide then return false end
  Skin.call(f.Hide, f)
  if not f.hhHideHooked and type(hooksecurefunc) == "function" then
    f.hhHideHooked = true
    pcall(hooksecurefunc, f, "Show", function(self)
      if Skin.cfg().enabled == false or self.hhUnhidden then return end
      Skin.call(self.Hide, self)
    end)
  end
  return true
end

Part.ART = {
  -- Classic-era globals
  "MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
  "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
  "MainMenuMaxLevelBar0", "MainMenuMaxLevelBar1", "MainMenuMaxLevelBar2", "MainMenuMaxLevelBar3",
  "MainMenuBarPageNumber", "StanceBarLeft", "StanceBarMiddle", "StanceBarRight",
  "SlidingActionBarTexture0", "SlidingActionBarTexture1", "PossessBackground1", "PossessBackground2",
  "MainMenuBarArtFrameBackground",
}
Part.ART_PATHS = {
  -- Modern mixins
  "MainMenuBar.EndCaps.LeftEndCap", "MainMenuBar.EndCaps.RightEndCap", "MainMenuBar.BorderArt", "MainMenuBar.Background",
  "MainMenuBar.ArtFrame.Background", "MainMenuBarArtFrame.Background", "StanceBar.BarArt", "PetActionBar.BarArt",
  "MultiBarBottomLeft.BarArt", "MultiBarBottomRight.BarArt",
}
Part.HIDE = { "ActionBarUpButton", "ActionBarDownButton", "MainMenuBarPerformanceBarFrame", "MainMenuBarVehicleLeaveButton" }

Part.PREFIXES = {
  { "ActionButton", 12 }, { "MultiBarBottomLeftButton", 12 }, { "MultiBarBottomRightButton", 12 }, { "MultiBarRightButton", 12 },
  { "MultiBarLeftButton", 12 }, { "MultiBar5Button", 12 }, { "MultiBar6Button", 12 }, { "MultiBar7Button", 12 },
  { "BonusActionButton", 12 }, { "PetActionButton", 10 }, { "StanceButton", 10 }, { "ShapeshiftButton", 10 }, { "PossessButton", 2 },
}

function Part.Buttons()
  local out = {}
  for _, p in ipairs(Part.PREFIXES) do
    for i = 1, p[2] do
      local b = rawget(_G, p[1] .. i)
      if type(b) == "table" then out[#out + 1] = b end
    end
    if rawget(_G, p[1] .. "1") ~= nil then Skin.found[p[1]] = true else Skin.missing[p[1]] = true end
  end
  return out
end

function Part.Apply()
  local d = Skin.cfg().actionBars
  if not d or d.enabled == false then return end
  if d.hideArt ~= false then
    for _, n in ipairs(Part.ART) do Skin.Kill(Skin.G(n)) end
    for _, p in ipairs(Part.ART_PATHS) do
      local v = Skin.Path(p)
      if type(v) == "table" then
        if v.GetObjectType and v:GetObjectType() == "Texture" then Skin.Kill(v) else Skin.KillRegions(v) end
      end
    end
    for _, n in ipairs(Part.HIDE) do Skin.HideFrame(Skin.G(n)) end
  end
  local n = 0
  for _, b in ipairs(Part.Buttons()) do
    if not b.hhSkinned then
      Skin.IconButton(b, { hotkeySize = d.hotkeySize or 10, hideNames = d.hideNames ~= false })
      Part.buttons[#Part.buttons + 1] = b
    end
    n = n + 1
  end
  Part.count = n
  return n
end

function Part.OnEvent(e)
  -- bars that exist only after entering the world (pet / stance) are caught on the next pass
  if e == "PLAYER_ENTERING_WORLD" then Part.Apply() end
end

Skin.Register(Part)
