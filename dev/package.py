"""Package HogTron UI for testers: one zip with every addon folder, nothing else.

Usage: python dev/package.py                 # dry run: lists what would go in, writes nothing
       python dev/package.py --write         # writes dist/HogTronUI-<version>.zip
       python dev/package.py --write --version 0.1.0-beta.1

The version defaults to `git describe --tags` (tocs carry the packager token @project-version@, which this script
rewrites to the version in every .toc and .lua it zips, same as the CurseForge build). The zip unpacks straight into Interface/AddOns:
every HogHeals*/ folder at the top level (Lua, toc, xml, Libs, Media), with tests, dev tooling, docs and dotfiles
left out. Refuses to write when a folder's toc lists a file that is missing (same check as dev/lint.py).
"""
from __future__ import annotations

import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KEEP = {".lua", ".toc", ".xml", ".tga", ".blp", ".ttf", ".otf", ".txt", ".md"}
SKIP_DIRS = {"__pycache__", ".git", ".scratch"}


TOKEN = "@project-version@"


def version() -> str:
    for line in (ROOT / "HogTronUI" / "HogTronUI.toc").read_text(encoding="utf-8").splitlines():
        if line.startswith("## Version:"):
            v = line.split(":", 1)[1].strip()
            if v and not v.startswith("@"):
                return v
    try:
        out = subprocess.run(["git", "describe", "--tags", "--always"], cwd=ROOT, capture_output=True, text=True, check=True)
        return out.stdout.strip().removeprefix("v") or "dev"
    except (OSError, subprocess.CalledProcessError):
        return "dev"


def addon_files() -> list[Path]:
    out: list[Path] = []
    for folder in sorted(p for pat in ("HogHeals*", "HogTron*") for p in ROOT.glob(pat) if p.is_dir()):
        for path in sorted(folder.rglob("*")):
            if path.is_dir() or any(part in SKIP_DIRS or part.startswith(".scratch") for part in path.parts):
                continue
            if path.suffix.lower() in KEEP:
                out.append(path)
    return out


def toc_complete() -> list[str]:
    """Every file a toc lists must exist; returns the problems."""
    bad: list[str] = []
    for folder in sorted(p for pat in ("HogHeals*", "HogTron*") for p in ROOT.glob(pat) if p.is_dir()):
        toc = folder / f"{folder.name}.toc"
        if not toc.exists():
            bad.append(f"{folder.name}: no toc")
            continue
        for line in toc.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if not (folder / line.replace("\\", "/")).exists():
                bad.append(f"{folder.name}: toc lists missing {line}")
    return bad


def main() -> int:
    write = "--write" in sys.argv
    ver = version()
    if "--version" in sys.argv:
        ver = sys.argv[sys.argv.index("--version") + 1]
    files = addon_files()
    problems = toc_complete()
    folders = sorted({f.relative_to(ROOT).parts[0] for f in files})
    total = sum(f.stat().st_size for f in files)
    print(f"HogTronUI-{ver}.zip: {len(folders)} addon folders, {len(files)} files, {total / 1e6:.1f} MB unpacked")
    for name in folders:
        print("  ", name)
    for p in problems:
        print("PROBLEM ", p)
    if problems:
        return 1
    if not write:
        print("dry run - add --write to build dist/")
        return 0
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    out = dist / f"HogTronUI-{ver}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for f in files:
            arc = f.relative_to(ROOT).as_posix()
            if f.suffix.lower() in (".toc", ".lua") and "/Libs/" not in f"/{arc}":
                text = f.read_text(encoding="utf-8")
                if TOKEN in text:
                    z.writestr(arc, text.replace(TOKEN, ver))
                    continue
            z.write(f, arc)
    print(f"wrote {out} ({out.stat().st_size / 1e6:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
