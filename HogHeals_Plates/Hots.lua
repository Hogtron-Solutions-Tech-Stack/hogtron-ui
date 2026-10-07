-- HoTs above friendly heads: my SHORT buffs (Renew, Regrowth, Rejuvenation, Riptide, Earth Shield...) in one row
-- centred above the plate's name. Blizzard's own buff row on the plate (left-aligned, every buff) goes quiet
-- while ours is on. Long buffs (Power Word: Fortitude, Mark of the Wild) stay OFF the plate - they live on the
-- party frame (Frames/Elements/Buffs.lua). Sean 2026-10-02: "only temporary buffs above their head... centre it".
--
-- Short = duration <= plates.buffs.maxDuration while the duration is a plain number. A SECRET duration (combat
-- on restricted clients) cannot be compared: that aura is SHOWN rather than lost - a healer's HoT must never
-- vanish because the client went quiet. No duration at all (0) = permanent = off the plate.
local HHP = HogHealsPlates
local HH = HogHeals

local Hots = {}
HHP.Hots = Hots

local LINE = { 0.05, 0.05, 0.06 }
Hots.BLIZZ = { "BuffFrame", "AurasFrame" }   -- Blizzard's buff row, by the names seen on the clients we run on

local function cfg() return HH.db.profile.plates.buffs or {} end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function bool(v) if isSecret(v) then return nil end return v and true or false end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
end

--- One aura by index through whichever reader this client has, as a table (modern field names), or nil.
function Hots.Aura(unit, i, filter)
  if type(C_UnitAuras) == "table" and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
    local a = call(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
    if type(a) == "table" then return a end
    return nil
  end
  if type(UnitAura) ~= "function" then return nil end
  local ok, name, icon, count, dtype, duration, expires, source = pcall(UnitAura, unit, i, filter)
  if not ok or name == nil then return nil end
  return { name = name, icon = icon, applications = count, dispelName = dtype, duration = duration, expirationTime = expires, sourceUnit = source }
end

--- My short buffs on the unit, in the client's order, capped. Returns the list and how many were skipped as long.
function Hots.Read(unit, d)
  local out, long = {}, 0
  local maxDur, max = d.maxDuration or 60, d.max or 6
  for i = 1, 40 do
    local a = Hots.Aura(unit, i, "HELPFUL|PLAYER")
    if not a then break end
    local dur = num(a.duration)
    local keep
    if dur ~= nil then keep = dur > 0 and dur <= maxDur
    else keep = a.duration ~= nil and isSecret(a.duration) end   -- secret: shown, never compared
    if keep then
      a.index, a.filter = i, "HELPFUL|PLAYER"
      out[#out + 1] = a
      if #out >= max then break end
    else
      long = long + 1
    end
  end
  return out, long
end

-- Blizzard's row: alpha 0 and kept there while ours is on (it re-shows itself on every aura update).
local quieted = setmetatable({}, { __mode = "k" })
local busy = setmetatable({}, { __mode = "k" })
local function quiet(f)
  if quieted[f] then return end
  quieted[f] = true
  call(f.SetAlpha, f, 0)
  if type(hooksecurefunc) == "function" and f.SetAlpha then
    pcall(hooksecurefunc, f, "SetAlpha", function(self)
      if busy[self] or not quieted[self] then return end
      busy[self] = true
      call(self.SetAlpha, self, 0)
      busy[self] = nil
    end)
  end
end
local function loud(f)
  if not quieted[f] then return end
  quieted[f] = nil
  call(f.SetAlpha, f, 1)
end

local function row(uf)
  local hh = uf.hh
  if hh.hots then return hh.hots end
  local r = CreateFrame("Frame", nil, uf)
  r:EnableMouse(false)
  r:SetFrameLevel((hh.overlay and hh.overlay:GetFrameLevel() or 1) + 2)
  r.icons = {}
  hh.hots = r
  return r
end

local function icon(r, i)
  local b = r.icons[i]
  if b then return b end
  b = CreateFrame("Frame", nil, r)
  b:EnableMouse(false)
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
  b.count = b:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
  b.count:SetJustifyH("RIGHT")
  r.icons[i] = b
  return b
end

local function paint(b, a, size)
  b.aura = a
  b:SetSize(size, size)
  b.icon:SetTexture(a.icon)
  local n = num(a.applications)
  if n and n > 1 then b.count:SetText(tostring(n)) b.count:Show()
  elseif n == nil and a.applications ~= nil and isSecret(a.applications) then b.count:SetText(string.format("%s", a.applications)) b.count:Show()
  else b.count:SetText("") b.count:Hide() end
  if b.count.SetFont then call(b.count.SetFont, b.count, HogHeals.Look.Font() or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", math.max(8, math.floor(size * 0.55)), "OUTLINE") end
  local dur, exp = num(a.duration), num(a.expirationTime)
  if dur and exp and dur > 0 and b.cd.SetCooldown then
    b.cd:SetCooldown(exp - dur, dur)
    b.cd:Show()
  else
    b.cd:Hide()
  end
  b:Show()
end

local function hideRow(hh)
  if not hh.hots then return end
  for _, b in ipairs(hh.hots.icons) do b:Hide() end
  hh.hots:Hide()
  hh.hotCount = 0
end

--- The row for one plate. Friendly plates only; enemy plates keep Blizzard's row untouched. Returns the count.
function Hots.Update(uf)
  local hh, d = uf.hh, cfg()
  if not hh or not hh.unit then return 0 end
  local unit = hh.unit
  local friendly = hh.nameOnly == true
  if not friendly then
    local f = bool(call(UnitIsFriend, "player", unit))
    if f == nil then local r = num(call(UnitReaction, unit, "player")) f = r ~= nil and r >= 5 end
    if bool(call(UnitCanAttack, "player", unit)) == true then f = false end
    friendly = f == true
  end
  local on = d.enabled ~= false and friendly
  for _, k in ipairs(Hots.BLIZZ) do
    local f = rawget(uf, k)
    if type(f) == "table" and f.SetAlpha then if on then quiet(f) else loud(f) end end
  end
  if not on then hideRow(hh) hh.hotCount = 0 return 0 end
  local r = row(uf)
  local size, gap = d.size or 18, 2
  local list, long = Hots.Read(unit, d)
  local n = #list
  r:SetSize(n > 0 and (n * size + (n - 1) * gap) or 1, size)
  r:ClearAllPoints()
  r:SetPoint("BOTTOM", uf.name or hh.bar or uf, "TOP", 0, d.gap or 2)   -- centred above the name
  for i, a in ipairs(list) do
    local b = icon(r, i)
    paint(b, a, size)
    b:ClearAllPoints()
    b:SetPoint("LEFT", r, "LEFT", (i - 1) * (size + gap), 0)
  end
  for i = n + 1, #r.icons do r.icons[i]:Hide() end
  if n > 0 then r:Show() else r:Hide() end
  hh.hotCount, hh.hotLong = n, long
  return n
end

--- Plate recycled: our row off, Blizzard's row back (the next occupant may be an enemy).
function Hots.Reset(uf)
  local hh = uf.hh
  if not hh then return end
  hideRow(hh)
  for _, k in ipairs(Hots.BLIZZ) do
    local f = rawget(uf, k)
    if type(f) == "table" then loud(f) end
  end
end

-- ------------------------------------------------------------------------------------------------ wiring
-- Self-wired, nothing edited in Plates.lua: after every Plates.Update / Plates.Reset ours runs, and UNIT_AURA on a
-- plate unit repaints that plate's row. (Plates.lua differs between branches; one hook here merges anywhere.)
local Plates = HHP.Plates
if type(Plates) == "table" and type(hooksecurefunc) == "function" then
  if type(Plates.Update) == "function" then
    hooksecurefunc(Plates, "Update", function(uf) local ok, err = pcall(Hots.Update, uf) if not ok then HH:LogError("plates hots: " .. tostring(err)) end end)
  end
  if type(Plates.Reset) == "function" then   -- newer Plates.lua has it; older ones are covered by the REMOVED event below
    hooksecurefunc(Plates, "Reset", function(uf) pcall(Hots.Reset, uf) end)
  end
end
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "UNIT_AURA")
pcall(ev.RegisterEvent, ev, "NAME_PLATE_UNIT_REMOVED")
ev:SetScript("OnEvent", function(_, e, unit)
  if type(Plates) ~= "table" or not unit then return end
  if e == "NAME_PLATE_UNIT_REMOVED" then
    local uf = Plates.FrameFor and Plates.FrameFor(unit)
    if uf and uf.hh then pcall(Hots.Reset, uf) end
    return
  end
  local uf = Plates.active and Plates.active[unit]
  if uf and uf.hh and uf.hh.unit then
    local ok, err = pcall(Hots.Update, uf)
    if not ok and err ~= Hots.lastError then Hots.lastError = err HH:LogError("plates hots UNIT_AURA: " .. tostring(err)) end
  end
end)
Hots.events = ev
