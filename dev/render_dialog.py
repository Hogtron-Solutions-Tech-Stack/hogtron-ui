"""Render PREVIEWS of the HogTron UI quest dialog window to docs/mockups/dialog-<page>.png.

Not screenshots of WoW. The real Dialog.lua runs in the test harness (lupa + tests/wow_mock.lua) against the sample
quest API in tests/test_quest_dialog.py; this script reads back what the code set on its frames (anchors, sizes,
colours, text, shown / hidden) and draws that with the addon's own Inter font. Line wrapping is PIL's, not the
client's, and item icons are quality-coloured squares. The quest text and items are SAMPLE DATA.

    python dev/render_dialog.py [--scale 2]
"""
from __future__ import annotations

import argparse
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
from loader import AddonLoader  # noqa: E402
from test_quest_dialog import boot  # noqa: E402

OUT = ROOT / "docs" / "mockups"
FONT = ROOT / "HogHeals" / "Media" / "Fonts" / "Inter-SemiBold.ttf"
WORLD = (36, 48, 40)
TEXT_KEYS = ("npc", "title", "body", "objHead", "objectives", "rewHead", "xp", "money", "hint")


def rgb(c, default=(245, 235, 220)):
    if c is None:
        return default
    v = list(c.values()) if hasattr(c, "values") else list(c)
    if len(v) < 3:
        return default
    return tuple(int(max(0, min(1, x)) * 255) for x in v[:3])


def alpha(c, default=1.0):
    v = list(c.values()) if c is not None else []
    return v[3] if len(v) > 3 and v[3] is not None else default


def blend(fg, bg, a):
    return tuple(int(f * a + b * (1 - a)) for f, b in zip(fg, bg))


class Painter:
    def __init__(self, lua, scale):
        self.lua, self.s = lua, scale
        self.fonts = {}

    def font(self, size):
        size = int(size or 14)
        if size not in self.fonts:
            self.fonts[size] = ImageFont.truetype(str(FONT), int(size * self.s * 0.92))
        return self.fonts[size]

    def size_of(self, fs, default):
        last = fs["_last"]["SetFont"] if fs["_last"] is not None else None
        vals = list(last.values()) if last is not None else []
        return vals[1] if len(vals) > 1 and vals[1] else default

    def rect(self, d, box, fill, outline=None):
        x, y, w, h = box
        d.rectangle([x * self.s, y * self.s, (x + w) * self.s - 1, (y + h) * self.s - 1], fill=fill, outline=outline)

    def wrap(self, d, text, font, width):
        lines = []
        for para in str(text).split("\n"):
            words, line = para.split(" "), ""
            for w in words:
                cand = (line + " " + w).strip()
                if line and d.textlength(cand, font=font) > width * self.s:
                    lines.append(line)
                    line = w
                else:
                    line = cand
            lines.append(line)
        return lines

    def text(self, d, x, y, text, fill, size, width=None, anchor="la"):
        font = self.font(size)
        if width:
            for i, line in enumerate(self.wrap(d, text, font, width)):
                d.text((x * self.s, (y + i * size * 1.3) * self.s), line, fill=fill, font=font, anchor=anchor)
        else:
            d.text((x * self.s, y * self.s), str(text), fill=fill, font=font, anchor=anchor)

    def paint(self):
        lua = self.lua
        D = lua.eval("HogHealsQuests.Dialog")
        f = D["frame"]
        size = lua.eval("HogHeals.db.profile.quests.dialog.fontSize") or 14
        fw, fh = f["_width"], f["_height"]
        m = 24
        img = Image.new("RGB", (int((fw + 2 * m) * self.s), int((fh + 2 * m) * self.s)), WORLD)
        d = ImageDraw.Draw(img)
        bg = rgb(f["bg"]["_color"])
        self.rect(d, (m, m, fw, fh), blend(bg, WORLD, alpha(f["bg"]["_color"])), outline=rgb(f["edge"][1]["_color"]))
        self.text(d, m + fw - 15, m + 15, "x", rgb(f["close"]["label"]["_color"]), size, anchor="mm")
        for key in TEXT_KEYS:
            el = f[key]
            if not el["_shown"] or not el["_text"]:
                continue
            p = el["_points"][1]
            sz = self.size_of(el, size)
            self.text(d, m + p[4], m - p[5], el["_text"], rgb(el["_color"]), sz, width=el["_width"])
        rule = f["rule"]["_points"][1]
        self.rect(d, (m + rule[4], m - rule[5], fw - 2 * rule[4], 1), rgb(f["rule"]["_color"]))
        for r in D["rows"].values():
            if not r["_shown"]:
                continue
            p = r["_points"][1]
            x, y, w, h = m + p[4], m - p[5], r["_width"], r["_height"]
            ca = alpha(r["bg"]["_color"], 0)
            if ca > 0:
                self.rect(d, (x, y, w, h), blend(rgb(r["bg"]["_color"]), blend(bg, WORLD, alpha(f["bg"]["_color"])), ca))
            if r["num"]["_text"]:
                self.text(d, x + 4, y + h / 2, r["num"]["_text"], rgb(r["num"]["_color"]), size - 3, anchor="lm")
            tex = r["icon"]["_texture"]
            if r["icon"]["_shown"] and tex is not None:
                ix, iy = x + 22, y + (h - 20) / 2
                tc = rgb(r["text"]["_color"])
                if isinstance(tex, str) and "quest_" in tex:
                    q = (242, 166, 38) if "open" in tex else (64, 204, 89)
                    self.rect(d, (ix, iy, 20, 20), (20, 20, 24), outline=q)
                    self.text(d, ix + 10, iy + 10, "!" if "open" in tex else "?", q, 14, anchor="mm")
                else:
                    self.rect(d, (ix, iy, 20, 20), tuple(int(c * 0.45) for c in tc), outline=tc)
            if r["glyph"]["_text"]:
                self.text(d, x + 32, y + h / 2, r["glyph"]["_text"], rgb(r["glyph"]["_color"]), size, anchor="mm")
            self.text(d, x + 50, y + h / 2, r["text"]["_text"], rgb(r["text"]["_color"]), size, anchor="lm")
        prim, sec = f["primary"], f["secondary"]
        px = None
        if prim["_shown"]:
            p = prim["_points"][1]
            px, py = m + fw + p[4] - prim["_width"], m - p[5]
            self.button(d, prim, px, py, size)
        if sec["_shown"]:
            p = sec["_points"][1]
            if p[1] == "RIGHT" and px is not None:
                sx, sy = px - 8 - sec["_width"], m - prim["_points"][1][5]
            else:
                sx, sy = m + fw + p[4] - sec["_width"], m - p[5]
            self.button(d, sec, sx, sy, size)
        return img

    def button(self, d, b, x, y, size):
        a = alpha(b["bg"]["_color"])
        self.rect(d, (x, y, b["_width"], b["_height"]), blend(rgb(b["bg"]["_color"]), WORLD, a))
        self.text(d, x + b["_width"] / 2, y + b["_height"] / 2, b["label"]["_text"], rgb(b["label"]["_color"]), size, anchor="mm")
        if b["key"]["_text"]:
            self.text(d, x + b["_width"] - 4, y + b["_height"] - 3, b["key"]["_text"], rgb(b["key"]["_color"]), size - 5, anchor="rd")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=int, default=2)
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    lua = boot(AddonLoader().bootstrap(), before='MockUnits.npc = { name = "Marshal Dughan" }')
    p = Painter(lua, args.scale)
    shots = [
        ("detail-ink", 'HogHeals.db.profile.quests.dialog.theme = "ink"; REWARDS = { { "Sample Wolfhide Cloak", 133762, 1, 2 } }; MockFire("QUEST_DETAIL")', None),
        ("complete-choice-ink", 'CHOICES = { { "Sample Brawler Gloves", 132939, 1, 2 }, { "Sample Woodland Tunic", 132721, 1, 2 }, { "Sample Light Pants", 134586, 1, 1 } }; MockFire("QUEST_COMPLETE")', 2),
        ("gossip-parchment", 'HogHeals.db.profile.quests.dialog.theme = "parchment"; GAC = { { title = "Wolves Across the Border", questID = 55, isComplete = true } }; GAV = { { title = "Kobold Camp Cleanup", questID = 101 } }; GOPT = { { name = "I would like to buy something.", gossipOptionID = 3, orderIndex = 0 }, { name = "Make this inn your home.", gossipOptionID = 4, orderIndex = 1 } }; MockFire("GOSSIP_SHOW")', None),
        ("detail-parchment", 'MockFire("QUEST_DETAIL")', None),
    ]
    for name, prep, pick in shots:
        lua.execute("HogHealsQuests.Dialog.Hide()")
        lua.execute(prep)
        if pick:
            lua.execute(f'_G["HogTronUIDialogRow" .. HogHealsQuests.Dialog.SlotOfPick({pick})]:Click()')
        img = p.paint()
        path = OUT / f"dialog-{name}.png"
        img.save(path)
        print("wrote", path.relative_to(ROOT))
    errs = [e["msg"] for e in lua.eval("HogHeals.errors").values()]
    print("addon errors:", errs or "none")
    return 1 if errs else 0


if __name__ == "__main__":
    raise SystemExit(main())
