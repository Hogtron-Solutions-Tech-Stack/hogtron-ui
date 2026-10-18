# HogTron UI: how the code is set up

A UI suite for **WoW: Forever** (and the Classic Era / TBC Anniversary clients): healer party/raid frames, unit frames,
action bars, a cast/mana/XP HUD, nameplates, quest tracker and dialog, a dungeon guide and journal, a damage meter,
chat, a skin for Blizzard's windows, end-of-run awards. Lua 5.1, no build step; tests run the real Lua in Python.

Repo: `Hogtron-Solutions-Tech-Stack/hogtron-ui` (MIT). CurseForge project 1744106 ("HogTron UI").

## 1. The addon folders

Each top-level folder is one WoW addon (its own `.toc`). Every module depends on the core.

| Folder | What | Size |
|---|---|---|
| `HogTronUI` | **Core.** Settings DB, options window, slash commands, combat queue, look/fonts, setup guide, edit mode, diag. Vendored libraries in `HogTronUI/Libs`. | 18 files, ~4.3k lines |
| `HogHeals_Frames` | Healer party + raid frames (the "HogHeals" product): elements, hover-bind keys, click-cast grid, test mode | 34 files, ~4.9k |
| `HogTron_Units` | Player / target / target-of-target / pet / focus frames | 3 files, ~1.2k |
| `HogTron_HUD` | Cast bar (+ themes), swing timer, mana + five-second rule, XP bar, rank advisor, mana pacing | 10 files, ~2.3k |
| `HogTron_Bars` | Own action bars (LibActionButton) | 4 files, ~1.3k |
| `HogTron_Plates` | Nameplates: flat bar, target mark, quest mobs, own cast bar, DoesItDie, object glow | 7 files, ~2.8k |
| `HogTron_Quests` | Quest tracker + GO row, quest dialog, waypoint, auto accept/turn-in, minimap pins, button drawer, world map | 15 files, ~5k |
| `HogTron_Atlas` | Dungeon guide: levels, bosses, loot, upgrades, attunements, where-next | 25 files, ~4.4k |
| `HogTron_Journal` | Healer's dungeon journal (what to dispel / shield / kick per boss) | 5 files, ~1.3k |
| `HogTron_Meter` | Damage / healing meter over Blizzard's own meter data (`C_DamageMeter`) | 2 files, ~0.9k |
| `HogTron_Chat` | Chat restyle, URL copy, short channels | 2 files |
| `HogTron_Skin` | Blizzard's action bars, bags, menu bar, tooltips, windows in the HogTron look; info bar; auto sell/repair | 10 files, ~2.8k |
| `HogTron_Training` | What's waiting at your class trainer | 2 files |
| `HogTron_Awards` | End-of-run awards screen (75 awards, group sync over addon messages) | 7 files, ~2k + 75 icons |
| `HogHeals` | **Settings bridge** only (from the 2026-10-15 folder rename). Loads the old `HogHealsDB` so the core can take it over once. Delete after a release or two. | 1 file |

**Naming rule:** every addon folder must start with `HogHeals` or `HogTron` - lint, packaging, the release-zip check
and several static tests find folders by those two globs. A folder named anything else is silently skipped.

## 2. The core (`HogTronUI`)

`HogHeals` is the core's global addon object (an AceAddon; the name is internal and stays). In code it is `HH`.

Load order (`HogTronUI.toc`): `Core.lua` -> `Core/Look.lua`, `GroupSize`, `Queue`, `ClassData`, `Defaults`, `Migrate`,
`Legacy`, `Options`, `Panel`, `Setup`, `EditMode`, `Perf`, `AtlasProbe`, `Session`, `ChatKey`, `Tray`.

| API | Use |
|---|---|
| `HH:RegisterModule(name, tbl)` | Register a module. `tbl.OnInitialize` runs when the DB exists, `tbl.OnEnable` at login, `tbl.OnProfileChanged` on profile switch, `tbl:GetOptions()` returns its AceConfig-style options table (rendered as a page in `/hh`). |
| `HH.db` | AceDB. `HH.db.profile.<module>` settings (shared by characters on the same profile), `HH.db.global` account-wide (diag lives in `global.diag`), `HH.db.char` per character. |
| `HH.defaults.profile` | All defaults, in `Core/Defaults.lua`. Add your module's block there. |
| `HH:RegisterSlash(word, fn, help)` | `/hh <word> ...` (HogTron Awards also claims `/htr` as an alias for `/hh`). |
| `HH:RunOutOfCombat(fn, ...)` | Run now, or queue until combat ends. **Every** change to a secure/protected frame goes through this. |
| `HH:SafeCall(obj, method, ...)` | Call a module method with errors caught and logged. |
| `HH:LogError(msg)` | Record an error (`/hh errors`, and on disk in `global.diag.errors`). |
| `HH:Print(...)` | Chat line with the HogTron UI prefix. |
| `HH.Panel` | The options window (`Core/Panel.lua`): renders AceConfig-style tables with our own widgets. `Panel.Open(source)` can render any table (the setup guide does). Painted vs flat look = `profile.look.menus` (flat is the default). |
| `HH.Look` | Fonts and bar textures; `HogTronFont*` font objects. Text must use `GameFont*` or `HogTronFont*` templates (a test checks). |
| `HH.Setup` | The setup guide (`/hh setup`): 13 pages that write real settings; opens once on every character's first login (`db.char.setupDone`). Add a page with `step(key, title, module, build)`. |
| `HH.IsSecret(v)` | True when a value is a WoW: Forever secret (see 4). |

Settings are saved as `HogTronUIDB` (+ `HogTronUIDBBackup`, a defaults-free copy refreshed at init and logout). The core
guards against the client handing over an empty or swapped SavedVariables table (`/hh svinfo` explains what it saw).

## 3. A module, by example

```
HogTron_Training/
  HogTron_Training.toc     ## Dependencies: HogTronUI   + the files in load order
  Data/WeaponTrainers.lua  data only
  Training.lua             HogHealsTraining = HogHealsTraining or {} ; local Module = {} ; HH:RegisterModule("Training", Module)
```

Each module keeps its code in one global namespace table (`HogHealsFrames`, `HogHealsHUD`, `HogHealsPlates`,
`HogHealsQuests`, `HogHealsAtlas`, `HogHealsSkin`, `HogTronAwards`, ...). Settings: `HH.db.profile.<module>` with
defaults in `Core/Defaults.lua` (or filled lazily by the module). Options: `Module:GetOptions()` -> a group with
tabs. Diagnostics: a `/hh <thing>diag` command that writes to `HH.db.global.diag.<thing>`, so evidence survives to disk.

## 4. WoW: Forever rules (measured, not assumed - break these and it breaks in game)

- **Secret values.** Unit health, power, incoming heals, range results, damage-meter amounts and more come back as
  opaque "secrets". You MAY: show them (`FontString:SetText`, `StatusBar:SetValue`), `tostring`, `string.format("%d")`,
  concatenate. You MAY NOT: compare (`==`, `<`), do arithmetic, use them in an `if`, or send them. `tostring(secret) == "x"`
  throws (a static test scans for it). Use `HH.IsSecret(v)` and fall back.
- **No restricted snippets.** Forever cannot compile secure snippets (`SecureHandlerExecute`, `WrapScript`, header
  `initialConfigFunction`...): `RestrictedExecution.lua: loadstring_untainted == nil`. Configure secure frames from plain
  Lua, out of combat, via `HH:RunOutOfCombat`.
- **Protected in combat.** `SetSize`, `SetPoint`, `Show/Hide`, `SetAttribute`, bindings on secure frames: only out of
  combat. In-combat attempts are logged as `ADDON_ACTION_BLOCKED` (`/hh errors`).
- **Unknown events throw.** `RegisterEvent` on an event this client lacks raises an error: wrap it in `pcall`.
- **APIs differ by client.** Legacy globals (`GetSpellInfo`, `UnitAura`, `GetSpellBookItemName`...) are missing on
  Forever; probe `C_*` first, legacy second. `/hh apicheck` and the core's client snapshot record what exists.
- **Don't touch Blizzard frames' fields** whose own code handles secrets (re-parenting, stubbing, writing fields taints
  them). Hide/alpha and post-hooks (`hooksecurefunc`) are fine.
- **No combat log for addons.** Per-player combat numbers only via `C_DamageMeter` (ranked lists, secret amounts).

## 5. Tests and tools

```bash
pip install -r requirements-dev.txt      # lupa, pytest (that's all CI has: no numpy / Pillow in tests)
python dev/lint.py                       # Lua 5.1 syntax of every addon file + every toc entry exists
python -m pytest tests -q                # ~1240 tests, ~1 min
```

- `tests/wow_mock.lua` is a WoW API mock (frames, units, events, timers via `MockAdvance`, secrets via `MockSecret`).
  `tests/loader.py` loads addons from their `.toc` like the client. Fixtures in `tests/conftest.py` (`core`, `frames`, `hud`, ...).
- A new feature ships with tests in `tests/test_<feature>.py`. Mutation-check the important ones (break the code, see a test fail).
- `dev/render_*.py` render PNG previews of UI from the real code in the harness (Playwright / Pillow; dev-only), into `docs/mockups/`.
- `dev/package.py --write` builds a tester zip; `dev/check_release_zip.py <zip>` checks every addon folder is top-level.
- `dev/link.ps1 -Client beta` links the addon folders into a WoW install (directory junctions). A NEW addon folder or
  new file in a `.toc` needs a **full WoW restart**; code changes need `/reload`.

CI (`.github/workflows/test.yml`): lint + tests + package check on every push. Release (`release.yml`): pushing a `v*`
tag builds with the BigWigs packager (`.pkgmeta`) and uploads to CurseForge / Wago / GitHub. **Any new addon folder must
be added to `.pkgmeta` move-folders**, or it ships nested and never loads (the package job fails loudly).

## 6. In-game diagnostics (ask the tester for these, don't guess)

`/hh errors` (caught errors), `/hh svinfo` (settings load forensics), `/hh apicheck` (client capabilities),
`/hh skindiag` (skin + which Blizzard art is still showing per window), `/hh under` (what's drawn under the cursor),
`/hh framediag`, `/hh platediag`, `/hh barsdiag`, `/hh meterdiag`, `/hh questdiag`, `/hh awards probe`, `/hh journal probe`.
Most write to `HogTronUIDB.global.diag` too: `WTF/Account/<acct>/SavedVariables/HogTronUI.lua` after a `/reload` or logout.

## 7. Docs

- `docs/superpowers/specs/` design specs, `plans/` implementation plans, `research/` other addons studied (with their
  licences - several are All Rights Reserved: ideas only, never code or art).
- `docs/mockups/` rendered previews, `docs/REVIEW-*.md` review notes, `docs/TESTERS.txt` tester instructions.
