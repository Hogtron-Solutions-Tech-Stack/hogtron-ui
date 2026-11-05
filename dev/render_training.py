"""Render PREVIEWS of the Training window (parchment page) to docs/mockups/training-<theme>.png.

Not screenshots of WoW: the real Training.lua runs in the test harness with the sample trainer of
tests/test_training.py, and render_dialog.py's Painter composites what the code drew (our page art, text in
Friz Quadrata when a local copy exists). Spell and weapon icons are placeholders.

    python -P dev/render_training.py [--scale 2]
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


class TrainingPainter(Painter):
    def paint(self):
        f = self.lua.eval("HogTronUITraining")
        m = 30
        fw, fh = f["_width"], f["_height"]
        self.root = (m, m, fw, fh)
        self.rects = {self.ident(f): self.root}
        self.portrait_id = self.ident(f["portrait"])
        img = Image.new("RGBA", (int((fw + 2 * m) * self.s), int((fh + 2 * m) * self.s)), WORLD + (255,))
        self.walk(img, f)
        return img.convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=int, default=2)
    s = ap.parse_args().scale
    OUT.mkdir(parents=True, exist_ok=True)
    lua = AddonLoader().bootstrap()
    lua.execute("MockState.playerClass = 'WARRIOR'; MockUnits.player.class = 'WARRIOR'; MockUnits.player.level = 22")
    lua.execute(TRAINER + 'GetSpellTexture = function(id) return "Interface\\\\Icons\\\\weapon" .. id end')
    for a in ("HogTronUI", "HogTron_Quests", "HogTron_Skin", "HogTron_Training"):
        lua.load_addon(a)
    lua.player_login()
    lua.execute("HogHealsTraining.Learn()")
    p = TrainingPainter(lua, s)
    for theme in ("light", "dark"):
        lua.execute(f'HogHeals.db.profile.quests.dialog.theme = "{theme}"; if HogTronUITraining then HogTronUITraining:Hide() end; HogHealsTraining.Toggle()')
        img = p.paint()
        path = OUT / f"training-{theme}.png"
        img.save(path)
        print("wrote", path.relative_to(ROOT), img.size)
    errs = [e["msg"] for e in lua.eval("HogHeals.errors").values()]
    print("addon errors:", errs or "none")
    return 1 if errs else 0


if __name__ == "__main__":
    raise SystemExit(main())
