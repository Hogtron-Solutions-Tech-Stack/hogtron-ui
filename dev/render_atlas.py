"""Render PREVIEWS of the HogUI Atlas window to docs/mockups/atlas-<tab>.png.

Not screenshots of WoW. The real addon code runs in the test harness (lupa + tests/wow_mock.lua) with sample
items, a sample quest log and sample drops; this script walks the frames the code built, reads back what the code
set on them (size, anchor offsets, text, colours, shown / hidden) and draws that. Fonts differ from the client and
item icons are drawn as quality-coloured squares. The item names in the previews are SAMPLE DATA, not real drops.

    python dev/render_atlas.py [--scale 2] [--level 20]
"""
from __future__ import annotations

import argparse
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
from loader import AddonLoader  # noqa: E402
from atlas_helpers import boot  # noqa: E402

OUT = ROOT / "docs" / "mockups"
# which List columns sit on which tab (proxies of Lua tables cannot be compared from Python)
LISTS = {"dungeons": ["dungeons", "bosses", "detail"], "upgrades": ["upgrades"], "sets": ["setList", "set"],
         "wish": ["wish"], "log": ["runs", "drops"]}

SAMPLE = r'''
LOGQ = {
  { title = "Wailing Caverns", header = true },
  { title = "Leaders of the Fang", level = 22, objectives = { { text = "Gem of Cobrahn: 1/1", done = true }, { text = "Gem of Anacondra: 0/1", done = false }, { text = "Gem of Pythas: 0/1", done = false }, { text = "Gem of Serpentis: 0/1", done = false } } },
  { title = "The Barrens", header = true },
  { title = "Deviate Hides", level = 17, complete = true, objectives = { { text = "Deviate Hide: 20/20", done = true } } },
  { title = "Serpentbloom", level = 18, objectives = { { text = "Serpentbloom: 6/10", done = false } } },
}
function FakeLog()
  local out, zone = {}, nil
  for _, q in ipairs(LOGQ) do
    if q.header then zone = q.title else
      out[#out + 1] = { title = q.title, level = q.level, zone = zone, objectives = q.objectives, complete = q.complete }
    end
  end
  return out
end
local n = 2000
local function item(name, q, min, loc, sub, scid, lines)
  n = n + 1
  ITEMS[n] = { name, q, min + 5, min, "Armor", sub, loc, 4, scid, lines }
  return n
end
SAMPLES = {
  wc = {
    ["Lady Anacondra"] = { item("Sample Serpent Wraps", 2, 16, "INVTYPE_WRIST", "Cloth", 1, { "+4 Intellect", "+3 Spirit" }),
                           item("Sample Snakeskin Belt", 2, 17, "INVTYPE_WAIST", "Leather", 2, { "+5 Agility", "+2 Stamina" }) },
    ["Lord Cobrahn"] = { item("Sample Robe of the Fang", 3, 18, "INVTYPE_ROBE", "Cloth", 1, { "+8 Intellect", "+6 Spirit", "Equip: Increases healing done by spells and effects by up to 11." }),
                         item("Sample Leggings of the Fang", 3, 18, "INVTYPE_LEGS", "Leather", 2, { "+9 Agility", "+5 Stamina" }) },
    ["Kresh"] = { item("Sample Shell Shield", 3, 17, "INVTYPE_SHIELD", "Shields", 6, { "400 Armor", "+6 Stamina", "+4 Intellect" }) },
    ["Lord Serpentis"] = { item("Sample Savage Trodders", 3, 19, "INVTYPE_FEET", "Leather", 2, { "+7 Intellect", "+7 Spirit" }),
                           item("Sample Serpent Gloves", 3, 19, "INVTYPE_HAND", "Cloth", 1, { "+6 Intellect", "Equip: Restores 2 mana per 5 sec." }) },
    ["Mutanus the Devourer"] = { item("Sample Deep Fathom Ring", 3, 20, "INVTYPE_FINGER", "Miscellaneous", 0, { "+6 Intellect", "+3 Stamina", "Equip: Increases healing done by spells and effects by up to 9." }),
                                 item("Sample Slime Cowl", 3, 22, "INVTYPE_HEAD", "Cloth", 1, { "+9 Intellect", "+8 Spirit" }),
                                 item("Sample Mutant Scale Hauberk", 3, 23, "INVTYPE_CHEST", "Mail", 3, { "+10 Strength", "+8 Stamina" }) },
  },
}
WORN[1], WORN[5], WORN[11] = 1002, 1010, 1005
BAGS = { 1006 }
'''


def seed(lua, level):
    A, S, G = "HogHealsAtlas", "HogHealsAtlas.Store", "HogHealsAtlas.Gear"
    lua.execute(f"MockUnits.player.level = {level}")
    lua.execute(f"{A}.DungeonQuests.For = (function(f) return function(k, log) return f(k, log or FakeLog()) end end)({A}.DungeonQuests.For)")
    lua.execute(f"""
      local i = 0
      for boss, items in pairs(SAMPLES.wc) do
        for _, id in ipairs(items) do
          i = i + 1
          {S}.Record("wc", boss, id, (i % 3 == 0) and "seen" or "journal")
          if i % 3 == 0 then {S}.Record("wc", boss, id, "seen") end
        end
      end
      {G}.ToggleWish(SAMPLES.wc["Lord Cobrahn"][1])
      {G}.ToggleWish(SAMPLES.wc["Mutanus the Devourer"][1])
      {G}.NewSet("Healing, level 20", "equipped")
      {G}.SetItem(1, SAMPLES.wc["Lord Cobrahn"][1])
      {G}.SetItem(1, SAMPLES.wc["Lord Serpentis"][2])
      {G}.SetItem(1, SAMPLES.wc["Mutanus the Devourer"][1])
      {G}.NewSet("Later")
      INST = {{ name = "Wailing Caverns", id = 43 }}
      MockFire("PLAYER_ENTERING_WORLD")
      MockFire("ENCOUNTER_END", 1, "Kresh", 1, 5, 1)
      LOOT = {{ {{ link = ItemLink(SAMPLES.wc["Kresh"][1]), guid = NpcGUID(3653) }} }}
      MockFire("LOOT_OPENED", true)
      MockAdvance(40)
      MockFire("ENCOUNTER_END", 2, "Lord Serpentis", 1, 5, 1)
      MockFire("CHAT_MSG_LOOT", "Thrall receives loot: " .. ItemLink(SAMPLES.wc["Lord Serpentis"][1]) .. ".", "Thrall")
      INST = nil
      MockFire("ZONE_CHANGED_NEW_AREA")
    """)


class Painter:
    def __init__(self, lua, scale):
        self.lua, self.s = lua, scale
        self.font = self._font(11)
        self.bold = self._font(12, bold=True)

    def _font(self, size, bold=False):
        for name in (("arialbd.ttf" if bold else "arial.ttf"), "DejaVuSans.ttf"):
            try:
                return ImageFont.truetype(name, size * self.s)
            except OSError:
                continue
        return ImageFont.load_default()

    @staticmethod
    def rgb(c, default=(245, 235, 220)):
        if c is None:
            return default
        v = list(c.values())[:3]
        if len(v) < 3:
            return default
        return tuple(int(max(0, min(1, x)) * 255) for x in v)

    def box(self, frame, origin):
        """Absolute (x, y, w, h) of a frame anchored TOPLEFT/TOPRIGHT/... to its parent; enough for this window."""
        ox, oy, ow, oh = origin
        w, h = frame["_width"] or 0, frame["_height"] or 0
        pts = list(frame["_points"].values())
        if not pts:
            return ox, oy, w, h
        x0 = y0 = x1 = y1 = None
        for p in pts:
            p = list(p.values())
            point = p[0]
            dx = p[3] if len(p) > 3 and isinstance(p[3], (int, float)) else 0
            dy = p[4] if len(p) > 4 and isinstance(p[4], (int, float)) else 0
            if point == "ALL":
                return ox, oy, ow, oh
            rel = p[2] if len(p) > 2 and isinstance(p[2], str) else point
            ax = ox + (ow if "RIGHT" in rel else (ow / 2 if rel in ("TOP", "BOTTOM", "CENTER") else 0)) + dx
            ay = oy + (oh if "BOTTOM" in rel else (oh / 2 if rel in ("LEFT", "RIGHT", "CENTER") else 0)) - dy
            if "LEFT" in point:
                x0 = ax
            if "RIGHT" in point:
                x1 = ax
            if "TOP" in point:
                y0 = ay
            if "BOTTOM" in point:
                y1 = ay
            if point in ("LEFT", "RIGHT"):
                y0 = ay - h / 2
            if point in ("TOP", "BOTTOM"):
                x0 = ax - w / 2
        if x0 is None and x1 is not None:
            x0 = x1 - w
        if y0 is None and y1 is not None:
            y0 = y1 - h
        if x0 is None:
            x0 = ox
        if y0 is None:
            y0 = oy
        if x1 is not None and x0 is not None and x1 - x0 > 0 and ("LEFT" in "".join(list(p.values())[0] for p in pts)):
            w = x1 - x0
        if y1 is not None and y1 - y0 > 0 and any("TOP" in list(p.values())[0] for p in pts):
            h = y1 - y0
        return x0, y0, w, h

    def rect(self, d, b, fill, outline=None):
        x, y, w, h = b
        s = self.s
        d.rectangle([x * s, y * s, (x + w) * s - 1, (y + h) * s - 1], fill=fill, outline=outline)

    def text(self, d, x, y, t, fill, font=None, anchor="lm", max_w=None):
        font = font or self.font
        t = str(t).replace("|cffF5EBDC", "").replace("|cff21D4E0", "").replace("|r", "")
        if max_w is not None:
            while t and d.textlength(t, font=font) > max_w * self.s:
                t = t[:-2] + "." if len(t) > 2 else ""
                if len(t) <= 2:
                    break
        d.text((x * self.s, y * self.s), t, fill=fill, font=font, anchor=anchor)

    def button(self, d, b, origin):
        if not b["_shown"]:
            return
        bx = self.box(b, origin)
        self.rect(d, bx, (28, 28, 36))
        on = b["on"]
        self.text(d, bx[0] + bx[2] / 2, bx[1] + bx[3] / 2, b["label"]["_text"], (33, 212, 224) if on else (245, 235, 220), anchor="mm")

    def list(self, d, lst, origin):
        f = lst["frame"]
        bx = self.box(f, origin)
        self.rect(d, bx, (14, 14, 18), outline=(40, 40, 50))
        rh = lst["opts"]["rowHeight"]
        data = list(lst["data"].values())
        off = lst["offset"]
        for i in range(lst["opts"]["rows"]):
            if i + off >= len(data):
                break
            r = data[i + off]
            y = bx[1] + i * rh
            if r["selected"]:
                self.rect(d, (bx[0], y, bx[2], rh), (20, 52, 58))
            x = bx[0] + 6 + (r["indent"] or 0)
            if r["icon"] is not None:
                q = self.rgb(r["color"])
                self.rect(d, (bx[0] + 2 + (r["indent"] or 0), y + 1, rh - 2, rh - 2), tuple(int(c * 0.45) for c in q), outline=q)
                x += rh
            color = self.rgb(r["color"], (33, 212, 224) if r["header"] else (245, 235, 220))
            right = r["right"] or ""
            rw = d.textlength(str(right), font=self.font) / self.s if right else 0
            has_mid = lst["opts"]["midX"] and r["mid"] and not r["header"]
            limit = (bx[0] + lst["opts"]["midX"] - x - 8) if has_mid else (bx[0] + bx[2] - x - rw - 14)
            self.text(d, x, y + rh / 2, r["text"] or "", color, self.bold if r["header"] else self.font, max_w=limit)
            if right:
                self.text(d, bx[0] + bx[2] - 6, y + rh / 2, right, self.rgb(r["rightColor"], (140, 140, 153)), anchor="rm")
            mid_x = lst["opts"]["midX"]
            if mid_x and r["mid"] and not r["header"]:
                self.text(d, bx[0] + mid_x, y + rh / 2, r["mid"], self.rgb(r["midColor"], (140, 140, 153)),
                          max_w=bx[2] - mid_x - rw - 16)
        if not data and lst["emptyText"]:
            yy = bx[1] + 16
            for para in str(lst["emptyText"]).split("\n"):
                words, line = para.split(), ""
                for w in words + [None]:
                    if w is None or d.textlength(line + " " + w, font=self.font) > (bx[2] - 30) * self.s:
                        self.text(d, bx[0] + bx[2] / 2, yy, line, (140, 140, 153), anchor="mm")
                        yy += 15
                        line = w or ""
                    else:
                        line = (line + " " + w).strip()
                yy += 6
        if len(data) > lst["opts"]["rows"]:
            total = len(data)
            track = bx[3]
            th = max(12, track * lst["opts"]["rows"] / total)
            ty = bx[1] + (track - th) * off / max(1, total - lst["opts"]["rows"])
            self.rect(d, (bx[0] + bx[2] - 3, ty, 3, th), (33, 212, 224))

    def window(self, tab):
        lua = self.lua
        W = lua.eval("HogHealsAtlas.Window")
        f = W["frame"]
        fw, fh = f["_width"], f["_height"]
        m = 20
        img = Image.new("RGB", (int((fw + 2 * m) * self.s), int((fh + 2 * m) * self.s)), (36, 48, 40))
        d = ImageDraw.Draw(img)
        origin = (m, m, fw, fh)
        self.rect(d, origin, (18, 18, 23), outline=(51, 51, 64))
        self.rect(d, (m, m, fw, 26), (28, 28, 36))
        self.rect(d, (m, m + 25, fw, 1), (33, 212, 224))
        x = m + 10
        for part, col in (("HOG", (245, 235, 220)), ("UI", (33, 212, 224)), ("  ATLAS", (245, 235, 220))):
            self.text(d, x, m + 13, part, col, self.bold)
            x += d.textlength(part, font=self.bold) / self.s
        self.text(d, m + fw - 16, m + 13, "x", (245, 235, 220), anchor="mm")
        for b in W["tabButtons"].values():
            self.button(d, b, origin)
        pane = W["panes"][tab]
        pbox = self.box(pane, origin)
        for c in pane["_children"].values():
            if c["_kind"] == "Button" and c["label"] is not None:
                self.button(d, c, pbox)
        for name in LISTS[tab]:
            self.list(d, W["lists"][name], pbox)
        self.text(d, m + 10, m + fh - 14, f["status"]["_text"], (140, 140, 153), max_w=fw - 20)
        return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=int, default=2)
    ap.add_argument("--level", type=int, default=20)
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    lua = boot(AddonLoader().bootstrap(), extra=SAMPLE)
    seed(lua, args.level)
    p = Painter(lua, args.scale)
    W = "HogHealsAtlas.Window"
    shots = [
        ("dungeons-loot", "dungeons", f'{W}.dungeon = "wc"; {W}.boss = nil; {W}.detail = "loot"'),
        ("dungeons-quests", "dungeons", f'{W}.dungeon = "wc"; {W}.detail = "quests"'),
        ("dungeons-guide", "dungeons", f'{W}.dungeon = "wc"; {W}.detail = "guide"'),
        ("upgrades", "upgrades", ""),
        ("sets", "sets", f"{W}.setIndex = 1"),
        ("wishlist", "wish", ""),
        ("lootlog", "log", ""),
    ]
    lua.execute('HogHeals:SlashCommand("atlas")')
    for name, tab, prep in shots:
        if prep:
            lua.execute(prep)
        lua.execute(f'{W}.SetTab("{tab}")')
        img = p.window(tab)
        path = OUT / f"atlas-{name}.png"
        img.save(path)
        print("wrote", path.relative_to(ROOT))
    errs = [e["msg"] for e in lua.eval("HogHeals.errors").values()]
    print("addon errors:", errs or "none")
    return 1 if errs else 0


if __name__ == "__main__":
    raise SystemExit(main())
