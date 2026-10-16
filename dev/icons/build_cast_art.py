"""Write PLACEHOLDER cast bar art: HogHeals/Media/cast_<theme>.tga, one 512x64 strip per theme (HogTron_HUD/CastThemes.lua).

The strip is repeated along the filled part of the cast bar and scrolled toward the spark, so it must tile left to
right without a seam (every pattern here wraps at x = 512). Light themes are drawn additively in game (black = no
light), matter themes (earth, herb, leather) blend normally (alpha = coverage).

These are procedural stand-ins (numpy + scipy + PIL, fixed seeds) so the art layer works today. Sean 2026-10-14 chose
OpenArt for the real set: those files replace these under the same names - same 512x64, same tiling rule.

Usage: python -P dev/icons/build_cast_art.py [--dry-run] [--preview out.png]
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

MEDIA = Path(__file__).resolve().parents[2] / "HogTronUI" / "Media"
W, H = 512, 64
YY, XX = np.mgrid[0:H, 0:W].astype(np.float32)
V = (YY + 0.5) / H                 # 0 top .. 1 bottom
U = (XX + 0.5) / W                 # 0 .. 1 across one tile


def noise(rng, sy, sx):
    """Smooth noise that wraps left-right (and top-bottom, harmless)."""
    n = ndimage.gaussian_filter(rng.standard_normal((H, W)), (sy, sx), mode="wrap")
    n -= n.mean()
    return n / (n.std() or 1)


def ramp(t, stops):
    """t 0..1 -> colour through stops [(pos, (r, g, b)), ...]."""
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,))
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        m = (t >= p0) & (t <= p1)
        k = ((t - p0) / max(1e-6, p1 - p0))[m][:, None]
        out[m] = np.array(c0) * (1 - k) + np.array(c1) * k
    return out


def sparkles(rng, n, radius, cross=True):
    a = np.zeros((H, W))
    for _ in range(n):
        cx, cy = rng.uniform(0, W), rng.uniform(6, H - 6)
        for dx in (-W, 0, W):   # wrap
            d2 = (XX - cx - dx) ** 2 + (YY - cy) ** 2
            a += np.exp(-d2 / (2 * radius ** 2))
            if cross:
                a += 0.6 * np.exp(-((YY - cy) ** 2) / 0.8) * np.exp(-((XX - cx - dx) ** 2) / (2 * (radius * 4) ** 2))
                a += 0.6 * np.exp(-((XX - cx - dx) ** 2) / 0.8) * np.exp(-((YY - cy) ** 2) / (2 * (radius * 3) ** 2))
    return np.clip(a, 0, 1)


def band(v, centre=0.5, width=0.42):
    return np.exp(-((v - centre) ** 2) / (2 * width ** 2))


def light(rgb, a):
    """Additive art: colour pre-multiplied by intensity, alpha = intensity (black = nothing)."""
    a = np.clip(a, 0, 1)
    return rgb * a[..., None], a


def fire(rng):
    flames = noise(rng, 3, 7) * 0.55 + noise(rng, 1.5, 3) * 0.3
    t = np.clip(0.55 + flames * 0.35 - (1 - V) * 0.55 + 0.25, 0, 1)
    return light(ramp(t, [(0, (0.25, 0.02, 0)), (0.45, (0.95, 0.30, 0.04)), (0.75, (1, 0.62, 0.12)), (1, (1, 0.95, 0.70))]), t ** 1.2)


def frost(rng):
    r = 1 - np.abs(noise(rng, 2.5, 5))
    r2 = 1 - np.abs(noise(rng, 1.2, 2.5))
    t = np.clip(r ** 8 * 0.6 + r2 ** 12 * 0.35 + 0.14 * band(V), 0, 1)
    return light(ramp(t, [(0, (0.10, 0.30, 0.55)), (0.6, (0.55, 0.85, 1)), (1, (1, 1, 1))]), t)


def holy(rng):
    rays = np.clip(noise(rng, 30, 3.5) * 0.5 + 0.35, 0, 1) ** 2
    t = np.clip(rays * band(V, 0.5, 0.38) + 0.10 * band(V, 0.5, 0.2) + sparkles(rng, 10, 1.4) * 0.8, 0, 1)
    return light(ramp(t, [(0, (0.50, 0.38, 0.10)), (0.5, (1, 0.86, 0.50)), (1, (1, 1, 0.92))]), t)


def arcane(rng):
    warp = noise(rng, 6, 12) * 1.6
    sw = np.sin(2 * math.pi * (U * 6 + V * 1.2) + warp) * np.sin(2 * math.pi * (U * 3 - V * 0.8) + warp * 0.7)
    t = np.clip(np.abs(sw) ** 3 * 0.85 * band(V, 0.5, 0.45) + sparkles(rng, 14, 1.2) * 0.9, 0, 1)
    return light(ramp(t, [(0, (0.25, 0.05, 0.45)), (0.5, (0.78, 0.45, 1)), (1, (1, 0.85, 1))]), t)


def shadow(rng):
    smoke = np.clip(noise(rng, 5, 12) * 0.45 + noise(rng, 2, 5) * 0.25 + 0.15, 0, 1)
    t = np.clip(smoke ** 1.6 * band(V, 0.5, 0.40), 0, 1)
    return light(ramp(t, [(0, (0.10, 0.02, 0.18)), (0.6, (0.48, 0.18, 0.75)), (1, (0.80, 0.55, 1))]), t * 0.95)


def nature(rng):
    leaves = np.clip(noise(rng, 2.5, 4) * 0.5 + 0.2, 0, 1)
    veins = (1 - np.abs(noise(rng, 6, 10))) ** 8
    t = np.clip(leaves ** 2 * 0.8 + veins * 0.5 + sparkles(rng, 6, 1.3, cross=False) * 0.5, 0, 1) * band(V, 0.5, 0.45)
    return light(ramp(t, [(0, (0.05, 0.25, 0.05)), (0.6, (0.40, 0.90, 0.35)), (1, (0.85, 1, 0.70))]), t)


def matter(rgb, a):
    return np.clip(rgb, 0, 1), np.clip(a, 0, 1)


def earth(rng):
    grit = noise(rng, 0.6, 0.6)
    strata = np.sin(2 * math.pi * (V * 5 + noise(rng, 8, 30) * 0.15))
    shade = 0.45 + grit * 0.12 + strata * 0.08
    rgb = np.stack([shade * 1.05, shade * 0.85, shade * 0.62], -1)
    a = np.clip(0.30 + (grit > 1.2) * 0.45 + (np.abs(strata) > 0.92) * 0.25, 0, 0.85)
    return matter(rgb, a)


def herb(rng):
    flecks = noise(rng, 1.4, 2.4)
    rgb = ramp(np.clip(flecks * 0.25 + 0.5, 0, 1), [(0, (0.10, 0.28, 0.06)), (1, (0.55, 0.80, 0.25))])
    a = np.clip((flecks > 0.6) * 0.75 + 0.15, 0, 0.9) * band(V, 0.5, 0.5)
    return matter(rgb, a)


def leather(rng):
    fibres = noise(rng, 0.7, 14)
    tone = 0.5 + fibres * 0.12 + noise(rng, 6, 20) * 0.05
    rgb = np.stack([tone * 0.95, tone * 0.68, tone * 0.45], -1)
    a = np.clip(0.35 + np.abs(fibres) * 0.25, 0, 0.8)
    return matter(rgb, a)


def water(rng):
    wobble = noise(rng, 20, 25) * 0.25
    ripple = np.sin(2 * math.pi * (V * 3.0 + U * 4 + wobble)) * 0.5 + 0.5
    caustic = (1 - np.abs(noise(rng, 2, 4))) ** 7
    t = np.clip(ripple ** 4 * 0.6 + caustic * 0.7, 0, 1) * band(V, 0.5, 0.45)
    return light(ramp(t, [(0, (0.02, 0.15, 0.40)), (0.6, (0.30, 0.65, 1)), (1, (0.90, 0.97, 1))]), t)


def gold(rng):
    t = np.clip(sparkles(rng, 22, 1.3) + 0.08 * band(V, 0.5, 0.25), 0, 1)
    return light(ramp(t, [(0, (0.40, 0.25, 0.02)), (0.5, (1, 0.78, 0.25)), (1, (1, 0.97, 0.80))]), t)


def craft(rng):
    embers = sparkles(rng, 16, 1.1, cross=False)
    haze = np.clip(noise(rng, 4, 10) * 0.3 + 0.1, 0, 1) * band(V, 0.55, 0.3)
    t = np.clip(embers * 0.95 + haze * 0.35, 0, 1)
    return light(ramp(t, [(0, (0.30, 0.10, 0.02)), (0.5, (0.95, 0.55, 0.18)), (1, (1, 0.90, 0.60))]), t)


def aim(rng):
    lines = np.clip(noise(rng, 0.6, 40) - 1.0, 0, None)
    t = np.clip(lines * 1.4, 0, 1) * band(V, 0.5, 0.45)
    return light(ramp(t, [(0, (0.40, 0.35, 0.25)), (1, (1, 0.97, 0.88))]), t)


STYLES = {"holy": holy, "fire": fire, "frost": frost, "arcane": arcane, "shadow": shadow, "nature": nature, "earth": earth,
          "herb": herb, "leather": leather, "water": water, "gold": gold, "craft": craft, "aim": aim}


def build(key, seed):
    rgb, a = STYLES[key](np.random.default_rng(seed))
    out = np.dstack([np.clip(rgb, 0, 1), np.clip(a, 0, 1)])
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA")


def main():
    dry = "--dry-run" in sys.argv
    built = {}
    for i, key in enumerate(STYLES):
        im = build(key, 1000 + i)
        built[key] = im
        # the seam check: the first and last columns must continue each other
        arr = np.asarray(im).astype(int)
        seam = np.abs(arr[:, 0] - arr[:, -1]).mean()
        print(("would write " if dry else "wrote ") + f"HogHeals/Media/cast_{key}.tga {im.size} seam diff {seam:.1f}")
        if not dry:
            im.save(MEDIA / f"cast_{key}.tga", format="TGA", rle=False)
    if "--preview" in sys.argv:
        out = sys.argv[sys.argv.index("--preview") + 1]
        sheet = Image.new("RGB", (W * 2 + 20, (H + 8) * len(built)), (14, 14, 18))
        for i, (key, im) in enumerate(built.items()):
            for k in range(2):   # two copies side by side: a seam would show in the middle
                sheet.paste(Image.alpha_composite(Image.new("RGBA", im.size, (14, 14, 18, 255)), im).convert("RGB"), (10 + k * W, i * (H + 8)))
        sheet.save(out)
        print("preview", out)


if __name__ == "__main__":
    main()
