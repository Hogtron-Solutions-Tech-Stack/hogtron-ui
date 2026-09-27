# AtlasProbe (HogHeals/Core/AtlasProbe.lua): measures what the client offers a dungeon loot guide.
# These tests pin the SHAPE of what it records (so the disk read-back is predictable) and that it never throws,
# never registers the forbidden combat log, and names secrets instead of touching them.
import pytest

MOCKS = r'''
C_LFGList = {
  GetAvailableCategories = function() return { 2 } end,
  GetLfgCategoryInfo = function(id) return { name = "Dungeons" } end,
  GetAvailableActivities = function(cat) return { 101, 102 } end,
  GetActivityInfoTable = function(id)
    if id == 101 then return { fullName = "The Deadmines", shortName = "DM", minLevel = 17, maxLevel = 26, categoryID = 2 } end
    return { fullName = "Wailing Caverns", shortName = "WC", minLevel = 15, maxLevel = 25, categoryID = 2 }
  end,
}
function GetInstanceInfo() return "The Deadmines", "party", 1, "Normal", 5, 0, false, 36, 5 end
function IsInInstance() return true, "party" end
function GetNumLootItems() return 2 end
function GetLootSlotType(i) return 1 end
function GetLootSlotInfo(i)
  if i == 1 then return 133, "Cruel Barb", 1, nil, 3, false, false, nil, true end
  return 134, "Linen Cloth", 3, nil, 1, false, false, nil, true
end
function GetLootSlotLink(i)
  if i == 1 then return MockLootLink or "|cff0070dd|Hitem:2169::::::::20:::::|h[Cruel Barb]|h|r" end
  return "|cffffffff|Hitem:2589::::::::20:::::|h[Linen Cloth]|h|r"
end
function GetLootSourceInfo(i) return "Creature-0-3134-36-14-644-00001A2B3C", 1 end
function GetLootRollItemLink(id) return "|cff0070dd|Hitem:2169::::::::20:::::|h[Cruel Barb]|h|r" end
function GetLootRollItemInfo(id) return 133, "Cruel Barb", 1, 3, true end
C_ChatInfo.IsAddonMessagePrefixRegistered = function() return true end
'''


def log(lua):
    return list(lua.eval('HogHeals.db.global.diag.atlas.log or {}').values())


def last_log(lua):
    lines = log(lua)
    assert lines, "nothing logged"
    return lines[-1]


@pytest.fixture
def probe(lua):
    lua.load_addon("HogHeals")
    lua.execute(MOCKS)
    lua.player_login()
    lua.execute("MockAdvance(6)")   # the 5 s Group Finder re-snapshot
    return lua


def test_snapshot_records_api_presence_and_group_finder_ranges(probe):
    api = probe.eval('HogHeals.db.global.diag.atlas.api')
    assert api["C_LFGList.GetActivityInfoTable"] == "function"
    assert api["EJ_GetInstanceInfo"] == "nil"            # no Encounter Journal in the mock, as players report on Forever
    assert api["GetLootSourceInfo"] == "function"
    acts = list(probe.eval('HogHeals.db.global.diag.atlas.lfg.activities').values())
    assert any("The Deadmines" in a and "17-26" in a for a in acts)
    assert any("Wailing Caverns" in a and "15-25" in a for a in acts)
    assert probe.eval('HogHeals.db.global.diag.atlas.lfg.status') == "1 categories, 2 activities"
    assert "fullName=string" in probe.eval('HogHeals.db.global.diag.atlas.lfg.activityFields')
    assert '"party"' in probe.eval('HogHeals.db.global.diag.atlas.calls.instance')
    assert probe.eval('#HogHeals.errors') == 0


def test_events_registered_unknown_event_does_not_abort_and_combat_log_never_registered(lua):
    lua.load_addon("HogHeals")
    lua.execute(MOCKS)
    lua.execute('MockUnknownEvents.BOSS_KILL = true')
    lua.player_login()
    reg = lua.eval('HogHeals.db.global.diag.atlas.events.registered')
    assert "LOOT_OPENED" in reg and "ENCOUNTER_END" in reg and "START_LOOT_ROLL" in reg
    assert "BOSS_KILL" not in reg
    assert "BOSS_KILL" in lua.eval('HogHeals.db.global.diag.atlas.events.failed')
    assert lua.eval('#HogHeals.errors') == 0
    assert lua.eval('HogHealsAtlasProbe._events.COMBAT_LOG_EVENT_UNFILTERED') is None   # forbidden action on this client
    assert "COMBAT_LOG" not in reg


def test_loot_opened_logs_item_id_source_npc_and_instance(probe):
    probe.fire("LOOT_OPENED", False)
    line = last_log(probe)
    assert "LOOT_OPENED" in line and "n=2" in line
    assert "slot1" in line and "itemID=2169" in line and "npc=644" in line
    assert "slot2" in line and "itemID=2589" in line
    assert 'inst="party":36' in line
    assert "SECRET" not in line
    assert probe.eval('#HogHeals.errors') == 0


def test_secret_loot_link_is_named_not_touched(probe):
    probe.execute('MockSetSecrets(true); MockLootLink = MockSecret("|Hitem:2169::::::::20:::::|h[Cruel Barb]|h")')
    probe.fire("LOOT_OPENED", False)
    line = last_log(probe)
    assert "link=SECRET(userdata)" in line and "itemID=nil" in line
    assert probe.eval('#HogHeals.errors') == 0


def test_encounter_roll_and_loot_chat_lines(probe):
    probe.fire("ENCOUNTER_END", 1, "Rhahk'Zor", 1, 5, 1)
    assert "ENCOUNTER_END" in last_log(probe) and "Rhahk'Zor" in last_log(probe)
    probe.fire("START_LOOT_ROLL", 7, 60000, 1)
    assert "START_LOOT_ROLL" in last_log(probe) and "itemID=2169" in last_log(probe) and "Cruel Barb" in last_log(probe)
    probe.fire("CHAT_MSG_LOOT", "Ann receives loot: |Hitem:2169::::::::20:::::|h[Cruel Barb]|h.", "Ann")
    assert "hasItemLink=true" in last_log(probe)
    probe.fire("CHAT_MSG_LOOT", "Ann receives loot: nothing.", "Ann")
    assert "hasItemLink=false" in last_log(probe)


def test_per_event_cap_keeps_counting(probe):
    for _ in range(10):
        probe.fire("CHAT_MSG_LOOT", "x", "Ann")
    assert probe.eval('HogHeals.db.global.diag.atlas.fired.CHAT_MSG_LOOT') == 10
    assert len([l for l in log(probe) if "CHAT_MSG_LOOT" in l]) == 6


def test_target_changed_logs_npcs_only_inside_instances(probe):
    probe.execute('MockUnits.target = { name = "Rhahk\'Zor", guid = "Creature-0-3134-36-14-644-00001A2B3C", isPlayer = false, classification = "elite", level = 19 }')
    probe.fire("PLAYER_TARGET_CHANGED")
    line = last_log(probe)
    assert "PLAYER_TARGET_CHANGED" in line and "npc=644" in line and '"elite"' in line and "level=19" in line
    probe.execute('MockUnits.target = { name = "Ann", guid = "Player-9", isPlayer = true }')
    n = len(log(probe))
    probe.fire("PLAYER_TARGET_CHANGED")
    assert len(log(probe)) == n                            # players are not bosses
    probe.execute('function IsInInstance() return false, "none" end')
    probe.execute('MockUnits.target = { name = "Boar", guid = "Creature-0-3134-0-14-113-0000000001", isPlayer = false }')
    probe.fire("PLAYER_TARGET_CHANGED")
    assert len(log(probe)) == n                            # outside an instance nothing is a boss


def test_other_addons_chat_traffic_is_not_logged(probe):
    probe.fire("CHAT_MSG_ADDON", "DBM", "hello", "PARTY", "Ann")
    assert not any("CHAT_MSG_ADDON" in l for l in log(probe))
    probe.fire("CHAT_MSG_ADDON", "HHATL", "1:36:npc:644:2169", "PARTY", "Ann")
    assert "CHAT_MSG_ADDON" in last_log(probe) and "2169" in last_log(probe)


def test_atlasdiag_prints_without_error(probe):
    probe.fire("LOOT_OPENED", False)
    probe.execute('wipe(HogHeals.errors); HogHeals:SlashCommand("atlasdiag")')
    assert probe.eval('#HogHeals.errors') == 0


def test_guid_and_link_helpers(probe):
    assert probe.eval('HogHeals.AtlasProbe.npcFromGUID("Creature-0-3134-36-14-644-00001A2B3C")') == "644"
    assert probe.eval('HogHeals.AtlasProbe.npcFromGUID("Player-3134-000ABC12")') == "nil"
    assert probe.eval('HogHeals.AtlasProbe.npcFromGUID(nil)') == "nil"
    assert probe.eval('HogHeals.AtlasProbe.itemIDFromLink("|cff0070dd|Hitem:2169::::::::20:::::|h[Cruel Barb]|h|r")') == "2169"
    assert probe.eval('HogHeals.AtlasProbe.itemIDFromLink("no link here")') == "nil"
