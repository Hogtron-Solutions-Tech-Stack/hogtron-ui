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
        fontSize = range(p, "fontSize", "Name size", 6, 7, 24, 1),
        barHeight = range(p, "barHeight", "Bar height", 6.1, 6, 30, 1),
        widthScale = range(p, "widthScale", "Plate width (x)", 6.2, 0.6, 2.0, 0.05),
        castbar = toggle(p, "castbar", "Flatten the cast bar under the plate", 7),
        flatBar = { type = "toggle", name = "Plain flat health bar (hide Blizzard's bar art)", order = 7.05,
          get = function() return p().flatBar ~= false end, set = function(_, v) p().flatBar = v and true or false; refresh() end },
        hideBorders = { type = "toggle", name = "Hide Blizzard's bar border (the yellow line)", order = 7.1,
          get = function() return p().hideBorders ~= false end, set = function(_, v) p().hideBorders = v and true or false; refresh() end },
        friendlyNameOnly = toggle(p, "friendlyNameOnly", "Friendly plates: name only (no health bar)", 7.5),
        friendlyNameSize = range(p, "friendlyNameSize", "Friendly name text size", 7.6, 8, 24, 1),
        hots = { type = "toggle", name = "My HoTs above friendly heads (short buffs only, centred; long buffs stay on the party frame)", order = 7.61, width = "full",
          get = function() return (p().buffs or {}).enabled ~= false end, set = function(_, v) p().buffs = p().buffs or {} p().buffs.enabled = v and true or false; refresh() end },
        hotsMax = { type = "range", name = "Longest buff still shown above the head (seconds)", order = 7.62, min = 10, max = 300, step = 5,
          get = function() return (p().buffs or {}).maxDuration or 60 end, set = function(_, v) p().buffs = p().buffs or {} p().buffs.maxDuration = v; refresh() end },
        hotsSize = { type = "range", name = "HoT icon size above the head", order = 7.63, min = 10, max = 32, step = 1,
          get = function() return (p().buffs or {}).size or 18 end, set = function(_, v) p().buffs = p().buffs or {} p().buffs.size = v; refresh() end },
        uniformScale = toggle(p, "uniformScale", "Same plate size at every distance (no shrink / fade)", 7.8),
        targetScale = range(p, "targetScale", "Target plate scale", 7.9, 0.8, 1.5, 0.05),
        maxDistance = { type = "range", name = "Plate distance (yards) - beyond it the game draws its own small names", order = 7.95, min = 20, max = 100, step = 5,
          get = function() return p().maxDistance or 60 end, set = function(_, v) p().maxDistance = v; HogHealsPlates.Plates.ApplyCVars() end },
        showLevel = { type = "toggle", name = "Level next to the bar", order = 7.7,
          get = function() return p().showLevel ~= false end, set = function(_, v) p().showLevel = v and true or false; refresh() end },
        nameClass = { type = "select", name = "Player names in class colour", order = 8,
          values = { friendly = "Friendly players", all = "All players", none = "Off" },
          get = function() return p().nameClass or "friendly" end, set = function(_, v) p().nameClass = v; refresh() end },
      } },
      highlight = { type = "group", name = "Highlight", order = 2, args = {
        about = { type = "description", order = 0, name = "Your target: four sharp corners around its bar (or a soft glow / the plate magnified / the old outline). A mob on YOU gets a red outline over everything; quest mobs an amber one." },
        target = toggle(sub("target"), "highlight", "Mark my target", 1),
        style = { type = "select", name = "Target mark", order = 1.5, values = { brackets = "Corner brackets (sharp)", glow = "Glow around the bar (soft)", scale = "Magnify the plate", outline = "Outline (box)", none = "None" },
          get = function() return sub("target")().style or "brackets" end, set = function(_, v) sub("target")().style = v; refresh() end },
        targetColor = colour(sub("target"), "color", "Target colour", 2),
        animate = { type = "toggle", name = "Animate the glow (lock on, then breathe)", order = 2.1,
          get = function() return sub("target")().animate ~= false end, set = function(_, v) sub("target")().animate = v and true or false; refresh() end },
        glowSize = range(sub("target"), "glowSize", "Glow size", 2.2, 3, 16, 1),
        bracketSize = range(sub("target"), "bracketSize", "Bracket size", 2.25, 4, 30, 1),
        hideBlizzard = { type = "toggle", name = "Hide Blizzard's own target highlight", order = 2.3,
          get = function() return sub("target")().hideBlizzard ~= false end, set = function(_, v) sub("target")().hideBlizzard = v and true or false; refresh() end },
        scale = range(sub("target"), "scale", "Magnification (style: magnify)", 2.5, 1.0, 2.0, 0.05),
        fade = toggle(sub("target"), "fadeOthers", "Fade plates that are not my target", 3),
        otherAlpha = range(sub("target"), "otherAlpha", "Faded opacity", 4, 0.1, 1, 0.05),
        aggro = toggle(sub("aggro"), "warn", "Red outline when a mob is attacking me", 5),
        aggroColor = colour(sub("aggro"), "color", "Aggro colour", 6),
      } },
      quest = { type = "group", name = "Quest mobs", order = 3, args = {
        about = { type = "description", order = 0, name = "Marks mobs you still need for a quest: a ! icon with your progress beside the plate. Read from the mob's tooltip, or matched by name against your quest log when the tooltip has no quest lines (that needs the HogHeals Quests addon on)." },
        icon = toggle(sub("quest"), "icon", "Quest icon", 1),
        progress = toggle(sub("quest"), "progress", "Progress next to the icon (3/8)", 2),
        highlight = toggle(sub("quest"), "highlight", "Amber outline on quest mobs (off = cleaner)", 3),
        tint = toggle(sub("quest"), "tint", "Tint the health bar too", 4),
        color = colour(sub("quest"), "color", "Quest colour", 5),
        iconSize = range(sub("quest"), "iconSize", "Icon size", 6, 10, 28, 1),
      } },
    },
  }
end
