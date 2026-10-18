# HogTron UI

## v0.2.0-beta.1

The second public beta, built for WoW: Forever.

### New
- **New name and folders: HogTron UI.** Your settings come across from HogHeals on their own (the HogHeals folder in
  this release is only that bridge).
- **Setup guide** on every character the first time you log in, step by step through the whole suite.
- **Cast bars that look like the spell.** Every class's casts with a cast bar get their own painted strip (Fireball,
  Frostbolt, Holy Light, Lightning Bolt, Shadow Bolt, Healing Touch and 80 more); everything else takes its school's
  look (holy, fire, frost, arcane, shadow, nature, plus mining, herbs, fishing ...).
- **Swing timer** with its own animation: a steel slash for melee, wind for Auto Shot, a flash on every hit.
- **Quest beam:** a beam of light over the quest giver instead of the flat diamond, an arrow when it is off screen.
- **Edit mode (`/hh unlock`):** every bar of the HUD (cast bar, swing timer, mana bar, info line) is its own box - click
  it for its size - and every frame with a size has a corner grip: drag it to resize.
- **Awards** at the end of a dungeon, raid or battleground run, and a dungeon **Journal**.
- **Nearest ore / herb / chest lights up** in any direction, not only straight ahead.
- **Quest dialog:** coin and XP icons on rewards.
- **Unit frames** show first and last names; nameplate names line up with the bar.
- **Menu bar:** bigger, distinct icons, including Forever's Legacy button. The minimap drawer's button is the HogTron
  boar; tooltips sit under it.
- **Click-cast** suggested layouts and a reworked binding window.

### Fixed
- Action bars: usable spells stuck grey, and no cooldowns on the buttons.
- Action bars: the lower half of a button not taking the mouse; Blizzard's main bar art showing under ours.
- "Interface action failed because of an AddOn" warnings in combat (bar click-through, quest map arrow).
- Opening a class trainer froze the game.
- Nameplates: an empty bar with "100%" on some mobs, an empty black bar over ore / herb nodes, dead mobs keeping a
  0% bar.
- Friends and Group Finder windows now take the HogTron look.
- Party frames: when the game refuses buffs / debuffs mid-fight, the frame clears instead of showing stale icons.
- Option labels wrap instead of overlapping; auto turn-in is off by default and labelled.
- Many smaller fixes; `/hh errors` lists anything still going wrong.

Report problems with `/hh errors` output and a screenshot.
