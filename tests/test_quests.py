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
    return boot(lua, MODERN)


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
    modern.execute('HogHealsQuests.Tracker.titles[1]:Click("RightButton")')
    assert modern.eval('QWatched[7]') is None


def test_tracker_collapse_and_mode_cycle(modern):
    modern.execute('HogHealsQuestTracker.header:Click("LeftButton")')
    assert modern.eval('HogHeals.db.profile.quests.tracker.collapsed') is True
    assert modern.eval('HogHealsQuestTracker._height') == 20
    modern.execute('HogHealsQuestTracker.header:Click("RightButton")')
    assert modern.eval('HogHeals.db.profile.quests.tracker.mode') == "zone"


def test_tracker_caps_height_and_says_how_many_more(modern):
    modern.execute('''
      for i = 1, 30 do QL[#QL + 1] = { title = "Q" .. i, questID = 100 + i, level = 5 } QObj[100 + i] = { { text = "Thing: 0/5" }, { text = "Other: 0/5" } } end
      HogHeals.db.profile.quests.tracker.mode = "all"
      HogHeals.db.profile.quests.tracker.maxHeight = 200
      HogHealsQuests.Tracker.Update()
    ''')
    assert modern.eval('HogHealsQuests.Tracker.moreCount') > 0
    assert modern.eval('HogHealsQuestTracker._height') <= 200 + 20 + 8 + 20


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
    # quest 7: 0.1 of a 1000-yard map north = 100 yd, radius 200, half width 70 - 14/3
    pt = modern.eval(f'{p1}._points[1]')
    assert pt[4] == pytest.approx(0) and pt[5] == pytest.approx((70 - 14 / 3) / 2)
    assert modern.eval(f'{p1}.glyph._text') == "!" and modern.eval(f'{p1}.icon._color[1]') == pytest.approx(0.95)
    # quest 9 is complete and far away: turn-in icon on the rim, dimmed
    assert modern.eval('HogHealsQuests.Pins.pool[2].glyph._text') == "?" and modern.eval('HogHealsQuests.Pins.pool[2].icon._color[2]') == pytest.approx(0.80)
    assert modern.eval('HogHealsQuests.Pins.pool[2]._alpha') == pytest.approx(0.6)


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
