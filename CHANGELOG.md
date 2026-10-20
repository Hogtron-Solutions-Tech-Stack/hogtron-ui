# HogTron UI

## v0.2.0-beta.3

### New
- **Eating and drinking show on the cast bar**, with their own strips: drink, food, or one "Food & Drink" bar when you
  do both. Stand up and it goes away.
- **Wax-seal quest marks** on the quest dialog's parchment: offered, finished and still-in-progress quests each get
  their own seal; quests far below your level show greyed out.
- **Attach your cast bar to your unit frame:** HUD > Castbar (or Units > Player) > Attach - under or over the player
  frame. It takes the frame's width and follows it when you move the frame.
- **Cast bar icon inside the bar**, spell name centred. Same on the target and focus cast bars.
- **Who's targeting whom:** the target and focus frames show "» name" for who that unit is targeting ("» You" in red
  when it's you), and their cast bars read "Shadow Bolt » You". Your own cast bar shows just the spell (the target name
  is a switch in HUD > Castbar).
- **Portraits** beside the player, target and focus frames: off by default, switch each on in its Units tab. Picture
  (2D) or live model (3D) in Units > General.
- **`/hh unlock` grid and snapping**, like Blizzard's Edit Mode: frames snap to each other, the screen centre and the
  grid when you let go; a cyan line shows what they will line up with. Hold Shift to place freely. Toolbar at the top
  (grid on/off, grid size, snap, lock).
- **XP bar dividers are back:** 20 segments over the animated fill.
- **Ore, herbs and chests:** the game's icon now sits inside the glow ring, clear of the name.

### Fixed
- The XP bar's animated fill never moved (and logged errors in the background); it now drifts toward the head.
- Units: the portrait checkbox looked ticked while portraits were off. Each feature's settings now sit next to its
  switch, in the tab where you would look for it.

## v0.2.0-beta.2

### New
- **Hearthstone gets its own cast bar**, on every class: a carved hearthstone with glowing recall runes and firelight in
  the cracks.
- **Conjure Water** has a new strip: a heavy surge of deep water.
- **Move the cast bar, swing timer or mana bar on their own.** Each one's tab has "Move it on its own (out of the
  strip)"; in `/hh unlock` drag its box anywhere, and the bars left in the strip close the gap.
- **Party / raid frames resize in `/hh unlock`:** drag the corner grip on their box (out of combat).

### Fixed
- Chat: the text size slider showed 14 until you moved it; it now starts at the chat window's real size.

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
