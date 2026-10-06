# GO line (HogHeals_Quests/Go.lua): the quest to do next by rule, yards to it, ETA to level, on top of the tracker.
import pytest

from test_quests import MODERN, boot, errors

G = "HogHealsQuests.Go"


@pytest.fixture
def go(lua):
    boot(lua, MODERN)
    lua.execute("MockUnits.player.level = 5; function UnitLevel(u) return 5 end")
    return lua


def test_scores_follow_the_rule(go):
    # quest 7: level 2, 3/8 done, 100 yd north. quest 9: level 5, ready, ~566 yd away. quest 8: no point on this map.
    yards = go.eval(f"{G}.Yards()")
    assert yards[7] == 100 and yards[9] == pytest.approx(566, abs=1) and yards[8] is None
    picks = {rule: go.eval(f"{G}.Pick(HogHealsQuests.Data.List(), {G}.Yards(), '{rule}').quest.id") for rule in ("fastest", "balanced", "travel")}
    assert picks == {"fastest": 9, "balanced": 9, "travel": 7}
    # a grey quest scores almost nothing
    assert go.eval(f"{G}.IsGrey(2, 20)") is True and go.eval(f"{G}.IsGrey(16, 20)") is False
    s_grey = go.eval(f"({G}.Score({{ level = 2, objectives = {{}} }}, {{ level = 20, yards = 10, rule = 'balanced' }}))")
    s_green = go.eval(f"({G}.Score({{ level = 20, objectives = {{}} }}, {{ level = 20, yards = 10, rule = 'balanced' }}))")
    assert s_grey < s_green / 5


def test_tracker_shows_the_go_row_with_yards_and_eta(go):
    go.execute("""
      -- the session engine is its own PR (feat/session-xp); a stub stands in for it here
      HogHeals.Session = { Stats = function() return { toLevel = 2280, level = 5 } end, FormatTime = function(s) return "38m" end }
      HogHealsQuests.Tracker.Show(); HogHealsQuests.Tracker.Update()
    """)
    row = "HogHealsQuests.Tracker.frame.go"
    assert go.eval(f"{row}:IsShown()") is True
    assert go.eval(f"{row}.tag._text") == "GO:" and go.eval(f"{row}.title._text") == "Report to Goldshire"
    detail = go.eval(f"{row}.detail._text")
    assert "566 yd" in detail and "ready to turn in" in detail and "lvl 6 in " in detail
    # the list starts under the GO row
    assert go.eval("HogHealsQuests.Tracker.titles[1]._points[1][5]") < -(12 + 6)
    # right-click cycles the rule; the pick follows
    go.execute(f"{row}:GetScript('OnClick')({row}, 'RightButton'); MockAdvance(0.2)")   # Schedule() repaints a beat later
    assert go.eval("HogHeals.db.profile.quests.go.rule") == "travel"
    assert go.eval(f"{row}.title._text") == "Kobold Camp Cleanup" and "100 yd" in go.eval(f"{row}.detail._text")
    # super-track follows the pick when the client has it
    go.execute("TRACKED = nil; C_SuperTrack = { SetSuperTrackedQuestID = function(id) TRACKED = id end, GetSuperTrackedQuestID = function() return TRACKED end }")
    go.execute("HogHealsQuests.Tracker.Update()")
    assert go.eval("TRACKED") == 7
    # off: no row, list back at the top
    go.execute("HogHeals.db.profile.quests.go.enabled = false; HogHealsQuests.Tracker.Update()")
    assert go.eval(f"{row}:IsShown()") is False and go.eval("HogHealsQuests.Tracker.titles[1]._points[1][5]") == 0
    assert errors(go) == []


def test_slash_prints_the_pick_and_sets_the_rule(go):
    go.execute("HogHeals:SlashCommand('go')")
    chat = "\n".join(go.eval("MockLog.chat").values())
    assert "GO: Report to Goldshire" in chat and "566 yd" in chat
    go.execute("HogHeals:SlashCommand('go travel')")
    assert go.eval("HogHeals.db.profile.quests.go.rule") == "travel"
    assert errors(go) == []
