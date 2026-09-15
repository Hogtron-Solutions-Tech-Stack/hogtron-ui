-- Capability flags per client. Everything aura-dependent checks these so a restricted
-- Forever API degrades gracefully instead of erroring.
HogHealsFrames = HogHealsFrames or {}
local HHF = HogHealsFrames

local Compat = {}
HHF.Compat = Compat

function Compat.Init()
  local id = WOW_PROJECT_ID
  Compat.projectId = id
  Compat.isEra = (id == WOW_PROJECT_CLASSIC)
  Compat.isTBC = (id == WOW_PROJECT_BURNING_CRUSADE_CLASSIC)
  local knownClassicLineage = Compat.isTBC or id == WOW_PROJECT_WRATH_CLASSIC
    or id == WOW_PROJECT_CATACLYSM_CLASSIC or id == WOW_PROJECT_MISTS_CLASSIC

  if Compat.isEra then
    Compat.hasNativeIncoming = false
    Compat.hasEarthShield = false
    Compat.auraFilterAllowed = true
  elseif knownClassicLineage then
    Compat.hasNativeIncoming = true
    Compat.hasEarthShield = true
    Compat.auraFilterAllowed = true
  else
    -- Unknown client (Forever until we learn its id): probe conservatively.
    Compat.hasNativeIncoming = type(UnitGetIncomingHeals) == "function"
    Compat.hasEarthShield = true
    -- Midnight-style restricted clients expose the private-aura API; treat its presence as "aura filtering restricted".
    Compat.auraFilterAllowed = not (type(C_UnitAuras) == "table" and type(C_UnitAuras.AddPrivateAuraAnchor) == "function")
  end
  Compat.hasGamepad = type(C_GamePad) == "table"
  Compat.hasLibHealComm = LibStub and LibStub("LibHealComm-4.0", true) ~= nil or false
  return Compat
end

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
