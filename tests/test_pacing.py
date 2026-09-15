def test_burn_rate_and_eta(hud):
    hud.execute('HH_p = HogHealsHUD.Pacing.NewState(1000, 0)')
    for t, mana in [(1, 950), (2, 900), (3, 850), (4, 800), (5, 750), (6, 700)]:
        hud.execute(f'HogHealsHUD.Pacing.Step(HH_p, {mana}, {t})')
    burn = hud.eval('HH_p.burn')
    assert 45 <= burn <= 50
    eta = hud.eval('HogHealsHUD.Pacing.Eta(HH_p)')
    assert 14 <= eta <= 16  # 700 / ~48


def test_regen_only_means_no_eta(hud):
    hud.execute('HH_p = HogHealsHUD.Pacing.NewState(500, 0)')
    for t, mana in [(1, 520), (2, 540), (3, 560)]:
        hud.execute(f'HogHealsHUD.Pacing.Step(HH_p, {mana}, {t})')
    assert hud.eval('HH_p.burn') == 0
    assert hud.eval('HogHealsHUD.Pacing.Eta(HH_p)') is None


def test_projection_at_target_length(hud):
    hud.execute('HH_p = HogHealsHUD.Pacing.NewState(1000, 0)')
    for t, mana in [(1, 950), (2, 900), (3, 850), (4, 800)]:
        hud.execute(f'HogHealsHUD.Pacing.Step(HH_p, {mana}, {t})')
    hud.execute('HH_p.burn = 50')
    # 300s target, 4s elapsed, 800 mana, 50/s -> 800 - 50*296 < 0 -> clamps to 0
    assert hud.eval('HogHealsHUD.Pacing.Project(HH_p, 300)') == 0
    assert hud.eval('HogHealsHUD.Pacing.Project(HH_p, 10)') == 500  # 800 - 50*6


def test_format_and_colour(hud):
    assert hud.eval('HogHealsHUD.Pacing.Fmt(95)') == "1:35"
    assert hud.eval('HogHealsHUD.Pacing.Fmt(5)') == "0:05"
    assert hud.eval('HogHealsHUD.Pacing.Colour(130)') == "normal"
    assert hud.eval('HogHealsHUD.Pacing.Colour(45)') == "amber"
    assert hud.eval('HogHealsHUD.Pacing.Colour(10)') == "red"


def test_combat_lifecycle_writes_info_line(hud):
    hud.execute('''
      HH_info = HogHealsHUD.HUD.rows.info
      MockState.time = 0
      MockUnits.player.power = 1000; MockUnits.player.maxPower = 1000
      MockFire("PLAYER_REGEN_DISABLED")
    ''')
    assert hud.eval('HogHealsHUD.Pacing.state.inCombat') is True
    for t, mana in [(1, 950), (2, 900), (3, 850), (4, 800), (5, 750)]:
        hud.execute(f'MockUnits.player.power = {mana}; MockState.time = {t}; HogHealsHUD.Pacing.Tick()')
    text = hud.eval('HH_info.left:GetText()')
    assert "OOM" in text and "0:05" in text
    hud.execute('MockFire("PLAYER_REGEN_ENABLED")')
    assert hud.eval('HogHealsHUD.Pacing.state.inCombat') is False
    assert "0:05" in hud.eval('HH_info.left:GetText()')  # summary lingers
    hud.execute('MockAdvance(11)')
    assert hud.eval('HH_info.left:GetText()') == ""
