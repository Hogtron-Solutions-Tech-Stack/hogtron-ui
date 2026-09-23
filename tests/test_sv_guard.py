"""SavedVariables wipe: forensics, early-init guard, backup SavedVariable.

2026-09-17 23:55 and 2026-09-18 00:21 (WoW: Forever beta): HogHeals came up with an EMPTY database (diag session
counter = 1, wizard again, positions gone) while a valid HogHeals.lua sat on disk. Nothing on disk said why.
Three defences, all testable without a client:
  1. OnInitialize records what it saw (was HogHealsDB a table? was the addon marked loaded? which ADDON_LOADED
     did AceAddon initialise us from?) into HogHealsDB.global.diag.init, so the next wipe explains itself.
  2. If AceAddon initialises us off ANOTHER addon's ADDON_LOADED before our own SavedVariables are read, the real
     init waits for ADDON_LOADED("HogHeals") instead of building a fresh DB that overwrites the file at logout.
  3. A second SavedVariable (HogHealsDBBackup) carries a diag-free copy of the profiles, refreshed at init and
     logout; an empty main DB is re-seeded from it. If the backup survives a wipe the cause is in the main file's
     CONTENT; if both die together it is the client.
"""
from loader import ROOT, AddonLoader

SEED = '''HogHealsDB = { profileKeys = { ["Hog Tistic - Classic Beta PvP"] = "Default" },
  global = { schema = 3, diag = { session = 5, errors = {} } },
  profiles = { Default = { wizardDone = true, frames = { appearance = { fontSize = 18 } }, hud = { x = -1.67, y = -241.67 } } } }'''

BACKUP = '''HogHealsDBBackup = { at = "2026-09-18 00:20:00", session = 22, schema = 3,
  profileKeys = { ["Hog Tistic - Classic Beta PvP"] = "Default" },
  profiles = { Default = { wizardDone = true, frames = { appearance = { fontSize = 18 } }, meter = { width = 370 } } } }'''


def boot():
    return AddonLoader().bootstrap()


def last_init(lua):
    return list(lua.eval("HogHeals.db.global.diag.init").values())[-1]


def test_toc_declares_backup_savedvariable():
    toc = (ROOT / "HogHeals" / "HogHeals.toc").read_text(encoding="utf-8")
    line = next(l for l in toc.splitlines() if l.startswith("## SavedVariables:"))
    assert "HogHealsDB" in line and "HogHealsDBBackup" in line


def test_normal_load_keeps_saved_profile_and_records_forensics():
    lua = boot(); lua.execute(SEED)
    lua.load_addon("HogHeals"); lua.player_login()
    assert lua.eval("HogHeals.db.global.diag.session") == 6
    assert lua.eval("HogHeals.db.profile.frames.appearance.fontSize") == 18
    e = last_init(lua)
    assert e["svPresent"] == "table" and e["hadProfiles"] is True and e["loaded"] is True
    assert e["baseName"] == "HogHeals" and e["how"] == "direct" and e["restored"] is False


def test_early_blizzard_addon_loaded_does_not_wipe_the_db():
    # Client order when a load-on-demand Blizzard addon fires ADDON_LOADED after our files ran but before our
    # SavedVariables were read: AceAddon initialises every queued addon on ANY ADDON_LOADED.
    lua = boot()
    lua.load_addon("HogHeals", fire=False)           # files executed; HogHealsDB not set; not marked loaded
    lua.fire("ADDON_LOADED", "Blizzard_PTRFeedback")
    assert lua.eval("HogHeals.db") is None            # must NOT have built a fresh DB
    lua.execute(SEED); lua.mark_loaded("HogHeals"); lua.fire("ADDON_LOADED", "HogHeals")
    lua.player_login()
    assert lua.eval("HogHeals.db.global.diag.session") == 6
    assert lua.eval("HogHeals.db.profile.frames.appearance.fontSize") == 18
    e = last_init(lua)
    assert e["baseName"] == "Blizzard_PTRFeedback" and e["how"].startswith("deferred")
    assert "Blizzard_PTRFeedback" in e["trace"]


def test_enable_without_init_still_initialises():
    # If the deferred ADDON_LOADED never arrives, PLAYER_LOGIN must not run OnEnable on a nil db.
    lua = boot(); lua.load_addon("HogHeals", fire=False); lua.fire("ADDON_LOADED", "Blizzard_PTRFeedback")
    lua.execute(SEED); lua.mark_loaded("HogHeals"); lua.player_login()
    assert lua.eval("HogHeals.db.global.diag.session") == 6
    assert last_init(lua)["how"].startswith("enable")


def test_empty_main_db_is_reseeded_from_backup():
    lua = boot(); lua.execute(BACKUP); lua.load_addon("HogHeals"); lua.player_login()
    assert lua.eval("HogHeals.db.profile.wizardDone") is True
    assert lua.eval("HogHeals.db.profile.meter.width") == 370
    assert lua.eval("HogHeals.db.profile.frames.appearance.fontSize") == 18
    assert lua.eval("HogHeals.db.global.schema") == 4
    e = last_init(lua)
    assert e["restored"] is True and e["svPresent"] == "nil" and e["backup"] == "table"


def test_backup_is_refreshed_at_logout_without_defaults_or_diag():
    lua = boot(); lua.execute(SEED); lua.load_addon("HogHeals"); lua.player_login()
    lua.execute("HogHeals.db.profile.frames.appearance.fontSize = 17; HogHeals.db.profile.meter.width = 333")
    lua.fire("PLAYER_LOGOUT")
    b = lua.eval("HogHealsDBBackup")
    d = b["profiles"]["Default"]
    assert d["frames"]["appearance"]["fontSize"] == 17 and d["meter"]["width"] == 333
    assert d["meter"]["barHeight"] is None          # default value, stripped (AceDB logout ran first)
    assert b["profileKeys"]["Hog Tistic - Classic Beta PvP"] == "Default"
    assert b["global"] is None and b["schema"] == 4 and b["reason"] == "logout"


def test_backup_written_at_init_without_baked_defaults():
    lua = boot(); lua.execute(SEED); lua.load_addon("HogHeals")
    d = lua.eval("HogHealsDBBackup.profiles.Default")
    assert d["wizardDone"] is True and d["frames"]["appearance"]["fontSize"] == 18
    assert d["meter"] is None                        # nothing but defaults there -> not in the backup
    assert lua.eval("HogHealsDBBackup.reason") == "init"
    assert lua.eval("HogHeals.db.profile.meter.width") == 300   # defaults still served after the round trip


def test_backup_drops_functions_and_secrets():
    lua = boot(); lua.execute(SEED); lua.load_addon("HogHeals"); lua.player_login()
    lua.execute("MockSetSecrets(true); HogHeals.db.profile.junk = { f = function() end, s = MockSecret(5), ok = 1 }")
    lua.fire("PLAYER_LOGOUT")
    j = lua.eval("HogHealsDBBackup.profiles.Default.junk")
    assert j["ok"] == 1 and j["f"] is None and j["s"] is None


def test_forensics_ring_is_capped():
    lua = boot()
    lua.execute(SEED + "; HogHealsDB.global.diag.init = {}; for i = 1, 20 do HogHealsDB.global.diag.init[i] = { at = i } end")
    lua.load_addon("HogHeals")
    entries = list(lua.eval("HogHeals.db.global.diag.init").values())
    assert len(entries) == 8 and entries[-1]["how"] == "direct"


def test_svinfo_slash_prints_without_error():
    lua = boot(); lua.execute(SEED); lua.load_addon("HogHeals"); lua.player_login()
    lua.execute('HogHeals:SlashCommand("svinfo")')
    assert lua.eval("#HogHeals.errors") == 0


def test_sv_missing_at_own_event_waits_for_login_and_records_late_arrival():
    # Forever beta 2026-09-18: the client fires ADDON_LOADED("HogHeals") with HogHealsDB == nil on every load,
    # yet writes the file fine at logout. Building a fresh DB at that moment is what overwrote the profile.
    lua = boot(); lua.load_addon("HogHeals")            # marked loaded, own event fired, no SV
    assert lua.eval("HogHeals.db") is None
    lua.execute(SEED)                                   # table shows up later
    lua.player_login()
    assert lua.eval("HogHeals.db.global.diag.session") == 6
    assert lua.eval("HogHeals.db.profile.frames.appearance.fontSize") == 18
    e = last_init(lua)
    assert e["how"].startswith("enable") and e["late"] is True
    assert e["svAtEvent"]["rawget"] == "nil" and e["svAtEvent"]["loaded"] is True and e["svAtEvent"]["event"] == "HogHeals"


def test_sv_never_arrives_gives_fresh_db_at_login():
    lua = boot(); lua.load_addon("HogHeals"); lua.player_login()
    assert lua.eval("HogHeals.db.global.diag.session") == 1
    e = last_init(lua)
    assert e["late"] is False and e["svPresent"] == "nil"


def test_swap_check_flags_a_replaced_global():
    lua = boot(); lua.execute(SEED); lua.load_addon("HogHeals"); lua.player_login()
    lua.execute('HogHeals:CheckSVSwap("t0")')
    assert last_init(lua)["sv@t0"] == "table:same"
    lua.execute('HogHealsDB = { global = {}, profiles = {} }; HogHeals:CheckSVSwap("t1")')
    assert last_init(lua)["sv@t1"] == "table:SWAPPED"
    assert any("replaced under AceDB" in str(e["msg"]) for e in lua.eval("HogHeals.errors").values())
