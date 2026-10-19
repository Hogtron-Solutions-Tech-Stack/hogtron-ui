"""Render PREVIEWS of /hh unlock (HogTronUI/Core/EditMode.lua): the whole screen with the grid, the boxes and the
toolbar (docs/mockups/edit-grid.png) and the toolbar close up (docs/mockups/edit-toolbar.png).

Not screenshots of WoW: the real addon code runs in the test harness (lupa + tests/wow_mock.lua) and
dev/render_frame.py composites what it built. Unit frames show sample data.

    python -P dev/render_edit_mode.py
"""
from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
sys.path.insert(0, str(ROOT / "dev"))
from loader import AddonLoader  # noqa: E402
from render_frame import Painter  # noqa: E402
from test_bars import CLIENT, EXTRA_CLIENT  # noqa: E402

OUT = ROOT / "docs" / "mockups"


def main() -> int:
    lua = AddonLoader().bootstrap()
    lua.execute(CLIENT + EXTRA_CLIENT)
    for a in ("HogTronUI", "HogHeals_Frames", "HogTron_HUD", "HogTron_Units"):
        lua.load_addon(a)
    lua.player_login()
    lua.execute('''UIParent:SetSize(1920, 1080); UIParent:ClearAllPoints(); UIParent:SetPoint("TOPLEFT", nil, "TOPLEFT", 0, 0)
      HogHeals:SlashCommand("unlock")''')
    p = Painter(lua, 1)
    OUT.mkdir(parents=True, exist_ok=True)
    bar = p.paint(lua.eval("HogTronUIEditBar"), margin=12, bg=(40, 44, 36))
    bar.resize((bar.width * 2, bar.height * 2)).save(OUT / "edit-toolbar.png")
    p.paint(lua.eval("UIParent"), margin=0, bg=(52, 60, 44)).save(OUT / "edit-grid.png")
    print("wrote docs/mockups/edit-toolbar.png, docs/mockups/edit-grid.png")
    errs = [e["msg"] for e in lua.eval("HogHeals.errors").values()]
    print("addon errors:", errs or "none")
    return 1 if errs else 0


if __name__ == "__main__":
    raise SystemExit(main())
