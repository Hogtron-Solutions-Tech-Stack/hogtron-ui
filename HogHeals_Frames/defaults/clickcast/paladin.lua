-- Suggested click-cast grid: PALADIN. Same rules as priest.lua (names only, alternates, plain Left/Right free).
HogHealsFrames = HogHealsFrames or {}
HogHealsFrames.ClickGridDefaults = HogHealsFrames.ClickGridDefaults or {}

HogHealsFrames.ClickGridDefaults.PALADIN = {
  { button = "LEFT", mod = "SHIFT", spell = "Flash of Light", rez = true },
  { button = "RIGHT", mod = "SHIFT", spell = "Holy Light", rez = true },
  { button = "MIDDLE", mod = "NONE", spell = "Holy Shock" },                -- talent; skipped until learned
  { button = "LEFT", mod = "CTRL", spell = { "Cleanse", "Purify" } },
  { button = "RIGHT", mod = "CTRL", spell = "Blessing of Protection" },
  { button = "LEFT", mod = "ALT", spell = "Blessing of Freedom" },
}
