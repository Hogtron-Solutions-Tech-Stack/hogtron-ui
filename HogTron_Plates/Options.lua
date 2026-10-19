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
  local t = Options.Table()
  Options.AddKindToggles(t)
  return t
end

function Options.Table()
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
        friendlyPets = { type = "toggle", name = "Friendly pets, minions and guardians get a nameplate (so their names use our font)", order = 6.1,
          desc = "Without a plate the game draws its own small blue name over them - no addon can change that one.",
          get = function() return p().friendlyPets ~= false end, set = function(_, v) p().friendlyPets = v and true or false; HHP.Plates.ApplyCVars() end },
        friendlyTotems = { type = "toggle", name = "Also totems", order = 6.2,
          get = function() return p().friendlyTotems == true end, set = function(_, v) p().friendlyTotems = v and true or false; HHP.Plates.ApplyCVars() end },
        barHeight = range(p, "barHeight", "Bar height", 6.1, 6, 30, 1),
        widthScale = range(p, "widthScale", "Plate width (x)", 6.2, 0.6, 2.0, 0.05),
        castbar = toggle(p, "castbar", "Flatten the cast bar under the plate", 7),
        flatBar = { type = "toggle", name = "Plain flat health bar (hide Blizzard's bar art)", order = 7.05,
          get = function() return p().flatBar ~= false end, set = function(_, v) p().flatBar = v and true or false; refresh() end },
        hideBorders = { type = "toggle", name = "Hide Blizzard's bar border (the yellow line)", order = 7.1,
          get = function() return p().hideBorders ~= false end, set = function(_, v) p().hideBorders = v and true or false; refresh() end },
        friendlyNameOnly = toggle(p, "friendlyNameOnly", "Friendly plates: name only (no health bar)", 7.5),
        hideDeadBars = toggle(p, "hideDeadBars", "Dead units: name only (no 0% bar on a corpse)", 7.55),
        nameAlign = { type = "select", name = "Name over the bar", order = 7.6, values = { left = "Left, lined up with the bar", center = "Centred" },
          get = function() return p().nameAlign or "left" end, set = function(_, v) p().nameAlign = v refresh() end },
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
      castbar = { type = "group", name = "Cast bar", order = 1.5, args = {
        about = { type = "description", order = 0, name = "Our own cast bar under the plate, the HUD look: flat fill, ink backing, spell icon, name, time left; grey while the cast cannot be interrupted. Blizzard's bar goes quiet." },
        enabled = toggle(p, "castbar", "HogTron UI cast bar under the plate", 1),
        height = range(sub("cast"), "height", "Height", 2, 6, 24, 1),
        icon = toggle(sub("cast"), "icon", "Spell icon", 3),
        time = toggle(sub("cast"), "time", "Time left", 4),
        fontSize = range(sub("cast"), "fontSize", "Text size", 5, 7, 16, 1),
        castColor = colour(sub("cast"), "castColor", "Cast colour", 6),
        channelColor = colour(sub("cast"), "channelColor", "Channel colour", 7),
        lockedColor = colour(sub("cast"), "lockedColor", "Uninterruptible colour", 8),
      } },
      objectGlow = { type = "group", name = "Object glow", order = 1.8, args = {
        about = { type = "description", order = 0, name = "Ore veins, herbs, chests, quest objects and your fishing bobber glow when you come near - the one the game picks for the interact key, tinted by kind (green herb, orange ore, gold chest, cyan quest). Grey and still = you cannot use it yet. Works through Blizzard's soft targeting: the settings it changes are given back when you turn this off and at logout." },
        enabled = { type = "toggle", name = "Object glow", order = 1, width = "full",
          get = function() return HH.db.profile.plates.objectGlow.enabled ~= false end,
          set = function(_, v) HH.db.profile.plates.objectGlow.enabled = v and true or false; HH:SafeCall(HHP.ObjectGlow, "Apply") end },
        anyDirection = { type = "toggle", name = "Any direction (the nearest one lights up wherever you face; off = only straight ahead)", order = 1.5, width = "full",
          get = function() return HH.db.profile.plates.objectGlow.anyDirection ~= false end,
          set = function(_, v) HH.db.profile.plates.objectGlow.anyDirection = v and true or false; HH:SafeCall(HHP.ObjectGlow, "Apply") end },
        range = { type = "range", name = "How far the game looks (yards)", order = 2, min = 5, max = 40, step = 1,
          get = function() return HH.db.profile.plates.objectGlow.range or 15 end,
          set = function(_, v) HH.db.profile.plates.objectGlow.range = v; HH:SafeCall(HHP.ObjectGlow, "Apply") end },
        kindsHeader = { type = "header", name = "Glow on", order = 3 },
        size = { type = "range", name = "Size", order = 4, min = 24, max = 120, step = 2,
          get = function() return HH.db.profile.plates.objectGlow.size or 56 end, set = function(_, v) HH.db.profile.plates.objectGlow.size = v end },
        intensity = { type = "range", name = "Brightness", order = 5, min = 0.2, max = 1, step = 0.05,
          get = function() return HH.db.profile.plates.objectGlow.intensity or 0.9 end, set = function(_, v) HH.db.profile.plates.objectGlow.intensity = v end },
        offset = { type = "range", name = "Up / down from the object's plate", order = 6, min = -60, max = 60, step = 2,
          get = function() return HH.db.profile.plates.objectGlow.offset or 0 end, set = function(_, v) HH.db.profile.plates.objectGlow.offset = v; HH:SafeCall(HHP.ObjectGlow, "Evaluate") end },
        label = { type = "toggle", name = "Its name above the glow", order = 7,
          get = function() return HH.db.profile.plates.objectGlow.label ~= false end, set = function(_, v) HH.db.profile.plates.objectGlow.label = v and true or false; HH:SafeCall(HHP.ObjectGlow, "Evaluate") end },
        icon = { type = "toggle", name = "What it is inside the ring (gear, pick, herb)", order = 7.5,
          desc = "The game's icon over the object moves into the middle of the glow, so it never sits under the name.",
          get = function() return HH.db.profile.plates.objectGlow.icon ~= false end, set = function(_, v) HH.db.profile.plates.objectGlow.icon = v and true or false; HH:SafeCall(HHP.ObjectGlow, "Evaluate") end },
        hideBlocked = { type = "toggle", name = "No glow on what you cannot use yet (instead of grey)", order = 8,
          get = function() return HH.db.profile.plates.objectGlow.hideBlocked == true end, set = function(_, v) HH.db.profile.plates.objectGlow.hideBlocked = v and true or false; HH:SafeCall(HHP.ObjectGlow, "Evaluate") end },
        preview = { type = "execute", name = "Preview", order = 9, desc = "Each kind for a moment, mid-screen. No object needed.", func = function() HH:SafeCall(HHP.ObjectGlow, "Preview") end },
        diag = { type = "execute", name = "Print diagnostics to chat", order = 10, func = function() HH:SlashCommand("glowdiag") end },
      } },
      die = { type = "group", name = "Does it die", order = 1.7, args = {
        about = { type = "description", order = 0, name = "Will my DoT finish this mob? A skull beside the plate when it will (move on), a red X pulsing when the DoT is about to drop and the mob will outlive it (reapply). Time to die comes from the mob's health over the last seconds; on a client that hides enemy health in combat the mark stays off (/hh platediag says so)." },
        enabled = { type = "toggle", name = "Show the mark", order = 1, width = "full",
          get = function() return HH.db.profile.plates.die.enabled ~= false end,
          set = function(_, v) HH.db.profile.plates.die.enabled = v and true or false end },
        reapplyAt = { type = "range", name = "Reapply warning (seconds left on the DoT)", order = 2, min = 1, max = 8, step = 0.5,
          get = function() return HH.db.profile.plates.die.reapplyAt or 3 end, set = function(_, v) HH.db.profile.plates.die.reapplyAt = v end },
        margin = { type = "range", name = "How clearly it must die first (%)", order = 3, min = 0, max = 40, step = 5,
          get = function() return (HH.db.profile.plates.die.margin or 0.1) * 100 end, set = function(_, v) HH.db.profile.plates.die.margin = v / 100 end },
        size = { type = "range", name = "Mark size", order = 4, min = 10, max = 32, step = 1,
          get = function() return HH.db.profile.plates.die.size or 18 end, set = function(_, v) HH.db.profile.plates.die.size = v end },
        showTime = { type = "toggle", name = "Seconds under the mark", order = 5,
          get = function() return HH.db.profile.plates.die.showTime ~= false end, set = function(_, v) HH.db.profile.plates.die.showTime = v and true or false end },
        target = { type = "toggle", name = "Also on the target frame", order = 6,
          get = function() return HH.db.profile.plates.die.target ~= false end, set = function(_, v) HH.db.profile.plates.die.target = v and true or false end },
      } },
      highlight = { type = "group", name = "Highlight", order = 2, args = {
        about = { type = "description", order = 0, name = "Your target: a soft glow around its bar that locks on, then breathes (or four sharp corners / the plate magnified / the old outline). A mob on YOU gets a red outline over everything; quest mobs an amber one." },
        target = toggle(sub("target"), "highlight", "Mark my target", 1),
        style = { type = "select", name = "Target mark", order = 1.5, values = { brackets = "Corner brackets (sharp)", glow = "Glow around the bar (soft)", scale = "Magnify the plate", outline = "Outline (box)", none = "None" },
          get = function() return sub("target")().style or "glow" end, set = function(_, v) sub("target")().style = v; refresh() end },
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

--- Object glow: one toggle per kind (herb / ore / chest / quest / bobber / other), under its "Glow on" header.
function Options.AddKindToggles(t)
  local G = HHP.ObjectGlow
  local args = t and t.args and t.args.objectGlow and t.args.objectGlow.args
  if not G or not args then return end
  for i, k in ipairs(G.KINDS) do
    args["kind_" .. k] = { type = "toggle", name = G.KIND_NAMES[k], order = 3 + i / 10, width = "full",
      get = function() local kinds = HH.db.profile.plates.objectGlow.kinds or {} if k == "other" then return kinds.other == true end return kinds[k] ~= false end,
      set = function(_, v) local og = HH.db.profile.plates.objectGlow og.kinds = og.kinds or {} og.kinds[k] = v and true or false; HH:SafeCall(G, "Evaluate") end }
  end
end
