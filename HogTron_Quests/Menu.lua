-- Menu: right-click a quest in the tracker -> what you can do with it: watch / stop watching, open in the quest
-- log, point the arrow at it, share with the party, abandon (with the game's own confirm). Sean 2026-10-08 in game:
-- "left-click should open the quest log; right-click a menu that will allow me to track, untrack, abandon, and
-- things like that".
--
-- Menu ladder, recorded in Menu.path: MenuUtil.CreateContextMenu (modern) -> EasyMenu on a UIDropDownMenuTemplate
-- (classic) -> UIDropDownMenu_Initialize + ToggleDropDownMenu (older) -> none (the tracker falls back to toggling
-- watch, as before). Abandon never happens without a confirm dialog: no StaticPopup on this client = a chat line
-- telling you to abandon from the quest log. Every API looked up by name.
HogHealsQuests = HogHealsQuests or {}
local HHQ = HogHealsQuests
local HH = HogHeals

local Menu = { seen = {}, path = "none" }
HHQ.Menu = Menu

local POPUP = "HOGHEALS_ABANDON_QUEST"

local function g(name) local f = rawget(_G, name) if type(f) == "function" then return f end end
local function fn(tbl, name) if type(tbl) == "table" and type(tbl[name]) == "function" then return tbl[name] end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a = pcall(f, ...)
  if ok then return a end
end
local function count(k) Menu.seen[k] = (Menu.seen[k] or 0) + 1 end

--- Make q the client's selected quest (modern by id, legacy by index). True when a way existed.
local function selectQuest(q)
  local C = rawget(_G, "C_QuestLog")
  if q.id and fn(C, "SetSelectedQuest") then call(C.SetSelectedQuest, q.id) return true end
  if q.index and g("SelectQuestLogEntry") then call(g("SelectQuestLogEntry"), q.index) return true end
  return false
end

-- ------------------------------------------------------------------------------------------------ pure
--- What the menu offers for q. ctx = { grouped, canPoint, canAbandon }. { { text, action, danger } } in order.
function Menu.Items(q, ctx)
  ctx = ctx or {}
  local items = {}
  local function add(text, action, danger) items[#items + 1] = { text = text, action = action, danger = danger or false } end
  add(q.watched and "Stop watching" or "Watch", "watch")
  add("Open in quest log", "open")
  if ctx.canPoint ~= false then add("Point the arrow at it", "point") end
  if ctx.grouped then add("Share with party", "share") end
  if ctx.canAbandon ~= false then add("Abandon...", "abandon", true) end
  return items
end

--- What this client can do.
function Menu.Context()
  local C = rawget(_G, "C_QuestLog")
  return {
    grouped = call(g("IsInGroup")) == true,
    canPoint = fn(rawget(_G, "C_SuperTrack"), "SetSuperTrackedQuestID") ~= nil,
    canAbandon = (fn(C, "AbandonQuest") or g("AbandonQuest")) ~= nil,
  }
end

-- ------------------------------------------------------------------------------------------------ actions
function Menu.Watch(q, on)
  HHQ.Data.SetWatched(q, on)
  if HHQ.Tracker and HHQ.Tracker.Schedule then HHQ.Tracker.Schedule() end
  count("watch")
  return true
end

function Menu.Open(q) HHQ.Data.Open(q) count("open") return true end

function Menu.Point(q)
  local st = rawget(_G, "C_SuperTrack")
  if q.id and fn(st, "SetSuperTrackedQuestID") then call(st.SetSuperTrackedQuestID, q.id) count("point") return true end
  return false
end

function Menu.Share(q)
  if not selectQuest(q) then return false end
  local push = g("QuestLogPushQuest")
  if not push then return false end
  call(push)
  count("share")
  return true
end

local function abandonNow(q)
  if not selectQuest(q) then return false end
  local C = rawget(_G, "C_QuestLog")
  local set, doit = fn(C, "SetAbandonQuest") or g("SetAbandonQuest"), fn(C, "AbandonQuest") or g("AbandonQuest")
  if not doit then return false end
  if set then call(set) end
  call(doit)
  count("abandoned")
  if HHQ.Tracker and HHQ.Tracker.Schedule then HHQ.Tracker.Schedule() end
  return true
end
Menu.AbandonNow = abandonNow

--- Ask first. The dialog's OnAccept re-selects the quest (the selection may have moved while it was up).
function Menu.Abandon(q)
  local dialogs, show = rawget(_G, "StaticPopupDialogs"), g("StaticPopup_Show")
  if type(dialogs) ~= "table" or not show then
    HH:Print("abandon: this client gives no confirm dialog - abandon it from the quest log.")
    return false
  end
  dialogs[POPUP] = dialogs[POPUP] or {
    text = "Abandon %s?", button1 = "Abandon", button2 = "Keep", timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function(_, data) if type(data) == "table" then abandonNow(data) end end,
  }
  call(show, POPUP, q.title or "this quest", nil, q)
  count("abandonAsked")
  return true
end

function Menu.Do(action, q)
  if action == "watch" then return Menu.Watch(q, not q.watched)
  elseif action == "open" then return Menu.Open(q)
  elseif action == "point" then return Menu.Point(q)
  elseif action == "share" then return Menu.Share(q)
  elseif action == "abandon" then return Menu.Abandon(q) end
  return false
end

-- ------------------------------------------------------------------------------------------------ showing
--- Open the menu at the cursor for q. True when a menu system drew it; false = caller does its old thing.
function Menu.Show(owner, q)
  local items = Menu.Items(q, Menu.Context())
  local title = q.title or "?"
  local MU = rawget(_G, "MenuUtil")
  if fn(MU, "CreateContextMenu") then
    local ok = pcall(MU.CreateContextMenu, owner, function(_, root)
      if root.CreateTitle then root:CreateTitle(title) end
      for _, it in ipairs(items) do root:CreateButton(it.text, function() Menu.Do(it.action, q) end) end
    end)
    if ok then Menu.path = "MenuUtil" count("shown") return true end
  end
  local list = { { text = title, isTitle = true, notCheckable = true } }
  for _, it in ipairs(items) do list[#list + 1] = { text = it.text, notCheckable = true, func = function() Menu.Do(it.action, q) end } end
  local easy = g("EasyMenu")
  if easy then
    if not Menu.dropdown then Menu.dropdown = CreateFrame("Frame", "HogHealsQuestMenu", UIParent, "UIDropDownMenuTemplate") end
    local ok = pcall(easy, list, Menu.dropdown, "cursor", 0, 0, "MENU")
    if ok then Menu.path = "EasyMenu" count("shown") return true end
  end
  local init, toggle, add = g("UIDropDownMenu_Initialize"), g("ToggleDropDownMenu"), g("UIDropDownMenu_AddButton")
  if init and toggle and add then
    if not Menu.dropdown then Menu.dropdown = CreateFrame("Frame", "HogHealsQuestMenu", UIParent, "UIDropDownMenuTemplate") end
    local ok = pcall(init, Menu.dropdown, function(_, level) for _, e in ipairs(list) do add(e, level or 1) end end, "MENU")
    if ok then
      pcall(toggle, 1, nil, Menu.dropdown, "cursor", 0, 0)
      Menu.path = "UIDropDownMenu" count("shown") return true
    end
  end
  Menu.path = "none"
  return false
end

function Menu.Lines()
  local parts = {}
  for k, v in pairs(Menu.seen) do parts[#parts + 1] = k .. "=" .. v end
  table.sort(parts)
  return { ("quest menu: via %s; %s"):format(Menu.path, #parts > 0 and table.concat(parts, " ") or "not used yet") }
end
