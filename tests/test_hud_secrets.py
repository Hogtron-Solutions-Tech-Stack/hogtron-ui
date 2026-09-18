# HUD on a secret-value client (Forever beta, diag session 5 + one uncaught error pasted by the tester):
#   Pacing.lua:42  arithmetic on field 'mana'          (uncaught: it runs from a C_Timer ticker)
#   Mana.lua:21 / :31  compare on secret mana          (FSR + tick detection)
#   RankAdvisor.lua:42  attempt to call a nil value    (GetSpellBookItemName is gone)
# Probe says: UnitPower secret, UnitPowerMax not; format/tostring/concat allowed; arithmetic/compare not.
import pytest


@pytest.fixture
def shud(hud):
    frames = hud
    frames.execute('MockSetSecrets(true); MockUnits.player.power = 400; MockUnits.player.maxPower = 1000; wipe(HogHeals.errors)')
    return frames


def test_pacing_stands_down_instead_of_throwing(shud):
    shud.execute('HogHealsHUD.Pacing.OnEvent(nil, "PLAYER_REGEN_DISABLED")')
    shud.execute('HogHealsHUD.Pacing.Tick(); HogHealsHUD.Pacing.Tick()')       # raw calls: the real ticker has no pcall
    shud.execute('HogHealsHUD.Pacing.OnEvent(nil, "PLAYER_REGEN_ENABLED")')
    assert shud.eval('HogHealsHUD.Pacing.blocked') is True
    assert shud.eval('HogHealsHUD.Pacing.ticker') is None


def test_pacing_still_works_on_open_clients(hud):
    frames = hud
    frames.execute('MockSetSecrets(false); HogHealsHUD.Pacing.blocked = nil; HogHealsHUD.Pacing.OnEvent(nil, "PLAYER_REGEN_DISABLED")')
    assert frames.eval('HogHealsHUD.Pacing.state ~= nil and HogHealsHUD.Pacing.state.inCombat') is True
    frames.execute('HogHealsHUD.Pacing.OnEvent(nil, "PLAYER_REGEN_ENABLED")')


def test_mana_state_machine_accepts_secret_readings(shud):
    shud.execute('HH_ms = HogHealsHUD.Mana.NewState(UnitPower("player", 0), 10)')
    shud.execute('HogHealsHUD.Mana.OnCast(HH_ms, UnitPower("player", 0), 11)')
    assert shud.eval('HH_ms.fsrEnd') == 16          # cannot see the cost, so any successful cast starts the 5 s window
    assert shud.eval('HogHealsHUD.Mana.Observe(HH_ms, UnitPower("player", 0), 12)') is None


def test_mana_bar_draws_with_secret_power(shud):
    shud.execute('HogHealsHUD.Mana.Update()')
    assert shud.eval('HogHealsHUD.HUD.rows.mana._value') == 400
    assert shud.eval('HogHealsHUD.HUD.rows.mana._max') == 1000


def test_rank_advisor_silent_on_secret_health_and_missing_spellbook_api(shud):
    shud.execute('HH_gsb = GetSpellBookItemName; GetSpellBookItemName = nil')
    try:
        shud.execute('HogHealsHUD.RankAdvisor.Scan()')
        assert shud.eval('HogHealsHUD.RankAdvisor.Advice("player")') == ""
    finally:
        shud.execute('GetSpellBookItemName = HH_gsb')
