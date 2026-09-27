-- Units options: General tab + one tab per frame. Every set() writes profile.units and refreshes the frames.
HogHealsUnits = HogHealsUnits or {}
local HHU = HogHealsUnits
local HH = HogHeals

local Options = {}
HHU.Options = Options

local function g() return HH.db.profile.units end
local function u(unit) return function() return HH.db.profile.units[unit] end end
local function refresh() HHU.Units.Refresh() end

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
    set = function(_, r, gg, b) tbl()[key] = { r, gg, b }; refresh() end }
end

local function mediaList(kind)
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  local out = {}
  if LSM and LSM.List then for _, n in ipairs(LSM:List(kind) or {}) do out[n] = n end end
  if not next(out) then out["Solid"] = "Solid" end
  return out
end

local function unitTab(unit, order)
  local label = HHU.Units.LABEL[unit]
  local t = { type = "group", name = label, order = order, args = {
    enabled = toggle(u(unit), "enabled", "Show the " .. label:lower() .. " frame", 1),
    width = range(u(unit), "width", "Width", 2, 80, 500, 5),
    height = range(u(unit), "height", "Height", 3, 16, 120, 1),
    powerHeight = range(u(unit), "powerHeight", "Power bar height", 4, 2, 30, 1),
    showPower = toggle(u(unit), "showPower", "Power bar", 5),
    showName = toggle(u(unit), "showName", "Name", 6),
    showLevel = toggle(u(unit), "showLevel", "Level", 7),
    fontSize = range(u(unit), "fontSize", "Text size", 8, 7, 28, 1),
    x = range(u(unit), "x", "X offset", 9, -1400, 1400, 1),
    y = range(u(unit), "y", "Y offset", 10, -900, 900, 1),
  } }
  if unit == "target" or unit == "focus" then
    t.args.castbar = toggle(u(unit), "castbar", "Cast bar above the frame", 11)
    t.args.castbarHeight = range(u(unit), "castbarHeight", "Cast bar height", 12, 8, 30, 1)
    t.args.debuffs = toggle(u(unit), "debuffs", "Debuffs under the frame", 13)
    t.args.buffs = { type = "toggle", name = "Buffs under the debuffs (off: Blizzard's buff area keeps them)", order = 14,
      get = function() return u(unit)().buffs == true end, set = function(_, v) u(unit)().buffs = v and true or false; refresh() end }
    t.args.auraSize = range(u(unit), "auraSize", "Aura icon size", 15, 12, 40, 1)
    t.args.aurasPerRow = range(u(unit), "aurasPerRow", "Auras per row", 16, 4, 20, 1)
    t.args.maxDebuffs = range(u(unit), "maxDebuffs", "Max debuffs", 17, 0, 40, 1)
    t.args.maxBuffs = range(u(unit), "maxBuffs", "Max buffs", 18, 0, 40, 1)
  end
  return t
end

function Options.Build()
  return {
    type = "group", name = "Units", order = 38,
    args = {
      general = { type = "group", name = "General", order = 1, args = {
        about = { type = "description", order = 0, name = "Player, target, target-of-target, pet and focus frames in the HogUI look. Left-click targets, right-click opens the menu. Unlock (/hh units unlock) to drag them, then lock. Blizzard's frames are hidden while these are on; turning them off needs a /reload to bring Blizzard's back." },
        enabled = toggle(g, "enabled", "HogUI unit frames", 1),
        hideBlizzard = toggle(g, "hideBlizzard", "Hide Blizzard's unit frames", 2),
        locked = { type = "description", order = 3, name = "Move: /hh unlock, drag the frames (hidden ones appear with a 'drag' label), then /hh lock." },
        classColors = toggle(g, "classColors", "Class colours on players", 4),
        reactionColors = toggle(g, "reactionColors", "Hostile / neutral / friendly colours on NPCs", 5),
        healthColor = colour(g, "healthColor", "Fallback health colour", 6),
        healthText = select_(g, "healthText", "Health text", 7, { percent = "Percent", current = "Current", ["current-max"] = "Current / max", ["current-percent"] = "Current + percent", none = "None" }),
        powerText = select_(g, "powerText", "Power text", 8, { ["current-max"] = "Current / max", current = "Current", none = "None" }),
        texture = select_(g, "texture", "Bar texture", 9, mediaList("statusbar")),
        font = select_(g, "font", "Font", 10, mediaList("font")),
        fontSize = range(g, "fontSize", "Text size (default for every frame)", 11, 7, 28, 1),
        backgroundAlpha = range(g, "backgroundAlpha", "Background opacity", 12, 0, 1, 0.05),
        tooltips = toggle(g, "tooltips", "Tooltip on hover", 13),
        reset = { type = "execute", name = "Reset positions", order = 14, func = function() HH:SlashCommand("units reset") end },
      } },
      player = unitTab("player", 2),
      target = unitTab("target", 3),
      targettarget = unitTab("targettarget", 4),
      pet = unitTab("pet", 5),
      focus = unitTab("focus", 6),
    },
  }
end
