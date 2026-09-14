# Healing-addon competitive research — "steal the one good thing"

Date: 2026-09-13
Purpose: feed HogHeals_Frames options design. Every claim below has a source
tag; nothing is from memory.

Sources (S1–S6):
- S1 Blizzard US forums, 10 threads, 295 posts mentioning a healing addon
  (Discourse JSON; likes not exposed so ranked by relevance, not popularity)
- S2 CurseForge project pages: Cell (4.4M dl), VuhDo (29.8M), DandersFrames (4.3M)
- S3 DandersFrames v4.3.7 on Sean's Retail client (Features/ folder, changelog)
- S4 Cell r274 on Sean's Era client (enUS locale keys)
- S5 Sean's own SavedVariables (Clique.lua on Era + Anniversary)
- S6 Fresh Forever threads 9/12–9/13 (addon-API question unanswered)

## 1. What each addon does best (and what people hate)

| Addon | The one thing it does right | Recurring complaint | Src |
|---|---|---|---|
| **VuhDo** | Bind *any* key while hovering (16 hover keys + 40 click combos), incl. items + macros. Free arrangement: any group to any panel, sort by class/group/role, drag-drop. Setup wizard. Skins + profiles stored separately, wago presets. HoT icons on bars. | "Higher learning curve"; dev quit after Midnight API cuts | S1,S2 |
| **HealBot** | Easiest out-of-box. Frees action-bar keybinds. **Health-bar colour changes by buff/debuff** for instant triage. Raid-lead overview. Accessibility: mouse-only workflow (RA user heals on bad days). Place/resize anywhere. | Mouse buttons only, can't bind keyboard keys | S1 |
| **Cell** | "Human-friendly" options UI. **Only show debuffs dispellable by me**, only buffs I can apply, only my PW:S. Glow on first debuff. Raid-debuff priority. Spotlight frames. Raid tools (ready check, rebuff, marks). Keyboard + mouse click-cast built in. | "Relies on icons for everything". Explicitly *refuses* layout-by-group-size and other click-cast addons | S1,S2,S4 |
| **Grid / Grid2** | The OG: status → indicator mapping made dispels/CC visible (KT dispeller story: 100–200 dispels/fight). Compact. | Grid2 "not quite the same" as Grid | S1 |
| **Clique** | Lightweight, keyboard hover-binds on *any* frames, item/macro binds, "bind when not over a frame too". | None — the complaint is at Blizzard's copy: no keyboard keys, L/R click steals target/menu, no items | S1,S5 |
| **DandersFrames** (post-Midnight winner) | **Aura Designer**: 8 indicator types, drag-to-place on 9 anchors, live preview. Health gradient + missing-health overlay + **health-threshold fade** (fade frames above X% HP). Heal prediction split me/others/all + overheal. Healer-only mana bar. **Auto layouts** by content + group size. Click-cast fallback chain **Focus → Mouseover → Target**; tooltip shows active bindings. Import/export. Test mode simulates health/absorbs/auras/dispels/range. Setup wizard. | Retail-only (12.0); no licence file (all rights reserved) | S1,S2,S3 |
| HealBarsClassic | Incoming heals *from other healers* on Classic | — | S1 |
| BigDebuffs | One big important debuff icon on the frame | — | S1 |
| Blizzard default frames | — | Raid frame vs character frame ambiguity eats a click slot; no "me + pet when solo"; no aura filtering; ugly | S1 |

## 2. What Sean actually does (S5)

Era Priest, Clique **keyboard hover-binds**, not mouse clicks:
`1`/`2` Greater Heal · `3` Flash Heal · `4` Renew · `F` Power Word: Shield ·
`Q` Dispel Magic · `Shift-1` Prayer of Healing · `Ctrl-2` PW: Fortitude ·
`Ctrl-4` Divine Spirit · `Button1` target · `Button2` menu.
Shaman: `1` Healing Wave. Anniversary Clique has only target/menu (fresh).

Consequence: the spec's "12 mouse-button slots" model is wrong for the
author himself. HogHeals must bind **any key or mouse button + modifier while
the cursor is over a frame**.

## 3. Steal list → HogHeals_Frames (ranked)

| # | Steal | From | Ships in |
|---|---|---|---|
| 1 | Hover-bind engine: any key/mouse button + modifier; items + macros; fallback chain Focus→Mouseover→Target; tooltip lists active binds | VuhDo, Clique, Danders | 1.0 |
| 2 | Health-threshold fade ("fade everyone above 90%") + health-bar colour by state | Danders, HealBot | 1.0 |
| 3 | Dispellable-by-me filter, user picks **icon OR bar-colour OR border** (answers Cell's "icons for everything") + one big priority-debuff slot | Cell, Grid, HealBot, BigDebuffs | 1.0 |
| 4 | Auto layout by group size (solo/party/10/20/40) — Cell refuses this, Danders proves demand | Danders | 1.0 (already in spec) |
| 5 | Setup wizard + shipped class presets, "done in 60 seconds" | VuhDo, Danders | 1.0 |
| 6 | Test mode that simulates health/auras/dispel/range, not just layout | Danders | 1.0 |
| 7 | Incoming heals split mine / others / all + overheal marker | Danders, HealBarsClassic | 1.0 |
| 8 | "Me + pet when solo" option | default-frames complaint | 1.0 |
| 9 | Profile import/export strings | Danders, Cell, VuhDo | 1.0 (in spec) |
| 10 | Accessibility preset: large frames, mouse-only workflow, fewer indicators | HealBot RA user | 1.0 as a preset |
| 11 | Free group arrangement (any group → any panel), sort by class/role | VuhDo | 1.1 |
| 12 | Aura Designer (drag-to-place indicator builder) | Danders | 1.2 — big; v1 ships fixed anchors |
| 13 | Spotlight/pinned frames (tank, focus) | Cell, Danders | 1.1 |
| 14 | Raid tools (ready check, rebuff, marks) | Cell | not Frames — later QoL module |

## 4. Landmine: Forever addon API is undecided (S1, S6)

- Midnight (Retail 12.0, Jan 2026) cut real-time combat info from the API.
  VuhDo went "incompatible" 1/20/26; its maintainer said the cuts "cripple
  most of the differentiated features". Forum consensus: **frames + click/hover
  binding survive; aura/debuff filtering and incoming heals are what die.**
- Forever's API base (Classic-open vs Midnight-restricted) is **unanswered**.
  It is in the question pool for the Live WoW Q&A on **2026-09-17**, the same
  day beta reportedly starts (launch reportedly **2026-11-04**; both dates from
  a guild recruitment post, not a blue post — treat as unconfirmed).
- Design rule adopted: HogHeals' hover-bind engine, layouts, health colouring
  and profiles must never depend on restricted data. Aura-based indicators
  (dispel filter, HoT tracking, incoming heals) live behind one
  `Compat/` capability flag so a restricted Forever degrades to
  "Danders-mode" instead of breaking.

## 5. Things NOT to copy
- Cell's icon-only indicator philosophy (explicit user complaint).
- VuhDo's options depth without a wizard in front of it.
- HealBot's mouse-only binding.
- Any code from Cell / VuhDo / DandersFrames / ElvUI — none are MIT. Patterns only.
