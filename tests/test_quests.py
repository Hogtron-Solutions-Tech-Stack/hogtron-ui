# HogHeals_Quests: quest tracker window + minimap quest pins.
# The Forever client's quest API family is unknown (probe saw C_QuestLog with GetQuestObjectives/GetQuestsOnMap; the
# legacy globals were never probed), so the data layer is exercised against BOTH families.
import math

import pytest

MODERN = '''
QL = {
  { title = "Elwynn Forest", isHeader = true },
  { title = "Kobold Camp Cleanup", questID = 7, level = 2 },
  { title = "Lost Necklace", questID = 8, level = 4 },
  { title = "Report to Goldshire", questID = 9, level = 5 },
}
QObj = {
  [7] = { { text = "Kobold Vermin slain: 3/8", finished = false, numFulfilled = 3, numRequired = 8 } },
  [8] = { { text = "Linen Scrap: 2/6", finished = false, numFulfilled = 2, numRequired = 6 } },
  [9] = {},
}
QDone = { [9] = true }
QWatched = { [7] = 1 }
C_QuestLog = {
  GetNumQuestLogEntries = function() return #QL end,
  GetInfo = function(i) return QL[i] end,
  IsComplete = function(id) return QDone[id] == true end,
  GetQuestObjectives = function(id) return QObj[id] end,
  GetQuestWatchType = function(id) return QWatched[id] end,
  AddQuestWatch = function(id) QWatched[id] = 1 end,
  RemoveQuestWatch = function(id) QWatched[id] = nil end,
  GetQuestsOnMap = function(mapID) return QPoints or {} end,
}
QPoints = { { questID = 7, x = 0.50, y = 0.40 }, { questID = 9, x = 0.9, y = 0.9 } }
C_Map = {
  GetBestMapForUnit = function() return 1429 end,
  GetPlayerMapPosition = function() return { x = 0.50, y = 0.50 } end,
  GetMapWorldSize = function() return 1000, 1000 end,
}
C_Minimap = { GetViewRadius = function() return 200 end }
Minimap:SetSize(140, 140)
function GetRealZoneText() return "Elwynn Forest" end
'''

LEGACY = '''
LQ = {
  { "Durotar", 0, nil, true },
  { "Vile Familiars", 3, nil, false, nil, nil, nil, 792 },
  { "Sarkoth", 4, nil, false, nil, 1, nil, 790 },
}
LObj = { [2] = { { "Vile Familiar slain: 4/8", "monster", false } }, [3] = { { "Sarkoth's Mangled Claw: 1/1", "item", true } } }
LWatch = { [3] = true }
function GetNumQuestLogEntries() return #LQ, #LQ end
function GetQuestLogTitle(i) local q = LQ[i] if not q then return nil end return q[1], q[2], q[3], q[4], nil, q[6], nil, q[8] end
function GetNumQuestLeaderBoards(i) return LObj[i] and #LObj[i] or 0 end
function GetQuestLogLeaderBoard(j, i) local o = LObj[i][j] return o[1], o[2], o[3] end
function IsQuestWatched(i) return LWatch[i] == true end
function AddQuestWatch(i) LWatch[i] = true end
function RemoveQuestWatch(i) LWatch[i] = nil end
'''


def boot(lua, api):
    lua.execute(api)
    for a in ("HogHeals", "HogHeals_Quests"):
        lua.load_addon(a)
    lua.player_login()
    lua.execute('wipe(HogHeals.errors)')
    return lua


@pytest.fixture
def modern(lua):
    boot(lua, MODERN)
    # pin geometry tests: pins on (default off since 2026-09-22), round 140 px minimap as the pin maths was written for
    lua.execute("HogHeals.db.profile.quests.minimap.enabled = true; GetMinimapShape = nil; Minimap:SetSize(140, 140)")
    return lua


@pytest.fixture
def legacy(lua):
    return boot(lua, LEGACY)


def errors(lua):
    return [e["msg"] for e in lua.eval('HogHeals.errors').values()]


def test_modern_api_list(modern):
    modern.execute('L = HogHealsQuests.Data.List()')
    assert modern.eval('#L') == 3
    assert modern.eval('L[1].title') == "Kobold Camp Cleanup" and modern.eval('L[1].zone') == "Elwynn Forest"
    assert modern.eval('L[1].watched') is True and modern.eval('L[2].watched') is False
    assert modern.eval('L[1].objectives[1].name') == "Kobold Vermin"
    assert modern.eval('L[1].objectives[1].have') == 3 and modern.eval('L[1].objectives[1].need') == 8
    assert modern.eval('L[3].complete') is True
    assert modern.eval('HogHealsQuests.Data.path.info') == "C_QuestLog.GetInfo"


def test_legacy_api_list(legacy):
    legacy.execute('L = HogHealsQuests.Data.List()')
    assert legacy.eval('#L') == 2
    assert legacy.eval('L[1].title') == "Vile Familiars" and legacy.eval('L[1].id') == 792
    assert legacy.eval('L[1].objectives[1].name') == "Vile Familiar"
    assert legacy.eval('L[2].complete') is True and legacy.eval('L[2].watched') is True
    assert legacy.eval('HogHealsQuests.Data.path.info') == "GetQuestLogTitle"
    assert legacy.eval('HogHealsQuests.Data.path.objectives') == "GetQuestLogLeaderBoard"


def test_no_quest_api_is_empty_not_an_error(lua):
    boot(lua, 'C_QuestLog = nil')
    assert lua.eval('#HogHealsQuests.Data.List()') == 0
    assert lua.eval('HogHealsQuests.Data.Available()') is False
    assert lua.eval('HogHealsQuestTracker.empty._text') == "This client does not share the quest log"
    assert errors(lua) == []


@pytest.mark.parametrize("text,name,have,need", [
    ("Kobold Vermin slain: 3/8", "Kobold Vermin", 3, 8),
    ("3/8 Kobold Vermin slain", "Kobold Vermin", 3, 8),
    ("Linen Scrap: 2/6", "Linen Scrap", 2, 6),
    ("Speak to Marshal Dughan", "Speak to Marshal Dughan", None, None),
])
def test_parse_objective(lua, text, name, have, need):
    boot(lua, MODERN)
    r = lua.eval(f'{{HogHealsQuests.Data.ParseObjective("{text}")}}')
    assert r[1] == name and r[2] == have and r[3] == need


def test_tracker_shows_watched_then_falls_back_to_all(modern):
    t = 'HogHealsQuests.Tracker'
    modern.execute(f'{t}.Update()')
    assert modern.eval(f'{t}.shownCount') == 1
    assert "Kobold Camp Cleanup" in modern.eval(f'{t}.titles[1].label._text')
    assert modern.eval(f'{t}.lines[1]._text') == "- Kobold Vermin slain: 3/8"
    modern.execute(f'wipe(QWatched); {t}.Update()')
    assert modern.eval(f'{t}.shownCount') == 3
    assert modern.eval('HogHealsQuestTracker.title._text').startswith("All quests")
    # ready-to-turn-in first
    assert "Report to Goldshire" in modern.eval(f'{t}.titles[1].label._text')
    assert errors(modern) == []


def test_tracker_click_opens_and_right_click_toggles_watch(modern):
    modern.execute('''
      OPENED = nil
      function QuestMapFrame_OpenToQuestDetails(id) OPENED = id end
      HogHealsQuests.Tracker.Update()
      HogHealsQuests.Tracker.titles[1]:Click("LeftButton")
    ''')
    assert modern.eval('OPENED') == 7
    modern.execute('HogHealsQuests.Tracker.titles[1]:Click("RightButton")')   # no menu system in the mock -> the old toggle
    assert modern.eval('QWatched[7]') is None


def test_tracker_collapse_and_mode_cycle(modern):
    modern.execute('HogHealsQuestTracker.header:Click("LeftButton")')
    assert modern.eval('HogHeals.db.profile.quests.tracker.collapsed') is True
    assert modern.eval('HogHealsQuestTracker._height') == modern.eval('HogHealsQuestTracker.header._height')
    modern.execute('HogHealsQuestTracker.header:Click("RightButton")')
    assert modern.eval('HogHeals.db.profile.quests.tracker.mode') == "zone"


def test_tracker_caps_height_and_says_how_many_more(modern):
    modern.execute('''
      for i = 1, 30 do QL[#QL + 1] = { title = "Q" .. i, questID = 100 + i, level = 5 } QObj[100 + i] = { { text = "Thing: 0/5" }, { text = "Other: 0/5" } } end
      HogHeals.db.profile.quests.tracker.mode = "all"
      HogHeals.db.profile.quests.tracker.fill = false
      HogHeals.db.profile.quests.tracker.maxHeight = 200
      HogHealsQuests.Tracker.Update()
    ''')
    assert modern.eval('HogHealsQuests.Tracker.moreCount') > 0
    assert modern.eval('HogHealsQuestTracker._height') <= 200 + 20 + 8 + 20


def test_unlock_shows_a_resize_grip_and_dragging_it_sets_width_and_the_fill_gap(modern):
    modern.execute('''
      HogHeals.db.profile.quests.tracker.scale = 1
      HogHealsQuestTracker.GetTop = function() return 900 end
      HogHeals:SlashCommand("lock")        -- the default profile is unlocked, so the grip starts visible
    ''')
    assert modern.eval('HogHealsQuestTracker.grip:IsShown()') is False
    assert modern.eval('HogHealsQuestTracker:GetScript("OnMouseWheel") ~= nil')
    assert modern.eval('HogHealsQuestTracker._calls.EnableMouse') >= 1            # takes the wheel on this client
    assert modern.eval('HogHealsQuests.Tracker.titles[1]:GetScript("OnMouseWheel") ~= nil')
    modern.execute('HogHeals:SlashCommand("unlock")')
    assert modern.eval('HogHealsQuestTracker.grip:IsShown()') is True
    assert modern.eval('HogHealsQuestTracker.edges[1]._color[2]') == pytest.approx(0.83)   # cyan while unlocked
    # the player drags the corner: the frame is 320 wide and its bottom sits 140 px above the screen edge
    modern.execute('''
      HogHealsQuestTracker.grip:GetScript("OnMouseDown")(HogHealsQuestTracker.grip)
      HogHealsQuestTracker._width, HogHealsQuestTracker._height = 320, 700
      HogHealsQuestTracker.GetBottom = function() return 140 end
      HogHealsQuests.Tracker.Update()      -- a quest update mid-drag must not snap the size back
    ''')
    assert modern.eval('HogHealsQuestTracker._width') == 320
    modern.execute('HogHealsQuestTracker.grip:GetScript("OnMouseUp")(HogHealsQuestTracker.grip)')
    assert modern.eval('HogHeals.db.profile.quests.tracker.width') == 320
    assert modern.eval('HogHealsQuests.Tracker.sizing') is None
    # the drag means "this tall": fill off, fixed height, and the panel IS that tall even with three short quests
    d = modern.eval('HogHeals.db.profile.quests.tracker')
    assert d["fill"] is False and d["fixedHeight"] is True and d["maxHeight"] == 700 - 21 - 8
    assert modern.eval('HogHealsQuestTracker._height') == 700
    assert modern.eval('HogHealsQuestTracker._width') == 320
    # a second drag re-sizes again
    modern.execute('''
      HogHealsQuestTracker.grip:GetScript("OnMouseDown")(HogHealsQuestTracker.grip)
      HogHealsQuestTracker._height = 500
      HogHealsQuestTracker.grip:GetScript("OnMouseUp")(HogHealsQuestTracker.grip)
    ''')
    assert modern.eval('HogHeals.db.profile.quests.tracker.maxHeight') == 500 - 21 - 8
    assert modern.eval('HogHealsQuestTracker._height') == 500
    # fixed height off: back to hugging the content
    modern.execute('HogHeals.db.profile.quests.tracker.fixedHeight = false; HogHealsQuests.Tracker.Update()')
    assert modern.eval('HogHealsQuestTracker._height') < 300
    modern.execute('HogHeals:SlashCommand("lock")')
    assert modern.eval('HogHealsQuestTracker.grip:IsShown()') is False
    assert modern.eval('HogHealsQuestTracker.edges[1]._color[2]') == pytest.approx(0.20)
    assert errors(modern) == []


def test_tracker_fills_down_to_the_screen_bottom_and_the_wheel_scrolls(modern):
    # Sean 2026-10-01: no "+7 more" - run to the bottom of the screen, scroll the rest.
    modern.execute('''
      for i = 1, 30 do QL[#QL + 1] = { title = "Q" .. i, questID = 100 + i, level = 5 } QObj[100 + i] = { { text = "Thing: 0/5" }, { text = "Other: 0/5" } } end
      local d = HogHeals.db.profile.quests.tracker
      d.mode, d.fontSize = "all", 13
      if HogHeals.db.profile.quests.go then HogHeals.db.profile.quests.go.enabled = false end   -- the GO row (Go.lua) would take two lines
      HogHealsQuestTracker.GetTop = function() return 900 end     -- panel top 900 px above the screen's bottom edge
      HogHealsQuests.Tracker.Update()
    ''')
    # fill: 900 - 20 margin - 21 header - 8 = 851 px of list; the 3 base quests are 39 px each (one line), the 30 added
    # ones 19 + 32 + 4 = 55 px -> 3 + 13 = 16 fit
    assert modern.eval('HogHealsQuests.Tracker.shownCount') == 16
    assert modern.eval('HogHealsQuestTracker._height') <= 900 - 20
    hint = modern.eval('HogHealsQuests.Tracker.lines[#HogHealsQuests.Tracker.lines]._text')
    assert hint.startswith("scroll:") and "below" in hint and "above" not in hint
    first = modern.eval('HogHealsQuests.Tracker.titles[1].label._text')
    # wheel up at the top: nothing; wheel down: the list moves one quest
    modern.execute('HogHealsQuestTracker:GetScript("OnMouseWheel")(HogHealsQuestTracker, 1)')
    assert modern.eval('HogHealsQuests.Tracker.offset') == 0
    modern.execute('HogHealsQuestTracker:GetScript("OnMouseWheel")(HogHealsQuestTracker, -1)')
    assert modern.eval('HogHealsQuests.Tracker.offset') == 1
    assert modern.eval('HogHealsQuests.Tracker.titles[1].label._text') != first
    assert "1 above" in modern.eval('HogHealsQuests.Tracker.lines[#HogHealsQuests.Tracker.lines]._text')
    # all the way down: stops at the end, never past it
    for _ in range(40):
        modern.execute('HogHealsQuestTracker:GetScript("OnMouseWheel")(HogHealsQuestTracker, -1)')
    assert modern.eval('HogHealsQuests.Tracker.moreCount') == 0
    assert modern.eval('HogHealsQuests.Tracker.offset') == 33 - 15     # 33 quests; once scrolled only 55 px quests show, 15 fit
    # the log shrinks under the scroll position: clamped, no error
    modern.execute('for i = 1, 25 do table.remove(QL) end; HogHealsQuests.Tracker.Update()')
    assert modern.eval('HogHealsQuests.Tracker.offset') <= 7
    # a client that cannot say where the top is falls back to the slider
    modern.execute('HogHealsQuestTracker.GetTop = function() return 0 end; HogHeals.db.profile.quests.tracker.maxHeight = 200; HogHealsQuests.Tracker.offset = 0; HogHealsQuests.Tracker.Update()')
    assert modern.eval('HogHealsQuestTracker._height') <= 200 + 20 + 8 + 20
    assert errors(modern) == []


def test_blizzard_tracker_hidden_only_when_we_can_read_the_log(lua):
    lua.execute('ObjectiveTrackerFrame = CreateFrame("Frame", "ObjectiveTrackerFrame", UIParent)')
    boot(lua, 'C_QuestLog = nil')
    assert lua.eval('ObjectiveTrackerFrame:GetParent() == UIParent')


def test_blizzard_tracker_hidden_when_ours_works(lua):
    lua.execute('ObjectiveTrackerFrame = CreateFrame("Frame", "ObjectiveTrackerFrame", UIParent)')
    boot(lua, MODERN)
    assert lua.eval('ObjectiveTrackerFrame:GetParent() == HogHealsHiddenParent')


# ---------------------------------------------------------------------------------------------- minimap geometry
def test_place_north_is_up_without_rotation(lua):
    boot(lua, MODERN)
    x, y, edge = lua.eval('{HogHealsQuests.Pins.Place(0, -100, 200, 70, nil, false)}').values()
    assert x == pytest.approx(0) and y == pytest.approx(35) and edge is False


def test_place_rotating_minimap_puts_facing_direction_up(lua):
    boot(lua, MODERN)
    # quest due west, player facing west (pi/2 counter-clockwise from north) -> pin straight up
    x, y, _ = lua.eval(f'{{HogHealsQuests.Pins.Place(-100, 0, 200, 70, {math.pi / 2}, false)}}').values()
    assert x == pytest.approx(0, abs=1e-9) and y == pytest.approx(35)


def test_place_far_pin_clamps_to_rim(lua):
    boot(lua, MODERN)
    x, y, edge = lua.eval('{HogHealsQuests.Pins.Place(1000, 0, 200, 70, nil, false)}').values()
    assert edge is True and x == pytest.approx(70) and y == pytest.approx(0)


def test_pins_placed_from_client_points(modern):
    n = modern.eval('HogHealsQuests.Pins.Update()')
    assert n == 2
    p1 = 'HogHealsQuests.Pins.pool[1]'
    # quest 7: 0.1 of a 1000-yard map north = 100 yd, radius 200, half width 70 - pin size (16) / 3
    pt = modern.eval(f'{p1}._points[1]')
    assert pt[4] == pytest.approx(0) and pt[5] == pytest.approx((70 - 16 / 3) / 2)
    assert modern.eval(f'{p1}.icon._texture').endswith("quest_open")
    # quest 9 is complete and far away: turn-in icon on the rim, dimmed
    # quest 9 is complete and far away: a rim ARROW turned toward it (south-east of the player), dimmed
    p2 = 'HogHealsQuests.Pins.pool[2]'
    assert modern.eval(f'{p2}.arrow._texture').endswith("quest_arrow")
    assert modern.eval(f'{p2}.arrow:IsShown()') is True and modern.eval(f'{p2}.icon:IsShown()') is False
    assert modern.eval(f'{p2}.arrow._last.SetRotation[1]') == pytest.approx(math.atan2(-1, 1) - math.pi / 2)
    assert modern.eval(f'{p2}._alpha') == pytest.approx(0.6)


def test_pins_hide_without_position(modern):
    modern.execute('HogHealsQuests.Pins.Update(); C_Map.GetPlayerMapPosition = function() return nil end')
    assert modern.eval('HogHealsQuests.Pins.Update()') == 0
    assert modern.eval('HogHealsQuests.Pins.pool[1]:IsShown()') is False
    assert modern.eval('HogHealsQuests.Pins.why') == "no player position"


def test_map_size_from_world_corners_when_no_world_size_api(modern):
    modern.execute('''
      C_Map.GetMapWorldSize = nil
      C_Map.GetWorldPosFromMapPos = function(_, v) return 0, { x = 500 - v.y * 800, y = 300 - v.x * 1200 } end
    ''')
    w, h = modern.eval('{HogHealsQuests.Pins.MapSize(55)}').values()
    assert w == pytest.approx(1200) and h == pytest.approx(800)


def test_watched_only_filter(modern):
    modern.execute('HogHeals.db.profile.quests.minimap.watchedOnly = true; HogHealsQuests.Data.List()')
    assert modern.eval('HogHealsQuests.Pins.Update()') == 1


def test_probe_and_slash_run_clean(modern):
    modern.execute('HogHeals:SlashCommand("questdiag"); HogHeals:SlashCommand("quests"); HogHeals:SlashCommand("quests")')
    q = modern.eval('HogHeals.db.global.diag.quests')
    assert q["data"]["quests"] == 3 and "GetQuestObjectives" in q["data"]["C_QuestLog"]
    assert q["minimap"]["points"] == 2
    assert errors(modern) == []


def test_unknown_events_do_not_break_enable(lua):
    lua.execute('MockUnknownEvents.QUEST_WATCH_UPDATE = true; MockUnknownEvents.UNIT_QUEST_LOG_CHANGED = true')
    boot(lua, MODERN)
    assert lua.eval('HogHealsQuestTracker:IsShown()') is True
    assert lua.eval('HogHealsQuests.module.unknown[1]') == "QUEST_WATCH_UPDATE"
    assert errors(lua) == []


def test_quest_events_repaint(modern):
    modern.execute('QObj[7][1] = { text = "Kobold Vermin slain: 4/8", numFulfilled = 4, numRequired = 8 }; MockFire("QUEST_LOG_UPDATE"); MockAdvance(1)')
    assert modern.eval('HogHealsQuests.Tracker.lines[1]._text') == "- Kobold Vermin slain: 4/8"


def test_more_line_stays_inside_the_panel_and_scale_applies(modern):
    modern.execute('''
      for i = 1, 30 do QL[#QL + 1] = { title = "Q" .. i, questID = 100 + i, level = 5 } QObj[100 + i] = { { text = "Thing: 0/5" } } end
      local d = HogHeals.db.profile.quests.tracker
      d.mode, d.maxHeight, d.scale, d.fontSize, d.fill = "all", 200, 1.5, 24, false
      HogHealsQuests.Tracker.Update()
    ''')
    i = modern.eval('#HogHealsQuests.Tracker.lines')
    assert modern.eval(f'HogHealsQuests.Tracker.lines[{i}]._text').startswith("scroll:")
    assert modern.eval(f'HogHealsQuests.Tracker.lines[{i}]._points[2][1]') == "RIGHT"
    assert modern.eval('HogHealsQuestTracker._calls.SetScale') >= 1
    assert modern.eval('HogHealsQuestTracker._last.SetScale[1]') == 1.5
    assert modern.eval('HogHealsQuestTracker.header._height') == 32


def test_quest_on_another_map_gets_its_next_waypoint_here(modern):
    modern.execute("""
      QL[#QL + 1] = { title = "Delivery to Silverpine Forest", questID = 50, level = 10 }
      QObj[50] = {}; QDone[50] = true
      C_QuestLog.GetNextWaypointForMap = function(id, map) if id == 50 then return 0.52, 0.55 end end
      C_QuestLog.GetNextWaypointText = function(id) return "Travel to Silverpine Forest" end
      HogHealsQuests.Data.List()
    """)
    pts = modern.eval('HogHealsQuests.Data.PointsOnMap(1429)')
    wp = [p for p in pts.values() if p["id"] == 50]
    assert len(wp) == 1 and wp[0]["waypoint"] is True and wp[0]["text"] == "Travel to Silverpine Forest"
    ids = [p["id"] for p in pts.values()]
    assert ids.count(7) == 1                                  # quests with a real point are not doubled
    assert modern.eval('HogHealsQuests.Pins.Update()') == 3
    n = [i for i in range(1, 4) if modern.eval(f'HogHealsQuests.Pins.pool[{i}].quest.id') == 50][0]
    assert modern.eval(f'HogHealsQuests.Pins.pool[{n}].waypoint') == "Next step: Travel to Silverpine Forest"


def test_blizzard_tracker_loading_after_us_is_still_hidden_and_stays_hidden(lua):
    boot(lua, MODERN)
    lua.execute("""
      ObjectiveTrackerFrame = CreateFrame("Frame", "ObjectiveTrackerFrame", UIParent)
      MockFire("ADDON_LOADED", "Blizzard_ObjectiveTracker")
    """)
    assert lua.eval('ObjectiveTrackerFrame:GetParent() == HogHealsHiddenParent')
    assert lua.eval('ObjectiveTrackerFrame:IsShown()') is False
    lua.execute('ObjectiveTrackerFrame:SetParent(UIParent); ObjectiveTrackerFrame:Show()')   # Blizzard puts it back
    assert lua.eval('ObjectiveTrackerFrame:GetParent() == HogHealsHiddenParent')
    assert lua.eval('ObjectiveTrackerFrame:IsShown()') is False
    assert errors(lua) == []


def test_tracker_hangs_under_the_minimap_box_until_dragged_away(modern):
    # Sean 2026-10-01: "should always be right below the minimap by default - currently overlapping every reload"
    p = modern.eval('HogHealsQuestTracker._points[1]')
    assert p[1] == "TOPRIGHT" and p[3] == "BOTTOMRIGHT" and p[5] == -8
    assert modern.eval('HogHealsQuestTracker._points[1][2] == Minimap')          # no cluster in this mock: the map itself
    assert modern.eval('HogHealsQuests.Tracker.anchoredTo') == "minimap"
    # a modern client has the Edit Mode box: hang under that instead
    modern.execute('MinimapCluster = CreateFrame("Frame", "MinimapCluster", UIParent); HogHealsQuests.Tracker.Refresh()')
    assert modern.eval('HogHealsQuestTracker._points[1][2] == MinimapCluster')
    # dragging the header detaches: the dropped spot is kept and used from then on
    modern.execute('''
      HogHealsQuestTracker.header:GetScript("OnDragStart")()
      HogHealsQuestTracker:ClearAllPoints(); HogHealsQuestTracker:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -300)
      HogHealsQuestTracker.header:GetScript("OnDragStop")()
    ''')
    d = modern.eval('HogHeals.db.profile.quests.tracker')
    assert d["followMinimap"] is False and d["point"] == "TOPLEFT" and d["x"] == 40 and d["y"] == -300
    modern.execute('HogHealsQuests.Tracker.Refresh()')
    assert modern.eval('HogHealsQuestTracker._points[1][2] == UIParent') and modern.eval('HogHealsQuestTracker._points[1][4]') == 40
    assert modern.eval('HogHealsQuests.Tracker.anchoredTo') == "free"
    # the option puts it back under the minimap
    modern.execute('HogHeals.OptionsTable().args.Quests.args.tracker.args.followMinimap.set({}, true)')
    assert modern.eval('HogHealsQuestTracker._points[1][2] == MinimapCluster')
    modern.execute('HogHeals.OptionsTable().args.Quests.args.tracker.args.gap.set({}, 20)')
    assert modern.eval('HogHealsQuestTracker._points[1][5]') == -20
    assert errors(modern) == []


def test_tracker_drags_without_unlock_unless_locked(modern):
    assert modern.eval('HogHeals.db.profile.locked') is True          # HogHeals frames locked (default)
    modern.execute('HogHealsQuestTracker.header:GetScript("OnDragStart")()')
    assert modern.eval('HogHealsQuestTracker._moving') is True
    modern.execute("""
      HogHealsQuestTracker:StopMovingOrSizing()
      HogHeals.db.profile.quests.tracker.lockPosition = true
      HogHealsQuestTracker.header:GetScript("OnDragStart")()
    """)
    assert modern.eval('HogHealsQuestTracker._moving') is False


def test_accepted_quest_is_watched_automatically(modern):
    modern.execute('wipe(QWatched); MockFire("QUEST_ACCEPTED", 3, 8); MockAdvance(0.6)')
    assert modern.eval('QWatched[8]') == 1
    modern.execute('HogHeals.db.profile.quests.tracker.autoTrack = false; MockFire("QUEST_ACCEPTED", 4, 9); MockAdvance(0.6)')
    assert modern.eval('QWatched[9]') is None
