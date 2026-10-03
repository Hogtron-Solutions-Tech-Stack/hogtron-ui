-- HogUI Bars: our own action bars on LibActionButton-1.0 (the engine Bartender / ElvUI run on), Blizzard's hidden.
--
-- Sean 2026-10-02: "make the action bars section of HogUI a separate thing, kind of like Bartender: always show
-- the slots, turn them on and off, quick binding (click a button, hover a slot, hit the key)".
-- Design: docs/superpowers/specs/2026-10-02-hogui-bars-design.md. This file: the module shell (T0); bars, layout,
-- the Blizzard hide and the flat look land in T1, bind mode in Bind.lua (T2).
--
-- Secret-safe by construction: the lib owns every cooldown / count / range read; we do layout, config, bindings
-- and the look. Nothing here does arithmetic on button state.
HogHealsBars = HogHealsBars or {}
local HHB = HogHealsBars
local HH = HogHeals

local Bars = { bars = {}, found = {}, missing = {} }
HHB.Bars = Bars

local function cfg() return HH.db.profile.bars end
Bars.cfg = cfg

--- The lib, if this client loaded it (it is stubbed in the harness; real only in game).
function Bars.Lib()
  local lib = LibStub and LibStub("LibActionButton-1.0", true)
  return lib
end

-- ------------------------------------------------------------------------------------------------ module
local Module = {}
HHB.module = Module

function Module:OnEnable()
  local d = cfg()
  if not d or d.enabled == false then return end
  if not Bars.Lib() then
    HH:LogError("bars: LibActionButton-1.0 did not load on this client; HogUI Bars stay off")
    Bars.unavailable = true
    return
  end
  Bars.Apply("enable")
end

function Module:OnProfileChanged() Bars.Apply("profile") end

function Module:GetOptions()
  if HHB.Options and HHB.Options.Build then return HHB.Options.Build() end
end

function Module:SetLocked(locked)
  if Bars.SetUnlocked then Bars.SetUnlocked(not locked) end
end

--- Build or refresh everything. Filled in by T1; the shell just records that it ran.
function Bars.Apply(reason)
  Bars.lastApply = reason
  if Bars.Build then return Bars.Build(reason) end
end

HH:RegisterModule("Bars", Module)

HH:RegisterSlash("barsdiag", function()
  local f, m = {}, {}
  for k in pairs(Bars.found) do f[#f + 1] = k end
  for k in pairs(Bars.missing) do if not Bars.found[k] then m[#m + 1] = k end end
  table.sort(f) table.sort(m)
  HH:Print(("bars: lib %s; %d bars built; found %d Blizzard pieces, %d missing"):format(Bars.Lib() and "loaded" or "MISSING", #Bars.bars, #f, #m))
  if #m > 0 then HH:Print("  missing: " .. table.concat(m, ", ")) end
  for i, b in ipairs(Bars.bars) do
    if b.describe then HH:Print("  " .. b.describe()) end
  end
end, "what HogUI Bars found on this client (bars, slots, Blizzard pieces)")
