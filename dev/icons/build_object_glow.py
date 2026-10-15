"""Write the object-glow art: HogHeals/Media/object_ring.tga and object_spark.tga.

The glow over an ore vein / herb / chest / quest object (HogHeals_Plates/ObjectGlow.lua) is three white layers,
tinted per kind in code: the soft halo (target_glow.tga, already shipped), a thin soft RING that turns slowly, and a
four-point SPARK that twinkles. One white file per shape serves every colour.

128x128, white, alpha only. Pure PIL, deterministic.
Usage: python dev/icons/build_object_glow.py [--dry-run]
"""
import math
import sys
from pathlib import Path

from PIL import Image

MEDIA = Path(__file__).resolve().parents[2] / "HogHeals" / "Media"
SIZE = 128


def ring_alpha(d: float) -> float:
    """d = distance from the centre as a fraction of the radius. A gaussian band peaking at 0.72, zero at the rim."""
    if d >= 1:
        return 0.0
    band = math.exp(-(((d - 0.72) / 0.085) ** 2))
    inner = 0.18 * math.exp(-(((d - 0.72) / 0.30) ** 2))   # faint light spilling inside the band
    edge = min(1.0, (1 - d) / 0.08)                          # forced to 0 at the rim: no hard square edge
    return min(1.0, band + inner) * edge


def spark_alpha(x: float, y: float) -> float:
    """x, y in -1..1. Four thin rays (long horizontal + vertical, short diagonals) over a small bright core."""
    r = math.hypot(x, y)
    if r >= 1:
        return 0.0
    def ray(along: float, across: float, length: float, width: float) -> float:
        if abs(along) >= length:
            return 0.0
        return math.exp(-((across / width) ** 2)) * (1 - abs(along) / length) ** 2.2
    main = max(ray(x, y, 1.0, 0.045), ray(y, x, 1.0, 0.045))
    u, v = (x + y) / math.sqrt(2), (x - y) / math.sqrt(2)
    diag = 0.55 * max(ray(u, v, 0.45, 0.035), ray(v, u, 0.45, 0.035))
    core = math.exp(-((r / 0.12) ** 2))
    return min(1.0, max(main, diag) + core)


def build(fn) -> Image.Image:
    im = Image.new("RGBA", (SIZE, SIZE))
    c = SIZE / 2
    px = im.load()
    for yy in range(SIZE):
        for xx in range(SIZE):
            x, y = (xx + 0.5 - c) / c, (yy + 0.5 - c) / c
            px[xx, yy] = (255, 255, 255, round(255 * fn(x, y)))
    return im


def main():
    dry = "--dry-run" in sys.argv
    shapes = {
        "object_ring.tga": lambda x, y: ring_alpha(math.hypot(x, y)),
        "object_spark.tga": spark_alpha,
    }
    for name, fn in shapes.items():
        im = build(fn)
        path = MEDIA / name
        print(("would write " if dry else "wrote ") + str(path.relative_to(MEDIA.parents[1])), im.size,
              "centre a=%d rim a=%d" % (im.getpixel((63, 63))[3], im.getpixel((0, 63))[3]))
        if not dry:
            im.save(path, format="TGA", rle=False)


if __name__ == "__main__":
    main()
