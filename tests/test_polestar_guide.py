# Polestar alongside (HogTronUI/Core/Polestar.lua; Sean 2026-11-06: "look at the polestar addon and implement that
# into hogtron UI" -> "work alongside it"). A fake Polestar stands in for the real one (GPL-3.0, never copied): only
# what HogTron UI reads - its message bus, settings and guide engine.
#   guide: the tracker's top row is Polestar's step (GUIDE) instead of GO
#   arrow: GO leaves the game's arrow to Polestar; the beam follows a user waypoint, titled with Polestar's goal
import pytest

from test_quests import MODERN, boot, errors
from test_waypoint import NAV

FAKE_POLESTAR = r'''
MockState.loadedAddons = MockState.loadedAddons or {}
MockState.loadedAddons.Polestar = true
PS_SETTINGS = { ["nav.blizzardWaypoint"] = false }
PS_FIRED = {}
PS_LISTENERS = {}
PS_GUIDE = { title = "Mulgore 1-12" }
PS_STEP = 4
PS_WAYPOINT = { map = 1412, x = 40, y = 50 }
PS_VIEW = { title = "Plainstriders", goals = {
  { status = "done", text = "Talk to Harken Windtotem" },
  { status = "current", text = "Kill 8 Plainstriders", progress = { cur = 3, max = 8 } },
  { status = "current", text = "Loot 5 Plainstrider Beaks" } } }
Polestar = {
  On = function(msg, fn) PS_LISTENERS[msg] = PS_LISTENERS[msg] or {} table.insert(PS_LISTENERS[msg], fn) return { msg = msg } end,
  Fire = function(msg, ...) PS_FIRED[#PS_FIRED + 1] = msg for _, fn in ipairs(PS_LISTENERS[msg] or {}) do fn(...) end end,
  Get = function(k) return PS_SETTINGS[k] end,
  Set = function(k, v) PS_SETTINGS[k] = v Polestar.Fire("SETTING_CHANGED", k, v) end,
  Engine = {
    GetGuide = function() return PS_GUIDE end, GetStepIndex = function() return PS_STEP end,
    GetStepCount = function() return 120 end, GetStepView = function(i) return PS_VIEW end,
    GetWaypoint = function() return PS_WAYPOINT end,
  },
}
'''

ROW = "HogHealsQuests.Tracker.frame.go"


@pytest.fixture
def ps(lua):
    boot(lua, MODERN + NAV + FAKE_POLESTAR)
    lua.execute("HogHealsQuests.Tracker.Show(); HogHealsQuests.Tracker.Update()")
    return lua


def chat(lua):
    return "\n".join(lua.eval("MockLog.chat").values())


def test_hooked_at_login_and_the_blizzard_waypoint_switched_on_once(ps):
    assert ps.eval("HogHeals.Polestar.Loaded()") is True and ps.eval("HogHeals.Polestar.hooked") is True
    for msg in ("GUIDE_CHANGED", "STEP_CHANGED", "STEP_UPDATED", "WAYPOINT_CHANGED"):
        assert ps.eval(f"#PS_LISTENERS['{msg}']") >= 1, msg
    assert ps.eval('PS_SETTINGS["nav.blizzardWaypoint"]') is True                # through Polestar.Set: it heard it
    assert "SETTING_CHANGED" in ps.eval("PS_FIRED").values()
    assert "Blizzard waypoint" in chat(ps)
    # once: switched off again in Polestar, it stays off
    ps.execute('PS_SETTINGS["nav.blizzardWaypoint"] = false; HogHeals.Polestar.hooked = nil; HogHeals.Polestar.Hook()')
    assert ps.eval('PS_SETTINGS["nav.blizzardWaypoint"]') is False
    assert errors(ps) == []


def test_the_tracker_top_row_is_polestars_step(ps):
    assert ps.eval(f"{ROW}:IsShown()") is True
    assert ps.eval(f"{ROW}.tag._text") == "GUIDE:"
    assert ps.eval(f"{ROW}.title._text") == "Plainstriders"
    detail = ps.eval(f"{ROW}.detail._text")
    assert "Kill 8 Plainstriders  3/8" in detail and "step 4/120" in detail
    assert "Harken" not in detail                                                 # a done goal is not "now"
    # Polestar moves on: its message repaints the row
    ps.execute("""PS_STEP = 5; PS_VIEW = { title = "Back to Bloodhoof", goals = { { status = "current", text = "Turn in Plainstrider Menace" } } }
      Polestar.Fire("STEP_CHANGED", 5); MockAdvance(0.3)""")
    assert ps.eval(f"{ROW}.title._text") == "Back to Bloodhoof" and "step 5/120" in ps.eval(f"{ROW}.detail._text")
    # click = Polestar's guide window
    ps.execute(f"{ROW}:GetScript('OnClick')({ROW}, 'LeftButton')")
    assert "TOGGLE_FRAME" in ps.eval("PS_FIRED").values()
    assert errors(ps) == []


def test_go_does_not_pull_the_arrow_while_polestar_guides(ps):
    ps.execute("TRACKED = nil; HogHealsQuests.Go.lastTracked = nil; HogHeals.db.profile.interop.polestar.guide = false; HogHealsQuests.Tracker.Update()")
    assert ps.eval(f"{ROW}.tag._text") == "GO:"                                   # guide row off: GO is back
    assert ps.eval("TRACKED") is None                                             # ... but the arrow is Polestar's
    # no guide running: GO points again
    ps.execute("PS_GUIDE = nil; HogHealsQuests.Tracker.Update()")
    assert ps.eval("TRACKED") is not None
    assert errors(ps) == []


def test_arrow_switch_off_gives_the_arrow_back_to_go(ps):
    ps.execute("""TRACKED = nil; HogHealsQuests.Go.lastTracked = nil
      HogHeals.db.profile.interop.polestar.guide = false; HogHeals.db.profile.interop.polestar.arrow = false
      HogHealsQuests.Tracker.Update()""")
    assert ps.eval("TRACKED") is not None
    assert errors(ps) == []


def test_the_beam_follows_a_user_waypoint_with_polestars_goal(ps):
    ps.execute("""
      TRACKED = nil; USERWP = true
      C_SuperTrack.IsSuperTrackingUserWaypoint = function() return USERWP end
      C_SuperTrack.IsSuperTrackingAnything = function() return TRACKED ~= nil or USERWP end
      MockFire("SUPER_TRACKING_CHANGED")
    """)
    w = "HogHealsWaypoint"
    assert ps.eval(f"{w}:IsShown()") is True
    assert ps.eval(f"{w}.title:GetText()") == "Kill 8 Plainstriders"
    assert "191 yd" in ps.eval(f"{w}.detail:GetText()")                           # the client's own distance
    # a map pin of your own, no guide: just "Waypoint"
    ps.execute('PS_GUIDE = nil; MockFire("SUPER_TRACKING_CHANGED")')
    assert ps.eval(f"{w}.title:GetText()") == "Waypoint"
    # nothing tracked at all: hidden as before
    ps.execute('USERWP = false; MockFire("SUPER_TRACKING_CHANGED")')
    assert ps.eval(f"{w}:IsShown()") is False
    assert errors(ps) == []


def test_master_switch_off_and_polestar_missing_change_nothing(lua):
    boot(lua, MODERN + NAV + FAKE_POLESTAR)
    lua.execute("HogHeals.db.profile.interop.polestar.enabled = false; HogHealsQuests.Tracker.Show(); HogHealsQuests.Tracker.Update()")
    assert lua.eval(f"{ROW}.tag._text") == "GO:"
    assert lua.eval("HogHeals.Polestar.Leads('guide')") is False


def test_without_polestar_nothing_changes(lua):
    boot(lua, MODERN + NAV)
    lua.execute("HogHealsQuests.Tracker.Show(); HogHealsQuests.Tracker.Update()")
    assert lua.eval("HogHeals.Polestar.Loaded()") is False and lua.eval("HogHeals.Polestar.hooked") is None
    assert lua.eval(f"{ROW}.tag._text") == "GO:"
    lines = list(lua.eval("HogHeals.Polestar.Diagnose()").values())
    assert lines[0].startswith("polestar: not installed")
    assert errors(lua) == []


def test_diag_reports_the_step_and_what_it_heard(ps):
    ps.execute('Polestar.Fire("WAYPOINT_CHANGED", PS_WAYPOINT)')
    lines = list(ps.eval("HogHeals.Polestar.Diagnose()").values())
    text = "\n".join(lines)
    assert "loaded, listening, engine yes, guiding yes" in text
    assert "step 4/120: Plainstriders - Kill 8 Plainstriders 3/8" in text
    assert "WAYPOINT_CHANGED 1" in text
    assert ps.eval("HogHeals.db.global.diag.polestar.guiding") is True
    assert errors(ps) == []


def test_a_polestar_that_throws_is_harmless(lua):
    boot(lua, MODERN + NAV + FAKE_POLESTAR + '''
      Polestar.Engine.GetStepView = function() error("boom") end
      Polestar.Get = function() error("boom") end
    ''')
    lua.execute("HogHealsQuests.Tracker.Show(); HogHealsQuests.Tracker.Update()")
    assert lua.eval(f"{ROW}.tag._text") == "GO:"                                  # no step readable: GO stays
    assert errors(lua) == []
