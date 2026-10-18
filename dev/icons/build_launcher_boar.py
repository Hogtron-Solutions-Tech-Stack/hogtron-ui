"""The minimap drawer's launcher icon (HogTronUI/Media/brand_launcher.tga): the HogTron logo's own boar head.

Sean 2026-10-17: "now that it's a bigger icon, looks bad ... make it into a mini boar that is the HogTron logo". Real
brand art beats generated art (and an OpenArt boar would not BE the logo), so this cuts the head out of the brand's
vector layers (C:/Hogtron/Branding/Vector/layers: navy / mid / cyan / white masks of hogtron-boar-color.svg):
the head only - at button size the "HT" letters and the shield are noise, and the whole charging boar is too wide for a
square. Colours: the brand's, navy lifted a little and a cyan rim added so the silhouette reads on the dark tile
(brand rule: never a cream boar).

    python -P dev/icons/build_launcher_boar.py
"""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

LAYERS = Path(r"C:\Hogtron\Branding\Vector\layers")
OUT = Path(__file__).resolve().parents[2] / "HogTronUI" / "Media" / "brand_launcher.tga"
HEAD = (690, 205, 1112, 660)   # x0, y0, x1, y1 in the 1126x999 layers: the head, clear of the "T" bar and the shield


def mask(name: str) -> np.ndarray:
    a = np.asarray(Image.open(LAYERS / f"{name}.png").convert("L")).astype(np.float32) / 255.0
    return a if a.mean() < 0.5 else 1.0 - a     # the shape is the minority


def main() -> None:
    x0, y0, x1, y1 = HEAD
    sl = (slice(y0, y1), slice(x0, x1))
    parts = [(mask("00_navy")[sl], (27, 74, 102)), (mask("01_mid")[sl], (46, 127, 166)),
             (mask("02_cyan")[sl], (47, 196, 232)), (mask("03_white")[sl], (233, 246, 250))]
    rgb = np.zeros(parts[0][0].shape + (3,), np.float32)
    alpha = np.zeros(parts[0][0].shape, np.float32)
    for m, col in parts:
        rgb = rgb * (1 - m[..., None]) + np.array(col, np.float32) * m[..., None]
        alpha = np.clip(alpha + m, 0, 1)
    k = max(4, int(min(alpha.shape) * 0.022))
    rim = ndimage.gaussian_filter((ndimage.binary_dilation(alpha > 0.5, iterations=k) & ~(alpha > 0.5)).astype(np.float32), 1.0)
    rgb = rgb * (1 - rim[..., None]) + np.array((47, 196, 232), np.float32) * rim[..., None]
    alpha = np.clip(alpha + rim, 0, 1)
    img = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), alpha * 255]).astype(np.uint8), "RGBA")
    s = max(img.size)
    sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sq.paste(img, ((s - img.width) // 2, (s - img.height) // 2))
    sq.resize((64, 64), Image.LANCZOS).save(OUT, format="TGA", rle=False)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
