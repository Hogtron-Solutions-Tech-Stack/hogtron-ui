-- Capability flags per client. Everything aura-dependent checks these so a restricted
-- Forever API degrades gracefully instead of erroring.
HogHealsFrames = HogHealsFrames or {}
local HHF = HogHealsFrames

local Compat = {}
local FOREVER_MIN_TOC = 16000
Compat.unknownEvents = {}   -- event names this client refused; filled by UnitButton, reported by Describe
HHF.Compat = Compat

function Compat.Init()
  local id = WOW_PROJECT_ID
  Compat.projectId = id
  -- Project ids disagree between addons on Anniversary (Cell keys TBC off id 5, LibHealComm off the
  -- build under id 2). Trust the build number first, project id second.
  local _, _, _, toc = GetBuildInfo()
  local major = math.floor((tonumber(toc) or 0) / 10000)
  Compat.build = toc
  -- WoW: Forever ships as 1.60.x (beta 2026-09-17: 1.60.1.69893, toc 160xx). Same major as Classic
  -- Era (1.13-1.15, toc 113xx-115xx), so split on the minor or Forever gets Era's "aura API is open"
  -- assumption without ever being probed.
  local n = tonumber(toc) or 0
  Compat.isForever = (n >= FOREVER_MIN_TOC and n < 20000)
  Compat.isEra = (major == 1 and not Compat.isForever) or (major == 0 and id == WOW_PROJECT_CLASSIC)
  Compat.isTBC = (major == 2) or (major == 0 and id == WOW_PROJECT_BURNING_CRUSADE_CLASSIC)
  local knownClassicLineage = Compat.isTBC or major == 3 or major == 4 or major == 5
    or id == WOW_PROJECT_WRATH_CLASSIC or id == WOW_PROJECT_CATACLYSM_CLASSIC or id == WOW_PROJECT_MISTS_CLASSIC

  if Compat.isEra then
    Compat.hasNativeIncoming = false
    Compat.hasEarthShield = false
    Compat.auraFilterAllowed = true
  elseif knownClassicLineage then
    Compat.hasNativeIncoming = true
    Compat.hasEarthShield = true
    Compat.auraFilterAllowed = true
  else
    -- Forever, or any client we do not recognise: probe, never assume.
    Compat.hasNativeIncoming = type(UnitGetIncomingHeals) == "function"
    Compat.hasEarthShield = true
    -- Midnight-style restricted clients expose the private-aura API; treat its presence as "aura filtering restricted".
    Compat.auraFilterAllowed = not (type(C_UnitAuras) == "table" and type(C_UnitAuras.AddPrivateAuraAnchor) == "function")
  end
  -- Secret values (seen on Forever beta 1.60.1): unit health / power / names / incoming heals come back
  -- opaque. Widgets accept them; arithmetic, comparison, # and concat throw. Elements that cannot work
  -- without maths are blocked at runtime. The saved profile is never touched, so the same profile is whole
  -- again on an open client.
  Compat.secretValues = type(issecretvalue) == "function"
  Compat.blocked = {}
  if Compat.secretValues then
    Compat.blocked.healPrediction = "needs arithmetic on incoming-heal amounts, which are secret on this client"
    -- dispel is NOT blocked any more: it runs on aura.canActivePlayerDispel (measured on the Forever beta) and,
    -- when aura fields are secret, hands the boolean to the widget (SetAlphaFromBoolean).
    local why = "aura names are secret on this client; needs a rebuild on Blizzard's filtered aura API"
    Compat.blocked.missingBuffs, Compat.blocked.myShield = why, why
  end
  Compat.hasGamepad = type(C_GamePad) == "table"
  Compat.hasLibHealComm = LibStub and LibStub("LibHealComm-4.0", true) ~= nil or false
  return Compat
end

function Compat.Describe()
  local keys = { "build", "projectId", "isEra", "isTBC", "isForever", "hasNativeIncoming", "hasEarthShield", "auraFilterAllowed", "secretValues", "hasGamepad", "hasLibHealComm" }
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. tostring(Compat[k]) end
  local ev = {}
  for name in pairs(Compat.unknownEvents) do ev[#ev + 1] = name end
  table.sort(ev)
  out[#out + 1] = "unknownEvents=" .. table.concat(ev, ",")
  return out
end

HogHeals:RegisterSlash("apicheck", function()
  Compat.Init()
  HogHeals:Print("API capability check (screenshot this on beta):")
  for _, line in ipairs(Compat.Describe()) do HogHeals:Print("  " .. line) end
end, "print client API capability flags")

-- ---------------------------------------------------------------- aura memo (perf, 2026-10-05)
-- One UNIT_AURA on a cell runs every aura element (buffs, debuffs, dispel, missing buffs, shield): 4-5 full walks of
-- the same 40 slots. While a dispatch is open (UnitButton.OnEvent / UpdateAll) every (unit, filter, index) read is
-- kept and handed back to the next element; the memo is dropped when the dispatch ends, so nothing goes stale.
-- Elements that mutate the returned table (Buffs sets mine / index / filter) are harmless: same event, same moment.
Compat.batchDepth = 0
function Compat.BeginAuraBatch()
  Compat.batchDepth = Compat.batchDepth + 1
  Compat.batch = Compat.batch or {}
end
function Compat.EndAuraBatch()
  Compat.batchDepth = Compat.batchDepth - 1
  if Compat.batchDepth <= 0 then Compat.batchDepth = 0 Compat.batch = nil end
end
local function memo(unit, key)
  local b = Compat.batch
  if not b then return nil end
  local u = b[unit]
  if not u then u = {} b[unit] = u end
  local f = u[key]
  if not f then f = {} u[key] = f end
  return f
end
Compat.memoHits = 0

--- UnitAura(unit, index, filter) for every client: the global was removed from modern clients.
-- Returns name, icon, count, dispelType, duration, expires, source.
function Compat.UnitAura(unit, index, filter)
  local slot = memo(unit, "ua:" .. tostring(filter))
  if slot then
    local c = slot[index]
    if c ~= nil then
      Compat.memoHits = Compat.memoHits + 1
      if c == false then return nil end
      return c[1], c[2], c[3], c[4], c[5], c[6], c[7]
    end
  end
  local name, icon, count, dtype, duration, expires, source
  if type(UnitAura) == "function" then
    name, icon, count, dtype, duration, expires, source = UnitAura(unit, index, filter)
  else
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    local a = get and get(unit, index, filter)
    if a then name, icon, count, dtype, duration, expires, source = a.name, a.icon, a.applications, a.dispelName, a.duration or 0, a.expirationTime, a.sourceUnit end
  end
  if slot then slot[index] = name and { name, icon, count, dtype, duration, expires, source } or false end
  if not name then return nil end
  return name, icon, count, dtype, duration, expires, source
end

--- One harmful/helpful aura as a table, on every client. Modern: C_UnitAuras.GetAuraDataByIndex (carries
-- canActivePlayerDispel, measured 2026-09-17). Legacy: UnitAura, with canActivePlayerDispel derived from our
-- class table. Returns nil past the last aura.
local function readAuraData(unit, index, filter)
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if type(get) == "function" then
    local a = get(unit, index, filter)
    if type(a) ~= "table" then return nil end
    if a.canActivePlayerDispel == nil and not Compat.IsSecret(a.dispelName) then
      local _, class = UnitClass("player")
      a.canActivePlayerDispel = HogHeals.CanDispel(class, a.dispelName)
    end
    return a
  end
  if type(UnitAura) ~= "function" then return nil end
  local name, icon, count, dtype, duration, expires, source, _, _, spellId = UnitAura(unit, index, filter)
  if not name then return nil end
  local _, class = UnitClass("player")
  return { name = name, icon = icon, applications = count, dispelName = dtype, duration = duration, expirationTime = expires,
    sourceUnit = source, spellId = spellId, canActivePlayerDispel = HogHeals.CanDispel(class, dtype) }
end

function Compat.AuraData(unit, index, filter)
  local slot = memo(unit, "ad:" .. tostring(filter))
  if slot then
    local c = slot[index]
    if c ~= nil then
      Compat.memoHits = Compat.memoHits + 1
      if c == false then return nil end
      return c
    end
  end
  local a = readAuraData(unit, index, filter)
  if slot then slot[index] = a or false end
  return a
end

--- True while the client is handing out SECRET aura fields (no `if` on them; widgets only).
function Compat.AurasSecretNow()
  if not Compat.secretValues then return false end
  local f = C_Secrets and C_Secrets.ShouldAurasBeSecret
  if type(f) ~= "function" then return true end
  local ok, r = pcall(f)
  return ok and r and true or false
end

--- True when v is a secret value (always false on clients without the restricted API).
function Compat.IsSecret(v)
  local f = issecretvalue
  if type(f) ~= "function" then return false end
  return f(v) and true or false
end

-- Class tokens, remembered. 2026-09-22 in game (Forever beta): the player frame's class-coloured health bar went
-- GREY in combat. The client has C_Secrets.ShouldUnitIdentityBeSecret: in combat UnitClass can come back secret or
-- empty, and "no readable class" fell through to the grey default. A unit's class never changes, so every class we
-- CAN read is kept (by GUID and by name - names were measured NOT secret) and handed back while it is hidden.
Compat.classByGUID, Compat.classByName = Compat.classByGUID or {}, Compat.classByName or {}

local function plainString(v)
  if type(v) ~= "string" or Compat.IsSecret(v) or v == "" then return nil end
  return v
end

--- Class token ("SHAMAN") for a unit, readable in combat too when we have seen it before. nil only for a unit whose
-- class we have never been able to read.
function Compat.ClassOf(unit)
  if not unit then return nil end
  local okC, _, class = pcall(UnitClass, unit)
  class = okC and plainString(class) or nil
  local okG, guid = pcall(UnitGUID, unit)
  guid = okG and plainString(guid) or nil
  local okN, name = pcall(UnitName, unit)
  name = okN and plainString(name) or nil
  if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
    if guid then Compat.classByGUID[guid] = class end
    if name then Compat.classByName[name] = class end
    if unit == "player" then Compat.playerClass = class end
    return class
  end
  if unit == "player" and Compat.playerClass then return Compat.playerClass end
  return (guid and Compat.classByGUID[guid]) or (name and Compat.classByName[name]) or nil
end

--- Reason string when this client cannot support an element, else nil. Runtime only, never saved.
function Compat.Blocked(name)
  return Compat.blocked and Compat.blocked[name] or nil
end

-- ------------------------------------------------------------------------------------------------ aura reader probe
-- Sean 2026-10-17, in a party: "GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by
-- 'HogHeals_Frames'" - in combat the client refuses that reader to us, so buffs / debuffs / the dispel highlight go
-- blank. This client carries other readers (C_UnitAuras.GetUnitAuras, GetAuraSlots + GetAuraDataBySlot, the
-- Buff/Debuff index readers, AuraUtil.ForEachAura); which of them answer in that moment cannot be tested outside the
-- game. On a refusal each is tried ONCE (pcall, nothing compared or branched on) and what it gave back - an error, a
-- type, which fields came back secret - is written to diag.auraReaders. At most once a minute, five records a session.
Compat.PROBE_EVERY, Compat.PROBE_MAX = 60, 5
Compat.probes = 0

local function describe(v)
  if Compat.IsSecret(v) then return "secret" end
  if type(v) ~= "table" then return type(v) end
  local parts, n = {}, 0
  for k, x in pairs(v) do
    n = n + 1
    if n <= 14 then parts[#parts + 1] = tostring(k) .. "=" .. (Compat.IsSecret(x) and "secret" or type(x)) end
  end
  table.sort(parts)
  return ("table(%d) %s"):format(n, table.concat(parts, " "))
end

local function try(label, f, ...)
  if type(f) ~= "function" then return label .. ": absent" end
  local r = { pcall(f, ...) }
  if not r[1] then return label .. ": ERR " .. tostring(r[2]):gsub("\n.*", ""):sub(1, 110) end
  local shown = {}
  for i = 2, math.min(#r, 4) do shown[#shown + 1] = describe(r[i]) end
  return label .. ": ok " .. (#shown > 0 and table.concat(shown, " | ") or "(nothing)")
end

-- 2026-10-18, first real data (Sean's party fights, diag.auraReaders x3): in combat EVERY index / slot reader refuses
-- ("cannot be accessed when secret while tainted"), the player's own debuffs included, and UnitAura is absent. Modern
-- secret-value clients hand addons auras by INSTANCE ID instead - UNIT_AURA's payload carries the ids - and this client
-- has C_UnitAuras.IsAuraFilteredOutByInstanceID. So the probe also records the client's whole C_UnitAuras list, what the
-- last UNIT_AURA for that unit carried, and the instance-id readers tried with an id from it. The listener keeps one
-- payload per group unit (a reference, nothing read) and stops once the probe has its five records.
Compat.lastAuraInfo = {}

function Compat.NoteAuraEvent(unit, info)
  if type(unit) ~= "string" or not (unit == "player" or unit:find("^party") or unit:find("^raid")) then return end
  Compat.lastAuraInfo[unit] = info
end

function Compat.StartAuraNotes()
  if Compat.auraNotes or type(CreateFrame) ~= "function" then return end
  local f = CreateFrame("Frame")
  if not pcall(f.RegisterEvent, f, "UNIT_AURA") then return end
  f:SetScript("OnEvent", function(self, _, unit, info)
    if Compat.probes >= Compat.PROBE_MAX then self:UnregisterAllEvents() return end
    pcall(Compat.NoteAuraEvent, unit, info)
  end)
  Compat.auraNotes = f
end

--- A plain aura instance id out of a UNIT_AURA payload (added auras first, then updated ids), or nil.
function Compat.AuraIDFrom(info)
  if type(info) ~= "table" or Compat.IsSecret(info) then return nil end
  local ok, id = pcall(function()
    for _, key in ipairs({ "addedAuras", "updatedAuraInstanceIDs" }) do
      local list = info[key]
      if type(list) == "table" and not Compat.IsSecret(list) then
        for i = 1, 40 do
          local x = list[i]
          if x == nil then break end
          local v = x
          if type(x) == "table" and not Compat.IsSecret(x) then v = x.auraInstanceID end
          if type(v) == "number" and not Compat.IsSecret(v) then return v end
        end
      end
    end
  end)
  return ok and id or nil
end

function Compat.ProbeAuraReaders(unit, filter)
  filter = filter or "HARMFUL"
  local now = type(GetTime) == "function" and GetTime() or 0
  if Compat.probes >= Compat.PROBE_MAX or (Compat.lastProbe and now - Compat.lastProbe < Compat.PROBE_EVERY) then return nil end
  Compat.lastProbe, Compat.probes = now, Compat.probes + 1
  local C = type(C_UnitAuras) == "table" and C_UnitAuras or {}
  local lines = {
    try("GetAuraDataByIndex", C.GetAuraDataByIndex, unit, 1, filter),
    try("GetUnitAuras", C.GetUnitAuras, unit, filter),
    try(filter == "HELPFUL" and "GetBuffDataByIndex" or "GetDebuffDataByIndex", filter == "HELPFUL" and C.GetBuffDataByIndex or C.GetDebuffDataByIndex, unit, 1),
  }
  -- slots: the first slot number, then that slot's data
  local slotLine = "GetAuraSlots: absent"
  if type(C.GetAuraSlots) == "function" then
    local r = { pcall(C.GetAuraSlots, unit, filter) }
    if not r[1] then slotLine = "GetAuraSlots: ERR " .. tostring(r[2]):gsub("\n.*", ""):sub(1, 110)
    else
      local slot = r[3]
      slotLine = ("GetAuraSlots: ok %d value(s), first slot %s"):format(#r - 1, describe(slot))
      if not Compat.IsSecret(slot) and slot ~= nil then lines[#lines + 1] = try("GetAuraDataBySlot", C.GetAuraDataBySlot, unit, slot) end
    end
  end
  lines[#lines + 1] = slotLine
  local AU = rawget(_G, "AuraUtil")
  if type(AU) == "table" and type(AU.ForEachAura) == "function" then
    local seen
    local ok, err = pcall(AU.ForEachAura, unit, filter, 1, function(a) seen = describe(a) return true end, true)
    lines[#lines + 1] = ok and ("AuraUtil.ForEachAura: ok " .. tostring(seen or "(no aura)")) or ("AuraUtil.ForEachAura: ERR " .. tostring(err):gsub("\n.*", ""):sub(1, 110))
  else
    lines[#lines + 1] = "AuraUtil.ForEachAura: absent"
  end
  lines[#lines + 1] = try("UnitAura", rawget(_G, "UnitAura"), unit, 1, filter)
  -- by instance id (2026-10-18): what the last UNIT_AURA carried, and the readers that take its ids
  local info = Compat.lastAuraInfo[unit]
  lines[#lines + 1] = "last UNIT_AURA payload: " .. (info ~= nil and describe(info) or "none seen")
  local id = Compat.AuraIDFrom(info)
  lines[#lines + 1] = "instance id from it: " .. (id and tostring(id) or "none plain")
  if id then
    lines[#lines + 1] = try("GetAuraDataByAuraInstanceID", C.GetAuraDataByAuraInstanceID, unit, id)
    lines[#lines + 1] = try("IsAuraFilteredOutByInstanceID", C.IsAuraFilteredOutByInstanceID, unit, id, filter)
  end
  lines[#lines + 1] = try("GetUnitAuraInstanceIDs", C.GetUnitAuraInstanceIDs, unit, filter)
  lines[#lines + 1] = try("canaccesssecrets", rawget(_G, "canaccesssecrets"))
  local CS = rawget(_G, "C_Secrets")
  lines[#lines + 1] = try("C_Secrets.ShouldAurasBeSecret", type(CS) == "table" and CS.ShouldAurasBeSecret or nil)
  if not Compat.auraKeysNoted then                      -- the client's whole aura API, once a session
    Compat.auraKeysNoted = true
    local ks = {}
    for k, v in pairs(C) do if type(v) == "function" then ks[#ks + 1] = tostring(k) end end
    table.sort(ks)
    lines[#lines + 1] = "C_UnitAuras: " .. (#ks > 0 and table.concat(ks, ",") or "(none)")
  end
  local rec = { at = date and date("%Y-%m-%d %H:%M:%S") or "?", unit = tostring(unit), filter = filter,
    combat = (type(InCombatLockdown) == "function" and InCombatLockdown()) and "yes" or "no", lines = lines }
  local g = HogHeals and HogHeals.db and HogHeals.db.global
  if g then
    g.diag = g.diag or {}
    local list = g.diag.auraReaders or {}
    table.insert(list, 1, rec)
    while #list > Compat.PROBE_MAX do table.remove(list) end
    g.diag.auraReaders = list
  end
  return rec
end

Compat.StartAuraNotes()
