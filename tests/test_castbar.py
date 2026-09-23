import pytest


@pytest.fixture
def cb(hud):
    hud.execute('''
      HH_cb = HogHealsHUD.HUD.rows.castbar
      HH_cb:SetWidth(200)
      MockState.time = 100
      MockState.latencyWorld = 250
      MockUnits.target = { name = "Zugzug", class = "WARRIOR", health = 50, maxHealth = 100 }
    ''')
    return hud


def start_cast(f, name="Greater Heal", dur=2.5, interruptible=True):
    # UnitCastingInfo: name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible
    f.execute(f'''
      MockUnits.player.casting = {{ "{name}", "{name}", "icon", {100 * 1000}, {int((100 + dur) * 1000)}, false, 1, {"false" if interruptible else "true"} }}
      MockFire("UNIT_SPELLCAST_START", "player", 1, 2060)
    ''')


def test_start_shows_bar_with_target_and_latency(cb):
    start_cast(cb)
    assert cb.eval('HH_cb:IsShown()') is True
    assert cb.eval('HH_cb.text:GetText()') == "Greater Heal » Zugzug"    # Latin-1 chevron: "→" is not in the fonts
    assert cb.eval('HH_cb.latency:IsShown()') is True
    assert cb.eval('HH_cb.latency:GetWidth()') == 20.0  # 250ms / 2500ms * 200px
    assert cb.eval('HogHealsHUD.Castbar.Progress(HogHealsHUD.Castbar.state, 101.25)') == 0.5


def test_time_text_and_precision(cb):
    start_cast(cb)
    cb.execute('MockState.time = 101.25; HogHealsHUD.Castbar.OnUpdate(HH_cb)')
    assert cb.eval('HH_cb.time:GetText()') == "1.3"
    cb.execute('HogHeals.db.profile.hud.castbar.precision = 2; MockState.time = 101.25; HogHealsHUD.Castbar.OnUpdate(HH_cb)')
    assert cb.eval('HH_cb.time:GetText()') == "1.25"


def test_delayed_extends_end(cb):
    start_cast(cb)
    cb.execute('MockUnits.player.casting[5] = 103000; MockFire("UNIT_SPELLCAST_DELAYED", "player", 1, 2060)')
    assert cb.eval('HogHealsHUD.Castbar.state.endTime') == 103.0


def test_stop_hides(cb):
    start_cast(cb)
    cb.execute('MockUnits.player.casting = nil; MockFire("UNIT_SPELLCAST_STOP", "player", 1, 2060)')
    assert cb.eval('HH_cb:IsShown()') is False


def test_interrupted_flashes_then_hides(cb):
    start_cast(cb)
    cb.execute('MockUnits.player.casting = nil; MockFire("UNIT_SPELLCAST_INTERRUPTED", "player", 1, 2060)')
    assert cb.eval('HH_cb:IsShown()') is True
    r, g, b = list(cb.eval('{HH_cb:GetStatusBarColor()}').values())[:3]
    assert r > g
    cb.execute('MockAdvance(0.5)')
    assert cb.eval('HH_cb:IsShown()') is False


def test_channel_drains(cb):
    cb.execute('''
      MockUnits.player.channeling = { "Tranquility", "Tranquility", "icon", 100000, 110000, false, false }
      MockFire("UNIT_SPELLCAST_CHANNEL_START", "player", 2, 740)
    ''')
    assert cb.eval('HogHealsHUD.Castbar.state.channel') is True
    assert cb.eval('HogHealsHUD.Castbar.Progress(HogHealsHUD.Castbar.state, 102.5)') == 0.75  # drains right→left
    cb.execute('MockUnits.player.channeling = nil; MockFire("UNIT_SPELLCAST_CHANNEL_STOP", "player", 2, 740)')
    assert cb.eval('HH_cb:IsShown()') is False


def test_uninterruptible_colour(cb):
    start_cast(cb, interruptible=False)
    r, g, b = list(cb.eval('{HH_cb:GetStatusBarColor()}').values())[:3]
    assert (round(r, 2), round(g, 2), round(b, 2)) == (0.6, 0.6, 0.6)


def test_hide_blizzard_castbar(hud):
    hud.execute('CastingBarFrame = CreateFrame("Frame", "CastingBarFrame"); CastingBarFrame:RegisterEvent("UNIT_SPELLCAST_START"); HogHealsHUD.Castbar.ApplyBlizzard()')
    assert hud.eval('CastingBarFrame:IsEventRegistered("UNIT_SPELLCAST_START")') is False
    hud.execute('HogHeals.db.profile.hud.castbar.hideBlizzard = false; HogHealsHUD.Castbar.ApplyBlizzard()')
    assert hud.eval('CastingBarFrame:IsEventRegistered("UNIT_SPELLCAST_START")') is True


def test_castdiag_reports_the_texture_the_cast_handed_us(cb):
    start_cast(cb)
    lines = cb.eval('table.concat(HogHealsHUD.Castbar.Diagnose(), "\\n")')
    assert "last cast: Greater Heal" in lines and "texture=" in lines and "icon: shown=" in lines
