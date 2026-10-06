"""Rebrand display strings: the word "HogUI" -> "HogTron UI" (Sean, 2026-10-05: share with Anthony under the HogTron name;
HogHeals, the healer module, keeps its hog name).

Touches TEXT only. Identifiers keep their names: frame globals (HogUIBar1, HogUIPlayer, HogUIAtlasWindow ...), the
LibDBIcon name, folder names and SavedVariables keys all stay, so nothing the game saved is lost. The regex needs a
word boundary after "HogUI", which is exactly what an identifier does not have.

Usage: python dev/rebrand.py            # dry run: lists every file + hit count, changes nothing
       python dev/rebrand.py --apply    # rewrite the files

Re-run after merging an older branch that still says HogUI; dev/lint.py fails on any leftover.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = ("docs/superpowers", "/Libs/")          # history + vendored
SKIP_FILES = re.compile(r"docs/REVIEW-")             # dated review notes are history, left as written

RULES = (
    (re.compile(r"\bHogUI\b"), "HogTron UI"),
    (re.compile(r"\bHOG UI\b"), "HOGTRON UI"),
    (re.compile(r"\bHog UI\b"), "HogTron UI"),
)


def files():
    pats = ["HogHeals*/**/*.lua", "HogHeals*/**/*.toc", "tests/*.py", "dev/*.py", "docs/*.md", "README.md"]
    seen = set()
    for pat in pats:
        for p in sorted(ROOT.glob(pat)):
            rel = p.relative_to(ROOT).as_posix()
            if any(s in f"/{rel}" for s in SKIP_DIRS) or SKIP_FILES.search(rel) or p.name == "rebrand.py":
                continue
            if rel not in seen:
                seen.add(rel)
                yield p, rel


def main() -> int:
    apply = "--apply" in sys.argv
    total, touched = 0, 0
    for p, rel in files():
        src = p.read_text(encoding="utf-8")
        out, n = src, 0
        for rx, repl in RULES:
            out, k = rx.subn(repl, out)
            n += k
        if n:
            total += n
            touched += 1
            print(f"{n:4d}  {rel}")
            if apply:
                p.write_text(out, encoding="utf-8", newline="")
    print(f"{'rewrote' if apply else 'would rewrite'} {total} hit(s) in {touched} file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
