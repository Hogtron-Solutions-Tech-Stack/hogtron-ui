# In game 2026-09-29: "GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'HogHeals_Quests'"
# out of Blizzard's Edit Mode anchor pass. The objective tracker and the minimap cluster are Edit Mode systems; the
# buff frame is anchored to the minimap cluster. A field an addon writes on a Blizzard frame is tainted, so what we
# remember about those frames lives in our own side tables. This test fails the day a field lands on one again.
import pathlib
import re

BLIZZ = '''
ObjectiveTrackerFrame = CreateFrame("Frame", "ObjectiveTrackerFrame", UIParent)
GameTimeFrame = CreateFrame("Button", "GameTimeFrame", UIParent)
QueueStatusButton = CreateFrame("Button", "QueueStatusButton", UIParent)
MinimapCluster = MinimapCluster or CreateFrame("Frame", "MinimapCluster", UIParent)
C_QuestLog = C_QuestLog or {
  GetNumQuestLogEntries = function() return 0 end,
  GetInfo = function() return nil end,
}
function OursOn(f)
  local out = {}
  for k in pairs(f) do if type(k) == "string" and k:match("^hh") then out[#out + 1] = k end end
  table.sort(out)
  return table.concat(out, ",")
end
'''


def test_nothing_of_ours_is_written_on_blizzards_frames(lua):
    lua.execute(BLIZZ)
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Quests")
    lua.player_login()
    lua.execute("MockAdvance(6)")
    lua.execute("HogHealsQuests.Tracker.ApplyBlizzard(); HogHealsQuests.MapSkin.Apply(); MockAdvance(1)")
    # the work was done ...
    assert lua.eval("ObjectiveTrackerFrame:GetParent() == HogHealsHiddenParent") is True
    assert lua.eval("HogHealsQuests.Tracker.blizzHooked[ObjectiveTrackerFrame]") is True
    assert lua.eval("HogHealsQuests.MapSkin.dockHooked[GameTimeFrame]") is True
    # ... the hooks still put things back ...
    lua.execute("ObjectiveTrackerFrame:SetParent(UIParent); ObjectiveTrackerFrame:Show()")
    assert lua.eval("ObjectiveTrackerFrame:IsShown()") is False
    # ... and none of it left a mark on a frame that is not ours
    for frame in ("ObjectiveTrackerFrame", "GameTimeFrame", "QueueStatusButton", "MinimapCluster", "Minimap"):
        assert lua.eval(f"OursOn({frame})") == "", frame
    assert [e["msg"] for e in lua.eval("HogHeals.errors").values()] == []


def test_no_quests_file_writes_a_field_through_self_or_a_frame_variable():
    # source check: the three names that carried flags on Blizzard frames must not come back
    root = pathlib.Path(__file__).resolve().parent.parent / "HogHeals_Quests"
    bad = []
    for f in sorted(root.glob("*.lua")):
        for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            if re.search(r"\.(hhBanishHooked|hhRebanishing|hhDocking|hhDockHooked)", line):
                bad.append(f"{f.name}:{n}")
    assert bad == []
