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
    owned = list(cfg["core"]["folders"]) + [m["name"] for m in cfg["modules"]]
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
    assert names[0] == "HogTronUI" and "HogHeals_Frames" in names and len(names) == 14
    assert [r["folders"] for r in rows if r["name"] == "HogTronUI"] == ["HogHeals,HogTronUI"]


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
