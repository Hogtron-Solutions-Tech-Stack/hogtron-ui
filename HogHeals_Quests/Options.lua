-- Quests options: two tabs, Tracker and Minimap. Every set() writes profile.quests and refreshes that part.
HogHealsQuests = HogHealsQuests or {}
local HHQ = HogHealsQuests
local HH = HogHeals

local Options = {}
HHQ.Options = Options

local function t() return HH.db.profile.quests.tracker end
local function mm() return HH.db.profile.quests.minimap end

local function toggle(tbl, key, name, order, after, desc)
  return { type = "toggle", name = name, desc = desc, order = order,
    get = function() return tbl()[key] ~= false and tbl()[key] ~= nil end,
    set = function(_, v) tbl()[key] = v and true or false; after() end }
end
local function range(tbl, key, name, order, min, max, step, after)
  return { type = "range", name = name, order = order, min = min, max = max, step = step,
    get = function() return tbl()[key] end,
    set = function(_, v) tbl()[key] = v; after() end }
end

function Options.Build()
  local tr = function() HHQ.Tracker.Refresh() end
  local pr = function() HHQ.Pins.Refresh() end
  return {
    type = "group", name = "Quests", order = 35,
    args = {
      tracker = { type = "group", name = "Tracker", order = 1, args = {
        about = { type = "description", order = 0, name = "Your quests in a HogHeals window. Left-click a quest to open it, right-click to watch / unwatch. Click the header to fold it, right-click the header to change what is listed." },
        enabled = toggle(t, "enabled", "Show the quest tracker", 1, tr),
        hideBlizzard = toggle(t, "hideBlizzard", "Hide Blizzard's tracker while ours is on", 2, tr, "Turning this off needs a /reload to bring Blizzard's tracker back."),
        mode = { type = "select", name = "List", order = 3, values = HHQ.Tracker.MODES,
          get = function() return t().mode or "watched" end, set = function(_, v) t().mode = v; tr() end },
        showLevels = toggle(t, "showLevels", "Quest levels", 4, tr),
        hideCompleted = toggle(t, "hideCompleted", "Hide finished quests", 5, tr),
        width = range(t, "width", "Width", 6, 160, 480, 10, tr),
        maxHeight = range(t, "maxHeight", "Max height", 7, 120, 900, 10, tr),
        fontSize = range(t, "fontSize", "Font size", 8, 8, 20, 1, tr),
        backgroundAlpha = range(t, "backgroundAlpha", "Background opacity", 9, 0, 1, 0.05, tr),
      } },
      minimap = { type = "group", name = "Minimap", order = 2, args = {
        about = { type = "description", order = 0, name = "Pins for your quests on the minimap: yellow ! = objective area, yellow ? = ready to turn in. Out of range pins sit on the rim, dimmed, pointing the way. Hover for the objectives, click to open the quest. These are the client's own quest points (not a Questie-style database), so quest givers you have not met yet do not show." },
        enabled = toggle(mm, "enabled", "Quest pins on the minimap", 1, pr),
        edge = toggle(mm, "edge", "Keep far quests on the rim", 2, pr),
        watchedOnly = toggle(mm, "watchedOnly", "Only watched quests", 3, pr),
        size = range(mm, "size", "Pin size", 4, 8, 28, 1, pr),
      } },
    },
  }
end
