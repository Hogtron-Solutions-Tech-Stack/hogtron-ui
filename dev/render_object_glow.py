"""Render a PREVIEW of the object glow for every kind to docs/mockups/object-glow.png.

Not a screenshot of WoW. The real ObjectGlow.lua runs in the test harness and picks each kind of object in turn; this
script reads back what the code set on its three layers (size, colour, alpha, the spark's offset, the label) at a
few moments of the animation and composites the addon's own TGA art (halo = target_glow, ring = object_ring, spark =
object_spark) with additive light over a dark ground. Ring rotation is not drawn.

    python dev/render_object_glow.py [--scale 2]
"""
from __future__ import annotations

import argparse
import pathlib
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
from loader import AddonLoader  # noqa: E402
from test_object_glow import boot  # noqa: E402

OUT = ROOT / "docs" / "mockups" / "object-glow.png"
MEDIA = ROOT / "HogHeals" / "Media"
FONT = ROOT / "HogHeals" / "Media" / "Fonts" / "Inter-SemiBold.ttf"
ART = {"halo": "target_glow.tga", "ring": "object_ring.tga", "spark": "object_spark.tga"}
CASES = [  # (label, Soft(...) call)
    ("herb", 'Soft("Peacebloom", "Interface/Cursor/GatherHerbs", "GameObject-0-1-2-3-1617-1")'),
    ("ore", 'Soft("Copper Vein", 9001, "GameObject-0-1-2-3-1731-2")'),
    ("chest", 'Soft("Battered Chest", "Interface/Cursor/Interact", "GameObject-0-1-2-3-2843-3")'),
    ("quest", 'TT.softinteract = { { leftText = "Sack of Candles", type = 2 }, { leftText = "Kobold Candles: 2/6", type = 8 } }; Soft("Sack of Candles", "Interface/Cursor/Pickup", "GameObject-0-1-2-3-105570-4")'),
    ("bobber", 'Soft("Fishing Bobber", "Interface/Cursor/Interact", "GameObject-0-1-2-3-35591-77")'),
    ("cannot use yet", 'Soft("Tin Vein", 9002, "GameObject-0-1-2-3-1732-6")'),
]
MOMENTS = (0.05, 0.6, 1.4)
CELL = 150


def vals(t):
    return list(t.values())


def tinted(name, size, rgba, s):
    a = Image.open(MEDIA / ART[name]).convert("RGBA").getchannel("A").resize((max(1, int(size * s)), max(1, int(size * s))))
    r, g, b, al = rgba
    a = a.point(lambda v: int(v * al))
    layer = Image.new("RGB", a.size, (0, 0, 0))
    col = Image.new("RGB", a.size, (int(r * 255), int(g * 255), int(b * 255)))
    return Image.composite(col, layer, a)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=int, default=2)
    s = ap.parse_args().scale
    lua = boot(AddonLoader().bootstrap())
    font = ImageFont.truetype(str(FONT), 11 * s)
    img = Image.new("RGB", (CELL * len(MOMENTS) * s + 120 * s, CELL * len(CASES) * s), (22, 26, 24))
    d = ImageDraw.Draw(img)
    for row, (kind, prep) in enumerate(CASES):
        lua.execute("HogHealsPlates.ObjectGlow.HideGlow()")
        lua.execute(prep)
        f = lua.eval("HogTronUIObjectGlow")
        d.text((8 * s, (row * CELL + CELL / 2) * s), kind, fill=(200, 200, 205), font=font, anchor="lm")
        for col, t in enumerate(MOMENTS):
            lua.execute(f"HogHealsPlates.ObjectGlow.shown.t = {t}; HogHealsPlates.ObjectGlow.Paint()")
            cx, cy = (120 + col * CELL + CELL / 2) * s, (row * CELL + CELL / 2 + 8) * s
            for name in ("halo", "ring", "spark"):
                layer = f[name]
                size = layer["_width"]
                rgba = vals(layer["_color"])
                ox = oy = 0
                if name == "spark":
                    p = vals(layer["_points"][1])
                    ox, oy = p[3] * s, -p[4] * s
                im = tinted(name, size, rgba, s)
                x0, y0 = int(cx + ox - im.width / 2), int(cy + oy - im.height / 2)
                region = img.crop((x0, y0, x0 + im.width, y0 + im.height))
                img.paste(ImageChops.add(region, im), (x0, y0))
            lab = f["label"]
            if lab["_shown"]:
                c = tuple(int(v * 255) for v in vals(lab["_color"])[:3])
                d.text((cx, cy - (f["_height"] / 2 + 10) * s), lab["_text"], fill=c, font=font, anchor="mb")
            if row == 0:
                d.text((cx, 10 * s), f"t = {t}s", fill=(140, 140, 150), font=font, anchor="mm")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print("wrote", OUT.relative_to(ROOT))
    errs = [e["msg"] for e in lua.eval("HogHeals.errors").values()]
    print("addon errors:", errs or "none")
    return 1 if errs else 0


if __name__ == "__main__":
    raise SystemExit(main())
