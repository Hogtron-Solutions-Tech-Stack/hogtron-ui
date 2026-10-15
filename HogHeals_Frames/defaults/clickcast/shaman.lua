-- Suggested click-cast grid: SHAMAN. Same rules as priest.lua (names only, plain Left/Right = Rank 1, alternates).
HogHealsFrames = HogHealsFrames or {}
HogHealsFrames.ClickGridDefaults = HogHealsFrames.ClickGridDefaults or {}

HogHealsFrames.ClickGridDefaults.SHAMAN = {
  { button = "LEFT", mod = "NONE", spell = { "Lesser Healing Wave", "Healing Wave" }, rank = 1, rez = true },
  { button = "RIGHT", mod = "NONE", spell = "Healing Wave", rank = 1, rez = true },
  { button = "LEFT", mod = "SHIFT", spell = { "Lesser Healing Wave", "Healing Wave" }, rez = true },
  { button = "RIGHT", mod = "SHIFT", spell = "Healing Wave", rez = true },
  { button = "MIDDLE", mod = "NONE", spell = "Chain Heal", rez = true },
  { button = "LEFT", mod = "CTRL", spell = "Cure Poison" },
  { button = "RIGHT", mod = "CTRL", spell = "Cure Disease" },
  { button = "LEFT", mod = "ALT", spell = "Earth Shield" },                 -- TBC talent; skipped where it does not exist
}
