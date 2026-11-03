"""Launch-day check: does every installed WoW client we ship for match a toc Interface number we list?

Blizzard patches a client (1.60.1 -> 1.60.2) and the addon turns "out of date" in the addon list: players with
"Load out of date AddOns" off see nothing load. The tocs carry `## Interface: 20505,20506,11508,11509,16001`;
this reads the launcher's `.build.info` (one row per installed product) and says which product moved past them.

    python dev/check_client_build.py                        # C:\\Program Files (x86)\\World of Warcraft\\.build.info
    python dev/check_client_build.py --build-info some.txt  # any .build.info copy

exit 0 = every installed product we target is covered; exit 1 = one is not (the fix line is printed).
A targeted product that is not installed is reported, not failed. Retail / other products are skipped.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BUILD_INFO = Path(r"C:\Program Files (x86)\World of Warcraft\.build.info")

# launcher product code -> what players call it. Only these are checked against the tocs.
TARGETED = {
    "wowf": "WoW: Forever",
    "wow_anniversary": "Anniversary (TBC)",
    "wow_classic_era": "Classic Era",
}


def parse_build_info(text: str) -> list[dict[str, str]]:
    """Rows of .build.info as dicts keyed by the header names ('Version', 'Product', 'Branch', ...)."""
    lines = [l for l in text.splitlines() if l.strip()]
    if not lines:
        return []
    cols = [c.split("!", 1)[0] for c in lines[0].split("|")]
    rows = []
    for line in lines[1:]:
        parts = line.split("|")
        rows.append({cols[i]: parts[i] if i < len(parts) else "" for i in range(len(cols))})
    return rows


def toc_from_version(version: str) -> int | None:
    """'1.60.1.70755' -> 16001, '2.5.6.70577' -> 20506, '1.15.9' -> 11509. None when it is not a version."""
    parts = version.strip().split(".")
    if len(parts) < 3:
        return None
    try:
        major, minor, patch = (int(p) for p in parts[:3])
    except ValueError:
        return None
    return major * 10000 + minor * 100 + patch


def toc_interfaces(root: Path = ROOT) -> dict[str, list[int]]:
    """{'HogTronUI/HogTronUI.toc': [20505, ...], ...} for every addon toc in the checkout."""
    out: dict[str, list[int]] = {}
    for toc in sorted(root.glob("*/*.toc")):
        if toc.parent.name != toc.stem:
            continue
        for line in toc.read_text(encoding="utf-8").splitlines():
            if line.lower().startswith("## interface:"):
                nums = [int(x) for x in line.split(":", 1)[1].replace(" ", "").split(",") if x.isdigit()]
                out[f"{toc.parent.name}/{toc.name}"] = nums
                break
    return out


def check(rows: list[dict[str, str]], shipped: list[int]) -> tuple[list[str], list[str]]:
    """(report lines, out-of-date product codes). Installed targeted products are compared with the shipped tocs."""
    lines: list[str] = []
    bad: list[str] = []
    seen: set[str] = set()
    for row in rows:
        product = row.get("Product", "")
        version = row.get("Version", "")
        label = TARGETED.get(product)
        if label is None:
            lines.append(f"skip         {product:<17} {version:<14} (not targeted)")
            continue
        seen.add(product)
        toc = toc_from_version(version)
        if toc is None:
            lines.append(f"?            {product:<17} {version:<14} (no version in .build.info)")
            continue
        if toc in shipped:
            lines.append(f"OK           {product:<17} {version:<14} -> {toc}  {label}")
        else:
            bad.append(product)
            lines.append(f"OUT OF DATE  {product:<17} {version:<14} -> {toc}  {label}  (tocs have {','.join(str(s) for s in shipped)})")
    for product, label in TARGETED.items():
        if product not in seen:
            lines.append(f"absent       {product:<17} {'-':<14} {label} is not installed here")
    return lines, bad


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--build-info", type=Path, default=DEFAULT_BUILD_INFO, help="the launcher's .build.info")
    ap.add_argument("--root", type=Path, default=ROOT, help="HogTron UI checkout (reads */*.toc)")
    args = ap.parse_args(argv)

    if not args.build_info.exists():
        print(f"no .build.info at {args.build_info} (is WoW installed there? pass --build-info)")
        return 1
    rows = parse_build_info(args.build_info.read_text(encoding="utf-8", errors="replace"))
    tocs = toc_interfaces(args.root)
    if not tocs:
        print(f"no addon tocs under {args.root}")
        return 1
    lists = {tuple(v) for v in tocs.values()}
    shipped = sorted(set(n for v in tocs.values() for n in v))
    print(f".build.info: {args.build_info}")
    if len(lists) == 1:
        print(f"tocs: {','.join(str(n) for n in next(iter(lists)))} ({len(tocs)} tocs agree)")
    else:
        print(f"WARNING: the {len(tocs)} tocs do not list the same Interface numbers:")
        for name, nums in tocs.items():
            print(f"  {name}: {','.join(str(n) for n in nums)}")
    lines, bad = check(rows, shipped)
    print("\n".join(lines))
    if bad:
        need = sorted(set(shipped) | {toc_from_version(r["Version"]) for r in rows if r.get("Product") in bad})
        print(f"\nFIX: set every toc to '## Interface: {','.join(str(n) for n in need)}', run the suite, tag a release.")
        return 1
    print("\nall installed targeted clients are covered")
    return 0


if __name__ == "__main__":
    sys.exit(main())
