-- Dispel indicator: only debuffs MY class can dispel. Style: icon | color | border. Plus a priority-debuff slot.
local HHF = HogHealsFrames
local HH = HogHeals

local E = { Events = { "UNIT_AURA" } }

local function playerClass()
  local _, c = UnitClass("player")
  return c
end

local function scanHarmful(unit, priorityNames)
  local class = playerClass()
  local firstDispel, priority
  local i = 1
  while true do
    local name, icon, count, dtype = UnitAura(unit, i, "HARMFUL")
    if not name then break end
    if not firstDispel and dtype and HH.CanDispel(class, dtype) then
      firstDispel = { name = name, icon = icon, type = dtype, count = count }
    end
    if not priority and priorityNames and priorityNames[name] then
      priority = { name = name, icon = icon }
    end
    i = i + 1
    if i > 40 then break end
  end
  return firstDispel, priority
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
  button.dispelBorder:Hide()
  button.priorityIcon:Hide()
  if button.unit then restoreHealthColor(button, button.unit) end
end

HHF.UnitButton.RegisterElement("dispel", E)
