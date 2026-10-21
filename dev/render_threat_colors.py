"""Preview of the nameplate threat colours (HogTron_Plates, plates.threat) -> docs/mockups/plates-threat-colors.png.

Top: style "border" (default) - the bar keeps red (hostile) / yellow (neutral), a thick border shows the threat.
Bottom: style "bar" - the whole bar takes the threat colour. Colours are read from HogTronUI/Core/Defaults.lua.

    python dev/render_threat_colors.py
"""
from __future__ import annotations

import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "mockups" / "plates-threat-colors.png"
FONT = ROOT / "HogTronUI" / "Media" / "Fonts" / "Inter-SemiBold.ttf"
HOSTILE, NEUTRAL, LINE = (217, 51, 51), (242, 204, 51), (13, 13, 15)


def defaults() -> dict[str, tuple[int, int, int]]:
    text = (ROOT / "HogTronUI" / "Core" / "Defaults.lua").read_text(encoding="utf-8")
    block = text[text.index("threat = { enabled"):]
    block = block[: block.index("},\n", block.index("lostColor"))]
    out = {}
    for name, r, g, b in re.findall(r"(\w+Color) = \{ ([\d.]+), ([\d.]+), ([\d.]+) \}", block):
        out[name] = tuple(int(float(v) * 255) for v in (r, g, b))
    return out


def font(size: int):
    try:
        return ImageFont.truetype(str(FONT), size)
    except OSError:
        return ImageFont.load_default()


def plate(d: ImageDraw.ImageDraw, x: int, y: int, name: str, fill_colour, fill: float, caption: str, edge=LINE, thick=1):
    w, h = 190, 16
    d.text((x, y - 20), name, font=font(14), fill=(235, 235, 235))
    if edge != LINE:   # the threat ring: 2 px of colour outside the plate's dark 1 px line (Plates.ThreatRing)
        d.rectangle([x - 3, y - 3, x + w + 3, y + h + 3], fill=edge)
    d.rectangle([x - 1, y - 1, x + w + 1, y + h + 1], fill=LINE)
    d.rectangle([x, y, x + w, y + h], fill=(15, 15, 20))
    d.rectangle([x, y, x + int(w * fill), y + h], fill=fill_colour)
    d.text((x + w // 2, y + h // 2), f"{int(fill * 100)}%", font=font(11), fill=(255, 255, 255), anchor="mm")
    d.text((x + w // 2, y + h + 15), caption, font=font(12), fill=(170, 175, 185), anchor="mm")


def main() -> None:
    c = defaults()
    img = Image.new("RGB", (1000, 560), (32, 36, 40))
    d = ImageDraw.Draw(img)
    d.text((24, 14), "Border (default): the bar stays red = hostile, yellow = neutral; the border shows threat", font=font(16), fill=(33, 212, 224))
    plate(d, 24, 70, "Defias Thug", HOSTILE, 1.0, "hostile, not fighting")
    plate(d, 262, 70, "Plainstrider", NEUTRAL, 1.0, "neutral, not fighting")
    plate(d, 500, 70, "Defias Thug", HOSTILE, 0.7, "fighting, safe", c["safeColor"], 2)
    plate(d, 738, 70, "Plainstrider", NEUTRAL, 0.6, "fighting, rising", c["risingColor"], 2)
    plate(d, 24, 150, "Defias Thug", HOSTILE, 0.5, "about to pull", c["highColor"], 2)
    plate(d, 262, 150, "Defias Thug", HOSTILE, 0.4, "on you", c["aggroColor"], 2)
    plate(d, 500, 150, "Plainstrider", NEUTRAL, 0.4, "on you (neutral mob)", c["aggroColor"], 2)

    d.text((24, 230), "Bar: the whole bar takes the threat colour while the mob fights you", font=font(16), fill=(33, 212, 224))
    row = [("Defias Thug", c["safeColor"], 0.8, "safe (under 50%)"), ("Defias Thug", c["risingColor"], 0.6, "rising (50%+)"),
           ("Defias Thug", c["highColor"], 0.5, "about to pull (80%+)"), ("Defias Thug", c["aggroColor"], 0.4, "on you")]
    for i, (n, col, f, cap) in enumerate(row):
        plate(d, 24 + i * 238, 286, n, col, f, cap)

    d.text((24, 370), "Tank (either style): green = on you, secure; orange = slipping; red = someone else has it", font=font(16), fill=(33, 212, 224))
    plate(d, 24, 426, "Defias Thug", HOSTILE, 0.8, "secure", c["secureColor"], 2)
    plate(d, 262, 426, "Defias Thug", HOSTILE, 0.6, "slipping", c["slippingColor"], 2)
    plate(d, 500, 426, "Defias Thug", HOSTILE, 0.5, "lost it", c["lostColor"], 2)
    d.text((24, 520), "Every colour, the yellow / orange thresholds and the style are settings: /hh > Nameplates > Threat colours.",
           font=font(12), fill=(150, 155, 165))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
