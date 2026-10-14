# CurseForge kit

Everything needed to put HogTron UI on CurseForge. You do the account-side steps once; after that every release is a tag push.

Files in this folder:
- `avatar-400.png`: the project avatar. CurseForge requires exactly 400x400 and no webp. Rebuild with `python docs/curseforge/make_avatar.py`; it uses the real boar logo, nothing generated.
- `description.md`: paste-ready project description (markdown).

## One-time setup (Sean)

1. **Create the project** at https://authors.curseforge.com, choosing World of Warcraft and Addons. Fill the form from the table below.
2. CurseForge reviews new projects (and their first file) before they go public, so expect a wait.
3. **Project ID:** shown in the project's "About Project" box. Add it to **`HogHeals/HogHeals.toc` only** (one project covers all 12 folders):
   ```
   ## X-Curse-Project-ID: 123456
   ```
4. **API token:** go to https://authors.curseforge.com/account/api-tokens, create a token named `hogtron-ui github`, then:
   ```bash
   gh secret set CF_API_TOKEN --repo Hogtron-Solutions-Tech-Stack/hogtron-ui
   ```
   Paste the token when asked. It never goes in a file or a commit.
5. Optional, Wago: create the project on https://addons.wago.io, add `## X-Wago-ID: <id>` to the same toc, and set the `WAGO_API_TOKEN` secret the same way.

### Form values

| Field | Value |
|---|---|
| Name | `HogTron UI` (no game name or version: CurseForge rule) |
| Summary | `Healer frames, action bars, HUD, nameplates, quest tracker and a dungeon guide in one matching UI suite.` |
| Description | paste `description.md` (switch the editor to Markdown first if it offers that) |
| Main category | Unit Frames |
| More categories (as many as the form allows, in this order) | Healer, Raid Frames, Action Bars, Quests & Leveling, Map & Minimap, Chat & Communication, Combat |
| Licence | MIT License |
| Avatar | `avatar-400.png` |
| Source / issues link | https://github.com/Hogtron-Solutions-Tech-Stack/hogtron-ui |

The category names are real CurseForge ones, read off Bartender4, Plater, Questie, VuhDo, Grid2, Prat and Details on 2026-10-13.

### Screenshots (optional, real ones only)

The rendered mockups in `docs/mockups/` are **not** the game. CurseForge requires a visible disclaimer on any image that could misrepresent the addon, so use real in-game captures (PrtScn saves them to `_classic_beta_\Screenshots`):

1. Party frames + HUD (`/hh test 5` works solo).
2. Action bars, bags open, a tooltip showing (the Skin).
3. Quest tracker + square minimap.
4. The Atlas window (`/hh atlas`).
5. The `/hh` options window.

## Releasing (after setup)

```bash
git checkout main && git pull
git tag v0.1.0-beta.2
git push origin v0.1.0-beta.2
```

The tag's name sets everything else:
- `-alpha.N` uploads as an alpha file, `-beta.N` as a beta, and a plain `vX.Y.Z` as a release.
- The tag becomes the version players see in game (`/hh version`, the panel footer).
- The file's changelog is generated from the commits since the previous tag.

The `release` workflow (Actions tab) runs the tests, then a preflight, then the build and the zip check, and then uploads to CurseForge, a GitHub Release, and Wago if set up. If the tag build fails at **Preflight**, the project ID or the `CF_API_TOKEN` secret is missing. That check exists because the packager skips the upload silently in that case and the run would otherwise go green having shipped nothing.

Every PR and push to main runs the same build without uploading. The zip is attached to the run as `HogTronUI-build`, so you can test exactly what would ship.

## Adding a new addon folder

A new `HogHeals_X` folder needs a line in `.pkgmeta` under `move-folders`, **above** the core line:
```
  HogHeals/HogHeals_X: HogHeals_X
```
Without it, the zip check fails the build with `HogHeals_X: not a top-level folder in the zip`.
