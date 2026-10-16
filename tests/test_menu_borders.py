# Sean 2026-10-15 (in game): the painted options window read heavy - a teal line inside every brass edge, along the
# sidebar pillar and under the banner - and the version label ("vdev") was unreadable. Teal recoloured out of the
# four frame textures (dev/icons/tone_down_menu_art.py); version label light.
from pathlib import Path

import numpy as np
from PIL import Image

MEDIA = Path(__file__).resolve().parents[1] / "HogHeals" / "Media"


def test_frame_textures_carry_no_teal_line():
    for name in ("menu_edge_h", "menu_edge_v", "menu_side", "menu_header"):
        a = np.asarray(Image.open(MEDIA / f"{name}.tga").convert("RGB")).astype(int)
        r, g, b = a[..., 0], a[..., 1], a[..., 2]
        teal = ((g > r + 35) & (b > r + 35)).sum()
        assert teal == 0, f"{name}: {teal} teal pixels"


def test_corner_gem_keeps_its_cyan():
    a = np.asarray(Image.open(MEDIA / "menu_corner.tga").convert("RGB")).astype(int)
    assert ((a[..., 1] > a[..., 0] + 35) & (a[..., 2] > a[..., 0] + 35)).sum() > 50


def test_version_label_is_readable(core):
    core.execute('HogHeals.Panel.Open()')
    r, g, b = [core.eval(f'HogHealsPanel.version._color[{i}]') for i in (1, 2, 3)]
    assert min(r, g, b) >= 0.65


def test_close_button_is_brass_in_the_corner_when_painted(core):
    # Sean 2026-10-15: "I don't like where this X is placed ... all the way in the corner or matching with the gold"
    core.execute('HogHeals.Panel.Open()')
    assert core.eval('HogHeals.Panel.artOn') is True
    c = 'HogHealsPanel.close'
    p = core.eval(f'{{ {c}:GetPoint(1) }}')
    assert p[1] == "TOPRIGHT" and core.eval(f'select(2, {c}:GetPoint(1)) == HogHealsPanel') and p[3] == "TOPRIGHT"
    assert core.eval(f'{c}.brass') is True
    r, g, b = [core.eval(f'{c}.fill._color[{i}]') for i in (1, 2, 3)]
    assert r > g > b and r > 0.4                                                    # brass, not the dark flat fill
    assert core.eval(f'{c}:GetFrameLevel() > HogHealsPanel.art.holder:GetFrameLevel()')


def test_close_button_back_in_the_title_bar_when_flat(core):
    core.execute('HogHeals.db.profile.look = HogHeals.db.profile.look or {}; HogHeals.db.profile.look.menus = "flat"; HogHeals.Panel.Open()')
    assert core.eval('HogHeals.Panel.artOn') is False and core.eval('HogHealsPanel.close.brass') is False
    assert core.eval('select(2, HogHealsPanel.close:GetPoint(1)) == HogHealsPanel.bar')
