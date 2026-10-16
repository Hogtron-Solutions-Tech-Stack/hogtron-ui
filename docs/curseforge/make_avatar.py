"""Build the CurseForge project avatar: 400x400 PNG (CurseForge requires exactly 400x400, no webp).

    python docs/curseforge/make_avatar.py      # writes docs/curseforge/avatar-400.png

Real asset only: the HogTron boar (Hogtron-Website/public/images/hogtron-icon-clean.png) on the addon's own ink
background (#121217, Media/palette.lua) with a thin cyan (#21D4E0) frame. No generated art.
"""
from pathlib import Path
import sys

from PIL import Image, ImageDraw

SRC = Path.home() / "Code" / "Hogtron-Website" / "public" / "images" / "hogtron-icon-clean.png"
OUT = Path(__file__).with_name("avatar-400.png")
INK, CYAN, SIZE, SS = (0x12, 0x12, 0x17, 255), (0x21, 0xD4, 0xE0, 255), 400, 4   # SS = supersample for clean edges


def main() -> int:
    if not SRC.is_file():
        print(f"FAIL no logo at {SRC}")
        return 1
    big = SIZE * SS
    canvas = Image.new("RGBA", (big, big), INK)
    d = ImageDraw.Draw(canvas)
    inset, width = 14 * SS, 4 * SS
    d.rounded_rectangle([inset, inset, big - inset, big - inset], radius=36 * SS, outline=CYAN, width=width)
    boar = Image.open(SRC).convert("RGBA")
    boar = boar.crop(boar.getbbox())
    target = int(big * 0.70)
    scale = target / max(boar.size)
    boar = boar.resize((round(boar.width * scale), round(boar.height * scale)), Image.LANCZOS)
    canvas.alpha_composite(boar, ((big - boar.width) // 2, (big - boar.height) // 2))
    out = canvas.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")
    out.save(OUT, "PNG", optimize=True)
    check = Image.open(OUT)
    assert check.size == (SIZE, SIZE) and check.format == "PNG", check.size
    print(f"wrote {OUT} {check.size} {check.format} {OUT.stat().st_size} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
