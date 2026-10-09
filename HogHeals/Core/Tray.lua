-- Tray: the HogTron UI entries in the addon-button drawer (the "H" beside the minimap, HogHeals_Quests/Buttons.lua).
-- Sean 2026-10-08 in game: "our menus are getting a little overwhelming ... it should be broken down into separate
-- things and put into this tray: a bar one, a menu one, all sorts of different things". One glyph per thing you
-- would go looking for; each opens ONLY that module's settings in the compact one-column window (the one edit mode
-- uses), with "All settings" a click away inside it. The full /hh window is untouched.
--
-- An entry names a registered module (and, optionally, one of its tabs); entries whose module is not loaded, or
-- whose tab does not exist on this build, are left out (Tray.Available). Actions (lock, key binds) are slash
-- commands. Pure lists here; the drawer draws them.
local HH = HogHeals

local T = { seen = {} }
HH.Tray = T

-- key, letter (the glyph when no art), title (tooltip + window title), desc (one tooltip line), then either
-- module [+ tab] or action (a /hh word). Order = order in the drawer.
T.ENTRIES = {
  { key = "bars", letter = "B", title = "Bars", desc = "Action bars: layout, size, grid, paging.", module = "Bars" },
  { key = "menu", letter = "M", title = "Menu bar", desc = "The bottom menu buttons and the bag cell.", module = "Skin", tab = "micro" },
  { key = "frames", letter = "F", title = "Party / raid frames", desc = "Healer frames: layout, sizes, what they show.", module = "Frames" },
  { key = "units", letter = "U", title = "Unit frames", desc = "Player, target, pet, focus frames.", module = "Units" },
  { key = "hud", letter = "H", title = "HUD", desc = "Castbar, swing, mana, experience.", module = "HUD" },
  { key = "quests", letter = "Q", title = "Quests", desc = "Tracker, GO row, auto accept, announce.", module = "Quests", tab = "tracker" },
  { key = "map", letter = "W", title = "Map & minimap", desc = "Minimap, quest markers, world map.", module = "Quests", tab = "minimap" },
  { key = "chat", letter = "C", title = "Chat", desc = "Chat windows and tabs.", module = "Chat" },
  { key = "tips", letter = "T", title = "Tooltips", desc = "Tooltip look and where it sits.", module = "Skin", tab = "tooltips" },
  { key = "atlas", letter = "A", title = "Atlas", desc = "Dungeon guide: loot, quests, attunements.", module = "Atlas" },
  { key = "meter", letter = "D", title = "Meter", desc = "Healing / damage meter.", module = "Meter" },
  { key = "plates", letter = "N", title = "Nameplates", desc = "Nameplates over units.", module = "Plates" },
  { key = "lock", letter = "L", title = "Unlock / lock", desc = "Drag frames, click a box or gear for its settings.", action = "toggleLock" },
  { key = "bind", letter = "K", title = "Key binds", desc = "Hover a bar slot, press a key.", action = "bind", needs = "Bars" },
  { key = "hover", letter = "V", title = "Hover-heal keys", desc = "Keys that heal whoever is under the mouse.", action = "hoverbind", needs = "Frames" },
  { key = "all", letter = "=", title = "All settings", desc = "The whole HogTron UI options window.", action = "config" },
}

local function moduleTab(name, tab)
  local m = HH.modules and HH.modules[name]
  if not m or not m.GetOptions then return nil end
  if not tab then return true end
  local ok, root = pcall(HH.OptionsTable)
  local g = ok and type(root) == "table" and root.args and root.args[name]
  return type(g) == "table" and type(g.args) == "table" and type(g.args[tab]) == "table" or false
end

--- The entries this build can serve, in order.
function T.Available()
  local out = {}
  for _, e in ipairs(T.ENTRIES) do
    local ok
    if e.module then ok = moduleTab(e.module, e.tab)
    elseif e.needs then ok = HH.modules and HH.modules[e.needs] ~= nil
    else ok = true end
    if ok then out[#out + 1] = e end
  end
  return out
end

function T.Get(key)
  for _, e in ipairs(T.ENTRIES) do if e.key == key then return e end end
end

--- The title as it reads right now (lock / unlock flips).
function T.Title(e)
  if e.action == "toggleLock" then return HH.db.profile.locked and "Unlock (edit mode)" or "Lock" end
  return e.title
end

--- Open one entry: a module's settings in the compact window beside `anchor`, or run its action.
function T.Open(e, anchor)
  if type(e) == "string" then e = T.Get(e) end
  if not e then return false end
  T.seen[e.key] = (T.seen[e.key] or 0) + 1
  if e.action == "toggleLock" then HH:SlashCommand(HH.db.profile.locked and "unlock" or "lock") return true end
  if e.action then HH:SlashCommand(e.action) return true end
  local P = HH.Panel
  if not P or not P.Open then return false end
  local name = e.module
  P.selected, P.selectedTab = name, e.tab
  P.Open(function()
    local root = HH.OptionsTable()
    local g = root and root.args and root.args[name]
    if not g then return { type = "group", args = {} } end
    return { type = "group", handler = root.handler, args = { [name] = g } }
  end, { compact = true, anchor = anchor, title = e.title })
  T.last = e.key
  return true
end

function T.Lines()
  local names = {}
  for _, e in ipairs(T.Available()) do names[#names + 1] = e.key end
  return { ("tray: %d entries (%s)%s"):format(#names, table.concat(names, ","), T.last and ("; last opened " .. T.last) or "") }
end
