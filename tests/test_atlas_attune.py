# Attunements (HogHeals_Atlas/Attune.lua + Data/Attunements.lua): what lets you into a raid / dungeon and where you
# stand - done by quest id, active by title in your log, held by item count. Attune clip, 2026-10-08.
import pytest

from atlas_helpers import boot, errors, vals

AT = "HogHealsAtlas.Attune"

CLIENT_EXTRA = '''
DONEQ, BAGS = {}, {}
C_QuestLog = C_QuestLog or {}
C_QuestLog.IsQuestFlaggedCompleted = function(id) return DONEQ[id] == true end
C_Item = C_Item or {}
C_Item.GetItemCount = function(id) return BAGS[id] or 0 end
FACTION = "Horde"
'''

LOG = '''
LOGQ = {
  { title = "Attunement to the Core", level = 60, id = 7848, objectives = { { text = "Core Fragment: 0/1", done = false } } },
  { title = "The Grave Knight", level = 30, id = 90001, complete = true, objectives = { { text = "Grave Knight slain: 1/1", done = true } } },
}
'''


@pytest.fixture
def at(lua):
    boot(lua, extra=CLIENT_EXTRA + LOG)
    return lua


def ctx(lua, log="LOGQ"):
    return f"{{ faction = HogHealsAtlas.playerFaction(), log = {AT}.Log({log}), done = {AT}.QuestDone, count = {AT}.ItemCount }}"


# ------------------------------------------------------------------------------------------------ data
def test_data_shape_and_dungeon_links(at):
    keys = [e["key"] for e in vals(at.eval("HogHealsAtlas.Data.Attunements"))]
    assert keys[:4] == ["ony", "mc", "bwl", "naxx"] and "dalaran" in keys
    # every dungeon link points at a real Atlas dungeon
    for e in vals(at.eval("HogHealsAtlas.Data.Attunements")):
        if e["dungeon"]:
            assert at.eval(f'HogHealsAtlas.Store.Dungeon("{e["dungeon"]}") ~= nil'), e["key"]
    assert at.eval(f'{AT}.ByKey("mc").steps[1].quest') == 7848
    assert at.eval(f'{AT}.ForDungeon("ubrs").key') == "ubrs"
    assert at.eval(f'{AT}.ForDungeon("wc")') is None


# ------------------------------------------------------------------------------------------------ pure state
def test_step_states(at):
    c = ctx(at)
    assert at.eval(f'{AT}.StepState({{ title = "X", quest = 7848 }}, {c})') == "active"        # in the log, not done
    assert at.eval(f'{AT}.StepState({{ title = "The Grave Knight" }}, {c})') == "ready"         # title only, log says complete
    assert at.eval(f'{AT}.StepState({{ title = "Nope", quest = 1 }}, {c})') == "none"           # id says not done, log says absent
    assert at.eval(f'{AT}.StepState({{ title = "Nope" }}, {c})') == "none"                      # log answers (absent)
    assert at.eval(f'{AT}.StepState({{ title = "Nope" }}, {{ faction = "H" }})') == "unknown"   # no log, no id: cannot tell
    assert at.eval(f'{AT}.StepState({{ item = 16309 }}, {c})') == "none"
    at.execute("BAGS[16309] = 1; DONEQ[7848] = true")
    assert at.eval(f'{AT}.StepState({{ item = 16309 }}, {c})') == "done"
    assert at.eval(f'{AT}.StepState({{ title = "X", quest = 7848 }}, {c})') == "done"           # the game's flag beats the log
    assert at.eval(f'{AT}.StepState({{ title = "X", quest = {{ A = 1, H = 2 }} }}, {{ faction = "H", done = function(id) return id == 2 end }})') == "done"


def test_entry_state_any_vs_all(at):
    c = ctx(at)
    s = at.eval(f'{AT}.State({AT}.ByKey("ony"), {c})')
    assert s["state"] == "none" and s["total"] == 2          # Horde: the Horde quest + the amulet; Alliance quest dropped
    at.execute("BAGS[16309] = 1")
    s = at.eval(f'{AT}.State({AT}.ByKey("ony"), {c})')
    assert s["state"] == "attuned" and s["done"] == 1        # any = true: the amulet alone is enough
    s = at.eval(f'{AT}.State({AT}.ByKey("mc"), {c})')
    assert s["state"] == "progress" and s["active"] == 1     # Attunement to the Core is in the log
    at.execute("DONEQ[7848] = true")
    assert at.eval(f'{AT}.State({AT}.ByKey("mc"), {c}).state') == "attuned"
    s = at.eval(f'{AT}.State({AT}.ByKey("naxx"), {c})')
    assert s["state"] == "none"


def test_forever_chain_is_titles_only(at):
    c = ctx(at)
    s = at.eval(f'{AT}.State({AT}.ByKey("dalaran"), {c})')
    steps = [(v["step"]["title"], v["state"]) for v in vals(s["steps"])]
    assert ("The Grave Knight", "ready") in steps
    assert ("Source of Power", "none") in steps               # the log answers: not there
    assert s["state"] == "progress"
    # without a quest log the chain cannot be told at all
    s2 = at.eval(f'{AT}.State({AT}.ByKey("dalaran"), {{ faction = "H", done = {AT}.QuestDone, count = {AT}.ItemCount }})')
    assert s2["state"] == "unknown"
    # Alliance sees no Horde-only steps
    s3 = at.eval(f'{AT}.State({AT}.ByKey("dalaran"), {{ faction = "A", log = {AT}.Log(LOGQ) }})')
    assert s3["total"] == 2


# ------------------------------------------------------------------------------------------------ client ladders
def test_client_paths_are_recorded_and_absent_apis_are_silent(at):
    at.eval(f'{AT}.QuestDone(7848)'); at.eval(f'{AT}.ItemCount(16309)')
    assert at.eval(f'{AT}.path.done') == "C_QuestLog.IsQuestFlaggedCompleted"
    assert at.eval(f'{AT}.path.item') == "C_Item.GetItemCount"
    at.execute("C_QuestLog.IsQuestFlaggedCompleted = nil; function IsQuestFlaggedCompleted(id) return DONEQ[id] == true end; C_Item.GetItemCount = nil; function GetItemCount(id) return BAGS[id] or 0 end")
    at.eval(f'{AT}.QuestDone(7848)'); at.eval(f'{AT}.ItemCount(16309)')
    assert at.eval(f'{AT}.path.done') == "IsQuestFlaggedCompleted" and at.eval(f'{AT}.path.item') == "GetItemCount"
    at.execute("IsQuestFlaggedCompleted = nil; GetItemCount = nil")
    assert at.eval(f'{AT}.QuestDone(7848)') is None and at.eval(f'{AT}.ItemCount(16309)') is None
    assert at.eval(f'{AT}.path.done') == "none"
    assert at.eval(f'{AT}.Log()') is None and at.eval(f'{AT}.path.log') == "none"   # Quests addon not loaded
    assert errors(at) == []


def test_log_through_quests_addon(lua):
    boot(lua, quests=True, extra=CLIENT_EXTRA)
    lua.execute('''
      HogHealsQuests.Data.List = function() return { { title = "Blackhand's Command", id = 7761, complete = false, objectives = {} } } end
    ''')
    assert lua.eval(f'{AT}.Log()["blackhand\'s command"] ~= nil') is True
    assert lua.eval(f'{AT}.path.log') == "HogHealsQuests"
    assert lua.eval(f'{AT}.State({AT}.ByKey("bwl"), {AT}.Context()).state') == "progress"


# ------------------------------------------------------------------------------------------------ rows + window + chat
def test_rows_group_and_colour(at):
    at.execute("BAGS[16309] = 1")
    rows = vals(at.eval(f'{AT}.Rows({ctx(at)})'))
    headers = [r["text"] for r in rows if r["header"]]
    assert headers == ["Raids", "Keys", "Forever dungeons"]
    ony = next(r for r in rows if r["key"] == "ony")
    assert ony["right"] == "attuned"
    mc = next(r for r in rows if r["key"] == "mc")
    assert mc["right"] == "0/1  in progress"
    dal = next(r for r in rows if r["key"] == "dalaran")
    assert dal["text"] == "City of Dalaran (partial)" and "Not verified" in dal["tip"]


def test_guide_rows_for_a_keyed_dungeon(at):
    rows = vals(at.eval(f'{AT}.GuideRows("scholo", {ctx(at)})'))
    assert rows[0]["header"] and rows[0]["text"] == "Key"
    assert any("Skeleton Key" in r["text"] for r in rows)
    assert at.eval(f'{AT}.GuideRows("wc")') is None
    # the Window's guide page carries them
    at.execute('HogHealsAtlas.Window.Show("dungeons"); HogHealsAtlas.Window.dungeon = "scholo"; HogHealsAtlas.Window.detail = "guide"; HogHealsAtlas.Window.Refresh()')
    guide = [r["text"] for r in vals(at.eval("HogHealsAtlas.Window.GuideRows()"))]
    assert "Key" in guide and any("Skeleton Key" in t for t in guide)
    assert errors(at) == []


def test_attunements_tab_and_slash(at):
    at.execute('HogHealsAtlas.Window.Show("attune")')
    assert at.eval("HogHealsAtlas.Window.tab") == "attune"
    assert at.eval("HogHealsAtlas.Window.lists.attune ~= nil")
    assert at.eval("HogHealsAtlas.Window.tabButtons.attune ~= nil")
    lines = vals(at.eval(f'{AT}.Say({ctx(at)})'))
    assert lines[0].startswith("Onyxia's Lair: not started  next: Drakefire Amulet")
    assert any(l.startswith("Molten Core: in progress (0/1)  next: Attunement to the Core") for l in lines)
    assert lines[-1].startswith("paths: done=")
    at.execute('HogHeals:SlashCommand("attune")')
    assert any("Onyxia" in m for m in at.eval("MockLog.chat").values())
    assert errors(at) == []
