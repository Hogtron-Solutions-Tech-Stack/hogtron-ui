-- Secure unit button factory + element registry. One Update(button, unit) per element.
HogHealsFrames = HogHealsFrames or {}
local HHF = HogHealsFrames
local HH = HogHeals

local UnitButton = {}
HHF.UnitButton = UnitButton
HHF.Elements = HHF.Elements or {}
HHF.ElementOrder = HHF.ElementOrder or {}

local buttons = {}       -- every button we created or set up (array)
local byName = {}

--- Elements register themselves: { Update = fn(button, unit), Events = { "UNIT_HEALTH", ... }, Enabled = fn() }
function UnitButton.RegisterElement(name, element)
  HHF.Elements[name] = element
  element.name = name
  local present = false
  for _, n in ipairs(HHF.ElementOrder) do if n == name then present = true end end
  if not present then HHF.ElementOrder[#HHF.ElementOrder + 1] = name end
end

local function db() return HH.db and HH.db.profile.frames end

local function elementEnabled(name)
  local d = db()
  local element = HHF.Elements[name]
  if element and element.Enabled and not element.Enabled() then return false end
  local ind = d and d.indicators
  if ind and ind[name] == false then return false end
  return true
end
UnitButton.ElementEnabled = elementEnabled

-- ---------------------------------------------------------------- regions
local function mkTexture(parent, layer, sub)
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
  return t
end

--- Build all regions on a (secure) button. Idempotent.
function UnitButton.Setup(button)
  if not button or button._hhSetup then return button end
  button._hhSetup = true
  button.bg = mkTexture(button, "BACKGROUND")
  button.bg:SetAllPoints(button)
  button.bg:SetColorTexture(0.07, 0.07, 0.09, 0.6)

  button.health = CreateFrame("StatusBar", nil, button)
  button.health:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
  button.health:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
  button.health:SetMinMaxValues(0, 1)
  button.health:SetValue(1)
  button.health.bg = mkTexture(button.health, "BACKGROUND")
  button.health.bg:SetAllPoints(button.health)

  button.healPred = mkTexture(button.health, "ARTWORK", 1)
  button.healPred:SetPoint("TOPLEFT", button.health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
  button.healPred:SetPoint("BOTTOMLEFT", button.health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
  button.healPred:SetWidth(0)
  button.healPred:Hide()
  button.healPredOthers = mkTexture(button.health, "ARTWORK", 2)
  button.healPredOthers:Hide()

  button.power = CreateFrame("StatusBar", nil, button)
  button.power:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 1)
  button.power:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
  button.power:SetHeight(3)
  button.power:SetMinMaxValues(0, 1)

  button.name = button:CreateFontString(nil, "OVERLAY")
  button.name:SetPoint("TOP", button, "TOP", 0, -3)
  button.healthText = button:CreateFontString(nil, "OVERLAY")
  button.healthText:SetPoint("BOTTOM", button, "BOTTOM", 0, 4)

  button.dispelBorder = mkTexture(button, "OVERLAY", 1)
  button.dispelBorder:SetAllPoints(button)
  button.dispelBorder:Hide()
  button.dispelIcon = mkTexture(button, "OVERLAY", 3)
  button.dispelIcon:SetSize(14, 14)
  button.dispelIcon:SetPoint("CENTER", button, "CENTER", 0, 0)
  button.dispelIcon:Hide()
  button.priorityIcon = mkTexture(button, "OVERLAY", 4)
  button.priorityIcon:SetSize(18, 18)
  button.priorityIcon:SetPoint("CENTER", button, "CENTER", 0, 0)
  button.priorityIcon:Hide()

  button.aggroBorder = mkTexture(button, "OVERLAY", 2)
  button.aggroBorder:SetAllPoints(button)
  button.aggroBorder:SetColorTexture(0.85, 0.2, 0.2, 0.8)
  button.aggroBorder:Hide()

  button.raidIcon = mkTexture(button, "OVERLAY", 5)
  button.raidIcon:SetSize(12, 12)
  button.raidIcon:SetPoint("TOP", button, "TOP", 0, 2)
  button.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
  button.raidIcon:Hide()

  button.statusIcon = mkTexture(button, "OVERLAY", 5)
  button.statusIcon:SetSize(12, 12)
  button.statusIcon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
  button.statusIcon:Hide()

  button.missingBuff = mkTexture(button, "OVERLAY", 5)
  button.missingBuff:SetSize(10, 10)
  button.missingBuff:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
  button.missingBuff:Hide()

  button.shieldIcon = mkTexture(button, "OVERLAY", 5)
  button.shieldIcon:SetSize(10, 10)
  button.shieldIcon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 4)
  button.shieldIcon:Hide()
  button.shieldText = button:CreateFontString(nil, "OVERLAY")
  button.shieldText:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -12, 4)
  button.shieldText:Hide()

  button.aoeGlow = mkTexture(button, "OVERLAY", 0)
  button.aoeGlow:SetAllPoints(button)
  button.aoeGlow:SetColorTexture(0.13, 0.83, 0.88, 0.25)
  button.aoeGlow:Hide()

  button.thresholds = {}

  button:SetScript("OnAttributeChanged", UnitButton.OnAttributeChanged)
  button:SetScript("OnEvent", UnitButton.OnEvent)
  button:SetScript("OnShow", function(self) UnitButton.UpdateAll(self) end)
  button:SetScript("OnEnter", UnitButton.OnEnter)
  button:SetScript("OnLeave", UnitButton.OnLeave)

  if not byName[button:GetName() or tostring(button)] then
    buttons[#buttons + 1] = button
    byName[button:GetName() or tostring(button)] = button
  end
  UnitButton.ApplyAppearance(button)
  return button
end

--- Create a standalone secure button (test mode / spotlight). Header children use Setup() instead.
function UnitButton.Create(name, parent, secure)
  local template = (secure == false) and nil or "SecureUnitButtonTemplate"
  local button = CreateFrame("Button", name, parent or UIParent, template)
  button:SetAttribute("*type1", "target")
  button:SetAttribute("*type2", "togglemenu")
  if button.RegisterForClicks then button:RegisterForClicks("AnyDown") end
  return UnitButton.Setup(button)
end

function UnitButton.All() return buttons end

-- ---------------------------------------------------------------- appearance
function UnitButton.ApplyAppearance(button)
  local d = db()
  if not d then return end
  local ap = d.appearance
  local LSM = LibStub("LibSharedMedia-3.0", true)
  local font = LSM and LSM:Fetch("font", ap.font) or STANDARD_TEXT_FONT
  local tex = LSM and LSM:Fetch("statusbar", ap.texture) or "Interface\\TargetingFrame\\UI-StatusBar"
  button.health:SetStatusBarTexture(tex)
  button.power:SetStatusBarTexture(tex)
  button.power:SetHeight(ap.powerHeight or 3)
  button.name:SetFont(font, ap.fontSize or 11, ap.fontOutline or "OUTLINE")
  button.healthText:SetFont(font, (ap.fontSize or 11) - 1, ap.fontOutline or "OUTLINE")
  button.shieldText:SetFont(font, (ap.fontSize or 11) - 2, ap.fontOutline or "OUTLINE")
  button.bg:SetColorTexture(0.07, 0.07, 0.09, ap.backgroundAlpha or 0.6)
  local layout = HHF.module and HHF.module.LayoutFor and HHF.module:LayoutFor()
  if layout then button:SetSize(layout.width, layout.height) end
end

-- ---------------------------------------------------------------- unit binding / events
function UnitButton.OnAttributeChanged(button, key, value)
  if key ~= "unit" then return end
  if value == button.unit then return end
  button.unit = value
  button:UnregisterAllEvents()
  if not value then return end
  local seen = {}
  for _, name in ipairs(HHF.ElementOrder) do
    local el = HHF.Elements[name]
    for _, ev in ipairs(el.Events or {}) do
      if not seen[ev] then
        seen[ev] = true
        if ev:sub(1, 5) == "UNIT_" and button.RegisterUnitEvent then button:RegisterUnitEvent(ev, value)
        else button:RegisterEvent(ev) end
      end
    end
  end
  UnitButton.UpdateAll(button)
end

function UnitButton.OnEvent(button, event, arg1)
  local unit = button.unit
  if not unit then return end
  if event:sub(1, 5) == "UNIT_" and arg1 and arg1 ~= unit then return end
  for _, name in ipairs(HHF.ElementOrder) do
    local el = HHF.Elements[name]
    if el.EventSet and el.EventSet[event] and elementEnabled(name) then
      local ok, err = pcall(el.Update, button, unit)
      if not ok then HH:LogError(name .. ": " .. tostring(err)) end
    end
  end
end

function UnitButton.UpdateAll(button)
  local unit = button.unit
  if not unit then return end
  for _, name in ipairs(HHF.ElementOrder) do
    local el = HHF.Elements[name]
    if elementEnabled(name) then
      local ok, err = pcall(el.Update, button, unit)
      if not ok then HH:LogError(name .. ": " .. tostring(err)) end
    elseif el.Hide then
      pcall(el.Hide, button)
    end
  end
end

function UnitButton.UpdateElement(button, name)
  local el = HHF.Elements[name]
  if el and button.unit and elementEnabled(name) then
    local ok, err = pcall(el.Update, button, button.unit)
    if not ok then HH:LogError(name .. ": " .. tostring(err)) end
  end
end

function UnitButton.OnEnter(button)
  if HHF.ClickCast and HHF.ClickCast.OnEnter then HHF.ClickCast.OnEnter(button) end
  if HHF.Elements.aoeHealing and elementEnabled("aoeHealing") then HHF.Elements.aoeHealing.OnEnter(button) end
end

function UnitButton.OnLeave(button)
  if HHF.ClickCast and HHF.ClickCast.OnLeave then HHF.ClickCast.OnLeave(button) end
  if HHF.Elements.aoeHealing then HHF.Elements.aoeHealing.OnLeave(button) end
end

-- Precompute EventSet for elements registered after this file loads.
function UnitButton.FinalizeElements()
  for _, name in ipairs(HHF.ElementOrder) do
    local el = HHF.Elements[name]
    el.EventSet = {}
    for _, ev in ipairs(el.Events or {}) do el.EventSet[ev] = true end
  end
end
