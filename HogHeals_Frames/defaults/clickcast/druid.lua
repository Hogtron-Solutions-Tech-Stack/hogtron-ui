-- Suggested click-cast grid: DRUID. Same rules as priest.lua (names only, alternates, plain Left/Right free).
-- Rez is Rebirth: usable in combat, but the macro keeps the nocombat gate so a misclick never spends it mid-fight.
HogHealsFrames = HogHealsFrames or {}
HogHealsFrames.ClickGridDefaults = HogHealsFrames.ClickGridDefaults or {}

HogHealsFrames.ClickGridDefaults.DRUID = {
  { button = "LEFT", mod = "SHIFT", spell = "Regrowth", rez = true },
  { button = "RIGHT", mod = "SHIFT", spell = "Healing Touch", rez = true },
  { button = "MIDDLE", mod = "NONE", spell = "Rejuvenation" },
  { button = "LEFT", mod = "CTRL", spell = "Remove Curse" },
  { button = "RIGHT", mod = "CTRL", spell = { "Abolish Poison", "Cure Poison" } },
  { button = "LEFT", mod = "ALT", spell = "Swiftmend" },                    -- talent; skipped until learned
  { button = "BUTTON4", mod = "NONE", spell = "Mark of the Wild" },
}
