-- Buffs and debuffs under a unit frame (target and focus by default): icon, stack count, dispel-type outline,
-- cooldown swipe when the client lets us read the times.
--
-- Aura data on restricted clients: the modern reader is C_UnitAuras.GetAuraDataByIndex; the legacy one is UnitAura
-- (nil on the Forever beta). Every field may be a SECRET in combat: icons and counts go straight to widgets, the
-- swipe is only drawn when start and duration are plain numbers, dispel colours only when the type is a plain
-- string. Hovering an icon shows the client's own aura tooltip.
HogHealsUnits = HogHealsUnits or {}
local HHU = HogHealsUnits
local HH = HogHeals

local Auras = {}
HHU.Auras = Auras

local LINE = { 0.20, 0.20, 0.25 }
local function cfg() return HH.db.profile.units end
local function ucfg(unit) return HH.db.profile.units[unit] end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function str(v) if type(v) == "string" and not isSecret(v) then return v end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d, e, g = pcall(f, ...)
  if ok then return a, b, c, d, e, g end
end

--- One aura by index through whichever reader this client has: { icon, count, dispel, duration, expires } or nil.
function Auras.Get(unit, i, filter)
  if type(C_UnitAuras) == "table" and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
    local a = call(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
    if type(a) ~= "table" then return nil end
    return { icon = a.icon, count = a.applications, dispel = a.dispelName, duration = a.duration, expires = a.expirationTime, name = a.name }
  end
  local name, icon, count, dispel, duration, expires = call(UnitAura, unit, i, filter)
  if name == nil then return nil end
  return { icon = icon, count = count, dispel = dispel, duration = duration, expires = expires, name = name }
end

function Auras.Read(unit, filter, max)
  local out = {}
  for i = 1, max do
    local a = Auras.Get(unit, i, filter)
    if not a then break end
    a.index, a.filter = i, filter
    out[#out + 1] = a
  end
  return out
end

-- ------------------------------------------------------------------------------------------------ icons
local function newIcon(parent, unit)
  local b = CreateFrame("Button", nil, parent)
  b.unit = unit
  b.edge = b:CreateTexture(nil, "BACKGROUND")
  b.edge:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
  b.edge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
  b.edge:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints(b)
  if b.icon.SetTexCoord then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end   -- trim Blizzard's icon border
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints(b)
  if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(false) end
  b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, 0)
  b.count:SetJustifyH("RIGHT")
  b:SetScript("OnEnter", function(self)
    if not GameTooltip or not self.aura then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    call(GameTooltip.SetUnitAura, GameTooltip, self.unit, self.aura.index, self.aura.filter)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return b
end

local function paint(b, a, size)
  b.aura = a
  b:SetSize(size, size)
  b.icon:SetTexture(a.icon)
  local n = num(a.count)
  if n and n > 1 then b.count:SetText(tostring(n)) b.count:Show()
  elseif n == nil and a.count ~= nil and isSecret(a.count) then b.count:SetText(string.format("%s", a.count)) b.count:Show()
  else b.count:SetText("") b.count:Hide() end
  local dispel = str(a.dispel)
  local c = dispel and DebuffTypeColor and DebuffTypeColor[dispel]
  if c then b.edge:SetColorTexture(c.r, c.g, c.b, 1) else b.edge:SetColorTexture(LINE[1], LINE[2], LINE[3], 1) end
  local dur, exp = num(a.duration), num(a.expires)
  if dur and exp and dur > 0 and b.cd.SetCooldown then
    b.cd:SetCooldown(exp - dur, dur)
    b.cd:Show()
  else
    b.cd:Hide()
  end
  b:Show()
end

--- Rows of icons under the frame: debuffs first (what a healer looks for), buffs below. Returns counts (tests).
function Auras.Update(f)
  local d = ucfg(f.unit)
  local unit = f.unit
  f.auras = f.auras or { buffs = {}, debuffs = {} }
  local shownD, shownB = 0, 0
  if d.debuffs ~= false and f:IsShown() then
    for i, a in ipairs(Auras.Read(unit, "HARMFUL", d.maxDebuffs or 16)) do
      local b = f.auras.debuffs[i] or newIcon(f, unit)
      f.auras.debuffs[i] = b
      paint(b, a, d.auraSize or 22)
      shownD = i
    end
  end
  for i = shownD + 1, #f.auras.debuffs do f.auras.debuffs[i]:Hide() end
  if d.buffs ~= false and f:IsShown() then
    for i, a in ipairs(Auras.Read(unit, "HELPFUL", d.maxBuffs or 16)) do
      local b = f.auras.buffs[i] or newIcon(f, unit)
      f.auras.buffs[i] = b
      paint(b, a, d.auraSize or 22)
      shownB = i
    end
  end
  for i = shownB + 1, #f.auras.buffs do f.auras.buffs[i]:Hide() end
  Auras.Layout(f)
  return shownD, shownB
end

--- Place the icons: per-row wrap, debuff rows then buff rows, growing downward from the frame's bottom edge.
function Auras.Layout(f)
  if not f.auras then return end
  local d = ucfg(f.unit)
  local size, gap, perRow = d.auraSize or 22, 3, d.aurasPerRow or 8
  local y = -(gap + 2)
  for _, key in ipairs({ "debuffs", "buffs" }) do
    local n = 0
    for i, b in ipairs(f.auras[key]) do
      if b:IsShown() then
        n = n + 1
        local col, row = (n - 1) % perRow, math.floor((n - 1) / perRow)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", col * (size + gap), y - row * (size + gap))
      end
    end
    if n > 0 then y = y - (math.floor((n - 1) / perRow) + 1) * (size + gap) - gap end
  end
end
