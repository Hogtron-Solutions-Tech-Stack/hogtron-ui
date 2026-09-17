def test_anchor_and_rows_exist(hud):
    assert hud.eval('HogHealsHUDAnchor ~= nil')
    for row in ("castbar", "mana", "info"):
        assert hud.eval(f'HogHealsHUD.HUD.rows.{row} ~= nil'), row
    p = list(hud.eval('{HogHealsHUDAnchor:GetPoint()}').values())
    assert p[0] == "CENTER" and p[3] == 0 and p[4] == -180


def test_layout_stacks_rows_and_collapses_disabled(hud):
    h = hud.eval('HogHealsHUD.HUD.Layout()')
    d = hud.eval('HogHeals.db.profile.hud')
    assert h == d["castbarHeight"] + d["manaHeight"] + d["infoHeight"] + 2 * d["rowSpacing"]
    hud.execute('HogHeals.db.profile.hud.showMana = false')
    h2 = hud.eval('HogHealsHUD.HUD.Layout()')
    assert h2 == d["castbarHeight"] + d["infoHeight"] + d["rowSpacing"]
    assert hud.eval('HogHealsHUD.HUD.rows.mana:IsShown()') is False
    # info row sits directly under the castbar when mana is hidden
    y_info = list(hud.eval('{HogHealsHUD.HUD.rows.info:GetPoint()}').values())[4]
    assert y_info == -(d["castbarHeight"] + d["rowSpacing"])


def test_unlock_shows_hud_anchor(hud):
    hud.execute('HogHeals:SlashCommand("unlock")')
    assert hud.eval('HogHealsHUDAnchor:IsShown()') is True
    hud.execute('HogHeals:SlashCommand("lock")')
    assert hud.eval('HogHealsHUDAnchor:IsShown()') is False


def test_module_registered_with_options_hook(hud):
    assert hud.eval('HogHeals.modules.HUD ~= nil')
    assert hud.eval('type(HogHeals.modules.HUD.GetOptions)') == "function"
