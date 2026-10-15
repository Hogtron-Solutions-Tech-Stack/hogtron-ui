-- Suggested click-cast grid: PALADIN. Same rules as priest.lua (names only, plain Left/Right = Rank 1, alternates).
HogHealsFrames = HogHealsFrames or {}
HogHealsFrames.ClickGridDefaults = HogHealsFrames.ClickGridDefaults or {}

HogHealsFrames.ClickGridDefaults.PALADIN = {
  { button = "LEFT", mod = "NONE", spell = "Flash of Light", rank = 1, rez = true },
  { button = "RIGHT", mod = "NONE", spell = "Holy Light", rank = 1, rez = true },
  { button = "LEFT", mod = "SHIFT", spell = "Flash of Light", rez = true },
  { button = "RIGHT", mod = "SHIFT", spell = "Holy Light", rez = true },
  { button = "MIDDLE", mod = "NONE", spell = "Holy Shock" },                -- talent; skipped until learned
  { button = "LEFT", mod = "CTRL", spell = { "Cleanse", "Purify" } },
  { button = "RIGHT", mod = "CTRL", spell = "Blessing of Protection" },
  { button = "LEFT", mod = "ALT", spell = "Blessing of Freedom" },
}
