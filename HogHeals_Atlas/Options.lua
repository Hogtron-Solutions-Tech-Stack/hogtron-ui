-- Options tab for Atlas (AceConfig-style table, drawn by the HogUI options window).
local A = HogHealsAtlas

local Options = {}
A.Options = Options

local function refresh() if A.Window and A.Window.Refresh then A.Window.Refresh() end end

local function toggle(key, name, order, desc)
  return { type = "toggle", name = name, order = order, desc = desc,
    get = function() return A.cfg()[key] ~= false end,
    set = function(_, v) A.cfg()[key] = v and true or false refresh() end }
end

function Options.Build()
  local args = {
    about = { type = "description", order = 0, name = "Dungeon guide: levels, bosses, loot, dungeon quests, gear upgrades, sets and a wishlist. Open with /hh atlas. Loot tables are read from the game and learned in play: Forever changed the old ones, so none are shipped." },
    open = { type = "execute", name = "Open Atlas", order = 1, func = function() A.Window.Show() end },
    scan = { type = "execute", name = "Read the game's journal", order = 2, func = function() A.Journal.Scan("options") refresh() end },
    enabled = toggle("enabled", "Record drops in dungeons", 3),
    tooltip = toggle("tooltip", "\"Drops from\" line on item tooltips", 4),
    wishAlerts = toggle("wishAlerts", "Chat line and sound when a wishlist item drops", 5),
    forMeNow = { type = "toggle", name = "Dungeon list: only dungeons for my level", order = 6,
      get = function() return A.cfg().forMeNow == true end, set = function(_, v) A.cfg().forMeNow = v and true or false refresh() end },
    minQuality = { type = "select", name = "Record drops of quality", order = 7,
      values = { [1] = "White and better", [2] = "Green and better", [3] = "Blue and better" },
      get = function() return A.cfg().minQuality or 2 end, set = function(_, v) A.cfg().minQuality = v end },
    futureLevels = { type = "range", name = "Upgrades: look ahead (levels)", order = 8, min = 0, max = 10, step = 1,
      get = function() return A.cfg().futureLevels or 3 end, set = function(_, v) A.cfg().futureLevels = v refresh() end },
    role = { type = "select", name = "Score gear for", order = 9,
      values = { auto = "My class (automatic)", healer = "Healer", caster = "Caster", melee = "Melee", ranged = "Ranged", tank = "Tank" },
      get = function() return A.cfg().role or "auto" end, set = function(_, v) A.cfg().role = v refresh() end },
    scale = { type = "range", name = "Window scale", order = 10, min = 0.6, max = 1.4, step = 0.05,
      get = function() return A.cfg().scale or 1 end,
      set = function(_, v) A.cfg().scale = v if A.Window.frame then A.Window.frame:SetScale(v) end end },
    weights = { type = "group", name = "Stat weights", order = 20, args = {
      about = { type = "description", order = 0, name = "Points per 1 of each stat, for the role gear is scored for now. Change the role above to edit another set. 0 = the stat does not count." },
      reset = { type = "execute", name = "Back to the starting weights", order = 1, func = function()
        A.cfg().weights[A.Stats.Role()] = nil
        refresh()
      end },
    } },
  }
  for i, key in ipairs(A.Stats.ORDER) do
    args.weights.args[key] = { type = "range", name = A.Stats.NAMES[key], order = 10 + i, min = 0, max = 20, step = 0.05,
      get = function() return A.Stats.Weights()[key] or 0 end,
      set = function(_, v)
        local c = A.cfg()
        local role = A.Stats.Role()
        c.weights[role] = c.weights[role] or {}
        c.weights[role][key] = v
        refresh()
      end }
  end
  return { type = "group", name = "Atlas", args = args }
end
