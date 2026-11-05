"""Make the Parchment look's icon set: every glyph icon as an ink stamp on a paper disc inside the dialog's bronze ring.

Sean 2026-11-05: "We even need to make new icons in the line ... to match those" (the menu bar, in the paper theme).
Built from our own glyph shapes (HogTronUI/Media/<id>.tga, the alpha mask), our page art (dialog_page_light, the
paper) and our ring (dialog_ring) - nothing of anyone else's. Output: HogTronUI/Media/<id>_page.tga, 128 x 128 RGBA,
the format the client reads (Look.Icon picks it in the Parchment look).

    python -P dev/make_page_icons.py [--sheet docs/mockups/page-icons.png]
"""
from __future__ import annotations

import argparse
import math
import pathlib

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
MEDIA = ROOT / "HogTronUI" / "Media"
SIZE = 128
DISC_R = 47           # the paper disc, just under the ring's inner edge (the ring is solid from r 48 to 57)
GLYPH_BOX = 60        # the glyph's box inside the disc
INK = (56, 36, 18)    # Parchment.THEMES.light.title as 0-255


def ids():
    return sorted(p.name[:-8] for p in MEDIA.glob("*_art.tga") if (MEDIA / (p.name[:-8] + ".tga")).exists())


def paper_disc():
    page = Image.open(MEDIA / "dialog_page_light.tga").convert("RGBA")
    crop = page.crop((150, 400, 150 + 200, 400 + 200)).resize((SIZE, SIZE), Image.LANCZOS)
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).ellipse([SIZE / 2 - DISC_R, SIZE / 2 - DISC_R, SIZE / 2 + DISC_R, SIZE / 2 + DISC_R], fill=255)
    # a soft vignette toward the rim: the disc reads as pressed into the page, not pasted on it
    vign = Image.new("L", (SIZE, SIZE), 0)
    px = vign.load()
    for y in range(SIZE):
        for x in range(SIZE):
            d = math.hypot(x - SIZE / 2 + 0.5, y - SIZE / 2 + 0.5) / DISC_R
            px[x, y] = int(max(0.0, min(1.0, (d - 0.55) / 0.45)) ** 2 * 70)
    dark = Image.new("RGBA", (SIZE, SIZE), (70, 45, 20, 255))
    disc = Image.composite(dark, crop, vign)
    disc.putalpha(mask)
    return disc


def stamp(glyph_path):
    """The glyph as a woodcut: its black strokes (outlines, a talent tree's links, a bag's handle) in ink, its cream
    fills as a pale paper highlight - every line of the sticker-style glyph survives."""
    g = Image.open(glyph_path).convert("RGBA")
    a = g.getchannel("A")
    bbox = a.getbbox() or (0, 0, g.width, g.height)
    g, a = g.crop(bbox), a.crop(bbox)
    lum = g.convert("L")
    dark = lum.point(lambda v: max(0, min(255, int((150 - v) * 255 / 90))))      # black stroke -> 255
    light = lum.point(lambda v: max(0, min(255, int((v - 110) * 255 / 90))))     # cream fill -> 255
    w, h = g.size
    k = GLYPH_BOX / max(w, h)
    size = (max(1, round(w * k)), max(1, round(h * k)))
    ink_a = ImageChops.multiply(a, dark).resize(size, Image.LANCZOS)
    fill_a = ImageChops.multiply(a, light).resize(size, Image.LANCZOS)
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ox, oy = (SIZE - size[0]) // 2, (SIZE - size[1]) // 2
    fill = Image.new("RGBA", size, (252, 242, 214, 0))
    fill.putalpha(fill_a.point(lambda v: int(v * 0.85)))
    layer.alpha_composite(fill, (ox, oy))
    ink = Image.new("RGBA", size, INK + (0,))
    ink.putalpha(ink_a)
    layer.alpha_composite(ink, (ox, oy))
    return layer


def make(icon_id, disc, ring):
    out = disc.copy()
    out.alpha_composite(stamp(MEDIA / f"{icon_id}.tga"))
    out.alpha_composite(ring)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", default=None)
    args = ap.parse_args()
    disc = paper_disc()
    ring = Image.open(MEDIA / "dialog_ring.tga").convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)
    made = []
    for i in ids():
        img = make(i, disc, ring)
        img.save(MEDIA / f"{i}_page.tga")
        made.append((i, img))
    print(f"wrote {len(made)} icons -> HogTronUI/Media/<id>_page.tga")
    if args.sheet:
        cols = 8
        cell = 96
        sheet = Image.new("RGBA", (cols * cell, math.ceil(len(made) / cols) * cell), (222, 200, 160, 255))
        page = Image.open(MEDIA / "dialog_page_light.tga").convert("RGBA").crop((40, 300, 472, 700)).resize(sheet.size)
        sheet.alpha_composite(page)
        for n, (_, img) in enumerate(made):
            sheet.alpha_composite(img.resize((cell - 8, cell - 8), Image.LANCZOS), ((n % cols) * cell + 4, (n // cols) * cell + 4))
        path = ROOT / args.sheet
        path.parent.mkdir(parents=True, exist_ok=True)
        sheet.convert("RGB").save(path)
        print("sheet", path.relative_to(ROOT))


if __name__ == "__main__":
    main()
