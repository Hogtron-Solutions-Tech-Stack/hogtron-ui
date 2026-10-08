# Questie's quality-of-life half without its database (HogHeals_Quests/Auto.lua, Announce.lua, Tooltip.lua):
# auto accept / turn in / gossip, party announce of objective progress, "needed for <quest>" tooltips. 2026-10-08.
import pytest

from test_quests import MODERN, boot, errors

A, AN, TT = "HogHealsQuests.Auto", "HogHealsQuests.Announce", "HogHealsQuests.Tooltip"

NPC = '''
CALLS = {}
local function rec(name) return function(...) CALLS[#CALLS + 1] = { name, ... } end end
AcceptQuest = rec("AcceptQuest"); CompleteQuest = rec("CompleteQuest"); GetQuestReward = rec("GetQuestReward")
SelectActiveQuest = rec("SelectActiveQuest"); SelectAvailableQuest = rec("SelectAvailableQuest")
COMPLETABLE, CHOICES = true, 0
function IsQuestCompletable() return COMPLETABLE end
function GetNumQuestChoices() return CHOICES end
GAV, GAC, GOPT = {}, {}, {}
C_GossipInfo = {
  GetAvailableQuests = function() return GAV end, GetActiveQuests = function() return GAC end, GetOptions = function() return GOPT end,
  SelectAvailableQuest = rec("C_GossipInfo.SelectAvailableQuest"), SelectActiveQuest = rec("C_GossipInfo.SelectActiveQuest"),
}
NAV_, NAC_ = 0, 0
function GetNumAvailableQuests() return NAV_ end
function GetNumActiveQuests() return NAC_ end
function GetActiveTitle(i) return "Active " .. i, GREETDONE and GREETDONE[i] or false end
SENT = {}
function SendChatMessage(msg, ch) SENT[#SENT + 1] = { msg, ch } end
GROUPED, RAIDED = false, false
function IsInGroup() return GROUPED end
function IsInRaid() return RAIDED end
SHIFT = false
function IsShiftKeyDown() return SHIFT end
'''


@pytest.fixture
def qol(lua):
    boot(lua, MODERN + NPC)
    return lua


def calls(lua):
    return [list(c.values()) for c in lua.eval("CALLS").values()]


# ================================================================================================ Auto
def test_accept_on_detail_unless_paused_or_off(qol):
    qol.execute('MockFire("QUEST_DETAIL")')
    assert calls(qol) == [["AcceptQuest"]]
    qol.execute('CALLS = {}; SHIFT = true; MockFire("QUEST_DETAIL")')
    assert calls(qol) == []
    qol.execute(f'SHIFT = false; HogHeals.db.profile.quests.auto.accept = false; MockFire("QUEST_DETAIL")')
    assert calls(qol) == []
    assert qol.eval(f"{A}.seen.skipped") == 2


def test_turn_in_progress_then_single_reward(qol):
    qol.execute('MockFire("QUEST_PROGRESS")')
    assert calls(qol) == [["CompleteQuest"]]
    qol.execute('CALLS = {}; COMPLETABLE = false; MockFire("QUEST_PROGRESS")')
    assert calls(qol) == [] and qol.eval(f"{A}.seen.notCompletable") == 1
    qol.execute('CALLS = {}; CHOICES = 0; MockFire("QUEST_COMPLETE")')
    assert calls(qol) == [["GetQuestReward", 0]]
    qol.execute('CALLS = {}; CHOICES = 1; MockFire("QUEST_COMPLETE")')
    assert calls(qol) == [["GetQuestReward", 1]]
    qol.execute('CALLS = {}; CHOICES = 3; MockFire("QUEST_COMPLETE")')
    assert calls(qol) == [] and qol.eval(f"{A}.seen.leftChoice") == 1


def test_reward_plan_pure(qol):
    assert qol.eval(f"{A}.RewardPlan(0)") == "take"
    assert qol.eval(f"{A}.RewardPlan(1)") == "take1"
    assert qol.eval(f"{A}.RewardPlan(2)") == "choose"
    assert qol.eval(f"{A}.RewardPlan(nil)") == "take"


def test_gossip_hands_in_finished_quests_first(qol):
    qol.execute('GAV = { { questID = 101 } }; GAC = { { questID = 55, isComplete = true }, { questID = 56, isComplete = false } }; MockFire("GOSSIP_SHOW")')
    assert calls(qol) == [["C_GossipInfo.SelectActiveQuest", 55]]
    assert qol.eval(f"{A}.last.gossipPath") == "C_GossipInfo"


def test_gossip_takes_the_only_offer_but_leaves_a_real_menu_alone(qol):
    qol.execute('GAV = { { questID = 101 } }; GAC = {}; GOPT = {}; MockFire("GOSSIP_SHOW")')
    assert calls(qol) == [["C_GossipInfo.SelectAvailableQuest", 101]]
    qol.execute('CALLS = {}; GAV = { { questID = 101 }, { questID = 102 } }; MockFire("GOSSIP_SHOW")')
    assert calls(qol) == [] and qol.eval(f"{A}.seen.gossipLeft") == 1
    qol.execute('CALLS = {}; GAV = { { questID = 101 } }; GOPT = { { name = "Train me" } }; MockFire("GOSSIP_SHOW")')
    assert calls(qol) == []
    qol.execute('CALLS = {}; GOPT = {}; GAV = { { questID = 101, isTrivial = true } }; HogHeals.db.profile.quests.auto.acceptTrivial = false; MockFire("GOSSIP_SHOW")')
    assert calls(qol) == []


def test_greeting_page_uses_the_plain_lists(qol):
    qol.execute('NAC_ = 2; GREETDONE = { false, true }; NAV_ = 1; MockFire("QUEST_GREETING")')
    assert calls(qol) == [["SelectActiveQuest", 2]]
    qol.execute('CALLS = {}; NAC_ = 0; NAV_ = 1; MockFire("QUEST_GREETING")')
    assert calls(qol) == [["SelectAvailableQuest", 1]]


def test_legacy_gossip_varargs(qol):
    qol.execute('''
      C_GossipInfo = nil
      function GetNumGossipAvailableQuests() return 0 end
      function GetNumGossipActiveQuests() return 2 end
      function GetGossipActiveQuests() return "A", 5, false, false, false, false,  "B", 6, false, true, false, false end
      function GetNumGossipOptions() return 0 end
      SelectGossipActiveQuest = function(i) CALLS[#CALLS + 1] = { "SelectGossipActiveQuest", i } end
      MockFire("GOSSIP_SHOW")
    ''')
    assert calls(qol) == [["SelectGossipActiveQuest", 2]]
    assert qol.eval(f"{A}.last.gossipPath") == "GetGossip*"


def test_auto_defers_to_questie(qol):
    qol.execute('MockState.loadedAddons.Questie = true; MockFire("QUEST_DETAIL")')
    assert calls(qol) == []
    assert qol.eval(f"{A}.Deferring()") is True
    assert "deferring to Questie" in " ".join(qol.eval(f"{A}.Lines()").values())
    qol.execute("MockState.loadedAddons.Questie = nil")


def test_auto_without_any_npc_api_is_silent(lua):
    boot(lua, MODERN)
    lua.execute('MockFire("QUEST_DETAIL"); MockFire("QUEST_PROGRESS"); MockFire("QUEST_COMPLETE"); MockFire("GOSSIP_SHOW"); MockFire("QUEST_GREETING")')
    assert errors(lua) == []
    assert lua.eval(f"{A}.last.gossipPath") == "none"


# ================================================================================================ Announce
def test_diff_pure(qol):
    d = qol.eval(f'''{AN}.Diff(
      {{ [7] = {{ title = "Kobolds", complete = false, obj = {{ {{ name = "Kobold Vermin", have = 3, need = 8, done = false }} }} }},
         [8] = {{ title = "Necklace", complete = false, obj = {{ {{ name = "Lost Necklace", have = 0, need = 1, done = false }} }} }} }},
      {{ [7] = {{ title = "Kobolds", complete = false, obj = {{ {{ name = "Kobold Vermin", have = 5, need = 8, done = false }} }} }},
         [8] = {{ title = "Necklace", complete = true,  obj = {{ {{ name = "Lost Necklace", have = 1, need = 1, done = true }} }} }},
         [9] = {{ title = "New one", complete = false, obj = {{ {{ name = "X", have = 1, need = 2, done = false }} }} }} }})''')
    lines = [v["text"] for v in d.values()]
    assert lines == ["Kobold Vermin 5/8", "Lost Necklace 1/1 - done"]
    # going backwards (abandon + re-accept) is not news
    d2 = qol.eval(f'''{AN}.Diff({{ [7] = {{ title = "K", obj = {{ {{ have = 5, need = 8 }} }} }} }}, {{ [7] = {{ title = "K", obj = {{ {{ have = 2, need = 8 }} }} }} }})''')
    assert len(d2) == 0


def test_progress_is_sent_to_the_party_only_when_grouped(qol):
    # baseline is the login read; quest 7 "Kobold Vermin slain: 3/8" -> 5/8
    qol.execute('GROUPED = true; QObj[7][1].numFulfilled = 5; QObj[7][1].text = "Kobold Vermin slain: 5/8"; MockFire("QUEST_LOG_UPDATE")')
    sent = [list(v.values()) for v in qol.eval("SENT").values()]
    assert sent == [["Kobold Camp Cleanup - Kobold Vermin 5/8", "PARTY"]]
    qol.execute('SENT = {}; MockFire("QUEST_LOG_UPDATE")')     # same log again: nothing new
    assert qol.eval("#SENT") == 0
    qol.execute('GROUPED = false; QObj[7][1].numFulfilled = 6; QObj[7][1].text = "Kobold Vermin slain: 6/8"; MockFire("QUEST_LOG_UPDATE")')
    assert qol.eval("#SENT") == 0      # solo: silent
    assert qol.eval(f"{AN}.seen.party") == 1


def test_self_echo_and_raid_channel(qol):
    qol.execute('''
      HogHeals.db.profile.quests.announce.self = true
      RAIDED = true; GROUPED = true
      QObj[7][1].finished = true; QObj[7][1].numFulfilled = 8; QObj[7][1].text = "Kobold Vermin slain: 8/8"
      MockFire("QUEST_LOG_UPDATE")
    ''')
    sent = [list(v.values()) for v in qol.eval("SENT").values()]
    assert sent == [["Kobold Camp Cleanup - Kobold Vermin 8/8 - done", "RAID"]]
    chat = " ".join(qol.eval("MockLog.chat").values())
    assert "Kobold Vermin 8/8 - done" in chat


def test_accepted_and_turned_in_lines_are_opt_in(qol):
    qol.execute('GROUPED = true; MockFire("QUEST_TURNED_IN", 7)')
    assert qol.eval("#SENT") == 0
    qol.execute('HogHeals.db.profile.quests.announce.turnedIn = true; MockFire("QUEST_TURNED_IN", 7)')
    sent = [list(v.values()) for v in qol.eval("SENT").values()]
    assert sent[-1] == ["turned in Kobold Camp Cleanup", "PARTY"]


def test_announce_defers_to_questie(qol):
    qol.execute('GROUPED = true; MockState.loadedAddons.Questie = true; QObj[7][1].numFulfilled = 5; MockFire("QUEST_LOG_UPDATE")')
    assert qol.eval("#SENT") == 0
    qol.execute("MockState.loadedAddons.Questie = nil")


# ================================================================================================ Tooltip
def test_name_matching_pure(qol):
    assert qol.eval(f'{TT}.SameName("Kobold Vermin", "kobold vermin")') is True
    assert qol.eval(f'{TT}.SameName("Kobold Vermins", "Kobold Vermin")') is True
    assert qol.eval(f'{TT}.SameName("Boar Meat", "Boar")') is False
    assert qol.eval(f'{TT}.SameName(nil, "Boar")') is False
    m = qol.eval(f'{TT}.Matches("Kobold Vermin", HogHealsQuests.Data.List())')
    assert len(m) == 1 and m[1]["title"] == "Kobold Camp Cleanup" and m[1]["have"] == 3 and m[1]["need"] == 8


def test_unit_tooltip_gets_the_quest_line(qol):
    qol.execute('''
      function GameTooltip:GetUnit() return "Kobold Vermin", "mouseover" end
      GameTooltip:ClearLines()
      GameTooltip:GetScript("OnTooltipSetUnit")(GameTooltip)
    ''')
    lines = list(qol.eval("GameTooltip._lines").values())
    assert lines == ["|cff21D4E0Kobold Camp Cleanup|r  3/8"]
    assert qol.eval(f"{TT}.path") == "HookScript"
    qol.execute('function GameTooltip:GetUnit() return "Innkeeper", "mouseover" end; GameTooltip:ClearLines(); GameTooltip:GetScript("OnTooltipSetUnit")(GameTooltip)')
    assert qol.eval("#GameTooltip._lines") == 0


def test_item_tooltip_and_done_colour(qol):
    qol.execute('''
      QObj[9] = { { text = "Report delivered: 1/1", type = "event", finished = true, numFulfilled = 1, numRequired = 1 } }
      HogHealsQuests.Data.List()
      function GameTooltip:GetItem() return "Report delivered", "item:1" end
      GameTooltip:ClearLines()
      GameTooltip:GetScript("OnTooltipSetItem")(GameTooltip)
    ''')
    lines = list(qol.eval("GameTooltip._lines").values())
    assert lines == ["|cff21D4E0Report to Goldshire|r  |cff40CC59done|r"]
    qol.execute(f'HogHeals.db.profile.quests.tooltip.items = false; GameTooltip:ClearLines(); GameTooltip:GetScript("OnTooltipSetItem")(GameTooltip)')
    assert qol.eval("#GameTooltip._lines") == 0


def test_tooltip_defers_to_questie(qol):
    qol.execute('''
      MockState.loadedAddons.Questie = true
      function GameTooltip:GetUnit() return "Kobold Vermin", "mouseover" end
      GameTooltip:ClearLines(); GameTooltip:GetScript("OnTooltipSetUnit")(GameTooltip)
    ''')
    assert qol.eval("#GameTooltip._lines") == 0
    qol.execute("MockState.loadedAddons.Questie = nil")


def test_modern_tooltip_data_processor_path(lua):
    lua.execute('''
      TDP_CALLS = {}
      TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) TDP_CALLS[#TDP_CALLS + 1] = kind end }
      Enum = Enum or {}; Enum.TooltipDataType = { Unit = 2, Item = 0 }
    ''')
    boot(lua, MODERN + NPC)
    assert lua.eval(f"{TT}.path") == "TooltipDataProcessor"
    assert sorted(lua.eval("TDP_CALLS").values()) == [0, 2]


# ================================================================================================ options + diag
def test_options_and_diag(qol):
    args = qol.eval("HogHealsQuests.Options.Build().args.qol.args")
    for key in ("accept", "turnIn", "gossip", "party", "units"):
        assert key in args, key
    text = " ".join(list(qol.eval(f"{A}.Lines()").values()) + list(qol.eval(f"{AN}.Lines()").values()) + list(qol.eval(f"{TT}.Lines()").values()))
    assert "auto quests: on" in text and "announce: on" in text and "quest tooltips: on" in text
    assert errors(qol) == []
