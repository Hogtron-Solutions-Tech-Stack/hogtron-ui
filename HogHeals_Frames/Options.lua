-- Frames options tab (AceConfig table). Every set() writes the profile and refreshes live frames.
HogHealsFrames = HogHealsFrames or {}
local HHF = HogHealsFrames
local HH = HogHeals

local INDICATOR_LABELS = {
  health = "Health bar", power = "Power bar", name = "Name", healPrediction = "Incoming heals",
  dispel = "Dispellable debuff (my class)", priorityDebuff = "Priority debuff slot", range = "Range fade",
  aggro = "Aggro border", raidIcon = "Raid target icon", statusIcons = "Status icons (ready/res/summon/leader)",
  missingBuffs = "Missing buff I can cast", myShield = "My shield + Weakened Soul", thresholds = "Health threshold ticks",
  aoeHealing = "AoE-heal scope highlight", requestGlow = "Dispel-request glow (/hh dispelme from others)",
  buffs = "Buffs on the cell (Fortitude-type buffs live here, not above heads)",
  debuffs = "Debuffs on the cell (DoTs, curses, poisons, bleeds - what is on them)",
}
local INDICATOR_ORDER = { "health", "power", "name", "healPrediction", "dispel", "priorityDebuff", "range", "aggro",
  "raidIcon", "statusIcons", "missingBuffs", "myShield", "buffs", "debuffs", "thresholds", "aoeHealing", "requestGlow" }

local function frames() return HH.db.profile.frames end
local function layout() return HHF.module:LayoutFor() end
local function refresh() HHF.module:Refresh() end
local function relayout() HHF.module:ApplyProfile(HHF.module.bucket) end

local function lsmValues(kind)
  local LSM = LibStub("LibSharedMedia-3.0", true)
  local out = {}
  if LSM then for _, n in ipairs(LSM:List(kind)) do out[n] = n end end
  return out
end

local function layoutGroup()
  local function L(key, name, min, max, step, order)
    return {
      type = "range", name = name, order = order, min = min, max = max, step = step,
      get = function() return layout()[key] end,
      set = function(_, v) layout()[key] = v; relayout() end,
    }
  end
  return {
    type = "group", name = "Layout", order = 1,
    args = {
      note = { type = "description", order = 0, name = function()
        local _, which = HHF.module.ResolveLayout(HHF.module.bucket or "solo")
        local label = (which == "party" and HH.db.profile.frames.soloSharesParty ~= false) and "solo & party" or tostring(which)
        return "Editing layout for group size: " .. label .. " (switches automatically)."
      end },
      soloSharesParty = {
        type = "toggle", name = "Solo uses the party layout", order = 0.5, width = "full",
        desc = "One size, direction and position whether you are alone or in a group. Untick to give solo its own layout.",
        get = function() return frames().soloSharesParty ~= false end,
        set = function(_, v) frames().soloSharesParty = v and true or false; relayout() end,
      },
      width = L("width", "Frame width", 40, 300, 1, 1),
      height = L("height", "Frame height", 12, 80, 1, 2),
      spacing = L("spacing", "Spacing", 0, 20, 1, 3),
      growth = {
        type = "select", name = "Units grow", order = 4, values = { DOWN = "Down", UP = "Up", RIGHT = "Right", LEFT = "Left", CENTER = "Centred (grow outward)" },
        get = function() return layout().growth end, set = function(_, v) layout().growth = v; relayout() end,
      },
      groupGrowth = {
        type = "select", name = "Groups grow", order = 5, values = { RIGHT = "Right", LEFT = "Left", DOWN = "Down", UP = "Up" },
        get = function() return layout().groupGrowth end, set = function(_, v) layout().groupGrowth = v; relayout() end,
      },
      groupsPerRow = L("groupsPerRow", "Groups per row", 1, 8, 1, 6),
      groupSpacing = L("groupSpacing", "Group spacing", 0, 40, 1, 7),
      showSolo = {
        type = "toggle", name = "Show me (+pet) when solo", order = 8,
        get = function() return layout().showSolo ~= false end, set = function(_, v) layout().showSolo = v; relayout() end,
      },
      scale = L("scale", "Scale", 0.5, 2, 0.05, 9),
      hideBlizzard = {
        type = "toggle", name = "Hide Blizzard party / raid frames", order = 9.5,
        desc = "While HogHeals frames are on, Blizzard's own party and raid-style frames are hidden. Turning this OFF needs a /reload to bring them back.",
        get = function() return HH.db.profile.frames.hideBlizzard ~= false end,
        set = function(_, v) HH.db.profile.frames.hideBlizzard = v and true or false; if v then HHF.Headers.HideBlizzard() else HH:Print("Blizzard frames come back after /reload.") end end,
      },
      lock = { type = "execute", name = function() return HH.db.profile.locked and "Unlock (drag anchor)" or "Lock" end, order = 10,
        func = function() HH:SetLocked(not HH.db.profile.locked) end },
      test = { type = "execute", name = "Test mode (10 units)", order = 11, func = function() HHF.TestMode.Start(10) end },
      testOff = { type = "execute", name = "Test mode off", order = 12, func = function() HHF.TestMode.Stop() end },
    },
  }
end

local function appearanceGroup()
  local ap = function() return frames().appearance end
  return {
    type = "group", name = "Appearance", order = 2,
    args = {
      font = { type = "select", name = "Font", order = 1, values = function() return lsmValues("font") end,
        get = function() return ap().font end, set = function(_, v) ap().font = v; refresh() end },
      fontSize = { type = "range", name = "Font size", order = 2, min = 6, max = 24, step = 1,
        get = function() return ap().fontSize end, set = function(_, v) ap().fontSize = v; refresh() end },
      fontOutline = { type = "select", name = "Outline", order = 3, values = { [""] = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick" },
        get = function() return ap().fontOutline end, set = function(_, v) ap().fontOutline = v; refresh() end },
      texture = { type = "select", name = "Bar texture", order = 4, values = function() return lsmValues("statusbar") end,
        get = function() return ap().texture end, set = function(_, v) ap().texture = v; refresh() end },
      healthMode = { type = "select", name = "Health colour", order = 5,
        values = { class = "Class colour", deficit = "Green → red by health", custom = "Custom colour" },
        get = function() return ap().healthMode end, set = function(_, v) ap().healthMode = v; refresh() end },
      healthColor = { type = "color", name = "Custom health colour", order = 6,
        get = function() local c = ap().healthColor return c[1], c[2], c[3] end,
        set = function(_, r, g, b) ap().healthColor = { r, g, b }; refresh() end },
      healthText = { type = "select", name = "Health text", order = 7,
        values = { percent = "Percent", deficit = "Missing (-1.2k)", none = "None" },
        get = function() return ap().healthText end, set = function(_, v) ap().healthText = v; refresh() end },
      powerHealerOnly = { type = "toggle", name = "Power bar: mana users only", order = 8,
        get = function() return ap().powerHealerOnly end, set = function(_, v) ap().powerHealerOnly = v; refresh() end },
      powerHeight = { type = "range", name = "Power bar height", order = 9, min = 1, max = 10, step = 1,
        get = function() return ap().powerHeight end, set = function(_, v) ap().powerHeight = v; refresh() end },
      nameLength = { type = "range", name = "Name length", order = 10, min = 0, max = 20, step = 1,
        get = function() return ap().nameLength end, set = function(_, v) ap().nameLength = v; refresh() end },
      textHead = { type = "header", name = "Text placement", order = 10.5 },
      namePosition = { type = "select", name = "Name: vertical", order = 10.6, values = { TOP = "Top", CENTER = "Centre", BOTTOM = "Bottom" },
        get = function() return ap().namePosition or "TOP" end, set = function(_, v) ap().namePosition = v; refresh() end },
      nameAlign = { type = "select", name = "Name: horizontal", order = 10.7, values = { LEFT = "Left", CENTER = "Centre", RIGHT = "Right" },
        get = function() return ap().nameAlign or "CENTER" end, set = function(_, v) ap().nameAlign = v; refresh() end },
      healthTextPosition = { type = "select", name = "Health text: vertical", order = 10.8, values = { TOP = "Top", CENTER = "Centre", BOTTOM = "Bottom" },
        get = function() return ap().healthTextPosition or "BOTTOM" end, set = function(_, v) ap().healthTextPosition = v; refresh() end },
      healthTextAlign = { type = "select", name = "Health text: horizontal", order = 10.9, values = { LEFT = "Left", CENTER = "Centre", RIGHT = "Right" },
        get = function() return ap().healthTextAlign or "CENTER" end, set = function(_, v) ap().healthTextAlign = v; refresh() end },
      outOfRangeAlpha = { type = "range", name = "Out-of-range alpha", order = 11, min = 0.1, max = 1, step = 0.05,
        get = function() return ap().outOfRangeAlpha end, set = function(_, v) ap().outOfRangeAlpha = v; refresh() end },
      backgroundAlpha = { type = "range", name = "Background alpha", order = 12, min = 0, max = 1, step = 0.05,
        get = function() return ap().backgroundAlpha end, set = function(_, v) ap().backgroundAlpha = v; refresh() end },
      fadeHeader = { type = "header", name = "Health-threshold fade", order = 20 },
      fadeEnabled = { type = "toggle", name = "Fade healthy frames", order = 21, desc = "Fade frames above a health % so damaged players pop.",
        get = function() return frames().healthFade.enabled end, set = function(_, v) frames().healthFade.enabled = v; refresh() end },
      fadeAbove = { type = "range", name = "Fade above %", order = 22, min = 50, max = 100, step = 1,
        get = function() return frames().healthFade.above end, set = function(_, v) frames().healthFade.above = v; refresh() end },
      fadeAlpha = { type = "range", name = "Faded alpha", order = 23, min = 0.1, max = 1, step = 0.05,
        get = function() return frames().healthFade.alpha end, set = function(_, v) frames().healthFade.alpha = v; refresh() end },
    },
  }
end

local function indicatorsGroup()
  local args = {}
  for i, key in ipairs(INDICATOR_ORDER) do
    args[key] = {
      type = "toggle", name = INDICATOR_LABELS[key] or key, order = i, width = "full",
      get = function() return frames().indicators[key] ~= false end,
      set = function(_, v) frames().indicators[key] = v and true or false; refresh() end,
    }
  end
  -- the two aura rows share one set of controls (Elements/AuraRow.lua)
  local ANCHORS = {}
  for _, a in ipairs(HHF.AuraRow and HHF.AuraRow.ANCHORS or { "BOTTOMLEFT" }) do ANCHORS[a] = a end
  local function rowControls(key, base, title, filters, filterDefault)
    local function row() frames()[key] = frames()[key] or {} return frames()[key] end
    args[key .. "Header"] = { type = "header", name = title, order = base }
    args[key .. "Filter"] = { type = "select", name = "Which", order = base + 1, values = filters,
      get = function() return row().filter or filterDefault end, set = function(_, v) row().filter = v; refresh() end }
    args[key .. "Size"] = { type = "range", name = "Icon size", order = base + 2, min = 8, max = 24, step = 1,
      get = function() return row().size or 12 end, set = function(_, v) row().size = v; refresh() end }
    args[key .. "Max"] = { type = "range", name = "Most icons", order = base + 3, min = 1, max = 8, step = 1,
      get = function() return row().max or 4 end, set = function(_, v) row().max = v; refresh() end }
    args[key .. "Anchor"] = { type = "select", name = "Corner / side of the cell", order = base + 4, values = ANCHORS,
      get = function() return row().anchor or "BOTTOMLEFT" end, set = function(_, v) row().anchor = v; refresh() end }
    args[key .. "X"] = { type = "range", name = "Nudge across", order = base + 5, min = -40, max = 40, step = 1,
      get = function() return row().x or 0 end, set = function(_, v) row().x = v; refresh() end }
    args[key .. "Y"] = { type = "range", name = "Nudge up / down", order = base + 6, min = -40, max = 40, step = 1,
      get = function() return row().y or row().offsetY or 0 end, set = function(_, v) row().y = v; refresh() end }
    args[key .. "Grow"] = { type = "select", name = "Grow", order = base + 7, values = { AUTO = "From the side it sits on", RIGHT = "Rightwards", LEFT = "Leftwards" },
      get = function() return row().grow or "AUTO" end, set = function(_, v) row().grow = (v ~= "AUTO") and v or nil; refresh() end }
    args[key .. "Numbers"] = { type = "toggle", name = "Countdown numbers on the swipe (icon size 14+)", order = base + 8, width = "full",
      get = function() return row().numbers == true end, set = function(_, v) row().numbers = v and true or false; refresh() end }
  end
  rowControls("buffs", 40, "Buffs on the cell", { mine = "Mine only", all = "Mine first, then everyone's" }, "all")
  rowControls("debuffs", 45, "Debuffs on the cell (what is on them)",
    { all = "Everything on them", dispellable = "Only what I can dispel", mine = "Only mine (my DoTs)" }, "all")
  args.dispelHeader = { type = "header", name = "Dispel display", order = 50 }
  args.dispelStyle = { type = "select", name = "Style", order = 51,
    values = { icon = "Icon", color = "Health bar colour", border = "Border" },
    get = function() return frames().dispel.style end, set = function(_, v) frames().dispel.style = v; refresh() end }
  args.priorityDebuffs = { type = "input", name = "Priority debuffs (comma separated)", order = 52, width = "full",
    get = function() return table.concat(frames().dispel.priorityDebuffs or {}, ", ") end,
    set = function(_, v) local t = {} for s in v:gmatch("[^,]+") do s = strtrim(s) if s ~= "" then t[#t + 1] = s end end frames().dispel.priorityDebuffs = t; refresh() end }
  args.thresholdsHeader = { type = "header", name = "Health thresholds", order = 60 }
  args.thresholdsList = { type = "input", name = "Tick marks at % (comma separated)", order = 61,
    get = function() return table.concat(frames().thresholds or {}, ", ") end,
    set = function(_, v) local t = {} for s in v:gmatch("%d+") do t[#t + 1] = tonumber(s) end table.sort(t) frames().thresholds = t; refresh() end }
  args.healHeader = { type = "header", name = "Incoming heals", order = 70 }
  args.healShow = { type = "select", name = "Show", order = 71, values = { mine = "Mine only", others = "Others only", all = "All" },
    get = function() return frames().healPrediction.show end, set = function(_, v) frames().healPrediction.show = v; refresh() end }
  args.healOverheal = { type = "toggle", name = "Mark overheal", order = 72,
    get = function() return frames().healPrediction.overheal end, set = function(_, v) frames().healPrediction.overheal = v; refresh() end }
  return { type = "group", name = "Indicators", order = 3, args = args }
end

local newBinding = { key = "", mod = "", type = "spell", value = "" }
local function bindingsGroup()
  local args = {
    intro = { type = "description", order = 0, name = function()
      if HHF.ClickCast.controlledBy == "Clique" then return "|cffF5A623Clique is loaded and controls click/hover bindings.|r" end
      return "Hover a frame and press a bound key, or click with a bound mouse button. Keys: 1-9, Q, F, BUTTON1..5 (mouse) + SHIFT/CTRL/ALT."
    end },
    list = { type = "description", order = 1, name = function()
      local lines = HHF.ClickCast.Describe()
      return #lines > 0 and ("|cff21D4E0Current bindings:|r\n" .. table.concat(lines, "\n")) or "No bindings."
    end },
    header = { type = "header", name = "Add binding", order = 10 },
    key = { type = "input", name = "Key (e.g. 3, Q, BUTTON2)", order = 11, get = function() return newBinding.key end, set = function(_, v) newBinding.key = strtrim(v):upper() end },
    mod = { type = "select", name = "Modifier", order = 12, values = { [""] = "None", SHIFT = "Shift", CTRL = "Ctrl", ALT = "Alt" },
      get = function() return newBinding.mod end, set = function(_, v) newBinding.mod = v end },
    kind = { type = "select", name = "Type", order = 13, values = { spell = "Spell", macro = "Macro text", item = "Item" },
      get = function() return newBinding.type end, set = function(_, v) newBinding.type = v end },
    value = { type = "input", name = "Spell / macro / item", order = 14, width = "full", get = function() return newBinding.value end, set = function(_, v) newBinding.value = strtrim(v) end },
    add = { type = "execute", name = "Add / replace", order = 15, func = function()
      if newBinding.key == "" or newBinding.value == "" then return end
      local list = {}
      for _, b in ipairs(HHF.ClickCast.bindings) do
        if not (b.key == newBinding.key and (b.mod or "") == newBinding.mod) then list[#list + 1] = b end
      end
      list[#list + 1] = { key = newBinding.key, mod = newBinding.mod, type = newBinding.type, value = newBinding.value }
      HHF.ClickCast.SetBindings(list)
      newBinding.key, newBinding.value = "", ""
    end },
    remove = { type = "input", name = "Remove binding by key (e.g. SHIFT-1)", order = 16, get = function() return "" end, set = function(_, v)
      v = strtrim(v):upper()
      local list = {}
      for _, b in ipairs(HHF.ClickCast.bindings) do
        local ks = (b.mod ~= "" and (b.mod .. "-") or "") .. b.key
        if ks ~= v then list[#list + 1] = b end
      end
      HHF.ClickCast.SetBindings(list)
    end },
    reset = { type = "execute", name = "Reset to class defaults", order = 17, func = function()
      local _, class = UnitClass("player")
      HHF.ClickCast.SetBindings(HHF.ClickCast.Defaults(class))
    end },
    fallbackHeader = { type = "header", name = "Macro fallback chain (for /hh macro <spell>)", order = 20 },
    fbMouseover = { type = "toggle", name = "Mouseover", order = 21, get = function() return frames().fallback.mouseover end, set = function(_, v) frames().fallback.mouseover = v end },
    fbFocus = { type = "toggle", name = "Focus", order = 22, get = function() return frames().fallback.focus end, set = function(_, v) frames().fallback.focus = v end },
    fbTarget = { type = "toggle", name = "Target", order = 23, get = function() return frames().fallback.target end, set = function(_, v) frames().fallback.target = v end },
    fbPlayer = { type = "toggle", name = "Self", order = 24, get = function() return frames().fallback.player end, set = function(_, v) frames().fallback.player = v end },
    tooltip = { type = "toggle", name = "Show bindings in tooltip on hover", order = 30,
      get = function() return frames().showBindingTooltip end, set = function(_, v) frames().showBindingTooltip = v end },
    combatHead = { type = "header", name = "Combat-safe bindings", order = 40 },
    combatInfo = { type = "description", order = 41, name = "Hover mode sets keys when your mouse enters a frame; restricted clients (WoW: Forever) block that during combat. Combat-safe mode binds each key once, out of combat, and casts on the hovered frame, then target, then you. The key is then taken everywhere, not only over frames." },
    bindingMode = { type = "select", name = "Mode", order = 42, values = { hover = "Hover (keys only over frames)", global = "Combat-safe (keys always on)" },
      get = function() return frames().bindingMode or "hover" end,
      set = function(_, v) frames().bindingMode = v; HHF.ClickCast.ApplyGlobal() end },
    bindingForce = { type = "toggle", name = "Take over keys that already have a binding", order = 43,
      desc = "Combat-safe mode skips keys bound to something else (e.g. action bar slots) and tells you which. Tick to use them anyway.",
      get = function() return frames().bindingForce == true end,
      set = function(_, v) frames().bindingForce = v and true or false; HHF.ClickCast.ApplyGlobal() end },
  }
  return { type = "group", name = "Bindings", order = 4, args = args }
end

local function profilesGroup()
  local AceDBOptions = LibStub("AceDBOptions-3.0", true)
  local t = AceDBOptions and AceDBOptions:GetOptionsTable(HH.db) or { type = "group", name = "Profiles", args = {} }
  t.order = 5
  t.name = "Profiles"
  t.args.exportHeader = { type = "header", name = "Share", order = 90 }
  t.args.export = { type = "input", name = "Export string", order = 91, width = "full", multiline = 4,
    get = function() return HHF.ExportProfile and HHF.ExportProfile() or "" end, set = function() end }
  t.args.import = { type = "input", name = "Import string", order = 92, width = "full", multiline = 4,
    get = function() return "" end, set = function(_, v) if HHF.ImportProfile then HHF.ImportProfile(v) end end }
  return t
end

function HHF.module:GetOptions()
  return {
    type = "group", name = "Frames", childGroups = "tab",
    args = {
      layout = layoutGroup(),
      appearance = appearanceGroup(),
      indicators = indicatorsGroup(),
      bindings = bindingsGroup(),
      profiles = profilesGroup(),
    },
  }
end

-- Profile export/import (LibDeflate + AceSerializer), so Sean can hand a profile to guildmates.
function HHF.ExportProfile()
  local Ser = LibStub("AceSerializer-3.0", true)
  local Deflate = LibStub("LibDeflate", true)
  if not Ser then return "" end
  local s = Ser:Serialize(HH.db.profile.frames)
  if Deflate then
    local c = Deflate:CompressDeflate(s)
    return "HH1:" .. Deflate:EncodeForPrint(c)
  end
  return "HH0:" .. s
end

function HHF.ImportProfile(str)
  str = strtrim(str or "")
  local Ser = LibStub("AceSerializer-3.0", true)
  local Deflate = LibStub("LibDeflate", true)
  local payload
  if str:sub(1, 4) == "HH1:" and Deflate then
    local d = Deflate:DecodeForPrint(str:sub(5))
    payload = d and Deflate:DecompressDeflate(d)
  elseif str:sub(1, 4) == "HH0:" then
    payload = str:sub(5)
  end
  if not payload or not Ser then HH:Print("Import failed: bad string.") return false end
  local ok, data = Ser:Deserialize(payload)
  if not ok or type(data) ~= "table" then HH:Print("Import failed: could not read profile.") return false end
  for k, v in pairs(data) do HH.db.profile.frames[k] = v end
  HHF.module:OnProfileChanged()
  HH:Print("Profile imported.")
  return true
end

HH:RegisterSlash("macro", function(rest)
  rest = strtrim(rest or "")
  if rest == "" then HH:Print("Usage: /hh macro <spell name>") return end
  HH:Print(HHF.ClickCast.Macro(rest, frames().fallback))
end, "macro <spell> — print a fallback-chain macro")
