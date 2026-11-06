# HogTron UI

## v0.2.0-beta.15

### New
- **Three looks, one switch** (General > Look > Style, and the setup guide): **Parchment** (new default) - the quest
  dialog's page on every window, the game's Friz Quadrata, ink on paper; **Modern** - HogTron's dark, flat look;
  **Blizzard** - the game's own look and icons. Every feature works in all three. `/hh look parchment | modern | blizzard`.
- Skin > Windows > Look now follows the UI's look by default (or force parchment / ink per your taste).
- `/hh open <window>` opens one of Blizzard's windows by name (character, spellbook, questlog, social, guild, map,
  bags, lfg, options, ...) - handy for checking the skin window by window.

- **Parchment reaches our own frames:** the quest tracker, the info bar (gold, durability, bags, fps ... in ink, the
  value colours darkened to read on paper), the menu bar and bags sit on plain paper in the Parchment look.
- **The minimap and the world map (M) on paper**: the minimap framed in paper with its zone name in ink; the map window
  on the torn page with its quest log stripped and inked (the map itself untouched).
- **Our settings window and the setup guide on the torn page** in the Parchment look (ink text, the two-tone wordmark
  in ink and amber, flat paper controls).
- **Chat, the damage meter and tooltips on the charred page** in the Parchment look - their text is Blizzard's own, in
  every colour, and reads on the dark sheet as it is.
- **New icon set for the Parchment look: ink stamps** - every menu and drawer icon as a woodcut on a paper disc inside
  the dialog's bronze ring (General > Look > Icons: Ink stamps; `dev/make_page_icons.py` makes them from our glyphs).

### Fixed
- The spellbook loses its dark top bar and book frame on the page like every other window; its dark text already reads.
- Parchment windows are solid paper (the damage meter showed through at 90%); inked text loses Blizzard's black
  outline and shadow ("Level 10 Druid" read as a smudge); list rows (the friends list) lose their navy bars and are
  inked like the rest.
- The settings window and setup guide on paper read again: the sidebar was still navy under ink labels and the body
  text still light grey on the page. Now the sidebar is a faint shade of the page with a ruled margin, the body text
  and inputs are ink on paper, and picked tabs and headers use a darker amber that reads at small size.
- Training learns your class trainer on this client: its list comes back in the newer layout (name, type, icon,
  level), which the old reader skipped, so "Nothing learned yet" stayed after every visit. Two ranks of a spell are
  kept apart by level. `/hh traindiag` shows exactly what the trainer handed over.
- The info bar's readings (and a bag's title, the menu bar's letters) lose the black outline on paper - brown ink with
  a black rim read as a smudge.
- Lists on paper are inked as they fill: the friends list kept Blizzard's light blue names, gold character names, white
  levels and class colours on the light page. Colour codes inside the text are inked too (the same darker hue), every
  scroll list's rows are inked again each time Blizzard repaints them, and one-line headers keep their own bar.
  `/hh skindiag` now reports what the list pass found ("lists FriendsFrame: ...").
- The waypoint beam no longer vanishes when GO's pick is a quest the game cannot place (a dungeon quest such as
  Searching for the Lost Satchel): GO's line still recommends it, but the beam and arrow point at the best quest
  that has a spot on your map. `/hh go` says so when they differ.

## v0.2.0-beta.14

### Fixed
- **Parchment windows lose their inner boxes, so every text reads.** The exit / confirm popups kept Blizzard's dark
  diamond box (`BG`), the escape menu its metal header, the character window its dark panes and stat rows - and the
  inked text on them could not be read. On the page every decorative texture inside a window now goes (buttons, bars,
  edit boxes, scroll bars, icons, item slots and selection marks stay), before the text is inked; lists that build late
  are caught a moment later. The spellbook keeps its own book page (it already reads). Windows whose art is their
  content (talents, achievements, journals, collections, calendar, auction house, professions, macros, key bindings,
  dressing room, stable) keep the ink panel with Blizzard's own text colours.
- A window without a title row (popups) gets no bronze rule across its message; a short page's torn slices meet
  instead of overlapping (no lighter band).

## v0.2.0-beta.13

### New
- **Blizzard's windows wear the parchment page** (Skin > Windows > Look, default): the quest dialog's torn page behind
  the character sheet, spellbook, escape menu, vendor, mail, bank, friends, Guild & Communities, popups and the rest -
  light or charred after Quests > Dialog > Look - with the title in Friz Quadrata ink, a bronze rule, a key-cap close
  and tabs as rounded slabs. On the light page every text is inked to read on paper: white and grey go ink and muted,
  gold goes amber, class / quality / red / green keep their hue. "Ink panel" keeps the flat look. A look change takes
  a /reload. Guild & Communities (load-on-demand) is now skinned too.

## v0.2.0-beta.12

### Fixed
- **Buffs, debuffs and chat windows stay where edit mode put them.** Blizzard's own layout pass (its Edit Mode
  systems, re-run when its layouts arrive from the server and after every loading screen) could land after our
  re-apply and put them back; now it is hooked and undone the moment it runs, `EDIT_MODE_LAYOUTS_UPDATED` re-applies,
  and for a minute after each world entry a watch puts back anything else that moves them. A chat window sized on
  Blizzard's own corner grip keeps that size through the pass too. A move made in Blizzard's Edit Mode hands the frame
  back to Blizzard. `/hh movediag` now lists the guards and what moved what, when (also in `HogTronUIDB.global.diag.moves`).
- A disabled menu-bar button (Talents under level 10) says why on click and in its tooltip instead of doing nothing.

## v0.2.0-beta.11

### New
- **The Training window is a parchment page** in the quest dialog's look: class circle, rounded section tags, ink
  text, spell icons, Friz Quadrata; it follows Quests > Dialog > Theme (parchment / charred).

### Fixed
- Nameplate level text spells classification out: "9 Rare", "20 Elite", "30 Rare Elite" (was "9R", "20+").

## v0.2.0-beta.10

### New
- **Blizzard's Quick Keybind Mode works on HogTron bars:** hover a slot, press a key. `/hh bind` stays too.
- **The world map (M) wears the HogTron look** by default (Quests > World map > skin to turn it off).

## v0.2.0-beta.9

### New
- **Blizzard's own pictures on the menu bar only** (Skin > Menu & bag bar > "Blizzard's own button pictures (this bar
  only)"). The bottom menu cells show the game's original button art and the Bags cell the backpack; the drawer, info
  bar and quest marks keep your General > Icons choice. Off by default.

## v0.2.0-beta.8

### Fixed
- **Nameplate threat colours showed nothing until a mob had you on its threat table.** A mob already fighting your
  group is coloured by whom it targets: a groupmate or pet = green (red in tank mode), you = red (green in tank mode).

## v0.2.0-beta.7

### Fixed
- **Chat windows moved in edit mode stayed put only until the next loading screen.** Their place and size are now
  remembered by HogTron UI and put back at login and on every world entry. `/hh movediag` shows what is remembered.

## v0.2.0-beta.6

### New
- **Pick which parts load at all.** One package, every module inside; in the setup guide's "Pick your parts" page
  (and General > Modules) each part has a load switch - off = the game does not load it, per character, from the
  next /reload. `/hh modules` lists them.

## v0.2.0-beta.5

### New
- **Icon look "Blizzard's own (OG)"** (General > Look > Icons): the bottom menu shows the game's original button art,
  the drawer uses stock icons and the quest marks become Blizzard's gossip icons. Painted stays the default.
- **Info bar fits its readings:** every reading is shown whole (the bar grows); Skin > Info bar > "Fit each reading".

### Changed
- CurseForge: one project. The per-module projects were refused by moderation ("Merge Projects"); the HogTron UI
  bundle is the everything-package and the only project that receives files.

## v0.2.0-beta.4

### New
- **HogTron Edit Mode on the Escape menu**, in place of Blizzard's Edit Mode (which arranges frames this UI replaces).
  General > "Escape menu: HogTron Edit Mode" brings Blizzard's button back.
- **Edit mode moves more:** the menu bar (bottom icons), every chat window (drag; corner grip resizes), the minimap
  box (drag; corner grip resizes, the map refits), and Blizzard's buff and debuff frames. Places are remembered.
- **Level-up card:** when you level, a small card says what to train now (from your trainer memory), which dungeons
  came into range, and talent points to spend - Train / Where next buttons. `/hh levelup` previews it; Training tab.
- **Camera zoom-out:** the camera pulls back further (2.6, the client's cap on Classic). General > "Camera zoom-out
  (max)"; `/hh zoom`.
- **Training window pictures:** each spell shows the trainer's own icon; weapon trainers show weapon-skill icons.
- **Nameplate threat colours:** yellow / orange / red as aggro climbs (tank mode flips it). Nameplates > Threat.

### Fixed
- Action bar keybinds read "SHIF" / "CTR" / "BUTT" on Anniversary and Forever: now `s-1`, `c-1`, `m4`.
- Blizzard's "unopened items in your collection" tip floated over the bag bar: menu-button tips are hidden while the
  HogTron menu bar stands in (switch in Skin > Menu & bag bar).
- `dev/check_client_build.py` warns before a release when an installed client has patched past the toc versions.

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
