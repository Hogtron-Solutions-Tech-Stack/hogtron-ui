# Per-module CurseForge projects (dev/split): every addon folder belongs to exactly one project, the generated packager
# configs are current, each packs only its own folder(s), and the zip gate holds a module zip to exactly that.
# Sean 2026-10-18: "have them install the Hogtron UI, but some of the other ones underneath it can be individual installs".
import importlib.util
import io
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


MK = load("make_pkgmeta", ROOT / "dev" / "split" / "make_pkgmeta.py")
GATE = load("check_release_zip", ROOT / "dev" / "check_release_zip.py")


def test_every_addon_folder_is_in_exactly_one_project():
    cfg = json.loads((ROOT / "dev" / "split" / "projects.json").read_text(encoding="utf-8"))
    owned = list(cfg["core"]["folders"]) + [m["name"] for m in cfg["modules"]] + list(cfg["bundle"]["folders"])
    assert sorted(owned) == MK.addon_folders()
    assert len(owned) == len(set(owned))


def test_the_generated_configs_are_current_and_each_packs_only_its_own_folders():
    files = MK.build()
    for name, text in files.items():
        assert (ROOT / "dev" / "split" / "pkgmeta" / name).read_text(encoding="utf-8") == text, f"{name} stale: run make_pkgmeta.py --write"
    every = MK.addon_folders()
    bars = files["HogTron_Bars.pkgmeta"]
    assert "package-as: HogTron_Bars" in bars and "  HogTron_Bars/HogTron_Bars: HogTron_Bars" in bars
    for other in every:
        if other != "HogTron_Bars":
            assert f"  - {other}\n" in bars, other
    assert "  - HogTron_Awards/assets/awards/*.png" in files["HogTron_Awards.pkgmeta"]   # the root .pkgmeta's own ignore
    core = files["HogTronUI.pkgmeta"]
    assert core.index("HogTronUI/HogHeals: HogHeals") < core.index("HogTronUI/HogTronUI: HogTronUI")   # own folder last
    assert "required-dependencies" not in core


def test_a_module_requires_the_core_once_its_slug_is_known():
    cfg = json.loads((ROOT / "dev" / "split" / "projects.json").read_text(encoding="utf-8"))
    cfg["core"]["slug"] = "hogtron-ui-core"
    plates = [p for p in MK.projects(cfg) if p["name"] == "HogTron_Plates"][0]
    text = MK.pkgmeta(plates, MK.addon_folders(), MK.root_ignores())
    assert "required-dependencies:\n  - hogtron-ui-core\n" in text


def test_the_matrix_lists_every_project_with_its_folders():
    rows = json.loads(MK.matrix())
    names = [r["name"] for r in rows]
    assert names[0] == "HogTronUI" and "HogHeals_Frames" in names and len(names) == 15
    assert [r["folders"] for r in rows if r["name"] == "HogTronUI"] == ["HogHeals,HogTronUI"]
    assert names[-1] == "HogTron_Everything" and [r["bundle"] for r in rows] == [False] * 14 + [True]


def module_zip(tmp_path, folder, extra_top=None):
    z = tmp_path / f"{folder}.zip"
    with zipfile.ZipFile(z, "w") as out:
        for f in (ROOT / folder).rglob("*"):
            if f.is_file():
                rel = f.relative_to(ROOT).as_posix()
                data = f.read_bytes()
                if f.suffix == ".toc":
                    data = data.replace(b"@project-version@", b"v9.9.9")
                out.writestr(rel, data)
        if extra_top:
            out.writestr(f"{extra_top}/{extra_top}.toc", "## Version: v9.9.9\n")
    return z


def test_the_zip_gate_holds_a_module_zip_to_exactly_its_folder(tmp_path):
    good = module_zip(tmp_path, "HogTron_Training")
    assert GATE.check(good, "v9.9.9", ["HogTron_Training"]) == []
    bad = module_zip(tmp_path, "HogTron_Chat", extra_top="HogTron_Training")
    problems = GATE.check(bad, None, ["HogTron_Chat"])
    assert any("HogTron_Training: top-level entry that is not an addon folder" in p for p in problems)


def test_every_project_exists_on_curseforge_and_each_gets_its_upload():
    # 2026-10-18: all 14 projects created (ids + slugs filled); live, so a tag uploads to each (moderators need a first file)
    cfg = json.loads((ROOT / "dev" / "split" / "projects.json").read_text(encoding="utf-8"))
    for p in [cfg["core"]] + cfg["modules"]:
        assert p["curse_id"].isdigit() and p["slug"].startswith("hogtron-ui"), p
    assert cfg["live"] is True
    rows = json.loads(MK.matrix())
    assert [r["curse_id"] for r in rows] == [cfg["core"]["curse_id"]] + [m["curse_id"] for m in cfg["modules"]] + ["1744106"]
    cfg["live"] = False
    MK_load = MK.load
    try:
        MK.load = lambda: cfg
        rows = json.loads(MK.matrix())
    finally:
        MK.load = MK_load
    assert all(r["curse_id"] == "" for r in rows)                                # the off switch still stops every upload


# ---- the everything-package (2026-10-20): project 1744106 "HogTron UI" ships a stub and requires Core + every module ----

CHECK = load("check_approved", ROOT / "dev" / "split" / "check_approved.py")


def test_the_everything_package_ships_only_its_stub_and_requires_core_and_every_module():
    cfg = json.loads((ROOT / "dev" / "split" / "projects.json").read_text(encoding="utf-8"))
    text = MK.build()["HogTron_Everything.pkgmeta"]
    assert "# CurseForge project: HogTron UI (1744106)" in text and "package-as: HogTron_Everything" in text
    assert "  HogTron_Everything/HogTron_Everything: HogTron_Everything" in text
    for other in MK.addon_folders():
        if other != "HogTron_Everything":
            assert f"  - {other}\n" in text, other                                # every real addon folder stays out
    deps = text.split("required-dependencies:\n", 1)[1].split()
    assert [d for d in deps if d != "-"] == [cfg["core"]["slug"]] + [m["slug"] for m in cfg["modules"]]


def test_the_stub_loads_nothing_and_needs_the_core():
    toc = (ROOT / "HogTron_Everything" / "HogTron_Everything.toc").read_text(encoding="utf-8").splitlines()
    assert "## Dependencies: HogTronUI" in toc and "## Version: @project-version@" in toc
    assert [l for l in toc if l.strip() and not l.startswith("#")] == []             # no file listed: no code runs


def test_the_core_folder_names_the_core_project():
    cfg = json.loads((ROOT / "dev" / "split" / "projects.json").read_text(encoding="utf-8"))
    toc = (ROOT / "HogTronUI" / "HogTronUI.toc").read_text(encoding="utf-8")
    assert f"## X-Curse-Project-ID: {cfg['core']['curse_id']}\n" in toc


def test_the_all_in_one_never_goes_to_curseforge_and_the_bundle_waits_for_its_dependencies():
    wf = (ROOT / ".github" / "workflows" / "release.yml").read_text(encoding="utf-8")
    assert 'args: -p 0 -n "HogTronUI-{project-version}"' in wf                     # job package: GitHub / Wago only
    gate = wf.index("run: python dev/split/check_approved.py")
    assert gate < wf.index("- name: Upload (tag + project created only)")
    assert "matrix.project.bundle && matrix.project.curse_id != ''" in wf[wf.rindex("if:", 0, gate):gate]


def fake_cf(answers):
    calls = []

    def get(curse_id):
        calls.append(curse_id)
        a = answers[curse_id]
        return a.pop(0) if isinstance(a, list) else a
    return get, calls


def tiny_cfg():
    return {"core": {"title": "Core", "curse_id": "1"}, "modules": [{"title": "Bars", "curse_id": "2"}]}


def test_check_approved_passes_only_when_every_required_project_has_a_public_file():
    with_file = (200, {"title": "x", "files": [{"display": "HogTronUI-v1"}]})
    get, calls = fake_cf({"1": with_file, "2": with_file})
    rows = CHECK.check(tiny_cfg(), get=get, sleep=lambda s: None)
    assert [r["ok"] for _, r in rows] == [True, True] and calls == ["1", "2"]
    get, _ = fake_cf({"1": with_file, "2": (200, {"title": "Bars", "files": []})})
    rows = CHECK.check(tiny_cfg(), get=get, sleep=lambda s: None)
    assert [r["ok"] for _, r in rows] == [True, False]
    assert "no public file yet" in rows[1][1]["why"]


def test_check_approved_waits_out_the_queue_and_fails_loud_when_there_is_no_answer():
    with_file = (200, {"title": "x", "files": [{"display": "v1"}]})
    get, calls = fake_cf({"1": [(202, {"error": "in_queue"}), with_file]})
    slept = []
    r = CHECK.look("1", get=get, sleep=slept.append)
    assert r["ok"] and calls == ["1", "1"] and slept == [CHECK.WAIT]

    def down(curse_id):
        raise OSError("network unreachable")
    r = CHECK.look("1", get=down, tries=3, sleep=lambda s: None)
    assert not r["ok"] and "OSError" in r["why"]
    get, _ = fake_cf({"1": (404, {"error": "not_found"})})
    r = CHECK.look("1", get=get, tries=2, sleep=lambda s: None)
    assert not r["ok"] and "HTTP 404" in r["why"]
