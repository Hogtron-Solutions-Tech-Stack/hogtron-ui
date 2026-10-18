"""Render PREVIEWS of the HogTron UI quest dialog to docs/mockups/dialog-<page>.png.

Not screenshots of WoW. The real Dialog.lua runs in the test harness (lupa + tests/wow_mock.lua) against the sample
quest API in tests/test_quest_dialog.py; this script walks every texture and font string the code created, resolves
their anchors, and composites the addon's own art (HogTronUI/Media/dialog_*.tga, with the code's tex coords and
vertex colours) the way the client stacks layers. Text is drawn in Friz Quadrata when a local copy exists (WoW
ships it inside its archives; a Dialogue UI install has a loose copy), else Georgia - so line breaks can differ a
little from the game. Item icons and the NPC portrait are placeholders. Quest text and items are SAMPLE DATA.

    python -P dev/render_dialog.py [--scale 2]
"""
from __future__ import annotations

import argparse
import pathlib
import re
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
from loader import AddonLoader  # noqa: E402
from test_quest_dialog import boot  # noqa: E402

OUT = ROOT / "docs" / "mockups"
MEDIA = ROOT / "HogTronUI" / "Media"
WORLD = (58, 66, 48)
LAYERS = {"BACKGROUND": 0, "BORDER": 1, "ARTWORK": 2, "OVERLAY": 3, None: 2}
FRIZ = [pathlib.Path(r"C:/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns/DialogueUI/Fonts/frizqt__.ttf"),
        pathlib.Path(r"C:/Windows/Fonts/georgia.ttf")]


def vals(t):
    return list(t.values()) if t is not None else []


# |Tpath:h:w:x:y|t - an inline texture in a font string (coin / XP icons). Ours are drawn from HogTronUI/Media.
ICON = re.compile(r"\|T([^:|]+)((?::-?\d+)*)\|t")


def pieces(s):
    """Text split into ("t", text) and ("i", media file or None, px) pieces."""
    out, pos = [], 0
    for m in ICON.finditer(s):
        if m.start() > pos:
            out.append(("t", s[pos:m.start()]))
        nums = [int(v) for v in m.group(2).split(":")[1:] if v]
        name = m.group(1).replace("\\", "/").split("/")[-1]
        f = MEDIA / f"{name}.tga"
        out.append(("i", f if f.exists() else None, nums[0] if nums else 14))
        pos = m.end()
    if pos < len(s):
        out.append(("t", s[pos:]))
    return out


class Painter:
    def __init__(self, lua, s):
        self.lua, self.s = lua, s
        self.font_path = next((str(p) for p in FRIZ if p.exists()), None)
        self.cache = {}
        self.rects = {}
        # lupa gives a new Python proxy for the same Lua table every time: identify tables by Lua's own tostring
        self.ident = lua.eval("tostring")

    def font(self, size):
        size = int(size or 14)
        if size not in self.cache:
            self.cache[size] = ImageFont.truetype(self.font_path, int(size * self.s)) if self.font_path else ImageFont.load_default()
        return self.cache[size]

    # ---- geometry: image coords, y down, the dialog frame's top-left at (m, m)
    @staticmethod
    def at(rect, point):
        l, t, w, h = rect
        x = {"LEFT": l, "TOPLEFT": l, "BOTTOMLEFT": l, "RIGHT": l + w, "TOPRIGHT": l + w, "BOTTOMRIGHT": l + w}.get(point, l + w / 2)
        y = {"TOP": t, "TOPLEFT": t, "TOPRIGHT": t, "BOTTOM": t + h, "BOTTOMLEFT": t + h, "BOTTOMRIGHT": t + h}.get(point, t + h / 2)
        return x, y

    def rect(self, r):
        key = self.ident(r)
        if key in self.rects:
            return self.rects[key]
        w, h = r["_width"] or 0, r["_height"] or 0
        pts = r["_points"]
        p = vals(pts[1]) if pts and pts[1] is not None else None
        if p is None:
            out = self.root
        else:
            point, rel, relp, x, y = (p + [None] * 5)[:5]
            base = self.rect(rel) if rel is not None else self.root
            ax, ay = self.at(base, relp or point)
            ax, ay = ax + (x or 0), ay - (y or 0)
            dx = {"LEFT": 0, "TOPLEFT": 0, "BOTTOMLEFT": 0, "RIGHT": w, "TOPRIGHT": w, "BOTTOMRIGHT": w}.get(point, w / 2)
            dy = {"TOP": 0, "TOPLEFT": 0, "TOPRIGHT": 0, "BOTTOM": h, "BOTTOMLEFT": h, "BOTTOMRIGHT": h}.get(point, h / 2)
            out = (ax - dx, ay - dy, w, h)
        self.rects[key] = out
        return out

    # ---- drawing
    def texture(self, img, r):
        tex = r["_texture"]
        l, t, w, h = self.rect(r)
        if w <= 0 or h <= 0:
            return
        col = vals(r["_color"]) or [1, 1, 1, 1]
        col = (col + [1, 1, 1, 1])[:4]
        name = str(tex) if tex is not None else ""
        src = None
        # our art: HogTronUI since the folder rename (only the old HogHeals name was matched here, so every preview
        # drew our textures as item-icon placeholders)
        if any(k in name.replace(chr(92), "/") for k in ("HogTronUI/Media/", "HogHeals/Media/")):
            f = MEDIA / (name.replace("\\", "/").split("/")[-1] + ".tga")
            if f.exists():
                src = Image.open(f).convert("RGBA")
        elif "WHITE8X8" in name:
            src = Image.new("RGBA", (8, 8), (255, 255, 255, 255))
        elif self.ident(r) == self.portrait_id:
            src = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
            dd = ImageDraw.Draw(src)
            dd.ellipse([0, 0, 63, 63], fill=(70, 58, 46, 255))
            dd.ellipse([20, 10, 44, 36], fill=(150, 120, 92, 255))
            dd.ellipse([10, 34, 54, 76], fill=(120, 96, 72, 255))
            col = [1, 1, 1, 1]
        elif tex is not None:   # an item icon: placeholder
            src = Image.new("RGBA", (64, 64), (96, 78, 58, 255))
            dd = ImageDraw.Draw(src)
            dd.rectangle([8, 8, 55, 55], fill=(140, 112, 76, 255))
            col = [1, 1, 1, 1]
        if src is None:
            return
        tc = vals(r["_texCoord"])
        if len(tc) == 4:
            W, H = src.size
            box = (int(tc[0] * W), int(tc[2] * H), max(int(tc[0] * W) + 1, int(round(tc[1] * W))), max(int(tc[2] * H) + 1, int(round(tc[3] * H))))
            src = src.crop(box)
        src = src.resize((max(1, int(w * self.s)), max(1, int(h * self.s))), Image.LANCZOS)
        rr, gg, bb, aa = src.split()
        rr = rr.point(lambda v: int(v * col[0])); gg = gg.point(lambda v: int(v * col[1])); bb = bb.point(lambda v: int(v * col[2]))
        aa = aa.point(lambda v: int(v * col[3]))
        img.alpha_composite(Image.merge("RGBA", (rr, gg, bb, aa)), (int(l * self.s), int(t * self.s)))

    def text(self, img, r):
        txt = r["_text"]
        if not txt:
            return
        size = 14
        last = r["_last"]["SetFont"] if r["_last"] is not None else None
        if last is not None and len(vals(last)) > 1:
            size = vals(last)[1]
        col = tuple(int(max(0, min(1, v)) * 255) for v in (vals(r["_color"]) + [1, 1, 1])[:3])
        font = self.font(size)
        d = ImageDraw.Draw(img)
        l, t, w, h = self.rect(r)
        p = vals(r["_points"][1]) if r["_points"][1] is not None else ["TOPLEFT"]
        point = p[0]
        just = vals(r["_last"]["SetJustifyH"])[0] if r["_last"]["SetJustifyH"] is not None else "LEFT"
        lines = []
        for para in str(txt).split("\n"):
            words, line = para.split(" "), ""
            for wd in words:
                cand = (line + " " + wd).strip()
                if w and line and self.measure(d, font, cand) > w * self.s:
                    lines.append(line)
                    line = wd
                else:
                    line = cand
            lines.append(line)
        lh = size * 1.25 + int(size * 0.25)
        if not w and point in ("CENTER", "LEFT", "RIGHT", "BOTTOMRIGHT"):
            anc = {"CENTER": "mm", "LEFT": "lm", "RIGHT": "rm", "BOTTOMRIGHT": "rd"}[point]
            d.text((l * self.s, t * self.s), lines[0], fill=col, font=font, anchor=anc)
            return
        if point == "CENTER":
            ax, ay = self.at((l, t, w, h), "CENTER")
            d.text((ax * self.s, ay * self.s), lines[0], fill=col, font=font, anchor="mm")
            return
        jv = vals(r["_last"]["SetJustifyV"])[0] if r["_last"]["SetJustifyV"] is not None else "TOP"
        if point == "LEFT" or (jv == "MIDDLE" and h):
            y0 = t + h / 2 - len(lines) * lh / 2 + size * 0.15
        else:
            y0 = t
        for i, ln in enumerate(lines):
            if ICON.search(ln) and just != "CENTER":
                self.rich(img, d, l * self.s, (y0 + i * lh) * self.s, ln, font, col, size)
                continue
            x = l if just != "CENTER" else l + w / 2
            d.text((x * self.s, (y0 + i * lh) * self.s), ICON.sub("", ln), fill=col, font=font, anchor="la" if just != "CENTER" else "ma")

    def measure(self, d, font, s):
        return sum(d.textlength(p[1], font=font) if p[0] == "t" else (p[2] + 2) * self.s for p in pieces(s))

    def rich(self, img, d, x, y, s, font, col, size):
        """One line with inline icons: text runs, then each icon pasted at the font's height, 2 px off the number."""
        for p in pieces(s):
            if p[0] == "t":
                d.text((x, y), p[1], fill=col, font=font, anchor="la")
                x += d.textlength(p[1], font=font)
            else:
                px = int(p[2] * self.s)
                x += 2 * self.s
                if p[1] is not None:
                    ic = Image.open(p[1]).convert("RGBA").resize((px, px), Image.LANCZOS)
                    img.alpha_composite(ic, (int(x), int(y + (size * 1.2 * self.s - px) / 2)))
                x += px

    def walk(self, img, frame):
        if not frame["_shown"]:
            return
        kids = vals(frame["_children"])
        regions = [c for c in kids if c["_kind"] in ("Texture", "FontString") and c["_shown"]]
        regions.sort(key=lambda c: (LAYERS.get(c["_layer"], 2) if c["_kind"] == "Texture" else 4))
        for c in regions:
            if c["_kind"] == "Texture":
                self.texture(img, c)
        for c in regions:
            if c["_kind"] == "FontString":
                self.text(img, c)
        for c in kids:
            if c["_kind"] not in ("Texture", "FontString"):
                self.walk(img, c)

    def paint(self):
        f = self.lua.eval("HogTronUIDialog")
        m = 30
        fw, fh = f["_width"], f["_height"]
        self.root = (m, m, fw, fh)
        self.rects = {self.ident(f): self.root}
        self.portrait_id = self.ident(f["portrait"])
        img = Image.new("RGBA", (int((fw + 2 * m) * self.s), int((fh + 2 * m) * self.s)), WORLD + (255,))
        self.walk(img, f)
        return img.convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=int, default=2)
    s = ap.parse_args().scale
    OUT.mkdir(parents=True, exist_ok=True)
    lua = boot(AddonLoader().bootstrap(), before='MockUnits.npc = { name = "Marshal Dughan" }; function GetQuestID() return 7 end')
    lua.execute('QObj[7] = { { text = "0/8 Tough Wolf Meat" }, { text = "0/1 Kobold Candle" } }')
    lua.execute('TITLE = "Wolves Across the Border"; TEXT = "The wolves have grown bold, Hogolas. They come down from the hills at night and take what they please from the Stonefield and Maclure farms.\\n\\nBring me the meat of the Prowlers and Young Wolves you find along the border, and Northshire will rest easier."')
    p = Painter(lua, s)
    shots = [
        ("detail-light", 'HogHeals.db.profile.quests.dialog.theme = "light"; CHOICES = { { "Sample Brawler Gloves", 1, 1, 2 }, { "Sample Woodland Tunic", 2, 1, 2 }, { "Sample Light Pants", 3, 1, 1 } }; REWARDS = { { "Sample Wolfhide Cloak", 4, 1, 3 } }; MockFire("QUEST_DETAIL")', None),
        ("complete-choice-light", 'MockFire("QUEST_COMPLETE")', 2),
        ("progress-light", 'COMPLETABLE = false; REQUIRED = { { "Tough Wolf Meat", 5, 3 } }; MockFire("QUEST_PROGRESS")', None),
        ("gossip-light", 'GAC = { { title = "Wolves Across the Border", questID = 55, isComplete = true } }; GAV = { { title = "Kobold Camp Cleanup", questID = 101 } }; GOPT = { { name = "I would like to buy something.", gossipOptionID = 3, orderIndex = 0 }, { name = "Make this inn your home.", gossipOptionID = 4, orderIndex = 1 } }; MockFire("GOSSIP_SHOW")', None),
        ("detail-dark", 'HogHeals.db.profile.quests.dialog.theme = "dark"; MockFire("QUEST_DETAIL")', None),
        # Sean 2026-10-17's turn-in page: two long names next to their number chips, XP + coins as icons
        ("complete-rewards-light", '''HogHeals.db.profile.quests.dialog.theme = "light"; COMPLETABLE = true; REQUIRED = {}; REWARDS = {}; CHOICES = { { "Hunter's Simple Cloak", 1, 1, 2 }, { "Highlands Defender's Shield", 2, 1, 2 } }; XP = 775; MONEY = 600; MockFire("QUEST_COMPLETE")''', None),
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
    for old in ("dialog-detail-ink.png", "dialog-complete-choice-ink.png", "dialog-gossip-parchment.png", "dialog-detail-parchment.png"):
        if (OUT / old).exists():
            (OUT / old).unlink()
            print("removed old", old)
    errs = [e["msg"] for e in lua.eval("HogHeals.errors").values()]
    print("addon errors:", errs or "none")
    return 1 if errs else 0


if __name__ == "__main__":
    raise SystemExit(main())
