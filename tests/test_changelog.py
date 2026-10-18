# Release gate: the tag's notes come from CHANGELOG.md (manual-changelog), so its newest section must be that tag.
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("check_changelog", ROOT / "dev" / "check_changelog.py")
CL = importlib.util.module_from_spec(spec)
spec.loader.exec_module(CL)


def test_the_changelog_leads_with_a_version_section_that_has_entries():
    text = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    top = CL.top_version(text)
    assert top and top.startswith("v0.")
    assert CL.check(text, top) == []


def test_a_tag_without_its_own_section_is_refused():
    text = "# HogTron UI\n\n## v0.2.0-beta.1\n\n### New\n- a thing\n"
    assert CL.check(text, "v0.2.0-beta.1") == []
    bad = CL.check(text, "v0.2.0-beta.2")
    assert bad and "newest section is v0.2.0-beta.1" in bad[0]
    assert CL.check("# HogTron UI\n\nnothing yet\n", "v1") == ["CHANGELOG.md has no '## <version>' section"]
    empty = "# HogTron UI\n\n## v0.2.0-beta.2\n\n### New\n\n## v0.2.0-beta.1\n- old\n"
    assert "no '- ' entries" in CL.check(empty, "v0.2.0-beta.2")[0]
