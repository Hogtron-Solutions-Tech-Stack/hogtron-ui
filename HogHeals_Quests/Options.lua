-- Quests options: two tabs, Tracker and Minimap. Every set() writes profile.quests and refreshes that part.
HogHealsQuests = HogHealsQuests or {}
local HHQ = HogHealsQuests
local HH = HogHeals

local Options = {}
HHQ.Options = Options

local function t() return HH.db.profile.quests.tracker end
local function mm() return HH.db.profile.quests.minimap end
local function mp() return HH.db.profile.quests.map end
local function bt() return HH.db.profile.quests.buttons end

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
  local sr = function() HHQ.MapSkin.Refresh() HH:SafeCall(HHQ.Buttons, "Anchor") end
  local br = function() HH:SafeCall(HHQ.Buttons, "Refresh") end
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
        lockPosition = toggle(t, "lockPosition", "Lock position (otherwise drag the header to move it)", 4.5, tr),
        autoTrack = toggle(t, "autoTrack", "Watch new quests automatically when accepted", 4.7, tr),
        hideCompleted = toggle(t, "hideCompleted", "Hide finished quests", 5, tr),
        width = range(t, "width", "Width", 6, 160, 480, 10, tr),
        maxHeight = range(t, "maxHeight", "Max height", 7, 120, 900, 10, tr),
        fontSize = range(t, "fontSize", "Text size", 8, 8, 28, 1, tr),
        scale = range(t, "scale", "Scale (whole window)", 8.5, 0.6, 2.5, 0.05, tr),
        backgroundAlpha = range(t, "backgroundAlpha", "Background opacity", 9, 0, 1, 0.05, tr),
      } },
      minimap = { type = "group", name = "Minimap", order = 2, args = {
        look = { type = "group", inline = true, name = "Look", order = 1, args = {
          about = { type = "description", order = 0, name = "Square minimap in the HogHeals frame, zone name on top (click it for the world map), mouse wheel zooms. Turning it off fully undoes it after a /reload." },
          enabled = toggle(mp, "enabled", "HogHeals minimap", 1, sr),
          fill = toggle(mp, "fill", "Fill the whole minimap box (resize it in Edit Mode)", 1.5, sr),
          size = { type = "range", name = "Size (when not filling the box)", order = 2, min = 120, max = 400, step = 5,
            disabled = function() return mp().fill ~= false end,
            get = function() return mp().size end, set = function(_, v) mp().size = v; sr() end },
          dockButtons = toggle(mp, "dockButtons", "Move the LFG eye and day/night button into the header", 2.5, sr),
          zoneText = toggle(mp, "zoneText", "Zone name on top", 3, sr),
          wheelZoom = toggle(mp, "wheelZoom", "Mouse wheel zoom", 4, sr),
          hideDecor = toggle(mp, "hideDecor", "Hide Blizzard's round border and zoom buttons", 5, sr),
        } },
        pins = { type = "group", inline = true, name = "Quest markers", order = 2, args = {
          about = { type = "description", order = 0, name = "Quest markers on the minimap: amber ! = objective, amber ? = ready to turn in. Blizzard only shades the quest AREA; these mark the spot. Far quests get an arrow on the rim (except the one Blizzard already points at with its gold arrow). Hover for the objectives, click to open the quest." },
          enabled = toggle(mm, "enabled", "Quest markers", 1, pr),
          edge = toggle(mm, "edge", "Arrow on the rim for far quests", 2, pr),
          watchedOnly = toggle(mm, "watchedOnly", "Only watched quests", 3, pr),
          turnInInRange = toggle(mm, "turnInInRange", "Also mark nearby turn-ins (Blizzard already shows a ? on the NPC)", 3.5, pr),
          size = range(mm, "size", "Pin size", 4, 8, 32, 1, pr),
        } },
        buttons = { type = "group", inline = true, name = "Addon buttons", order = 3, args = {
          about = { type = "description", order = 0, name = "Every addon's minimap icon (Atlas, Details, Bagnon, ...) gathered into one drawer under the minimap - click the three-dot button to open it. Blizzard's own buttons (tracking, mail, clock, LFG) stay where they are. Turning this off hands the icons back." },
          enabled = toggle(bt, "enabled", "Gather addon buttons into a drawer", 1, br),
          columns = range(bt, "columns", "Columns", 2, 1, 10, 1, br),
          size = range(bt, "size", "Icon size", 3, 16, 40, 2, br),
          hover = toggle(bt, "hover", "Open on mouse-over", 4, br),
          autoClose = toggle(bt, "autoClose", "Close when the mouse leaves", 5, br),
        } },
      } },
    },
  }
end
