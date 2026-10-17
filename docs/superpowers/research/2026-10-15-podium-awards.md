# Podium: inspiration source for HogTron Awards

Date: 2026-10-15
Branch: `feat/awards` (new addon folder `HogTron_Awards`)

## Licence check

**Podium**, CurseForge project **1717948**, by **Dalorrian** ("end-of-run awards for WoW Forever").
**Licence: All Rights Reserved.** Read from the project page's sidebar (`licenseType: "All Rights Reserved"`), fetched
2026-10-15. curseforge.com answers scripts with 403, so the page came through a reader proxy (`r.jina.ai`).

HogTron UI is MIT, so nothing from Podium was taken: no code, assets or text. Its source was never downloaded or
opened. This is the same rule we use for HealKit (ARR) and the Cell / VuhDo / DandersFrames notes in
`2026-09-13-healing-addon-research.md`. Everything below comes from Podium's **public feature description** and is
used as ideas only.

## Patterns taken (ideas, not code)

| Podium (public description) | HogTron Awards |
|---|---|
| Gold VIEW AWARDS button when a dungeon, raid or BG ends | `UI.ShowPrompt`: top centre, pulsing, gone after 60 s |
| Five players on stage with 3D models, each playing an emote for their award; headline in the middle | `UI.ShowStage`: `PlayerModel:SetUnit` + `SetAnimation(EMOTES[award.emote])`; two layouts (arc / 2x2) |
| 75 awards, "real ones" and roasts | 38 honors + 37 roasts, all named and written for HogTron (pig puns) |
| One award per person, no repeats, headline + random draw | `Resolve.Stage`: MVP headline, seeded shuffle, alternating honor/roast |
| Same screen for the whole group | Addon messages (`HTR_AWD`) + a shared seed (lowest run id) |
| Ends at the last boss; the leader can end it by hand | `data/finalbosses.lua` + `/hh awards end` (anyone, tells the group) |
| Uses the built-in damage meter data | `Metrics.ReadMeter` reads `C_DamageMeter` **ranks only** (see below) |

**Flag for Sean: award names.** Podium lists MVP, Boss Slayer, The Wall, Lifeline, Executioner, Floor Inspector,
Magnet, Pacifist, Wipe Lord and Loot Goblin among its awards. Your seed list reuses nine of those exactly (MVP, The
Wall, Lifeline, Executioner, Floor Inspector, Magnet, Pacifist, Wipe Lord, Loot Goblin); "Boss Slayer" became
"Boar Slayer". They're short generic gaming terms and the flavor text is all ours, so the risk is low, but renaming
them is a 2-minute job if you'd rather not share any names.

Not taken, and not built: honorable mentions, history of the last 5 screens, crash recovery ("ask the group"),
Send to Party, minimap button.

## What WoW: Forever lets an addon see (MEASURED, game SavedVariables 2026-10-15 15:48)

- `C_DamageMeter` exists: `GetCombatSessionFromType`, `GetCombatSessionSourceFromType/FromID`, `GetSessionDurationSeconds`, ...
  `Enum.DamageMeterType` = DamageDone 0, Dps 1, HealingDone 2, Hps 3, Absorbs 4, Interrupts 5, Dispels 6,
  DamageTaken 7, AvoidableDamageTaken 8, Deaths 9, EnemyDamageTaken 10. `Enum.DamageMeterSessionType` = Overall 0,
  Current 1, Expired 2. Rows: name, classFilename, totalAmount, amountPerSecond, sourceGUID, isLocalPlayer, ...
- **Every amount is SECRET** (HogHeals_Meter note): it can be shown but not compared, sorted or sent. So awards use
  each list's **order**, which Blizzard ranks already. They never use the numbers.
- No combat log for addons. Killing blows, overheal, damage to a specific target, mana: **not derivable** in PvE.
- `C_ChatInfo.SendAddonMessage` / `RegisterAddonMessagePrefix` are present; the legacy globals are nil.
  `CHAT_MSG_ADDON` registers fine. Delivery inside an instance has **not been proven**.
- `CHAT_MSG_LOOT` is readable and not secret (1159 fires, outside instances). Inside instances it's unknown, so loot
  awards count each player's **own** loot and share the count.
- `ENCOUNTER_START`, `ENCOUNTER_END` and `BOSS_KILL` register without error **but have never fired** in a recorded
  session (no dungeon boss was killed while the probe ran). Run-end-by-boss is unproven. `/hh awards probe` counts
  every trigger, and `/hh awards end` always works.

## The 75: dropped / reframed (final count: 75, nothing dropped)

| Award | What changed | Why |
|---|---|---|
| MVP | sum of meter **ranks** (damage, healing, absorbs, interrupts, dispels) minus deaths | amounts are secret, so they can't be added up |
| Mana Monk | fewest **Drink** casts among healers | mana is secret |
| Executioner | **battlegrounds only** (scoreboard killing blows) | PvE killing blows need the combat log |
| Clutch Rez | rez spell cast while in combat (own client) | "clutch" timing isn't observable |
| Mythic Mover | most time moving | Forever has no Mythic+ |
| Trotter's Pride | best contributor with no avoidable damage | needed a measurable definition |
| Oinkspiration | top of the Absorbs list | "inspiring" isn't measurable |
| Pigskin Protector | most taunts cast | needed a measurable definition |
| Boar Mitzvah | levelled up during the run | needed a measurable definition |
| Oinkmentum | entered combat while the group's tank wasn't | **unproven**: reading another unit's combat state may be secret |
| Wipe Lord / Swine Dive | deaths in failed / early boss fights | **unproven**: needs `ENCOUNTER_START/END` to fire |
| Pork Chop | loss-of-control effects on you | **unproven**: `LOSS_OF_CONTROL_ADDED` not probed yet |
| Objective Pig, Hog Hunter, Ham-mortal | BG scoreboard | **unproven**: scoreboard fields may be secret on Forever |

Every other award uses either the meter order (same for everyone) or a counter the player's own client keeps
(jumps, loot, drinks, emotes, gold, errors, ready checks, ...), shared over `HTR_AWD`.

## Open questions for the first in-game run

1. Does `ENCOUNTER_END` / `BOSS_KILL` fire for a 5-man boss? (`/hh awards probe` after a dungeon)
2. Do addon messages arrive inside an instance?
3. Is the meter's `Overall` session the whole run? It also includes fights from before the run unless the player
   resets the meter. Not reset by us (that's the player's data); flagged.
4. Spell-name matching (food, drinks, rezzes, taunts, CC) uses enUS names; other locales count casts but not the categories.
