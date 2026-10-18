"""Render the Click-cast tab (HogHeals_Frames/ClickGrid.lua) in six states to docs/mockups/binding-ui/*.png.

Same pipeline as dev/render_mockups.py: the addon runs for real in the test harness (lupa + tests/wow_mock.lua),
the page is walked from the LIVE options table (HogHeals.OptionsTable() -> Frames -> clickcast), and the grid,
picker, rank menu and editor are drawn from ClickGrid.ViewModel() - the same data the in-game widget draws.
Each state is reached by calling the real ClickGrid actions (Pick / OpenPicker / OpenRankMenu / Select), with a
mocked level-60 spellbook (tests/spellbooks.py). Not a WoW screenshot: fonts differ in game.

Spell icons: the icon PATH comes from the addon's own spellbook scan (GetSpellTexture, as in game); the picture for
that path is fetched once from Wowhead's icon CDN into .scratch-icons/ (gitignored) and drawn into the PNG, the way
a screenshot shows it; the saved .html links the CDN instead of embedding the art. Offline / unknown icon -> lettered tile.

    python dev/render_binding_ui.py
"""
from __future__ import annotations

import base64
import hashlib
import urllib.request
import html
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
sys.path.insert(0, str(ROOT / "dev"))
from loader import AddonLoader  # noqa: E402
from spellbooks import boot  # noqa: E402
import render_mockups as rm  # noqa: E402

OUT = ROOT / "docs" / "mockups" / "binding-ui"

CSS = """
.cc{grid-column:1/3;position:relative}
.toast{grid-column:1/3;background:#121217;border:1px solid var(--cyan);border-radius:4px;padding:7px 12px;color:var(--cream)}
.toast b{color:var(--cyan)}
.clique{grid-column:1/3;color:var(--amber);font-weight:600;font-size:14px;padding:6px 0}
.g{display:grid;grid-template-columns:86px repeat(5,1fr);gap:5px;align-items:stretch}
.g .ch{color:var(--cyan);text-align:center;font-weight:600;font-size:12px;padding:2px 0}
.g .rh{color:var(--cream);font-size:12px;display:flex;align-items:center}
.cell{position:relative;height:46px;background:#1c1c24;border:1px solid #34343f;border-radius:3px;display:flex;align-items:center;gap:7px;padding:0 6px;overflow:hidden}
.cell.sel{border-color:var(--cyan);box-shadow:0 0 0 1px var(--cyan)}
.cell.off{opacity:.42}.cell.empty .fb{color:#737380;font-size:11px}
img.ico,img.mi{object-fit:cover;padding:0}.ico{flex:none;width:32px;height:32px;border-radius:3px;border:1px solid #000;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:12px;color:#fff;text-shadow:0 0 3px #000}
.cn{display:flex;flex-direction:column;min-width:0}.cn .n{font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.cn .r{font-size:10.5px;color:var(--muted)}.rz{position:absolute;right:4px;top:2px;font-size:10px;color:var(--cyan)}
.dim .g{opacity:.42}
.ed{margin-top:8px;background:#0d0d11;border:1px solid #34343f;border-radius:4px;padding:10px 12px;position:relative}
.ed .t{color:var(--cyan);font-weight:600}.ed .row{display:flex;gap:26px;align-items:flex-end;margin-top:8px}
.ed label{display:block;color:var(--muted);font-size:12px;margin-bottom:4px}
.ed .dd{width:250px;background:#111;border:1px solid #555;border-radius:3px;padding:6px 8px}.ed .dd:after{content:" \\25BE";float:right;color:var(--cyan)}
.ed .dd.open{border-color:var(--cyan)}
.ed .chk{display:flex;gap:9px;align-items:center;padding-bottom:6px}.ed .mac{margin-top:9px;color:#9a9aa8;font-family:Consolas,monospace;font-size:11.5px}
.ed .btns{position:absolute;right:12px;top:8px;display:flex;gap:6px}.ed .btns span{background:linear-gradient(#3a3a46,#2a2a34);border:1px solid #666;border-radius:3px;padding:4px 10px;font-size:12px}
.pop{position:absolute;z-index:5;background:#1c1c24;border:1px solid var(--cyan);border-radius:3px;box-shadow:0 8px 24px #000c;min-width:270px}
.pop .pt{color:var(--cyan);font-weight:600;font-size:12px;padding:6px 9px 4px}
.pop .it{display:flex;align-items:center;gap:8px;height:22px;padding:0 9px;font-size:12px}
.pop .it.cur{color:var(--cyan)}.pop .it.hov{background:#21D4E02e}.pop .it .s{margin-left:auto;color:var(--muted);font-size:11px}
.pop .it .mi{width:16px;height:16px;border-radius:2px;font-size:8px;display:flex;align-items:center;justify-content:center;color:#fff}
.pop .more{color:var(--muted);font-size:11px;padding:3px 9px 6px}
.cap{grid-column:1/3;color:var(--muted);font-size:12px;border-top:1px dashed #34343f;padding-top:8px;margin-top:4px}
"""

PALETTE = ["#3b6fb6", "#b88a2e", "#2e8a6a", "#8a3bb6", "#b63b4e", "#3b9ab6", "#6a8a2e", "#b65f3b"]


def lv(v):
    return rm.lua_val(v)


def lst(v):
    return [] if v is None else list(lv(v).values())


ICON_CACHE = ROOT / ".scratch-icons"
ICON_CDN = "https://wow.zamimg.com/images/wow/icons/large/{}.jpg"
ICON_URLS: dict[str, str] = {}   # data URI -> CDN url, so the committed .html links the art instead of embedding it


def icon_data(path: str | None) -> str | None:
    r"""'Interface\Icons\spell_holy_flashheal' -> data: URI of the real icon (cached), or None."""
    if not path or not isinstance(path, str):
        return None
    stem = path.replace("/", chr(92)).split(chr(92))[-1].lower()
    if not stem or not all(ch.isalnum() or ch == "_" for ch in stem):
        return None
    f = ICON_CACHE / f"{stem}.jpg"
    if not f.exists():
        try:
            ICON_CACHE.mkdir(exist_ok=True)
            with urllib.request.urlopen(ICON_CDN.format(stem), timeout=10) as r:
                f.write_bytes(r.read())
        except Exception:
            return None
    uri = "data:image/jpeg;base64," + base64.b64encode(f.read_bytes()).decode()
    ICON_URLS[uri] = ICON_CDN.format(stem)
    return uri


def tile(name: str | None, size: str = "", icon: str | None = None) -> str:
    if not name:
        return ""
    cls = "mi" if size == "mini" else "ico"
    uri = icon_data(icon)
    if uri:
        return f'<img class="{cls}" src="{uri}" alt="{html.escape(name)}">'
    col = PALETTE[int(hashlib.md5(name.encode()).hexdigest(), 16) % len(PALETTE)]
    letters = "".join(w[0] for w in name.replace(":", "").split()[:2]).upper()
    cls = "mi" if size == "mini" else "ico"
    return f'<span class="{cls}" style="background:{col}">{html.escape(letters)}</span>'


def e(s) -> str:
    import re
    return html.escape(re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", str(s if s is not None else "")))


def wow_markup(s) -> str:
    """WoW |cffRRGGBB...|r colour codes -> HTML spans (they render as colour in game)."""
    import re
    t = html.escape(str(s or ""))
    t = re.sub(r"\|c[0-9a-fA-F]{2}([0-9a-fA-F]{6})(.*?)\|r", r'<span style="color:#\1">\2</span>', t)
    return t


CELL_H, GAP, HEAD_H, LABEL_W = 46, 5, 22, 86


def grid_html(vm) -> str:
    vm = lv(vm)
    cols = lst(vm["columns"])
    rows = lst(vm["rows"])
    out = ['<div class="g">', '<div></div>'] + [f'<div class="ch">{e(lv(c)["label"])}</div>' for c in cols]
    for r in rows:
        r = lv(r)
        out.append(f'<div class="rh">{e(r["label"])}</div>')
        for c in lst(r["cells"]):
            c = lv(c)
            cls = ["cell"]
            if c.get("selected"):
                cls.append("sel")
            if c.get("empty"):
                cls.append("empty")
                inner = f'<span class="fb">({e(c["fallback"])})</span>' if c.get("fallback") else ""
            else:
                if not c.get("known"):
                    cls.append("off")
                rz = '<span class="rz">+rez</span>' if c.get("rezActive") else ""
                inner = f'{tile(c.get("spell"), "", c.get("icon"))}<div class="cn"><span class="n">{e(c.get("spell"))}</span><span class="r">{e(c.get("rankText"))}</span></div>{rz}'
            out.append(f'<div class="{" ".join(cls)}">{inner}</div>')
    out.append("</div>")
    return "".join(out)


def cell_pos(vm, key):
    rows = lst(lv(vm)["rows"])
    for i, r in enumerate(rows):
        for j, c in enumerate(lst(lv(r)["cells"])):
            if lv(c)["key"] == key:
                return i, j
    return 0, 0


def picker_html(vm) -> str:
    p = lv(lv(vm).get("picker"))
    if not p:
        return ""
    i, j = cell_pos(vm, p["key"])
    top = HEAD_H + GAP + (i + 1) * (CELL_H + GAP)
    left = f"calc({LABEL_W + GAP}px + {j} * ((100% - {LABEL_W + GAP * 5}px) / 5 + {GAP}px))"
    items = [{"name": None, "label": "(empty: clear this slot)"}] + [
        {"name": lv(x)["name"], "label": lv(x)["name"], "sub": lv(x).get("rankText"), "icon": lv(x).get("icon")} for x in lst(p["entries"])]
    shown = items[:12]
    rows = []
    for k, it in enumerate(shown):
        hov = " hov" if it["name"] == "Abolish Disease" else ""
        rows.append(f'<div class="it{hov}">{tile(it["name"], "mini", it.get("icon")) if it["name"] else "<span class=mi></span>"}'
                    f'<span>{e(it["label"])}</span><span class="s">{e(it.get("sub") or "")}</span></div>')
    more = f'<div class="more">▾ scroll for {len(items) - 12} more</div>' if len(items) > 12 else ""
    return f'<div class="pop" style="top:{top}px;left:{left}">' \
           f'<div class="pt">{e(p["title"])}</div>{"".join(rows)}{more}</div>'


def editor_html(vm) -> str:
    ed = lv(lv(vm).get("editor"))
    if not ed:
        return ""
    rank_open = lv(vm).get("rankMenu") is not None
    menu = ""
    if rank_open:
        rmn = lv(lv(vm)["rankMenu"])
        cur = rmn.get("current")
        its = "".join(f'<div class="it{" cur" if lv(x)["key"] == cur else ""}">{e(lv(x)["label"])}</div>' for x in lst(rmn["entries"]))
        menu = f'<div class="pop" style="top:78px;left:12px;min-width:250px">{its}</div>'
    box = '<span class="box on"></span>' if ed.get("rez") else '<span class="box"></span>'
    rez_label = f'Resurrect if dead ({ed["rezSpell"]}, out of combat)' if ed.get("rezSpell") else "Resurrect if dead (no rez spell learned yet: skipped)"
    macro = f'Macro: {ed["macro"]}' if ed.get("macro") else "Not castable yet: spell or rank not learned."
    return (f'<div class="ed"><div class="t">{e(ed["title"])}</div><div class="btns"><span>Clear slot</span><span>Change spell</span></div>'
            f'<div class="row"><div><label>Rank</label><div class="dd{" open" if rank_open else ""}">{e(ed["rankLabel"])}</div></div>'
            f'<div class="chk">{box}<span>{e(rez_label)}</span></div></div>'
            f'<div class="mac">{e(macro)}</div>{menu}</div>')


def tab_body(l, caption: str) -> str:
    root = lv(l.eval("HogHeals.OptionsTable()"))
    tab = lv(lv(lv(root["args"])["Frames"])["args"]["clickcast"])
    ctx = l.lua.table()
    items = []
    for key, opt in lv(tab["args"]).items():
        opt = lv(opt)
        o = opt.get("order")
        items.append((100.0 if o is None or callable(o) else float(o), str(key), opt))
    items.sort(key=lambda x: (x[0], x[1]))
    vm = l.eval("HogHealsFrames.ClickGrid.ViewModel()")
    out = []
    toast = l.eval("HogHealsFrames.ClickGrid.lastToast")
    if toast:
        out.append(f'<div class="toast"><b>Toast on first login:</b> {e(toast)}</div>')
    for _, key, opt in items:
        hidden = opt.get("hidden")
        if callable(hidden) and rm.call(hidden, ctx):
            continue
        if opt.get("hhAttach") is not None:
            dim = " dim" if lv(vm).get("disabled") else ""
            # room under the grid so an open popup is not clipped by the window (in game it floats over everything)
            room = 260 if lv(vm).get("picker") else (150 if lv(vm).get("rankMenu") else 0)
            out.append(f'<div class="cc{dim}" style="margin-bottom:{room}px">{grid_html(vm)}{picker_html(vm)}{editor_html(vm)}</div>')
            continue
        if key == "clique":
            out.append(f'<div class="clique">{e(lv(vm)["disabled"])}</div><div class="w full"><div class="desc">Clique owns clicks on the frames. Unload Clique (or untick it in AddOns) and /reload to use this grid.</div></div>')
            continue
        if opt.get("type") == "description":
            name = opt.get("name")
            name = rm.call(name, ctx) if callable(name) else name
            out.append(f'<div class="w full"><div class="desc">{wow_markup(name)}</div></div>')
            continue
        html_w = rm.widget_html(key, opt, ctx)
        disabled = opt.get("disabled")
        if callable(disabled) and rm.call(disabled, ctx):
            html_w = html_w.replace('class="btn"', 'class="btn" style="opacity:.4"')
        out.append(html_w)
    out.append(f'<div class="cap">{e(caption)}</div>')
    return "".join(out)


def page(l, title_suffix: str, caption: str) -> str:
    side = ["Layout", "Appearance", "Indicators", "Bindings", "Click-cast", "Profiles"]
    doc = rm.page(f"Frames › Click-cast{title_suffix}", ["General", "Frames", "HUD"], "Frames", side, "Click-cast",
                  tab_body(l, caption),
                  foot="/hh click-cast  ·  mockup rendered from the live options table + ClickGrid.ViewModel() in the test harness")
    return doc.replace("</style>", CSS + "</style>", 1)


def fresh(cls="PRIEST", before_login=""):
    return boot(AddonLoader().bootstrap(), cls, before_login=before_login)


def states():
    G = "HogHealsFrames.ClickGrid"
    out = []

    l = fresh("WARRIOR")
    out.append(("1-empty", page(l, " — empty", "State 1. First login on a non-healer (Warrior, level 60 spellbook): no suggested layout, "
                                "empty grid, setup toast. Empty plain Left / Right show the target / menu they fall back to.")))

    l = fresh("PRIEST")
    out.append(("2-priest-defaults", page(l, " — Priest suggested layout", "State 2. First login on a Priest: grid seeded from "
                "defaults/clickcast/priest.lua (plain Left / Right = Rank 1, Shift + Left / Right = Highest: Flash Heal 7, Greater Heal 5; Renew 10). "
                "+rez = resurrects a dead target out of combat.")))

    l = fresh("PRIEST")
    l.execute(f'{G}.OpenPicker("BUTTON5:ALT")')
    out.append(("3-spell-picker", page(l, " — spell picker", "State 3. Right-click on the empty Alt + Button 5 slot: the picker lists the "
                "helpful, non-passive spells read from the spellbook (Smite, Mind Blast, Shoot and passive Spirit Tap are filtered out) with "
                "their learned rank span. Highlighted row = hover.")))

    l = fresh("PRIEST")
    l.execute(f'{G}.Select("LEFT:SHIFT"); {G}.OpenRankMenu("LEFT:SHIFT")')
    out.append(("4-rank-selector", page(l, " — rank selector", "State 4. Shift + Left (Flash Heal) selected, rank dropdown open: "
                "Highest rank (auto-upgrade, follows new ranks) or any learned rank 7..1. Default is Highest.")))

    l = fresh("PRIEST")
    l.execute(f'{G}.Select("RIGHT:SHIFT")')
    out.append(("5-resurrect-if-dead", page(l, " — resurrect if dead", "State 5. Shift + Right (Greater Heal, a direct heal) selected: "
                "'Resurrect if dead' is on by default. The macro line is the exact secure macrotext written to the frames.")))

    l = fresh("PRIEST", before_login='MockState.cliqueLoaded = true; HogHealsFramesCharDB = { schema = 1, slots = { ["LEFT:SHIFT"] = '
              '{ spell = "Flash Heal", rank = "highest", rez = true } } }')
    out.append(("6-clique-disabled", page(l, " — Clique detected", "State 6. Clique is loaded: no click-cast attributes are written, "
                "the grid is greyed and read-only, Reset / Clear are disabled. Saved slots are kept for when Clique is gone.")))
    return out


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    pages = states()
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width": 1240, "height": 900}, device_scale_factor=1)
        for name, content in pages:
            linked = content
            for uri, url in ICON_URLS.items():
                linked = linked.replace(uri, url)
            (OUT / f"{name}.html").write_text(linked, encoding="utf-8")
            pg.set_content(content)
            pg.screenshot(path=str(OUT / f"{name}.png"), full_page=True)
            print("rendered", OUT / f"{name}.png")
        b.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
