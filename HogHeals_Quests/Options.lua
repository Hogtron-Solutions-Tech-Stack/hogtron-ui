-- Quests options: two tabs, Tracker and Minimap. Every set() writes profile.quests and refreshes that part.
HogHealsQuests = HogHealsQuests or {}
local HHQ = HogHealsQuests
local HH = HogHeals

local Options = {}
HHQ.Options = Options

local function t() return HH.db.profile.quests.tracker end
local function mm() return HH.db.profile.quests.minimap end
local function mp() return HH.db.profile.quests.map end
local function wm() return HH.db.profile.quests.worldMap end
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
  local sr = function() HHQ.MapSkin.Refresh() end
  local wr = function() HH:SafeCall(HHQ.WorldMap, "Refresh") end
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
        followMinimap = toggle(t, "followMinimap", "Sit under the minimap (dragging the header detaches it; tick again to put it back)", 4.3, tr),
        gap = range(t, "gap", "Gap under the minimap", 4.4, 0, 60, 2, tr),
        lockPosition = toggle(t, "lockPosition", "Lock position (otherwise drag the header to move it; /hh unlock shows a resize grip in the corner)", 4.5, tr),
        autoTrack = toggle(t, "autoTrack", "Watch new quests automatically when accepted", 4.7, tr),
        hideCompleted = toggle(t, "hideCompleted", "Hide finished quests", 5, tr),
        width = range(t, "width", "Width", 6, 160, 480, 10, tr),
        fill = toggle(t, "fill", "Run to the bottom of the screen (mouse wheel scrolls)", 6.5, tr),
        bottomMargin = { type = "range", name = "Gap above the screen's bottom edge", order = 6.7, min = 0, max = 400, step = 10,
          disabled = function() return t().fill == false end,
          get = function() return t().bottomMargin or 20 end, set = function(_, v) t().bottomMargin = v; tr() end },
        maxHeight = { type = "range", name = "Height (when not running to the bottom)", order = 7, min = 120, max = 900, step = 10,
          disabled = function() return t().fill ~= false end,
          get = function() return t().maxHeight end, set = function(_, v) t().maxHeight = v; tr() end },
        fixedHeight = { type = "toggle", name = "Keep that height even when the list is shorter (the resize grip sets this)", order = 7.2,
          disabled = function() return t().fill ~= false end,
          get = function() return t().fixedHeight == true end, set = function(_, v) t().fixedHeight = v and true or false; tr() end },
        fontSize = range(t, "fontSize", "Text size", 8, 8, 28, 1, tr),
        scale = range(t, "scale", "Scale (whole window)", 8.5, 0.6, 2.5, 0.05, tr),
        backgroundAlpha = range(t, "backgroundAlpha", "Background opacity", 9, 0, 1, 0.05, tr),
      } },
      worldmap = { type = "group", name = "World map", order = 3, args = {
        about = { type = "description", order = 0, name = "The map you open with M: size slider and fade while moving. Opt-ins (off - this client's map already shows your coordinates, and its combined map + quest log frame does not take the ink panel well): a coordinates strip with the cursor position, and the ink panel. Revealing unexplored terrain the way Leatrix Maps does needs its hand-built zone data; run Leatrix Maps alongside for that - when it is loaded, this leaves the map's look to it." },
        enabled = toggle(wm, "enabled", "HogUI world map", 1, wr),
        coords = toggle(wm, "coords", "Coordinates strip (you + cursor) - experimental", 2, wr),
        scale = range(wm, "scale", "Map size", 3, 0.5, 1.5, 0.05, wr),
        fadeWhileMoving = toggle(wm, "fadeWhileMoving", "Fade the map while moving", 4, wr),
        skin = toggle(wm, "skin", "Ink panel instead of Blizzard's border art - experimental (needs /reload to undo)", 5, wr),
        alpha = range(wm, "alpha", "Panel opacity", 6, 0.3, 1, 0.05, wr),
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
          about = { type = "description", order = 0, name = "Every addon's minimap icon (Atlas, Details, Bagnon, ...) gathered into one drawer - click the small H beside the minimap to open it. /hh unlock, then drag the H anywhere. Blizzard's own buttons (tracking, mail, clock, LFG) stay where they are. Turning this off hands the icons back." },
          enabled = toggle(bt, "enabled", "Gather addon buttons into a drawer", 1, br),
          side = { type = "select", name = "Where", order = 1.5, values = { left = "Bottom-left of the map, opens toward the screen", right = "Under the map, opens down" },
            get = function() return bt().side == "right" and "right" or "left" end, set = function(_, v) bt().side = v; br() end },
          resetPos = { type = "execute", name = "Reset position", order = 1.7, desc = "Back beside the map after you dragged it somewhere.",
            func = function() local d = bt() d.point, d.x, d.y = nil, nil, nil; br() end },
          alpha = range(bt, "alpha", "Drawer opacity", 3.5, 0.3, 1, 0.05, br),
          columns = range(bt, "columns", "Columns", 2, 1, 10, 1, br),
          size = range(bt, "size", "Icon size", 3, 16, 40, 2, br),
          hover = toggle(bt, "hover", "Open on mouse-over", 4, br),
          autoClose = toggle(bt, "autoClose", "Close when the mouse leaves", 5, br),
        } },
      } },
    },
  }
end
