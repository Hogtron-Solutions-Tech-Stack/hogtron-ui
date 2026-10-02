-- Buffs on the cell: a short row of the unit's helpful auras at the bottom-left of the party / raid cell.
-- Sean 2026-10-02: long buffs (Power Word: Fortitude, Mark of the Wild) belong on the party frame and only
-- there; the plate above a head carries just the short ones (Plates/Hots.lua).
--
-- Secret-safe the way Units/Auras.lua is: icon and count go straight to widgets (a secret count is printed
-- with %s, never compared), the cooldown swipe is drawn only when start and duration are plain numbers.
-- The icons are plain Frames with the mouse OFF: the cell under them keeps every hover-cast binding.
local HHF = HogHealsFrames
local HH = HogHeals

local E = { Events = { "UNIT_AURA" } }
HHF.Buffs = E

local LINE = { 0.20, 0.20, 0.25 }
local CYAN = { 0.13, 0.83, 0.88 }

local function cfg() return HH.db.profile.frames.buffs or {} end
local function isSecret(v) return HHF.Compat.IsSecret(v) end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function str(v) if type(v) == "string" and not isSecret(v) then return v end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a = pcall(f, ...)
  if ok then return a end
end

--- A key that tells two readings of one aura apart without touching a secret: the plain name, else the instance id.
local function auraKey(a)
  local n = str(a.name)
  if n then return n end
  local id = num(a.auraInstanceID)
  if id then return "#" .. id end
  return nil
end

--- The unit's helpful auras by mode: "mine" = cast by me (HELPFUL|PLAYER); "all" = mine first and flagged, then
-- everyone else's. Capped at `max`. Each entry carries index + filter (for a tooltip) and `mine`.
function E.Read(unit, mode, max)
  local out, seen = {}, {}
  local function take(filter, mine)
    for i = 1, 40 do
      local a = HHF.Compat.AuraData(unit, i, filter)
      if type(a) ~= "table" then break end
      local k = auraKey(a)
      if not (k and seen[k]) then
        if k then seen[k] = true end
        a.mine, a.index, a.filter = mine, i, filter
        out[#out + 1] = a
        if #out >= max then return end
      end
    end
  end
  take("HELPFUL|PLAYER", true)
  if mode == "all" and #out < max then take("HELPFUL", false) end
  return out
end

local function icon(button, i)
  local b = button.buffs[i]
  if b then return b end
  b = CreateFrame("Frame", nil, button.overlay)
  b:EnableMouse(false)
  b:SetFrameLevel(button.overlay:GetFrameLevel() + 1)
  b.edge = b:CreateTexture(nil, "BACKGROUND")
  b.edge:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
  b.edge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
  b.edge:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints(b)
  if b.icon.SetTexCoord then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints(b)
  if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
  if b.cd.SetDrawEdge then b.cd:SetDrawEdge(false) end
  b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
  b.count:SetJustifyH("RIGHT")
  button.buffs[i] = b
  return b
end

local function paint(b, a, size, mineFlagged)
  b.aura = a
  b:SetSize(size, size)
  b.icon:SetTexture(a.icon)
  local n = num(a.applications)
  if n and n > 1 then b.count:SetText(tostring(n)) b.count:Show()
  elseif n == nil and a.applications ~= nil and isSecret(a.applications) then b.count:SetText(string.format("%s", a.applications)) b.count:Show()
  else b.count:SetText("") b.count:Hide() end
  if b.count.SetFont then call(b.count.SetFont, b.count, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", math.max(7, math.floor(size * 0.6)), "OUTLINE") end
  local c = (mineFlagged and a.mine) and CYAN or LINE
  b.edge:SetColorTexture(c[1], c[2], c[3], 1)
  local dur, exp = num(a.duration), num(a.expirationTime)
  if dur and exp and dur > 0 and b.cd.SetCooldown then
    b.cd:SetCooldown(exp - dur, dur)
    b.cd:Show()
  else
    b.cd:Hide()
  end
  b:Show()
end

function E.Update(button, unit)
  local d = cfg()
  button.buffs = button.buffs or {}
  local size, gap, max = d.size or 12, 1, d.max or 4
  local mode = d.filter or "mine"
  local shown = 0
  if UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
    for i, a in ipairs(E.Read(unit, mode, max)) do
      local b = icon(button, i)
      paint(b, a, size, mode == "all")
      b:ClearAllPoints()
      b:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2 + (i - 1) * (size + gap), d.offsetY or 5)
      shown = i
    end
  end
  for i = shown + 1, #button.buffs do button.buffs[i]:Hide() end
  button.buffCount = shown
  return shown
end

function E.Hide(button)
  for _, b in ipairs(button.buffs or {}) do b:Hide() end
  button.buffCount = 0
end

HHF.UnitButton.RegisterElement("buffs", E)
