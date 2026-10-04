# Plate cast bar + party highlight + hover-heal quick bind — plan (2026-10-03)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkboxes.

**Goal:** our own cast bar under every nameplate, hover/target marks on party cells with picked styles, and a
hover-a-spell-press-a-key panel for the hover-heal bindings.

**Architecture:** three self-contained files, one per feature, each on its own branch off `origin/main` with its own
test file; existing seams only (`hooksecurefunc` on Plates, `UnitButton.RegisterElement`, `ClickCast.SetBindings`).

**Tech stack:** WoW Lua (Forever beta / mainline engine, secret values), lupa harness (`tests/`), `python dev/lint.py`,
`python -m pytest tests -q`. Spec: `docs/superpowers/specs/2026-10-03-plates-castbar-highlight-hoverbind-design.md`.

Every task: failing test first → run → implement → green → lint → commit. Push + PR to main when the task list is done.
Play merge: worktree merge + `--ff-only`, Sean warned before and after.

## A — plate cast bar (`feat/plates-own-castbar`, worktree `_wt-hh-platecast`)
- [ ] A1 defaults `plates.cast = { height, icon, time, fontSize, precision, castColor, channelColor, lockedColor }`;
      test: defaults present.
- [ ] A2 `Castbar.lua` skeleton: side table, `Build(uf)` on Skin hook, geometry under the bar; test: built on Skin,
      anchored to `hh.bar`, hidden; not built when option off.
- [ ] A3 `Quiet(uf)`: Blizzard container / castBar alpha 0 on Skin and Update; test: alpha 0 both times, Unquiet restores.
- [ ] A4 `Read(uf)` + `Show`: casting info → bar shown with name/icon/min-max/value; secret values → shown, no compare;
      channel drains; test with plain and secret mocks.
- [ ] A5 events frame + OnUpdate tick: START/CHANNEL_START show, STOP/FAILED/INTERRUPTED/CHANNEL_STOP hide, poll re-reads,
      tick throw latches `broken` + one log; Reset hides; nameOnly plates skip.
- [ ] A6 options group + platediag line + diag.plateCast; `ApplyLook` no longer calls `SkinCastbar`; toc entry.
- [ ] A7 lint, full suite, commit, push, PR; merge into play (Sean warned); in-game checklist in PR body.

## B — party highlight (`feat/frames-highlight`, worktree `_wt-hh-highlight`)
- [ ] B1 defaults `frames.highlight`, `indicators.aoeHealing = false`; test.
- [ ] B2 `Elements/Highlight.lua`: Mark builder (edges / corners / fill), `Apply(mark, cfg, on)`; test: styles show the
      right regions, colour + thickness applied, outside-the-rect anchors.
- [ ] B3 hover seam: `UnitButton.OnEnter/OnLeave` → element; test: only the hovered cell marked, cleared on leave,
      disabled indicator → nothing.
- [ ] B4 target: `PLAYER_TARGET_CHANGED` → update all; `Update` reads `UnitIsUnit`; test: moves between cells, secret → none,
      both marks on one cell.
- [ ] B5 AoE fill colour/alpha from config; options group with presets; test write-through.
- [ ] B6 lint, suite, commit, push, PR, play merge.

## C — hover-heal quick bind (`feat/frames-hover-bind`, worktree `_wt-hh-hoverbind`)
- [ ] C1 `HoverBind.Catalog(class, bindings)` + `KeyString`; tests.
- [ ] C2 panel + rows (icon ladder, name, keys), `Open/Close/Toggle`, refused in combat / Clique; tests.
- [ ] C3 `Press(key)` on the hovered row → `ClickCast.SetBindings` (move key, Esc clears spell, mouse 3–5); tests.
- [ ] C4 slash routing (`bind heals` wrap / register, `hoverbind`), options button, `PLAYER_REGEN_DISABLED` closes; tests.
- [ ] C5 "Other spell…" edit box adds a row; diag.hoverBind; lint, suite, commit, push, PR, play merge.
