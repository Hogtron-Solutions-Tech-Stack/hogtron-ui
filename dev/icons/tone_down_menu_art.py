"""Lighter borders on the painted options window (Sean 2026-10-15: "lighter borders").

The OpenArt menu frame paints a glowing teal line inside every brass edge, along the sidebar's right pillar and
under the title banner. With the brass frame that reads as a heavy double border. This recolours ONLY those teal
pixels into the dark slate of the panel, so the brass carries the frame on its own. The small cyan gems in the
corners stay (accent, not border).

Idempotent: once a texture has no teal left, a second run changes nothing.

    python -P dev/icons/tone_down_menu_art.py            # dry run: counts per texture
    python -P dev/icons/tone_down_menu_art.py --write
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

MEDIA = Path(__file__).resolve().parents[2] / "HogHeals" / "Media"
TARGETS = ["menu_edge_h", "menu_edge_v", "menu_side", "menu_header"]
SLATE = np.array([28, 34, 44], dtype=np.float32)       # the panel's dark slate


def teal_mask(rgb: np.ndarray) -> np.ndarray:
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    return (g > r + 35) & (b > r + 35) & (np.abs(g - b) < 90)


def process(path: Path, write: bool) -> int:
    im = Image.open(path).convert("RGBA")
    a = np.asarray(im).astype(np.float32)
    m = teal_mask(a[..., :3])
    n = int(m.sum())
    if n and write:
        # keep a little of the original brightness so the groove still has shape, but no colour
        lum = (0.3 * a[..., 0] + 0.59 * a[..., 1] + 0.11 * a[..., 2])[..., None]
        shaded = SLATE[None, None, :] * (0.75 + 0.5 * lum / 255.0)
        a[..., :3] = np.where(m[..., None], np.clip(shaded, 0, 255), a[..., :3])
        Image.fromarray(a.astype(np.uint8), "RGBA").save(path)
    return n


def main() -> int:
    write = "--write" in sys.argv
    for name in TARGETS:
        n = process(MEDIA / f"{name}.tga", write)
        print(f"{name}: {n} teal pixels {'recoloured' if write else '(dry run)'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
