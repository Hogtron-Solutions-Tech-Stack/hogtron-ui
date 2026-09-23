# /hh perf: time every HogUI function while measuring, zero cost when off, restore everything on stop.
import pytest


@pytest.fixture
def full(lua):
    for a in ("HogHeals", "HogHeals_Frames", "HogHeals_HUD", "HogHeals_Meter"):
        lua.load_addon(a)
    lua.player_login()
    lua.execute('''
      function UpdateAddOnMemoryUsage() end
      function GetAddOnMemoryUsage(name) return name == "HogHeals" and 512 or 128 end
      function GetFramerate() return 60 end
      wipe(HogHeals.errors)
    ''')
    return lua


def errors(lua):
    return [e["msg"] for e in lua.eval('HogHeals.errors').values()]


def test_off_by_default_nothing_wrapped(full):
    assert full.eval('HogHeals.Perf.on') is False
    assert full.eval('#HogHeals.Perf.patched') == 0


def test_start_wraps_module_functions_and_counts_calls(full):
    n = full.eval('HogHeals.Perf.Start()')
    assert n > 20
    full.execute('ORIG_UPDATE = nil; HogHealsFrames.UnitButton.UpdateAll({ unit = nil }); HogHealsMeter.Meter.Refresh()')
    e = full.eval('HogHeals.Perf.entries["Frames.UnitButton.UpdateAll"]')
    assert e["calls"] == 1
    assert full.eval('HogHeals.Perf.entries["Meter.Meter.Refresh"].calls') == 1
    # element updates three tables deep are covered too
    assert full.eval('HogHeals.Perf.entries["Frames.Elements.health.Update"] ~= nil')
    assert errors(full) == []


def test_stop_restores_the_originals(full):
    full.execute('ORIG = HogHealsFrames.UnitButton.UpdateAll')
    full.execute('HogHeals.Perf.Start()')
    assert full.eval('HogHealsFrames.UnitButton.UpdateAll ~= ORIG')
    full.execute('HogHeals.Perf.Stop()')
    assert full.eval('HogHealsFrames.UnitButton.UpdateAll == ORIG')
    assert full.eval('#HogHeals.Perf.patched') == 0


def test_frames_are_never_walked_into(full):
    full.execute('HogHealsFrames.UnitButton.Create("HogHealsPerfBtn", UIParent)')
    full.execute('HogHeals.Perf.Start()')
    for p in full.eval('HogHeals.Perf.patched').values():
        assert p["tbl"]["_kind"] is None                     # never a widget (mock frames carry _kind)
    full.execute('HogHeals.Perf.Stop()')


def test_wrapped_function_returns_its_values(full):
    full.execute('HogHeals.Perf.Start()')
    r = full.eval('{ HogHealsFrames.module.ResolveLayout("party") }')
    assert r[2] == "party"
    full.execute('HogHeals.Perf.Stop()')


def test_slash_measures_reports_and_stops(full):
    full.execute('wipe(MockLog.chat or {}); HogHeals:SlashCommand("perf 5")')
    assert full.eval('HogHeals.Perf.on') is True
    full.execute('HogHealsMeter.Meter.Refresh(); MockAdvance(5.1)')
    chat = "\n".join(full.eval('MockLog.chat').values())
    assert "perf:" in chat and "memory:" in chat and "Meter.Meter.Refresh" in chat
    assert full.eval('HogHeals.Perf.on') is False
    assert full.eval('HogHeals.db.global.diag.perf.memoryKB') == 512 + 128 * 8
    assert errors(full) == []


def test_report_now_and_manual_stop(full):
    full.execute('HogHeals:SlashCommand("perf 60"); wipe(MockLog.chat); HogHeals:SlashCommand("perf")')
    assert any("perf:" in l for l in full.eval('MockLog.chat').values())
    full.execute('HogHeals:SlashCommand("perf stop")')
    assert full.eval('HogHeals.Perf.on') is False
    assert errors(full) == []
