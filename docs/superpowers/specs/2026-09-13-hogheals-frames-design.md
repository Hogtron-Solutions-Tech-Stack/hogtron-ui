# HogHeals — Suite Roadmap + Module 1 (Frames) Design

Date: 2026-09-13
Status: DRAFT — awaiting Sean's review
Author: Sean Bilger + Claude (Fable 5.1)

## 0. Why

World of Warcraft: Forever (Classic+, BlizzCon 2026): beta reportedly opens
2026-09-17, launch reportedly 2026-11-04 (guild recruitment post, not a blue
post — unconfirmed); Hardcore follows "later this Winter". Sean heals (Priest 60 on Era, Resto Shaman on
Anniversary) and runs ~90 addons per client. Goal: a public CurseForge UI suite,
healer-first, called **HogHeals**, that ships module by module so something is
live at Forever launch instead of an unfinished ElvUI clone.

Competitive research: `docs/superpowers/research/2026-09-13-healing-addon-research.md`
(what VuhDo/HealBot/Cell/Grid/Clique/DandersFrames each do best; steal list).

Positioning: NOT another Cell/VuhDo. Opinionated, small, modern-looking,
mouseover-first with zero config required; customization is deep but optional.
Forever-shaped: 10-man / 20-man layouts are first-class, realmless grouping
assumed, controller mode planned as a later module because Forever ships full
controller support.

## 1. Suite structure (decomposition — APPROVED)

One repo, many addons. A core addon plus child modules, EllesmereUI-style:
each child declares `## Dependencies: HogHeals`, owns its own SavedVariables,
and can be enabled/disabled independently.

| # | Addon folder        | Purpose                                                       | Ships |
|---|---------------------|---------------------------------------------------------------|-------|
| 0 | `HogHeals`          | Core: Ace3 bootstrap, media registry, profile system, `/hh` options shell, shared utils | with #1 |
| 1 | `HogHeals_Frames`   | Party + raid frames, mouseover + click-cast healing, indicators | **first release** |
| 2 | `HogHeals_HUD`      | Healer castbar, mana bar, five-second-rule bar, rank-picker    | 2nd |
| 3 | `HogHeals_Bars`     | Action bars                                                   | 3rd |
| 4 | `HogHeals_QoL`      | Minimap, chat, tooltip, Blizzard-frame skins                  | 4th |
| 5 | `HogHeals_Pad`      | Controller healing mode layered on Frames                     | after Forever beta confirms gamepad API |

Rule: module N+1 does not start until module N is on CurseForge.
Each module gets its own spec + plan. This document fully specifies #0 and #1
only.

## 2. Targets

| Client         | TOC suffix        | Interface | Status |
|----------------|-------------------|-----------|--------|
| Classic Era    | `_Vanilla.toc`    | 11508     | primary dev + test target today |
| Anniversary/TBC| `_TBC.toc`        | 20505     | secondary test target today |
| WoW: Forever   | `_Forever.toc`    | not yet published | file created with the Vanilla interface number; corrected the day the beta client exposes its number in `.build.info` |

Decision: until Forever beta is installed, the Vanilla client is the source of
truth for API behaviour. Any Forever-only divergence is handled in a
`Compat/` layer, never by forking modules.

Retail is explicitly out of scope for v1.

## 3. Module 0 — `HogHeals` core

### 3.1 Libraries (embedded via `.pkgmeta` externals, versions pinned)
- LibStub, CallbackHandler-1.0
- Ace3: AceAddon-3.0, AceDB-3.0, AceDBOptions-3.0, AceConfig-3.0, AceGUI-3.0, AceEvent-3.0, AceTimer-3.0, AceConsole-3.0, AceSerializer-3.0
- LibSharedMedia-3.0 (fonts, bar textures, borders)
- LibDeflate (profile export strings)
- LibDataBroker-1.1 + LibDBIcon-1.0 (minimap button, off by default)

### 3.2 Responsibilities
- `HogHeals` global namespace table; modules register with `HogHeals:RegisterModule(name, tbl)`.
- Profile system: one AceDB (`HogHealsDB`) with per-character profiles and
  a spec-agnostic (Classic has no specs) "auto profile by group size" switch
  that modules may subscribe to: `solo | party | raid10 | raid20 | raid40`.
  Group size is derived from `GetNumGroupMembers()` + `IsInRaid()` and
  bucketed: 1 → solo, 2–5 → party, 6–10 → raid10, 11–20 → raid20, 21–40 → raid40.
- Media registry: registers HogTron-brand font (cream/ink/cyan palette lives
  in `Media/palette.lua`, but every colour is user-overridable).
- Options shell: `/hh` and `/hogheals` open a single AceConfig dialog with one
  tab per installed module. Modules append their option tables.
- Shared utils: class-dispel table, combat-lockdown queue, throttle helper.

### 3.3 Combat-lockdown queue (used by every module)
```
HogHeals:RunOutOfCombat(fn)
  if InCombatLockdown() then queue[#queue+1] = fn
  else fn() end
PLAYER_REGEN_ENABLED → drain queue in order
```
Any function that touches secure frames (SetAttribute, SetPoint on protected
frames, Show/Hide of secure headers) MUST go through this.

## 4. Module 1 — `HogHeals_Frames`

### 4.1 Libraries (module-local)
- **oUF** (unit-frame framework; Classic-lineage build) — frames are oUF
  spawns, so secure unit-button behaviour, event registration and element
  updates are handled by a proven layer.
- **LibHealComm-4.0** — Classic Era has no native incoming-heal API.
  `UnitGetIncomingHeals` exists on TBC-lineage; the heal-prediction element
  reads LibHealComm on Vanilla and the native API elsewhere via `Compat/`.
- **LibRangeCheck-3.0** — range fade for units outside heal range.

### 4.2 Components

```
HogHeals_Frames/
  Frames.lua            module entry, registers with core, spawns headers
  Layout.lua            pure functions: grid math, growth, anchors (unit-tested)
  Headers/
    Party.lua           oUF:SpawnHeader for party (self + 4 + pets)
    Raid.lua            oUF:SpawnHeader per raid group 1..8, sorted by group
  Elements/
    Health.lua          bar, class colour OR deficit mode, dead/ghost/offline text
    Power.lua           mana/rage/energy bar, healer-only display toggle
    HealPrediction.lua  incoming heals overlay (LibHealComm / native)
    Dispel.lua          dispellable-by-MY-class debuff icon + border colour
    Range.lua           alpha fade via LibRangeCheck
    Aggro.lua           threat border (UNIT_THREAT_SITUATION_UPDATE)
    RaidIcon.lua        raid target marker
    Name.lua            truncated name, colour by class or by reaction
    AoEHealing.lua      highlight units inside my AoE heal (PoH = my party;
                        Chain Heal = jump range from mouseover) — Cell pattern
    MissingBuffs.lua    icon when unit lacks a buff I can cast (Fort/Spirit/
                        Earth Shield/MotW); click-cast rebuff friendly
    MyShield.lua        my PW:S / Earth Shield on unit + Weakened Soul timer
    Thresholds.lua      tick marks on health bar at user % (35/50/…)
    StatusIcons.lua     summon/res pending, ready-check state, leader/assist
  ClickCast.lua         per-class spell bindings → SecureActionButton attrs
  TestMode.lua          /hh test → fake 5/10/20/40 units WITH simulated health
                        changes, auras, dispels, range (Danders pattern)
  Options.lua           AceConfig table appended to core dialog
  Compat/
    Vanilla.lua         11508 shims
    TBC.lua             20505 shims
    Forever.lua         empty until beta
  HogHeals_Frames_Vanilla.toc
  HogHeals_Frames_TBC.toc
  HogHeals_Frames_Forever.toc
```

### 4.3 Layouts
- Party layout: self + 4 party members (+ optional pet row). Vertical or
  horizontal growth.
- Raid layout: groups 1–8 as columns or rows; per-size profile picks how many
  groups to show (raid10 → 2, raid20 → 4, raid40 → 8) and frame size.
- Auto-switch on group-size bucket change from core; switch is queued through
  the combat-lockdown queue.
- Anchor: single draggable anchor per layout, lock/unlock from `/hh`.

### 4.4 Healing input — hover-bind engine
Research finding: the author himself heals with Clique **keyboard** hover-binds
(`1`/`2` Greater Heal, `3` Flash Heal, `4` Renew, `F` PW:S, `Q` Dispel Magic,
`Shift-1` Prayer of Healing). Blizzard's native click-casting cannot do this and
it is the #1 forum complaint. So the input model is a hover-bind engine, not a
mouse-button grid.

1. **Native mouseover.** Frames are secure unit buttons (oUF gives this).
   Users' existing `[@mouseover]` macros and keybinds work with no setup.
2. **Hover-bind engine (`ClickCast.lua`).** Bind **any key or mouse button,
   with any modifier**, to a spell, item, or macro. Implementation: a secure
   `OnEnter`/`OnLeave` handler on every frame calls `SetBindingClick` /
   `ClearOverrideBindings` for the keyboard slots (Clique's technique), while
   mouse buttons use `SetAttribute("type-<button>")` attributes. No slot
   limit. Bindings are per-class with optional per-profile override.
   - Target fallback chain (DandersFrames pattern): **Mouseover → Focus →
     Target → Player**, each step user-toggleable.
   - Tooltip on hover lists the active bindings for that frame.
   - Shipped defaults are Sean's real Clique layouts per class (Priest above;
     Shaman `1` Healing Wave, `2` Lesser Healing Wave, `Q` Cure Poison;
     Paladin `1` Holy Light, `2` Flash of Light, `Q` Cleanse/Purify; Druid `1`
     Healing Touch, `2` Regrowth, `3` Rejuvenation, `Q` Remove Curse).
     Defaults are a starting point, never enforced; users can clear all.
   - Attribute and binding writes go through the combat-lockdown queue.

Decision: no Clique dependency. If Clique is loaded, HogHeals frames register
with Clique's frame registry so Clique users keep their bindings, and the
built-in engine shows a notice that Clique is in control.

### 4.5 Indicators (MVP list — fixed, no additions before release)
- Health bar: class colour (default) or deficit colour scale (green→red).
- Health text: percent, deficit, or none.
- Incoming heals overlay.
- Power bar (thin, bottom), toggleable.
- Dispel indicator for debuffs the **player's class can dispel** on the current
  client. Display style is the user's choice — **icon, bar colour, or border**
  (Cell is criticised for "icons for everything"; HealBot users triage by bar
  colour). One additional "big priority debuff" slot (BigDebuffs pattern).
  Class table:
  - Priest: Magic, Disease
  - Shaman: Poison, Disease
  - Paladin: Magic, Poison, Disease
  - Druid: Curse, Poison
  - Mage: Curse
  - everyone else: none (indicator hidden)
- Range fade (alpha 0.4 out of range).
- **Health-threshold fade**: fade frames above N% health (default 90%) so
  damaged players pop (DandersFrames pattern; off by default, one toggle).
- Incoming heals split **mine / others / all**, plus overheal marker.
- "Me + pet when solo" option (default-frames complaint).
- Aggro border (red at threat status ≥ 2).
- Dead / Ghost / Offline / AFK text state.
- Raid target icon.
- Name, truncated to N characters, configurable.
- **AoE-heal highlight** (Cell `aoeHealing`): units inside my group-heal
  scope light up — Priest Prayer of Healing = own party; Shaman Chain Heal =
  units within jump range of the hovered target. Data source: group
  membership + LibRangeCheck; no aura data needed.
- **Missing-buff icon** (Cell `missingBuffs`): unit lacks a buff I can cast
  (Priest Fort/Spirit/Shadow Prot; Shaman Earth Shield; Druid MotW/Thorns;
  Paladin Blessings; Mage AI). Class table shipped, user-editable.
- **My shield** (Cell `powerWordShield`/`shieldBar`): my PW:S or Earth Shield
  active on unit, plus Weakened Soul remaining time.
- **Health thresholds** (Cell `healthThresholds`): tick marks on the bar at
  user-set percentages (defaults 35, 50).
- **Status icons** (Cell `statusIcon`/`readyCheckIcon`/`leaderIcon`): summon
  or resurrection pending, ready-check yes/no/waiting, leader/assist badge.

Aura-dependent items in this list (dispel, missing-buff, my-shield, incoming
heals) sit behind the `Compat/` capability flag from §4.11.

Explicit non-goals for v1: general buff tracking, custom aura lists, role icons
(Classic has none), leader/assist icons, spotlight/tank frames, pet frames in
raid, WeakAura-style custom indicators.

### 4.6 Customization (options tab "Frames")
- Size: width, height, spacing.
- Layout: growth direction, groups per row, party orientation.
- Font: face (LibSharedMedia), size, outline.
- Texture: bar texture (LibSharedMedia).
- Colours: every indicator colour, class-colour toggle.
- Indicators: toggle each MVP indicator.
- Click-cast: 12-slot grid with spell picker.
- **Setup wizard** on first load: class → layout preset → binding preset →
  done in under a minute (VuhDo/Danders pattern; kills the learning-curve
  complaint). Re-runnable from `/hh wizard`.
- Shipped presets: per-class defaults + an **Accessibility** preset (large
  frames, mouse-only bindings, minimal indicators — HealBot's RA-user story).
- Profiles: AceDBOptions (new / copy / delete / per-char), plus
  export/import string (LibDeflate + AceSerializer) so Sean can hand a
  profile to guildmates.

### 4.7 Data flow
```
WoW events ──► oUF element updates ──► frame visuals
Group change ──► core size-bucket ──► Frames:ApplyProfile (queued OOC)
Options change ──► AceDB profile ──► Frames:Refresh (queued OOC)
/hh test ──► TestMode fakes units (non-secure clones, never in combat)
```

### 4.8 Error handling
- All non-secure element update callbacks wrapped in `xpcall` with a
  once-per-session throttled error print (`/hh errors` shows the log). A
  broken aura never blanks a frame.
- Secure operations only via combat-lockdown queue; attempting one in combat
  logs a queued notice, never a Lua error.
- Missing library (oUF/LibHealComm not loaded) → module prints one red line and
  disables itself instead of erroring on every event.
- Profile migration: `db.global.schema` integer; migrations run in order on
  `OnInitialize`, each idempotent.

### 4.9 Testing
| Layer | Tool | Runs where |
|-------|------|-----------|
| Lint  | `luacheck` with WoW API globals file | CI on every push |
| Unit  | `busted` against a small mocked WoW API (`spec/wow_mock.lua`): Layout math, dispel table, size bucketing, profile migrations, click-cast attribute generation | CI on every push |
| Load  | in-game, `/console scriptErrors 1`, `/reload`, zero errors | Sean, every release |
| Layout| `/hh test 5`, `10`, `20`, `40` renders fake units | Sean, every release |
| Combat| real dungeon/raid pull: no "action blocked" and click-cast fires | Sean, every release |

Honesty rule for this project: Claude cannot drive the WoW client. Anything
in the bottom three rows is BUILT-UNVERIFIED until Sean reports it, with a
screenshot or the error text. Release notes state which rows were run.

### 4.10 Packaging + release
- Repo: `sbilger/hogheals`, public, MIT licence. (Remote creation waits for
  Sean's go — public repo is his call.)
- Layout: repo root holds one folder per addon (`HogHeals/`, `HogHeals_Frames/`),
  `.pkgmeta` maps externals and `move-folders` so each addon packages separately.
- Release: BigWigsMods packager GitHub Action on tag `v*` → CurseForge + Wago.
  Requires `CF_API_KEY` and `WAGO_API_TOKEN` secrets (Sean creates the
  CurseForge project; the project id goes in each `.toc` `X-Curse-Project-ID`).
- Local dev: junction from repo folders into
  `C:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns\`
  (and `_anniversary_`), plus a `dev/link.ps1` script that creates them.
- Versioning: semver; `1.0.0` = first CurseForge release of Frames.

### 4.11 Landmines (known before we start)
- **Forever addon-API stance is undecided.** Midnight (Retail 12.0, Jan 2026)
  cut real-time combat data; VuhDo went "incompatible". Forever's base
  (Classic-open vs Midnight-restricted) is in the Live Q&A question pool for
  **2026-09-17** and the beta client will show it. Rule: hover-bind engine,
  layouts, health colouring, profiles must NEVER depend on restricted data;
  aura-based indicators (dispel filter, incoming heals) sit behind one
  `Compat/` capability flag and degrade gracefully instead of erroring.
- Forever TOC interface number and any API changes unknown until beta.
  Detect: beta client `.build.info` Version field. Fix: `Compat/Forever.lua`.
- Cell already has `Cell_Vanilla.toc`, `_TBC.toc` — same multi-toc pattern;
  copy the pattern, not the code (Cell is not MIT).
- ElvUI is "All rights reserved" — do not lift code; oUF (MIT) and Ace3
  (BSD) are the safe sources.
- Secure-header attribute errors surface only in combat → `/hh test` proves
  layout, never combat safety.
- oUF Classic build: must use the current Classic-compatible branch; pin the
  commit in `.pkgmeta`.
- Sean's Era client is v1.15.8 (11508) — the `_Vanilla.toc` number must match
  or the addon shows "out of date" and stays disabled by default.

## 5. Decisions log
- 2026-09-13 Name: **HogHeals** (Sean). Two-tone wordmark rule applies to any
  logo asset (HOG cream/ink, HEALS cyan).
- 2026-09-13 Scope: whole-UI suite, decomposed into modules, Frames first (Sean).
- 2026-09-13 Frames MVP = party + raid10/20/40 layouts in first release (Sean).
- 2026-09-13 Foundation: Ace3 + oUF + LibHealComm, not a custom framework (Claude, approved).
- 2026-09-13 Controller mode deferred to module 5 pending Forever beta (Sean: keyboard/mouse only).
- 2026-09-13 Public repo + MIT (Claude default; Sean to confirm at spec review).
- 2026-09-13 Input model = hover-bind engine (any key + modifier while hovering),
  not a mouse-button grid — driven by Sean's own Clique config + forum research.
- 2026-09-13 Steal list adopted from research doc; items 1–10 in 1.0, 11–14 deferred.
- 2026-09-13 Cell indicators added to Frames 1.0 (Sean): aoeHealing, missingBuffs,
  my shield, healthThresholds, status/readyCheck/leader icons. Parked: raidDebuffs +
  Request_Dispel → later `HogHeals_RaidDebuffs` data pack after beta. Deferred:
  crowdControls, targetCounter (PvP), Utilities → QoL module.
- 2026-09-13 Cell licence = all rights reserved / private-mod only → patterns
  and feature lists only, zero code reuse (verified from LICENSE.txt on disk).

## 6. Out of scope for this spec
Modules 2–5 (each gets its own spec). Retail support. Buff tracking.
Custom aura editor. Any HogTron marketing assets.
