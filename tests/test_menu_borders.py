# Sean 2026-10-15 (in game): the painted options window read heavy - a teal line inside every brass edge, along the
# sidebar pillar and under the banner - and the version label ("vdev") was unreadable. Teal recoloured out of the
# four frame textures (dev/icons/tone_down_menu_art.py); version label light.
from pathlib import Path

MEDIA = Path(__file__).resolve().parents[1] / "HogTronUI" / "Media"


def tga_pixels(path):
    """(r, g, b) of every pixel of a truecolor TGA (types 2 and 10), plain Python: CI has no numpy / Pillow."""
    data = path.read_bytes()
    id_len, kind, w, h, bpp = data[0], data[2], data[12] | data[13] << 8, data[14] | data[15] << 8, data[16]
    step, i, out, n = bpp // 8, 18 + id_len, [], w * h
    assert kind in (2, 10) and step in (3, 4), (path.name, kind, bpp)
    while len(out) < n:
        if kind == 2:
            b, g, r = data[i], data[i + 1], data[i + 2]
            out.append((r, g, b))
            i += step
        else:
            head = data[i]
            i += 1
            count = (head & 0x7F) + 1
            if head & 0x80:
                b, g, r = data[i], data[i + 1], data[i + 2]
                out.extend([(r, g, b)] * count)
                i += step
            else:
                for _ in range(count):
                    b, g, r = data[i], data[i + 1], data[i + 2]
                    out.append((r, g, b))
                    i += step
    return out


def teal(px):
    return sum(1 for r, g, b in px if g > r + 35 and b > r + 35)


def test_frame_textures_carry_no_teal_line():
    for name in ("menu_edge_h", "menu_edge_v", "menu_side", "menu_header"):
        n = teal(tga_pixels(MEDIA / f"{name}.tga"))
        assert n == 0, f"{name}: {n} teal pixels"


def test_corner_gem_keeps_its_cyan():
    assert teal(tga_pixels(MEDIA / "menu_corner.tga")) > 50


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
