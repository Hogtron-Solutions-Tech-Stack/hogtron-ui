# Session (HogHeals/Core/Session.lua): time played, xp + gold gained, xp/hour, time to level; the info bar texts.
import pytest

S = "HogHeals.Session"


@pytest.fixture
def sess(lua):
    lua.execute("""
      XP, XPMAX, LVL, MONEY = 1000, 10000, 20, 50000
      function UnitXP(u) return XP end
      function UnitXPMax(u) return XPMAX end
      function GetMoney() return MONEY end
      MockUnits.player.level = 20
      function UnitLevel(u) return LVL end
      MockState.time = 1000
    """)
    lua.load_addon("HogHeals")
    lua.player_login()
    lua.execute("HogHeals.Session.Reset()")
    return lua


def stats(lua):
    return lua.eval(f"{S}.Stats()")


def test_counts_xp_gold_and_time_from_the_events(sess):
    st = stats(sess)
    assert st["xp"] == 0 and st["gold"] == 0 and st["seconds"] == 0 and st["rate"] is None
    sess.execute("MockState.time = 1120; XP = 1600; MockFire('PLAYER_XP_UPDATE'); MONEY = 52500; MockFire('PLAYER_MONEY')")
    st = stats(sess)
    assert st["xp"] == 600 and st["gold"] == 2500 and st["seconds"] == 120
    assert st["sessionRate"] == pytest.approx(600 / 120 * 3600) and st["rateSource"] == "session"
    assert st["remaining"] == 8400 and st["toLevel"] == pytest.approx(8400 / (600 / 120 * 3600) * 3600)
    assert st["goldPerHour"] == pytest.approx(2500 / 120 * 3600)


def test_a_level_up_counts_the_rest_of_the_old_bar(sess):
    sess.execute("MockState.time = 1100; XP = 9000; MockFire('PLAYER_XP_UPDATE')")
    assert stats(sess)["xp"] == 8000
    sess.execute("XP, XPMAX, LVL = 300, 12000, 21; MockFire('PLAYER_LEVEL_UP'); MockFire('PLAYER_XP_UPDATE')")
    st = stats(sess)
    assert st["xp"] == 8000 + 1000 + 300 and st["levels"] == 1 and st["level"] == 21


def test_recent_pace_beats_the_session_average_after_a_break(sess):
    # 10 minutes of fast xp, a 30-minute break, then 10 minutes slower: the ETA follows the last 15 minutes
    sess.execute("""
      for i = 1, 10 do MockState.time = 1000 + i * 60; XP = XP + 300; MockFire('PLAYER_XP_UPDATE') end
      MockState.time = 1000 + 40 * 60
      for i = 1, 10 do MockState.time = 1000 + (40 + i) * 60; XP = XP + 50; MockFire('PLAYER_XP_UPDATE') end
    """)
    st = stats(sess)
    assert st["rateSource"] == "recent"
    assert st["rate"] == pytest.approx(50 * 60, rel=0.2)                 # ~3000 xp/h, not the session's 4200
    assert st["sessionRate"] == pytest.approx(3500 / (50 * 60) * 3600)
    assert "last 15 min" in "\n".join(sess.eval(f"{S}.Lines()").values())


def test_secret_or_missing_xp_is_said_not_compared(sess):
    sess.execute("MockSetSecrets(true); function UnitXP(u) return MockSecret(1500) end; MockFire('PLAYER_XP_UPDATE')")
    st = stats(sess)
    assert st["hidden"] is not None and st["xp"] == 0 and st["toLevel"] is None
    assert any("hidden" in l for l in sess.eval(f"{S}.Lines()").values())
    assert [e["msg"] for e in sess.eval("HogHeals.errors").values()] == []


def test_formatters_and_slash(sess):
    assert sess.eval(f"{S}.FormatTime(4320)") == "1h 12m" and sess.eval(f"{S}.FormatTime(2280)") == "38m" and sess.eval(f"{S}.FormatTime(30)") == "<1m"
    assert sess.eval(f"{S}.FormatNumber(4200)") == "4.2k" and sess.eval(f"{S}.FormatNumber(812)") == "812" and sess.eval(f"{S}.FormatNumber(15000)") == "15k"
    assert sess.eval(f"{S}.FormatMoney(123456)") == "12g 34s" and sess.eval(f"{S}.FormatMoney(-250)") == "-2s 50c"
    sess.execute("MockState.time = 1120; XP = 1600; MockFire('PLAYER_XP_UPDATE'); HogHeals:SlashCommand('session')")
    chat = "\n".join(sess.eval("MockLog.chat").values())
    assert "2m played, 600 xp" in chat and "xp/h" in chat
    sess.execute("HogHeals:SlashCommand('session reset')")
    assert stats(sess)["xp"] == 0


def test_info_bar_texts(lua):
    lua.execute("""
      XP, XPMAX, LVL, MONEY = 1000, 10000, 20, 50000
      function UnitXP(u) return XP end
      function UnitXPMax(u) return XPMAX end
      function GetMoney() return MONEY end
      function UnitLevel(u) return LVL end
      MockState.time = 1000
    """)
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Skin")
    lua.player_login()
    lua.execute("HogHeals.Session.Reset(); MockState.time = 1600; XP = 2500; MockFire('PLAYER_XP_UPDATE'); MONEY = 56000; MockFire('PLAYER_MONEY')")
    P = "HogHealsSkin.InfoBar.providers"
    assert lua.eval(f"{P}.session.value()") == "10m  9.0k xp/h"
    assert lua.eval(f"{P}.tolevel.value()").startswith("lvl 21 in ")
    assert lua.eval(f"{P}.goldph.value()") == "3g 60s/h"
    slots = list(lua.eval("HogHeals.db.profile.skin.infoBar.slots").values())
    assert "session" in slots and "tolevel" in slots
