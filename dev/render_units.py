"""Render PREVIEWS of the HogTron UI unit frames to docs/mockups/units-*.png.

Not screenshots of WoW: the real HogTron_Units code runs in the test harness (lupa + tests/wow_mock.lua) against sample
units, and dev/render_frame.py composites what it built. Health / power / names are SAMPLE DATA; portrait art is a
placeholder square (the client draws the real face).

    python -P dev/render_units.py
"""
from __future__ import annotations

import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
sys.path.insert(0, str(ROOT / "dev"))
from loader import AddonLoader  # noqa: E402
from render_frame import Painter  # noqa: E402
from test_units import boot  # noqa: E402

OUT = ROOT / "docs" / "mockups"

SAMPLE = '''
  MockState.playerClass = "MAGE"; MockUnits.player.class = "MAGE"
  MockUnits.player.name, MockUnits.player.health, MockUnits.player.maxHealth = "Crispin", 343, 343
  MockUnits.player.power, MockUnits.player.maxPower, MockUnits.player.level = 512, 640, 22
  MockUnits.target = { name = "Shriekling Matriarch", class = "WARRIOR", isPlayer = false, health = 412, maxHealth = 690,
    level = 23, guid = "C-70", power = 0, maxPower = 0 }
  MockUnits.targettarget = { name = "Crispin", class = "MAGE", guid = "Player-0" }
  MockState.time = 80
  MockUnits.target.casting = { "Shadow Bolt", "Shadow Bolt", "icon", 79000, 82000, false, 1, false, 686 }
  MockFire("PLAYER_TARGET_CHANGED"); MockFire("UNIT_SPELLCAST_START", "target")
  HogHealsUnits.Units.ForEach(HogHealsUnits.Units.UpdateAll)
'''


def side_by_side(images, gap=24, bg=(46, 54, 40)):
    w = sum(i.width for i in images) + gap * (len(images) - 1)
    h = max(i.height for i in images)
    out = Image.new("RGB", (w, h), bg)
    x = 0
    for i in images:
        out.paste(i, (x, (h - i.height) // 2))
        x += i.width + gap
    return out


def main() -> int:
    lua = boot(AddonLoader().bootstrap())
    lua.execute(SAMPLE)
    p = Painter(lua, 2)
    OUT.mkdir(parents=True, exist_ok=True)
    shots = [p.paint(lua.eval(name), margin=34) for name in ("HogUIPlayer", "HogUITarget")]
    path = OUT / "units-player-target.png"
    side_by_side(shots).save(path)
    print("wrote", path.relative_to(ROOT))
    # portraits on (off by default): player's on the left, target's on the right; the picture is the client's
    lua.execute('''function SetPortraitTexture(tex, unit) tex:SetTexture("portrait:" .. unit) end
      HogHeals.db.profile.units.player.portrait = true; HogHeals.db.profile.units.target.portrait = true
      HogHealsUnits.Units.Refresh()''')
    shots = [p.paint(lua.eval(name), margin=34 + 46) for name in ("HogUIPlayer", "HogUITarget")]
    path = OUT / "units-portraits.png"
    side_by_side(shots).save(path)
    print("wrote", path.relative_to(ROOT))
    errs = [e["msg"] for e in lua.eval("HogHeals.errors").values()]
    print("addon errors:", errs or "none")
    return 1 if errs else 0


if __name__ == "__main__":
    raise SystemExit(main())
