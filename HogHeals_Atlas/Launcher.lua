-- Launcher: a minimap button (and an entry for any LibDataBroker display) so Atlas opens without a slash command.
--   left-click   the window        right-click   gear upgrades        shift-click   the dungeon tracker
-- The tooltip answers the two questions you have at a glance: which dungeons are for my level, and is anything in
-- my bags better than what I wear. Uses the libraries the HogUI core already carries; without them, no button.
local A = HogHealsAtlas
local HH = HogHeals

local Launcher = { NAME = "HogUIAtlas" }
A.Launcher = Launcher

--- Tooltip lines: { { text, r, g, b }, ... }. Pure apart from reading the player.
function Launcher.Lines()
  local out = {}
  local C = A.COLORS
  local function add(text, c) out[#out + 1] = { text, c[1], c[2], c[3] } end
  add("HogUI Atlas", C.cream)
  local L = A.playerLevel()
  local mine = A.Levels.List(L, true)
  local faction = A.playerFaction()
  if #mine == 0 then
    add("No dungeon fits level " .. L .. " yet.", C.grey)
  else
    add("For level " .. L .. ":", C.grey)
    for i, e in ipairs(mine) do
      if i > 6 then add(("  ... and %d more"):format(#mine - 6), C.grey) break end
      local d = e.dungeon
      local other = d.faction and faction and d.faction ~= faction
      add(("  %s  %d-%d%s"):format(d.name, e.min, e.max, other and "  (other side)" or ""), C[e.band] or C.cream)
    end
  end
  local bag = {}
  for _, b in ipairs(A.Gear.BagItems()) do bag[#bag + 1] = b.link end
  local n, best = A.Gear.CountUpgrades(bag)
  if n > 0 then add(("%d upgrade%s in your bags (best +%.1f)"):format(n, n == 1 and "" or "s", best), C.green) end
  add("Left: Atlas.  Right: upgrades.  Shift: dungeon tracker.", C.grey)
  return out
end

function Launcher.Click(button)
  local shift = type(rawget(_G, "IsShiftKeyDown")) == "function" and IsShiftKeyDown()
  if shift then A.Tracker.Toggle()
  elseif button == "RightButton" then A.Window.Toggle("upgrades")
  else A.Window.Toggle() end
end

function Launcher.Start()
  if Launcher.object then return true end
  local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
  if not LDB then Launcher.why = "no LibDataBroker" return false end
  local ok, obj = pcall(LDB.NewDataObject, LDB, Launcher.NAME, {
    type = "launcher", text = "Atlas", label = "HogUI Atlas", icon = "Interface\\Icons\\INV_Misc_Map_01",
    OnClick = function(_, button)
      local good, err = pcall(Launcher.Click, button)
      if not good then HH:LogError("atlas launcher: " .. tostring(err)) end
    end,
    OnTooltipShow = function(tt)
      local good, lines = pcall(Launcher.Lines)
      if not good or type(tt) ~= "table" or not tt.AddLine then return end
      for _, l in ipairs(lines) do tt:AddLine(l[1], l[2], l[3], l[4]) end
    end,
  })
  if not ok or not obj then Launcher.why = "data object refused" return false end
  Launcher.object = obj
  local icon = LibStub("LibDBIcon-1.0", true)
  if icon then
    local c = A.cfg()
    if pcall(icon.Register, icon, Launcher.NAME, obj, c.minimap) then Launcher.icon = icon end
  end
  return true
end

function Launcher.Refresh()
  local icon = Launcher.icon
  if not icon then return end
  if A.cfg().minimap.hide then pcall(icon.Hide, icon, Launcher.NAME) else pcall(icon.Show, icon, Launcher.NAME) end
end
