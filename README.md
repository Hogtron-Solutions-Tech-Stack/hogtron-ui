# HogUI

HogTron's UI suite for **World of Warcraft: Forever** (Classic+), Anniversary (TBC) and Classic Era: healer frames (HogHeals), HUD, meter, quests & map, nameplates, chat, unit frames and a skin for Blizzard's bars, bags and tooltips.
Opinionated, small, mouseover-first. Not another ElvUI — the one good thing from each, nothing else.

> Naming: **HogUI** is the umbrella; **HogHeals** is the healer-frames module it grew out of. Addon folders keep the `HogHeals_*` names until the first public release (saved variables and every module namespace key off them).

**Status:** pre-release (0.1.0). Module 1 (`HogHeals_Frames`) built + unit-tested; in-game verification pending.

## Modules

| Addon | What |
|---|---|
| `HogHeals` | Core: profiles, `/hh` options, group-size auto-layout, combat-safe queue |
| `HogHeals_Frames` | Party + raid frames, **hover-bind engine** (any key + modifier while hovering), dispel-by-my-class, missing buffs, my shield, AoE-heal scope, thresholds, health-threshold fade, incoming heals, test mode, setup wizard |

Roadmap: HUD (castbar/mana/FSR/rank-picker) → Bars → QoL → Pad (controller). One module ships before the next starts.

## Install (dev)

```powershell
.\dev\link.ps1 -Client anniversary     # junction both addons into _anniversary_\Interface\AddOns
```

In game: `/reload`, then

```
/hh              options
/hh test 10      preview 10 fake units (also 5 / 20 / 40, "off")
/hh unlock       drag the anchor, then /hh lock
/hh wizard       re-run setup
/hh errors       show caught errors
/hh macro Flash Heal    print a mouseover→focus→target→self macro
```

## Tests

Lua 5.1 runs inside Python via `lupa` against a WoW API mock — no client needed for logic.

```bash
pip install -r requirements-dev.txt
python dev/lint.py        # syntax + toc check
python -m pytest tests -q
```

What tests cannot prove: secure-frame behaviour in combat, real header child creation, rendering. Those need
`/console scriptErrors 1` + a real dungeon pull. Release notes say which rows were run.

## Docs

- `docs/superpowers/specs/2026-09-13-hogheals-frames-design.md` — design spec
- `docs/superpowers/research/2026-09-13-healing-addon-research.md` — what VuhDo/HealBot/Cell/Grid/Clique/Danders each do best
- `docs/superpowers/plans/2026-09-13-hogheals-frames.md` — implementation plan

## Licence

MIT. Vendored libraries keep their own licences (see `LICENSE`).
