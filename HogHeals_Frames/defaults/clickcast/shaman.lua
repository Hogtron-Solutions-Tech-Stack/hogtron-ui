-- Suggested click-cast grid: SHAMAN. Same rules as priest.lua (names only, alternates, plain Left/Right free).
HogHealsFrames = HogHealsFrames or {}
HogHealsFrames.ClickGridDefaults = HogHealsFrames.ClickGridDefaults or {}

HogHealsFrames.ClickGridDefaults.SHAMAN = {
  { button = "LEFT", mod = "SHIFT", spell = { "Lesser Healing Wave", "Healing Wave" }, rez = true },
  { button = "RIGHT", mod = "SHIFT", spell = "Healing Wave", rez = true },
  { button = "MIDDLE", mod = "NONE", spell = "Chain Heal", rez = true },
  { button = "LEFT", mod = "CTRL", spell = "Cure Poison" },
  { button = "RIGHT", mod = "CTRL", spell = "Cure Disease" },
  { button = "LEFT", mod = "ALT", spell = "Earth Shield" },                 -- TBC talent; skipped where it does not exist
}
