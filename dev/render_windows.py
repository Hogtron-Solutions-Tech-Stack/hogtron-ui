"""Render PREVIEWS of a Blizzard window in the HogTron window skin (HogTron_Skin/Panels.lua, skin.panels.look) to
docs/mockups/windows-<look>.png. Not screenshots of WoW: the test harness's modern-template window (NineSlice border,
portrait, title, inset, close, tab strip) gets a Friends-list body (gold headers, white / class-coloured / grey names,
a Blizzard button), is shown through ShowUIPanel, the real skin runs in the harness, and render_dialog.py's Painter
composites what it drew (our page art, text in Friz Quadrata when a local copy exists).

    python -P dev/render_windows.py [--scale 2]
"""
from __future__ import annotations

import argparse
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
sys.path.insert(0, str(ROOT / "dev"))
from loader import AddonLoader  # noqa: E402
from render_dialog import LAYERS, Painter, WORLD, vals  # noqa: E402
from test_skin_windows import WINDOW  # noqa: E402

OUT = ROOT / "docs" / "mockups"

SCENE = '''
local f = FriendsFrame
f:SetSize(520, 400) f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
f.TitleContainer.TitleText:SetText("Friends") f.TitleContainer.TitleText:SetPoint("TOP", f, "TOP", 0, -9)
f.CloseButton:SetSize(26, 26) f.CloseButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -6)
for i, label in ipairs({ "Friends", "Who", "Raid" }) do
  local t = _G["FriendsFrameTab" .. i]
  t:SetSize(84, 24) t:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 16 + (i - 1) * 90, 2)
  t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormal") t.text:SetPoint("CENTER", t, "CENTER", 0, 0)
  t.text:SetText(label) if i == 1 then t.text:SetTextColor(1, 1, 1) else t.text:SetTextColor(1, 0.82, 0) end
end
local rows = { { "ONLINE - 5", 1, 0.82, 0 }, { "Jackpot Baby - Fear Not When", 0.25, 0.78, 0.92 }, { "Berdon Bloodskalp", 1, 0.96, 0.41 },
  { "Sandy Mellow", 1, 1, 1 }, { "Raekwon Ragefist", 0.78, 0.61, 0.43 }, { "Magic Melons", 0.41, 0.8, 0.94 },
  { "OFFLINE - 2", 1, 0.82, 0 }, { "Chootem Clayjon", 0.5, 0.5, 0.5 }, { "Locks Mo", 0.5, 0.5, 0.5 } }
f.List = CreateFrame("Frame", nil, f)
for i, r in ipairs(rows) do
  local s = f.List:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  s:SetPoint("TOPLEFT", f, "TOPLEFT", r[1]:find("^%u+ %-") and 26 or 40, -62 - (i - 1) * 26)
  s:SetText(r[1]) s:SetTextColor(r[2], r[3], r[4])
end
local b = CreateFrame("Button", "FriendsFrameAddFriendButton", f)
b:SetSize(110, 24) b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 16)
b.art = b:CreateTexture(nil, "BACKGROUND") b.art:SetAllPoints(b) b.art:SetColorTexture(0.38, 0.12, 0.08, 1)
b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal") b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
b.label:SetText("Add Friend") b.label:SetTextColor(1, 0.82, 0)
ShowUIPanel(f) MockAdvance(1)
'''

POPUP = r'''
local f = CreateFrame("Frame", "StaticPopup1", UIParent)
f:SetSize(320, 96) f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
f.BG = CreateFrame("Frame", nil, f) f.BG:SetAllPoints(f)
f.BG.Bottom = f.BG:CreateTexture(nil, "BACKGROUND") f.BG.Bottom:SetAllPoints(f.BG) f.BG.Bottom:SetColorTexture(0.12, 0.11, 0.10, 0.95)
f.BG.Top = f.BG:CreateTexture(nil, "BORDER") f.BG.Top:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0) f.BG.Top:SetSize(320, 3) f.BG.Top:SetColorTexture(0.6, 0.45, 0.2, 1)
local msg = f:CreateFontString("StaticPopup1Text", "OVERLAY", "GameFontHighlight") msg:SetPoint("TOP", f, "TOP", 0, -18)
msg:SetText("15 Seconds until exit") msg:SetTextColor(1, 0.82, 0)
for i, label in ipairs({ "Exit now", "Cancel" }) do
  local b = CreateFrame("Button", "StaticPopup1Button" .. i, f) b:SetSize(130, 24) b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20 + (i - 1) * 150, 16)
  b.art = b:CreateTexture(nil, "BACKGROUND") b.art:SetAllPoints(b) b.art:SetColorTexture(0.45, 0.06, 0.04, 1)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal") b.label:SetPoint("CENTER", b, "CENTER", 0, 0) b.label:SetText(label) b.label:SetTextColor(1, 0.82, 0)
end
f:Hide() ShowUIPanel(f) MockAdvance(1)
'''


class WindowPainter(Painter):
    """Two-point anchors (TOPLEFT + BOTTOMRIGHT, SetAllPoints), solid colour textures, and our backing drawn first."""

    def rect(self, r):
        key = self.ident(r)
        if key in self.rects:
            return self.rects[key]
        pts = [vals(p) for p in vals(r["_points"]) if p is not None]
        if pts and pts[0][0] == "ALL":
            out = self.rect(pts[0][1]) if pts[0][1] is not None else self.root
            self.rects[key] = out
            return out
        if len(pts) >= 2:
            xs, ys = {}, {}
            for p in pts:
                point, rel, relp, x, y = (p + [None] * 5)[:5]
                base = self.rect(rel) if rel is not None else self.root
                ax, ay = self.at(base, relp or point)
                ax, ay = ax + (x or 0), ay - (y or 0)
                if "LEFT" in point: xs["l"] = ax
                elif "RIGHT" in point: xs["r"] = ax
                if "TOP" in point: ys["t"] = ay
                elif "BOTTOM" in point: ys["b"] = ay
            w = xs["r"] - xs["l"] if "l" in xs and "r" in xs else (r["_width"] or 0)
            h = ys["b"] - ys["t"] if "t" in ys and "b" in ys else (r["_height"] or 0)
            out = (xs.get("l", xs.get("r", self.root[0]) - w), ys.get("t", ys.get("b", self.root[1]) - h), w, h)
            self.rects[key] = out
            return out
        return super().rect(r)

    def texture(self, img, r):
        c = vals(r["_color"])
        if r["_texture"] is None and len(c) >= 3:
            l, t, w, h = self.rect(r)
            if w > 0 and h > 0:
                a = int((c[3] if len(c) > 3 else 1) * (r["_alpha"] if r["_alpha"] is not None else 1) * 255)
                ov = Image.new("RGBA", (int(w * self.s), int(h * self.s)), (int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), a))
                img.alpha_composite(ov, (int(l * self.s), int(t * self.s)))
            return
        super().texture(img, r)

    def walk(self, img, frame):
        if not frame["_shown"] or (frame["_alpha"] is not None and frame["_alpha"] <= 0):
            return
        kids = vals(frame["_children"])
        # our backing (the page, one frame level under the window in game) is painted before the window's own regions
        backing = [c for c in kids if c["_kind"] not in ("Texture", "FontString") and c["hhOurs"]]
        for c in backing:
            self.walk(img, c)
        kids = [c for c in kids if not any(c is b for b in backing)]
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

    def paint(self, name="FriendsFrame"):
        f = self.lua.eval(name)
        m = 40
        fw, fh = f["_width"], f["_height"]
        self.root = (m, m, fw, fh)
        self.rects = {self.ident(f): self.root}
        self.portrait_id = None
        img = Image.new("RGBA", (int((fw + 2 * m) * self.s), int((fh + 2 * m + 30) * self.s)), WORLD + (255,))
        self.walk(img, f)
        return img.convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=int, default=2)
    s = ap.parse_args().scale
    OUT.mkdir(parents=True, exist_ok=True)
    errs = []
    for look, theme in (("light", "light"), ("dark", "dark"), ("ink", None)):
        lua = AddonLoader().bootstrap()
        lua.execute(WINDOW)
        if theme:
            lua.execute(f'HogTronUIDB = {{ profiles = {{ Default = {{ quests = {{ dialog = {{ theme = "{theme}" }} }} }} }} }}')
        else:
            lua.execute('HogTronUIDB = { profiles = { Default = { skin = { panels = { look = "ink" } } } } }')
        for a in ("HogTronUI", "HogTron_Skin"):
            lua.load_addon(a)
        lua.player_login()
        lua.execute(SCENE)
        img = WindowPainter(lua, s).paint()
        path = OUT / f"windows-{look}.png"
        img.save(path)
        print("wrote", path.relative_to(ROOT), img.size)
        lua.execute(POPUP)                                  # the exit popup, as the client reported it (StaticPopup1.BG)
        img = WindowPainter(lua, s).paint("StaticPopup1")
        path = OUT / f"windows-popup-{look}.png"
        img.save(path)
        print("wrote", path.relative_to(ROOT), img.size)
        errs += [e["msg"] for e in lua.eval("HogHeals.errors").values()]
    print("addon errors:", errs or "none")
    return 1 if errs else 0


if __name__ == "__main__":
    raise SystemExit(main())
