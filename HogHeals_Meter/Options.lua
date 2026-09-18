-- Meter options tab. Every set() writes profile.meter and calls Meter.Refresh().
HogHealsMeter = HogHealsMeter or {}
local HHM = HogHealsMeter
local HH = HogHeals

local Options = {}
HHM.Options = Options

local function m() return HH.db.profile.meter end
local function refresh() HHM.Meter.Refresh() end

local function toggle(key, name, order, desc)
  return { type = "toggle", name = name, desc = desc, order = order,
    get = function() return m()[key] ~= false end,
    set = function(_, v) m()[key] = v and true or false; refresh() end }
end
local function range(key, name, order, min, max, step)
  return { type = "range", name = name, order = order, min = min, max = max, step = step,
    get = function() return m()[key] end,
    set = function(_, v) m()[key] = v; refresh() end }
end

function Options.Build()
  local modes, segments = {}, {}
  for _, mode in ipairs(HHM.Meter.MODES) do modes[mode.key] = mode.label end
  for _, s in ipairs(HHM.Meter.SEGMENTS) do segments[s.key] = s.label end
  return {
    type = "group", name = "Meter", order = 30,
    args = {
      about = { type = "description", order = 0, name = function()
        if HHM.Meter.unavailable then return "This client exposes no damage-meter data to addons." end
        return "Shows the client's own meter data in HogHeals style. Left-click the header to change what is shown, right-click for current fight / overall. Numbers are Blizzard's; the addon only draws them."
      end },
      enabled = toggle("enabled", "Show the meter", 1),
      hideBlizzard = toggle("hideBlizzard", "Hide Blizzard's meter while ours is on", 2, "Turning this off needs a /reload to bring Blizzard's window back."),
      mode = { type = "select", name = "Show", order = 3, values = modes,
        get = function() return m().mode end, set = function(_, v) HHM.Meter.SetMode(v) end },
      segment = { type = "select", name = "Segment", order = 4, values = segments,
        get = function() return m().segment end, set = function(_, v) HHM.Meter.SetSegment(v) end },
      width = range("width", "Width", 5, 140, 500, 10),
      barHeight = range("barHeight", "Bar height", 6, 12, 30, 1),
      fontSize = range("fontSize", "Font size", 6.5, 8, 20, 1),
      maxBars = range("maxBars", "Max rows", 7, 1, 40, 1),
      backgroundAlpha = range("backgroundAlpha", "Background opacity", 8, 0, 1, 0.05),
      refresh = range("refresh", "Refresh (seconds)", 9, 0.5, 5, 0.5),
      reset = { type = "execute", name = "Reset meter data", order = 10, func = function() HHM.Meter.Reset() end },
    },
  }
end
