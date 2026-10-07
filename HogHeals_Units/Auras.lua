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
    return { icon = a.icon, count = a.applications, dispel = a.dispelName, duration = a.duration, expires = a.expirationTime, name = a.name,
      id = a.auraInstanceID, source = a.sourceUnit }
  end
  local name, icon, count, dispel, duration, expires, source = call(UnitAura, unit, i, filter)
  if name == nil then return nil end
  return { icon = icon, count = count, dispel = dispel, duration = duration, expires = expires, name = name, source = source }
end

--- A key that tells two readings of the same aura apart without touching a secret: the instance id, else name+icon.
local function auraKey(a)
  local id = num(a.id)
  if id then return "#" .. id end
  local n, ic = str(a.name), a.icon
  if n then return n .. "|" .. tostring(type(ic) == "number" and not isSecret(ic) and ic or "") end
  return nil
end

--- Debuffs for a frame by mode (Sean 2026-09-23, Warlock: "track my debuffs better"):
--   mine-first  mine (HARMFUL|PLAYER) first and flagged, then everyone else's       (default)
--   mine        only mine
--   all         the client's order, mine flagged
function Auras.Debuffs(unit, d)
  local mode, max = d.debuffFilter or "mine-first", d.maxDebuffs or 16
  local mine = Auras.Read(unit, "HARMFUL|PLAYER", max)
  for _, a in ipairs(mine) do a.mine = true end
  if mode == "mine" then return mine end
  local all = Auras.Read(unit, "HARMFUL", max)
  local seen = {}
  for _, a in ipairs(mine) do local k = auraKey(a) if k then seen[k] = true end end
  if mode == "all" then
    for _, a in ipairs(all) do local k = auraKey(a) if k and seen[k] then a.mine = true end end
    return all
  end
  local out = {}
  for _, a in ipairs(mine) do out[#out + 1] = a end
  for _, a in ipairs(all) do
    local k = auraKey(a)
    if not (k and seen[k]) then out[#out + 1] = a end
    if #out >= max then break end
  end
  return out
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
  -- the swipe shows the time; Blizzard's countdown numbers were far too big for a 22 px icon (in game 2026-09-23)
  if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
  if b.cd.SetDrawEdge then b.cd:SetDrawEdge(false) end
  b.count = b:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, 0)
  b.count:SetJustifyH("RIGHT")
  -- seconds left, our own text (Blizzard's countdown numbers were too big for these icons); only when the times are
  -- plain numbers - a secret expiry keeps the swipe and no text
  b.timer = b:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  b.timer:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.timer:SetTextColor(0.96, 0.92, 0.86)
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
  b.size = size
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
  b.expires = (dur and exp and dur > 0) and exp or nil
  if b.timer.SetFont then call(b.timer.SetFont, b.timer, HogHeals.Look.Font() or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", math.max(8, math.floor(size * 0.5)), "OUTLINE") end
  b.timer:SetText("")
  b:Show()
end

--- "12", "1m", "" - what the countdown shows for a remaining time.
function Auras.TimerText(remaining)
  if remaining == nil then return "" end
  if remaining <= 0 then return "" end
  if remaining < 60 then return string.format("%d", math.ceil(remaining)) end
  if remaining < 3600 then return string.format("%dm", math.floor(remaining / 60 + 0.5)) end
  return string.format("%dh", math.floor(remaining / 3600))
end

--- Countdown text on every icon with a plain expiry. Driven by a plain ticker frame (never an OnUpdate on the secure
-- unit buttons) at 5 Hz, only while any icon has a time to count.
function Auras.Tick(now)
  local any = false
  for _, f in pairs(HHU.Units.frames or {}) do
    if f.auras and f:IsShown() then
      local d = ucfg(f.unit)
      for _, key in ipairs({ "debuffs", "buffs" }) do
        for _, b in ipairs(f.auras[key]) do
          if b:IsShown() and b.expires and d.auraTimers ~= false then
            any = true
            b.timer:SetText(Auras.TimerText(b.expires - now))
          elseif b.timer then
            b.timer:SetText("")
          end
        end
      end
    end
  end
  return any
end

function Auras.StartTicker()
  if Auras.ticker then return Auras.ticker end
  local t = CreateFrame("Frame")
  local acc = 0
  t:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc < 0.2 then return end
    acc = 0
    Auras.Tick(GetTime())
  end)
  Auras.ticker = t
  return t
end

--- Rows of icons under the frame: debuffs first (what a healer looks for), buffs below. Returns counts (tests).
function Auras.Update(f)
  local d = ucfg(f.unit)
  local unit = f.unit
  -- only frames configured for auras (target, focus): the player's buffs live in Blizzard's buff area
  if d.debuffs == nil and d.buffs == nil then
    if f.auras then for _, k in ipairs({ "debuffs", "buffs" }) do for _, b in ipairs(f.auras[k]) do b:Hide() end end end
    return 0, 0
  end
  f.auras = f.auras or { buffs = {}, debuffs = {} }
  local shownD, shownB = 0, 0
  if d.debuffs ~= false and f:IsShown() then
    local size, mineSize = d.auraSize or 22, d.myDebuffSize or ((d.auraSize or 22) + 6)
    for i, a in ipairs(Auras.Debuffs(unit, d)) do
      local b = f.auras.debuffs[i] or newIcon(f, unit)
      f.auras.debuffs[i] = b
      paint(b, a, a.mine and mineSize or size)
      shownD = i
    end
  end
  for i = shownD + 1, #f.auras.debuffs do f.auras.debuffs[i]:Hide() end
  if d.buffs == true and f:IsShown() then
    for i, a in ipairs(Auras.Read(unit, "HELPFUL", d.maxBuffs or 16)) do
      local b = f.auras.buffs[i] or newIcon(f, unit)
      f.auras.buffs[i] = b
      paint(b, a, d.auraSize or 22)
      shownB = i
    end
  end
  for i = shownB + 1, #f.auras.buffs do f.auras.buffs[i]:Hide() end
  Auras.Layout(f)
  Auras.StartTicker()
  Auras.Tick(GetTime and GetTime() or 0)
  return shownD, shownB
end

--- Place the icons: per-row wrap, debuff rows then buff rows, growing downward from the frame's bottom edge.
-- Icons can differ in size (my debuffs are bigger): each row is as tall as its tallest icon, x runs cumulatively.
function Auras.Layout(f)
  if not f.auras then return end
  local d = ucfg(f.unit)
  local gap, perRow = 3, d.aurasPerRow or 8
  local y = -(gap + 2)
  for _, key in ipairs({ "debuffs", "buffs" }) do
    local n, x, rowH = 0, 0, 0
    for _, b in ipairs(f.auras[key]) do
      if b:IsShown() then
        if n > 0 and n % perRow == 0 then
          y = y - rowH - gap
          x, rowH = 0, 0
        end
        n = n + 1
        local size = b.size or d.auraSize or 22
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", x, y)
        x = x + size + gap
        if size > rowH then rowH = size end
      end
    end
    if n > 0 then y = y - rowH - gap - gap end
  end
end
