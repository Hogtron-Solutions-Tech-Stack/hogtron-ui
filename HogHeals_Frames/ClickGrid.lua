-- Click-cast grid: mouse button x modifier -> spell, saved PER CHARACTER (HogHealsFramesCharDB).
--
-- A second input layer next to the hover-bind engine (ClickCast.lua), which stays untouched and keeps owning keyboard
-- keys. This layer owns mouse clicks on the unit frames. Both fire independently. Where a Bindings-tab entry uses the
-- same mouse button + modifier as a grid slot, the grid wins (it is applied after the engine, and again after every
-- engine SetBindings).
--
-- UX pattern after HealKit (OzwaldTinker, CurseForge; All Rights Reserved). Patterns only, no code taken; see
-- docs/superpowers/research/2026-10-15-healkit-binding-ui.md.
--
-- Secure path: plain SetAttribute on the SecureUnitButtons, out of combat only (HH:RunOutOfCombat). Each slot is a
-- "macro" type with a /cast [@mouseover...] macrotext. NO restricted snippets (SecureHandlerExecute & co): the
-- WoW: Forever client cannot compile them (RestrictedExecution.lua:79, loadstring_untainted == nil; see Headers.lua).
-- Attributes written out of combat are read by Blizzard's secure click handler in combat, so clicks work in combat
-- and nothing is tainted.
HogHealsFrames = HogHealsFrames or {}
local HHF = HogHealsFrames
local HH = HogHeals

local Grid = {}
HHF.ClickGrid = Grid
HHF.ClickGridDefaults = HHF.ClickGridDefaults or {}

Grid.SCHEMA = 1
Grid.BUTTONS = {
  { key = "LEFT", n = 1, label = "Left" },
  { key = "RIGHT", n = 2, label = "Right" },
  { key = "MIDDLE", n = 3, label = "Middle" },
  { key = "BUTTON4", n = 4, label = "Button 4" },
  { key = "BUTTON5", n = 5, label = "Button 5" },
}
Grid.MODS = {
  { key = "NONE", prefix = "", label = "None" },
  { key = "SHIFT", prefix = "shift-", label = "Shift" },
  { key = "CTRL", prefix = "ctrl-", label = "Ctrl" },
  { key = "ALT", prefix = "alt-", label = "Alt" },
  { key = "META", prefix = "meta-", label = "Meta" },     -- "Cmd" on a Mac client, see ModLabel
}
--- Resurrection spell per class. Druid's Rebirth works in combat, but the macro keeps the nocombat gate anyway:
-- a misclick on a dead tank mid-pull must not burn the battle-rez cooldown.
Grid.REZ = { PRIEST = "Resurrection", PALADIN = "Redemption", DRUID = "Rebirth", SHAMAN = "Ancestral Spirit" }

Grid.TOAST_HEALER = "HogHeals suggested a healer click-cast layout. Open /hh click-cast to edit."
Grid.TOAST_OTHER = "HogHeals: open /hh click-cast to set up click-casting."
Grid.CLIQUE_TEXT = "Clique detected — HogHeals click-cast disabled"

Grid.ui = { selected = nil, pickerFor = nil, rankMenuFor = nil, pickerOffset = 0 }

local BY_BUTTON, BY_MOD = {}, {}
for _, b in ipairs(Grid.BUTTONS) do BY_BUTTON[b.key] = b end
for _, m in ipairs(Grid.MODS) do BY_MOD[m.key] = m end

function Grid.SlotKey(button, mod) return tostring(button) .. ":" .. tostring(mod or "NONE") end
function Grid.SplitKey(key)
  local b, m = tostring(key):match("^([^:]+):(.+)$")
  return b, m
end

function Grid.ModLabel(mod)
  if mod == "META" then return (type(IsMacClient) == "function" and IsMacClient()) and "Cmd" or "Meta" end
  return BY_MOD[mod] and BY_MOD[mod].label or tostring(mod)
end

--- "Shift + Left", "Middle".
function Grid.SlotLabel(key)
  local b, m = Grid.SplitKey(key)
  local bl = BY_BUTTON[b] and BY_BUTTON[b].label or tostring(b)
  if not m or m == "NONE" then return bl end
  return Grid.ModLabel(m) .. " + " .. bl
end

local function isSecret(v) return HHF.Compat and HHF.Compat.IsSecret and HHF.Compat.IsSecret(v) or false end

local function copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = copy(v) end
  return o
end
Grid.Copy = copy

-- ------------------------------------------------------------------------------------------------ spellbook
local function parseRank(sub)
  if type(sub) ~= "string" or isSecret(sub) then return nil end
  local n = sub:match("(%d+)")
  return n and tonumber(n) or nil
end
Grid.ParseRank = parseRank

local function isFuture(kind)
  if kind == "FUTURESPELL" or kind == "FLYOUT" or kind == "PETACTION" then return true end
  local E = Enum and Enum.SpellBookItemType
  return E ~= nil and kind ~= nil and (kind == E.FutureSpell or kind == E.Flyout or kind == E.PetAction)
end

-- Legacy API (Classic Era / TBC Anniversary): GetSpellBookItemName / GetSpellBookItemInfo / IsHelpfulSpell by index.
local function legacyEntry(i, book)
  local name, sub = GetSpellBookItemName(i, book)
  if not name then return nil end
  local e = { index = i, name = name, rank = parseRank(sub) }
  if type(GetSpellBookItemInfo) == "function" then
    local kind, id = GetSpellBookItemInfo(i, book)
    if type(kind) == "table" then e.kind, e.spellID = kind.itemType, kind.spellID or kind.actionID
    else e.kind, e.spellID = kind, tonumber(id) end
  end
  if type(GetSpellTexture) == "function" then e.icon = GetSpellTexture(i, book) end
  if type(IsPassiveSpell) == "function" then e.passive = IsPassiveSpell(i, book) and true or false end
  if type(IsHelpfulSpell) == "function" then e.helpful = IsHelpfulSpell(i, book) and true or false end
  return e
end

-- Modern API (WoW: Forever may ship it; the globals above were removed there): C_SpellBook.* by index + bank.
local function modernEntry(i, bank)
  local SB = C_SpellBook
  local info = SB.GetSpellBookItemInfo and SB.GetSpellBookItemInfo(i, bank)
  local name, sub
  if type(info) == "table" then name, sub = info.name, info.subName end
  if not name and SB.GetSpellBookItemName then name, sub = SB.GetSpellBookItemName(i, bank) end
  if not name then return nil end
  info = type(info) == "table" and info or {}
  local e = { index = i, name = name, rank = parseRank(sub), kind = info.itemType, spellID = info.spellID or info.actionID,
    icon = info.iconID, passive = info.isPassive and true or false }
  if e.spellID and C_Spell and type(C_Spell.IsSpellHelpful) == "function" then e.helpful = C_Spell.IsSpellHelpful(e.spellID) and true or false end
  return e
end

local function castTimeOf(spellID)
  if not spellID then return nil end
  if type(GetSpellInfo) == "function" then
    local ok, _, _, _, ct = pcall(GetSpellInfo, spellID)
    if ok and type(ct) == "number" and not isSecret(ct) then return ct end
  end
  if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
    local ok, t = pcall(C_Spell.GetSpellInfo, spellID)
    if ok and type(t) == "table" and type(t.castTime) == "number" and not isSecret(t.castTime) then return t.castTime end
  end
  return nil
end

--- Read the live spellbook. Returns { list = {spell...} sorted by name, byName = { [name] = spell } } where
-- spell = { name, icon, ranks = {ascending}, ids = {[rank]=spellID}, helpful, passive, castTime }.
-- Nothing is hardcoded: what the character has learned is what the picker offers.
function Grid.ScanSpellbook()
  local entry, book
  if type(GetSpellBookItemName) == "function" then
    entry, book = legacyEntry, BOOKTYPE_SPELL or "spell"
  elseif type(C_SpellBook) == "table" and (C_SpellBook.GetSpellBookItemInfo or C_SpellBook.GetSpellBookItemName) then
    entry, book = modernEntry, (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
  end
  local byName, list = {}, {}
  if entry then
    for i = 1, 1024 do
      local ok, e = pcall(entry, i, book)
      if not ok or not e then break end
      if type(e.name) == "string" and not isSecret(e.name) and not isFuture(e.kind) then
        local s = byName[e.name]
        if not s then
          s = { name = e.name, icon = e.icon, ranks = {}, ids = {}, helpful = e.helpful, passive = e.passive }
          byName[e.name] = s
          list[#list + 1] = s
        end
        if e.rank and not s.ids[e.rank] then s.ranks[#s.ranks + 1] = e.rank end
        local r = e.rank or 0
        if e.spellID then s.ids[r] = e.spellID end
        if (e.rank or 0) >= (s.topRank or -1) then
          s.topRank, s.topID = e.rank or 0, e.spellID or s.topID
          s.icon = e.icon or s.icon
        end
        if e.helpful ~= nil then s.helpful = e.helpful end
        if e.passive then s.passive = true end
      end
    end
  end
  for _, s in ipairs(list) do
    table.sort(s.ranks)
    s.castTime = castTimeOf(s.topID)
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  Grid.book = { list = list, byName = byName }
  return Grid.book
end

function Grid.Book() return Grid.book or Grid.ScanSpellbook() end

local function isRezName(name)
  for _, r in pairs(Grid.REZ) do if r == name then return true end end
  return false
end

--- Healing + support spells for the picker: helpful (the client says so) and not passive. A client without a
-- helpful/harmful API lists every active spell rather than hiding them.
function Grid.PickerEntries(book)
  book = book or Grid.Book()
  local out = {}
  for _, s in ipairs(book.list) do
    if s.helpful ~= false and not s.passive then
      local n = #s.ranks
      out[#out + 1] = { name = s.name, icon = s.icon, ranks = copy(s.ranks),
        rankText = n > 1 and ("Rank " .. s.ranks[1] .. "-" .. s.ranks[n]) or (n == 1 and ("Rank " .. s.ranks[1]) or "") }
    end
  end
  return out
end

--- A direct heal: helpful with a cast time, and not itself a resurrection. Decides the "Resurrect if dead" default.
function Grid.IsDirectHeal(name, book)
  book = book or Grid.Book()
  local s = book.byName[name]
  if not s or s.helpful == false or isRezName(name) then return false end
  return (s.castTime or 0) > 0
end

--- The class rez spell if this character knows it, else nil (rez clause then omitted).
function Grid.RezSpell(class, book)
  local r = Grid.REZ[class or Grid.class or ""]
  if not r then return nil end
  book = book or Grid.Book()
  return book.byName[r] and r or nil
end

-- ------------------------------------------------------------------------------------------------ resolution
--- slot = { spell = "Flash Heal" | alts = {...}, rank = "highest" | n, rez = bool }
-- -> { name, known, rank, highest, cast, icon, missingRank }
function Grid.Resolve(slot, book)
  if type(slot) ~= "table" then return nil end
  book = book or Grid.Book()
  local names = (type(slot.alts) == "table" and #slot.alts > 0) and slot.alts or { slot.spell }
  local s
  for _, n in ipairs(names) do
    s = book.byName[n]
    if s then break end
  end
  if not s then return { name = slot.spell or names[1], known = false } end
  local top = s.ranks[#s.ranks]
  if slot.rank == nil or slot.rank == "highest" then
    -- Bare name: the client casts the highest rank it knows, so a rank learned mid-session is used at once.
    return { name = s.name, known = true, rank = top, highest = true, cast = s.name, icon = s.icon }
  end
  local want = tonumber(slot.rank)
  for _, r in ipairs(s.ranks) do
    if r == want then return { name = s.name, known = true, rank = r, highest = false, cast = s.name .. "(Rank " .. r .. ")", icon = s.icon } end
  end
  return { name = s.name, known = false, rank = want, missingRank = true, icon = s.icon }
end

--- Secure macro for one slot.
function Grid.MacroFor(cast, rez)
  if rez then return ("/cast [@mouseover,dead,nocombat] %s; [@mouseover,help,nodead] %s"):format(rez, cast) end
  return "/cast [@mouseover,help,nodead] " .. cast
end

--- Macro text a slot produces right now, or nil when it is empty / not castable.
function Grid.SlotMacro(slot, class, book)
  local r = Grid.Resolve(slot, book)
  if not r or not r.known then return nil end
  local rez = slot.rez and Grid.RezSpell(class, book) or nil
  return Grid.MacroFor(r.cast, rez)
end

--- Every attribute the grid wants on a unit button.
function Grid.AttributesFor(slots, class, book)
  local attrs = {}
  book = book or Grid.Book()
  for _, b in ipairs(Grid.BUTTONS) do
    for _, m in ipairs(Grid.MODS) do
      local slot = slots and slots[Grid.SlotKey(b.key, m.key)]
      local macro = slot and Grid.SlotMacro(slot, class, book)
      if macro then
        attrs[m.prefix .. "type" .. b.n] = "macro"
        attrs[m.prefix .. "macrotext" .. b.n] = macro
      end
    end
  end
  return attrs
end

-- ------------------------------------------------------------------------------------------------ defaults + storage
--- Default slots for a class, from defaults/clickcast/<class>.lua. Spell names; rank = highest unless the file pins one.
function Grid.DefaultSlots(class)
  local list = HHF.ClickGridDefaults[class or ""]
  local slots = {}
  for _, d in ipairs(list or {}) do
    local slot = { rank = tonumber(d.rank) or "highest", rez = d.rez and true or false }
    if type(d.spell) == "table" then slot.spell, slot.alts = d.spell[1], copy(d.spell) else slot.spell = d.spell end
    slots[Grid.SlotKey(d.button, d.mod or "NONE")] = slot
  end
  return slots
end

function Grid.CliqueLoaded()
  return ((C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Clique"))
    or (IsAddOnLoaded and IsAddOnLoaded("Clique")) or _G.Clique ~= nil) and true or false
end

local function charMirror()
  local db = HH.db
  local ok, c = pcall(function() return db and db.char end)
  return ok and type(c) == "table" and c or nil
end

--- Copy the per-character table into HogHealsDB.char as well. The client has handed us an EMPTY SavedVariables
-- table before (Forever beta, 2026-09-18); with two copies in two files a lost one is restored, not re-seeded.
function Grid.Mirror()
  local c = charMirror()
  if c and Grid.db then c.clickGrid = copy(Grid.db) end
end

local function save()
  if Grid.db then Grid.db.slots = Grid.slots end
  Grid.Mirror()
end

local toastFrame
function Grid.Toast(msg)
  Grid.lastToast = msg
  HH:Print(msg)
  if not CreateFrame or not UIParent then return end
  if not toastFrame then
    toastFrame = CreateFrame("Frame", "HogHealsClickCastToast", UIParent)
    toastFrame:SetSize(520, 26)
    toastFrame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    toastFrame:SetFrameStrata("HIGH")
    local bg = toastFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(toastFrame)
    bg:SetColorTexture(0.07, 0.07, 0.09, 0.9)
    toastFrame.text = toastFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    toastFrame.text:SetPoint("CENTER", toastFrame, "CENTER", 0, 0)
  end
  toastFrame.text:SetText(msg)
  toastFrame:Show()
  if C_Timer and C_Timer.After then C_Timer.After(8, function() toastFrame:Hide() end) end
end

--- PLAYER_LOGIN: load (or restore, or seed) this character's grid, then apply it.
function Grid.Init()
  Grid.class = (HHF.Compat and HHF.Compat.ClassOf and HHF.Compat.ClassOf("player")) or select(2, UnitClass("player"))
  Grid.controlledBy = Grid.CliqueLoaded() and "Clique" or nil
  Grid.ScanSpellbook()
  local sv = rawget(_G, "HogHealsFramesCharDB")
  Grid.seededNow, Grid.restoredNow = false, false
  if type(sv) ~= "table" or type(sv.slots) ~= "table" then
    local mirror = charMirror()
    mirror = mirror and mirror.clickGrid
    if type(mirror) == "table" and type(mirror.slots) == "table" then
      sv = copy(mirror)
      Grid.restoredNow = true
    elseif Grid.controlledBy == "Clique" then
      -- Do not seed under Clique: the first login WITHOUT Clique seeds and says so.
      sv = nil
    else
      sv = { schema = Grid.SCHEMA, slots = Grid.DefaultSlots(Grid.class), seededFor = tostring(Grid.class),
        seededAt = date and date("%Y-%m-%d %H:%M:%S") or "" }
      Grid.seededNow = true
    end
    if sv then _G.HogHealsFramesCharDB = sv end
  end
  Grid.db = sv
  Grid.slots = sv and sv.slots or {}
  if sv then Grid.Mirror() end
  if Grid.seededNow then
    Grid.Toast(next(Grid.slots) and Grid.TOAST_HEALER or Grid.TOAST_OTHER)
  end
  Grid.ApplyAll()
  return Grid.slots
end

-- ------------------------------------------------------------------------------------------------ apply
--- Write the grid's attributes onto one unit button (queued out of combat). Keys the grid set before and no longer
-- wants are cleared (nil), so the button falls back to *type1 target / *type2 menu.
function Grid.Apply(button)
  if not button then return false end
  local attrs = {}
  if Grid.controlledBy ~= "Clique" then attrs = Grid.AttributesFor(Grid.slots, Grid.class) end
  return HH:RunOutOfCombat(function()
    for k in pairs(button._hhGridKeys or {}) do
      if attrs[k] == nil then button:SetAttribute(k, nil) end
    end
    for k, v in pairs(attrs) do button:SetAttribute(k, v) end
    button._hhGridKeys = attrs
  end)
end
Grid.ApplyTo = Grid.Apply

function Grid.ApplyAll()
  if not (HHF.UnitButton and HHF.UnitButton.All) then return end
  for _, b in ipairs(HHF.UnitButton.All()) do Grid.Apply(b) end
end

-- The hover-bind engine rewrites mouse attributes when its list changes; re-apply the grid after it so a shared
-- mouse slot keeps the grid's spell. A post-hook, the engine itself is not modified.
if HHF.ClickCast and type(HHF.ClickCast.SetBindings) == "function" and type(hooksecurefunc) == "function" then
  hooksecurefunc(HHF.ClickCast, "SetBindings", function() if Grid.slots then Grid.ApplyAll() end end)
end

-- New ranks / newly learned spells: rescan, and re-apply only if what the buttons should carry changed.
local function signature()
  local parts = {}
  for k, v in pairs(Grid.AttributesFor(Grid.slots, Grid.class)) do parts[#parts + 1] = k .. "=" .. v end
  table.sort(parts)
  return table.concat(parts, "\n")
end

function Grid.OnSpellsChanged()
  if not Grid.slots then return end
  local before = signature()
  Grid.ScanSpellbook()
  if signature() ~= before then Grid.ApplyAll() end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function() if Grid.db then Grid.OnSpellsChanged() end end)

-- ------------------------------------------------------------------------------------------------ edit actions
local function slotOf(key) return Grid.slots and Grid.slots[key] end

function Grid.SetSlot(key, slot)
  if Grid.controlledBy == "Clique" then return false end
  if not Grid.db then
    Grid.db = { schema = Grid.SCHEMA, slots = {} }
    _G.HogHealsFramesCharDB = Grid.db
    Grid.slots = Grid.db.slots
  end
  Grid.slots[key] = slot
  save()
  Grid.ApplyAll()
  return true
end

--- Bind a spell (picker choice). Rank starts at Highest; "Resurrect if dead" starts on for a direct heal.
function Grid.Pick(key, name)
  Grid.ui.pickerFor = nil
  if name == nil or name == "" then return Grid.Clear(key) end
  Grid.ui.selected = key
  return Grid.SetSlot(key, { spell = name, rank = "highest", rez = Grid.IsDirectHeal(name) })
end

function Grid.Clear(key)
  Grid.ui.pickerFor, Grid.ui.rankMenuFor = nil, nil
  if Grid.ui.selected == key then Grid.ui.selected = nil end
  return Grid.SetSlot(key, nil)
end

function Grid.SetRank(key, rank)
  local s = slotOf(key)
  if not s then return false end
  Grid.ui.rankMenuFor = nil
  local n = tonumber(rank)
  local new = copy(s)
  new.rank = n or "highest"
  if n then new.alts = nil end          -- an exact rank pins the exact spell; no alternates
  return Grid.SetSlot(key, new)
end

function Grid.SetRez(key, on)
  local s = slotOf(key)
  if not s then return false end
  local new = copy(s)
  new.rez = on and true or false
  return Grid.SetSlot(key, new)
end

function Grid.ResetToDefaults()
  Grid.ui.selected, Grid.ui.pickerFor, Grid.ui.rankMenuFor = nil, nil, nil
  if Grid.controlledBy == "Clique" then return false end
  local slots = Grid.DefaultSlots(Grid.class)
  Grid.db = Grid.db or { schema = Grid.SCHEMA }
  _G.HogHealsFramesCharDB = Grid.db
  Grid.slots = slots
  save()
  Grid.ApplyAll()
  return true
end

function Grid.ClearAll()
  Grid.ui.selected, Grid.ui.pickerFor, Grid.ui.rankMenuFor = nil, nil, nil
  if Grid.controlledBy == "Clique" then return false end
  Grid.db = Grid.db or { schema = Grid.SCHEMA }
  _G.HogHealsFramesCharDB = Grid.db
  Grid.slots = {}
  save()
  Grid.ApplyAll()
  return true
end

function Grid.Select(key) Grid.ui.selected, Grid.ui.pickerFor, Grid.ui.rankMenuFor = key, nil, nil end
function Grid.OpenPicker(key)
  if Grid.controlledBy == "Clique" then return false end
  Grid.ui.pickerFor, Grid.ui.rankMenuFor, Grid.ui.pickerOffset = key, nil, 0
  return true
end
function Grid.OpenRankMenu(key)
  if not slotOf(key) then return false end
  Grid.ui.selected, Grid.ui.rankMenuFor, Grid.ui.pickerFor = key, key, nil
  return true
end
function Grid.CloseMenus() Grid.ui.pickerFor, Grid.ui.rankMenuFor = nil, nil end

--- Entries for the rank dropdown: Highest first, then every learned rank of the bound spell.
function Grid.RankChoices(key, book)
  local s = slotOf(key)
  if not s then return {} end
  book = book or Grid.Book()
  local r = Grid.Resolve(s, book)
  local spell = r and book.byName[r.name]
  local top = spell and spell.ranks[#spell.ranks]
  local out = { { key = "highest", label = "Highest rank (auto-upgrade)" .. (top and (" — now Rank " .. top) or "") } }
  for i = (spell and #spell.ranks or 0), 1, -1 do
    out[#out + 1] = { key = spell.ranks[i], label = "Rank " .. spell.ranks[i] }
  end
  return out
end

-- ------------------------------------------------------------------------------------------------ view model
--- Everything the tab shows, as plain data. The in-game widget (ClickGridUI.lua) and the mockup renderer
-- (dev/render_binding_ui.py) both draw from this, so a mockup shows what the code computes.
function Grid.ViewModel()
  local book = Grid.Book()
  local vm = { disabled = (Grid.controlledBy == "Clique") and Grid.CLIQUE_TEXT or nil, columns = {}, rows = {},
    selected = Grid.ui.selected, class = Grid.class, rezSpell = Grid.RezSpell(Grid.class, book), classRez = Grid.REZ[Grid.class or ""] }
  for _, m in ipairs(Grid.MODS) do vm.columns[#vm.columns + 1] = { key = m.key, label = Grid.ModLabel(m.key) } end
  for _, b in ipairs(Grid.BUTTONS) do
    local row = { key = b.key, label = b.label, cells = {} }
    for _, m in ipairs(Grid.MODS) do
      local key = Grid.SlotKey(b.key, m.key)
      local slot = Grid.slots and Grid.slots[key] or nil      -- shown greyed under Clique: kept, not lost
      local cell = { key = key, empty = slot == nil }
      if not slot and (m.key == "NONE") and (b.key == "LEFT" or b.key == "RIGHT") then
        cell.fallback = b.key == "LEFT" and "Target" or "Menu"
      end
      if slot then
        local r = Grid.Resolve(slot, book) or {}
        cell.spell, cell.icon, cell.known = r.name, r.icon, r.known and true or false
        cell.rankText = r.known and (r.highest and ("Highest" .. (r.rank and (" (" .. r.rank .. ")") or "")) or ("Rank " .. tostring(r.rank)))
          or (r.missingRank and ("Rank " .. tostring(r.rank) .. " not learned") or "not learned")
        cell.rez = slot.rez and true or false
        cell.rezActive = cell.rez and vm.rezSpell ~= nil
        cell.macro = Grid.SlotMacro(slot, Grid.class, book)
      end
      cell.selected = key == Grid.ui.selected
      row.cells[#row.cells + 1] = cell
    end
    vm.rows[#vm.rows + 1] = row
  end
  local sel = Grid.ui.selected and Grid.slots and Grid.slots[Grid.ui.selected]
  if sel and not vm.disabled then
    local r = Grid.Resolve(sel, book) or {}
    vm.editor = { key = Grid.ui.selected, title = Grid.SlotLabel(Grid.ui.selected) .. ": " .. tostring(r.name or sel.spell),
      rankLabel = (sel.rank == nil or sel.rank == "highest") and ("Highest rank" .. (r.rank and (" (Rank " .. r.rank .. ")") or ""))
        or ("Rank " .. tostring(sel.rank)),
      rez = sel.rez and true or false, rezSpell = vm.rezSpell, directHeal = Grid.IsDirectHeal(r.name or sel.spell, book),
      macro = Grid.SlotMacro(sel, Grid.class, book) }
  end
  if Grid.ui.pickerFor and not vm.disabled then
    vm.picker = { key = Grid.ui.pickerFor, title = "Pick a spell for " .. Grid.SlotLabel(Grid.ui.pickerFor), entries = Grid.PickerEntries(book),
      offset = Grid.ui.pickerOffset or 0 }
  end
  if Grid.ui.rankMenuFor and not vm.disabled then
    local s = Grid.slots[Grid.ui.rankMenuFor]
    vm.rankMenu = { key = Grid.ui.rankMenuFor, entries = Grid.RankChoices(Grid.ui.rankMenuFor, book),
      current = s and ((s.rank == nil) and "highest" or s.rank) }
  end
  return vm
end
