-- Old folders after the 2026-10-15 rename. An unzip over an old install (or a client that did not remove them)
-- leaves HogHeals_Bars, HogHeals_Skin ... next to the new HogTron_Bars, HogTron_Skin ...: both copies load and
-- every module runs twice. At login: any old module folder that is loaded is switched off for the next reload and
-- named in chat, once per session. HogHeals (the settings bridge) and HogHeals_Frames are not old: they stay.
local ADDON, ns = ...
local HH = HogHeals

local Legacy = {}
HH.Legacy = Legacy
Legacy.OLD = { "HogHeals_Atlas", "HogHeals_Bars", "HogHeals_Chat", "HogHeals_HUD", "HogHeals_Meter", "HogHeals_Plates",
  "HogHeals_Quests", "HogHeals_Skin", "HogHeals_Training", "HogHeals_Units", "HogHeals_Journal" }

local function api(name) return (C_AddOns and C_AddOns[name]) or _G[name] end

--- Old module folders loaded this session (the ones that must go). Returns a list of names.
function Legacy.Loaded()
  local isLoaded = api("IsAddOnLoaded")
  local out = {}
  if type(isLoaded) ~= "function" then return out end
  for _, n in ipairs(Legacy.OLD) do
    local ok, yes = pcall(isLoaded, n)
    if ok and yes then out[#out + 1] = n end
  end
  return out
end

function Legacy.Check()
  local old = Legacy.Loaded()
  if #old == 0 then return old end
  local disable = api("DisableAddOn")
  for _, n in ipairs(old) do if type(disable) == "function" then pcall(disable, n) end end
  HH:Print("|cffF5A623Old HogTron UI folders are still installed:|r " .. table.concat(old, ", ")
    .. ". They are switched off now (/reload). Delete them from Interface\AddOns: their new copies are the HogTron_ folders.")
  return old
end

local f = CreateFrame("Frame")
pcall(f.RegisterEvent, f, "PLAYER_LOGIN")
f:SetScript("OnEvent", function() pcall(Legacy.Check) end)
