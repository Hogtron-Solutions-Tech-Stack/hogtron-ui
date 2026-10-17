"""Procedural light shaft for the world waypoint (HogTronUI/Media/waypoint_beam.tga), $0, no art source.

Sean 2026-10-17: "put a glow ... or like a beam of light coming down rather than this diamond ... it looks kind of
cheap". White (tinted in game by SetVertexColor), drawn with ADD: a bright narrow core and a soft halo across, full
at the bottom (where the quest is) and fading to nothing toward the top, with a faint banding so it reads as light.

    python dev/icons/build_beam.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

W, H = 64, 256
OUT = Path(__file__).resolve().parents[2] / "HogTronUI" / "Media" / "waypoint_beam.tga"


def main() -> None:
    x = np.linspace(-1, 1, W)[None, :]
    y = np.linspace(0, 1, H)[:, None]          # 0 = top row, 1 = bottom row
    core = np.exp(-(x / 0.10) ** 2)            # the bright thread
    halo = np.exp(-(x / 0.42) ** 2) * 0.55     # the soft glow around it
    across = np.clip(core + halo, 0, 1)
    up = y ** 1.6                              # full at the bottom, gone at the top
    bands = 0.9 + 0.1 * np.sin(y * np.pi * 9)  # faint banding, reads as light not paint
    a = np.clip(across * up * bands, 0, 1)
    rgba = np.zeros((H, W, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(OUT, format="TGA", rle=False)
    print("wrote", OUT, (W, H))


if __name__ == "__main__":
    main()
