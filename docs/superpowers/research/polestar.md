# Polestar - working alongside it (2026-11-06)

Sean 2026-11-06: "look at the 'polestar' addon and implement that into hogtron UI, I have it installed and running".
Asked how (licence below): **"Work alongside it"**, features wanted first: guide steps + arrow, quest givers + chains,
gear + reward advice, QoL automation.

## What Polestar is
- github.com/fitzforge/polestar - "Leveling guides for World of Warcraft: Forever": guide steps (1-60 routes), a
  waypoint arrow with walking routes (router started from Shortest Path Forever), quest markers from its own quest
  database, gear advice, quality-of-life chores, rares, talents, alts, dungeons. 0.3.2 on Sean's client; ~200 stars,
  pushed daily. 28 folders, ~80 MB (Polestar_Nav_* walking maps are most of it).
- Interface 16001 (Forever). `## OptionalDeps: EllesmereUI, TomTom, OpenMap`. SavedVariables PolestarDB /
  PolestarCharDB.

## Licence
- Code: **GPL-3.0-only** (`Polestar/LICENSE`, `## X-License`). HogTron UI is MIT -> **no Polestar code is copied**.
  Relicensing HogTron UI to GPL was offered as an option and not picked.
- Data folders carry their own notices (`LICENSE-DATA.txt`): Polestar_QuestDB from pfQuest (MIT); Polestar_Guides
  uses cmangos classic-db facts (GPL-3.0) + pfQuest (MIT); Polestar_ItemDB MIT; Polestar_Nav = Shortest Path Forever
  maps (GPL-3.0-or-later). We read none of it at build time and ship none of it.

## What HogTron UI reads (runtime only, every call pcall'd) - HogTronUI/Core/Polestar.lua
- `Polestar` global = its addon namespace (Core/Init.lua `Polestar = ns`).
- Quest database `Polestar.QuestDB`: IsLoaded, Load (on demand), GetQuest(id) -> { title, level, pre, preAll, ... },
  QuestIds. Gear `Polestar.Gear.RankChoices(links)` -> list { upgrade, pct }, pick. Polestar has no quest auto-accept /
  turn-in (HogTron's stays).
- Message bus: `Polestar.On(msg, fn)` / `Polestar.Fire(msg, ...)`. Messages used: GUIDE_CHANGED, STEP_CHANGED,
  STEP_UPDATED, WAYPOINT_CHANGED. `Fire("TOGGLE_FRAME")` toggles its guide window (UI/UI.lua).
- Settings: `Polestar.Get(path)` / `Polestar.Set(path, v)` - Set fires SETTING_CHANGED, so Polestar applies it.
- Guide engine `Polestar.Engine`: GetGuide, GetStepIndex, GetStepCount, GetStepView(i) -> { title, goals = { {
  status = done|na|skipped|current..., text, progress = { cur, max } } } }, GetWaypoint.
- Arrow: with Polestar's `nav.blizzardWaypoint` on (OFF by default) its target is set as the game's user waypoint
  and super-tracked (Nav/Bridges.lua). HogTron's beam only followed super-tracked QUESTS -> it now follows a
  super-tracked user waypoint too, titled with Polestar's open goal.

## Overlaps found (both on = both act) and who leads
| Area | Polestar | HogTron UI | Decision |
|---|---|---|---|
| Next thing to do | guide step | GO row (tracker) | Polestar's step on the GO row while it guides (`interop.polestar.guide`) |
| Game's arrow | user waypoint (`nav.blizzardWaypoint`) | GO super-tracks its pick | GO stands down while Polestar guides (`arrow`); waypoint switch turned on once |
| Quest givers / turn-ins on M | `qol.availableQuests`, `qol.turnInMarkers` (OFF by default) | none (backlog #28) | givers switched on once; Quests > Polestar drives its marker switches (`quests`) |
| Quest chains | quest records `pre` / `preAll` / `excl` | none (backlog #27) | shift-click a tracked quest = chain from its quest DB (HogTron_Quests/Chain.lua) |
| Quest lines on tooltips | `qol.questTooltips` (ON) | Quests > tooltip (ON) | ours defers while its switch is on (`chores`) |
| Gossip | `qol.skipGossip`, `qol.stepGossip` (ON) - NPCs WITHOUT quests only | quests.auto.gossip - quest menus only | no overlap: both stay |
| Sell junk / repair | `qol.sellJunk`, `qol.autoRepair` (ON) | skin.auto.sellJunk / repair (ON) | ours defers per switch (`chores`) |
| Upgrade offers | `qol.wearOffer`, `qol.rewardHighlight` (ON; its marks sit on Blizzard's reward panel) | atlas.upgradeAlerts (ON); our quest dialog replaces that panel | Atlas line defers to wearOffer; its `Gear.RankChoices` verdict shown in our dialog (`gear`) |
| XP level target | marks the game's XP bar | our XP bar replaces it | idea: draw its target on ours |

## Facts to check in game
- Does Forever's `C_SuperTrack.IsSuperTrackingUserWaypoint` exist and return true for Polestar's pin? `/hh wpdiag`
  (`path.user`) then `/hh polestardiag`.
- Polestar loads after HogTron UI (alphabetical); the hook runs at PLAYER_LOGIN and 2 s later.
