-- Nameplates options: Look / Highlight / Quest mobs. Every set() writes profile.plates and repaints live plates.
HogHealsPlates = HogHealsPlates or {}
local HHP = HogHealsPlates
local HH = HogHeals

local Options = {}
HHP.Options = Options

local function p() return HH.db.profile.plates end
local function sub(key) return function() return HH.db.profile.plates[key] end end
local function refresh() HHP.Plates.Refresh() end

local function toggle(tbl, key, name, order, desc)
  return { type = "toggle", name = name, desc = desc, order = order,
    get = function() return tbl()[key] and true or false end,
    set = function(_, v) tbl()[key] = v and true or false; refresh() end }
end
local function range(tbl, key, name, order, min, max, step)
  return { type = "range", name = name, order = order, min = min, max = max, step = step,
    get = function() return tbl()[key] end,
    set = function(_, v) tbl()[key] = v; refresh() end }
end
local function colour(tbl, key, name, order)
  return { type = "color", name = name, order = order,
    get = function() local c = tbl()[key] return c[1], c[2], c[3] end,
    set = function(_, r, g, b) tbl()[key] = { r, g, b }; refresh() end }
end

function Options.Build()
  return {
    type = "group", name = "Nameplates", order = 36,
    args = {
      look = { type = "group", name = "Look", order = 1, args = {
        about = { type = "description", order = 0, name = "Restyles Blizzard's own nameplates: flat bar, dark backing, outline, health text, class / reaction colours. Turning the restyle off fully undoes it after a /reload." },
        enabled = toggle(p, "enabled", "Restyle nameplates", 1),
        border = toggle(p, "border", "Outline", 2),
        classColors = toggle(p, "classColors", "Class colours on enemy players", 3),
        reactionColors = toggle(p, "reactionColors", "Hostile / neutral / friendly colours", 4),
        healthText = { type = "select", name = "Health text", order = 5, values = { percent = "Percent", value = "Value", none = "None" },
          get = function() return p().healthText or "percent" end, set = function(_, v) p().healthText = v; refresh() end },
        fontSize = range(p, "fontSize", "Font size", 6, 7, 18, 1),
        castbar = toggle(p, "castbar", "Flatten the cast bar under the plate", 7),
      } },
      highlight = { type = "group", name = "Highlight", order = 2, args = {
        about = { type = "description", order = 0, name = "Outline colour by priority: a mob on YOU (red) beats your target (cyan) beats a quest mob (amber)." },
        target = toggle(sub("target"), "highlight", "Highlight my target", 1),
        targetColor = colour(sub("target"), "color", "Target colour", 2),
        fade = toggle(sub("target"), "fadeOthers", "Fade plates that are not my target", 3),
        otherAlpha = range(sub("target"), "otherAlpha", "Faded opacity", 4, 0.1, 1, 0.05),
        aggro = toggle(sub("aggro"), "warn", "Red outline when a mob is attacking me", 5),
        aggroColor = colour(sub("aggro"), "color", "Aggro colour", 6),
      } },
      quest = { type = "group", name = "Quest mobs", order = 3, args = {
        about = { type = "description", order = 0, name = "Marks mobs you still need for a quest: a ! icon with your progress beside the plate. Read from the mob's tooltip, or matched by name against your quest log when the tooltip has no quest lines (that needs the HogHeals Quests addon on)." },
        icon = toggle(sub("quest"), "icon", "Quest icon", 1),
        progress = toggle(sub("quest"), "progress", "Progress next to the icon (3/8)", 2),
        highlight = toggle(sub("quest"), "highlight", "Outline quest mobs", 3),
        tint = toggle(sub("quest"), "tint", "Tint the health bar too", 4),
        color = colour(sub("quest"), "color", "Quest colour", 5),
        iconSize = range(sub("quest"), "iconSize", "Icon size", 6, 10, 28, 1),
      } },
    },
  }
end
