"""The 2026-10-15 folder rename (HogHeals -> HogTronUI, HogHeals_<X> -> HogTron_<X>, HogHeals_Frames unchanged, a
HogHeals settings bridge for one release). The risk is settings: a SavedVariables file is named after its folder."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OLD_SV = """
HogHealsDB = {
  profileKeys = { ["Hognificent - Nightslayer"] = "Default" },
  profiles = { Default = { locked = false, plates = { target = { style = "brackets" } }, frames = { appearance = { fontSize = 15 } } } },
  global = { schema = 4, training = { PRIEST = { spells = { 1 } } } },
  char = { ["Hognificent - Nightslayer"] = { atlas = { role = "caster" } } },
}
"""


def boot(lua, before=""):
    if before:
        lua.execute(before)
    lua.load_addon("HogHeals")            # the bridge (declares the old SavedVariables)
    lua.load_addon("HogTronUI")
    lua.player_login()
    return lua


# ------------------------------------------------------------------ settings carried over
def test_old_settings_are_taken_over_on_the_first_login_after_the_rename(lua):
    boot(lua, OLD_SV)
    assert lua.eval('HogHeals.db.profile.locked') is False
    assert lua.eval('HogHeals.db.profile.plates.target.style') == "brackets"
    assert lua.eval('HogHeals.db.profile.frames.appearance.fontSize') == 15
    assert lua.eval('HogHeals.db.global.training.PRIEST ~= nil')
    assert lua.eval('HogHeals.db.char.atlas.role') == "caster"                       # per-character data too
    init = lua.eval('HogHeals.db.global.diag.init[#HogHeals.db.global.diag.init]')
    assert init["migratedFrom"] == "HogHealsDB"
    assert lua.eval('rawequal(HogTronUIDB, rawget(HogHeals.db, "sv"))')              # the live table is the NEW variable
    assert lua.eval('HogHealsDB.profiles.Default.locked') is False                  # the old file is left as it was


def test_existing_new_settings_are_never_overwritten_by_the_old_file(lua):
    boot(lua, OLD_SV + """
HogTronUIDB = { profileKeys = { ["Hognificent - Nightslayer"] = "Default" }, profiles = { Default = { locked = true } }, global = { schema = 4 } }
""")
    assert lua.eval('HogHeals.db.profile.locked') is True
    init = lua.eval('HogHeals.db.global.diag.init[#HogHeals.db.global.diag.init]')
    assert init["migratedFrom"] is None


def test_old_backup_is_used_when_the_old_main_table_is_empty(lua):
    boot(lua, """
HogHealsDB = {}
HogHealsDBBackup = { schema = 4, profileKeys = { ["Hognificent - Nightslayer"] = "Default" }, profiles = { Default = { locked = false } } }
""")
    assert lua.eval('HogHeals.db.profile.locked') is False
    assert lua.eval('HogHeals.db.global.diag.init[#HogHeals.db.global.diag.init].migratedFrom') == "HogHealsDBBackup"


def test_a_brand_new_install_starts_fresh(lua):
    boot(lua)
    assert lua.eval('HogHeals.db.profile.locked') is True                            # the default
    assert lua.eval('HogHeals.db.global.diag.init[#HogHeals.db.global.diag.init].migratedFrom') is None


def test_tocs_declare_new_and_old_savedvariables_in_the_right_folders():
    core = (ROOT / "HogTronUI" / "HogTronUI.toc").read_text(encoding="utf-8")
    bridge = (ROOT / "HogHeals" / "HogHeals.toc").read_text(encoding="utf-8")
    assert "## SavedVariables: HogTronUIDB, HogTronUIDBBackup" in core
    assert "## SavedVariables: HogHealsDB, HogHealsDBBackup" in bridge
    assert "HogHealsDB" not in core and "HogTronUIDB" not in bridge                  # never the same variable twice


# ------------------------------------------------------------------ old folders left on disk
def test_old_module_folders_still_loaded_are_switched_off_and_named(lua):
    lua.execute('MockState.loadedAddons = MockState.loadedAddons or {}; MockState.loadedAddons.HogHeals_Bars = true; MockState.loadedAddons.HogHeals_Skin = true')
    lua.execute('HH_disabled = {}; C_AddOns.DisableAddOn = function(n) HH_disabled[#HH_disabled + 1] = n end')
    boot(lua)
    lua.execute('MockLog.chat = {}; HogHeals.Legacy.Check()')
    assert sorted(set(lua.eval("HH_disabled").values())) == ["HogHeals_Bars", "HogHeals_Skin"]   # login ran it, the test again
    assert any("HogHeals_Bars" in l and "/reload" in l for l in lua.eval('MockLog.chat').values())


def test_frames_and_the_bridge_are_not_old_folders(lua):
    lua.execute('MockState.loadedAddons = { HogHeals = true, HogHeals_Frames = true }')
    boot(lua)
    assert len(lua.eval('HogHeals.Legacy.Loaded()')) == 0


# ------------------------------------------------------------------ layout guards
def test_folder_layout():
    names = sorted(p.name for p in ROOT.iterdir() if p.is_dir() and (p.name.startswith("HogHeals") or p.name.startswith("HogTron")))
    assert "HogTronUI" in names and "HogHeals" in names and "HogHeals_Frames" in names
    old = [n for n in names if n.startswith("HogHeals_") and n != "HogHeals_Frames"]
    assert old == []


def test_every_toc_dependency_names_a_folder_that_exists():
    folders = {p.name for p in ROOT.iterdir() if p.is_dir()}
    bad = []
    for toc in list(ROOT.glob("HogHeals*/*.toc")) + list(ROOT.glob("HogTron*/*.toc")):
        for line in toc.read_text(encoding="utf-8").splitlines():
            m = re.match(r"## (Dependencies|OptionalDeps|RequiredDeps):\s*(.+)", line)
            if m:
                for dep in [d.strip() for d in m.group(2).split(",")]:
                    if dep and dep not in folders:
                        bad.append(f"{toc.parent.name}: {dep}")
    assert bad == []


def test_every_texture_path_in_the_code_points_at_a_real_folder():
    bad = []
    for f in list(ROOT.glob("HogHeals*/**/*.lua")) + list(ROOT.glob("HogTron*/**/*.lua")):
        if "Libs" in f.parts:
            continue
        for m in re.finditer(r"AddOns\\\\([A-Za-z_]+)\\\\", f.read_text(encoding="utf-8")):
            if not (ROOT / m.group(1)).is_dir():
                bad.append(f"{f.relative_to(ROOT).as_posix()}: {m.group(1)}")
    assert bad == []
