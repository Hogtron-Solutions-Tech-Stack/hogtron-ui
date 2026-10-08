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

local function playerClass() return HHF.Compat.ClassOf("player") end

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
  -- a reserved key (Enter = chat) that an older build let through is dropped here, said once, and saved without it
  if HH.ChatKey and HH.ChatKey.Strip then
    local kept, gone = HH.ChatKey.Strip(ClickCast.bindings)
    if #gone > 0 then
      ClickCast.bindings = kept
      if db then db.bindings = db.bindings or {} db.bindings[class] = kept end
      local names = {}
      for _, b in ipairs(gone) do names[#names + 1] = tostring(b.key) .. " (" .. tostring(b.value) .. ")" end
      HH:Print("Hover-heal: dropped " .. table.concat(names, ", ") .. " - that key is for chat.")
    end
  end
  ClickCast.ApplyGlobal()
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
  ClickCast.ApplyGlobal()
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
  if ClickCast.Mode() == "global" then return end            -- keys are already bound; nothing to do on hover
  -- SetOverrideBindingClick is protected: in combat the client blocks it (popup with a Disable button). Fail quiet;
  -- combat-safe mode exists for exactly this.
  if InCombatLockdown() then
    if not ClickCast.warnedCombat then
      ClickCast.warnedCombat = true
      HH:Print("Hover keys can't be set during combat on this client. Turn on combat-safe bindings in /hh > Frames > Bindings.")
    end
    return
  end
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
  if ClickCast.Mode() == "global" or InCombatLockdown() then return end
  ClearOverrideBindings(button)
  if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
end

-- ---------------------------------------------------------------- combat-safe ("global") mode
-- Keys are bound ONCE, out of combat, to hidden SecureActionButtons that run a /cast with the fallback chain
-- ([@mouseover,help,nodead] first). Hovering a unit frame makes that unit the mouseover, so the heal lands on it;
-- with nothing hovered it falls through to target, then self. Fully secure, no snippets, works in combat.
-- Cost: the key is taken everywhere, not only over frames; keys that already have a binding are skipped unless
-- frames.bindingForce is on.
function ClickCast.Mode()
  local db = HH.db and HH.db.profile.frames
  return db and db.bindingMode or "hover"
end

local owner
local function globalButton(i)
  local name = "HogHealsKey" .. i
  local b = _G[name]
  if not b then
    b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    if b.RegisterForClicks then b:RegisterForClicks("AnyDown", "AnyUp") end
    b:Hide()
  end
  return b
end

local function applyGlobalNow()
  local db = HH.db.profile.frames
  if ClickCast.globalApplied then ClearOverrideBindings(owner) end
  ClickCast.globalApplied = false
  if ClickCast.Mode() ~= "global" or ClickCast.controlledBy == "Clique" then return end
  owner = owner or CreateFrame("Frame", "HogHealsBindOwner", UIParent)
  ClickCast.globalApplied = true
  local skipped = {}
  local n = 0
  for _, b in ipairs(ClickCast.bindings or {}) do
    if not isMouse(b.key) then
      local key = keyString(b)
      local taken = type(GetBindingAction) == "function" and (GetBindingAction(key) or "") ~= ""
      if taken and not db.bindingForce then
        skipped[#skipped + 1] = key
      else
        n = n + 1
        local btn = globalButton(n)
        if b.type == "spell" then
          btn:SetAttribute("type", "macro")
          btn:SetAttribute("macrotext", ClickCast.Macro(b.value, db.fallback))
        else
          btn:SetAttribute("type", b.type)
          local va = VALUE_ATTR[b.type]
          if va then btn:SetAttribute(va, b.value) end
        end
        SetOverrideBindingClick(owner, true, key, btn:GetName())
      end
    end
  end
  if #skipped > 0 and table.concat(skipped, ",") ~= ClickCast.lastSkipped then
    ClickCast.lastSkipped = table.concat(skipped, ",")
    HH:Print("Combat-safe bindings: skipped " .. table.concat(skipped, ", ") .. " (already bound to something). Tick 'take over bound keys' in /hh > Frames > Bindings to use them anyway.")
  end
end

--- (Re)apply global bindings; queued until out of combat (binding functions are protected in combat).
function ClickCast.ApplyGlobal()
  HH:RunOutOfCombat(applyGlobalNow)
end

--- Human list for the options panel / tooltip.
function ClickCast.Describe(bindings)
  local out = {}
  for _, b in ipairs(bindings or ClickCast.bindings) do out[#out + 1] = keyString(b) .. " = " .. tostring(b.value) end
  return out
end
