# HogTron UI Atlas: the shipped dungeon / quest lists hold together, and level colours fall on the right side of each
# boundary.
import pytest

from atlas_helpers import boot, errors, vals

A = "HogHealsAtlas"


@pytest.fixture
def atlas(lua):
    return boot(lua)


def test_every_dungeon_is_complete_and_keys_are_unique(atlas):
    n = atlas.eval(f"#{A}.Data.Dungeons")
    assert n >= 27
    keys = set()
    for i in range(1, n + 1):
        d = f"{A}.Data.Dungeons[{i}]"
        key, name = atlas.eval(f"{d}.key"), atlas.eval(f"{d}.name")
        assert key and name and key not in keys, key
        keys.add(key)
        lo, hi = atlas.eval(f"{d}.min"), atlas.eval(f"{d}.max")
        assert 1 <= lo <= hi <= 60, name
        assert atlas.eval(f"{d}.enter") <= lo, name                       # you can walk in before it is for you
        bosses = vals(atlas.eval(f"{d}.bosses"))
        assert len(bosses) == len(set(bosses)), name                      # no boss twice in one dungeon
        if not atlas.eval(f"{d}.unverified"):
            assert len(bosses) >= 1, name
        assert atlas.eval(f"{A}.Data.Quests['{key}']") is not None, key   # a quest list exists, even if empty
    assert atlas.eval(f"{A}.Data.byKey.lordaeron.unverified") is True and atlas.eval(f"{A}.Data.byKey.lordaeron.inst") == 2999
    assert atlas.eval(f"#{A}.Data.byKey.lordaeron.bosses") == 0           # nothing invented for the new dungeons
    assert atlas.eval(f"{A}.Data.byKey.dalaran.unverified") is True


def test_curated_loot_ships_empty(atlas):
    # item ids are never written from memory: the file stays empty until drops are verified
    assert atlas.eval(f"next({A}.Data.Curated)") is None


def test_every_quest_list_belongs_to_a_dungeon_and_has_titles(atlas):
    atlas.execute(f"""
      BAD = {{}}
      for key, list in pairs({A}.Data.Quests) do
        if not {A}.Data.byKey[key] then BAD[#BAD + 1] = "no dungeon " .. key end
        local seen = {{}}
        for _, q in ipairs(list) do
          if type(q.title) ~= "string" or q.title == "" then BAD[#BAD + 1] = key .. ": empty title" end
          if seen[q.title] then BAD[#BAD + 1] = key .. ": twice " .. q.title end
          seen[q.title] = true
          if q.side and q.side ~= "A" and q.side ~= "H" then BAD[#BAD + 1] = key .. ": side " .. q.side end
        end
      end
    """)
    assert vals(atlas.eval("BAD")) == []


def test_find_boss_prefers_the_wing_behind_a_shared_instance_id(atlas):
    assert atlas.eval(f"({A}.Data.FindBoss('herod', 189)).key") == "sm_arm"
    assert atlas.eval(f"({A}.Data.FindBoss('Arcanist Doan', 189)).key") == "sm_lib"
    assert atlas.eval(f"({A}.Data.FindBoss('Edwin VanCleef')).key") == "vc"
    assert atlas.eval(f"({A}.Data.FindBoss('Miner Johnson', 36)).key") == "vc"          # rares count
    assert atlas.eval(f"{A}.Data.FindBoss('Nobody At All', 36)") is None
    assert atlas.eval(f"({A}.Data.FindBoss('King Gordok', 36)).key") == "dm_n"           # wrong id given: still found


@pytest.mark.parametrize("level,band", [(16, "red"), (17, "orange"), (18, "orange"), (19, "green"), (26, "green"), (27, "grey")])
def test_level_bands_at_the_boundaries(atlas, level, band):
    # The Deadmines 17-26
    assert atlas.eval(f"{A}.Levels.Band({level}, 17, 26)") == band


def test_level_band_without_numbers_is_unknown_not_an_error(atlas):
    assert atlas.eval(f"{A}.Levels.Band(nil, 17, 26)") == "unknown"
    assert atlas.eval(f"{A}.Levels.Band(20, nil, nil)") == "unknown"


def test_list_is_sorted_and_the_for_me_filter_keeps_orange_and_green_only(atlas):
    rows = vals(atlas.eval(f"{A}.Levels.List(20, false)"))
    mins = [r["min"] for r in rows]
    assert mins == sorted(mins) and len(rows) == atlas.eval(f"#{A}.Data.Dungeons")
    mine = vals(atlas.eval(f"{A}.Levels.List(20, true)"))
    assert {r["band"] for r in mine} <= {"orange", "green"}
    names = [r["dungeon"]["name"] for r in mine]
    assert "The Deadmines" in names and "Wailing Caverns" in names and "Scholomance" not in names and "Ragefire Chasm" not in names


def test_game_ranges_win_over_the_list_and_say_so(atlas):
    atlas.execute("""
      C_LFGList = {
        GetAvailableCategories = function() return { 2 } end,
        GetAvailableActivities = function(cat) return { 10, 11, 12 } end,
        GetActivityInfoTable = function(id)
          if id == 10 then return { fullName = "The Deadmines", minLevelSuggestion = 15, maxLevelSuggestion = 22 } end
          if id == 11 then return { fullName = "Westfall", minLevel = 0 } end                       -- a zone: no range
          if id == 12 then return { fullName = "Wailing Caverns", minLevelSuggestion = 0, maxLevelSuggestion = 0 } end
        end,
      }
    """)
    assert atlas.eval(f"{A}.Levels.Refresh()") == 1
    assert list(atlas.eval(f"{{ {A}.Levels.For({A}.Data.byKey.vc) }}").values()) == [15, 22, "game"]
    assert list(atlas.eval(f"{{ {A}.Levels.For({A}.Data.byKey.wc) }}").values()) == [17, 24, "list"]   # 0-0 is no answer


def test_zone_only_group_finder_like_forever_changes_nothing(atlas):
    # measured 2026-09-28: 41 activities, all zones, all "0-nil"
    atlas.execute("""
      C_LFGList = {
        GetAvailableCategories = function() return { 116 } end,
        GetAvailableActivities = function() return { 853, 854 } end,
        GetActivityInfoTable = function(id) return { fullName = id == 853 and "Elwynn Forest" or "Westfall", minLevel = 0 } end,
      }
    """)
    assert atlas.eval(f"{A}.Levels.Refresh()") == 0
    assert errors(atlas) == []
