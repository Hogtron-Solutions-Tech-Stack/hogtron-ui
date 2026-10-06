"""Package HogTron UI for testers: one zip with every addon folder, nothing else.

Usage: python dev/package.py                 # dry run: lists what would go in, writes nothing
       python dev/package.py --write         # writes dist/HogTronUI-<version>.zip
       python dev/package.py --write --version 0.1.0-beta.1

The version defaults to the ## Version in HogHeals/HogHeals.toc. The zip unpacks straight into Interface/AddOns:
every HogHeals*/ folder at the top level (Lua, toc, xml, Libs, Media), with tests, dev tooling, docs and dotfiles
left out. Refuses to write when a folder's toc lists a file that is missing (same check as dev/lint.py).
"""
from __future__ import annotations

import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KEEP = {".lua", ".toc", ".xml", ".tga", ".blp", ".ttf", ".otf", ".txt", ".md"}
SKIP_DIRS = {"__pycache__", ".git", ".scratch"}


def version() -> str:
    for line in (ROOT / "HogHeals" / "HogHeals.toc").read_text(encoding="utf-8").splitlines():
        if line.startswith("## Version:"):
            return line.split(":", 1)[1].strip()
    return "0.0.0"


def addon_files() -> list[Path]:
    out: list[Path] = []
    for folder in sorted(p for p in ROOT.glob("HogHeals*") if p.is_dir()):
        for path in sorted(folder.rglob("*")):
            if path.is_dir() or any(part in SKIP_DIRS or part.startswith(".scratch") for part in path.parts):
                continue
            if path.suffix.lower() in KEEP:
                out.append(path)
    return out


def toc_complete() -> list[str]:
    """Every file a toc lists must exist; returns the problems."""
    bad: list[str] = []
    for folder in sorted(p for p in ROOT.glob("HogHeals*") if p.is_dir()):
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
            z.write(f, f.relative_to(ROOT).as_posix())
    print(f"wrote {out} ({out.stat().st_size / 1e6:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
