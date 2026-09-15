# HogHeals Core + Frames Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `HogHeals` (core) + `HogHeals_Frames` (party/raid healer frames with a hover-bind engine) loadable on Anniversary (20505) and Era (11508), with every non-secure behaviour covered by Lua unit tests run under Python/lupa.

**Architecture:** Two addons in one repo. Core owns libs, profile DB, group-size bucketing, combat-lockdown queue, class data tables, options shell. Frames owns `SecureGroupHeaderTemplate` headers, a `UnitButton` factory, one `Update(button, unit)` function per indicator, the hover-bind engine, test mode, and its options tab. All logic that does not need a secure frame is a pure function in a file that can be loaded under the test harness with a mocked WoW API.

**Tech Stack:** Lua 5.1 (WoW), Ace3 (vendored), LibSharedMedia, LibDeflate, LibRangeCheck-3.0, LibHealComm-4.0, Python 3.14 + `lupa` (Lua 5.1) + `pytest` for tests, PowerShell junction script for install.

**Spec:** `docs/superpowers/specs/2026-09-13-hogheals-frames-design.md`

---

## File structure

```
HogHeals/
  HogHeals.toc                ## Interface: 20505,11508
  embeds.xml                  lib load order
  Libs/                       vendored (done)
  Core.lua                    namespace, RegisterModule, addon object, slash
  Core/GroupSize.lua          BucketForSize(n, isRaid) -> "solo".."raid40"
  Core/Queue.lua              RunOutOfCombat(fn), drain on PLAYER_REGEN_ENABLED
  Core/ClassData.lua          CanDispel(class, type), MissingBuffSpells(class), ShieldSpells(class)
  Core/Defaults.lua           DB defaults + per-size layout profiles
  Core/Migrate.lua            schema migrations (idempotent, ordered)
  Core/Options.lua            AceConfig root + module tab registration
  Media/palette.lua           brand colours (all user-overridable)
HogHeals_Frames/
  HogHeals_Frames.toc         ## Dependencies: HogHeals
  Frames.lua                  module entry: spawn headers on PLAYER_LOGIN, profile apply
  Layout.lua                  pure grid math
  UnitButton.lua              secure button factory + region creation
  Headers.lua                 party + raid SecureGroupHeader spawn/config
  Elements/Health.lua .. StatusIcons.lua   Update(button, unit) each
  ClickCast.lua               hover-bind engine: bindings table -> attributes + SetBindingClick
  Compat.lua                  capability flags by WOW_PROJECT_ID
  TestMode.lua                fake units
  Options.lua                 Frames tab builder
  Wizard.lua                  first-run wizard state machine + thin UI
tests/
  wow_mock.lua                minimal WoW API + frame mock
  loader.py                   loads .toc order into a lupa runtime
  test_*.py                   pytest files driving Lua asserts
dev/link.ps1                  junction into WoW AddOns
.github/workflows/test.yml    pytest on push
```

---

### Task 0: Test harness (Python + lupa)

**Files:** `tests/wow_mock.lua`, `tests/loader.py`, `tests/conftest.py`, `tests/test_harness.py`, `requirements-dev.txt`

- [ ] Write `tests/test_harness.py`:
```python
def test_runtime_has_wow_globals(lua):
    assert lua.eval("type(CreateFrame)") == "function"
    assert lua.eval("type(UnitHealth)") == "function"
    assert lua.eval("_VERSION") == "Lua 5.1"

def test_can_load_core(core):
    assert core.eval("type(HogHeals)") == "table"
```
- [ ] Run `python -m pytest tests -q` → FAIL (no conftest fixtures).
- [ ] Write `tests/wow_mock.lua` (frames as tables with SetAttribute/GetAttribute/SetPoint/RegisterEvent recorders; Unit* functions reading from a `MockUnits` table; `InCombatLockdown` reading `MockState.inCombat`; `GetNumGroupMembers`/`IsInRaid` from `MockState`; `WOW_PROJECT_ID` constants; `C_Timer.After` immediate; `GetTime`; string/table helpers `strsplit`, `tinsert`, `wipe`, `tContains`; `SetBindingClick`/`ClearOverrideBindings` recorders into `MockBindings`; `UnitAura` reading `MockUnits[unit].auras`).
- [ ] Write `tests/loader.py`: `load_toc(lua, toc_path)` reads `## ` headers, follows `.xml` includes (`<Script file>` / `<Include file>`), executes each `.lua` with `(addonName, addonTable)` varargs semantics by wrapping in `local ADDON_NAME, ADDON_TABLE = ...`.
- [ ] Write `tests/conftest.py` with fixtures `lua` (fresh runtime + mock), `core` (lua + HogHeals loaded), `frames` (core + HogHeals_Frames loaded).
- [ ] Run → PASS. Commit `test: python/lupa harness with WoW API mock`.

### Task 1: Core skeleton

**Files:** `HogHeals/HogHeals.toc`, `HogHeals/embeds.xml`, `HogHeals/Core.lua`, `tests/test_core.py`

- [ ] Test:
```python
def test_register_module(core):
    core.execute('HogHeals:RegisterModule("Demo", {OnEnable=function() end})')
    assert core.eval('HogHeals.modules.Demo ~= nil')
def test_version_string(core):
    assert core.eval('type(HogHeals.version)') == "string"
```
- [ ] toc: `## Interface: 20505,11508`, `## SavedVariables: HogHealsDB`, `## X-Curse-Project-ID:` (blank until created), load `embeds.xml`, `Core.lua`, `Core\*.lua`.
- [ ] embeds.xml order: LibStub, CallbackHandler, AceAddon, AceEvent, AceTimer, AceConsole, AceDB, AceDBOptions, AceGUI, AceConfig, AceSerializer, LibSharedMedia, LibDeflate, LibDataBroker, LibDBIcon, LibRangeCheck, LibHealComm.
- [ ] Core.lua: `HogHeals = LibStub("AceAddon-3.0"):NewAddon("HogHeals","AceConsole-3.0","AceEvent-3.0")`; `HogHeals.version = C_AddOns and C_AddOns.GetAddOnMetadata("HogHeals","Version") or GetAddOnMetadata("HogHeals","Version") or "dev"`; `HogHeals.modules = {}`; `function HogHeals:RegisterModule(name, tbl) self.modules[name]=tbl; tbl.name=name; return tbl end`; `OnInitialize` creates AceDB; `OnEnable` calls each module's `OnEnable`.
- [ ] PASS → commit `feat(core): addon skeleton + module registry`.

### Task 2: Group-size bucketing (pure)

**Files:** `HogHeals/Core/GroupSize.lua`, `tests/test_groupsize.py`

- [ ] Test table: `(1,false)->solo`, `(2,false)->party`, `(5,false)->party`, `(6,true)->raid10`, `(10,true)->raid10`, `(11,true)->raid20`, `(20,true)->raid20`, `(21,true)->raid40`, `(40,true)->raid40`, `(5,true)->raid10` (raid with 5 = raid10 layout), `(0,false)->solo`.
- [ ] Implement `HogHeals.BucketForSize(n, isRaid)`; `HogHeals:CurrentBucket()` reads `GetNumGroupMembers()`, `IsInRaid()`; fires `HogHeals.callbacks:Fire("BUCKET_CHANGED", new, old)` on `GROUP_ROSTER_UPDATE`/`PLAYER_ENTERING_WORLD` when changed.
- [ ] PASS → commit.

### Task 3: Combat-lockdown queue

**Files:** `HogHeals/Core/Queue.lua`, `tests/test_queue.py`

- [ ] Tests: runs immediately out of combat; queues in combat; drains in order on `PLAYER_REGEN_ENABLED`; a throwing fn does not stop the drain (error captured to `HogHeals.errors`).
- [ ] Implement `HogHeals:RunOutOfCombat(fn)`, `HogHeals:DrainQueue()`, register event.
- [ ] PASS → commit.

### Task 4: Class data (pure)

**Files:** `HogHeals/Core/ClassData.lua`, `tests/test_classdata.py`

- [ ] Tests: `CanDispel("PRIEST","Magic")==true`, `("PRIEST","Poison")==false`, `("SHAMAN","Poison")==true`, `("PALADIN","Magic")==true`, `("DRUID","Curse")==true`, `("MAGE","Curse")==true`, `("WARRIOR","Magic")==false`; `MissingBuffSpells("PRIEST")` contains `"Power Word: Fortitude"`; `ShieldSpells("PRIEST")=={"Power Word: Shield"}`, `("SHAMAN")=={"Earth Shield"}` — Earth Shield only if `HogHeals.Compat.hasEarthShield` (TBC+).
- [ ] Implement tables keyed by class token; Earth Shield gated on `WOW_PROJECT_ID ~= WOW_PROJECT_CLASSIC`.
- [ ] PASS → commit.

### Task 5: Defaults + migration

**Files:** `HogHeals/Core/Defaults.lua`, `HogHeals/Core/Migrate.lua`, `tests/test_defaults.py`

- [ ] Tests: defaults has `profile.frames.layouts.{solo,party,raid10,raid20,raid40}` each with `width,height,spacing,growth,groupsPerRow,groupsShown`; `raid10.groupsShown==2`, `raid20==4`, `raid40==8`; `profile.frames.indicators` toggles all boolean; `profile.frames.thresholds=={35,50}`; `profile.frames.healthFade={enabled=false,above=90}`; `Migrate.Run(db)` on `schema=nil` sets `schema=1` and is idempotent.
- [ ] PASS → commit.

### Task 6: Frames module skeleton + Layout math (pure)

**Files:** `HogHeals_Frames/HogHeals_Frames.toc`, `HogHeals_Frames/Frames.lua`, `HogHeals_Frames/Layout.lua`, `tests/test_layout.py`

- [ ] Tests for `Layout.Compute(cfg, n)` returning `{ {x,y}, ... }`: party vertical 5 units height 30 spacing 2 → y = 0,-32,-64,...; horizontal → x steps; raid `groupsPerRow=2` places group 3 under group 1; `Layout.HeaderAttributes(cfg, bucket)` returns `{point="TOP", xOffset=0, yOffset=-(h+s), columnSpacing, unitsPerColumn, maxColumns, columnAnchorPoint}` correct for growth `DOWN`/`RIGHT`.
- [ ] Frames.lua registers module `Frames`, `OnEnable` calls `Headers.Spawn()` via `RunOutOfCombat`, listens `BUCKET_CHANGED` → `Frames:ApplyProfile(bucket)`.
- [ ] PASS → commit.

### Task 7: UnitButton + Headers

**Files:** `HogHeals_Frames/UnitButton.lua`, `HogHeals_Frames/Headers.lua`, `tests/test_headers.py`

- [ ] Tests: `UnitButton.Create(name, parent)` returns frame with regions `health, power, name, healPred, dispelIcon, dispelBorder, aggroBorder, raidIcon, statusIcon, missingBuff, shieldIcon, aoeGlow, thresholds` and attributes `type1="target"`, `type2="togglemenu"`, `*type-nocombat`; `Headers.Spawn()` creates `HogHealsPartyHeader` (attrs `showParty=true, showPlayer=true, showRaid=false`) and `HogHealsRaidHeader1..8` (`showRaid=true, groupFilter="1".."8"`); `Headers.Apply(bucket)` shows party header for `party`, hides for `raid10`, shows raid headers 1..2 for `raid10`, 1..4 for `raid20`, 1..8 for `raid40`; all attribute writes happen through `RunOutOfCombat` (in-combat call queues, count of SetAttribute calls == 0 until drain).
- [ ] Implement with `CreateFrame("Button", name, parent, "SecureUnitButtonTemplate")`, `RegisterForClicks("AnyDown")`, header `initialConfigFunction` sets `SetAttribute("*type1","target")` etc. via `header:SetAttribute("initialConfigFunction", [[ self:SetAttribute("*type1","target") ... ]])` and post-creation Lua `UnitButton.Setup(button)` on `OnAttributeChanged("unit")`.
- [ ] PASS → commit.

### Task 8: Base elements

**Files:** `HogHeals_Frames/Elements/{Health,Power,Name,Range,Aggro,RaidIcon,StatusIcons}.lua`, `tests/test_elements_base.py`

Each element exposes `HogHealsFrames.Elements.<Name>.Update(button, unit)` and `.Events = {...}`.
- [ ] Tests (mock unit "party1" with `health=40,maxHealth=100,class="PRIEST",dead=false,connected=true`): Health sets bar value 40/100, class colour when `mode="class"`, deficit gradient when `mode="deficit"`; text `percent`→"40%", `deficit`→"-60", `none`→""; dead → text "Dead", ghost → "Ghost", offline → "Offline"; Power hidden when `healerOnly` and unit is not mana-user; Name truncates to `nameLength`; Range sets alpha 0.4 when `MockUnits[unit].inRange=false`; Aggro border shown when `UnitThreatSituation>=2`; RaidIcon shows index; StatusIcons shows `summon`/`res`/`readyCheck`/`leader`.
- [ ] Implement. PASS → commit per element (7 commits).

### Task 9: Healer elements

**Files:** `Elements/{Dispel,MissingBuffs,MyShield,Thresholds,AoEHealing,HealPrediction}.lua`, `tests/test_elements_healer.py`

- [ ] Dispel: given auras `{ {name="Curse of X", type="Curse"}, {name="Sleep", type="Magic"} }` and player class PRIEST → shows Magic aura, style per cfg (`icon|color|border`), colour `DebuffTypeColor.Magic`; WARRIOR → hidden; `priority` slot shows first match from `cfg.priorityDebuffs`.
- [ ] MissingBuffs: PRIEST viewing unit without `Power Word: Fortitude`/`Prayer of Fortitude` → icon shown with Fort texture; with Prayer variant present → hidden.
- [ ] MyShield: aura `Power Word: Shield` with `source="player"` → shown + remaining; `source="party2"` → hidden; Weakened Soul shown as timer.
- [ ] Thresholds: ticks at 35% and 50% of bar width (`tick[1]:GetPoint()` x = 0.35*w).
- [ ] AoEHealing: PRIEST hovering `party2` → all party units glow (own party); SHAMAN hovering `raid7` → units with `MockUnits[u].distanceTo["raid7"] <= 12.5` glow; unhover clears.
- [ ] HealPrediction: `Compat.hasNativeIncoming=true` → uses `UnitGetIncomingHeals(unit)`/`(unit,"player")`; false → LibHealComm stub `GetHealAmount`; overlay width = incoming/max * bar width; split `mine/others/all`.
- [ ] Implement. PASS → commit per element.

### Task 10: Compat flags

**Files:** `HogHeals_Frames/Compat.lua`, `tests/test_compat.py`

- [ ] Tests: `WOW_PROJECT_ID=WOW_PROJECT_CLASSIC` → `hasNativeIncoming=false, hasEarthShield=false, auraFilterAllowed=true`; `WOW_PROJECT_BURNING_CRUSADE_CLASSIC` → `hasNativeIncoming=true, hasEarthShield=true`; unknown id → conservative `{hasNativeIncoming=type(UnitGetIncomingHeals)=="function", auraFilterAllowed=type(C_UnitAuras)~="table" or C_UnitAuras.AddPrivateAuraAnchor==nil}`; `Compat.Degrade(cfg)` disables dispel/missingBuffs/myShield/healPred when `auraFilterAllowed=false`.
- [ ] PASS → commit.

### Task 11: Hover-bind engine

**Files:** `HogHeals_Frames/ClickCast.lua`, `tests/test_clickcast.py`

Binding model: `{ key="1", mod="", type="spell", value="Greater Heal" }`, `key` ∈ mouse (`BUTTON1..5`) or keyboard (`1`,`Q`,`F`...), `mod` ∈ `""|SHIFT|CTRL|ALT`.
- [ ] Tests: `ClickCast.AttributesFor(bindings)` → mouse bindings become `{["shift-type1"]="spell",["shift-spell1"]="Prayer of Healing"}`; keyboard bindings are NOT attributes; `ClickCast.Apply(button, bindings)` sets those attributes (recorded) via queue; `ClickCast.OnEnter(button)` calls `SetBindingClick(true,"1",buttonName,"hh1")` for each keyboard bind and sets attributes `type-hh1="spell", spell-hh1="Greater Heal"`; `OnLeave` calls `ClearOverrideBindings(button)`; `ClickCast.Defaults("PRIEST")` equals Sean's layout; fallback chain `ClickCast.Macro("Flash Heal", chain)` builds `/cast [@mouseover,help,nodead][@focus,help,nodead][help,nodead][@player] Flash Heal` per toggled steps; if `Clique` global exists → `Apply` is a no-op and `ClickCast.controlledBy=="Clique"`.
- [ ] Implement. PASS → commit.

### Task 12: Test mode

**Files:** `HogHeals_Frames/TestMode.lua`, `tests/test_testmode.py`

- [ ] Tests: `TestMode.Start(20)` creates 20 non-secure buttons named `HogHealsTest1..20` with fake units cycling health 20–100 and classes; every 1s (`C_Timer`) health changes; 30% of fakes carry a dispellable aura, 10% out of range; `TestMode.Stop()` hides all; refuses to start in combat (returns false, message).
- [ ] PASS → commit.

### Task 13: Options tab + slash + wizard

**Files:** `HogHeals/Core/Options.lua`, `HogHeals_Frames/Options.lua`, `HogHeals_Frames/Wizard.lua`, `tests/test_options.py`

- [ ] Tests: `HogHeals.OptionsTable()` returns AceConfig table with `type="group"`, `childGroups="tab"`, args containing `general` + one key per registered module; Frames tab has groups `layout, appearance, indicators, bindings, profiles`; every `set` writes to `db.profile.frames.*` and calls `Frames:Refresh()`; `/hh` opens; `/hh test 10`, `/hh test off`, `/hh lock`, `/hh unlock`, `/hh wizard`, `/hh errors` dispatch; `Wizard.New(class)` steps `class→layout→bindings→done`, `Wizard.Finish(state)` writes profile + bindings.
- [ ] Implement. PASS → commit.

### Task 14: Install script, syntax lint, CI, README

**Files:** `dev/link.ps1`, `dev/lint.py`, `.github/workflows/test.yml`, `README.md`, `.pkgmeta`, `LICENSE` (MIT)

- [ ] `dev/lint.py`: `loadstring` every `.lua` under the two addon folders through lupa; non-zero exit on any syntax error; prints file:line.
- [ ] `dev/link.ps1 -Client anniversary|era|all`: `New-Item -ItemType Junction` for both addon folders into `C:\Program Files (x86)\World of Warcraft\<client>\Interface\AddOns\`; `-Remove` deletes.
- [ ] CI: `pip install lupa pytest`, `python dev/lint.py`, `pytest -q`.
- [ ] Commit.

### Task 15: Settings-UI mockups (HTML → PNG)

**Files:** `docs/mockups/*.html`, `docs/mockups/*.png`, `dev/render_mockups.py`

- [ ] One HTML page per tab (General, Frames/Layout, Indicators, Bindings, Profiles, Wizard) styled as a dark WoW-ish panel with HogTron palette; render with Playwright/Chrome to 1280×800 PNG.

### Task 16 (stretch): items 6–8 design addendum + what fits

- [ ] Read Cell `RaidDebuffs/`, `Utilities/Request_Dispel.lua`, `Indicators/TargetCounter.lua` for behaviour only; write `docs/superpowers/specs/2026-09-13-addendum-items-6-8.md`.
- [ ] If time: `Elements/RequestDispel.lua` (addon-message `HH_DISPEL` from a party member → glow on their frame, `/hh dispelme` sender) — API-safe.

---

## Self-review
- Spec coverage: §3 core → T1–T5, §4.2–4.3 → T6–T7, §4.4 → T11, §4.5 → T8–T9, §4.6 → T13, §4.8 → T3 (errors captured), §4.9 → T0/T14, §4.10 → T14, test mode → T12, wizard → T13, Compat → T10, mockups → Sean's ask T15, items 6–8 → T16.
- Names used consistently: `HogHeals.RunOutOfCombat`, `HogHeals.BucketForSize`, `HogHealsFrames.Elements.X.Update`, `ClickCast.AttributesFor/Apply/OnEnter/OnLeave/Defaults/Macro`, `Layout.Compute/HeaderAttributes`, `Headers.Spawn/Apply`, `TestMode.Start/Stop`, `Compat.*`.
