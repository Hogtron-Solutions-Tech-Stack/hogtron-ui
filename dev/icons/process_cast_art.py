"""Cut an OpenArt image into a cast bar strip: HogHeals/Media/cast_<theme>.tga (512x64, tiles left to right).

Input = one wide image of an energy band on pure black (made by C:/Hogtron/Ads-Demos/HogTronUI-CastArt/
openart_cast_art.py, Sean's OpenArt pick 2026-10-14). Steps:
  1. find the band: the rows whose brightness clears a floor; its centre is the strip's centre;
  2. crop an 8:1 window around that centre at full width (the bar is thin: the hot core is what reads);
  3. loop it: the last `blend` px are crossfaded into the first `blend` px and then dropped, so the strip's right
     edge runs straight into its left edge (checked: seam step vs a typical neighbour step is printed);
  4. resize to 512x64; light themes keep black as "no light" (alpha 255, drawn ADD in game; a noise floor is cut
     to pure black so no grey haze), matter themes (earth, herb, leather) get alpha from brightness (drawn BLEND).

Usage: python -P dev/icons/process_cast_art.py <theme> <raw.png> [--blend 0.12] [--floor 10] [--dry-run]
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

MEDIA = Path(__file__).resolve().parents[2] / "HogHeals" / "Media"
OUT_W, OUT_H = 512, 64
MATTER = {"earth", "herb", "leather"}


def band_centre(lum: np.ndarray) -> int:
    rows = lum.mean(axis=1)
    lit = np.where(rows > max(6.0, rows.max() * 0.15))[0]
    if len(lit) == 0:
        return lum.shape[0] // 2
    weights = rows[lit]
    return int(round((lit * weights).sum() / weights.sum()))


def loop(arr: np.ndarray, blend_px: int) -> np.ndarray:
    """Crossfade the last blend_px columns into the first ones, then drop them: the result tiles seamlessly."""
    w = arr.shape[1]
    k = max(1, min(blend_px, w // 3))
    t = np.linspace(0, 1, k)[None, :, None]
    out = arr[:, : w - k].copy()
    out[:, :k] = arr[:, w - k:] * (1 - t) + arr[:, :k] * t
    return out


def process(theme: str, raw: Path, blend: float, floor: int) -> Image.Image:
    im = np.asarray(Image.open(raw).convert("RGB")).astype(np.float32)
    lum = im.mean(axis=2)
    h, w = lum.shape
    c = band_centre(lum)
    ch = int(round(w / 8))                       # 8:1 window = the strip's own shape
    top = max(0, min(h - ch, c - ch // 2))
    crop = im[top: top + ch]
    looped = loop(crop, int(round(crop.shape[1] * blend)))
    strip = Image.fromarray(np.clip(looped, 0, 255).astype(np.uint8)).resize((OUT_W, OUT_H), Image.LANCZOS)
    rgb = np.asarray(strip).astype(np.float32)
    if theme in MATTER:
        a = np.clip((rgb.max(axis=2) - floor) / 60.0, 0, 1) * 255
    else:
        rgb = np.where(rgb.max(axis=2, keepdims=True) < floor, 0, rgb)
        a = np.full(rgb.shape[:2], 255.0)
    out = np.dstack([rgb, a]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def seam_ratio(img: Image.Image) -> float:
    a = np.asarray(img).astype(int)[:, :, :3]
    seam = np.abs(a[:, 0] - a[:, -1]).mean()
    typical = np.abs(np.diff(a, axis=1)).mean()
    return seam / max(typical, 1e-6)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("theme")
    ap.add_argument("raw", type=Path)
    ap.add_argument("--blend", type=float, default=0.12, help="fraction of the width crossfaded to loop it")
    ap.add_argument("--floor", type=int, default=10, help="brightness below this = pure black (light themes)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    img = process(a.theme, a.raw, a.blend, a.floor)
    r = seam_ratio(img)
    path = MEDIA / f"cast_{a.theme}.tga"
    print(("would write " if a.dry_run else "wrote ") + f"{path.relative_to(MEDIA.parents[1])} {img.size} seam/typical {r:.2f}")
    if r > 2.0:
        raise SystemExit("REFUSING: the loop seam is more than twice a normal column step - raise --blend")
    if not a.dry_run:
        img.save(path, format="TGA", rle=False)


if __name__ == "__main__":
    main()
