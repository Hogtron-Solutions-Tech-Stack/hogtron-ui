"""Render PREVIEWS of the cast bar: every school theme (docs/mockups/cast-themes.png) or, with --spells, every class's
own spell strips (docs/mockups/cast-spells-<class>.png).

Not a screenshot of WoW. The real HogTron_HUD (HUD.lua + Castbar.lua + CastThemes.lua) runs in the test harness;
for each row this script starts a cast through CastThemes.Apply (the theme, and for --spells the spell's own strip),
moves time on so the fill sits at 60 %, lets CastThemes.Tick place the glow and the motes, then reads back what the
code set (fill colour, which strip it drew and in which blend mode, glow colour / alpha, mote positions / sizes /
alphas, spark colour, texts) and draws it with the addon's own art, Inter font and additive light.

    python dev/render_cast_themes.py [--scale 2]
    python dev/render_cast_themes.py --spells [--scale 2]
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
from loader import AddonLoader  # noqa: E402

MOCKUPS = ROOT / "docs" / "mockups"
OUT = MOCKUPS / "cast-themes.png"
MEDIA = ROOT / "HogTronUI" / "Media"
GLOW = MEDIA / "target_glow.tga"
FONT = MEDIA / "Fonts" / "Inter-SemiBold.ttf"
W, H, ROW, LEFT = 300, 18, 46, 150
SAMPLES = {"holy": "Flash Heal", "fire": "Fireball", "frost": "Frostbolt", "arcane": "Arcane Missiles", "shadow": "Mind Flay",
           "nature": "Lightning Bolt", "earth": "Mining", "herb": "Herb Gathering", "leather": "Skinning", "water": "Fishing",
           "gold": "Opening", "craft": "Linen Bandage", "aim": "Aimed Shot"}
CLASSES = ("mage", "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "warlock", "druid")


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


def paint_row(lua, img, d, font, s, row, label, key, art, name):
    """One bar: cast `name` with theme `key` (and the spell strip `art`, or None) through the real Apply / Tick."""
    art_arg = f'"{art}"' if art else "nil"
    lua.execute(f'''
      MockUnits.player.casting = {{ "{name}", "{name}", "icon", 100000, 102000, false, 1, false, nil }}
      HogHealsHUD.Castbar.state.casting = false
      MockState.time = 100
      local C = HogHealsHUD.Castbar
      C.state.preview = nil
      local b = HH_cb
      local T = HogHealsHUD.CastThemes
      b:SetStatusBarColor(0.13, 0.83, 0.88)
      T.Apply(b, "{key}", 100, {art_arg})
      b.text:SetText("{name}")
      b:SetValue(0.6)
      T.Tick(b, 0.6, 100.8)''')
    y0 = 20 + row * ROW + ROW / 2
    x0 = LEFT
    L = lua.eval("HogHealsHUD.CastThemes.layers")
    active = lua.eval("HogHealsHUD.CastThemes.active")
    cb = lua.eval("HH_cb")
    d.text((10 * s, y0 * s), label, fill=(200, 200, 205), font=font, anchor="lm")
    if L["glow"]["_shown"]:
        add_light(img, x0 + W / 2, y0, W + 24, H + 18, vals(L["glow"]["_color"]), s)
    # bar: ink background at 0.7, then the fill
    bg = Image.new("RGB", (W * s, H * s), (18, 18, 23))
    region = img.crop((int(x0 * s), int((y0 - H / 2) * s), int((x0 + W) * s), int((y0 + H / 2) * s)))
    img.paste(Image.blend(region, bg, 0.7), (int(x0 * s), int((y0 - H / 2) * s)))
    fc = tuple(int(v * 255) for v in vals(cb["_color"])[:3])
    d.rectangle([x0 * s, (y0 - H / 2) * s, (x0 + W * 0.6) * s - 1, (y0 + H / 2) * s - 1], fill=fc)
    layer = L["art"]
    drawn = active["art"] if active is not None else None
    if layer["_shown"] and drawn:
        # the strip the code really drew: repeated, scaled to the bar's height, cropped to u0..u1 (REPEAT wrap)
        tc = vals(layer["_texCoord"])
        strip = Image.open(MEDIA / f"cast_{drawn}.tga").convert("RGBA")
        rep = int(512 * H / 64 * s)
        strip = strip.resize((rep, int(H * s)), Image.LANCZOS)
        fill_w = int(W * 0.6 * s)
        u0 = tc[0] % 1.0
        start = int(u0 * rep)
        tiles = Image.new("RGBA", (rep * (fill_w // rep + 3), int(H * s)))
        for k in range(fill_w // rep + 3):
            tiles.paste(strip, (k * rep, 0))
        piece = tiles.crop((start, 0, start + fill_w, int(H * s)))
        alpha = vals(layer["_color"])[3] if len(vals(layer["_color"])) > 3 else 1
        region = img.crop((int(x0 * s), int((y0 - H / 2) * s), int(x0 * s) + fill_w, int((y0 + H / 2) * s)))
        blend = vals(layer["_last"]["SetBlendMode"])[0] if layer["_last"]["SetBlendMode"] is not None else "BLEND"
        if blend == "ADD":
            rgb = piece.convert("RGB").point(lambda v: int(v * alpha))
            img.paste(ImageChops.add(region, rgb), (int(x0 * s), int((y0 - H / 2) * s)))
        else:
            a = piece.getchannel("A").point(lambda v: int(v * alpha))
            region.paste(piece.convert("RGB"), (0, 0), a)
            img.paste(region, (int(x0 * s), int((y0 - H / 2) * s)))
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
    return drawn


def sheet(lua, s, rows, out):
    """rows: (label, theme key, spell strip or None, cast name)."""
    font = ImageFont.truetype(str(FONT), 10 * s)
    img = Image.new("RGB", ((LEFT + W + 40) * s, (ROW * len(rows) + 20) * s), (20, 24, 22))
    d = ImageDraw.Draw(img)
    for i, (label, key, art, name) in enumerate(rows):
        drawn = paint_row(lua, img, d, font, s, i, label, key, art, name)
        if art and drawn != art:
            print(f"  WARNING {label}: wanted {art}, drew {drawn}")
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print("wrote", out.relative_to(ROOT))


def spell_rows(lua):
    """Per class: one row per strip, labelled with the first spell it covers, cast through T.SpellArt's own match."""
    rows = {c: [] for c in CLASSES}
    owner = {}
    for c in CLASSES[1:]:
        for st in json.loads((ROOT / "dev" / "data" / f"spell_art_{c}.json").read_text())["strips"]:
            owner.setdefault(st["strip"], c)
    src = (ROOT / "HogTron_HUD" / "CastThemes.lua").read_text(encoding="utf-8")
    seen = set()
    for pat, art, theme in re.findall(r'\{ "([^"]+)", "(spell_[a-z_]+)", "([a-z]+)" \}', src):
        if art in seen:
            continue
        seen.add(art)
        name = pat.strip("^$").replace("%-", "-")
        if name == "Poison":
            name = "Instant Poison"
        if lua.eval(f'(HogHealsHUD.CastThemes.SpellArt("{name}"))') != art:
            print(f"  note: '{name}' does not match {art} on its own name")
        rows[owner.get(art, "mage")].append((name, theme, art, name))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=int, default=2)
    ap.add_argument("--spells", action="store_true", help="one sheet per class of the per-spell strips")
    a = ap.parse_args()
    s = a.scale
    lua = AddonLoader().bootstrap()
    for addon in ("HogTronUI", "HogTron_HUD"):
        lua.load_addon(addon)
    lua.player_login()
    lua.execute("HH_cb = HogHealsHUD.HUD.rows.castbar; HH_cb:SetWidth(300); HH_cb:SetHeight(18); MockState.time = 100")
    if a.spells:
        for cls, rows in spell_rows(lua).items():
            sheet(lua, s, rows, MOCKUPS / f"cast-spells-{cls}.png")
    else:
        order = list(lua.eval("HogHealsHUD.CastThemes.ORDER").values())
        sheet(lua, s, [(k, k, None, SAMPLES[k]) for k in order], OUT)
    errs = [e["msg"] for e in lua.eval("HogHeals.errors").values()]
    print("addon errors:", errs or "none")
    return 1 if errs else 0


if __name__ == "__main__":
    raise SystemExit(main())
