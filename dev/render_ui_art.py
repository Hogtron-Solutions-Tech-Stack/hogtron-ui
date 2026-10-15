"""PREVIEWS of the 2026-10-15 HogTron art set: the options window (painted + flat), the menu bar and the info bar.

Not screenshots of WoW: the real addon code runs in the test harness and dev/render_frame.py composites what it built
with the addon's own textures. Writes docs/mockups/art-*.png.

    python -P dev/render_ui_art.py
"""
from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
sys.path.insert(0, str(ROOT / "dev"))
from loader import AddonLoader  # noqa: E402
from render_frame import Painter  # noqa: E402

OUT = ROOT / "docs" / "mockups"


def main() -> int:
    lua = AddonLoader().bootstrap()
    for a in ("HogHeals", "HogHeals_Frames", "HogHeals_HUD", "HogHeals_Skin", "HogHeals_Quests"):
        lua.load_addon(a)
    lua.player_login()
    lua.execute("MockAdvance(6)")
    p = Painter(lua, 2)
    OUT.mkdir(parents=True, exist_ok=True)
    lua.execute('HogHeals.Panel.Open()')
    n = lua.eval('#HogHeals.Panel.nav')
    keys = [lua.eval(f'HogHeals.Panel.nav[{i}].key') for i in range(1, n + 1)]
    pick = "HUD" if "HUD" in keys else keys[0]
    lua.execute(f'HogHeals.Panel.Select("{pick}")')
    panel = lua.eval("HogHealsPanel")
    p.paint(panel, bg=(52, 60, 44)).save(OUT / "art-options-painted.png")
    lua.execute('HogHeals.db.profile.look.menus = "flat"; HogHeals.Panel.ApplyArt()')
    p.paint(panel, bg=(52, 60, 44)).save(OUT / "art-options-flat.png")
    lua.execute('HogHeals.db.profile.look.menus = "art"; HogHeals.Panel.ApplyArt()')
    bar = lua.eval("rawget(_G, 'HogHealsMicroBar')")
    if bar is not None:
        lua.execute("HogHealsSkin.Micro.Strip()")
        p.paint(bar, margin=10, bg=(40, 44, 36)).save(OUT / "art-menubar.png")
    info = lua.eval("rawget(_G, 'HogUIInfoBar')")
    if info is not None:
        lua.execute("HogHealsSkin.InfoBar.Refresh(); HogHealsSkin.InfoBar.Update()")
        p.paint(info, margin=10, bg=(40, 44, 36)).save(OUT / "art-infobar.png")
    errs = [e["msg"] for e in lua.eval("HogHeals.errors").values()]
    print("panel page:", pick, "| wrote art-options-painted / -flat, art-menubar, art-infobar | addon errors:", errs or "none")
    return 1 if errs else 0


if __name__ == "__main__":
    raise SystemExit(main())
