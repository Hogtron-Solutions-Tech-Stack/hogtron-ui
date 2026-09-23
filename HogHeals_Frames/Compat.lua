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

--- UnitAura(unit, index, filter) for every client: the global was removed from modern clients.
-- Returns name, icon, count, dispelType, duration, expires, source.
function Compat.UnitAura(unit, index, filter)
  if type(UnitAura) == "function" then return UnitAura(unit, index, filter) end
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not get then return nil end
  local a = get(unit, index, filter)
  if not a then return nil end
  return a.name, a.icon, a.applications, a.dispelName, a.duration or 0, a.expirationTime, a.sourceUnit
end

--- One harmful/helpful aura as a table, on every client. Modern: C_UnitAuras.GetAuraDataByIndex (carries
-- canActivePlayerDispel, measured 2026-09-17). Legacy: UnitAura, with canActivePlayerDispel derived from our
-- class table. Returns nil past the last aura.
function Compat.AuraData(unit, index, filter)
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
