-- Debuffs on the cell: a short row of the unit's harmful auras (DoTs, curses, poisons, diseases, bleeds) with the
-- swipe running down and the 1 px edge in the dispel-type colour. Sean 2026-10-05: "overlays for dots and buffs
-- that they have, displayed on the frames".
--
-- This is NOT the dispel indicator (Dispel.lua): that one answers "can I fix it" with one big icon in the middle.
-- This row answers "what is on them" - everything, dispellable or not, so a healer sees the DoT ticking before
-- the health moves.
--
-- Secret-safe like Buffs.lua: fields go straight to widgets, a secret type gives the plain edge, a secret
-- canActivePlayerDispel is never branched on (filter "dispellable" keeps the aura when it cannot tell).
local HHF = HogHealsFrames
local HH = HogHeals
local R = HHF.AuraRow

local E = { Events = { "UNIT_AURA" } }
HHF.Debuffs = E

local function cfg() return HH.db.profile.frames.debuffs or {} end

--- The unit's harmful auras. filter: "all" | "dispellable" (only what my class can dispel, when the client says
-- so plainly) | "mine" (cast by me - a DoT class watching its own DoTs). Capped at max.
function E.Read(unit, filter, max)
  local out, seen = {}, {}
  local f = filter == "mine" and "HARMFUL|PLAYER" or "HARMFUL"
  for i = 1, 40 do
    local a = HHF.Compat.AuraData(unit, i, f)
    if type(a) ~= "table" then break end
    local k = R.Key(a)
    if not (k and seen[k]) then
      if k then seen[k] = true end
      local keep = true
      if filter == "dispellable" then
        local can = a.canActivePlayerDispel
        if not HHF.Compat.IsSecret(can) and can ~= true then keep = false end
      end
      if keep then
        a.index, a.filter = i, f
        out[#out + 1] = a
        if #out >= max then break end
      end
    end
  end
  return out
end

--- Draw a ready list (the element and test mode both come through here).
function E.Draw(button, list)
  return R.Row(button, "debuffs", list, cfg(), R.HarmfulEdge)
end

function E.Update(button, unit)
  local d = cfg()
  if UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
    return E.Draw(button, E.Read(unit, d.filter or "all", d.max or 3))
  end
  R.HideAll(button, "debuffs")
  return 0
end

function E.Hide(button) R.HideAll(button, "debuffs") end

HHF.UnitButton.RegisterElement("debuffs", E)
