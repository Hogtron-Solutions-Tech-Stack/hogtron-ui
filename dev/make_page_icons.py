"""Make the Parchment look's icon set: every icon on a paper disc inside the quest dialog's bronze ring.

Sean 2026-11-05: "We even need to make new icons in the line ... to match those" (the menu bar, in the paper theme).
Two sources, one frame:
  painted - Sean 2026-11-05 later, on the ink stamps: "These icons look terrible compared to the ones that we have.
            Can we upgrade these? We can use open art". OpenArt 3x3 sheets (C:/Hogtron/Ads-Demos/HogTronUI-CastArt,
            specs page_icons_a..d in ui_specs.py): the arcane-tech set's subjects painted as illuminated-manuscript
            miniatures on parchment. Each tile is cut to the disc. Every id in PAINTED whose raw sheet exists.
  stamp   - everything else: the glyph (HogTronUI/Media/<id>.tga, the alpha mask) pressed as an ink stamp on our page art
            (dialog_page_light). Built from our own files only.
Output: HogTronUI/Media/<id>_page.tga, 128 x 128 RGBA, the format the client reads (Look.Icon picks it in the
Parchment look). The ring is ours (dialog_ring).

    python -P dev/make_page_icons.py [--sheet docs/mockups/page-icons.png] [--stamps-only] [--dry-run]
"""
from __future__ import annotations

import argparse
import math
import pathlib
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
MEDIA = ROOT / "HogTronUI" / "Media"
RAW = pathlib.Path(r"C:\Hogtron\Ads-Demos\HogTronUI-CastArt\raw")
SIZE = 128
DISC_R = 47           # the paper disc, just under the ring's inner edge (the ring is solid from r 48 to 57)
GLYPH_BOX = 60        # the glyph's box inside the disc
INK = (56, 36, 18)    # Parchment.THEMES.light.title as 0-255
FILL = 0.90           # painted tiles: the radius holding 90% of the emblem's ink, as a share of the disc's
ZOOM_RANGE = (1.0, 1.45)   # never show more than the whole tile, never crop in past about two thirds of it

# sheet -> ids in reading order (None = a tile we do not use). Same order as the prompts in ui_specs.py.
PAINTED = {
    "page_icons_a": ["micro_character", "micro_spellbook", "micro_talents", "micro_achievements", "micro_quests",
                     "micro_guild", "micro_social", "micro_lfg", "micro_collections"],
    "page_icons_b": ["micro_ej", "micro_pvp", "micro_shop", "micro_help", "micro_menu", "micro_map", "micro_bags",
                     "micro_professions", "tray_all"],
    "page_icons_c": ["micro_legacy", "micro_other", "tray_bars", "tray_menu", "tray_frames", "tray_units", "tray_hud",
                     "tray_chat", "tray_tips"],
    "page_icons_d": ["tray_atlas", "tray_meter", "tray_plates", "tray_lock", "tray_bind", "tray_hover", None,
                     None, None],   # gold, timer, minimap: spare tiles (no drawer entry uses them)
}


def ids():
    """Every glyph that has a painted twin: the stamp set (a test holds each one has a _page file)."""
    return sorted(p.name[:-8] for p in MEDIA.glob("*_art.tga") if (MEDIA / (p.name[:-8] + ".tga")).exists())


def disc_mask():
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).ellipse([SIZE / 2 - DISC_R, SIZE / 2 - DISC_R, SIZE / 2 + DISC_R, SIZE / 2 + DISC_R], fill=255)
    return mask


def vignette(img, strength=70):
    """A soft darkening toward the rim: the disc reads as pressed into the page, not pasted on it."""
    vign = Image.new("L", (SIZE, SIZE), 0)
    px = vign.load()
    for y in range(SIZE):
        for x in range(SIZE):
            d = math.hypot(x - SIZE / 2 + 0.5, y - SIZE / 2 + 0.5) / DISC_R
            px[x, y] = int(max(0.0, min(1.0, (d - 0.55) / 0.45)) ** 2 * strength)
    dark = Image.new("RGBA", (SIZE, SIZE), (70, 45, 20, 255))
    return Image.composite(dark, img, vign)


def paper_disc():
    page = Image.open(MEDIA / "dialog_page_light.tga").convert("RGBA")
    crop = page.crop((150, 400, 150 + 200, 400 + 200)).resize((SIZE, SIZE), Image.LANCZOS)
    disc = vignette(crop)
    disc.putalpha(disc_mask())
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


def tiles(sheet_path, want):
    """The sheet's square tiles in reading order, found by their difference from the black background
    (the finder in dev/icons/process_ui_art.py), each as an RGB image."""
    sys.path.insert(0, str(ROOT / "dev" / "icons"))
    from process_ui_art import background, components, mask_of
    rgb = np.asarray(Image.open(sheet_path).convert("RGB")).astype(np.float32)
    boxes = components(mask_of(rgb, background(rgb)), want)
    out = []
    for y0, y1, x0, x1 in boxes:
        side = min(y1 - y0, x1 - x0)              # the tile's square (a soft drop shadow may widen one side)
        cy, cx = (y0 + y1) // 2, (x0 + x1) // 2
        crop = rgb[cy - side // 2:cy + side // 2, cx - side // 2:cx + side // 2]
        out.append(Image.fromarray(crop.astype(np.uint8), "RGB"))
    return out


def fit_zoom(tile):
    """How far to crop in so the emblem fills the disc. The emblem is outlined in dark ink, so its pixels are the dark
    ones (luminance < 130; paper, stains and the faint guide circle are lighter); its size is the radius holding 90%
    of them, measured from the tile's centre with the deckled edge left out. One rule for every tile: a wide rail and
    a small chat bubble end up the same size on the bar; an odd corner (a sword tip) may run under the ring."""
    a = np.asarray(tile.convert("L")).astype(np.float32)
    n = a.shape[0]
    edge = max(4, n // 14)
    inner = a[edge:n - edge, edge:n - edge]
    ys, xs = np.nonzero(inner < 130)
    if len(ys) < 50:
        return ZOOM_RANGE[0]
    c = (n - 2 * edge) / 2
    reach = np.percentile(np.hypot(ys - c, xs - c), 90)
    return float(min(ZOOM_RANGE[1], max(ZOOM_RANGE[0], (n / 2) * FILL / reach)))


def painted(tile, ring, zoom=1.0):
    """One painted tile on the disc: its centre scaled so the tile's inscribed circle / zoom fills the disc."""
    side = tile.width
    keep = side / zoom
    off = (side - keep) / 2
    d = 2 * DISC_R
    face = tile.crop((round(off), round(off), round(off + keep), round(off + keep))).resize((d, d), Image.LANCZOS)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.alpha_composite(face.convert("RGBA"), (SIZE // 2 - DISC_R, SIZE // 2 - DISC_R))
    out = vignette(out, 55)
    out.putalpha(disc_mask())
    out.alpha_composite(ring)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", default=None, help="also write a preview sheet of every _page icon here")
    ap.add_argument("--stamps-only", action="store_true", help="ignore the painted sheets (the old ink-stamp set)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    disc = paper_disc()
    ring = Image.open(MEDIA / "dialog_ring.tga").convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)
    made = {}
    if not args.stamps_only:
        for sheet, names in PAINTED.items():
            path = RAW / f"{sheet}.png"
            if not path.exists():
                print(f"skip {sheet}: no raw sheet at {path}")
                continue
            for name, tile in zip(names, tiles(path, len(names))):
                if name:
                    made[name] = ("painted", painted(tile, ring, fit_zoom(tile)))
    for i in ids():
        if i not in made:
            made[i] = ("stamp", make(i, disc, ring))
    for i, (_, img) in sorted(made.items()):
        if not args.dry_run:
            img.save(MEDIA / f"{i}_page.tga")
    kinds = [k for k, _ in made.values()]
    print(("would write " if args.dry_run else "wrote ") +
          f"{len(made)} icons ({kinds.count('painted')} painted, {kinds.count('stamp')} stamps) -> HogTronUI/Media/<id>_page.tga")
    if args.sheet:
        cols = 8
        cell = 96
        items = sorted(made.items())
        sheet = Image.new("RGBA", (cols * cell, math.ceil(len(items) / cols) * cell), (222, 200, 160, 255))
        page = Image.open(MEDIA / "dialog_page_light.tga").convert("RGBA").crop((40, 300, 472, 700)).resize(sheet.size)
        sheet.alpha_composite(page)
        for n, (_, (_, img)) in enumerate(items):
            sheet.alpha_composite(img.resize((cell - 8, cell - 8), Image.LANCZOS), ((n % cols) * cell + 4, (n // cols) * cell + 4))
        path = ROOT / args.sheet
        path.parent.mkdir(parents=True, exist_ok=True)
        sheet.convert("RGB").save(path)
        print("sheet", path.relative_to(ROOT))


if __name__ == "__main__":
    main()
