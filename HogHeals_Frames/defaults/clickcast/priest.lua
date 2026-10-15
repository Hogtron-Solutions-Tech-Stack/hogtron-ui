-- Suggested click-cast grid: PRIEST. Formalised from Sean's real Clique layout (the keyboard hover-binds in
-- ClickCast.Defaults): the same spells, moved onto mouse button + modifier.
--
-- Rules for every defaults/clickcast/*.lua file:
--   * spell NAMES only. No rank -> Highest: the grid casts the top rank learned and follows new ranks on its own.
--   * rank = 1 pins Rank 1 (the cheap, efficient heal). Sean 2026-10-15: plain Left / plain Right = Rank 1 of the two
--     main heals, Shift + Left / Right = the same heals at Highest. Plain clicks no longer target / open the menu
--     on the frames; clear those two slots to get that back.
--   * spell = { "A", "B" } lists alternates: the first one this character knows is used (low-level fallback).
--   * rez = true on direct heals: the slot resurrects a dead target out of combat (class rez, if learned).
-- A spell (or pinned rank) the character has not learned yet shows as "not learned" and is skipped until it is.
HogHealsFrames = HogHealsFrames or {}
HogHealsFrames.ClickGridDefaults = HogHealsFrames.ClickGridDefaults or {}

HogHealsFrames.ClickGridDefaults.PRIEST = {
  { button = "LEFT", mod = "NONE", spell = "Flash Heal", rank = 1, rez = true },
  { button = "RIGHT", mod = "NONE", spell = "Greater Heal", rank = 1, rez = true },
  { button = "LEFT", mod = "SHIFT", spell = "Flash Heal", rez = true },
  { button = "RIGHT", mod = "SHIFT", spell = "Greater Heal", rez = true },
  { button = "MIDDLE", mod = "NONE", spell = "Renew" },
  { button = "LEFT", mod = "CTRL", spell = "Power Word: Shield" },
  { button = "RIGHT", mod = "CTRL", spell = "Dispel Magic" },
  { button = "LEFT", mod = "ALT", spell = "Prayer of Healing" },
  { button = "BUTTON4", mod = "NONE", spell = "Power Word: Fortitude" },
  { button = "BUTTON5", mod = "NONE", spell = "Divine Spirit" },
}
