# HogTron_Quests/Dialog.lua: the quest giver's pages in our window instead of Blizzard's (Sean 2026-10-14, from the
# WoW Forever add-on clip #5 "Dialogue UI"). Blizzard's QuestFrame / GossipFrame here are real mock frames that log
# every event they still receive, so "muted" is tested by what they hear, not by a flag we set ourselves.
import pathlib
import pytest

from test_quests import MODERN

D = "HogHealsQuests.Dialog"

API = '''
CALLS = {}
local function rec(name) return function(...) CALLS[#CALLS + 1] = { name, ... } end end
AcceptQuest = rec("AcceptQuest"); DeclineQuest = rec("DeclineQuest"); CompleteQuest = rec("CompleteQuest")
GetQuestReward = rec("GetQuestReward"); CloseQuest = rec("CloseQuest")
SelectActiveQuest = rec("SelectActiveQuest"); SelectAvailableQuest = rec("SelectAvailableQuest")
TITLE, TEXT, OBJ = "Wolves Across the Border", "Those wolves have harried the farms for too long.", "Bring 8 Tough Wolf Meat to Marshal Dughan."
function GetTitleText() return TITLE end
function GetQuestText() return TEXT end
function GetObjectiveText() return OBJ end
function GetProgressText() return "Have you got the meat?" end
function GetRewardText() return "Well done." end
COMPLETABLE = true
function IsQuestCompletable() return COMPLETABLE end
REWARDS, CHOICES, REQUIRED = {}, {}, {}
function GetNumQuestRewards() return #REWARDS end
function GetNumQuestChoices() return #CHOICES end
function GetNumQuestItems() return #REQUIRED end
function GetQuestItemInfo(kind, i)
  local t = kind == "reward" and REWARDS or kind == "choice" and CHOICES or REQUIRED
  local it = t[i]
  if it then return it[1], it[2], it[3] or 1, it[4] or 1, true end
end
XP, XPMAX, MONEY = 1250, 8800, 750
function GetRewardXP() return XP end
function UnitXPMax() return XPMAX end
function GetRewardMoney() return MONEY end
function GetMaxPlayerLevel() return 60 end
MockUnits.player = MockUnits.player or {}
MockUnits.player.level = 12
GAV, GAC, GOPT = {}, {}, {}
C_GossipInfo = {
  GetText = function() return "Greetings." end,
  GetAvailableQuests = function() return GAV end, GetActiveQuests = function() return GAC end, GetOptions = function() return GOPT end,
  SelectAvailableQuest = rec("C_GossipInfo.SelectAvailableQuest"), SelectActiveQuest = rec("C_GossipInfo.SelectActiveQuest"),
  SelectOption = rec("C_GossipInfo.SelectOption"), CloseGossip = rec("C_GossipInfo.CloseGossip"),
}
NAV_, NAC_ = 0, 0
function GetGreetingText() return "Hail." end
function GetNumAvailableQuests() return NAV_ end
function GetNumActiveQuests() return NAC_ end
function GetAvailableTitle(i) return "Offer " .. i end
function GetActiveTitle(i) return "Active " .. i, GREETDONE and GREETDONE[i] or false end
SHIFT = false
function IsShiftKeyDown() return SHIFT end
BLIZZ = {}
QuestFrame = CreateFrame("Frame", "QuestFrame", UIParent)
for _, e in ipairs({ "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_ITEM_UPDATE", "UNIT_PORTRAIT_UPDATE" }) do QuestFrame:RegisterEvent(e) end
QuestFrame:SetScript("OnEvent", function(_, e) BLIZZ[#BLIZZ + 1] = "QuestFrame:" .. e end)
GossipFrame = CreateFrame("Frame", "GossipFrame", UIParent)
for _, e in ipairs({ "GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_LOG_UPDATE" }) do GossipFrame:RegisterEvent(e) end
GossipFrame:SetScript("OnEvent", function(_, e) BLIZZ[#BLIZZ + 1] = "GossipFrame:" .. e end)
'''


def boot(lua, before="", auto=False):
    lua.execute(MODERN + API + before)
    for a in ("HogTronUI", "HogTron_Quests"):
        lua.load_addon(a)
    lua.player_login()
    lua.execute("wipe(HogHeals.errors)")
    lua.execute(f"HogHeals.db.profile.quests.auto.enabled = {'true' if auto else 'false'}")
    return lua


@pytest.fixture
def dlg(lua):
    return boot(lua)


def calls(lua):
    return [list(c.values()) for c in lua.eval("CALLS").values()]


def blizz(lua):
    return list(lua.eval("BLIZZ").values())


def shown(lua):
    return lua.eval("HogTronUIDialog ~= nil and HogTronUIDialog:IsShown()") is True


def bound(lua, key):
    """The button name an override binding of `key` clicks (last one wins), or None."""
    out = None
    for c in lua.eval("MockBindings.clicks").values():
        if c["key"] == key:
            out = c["name"]
    return out


def click_pick(lua, i):
    lua.execute(f'_G["HogTronUIDialogRow" .. {D}.SlotOfPick({i})]:Click()')


# ================================================================================================ mute
def ic(name, size=14):
    """The inline icon escape Dialog.Icon writes for a HogTronUI/Media file."""
    return "|T" + "\\".join(["Interface", "AddOns", "HogTronUI", "Media", name]) + f":{size}:{size}:2:0|t"


def test_blizzard_frames_stop_hearing_their_page_events_and_get_them_back(dlg):
    assert dlg.eval('QuestFrame:IsEventRegistered("QUEST_DETAIL")') is False
    assert dlg.eval('QuestFrame:IsEventRegistered("QUEST_FINISHED")') is False
    assert dlg.eval('QuestFrame:IsEventRegistered("UNIT_PORTRAIT_UPDATE")') is True   # not ours to take
    assert dlg.eval('GossipFrame:IsEventRegistered("GOSSIP_SHOW")') is False
    assert dlg.eval('GossipFrame:IsEventRegistered("QUEST_LOG_UPDATE")') is True
    dlg.execute('MockFire("QUEST_DETAIL"); MockFire("GOSSIP_SHOW")')
    assert blizz(dlg) == []
    assert shown(dlg)
    # off: every event back, Blizzard's window answers, ours stays shut - no reload
    dlg.execute('HogHeals:SlashCommand("dialog off")')
    assert not shown(dlg)
    assert dlg.eval('QuestFrame:IsEventRegistered("QUEST_DETAIL") and GossipFrame:IsEventRegistered("GOSSIP_SHOW")') is True
    dlg.execute('MockFire("QUEST_DETAIL")')
    assert blizz(dlg) == ["QuestFrame:QUEST_DETAIL"]
    assert not shown(dlg)
    dlg.execute('HogHeals:SlashCommand("dialog on")')
    assert dlg.eval('QuestFrame:IsEventRegistered("QUEST_DETAIL")') is False


def test_capability_gate_leaves_blizzards_window_when_a_call_is_missing(lua):
    boot(lua, before="AcceptQuest = nil")
    assert lua.eval('QuestFrame:IsEventRegistered("QUEST_DETAIL")') is True
    assert lua.eval(f"{D}.active.quest") is False
    assert "AcceptQuest" in lua.eval(f"{D}.why.quest")
    assert lua.eval(f"{D}.active.gossip") is True   # gossip has everything it needs
    lua.execute('MockFire("QUEST_DETAIL")')
    assert blizz(lua) == ["QuestFrame:QUEST_DETAIL"] and not shown(lua)


def test_a_frame_that_does_not_listen_is_never_half_muted(lua):
    boot(lua, before='GossipFrame:UnregisterEvent("GOSSIP_SHOW")')
    assert lua.eval('GossipFrame:IsEventRegistered("GOSSIP_CLOSED")') is True
    assert lua.eval(f"{D}.active.gossip") is False


def test_steps_aside_for_dialogue_ui(lua):
    boot(lua, before="MockState.loadedAddons = { DialogueUI = true }")
    assert lua.eval('QuestFrame:IsEventRegistered("QUEST_DETAIL")') is True
    assert "DialogueUI" in lua.eval(f"{D}.why.all")


def test_nothing_of_ours_on_blizzards_frames(dlg):
    dlg.execute('MockFire("QUEST_DETAIL")')
    for name in ("QuestFrame", "GossipFrame"):
        keys = [k for k in dlg.eval(name).keys() if isinstance(k, str) and k.startswith("hh")]
        assert keys == [], name


# ================================================================================================ pages
def test_detail_page_text_xp_share_and_accept(dlg):
    dlg.execute('MockFire("QUEST_DETAIL")')
    assert shown(dlg)
    assert dlg.eval("HogTronUIDialog.title:GetText()") == "Wolves Across the Border"
    assert dlg.eval("HogTronUIDialog.body:GetText()").startswith("Those wolves")
    assert dlg.eval("HogTronUIDialog.objectives:GetText()").startswith("Bring 8")
    assert dlg.eval("HogTronUIDialog.xp:GetText()") == ic("reward_xp") + " +1,250 XP  (14% of a level)"
    assert dlg.eval("HogTronUIDialog.money:GetText()") == "7" + ic("coin_silver") + "  50" + ic("coin_copper")
    assert dlg.eval("HogTronUIDialog.primary.label:GetText()") == "Accept"
    assert dlg.eval("HogTronUIDialog.secondary.label:GetText()") == "Decline"
    assert bound(dlg, "SPACE") == "HogTronUIDialogPrimary"
    dlg.execute("HogTronUIDialogPrimary:Click()")
    assert calls(dlg) == [["AcceptQuest"]]


def test_decline_button_declines_and_closes(dlg):
    dlg.execute('MockFire("QUEST_DETAIL"); HogTronUIDialogSecondary:Click()')
    assert calls(dlg) == [["DeclineQuest"]]
    assert not shown(dlg)


def test_auto_answers_first_and_the_window_stays_shut(lua):
    boot(lua, auto=True)
    lua.execute('MockFire("QUEST_DETAIL")')
    assert calls(lua) == [["AcceptQuest"]]
    assert not shown(lua)
    assert lua.eval(f"{D}.seen.autoAnswered") == 1
    # Shift held = read it yourself, in our window
    lua.execute('CALLS = {}; SHIFT = true; MockFire("QUEST_DETAIL")')
    assert calls(lua) == [] and shown(lua)


def test_reward_choice_waits_for_a_pick(lua):
    boot(lua, auto=True)   # the real default: auto leaves a real choice to you, so this is where the window shows
    lua.execute('CHOICES = { { "Brawler Gloves", 132939 }, { "Woodland Tunic", 132721 }, { "Light Pants", 134586 } }; MockFire("QUEST_COMPLETE")')
    assert shown(lua)
    assert lua.eval(f"{D}.model.primary.disabled") is True
    lua.execute("HogTronUIDialogPrimary:Click()")
    assert calls(lua) == []
    assert bound(lua, "1") is not None and bound(lua, "3") is not None
    click_pick(lua, 2)
    assert lua.eval(f"{D}.choice") == 2
    assert lua.eval(f"{D}.model.primary.disabled") is False
    lua.execute("HogTronUIDialogPrimary:Click()")
    assert calls(lua) == [["GetQuestReward", 2]]


def test_one_or_no_choice_takes_it(dlg):
    dlg.execute('CHOICES = { { "Only Ring", 1 } }; MockFire("QUEST_COMPLETE"); HogTronUIDialogPrimary:Click()')
    assert calls(dlg) == [["GetQuestReward", 1]]
    dlg.execute('CALLS = {}; CHOICES = {}; MockFire("QUEST_COMPLETE"); HogTronUIDialogPrimary:Click()')
    assert calls(dlg) == [["GetQuestReward", 0]]


def test_progress_continues_only_when_completable(dlg):
    dlg.execute('COMPLETABLE = false; REQUIRED = { { "Tough Wolf Meat", 133970, 8 } }; MockFire("QUEST_PROGRESS")')
    assert dlg.eval("HogTronUIDialog.primary.label:GetText()") == "Incomplete"   # like Dialogue UI: greyed, outlined
    assert dlg.eval("HogTronUIDialog.primary.line.shown") is True and dlg.eval("HogTronUIDialog.primary.bg.shown") is False
    dlg.execute("HogTronUIDialogPrimary:Click()")
    assert calls(dlg) == []
    assert dlg.eval(f'{D}.Do("continue")') is False and calls(dlg) == []   # the action refuses too, not only the button
    assert dlg.eval("HogTronUIDialog.reqTag.text:GetText()") == "Required items"
    assert dlg.eval("HogTronUIDialogRow1.text:GetText()") == "Tough Wolf Meat"
    assert dlg.eval("HogTronUIDialogRow1.count:GetText()") == "8"
    assert dlg.eval("HogTronUIDialog.secondary.label:GetText()") == "Cancel"
    dlg.execute('COMPLETABLE = true; MockFire("QUEST_PROGRESS")')
    assert dlg.eval("HogTronUIDialog.primary.label:GetText()") == "Continue"
    dlg.execute("HogTronUIDialogPrimary:Click()")
    assert calls(dlg) == [["CompleteQuest"]]


def test_gossip_lists_hand_ins_then_offers_then_open_quests_then_options(dlg):
    dlg.execute('''
      GAC = { { title = "Done Q", questID = 55, isComplete = true }, { title = "Open Q", questID = 56, isComplete = false } }
      GAV = { { title = "New Q", questID = 101 } }
      GOPT = { { name = "Train me", gossipOptionID = 9, orderIndex = 1 }, { name = "Make this inn your home", gossipOptionID = 7, orderIndex = 0 } }
      MockFire("GOSSIP_SHOW")''')
    picks = [dlg.eval(f"{D}.model.picks[{i}].text") for i in range(1, 6)]
    assert picks == ["Done Q", "New Q", "Open Q", "Make this inn your home", "Train me"]
    assert dlg.eval("HogTronUIDialogRow1.key.text:GetText()") == "1"
    assert bound(dlg, "SPACE") is None          # five lines: Space would be a guess
    assert bound(dlg, "5") is not None
    click_pick(dlg, 4)
    click_pick(dlg, 2)
    click_pick(dlg, 1)
    assert calls(dlg) == [["C_GossipInfo.SelectOption", 7], ["C_GossipInfo.SelectAvailableQuest", 101], ["C_GossipInfo.SelectActiveQuest", 55]]
    dlg.execute("CALLS = {}; HogTronUIDialogSecondary:Click()")
    assert calls(dlg) == [["C_GossipInfo.CloseGossip"]] and not shown(dlg)


# Sean 2026-10-18 on the parchment page: "I also dont like this '!' and want one that fits more" -> the wax seals.
def test_every_quest_line_wears_its_wax_seal(dlg):
    dlg.execute('''
      GAC = { { title = "Done Q", questID = 55, isComplete = true }, { title = "Open Q", questID = 56, isComplete = false } }
      GAV = { { title = "New Q", questID = 101 }, { title = "Grey Q", questID = 102, isTrivial = true } }
      GOPT = { { name = "Train me", gossipOptionID = 9, orderIndex = 1 } }
      MockFire("GOSSIP_SHOW")''')

    def row(i):
        return f'_G["HogTronUIDialogRow" .. {D}.SlotOfPick({i})].icon'
    want = [("Done Q", "dialog_quest_done", False), ("New Q", "dialog_quest_open", False), ("Grey Q", "dialog_quest_open", True),
            ("Open Q", "dialog_quest_wait", False)]
    for i, (title, art, grey) in enumerate(want, 1):
        assert dlg.eval(f"{D}.model.picks[{i}].text") == title
        tex = dlg.eval(f"{row(i)}:GetTexture()")
        assert "HogTronUI" in tex and tex.endswith(art), title
        assert dlg.eval(f"{row(i)}:IsShown()") is True and dlg.eval(f"{row(i)}:IsDesaturated()") is grey, title
    assert dlg.eval(f"{row(5)}:IsShown()") is False                       # a gossip line keeps its ">" (no client icon)
    for art in ("dialog_quest_open", "dialog_quest_done", "dialog_quest_wait"):
        assert (pathlib.Path(__file__).resolve().parents[1] / "HogTronUI" / "Media" / f"{art}.tga").is_file(), art
    # the same row later shows something plain: never left grey
    dlg.execute('GAC = {}; GAV = { { title = "Fresh Q", questID = 103 } }; GOPT = {}; MockFire("GOSSIP_SHOW")')
    assert dlg.eval(f"{row(1)}:IsDesaturated()") is False
    # ... or a reward item: a page of rewards after a grey seal shows them in full colour
    dlg.execute('GAC = {}; GAV = { { title = "Grey Q", questID = 102, isTrivial = true } }; GOPT = {}; MockFire("GOSSIP_SHOW")')
    assert dlg.eval(f"{row(1)}:IsDesaturated()") is True
    dlg.execute('CHOICES = { { "Sample Gloves", 1, 1, 2 }, { "Sample Tunic", 2, 1, 2 } }; MockFire("QUEST_DETAIL")')
    greyed = dlg.eval("(function() local n = 0 for i = 1, 12 do local r = _G['HogTronUIDialogRow' .. i] "
                      "if r and r:IsShown() and r.icon:IsShown() and r.icon:IsDesaturated() then n = n + 1 end end return n end)()")
    assert greyed == 0


def test_one_gossip_line_takes_space(dlg):
    dlg.execute('GOSSIP_N = 0; GOPT = { { name = "Show me your wares", gossipOptionID = 3 } }; MockFire("GOSSIP_SHOW")')
    assert bound(dlg, "SPACE") == dlg.eval(f'"HogTronUIDialogRow" .. {D}.SlotOfPick(1)')


def test_greeting_page_uses_the_plain_lists(dlg):
    dlg.execute('NAC_, NAV_, GREETDONE = 1, 2, { true }; MockFire("QUEST_GREETING")')
    assert [dlg.eval(f"{D}.model.picks[{i}].text") for i in (1, 2, 3)] == ["Active 1", "Offer 1", "Offer 2"]
    click_pick(dlg, 3)
    assert calls(dlg) == [["SelectAvailableQuest", 2]]


# ================================================================================================ closing
def test_finished_waits_a_beat_for_the_next_page(dlg):
    dlg.execute('GAV = { { title = "New Q", questID = 101 } }; GOPT = { { name = "Bye", gossipOptionID = 1 } }; MockFire("GOSSIP_SHOW")')
    # picking a quest from gossip: the gossip closes, the quest page follows a moment later
    dlg.execute('MockFire("GOSSIP_CLOSED"); MockFire("QUEST_DETAIL"); MockAdvance(0.3)')
    assert shown(dlg) and dlg.eval(f"{D}.model.kind") == "detail"
    # a late gossip close while a quest page shows is not ours to act on
    dlg.execute('MockFire("GOSSIP_CLOSED"); MockAdvance(0.3)')
    assert shown(dlg)
    dlg.execute('MockFire("QUEST_FINISHED"); MockAdvance(0.3)')
    assert not shown(dlg)
    assert calls(dlg) == []   # the game closed it: we send nothing back


def test_item_names_arriving_do_not_cancel_a_close(dlg):
    dlg.execute('MockFire("QUEST_DETAIL"); REWARDS = { { "Late Name", 1 } }; MockFire("QUEST_ITEM_UPDATE")')
    assert dlg.eval("HogTronUIDialogRow1.text:GetText()") == "Late Name"   # a refresh redraws the page ...
    dlg.execute('MockFire("QUEST_FINISHED"); MockFire("QUEST_ITEM_UPDATE"); MockAdvance(0.3)')
    assert not shown(dlg)                                                  # ... but never keeps a closed one open


def test_escape_backs_out_like_blizzards_window(dlg):
    def esc():
        dlg.execute('HogTronUIDialog:Hide(); HogTronUIDialog:GetScript("OnHide")(HogTronUIDialog)')
    dlg.execute('MockFire("QUEST_DETAIL")')
    esc()
    dlg.execute('MockFire("QUEST_PROGRESS")')
    esc()
    dlg.execute('GOPT = { { name = "Hi", gossipOptionID = 1 } }; MockFire("GOSSIP_SHOW")')
    esc()
    assert calls(dlg) == [["DeclineQuest"], ["CloseQuest"], ["C_GossipInfo.CloseGossip"]]
    assert dlg.eval(f"{D}.seen.backOut") == 3


# ================================================================================================ keys + combat
def test_combat_gives_the_keys_back_and_takes_them_after(dlg):
    dlg.execute('MockFire("QUEST_DETAIL")')
    assert dlg.eval(f"{D}.keysBound") is True
    before = len(dlg.eval("MockBindings.cleared"))
    dlg.execute('MockFire("PLAYER_REGEN_DISABLED")')   # still out of lockdown inside this event
    assert len(dlg.eval("MockBindings.cleared")) == before + 1
    assert dlg.eval(f"{D}.keysBound") is False
    # a new page in combat: drawn, but no keys taken
    dlg.execute('MockState.inCombat = true; MockBindings.clicks = {}; MockFire("QUEST_PROGRESS")')
    assert shown(dlg) and bound(dlg, "SPACE") is None
    dlg.execute('MockState.inCombat = false; MockFire("PLAYER_REGEN_ENABLED")')
    assert bound(dlg, "SPACE") == "HogTronUIDialogPrimary"


def test_keys_option_off_binds_nothing(dlg):
    dlg.execute('HogHeals.db.profile.quests.dialog.keys = false; MockBindings.clicks = {}; MockFire("QUEST_DETAIL")')
    assert shown(dlg) and bound(dlg, "SPACE") is None
    assert dlg.eval("HogTronUIDialog.primary.key.text:IsShown()") is False


# ================================================================================================ failsafe
def test_a_page_that_throws_goes_to_blizzards_window(dlg):
    dlg.execute(f'{D}.Read = function() error("boom") end; MockFire("QUEST_DETAIL")')
    assert blizz(dlg) == ["QuestFrame:QUEST_DETAIL"]          # handed this very page
    assert dlg.eval('QuestFrame:IsEventRegistered("QUEST_DETAIL")') is True
    assert "boom" in dlg.eval(f"{D}.broken")
    assert any("boom" in e["msg"] for e in dlg.eval("HogHeals.errors").values())
    dlg.execute('MockFire("QUEST_DETAIL")')                    # and stays Blizzard's until /reload
    assert blizz(dlg) == ["QuestFrame:QUEST_DETAIL", "QuestFrame:QUEST_DETAIL"] and not shown(dlg)


# ================================================================================================ look, preview, options
def test_light_page_by_default_dark_on_request_and_the_old_names_still_work(dlg):
    dlg.execute('MockFire("QUEST_DETAIL")')
    assert dlg.eval("HogTronUIDialog.pageTop._texture").endswith("dialog_page_light")
    assert sum(list(dlg.eval("HogTronUIDialog.title._color").values())[:3]) < 0.6   # dark ink on paper
    dlg.execute('HogHeals:SlashCommand("dialog dark")')
    assert dlg.eval("HogHeals.db.profile.quests.dialog.theme") == "dark"
    assert dlg.eval("HogTronUIDialog.pageMid._texture").endswith("dialog_page_dark")
    assert sum(list(dlg.eval("HogTronUIDialog.title._color").values())[:3]) > 2.4  # light text on the charred page
    for old, new in (("parchment", "light"), ("ink", "dark")):
        dlg.execute(f'HogHeals.db.profile.quests.dialog.theme = "{old}"')
        assert dlg.eval(f"{D}.ThemeKey()") == new


def test_preview_needs_no_npc_and_sends_nothing(dlg):
    dlg.execute('HogHeals:SlashCommand("dialog preview")')
    assert shown(dlg) and dlg.eval(f"{D}.model.kind") == "detail"
    assert dlg.eval("HogTronUIDialog.primary.label:GetText()") == "Accept"
    dlg.execute("HogTronUIDialogPrimary:Click()")
    assert calls(dlg) == [] and not shown(dlg)
    dlg.execute('HogHeals:SlashCommand("dialog preview reward")')
    assert shown(dlg)
    assert dlg.eval("HogTronUIDialog.title:GetText()") == "Wolves Across the Border"
    click_pick(dlg, 2)
    assert dlg.eval(f"{D}.choice") == 2 and dlg.eval(f"{D}.model.primary.disabled") is False
    dlg.execute("HogTronUIDialogPrimary:Click()")
    assert calls(dlg) == [] and not shown(dlg)


def test_max_level_drops_the_share(dlg):
    dlg.execute('MockUnits.player.level = 60; MockFire("QUEST_DETAIL")')
    assert dlg.eval("HogTronUIDialog.xp:GetText()") == ic("reward_xp") + " +1,250 XP"


def test_pure_helpers(dlg):
    assert dlg.eval(f"{D}.XPShare(1250, 8800)") == 14
    assert dlg.eval(f"{D}.XPShare(0, 8800)") is None
    assert dlg.eval(f"{D}.XPShare(50, 0)") is None
    assert dlg.eval(f"{D}.Thousands(1234567)") == "1,234,567"
    assert dlg.eval(f"{D}.Thousands(999)") == "999"
    assert dlg.eval(f"{D}.Thousands(1000)") == "1,000"
    assert dlg.eval(f"{D}.XPLine(0)") is None
    short = dlg.eval(f'{D}.EstimateHeight("short", 400, 14)')
    long = dlg.eval(f'{D}.EstimateHeight(string.rep("word ", 200), 400, 14)')
    assert 0 < short < long
    assert dlg.eval(f'{D}.EstimateHeight("", 400, 14)') == 0


def test_options_and_diag(dlg):
    opts = dlg.eval("HogHealsQuests.Options.Build()")
    assert opts["args"]["dialog"]["args"]["theme"]["values"]["light"] == "Parchment (light)"
    dlg.execute('MockFire("QUEST_DETAIL")')
    dlg.execute('HogHeals:SlashCommand("dialogdiag")')
    d = dlg.eval("HogHeals.db.global.diag.dialog")
    assert d["active"]["quest"] is True and d["active"]["gossip"] is True
    assert "QUEST_DETAIL" in d["muted"]["QuestFrame"]
    assert any("show:detail=1" in l for l in dlg.eval(f"{D}.Lines()").values())
    assert dlg.eval("#HogHeals.errors") == 0


# ================================================================================================ the page (redesign 10/14)
def test_the_page_is_three_slices_that_add_up_to_the_window(dlg):
    dlg.execute('MockFire("QUEST_DETAIL")')
    h = dlg.eval("HogTronUIDialog:GetHeight()")
    parts = [dlg.eval(f"HogTronUIDialog.{p}:GetHeight()") for p in ("pageTop", "pageMid", "pageBot")]
    assert sum(parts) == pytest.approx(h)
    assert parts[0] == pytest.approx(parts[2])                      # torn top and bottom keep their shape
    assert dlg.eval("HogTronUIDialog:GetWidth()") == 540
    # a long text grows the page, it never runs off it
    dlg.execute('TEXT = string.rep("The wolves came again last night. ", 40); MockFire("QUEST_DETAIL")')
    assert dlg.eval("HogTronUIDialog:GetHeight()") > h


def test_objectives_as_a_list_when_the_client_has_them(dlg):
    dlg.execute('function GetQuestID() return 7 end; MockFire("QUEST_DETAIL")')
    assert dlg.eval("HogTronUIDialog.objectives:GetText()") == "- Kobold Vermin slain: 3/8"
    assert dlg.eval("HogTronUIDialog.objTag.text:GetText()") == "Objectives"
    dlg.execute('function GetQuestID() return 0 end; MockFire("QUEST_DETAIL")')
    assert dlg.eval("HogTronUIDialog.objectives:GetText()").startswith("Bring 8")   # the paragraph otherwise


def test_main_button_left_way_out_right_with_key_caps(dlg):
    dlg.execute('MockFire("QUEST_DETAIL")')
    px = list(dlg.eval("HogTronUIDialogPrimary._points[1]").values())[3]
    sx = list(dlg.eval("HogTronUIDialogSecondary._points[1]").values())[3]
    assert px < sx
    assert dlg.eval("HogTronUIDialog.primary.key.text:GetText()") == "Space"
    assert dlg.eval("HogTronUIDialog.secondary.key.text:GetText()") == "Esc"
    assert dlg.eval("HogTronUIDialogPrimary:GetWidth()") == dlg.eval("HogTronUIDialogSecondary:GetWidth()")


def test_rewards_are_icon_tiles_two_to_a_row_in_colours_that_read_on_paper(dlg):
    dlg.execute('CHOICES = { { "Gloves", 1, 1, 2 }, { "Tunic", 2, 1, 2 }, { "Pants", 3, 1, 1 } }; REWARDS = { { "Cloak", 4, 1, 3 } }; MockFire("QUEST_DETAIL")')
    pts = [list(dlg.eval(f"HogTronUIDialogRow{i}._points[1]").values()) for i in (1, 2, 3, 4)]
    assert pts[0][4] == pts[1][4] and pts[0][3] < pts[1][3]          # 1 and 2 side by side
    assert pts[2][4] < pts[0][4]                                     # 3 on the next line
    assert dlg.eval("HogTronUIDialog.chooseCap:GetText()") == "Choose one of these rewards:"
    assert dlg.eval("HogTronUIDialog.alsoCap:GetText()") == "You will also receive:"
    green = list(dlg.eval("HogTronUIDialogRow1.text._color").values())[:3]
    assert green == pytest.approx([0.08, 0.42, 0.02])                 # Blizzard's bright green would vanish on parchment
    assert dlg.eval("HogTronUIDialogRow1.icon._texture") == 1
    assert dlg.eval("HogTronUIDialogRow1.key.text:IsShown()") is False  # an offer is not picked on the detail page



# ---------------------------------------------------------------- reward polish (Sean 2026-10-17, a turn-in page in game)
# "the text gets close to the 2" / "images for the currency received instead of S or C" / "a small image for XP that
# is slightly different" / "the spacing on the bottom left with the left button and the bottom of the dialog box".
def test_money_is_coin_icons_and_zero_coins_are_left_out(dlg):
    icon = lambda c: ic("coin_" + c)
    assert dlg.eval(f"{D}.Money(600, 14)") == "6" + icon("silver")                      # was "6s 0c"
    assert dlg.eval(f"{D}.Money(1234567, 14)") == "123" + icon("gold") + "  45" + icon("silver") + "  67" + icon("copper")
    assert dlg.eval(f"{D}.Money(5, 14)") == "5" + icon("copper")
    assert dlg.eval(f"{D}.Money(0, 14)") is None and dlg.eval(f"{D}.Money(nil, 14)") is None
    assert "s " not in dlg.eval(f"{D}.Money(600, 14)") and not dlg.eval(f"{D}.Money(600, 14)").endswith("c")


def test_the_reward_icons_ship_with_the_addon():
    import pathlib
    media = pathlib.Path(__file__).resolve().parent.parent / "HogTronUI" / "Media"
    for n in ("coin_gold", "coin_silver", "coin_copper", "reward_xp"):
        assert (media / f"{n}.tga").exists(), n


def test_a_reward_name_stops_short_of_its_number_chip(dlg):
    dlg.execute('CHOICES = { { "Hunter\'s Simple Cloak", 1, 1, 2 }, { "Highlands Defender\'s Shield", 2, 1, 2 } }; MockFire("QUEST_COMPLETE")')
    for i in (1, 2):
        r = f"HogTronUIDialogRow{i}"
        assert dlg.eval(f"{r}.key.text:IsShown()") is True
        text_right = dlg.eval(f"{r}.text._points[1][4]") + dlg.eval(f"{r}.text:GetWidth()")
        chip_left = dlg.eval(f"{r}.key.bg.box.x")
        assert chip_left - text_right >= 8, (text_right, chip_left)


def test_the_button_row_clears_the_torn_bottom_edge(dlg):
    dlg.execute('MockFire("QUEST_DETAIL")')
    W, H = dlg.eval("HogTronUIDialog:GetWidth()"), dlg.eval("HogTronUIDialog:GetHeight()")
    s = W / 512
    top = -dlg.eval("HogTronUIDialogPrimary._points[1][5]")                  # TOPLEFT y below the frame's top
    gap = H - (top + dlg.eval("HogTronUIDialogPrimary:GetHeight()"))           # paper under the buttons, px
    assert gap >= (46 + 10) * s, (gap, s)                                     # the art's worst tear is 46 px (x 56)
