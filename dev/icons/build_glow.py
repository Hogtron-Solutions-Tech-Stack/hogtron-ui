"""Write HogHeals/Media/target_glow.tga: the soft light used for the nameplate target glow.

64x64, white, alpha = a smooth radial fall-off from the centre (1.0) to the rim (0.0). The Lua cuts it into a
9-slice around the health bar: the four quadrants become the rounded corners, the centre row / column the straight
edges, so the bar edge is always the brightest line and the light fades out evenly on every side. Tinted and
alpha-animated in code (Plates.lua), so one white file serves every colour.

Pure PIL (no browser), deterministic.
Usage: python dev/icons/build_glow.py [--dry-run]
"""
import math
import sys
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parents[2] / "HogHeals" / "Media" / "target_glow.tga"
SIZE = 64
K = 2.4   # fall-off steepness: exp(-K d^2) rescaled so the rim is exactly 0 (bigger = tighter light)


def alpha_at(d: float) -> float:
    """d = distance from the centre as a fraction of the radius (0 centre, 1 rim)."""
    if d >= 1:
        return 0.0
    rim = math.exp(-K)
    return (math.exp(-K * d * d) - rim) / (1 - rim)


def build() -> Image.Image:
    im = Image.new("RGBA", (SIZE, SIZE))
    c = SIZE / 2          # centre sits between texels 31 and 32: the middle row / column is symmetric
    px = im.load()
    for y in range(SIZE):
        for x in range(SIZE):
            d = math.hypot(x + 0.5 - c, y + 0.5 - c) / c
            px[x, y] = (255, 255, 255, round(255 * alpha_at(d)))
    return im


def main():
    im = build()
    print(("would write " if "--dry-run" in sys.argv else "wrote ") + str(OUT), im.size,
          "centre a=%d rim a=%d" % (im.getpixel((31, 31))[3], im.getpixel((0, 31))[3]))
    if "--dry-run" not in sys.argv:
        im.save(OUT, format="TGA", rle=False)


if __name__ == "__main__":
    main()
