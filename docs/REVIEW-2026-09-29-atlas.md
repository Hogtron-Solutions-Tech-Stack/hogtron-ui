# HogUI Atlas: review notes, 2026-09-29 (two-hour unattended run)

Ask: Sixty Upgrades + AtlasLoot in game, plus a loot tracker, a quest tracker for dungeons and a dungeon guide.
Decisions taken with Sean before the run: upgrade finder first, then set planner; game data first, site data only as
a local fill-in; role presets with editable weights.

## State in one line

BUILT-UNVERIFIED. Everything below runs in the test harness; nothing has been seen in the game.

## What exists

| Piece | File | State |
|---|---|---|
| Dungeon list, level colours, guide | `Data/Dungeons.lua`, `Levels.lua` | built, tested |
| Bosses + loot, 4 sources | `Store.lua`, `Journal.lua`, `Capture.lua`, `Data/Loot.lua` | built, tested |
| Dungeon quest tracker | `DungeonQuests.lua`, `Data/Quests.lua` | built, tested |
| Upgrade finder, item compare | `Stats.lua`, `Gear.lua` | built, tested |
| Sets, wishlist | `Gear.lua` | built, tested |
| Window, 5 tabs | `List.lua`, `Window.lua` | built, tested, previews rendered |
| On-screen dungeon tracker | `Tracker.lua` | built, tested, preview rendered |
| Tooltip lines, loot alert | `Tooltip.lua`, `Capture.lua` | built, tested |
| Sharing with party / guild | `Share.lua` | built, tested |
| State recorder for disk reads | `Diag.lua` | built, tested |
| Curated import tool | `dev/atlas_import.py` | built, tested |
| Preview renderer | `dev/render_atlas.py` | built, run |

## What is NOT known until the game is run (each is recorded to disk by the addon)

1. **Does the dungeon journal answer on Forever?** The functions exist (measured 9/28). If it answers, loot tables
   fill at login. If not, tables start empty and fill from play. `/hh atlas scan` prints the answer.
2. **Are loot links, boss names and loot chat readable inside an instance?** Outdoors they are (measured). If they
   are secret inside, discovery records nothing in dungeons and says why under "skipped" in `/hh atlasinfo`.
3. **Does ENCOUNTER_END fire for 5-man bosses?** If not, bosses are still ticked off by their loot.
4. **Does item stat reading work?** Tooltip text is parsed in English. `/hh atlasinfo` prints one worn item as Atlas
   read it.
5. **Does the client allow addon messages in a dungeon?** A refusal is counted, not raised.

## What is from memory, and marked so in the game

Dungeon names, boss names, level ranges, entrance notes and quest titles are from the old game, written from
knowledge, not read from Forever. The window labels them. No item id was written from memory: the curated loot
file ships empty.

## Found and fixed during the run

| Found by | Problem | Fix |
|---|---|---|
| test | `secret ~= nil` throws on this client; loot links were compared before the secret test | secret test first, everywhere |
| test | `HH:SafeCall` passes the table as first argument; the state recorder got it as its reason | plain `pcall` |
| test | grey junk with 5 armour raised an "upgrade" alert over an empty slot | alerts skip grey items |
| own review of the previews | a half-filled set was compared as if empty slots were bare | judged as you would wear it |
| own review of the previews | set rows did not name the slot; stat totals wrapped inside a stat | slot column; wraps between stats |
| own review of the previews | where an upgrade drops was hidden behind a tooltip | in the row |
| code review | random-suffix items share an id but not stats; stats were cached per id | cached per item string |
| code review | a journal listing hundreds of instances could freeze login | 60 instances and 120 ms per scan, carries on next time |
| code review | defaults added later would never reach a saved profile | filled once per session |
| code review | the journal scan asked the server for every item at login | items are asked for when shown |

Two of my own test expectations were wrong arithmetic (the code was right): corrected, noted here for honesty.

## Not done

- Sixty Upgrades' own item data. Their API refuses unsigned requests (`403 Missing Authentication Token`). Using it
  means signing in as their web app does; that is a decision about their terms, not a technical one. Left alone.
- Raids in the dungeon list.
- A button on the micro menu or minimap. Slash commands and the options window only.
- Non-English clients.
- Weapon skill checks in the upgrade finder.

## In-game checklist

1. Start the game fresh (new addon folder). On the AddOns screen, HogUI Atlas ticked.
2. `/hh atlas` : window opens, a dungeon for your level is selected.
3. `/hh atlas scan` : read the chat line.
4. `/hh gear` : anything in your bags that beats what you wear lists at once.
5. Hover any gear item: an upgrade line at the bottom of the tooltip.
6. Walk into a dungeon: the tracker appears on the right. Kill a boss, loot: boss ticks off, `/hh lootlog` has the drop.
7. `/hh atlasinfo`, then `/reload`. The answers to the five unknowns are then on disk.
