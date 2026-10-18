# HogTron UI on CurseForge: one install for everything, single modules too

Sean 2026-10-18: "I also want to be able to have them install the Hogtron UI, but some of the other ones underneath it
can be individual installs. Like, you can look them up on Curse Forge as well. ... look at maybe some of the, like,
all-in-one add-ons to see if they do that."

## What the big multi-part addons do (their own .pkgmeta, fetched 2026-10-18)

| Addon | How it is split on CurseForge |
|---|---|
| Deadly Boss Mods | `DeadlyBossMods/DeadlyBossMods` packages **DBM-Core** (+ current raids). Dungeons (`DBM-Dungeons` repo, packaged as `DBM-Party-Vanilla` + the other expansions' folders) and PvP (`DBM-PvP`) are **separate repos = separate CurseForge projects**, each needing DBM-Core. |
| BigWigs | **BigWigs** (core, options, plugins, current raids) is one project; **LittleWigs** (dungeons) is another, from its own repo, needing BigWigs. |
| Masque | **Masque** is the core; every skin pack is its own project that needs Masque. |

The pattern: **a core project, plus optional packs, and no folder ever ships in two projects.** A pack declares the
core as a *required dependency*; the CurseForge app installs the core with it. None of them ships a module both inside a
bundle and on its own: two projects carrying the same folder fight over it in the CurseForge app.

The packager we already use (BigWigsMods/packager) supports exactly this, per its README:
`required-dependencies` / `optional-dependencies` in the .pkgmeta (set as relations on the uploaded file),
`-m pkgmeta.yaml` (a different config per project, same repo), `-p curse-id` (upload to a different project).

## Recommended shape for us

| CurseForge project | Ships | Requires |
|---|---|---|
| **HogTron UI** (today's project 1744106) | a tiny "HogTron UI (everything)" stub folder | HogTron UI Core + all 13 modules |
| **HogTron UI Core** (new) | `HogTronUI` (+ the `HogHeals` settings bridge while it exists) | - |
| **HogTron UI: Action Bars**, **: HUD**, **: Nameplates**, **: Unit Frames**, **: Healer Frames**, **: Quests & Map**, **: Skin**, **: Meter**, **: Atlas**, **: Awards**, **: Journal**, **: Chat**, **: Training** (13 new) | its one folder | HogTron UI Core |

- "Install HogTron UI" still gets a player everything (the app pulls Core + every module as dependencies).
- "Install HogTron UI: Nameplates" gets just the nameplates + Core.
- Every module already declares `## Dependencies: HogTronUI` and nothing else, so each loads with Core alone. Some
  features lean on a sibling when it is present and stand down when it is not (nameplate quest marks use Quests).
- Why the existing project becomes the everything-package and not the core: if 1744106 stayed the core *and* required
  every module, installing one module would pull the core, which would pull every module. A separate Core avoids that
  loop.

## What is built (dev/split, this PR)

- `dev/split/projects.json` - the one table: Core, 13 modules, their CurseForge ids / slugs (empty for now).
- `dev/split/make_pkgmeta.py --write` - generates `dev/split/pkgmeta/<project>.pkgmeta`: each packs only its own
  folder(s), carries the repo .pkgmeta's ignores (Awards' source art), and requires Core once Core's slug is filled in.
- `dev/check_release_zip.py --only <folders>` - a module zip must hold exactly its folder(s).
- `.github/workflows/release.yml` jobs `split-matrix` + `split` - every project is **built and zip-gated on every
  push / PR**; a project is **uploaded only on a tag and only once its curse_id is filled in**. Until then they ship
  nothing, and the all-in-one release is untouched.
- `tests/test_split_packaging.py` - every addon folder in exactly one project, configs current, gate behaviour.

## What Sean does to go live (in this order)

1. On CurseForge, create **HogTron UI Core** and the 13 module projects (WoW addon, same category / art as HogTron UI;
   descriptions can reuse `docs/curseforge/description.md`). ~5 min each.
2. Send me each project's **id** and **slug** (both on the project page). I fill `dev/split/projects.json`, regenerate,
   and turn 1744106 into the everything-package (stub folder + required dependencies) in one PR.
3. Tag the next release. Core + modules upload as their own files; 1744106 uploads the everything-package.

## Risks / open questions

- **Existing installs of 1744106.** On the update where it becomes the everything-package, the CurseForge app removes
  the module folders that came with 1744106 and installs them again from their own projects (same folder names, so
  settings are untouched: they live in `HogTronUIDB` by folder name). Test this once on a second machine (Anthony) with a
  beta tag before a public release.
- **Wago / WoWInterface** have no dependency auto-install comparable to CurseForge's; on those, keep the all-in-one zip.
- **Size.** Core carries all shared art (24 MB, mostly the cast bar strips). A nameplates-only install still downloads
  it. Moving each module's art into its own folder is possible later.
- Release cost: 15 uploads per tag instead of 1 (automatic; ~2 min of CI more).
