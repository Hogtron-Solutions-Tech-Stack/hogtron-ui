# HogHeals_HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `HogHeals_HUD` — castbar, mana bar with five-second-rule + tick spark, mana pacing, rank advisor — one anchored strip, fully unit-tested under the lupa harness.

**Architecture:** Fourth addon folder. `HUD.lua` owns the anchor strip and stacks rows; each row is a file exposing pure logic (`Step`, `Pick`, state transitions) plus a thin paint function. No secure frames. Rank data is a generated Lua table.

**Tech Stack:** Lua 5.1, Ace3 via core, LibSharedMedia, harness `tests/` (lupa + `wow_mock.lua`).

**Spec:** `docs/superpowers/specs/2026-09-14-hogheals-hud-design.md`

---

### Task 0: Generated rank data
**Files:** `dev/gen_healranks.py`, `HogHeals_HUD/Data/HealRanks.lua`, `tests/test_healranks_data.py`
- [ ] Test: `HogHealsHUD.HealRanks.era["Greater Heal"].ranks[1].avg > 800`, `.coeff` ≈ 3/3.5, `tbc["Greater Heal"]` has 7 ranks, `era["Chain Heal"]`, `tbc["Flash of Light"]` present, every rank has `rank, level, avg`.
- [ ] `gen_healranks.py`: run LibHealComm's data block in lupa twice (build 1 / build 2) with `GetSpellInfo(id)` stubbed to a name map; walk `spellData`; emit sorted Lua with attribution header.
- [ ] PASS → commit.

### Task 1: HUD skeleton + anchor strip
**Files:** `HogHeals_HUD/HogHeals_HUD.toc`, `HUD.lua`, `Options.lua` (stub), `tests/test_hud.py`
- [ ] Test: after login `HogHealsHUDAnchor` exists at profile position; rows `castbar, mana, info` frames exist; `HUD.Layout()` stacks enabled rows top→bottom with heights from profile; disabling `mana` collapses height; `/hh unlock` shows the HUD anchor too.
- [ ] Defaults added to core `Defaults.lua` under `profile.hud`.
- [ ] PASS → commit.

### Task 2: Castbar
**Files:** `HogHeals_HUD/Castbar.lua`, `tests/test_castbar.py`
- [ ] Tests (mock `UnitCastingInfo`/`UnitChannelInfo` + `GetNetStats`): START → visible, name "Greater Heal → Zugzug", latency width = 250ms/2500ms × barWidth; DELAYED extends end; STOP/SUCCEEDED hides; INTERRUPTED flashes red then hides after 0.3 s (`MockAdvance`); CHANNEL_START fills from full and drains; `hideBlizzard` unregisters `CastingBarFrame` events.
- [ ] Pure `Castbar.Progress(state, now)` → 0..1 tested directly.
- [ ] PASS → commit.

### Task 3: Mana + FSR + ticks
**Files:** `HogHeals_HUD/Mana.lua`, `tests/test_mana.py`
- [ ] Tests: bar shows mana/max + text modes; `UNIT_SPELLCAST_SUCCEEDED` with mana drop → `state.fsrEnd = now+5`, overlay shown; without drop → no FSR; mana gains outside FSR schedule `nextTick = t+2`; gain during FSR ignored; non-mana class hides the row. Pure `Mana.Observe(state, mana, t)` returns events `"fsr" | "tick" | nil`.
- [ ] PASS → commit.

### Task 4: Pacing
**Files:** `HogHeals_HUD/Pacing.lua`, `tests/test_pacing.py`
- [ ] Tests: `Pacing.Step` over a sample series (1000, 950, 900, 850…) → burn ≈ 50/s → `Eta` = 17 s; regen-only series → burn 0 → eta nil; `Project(state, targetLength)` math; text formatting `m:ss`; colours thresholds; reset on `PLAYER_REGEN_ENABLED`.
- [ ] PASS → commit.

### Task 5: Rank advisor
**Files:** `HogHeals_HUD/RankAdvisor.lua`, `tests/test_rankadvisor.py`
- [ ] Tests: `ParseRank("Rank 4")==4`; spellbook scan (mock `GetSpellBookItemName`) → known ranks; `Pick("Greater Heal", missing=1200, bonus=500, margin=0.9)` returns the lowest rank whose `avg + coeff*bonus ≥ 1080`; missing 0 → nil; unknown spell → nil; hover hook sets info text `GH r4 (1.6k)`; `/hh rankmacros` prints `/cast Greater Heal(Rank N)` for each known rank.
- [ ] PASS → commit.

### Task 6: Options tab + smoke + mockups
**Files:** `HogHeals_HUD/Options.lua`, `tests/test_hud_options.py`, `dev/render_mockups.py` (add HUD tab + strip preview)
- [ ] Tests: `OptionsTable().args.HUD` groups `layout, castbar, mana, pacing, advisor`; setters write `profile.hud.*` and call `HUD.Refresh()`; session smoke extended (cast, fight, hover) → zero errors.
- [ ] Re-render mockups (`09-hud.png`, `10-hud-strip.png`).
- [ ] Commit; `dev/link.ps1` links the third folder; push; open PR #2 stacked on `feat/frames-core`.

## Self-review
Spec §2.1→T2, §2.2→T3, §2.3→T4, §2.4→T0+T5, §2.5→T6, §1→T1. Names: `HogHealsHUD.{HUD,Castbar,Mana,Pacing,RankAdvisor,HealRanks}`; pure fns `Castbar.Progress`, `Mana.Observe`, `Pacing.Step/Eta/Project`, `RankAdvisor.Pick/ParseRank`.
