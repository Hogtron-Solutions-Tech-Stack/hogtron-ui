"""Does every project the everything-package requires have a PUBLIC file on CurseForge?

The CurseForge project "HogTron UI" (the bundle) ships only the HogTron_Everything stub and requires HogTron UI Core
plus all 13 module projects. Upload it while any of those has no approved file and the CurseForge app hands players an
install it cannot complete. The release workflow runs this before the bundle's upload; run it yourself to see where
moderation stands.

CurseForge's own site answers scripts with a Cloudflare 403. api.cfwidget.com serves the public project data, and a
file is listed there only once CurseForge approved it (an upload still in review is not).

    python dev/split/check_approved.py         # table; exit 0 only when every required project has a public file
"""
from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
API = "https://api.cfwidget.com/{id}"
TRIES = 6          # cfwidget answers 202 "in queue" while it fetches a project it has not seen lately
WAIT = 10.0        # seconds between tries


def required(cfg: dict) -> list[dict]:
    """Core + every module: what the bundle's required-dependencies point at."""
    return [cfg["core"]] + list(cfg["modules"])


def fetch(curse_id: str) -> tuple[int, dict]:
    req = urllib.request.Request(API.format(id=curse_id), headers={"User-Agent": "hogtron-ui release check"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read().decode("utf-8") or "{}")
        except ValueError:
            body = {}
        return e.code, body


def look(curse_id: str, get=fetch, tries: int = TRIES, wait: float = WAIT, sleep=time.sleep) -> dict:
    """{"ok": bool, "files": n, "latest": label, "why": text} for one project."""
    for n in range(tries):
        try:
            code, data = get(curse_id)
        except (OSError, ValueError) as e:      # network down, bad JSON: say so, never pass silently
            code, data = 0, {"error": f"{type(e).__name__}: {e}"}
        if code == 200 and "title" in data:
            files = data.get("files") or []
            latest = files[0].get("display", "?") if files else "-"
            return {"ok": bool(files), "files": len(files), "latest": latest, "title": data["title"],
                    "why": "" if files else "no public file yet (in review, or never uploaded)"}
        if n + 1 < tries:
            sleep(wait)
    return {"ok": False, "files": 0, "latest": "-", "title": "?", "why": f"no answer: HTTP {code} {str(data)[:120]}"}


def check(cfg: dict, get=fetch, sleep=time.sleep) -> list[tuple[dict, dict]]:
    return [(p, look(p["curse_id"], get=get, sleep=sleep)) for p in required(cfg)]


def main(argv: list[str]) -> int:
    cfg = json.loads((HERE / "projects.json").read_text(encoding="utf-8"))
    rows = check(cfg)
    for p, r in rows:
        mark = "OK " if r["ok"] else "-- "
        print(f"{mark} {p['curse_id']:>8}  {p['title'][:40]:40}  files={r['files']}  latest={r['latest']}  {r['why']}")
    waiting = [p["title"] for p, r in rows if not r["ok"]]
    if waiting:
        print(f"\n{len(waiting)} of {len(rows)} not public yet - the everything-package must wait: {', '.join(waiting)}")
        return 1
    print(f"\nall {len(rows)} public - the everything-package's dependencies install")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
