# Experience bar (HogHeals_HUD/XPBar.lua): the "xp" HUD row - fill, rested overlay, "quests in the log" overlay,
# level / numbers left, pace from Session right. From the ForeverXP Bar clip (2026-10-08): "XP per hour, session
# playtime, and how much your quest will contribute to your next level".
import pytest

X = "HogHealsHUD.XPBar"

MODERN_LOG = """
  QL = {
    { questID = 11, title = "Boars", level = 20, complete = true,  xp = 500 },
    { questID = 12, title = "Wolves", level = 21, complete = false, xp = 700 },
    { questID = 13, title = "Zone", level = 20, isHeader = true },
  }
  C_QuestLog = C_QuestLog or {}
  C_QuestLog.GetNumQuestLogEntries = function() return #QL, #QL end
  C_QuestLog.GetInfo = function(i) return QL[i] end
  C_QuestLog.IsComplete = function(id) for _, q in ipairs(QL) do if q.questID == id then return q.complete end end end
  function GetQuestLogRewardXP(id) for _, q in ipairs(QL) do if q.questID == id then return q.xp end end return 0 end
"""


@pytest.fixture
def xp(lua):
    lua.execute("""
      XP, XPMAX, LVL, RESTED, MAXLVL = 1000, 10000, 20, 0, 60
      function UnitXP(u) return XP end
      function UnitXPMax(u) return XPMAX end
      function UnitLevel(u) return LVL end
      function GetXPExhaustion() return RESTED > 0 and RESTED or nil end
      function GetMaxPlayerLevel() return MAXLVL end
      MockUnits.player.level = 20
      MockState.time = 1000
    """)
    lua.execute(MODERN_LOG)
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Frames")
    lua.load_addon("HogHeals_HUD")
    lua.player_login()
    lua.execute(f"HH_x = HogHealsHUD.HUD.rows.xp; HH_x:SetWidth(200); {X}.Update()")
    return lua


# ------------------------------------------------------------------------------------------------ pure maths
def test_compute_fractions(xp):
    c = xp.eval(f"{X}.Compute(1000, 10000, 2000, 500)")
    assert c["fill"] == 0.1
    assert c["restedTo"] == 0.3 and c["questTo"] == 0.15
    assert c["percent"] == 10 and c["restedPercent"] == 20 and c["questPercent"] == 5
    assert c["remaining"] == 9000


def test_compute_clamps_and_refuses_bad_input(xp):
    c = xp.eval(f"{X}.Compute(9500, 10000, 4000, 9000)")
    assert c["restedTo"] == 1 and c["questTo"] == 1
    assert xp.eval(f"{X}.Compute(nil, 10000)") is None
    assert xp.eval(f"{X}.Compute(100, 0)") is None
    assert xp.eval(f"{X}.Compute(100, 1000, nil, nil)")["restedTo"] == 0.1


def test_commas(xp):
    assert xp.eval(f'{X}.Commas(31700)') == "31,700"
    assert xp.eval(f'{X}.Commas(999)') == "999"
    assert xp.eval(f'{X}.Commas(1234567)') == "1,234,567"


# ------------------------------------------------------------------------------------------------ the row
def test_row_exists_and_is_in_the_strip(xp):
    assert xp.eval("HogHealsHUD.HUD.rows.xp ~= nil")
    d = xp.eval("HogHeals.db.profile.hud")
    h = xp.eval("HogHealsHUD.HUD.Layout()")
    assert h == d["castbarHeight"] + d["swingHeight"] + d["manaHeight"] + d["xpHeight"] + d["infoHeight"] + 4 * d["rowSpacing"]
    xp.execute("HogHeals.db.profile.hud.showXP = false")
    h2 = xp.eval("HogHealsHUD.HUD.Layout()")
    assert h2 == h - d["xpHeight"] - d["rowSpacing"]
    assert xp.eval("HogHealsHUD.HUD.rows.xp:IsShown()") is False


def test_fill_and_left_text(xp):
    assert xp.eval("HH_x:GetValue()") == 0.1
    assert xp.eval("HH_x:IsShown()") is True
    left = xp.eval("HH_x.left:GetText()")
    assert "20" in left and "1,000 / 10,000" in left and "10%" in left


def test_rested_overlay_and_text(xp):
    xp.execute(f"RESTED = 2000; {X}.Update()")
    assert xp.eval("HH_x.rested:IsShown()") is True
    # overlay runs from the fill head to xp+rested: 10% -> 30% of a 200 px bar = 40 px wide
    assert xp.eval("HH_x.rested:GetWidth()") == 40
    assert "+20% rested" in xp.eval("HH_x.right:GetText()")
    xp.execute(f"RESTED = 0; {X}.Update()")
    assert xp.eval("HH_x.rested:IsShown()") is False


def test_quest_xp_counts_turn_in_ready_quests_by_default(xp):
    assert xp.eval(f"{X}.QuestXP()") == 500
    assert xp.eval(f"{X}.path.reward") == "GetQuestLogRewardXP(questID)"
    assert xp.eval("HH_x.quest:IsShown()") is True
    assert xp.eval("HH_x.quest:GetWidth()") == pytest.approx(10)     # 5% of 200
    assert "+5% quests" in xp.eval("HH_x.right:GetText()")


def test_quest_xp_mode_all_counts_every_quest_in_the_log(xp):
    xp.execute(f'HogHeals.db.profile.hud.xp.questMode = "all"; {X}.Update()')
    assert xp.eval(f"{X}.QuestXP()") == 1200
    assert "+12% quests" in xp.eval("HH_x.right:GetText()")


def test_quest_overlay_off_hides_it(xp):
    xp.execute(f"HogHeals.db.profile.hud.xp.showQuest = false; {X}.Update()")
    assert xp.eval("HH_x.quest:IsShown()") is False
    assert "quests" not in xp.eval("HH_x.right:GetText()")


def test_pace_from_session_on_the_right(xp):
    # a minute of play, 600 xp gained -> session rate 36k/h; 8,400 left -> 14 min
    xp.execute(f"""
      HogHeals.Session.Reset()
      MockState.time = 1060; XP = 1600; MockFire("PLAYER_XP_UPDATE")
    """)
    right = xp.eval("HH_x.right:GetText()")
    assert "36k xp/h" in right and "lvl in 14m" in right
    assert xp.eval("HH_x:GetValue()") == 0.16


def test_secret_xp_does_not_throw_and_shows_dashes(xp):
    xp.execute(f"MockSetSecrets(true); function UnitXP(u) return MockSecret(1500) end; {X}.Update()")
    assert xp.eval("HH_x.left:GetText()") == "-"
    assert xp.eval("HH_x:GetValue()") == 0
    assert xp.eval(f"{X}.seen.secretXP") >= 1
    xp.execute("MockSetSecrets(false)")


def test_hidden_at_max_level_unless_told_otherwise(xp):
    xp.execute(f"LVL = 60; {X}.Update()")
    assert xp.eval("HH_x:IsShown()") is False
    xp.execute(f"HogHeals.db.profile.hud.xp.hideAtMax = false; {X}.Update()")
    assert xp.eval("HH_x:IsShown()") is True
    xp.execute(f"LVL = 20; HogHeals.db.profile.hud.xp.hideAtMax = true; {X}.Update()")
    assert xp.eval("HH_x:IsShown()") is True


def test_xp_user_disabled_hides_the_row(xp):
    xp.execute(f"function IsXPUserDisabled() return true end; {X}.Update()")
    assert xp.eval("HH_x:IsShown()") is False
    xp.execute(f"IsXPUserDisabled = nil; {X}.Update()")
    assert xp.eval("HH_x:IsShown()") is True


def test_events_refresh_the_bar(xp):
    xp.execute('XP = 2000; MockFire("PLAYER_XP_UPDATE")')
    assert xp.eval("HH_x:GetValue()") == 0.2
    xp.execute('QL[2].complete = true; MockFire("QUEST_LOG_UPDATE")')
    assert xp.eval(f"{X}.QuestXP()") == 1200
    xp.execute('RESTED = 1000; MockFire("UPDATE_EXHAUSTION")')
    assert xp.eval("HH_x.rested:IsShown()") is True


def test_onupdate_throttle_refreshes_pace_text(xp):
    # the pace text is time-based, so the row refreshes itself every REFRESH seconds without an event
    xp.execute(f"{X}.seen.updates = 0; local n = {X}.seen.updates")
    before = xp.eval(f"{X}.seen.updates")
    xp.execute(f"{X}.OnUpdate(HH_x, {X}.REFRESH - 0.1)")
    assert xp.eval(f"{X}.seen.updates") == before
    xp.execute(f"{X}.OnUpdate(HH_x, 0.2)")
    assert xp.eval(f"{X}.seen.updates") == before + 1


# ------------------------------------------------------------------------------------------------ legacy log
def test_legacy_quest_log_path_selects_and_restores(lua):
    lua.execute("""
      XP, XPMAX, LVL, RESTED, MAXLVL = 1000, 10000, 20, 0, 60
      function UnitXP(u) return XP end
      function UnitXPMax(u) return XPMAX end
      function UnitLevel(u) return LVL end
      function GetMaxPlayerLevel() return MAXLVL end
      C_QuestLog = nil
      LQ = { { "Boars", 20, nil, nil, nil, 1, nil, 11, xp = 500 }, { "Wolves", 21, nil, nil, nil, nil, nil, 12, xp = 700 } }
      SEL = 2
      function GetNumQuestLogEntries() return #LQ, #LQ end
      function GetQuestLogTitle(i) local q = LQ[i] if not q then return nil end return q[1], q[2], q[3], q[4], nil, q[6], nil, q[8] end
      function GetQuestLogSelection() return SEL end
      function SelectQuestLogEntry(i) SEL = i end
      function GetQuestLogRewardXP() return LQ[SEL] and LQ[SEL].xp or 0 end
    """)
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Frames")
    lua.load_addon("HogHeals_HUD")
    lua.player_login()
    assert lua.eval(f"{X}.QuestXP()") == 500
    assert lua.eval(f"{X}.path.reward") == "SelectQuestLogEntry+GetQuestLogRewardXP()"
    assert lua.eval("SEL") == 2     # the player's selection is put back
    lua.execute('HogHeals.db.profile.hud.xp.questMode = "all"')
    assert lua.eval(f"{X}.QuestXP()") == 1200


def test_no_reward_api_means_zero_not_error(lua):
    lua.execute("""
      function UnitXP(u) return 1000 end
      function UnitXPMax(u) return 10000 end
      C_QuestLog = nil
      GetQuestLogRewardXP = nil
    """)
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Frames")
    lua.load_addon("HogHeals_HUD")
    lua.player_login()
    assert lua.eval(f"{X}.QuestXP()") == 0
    assert lua.eval(f"{X}.path.reward") == "none"


# ------------------------------------------------------------------------------------------------ options + diag
def test_options_group_and_diag(xp):
    assert xp.eval("HogHealsHUD.Options.Build().args.xp ~= nil")
    assert xp.eval("HogHealsHUD.Options.Build().args.xp.args.enabled ~= nil")
    lines = xp.eval(f"{X}.Lines()")
    joined = " ".join(lines.values())
    assert "1,000 / 10,000" in joined and "quests" in joined
