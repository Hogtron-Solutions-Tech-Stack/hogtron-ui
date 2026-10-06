-- Weapon trainers by city: who teaches which weapon skill, and the old game's reputation discount at a city's
-- trainer (friendly 5%, honored 10%, revered 15%, exalted 20%). Sean 2026-10-06, from the "What's Training?"
-- clip: "all available weapon skills that I can go train, where to get them, and any reputation discounts".
--
-- SOURCE: the 2004-2006 game (Classic), from memory. NOT VERIFIED ON FOREVER: a trainer may have moved or teach
-- more; the window says "old list" on every row. Spell / rank data is never shipped here - that is learned at the
-- trainer (Training.lua).
HogHealsTraining = HogHealsTraining or {}
local T = HogHealsTraining
T.Data = T.Data or {}

local function tr(city, name, where, skills) return { city = city, name = name, where = where, skills = skills } end

T.Data.WeaponTrainers = {
  A = {
    tr("Stormwind City", "Woo Ping", "Weapons Master, the Canals (Trade District side)", { "Crossbows", "Daggers", "Polearms", "Staves", "Swords", "Two-Handed Swords" }),
    tr("Ironforge", "Bixi Wobblebonk", "Military Ward", { "Crossbows", "Daggers", "Thrown" }),
    tr("Ironforge", "Buliwyf Stonehand", "Military Ward", { "Axes", "Fist Weapons", "Guns", "Maces", "Two-Handed Axes", "Two-Handed Maces" }),
    tr("Darnassus", "Ilyenia Moonfire", "Warrior's Terrace", { "Bows", "Daggers", "Fist Weapons", "Staves", "Thrown" }),
  },
  H = {
    tr("Orgrimmar", "Sayoc", "Valley of Honor", { "Axes", "Bows", "Daggers", "Fist Weapons", "Staves", "Thrown", "Two-Handed Axes" }),
    tr("Orgrimmar", "Hanashi", "Valley of Honor", { "Axes", "Bows", "Thrown", "Two-Handed Axes" }),
    tr("Thunder Bluff", "Ansekhwa", "Hunter Rise", { "Guns", "Maces", "Staves", "Two-Handed Maces" }),
    tr("Undercity", "Archibald", "War Quarter", { "Crossbows", "Daggers", "Polearms", "Swords", "Two-Handed Swords" }),
  },
}

T.Data.REP_DISCOUNT = { { "Friendly", 5 }, { "Honored", 10 }, { "Revered", 15 }, { "Exalted", 20 } }

--- Trainers for a side ("A" / "H"), optionally only those teaching `skill` (case-insensitive substring).
function T.Data.Trainers(side, skill)
  local out = {}
  for _, t in ipairs(T.Data.WeaponTrainers[side] or {}) do
    if not skill then out[#out + 1] = t
    else
      for _, s in ipairs(t.skills) do
        if s:lower():find(skill:lower(), 1, true) then out[#out + 1] = t break end
      end
    end
  end
  return out
end
