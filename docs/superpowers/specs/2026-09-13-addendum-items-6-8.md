# Addendum — Cell items 6 / 7 / 8 (design notes, 2026-09-13 overnight)

Source: reading Cell r274 on the Anniversary client for *behaviour* (patterns only; Cell's licence is
all-rights-reserved, zero code reuse). Decisions here are defaults; Sean can strike any.

## 6a. Request_Dispel — BUILT tonight as `HogHeals_Frames/RequestDispel.lua`

How Cell does it: the requester runs a macro `/run C_ChatInfo.SendAddonMessage("CELL_REQ_D","D","RAID")`;
every Cell user in the group receives `CHAT_MSG_ADDON` with that prefix and glows the sender's frame
for a few seconds (glow style configurable). No aura data, no combat-log data — API-safe under any
Forever regime.

HogHeals version:
- Prefix `HHREQ`, payload `D` (dispel). Room for `S:<spell>` (Request_Spell) later.
- Sender: `/hh dispelme` (party → `PARTY`, raid → `RAID`). Users macro it to a key.
- Receiver: finds the button whose unit name matches the sender (name-realm stripped), shows
  `button.requestGlow` (cyan border) for 5 s, then hides. Never errors on unknown sender/prefix.
- Toggle in Indicators (`requestGlow`), duration in Appearance later if asked.
- Tests: `tests/test_request_dispel.py` (glow on message, ignore unknown, send channel, prefix registered).

## 6b. RaidDebuffs — data pack, DEFERRED until beta

How Cell does it: `debuffs[instanceID][encounterID] = { spellId, ... }` per expansion file, curated from
an "Instance Spell Collector" the community runs. Frames show the highest-priority boss debuff as a big
icon with optional glow.

HogHeals plan: separate addon `HogHeals_RaidDebuffs` (own toc, `## Dependencies: HogHeals_Frames`) so
data updates don't churn Frames. Data shape identical (instance → encounter → ordered spell IDs).
Forever's instances/encounter IDs are unknown until the beta client exists; the priority-debuff slot
(`priorityDebuffs` list) already provides the display path, so the pack only supplies names/IDs.
Collector: `/hh collect on` logs every new debuff seen in an instance to SavedVariables → Sean pastes
into the pack. Landmine: aura data is exactly what Midnight restricted; if Forever restricts it, this
pack is dead on arrival — do not build before the 9/17 answer.

## 7. crowdControls / targetCounter — DEFERRED (PvP)

- `targetCounter` counts how many enemy nameplates target each friendly unit (nameplate unit tokens →
  `UnitGUID(nameplateN.."target")`). PvP/arena tool; needs nameplates on and a 0.1 s scanner. Cheap
  to build later as an element with `Ticker = 0.2`; no aura data needed → API-safe.
- `crowdControls` shows CC auras on frames (sheep, sap, fear) from a curated list — aura-dependent,
  same API risk as RaidDebuffs. Defer with it.

## 8. Utilities — belongs to the QoL module, not Frames

Cell's Utilities folder (13.8k lines) is a second addon in disguise: QuickAssist (3.7k), QuickCast
(1.5k), BuffTracker (1.8k, rebuff helper — Classic-relevant), Request_Spell (0.8k), RaidRosterFrame,
ReadyAndPull, Marks, DeathReport, BattleRes. For HogHeals:

| Cell utility | HogHeals home | Note |
|---|---|---|
| BuffTracker / rebuff | HUD module (2) | pairs with `missingBuffs` element; one-click rebuff = macro fallback chain |
| Request_Spell | Frames 1.1 | same wire as Request_Dispel (`S:<spell>`) |
| ReadyAndPull, Marks, RaidRoster | QoL module (4) | raid-lead tools; not healer-specific |
| DeathReport | QoL module (4) | combat-log dependent — API risk |
| QuickAssist / QuickCast | not planned | Retail-era Augmentation Evoker / spotlight tooling |
| BattleRes | never | no battle res in Classic |

## Sequence recommendation

1. Ship Frames 1.0 with Request_Dispel included (done tonight).
2. 9/17: read the addon-API answer; if aura filtering survives → start `HogHeals_RaidDebuffs` collector.
3. Request_Spell + targetCounter as Frames 1.1 (both API-safe).
4. Everything in §8 waits for its module per the roadmap rule (N+1 after N ships).
