# HogUI: plate cast bar, party highlight, hover-heal quick bind — design (2026-10-03)

Three asks from Sean (screenshot of a Windfury Matriarch plate casting Lightning Bolt in Blizzard's own cast-bar art):

1. "The cast bar on the nameplate looks like the old Blizzard style. Style it just like ours."
2. "Different highlighting options for which party / raid member we're highlighting — white outline, red outline, corners."
3. "Quick binding on the hover-over heals."

Decisions taken with Sean (AskUserQuestion, 2026-10-03): highlight = hover AND target, separate styles; defaults hover =
white 1 px outline, target = white corners; quick bind = a spell-list panel (`/hh bind heals`): hover a spell, press a key.

Three concerns, three branches off `origin/main` (1b3c8f8), one PR each, each merged into the play checkout only
with Sean warned first ("don't reload" / "reload"). Spec + plan live on the first branch.

---

## 1. Plate cast bar = our own bar (`HogHeals_Plates/Castbar.lua`, branch `feat/plates-own-castbar`)

### Why not keep skinning Blizzard's
`Plates.SkinCastbar` looks for `uf.castBar` / `uf.CastBar` / `CastBarsContainer.castBar`. The screenshot shows the raw
Blizzard bar: nothing was found on Forever (the plate-structure diag never recorded the cast bar's key). Even when it
is found, re-texturing Blizzard's bar leaves its icon frame, shield, border and spark, and writing textures onto a
Blizzard frame whose code handles secrets is the taint pattern that killed the adopted target cast bar (PR #51). Rule
from that landmine: hide Blizzard's, build ours.

### Look (same as the HUD player bar and the Units target bar)
- `StatusBar` child of `uf.hh.overlay`, anchored `TOPLEFT/TOPRIGHT` to `hh.bar`'s `BOTTOMLEFT/BOTTOMRIGHT`, gap 3 px,
  height `plates.cast.height` (default 10). Flat fill (`WHITE8X8`), ink backing 1 px larger, 1 px dark edges
  (`LINE`), spell icon left of the bar (square = bar height, tex-coords trimmed 0.08–0.92), name text cream left,
  remaining seconds right (`precision` 1), grey overlay over the fill while the cast cannot be interrupted.
- Colours from `plates.cast`: `castColor` cyan, `channelColor` green, `lockedColor` grey — the HUD's values copied as
  defaults so the three bars match; HUD and plates stay independently configurable.
- Hidden on name-only friendly plates (`hh.nameOnly`) and when `plates.castbar` is off.

### Data (secret-safe, copied from `Units.UpdateCastbar`)
- `UnitCastingInfo(unit)` then `UnitChannelInfo(unit)` through pcall; presence = `issecretvalue(v) or v ~= nil`.
- `SetMinMaxValues(startMS, endMS)` straight from the client (plain or secret), `SetValue(GetTime()*1000)` from our clock;
  a channel drains only when both ends are plain numbers.
- Lock marker: `SetAlphaFromBoolean(notInterruptible, 1, 0)` when secret, plain alpha otherwise.
- Name / icon rendered, never compared. Nothing in this file tests, concatenates or formats a unit value.
- Events (one frame, all units, filtered by `Plates.active[unit]`): `UNIT_SPELLCAST_START/STOP/FAILED/INTERRUPTED/
  DELAYED/CHANNEL_START/CHANNEL_UPDATE/CHANNEL_STOP`. OnUpdate while shown: move the fill, update the time text,
  re-read the client every 0.25 s so a cast whose stop event never came still ends. A throw inside the tick latches
  that bar off (`bar.broken`) and logs once — never an error per frame.
- First cast seen writes `diag.plateCast = { secretName, secretTimes, secretLock, blizzKey }`.

### Blizzard's bar
`Castbar.Quiet(uf)`: `CastBarsContainer`, `castBar`, `CastBar` (whichever exist) → `SetAlpha(0)`; re-applied on every
`Plates.Update` (Blizzard re-shows on plate reuse). No fields written on Blizzard frames — ours live in a weak-keyed
side table `Castbar.bars[uf]`. `Castbar.Unquiet` restores alpha 1 when the option is turned off.

### Wiring
Self-wired like `Hots.lua`: `hooksecurefunc(Plates, "Skin" | "Update" | "Reset")` guarded by `type(...) == "function"`
(an unguarded hook on a nil function throws at file load). `Plates.SkinCastbar` stays but is no longer called from
`ApplyLook` — the `plates.castbar` option now means "our bar".

### Options (Nameplates > Look > Cast bar)
Enabled, height, icon on/off, time on/off, text size, cast / channel / locked colours.

### Diag
`/hh platediag` gains one line: `cast bar: built=N shown=N blizzKey=<key or none>`.

### Tests (`tests/test_plate_castbar.py`, harness mock plates from `test_plates.py`)
Built on Skin; `UNIT_SPELLCAST_START` for an active plate shows the bar with name + icon; secret name/start/end
→ shown, no compare; channel drains; `STOP` hides; `Reset` hides and clears; Blizzard container alpha 0 after Skin
and again after Update; option off → nothing built; tick error latches `broken` and logs once; diag written once.

---

## 2. Party / raid highlight (`HogHeals_Frames/Elements/Highlight.lua`, branch `feat/frames-highlight`)

### Today
No target or hover mark on the cells. The only "highlight" is the cyan 25 % FILL painted on every cell in the hovered
unit's AoE scope (`aoeGlow`). Sean: "I don't like the current highlighting."

### Design
- New element `highlight`. Two marks per cell, built lazily on first use: `button.hoverMark`, `button.targetMark`.
  A mark = four edge textures (outline), eight corner arms (corners), one fill — a `style` picks which set shows.
  Styles: `outline`, `corners`, `fill`, `none`. Per mark: `color {r,g,b}`, `thick` (px), `size` (corner arm length).
- Hover: `UnitButton.OnEnter/OnLeave` → `E.OnEnter/OnLeave` (same seam as aoeHealing). Target: `PLAYER_TARGET_CHANGED`
  (non-unit event; element `Events` + an update of every button), plus `E.Update(button, unit)` reads
  `UnitIsUnit(unit, "target")` through `bool()` (secret → no mark).
- Draw order: marks sit 1 px OUTSIDE the cell rect so the red aggro border (inside) stays visible; target corners
  gap 2 px, layer OVERLAY sub-level 7 (above requestGlow 6); hover outline sub-level 7 as well — a cell that is both
  hovered and targeted shows both (outline + corners read fine together; two outlines would fight, so when both
  styles are `outline` the target one wins).
- AoE scope fill stays as its own element, default now OFF (`indicators.aoeHealing = false`); its colour / alpha get
  options (`frames.highlight.aoe`).
- Defaults: `frames.highlight = { hover = { style = "outline", color = {1,1,1}, thick = 1 },
  target = { style = "corners", color = {1,1,1}, thick = 2, size = 8 }, aoe = { color = {0.13,0.83,0.88}, alpha = 0.25 } }`.

### Options (Frames > Highlight)
Hover: style, colour, thickness. Target: style, colour, thickness, corner size. AoE scope: on/off (mirrors the
indicator), colour, alpha. Presets row: "White outline", "Red outline", "Corners" buttons that write the fields.

### Tests (`tests/test_highlight.py`)
Defaults; OnEnter shows a white 1 px outline on that cell only, OnLeave hides; target change shows corners on the
targeted cell and clears the old one; style switch rebuilds; colour write-through; secret `UnitIsUnit` → no mark;
aoe default off; both marks on one cell; TestMode fakes unaffected.

---

## 3. Hover-heal quick bind (`HogHeals_Frames/HoverBind.lua`, branch `feat/frames-hover-bind`)

### Today
Bindings are typed: key field + spell field in `/hh > Frames > Bindings`. The bars addon (play only) has `/hh bind`:
hover a slot, press a key.

### Design
- Panel `HogHealsHoverBind` (DIALOG strata, ink backing, cyan title "Hover-heal keys", instruction line). One row per
  spell: icon (`C_Spell.GetSpellTexture` → `GetSpellTexture` → letter fallback; which one worked → `diag.hoverBind.iconApi`),
  spell name (cream), current keys (grey). Rows: the class catalogue (`ClickCast.Defaults(class)` names ∪ names in the
  current bindings), deduplicated, plus an "Other spell…" edit box that adds a row.
- Hover a row → it is the target (cyan tint). Press a key → `KeyString` (ALT-/CTRL-/SHIFT- + key, lone modifiers
  ignored) → the binding list gets `{ key, mod, type = "spell", value = name }`; a key already on another spell MOVES
  (one key, one spell; chat line says what moved). Esc on a row clears every key on that spell. Mouse 3–5 bind too
  (left / right never: they are target / menu). Keys pressed with nothing hovered propagate (movement keeps working).
  Writes go through `ClickCast.SetBindings` (persisted per class, applied to every cell, combat-safe mode re-applied).
- Entry: `/hh bind heals` — Frames wraps an existing `bind` slash entry (the bars addon registers it first, load order
  is alphabetical) so `heals` opens the panel and anything else falls through; without bars, Frames registers `bind`
  itself (`heals` → panel, otherwise a one-line help). Also `/hh hoverbind` and a button in Frames > Bindings.
- Refused in combat; closes on `PLAYER_REGEN_DISABLED`; refused when Clique controls the bindings.
- `KeyString` is a copy of `Bars.Bind.KeyString` (bars is not on main; a shared Core helper is a follow-up).

### Tests (`tests/test_hoverbind.py`)
Catalogue for PRIEST holds the defaults; rows built once per spell; hover + press writes the binding; key moved off the
old spell; Esc clears that spell only; mouse buttons; modifiers; refused in combat; closes on combat; slash routing
with and without an existing `bind` entry; Clique → refused; icon ladder with and without `C_Spell`.

---

## Out of scope
Raid-wide target-of-target marks; plate cast bars on friendly name-only plates; a shared key-capture helper in Core;
the bars addon's own bind mode (play only, untouched).

## In-game unknowns (Forever)
`UnitCastingInfo("nameplateN")` secrecy in combat (handled either way, measured by `diag.plateCast`); which of
`CastBarsContainer / castBar / CastBar` exists on the plate (diag names it); `C_Spell.GetSpellTexture` presence.
