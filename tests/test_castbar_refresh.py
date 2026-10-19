# Eating and drinking on the HUD cast bar (Sean 2026-10-18: "I want to make drinking and eat cast bars"). On
# Classic-rules clients food and drink are a buff you sit with, not a cast: HogTron_HUD/Castbar.lua CheckRefresh shows
# that buff as a cast filling over its duration, in its own strip, plain values only.
import pytest

from test_castbar import cb  # noqa: F401  (fixture)

CB = "HogHealsHUD.Castbar"


@pytest.fixture
def eat(cb):  # noqa: F811
    cb.execute('MockState.playerClass = "MAGE"')
    return cb


def buffs(f, *auras):
    # MockUnits.player.auras: name, duration, expires (GetTime units), spellId; helpful (no type)
    rows = ", ".join('{ name = "%s", duration = %s, expires = %s, spellId = %s, icon = "%s", source = "player" }'
                     % (n, d, e, sid, n.lower()) for n, d, e, sid in auras)
    f.execute(f'MockUnits.player.auras = {{ {rows} }}; MockFire("UNIT_AURA", "player")')


def shown(f):
    return f.eval("HH_cb:IsShown()") is True


def test_drinking_fills_the_bar_over_the_buff_in_its_own_strip(eat):
    buffs(eat, ("Arcane Intellect", 1800, 1900, 1459), ("Drink", 18, 118, 430))   # sat down at t=100
    assert shown(eat)
    assert eat.eval("HH_cb.text:GetText()") == "Drink"                     # no "» Zugzug": you are sitting down
    assert eat.eval(f"{CB}.state.aura.label") == "Drink"
    assert eat.eval(f"{CB}.state.spellArt") == "spell_drink" and eat.eval(f"{CB}.state.theme") == "water"
    assert eat.eval(f"{CB}.state.channel") is False and eat.eval("HH_cb.latency:IsShown()") is False
    assert eat.eval(f"{CB}.Progress({CB}.state, 109)") == pytest.approx(0.5)  # fills up, halfway at 9 of 18 s
    rec = eat.eval("HogHeals.db.global.diag.refreshBar")
    assert rec["why"] == "shown" and rec["label"] == "Drink" and rec["duration"] == 18 and rec["reader"] == "UnitAura"


def test_eating_and_drinking_at_once_is_one_bar_to_the_later_end(eat):
    buffs(eat, ("Food", 21, 121, 433), ("Drink", 18, 118, 430))
    assert eat.eval("HH_cb.text:GetText()") == "Food & Drink"
    assert eat.eval(f"{CB}.state.endTime") == 121
    assert eat.eval(f"{CB}.state.spellArt") == "spell_food" and eat.eval(f"{CB}.state.theme") == "gold"


def test_standing_up_clears_it_and_other_buffs_never_show(eat):
    buffs(eat, ("Food", 21, 121, 433))
    assert shown(eat)
    buffs(eat, ("Well Fed", 900, 1000, 19705))                              # the buff after eating is not eating
    assert not shown(eat) and eat.eval(f"{CB}.state.aura") is None


def test_a_real_cast_wins_and_stray_stop_or_fail_events_leave_the_food(eat):
    buffs(eat, ("Drink", 18, 118, 430))
    eat.execute('MockFire("UNIT_SPELLCAST_STOP", "player", 1, 430); MockFire("UNIT_SPELLCAST_FAILED", "player", 1, 133)')
    eat.execute("MockAdvance(0.5)")                                         # a "Failed" flash would be gone by now
    assert shown(eat) and eat.eval(f"{CB}.state.aura.label") == "Drink" and eat.eval("HH_cb.text:GetText()") == "Drink"
    assert eat.eval(f"{CB}.state.casting") is True
    eat.execute('''
      MockUnits.player.casting = { "Fireball", "Fireball", "icon", 101000, 103500, false, 1, false, 133 }
      MockState.time = 101; MockFire("UNIT_SPELLCAST_START", "player", 1, 133)''')
    assert eat.eval("HH_cb.text:GetText()").startswith("Fireball") and eat.eval(f"{CB}.state.aura") is None
    eat.execute('MockFire("UNIT_AURA", "player")')                           # an aura change mid-cast: the cast stays
    assert eat.eval("HH_cb.text:GetText()").startswith("Fireball")
    eat.execute('MockUnits.player.casting = nil; MockState.time = 103.5; MockFire("UNIT_SPELLCAST_STOP", "player", 1, 133)')
    assert shown(eat) and eat.eval("HH_cb.text:GetText()") == "Drink"     # still sitting with the drink: back


def test_the_modern_reader_and_hidden_values(eat):
    eat.execute("MockEnableModernAuras(false)")
    buffs(eat, ("Drink", 18, 118, 430))
    assert shown(eat) and eat.eval("HogHeals.db.global.diag.refreshBar.reader") == "C_UnitAuras"
    buffs(eat)
    assert not shown(eat)
    eat.execute("MockEnableModernAuras(true)")                               # names hidden: nothing to go on, no bar
    buffs(eat, ("Drink", 18, 118, 430))
    assert not shown(eat)


def test_hidden_times_show_nothing_and_say_why(eat):
    eat.execute("MockEnableModernAuras(false)")
    eat.execute('''
      local get = C_UnitAuras.GetAuraDataByIndex
      C_UnitAuras.GetAuraDataByIndex = function(...)
        local a = get(...) if a then a.duration, a.expirationTime = MockSecret(a.duration), MockSecret(a.expirationTime) end return a
      end''')
    buffs(eat, ("Drink", 18, 118, 430))
    assert not shown(eat)
    assert eat.eval("HogHeals.db.global.diag.refreshBar.why") == "times hidden or missing (C_UnitAuras)"


def test_switched_off_or_in_combat_shows_nothing(eat):
    eat.execute("HogHeals.db.profile.hud.castbar.refresh = false")
    buffs(eat, ("Drink", 18, 118, 430))
    assert not shown(eat)
    eat.execute("HogHeals.db.profile.hud.castbar.refresh = true; MockState.inCombat = true")
    buffs(eat, ("Drink", 18, 118, 430))
    assert not shown(eat)
    eat.execute("MockState.inCombat = false")
    buffs(eat, ("Drink", 18, 118, 430))
    assert shown(eat)
    eat.execute('HogHeals.db.profile.hud.castbar.refresh = false; MockFire("UNIT_AURA", "player")')   # off mid-drink
    assert not shown(eat)


def test_castdiag_reports_the_last_food_or_drink(eat):
    lines = list(eat.eval(f"{CB}.Diagnose()").values())
    assert any("no food or drink buff seen yet" in l for l in lines)
    buffs(eat, ("Food", 21, 121, 433))
    lines = list(eat.eval(f"{CB}.Diagnose()").values())
    assert any("eating / drinking" in l and "Food - shown, 21s, reader UnitAura" in l for l in lines)
