"""Release gate: CHANGELOG.md's newest section must be the tag being released.

The packager ships CHANGELOG.md as the file's notes (.pkgmeta manual-changelog), so a tag pushed without a new section
would publish the previous release's notes under the new version. The release workflow runs this before any upload.

    python dev/check_changelog.py v0.2.0-beta.2      # exit 1 when the top "## " heading is anything else
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def top_version(text: str) -> str | None:
    """The first level-2 heading's text (e.g. 'v0.2.0-beta.2'), or None."""
    m = re.search(r"^## +(\S+)\s*$", text, re.MULTILINE)
    return m.group(1) if m else None


def check(text: str, tag: str) -> list[str]:
    top = top_version(text)
    if top is None:
        return ["CHANGELOG.md has no '## <version>' section"]
    if top != tag:
        return [f"CHANGELOG.md's newest section is {top}, the tag is {tag}: add a '## {tag}' section at the top"]
    body = text.split(f"## {tag}", 1)[1]
    nxt = re.search(r"^## ", body, re.MULTILINE)
    if not re.search(r"^- ", body[: nxt.start()] if nxt else body, re.MULTILINE):
        return [f"CHANGELOG.md's {tag} section has no '- ' entries"]
    return []


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print(__doc__)
        return 2
    bad = check((ROOT / "CHANGELOG.md").read_text(encoding="utf-8"), argv[0])
    for b in bad:
        print("FAIL", b)
    if not bad:
        print(f"OK CHANGELOG.md leads with {argv[0]}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
