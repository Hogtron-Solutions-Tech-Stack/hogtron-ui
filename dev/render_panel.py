"""Render a PREVIEW of the HogHeals options panel (HogHeals/Core/Panel.lua) to docs/mockups/panel-*.png.

Not a screenshot of WoW. The panel code runs for real inside the test harness (lupa + tests/wow_mock.lua) against
the live options table; this script reads back the geometry the code actually set (row offsets, widths, heights,
labels, values) and draws it with matching colours. Fonts and pixel snapping will differ in the client.

    python dev/render_panel.py            # writes docs/mockups/panel-<page>.png
"""
from __future__ import annotations

import html
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
from loader import AddonLoader  # noqa: E402

OUT = ROOT / "docs" / "mockups"
W, H, SIDEBAR, TITLE, PAD = 860, 580, 170, 40, 16

CSS = """
*{box-sizing:border-box;margin:0;padding:0}
body{background:#2a1a12;padding:30px;font-family:'Friz Quadrata Std','Trebuchet MS',Verdana,sans-serif;font-size:11px;color:#F5EBDC}
.win{position:relative;width:860px;height:580px;background:rgba(18,18,23,.97);border:1px solid #333340;overflow:hidden}
.bar{position:absolute;left:1px;top:1px;right:1px;height:40px;background:#1c1c24;border-bottom:2px solid #21D4E0;display:flex;align-items:center;padding-left:16px}
.hog{font-size:17px;color:#F5EBDC;letter-spacing:.5px}.heals{font-size:17px;color:#21D4E0;letter-spacing:.5px}
.ver{color:#737380;margin-left:10px}.x{position:absolute;right:8px;top:8px;width:24px;height:24px;border:1px solid #333340;background:#1c1c24;text-align:center;line-height:22px}
.side{position:absolute;left:1px;top:43px;bottom:1px;width:170px;background:#17171d}
.nav{position:absolute;left:0;right:0;height:30px;line-height:30px;padding-left:16px;font-size:12px}
.nav.on{background:rgba(33,212,224,.12);border-left:3px solid #21D4E0;color:#21D4E0;padding-left:13px}
.tabs{position:absolute;left:187px;top:53px;right:16px;height:28px}
.tab{position:absolute;bottom:0;height:26px;line-height:25px;text-align:center;color:#737380}
.tab.on{color:#21D4E0;border-bottom:2px solid #21D4E0}
.view{position:absolute;left:187px;top:91px;right:16px;bottom:16px;overflow:hidden}
.row{position:absolute}
.lbl{position:absolute;left:0;top:2px}.val{position:absolute;right:0;top:2px;color:#21D4E0}
.track{position:absolute;left:0;right:0;top:25px;height:4px;background:#333340}.thumb{position:absolute;top:20px;width:8px;height:14px;background:#21D4E0}
.box{position:absolute;left:0;top:5px;width:16px;height:16px;background:#1c1c24;border:1px solid #333340}.tick{position:absolute;left:3px;top:3px;right:3px;bottom:3px;background:#21D4E0}
.tlbl{position:absolute;left:24px;top:6px}
.btn{position:absolute;left:0;right:0;height:24px;top:2px;background:#1c1c24;border:1px solid #333340;text-align:center;line-height:22px}
.sel{position:absolute;left:0;right:0;top:18px;height:22px;background:#1c1c24;border:1px solid #333340;line-height:20px;padding:0 8px}.sel i{float:right;color:#21D4E0;font-style:normal}
.well{position:absolute;left:0;right:0;top:18px;bottom:6px;background:#0d0d11;border:1px solid #333340;padding:4px 6px;white-space:pre-wrap;overflow:hidden}
.hdr{position:absolute;left:0;right:0;bottom:0;border-bottom:1px solid #333340;color:#21D4E0;padding-bottom:6px;letter-spacing:.6px}
.desc{color:#c7bfb3;line-height:1.35}
.sw{position:absolute;left:0;top:5px;width:28px;height:16px;border:1px solid #333340}
.off{opacity:.4}
.note{margin-top:10px;color:#9a8f85;font-size:10px}
"""


def e(s) -> str:
    import re
    s = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", str(s if s is not None else ""))   # WoW colour markup renders in game, not in HTML
    return html.escape(s)


def rows(lua) -> list[dict]:
    out = []
    keys = list(lua.eval('(function() local t = {} for k in pairs(HogHeals.Panel.controls) do t[#t + 1] = k end return t end)()').values())
    for k in keys:
        r = f'HogHeals.Panel.controls["{k}"]'
        pt = lua.eval(f'{{ {r}:GetPoint(1) }}')
        p = list(pt.values())
        d = {"key": k, "kind": lua.eval(f'{r}.kind'), "x": p[3] if len(p) > 3 else 0, "y": -(p[4] if len(p) > 4 else 0),
             "w": lua.eval(f'{r}:GetWidth()') or 0, "h": lua.eval(f'{r}:GetHeight()') or 26,
             "alpha": lua.eval(f'{r}._alpha')}
        kind = d["kind"]
        if kind in ("toggle", "range", "select", "input", "color"):
            d["label"] = lua.eval(f'{r}.label._text')
        if kind == "toggle":
            d["checked"] = lua.eval(f'{r}.checked')
        elif kind == "range":
            d["value"] = lua.eval(f'{r}.valueText._text')
            d["min"], d["max"], d["cur"] = lua.eval(f'{r}.slider._min'), lua.eval(f'{r}.slider._max'), lua.eval(f'{r}.slider._value')
        elif kind == "select":
            d["value"] = lua.eval(f'{r}.button.label._text')
        elif kind == "execute":
            d["label"] = lua.eval(f'{r}.button.label._text')
        elif kind == "input":
            d["value"] = lua.eval(f'{r}.edit._text')
        elif kind in ("header", "description"):
            d["label"] = lua.eval(f'{r}.text._text')
        elif kind == "color":
            c = list(lua.eval(f'{{ {r}.swatch._color and unpack({r}.swatch._color) }}').values()) if lua.eval(f'{r}.swatch._color ~= nil') else []
            d["rgb"] = c
        out.append(d)
    return sorted(out, key=lambda d: (d["y"], d["x"]))


def row_html(d: dict) -> str:
    k = d["kind"]
    inner = ""
    if k == "toggle":
        inner = f'<div class="box">{"<div class=tick></div>" if d.get("checked") else ""}</div><div class="tlbl">{e(d["label"])}</div>'
    elif k == "range":
        lo, hi, cur = d.get("min") or 0, d.get("max") or 1, d.get("cur") or 0
        frac = 0 if hi == lo else max(0, min(1, (cur - lo) / (hi - lo)))
        inner = f'<div class="lbl">{e(d["label"])}</div><div class="val">{e(d["value"])}</div><div class="track"></div><div class="thumb" style="left:calc({frac * 100:.1f}% - {frac * 8:.1f}px)"></div>'
    elif k == "select":
        inner = f'<div class="lbl">{e(d["label"])}</div><div class="sel">{e(d["value"])}<i>v</i></div>'
    elif k == "execute":
        inner = f'<div class="btn">{e(d["label"])}</div>'
    elif k == "input":
        inner = f'<div class="lbl">{e(d["label"])}</div><div class="well">{e(d["value"])}</div>'
    elif k == "header":
        inner = f'<div class="hdr">{e(d["label"])}</div>'
    elif k == "description":
        inner = f'<div class="desc">{e(d["label"])}</div>'
    elif k == "color":
        inner = f'<div class="sw" style="background:#21D4E0"></div><div class="tlbl" style="left:36px">{e(d["label"])}</div>'
    off = " off" if (d.get("alpha") or 1) < 1 else ""
    return f'<div class="row{off}" style="left:{d["x"]}px;top:{d["y"]}px;width:{d["w"]}px;height:{d["h"]}px">{inner}</div>'


def page(lua, note: str) -> str:
    n = lua.eval('#HogHeals.Panel.nav')
    sel = lua.eval('HogHeals.Panel.selected')
    nav = ""
    for i in range(1, n + 1):
        key, label = lua.eval(f'HogHeals.Panel.nav[{i}].key'), lua.eval(f'HogHeals.Panel.nav[{i}].label._text')
        nav += f'<div class="nav{" on" if key == sel else ""}" style="top:{10 + (i - 1) * 32}px">{e(label)}</div>'
    tabs, x = "", 0
    tsel = lua.eval('HogHeals.Panel.selectedTab')
    for i in range(1, (lua.eval('#HogHeals.Panel.tabs') or 0) + 1):
        key, label = lua.eval(f'HogHeals.Panel.tabs[{i}].key'), lua.eval(f'HogHeals.Panel.tabs[{i}].label._text')
        w = lua.eval(f'HogHeals.Panel.tabs[{i}]:GetWidth()') or 80
        tabs += f'<div class="tab{" on" if key == tsel else ""}" style="left:{x}px;width:{w}px">{e(label)}</div>'
        x += w + 4
    body = "".join(row_html(d) for d in rows(lua))
    ver = lua.eval('HogHeals.version')
    return (f'<!doctype html><meta charset="utf-8"><style>{CSS}</style><div class="win">'
            f'<div class="bar"><span class="hog">HOG</span><span class="heals">HEALS</span><span class="ver">v{e(ver)}</span><div class="x">x</div></div>'
            f'<div class="side">{nav}</div><div class="tabs">{tabs}</div><div class="view">{body}</div></div>'
            f'<div class="note">{e(note)}</div>')


def main() -> int:
    lua = AddonLoader().bootstrap()
    for a in ("HogHeals", "HogHeals_Frames", "HogHeals_HUD"):
        lua.load_addon(a)
    lua.player_login()
    lua.execute('HogHeals.Panel.Open()')
    OUT.mkdir(parents=True, exist_ok=True)
    pages = []
    n = lua.eval('#HogHeals.Panel.nav')
    for i in range(1, n + 1):
        key = lua.eval(f'HogHeals.Panel.nav[{i}].key')
        lua.execute(f'HogHeals.Panel.Select("{key}")')
        tabs = lua.eval('#HogHeals.Panel.tabs') or 0
        if tabs == 0:
            pages.append((f"panel-{key}".lower(), page(lua, "PREVIEW rendered from the panel code's real layout in the test harness. Not a WoW screenshot: fonts differ in game.")))
        for t in range(1, tabs + 1):
            tkey = lua.eval(f'HogHeals.Panel.tabs[{t}].key')
            lua.execute(f'HogHeals.Panel.SelectTab("{tkey}")')
            pages.append((f"panel-{key}-{tkey}".lower(), page(lua, "PREVIEW rendered from the panel code's real layout in the test harness. Not a WoW screenshot: fonts differ in game.")))
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width": 940, "height": 680})
        for name, doc in pages:
            pg.set_content(doc)
            pg.screenshot(path=str(OUT / f"{name}.png"), full_page=True)
            print("wrote", OUT / f"{name}.png")
        b.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
