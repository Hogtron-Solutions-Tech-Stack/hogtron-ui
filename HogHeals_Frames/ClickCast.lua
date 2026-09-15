-- Hover-bind engine. Any key or mouse button (+modifier) casts on the hovered frame.
-- Mouse buttons -> SecureActionButton attributes. Keyboard keys -> override bindings set on
-- OnEnter and cleared on OnLeave (Clique's technique), routed to virtual buttons "hhkeyN".
HogHealsFrames = HogHealsFrames or {}
local HHF = HogHealsFrames
local HH = HogHeals

local ClickCast = {}
HHF.ClickCast = ClickCast
ClickCast.bindings = {}
ClickCast.controlledBy = nil

local VALUE_ATTR = { spell = "spell", macro = "macrotext", item = "item", target = nil, menu = nil }

local function isMouse(key) return key and key:match("^BUTTON%d+$") ~= nil end
local function prefix(mod) return (mod and mod ~= "") and (mod:lower() .. "-") or "" end
local function keyString(b) return (b.mod and b.mod ~= "") and (b.mod:upper() .. "-" .. b.key:upper()) or b.key:upper() end

--- Mouse bindings -> attribute table (keyboard ones are handled by OnEnter).
function ClickCast.AttributesFor(bindings)
  local attrs = {}
  for _, b in ipairs(bindings or {}) do
    if isMouse(b.key) then
      local n = b.key:match("^BUTTON(%d+)$")
      local p = prefix(b.mod)
      attrs[p .. "type" .. n] = b.type
      local va = VALUE_ATTR[b.type]
      if va then attrs[p .. va .. n] = b.value end
    end
  end
  return attrs
end

--- Keyboard bindings -> attributes for virtual buttons hhkeyN (N = index in list).
function ClickCast.KeyAttributesFor(bindings)
  local attrs = {}
  for i, b in ipairs(bindings or {}) do
    if not isMouse(b.key) then
      local id = "hhkey" .. i
      attrs["type-" .. id] = b.type
      local va = VALUE_ATTR[b.type]
      if va then attrs[va .. "-" .. id] = b.value end
    end
  end
  return attrs
end

--- Fallback-chain macro for a spell.
function ClickCast.Macro(spell, chain)
  chain = chain or { mouseover = true, target = true, player = true }
  local parts = {}
  if chain.mouseover then parts[#parts + 1] = "[@mouseover,help,nodead]" end
  if chain.focus then parts[#parts + 1] = "[@focus,help,nodead]" end
  if chain.target then parts[#parts + 1] = "[help,nodead]" end
  if chain.player then parts[#parts + 1] = "[@player]" end
  return "/cast " .. table.concat(parts, "") .. " " .. spell
end

local function purify()
  return (HHF.Compat and HHF.Compat.isTBC) and "Cleanse" or "Purify"
end

--- Shipped defaults per class (Sean's real Clique layout for Priest).
function ClickCast.Defaults(class)
  local B = function(key, mod, value, kind) return { key = key, mod = mod or "", type = kind or "spell", value = value } end
  local D = {
    PRIEST = {
      B("1", "", "Greater Heal"), B("2", "", "Greater Heal"), B("3", "", "Flash Heal"), B("4", "", "Renew"),
      B("F", "", "Power Word: Shield"), B("Q", "", "Dispel Magic"), B("1", "SHIFT", "Prayer of Healing"),
      B("2", "CTRL", "Power Word: Fortitude"), B("4", "CTRL", "Divine Spirit"),
    },
    SHAMAN = {
      B("1", "", "Healing Wave"), B("2", "", "Lesser Healing Wave"), B("3", "", "Chain Heal"),
      B("Q", "", "Cure Poison"), B("F", "", "Cure Disease"),
    },
    PALADIN = {
      B("1", "", "Holy Light"), B("2", "", "Flash of Light"), B("Q", "", purify()),
      B("F", "", "Blessing of Protection"),
    },
    DRUID = {
      B("1", "", "Healing Touch"), B("2", "", "Regrowth"), B("3", "", "Rejuvenation"),
      B("Q", "", "Remove Curse"), B("F", "", "Cure Poison"),
    },
  }
  return D[class] or {}
end

local function playerClass() local _, c = UnitClass("player") return c end

function ClickCast.Init()
  local cliqueLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Clique"))
    or (IsAddOnLoaded and IsAddOnLoaded("Clique")) or _G.Clique ~= nil
  if cliqueLoaded then
    ClickCast.controlledBy = "Clique"
    return
  end
  ClickCast.controlledBy = nil
  local db = HH.db and HH.db.profile.frames
  local class = playerClass()
  local saved = db and db.bindings and db.bindings[class]
  ClickCast.bindings = saved or ClickCast.Defaults(class)
end

--- Replace current bindings and persist for this class.
function ClickCast.SetBindings(list)
  ClickCast.bindings = list or {}
  local db = HH.db and HH.db.profile.frames
  if db then
    db.bindings = db.bindings or {}
    db.bindings[playerClass()] = ClickCast.bindings
  end
  for _, b in ipairs(HHF.UnitButton.All()) do ClickCast.Apply(b) end
end

--- Write mouse + keyboard attributes onto a button (queued out of combat).
function ClickCast.Apply(button, bindings)
  if ClickCast.controlledBy == "Clique" then
    if _G.Clique and _G.Clique.UpdateRegisteredClicks then pcall(_G.Clique.UpdateRegisteredClicks, _G.Clique, button) end
    return false
  end
  bindings = bindings or ClickCast.bindings
  local attrs = ClickCast.AttributesFor(bindings)
  for k, v in pairs(ClickCast.KeyAttributesFor(bindings)) do attrs[k] = v end
  button._hhBindings = bindings
  return HH:RunOutOfCombat(function()
    for k, v in pairs(attrs) do button:SetAttribute(k, v) end
  end)
end
ClickCast.ApplyTo = function(button) return ClickCast.Apply(button) end

function ClickCast.OnEnter(button)
  if ClickCast.controlledBy == "Clique" then return end
  local name = button:GetName()
  if not name then return end
  local bindings = button._hhBindings or ClickCast.bindings
  for i, b in ipairs(bindings) do
    if not isMouse(b.key) then
      SetOverrideBindingClick(button, true, keyString(b), name, "hhkey" .. i)
    end
  end
  if HH.db.profile.frames.showBindingTooltip and GameTooltip then
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    for _, b in ipairs(bindings) do GameTooltip:AddLine(keyString(b) .. "  " .. tostring(b.value)) end
    GameTooltip:Show()
  end
end

function ClickCast.OnLeave(button)
  if ClickCast.controlledBy == "Clique" then return end
  ClearOverrideBindings(button)
  if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
end

--- Human list for the options panel / tooltip.
function ClickCast.Describe(bindings)
  local out = {}
  for _, b in ipairs(bindings or ClickCast.bindings) do out[#out + 1] = keyString(b) .. " = " .. tostring(b.value) end
  return out
end
