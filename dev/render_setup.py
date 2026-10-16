"""PREVIEWS of the setup guide (HogHeals/Core/Setup.lua): every page, painted by dev/render_frame.py from what the addon
code built in the test harness (all modules loaded). Not WoW screenshots: fonts and pixel snapping differ in game.

    python -P dev/render_setup.py          # docs/mockups/setup/NN-<step>.png
"""
from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
sys.path.insert(0, str(ROOT / "dev"))
from loader import AddonLoader  # noqa: E402
from render_frame import Painter  # noqa: E402

OUT = ROOT / "docs" / "mockups" / "setup"


def main() -> int:
    lua = AddonLoader().bootstrap()
    mods = sorted(p.name for p in ROOT.glob("HogHeals*") if p.is_dir())
    mods.remove("HogHeals")
    for a in ["HogHeals"] + mods:
        lua.load_addon(a)
    lua.execute('MockState.playerClass = "PRIEST"; MockUnits.player.name = "Hognificent"; MockUnits.player.level = 12')
    lua.player_login()
    lua.execute("MockAdvance(6)")                       # the guide opens itself on a new profile
    OUT.mkdir(parents=True, exist_ok=True)
    p = Painter(lua, 2)
    panel = lua.eval("HogHealsPanel")
    keys = [s["key"] for s in lua.eval("HogHeals.Setup.Visible()").values()]
    for i, key in enumerate(keys, 1):
        lua.execute(f"HogHeals.Setup.Go({i})")
        p.paint(panel, bg=(52, 60, 44)).save(OUT / f"{i:02d}-{key}.png")
    errs = [e["msg"] for e in lua.eval("HogHeals.errors").values()]
    print(f"wrote {len(keys)} pages to {OUT} | addon errors:", errs or "none")
    return 1 if errs else 0


if __name__ == "__main__":
    raise SystemExit(main())
