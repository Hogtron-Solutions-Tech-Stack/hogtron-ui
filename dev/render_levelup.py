"""Render PREVIEWS of the level-up card to docs/mockups/levelup-<look>.png.

Not screenshots of WoW: the real LevelUp.lua runs in the test harness (a warrior who just hit 22, after one trainer
visit, and a druid at 11 before any visit), and render_dialog.py's Painter composites what the code drew (our page
art, text in Friz Quadrata when a local copy exists).

    python -P dev/render_levelup.py [--scale 2]
"""
from __future__ import annotations

import argparse
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
sys.path.insert(0, str(ROOT / "dev"))
from loader import AddonLoader  # noqa: E402
from render_dialog import Painter, WORLD  # noqa: E402
from test_training import TRAINER  # noqa: E402

OUT = ROOT / "docs" / "mockups"


class CardPainter(Painter):
    def paint(self):
        f = self.lua.eval("HogTronUILevelUpCard")
        m = 30
        fw, fh = f["_width"], f["_height"]
        self.root = (m, m, fw, fh)
        self.rects = {self.ident(f): self.root}
        self.portrait_id = None
        img = Image.new("RGBA", (int((fw + 2 * m) * self.s), int((fh + 2 * m) * self.s)), WORLD + (255,))
        self.walk(img, f)
        return img.convert("RGB")


def card(style, visited, level, s):
    lua = AddonLoader().bootstrap()
    lua.execute('HogTronUIDB = { profiles = { Default = { look = { style = "%s" } } } }' % style)
    lua.execute("MockState.playerClass = 'WARRIOR'; MockUnits.player.class = 'WARRIOR'; MockUnits.player.level = %d" % level)
    lua.execute(TRAINER)
    for a in ("HogTronUI", "HogTron_Quests", "HogTron_Skin", "HogTron_Atlas", "HogTron_Training"):
        lua.load_addon(a)
    lua.player_login()
    if visited:
        lua.execute("HogHealsTraining.Learn()")
    lua.execute("HogHealsTraining.ShowLevelUp(%d)" % level)
    img = CardPainter(lua, s).paint()
    errs = [e["msg"] for e in lua.eval("HogHeals.errors").values()]
    return img, errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=int, default=2)
    s = ap.parse_args().scale
    OUT.mkdir(parents=True, exist_ok=True)
    bad = []
    # the Parchment look only: the Painter draws page art and text, not the Modern card's flat colour fills
    for style, visited, level, name in (("parchment", False, 11, "levelup-parchment-first"),
                                        ("parchment", True, 22, "levelup-parchment")):
        img, errs = card(style, visited, level, s)
        path = OUT / f"{name}.png"
        img.save(path)
        print("wrote", path.relative_to(ROOT), img.size, "errors:", errs or "none")
        bad += errs
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
