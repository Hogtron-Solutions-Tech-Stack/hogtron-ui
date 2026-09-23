"""Render dev/icons/icons.html (SVG) to game textures: HogHeals/Media/<id>.tga, 64x64 32-bit with alpha.
Chromium via Playwright (same renderer Remotion uses), Lanczos downsample, TGA written uncompressed.
Also writes dev/icons/preview.png (each icon at 64/32/16 px on light + dark) for review.
Usage: python dev/icons/build_icons.py [--dry-run]"""
import io, sys
from pathlib import Path
from PIL import Image
from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
OUT = HERE.parents[1] / "HogHeals" / "Media"
IDS = ["quest_open", "quest_done", "quest_arrow"]
DRY = "--dry-run" in sys.argv

def main():
    imgs = {}
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width": 900, "height": 300}, device_scale_factor=1)
        pg.goto((HERE / "icons.html").as_uri())
        for i in IDS:
            png = pg.locator(f"#{i}").screenshot(omit_background=True)
            imgs[i] = Image.open(io.BytesIO(png)).convert("RGBA").resize((64, 64), Image.LANCZOS)
        b.close()
    for i, im in imgs.items():
        dest = OUT / f"{i}.tga"
        print(("would write " if DRY else "wrote ") + str(dest), im.size)
        if not DRY:
            im.save(dest, format="TGA", rle=False)
    # review sheet
    sheet = Image.new("RGBA", (3 * 130, 2 * 80), (0, 0, 0, 0))
    for row, bg in enumerate([(120, 150, 90, 255), (18, 18, 23, 255)]):
        tile = Image.new("RGBA", (3 * 130, 80), bg)
        x = 6
        for i in IDS:
            for s in (64, 32, 16):
                tile.alpha_composite(imgs[i].resize((s, s), Image.LANCZOS), (x, 8))
                x += s + 4
            x += 6
        sheet.paste(tile, (0, row * 80))
    sheet = sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)
    if not DRY:
        sheet.save(HERE / "preview.png")
        print("wrote", HERE / "preview.png")

if __name__ == "__main__":
    main()
