"""Build the small reward icons the quest dialog shows inline: gold / silver / copper coins and the XP mark.

Sean 2026-10-17 (in game, a quest turn-in page): "We need images for the currency received instead of S or C. We
should also have a small image for "XP" that is slightly different." This client has no GetCoinTextureString, so the
dialog printed "6s 0c". Ours, drawn here (no third-party art): three minted discs - rim, face gradient, a raised inner
ring and a highlight - and the XP mark as the same disc in arcane violet carrying a four-point star, so it reads as
one family but is plainly not money.

    python -P dev/icons/build_reward_icons.py          -> HogTronUI/Media/coin_{gold,silver,copper}.tga, reward_xp.tga
"""
from __future__ import annotations

import math
import pathlib

from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parents[2]
MEDIA = ROOT / "HogTronUI" / "Media"
OUT_PX = 64          # shipped size (WoW scales it to the font height inline)
SS = 4               # supersampling for clean edges
N = OUT_PX * SS

# face light, face dark, rim, highlight
PALETTE = {
    "coin_gold":   ((255, 222, 120), (196, 136, 28), (120, 78, 12), (255, 247, 205)),
    "coin_silver": ((238, 241, 248), (150, 156, 172), (86, 90, 104), (255, 255, 255)),
    "coin_copper": ((236, 152, 98), (160, 82, 40), (96, 46, 20), (255, 214, 180)),
    "reward_xp":   ((176, 140, 255), (88, 52, 186), (48, 24, 110), (236, 226, 255)),
}


def lerp(a, b, t):
    return tuple(int(round(x + (y - x) * t)) for x, y in zip(a, b))


def disc(light, dark, rim, hi):
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    c = N / 2
    r_out = N * 0.46
    r_face = r_out * 0.84
    px = img.load()
    # face: lit from the top-left, darker toward the bottom-right edge
    for y in range(N):
        for x in range(N):
            dx, dy = x - c, y - c
            d = math.hypot(dx, dy)
            if d > r_out:
                continue
            if d > r_face:   # the rim: darker, with its own small gradient
                t = 0.35 + 0.65 * ((dx + dy) / (2 * r_out) + 0.5)
                px[x, y] = lerp(lerp(rim, dark, 0.35), rim, max(0, min(1, t))) + (255,)
            else:
                t = ((dx + dy) / (2 * r_face) + 0.5) * 0.85 + (d / r_face) * 0.15
                px[x, y] = lerp(light, dark, max(0, min(1, t))) + (255,)
    d = ImageDraw.Draw(img)
    # the raised inner ring a minted coin has
    ring = r_face * 0.80
    d.ellipse((c - ring, c - ring, c + ring, c + ring), outline=lerp(dark, rim, 0.3) + (150,), width=int(N * 0.018))
    # a soft highlight on the upper left
    glow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    hx, hy, hr = c - r_face * 0.38, c - r_face * 0.42, r_face * 0.30
    gd.ellipse((hx - hr, hy - hr * 0.7, hx + hr, hy + hr * 0.7), fill=hi + (170,))
    glow = glow.filter(ImageFilter.GaussianBlur(N * 0.03))
    img = Image.alpha_composite(img, glow)
    return img


def star(img, color, glow_color):
    """A four-point star (the XP mark) with a soft glow, centred."""
    c = N / 2
    big, small = N * 0.30, N * 0.075
    pts = []
    for i in range(8):
        a = -math.pi / 2 + i * math.pi / 4
        r = big if i % 2 == 0 else small
        pts.append((c + r * math.cos(a), c + r * math.sin(a)))
    halo = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(halo).polygon(pts, fill=glow_color + (200,))
    halo = halo.filter(ImageFilter.GaussianBlur(N * 0.035))
    img = Image.alpha_composite(img, halo)
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon(pts, fill=color + (255,))
    return Image.alpha_composite(img, layer)


def build():
    MEDIA.mkdir(parents=True, exist_ok=True)
    for name, (light, dark, rim, hi) in PALETTE.items():
        img = disc(light, dark, rim, hi)
        if name == "reward_xp":
            img = star(img, (255, 252, 240), (255, 236, 160))
        img = img.resize((OUT_PX, OUT_PX), Image.LANCZOS)
        path = MEDIA / f"{name}.tga"
        img.save(path)
        print("wrote", path.relative_to(ROOT))


if __name__ == "__main__":
    build()
