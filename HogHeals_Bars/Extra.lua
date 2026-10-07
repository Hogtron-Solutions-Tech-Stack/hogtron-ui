-- Pet bar and stance / shapeshift bar: our own secure buttons on the same layout engine, flat look, bind mode
-- targets (BONUSACTIONBUTTON<i> / SHAPESHIFTBUTTON<i>). Blizzard's PetActionBar / StanceBar hidden.
--
-- Secret-safe: icons, checked state and autocast come straight from the client; the cooldown swipe is drawn only
-- when start and duration are plain numbers. Attributes (the spell behind a stance) are set out of combat only.
HogHealsBars = HogHealsBars or {}
local HHB = HogHealsBars
local HH = HogHeals
local Bars = HHB.Bars

local Extra = {}
HHB.Extra = Extra

local CYAN = { 0.13, 0.83, 0.88 }
local LINE = { 0.20, 0.20, 0.25 }
local function cfg() return HH.db.profile.bars end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local r = { pcall(f, ...) }
  if r[1] then return select(2, unpack(r)) end
end

-- ------------------------------------------------------------------------------------------------ bindings mixin
--- What bind mode needs from a button that is not the lib's: the same four methods, over one binding name.
local function bindMixin(b, target)
  b.keyBoundTarget = target
  function b:GetBindingAction() return self.keyBoundTarget end
  function b:GetBindings()
    local out = {}
    local n = select("#", GetBindingKey(self.keyBoundTarget))
    for i = 1, n do
      local k = select(i, GetBindingKey(self.keyBoundTarget))
      out[#out + 1] = (type(GetBindingText) == "function" and call(GetBindingText, k)) or k
    end
    return table.concat(out, ", ")
  end
  function b:SetKey(key) call(SetBinding, key, self.keyBoundTarget) end
  function b:ClearBindings()
    for _ = 1, 8 do
      local k = GetBindingKey(self.keyBoundTarget)
      if not k then break end
      local ok = pcall(SetBinding, k, nil)
      if not ok then break end
    end
  end
  function b:UpdateHotkeys()
    local k = GetBindingKey(self.keyBoundTarget)
    local text = k and ((type(GetBindingText) == "function" and call(GetBindingText, k, 1)) or k) or ""
    self.HotKey:SetText(text)
  end
end

local function newButton(bar, name, i, target)
  local b = CreateFrame("CheckButton", name, bar, "SecureActionButtonTemplate")
  b.id, b.hhBar = i, bar
  if b.RegisterForClicks then b:RegisterForClicks(HH.SecureClick and HH.SecureClick() or "AnyUp") end
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints(b)
  b.HotKey = b:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  b.HotKey:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
  b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cooldown:SetAllPoints(b)
  bindMixin(b, target)
  Bars.Dress(b)
  if b.HotKey.SetFont then call(b.HotKey.SetFont, b.HotKey, HogHeals.Look.Font() or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", cfg().hotkeySize or 10, "OUTLINE") end
  return b
end

local function paintCooldown(b, start, duration, enable)
  local s, d = num(start), num(duration)
  if s and d and d > 0 and enable ~= 0 and enable ~= false and b.cooldown.SetCooldown then
    b.cooldown:SetCooldown(s, d)
    b.cooldown:Show()
  else
    b.cooldown:Hide()
  end
end

-- ------------------------------------------------------------------------------------------------ pet bar
function Extra.CreatePet()
  if Bars.bars.pet then return Bars.bars.pet end
  local bar = CreateFrame("Frame", "HogUIPetBar", UIParent, "SecureHandlerStateTemplate")
  bar.n, bar.buttons, bar.spec = "pet", {}, { label = "Pet bar" }
  bar:SetMovable(true)
  bar:SetClampedToScreen(true)
  bar:SetFrameStrata("MEDIUM")
  bar.hhOurs = true
  for i = 1, 10 do
    local b = newButton(bar, "HogUIPetButton" .. i, i, "BONUSACTIONBUTTON" .. i)
    b:SetAttribute("type", "pet")
    b:SetAttribute("action", i)
    function b:HasAction() return call(GetPetActionInfo, self.id) ~= nil end
    b:SetScript("OnEnter", function(self)
      if GameTooltip and GameTooltip.SetPetAction then GameTooltip:SetOwner(self, "ANCHOR_RIGHT") call(GameTooltip.SetPetAction, GameTooltip, self.id) GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
    bar.buttons[i] = b
  end
  bar.visPrefix = "[nopet]hide;"   -- no pet, no bar - whatever the visibility option says
  bar.handle = Bars.DragHandle(bar, "Pet")
  bar.describe = function() return ("pet bar: %d actions, %s"):format(Extra.petCount or 0, Bars.bars.pet:IsShown() and "shown" or "hidden") end
  Bars.bars.pet = bar
  return bar
end

--- Icons, checked state, autocast and cooldowns from the client. Returns how many actions the pet has.
function Extra.UpdatePet()
  local bar = Bars.bars.pet
  if not bar then return 0 end
  local n = 0
  for i, b in ipairs(bar.buttons) do
    local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled = call(GetPetActionInfo, i)
    if name ~= nil then
      n = n + 1
      local icon = texture
      if isToken == true and type(texture) == "string" then icon = rawget(_G, texture) or texture end
      b.icon:SetTexture(icon)
      if b.SetChecked then call(b.SetChecked, b, isActive == true) end
      local on = autoCastEnabled == true
      if b.hh and b.hh.edges then for _, e in ipairs(b.hh.edges) do e:SetColorTexture(on and CYAN[1] or LINE[1], on and CYAN[2] or LINE[2], on and CYAN[3] or LINE[3], 1) end end
      paintCooldown(b, call(GetPetActionCooldown, i))
    else
      b.icon:SetTexture(nil)
      if b.SetChecked then call(b.SetChecked, b, false) end
      b.cooldown:Hide()
    end
    b:UpdateHotkeys()
    Bars.UpdateCell(b)
  end
  Extra.petCount = n
  return n
end

-- ------------------------------------------------------------------------------------------------ stance bar
function Extra.CreateStance()
  if Bars.bars.stance then return Bars.bars.stance end
  local bar = CreateFrame("Frame", "HogUIStanceBar", UIParent, "SecureHandlerStateTemplate")
  bar.n, bar.buttons, bar.spec = "stance", {}, { label = "Stance / form bar" }
  bar:SetMovable(true)
  bar:SetClampedToScreen(true)
  bar:SetFrameStrata("MEDIUM")
  bar.hhOurs = true
  for i = 1, 10 do
    local b = newButton(bar, "HogUIStanceButton" .. i, i, "SHAPESHIFTBUTTON" .. i)
    b:SetAttribute("type", "spell")
    function b:HasAction() return self.id <= (num(call(GetNumShapeshiftForms)) or 0) end
    b:SetScript("OnEnter", function(self)
      if GameTooltip and GameTooltip.SetShapeshift then GameTooltip:SetOwner(self, "ANCHOR_RIGHT") call(GameTooltip.SetShapeshift, GameTooltip, self.id) GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
    bar.buttons[i] = b
  end
  bar.handle = Bars.DragHandle(bar, "Stances")
  bar.describe = function() return ("stance bar: %d forms"):format(Extra.formCount or 0) end
  Bars.bars.stance = bar
  return bar
end

--- Forms from the client: icon, active, castable, and the spell behind each (modern clients hand a spell id,
-- older ones a name - both cast through type = "spell"). Attributes only out of combat. Returns the form count.
function Extra.UpdateStance()
  local bar = Bars.bars.stance
  if not bar then return 0 end
  local n = num(call(GetNumShapeshiftForms)) or 0
  Extra.formCount = n
  bar.countOverride = n > 0 and n or 1
  for i, b in ipairs(bar.buttons) do
    if i <= n then
      local icon, a2, a3, a4 = call(GetShapeshiftFormInfo, i)
      -- modern: icon, isActive, isCastable, spellID; classic: icon, name, isActive, isCastable
      local isActive, spell
      if type(a2) == "string" then spell, isActive = a2, a3 == true else isActive, spell = a2 == true, a4 end
      b.icon:SetTexture(icon)
      if b.SetChecked then call(b.SetChecked, b, isActive) end
      if spell ~= nil and not (type(InCombatLockdown) == "function" and InCombatLockdown()) then
        if b:GetAttribute("spell") ~= spell then b:SetAttribute("spell", spell) end
      end
      paintCooldown(b, call(GetShapeshiftFormCooldown, i))
    else
      b.icon:SetTexture(nil)
      b.cooldown:Hide()
    end
    b:UpdateHotkeys()
    Bars.UpdateCell(b)
  end
  if n == 0 then bar:Hide() elseif cfg().list.stance.enabled ~= false then bar:Show() end
  return n
end

-- ------------------------------------------------------------------------------------------------ build / events
Extra.BLIZZARD = { "PetActionBar", "PetActionBarFrame", "StanceBar", "StanceBarFrame", "ShapeshiftBarFrame", "PossessBarFrame" }
Extra.BLIZZARD_BUTTONS = { "PetActionButton", "StanceButton", "ShapeshiftButton", "PossessButton" }

function Extra.HideBlizzard()
  local n = 0
  for _, name in ipairs(Extra.BLIZZARD) do
    local f = rawget(_G, name)
    if f then Bars.found[name] = true if Bars.Banish(f) then n = n + 1 end else Bars.missing[name] = true end
  end
  for _, p in ipairs(Extra.BLIZZARD_BUTTONS) do
    for i = 1, 10 do local b = rawget(_G, p .. i) if b and Bars.Banish(b) then n = n + 1 end end
  end
  return n
end

--- Called from Bars.Build (out of combat): both bars built / laid out / updated as the profile says.
function Extra.Build()
  local d = cfg()
  Extra.HideBlizzard()
  local pet = Extra.CreatePet()
  if d.list.pet.enabled ~= false then Bars.Layout(pet) pet:Show() else pet:Hide() end
  Extra.UpdatePet()
  local st = Extra.CreateStance()
  if d.list.stance.enabled ~= false then Bars.Layout(st) else st:Hide() end
  Extra.UpdateStance()
  if not Extra.events then
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PET_BAR_UPDATE", "PET_BAR_UPDATE_COOLDOWN", "UNIT_PET", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PET_UI_UPDATE",
      "UPDATE_SHAPESHIFT_FORMS", "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_USABLE", "UPDATE_SHAPESHIFT_COOLDOWN", "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS" }) do
      pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, e)
      local ok, err = pcall(function()
        if e:find("^PET") or e == "UNIT_PET" or e:find("^PLAYER_CONTROL") or e == "PLAYER_ENTERING_WORLD" or e == "UPDATE_BINDINGS" then Extra.UpdatePet() end
        if e:find("^UPDATE_SHAPESHIFT") or e == "PLAYER_ENTERING_WORLD" or e == "UPDATE_BINDINGS" then Extra.UpdateStance() end
      end)
      if not ok and err ~= Extra.lastError then Extra.lastError = err HH:LogError("bars extra " .. e .. ": " .. tostring(err)) end
    end)
    Extra.events = ev
  end
  return 2
end
