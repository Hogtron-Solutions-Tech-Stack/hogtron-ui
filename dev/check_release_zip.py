"""Gate a packager zip before it goes anywhere: the shape players unzip into Interface/AddOns has to be right.

Usage: python dev/check_release_zip.py .release/HogTronUI-v0.1.0.zip
       python dev/check_release_zip.py .release/HogTronUI-v0.1.0.zip --expect-version 0.1.0

Fails (exit 1, one line per problem) when:
  - a HogHeals* folder in the repo is not a top-level folder in the zip (missing from .pkgmeta move-folders ->
    it ships nested inside HogHeals/ and the game never loads it)
  - the zip has a top-level entry that is not a repo addon folder (stray LICENSE, tests, docs ...)
  - a folder's .toc is missing, or a file its .toc lists is missing from the zip
  - repo-only stuff leaked in (tests/, dev/, docs/, .github/)
  - a .toc still carries the raw @project-version@ token, or (with --expect-version) the wrong version
"""
from __future__ import annotations

import sys
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
LEAK = ("tests/", "dev/", "docs/", ".github/", ".pkgmeta", "requirements-dev.txt")


def check(zip_path: Path, expect_version: str | None) -> list[str]:
    bad: list[str] = []
    with zipfile.ZipFile(zip_path) as z:
        names = [n for n in z.namelist() if not n.endswith("/")]
        name_set = set(names)
        tops = {PurePosixPath(n).parts[0] for n in names}
        repo = {p.name for pat in ("HogHeals*", "HogTron_*") for p in ROOT.glob(pat) if p.is_dir()}

        for folder in sorted(repo - tops):
            bad.append(f"{folder}: not a top-level folder in the zip (add it to .pkgmeta move-folders)")
        for top in sorted(tops - repo):
            bad.append(f"{top}: top-level entry that is not an addon folder")
        for n in names:
            inner = "/".join(PurePosixPath(n).parts[1:])
            if any(inner.startswith(x) or f"/{x}" in f"/{inner}" for x in LEAK) and "/Libs/" not in f"/{n}":
                bad.append(f"{n}: repo-only file leaked into the zip")

        for folder in sorted(repo & tops):
            toc = f"{folder}/{folder}.toc"
            if toc not in name_set:
                bad.append(f"{folder}: no {folder}.toc in the zip")
                continue
            text = z.read(toc).decode("utf-8-sig")
            for line in text.splitlines():
                line = line.strip()
                if line.startswith("## Version:"):
                    got = line.split(":", 1)[1].strip()
                    if got.startswith("@"):
                        bad.append(f"{toc}: Version still the raw token {got}")
                    elif expect_version and got.removeprefix("v") != expect_version.removeprefix("v"):
                        bad.append(f"{toc}: Version {got}, expected {expect_version}")
                    continue
                if not line or line.startswith("#"):
                    continue
                listed = f"{folder}/{line.replace(chr(92), '/')}"
                if listed not in name_set:
                    bad.append(f"{toc}: lists {line}, not in the zip")
    return bad


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    expect = None
    if "--expect-version" in args:
        i = args.index("--expect-version")
        expect = args[i + 1]
        del args[i:i + 2]
    zip_path = Path(args[0])
    if not zip_path.is_file():
        print(f"FAIL no zip at {zip_path}")
        return 1
    bad = check(zip_path, expect)
    with zipfile.ZipFile(zip_path) as z:
        tops = sorted({PurePosixPath(n).parts[0] for n in z.namelist()})
        count = len([n for n in z.namelist() if not n.endswith("/")])
    print(f"{zip_path.name}: {len(tops)} top-level folders, {count} files")
    for t in tops:
        print("  ", t)
    for b in bad:
        print("FAIL", b)
    if bad:
        return 1
    print("OK zip layout matches the repo's addon folders")
    return 0


if __name__ == "__main__":
    sys.exit(main())
