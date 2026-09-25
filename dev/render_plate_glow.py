"""Render a PREVIEW of the nameplate target glow (HogHeals_Plates) to docs/mockups/plate-target-glow.{gif,png}.

Not a screenshot of WoW. The real Plates.lua runs in the test harness (lupa + tests/wow_mock.lua): the plate is
added, targeted, and each frame advances the mock clock and fires the real glow driver; this script reads back what
the code set (glow spread, alpha, colour, the outline colour) and draws the 9-slice with the real
HogHeals/Media/target_glow.tga, additive, exactly as Plates.GLOW_SLICES lays it out. Fonts and the ground differ from
the client; Blizzard's own plate pieces are not drawn.

    python dev/render_plate_glow.py [--bg screenshot.png] [--scale 3]
      --bg     use the top strip of a real in-game screenshot as the ground (default: generated dark grass)
"""
from __future__ import annotations

import argparse
import pathlib
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
from loader import AddonLoader  # noqa: E402
from test_plates import add, boot  # noqa: E402

OUT = ROOT / "docs" / "mockups"
GLOW = np.asarray(Image.open(ROOT / "HogHeals" / "Media" / "target_glow.tga").convert("RGBA"), dtype=np.float32)[:, :, 3] / 255
QUEST = Image.open(ROOT / "HogHeals" / "Media" / "quest_open.tga").convert("RGBA")
W, H = 260, 90                         # canvas in game pixels
BAR = (76, 48, 144, 14)                # x, y, w, h: the bar in game pixels (height = default barHeight 14)
FPS = 25


def ground(bg: str | None) -> np.ndarray:
    if bg:
        im = Image.open(bg).convert("RGB")
        strip = im.crop((0, 0, im.width, min(24, im.height)))
        tile = Image.new("RGB", (max(W, strip.width), H))
        y, flip = 0, False
        while y < H:                                   # mirror-stack the clean top strip to fill the canvas
            tile.paste(strip.transpose(Image.FLIP_TOP_BOTTOM) if flip else strip, (0, y))
            y, flip = y + strip.height, not flip
        return np.asarray(tile.crop((0, 0, W, H)), dtype=np.float32) / 255
    rng = np.random.default_rng(7)
    n = rng.random((H // 3 + 1, W // 3 + 1))
    n = np.kron(n, np.ones((3, 3)))[:H, :W]
    base = np.array([0.11, 0.19, 0.14])
    return np.clip(base[None, None, :] * (0.75 + 0.5 * n[:, :, None]), 0, 1).astype(np.float32)


def frames_from_code(scale_glow_default=True):
    """Run the real addon; return one record per frame."""
    lua = boot(AddonLoader().bootstrap())
    uf = add(lua, "nameplate1", '{ name = "Moonrage Glutton", class = "WARRIOR", health = 4, maxHealth = 10, guid = "C-1" }',
             '{ { leftText = "Moonrage Glutton", type = 2 }, { leftText = " - Moonrage Glutton slain: 1/6", type = 8 } }')
    recs = []

    def grab():
        lit = lua.eval(f'{uf}.hh.lit') is True
        edge = list(lua.eval(f'{uf}.hh.edges[1]._color').values())
        rec = {"lit": lit, "edge": edge[:3]}
        if lit:
            rec["R"] = lua.eval(f'{uf}.hh.glowSpread')
            rec["a"] = lua.eval(f'{uf}.hh.glowAlpha')
            rec["c"] = list(lua.eval(f'{uf}.hh.glows[1]._color').values())[:3]
        recs.append(rec)

    dt = 1 / FPS
    for _ in range(int(0.6 * FPS)):                    # not targeted yet
        lua.execute(f'MockAdvance({dt})')
        grab()
    lua.execute('TARGET = "nameplate1"; MockFire("PLAYER_TARGET_CHANGED")')
    grab()
    for _ in range(int(3.2 * FPS)):                    # lock-on + a breath and a bit
        lua.execute(f'MockAdvance({dt}); local d = HogHealsPlates.Plates.driver; d._scripts.OnUpdate(d, {dt})')
        grab()
    errs = [e["msg"] for e in lua.eval('HogHeals.errors').values()]
    if errs:
        raise SystemExit("addon errors while rendering: " + "; ".join(errs))
    return recs


def glow_alpha(R: float, s: int) -> np.ndarray:
    """Alpha map (canvas px at scale s) of the 9-slice around BAR, spread R game px; same slices as Plates.lua."""
    A = np.zeros((H * s, W * s), dtype=np.float32)
    rp = max(1, round(R * s))
    x0, y0 = BAR[0] * s, BAR[1] * s
    x1, y1 = x0 + BAR[2] * s, y0 + BAR[3] * s

    def rs(a: np.ndarray, w: int, h: int) -> np.ndarray:
        return np.asarray(Image.fromarray(a).resize((w, h), Image.BILINEAR), dtype=np.float32)

    col = (GLOW[:, 31] + GLOW[:, 32]) / 2              # centre column / row = texcoords 31.5/64 .. 32.5/64
    row = (GLOW[31, :] + GLOW[32, :]) / 2
    A[y0 - rp:y0, x0 - rp:x0] += rs(GLOW[0:32, 0:32], rp, rp)
    A[y0 - rp:y0, x1:x1 + rp] += rs(GLOW[0:32, 32:64], rp, rp)
    A[y1:y1 + rp, x0 - rp:x0] += rs(GLOW[32:64, 0:32], rp, rp)
    A[y1:y1 + rp, x1:x1 + rp] += rs(GLOW[32:64, 32:64], rp, rp)
    A[y0 - rp:y0, x0:x1] += rs(col[0:32, None].copy(), 1, rp)
    A[y1:y1 + rp, x0:x1] += rs(col[32:64, None].copy(), 1, rp)
    A[y0:y1, x0 - rp:x0] += rs(row[None, 0:32].copy(), rp, 1)
    A[y0:y1, x1:x1 + rp] += rs(row[None, 32:64].copy(), rp, 1)
    return A


def font(size: int, bold=True):
    for f in (("georgiab.ttf" if bold else "georgia.ttf"), "DejaVuSerif-Bold.ttf"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


def draw_frame(rec: dict, bg: np.ndarray, s: int) -> Image.Image:
    img = np.kron(bg, np.ones((s, s, 1), dtype=np.float32))
    if rec["lit"]:                                     # additive: dst + colour * alpha
        A = glow_alpha(rec["R"], s) * rec["a"]
        img = np.clip(img + A[:, :, None] * np.array(rec["c"], dtype=np.float32)[None, None, :], 0, 1)
    im = Image.fromarray((img * 255).astype(np.uint8), "RGB").convert("RGBA")
    d = ImageDraw.Draw(im)
    x0, y0, bw, bh = (v * s for v in BAR)
    # bar: dark backing (0.06,0.06,0.08 @ .85), 40 % red fill, 1 px outline in the colour the code chose
    over = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(over).rectangle([x0, y0, x0 + bw - 1, y0 + bh - 1], fill=(15, 15, 20, 217))
    im = Image.alpha_composite(im, over)
    d = ImageDraw.Draw(im)
    d.rectangle([x0, y0, x0 + int(bw * 0.4) - 1, y0 + bh - 1], fill=(217, 51, 51, 255))
    ec = tuple(int(c * 255) for c in rec["edge"]) + (255,)
    d.rectangle([x0 - s, y0 - s, x0 + bw + s - 1, y0 + bh + s - 1], outline=ec, width=s)
    f_hp, f_name, f_q = font(10 * s), font(13 * s), font(11 * s, bold=False)
    cx = x0 + bw // 2
    d.text((cx, y0 + bh // 2), "40%", font=f_hp, anchor="mm", fill="white", stroke_width=s, stroke_fill="black")
    d.text((cx, y0 - 3 * s), "Moonrage Glutton", font=f_name, anchor="ms", fill="white", stroke_width=s, stroke_fill="black")
    q = QUEST.resize((16 * s, 16 * s), Image.LANCZOS)
    qx, qy = x0 - 4 * s - 16 * s, y0 + bh // 2 - 8 * s
    im.alpha_composite(q, (qx, qy))
    d.text((qx - 3 * s, y0 + bh // 2), "1/6", font=f_q, anchor="rm", fill=(242, 166, 38), stroke_width=s, stroke_fill="black")
    return im.convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bg")
    ap.add_argument("--scale", type=int, default=3)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    recs = frames_from_code()
    bg = ground(a.bg)
    frames = [draw_frame(r, bg, a.scale) for r in recs]
    lit = [r for r in recs if r["lit"]]
    print(f"{len(frames)} frames; spread {lit[0]['R']:.2f} -> {min(r['R'] for r in lit):.2f}, alpha {min(r['a'] for r in lit):.2f}..{max(r['a'] for r in lit):.2f}")
    if a.dry_run:
        return
    OUT.mkdir(parents=True, exist_ok=True)
    gif = OUT / "plate-target-glow.gif"
    frames[0].save(gif, save_all=True, append_images=frames[1:], duration=int(1000 / FPS), loop=0, optimize=True)
    # still strip: before, lock-on (3 steps), bright, dim
    first = next(i for i, r in enumerate(recs) if r["lit"])
    picks = [(first - 1, "not targeted"), (first + 1, "lock-on 0.04 s"), (first + 4, "lock-on 0.16 s"),
             (first + 8, "landed 0.32 s"), (first + 8 + int(1.2 * FPS), "breath: dimmest"), (first + 8 + int(2.4 * FPS), "breath: brightest")]
    fw, fh = frames[0].size
    strip = Image.new("RGB", (fw, (fh + 28) * len(picks)), (12, 12, 16))
    dd = ImageDraw.Draw(strip)
    for k, (i, label) in enumerate(picks):
        strip.paste(frames[min(i, len(frames) - 1)], (0, k * (fh + 28) + 28))
        dd.text((8, k * (fh + 28) + 6), label, font=font(16, bold=False), fill=(230, 230, 230))
    png = OUT / "plate-target-glow.png"
    strip.save(png)
    print("wrote", gif, "and", png)


if __name__ == "__main__":
    main()
