-- Buffs on the cell: a short row of the unit's helpful auras on the party / raid cell (bottom-left by default).
-- Sean 2026-10-02: long buffs (Power Word: Fortitude, Mark of the Wild) belong on the party frame and only
-- there; the plate above a head carries just the short ones (Plates/Hots.lua).
-- Sean 2026-10-05: "buffs that they have" - everyone's by default now, mine first with a cyan edge.
--
-- Drawing is AuraRow.lua (shared with the debuff row): icons with the mouse OFF so the cell keeps its hover-cast
-- bindings, secret fields handed to widgets and never compared.
local HHF = HogHealsFrames
local HH = HogHeals
local R = HHF.AuraRow

local E = { Events = { "UNIT_AURA" } }
HHF.Buffs = E

local function cfg()
  local d = HH.db.profile.frames.buffs or {}
  -- offsetY was the only position setting before the anchor / x / y trio; honour a saved one
  if d.y == nil and d.offsetY ~= nil then d.y = d.offsetY end
  return d
end

--- The unit's helpful auras by mode: "mine" = cast by me (HELPFUL|PLAYER); "all" = mine first and flagged, then
-- everyone else's. Capped at `max`. Each entry carries index + filter (for a tooltip) and `mine`.
function E.Read(unit, mode, max)
  local out, seen = {}, {}
  local function take(filter, mine)
    for i = 1, 40 do
      local a = HHF.Compat.AuraData(unit, i, filter)
      if type(a) ~= "table" then break end
      local k = R.Key(a)
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

--- Draw a ready list (the element and test mode both come through here). Mine get the cyan edge in "all" mode.
function E.Draw(button, list, mode)
  local flag = mode == "all"
  local n = R.Row(button, "buffs", list, cfg(), function(a) return (flag and a.mine) and R.CYAN or R.LINE end)
  button.buffCount = n   -- the name the first version used; Plates and tests read it
  return n
end

function E.Update(button, unit)
  local d = cfg()
  local mode = d.filter or "all"
  if UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
    return E.Draw(button, E.Read(unit, mode, d.max or 4), mode)
  end
  R.HideAll(button, "buffs")
  button.buffCount = 0
  return 0
end

function E.Hide(button) R.HideAll(button, "buffs") button.buffCount = 0 end

HHF.UnitButton.RegisterElement("buffs", E)
