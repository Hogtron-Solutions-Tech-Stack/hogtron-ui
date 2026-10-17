"""Generate the 75 HogTron Awards icons on OpenArt, nine per 3x3 sheet, then cut them into the addon.

Source of truth for every prompt: HogTron_Awards/data/awards.lua (read through the Lua harness - nothing is copied
here). Nine awards share one generation (75 icons = 9 sheets, ~40 credits each at 2K), on a flat magenta key so the
cutter can give every icon real transparency.

    python -P dev/gen_award_icons.py                 # quote every sheet, spend nothing (default)
    python -P dev/gen_award_icons.py --go            # generate (resumable: a sheet already submitted is never resubmitted)
    python -P dev/gen_award_icons.py --cut           # cut raw sheets -> HogTron_Awards/assets/awards/<id>.png + .tga
    python -P dev/gen_award_icons.py --only 3 --redo --go   # regenerate sheet 3

Hard caps: --max-credits (default 600) for this run, and never below --floor (default 20000) on the account.
Raw sheets + job state live OUTSIDE the repo (--work, default C:/Hogtron/Ads-Demos/HogTronAwards).
Fallback if OpenArt is down: the genimage skill (Nano Banana Pro) with sheet_prompt() per sheet, raw PNGs into
<work>/raw/sheetNN.png, then --cut as usual.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
ASSETS = ROOT / "HogTron_Awards" / "assets" / "awards"
OPENART_TOOLS = pathlib.Path(r"C:\Hogtron\Ads-Demos\OpenArt-Plates\tools")
MODEL = "nano-banana-2-1"
PER_SHEET = 9
# The last sheet has only 3 real awards; its other 6 tiles are second takes of headline awards (kept as alternates).
SPARE_IDS = ["mvp", "boar_slayer", "lifeline", "floor_inspector", "the_wall", "loot_goblin"]


def awards() -> list[dict]:
    from loader import AddonLoader
    lua = AddonLoader().bootstrap()
    lua.load_addon("HogTronUI")
    lua.load_addon("HogTron_Awards")
    out = []
    for a in lua.eval("HogTronAwards.LIST").values():
        out.append({"id": a["id"], "name": a["name"], "kind": a["kind"], "icon": a["icon"],
                    "prompt": lua.eval(f'HogTronAwards.IconPrompt(HogTronAwards.BY_ID["{a["id"]}"])')})
    return out


def sheets(items: list[dict]) -> list[list[dict]]:
    groups = [items[i:i + PER_SHEET] for i in range(0, len(items), PER_SHEET)]
    if len(groups[-1]) < PER_SHEET:
        by_id = {a["id"]: a for a in items}
        spares = [dict(by_id[i], id=i + "_alt") for i in SPARE_IDS]
        groups[-1] = groups[-1] + spares[: PER_SHEET - len(groups[-1])]
    return groups


def sheet_prompt(group: list[dict]) -> str:
    rows = []
    for r in range(3):
        cells = [f"({r * 3 + c + 1}) {group[r * 3 + c]['icon']}" for c in range(3)]
        rows.append(f"Row {r + 1}, left to right: " + "; ".join(cells) + ".")
    return ("A 3x3 grid sheet of nine separate square fantasy game award icons, all the same size, evenly spaced, "
            "every icon fully separated by wide gaps of solid flat pure magenta #FF00FF; the whole background is that "
            "one flat magenta, no gradient, no shadows on it, no frame around the sheet. " + " ".join(rows) + " "
            "Every icon in the same HogTron style: aged bronze circular rim with rivets and small boar-tusk ornaments, "
            "deep navy enamel inside the rim, warm brass and ivory highlights, subtle cyan magical glow, painted "
            "World of Warcraft spell-icon look, bold readable silhouette, centered subject. No text, no letters, "
            "no numbers, no watermark.")


# ------------------------------------------------------------------------------------------------ OpenArt
def openart():
    sys.path.insert(0, str(OPENART_TOOLS))
    from openart_mcp import MCP, UA  # noqa: E402
    m = MCP()
    m.initialize()
    return m, UA


def tool(m, name, args):
    res = m.call("tools/call", {"name": name, "arguments": args})
    if "error" in res:
        raise SystemExit(f"MCP error: {json.dumps(res['error'])[:600]}")
    r = res["result"]
    if r.get("isError"):
        raise SystemExit(f"tool error: {json.dumps(r)[:800]}")
    return r.get("structuredContent") or json.loads(r["content"][0]["text"])


def urls_in(obj, out=None):
    out = [] if out is None else out
    if isinstance(obj, dict):
        for v in obj.values():
            urls_in(v, out)
    elif isinstance(obj, list):
        for v in obj:
            urls_in(v, out)
    elif isinstance(obj, str) and re.match(r"^https?://", obj) and re.search(r"\.(png|jpe?g|webp)(\?|$)", obj, re.I):
        out.append(obj)
    return out


def generate_openart(groups, work: pathlib.Path, a):
    jobs_file = work / "jobs.json"
    jobs = json.loads(jobs_file.read_text()) if jobs_file.exists() else {}
    m, ua = openart()
    spent = 0
    for i, g in enumerate(groups, 1):
        if a.only and i not in a.only:
            continue
        key = f"sheet{i:02d}"
        dest = work / "raw" / f"{key}.png"
        if a.redo and key in jobs:
            jobs.pop(key)
            if dest.exists():
                dest.rename(dest.with_suffix(f".v{int(time.time())}.png"))
        params = {"prompt": sheet_prompt(g), "aspectRatio": "1:1", "resolution": "2K", "imageCount": 1}
        hist = jobs.get(key, {}).get("historyId")
        if not hist:
            q = tool(m, "openart_model_cost", {"model": MODEL, "mode": "text2image", "params": params})
            item, bal = q["items"][0], q.get("balance")
            cost = item["totalCredits"]
            print(f"{key}: {', '.join(x['id'] for x in g)}\n  quote {cost} cr ({item['config']}), balance {bal}")
            if not item["affordable"]:
                raise SystemExit(f"REFUSING: not affordable ({q.get('upgradeUrl')})")
            if spent + cost > a.max_credits:
                raise SystemExit(f"REFUSING: this run would spend {spent + cost} > --max-credits {a.max_credits}")
            if bal is not None and bal - cost < a.floor:
                raise SystemExit(f"REFUSING: balance {bal} - {cost} under the floor {a.floor}")
            if not a.go:
                print("  DRY RUN")
                continue
            sub = tool(m, "openart_generate_image", {"model": MODEL, "mode": "text2image", "params": params})
            hist = sub.get("historyId") or sub.get("id")
            if not hist:
                raise SystemExit(f"no historyId: {json.dumps(sub)[:400]}")
            jobs[key] = {"historyId": hist, "cost": cost, "ids": [x["id"] for x in g], "submitted": time.time()}
            jobs_file.write_text(json.dumps(jobs, indent=2))
            spent += cost
            print(f"  submitted {hist}")
    # collect
    for key, j in sorted(jobs.items()):
        dest = work / "raw" / f"{key}.png"
        if dest.exists() or not a.go:
            continue
        deadline = time.time() + 900
        while time.time() < deadline:
            res = tool(m, "openart_creation_wait", {"historyId": j["historyId"], "timeoutSeconds": 90})
            st = res.get("status")
            print(f"  {key}: {st}", flush=True)
            if st == "COMPLETED":
                urls = urls_in(res)
                if not urls:
                    raise SystemExit(f"{key}: COMPLETED without an image url")
                dest.parent.mkdir(parents=True, exist_ok=True)
                req = urllib.request.Request(urls[0], headers={"User-Agent": ua})
                with urllib.request.urlopen(req, timeout=600) as r:
                    dest.write_bytes(r.read())
                j["url"] = urls[0]
                jobs_file.write_text(json.dumps(jobs, indent=2))
                break
            if st in ("FAILED", "CANCELLED"):
                print(f"  {key}: {st}")
                break
            time.sleep(max(2, int(res.get("pollAfterSeconds") or 5)))
    print(f"spent this run: {spent} credits")


# ------------------------------------------------------------------------------------------------ cut
def round_off_navy_corners(tile):
    """Some sheets come back with each round icon painted on an inset NAVY square (sheets 6 and 9, 2026-10-15) that
    the magenta key keeps. Outside the rim circle, clear every navy pixel and any leftover magenta fringe. Bronze
    pieces outside the circle (tusk ornaments, the square frames some sheets draw on purpose) are not blue: kept."""
    import numpy as np
    from PIL import Image
    a = np.asarray(tile).astype(np.float32)
    n = a.shape[0]
    yy, xx = np.mgrid[0:n, 0:n]
    rad = np.sqrt((yy - (n - 1) / 2) ** 2 + (xx - (n - 1) / 2) ** 2)
    outside = rad > n * 0.468
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    lum = 0.3 * r + 0.59 * g + 0.11 * b
    navy = (b > r + 10) & (lum < 100)
    fringe = (np.minimum(r, b) > g + 25) & (a[..., 3] < 255)
    kill = outside & (navy | fringe)
    a[..., 3] = np.where(kill, 0, a[..., 3])
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def cut(groups, work: pathlib.Path, only=None) -> int:
    import numpy as np
    from PIL import Image
    from scipy import ndimage
    ASSETS.mkdir(parents=True, exist_ok=True)
    made = 0
    for i, g in enumerate(groups, 1):
        if only and i not in only:
            continue
        src = work / "raw" / f"sheet{i:02d}.png"
        if not src.exists():
            print(f"sheet{i:02d}: no raw image")
            continue
        img = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
        h, w, _ = img.shape
        # key: "magenta-ness" = red and blue high, green low. Robust to the model's slightly-off magenta.
        r, gch, b = img[..., 0], img[..., 1], img[..., 2]
        magenta = (r > 150) & (b > 150) & (gch < 110) & (np.abs(r - b) < 90)
        fg = ~magenta
        fg = ndimage.binary_opening(fg, iterations=2)
        filled = ndimage.binary_fill_holes(ndimage.binary_closing(fg, iterations=4))
        lab, n = ndimage.label(filled)
        sizes = ndimage.sum(filled, lab, range(1, n + 1))
        order = list(np.argsort(sizes)[::-1][:9])
        if len(order) < 9 or sizes[order[-1]] < (h * w) / 200:
            print(f"sheet{i:02d}: found {len(order)} usable shapes, wanted 9 - regenerate it (--only {i} --redo --go)")
            continue
        boxes = [ndimage.find_objects(lab)[k] for k in order]
        cy = [(b0.start + b0.stop) / 2 for b0, _ in boxes]
        cx = [(b1.start + b1.stop) / 2 for _, b1 in boxes]
        idx = sorted(range(9), key=lambda k: (int(cy[k] / (h / 3)), cx[k]))
        for slot, k in enumerate(idx):
            award = g[slot]
            b0, b1 = boxes[k]
            y0, y1, x0, x1 = b0.start, b0.stop, b1.start, b1.stop
            side = int(max(y1 - y0, x1 - x0) * 1.04)
            cyy, cxx = (y0 + y1) // 2, (x0 + x1) // 2
            Y0, X0 = max(0, cyy - side // 2), max(0, cxx - side // 2)
            Y1, X1 = min(h, Y0 + side), min(w, X0 + side)
            rgb = img[Y0:Y1, X0:X1]
            mask = (lab[Y0:Y1, X0:X1] == order[k] + 1)
            alpha = ndimage.gaussian_filter(mask.astype(np.float32), 0.8)
            # despill: pull leftover magenta out of the rim's edge pixels
            rr, gg, bb = rgb[..., 0], rgb[..., 1], rgb[..., 2]
            spill = np.clip(np.minimum(rr, bb) - gg, 0, None) * (1 - mask)
            rgb = rgb.copy()
            rgb[..., 0] -= spill * 0.8
            rgb[..., 2] -= spill * 0.8
            rgba = np.dstack([np.clip(rgb, 0, 255), alpha * 255]).astype(np.uint8)
            tile = Image.fromarray(rgba, "RGBA").resize((256, 256), Image.LANCZOS)
            tile = round_off_navy_corners(tile)
            if award["id"].endswith("_alt"):              # spare second takes: kept for review, never shipped
                (work / "alts").mkdir(exist_ok=True)
                tile.save(work / "alts" / f"{award['id']}.png")
            else:
                tile.save(ASSETS / f"{award['id']}.png")      # 256x256 source (repo only; .pkgmeta keeps it out of the zip)
                # what the game loads: Classic clients read TGA/BLP, not PNG. 128x128 is sharp at the card's 72 px and
                # keeps 75 icons near 5 MB (256x256 TGA would be ~20 MB).
                tile.resize((128, 128), Image.LANCZOS).save(ASSETS / f"{award['id']}.tga")
            made += 1
        print(f"sheet{i:02d}: cut {len(idx)} icons")
    return made


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--go", action="store_true", help="spend credits (default: quote only)")
    ap.add_argument("--cut", action="store_true", help="cut raw sheets into the addon")
    ap.add_argument("--only", type=int, nargs="*", help="sheet numbers (1-based)")
    ap.add_argument("--redo", action="store_true")
    ap.add_argument("--max-credits", type=int, default=600)
    ap.add_argument("--floor", type=int, default=20000)
    ap.add_argument("--work", default=r"C:\Hogtron\Ads-Demos\HogTronAwards")
    a = ap.parse_args()
    work = pathlib.Path(a.work)
    (work / "raw").mkdir(parents=True, exist_ok=True)
    items = awards()
    groups = sheets(items)
    (work / "sheets.json").write_text(json.dumps([[x["id"] for x in g] for g in groups], indent=2))
    print(f"{len(items)} awards -> {len(groups)} sheets")
    if a.cut:
        n = cut(groups, work, a.only)
        real = len([p for p in ASSETS.glob("*.png") if not p.stem.endswith("_alt")])
        print(f"cut {n} tiles; {real} of {len(items)} award icons present")
        return 0
    generate_openart(groups, work, a)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
