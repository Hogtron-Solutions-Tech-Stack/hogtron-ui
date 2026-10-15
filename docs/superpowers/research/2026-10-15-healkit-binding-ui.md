# HealKit — inspiration source for the Click-cast tab

Date: 2026-10-15
Branch: `feat/binding-ui` (items 1-3: click-cast grid, per-class suggested layouts, resurrect-if-dead)

**Source:** HealKit, CurseForge, WoW: Forever flavor, by OzwaldTinker, versions 1.60.1 / 0.57.0.
**Licence: All Rights Reserved.** HogHeals is MIT. Nothing from HealKit's code, assets or text is copied into this
repo. Patterns and UX only — the same rule as `2026-09-13-healing-addon-research.md` (Cell / VuhDo / DandersFrames).

Provenance: the HealKit facts above (author, flavor, versions, licence) and the patterns below come from Sean's
brief of 2026-10-15. HealKit's source was not opened or read while building this branch; every line of HogHeals'
implementation was written from the WoW API and this repo's existing code.

## Patterns taken (ideas, not code)

| HealKit pattern | HogHeals implementation |
|---|---|
| Slot grid: mouse button rows x modifier columns | `ClickGrid.BUTTONS` x `ClickGrid.MODS`, 5x5 (Left/Right/Middle/4/5 x None/Shift/Ctrl/Alt/Meta-or-Cmd) |
| Right-click a slot to pick a spell from the spellbook | Picker reads the live spellbook (`GetSpellBookItemName` / `GetSpellBookItemInfo`, `C_SpellBook` on modern clients), helpful + non-passive only, no hardcoded spell lists |
| Per-slot rank: highest (auto-upgrade) or a pinned rank | `rank = "highest"` casts the bare name (client picks the top rank, new ranks apply at once); a number casts `Name(Rank n)` |
| Bindings per character, not per profile | `## SavedVariablesPerCharacter: HogHealsFramesCharDB` (+ a mirror in `HogHealsDB.char` against SavedVariables loss) |
| Same click resurrects a dead target out of combat | `/cast [@mouseover,dead,nocombat] <ClassRez>; [@mouseover,help,nodead] <Spell>` |

## Where HogHeals deliberately differs

- Plain Left / plain Right click are left free by the suggested layouts (they keep target / menu).
- No restricted snippets: WoW: Forever cannot compile them (see `HogHeals_Frames/Headers.lua`), so slots are plain
  secure attributes written out of combat.
- Runs next to the keyboard hover-bind engine instead of replacing it.
