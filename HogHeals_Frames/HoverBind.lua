-- Hover-heal quick bind: `/hh bind heals` (or `/hh hoverbind`, or the button in Frames > Bindings). A panel lists
-- the class's heal spells; hover a spell, press a key = that key hover-casts it. Esc on a spell clears its keys.
-- Mouse 3-5 bind too (left / right never: they are target / menu). Modifiers combine (CTRL-SHIFT-F).
-- Sean 2026-10-03: "I want the quick binding on the hover over heals" - picked the spell-list panel.
--
-- How: rows are plain Buttons; hovering one makes it the target; the panel takes keyboard input while open and
-- turns a press into Blizzard's binding string (ALT-CTRL-SHIFT-key order). Writes go through
-- ClickCast.SetBindings (persisted per class, applied to every cell, combat-safe mode re-applied). One key, one
-- spell: a key already on another spell moves. Keys pressed with nothing hovered pass through (movement keeps
-- working). Refused in combat, closes when combat starts, refused when Clique controls the bindings.
-- KeyString is a copy of the bars addon's (that addon is not on main); a shared Core helper is a follow-up.
HogHealsFrames = HogHealsFrames or {}
local HHF = HogHealsFrames
local HH = HogHeals

local HoverBind = { rows = {}, extra = {} }
HHF.HoverBind = HoverBind

local CREAM = { 0.96, 0.92, 0.86 }
local CYAN = { 0.13, 0.83, 0.88 }
local GREY = { 0.55, 0.55, 0.60 }
local INK = { 0.07, 0.07, 0.09 }
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, UNKNOWN = true }
local MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
local ROW_H, WIDTH, TOP, PAD = 24, 320, 46, 8

local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a = pcall(f, ...)
  if ok then return a end
end

-- ---------------------------------------------------------------- keys
--- Blizzard's binding string for a press: modifiers in Blizzard's order, then the key. nil for a lone modifier.
function HoverBind.KeyString(key, alt, ctrl, shift)
  if type(key) ~= "string" or key == "" or MODIFIER_KEYS[key] then return nil end
  local s = ""
  if alt then s = s .. "ALT-" end
  if ctrl then s = s .. "CTRL-" end
  if shift then s = s .. "SHIFT-" end
  return s .. key
end

--- "ALT-CTRL-3" -> "3", "ALT-CTRL"; "F" -> "F", "" (ClickCast keeps key and modifier apart).
function HoverBind.Split(s)
  local mod, key = s:match("^(.+)%-([^%-]+)$")
  if not key then return s, "" end
  return key, mod
end

local function mods()
  return call(IsAltKeyDown) == true, call(IsControlKeyDown) == true, call(IsShiftKeyDown) == true
end

local function keyString(b) return (b.mod and b.mod ~= "") and (b.mod:upper() .. "-" .. b.key:upper()) or b.key:upper() end

-- ---------------------------------------------------------------- spells
--- The class's heal catalogue: the shipped defaults, every spell already bound, and anything typed in - in
-- that order, no duplicates.
function HoverBind.Catalog(class, bindings)
  local names, seen = {}, {}
  local function add(n)
    if type(n) == "string" and n ~= "" and not seen[n] then seen[n] = true names[#names + 1] = n end
  end
  for _, b in ipairs(HHF.ClickCast.Defaults(class) or {}) do if b.type == "spell" then add(b.value) end end
  for _, b in ipairs(bindings or {}) do if b.type == "spell" then add(b.value) end end
  for _, n in ipairs(HoverBind.extra) do add(n) end
  return names
end

--- Keys bound to a spell, as binding strings.
function HoverBind.KeysFor(name, bindings)
  local out = {}
  for _, b in ipairs(bindings or HHF.ClickCast.bindings or {}) do
    if b.type == "spell" and b.value == name then out[#out + 1] = keyString(b) end
  end
  return out
end

--- Spell icon by whichever reader this client has; the second return names the one that worked (diag).
function HoverBind.Icon(name)
  if type(C_Spell) == "table" then
    if type(C_Spell.GetSpellTexture) == "function" then
      local t = call(C_Spell.GetSpellTexture, name)
      if t then return t, "C_Spell.GetSpellTexture" end
    end
    if type(C_Spell.GetSpellInfo) == "function" then
      local i = call(C_Spell.GetSpellInfo, name)
      if type(i) == "table" and i.iconID then return i.iconID, "C_Spell.GetSpellInfo" end
    end
  end
  if type(GetSpellTexture) == "function" then
    local t = call(GetSpellTexture, name)
    if t then return t, "GetSpellTexture" end
  end
  return nil, "none"
end

--- A spell typed into the panel: a row of its own from now on (this session; once bound it lives in the profile).
function HoverBind.AddSpell(name)
  name = strtrim(name or "")
  if name == "" then return false end
  for _, n in ipairs(HoverBind.extra) do if n == name then return false end end
  HoverBind.extra[#HoverBind.extra + 1] = name
  if HoverBind.active then HoverBind.Fill() end
  return true
end

-- ---------------------------------------------------------------- panel
local function panel()
  if HoverBind.frame then return HoverBind.frame end
  local f = CreateFrame("Frame", "HogHealsHoverBind", UIParent)
  f:SetSize(WIDTH, 160)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  call(f.SetFrameStrata, f, "DIALOG")
  call(f.EnableMouse, f, true)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints(f)
  f.bg:SetColorTexture(INK[1], INK[2], INK[3], 0.95)
  f.title = f:CreateFontString(nil, "OVERLAY", "HogTronFontNormal")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
  f.title:SetTextColor(CYAN[1], CYAN[2], CYAN[3])
  f.title:SetText("Hover-heal keys")
  f.hint = f:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(PAD + 18))
  f.hint:SetTextColor(GREY[1], GREY[2], GREY[3])
  f.hint:SetText("Hover a spell, press a key. Esc clears it. Mouse 3-5 bind too.")
  f.close = CreateFrame("Button", nil, f)
  f.close:SetSize(18, 18)
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -PAD)
  f.close.text = f.close:CreateFontString(nil, "OVERLAY", "HogTronFontNormal")
  f.close.text:SetPoint("CENTER", f.close, "CENTER", 0, 0)
  f.close.text:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
  f.close.text:SetText("x")
  f.close:SetScript("OnClick", function() HoverBind.Close("done") end)
  -- "Other spell..." : type a name, Enter adds a row for it
  f.edit = CreateFrame("EditBox", "HogHealsHoverBindEdit", f, "InputBoxTemplate")
  f.edit:SetSize(WIDTH - 2 * PAD - 8, 20)
  call(f.edit.SetAutoFocus, f.edit, false)
  f.edit:SetScript("OnEnterPressed", function(self)
    local t = call(self.GetText, self)
    if HoverBind.AddSpell(t) then call(self.SetText, self, "") end
    call(self.ClearFocus, self)
  end)
  f.edit:SetScript("OnEscapePressed", function(self) call(self.ClearFocus, self) end)
  f.editLabel = f:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  f.editLabel:SetTextColor(GREY[1], GREY[2], GREY[3])
  f.editLabel:SetText("Other spell: type a name, Enter")
  -- the keyboard: the panel takes every press while open; with nothing hovered the press passes through
  call(f.EnableKeyboard, f, true)
  f:SetScript("OnKeyDown", function(self, key)
    if not HoverBind.active or not HoverBind.target or MODIFIER_KEYS[key] then
      call(self.SetPropagateKeyboardInput, self, true)
      return
    end
    call(self.SetPropagateKeyboardInput, self, false)
    HoverBind.Press(key)
  end)
  f:SetScript("OnEvent", function(_, e) if e == "PLAYER_REGEN_DISABLED" then HoverBind.Close("combat") end end)
  pcall(f.RegisterEvent, f, "PLAYER_REGEN_DISABLED")
  f:Hide()
  HoverBind.frame = f
  return f
end

local function row(i)
  local r = HoverBind.rows[i]
  if r then return r end
  local f = panel()
  r = CreateFrame("Button", nil, f)
  r:SetSize(WIDTH - 2 * PAD, ROW_H)
  call(r.EnableMouse, r, true)
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints(r)
  r.bg:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(ROW_H - 4, ROW_H - 4)
  r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)
  if r.icon.SetTexCoord then call(r.icon.SetTexCoord, r.icon, 0.08, 0.92, 0.08, 0.92) end
  r.letter = r:CreateFontString(nil, "OVERLAY", "HogTronFontNormal")
  r.letter:SetPoint("CENTER", r.icon, "CENTER", 0, 0)
  r.letter:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
  r.name = r:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.name:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
  r.keys = r:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  r.keys:SetPoint("RIGHT", r, "RIGHT", -6, 0)
  r.keys:SetTextColor(GREY[1], GREY[2], GREY[3])
  r:SetScript("OnEnter", function(self)
    HoverBind.target = self
    self.bg:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.35)
  end)
  r:SetScript("OnLeave", function(self)
    if HoverBind.target == self then HoverBind.target = nil end
    self.bg:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0)
  end)
  r:SetScript("OnMouseDown", function(self, button)
    local key = MOUSE[button]
    if key then HoverBind.target = self HoverBind.Press(key) end   -- left / right never bind
  end)
  HoverBind.rows[i] = r
  return r
end

--- (Re)build the rows from the catalogue and the current bindings; sizes the panel.
function HoverBind.Fill()
  local f = panel()
  local class = HHF.Compat and HHF.Compat.ClassOf and HHF.Compat.ClassOf("player")
  local names = HoverBind.Catalog(class, HHF.ClickCast.bindings)
  local api
  for i, n in ipairs(names) do
    local r = row(i)
    r.spell = n
    local icon, which = HoverBind.Icon(n)
    api = api or which
    if icon then
      call(r.icon.SetTexture, r.icon, icon)
      r.icon:Show()
      r.letter:SetText("")
    else
      r.icon:Hide()
      r.letter:SetText(n:sub(1, 1))
    end
    r.name:SetText(n)
    r.keys:SetText(table.concat(HoverBind.KeysFor(n), "  "))
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(TOP + (i - 1) * ROW_H))
    r:Show()
  end
  for i = #names + 1, #HoverBind.rows do HoverBind.rows[i]:Hide() end
  local bottom = TOP + #names * ROW_H
  f.editLabel:ClearAllPoints()
  f.editLabel:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(bottom + 6))
  f.edit:ClearAllPoints()
  f.edit:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 4, -(bottom + 22))
  f:SetHeight(bottom + 56)
  HoverBind.count = #names
  HoverBind.iconApi = api or "none"
  return #names
end

-- ---------------------------------------------------------------- binding
--- Bind `key` (a raw key name from OnKeyDown, or BUTTONn) to the hovered row's spell; ESCAPE clears that spell.
-- Returns the binding string (or "cleared") and the spell a moved key came from, for the chat line and tests.
function HoverBind.Press(key)
  local r = HoverBind.target
  if not r or not r.spell then return nil end
  local reserved = key ~= "ESCAPE" and HH.ChatKey and HH.ChatKey.Reserved(key)
  if reserved then HH:Print(("Hover-heal: %s is for %s, not for a spell."):format(key == "ENTER" and "Enter" or key, reserved)) return nil end
  local current = HHF.ClickCast.bindings or {}
  local list = {}
  if key == "ESCAPE" then
    for _, b in ipairs(current) do
      if not (b.type == "spell" and b.value == r.spell) then list[#list + 1] = b end
    end
    HHF.ClickCast.SetBindings(list)
    HoverBind.Fill()
    HoverBind.last = { spell = r.spell, key = "cleared" }
    HH:Print("Hover-heal: " .. r.spell .. " has no key now.")
    return "cleared"
  end
  local s = HoverBind.KeyString(key, mods())
  if not s then return nil end
  local k, mod = HoverBind.Split(s)
  local moved
  for _, b in ipairs(current) do
    if (b.key or ""):upper() == k:upper() and (b.mod or ""):upper() == mod:upper() then
      if b.value ~= r.spell then moved = b.value end
    else
      list[#list + 1] = b
    end
  end
  list[#list + 1] = { key = k, mod = mod, type = "spell", value = r.spell }
  HHF.ClickCast.SetBindings(list)
  HoverBind.Fill()
  HoverBind.last = { spell = r.spell, key = s, moved = moved }
  HH:Print(("Hover-heal: %s = %s%s"):format(s, r.spell, moved and (" (was " .. tostring(moved) .. ")") or ""))
  return s, moved
end

-- ---------------------------------------------------------------- open / close
function HoverBind.Open()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then HH:Print("Hover-heal keys: not in combat.") return false end
  if HHF.ClickCast.controlledBy == "Clique" then HH:Print("Hover-heal keys: Clique controls the bindings here - use Clique's panel.") return false end
  HoverBind.active = true
  HoverBind.Fill()
  panel():Show()
  local g = HH.db and HH.db.global
  if g then g.diag = g.diag or {} g.diag.hoverBind = { iconApi = HoverBind.iconApi, rows = HoverBind.count } end
  HH:Print("Hover-heal keys: hover a spell, press a key. Esc clears that spell. /hh bind heals to finish.")
  return true
end

function HoverBind.Close(why)
  if not HoverBind.active then return false end
  HoverBind.active, HoverBind.target = false, nil
  if HoverBind.frame then HoverBind.frame:Hide() end
  HH:Print(why == "combat" and "Hover-heal keys closed (combat)." or "Hover-heal keys saved.")
  return true
end

function HoverBind.Toggle()
  if HoverBind.active then return HoverBind.Close("done") end
  return HoverBind.Open()
end

-- ---------------------------------------------------------------- slash
local function wantsHeals(rest)
  local r = strtrim(rest or ""):lower()
  return r == "heals" or r == "heal" or r == "hover"
end

--- `/hh bind heals` on top of whatever already owns `bind` (the bars addon loads first and registers it);
-- without an owner, `bind` is ours and anything but "heals" gets a one-line help. `/hh hoverbind` always works.
function HoverBind.Init()
  if HoverBind.inited then return end
  HoverBind.inited = true
  local existing = HH.slash and HH.slash.bind
  if existing and not existing.hhHover then
    local fn = existing.fn
    HH:RegisterSlash("bind", function(rest)
      if wantsHeals(rest) then HoverBind.Toggle() else fn(rest) end
    end, (existing.help or "") .. "; 'bind heals' = hover-heal keys")
    HH.slash.bind.hhHover = true
  elseif not existing then
    HH:RegisterSlash("bind", function(rest)
      if wantsHeals(rest) then HoverBind.Toggle()
      else HH:Print("/hh bind heals = hover-heal keys (hover a spell, press a key). Action-bar key binding needs HogTron UI Bars.") end
    end, "heals: hover-heal keys (hover a spell, press a key)")
    HH.slash.bind.hhHover = true
  end
  HH:RegisterSlash("hoverbind", function() HoverBind.Toggle() end, "hover-heal keys: hover a spell, press a key")
end
