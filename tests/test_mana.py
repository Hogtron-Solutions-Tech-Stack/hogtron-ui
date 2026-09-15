import pytest


@pytest.fixture
def m(hud):
    hud.execute('''
      HH_m = HogHealsHUD.HUD.rows.mana
      HH_m:SetWidth(200)
      MockState.time = 100
      MockUnits.player.power = 800; MockUnits.player.maxPower = 1000; MockUnits.player.powerType = "MANA"
      HogHealsHUD.Mana.Reset()
      HogHealsHUD.Mana.Update()
    ''')
    return hud


def test_bar_and_text_modes(m):
    assert m.eval('HH_m:GetValue()') == 800
    assert m.eval('HH_m.text:GetText()') == "800 / 1000"
    m.execute('HogHeals.db.profile.hud.mana.textMode = "percent"; HogHealsHUD.Mana.Update()')
    assert m.eval('HH_m.text:GetText()') == "80%"
    m.execute('HogHeals.db.profile.hud.mana.textMode = "none"; HogHealsHUD.Mana.Update()')
    assert m.eval('HH_m.text:GetText()') == ""


def test_observe_pure_fsr_and_ticks(hud):
    # Observe(state, mana, t) -> event
    hud.execute('HH_s = HogHealsHUD.Mana.NewState(1000, 100)')
    assert hud.eval('HogHealsHUD.Mana.Observe(HH_s, 1000, 100.5)') is None
    # a cast spends mana -> caller marks the cast; FSR begins
    hud.execute('HogHealsHUD.Mana.OnCast(HH_s, 900, 101)')
    assert hud.eval('HH_s.fsrEnd') == 106.0
    # gains during FSR are ignored (no tick scheduling)
    assert hud.eval('HogHealsHUD.Mana.Observe(HH_s, 920, 103)') is None
    assert hud.eval('HH_s.nextTick') is None
    # after FSR, first gain is a tick and schedules the next one 2s later
    assert hud.eval('HogHealsHUD.Mana.Observe(HH_s, 940, 106.4)') == "tick"
    assert hud.eval('HH_s.nextTick') == 108.4
    assert hud.eval('HogHealsHUD.Mana.Observe(HH_s, 960, 108.4)') == "tick"
    assert hud.eval('HH_s.nextTick') == 110.4


def test_cast_without_mana_drop_no_fsr(hud):
    hud.execute('HH_s = HogHealsHUD.Mana.NewState(1000, 100); HogHealsHUD.Mana.OnCast(HH_s, 1000, 101)')
    assert hud.eval('HH_s.fsrEnd') is None


def test_spellcast_event_starts_overlay(m):
    m.execute('''
      MockUnits.player.power = 700
      MockFire("UNIT_SPELLCAST_SUCCEEDED", "player", 1, 2060)
    ''')
    assert m.eval('HH_m.fsr:IsShown()') is True
    assert m.eval('HogHealsHUD.Mana.state.fsrEnd') == 105.0
    m.execute('MockState.time = 102.5; HogHealsHUD.Mana.OnUpdate(HH_m)')
    assert m.eval('HH_m.fsr:GetWidth()') == 100.0  # half of 200 drained
    m.execute('MockState.time = 105.1; HogHealsHUD.Mana.OnUpdate(HH_m)')
    assert m.eval('HH_m.fsr:IsShown()') is False


def test_tick_spark_moves(m):
    m.execute('''
      HogHealsHUD.Mana.state.lastTick = 110; HogHealsHUD.Mana.state.nextTick = 112
      MockState.time = 111; HogHealsHUD.Mana.OnUpdate(HH_m)
    ''')
    assert m.eval('HH_m.tick:IsShown()') is True
    x = list(m.eval('{HH_m.tick:GetPoint()}').values())[3]
    assert x == 100.0  # halfway across 200px


def test_non_mana_hides_row(m):
    m.execute('MockUnits.player.powerType = "RAGE"; HogHealsHUD.Mana.Update()')
    assert m.eval('HH_m:IsShown()') is False
