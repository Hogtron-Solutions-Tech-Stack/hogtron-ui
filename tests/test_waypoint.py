# Waypoint (HogHeals_Quests/Waypoint.lua): the super-tracked quest marked in the world, anchored to Blizzard's
# navigation frame; yards + eta + progress under it; an arrow on the edge when clamped. Waypoint UI clip, 2026-10-08.
import pytest

from test_quests import MODERN, boot, errors

W = "HogHealsQuests.Waypoint"

NAV = '''
NavFrame = CreateFrame("Frame", "SuperTrackedFrame", UIParent)
NavFrame._cx, NavFrame._cy = 1200, 700
NavFrame.Icon = NavFrame:CreateTexture()
NavFrame.DistanceText = NavFrame:CreateFontString()
NAVDIST, CLAMPED, VALIDPOS, TRACKED, SPEED = 191, false, true, 9, 7
C_Navigation = {
  GetFrame = function() return NavFrame end,
  GetDistance = function() return NAVDIST end,
  WasClampedToScreen = function() return CLAMPED end,
  HasValidScreenPosition = function() return VALIDPOS end,
}
C_SuperTrack = {
  GetSuperTrackedQuestID = function() return TRACKED end,
  IsSuperTrackingAnything = function() return TRACKED ~= nil end,
  SetSuperTrackedQuestID = function(id) TRACKED = id end,
}
function GetUnitSpeed(u) return SPEED end
MockUnits.player.level = 5
function UnitLevel(u) return 5 end
'''


@pytest.fixture
def wp(lua):
    # the GO row super-tracks its own pick on login (quest 9, ready, 566 map-yards away) - what a player sees
    boot(lua, MODERN + NAV)
    lua.execute(f"HH_w = HogHealsWaypoint; {W}.Update()")
    return lua


# ------------------------------------------------------------------------------------------------ pure
def test_eta_and_formats(core):
    core.load_addon("HogHeals_Quests")
    assert core.eval(f"{W}.ETA(191, 7)") == pytest.approx(27.28, abs=0.01)
    assert core.eval(f"{W}.ETA(191, 0)") is None and core.eval(f"{W}.ETA(nil, 7)") is None
    assert core.eval(f"{W}.FormatDistance(191.4)") == "191 yd"
    assert core.eval(f"{W}.FormatDistance(1260)") == "1.3k yd"
    assert core.eval(f"{W}.FormatETA(27.3)") == "27s"
    assert core.eval(f"{W}.FormatETA(65)") == "1m 05s"
    assert core.eval(f"{W}.FormatETA(3720)") == "1h 2m"


def test_angle_is_clockwise_from_up(core):
    core.load_addon("HogHeals_Quests")
    assert core.eval(f"{W}.Angle(0, 0, 0, 10)") == pytest.approx(0)
    assert core.eval(f"{W}.Angle(0, 0, 10, 0)") == pytest.approx(1.5708, abs=0.001)
    assert core.eval(f"{W}.Angle(960, 540, 1200, 700)") == pytest.approx(0.9828, abs=0.001)


def test_content_pure(core):
    core.load_addon("HogHeals_Quests")
    c = core.eval(f"{W}.Content({{ title = 'Boars', objectives = {{ {{ done = true }}, {{ done = false }} }} }}, 191, 7, {{}})")
    assert c["title"] == "Boars" and c["detail"] == "191 yd  ·  27s  ·  1/2"
    c = core.eval(f"{W}.Content({{ title = 'Done', complete = true }}, 50, 7, {{}})")
    assert "ready to turn in" in c["detail"] and c["color"][1] == 0.25
    c = core.eval(f"{W}.Content({{ title = 'X' }}, nil, 7, {{ eta = false }})")
    assert c["detail"] == ""


def test_alpha_dims_when_you_are_there(core):
    core.load_addon("HogHeals_Quests")
    assert core.eval(f"{W}.Alpha(5, {{ near = 10 }})") == 0.5
    assert core.eval(f"{W}.Alpha(50, {{ near = 10 }})") == 1
    assert core.eval(f"{W}.Alpha(5, {{ near = 0 }})") == 1


# ------------------------------------------------------------------------------------------------ in the world
def test_anchored_to_the_navigation_frame_with_texts(wp):
    assert wp.eval("HH_w:IsShown()") is True
    assert wp.eval("select(2, HH_w:GetPoint()) == NavFrame") is True
    assert wp.eval(f"{W}.path.nav") == "C_Navigation.GetFrame"
    assert wp.eval(f"{W}.path.distance") == "C_Navigation"
    assert wp.eval("HH_w.title:GetText()") == "Report to Goldshire"
    detail = wp.eval("HH_w.detail:GetText()")
    assert "191 yd" in detail and "27s" in detail and "ready to turn in" in detail
    assert wp.eval("HH_w.marker:IsShown()") is True and wp.eval("HH_w.arrow:IsShown()") is False
    assert errors(wp) == []


def test_blizzard_art_goes_transparent_and_comes_back(wp):
    assert wp.eval("NavFrame.Icon:GetAlpha()") == 0
    assert wp.eval("NavFrame.DistanceText:GetAlpha()") == 0
    wp.execute(f"HogHeals.db.profile.quests.waypoint.hideBlizzard = false; {W}.Update()")
    assert wp.eval("NavFrame.Icon:GetAlpha()") == 1
    wp.execute(f"HogHeals.db.profile.quests.waypoint.hideBlizzard = true; {W}.Update()")
    assert wp.eval("NavFrame.Icon:GetAlpha()") == 0
    wp.execute(f"HogHeals.db.profile.quests.waypoint.enabled = false; {W}.Refresh()")
    assert wp.eval("HH_w:IsShown()") is False
    assert wp.eval("NavFrame.Icon:GetAlpha()") == 1


def test_clamped_shows_the_edge_arrow_turned_toward_the_objective(wp):
    wp.execute(f"CLAMPED = true; {W}.Update()")
    assert wp.eval("HH_w.arrow:IsShown()") is True and wp.eval("HH_w.marker:IsShown()") is False
    assert wp.eval(f"{W}.angle") == pytest.approx(0.9828, abs=0.001)
    wp.execute(f"CLAMPED = false; {W}.Update()")
    assert wp.eval("HH_w.arrow:IsShown()") is False and wp.eval("HH_w.marker:IsShown()") is True
    wp.execute(f"CLAMPED = true; HogHeals.db.profile.quests.waypoint.arrow = false; {W}.Update()")
    assert wp.eval("HH_w.arrow:IsShown()") is False


def test_near_the_objective_the_marker_dims(wp):
    wp.execute(f"NAVDIST = 4; {W}.Update()")
    assert wp.eval("HH_w:GetAlpha()") == 0.5
    wp.execute(f"NAVDIST = 191; {W}.Update()")
    assert wp.eval("HH_w:GetAlpha()") == 1


def test_super_tracking_changed_event_follows_the_new_quest(wp):
    wp.execute('TRACKED = 7; MockFire("SUPER_TRACKING_CHANGED")')
    assert wp.eval("HH_w.title:GetText()") == "Kobold Camp Cleanup"
    assert "3/8" in wp.eval("HH_w.detail:GetText()") or "/" in wp.eval("HH_w.detail:GetText()")
    wp.execute('TRACKED = nil; MockFire("SUPER_TRACKING_CHANGED")')
    assert wp.eval("HH_w:IsShown()") is False
    assert wp.eval("NavFrame.Icon:GetAlpha()") == 1


def test_speed_uses_the_player_when_moving_else_the_last_known_else_a_run(wp):
    assert wp.eval(f"{W}.Speed()") == 7
    wp.execute("SPEED = 14")
    assert wp.eval(f"{W}.Speed()") == 14
    wp.execute("SPEED = 0")
    assert wp.eval(f"{W}.Speed()") == 14
    wp.execute(f"{W}.lastSpeed = nil; GetUnitSpeed = nil")
    assert wp.eval(f"{W}.Speed()") == 7


def test_onupdate_throttle(wp):
    before = wp.eval(f"{W}.seen.updates")
    wp.execute(f"{W}.elapsed = 0; {W}.OnUpdate(HH_w, 0.1)")
    assert wp.eval(f"{W}.seen.updates") == before
    wp.execute(f"{W}.OnUpdate(HH_w, 0.2)")
    assert wp.eval(f"{W}.seen.updates") == before + 1


def test_nav_frame_destroyed_reattaches_to_the_next_one(wp):
    wp.execute('''
      MockFire("NAVIGATION_FRAME_DESTROYED")
      NavFrame = CreateFrame("Frame", "SuperTrackedFrame2", UIParent)
      MockFire("NAVIGATION_FRAME_CREATED")
    ''')
    assert wp.eval("select(2, HH_w:GetPoint()) == NavFrame") is True
    assert wp.eval(f"{W}.seen.attach") >= 2   # once at login, again after the destroy, again for the new frame


# ------------------------------------------------------------------------------------------------ poorer clients
def test_without_c_navigation_distance_falls_back_to_map_yards(lua):
    boot(lua, MODERN + NAV + "C_Navigation = nil")
    lua.execute(f"{W}.Update()")
    # SuperTrackedFrame global still there -> marker drawn; yards from Go.Yards (quest 9: ~566 map yards)
    assert lua.eval(f"{W}.path.nav") == "SuperTrackedFrame"
    assert lua.eval(f"{W}.path.distance") == "map"
    assert "566 yd" in lua.eval("HogHealsWaypoint.detail:GetText()")
    assert errors(lua) == []


def test_without_any_navigation_frame_nothing_is_drawn_and_diag_says_so(lua):
    boot(lua, MODERN + NAV + "C_Navigation = nil; SuperTrackedFrame = nil")
    lua.execute(f"{W}.Update()")
    assert lua.eval("HogHealsWaypoint:IsShown()") is False
    assert lua.eval(f"{W}.path.nav") == "none"
    lines = " ".join(lua.eval(f"{W}.Lines()").values())
    assert "no navigation frame" in lines
    assert errors(lua) == []


def test_without_super_track_api_nothing_is_drawn(lua):
    boot(lua, MODERN + NAV + "C_SuperTrack = nil")
    lua.execute(f"{W}.Update()")
    assert lua.eval("HogHealsWaypoint:IsShown()") is False
    assert errors(lua) == []


# ------------------------------------------------------------------------------------------------ options + diag
def test_options_group_and_diag_lines(wp):
    assert wp.eval("HogHealsQuests.Options.Build().args.waypoint ~= nil")
    assert wp.eval("HogHealsQuests.Options.Build().args.waypoint.args.enabled ~= nil")
    lines = " ".join(wp.eval(f"{W}.Lines()").values())
    assert "C_Navigation.GetFrame" in lines and "Report to Goldshire" in lines and "191 yd" in lines
    p = wp.eval(f"{W}.Probe()")
    assert p["hasGetFrame"] is True and p["tracked"] == 9
