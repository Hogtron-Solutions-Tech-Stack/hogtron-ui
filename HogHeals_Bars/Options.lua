-- Bars options tab. Every set() writes profile.bars and re-applies. Per-bar groups are built from Bars.SPECS (T1).
HogHealsBars = HogHealsBars or {}
local HHB = HogHealsBars
local HH = HogHeals

local Options = {}
HHB.Options = Options

local function root() return HH.db.profile.bars end
local function apply() HHB.Bars.Apply("options") end

local function toggle(tbl, key, name, order, desc, width)
  return { type = "toggle", name = name, desc = desc, order = order, width = width,
    get = function() return tbl()[key] ~= false end,
    set = function(_, v) tbl()[key] = v and true or false; apply() end }
end
local function range(tbl, key, name, order, min, max, step, default)
  return { type = "range", name = name, order = order, min = min, max = max, step = step,
    get = function() local v = tbl()[key] if v == nil then return default end return v end,
    set = function(_, v) tbl()[key] = v; apply() end }
end
Options.toggle, Options.range = toggle, range

function Options.Build()
  local args = {
    about = { type = "description", order = 0, name = "Your own action bars (Bartender-style) in the HogUI look: Blizzard's bars are hidden, every spell stays in its slot and every keybind keeps working. Each bar has its own layout, grid and visibility. /hh unlock to drag the bars, /hh bind to bind keys by hovering a slot." },
    enabled = toggle(root, "enabled", "HogUI Bars on (needs a /reload when turned off)", 1, nil, "full"),
    grid = toggle(root, "grid", "Always show empty slots (grid)", 2, nil, "full"),
    hotkeySize = range(root, "hotkeySize", "Keybind text size", 3, 7, 16, 1, 10),
    hideNames = toggle(root, "hideNames", "Hide macro names on buttons", 4),
    bind = { type = "execute", name = "Key bindings (hover a slot, press a key)", order = 5, width = "full",
      func = function() if HHB.Bind and HHB.Bind.Toggle then HHB.Bind.Toggle() else HH:Print("Bind mode lands in the next step.") end end },
  }
  if HHB.Bars.BarOptions then
    for key, group in pairs(HHB.Bars.BarOptions()) do args[key] = group end
  end
  return { type = "group", name = "Bars", order = 38, childGroups = "tab", args = args }
end
