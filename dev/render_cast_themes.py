"""Render a PREVIEW of every cast bar theme to docs/mockups/cast-themes.png.

Not a screenshot of WoW. The real HogHeals_HUD (HUD.lua + Castbar.lua + CastThemes.lua) runs in the test harness;
for each theme this script starts a cast, moves time on so the fill sits at 60 %, lets CastThemes.Tick place the
glow and the motes, then reads back what the code set (fill colour, glow colour / alpha, mote positions / sizes /
alphas, spark colour, texts) and draws it with the addon's own target_glow.tga, Inter font and additive light.

    python dev/render_cast_themes.py [--scale 2]
"""
from __future__ import annotations

import argparse
import pathlib
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
from loader import AddonLoader  # noqa: E402

OUT = ROOT / "docs" / "mockups" / "cast-themes.png"
GLOW = ROOT / "HogHeals" / "Media" / "target_glow.tga"
FONT = ROOT / "HogHeals" / "Media" / "Fonts" / "Inter-SemiBold.ttf"
W, H, ROW, LEFT = 300, 18, 46, 110
SAMPLES = {"holy": "Flash Heal", "fire": "Fireball", "frost": "Frostbolt", "arcane": "Arcane Missiles", "shadow": "Mind Flay",
           "nature": "Lightning Bolt", "earth": "Mining", "herb": "Herb Gathering", "leather": "Skinning", "water": "Fishing",
           "gold": "Opening", "craft": "Linen Bandage", "aim": "Aimed Shot"}


def vals(t):
    return list(t.values()) if t is not None else []


def add_light(img, x, y, w, h, rgba, s):
    a = Image.open(GLOW).convert("RGBA").getchannel("A").resize((max(1, int(w * s)), max(1, int(h * s))))
    r, g, b, al = (rgba + [1])[:4]
    a = a.point(lambda v: int(v * al))
    col = Image.new("RGB", a.size, (int(r * 255), int(g * 255), int(b * 255)))
    light = Image.composite(col, Image.new("RGB", a.size, (0, 0, 0)), a)
    x0, y0 = int(x * s - light.width / 2), int(y * s - light.height / 2)
    region = img.crop((x0, y0, x0 + light.width, y0 + light.height))
    img.paste(ImageChops.add(region, light), (x0, y0))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=int, default=2)
    s = ap.parse_args().scale
    lua = AddonLoader().bootstrap()
    for a in ("HogHeals", "HogHeals_HUD"):
        lua.load_addon(a)
    lua.player_login()
    lua.execute("HH_cb = HogHealsHUD.HUD.rows.castbar; HH_cb:SetWidth(300); HH_cb:SetHeight(18); MockState.time = 100")
    order = list(lua.eval("HogHealsHUD.CastThemes.ORDER").values())
    font = ImageFont.truetype(str(FONT), 10 * s)
    img = Image.new("RGB", ((LEFT + W + 40) * s, (ROW * len(order) + 20) * s), (20, 24, 22))
    d = ImageDraw.Draw(img)
    for row, key in enumerate(order):
        name = SAMPLES[key]
        lua.execute(f'''
          MockUnits.player.casting = {{ "{name}", "{name}", "icon", 100000, 102000, false, 1, false, nil }}
          HogHealsHUD.Castbar.state.casting = false
          MockState.time = 100''')
        lua.execute(f'''
          local C = HogHealsHUD.Castbar
          C.state.preview = nil
          local b = HH_cb
          -- start through the real path, with the theme forced (no spell to read here)
          local T = HogHealsHUD.CastThemes
          b:SetStatusBarColor(0.13, 0.83, 0.88)
          T.Apply(b, "{key}", 100)
          b.text:SetText("{name}")
          b:SetValue(0.6)
          T.Tick(b, 0.6, 100.8)''')
        y0 = 20 + row * ROW + ROW / 2
        x0 = LEFT
        L = lua.eval("HogHealsHUD.CastThemes.layers")
        cb = lua.eval("HH_cb")
        d.text((10 * s, y0 * s), key, fill=(200, 200, 205), font=font, anchor="lm")
        if L["glow"]["_shown"]:
            add_light(img, x0 + W / 2, y0, W + 24, H + 18, vals(L["glow"]["_color"]), s)
        # bar: ink background at 0.7, then the fill
        bg = Image.new("RGB", (W * s, H * s), (18, 18, 23))
        region = img.crop((int(x0 * s), int((y0 - H / 2) * s), int((x0 + W) * s), int((y0 + H / 2) * s)))
        img.paste(Image.blend(region, bg, 0.7), (int(x0 * s), int((y0 - H / 2) * s)))
        fc = tuple(int(v * 255) for v in vals(cb["_color"])[:3])
        d.rectangle([x0 * s, (y0 - H / 2) * s, (x0 + W * 0.6) * s - 1, (y0 + H / 2) * s - 1], fill=fc)
        sp = tuple(int(min(1, v) * 255) for v in vals(cb["spark"]["_color"])[:3]) if cb["spark"]["_color"] else (255, 255, 255)
        d.rectangle([(x0 + W * 0.6 - 1) * s, (y0 - H / 2 - 3) * s, (x0 + W * 0.6 + 1) * s, (y0 + H / 2 + 3) * s], fill=sp)
        for m in L["motes"].values():
            if not m["_shown"] or not m["_points"][1]:
                continue
            p = vals(m["_points"][1])
            add_light(img, x0 + p[3], y0 - p[4], m["_width"] * 2.2, m["_height"] * 2.2, vals(m["_color"]), s)
        # the HUD font's look in game: cream with a 1 px black drop shadow (Look.lua "shadow" edge, the default)
        for (tx, anchor, txt) in (((x0 + 5), "lm", name), ((x0 + W - 5), "rm", "0.8")):
            d.text(((tx + 1) * s, (y0 + 1) * s), txt, fill=(0, 0, 0), font=font, anchor=anchor)
            d.text((tx * s, y0 * s), txt, fill=(245, 235, 220), font=font, anchor=anchor)
        lua.execute("HogHealsHUD.CastThemes.Clear(HH_cb)")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print("wrote", OUT.relative_to(ROOT))
    errs = [e["msg"] for e in lua.eval("HogHeals.errors").values()]
    print("addon errors:", errs or "none")
    return 1 if errs else 0


if __name__ == "__main__":
    raise SystemExit(main())
