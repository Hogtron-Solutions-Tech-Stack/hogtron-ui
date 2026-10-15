-- Suggested click-cast grid: PRIEST. Formalised from Sean's real Clique layout (the keyboard hover-binds in
-- ClickCast.Defaults): the same spells, moved onto mouse button + modifier.
--
-- Rules for every defaults/clickcast/*.lua file:
--   * spell NAMES only, never ranks. The grid casts the highest rank learned and follows new ranks on its own.
--   * spell = { "A", "B" } lists alternates: the first one this character knows is used (low-level fallback).
--   * plain Left / plain Right stay unbound so clicking a frame still targets / opens the menu.
--   * rez = true on direct heals: the slot resurrects a dead target out of combat (class rez, if learned).
-- A spell the character has not learned yet shows as "not learned" and is skipped until it is.
HogHealsFrames = HogHealsFrames or {}
HogHealsFrames.ClickGridDefaults = HogHealsFrames.ClickGridDefaults or {}

HogHealsFrames.ClickGridDefaults.PRIEST = {
  { button = "LEFT", mod = "SHIFT", spell = "Flash Heal", rez = true },
  { button = "RIGHT", mod = "SHIFT", spell = "Greater Heal", rez = true },
  { button = "MIDDLE", mod = "NONE", spell = "Renew" },
  { button = "LEFT", mod = "CTRL", spell = "Power Word: Shield" },
  { button = "RIGHT", mod = "CTRL", spell = "Dispel Magic" },
  { button = "LEFT", mod = "ALT", spell = "Prayer of Healing" },
  { button = "BUTTON4", mod = "NONE", spell = "Power Word: Fortitude" },
  { button = "BUTTON5", mod = "NONE", spell = "Divine Spirit" },
}
