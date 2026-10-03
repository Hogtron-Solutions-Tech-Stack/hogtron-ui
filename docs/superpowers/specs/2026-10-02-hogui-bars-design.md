# HogUI Bars — design (2026-10-02)

**Sean's ask (10/02):** "make the action bars section of HogUI a separate thing, kind of like Bartender. More
settings: always show the slots, turn them on and off, quick binding (click a button, hover a slot, hit the key).
Look into Bartender and see what they use."

**Decisions (Sean, 2026-10-02, via AskUserQuestion):** own bars on LibActionButton-1.0 (Blizzard's bars hidden);
first layout = HogUI default stack; bind mode = hover + press, Esc clears, modifiers combine, per character.

## What Bartender4 uses (read on disk, `_anniversary_/Interface/AddOns/Bartender4` 4.17.4, Midnight-ready)

- **LibActionButton-1.0** (minor 145, **BSD**) — the button engine ElvUI/Bartender run on: secure action buttons
  with paging states, drag-and-drop, cooldowns, charges, range/mana colouring, hotkey + macro text, flyouts,
  **already secret-aware** (`Midnight` flag; GetActionCount paths disabled on secrets). We vendor it.
- **LibKeyBound-1.0** — hover + press binder. No licence header we can verify → **not vendored**; our own bind
  mode is ~150 lines over LAB's `GetBindingAction / GetHotkey / SetKey / ClearBindings`.
- **LibButtonGlow-1.0** (BSD, optional dep of LAB) — proc glow. Vendored.
- Bartender's own code is *All rights reserved* → feature list and API usage patterns only, nothing copied:
  `SecureHandlerStateTemplate` bar frames, `RegisterStateDriver(bar, "page", …)` for bar-1 paging,
  `RegisterStateDriver(bar, "vis", …)` for visibility conditions, `HideBase()`/reparent-to-hidden for Blizzard's
  bars (Edit Mode overrides `Hide`), `showgrid` per bar.

## Shape

New addon folder **`HogHeals_Bars`** (display "HogUI Bars"), `## Dependencies: HogHeals`. Registers as module
`Bars` (`HH:RegisterModule`). When enabled, `HogHeals_Skin`'s `actionbars` part stands down (it only restyles
Blizzard's buttons, which are now hidden).

```
HogHeals_Bars/
  HogHeals_Bars.toc
  Libs/LibActionButton-1.0/   (vendored, BSD)   Libs/LibButtonGlow-1.0/ (vendored, BSD)
  Bars.lua      bar factory + layout + Blizzard hide + flat skin via LAB callbacks
  Bind.lua      bind mode (/hh bind)
  Pet.lua       pet bar (T4)      Stance.lua  stance / shapeshift bar (T4)
  Options.lua   Bars tab
```

### Bars
- Bars 1–8 map to Blizzard's action slots so every spell stays where the player put it:
  bar 1 = slots 1–12 **paged** (`[bar:2]2;[bar:3]3;[bar:4]4;[bar:5]5;[bar:6]6;[bonusbar:1]7;…;1`),
  bar 2 = 61–72 (BottomLeft), bar 3 = 49–60 (BottomRight), bar 4 = 25–36 (Right), bar 5 = 37–48 (Left),
  bars 6–8 = 145–156 / 157–168 / 169–180 (MultiBar5–7) where the client has them.
- Each bar: `SecureHandlerStateTemplate` frame `HogUIBar<n>`, LAB buttons `HogUIBar<n>Button<i>`,
  `keyBoundTarget` = Blizzard's binding name for that slot (`ACTIONBUTTON<i>`, `MULTIACTIONBAR<k>BUTTON<i>`) so
  existing keybinds keep working and hotkey text is right.
- Per-bar settings: enabled, buttons (1–12), buttons per row, padding, scale, alpha, anchor point + x/y,
  **show grid** (empty slots always drawn), fade out (alpha when not hovered, delay), click-through, visibility
  (always / hide in combat / hide out of combat / hide with pet / custom macro conditional), hotkey + macro text.
- Global: lock (drag only under `/hh unlock`, same handle look as the frames), hotkey font size, hide macro text,
  cooldown numbers, flat look (ink backdrop, 1 px outline, trimmed icon — the HogUI cell), out-of-range red,
  out-of-mana blue.
- HogUI default stack: bar 1 bottom-centre (y 60), bar 2 above it, bar 3 above that; bars 4 and 5 vertical on the
  right edge (1 per row); bars 6–8 off; pet + stance above bar 3.
- Blizzard: `MainMenuBar` left alive (Skin's XP bar lives on it); `MultiBar*`, `ActionButton1-12` and the
  `MultiBar*Button*` reparented to a hidden frame with events unregistered, `HideBase()` where Edit Mode owns
  `Hide`. `ActionBarUpButton/Down`, `MainMenuBarPerformanceBar` hidden.

### Bind mode (`/hh bind`, Options > Bars > "Key bindings")
- Refused in combat. A cream instruction strip appears ("Hover a slot, press a key. Esc clears. /hh bind to stop.").
- Hovering any of our buttons shows its current keys in a small panel next to it; the hovered button is the
  target. A key-capture frame (`EnableKeyboard`, `OnKeyDown`) turns the press into Blizzard's binding string:
  modifiers from `IsShiftKeyDown/IsControlKeyDown/IsAltKeyDown` (`SHIFT-CTRL-F`), mouse buttons 3–5 via
  `OnMouseDown`. `button:SetKey(key)` (LAB: `SetBinding` + `SaveBindings`), `ESCAPE` → `button:ClearBindings()`.
  Per character: `SaveBindings(2)` when the character set is active, else `SaveBindings(1)`.
- Leaving bind mode or entering combat (`PLAYER_REGEN_DISABLED`) ends it and repaints hotkeys.

### Secret-safe
LAB owns every cooldown / count / range read. Our layer never does arithmetic on button state: layout, config,
bindings and the flat look only. Harness: LAB is **stubbed** (`lib_stubs.lua`: `CreateButton` returns a mock
button recording `SetState / UpdateConfig / SetKey / ClearBindings / GetBindingAction`), so tests cover our
layer and the real lib runs only in the client.

### Not in v1
Masque, flyout art, extra action bar, vehicle bar, totem (multi-cast) bar, profiles-per-spec switching,
Blizzard-art bars. Pet / stance land in T4.

## Risks / unknowns (Forever)
- `NUM_ACTIONBAR_BUTTONS`, `MultiBar5-7` existence, `bonusbar` states, `HasOverrideActionBar` → probed at load,
  bars that do not exist on the client are not built; `/hh barsdiag` prints what was found.
- Edit Mode owning `Hide` on bar frames: `HideBase()` first, else `Hide()`, then reparent (Bartender's order).
- LAB on toc 16001: LAB declares 120000/120001; Forever reports project 1 (Mainline). The `Midnight` flag keys off
  build >= 120000 — Forever's build is 70170 (1.60.1) so LAB will think *pre-Midnight* while the client hands out
  secrets. **First in-game check: an action button's count/charge text without a Lua error.** If it errors,
  patch the vendored lib's `Midnight` flag to `issecretvalue ~= nil` (one line, documented in Libs/README).
