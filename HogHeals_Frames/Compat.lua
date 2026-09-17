-- Capability flags per client. Everything aura-dependent checks these so a restricted
-- Forever API degrades gracefully instead of erroring.
HogHealsFrames = HogHealsFrames or {}
local HHF = HogHealsFrames

local Compat = {}
local FOREVER_MIN_TOC = 16000
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
  Compat.hasGamepad = type(C_GamePad) == "table"
  Compat.hasLibHealComm = LibStub and LibStub("LibHealComm-4.0", true) ~= nil or false
  return Compat
end

function Compat.Describe()
  local keys = { "build", "projectId", "isEra", "isTBC", "isForever", "hasNativeIncoming", "hasEarthShield", "auraFilterAllowed", "hasGamepad", "hasLibHealComm" }
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. tostring(Compat[k]) end
  return out
end

HogHeals:RegisterSlash("apicheck", function()
  Compat.Init()
  HogHeals:Print("API capability check (screenshot this on beta):")
  for _, line in ipairs(Compat.Describe()) do HogHeals:Print("  " .. line) end
end, "print client API capability flags")

--- Turn off indicators that need data this client refuses to give.
function Compat.Degrade(frames)
  if Compat.auraFilterAllowed then return frames end
  local ind = frames.indicators
  ind.dispel = false
  ind.missingBuffs = false
  ind.myShield = false
  ind.healPrediction = false
  ind.priorityDebuff = false
  frames.degraded = true
  return frames
end
