# HogUI Atlas

Dungeon guide for WoW: Forever, inside the game: what each dungeon is for, who is in it, what they drop, which
quests send you there, and which of those drops are better than what you wear.

Previews (drawn from the real code with sample items, not screenshots): `docs/mockups/atlas-*.png`.

## Commands

| Command | Opens |
|---|---|
| `/hh atlas` | the window, on the dungeon you stand in or one for your level |
| `/hh gear` | Upgrades tab |
| `/hh sets` | Sets tab |
| `/hh wish` | Wishlist tab |
| `/hh lootlog` | Loot log tab |
| `/hh dungeon` | the on-screen tracker (inside a dungeon) |
| `/hh atlas scan` | reads the game's own dungeon journal again |
| `/hh atlasinfo` | what Atlas could read on this client |

## The window

**Dungeons.** Left: every dungeon with its level range, coloured for your level: red = too low, orange = hard,
green = right, grey = outgrown. "For my level" keeps orange and green only. Middle: bosses in kill order, with the
number of drops known. Right: Loot, Quests or Guide for the dungeon.

**Upgrades.** Per gear slot, everything Atlas knows that beats what you wear, best first, with where it drops and
what it gives. The number is points better for your role. Amber = you need a higher level first. Items in your
bags count and say so.

**Sets.** Save what you wear as a set, or build one: alt-click any item in Atlas to put it in the selected set.
A set is judged as you would wear it: slots the set leaves empty keep your current item.

**Wishlist.** Right-click any item to add or remove it. When a wishlist item drops in a dungeon you get a chat
line and a sound.

**Loot log.** What dropped in your last 20 dungeon runs, by boss.

Item rows everywhere: hover = tooltip, shift-click = link in chat, ctrl-click = dressing room, right-click =
wishlist, alt-click = into the selected set.

## Outside the window

- **Tracker.** Inside a dungeon a small panel shows the bosses (ticked off as they die), your dungeon quests with
  progress, and wishlist items that drop there. Click its title for the full window. Closing it lasts for that run.
- **Tooltips.** Every item tooltip gets `Drops from: Boss (Dungeon)` when Atlas knows, and an upgrade line:
  `+31.9 for healer, over Plain Hood (Head)`.
- **Loot alert.** Loot something better than what you wear and chat says so.
- **Sharing.** New drops you discover go to your party and guild; theirs come to you, marked "group".

## Where the data comes from

Forever changed the old loot tables, added dungeons and hides item data, so no ready-made database exists. Every
drop in Atlas carries its source:

| Badge | Meaning |
|---|---|
| `seen` | you or your group saw it drop |
| `group` | another HogUI player saw it and shared it |
| `journal` | read from the game's own dungeon journal |
| `reported` | the curated file shipped with the addon (empty until drops are verified) |

Dungeon names, boss names, level ranges and quest titles are from the 2004-2006 game. Forever may differ. Whatever
the game itself reports replaces the shipped value, and the Guide tab says which one you are looking at. The two
dungeons new in Forever ship with no bosses: they fill in as you kill them.

## Scoring

An item's score is the sum of its stats times a weight per stat. Weights come in five presets (healer, caster,
melee, ranged, tank); your class picks one and you can pick another. Every weight can be changed under
`/hh` > Atlas > Stat weights. Rules:

- rings, trinkets and one-handers are measured against the weaker of your two
- a two-hander is measured against main hand and off hand together
- armour you cannot wear yet (mail before 40, plate before 40) is left out
- weapon skills are not checked

Stats are read from the item's tooltip text (English) and the client's stat table. An item the server has not sent
yet is asked for and appears a moment later.

## Filling the curated file

`dev/atlas_import.py drops.csv` (dry run) then `--write`. Columns: `dungeon_key,boss_name,item_id,source`. A row
without a source, with an unknown dungeon, or with a boss the list does not know fails the whole run.

## Limits

- English client text only (stat parsing, "You receive loot").
- Random-suffix items ("of the Eagle") from the journal show their base stats: the suffix is only known once the
  item exists.
- Raids are recorded when you are in one but are not in the dungeon list.
