"""Render a PREVIEW of the druid player frame in caster / bear / cat form to docs/mockups/units-druid-forms.png.

Sean 2026-11-06: "energy and mana displayed for hybrid classes as well as combo points for feral". Not a screenshot of
WoW: the real HogTron_Units code runs in the test harness (lupa + tests/wow_mock.lua) and dev/render_frame.py
composites what it built. Numbers are SAMPLE DATA.

    python -P dev/render_class_power.py
"""
from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
sys.path.insert(0, str(ROOT / "dev"))
from loader import AddonLoader  # noqa: E402
from render_frame import Painter  # noqa: E402
from render_units import side_by_side  # noqa: E402
from test_units_class_power import boot  # noqa: E402

OUT = ROOT / "docs" / "mockups"

SAMPLE = '''
  MockUnits.player.name, MockUnits.player.health, MockUnits.player.maxHealth = "Hogbibi", 612, 640
  MockUnits.player.level, MockUnits.player.maxMana = 24, 980
  HogHealsUnits.module.events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
'''

FORMS = [
    ("caster", 'MockUnits.player.powerType = "MANA"; MockUnits.player.power = 742; MockUnits.player.maxPower = 980; MockUnits.player.mana = 742'),
    ("bear", 'MockUnits.player.powerType = "RAGE"; MockUnits.player.power = 46; MockUnits.player.maxPower = 100; MockUnits.player.mana = 610'),
    ("cat", 'MockUnits.player.powerType = "ENERGY"; MockUnits.player.power = 72; MockUnits.player.maxPower = 100; MockUnits.player.mana = 520; MockUnits.player.combo = 3'),
]


def main() -> int:
    lua = boot(AddonLoader().bootstrap())
    lua.execute(SAMPLE)
    p = Painter(lua, 2)
    OUT.mkdir(parents=True, exist_ok=True)
    shots = []
    for _, code in FORMS:
        lua.execute(code + '; HogHealsUnits.module.events:Fire("UPDATE_SHAPESHIFT_FORM"); HogHealsUnits.Units.UpdateAll(HogUIPlayer)')
        shots.append(p.paint(lua.eval("HogUIPlayer"), margin=34))
    path = OUT / "units-druid-forms.png"
    side_by_side(shots).save(path)
    print("wrote", path.relative_to(ROOT))
    errs = [e["msg"] for e in lua.eval("HogHeals.errors").values()]
    print("addon errors:", errs or "none")
    return 1 if errs else 0


if __name__ == "__main__":
    raise SystemExit(main())
