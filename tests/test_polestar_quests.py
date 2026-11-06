# Polestar alongside, quests (Core/Polestar.lua + HogTron_Quests/Chain.lua). Sean 2026-11-05 backlog #27: "in Questie,
# you can shift-click a Quest and it will show you the chain. I want that too." + #28: "see the Quest pickups if I hit
# M". The chain comes from Polestar's quest database (a fake one here); the quest givers on M are Polestar's own
# markers, switched on once.
import pytest

from test_polestar_guide import FAKE_POLESTAR
from test_quests import MODERN, boot, errors
from test_waypoint import NAV

# quest 7 (Kobold Camp Cleanup, in the log) sits in a chain: 5 (done) -> 7 -> 12 -> 13; 14 also needs 7 (a branch)
FAKE_QUESTDB = r'''
PS_SETTINGS["qol.availableQuests"] = false
PS_SETTINGS["qol.turnInMarkers"] = false
PS_QUESTS = {
  [5] = { id = 5, title = "Report to Marshal", level = 1, pre = {}, preAll = {} },
  [7] = { id = 7, title = "Kobold Camp Cleanup", level = 2, pre = { 5 }, preAll = {} },
  [12] = { id = 12, title = "Investigate Echo Ridge", level = 3, pre = { 7 }, preAll = {} },
  [13] = { id = 13, title = "Skirmish at Echo Ridge", level = 4, pre = {}, preAll = { 12 } },
  [14] = { id = 14, title = "Side Errand", level = 3, pre = { 7 }, preAll = {} },
  [8] = { id = 8, title = "Lost Necklace", level = 4, pre = {}, preAll = {} },
}
PS_QDB_LOADED = false
PS_LOADS = 0
Polestar.QuestDB = {
  IsLoaded = function() return PS_QDB_LOADED end,
  Load = function() PS_LOADS = PS_LOADS + 1 PS_QDB_LOADED = true return true end,
  GetQuest = function(id) return PS_QUESTS[id] end,
  QuestIds = function() local t = {} for id in pairs(PS_QUESTS) do t[#t + 1] = id end table.sort(t) return t end,
}
QFlagged = { [5] = true }
C_QuestLog.IsQuestFlaggedCompleted = function(id) return QFlagged[id] == true end
'''

C = "HogHealsQuests.Chain"


@pytest.fixture
def pq(lua):
    boot(lua, MODERN + NAV + FAKE_POLESTAR + FAKE_QUESTDB)
    lua.execute("HogHealsQuests.Tracker.Show(); HogHealsQuests.Tracker.Update()")
    return lua


def row_for(lua, qid):
    lua.execute(f"""ROW = nil
      for _, b in ipairs(HogHealsQuests.Tracker.titles) do if b.quest and b.quest.id == {qid} then ROW = b end end""")
    assert lua.eval("ROW ~= nil") is True
    return "ROW"


def test_the_chain_runs_back_and_forward_through_the_quest(pq):
    c = pq.eval(f"{C}.Build(7)")
    titles = [q["title"] for q in c["quests"].values()]
    assert titles == ["Report to Marshal", "Kobold Camp Cleanup", "Investigate Echo Ridge", "Skirmish at Echo Ridge"]
    assert c["here"] == 2 and c["branches"] == 1                                   # 14 also needs 7
    assert pq.eval("PS_LOADS") == 1                                                # loaded on the first ask, once
    pq.execute(f"{C}.Build(12)")
    assert pq.eval("PS_LOADS") == 1
    assert errors(pq) == []


def test_lines_mark_done_in_log_and_later(pq):
    lines = [l[1] for l in pq.eval(f"{C}.Lines({C}.Build(7))").values()]
    assert lines[0] == "Quest chain: 2 of 4"
    assert lines[1] == "done  [1] Report to Marshal"
    assert lines[2] == "> [2] Kobold Camp Cleanup"
    assert lines[3] == "   [3] Investigate Echo Ridge"
    assert "(+1 other quest branch off this chain)" in lines
    assert lines[-1] == "From Polestar's quest database"


def test_shift_click_shows_the_chain_instead_of_unwatching(pq):
    r = row_for(pq, 7)
    pq.execute("IsShiftKeyDown = function() return true end; GameTooltip._lines = {}")
    pq.execute(f"{r}:GetScript('OnClick')({r}, 'LeftButton')")
    lines = list(pq.eval("GameTooltip._lines").values())
    assert lines[0] == "Quest chain: 2 of 4" and "> [2] Kobold Camp Cleanup" in lines
    assert pq.eval("QWatched[7]") == 1                                              # still watched
    # a quest with no chain (8 is not on the tracker - watched only - so asked directly): says so
    pq.execute(f"GameTooltip._lines = {{}}; {C}.Show({r}, {{ id = 8, title = 'Lost Necklace' }})")
    assert "No chain: this quest stands on its own." in pq.eval("GameTooltip._lines").values()
    assert errors(pq) == []


def test_without_the_database_shift_click_watches_as_before(pq):
    pq.execute("Polestar.QuestDB = nil")
    r = row_for(pq, 7)
    pq.execute(f"IsShiftKeyDown = function() return true end; {r}:GetScript('OnClick')({r}, 'LeftButton')")
    assert pq.eval("QWatched[7]") is None                                          # unwatched, the old way
    assert errors(pq) == []


def test_no_chain_loading_in_combat(pq):
    pq.execute("MockState.inCombat = true")
    assert pq.eval(f"{C}.Build(7)") is None and pq.eval("PS_LOADS") == 0
    assert errors(pq) == []


def test_hover_hint_names_the_chain_without_loading_anything(pq):
    r = row_for(pq, 7)
    pq.execute(f"GameTooltip._lines = {{}}; {r}:GetScript('OnEnter')({r})")
    assert any("Shift-click: its quest chain" in l for l in pq.eval("GameTooltip._lines").values())
    assert pq.eval("PS_LOADS") == 0


def test_quest_givers_switched_on_once_and_the_switches_drive_polestar(pq):
    assert pq.eval('PS_SETTINGS["qol.availableQuests"]') is True
    assert "quest givers with a quest for you are marked on the map" in "\n".join(pq.eval("MockLog.chat").values())
    # off again in Polestar: a new hook does not turn it back on
    pq.execute('PS_SETTINGS["qol.availableQuests"] = false; HogHeals.Polestar.hooked = nil; HogHeals.Polestar.Hook()')
    assert pq.eval('PS_SETTINGS["qol.availableQuests"]') is False
    # our options page writes Polestar's own settings (through Polestar.Set)
    m = "HogHealsQuests.Options.Build().args.polestar.args.markers.args"
    pq.execute(f"{m}.turnIns.set(nil, true); {m}.givers.set(nil, true)")
    assert pq.eval('PS_SETTINGS["qol.turnInMarkers"]') is True and pq.eval('PS_SETTINGS["qol.availableQuests"]') is True
    assert pq.eval(f"{m}.turnIns.get()") is True
    lines = "\n".join(pq.eval("HogHeals.Polestar.Diagnose()").values())
    assert "quest givers true, turn-ins true" in lines
    assert errors(pq) == []
