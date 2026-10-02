-- Skin options: Action bars / Bags / Menu & bag bar / Tooltips / Info bar. Every set() writes profile.skin and re-applies.
HogHealsSkin = HogHealsSkin or {}
local HHS = HogHealsSkin
local HH = HogHeals

local Options = {}
HHS.Options = Options

local function root() return HH.db.profile.skin end
local function sub(key) return function() return HH.db.profile.skin[key] end end
local function apply() HHS.Skin.ApplyAll("options") end
local function infobar() HHS.InfoBar.Refresh() end

local function toggle(tbl, key, name, order, after, desc)
  return { type = "toggle", name = name, desc = desc, order = order,
    get = function() return tbl()[key] ~= false end,
    set = function(_, v) tbl()[key] = v and true or false; (after or apply)() end }
end
local function range(tbl, key, name, order, min, max, step, after)
  return { type = "range", name = name, order = order, min = min, max = max, step = step,
    get = function() return tbl()[key] end,
    set = function(_, v) tbl()[key] = v; (after or apply)() end }
end

local function slotValues()
  local v = {}
  for k, p in pairs(HHS.InfoBar.providers) do v[k] = p.label end
  return v
end

local function slotSelect(i)
  return { type = "select", name = "Slot " .. i, order = 20 + i, values = slotValues,
    get = function() return root().infoBar.slots[i] or "none" end,
    set = function(_, val) root().infoBar.slots[i] = val; infobar() end }
end

function Options.Build()
  return {
    type = "group", name = "Skin", order = 39,
    args = {
      bars = { type = "group", name = "Action bars", order = 1, args = {
        about = { type = "description", order = 0, name = "Blizzard's action bars with the art (gryphons, end caps) removed and every button flattened: dark backdrop, 1 px outline, trimmed icon. The buttons stay Blizzard's, so bindings, paging and Edit Mode all keep working. Turning a piece off needs a /reload to bring Blizzard's art back." },
        enabled = toggle(sub("actionBars"), "enabled", "Skin the action bars", 1),
        hideArt = toggle(sub("actionBars"), "hideArt", "Hide the bar art (gryphons, end caps, page arrows)", 2),
        hotkeySize = range(sub("actionBars"), "hotkeySize", "Keybind text size", 3, 7, 16, 1),
        hideNames = toggle(sub("actionBars"), "hideNames", "Hide macro names on buttons", 4),
        cooldownNumbers = toggle(sub("actionBars"), "cooldownNumbers", "Cooldown numbers on buttons (Blizzard's countdown)", 5),
      } },
      bags = { type = "group", name = "Bags", order = 2, args = {
        about = { type = "description", order = 0, name = "Blizzard's bags in the HogUI panel: art removed, item slots flattened, outline coloured by item quality." },
        enabled = toggle(sub("bags"), "enabled", "Skin the bags", 1),
        qualityMin = range(sub("bags"), "qualityMin", "Colour the outline from this quality up (2 = uncommon)", 2, 0, 5, 1),
        fontSize = range(sub("bags"), "fontSize", "Text size (title, counts)", 3, 8, 20, 1),
        backgroundAlpha = range(sub("bags"), "backgroundAlpha", "Background opacity", 4, 0, 1, 0.05),
      } },
      micro = { type = "group", name = "Menu & bag bar", order = 3, args = {
        about = { type = "description", order = 0, name = "The bottom menu buttons and the bag slots: Blizzard's backdrop art removed, one HogUI strip behind each group, bag slots flattened." },
        microEnabled = toggle(sub("micro"), "enabled", "Skin the menu buttons", 1),
        strip = toggle(sub("micro"), "strip", "HogUI letter buttons instead of Blizzard's art (C S T A Q G L J E ? M); /hh unlock to drag the bar", 1.5),
        size = range(sub("micro"), "size", "Letter button size", 1.7, 14, 36, 1),
        scale = range(sub("micro"), "scale", "Menu buttons scale", 2, 0.5, 1.5, 0.05),
        resetPos = { type = "execute", name = "Reset menu bar position", order = 2.5, func = function() local m = sub("micro")() m.point, m.x, m.y = nil, nil, nil; HHS.Skin.ApplyAll("options") end },
        bagBarEnabled = toggle(sub("bagBar"), "enabled", "Skin the bag slots", 3),
      } },
      tooltips = { type = "group", name = "Tooltips", order = 4, args = {
        about = { type = "description", order = 0, name = "Tooltips on an ink panel with a 1 px outline, flat health bar." },
        enabled = toggle(sub("tooltips"), "enabled", "Skin tooltips", 1),
        alpha = range(sub("tooltips"), "alpha", "Background opacity", 2, 0.3, 1, 0.05),
        fontSize = { type = "range", name = "Text size (0 = Blizzard's)", order = 3, min = 0, max = 20, step = 1,
          get = function() return root().tooltips.fontSize or 0 end,
          set = function(_, v) root().tooltips.fontSize = v > 0 and v or nil; apply() end },
        anchorCursor = toggle(sub("tooltips"), "anchorCursor", "Anchor tooltips to the cursor", 4),
      } },
      extras = { type = "group", name = "Buffs & XP bar", order = 4.5, args = {
        about = { type = "description", order = 0, name = "Your buff / debuff icons (top right) flattened with the HogUI outline, and the experience / reputation bar made flat." },
        buffs = toggle(sub("extras"), "buffs", "Skin my buff and debuff icons", 1),
        durationSize = range(sub("extras"), "durationSize", "Duration / count text size", 2, 7, 16, 1),
        xpBar = toggle(sub("extras"), "xpBar", "Flat experience / reputation bar", 3),
      } },
      panels = { type = "group", name = "Windows", order = 4.7, args = {
        about = { type = "description", order = 0, name = "Blizzard's windows (character, spellbook, escape menu, vendor, mail, trade, bank, ...) on the HogUI panel: art and portrait off, outline, flat close button. Parchment windows (gossip, quest text, quest log, books, opened mail) get their text recoloured cream / amber and the parchment stripped. Untick a window to leave it alone (needs a /reload to come back)." },
        enabled = toggle(sub("panels"), "enabled", "Skin Blizzard's windows", 1),
        alpha = range(sub("panels"), "alpha", "Background opacity", 2, 0.3, 1, 0.05),
        titleSize = range(sub("panels"), "titleSize", "Title text size", 3, 9, 20, 1),
        list = { type = "group", inline = true, name = "Windows", order = 4, args = (function()
          local a = {}
          for i, n in ipairs(HHS.Panels.NAMES) do
            a[n] = { type = "toggle", name = n:gsub("Frame$", ""), order = i,
              get = function() return not (root().panels.skip and root().panels.skip[n]) end,
              set = function(_, v) root().panels.skip = root().panels.skip or {} root().panels.skip[n] = (not v) or nil; apply() end }
          end
          return a
        end)() },
      } },
      auto = { type = "group", name = "Vendor", order = 4.8, args = {
        about = { type = "description", order = 0, name = "At a merchant: sell grey junk and repair automatically, with one chat line saying what happened. Capped at 60 items per visit." },
        sellJunk = toggle(sub("auto"), "sellJunk", "Sell grey junk", 1),
        repair = toggle(sub("auto"), "repair", "Repair (own gold)", 2),
        guildRepair = { type = "toggle", name = "Use guild bank repair when allowed", order = 3,
          get = function() return root().auto.guildRepair == true end,
          set = function(_, v) root().auto.guildRepair = v and true or false end },
      } },
      infobar = { type = "group", name = "Info bar", order = 5, args = {
        about = { type = "description", order = 0, name = "A slim strip of live readouts: gold, durability, bag space, fps, latency, clock, coordinates, friends, guild, experience. Click a readout to open its frame. Drag it when frames are unlocked (/hh unlock)." },
        enabled = toggle(sub("infoBar"), "enabled", "Show the info bar", 1, infobar),
        width = range(sub("infoBar"), "width", "Width", 2, 200, 2000, 10, infobar),
        height = range(sub("infoBar"), "height", "Height", 3, 12, 40, 1, infobar),
        fontSize = range(sub("infoBar"), "fontSize", "Text size", 4, 7, 20, 1, infobar),
        backgroundAlpha = range(sub("infoBar"), "backgroundAlpha", "Background opacity", 5, 0, 1, 0.05, infobar),
        refresh = range(sub("infoBar"), "refresh", "Refresh (seconds)", 6, 0.5, 10, 0.5, infobar),
        time24 = toggle(sub("infoBar"), "time24", "24-hour clock", 7, infobar),
        serverTime = toggle(sub("infoBar"), "serverTime", "Server time instead of local", 8, infobar),
        slot1 = slotSelect(1), slot2 = slotSelect(2), slot3 = slotSelect(3), slot4 = slotSelect(4),
        slot5 = slotSelect(5), slot6 = slotSelect(6), slot7 = slotSelect(7), slot8 = slotSelect(8),
      } },
    },
  }
end
