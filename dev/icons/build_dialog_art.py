"""Write the quest dialog art (HogTron_Quests/Dialog.lua): a parchment page with torn edges in two looks, the bronze
ring around the NPC portrait, the fading rule under the title and the rounded shapes for tags, keys and buttons.

Sean 2026-10-14: the flat ink box "looks absolutely terrible" - he wants the book-page look of the Dialogue UI clip.
Our own art, generated here (procedural, numpy + scipy + PIL, fixed seeds = the same files every run). Nothing copied.

  dialog_page_light.tga   512x1024  warm parchment, torn edges, burnt rim, soft drop shadow
  dialog_page_dark.tga    512x1024  the same sheet charred: near-black, ash-grey rim
  dialog_ring.tga         128x128   bronze ring for the portrait (inside clear, a little inner shadow)
  dialog_rule.tga         256x8     white line fading out to the right (tinted in code)
  dialog_round.tga        64x64     white rounded rectangle (tinted: tags, key caps, buttons, tiles)
  dialog_round_line.tga   64x64     the same as an outline (disabled buttons, the picked reward)

The page is drawn in three slices (top 160 px, middle stretched, bottom 160 px), so the torn top and bottom edges
keep their shape whatever the page's height.

Usage: python -P dev/icons/build_dialog_art.py [--dry-run] [--preview out.png]
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

MEDIA = Path(__file__).resolve().parents[2] / "HogTronUI" / "Media"
PW, PH = 512, 1024
MARGIN = 20          # room for the torn edge + shadow inside the texture
PERIOD = 176         # the side edges repeat every 176 px: 704 px of middle = 4 periods, so a middle cropped to a
                     # multiple of 176 meets the bottom slice with the edge exactly where it left off (Dialog.lua)


def noise(rng, shape, sigma):
    n = ndimage.gaussian_filter(rng.standard_normal(shape), sigma, mode="wrap")
    n -= n.mean()
    s = n.std()
    return n / s if s > 0 else n


def edge_curve(rng, length, depth, slow=True):
    """1-D torn-edge offset, >= 0 px inward. Top / bottom: slow waves + roughness. Left / right (slow=False): roughness
    that repeats every PERIOD px (made on one period with wrap-around blur, then tiled)."""
    if slow:
        c = noise(rng, (length,), 24) * depth * 0.55 + noise(rng, (length,), 5) * depth * 0.45 + noise(rng, (length,), 1.4) * depth * 0.20
    else:
        one = noise(rng, (PERIOD,), 9) * depth * 0.40 + noise(rng, (PERIOD,), 3.5) * depth * 0.35 + noise(rng, (PERIOD,), 1.2) * depth * 0.20
        c = np.tile(one, length // PERIOD + 1)[:length]
    return c - c.min()


def page_mask(rng):
    yy, xx = np.mgrid[0:PH, 0:PW].astype(np.float32)
    left = MARGIN + edge_curve(rng, PH, 5, slow=False)
    right = PW - MARGIN - edge_curve(rng, PH, 5, slow=False)
    top = MARGIN + edge_curve(rng, PW, 6)
    bottom = PH - MARGIN - edge_curve(rng, PW, 6)
    inside = (xx >= left[:, None]) & (xx <= right[:, None]) & (yy >= top[None, :]) & (yy <= bottom[None, :])
    for cx, cy in ((MARGIN, MARGIN), (PW - MARGIN, MARGIN), (MARGIN, PH - MARGIN), (PW - MARGIN, PH - MARGIN)):
        inside &= np.hypot(xx - cx, yy - cy) > 9            # old paper is never square
    inner = ndimage.distance_transform_edt(inside)
    outer = ndimage.distance_transform_edt(~inside)
    alpha = np.clip(inner - outer + 0.5, 0, 1)
    return inside, inner, alpha


def page(dark: bool, seed: int = 7) -> Image.Image:
    rng = np.random.default_rng(seed)          # same seed both looks: the same torn sheet
    inside, inner, alpha = page_mask(rng)
    rng2 = np.random.default_rng(seed + (101 if dark else 0))
    # seam-safe: the middle is cropped in game, so nothing large varies from top to bottom - big blotches would show
    # as a step where the cropped middle meets the bottom slice. Grain hides any seam; stains live in the end slices.
    mottle = noise(rng2, (PH, PW), 38) * 0.010 + noise(rng2, (PH, PW), 11) * 0.016 + noise(rng2, (PH, PW), 2.2) * 0.018
    fibres = ndimage.gaussian_filter(rng2.standard_normal((PH, PW)), (0.8, 3.5), mode="wrap")
    fibres = fibres / (fibres.std() or 1) * 0.009
    yy, xx = np.mgrid[0:PH, 0:PW].astype(np.float32)
    stains = np.zeros((PH, PW), np.float32)
    for _ in range(7):
        cx = rng2.uniform(60, PW - 60)
        cy = rng2.uniform(30, 120) if rng2.random() < 0.5 else rng2.uniform(PH - 120, PH - 30)
        r = rng2.uniform(25, 60)
        stains += rng2.uniform(0.025, 0.07) * np.exp(-(((xx - cx) ** 2 + (yy - cy) ** 2) / (2 * r * r)))
    vig = ((xx - PW / 2) / (PW / 2)) ** 2 * 0.6        # across only: every row of the middle looks alike
    burn = np.exp(-inner / 9.0) * 0.70 + np.exp(-inner / 36.0) * 0.14
    if dark:
        base = np.array([0.155, 0.145, 0.135])
        rim = np.array([0.36, 0.34, 0.31])               # ash: the charred edge reads lighter
        grit = noise(rng2, (PH, PW), 1.0) * 0.05 + noise(rng2, (PH, PW), 6) * 0.06
        lum = 1 + mottle * 2.2 + grit + fibres - stains * 0.8 - vig * 0.25
    else:
        base = np.array([0.885, 0.775, 0.585])           # warm tan, lighter in the middle
        rim = np.array([0.40, 0.27, 0.15])               # burnt brown, not orange
        lum = 1 + mottle + fibres - vig * 0.10
    rgb = base[None, None, :] * lum[..., None]
    if not dark:
        rgb = rgb - stains[..., None] * np.array([0.45, 0.70, 1.05])[None, None, :]   # tea-brown stains, never grey
    rgb = rgb * (1 - burn[..., None]) + rim[None, None, :] * burn[..., None]
    rgb = np.clip(rgb, 0, 1)
    shadow = ndimage.gaussian_filter(np.roll(inside.astype(np.float32), 4, axis=0), 6) * (0.65 if dark else 0.55)
    a = alpha + shadow * (1 - alpha)
    col = np.where(a[..., None] > 0, (rgb * alpha[..., None]) / np.maximum(a[..., None], 1e-6), 0)
    out = np.dstack([np.clip(col, 0, 1), np.clip(a, 0, 1)])
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA")


def ring() -> Image.Image:
    S = 128
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    cx = cy = S / 2 - 0.5
    r = np.hypot(xx - cx, yy - cy)
    ang = np.arctan2(yy - cy, xx - cx)
    r_out, r_in = 60.0, 47.5
    p = np.clip((r - r_in) / (r_out - r_in), 0, 1)
    bevel = np.sin(p * math.pi)                          # rounded cross-section
    light = 0.55 + 0.45 * np.cos(ang + 3 * math.pi / 4)   # lit from the top-left
    t = np.clip(0.35 + 0.65 * bevel * light + 0.15 * bevel, 0, 1)[..., None]
    dark, mid, hi = np.array([0.22, 0.14, 0.06]), np.array([0.58, 0.42, 0.20]), np.array([0.95, 0.82, 0.55])
    rgb = np.where(t < 0.5, dark + (mid - dark) * (t / 0.5), mid + (hi - mid) * ((t - 0.5) / 0.5))
    ring_a = np.clip(r_out + 0.5 - r, 0, 1) * np.clip(r - r_in + 0.5, 0, 1)
    line = (np.exp(-((r - r_out + 0.8) ** 2) / 0.8) + np.exp(-((r - r_in - 0.8) ** 2) / 0.8)) * 0.8
    rgb = rgb * (1 - line[..., None] * 0.85)
    inner_sh = np.clip(1 - (r_in - r) / 7.0, 0, 1) * (r < r_in) * 0.55
    a = np.clip(ring_a + inner_sh * (1 - ring_a), 0, 1)
    col = np.where(ring_a[..., None] > 0, rgb, 0.0)
    return Image.fromarray((np.clip(np.dstack([col, a]), 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def rule() -> Image.Image:
    w, h = 256, 8
    x = (np.arange(w) + 0.5) / w
    fade = np.clip((1 - x) / 0.45, 0, 1) ** 1.4 * np.clip(x / 0.03, 0, 1)
    y = np.arange(h) + 0.5
    core = np.exp(-((y - h / 2) ** 2) / (2 * 0.75 ** 2))
    a = core[:, None] * fade[None, :]
    ones = np.ones((h, w))
    return Image.fromarray((np.dstack([ones, ones, ones, a]) * 255 + 0.5).astype(np.uint8), "RGBA")


def rounded(outline: bool) -> Image.Image:
    """Signed distance to a rounded square (radius 14) -> anti-aliased fill, or a 2 px ring for the outline."""
    S, rad = 64, 14.0
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) + 0.5
    half = S / 2 - 1.0
    qx = np.abs(xx - S / 2) - (half - rad)
    qy = np.abs(yy - S / 2) - (half - rad)
    d = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - rad
    a = np.clip(0.5 - d, 0, 1)
    if outline:
        a = a * np.clip(d + 2.5, 0, 1)
    ones = np.ones((S, S))
    return Image.fromarray((np.dstack([ones, ones, ones, a]) * 255 + 0.5).astype(np.uint8), "RGBA")


FILES = {
    "dialog_page_light.tga": lambda: page(False),
    "dialog_page_dark.tga": lambda: page(True),
    "dialog_ring.tga": ring,
    "dialog_rule.tga": rule,
    "dialog_round.tga": lambda: rounded(False),
    "dialog_round_line.tga": lambda: rounded(True),
}


def main():
    dry = "--dry-run" in sys.argv
    built = {}
    for name, fn in FILES.items():
        im = fn()
        built[name] = im
        print(("would write " if dry else "wrote ") + f"HogHeals/Media/{name} {im.size} alpha {im.getchannel('A').getextrema()}")
        if not dry:
            im.save(MEDIA / name, format="TGA", rle=False)
    if "--preview" in sys.argv:
        out = sys.argv[sys.argv.index("--preview") + 1]
        bg = Image.new("RGBA", (PW * 2 + 60, PH // 2 + 40), (52, 70, 46, 255))
        for i, n in enumerate(("dialog_page_light.tga", "dialog_page_dark.tga")):
            bg.alpha_composite(built[n].resize((PW, PH // 2)), (20 + i * (PW + 20), 20))
        bg.alpha_composite(built["dialog_ring.tga"], (60, 40))
        bg.convert("RGB").save(out)
        print("preview", out)


if __name__ == "__main__":
    main()
