"""Generic PREVIEW painter for HogTron UI frames built in the test harness (lupa + tests/wow_mock.lua).

Walks a frame's regions and children the way the client stacks them (texture layers, then child frames by level),
resolves anchors (one point + size, two points, SetAllPoints), and composites: our own art (HogHeals/Media/*.tga,
with tex coords incl. mirrored and repeated ones), plain colour textures, font strings (Inter, the HogTron UI default
font). Item / spell / portrait art is a placeholder square. NOT a screenshot of WoW: fonts and pixel snapping differ.

Used by dev/render_ui_art.py (the 2026-10-15 art-set previews).
"""
from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
MEDIA = ROOT / "HogTronUI" / "Media"
FONT = ROOT / "HogTronUI" / "Media" / "Fonts" / "Inter-SemiBold.ttf"
LAYERS = {"BACKGROUND": 0, "BORDER": 1, "ARTWORK": 2, "OVERLAY": 3}
TEMPLATE_SIZE = {"HogTronFontSmall": 10, "HogTronFontHighlight": 12, "HogTronFontNormal": 12, "HogTronFontNormalSmall": 10,
                 "HogTronFontNormalLarge": 16, "GameFontNormal": 12}


def vals(t):
    return list(t.values()) if t is not None else []


class Painter:
    def __init__(self, lua, scale=2):
        self.lua, self.s = lua, scale
        self.ident = lua.eval("tostring")
        self.fonts = {}
        self.rects = {}
        self.cache = {}

    def font(self, size):
        size = int(round(size or 12))
        if size not in self.fonts:
            self.fonts[size] = ImageFont.truetype(str(FONT), int(size * self.s * 0.95))
        return self.fonts[size]

    @staticmethod
    def at(rect, point):
        l, t, w, h = rect
        x = {"LEFT": l, "TOPLEFT": l, "BOTTOMLEFT": l, "RIGHT": l + w, "TOPRIGHT": l + w, "BOTTOMRIGHT": l + w}.get(point, l + w / 2)
        y = {"TOP": t, "TOPLEFT": t, "TOPRIGHT": t, "BOTTOM": t + h, "BOTTOMLEFT": t + h, "BOTTOMRIGHT": t + h}.get(point, t + h / 2)
        return x, y

    def anchor_xy(self, p):
        point, rel, relp, x, y = (p + [None] * 5)[:5]
        base = self.rect(rel) if rel is not None else self.root
        ax, ay = self.at(base, relp or point)
        return point, ax + (x or 0), ay - (y or 0)

    def rect(self, r):
        key = self.ident(r)
        if key in self.rects:
            return self.rects[key]
        w, h = r["_width"] or 0, r["_height"] or 0
        if r["_kind"] == "FontString" and not w and r["_text"]:
            # the client sizes an unconstrained font string to its text; chained anchors (title "HOG" + "TRON UI") need it
            last = r["_last"]["SetFont"] if r["_last"] is not None else None
            size = vals(last)[1] if last is not None and len(vals(last)) > 1 else TEMPLATE_SIZE.get(r["_font"], 12)
            w = ImageDraw.Draw(Image.new("RGB", (1, 1))).textlength(str(r["_text"]), font=self.font(size)) / self.s
            h = h or size * 1.2
        pts = [vals(p) for p in vals(r["_points"])]
        parent = r["_parent"]
        if not pts and parent is not None and parent["_kind"] == "Slider" and r["_kind"] == "Texture":
            # a slider's thumb has no anchor of its own: the client puts it at the value
            pl, pt, pw, ph = self.rect(parent)
            lo, hi, v = parent["_min"] or 0, parent["_max"] or 1, parent["_value"] or 0
            f = 0 if hi == lo else max(0, min(1, (v - lo) / (hi - lo)))
            out = (pl + f * (pw - w), pt + (ph - h) / 2, w, h)
            self.rects[key] = out
            return out
        if not pts:
            out = self.rect(parent) if parent is not None else self.root
        elif pts[0][0] == "ALL":
            out = self.rect(pts[0][1]) if pts[0][1] is not None else self.rect(r["_parent"])
        else:
            xs, ys = {}, {}
            for p in pts:
                point, ax, ay = self.anchor_xy(p)
                if point in ("LEFT", "TOPLEFT", "BOTTOMLEFT"):
                    xs["l"] = ax
                elif point in ("RIGHT", "TOPRIGHT", "BOTTOMRIGHT"):
                    xs["r"] = ax
                else:
                    xs["c"] = ax
                if point in ("TOP", "TOPLEFT", "TOPRIGHT"):
                    ys["t"] = ay
                elif point in ("BOTTOM", "BOTTOMLEFT", "BOTTOMRIGHT"):
                    ys["b"] = ay
                else:
                    ys["m"] = ay
            if "l" in xs and "r" in xs:
                l, w = xs["l"], xs["r"] - xs["l"]
            elif "l" in xs:
                l = xs["l"]
            elif "r" in xs:
                l = xs["r"] - w
            else:
                l = xs.get("c", 0) - w / 2
            if "t" in ys and "b" in ys:
                t, h = ys["t"], ys["b"] - ys["t"]
            elif "t" in ys:
                t = ys["t"]
            elif "b" in ys:
                t = ys["b"] - h
            else:
                t = ys.get("m", 0) - h / 2
            out = (l, t, w, h)
        self.rects[key] = out
        return out

    def source(self, name):
        if name in self.cache:
            return self.cache[name]
        im = None
        if "HogTronUI" in name and "Media" in name:
            f = MEDIA / (name.replace("\\", "/").split("/")[-1] + ".tga")
            if f.exists():
                im = Image.open(f).convert("RGBA")
        elif "WHITE8X8" in name:
            im = Image.new("RGBA", (8, 8), (255, 255, 255, 255))
        else:
            im = Image.new("RGBA", (64, 64), (90, 74, 56, 255))
            ImageDraw.Draw(im).rectangle([8, 8, 55, 55], fill=(140, 112, 76, 255))
        self.cache[name] = im
        return im

    def texture(self, img, r):
        l, t, w, h = self.rect(r)
        if w <= 0.5 or h <= 0.5:
            return
        col = (vals(r["_color"]) + [1, 1, 1, 1])[:4]
        tex = r["_texture"]
        W, H = max(1, int(round(w * self.s))), max(1, int(round(h * self.s)))
        if tex is None:
            if not vals(r["_color"]):
                return
            piece = Image.new("RGBA", (W, H), tuple(int(max(0, min(1, c)) * 255) for c in col))
            img.alpha_composite(piece, (int(l * self.s), int(t * self.s)))
            return
        src = self.source(str(tex))
        tc = vals(r["_texCoord"])
        u0, u1, v0, v1 = (tc + [0, 1, 0, 1])[:4] if len(tc) >= 4 else (0, 1, 0, 1)
        sw, sh = src.size
        lo_u, hi_u, lo_v, hi_v = min(u0, u1), max(u0, u1), min(v0, v1), max(v0, v1)
        import math
        nx = max(1, math.ceil(hi_u) - math.floor(lo_u))
        ny = max(1, math.ceil(hi_v) - math.floor(lo_v))
        tile = Image.new("RGBA", (sw * nx, sh * ny))
        for i in range(nx):
            for j in range(ny):
                tile.paste(src, (i * sw, j * sh))
        ou, ov = math.floor(lo_u), math.floor(lo_v)
        box = (int((lo_u - ou) * sw), int((lo_v - ov) * sh), max(int((lo_u - ou) * sw) + 1, int(round((hi_u - ou) * sw))),
               max(int((lo_v - ov) * sh) + 1, int(round((hi_v - ov) * sh))))
        piece = tile.crop(box)
        if u0 > u1:
            piece = piece.transpose(Image.FLIP_LEFT_RIGHT)
        if v0 > v1:
            piece = piece.transpose(Image.FLIP_TOP_BOTTOM)
        piece = piece.resize((W, H), Image.LANCZOS)
        if col != [1, 1, 1, 1]:
            rr, gg, bb, aa = piece.split()
            rr = rr.point(lambda v: int(v * col[0])); gg = gg.point(lambda v: int(v * col[1])); bb = bb.point(lambda v: int(v * col[2]))
            aa = aa.point(lambda v: int(v * col[3]))
            piece = Image.merge("RGBA", (rr, gg, bb, aa))
        blend = vals(r["_last"]["SetBlendMode"])[0] if r["_last"]["SetBlendMode"] is not None else "BLEND"
        x0, y0 = int(l * self.s), int(t * self.s)
        if blend == "ADD":
            from PIL import ImageChops
            region = img.crop((x0, y0, x0 + W, y0 + H)).convert("RGB")
            lit = Image.composite(piece.convert("RGB"), Image.new("RGB", piece.size), piece.getchannel("A"))
            img.paste(ImageChops.add(region, lit).convert("RGBA"), (x0, y0))
        else:
            img.alpha_composite(piece, (x0, y0))

    def text(self, img, r):
        txt = r["_text"]
        if not txt:
            return
        import re
        txt = re.sub(r"\|c[0-9a-fA-F]{8}|\|r|\|T[^|]*\|t", "", str(txt))
        last = r["_last"]["SetFont"] if r["_last"] is not None else None
        size = vals(last)[1] if last is not None and len(vals(last)) > 1 else TEMPLATE_SIZE.get(r["_font"], 12)
        col = tuple(int(max(0, min(1, c)) * 255) for c in (vals(r["_color"]) + [0.96, 0.92, 0.86])[:3])
        font = self.font(size)
        d = ImageDraw.Draw(img)
        l, t, w, h = self.rect(r)
        pts = vals(r["_points"])
        point = vals(pts[0])[0] if pts else "CENTER"
        just = vals(r["_last"]["SetJustifyH"])[0] if r["_last"]["SetJustifyH"] is not None else None
        line = str(txt).split("\n")[0]
        wrap = r["_last"]["SetWordWrap"] is not None and vals(r["_last"]["SetWordWrap"])[0]
        if wrap and w and max(d.textlength(x, font=font) for x in str(txt).split("\n")) > w * self.s:   # wraps: the client lays it out over lines
            lines = []
            for para in str(txt).split("\n"):
                cur = ""
                for word in para.split(" "):
                    test = (cur + " " + word).strip()
                    if cur and d.textlength(test, font=font) > w * self.s:
                        lines.append(cur)
                        cur = word
                    else:
                        cur = test
                lines.append(cur)
            step = (size + 4) * self.s
            for i, ln in enumerate(lines):
                y = t * self.s + i * step
                d.text((l * self.s + 1, y + 1), ln, fill=(0, 0, 0), font=font, anchor="la")
                d.text((l * self.s, y), ln, fill=col, font=font, anchor="la")
            return
        if w and d.textlength(line, font=font) > w * self.s:
            while line and d.textlength(line + "...", font=font) > w * self.s:
                line = line[:-1]
            line += "..."
        cy = t + h / 2 if h else t
        if not w:
            anc = {"LEFT": "lm", "RIGHT": "rm", "TOPLEFT": "la", "TOPRIGHT": "ra", "TOP": "ma", "BOTTOM": "md"}.get(point, "mm")
            d.text((l * self.s + 1, t * self.s + 1), line, fill=(0, 0, 0), font=font, anchor=anc)
            d.text((l * self.s, t * self.s), line, fill=col, font=font, anchor=anc)
            return
        if just == "LEFT" or (just is None and point in ("LEFT", "TOPLEFT", "BOTTOMLEFT")):
            x, anc = l, "lm"
        elif just == "RIGHT":
            x, anc = l + w, "rm"
        else:
            x, anc = l + w / 2, "mm"
        if point in ("TOPLEFT", "TOP", "TOPRIGHT") and not h:
            anc = anc[0] + "a"
            cy = t
        d.text((x * self.s + 1, cy * self.s + 1), line, fill=(0, 0, 0), font=font, anchor=anc)
        d.text((x * self.s, cy * self.s), line, fill=col, font=font, anchor=anc)

    def walk(self, img, frame):
        if not frame["_shown"]:
            return
        if frame["_kind"] == "ScrollFrame" and not getattr(self, "_clipping", False):
            # the client clips a scroll frame's content to its own rect (what is below scrolls); draw it that way
            l, t, w, h = self.rect(frame)
            if w and h:
                layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
                self._clipping = True
                try:
                    self.walk(layer, frame)
                finally:
                    self._clipping = False
                box = (int(l * self.s), int(t * self.s), int((l + w) * self.s), int((t + h) * self.s))
                img.alpha_composite(layer.crop(box), (box[0], box[1]))
                return
        kids = vals(frame["_children"])
        regions = [c for c in kids if c["_kind"] in ("Texture", "FontString") and c["_shown"]]
        regions.sort(key=lambda c: LAYERS.get(c["_layer"], 2) if c["_kind"] == "Texture" else 4)
        for c in regions:
            if c["_kind"] == "Texture":
                self.texture(img, c)
        for c in regions:
            if c["_kind"] == "FontString":
                self.text(img, c)
        frames = [c for c in kids if c["_kind"] not in ("Texture", "FontString", "AnimationGroup")]
        frames.sort(key=lambda c: c["_frameLevel"] or 0)
        for c in frames:
            self.walk(img, c)

    def paint(self, frame, margin=24, bg=(46, 54, 40)):
        fw, fh = frame["_width"], frame["_height"]
        self.rects = {}
        self.root = (margin, margin, fw, fh)
        self.rects[self.ident(frame)] = self.root
        img = Image.new("RGBA", (int((fw + 2 * margin) * self.s), int((fh + 2 * margin) * self.s)), bg + (255,))
        self.walk(img, frame)
        return img.convert("RGB")
