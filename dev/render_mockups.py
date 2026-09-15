"""Render settings-UI mockups straight from the real AceConfig option tables.

Loads HogHeals + HogHeals_Frames into lupa, walks HogHeals.OptionsTable(), emits one HTML page per
tab (WoW-dark panel styling) and screenshots each with Playwright/Chromium. Also renders a frames
preview (party + raid with indicators) and the setup wizard.

Usage: python dev/render_mockups.py            -> docs/mockups/*.html + *.png
"""
from __future__ import annotations

import html
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
from loader import AddonLoader  # noqa: E402

OUT = ROOT / "docs" / "mockups"
OUT.mkdir(parents=True, exist_ok=True)

CSS = """
:root{--ink:#121217;--panel:#1b1b22;--panel2:#22222b;--line:#34343f;--cream:#F5EBDC;--cyan:#21D4E0;--muted:#9a9aa8;--amber:#F5A623;--red:#d93636;--green:#3fbf5a}
*{box-sizing:border-box}body{margin:0;background:#0b0b0e;font:13px/1.4 "Segoe UI",Arial,sans-serif;color:var(--cream)}
.win{width:1180px;margin:24px auto;background:var(--panel);border:1px solid var(--line);border-radius:6px;box-shadow:0 12px 40px #000c;overflow:hidden}
.title{display:flex;align-items:center;justify-content:space-between;padding:10px 16px;background:linear-gradient(#26262f,#1b1b22);border-bottom:1px solid var(--line)}
.title b{font-size:16px;letter-spacing:.5px}.title b .h{color:var(--cream)}.title b .t{color:var(--cyan)}
.title .x{color:var(--muted)}.tabs{display:flex;gap:2px;padding:8px 12px 0;background:var(--panel);border-bottom:1px solid var(--line)}
.tab{padding:7px 16px;border:1px solid var(--line);border-bottom:none;border-radius:5px 5px 0 0;background:#191920;color:var(--muted)}
.tab.on{background:var(--panel2);color:var(--cyan);border-color:var(--cyan);font-weight:600}
.body{display:flex;min-height:600px}.side{width:190px;background:#17171d;border-right:1px solid var(--line);padding:10px 0}
.side div{padding:8px 16px;color:var(--muted)}.side div.on{color:var(--cream);background:#22222b;border-left:3px solid var(--cyan)}
.main{flex:1;padding:16px 22px;display:grid;grid-template-columns:1fr 1fr;gap:10px 28px;align-content:start;background:var(--panel2)}
.full{grid-column:1/3}.w{display:flex;flex-direction:column;gap:4px}.w label{color:var(--muted);font-size:12px}
.w .desc{color:var(--cream);opacity:.85;white-space:pre-wrap}.hdr{grid-column:1/3;margin-top:8px;padding-bottom:4px;border-bottom:1px solid var(--line);color:var(--cyan);font-weight:600;letter-spacing:.3px}
.toggle{display:flex;align-items:center;gap:10px}.box{width:18px;height:18px;border:1px solid #666;border-radius:3px;background:#111}.box.on{background:var(--cyan);border-color:var(--cyan);box-shadow:inset 0 0 0 3px #111}
.range{display:flex;align-items:center;gap:10px}.track{flex:1;height:6px;background:#111;border:1px solid #444;border-radius:3px;position:relative}.knob{position:absolute;top:-6px;width:14px;height:16px;background:#c9c0b0;border-radius:3px;border:1px solid #777}
.val{min-width:44px;text-align:right;color:var(--cream)}.select,.input{background:#111;border:1px solid #555;border-radius:3px;padding:6px 8px;color:var(--cream)}
.select:after{content:" \\25BE";color:var(--muted);float:right}.btn{background:linear-gradient(#3a3a46,#2a2a34);border:1px solid #666;border-radius:3px;padding:7px 12px;text-align:center;color:var(--cream)}
.btn.primary{border-color:var(--cyan);color:var(--cyan)}.color{width:26px;height:18px;border:1px solid #777;border-radius:3px}
.multi{min-height:64px}.note{color:var(--muted);font-size:12px}
.foot{padding:8px 16px;border-top:1px solid var(--line);color:var(--muted);font-size:12px;display:flex;justify-content:space-between}
/* frames preview */
.stage{position:relative;height:640px;background:radial-gradient(ellipse at 50% 30%,#1a2430,#0a0c10 70%)}
.unit{position:absolute;background:#121217;border:1px solid #2a2a33;overflow:hidden}
.unit .hp{position:absolute;left:1px;top:1px;bottom:4px;background:#8a8a8a}.unit .hpbg{position:absolute;inset:1px 1px 4px 1px;background:#26262d}
.unit .mp{position:absolute;left:1px;right:1px;bottom:1px;height:3px;background:#2290f2}
.unit .nm{position:absolute;top:3px;left:0;right:0;text-align:center;font-size:11px;font-weight:600;text-shadow:0 0 3px #000,0 0 3px #000}
.unit .ht{position:absolute;bottom:5px;left:0;right:0;text-align:center;font-size:10px;text-shadow:0 0 3px #000}
.unit .pred{position:absolute;top:1px;bottom:4px;background:#3fbf5a80}.unit .aggro{position:absolute;inset:0;border:2px solid var(--red)}
.unit .dis{position:absolute;left:50%;top:50%;width:14px;height:14px;margin:-7px 0 0 -7px;border-radius:3px;background:#2a7de1;border:1px solid #fff}
.unit .mb{position:absolute;right:2px;top:2px;width:9px;height:9px;background:#e8d27a;border-radius:2px}.unit .sh{position:absolute;right:2px;bottom:5px;width:9px;height:9px;background:#fff;border-radius:50%}
.unit .st{position:absolute;left:2px;top:2px;width:10px;height:10px;background:#f2c94c;border-radius:50%}.unit .tick{position:absolute;top:1px;bottom:4px;width:1px;background:#F5EBDC99}
.unit .glow{position:absolute;inset:0;background:#21D4E040;border:1px solid #21D4E0}.legend{position:absolute;right:18px;top:16px;background:#121217dd;border:1px solid var(--line);border-radius:6px;padding:10px 14px;font-size:12px;color:var(--muted);line-height:1.7}
.legend b{color:var(--cream)}.tag{position:absolute;left:18px;top:16px;font-size:12px;color:var(--muted)}
"""

CLASS_COLORS = {"PRIEST": "#ffffff", "SHAMAN": "#0070de", "PALADIN": "#f48cba", "DRUID": "#ff7c0a", "MAGE": "#3fc7eb",
                "WARRIOR": "#c69b6d", "ROGUE": "#fff468", "HUNTER": "#aad372", "WARLOCK": "#8788ee"}


def lua_val(v):
    try:
        if hasattr(v, "items"):
            return dict(v.items())
    except Exception:
        pass
    return v


def call(fn, *args):
    try:
        return fn(*args)
    except Exception:
        return None


def widget_html(key, opt, get_ctx) -> str:
    kind = opt.get("type")
    name = opt.get("name")
    if not isinstance(name, str) and callable(name):
        name = call(name) or key
    name = html.escape(str(name))
    width_cls = " full" if opt.get("width") == "full" or kind in ("description", "header") else ""
    if kind == "header":
        return f'<div class="hdr">{name}</div>'
    if kind == "description":
        return f'<div class="w full"><div class="desc">{name}</div></div>'
    getter = opt.get("get")
    value = call(getter, get_ctx) if callable(getter) else None
    if kind == "toggle":
        on = "on" if value else ""
        return f'<div class="w{width_cls}"><div class="toggle"><span class="box {on}"></span><span>{name}</span></div></div>'
    if kind == "range":
        mn, mx = float(opt.get("min", 0)), float(opt.get("max", 1))
        v = float(value) if isinstance(value, (int, float)) else mn
        pct = 0 if mx == mn else max(0, min(1, (v - mn) / (mx - mn)))
        shown = f"{v:g}"
        return (f'<div class="w{width_cls}"><label>{name}</label><div class="range"><div class="track">'
                f'<div class="knob" style="left:calc({pct*100:.1f}% - 7px)"></div></div><span class="val">{shown}</span></div></div>')
    if kind == "select":
        values = opt.get("values")
        if not hasattr(values, "items") and callable(values):
            values = call(values)
        values = lua_val(values) or {}
        label = values.get(value, value) if isinstance(values, dict) else value
        return f'<div class="w{width_cls}"><label>{name}</label><div class="select">{html.escape(str(label if label is not None else "—"))}</div></div>'
    if kind == "input":
        v = "" if value is None else str(value)
        multi = " multi" if opt.get("multiline") else ""
        return f'<div class="w{width_cls}"><label>{name}</label><div class="input{multi}">{html.escape(v) or "&nbsp;"}</div></div>'
    if kind == "execute":
        return f'<div class="w{width_cls}"><label>&nbsp;</label><div class="btn">{name}</div></div>'
    if kind == "color":
        rgb = "#3fbf5a"
        return f'<div class="w{width_cls}"><label>{name}</label><div class="color" style="background:{rgb}"></div></div>'
    if kind == "group":
        inner = "".join(render_args(opt.get("args"), get_ctx))
        return f'<div class="hdr">{name}</div>{inner}'
    return f'<div class="w"><label>{name}</label><div class="note">({kind})</div></div>'


def render_args(args, get_ctx):
    items = []
    for key, opt in lua_val(args).items():
        opt = lua_val(opt)
        order = opt.get("order")
        if callable(order):
            order = 100
        items.append((float(order or 100), str(key), opt))
    items.sort(key=lambda x: (x[0], x[1]))
    return [widget_html(k, o, get_ctx) for _, k, o in items]


def page(title, tabs, active_tab, side, active_side, body, foot="/hh  ·  HogHeals 0.1.0  ·  mockup rendered from the live options table"):
    tabs_html = "".join(f'<div class="tab {"on" if t == active_tab else ""}">{html.escape(t)}</div>' for t in tabs)
    side_html = "".join(f'<div class="{"on" if s == active_side else ""}">{html.escape(s)}</div>' for s in side)
    return f"""<!doctype html><html><head><meta charset="utf-8"><title>{html.escape(title)}</title><style>{CSS}</style></head>
<body><div class="win"><div class="title"><b><span class="h">Hog</span><span class="t">Heals</span> &nbsp;<span style="color:var(--muted);font-weight:400">{html.escape(title)}</span></b><span class="x">✕</span></div>
<div class="tabs">{tabs_html}</div><div class="body"><div class="side">{side_html}</div><div class="main">{body}</div></div>
<div class="foot"><span>{foot}</span><span>Esc closes · changes apply live</span></div></div></body></html>"""


def frames_preview_html():
    # party of 5 (self+4) at 120x32 and a raid20 grid at 80x26, with indicators sprinkled
    def unit(x, y, w, h, name, cls, hp, extras=""):
        col = CLASS_COLORS.get(cls, "#888")
        pct = hp / 100
        pred = f'<div class="pred" style="left:{1+(w-2)*pct:.0f}px;width:{(w-2)*0.18:.0f}px"></div>' if "pred" in extras else ""
        return (f'<div class="unit" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px">'
                f'<div class="hpbg"></div><div class="hp" style="width:{(w-2)*pct:.0f}px;background:{col}"></div>{pred}<div class="mp"></div>'
                f'<div class="tick" style="left:{1+(w-2)*0.35:.0f}px"></div><div class="tick" style="left:{1+(w-2)*0.5:.0f}px"></div>'
                f'{"<div class=aggro></div>" if "aggro" in extras else ""}{"<div class=dis></div>" if "dis" in extras else ""}'
                f'{"<div class=mb></div>" if "mb" in extras else ""}{"<div class=sh></div>" if "sh" in extras else ""}'
                f'{"<div class=st></div>" if "st" in extras else ""}{"<div class=glow></div>" if "glow" in extras else ""}'
                f'<div class="nm" style="color:#F5EBDC">{name}</div><div class="ht">{"-"+str(100-hp) if hp<100 else ""}</div></div>')
    party = [("Hognificent", "PRIEST", 100, "sh"), ("Zugzug", "WARRIOR", 62, "aggro pred"), ("Brianna", "MAGE", 88, "mb"),
             ("Anthony", "ROGUE", 35, "dis pred"), ("Scoop", "HUNTER", 100, "st")]
    out = ['<div class="tag">Party layout 120×32 · hover = AoE-heal scope glow (Prayer of Healing)</div>']
    for i, (n, c, hp, ex) in enumerate(party):
        out.append(unit(40, 60 + i * 34, 120, 32, n, c, hp, ex + (" glow" if i in (1, 2, 3, 4, 0) else "")))
    out.append('<div class="tag" style="top:250px;left:40px">Raid-20 layout 80×26 · 4 groups · groups grow RIGHT, units DOWN</div>')
    names = ["Fable", "Penny", "Boar", "Tusk", "Mika", "Rune", "Vex", "Orla", "Dax", "Nyx", "Kor", "Ash", "Bel", "Cyn", "Dov", "Eir", "Fen", "Gil", "Hex", "Ivo"]
    classes = list(CLASS_COLORS)
    for g in range(4):
        for k in range(5):
            i = g * 5 + k
            hp = [100, 74, 41, 93, 58, 100, 22, 67, 100, 85, 49, 100, 77, 31, 100, 90, 64, 100, 55, 100][i]
            ex = {2: "dis", 6: "aggro pred", 13: "dis pred", 4: "mb", 10: "sh", 16: "st"}.get(i, "")
            out.append(unit(40 + g * 86, 290 + k * 28, 80, 26, names[i], classes[i % len(classes)], hp, ex))
    out.append('<div class="legend"><b>Indicators shown</b><br>▮ class-coloured health, missing-health text<br>'
               '▭ incoming heals overlay (mine/others/all)<br>│ threshold ticks at 35% / 50%<br>'
               '<span style="color:#d93636">▢</span> aggro border<br><span style="color:#2a7de1">■</span> dispellable-by-me (Magic) — icon / colour / border<br>'
               '<span style="color:#e8d27a">■</span> missing buff I can cast<br><span style="color:#fff">●</span> my PW:S + Weakened Soul timer<br>'
               '<span style="color:#f2c94c">●</span> status: ready-check / res / summon / leader<br>'
               '<span style="color:#21D4E0">▢</span> AoE-heal scope while hovering<br>faded frame = out of range / above 90% (optional)</div>')
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body><div class="win"><div class="title"><b><span class="h">Hog</span><span class="t">Heals</span> &nbsp;<span style="color:var(--muted);font-weight:400">Frames preview — /hh test 20</span></b><span class="x">✕</span></div><div class="stage">{''.join(out)}</div><div class="foot"><span>Mockup: what the frames look like in game with defaults</span><span>hover-binds: 1/2 Greater Heal · 3 Flash Heal · 4 Renew · F PW:S · Q Dispel · Shift-1 PoH</span></div></div></body></html>"""


def hud_strip_html():
    strip = (
        '<div class="tag">HUD strip 300px · centred, y −180 · castbar / mana+FSR / info line</div>'
        '<div style="position:absolute;left:460px;top:250px;width:300px">'
        '  <div style="position:relative;height:18px;background:#121217;border:1px solid #2a2a33">'
        '    <div style="position:absolute;left:-22px;top:0;width:18px;height:18px;background:#3b6fb6;border:1px solid #888"></div>'
        '    <div style="position:absolute;left:0;top:0;bottom:0;width:58%;background:#21D4E0"></div>'
        '    <div style="position:absolute;right:0;top:0;bottom:0;width:10%;background:#d9363699"></div>'
        '    <div style="position:absolute;left:58%;top:-3px;width:3px;height:24px;background:#fff;box-shadow:0 0 6px #fff"></div>'
        '    <div style="position:absolute;left:5px;top:2px;font-size:11px;font-weight:600;text-shadow:0 0 3px #000">Greater Heal → Zugzug</div>'
        '    <div style="position:absolute;right:5px;top:2px;font-size:11px;text-shadow:0 0 3px #000">1.1</div>'
        '  </div>'
        '  <div style="position:relative;height:12px;margin-top:2px;background:#121217;border:1px solid #2a2a33">'
        '    <div style="position:absolute;left:0;top:0;bottom:0;width:72%;background:#2290f2"></div>'
        '    <div style="position:absolute;left:0;top:0;bottom:0;width:38%;background:#21D4E059"></div>'
        '    <div style="position:absolute;left:4px;top:-1px;font-size:9px;color:#F5EBDC">3.2</div>'
        '    <div style="position:absolute;left:50%;top:0;font-size:9px;transform:translateX(-50%);text-shadow:0 0 3px #000">4 320 / 6 000</div>'
        '  </div>'
        '  <div style="position:relative;height:14px;margin-top:2px;font-size:11px">'
        '    <span style="position:absolute;left:2px;color:#F5A623">OOM 1:42 · 2:15 · at 5:00: 31%</span>'
        '    <span style="position:absolute;right:2px;color:#F5EBDC">GH r3 (1.4k) · FH r6 (1.1k)</span>'
        '  </div>'
        '</div>'
        '<div class="legend"><b>HUD rows</b><br>▮ castbar: icon, name → target, remaining time<br>'
        '<span style="color:#d93636">▮</span> latency segment (world ms) at the end<br>│ spark at the fill edge<br>'
        '▮ mana bar with current / max text<br><span style="color:#21D4E0">▮</span> five-second-rule drain overlay + countdown<br>'
        '│ regen tick spark every 2 s after the window<br><span style="color:#F5A623">OOM 1:42</span> time-to-OOM (amber &lt; 60 s, red &lt; 20 s) · fight timer · projected mana at target length<br>'
        'GH r3 / FH r6 = lowest rank covering the hovered unit&#39;s missing health</div>'
    )
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body><div class="win"><div class="title"><b><span class="h">Hog</span><span class="t">Heals</span> &nbsp;<span style="color:var(--muted);font-weight:400">HUD strip preview</span></b><span class="x">✕</span></div><div class="stage">{strip}</div><div class="foot"><span>Mockup: the HUD under the character while healing</span><span>/hh unlock to drag · replaces Quartz + FiveSecondRule</span></div></div></body></html>"""


def wizard_html():
    body = ('<div class="hdr">HogHeals setup — three quick choices</div>'
            '<div class="w full"><div class="desc">You can change everything later in /hh. Takes under a minute.</div></div>'
            '<div class="w full"><label>1 · Your class</label><div class="select">Priest (detected)</div></div>'
            '<div class="w full"><label>2 · Layout preset</label><div class="select">Default — Balanced sizes for party and raid</div>'
            '<div class="note">Compact · Large · Accessibility (very large frames, big text, mouse-only bindings, fewer indicators)</div></div>'
            '<div class="w full"><label>3 · Bindings</label><div class="select">Class defaults (keyboard hover-binds)</div>'
            '<div class="note">Mouse-only (HealBot style) · None — I use my own macros / Clique</div></div>'
            '<div class="w full"><div class="desc">Priest defaults: 1/2 Greater Heal · 3 Flash Heal · 4 Renew · F Power Word: Shield · Q Dispel Magic · Shift-1 Prayer of Healing · Ctrl-2 Fortitude · Ctrl-4 Divine Spirit</div></div>'
            '<div class="w"><label>&nbsp;</label><div class="btn primary">Finish</div></div><div class="w"><label>&nbsp;</label><div class="btn">Preview (/hh test 10)</div></div>')
    return page("Setup wizard (first login)", ["Wizard"], "Wizard", ["Class", "Layout", "Bindings", "Done"], "Layout", body,
                foot="Auto-runs once on first login · re-run any time with /hh wizard")


def main() -> int:
    l = AddonLoader().bootstrap()
    l.load_addon("HogHeals")
    l.load_addon("HogHeals_Frames")
    l.load_addon("HogHeals_HUD")
    l.player_login()
    # give the mock a realistic bucket so "Editing layout for group size" reads sensibly
    l.execute('MockSetGroup(5, false); MockFire("GROUP_ROSTER_UPDATE")')
    root = lua_val(l.eval("HogHeals.OptionsTable()"))
    tabs = []
    args = lua_val(root["args"])
    ctx = l.lua.table()
    pages: list[tuple[str, str]] = []
    # General
    tabs = ["General", "Frames", "HUD"]
    general = lua_val(args["general"])
    pages.append(("01-general", page("General", tabs, "General", ["General"], "General", "".join(render_args(general["args"], ctx)))))
    frames_tab = lua_val(args["Frames"])
    subs = lua_val(frames_tab["args"])
    order = ["layout", "appearance", "indicators", "bindings", "profiles"]
    side_labels = {"layout": "Layout", "appearance": "Appearance", "indicators": "Indicators", "bindings": "Bindings", "profiles": "Profiles"}
    for i, key in enumerate(order, start=2):
        sub = lua_val(subs[key])
        body = "".join(render_args(sub["args"], ctx))
        pages.append((f"{i:02d}-frames-{key}", page(f"Frames › {side_labels[key]}", tabs, "Frames", [side_labels[k] for k in order], side_labels[key], body)))
    pages.append(("07-wizard", wizard_html()))
    pages.append(("08-frames-preview", frames_preview_html()))
    hud_tab = lua_val(args.get("HUD"))
    if hud_tab:
        hsubs = lua_val(hud_tab["args"])
        horder = ["layout", "castbar", "mana", "pacing", "advisor"]
        hlabels = {"layout": "Layout", "castbar": "Castbar", "mana": "Mana & five-second rule", "pacing": "Mana pacing", "advisor": "Rank advisor"}
        for i, key in enumerate(horder, start=9):
            sub = lua_val(hsubs[key])
            body = "".join(render_args(sub["args"], ctx))
            pages.append((f"{i:02d}-hud-{key}", page(f"HUD › {hlabels[key]}", tabs, "HUD", [hlabels[k] for k in horder], hlabels[key], body)))
        pages.append(("14-hud-strip", hud_strip_html()))

    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width": 1240, "height": 900}, device_scale_factor=1)
        for name, content in pages:
            (OUT / f"{name}.html").write_text(content, encoding="utf-8")
            pg.set_content(content)
            pg.screenshot(path=str(OUT / f"{name}.png"), full_page=True)
            print("rendered", name)
        b.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
