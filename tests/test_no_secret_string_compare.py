# Static guard for one bug class the Lua harness cannot reproduce: on the Forever beta, tostring() of a SECRET
# value yields a *secret string*, and comparing it (==, ~=) throws "attempt to compare a secret string value".
# Seen in game 2026-09-23: Units.lua PowerText `tostring(p) == "0"`. The mock's __tostring has to return a plain
# string (Lua requires it), so a unit test would pass while the client throws. This test reads the source instead.
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATTERN = re.compile(r'tostring\([^()]*(?:\([^()]*\))?[^()]*\)\s*[=~]=|[=~]=\s*tostring\(')


def addon_lua_files():
    for folder in sorted(ROOT.glob("HogHeals*")):
        if not folder.is_dir():
            continue
        for path in sorted(folder.rglob("*.lua")):
            if "Libs" in path.parts:
                continue
            yield path


def test_no_comparison_on_tostring_of_a_possible_secret():
    hits = []
    for path in addon_lua_files():
        for n, line in enumerate(path.read_text(encoding="utf-8", errors="ignore").splitlines(), 1):
            code = line.split("--", 1)[0]
            if PATTERN.search(code):
                hits.append(f"{path.relative_to(ROOT).as_posix()}:{n}: {line.strip()}")
    assert not hits, "comparison on tostring(): a secret string throws on the client; test with num()/str() instead\n" + "\n".join(hits)


def test_guard_sees_at_least_the_addon_folders():
    assert len(list(addon_lua_files())) > 20
