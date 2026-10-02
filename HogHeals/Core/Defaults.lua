-- AceDB defaults. Layout profiles per group-size bucket.
local ADDON, ns = ...
local HH = HogHeals

local function layout(width, height, spacing, growth, groupsPerRow, groupsShown, orientation)
  return {
    width = width, height = height, spacing = spacing,
    growth = growth,                 -- "DOWN" | "UP" | "RIGHT" | "LEFT" (unit growth inside a group)
    groupsPerRow = groupsPerRow,     -- how many groups side by side before wrapping
    groupsShown = groupsShown,       -- 1 for party, 2/4/8 for raids
    groupGrowth = "RIGHT",           -- direction groups stack
    orientation = orientation or "vertical",
    showPets = false,
    showSolo = true,                 -- "me + pet when solo"
    anchor = { point = "CENTER", x = 0, y = -200 },
    scale = 1,
  }
end

HH.defaults = {
  global = { schema = nil },
  profile = {
    locked = true,
    minimap = { hide = true },
    wizardDone = false,
    units = {
      enabled = true, hideBlizzard = true, tooltips = true,
      classColors = true, reactionColors = true, healthColor = { 0.25, 0.80, 0.35 },
      healthText = "current-max", powerText = "current-max",   -- percent | current | current-max | current-percent | none (Sean: "343 / 343")
      texture = "Solid", font = "Friz Quadrata TT", fontSize = 12, backgroundAlpha = 0.6,
      -- flanking the bottom centre (ElvUI's arrangement): player left, target right, small frames beside them
      player = { enabled = true, width = 240, height = 42, powerHeight = 8, showPower = true, showName = true, showLevel = true, point = "BOTTOM", x = -280, y = 230 },
      target = { enabled = true, width = 240, height = 42, powerHeight = 8, showPower = true, showName = true, showLevel = true, point = "BOTTOM", x = 280, y = 230,
        castbar = true, castbarHeight = 16, debuffs = true, buffs = false, auraSize = 22, aurasPerRow = 8, maxDebuffs = 16, maxBuffs = 16,
        debuffFilter = "mine-first", myDebuffSize = 28, auraTimers = true },   -- debuffFilter: mine-first | mine | all
      targettarget = { enabled = true, width = 170, height = 28, powerHeight = 4, showPower = true, showName = true, showLevel = false, point = "BOTTOM", x = 500, y = 275 },
      pet = { enabled = true, width = 170, height = 28, powerHeight = 4, showPower = true, showName = true, showLevel = false, point = "BOTTOM", x = -500, y = 275 },
      focus = { enabled = false, width = 200, height = 36, powerHeight = 6, showPower = true, showName = true, showLevel = true, point = "BOTTOM", x = 280, y = 330,
        castbar = true, castbarHeight = 14, debuffs = true, buffs = false, auraSize = 20, aurasPerRow = 8, maxDebuffs = 8, maxBuffs = 8,
        debuffFilter = "mine-first", myDebuffSize = 26, auraTimers = true },
    },
    frames = {
      hideBlizzard = true,           -- our group frames on = Blizzard's party / raid-style frames off
      soloSharesParty = true,        -- one layout for solo and party (size, growth, anchor); showSolo stays solo's own
      layouts = {
        -- Square-ish cells (Grid / Cell proportions): name on top, deficit below, thin power strip.
        solo   = layout(90, 60, 2, "CENTER", 1, 1),   -- me dead centre; the row widens both ways as people join
        party  = layout(90, 60, 2, "CENTER", 1, 1),
        raid10 = layout(80, 52, 2, "DOWN", 2, 2),
        raid20 = layout(72, 46, 2, "DOWN", 4, 4),
        raid40 = layout(62, 40, 1, "DOWN", 8, 8),
      },
      appearance = {
        font = "Friz Quadrata TT", fontSize = 11, fontOutline = "OUTLINE",
        texture = "Solid",           -- flat; the glossy Blizzard bar read as "what is this"
        healthMode = "class",        -- "class" | "deficit" | "custom"
        healthText = "deficit",      -- "percent" | "deficit" | "none"
        healthColor = { 0.25, 0.80, 0.35 },
        backgroundAlpha = 0.6,
        powerHeight = 3,
        powerHealerOnly = true,
        nameLength = 10,
        namePosition = "TOP",        -- TOP | CENTER | BOTTOM   (vertical)
        nameAlign = "CENTER",        -- LEFT | CENTER | RIGHT   (horizontal)
        healthTextPosition = "BOTTOM",
        healthTextAlign = "CENTER",
        outOfRangeAlpha = 0.4,
        deficitGradient = true,
      },
      indicators = {
        health = true, power = true, name = true, healPrediction = true,
        dispel = true, range = true, aggro = true, raidIcon = true, statusIcons = true,
        missingBuffs = true, myShield = true, thresholds = false, aoeHealing = true,
        priorityDebuff = true, requestGlow = true,
      },
      dispel = { style = "icon", priorityDebuffs = {} },  -- style: "icon" | "color" | "border"
      thresholds = { 35, 50 },
      healthFade = { enabled = false, above = 90, alpha = 0.5 },
      healPrediction = { show = "all", overheal = true },    -- "mine" | "others" | "all"
      bindings = {},                                          -- per-class hover-binds, filled by ClickCast.Defaults
      fallback = { mouseover = true, focus = false, target = true, player = true },
      bindingMode = "hover",          -- "hover": keys bound while the mouse is over a frame (blocked in combat on
                                      -- restricted clients) | "global": keys bound once, cast on mouseover/target/self
      bindingForce = false,           -- global mode: also take keys that already have a binding
    },
    meter = {
      enabled = true, hideBlizzard = true, mode = "DamageDone", segment = "Current",
      width = 300, barHeight = 22, maxBars = 10, backgroundAlpha = 0.85, refresh = 1, fontSize = 12,
      fixedHeight = true,             -- Details-style: the panel always shows maxBars slots, even empty
      border = true, classIcons = true,
      point = "CENTER", x = 420, y = -220,
    },
    quests = {
      tracker = {
        enabled = true, hideBlizzard = true, mode = "watched",   -- "watched" (all when none) | "zone" | "all"
        showLevels = true, hideCompleted = false, collapsed = false, lockPosition = false, autoTrack = true,
        width = 260, maxHeight = 420, fontSize = 13, scale = 1, backgroundAlpha = 0.6,
        fill = true, bottomMargin = 20,   -- run down to the screen's bottom edge and scroll; maxHeight only when fill is off
        point = "TOPRIGHT", x = -80, y = -260,
      },
      minimap = { enabled = true, edge = true, watchedOnly = false, turnInInRange = false, size = 16 },   -- Forever draws areas only, not points
      map = { enabled = true, fill = true, size = 180, zoneText = true, wheelZoom = true, hideDecor = true, dockButtons = true },
      -- the world map (M): coordinates strip, scale, fade while moving, border art off (skipped when Leatrix Maps runs)
      -- coords + skin OFF: in game 2026-09-23 this client's "Map & Quest Log" frame already prints the player's
      -- coordinates, and hiding its art left holes ("this looks terrible"). Both stay as opt-ins.
      worldMap = { enabled = true, coords = false, scale = 1.0, fadeWhileMoving = true, skin = false, alpha = 0.95 },
      buttons = { enabled = true, side = "left", columns = 4, size = 28, alpha = 0.92, hover = false, autoClose = true },   -- addon minimap icons in one drawer; side: left (opens toward the screen) | right (opens down); point/x/y once dragged
    },
    chat = {
      enabled = true, backgroundAlpha = 0.6, fontSize = nil, outline = false,   -- fontSize nil = keep Blizzard's size
      shortChannels = true, classNames = true, fade = true, hideButtons = true, hideMenuButtons = false, urlCopy = true,
    },
    plates = {
      enabled = true,                 -- restyle Blizzard's nameplates (flat bar, outline, health text)
      font = "Friz Quadrata TT", fontSize = 13, healthText = "percent",   -- "percent" | "value" | "none"
      barHeight = 14, widthScale = 1.3,   -- bar height in px; plate width as a multiple of Blizzard's (cvar)
      flatBar = true,                 -- plain flat bar: all of Blizzard's art on the health bar hidden (heal / absorb kept)
      hideBorders = true,             -- Blizzard's own bar border / selection line off (ours is the dark 1 px edge)
      border = true, classColors = true, reactionColors = true, castbar = true,
      nameClass = "friendly",         -- player names on plates in class colour: "friendly" | "all" | "none"
      friendlyNameOnly = true,        -- friendly plates: just the name, no health bar
      friendlyNameSize = 14,          -- text size of that name (the overhead name is about this)
      showLevel = true,               -- the unit's level, right of the bar (our text; Blizzard's badge stays hidden)
      uniformScale = true, targetScale = 1.15,  -- same plate size at every distance; the target's plate scale
      maxDistance = 60,               -- nameplateMaxDistance (yards); the client clamps to what it allows
      target = { highlight = true, style = "brackets", scale = 1.25, color = { 0.13, 0.83, 0.88 }, fadeOthers = false, otherAlpha = 0.6,
        glowSize = 9, animate = true, hideBlizzard = true, bracketSize = 10,
      },   -- style: brackets | glow | scale | outline | none; brackets = hard corners, glow = lock on + breathe
      aggro = { warn = true, color = { 0.85, 0.20, 0.20 } },   -- healer pulled threat: red outline
      quest = { icon = true, highlight = false, progress = true, tint = false, iconSize = 16, color = { 0.95, 0.65, 0.15 } },
    },
    hud = {
      x = 0, y = -180, width = 300, followFrames = false,
      castbarHeight = 18, manaHeight = 12, infoHeight = 14, rowSpacing = 2,
      showCastbar = true, showMana = true, showInfo = true,
      font = "Friz Quadrata TT", fontSize = 11, texture = "Solid",
      castbar = {
        icon = true, showTarget = true, latency = true, gcd = false, hideBlizzard = true, precision = 1,
        castColor = { 0.13, 0.83, 0.88 }, channelColor = { 0.25, 0.80, 0.35 }, uninterruptibleColor = { 0.6, 0.6, 0.6 },
        failColor = { 0.85, 0.2, 0.2 },
      },
      mana = { textMode = "cur", showTicks = true, showFsrText = true, fsrColor = { 0.13, 0.83, 0.88 }, tickColor = { 0.96, 0.92, 0.86 } },
      pacing = { enabled = true, targetLength = 300, amber = 60, red = 20, showProjection = true },
      advisor = { enabled = true, margin = 0.9, onFrame = false, spells = {} },
    },
    skin = {
      enabled = true, font = "Friz Quadrata TT", backgroundAlpha = 0.75,
      actionBars = { enabled = true, hideArt = true, hotkeySize = 10, hideNames = true, cooldownNumbers = true },
      -- parchment windows get the parchment treatment in Panels.lua (fonts recoloured, inner art stripped);
      -- World Map and the tabard designer keep their own art
      -- skipped: World Map and the flight map draw their maps as plain textures (in game 2026-09-23 the flight
      -- map went black); the tabard designer needs its art
      panels = { enabled = true, alpha = 0.9, titleSize = 13, skip = { WorldMapFrame = true, TaxiFrame = true, TabardFrame = true } },
      auto = { sellJunk = true, repair = true, guildRepair = false },
      micro = { enabled = true, scale = 1 },
      bagBar = { enabled = true },
      bags = { enabled = true, qualityMin = 2, fontSize = 12, backgroundAlpha = 0.85 },
      tooltips = { enabled = true, alpha = 0.9, fontSize = nil, anchorCursor = false },
      extras = { buffs = true, xpBar = true, durationSize = 10 },
      infoBar = { enabled = true, width = 640, height = 18, fontSize = 11, backgroundAlpha = 0.8, refresh = 1,
        time24 = false, serverTime = false, point = "BOTTOM", x = 0, y = 0,
        slots = { "gold", "durability", "bags", "fps", "latency", "time" } },
    },
  },
}

-- Solo frame off by default since 2026-09-23: HogUI Units draws the player and pet frames; the healer frames are
-- for party / raid. (Sean: "turn off the HogHeals solo frames".)
HH.defaults.profile.frames.layouts.solo.showSolo = false
