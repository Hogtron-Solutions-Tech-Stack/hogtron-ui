-- Dispel indicator: only debuffs MY class can dispel. Style: icon | color | border. Plus a priority-debuff slot.
local HHF = HogHealsFrames
local HH = HogHeals

local E = { Events = { "UNIT_AURA" } }

local function playerClass()
  local _, c = UnitClass("player")
  return c
end

-- Cell-style "dispellable by me": Blizzard says so per aura (canActivePlayerDispel), no name or type comparisons.
local function scanHarmful(unit, priorityNames)
  local firstDispel, priority
  for i = 1, 40 do
    local a = HHF.Compat.AuraData(unit, i, "HARMFUL")
    if not a then break end
    if not firstDispel and a.canActivePlayerDispel then
      firstDispel = { name = a.name, icon = a.icon, type = a.dispelName, count = a.applications }
    end
    if not priority and priorityNames and a.name ~= nil and priorityNames[a.name] then
      priority = { name = a.name, icon = a.icon }
    end
  end
  return firstDispel, priority
end

--- Secret auras (restricted client, in combat): we may not test canActivePlayerDispel, but the client may. One
-- icon per harmful aura slot; alpha 1 if dispellable by me, 0 if not. Names are secret, so no priority slot.
local function updateSecret(button, unit)
  local icons = button.dispelIcons or { button.dispelIcon }
  for i, icon in ipairs(icons) do
    local a = HHF.Compat.AuraData(unit, i, "HARMFUL")
    if a and a.icon ~= nil and icon.SetAlphaFromBoolean then
      icon:SetTexture(a.icon)
      icon:SetAlphaFromBoolean(a.canActivePlayerDispel, 1, 0)
      icon:Show()
    else
      icon:Hide()
    end
  end
  button.dispelIcon.debuffType = nil
  button.dispelBorder:Hide()
  button.priorityIcon:Hide()
end

local function restoreHealthColor(button, unit)
  if button.dispelColored then
    button.dispelColored = false
    button.dispelColor = nil
    local h = HHF.Elements.health
    if h then pcall(h.Update, button, unit) end
  end
end

function E.Update(button, unit)
  local cfg = HH.db.profile.frames.dispel
  if HHF.Compat.AurasSecretNow() then
    restoreHealthColor(button, unit)
    return updateSecret(button, unit)
  end
  for i = 2, #(button.dispelIcons or {}) do button.dispelIcons[i]:Hide() end
  if button.dispelIcon.SetAlpha then button.dispelIcon:SetAlpha(1) end
  local prioSet
  if cfg.priorityDebuffs and #cfg.priorityDebuffs > 0 then
    prioSet = {}
    for _, n in ipairs(cfg.priorityDebuffs) do prioSet[n] = true end
  end
  local d, p = scanHarmful(unit, prioSet)

  -- priority slot
  if p and HH.db.profile.frames.indicators.priorityDebuff ~= false then
    button.priorityIcon:SetTexture(p.icon)
    button.priorityIcon.name = p.name
    button.priorityIcon:Show()
  else
    button.priorityIcon.name = nil
    button.priorityIcon:Hide()
  end

  if not d then
    button.dispelIcon.debuffType = nil
    button.dispelIcon:Hide()
    button.dispelBorder:Hide()
    restoreHealthColor(button, unit)
    return
  end

  local c = DebuffTypeColor[d.type] or DebuffTypeColor.none
  local style = cfg.style or "icon"
  button.dispelIcon.debuffType = d.type
  if style == "icon" then
    button.dispelIcon:SetTexture(d.icon)
    button.dispelIcon:Show()
    button.dispelBorder:Hide()
    restoreHealthColor(button, unit)
  elseif style == "border" then
    button.dispelBorder:SetColorTexture(c.r, c.g, c.b, 0.9)
    button.dispelBorder:Show()
    button.dispelIcon:Hide()
    restoreHealthColor(button, unit)
  else -- color
    button.dispelColored = true
    button.dispelColor = { c.r, c.g, c.b }
    button.health:SetStatusBarColor(c.r, c.g, c.b)
    button.dispelIcon:Hide()
    button.dispelBorder:Hide()
  end
end

function E.Hide(button)
  button.dispelIcon:Hide()
  for i = 2, #(button.dispelIcons or {}) do button.dispelIcons[i]:Hide() end
  button.dispelBorder:Hide()
  button.priorityIcon:Hide()
  if button.unit then restoreHealthColor(button, button.unit) end
end

HHF.UnitButton.RegisterElement("dispel", E)
