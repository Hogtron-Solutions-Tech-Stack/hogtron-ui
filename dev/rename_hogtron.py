"""One-time folder rename (Sean 2026-10-15, locked): HogHeals -> HogTronUI, HogHeals_<X> -> HogTron_<X>,
HogHeals_Frames keeps its name (the healer frames are the HogHeals product). A tiny HogHeals folder stays behind for
one release as the settings bridge (its toc declares the OLD SavedVariables so the old file still loads).

Internal Lua names (the HogHeals addon object, HogHealsDB-style namespaces, minimap icon id) are NOT folder names
and stay. Only things that name a FOLDER change: texture paths, toc dependencies, test loaders, packaging, tooling.

    python -P dev/rename_hogtron.py            # dry run: what would change, per file
    python -P dev/rename_hogtron.py --write
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULES = ["Atlas", "Bars", "Chat", "HUD", "Meter", "Plates", "Quests", "Skin", "Training", "Units"]
TEXT_SUFFIXES = {".lua", ".toc", ".xml", ".py", ".ps1", ".yml", ".yaml", ".md", ".txt"}
SKIP_PARTS = {"Libs", ".git", "__pycache__", "dist", ".release"}
SKIP_DOCS = True          # docs/ is history (reviews, specs, research): left as written, except the files below
DOC_KEEP = {"README.md", "docs/TESTERS.txt", "docs/curseforge"}

MOD_RE = re.compile(r"HogHeals_(" + "|".join(MODULES) + r")\b")
REPLACERS = [
    (MOD_RE, r"HogTron_\1"),
    (re.compile(r"AddOns\\\\HogHeals\\\\"), r"AddOns\\\\HogTronUI\\\\"),        # Lua "Interface\\AddOns\\HogHeals\\..."
    (re.compile(r"AddOns\\HogHeals\\"), r"AddOns\\HogTronUI\\"),                # single-backslash forms (docs, ps1)
    (re.compile(r"AddOns/HogHeals/"), "AddOns/HogTronUI/"),
    (re.compile(r"^(## (?:Dependencies|RequiredDeps):\s*)HogHeals\s*$", re.M), r"\1HogTronUI"),
]
# Python: the folder name as a string literal or a path part
PY_REPLACERS = [
    (re.compile(r"(['\"])HogHeals\1"), r"\1HogTronUI\1"),
    (re.compile(r"HogHeals/HogHeals\.toc"), "HogTronUI/HogTronUI.toc"),
    (re.compile(r'glob\("HogTron_\*"\)'), 'glob("HogTron*")'),
]
OTHER_REPLACERS = [
    (re.compile(r"HogHeals/HogHeals\.toc"), "HogTronUI/HogTronUI.toc"),
    (re.compile(r'"HogHeals",'), '"HogTronUI",'),                                # ps1 / yml lists
]


def files() -> list[Path]:
    out = []
    for p in ROOT.rglob("*"):
        if not p.is_file() or p.suffix.lower() not in TEXT_SUFFIXES and p.name != ".pkgmeta":
            continue
        rel = p.relative_to(ROOT).as_posix()
        if any(part in SKIP_PARTS for part in p.relative_to(ROOT).parts):
            continue
        if rel == "dev/rename_hogtron.py":
            continue
        if SKIP_DOCS and rel.startswith("docs/") and not any(rel == k or rel.startswith(k + "/") for k in DOC_KEEP):
            continue
        out.append(p)
    return out


def transform(p: Path, s: str) -> str:
    for rx, rep in REPLACERS:
        s = rx.sub(rep, s)
    if p.suffix == ".py":
        for rx, rep in PY_REPLACERS:
            s = rx.sub(rep, s)
    elif p.suffix in (".ps1", ".yml", ".yaml") or p.name == ".pkgmeta":
        for rx, rep in OTHER_REPLACERS:
            s = rx.sub(rep, s)
    return s


def git_mv(a: str, b: str, write: bool):
    print(f"  mv {a} -> {b}")
    if write:
        subprocess.run(["git", "-C", str(ROOT), "mv", a, b], check=True)


def main() -> int:
    write = "--write" in sys.argv
    # 1. text first (paths still old), so file names below are found
    changed = 0
    for p in sorted(files()):
        s = p.read_text(encoding="utf-8", errors="surrogateescape")
        t = transform(p, s)
        if t != s:
            changed += 1
            n = sum(1 for a, b in zip(s.splitlines(), t.splitlines()) if a != b)
            print(f"edit {p.relative_to(ROOT).as_posix()}: {n} line(s)")
            if write:
                p.write_text(t, encoding="utf-8", errors="surrogateescape", newline="")
    # 2. folders and their tocs
    print("folders:")
    for m in MODULES:
        old, new = f"HogHeals_{m}", f"HogTron_{m}"
        if (ROOT / old).exists():
            git_mv(f"{old}/{old}.toc", f"{old}/{new}.toc", write)
            git_mv(old, new, write)
    if (ROOT / "HogHeals").exists() and not (ROOT / "HogTronUI").exists():
        git_mv("HogHeals/HogHeals.toc", "HogHeals/HogTronUI.toc", write)
        git_mv("HogHeals", "HogTronUI", write)
    print(f"{changed} file(s) {'edited' if write else 'would change'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
