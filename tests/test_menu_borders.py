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
