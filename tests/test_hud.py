def test_anchor_and_rows_exist(hud):
    assert hud.eval('HogHealsHUDAnchor ~= nil')
    for row in ("castbar", "swing", "mana", "xp", "info"):
        assert hud.eval(f'HogHealsHUD.HUD.rows.{row} ~= nil'), row
    p = list(hud.eval('{HogHealsHUDAnchor:GetPoint()}').values())
    assert p[0] == "CENTER" and p[3] == 0 and p[4] == -180


def test_layout_stacks_rows_and_collapses_disabled(hud):
    h = hud.eval('HogHealsHUD.HUD.Layout()')
    d = hud.eval('HogHeals.db.profile.hud')
    # the experience row is off the strip by default (its own bar, hud.xp.mode = "bar")
    assert h == d["castbarHeight"] + d["swingHeight"] + d["manaHeight"] + d["infoHeight"] + 3 * d["rowSpacing"]
    hud.execute('HogHeals.db.profile.hud.showMana = false')
    h2 = hud.eval('HogHealsHUD.HUD.Layout()')
    assert h2 == d["castbarHeight"] + d["swingHeight"] + d["infoHeight"] + 2 * d["rowSpacing"]
    assert hud.eval('HogHealsHUD.HUD.rows.mana:IsShown()') is False
    # info row sits directly under the swing row when mana is hidden; swing off -> directly under the castbar
    # (the xp row, which also sits between them since 2026-10-08, off for these two checks)
    hud.execute('HogHeals.db.profile.hud.showXP = false; HogHealsHUD.HUD.Layout()')
    y_info = list(hud.eval('{HogHealsHUD.HUD.rows.info:GetPoint()}').values())[4]
    assert y_info == -(d["castbarHeight"] + d["rowSpacing"] + d["swingHeight"] + d["rowSpacing"])
    hud.execute('HogHeals.db.profile.hud.showSwing = false; HogHealsHUD.HUD.Layout()')
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


def test_cast_bar_and_mana_bar_take_their_own_width_or_the_strips(hud):
    # Sean 2026-10-18: sizes per bar in /hh unlock - the cast bar and mana bar get their own width like the swing bar
    hud.execute('local d = HogHeals.db.profile.hud; d.width = 300; d.mana.width = 200; d.castbar.width = 0; HogHealsHUD.HUD.Refresh()')
    assert hud.eval('HogHealsHUD.HUD.rows.mana:GetWidth()') == 200
    assert hud.eval('HogHealsHUD.HUD.rows.mana._points[1][1]') == "TOP"             # centred on the strip
    assert hud.eval('HogHealsHUD.HUD.rows.castbar:GetWidth()') == 300               # 0 = the strip's width
    hud.execute('HogHeals.db.profile.hud.mana.width = 0; HogHealsHUD.HUD.Refresh()')
    assert hud.eval('HogHealsHUD.HUD.rows.mana:GetWidth()') == 300


# ---------------------------------------------------------------- bars that move on their own (backlog 2026-10-18)
def test_a_detached_bar_sits_at_its_own_spot_and_the_strip_closes_up(hud):
    hud.execute('''local d = HogHeals.db.profile.hud
      d.width, d.castbarHeight, d.swingHeight, d.rowSpacing, d.showSwing = 300, 18, 16, 2, true
      d.castbar.detached, d.castbar.point, d.castbar.x, d.castbar.y = true, "CENTER", 120, -80
      HogHealsHUD.HUD.Refresh()''')
    cb = "HogHealsHUD.HUD.rows.castbar"
    p = list(hud.eval(f'{cb}._points[1]').values())
    assert p[0] == "CENTER" and hud.eval(f'{cb}._points[1][2] == UIParent') and p[3] == 120 and p[4] == -80
    assert hud.eval(f'{cb}:GetWidth()') == 300 and hud.eval(f'{cb}.detached') is True
    # the swing bar moves up to the top of the strip: the cast bar no longer takes a row there
    assert hud.eval('HogHealsHUD.HUD.rows.swing._points[1][5]') == 0
    # back in the strip
    hud.execute('HogHealsHUD.HUD.Detach("castbar", false)')
    assert hud.eval(f'{cb}.detached') is None and hud.eval(f'{cb}._points[1][2] == HogHealsHUD.HUD.container')
    assert hud.eval('HogHealsHUD.HUD.rows.swing._points[1][5]') == -(18 + 2)


def test_detaching_starts_the_bar_where_it_already_is(hud):
    hud.execute('''UIParent.GetCenter = function() return 960, 540 end
      HogHealsHUD.HUD.rows.mana.GetCenter = function() return 1000, 400 end
      HogHealsHUD.HUD.Detach("mana", true)''')
    m = "HogHeals.db.profile.hud.mana"
    assert hud.eval(f'{m}.detached') is True and hud.eval(f'{m}.x') == 40 and hud.eval(f'{m}.y') == -140
