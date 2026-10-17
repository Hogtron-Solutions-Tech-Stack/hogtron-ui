# CLAUDE.md - working on HogTron UI

Read `docs/ARCHITECTURE.md` first: folders, core API, module pattern, tests. This file is the rules.

## Before you change anything
- `git status` first. Work on a branch off **current `main`** (`git fetch && git switch -c feat/<thing> origin/main`);
  a git worktree per branch is the usual setup. One concern per PR. Never push to `main` directly.
- Two people work here (Sean, Anthony). Open PRs belong to whoever opened them: don't rebase or merge someone else's.

## WoW: Forever hard rules (each one broke the addon in game once)
1. **Secret values** (health, power, heals, range, meter amounts...): show them, never compare / add / `if` / send them.
   No `tostring(x) == ...` on anything that may be secret. Use `HH.IsSecret(v)`.
2. **No restricted snippets** (`SecureHandlerExecute`, `WrapScript`, `initialConfigFunction`): Forever can't compile them.
3. **Protected in combat**: anything touching secure frames goes through `HH:RunOutOfCombat(fn)`.
4. `RegisterEvent` for events the client may lack: wrap in `pcall`. Probe `C_*` APIs before legacy globals.
5. Text: `CreateFontString(..., "GameFont*" | "HogTronFont*")` only.
6. Don't write fields on / re-parent Blizzard frames; hide, alpha and `hooksecurefunc` post-hooks are fine.

## Repo rules
- New addon folder: name starts with `HogTron_` (or it's skipped by lint/packaging), `## Dependencies: HogTronUI`,
  add it to `.pkgmeta` move-folders and `dev/link.ps1`.
- New settings: defaults in `HogTronUI/Core/Defaults.lua` (`profile.<module>`); options via `Module:GetOptions()`;
  consider a page/switch in the setup guide (`HogTronUI/Core/Setup.lua`; a test checks every path it names exists).
- Saved settings are `HogTronUIDB`. Never rename SavedVariables without a migration (a file is named after its folder).
- Diagnostics over guessing: when something can't be reproduced in the harness, add a probe that records what the
  client really does to `HH.db.global.diag.<thing>` + a `/hh <thing>diag` line, and ask for its output.
- Other addons' code/art: check the licence. All Rights Reserved = ideas only (record it in `docs/superpowers/research/`).

## Done means
```bash
python dev/lint.py            # 0 problems
python -m pytest tests -q     # all pass; new behaviour has new tests (CI has only lupa + pytest)
```
- Report status honestly: verified (show the output), built-but-unverified (say what would verify it), or blocked.
  Nothing is "working in game" until someone saw it in game.
- PR body: what changed and why, the real test/lint output, what the reviewer must check in game.
- UI changes: a rendered preview (`dev/render_*.py` -> `docs/mockups/`) beats a description.
- In game, a new file or folder needs a full restart; a code change needs `/reload`.
