-- HUD options tab (AceConfig table). Every set() writes profile.hud and calls HUD.Refresh().
HogHealsHUD = HogHealsHUD or {}
local HHD = HogHealsHUD
local HH = HogHeals

local Options = {}
HHD.Options = Options

local function hud() return HH.db.profile.hud end
local function refresh() HHD.HUD.Refresh() end

local function lsmValues(kind)
  local LSM = LibStub("LibSharedMedia-3.0", true)
  local out = {}
  if LSM then for _, n in ipairs(LSM:List(kind)) do out[n] = n end end
  return out
end

-- tiny builders ---------------------------------------------------------
local function toggle(tbl, key, name, order, desc)
  return { type = "toggle", name = name, desc = desc, order = order,
    get = function() return tbl()[key] ~= false end,
    set = function(_, v) tbl()[key] = v and true or false; refresh() end }
end
local function range(tbl, key, name, order, min, max, step)
  return { type = "range", name = name, order = order, min = min, max = max, step = step,
    get = function() return tbl()[key] end,
    set = function(_, v) tbl()[key] = v; refresh() end }
end
local function select_(tbl, key, name, order, values)
  return { type = "select", name = name, order = order, values = values,
    get = function() return tbl()[key] end,
    set = function(_, v) tbl()[key] = v; refresh() end }
end
local function colour(tbl, key, name, order)
  return { type = "color", name = name, order = order,
    get = function() local c = tbl()[key] return c[1], c[2], c[3] end,
    set = function(_, r, g, b) tbl()[key] = { r, g, b }; refresh() end }
end

local function layoutGroup()
  return { type = "group", name = "Layout", order = 1, args = {
    note = { type = "description", order = 0, name = "One strip: castbar on top, mana bar (with five-second rule + ticks) under it, info line at the bottom. /hh unlock to drag." },
    width = range(hud, "width", "Width", 1, 120, 600, 2),
    x = range(hud, "x", "X offset", 2, -1200, 1200, 1),
    y = range(hud, "y", "Y offset", 3, -800, 800, 1),
    rowSpacing = range(hud, "rowSpacing", "Row spacing", 4, 0, 10, 1),
    showCastbar = toggle(hud, "showCastbar", "Castbar row", 5),
    castbarHeight = range(hud, "castbarHeight", "Castbar height", 6, 8, 40, 1),
    showMana = toggle(hud, "showMana", "Mana row", 7),
    manaHeight = range(hud, "manaHeight", "Mana height", 8, 6, 30, 1),
    showInfo = toggle(hud, "showInfo", "Info line", 9),
    infoHeight = range(hud, "infoHeight", "Info height", 10, 10, 30, 1),
    font = { type = "select", name = "Font", order = 11, values = function() return lsmValues("font") end,
      get = function() return hud().font end, set = function(_, v) hud().font = v; refresh() end },
    fontSize = range(hud, "fontSize", "Font size", 12, 6, 24, 1),
    texture = { type = "select", name = "Bar texture", order = 13, values = function() return lsmValues("statusbar") end,
      get = function() return hud().texture end, set = function(_, v) hud().texture = v; refresh() end },
    lock = { type = "execute", order = 20, name = function() return HH.db.profile.locked and "Unlock (drag)" or "Lock" end,
      func = function() HH:SetLocked(not HH.db.profile.locked) end },
  } }
end

local function castbarGroup()
  local c = function() return hud().castbar end
  return { type = "group", name = "Castbar", order = 2, args = {
    icon = toggle(c, "icon", "Spell icon", 1),
    showTarget = toggle(c, "showTarget", "Show target name after spell", 2),
    latency = toggle(c, "latency", "Latency segment", 3, "Red segment at the end of the bar = your world latency; the part of the cast you can't interrupt in time."),
    gcd = toggle(c, "gcd", "GCD sliver under the bar", 4),
    hideBlizzard = toggle(c, "hideBlizzard", "Hide Blizzard's casting bar", 5),
    precision = range(c, "precision", "Time decimals", 6, 0, 2, 1),
    castColor = colour(c, "castColor", "Cast colour", 10),
    channelColor = colour(c, "channelColor", "Channel colour", 11),
    uninterruptibleColor = colour(c, "uninterruptibleColor", "Uninterruptible colour", 12),
    failColor = colour(c, "failColor", "Failed / interrupted colour", 13),
  } }
end

local function manaGroup()
  local m = function() return hud().mana end
  return { type = "group", name = "Mana & five-second rule", order = 3, args = {
    note = { type = "description", order = 0, name = "After a mana-costing cast, a 5 s overlay drains across the bar (no regen). Then a spark marks each 2 s regen tick." },
    textMode = select_(m, "textMode", "Text", 1, { cur = "Current / max", percent = "Percent", none = "None" }),
    showTicks = toggle(m, "showTicks", "Show regen tick spark", 2),
    showFsrText = toggle(m, "showFsrText", "Show five-second countdown text", 3),
    fsrColor = colour(m, "fsrColor", "Five-second overlay colour", 4),
    tickColor = colour(m, "tickColor", "Tick spark colour", 5),
  } }
end

local function pacingGroup()
  local p = function() return hud().pacing end
  return { type = "group", name = "Mana pacing", order = 4, args = {
    note = { type = "description", order = 0, name = "In combat the info line shows time-to-OOM at your current burn rate and the fight timer. Mana sampling only — no combat log." },
    enabled = toggle(p, "enabled", "Enabled", 1),
    targetLength = range(p, "targetLength", "Target fight length (s)", 2, 60, 900, 15),
    showProjection = toggle(p, "showProjection", "Show projected mana at target length", 3),
    amber = range(p, "amber", "Amber below (s)", 4, 10, 300, 5),
    red = range(p, "red", "Red below (s)", 5, 5, 120, 5),
  } }
end

local function advisorGroup()
  local a = function() return hud().advisor end
  return { type = "group", name = "Rank advisor", order = 5, args = {
    note = { type = "description", order = 0, name = "Hover a frame: the info line shows the lowest rank of your two main heals that covers the missing health. Advisory only — bind ranks with /hh rankmacros." },
    enabled = toggle(a, "enabled", "Enabled", 1),
    margin = range(a, "margin", "Cover margin (0.9 = heal ≥ 90% of missing)", 2, 0.5, 1.2, 0.05),
    onFrame = toggle(a, "onFrame", "Also show on the hovered frame", 3),
    spells = { type = "input", name = "Spells (comma separated, blank = class defaults)", order = 4, width = "full",
      get = function() local _, cls = UnitClass("player") local l = a().spells and a().spells[cls] return l and table.concat(l, ", ") or "" end,
      set = function(_, v) local _, cls = UnitClass("player") local t = {} for s in v:gmatch("[^,]+") do s = strtrim(s) if s ~= "" then t[#t + 1] = s end end
        a().spells = a().spells or {} a().spells[cls] = (#t > 0) and t or nil; refresh() end },
    macros = { type = "execute", name = "Print rank macros to chat", order = 5, func = function() HH:SlashCommand("rankmacros") end },
  } }
end

function Options.Build()
  return { type = "group", name = "HUD", childGroups = "tab", args = {
    layout = layoutGroup(), castbar = castbarGroup(), mana = manaGroup(), pacing = pacingGroup(), advisor = advisorGroup(),
  } }
end
