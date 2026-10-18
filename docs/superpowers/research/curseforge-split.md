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

## Status (2026-10-18)

- **All 14 projects exist** (created through a scripted Chrome window on Sean's account, his approval per project set):
  HogTron UI Core 1753233 (`hogtron-ui-core`) and the 13 modules 1753242 - 1753265 - ids and slugs in
  `dev/split/projects.json`. CurseForge holds each new project for moderator review; a project only shows publicly
  once approved (moderators usually look at the first file).
- Every module's packager config now requires `hogtron-ui-core`.
- **`live` is true** (2026-10-18): the next tag uploads a first file to each of the 14, which is what the moderators
  review. The bundle 1744106 still ships everything meanwhile. That is safe only because the 14 are not public until
  approved: no player can install a folder from two projects yet.
- If a module upload is refused because Core is not approved yet (the relation points at an unapproved project), that
  one job goes red and the bundle upload is unaffected (separate job, `fail-fast: false`). Re-run it after approval.

## Going live

1. Done: `live` true, so a tag gives every project its first file for moderation (the bundle unchanged).
2. **Once CurseForge approves the 14** (before that the dependencies can't install for anyone): one PR turning today's
   project 1744106 ("HogTron UI") into the everything-package: its .pkgmeta ships a small stub folder and
   `required-dependencies` on `hogtron-ui-core` + the 13 module slugs. Do this soon after approval: until it lands the
   same folders are public in two projects.
3. Tag a beta, install it on a second machine through the CurseForge app (both a fresh install and an update of the
   old all-in-one), then a public tag.

## Risks / open questions

- **Existing installs of 1744106.** On the update where it becomes the everything-package, the CurseForge app removes
  the module folders that came with 1744106 and installs them again from their own projects (same folder names, so
  settings are untouched: they live in `HogTronUIDB` by folder name). Test this once on a second machine (Anthony) with a
  beta tag before a public release.
- **Wago / WoWInterface** have no dependency auto-install comparable to CurseForge's; on those, keep the all-in-one zip.
- **Size.** Core carries all shared art (24 MB, mostly the cast bar strips). A nameplates-only install still downloads
  it. Moving each module's art into its own folder is possible later.
- Release cost: 15 uploads per tag instead of 1 (automatic; ~2 min of CI more).
