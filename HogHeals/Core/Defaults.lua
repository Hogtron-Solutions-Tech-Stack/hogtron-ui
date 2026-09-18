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
    frames = {
      hideBlizzard = true,           -- our group frames on = Blizzard's party / raid-style frames off
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
      point = "CENTER", x = 420, y = -220,
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
  },
}
