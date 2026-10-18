# Every addon of the suite takes its version from the release tag (the packager replaces @project-version@).
# 2026-10-18: the v0.2.0-beta.1 tag build stopped at the zip gate - HogTron_Journal.toc said "0.1.0", hard-coded.
# The gate caught it before any upload; this catches it on every push instead of on the tag.
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]


def addon_tocs():
    for folder in sorted(ROOT.iterdir()):
        if folder.is_dir() and (folder.name.startswith("HogTron") or folder.name.startswith("HogHeals")):
            toc = folder / f"{folder.name}.toc"
            if toc.is_file():
                yield toc


def test_every_addon_toc_takes_the_release_version():
    tocs = list(addon_tocs())
    assert len(tocs) >= 15
    for toc in tocs:
        lines = toc.read_text(encoding="utf-8").replace("\r", "").split("\n")
        versions = [l.split(":", 1)[1].strip() for l in lines if l.startswith("## Version:")]
        assert versions == ["@project-version@"], (toc.name, versions)
