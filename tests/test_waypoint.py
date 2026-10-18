# Waypoint (HogTron_Quests/Waypoint.lua): the super-tracked quest marked in the world, anchored to Blizzard's
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
    core.load_addon("HogTron_Quests")
    assert core.eval(f"{W}.ETA(191, 7)") == pytest.approx(27.28, abs=0.01)
    assert core.eval(f"{W}.ETA(191, 0)") is None and core.eval(f"{W}.ETA(nil, 7)") is None
    assert core.eval(f"{W}.FormatDistance(191.4)") == "191 yd"
    assert core.eval(f"{W}.FormatDistance(1260)") == "1.3k yd"
    assert core.eval(f"{W}.FormatETA(27.3)") == "27s"
    assert core.eval(f"{W}.FormatETA(65)") == "1m 05s"
    assert core.eval(f"{W}.FormatETA(3720)") == "1h 2m"


def test_angle_is_clockwise_from_up(core):
    core.load_addon("HogTron_Quests")
    assert core.eval(f"{W}.Angle(0, 0, 0, 10)") == pytest.approx(0)
    assert core.eval(f"{W}.Angle(0, 0, 10, 0)") == pytest.approx(1.5708, abs=0.001)
    assert core.eval(f"{W}.Angle(960, 540, 1200, 700)") == pytest.approx(0.9828, abs=0.001)


def test_content_pure(core):
    core.load_addon("HogTron_Quests")
    c = core.eval(f"{W}.Content({{ title = 'Boars', objectives = {{ {{ done = true }}, {{ done = false }} }} }}, 191, 7, {{}})")
    assert c["title"] == "Boars" and c["detail"] == "191 yd  ·  27s  ·  1/2"
    c = core.eval(f"{W}.Content({{ title = 'Done', complete = true }}, 50, 7, {{}})")
    assert "ready to turn in" in c["detail"] and c["color"][1] == 0.25
    c = core.eval(f"{W}.Content({{ title = 'X' }}, nil, 7, {{ eta = false }})")
    assert c["detail"] == ""


def test_alpha_dims_when_you_are_there(core):
    core.load_addon("HogTron_Quests")
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
    assert wp.eval("HH_w.beam:IsShown()") is True and wp.eval("HH_w.marker:IsShown()") is False and wp.eval("HH_w.arrow:IsShown()") is False   # the beam by default (2026-10-17)
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
    assert wp.eval("HH_w.arrow:IsShown()") is True and wp.eval("HH_w.marker:IsShown()") is False and wp.eval("HH_w.beam:IsShown()") is False   # off-screen: the arrow only
    assert wp.eval(f"{W}.angle") == pytest.approx(0.9828, abs=0.001)
    wp.execute(f"CLAMPED = false; {W}.Update()")
    assert wp.eval("HH_w.arrow:IsShown()") is False and wp.eval("HH_w.beam:IsShown()") is True
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



# ---------------------------------------------------------------- the beam (Sean 2026-10-17)
# "put a glow ... or like a beam of light coming down rather than this diamond ... it looks kind of cheap"
def test_beam_breathes_fades_up_close_and_texts_sit_under_its_foot(wp):
    wp.execute("HogHealsQuests.Waypoint.Update()")
    assert wp.eval("HH_w.beam:IsShown()") is True and wp.eval("HH_w.base:IsShown()") is False   # no ring on the NPC
    assert wp.eval("HH_w.beam._blend") == "ADD"
    assert wp.eval("HH_w.title._points[1][1]") == "TOP" and wp.eval("HH_w.title._points[1][5]") < 0   # under the foot
    W = "HogHealsQuests.Waypoint"
    wp.execute(f"{W}.OnUpdate(nil, 0.1)")
    a1 = wp.eval(f"{W}.lastBeam")
    wp.execute(f"{W}.OnUpdate(nil, 0.5)")
    assert wp.eval(f"{W}.lastBeam") != a1                                         # it breathes
    assert wp.eval(f"{W}.BeamAlpha(4, {{}})") == 0                              # close: no beam at all
    assert wp.eval(f"{W}.BeamAlpha(20, {{}})") == 0.5                           # fading in from 15 yd
    assert wp.eval(f"{W}.BeamAlpha(60, {{}})") == 1
    assert 0.7 <= wp.eval(f"{W}.Breath(0.55)") <= 1.0


def test_the_diamond_is_still_a_choice(wp):
    wp.execute('HogHeals.db.profile.quests.waypoint.style = "diamond"; HogHealsQuests.Waypoint.Update()')
    assert wp.eval("HH_w.marker:IsShown()") is True and wp.eval("HH_w.beam:IsShown()") is False
    assert wp.eval("HH_w.title._points[1][1]") == "BOTTOM"                      # name back above the marker



# ---------------------------------------------------------------- beam v2 (Sean 2026-10-17, second look)
# "start from above the question mark, so it doesn't interrupt anything ... really, really tall ... only from a certain
# distance"
def test_the_beam_starts_above_the_question_mark_at_any_distance_and_is_tall(wp):
    W_ = "HogHealsQuests.Waypoint"
    assert wp.eval(f"{W_}.BeamGap(25)") == 50                                     # measured in game: ~50 px at 25 yd
    assert wp.eval(f"{W_}.BeamGap(10)") > wp.eval(f"{W_}.BeamGap(40)")            # closer = the head is taller on screen
    assert wp.eval(f"{W_}.BeamGap(2)") == 240 and wp.eval(f"{W_}.BeamGap(500)") == 40
    wp.execute(f"{W_}.Update()")                                                   # the GO pick: 566 map-yards away
    p = wp.eval("HH_w.beam._points[1]")
    assert p[1] == "BOTTOM" and p[3] == "CENTER" and p[5] >= 40                  # its foot well above the point
    assert wp.eval("HH_w.beam._height") == 900


def test_inside_the_beam_distance_there_is_no_beam(wp):
    wp.execute("HogHeals.db.profile.quests.waypoint.beamFrom = 1000; HogHealsQuests.Waypoint.Update()")
    assert wp.eval("HH_w.beam:IsShown()") is False and wp.eval("HH_w.arrow:IsShown()") is False



# ---------------------------------------------------------------- blocked view (Sean 2026-10-17, v3)
# "Can we hide the beam behind objects so it only appears above them if they are blocked?" - no depth for addons; the
# client's own occluded flag (retail C_Navigation.GetTargetState) lifts the beam into the sky instead.
def test_a_blocked_target_lifts_the_beam_into_the_sky(wp):
    W_ = "HogHealsQuests.Waypoint"
    wp.execute(f"{W_}.Update()")
    base = wp.eval("HH_w.beam._points[1][5]")
    wp.execute(f"""Enum = Enum or {{}}; Enum.NavigationState = {{ Invalid = 0, Occluded = 1, InRange = 2, Disabled = 3 }}
      HH_state = 1; C_Navigation.GetTargetState = function() return HH_state end; {W_}.Update()""")
    assert wp.eval("HH_w.beam._points[1][5]") == base + wp.eval(f"{W_}.OCCLUDED_LIFT")
    assert wp.eval(f"{W_}.blocked") is True and wp.eval(f"{W_}.beamTarget") < 1
    assert wp.eval("HogHeals.db.global.diag.waypointOcclusion.api") == "C_Navigation.GetTargetState"
    wp.execute(f"HH_state = 2; {W_}.Update()")                                   # in view again
    assert wp.eval("HH_w.beam._points[1][5]") == base and wp.eval(f"{W_}.blocked") is False


def test_a_client_that_cannot_say_changes_nothing_and_says_so(wp):
    W_ = "HogHealsQuests.Waypoint"
    wp.execute(f"C_Navigation.GetTargetState = nil; {W_}.Update()")
    assert wp.eval(f"{W_}.blocked") is False and wp.eval(f"{W_}.path.occlusion") == "none"
    assert any("blocked-view lift: none" in l for l in wp.eval(f"{W_}.Lines()").values())



# ---------------------------------------------------------------- no usable target (Sean 2026-10-17)
# "it says it's ready to turn in, but anywhere I turn, the quest stays in the middle of my screen" - no distance, no
# valid screen spot, the client's frame parked mid-screen: nothing is drawn in the world then.
def test_no_position_and_no_distance_draws_nothing_in_the_world(wp):
    W_ = "HogHealsQuests.Waypoint"
    wp.execute(f"VALIDPOS = false; NAVDIST = nil; C_Navigation.GetDistance = function() return nil end; {W_}.Distance = function() return nil end; {W_}.Update()")
    assert wp.eval("HH_w:IsShown()") is False
    assert "no distance" in wp.eval(f"{W_}.noTarget")
    assert any("nothing drawn in the world" in l for l in wp.eval(f"{W_}.Lines()").values())


def test_an_invalid_target_state_draws_nothing(wp):
    W_ = "HogHealsQuests.Waypoint"
    wp.execute(f"C_Navigation.GetTargetState = function() return 0 end; {W_}.Update()")
    assert wp.eval("HH_w:IsShown()") is False and wp.eval(f"{W_}.noTarget") == "client: invalid target"
    wp.execute(f"C_Navigation.GetTargetState = function() return 2 end; {W_}.Update()")   # in range again
    assert wp.eval("HH_w:IsShown()") is True and wp.eval(f"{W_}.noTarget") is None


def test_off_screen_with_the_frame_parked_mid_screen_draws_nothing(wp):
    W_ = "HogHealsQuests.Waypoint"
    wp.execute(f"""VALIDPOS = false
      local nav = {W_}.NavFrame()
      function nav:GetCenter() return GetScreenWidth() / 2, GetScreenHeight() / 2 end
      {W_}.Update()""")
    assert wp.eval("HH_w:IsShown()") is False and "parked mid-screen" in wp.eval(f"{W_}.noTarget")


# ---------------------------------------------------------------- what the marker did, saved (Sean 2026-10-17)
# "I dont see the quest beam anymore" - and the save held no trace of why. Every outcome change is recorded.
def test_each_outcome_change_is_saved_with_the_clients_answers(wp):
    W_ = "HogHealsQuests.Waypoint"
    wp.execute(f"""Enum = Enum or {{}}; Enum.NavigationState = {{ Invalid = 0, Occluded = 1, InRange = 2, Disabled = 3 }}
      HH_state = 2; C_Navigation.GetTargetState = function() return HH_state end
      {W_}.lastOutcome = nil; HogHeals.db.global.diag.waypoint = nil; {W_}.Update()""")
    rec = wp.eval("HogHeals.db.global.diag.waypoint")
    assert rec["outcome"] == "beam" and rec["state"] == "2" and rec["validScreen"] == "yes" and rec["quest"] == "9"
    assert "Invalid=0" in rec["enum"] and "InRange=2" in rec["enum"]
    wp.execute(f"for i = 1, 5 do {W_}.Update() end")                              # unchanged: no new history lines
    assert len(wp.eval("HogHeals.db.global.diag.waypoint.history")) == 1
    wp.execute(f"HH_state = 0; {W_}.Update()")
    rec = wp.eval("HogHeals.db.global.diag.waypoint")
    assert rec["outcome"] == "hidden: client: invalid target" and rec["state"] == "0"
    assert len(rec["history"]) == 2
    wp.execute(f"TRACKED = nil; {W_}.Update()")
    assert wp.eval("HogHeals.db.global.diag.waypoint.outcome") == "nothing super-tracked"
    assert any("last outcome: nothing super-tracked" in l for l in wp.eval(f"{W_}.Lines()").values())
    assert errors(wp) == []


def test_a_secret_target_state_is_written_as_secret(wp):
    W_ = "HogHealsQuests.Waypoint"
    wp.execute(f"""MockSetSecrets(true); C_Navigation.GetTargetState = function() return MockSecret(2) end
      {W_}.lastOutcome = nil; {W_}.Update()""")
    assert wp.eval("HogHeals.db.global.diag.waypoint.state") == "secret"
    assert errors(wp) == []
