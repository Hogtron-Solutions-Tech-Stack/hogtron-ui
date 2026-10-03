# HogUI Bars — plan (2026-10-02)

Spec: `docs/superpowers/specs/2026-10-02-hogui-bars-design.md`. Branch `feat/hogui-bars` off play (the Skin /
Atlas / Plates work this leans on is not on main yet). Every task: tests in `tests/test_bars.py`, lint clean,
merged into play when its checklist is green. **New folder ⇒ `dev\link.ps1 -Client beta` + full client restart**
before anything shows in game.

## T0 — skeleton (no behaviour)
- [x] `HogHeals_Bars/` + toc (`## Dependencies: HogHeals`, `## Interface: 20505,20506,11508,11509,16001`), `Libs/`
      with vendored `LibActionButton-1.0` + `LibButtonGlow-1.0` (BSD headers kept; `Libs/README.md` = origin +
      version + any local patch), `Bars.lua` registering module `Bars`, `Options.lua` with an empty tab.
- [x] `dev/link.ps1`: folder added. `HogHeals/Core/Defaults.lua`: `profile.bars` defaults (HogUI stack).
- [x] Harness: `tests/loader.py` STUBBED += `LibActionButton-1.0`, `LibButtonGlow-1.0`; `tests/lib_stubs.lua`
      fake LAB (`CreateButton` → mock Button with `SetState/UpdateConfig/SetKey/ClearBindings/GetBindingAction/
      GetHotkey/UpdateHotkeys/NewHeader/ClearStates`, recorded).
- [x] Test: module registers, options table exists, no errors at login.

## T1 — bars 1–5: layout, grid, flat skin, Blizzard hidden
- [x] `Bars.Create(n)`: `SecureHandlerStateTemplate` bar frame, LAB buttons with slot mapping + `keyBoundTarget`,
      `Bars.Layout(n)` (buttons / perRow / padding / scale / alpha / anchor), `showGrid` per bar + global.
- [x] Flat look through `lib.callbacks.OnButtonCreated` (ink backdrop, 1 px outline, trimmed icon, hotkey font).
- [x] `Bars.HideBlizzard()` (reparent + HideBase, buttons' events off); Skin `actionbars` part yields when
      `HogHealsBars` is enabled.
- [x] Drag under `/hh unlock` (handle + saved point like the frames); `Bars.Refresh()` on profile change.
- [x] `/hh barsdiag`: which Blizzard bars existed, how many buttons built, slot mapping in force.
- [x] Tests: 5 bars built with right slot ids + binding names; layout maths (perRow wrap, padding, growth);
      grid flag passed to `UpdateConfig`; Blizzard bars reparented; options write-through; drag saves point.

## T2 — bind mode
- [x] `Bind.lua`: `/hh bind` + options button; refused in combat; instruction strip; hover target; key capture
      → binding string with modifiers; mouse 3–5; `SetKey` / `ClearBindings`; `SaveBindings(set)`; ends on
      `PLAYER_REGEN_DISABLED`; hotkeys repainted.
- [x] Tests: key string building (modifiers, mouse buttons, Esc), target follows hover, refused in combat,
      per-character set chosen, exit repaints.

## T3 — paging, visibility, fade, click-through
- [x] Bar 1 page driver (`[bar:2]2;…;[bonusbar:1]7;…;1`) via `_onstate-page` + `SetState` per button.
- [x] Per-bar `vis` driver from the visibility option (always / combat / out of combat / pet / custom).
- [x] Fade out (alpha + delay, OnEnter/OnLeave on the bar and its buttons), click-through (`EnableMouse(false)`).
- [x] Tests: driver strings, state registration calls, fade alpha, click-through.

## T4 — pet + stance bars
- [x] Pet bar (10 `SecureActionButtonTemplate` buttons, `type = "pet"`, `action = i`, icons from
      `GetPetActionInfo`, autocast border), stance bar (`GetNumShapeshiftForms`, `type = "spell"` by form).
- [x] Both: same layout engine, flat look, bind mode targets (`BONUSACTIONBUTTON<i>`, `SHAPESHIFTBUTTON<i>`).
- [x] Blizzard's `PetActionBar` / `StanceBar` hidden; Skin yields.

## T5 — polish (OPEN)
- [ ] Options: presets ("HogUI stack", "Two rows", "Blizzard-like"), per-bar copy, reset.
- [ ] Review doc for Sean + memory update + PR to main once Skin/Atlas land there.

## In-game verification order (Sean, after link + restart)
1. Bars appear in the HogUI stack, spells in the same slots as before, keybinds still fire.
2. `/hh bind` → hover slot → press key → hotkey text updates; Esc clears.
3. Empty slots visible with grid on, gone with grid off.
4. Enter combat: no Lua errors (secrets), cooldown swipes and counts draw.
