"""Syntax-check every .lua file in the addon folders with a real Lua 5.1 parser (lupa).

Usage: python dev/lint.py            # non-zero exit on any syntax error
       python dev/lint.py --all      # include vendored Libs
"""
from __future__ import annotations

import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
FOLDERS = sorted(p.name for p in ROOT.glob("HogHeals*") if p.is_dir())


def main() -> int:
    include_libs = "--all" in sys.argv
    lua = LuaRuntime()
    load = lua.eval("function(src, name) local f, err = loadstring(src, '@' .. name) return f ~= nil, err end")
    bad = 0
    count = 0
    for folder in FOLDERS:
        for path in sorted((ROOT / folder).rglob("*.lua")):
            rel = path.relative_to(ROOT).as_posix()
            if "/Libs/" in f"/{rel}" and not include_libs:
                continue
            count += 1
            src = path.read_text(encoding="utf-8", errors="ignore").lstrip("﻿")
            ok, err = load(src, rel)
            if not ok:
                bad += 1
                print(f"SYNTAX  {err}")
    # toc sanity: every listed file exists
    for folder in FOLDERS:
        toc = ROOT / folder / f"{folder}.toc"
        for line in toc.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            p = toc.parent / line.replace("\\", "/")
            if not p.exists():
                bad += 1
                print(f"TOC     {folder}: missing {line}")
    # brand guard: display text says "HogTron UI" (dev/rebrand.py); identifiers like HogUIBar1 are fine
    import re
    brand = re.compile(r"\bHogUI\b|\bHOG UI\b|\bHog UI\b")
    targets = [ROOT / "README.md"]
    for folder in FOLDERS:
        targets += [p for p in (ROOT / folder).rglob("*.lua") if "/Libs/" not in f"/{p.relative_to(ROOT).as_posix()}"]
        targets += list((ROOT / folder).glob("*.toc"))
    for path in targets:
        for i, line in enumerate(path.read_text(encoding="utf-8", errors="ignore").splitlines(), 1):
            if brand.search(line):
                bad += 1
                print(f"BRAND   {path.relative_to(ROOT).as_posix()}:{i}: says HogUI - run python dev/rebrand.py --apply")
    print(f"checked {count} lua files, {bad} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
