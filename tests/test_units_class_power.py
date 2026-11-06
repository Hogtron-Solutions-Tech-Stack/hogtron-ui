# Druid mana in forms + combo points (Sean 2026-11-06: "I want energy and mana displayed for hybrid classes as well as
# combo points for feral"). HogTron_Units: a thin mana bar under the player frame while a form shows rage / energy;
# five pips over it for rogues and cat-form druids, each pip a StatusBar i-1..i fed the count (secret-safe).
# HogTron_HUD: the mana row stays in forms; a cast bar attached to the player frame hangs past both.
import pytest

from test_units import BLIZZ

# the client's power by type: 0 mana, 4 combo points, anything else / nothing = the shown power
TYPED_POWER = '''
function UnitPower(u, t)
  local m = MockUnits[u]
  local v
  if not m then v = 0 elseif t == 0 then v = m.mana or 0 elseif t == 4 then v = m.combo or 0 else v = m.power or 100 end
  if MockState.secrets then return MockSecret(v) end
  return v
end
function UnitPowerMax(u, t)
  local m = MockUnits[u]
  if not m then return 0 end
  if t == 0 then return m.maxMana or 0 elseif t == 4 then return 5 end
  return m.maxPower or 100
end
'''


def boot(lua, cls="DRUID", extra="", addons=("HogTronUI", "HogTron_Units")):
    lua.execute(BLIZZ + TYPED_POWER + f'MockState.playerClass = "{cls}"; MockUnits.player.class = "{cls}"' + extra)
    for a in addons:
        lua.load_addon(a)
    lua.player_login()
    lua.execute('wipe(HogHeals.errors)')
    return lua


def errors(lua):
    return [e["msg"] for e in lua.eval('HogHeals.errors').values()]


def shift(lua, power_type, power=None, mana=None, combo=None):
    sets = [f'MockUnits.player.powerType = "{power_type}"']
    if power is not None: sets.append(f"MockUnits.player.power = {power}")
    if mana is not None: sets.append(f"MockUnits.player.mana = {mana}; MockUnits.player.maxMana = 1200")
    if combo is not None: sets.append(f"MockUnits.player.combo = {combo}")
    lua.execute("; ".join(sets) + '; HogHealsUnits.module.events:Fire("UPDATE_SHAPESHIFT_FORM")')


def test_a_druid_in_caster_form_has_no_extra_bars(lua):
    boot(lua)
    f = "HogUIPlayer"
    # built (hidden, collapsed) so an attached cast bar already hangs past them
    assert lua.eval(f"{f}.formMana ~= nil") is True and lua.eval(f"{f}.formMana:IsShown()") is False
    assert lua.eval(f"{f}.formMana:GetHeight()") < 0.01
    assert lua.eval(f"{f}.combo:IsShown()") is False
    assert errors(lua) == []


def test_bear_form_shows_rage_on_the_frame_and_mana_under_it(lua):
    boot(lua)
    lua.execute('HogHealsUnits.module.events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")')
    shift(lua, "RAGE", power=35, mana=800)
    b = "HogUIPlayer.formMana"
    assert lua.eval(f"{b}:IsShown()") is True and lua.eval(f"{b}:GetHeight()") == 10
    assert lua.eval(f"{b}:GetValue()") == 800 and lua.eval(f"select(2, {b}:GetMinMaxValues())") == 1200
    assert lua.eval(f"{b}.text._text") == "800 / 1.2k"                              # abbreviated like the power text
    assert lua.eval(f"{b}.label._text") == "Mana"
    assert lua.eval(f"{b}._points[1][1]") == "TOPLEFT" and lua.eval(f"{b}._points[1][3]") == "BOTTOMLEFT"   # under the frame
    assert lua.eval("HogUIPlayer.power:GetValue()") == 35                           # the frame's own bar: rage
    assert lua.eval("HogUIPlayer.combo:IsShown()") is False                          # bear: no combo points
    # back to caster form: gone, collapsed
    shift(lua, "MANA")
    assert lua.eval(f"{b}:IsShown()") is False and lua.eval(f"{b}:GetHeight()") < 0.01
    assert errors(lua) == []


def test_cat_form_shows_energy_mana_and_combo_pips_that_fill_without_comparing(lua):
    boot(lua)
    lua.execute('HogHealsUnits.module.events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")')
    shift(lua, "ENERGY", power=80, mana=500, combo=3)
    c = "HogUIPlayer.combo"
    assert lua.eval("HogUIPlayer.formMana:IsShown()") is True
    assert lua.eval(f"{c}:IsShown()") is True
    assert lua.eval(f"#{c}.pips") == 5
    for i in range(1, 6):
        lo, hi = lua.eval(f"{c}.pips[{i}]:GetMinMaxValues()")
        assert (lo, hi) == (i - 1, i)
        assert lua.eval(f"{c}.pips[{i}]:GetValue()") == 3                            # every pip gets the count
    assert lua.eval(f"{c}._points[1][1]") == "BOTTOMLEFT" and lua.eval(f"{c}._points[1][3]") == "TOPLEFT"   # over the frame
    # a new combo point arrives as a power update
    lua.execute('MockUnits.player.combo = 5; HogHealsUnits.module.events:Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")')
    assert lua.eval(f"{c}.pips[5]:GetValue()") == 5
    assert lua.eval("HogHeals.db.global.diag.combo.source") == "UnitPower"
    assert errors(lua) == []


def test_classic_points_on_the_target_win_over_a_plain_zero(lua):
    boot(lua, extra='\nfunction GetComboPoints(u, t) return COMBO_ON_TARGET or 0 end')
    lua.execute('HogHealsUnits.module.events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")')
    lua.execute("COMBO_ON_TARGET = 4")
    shift(lua, "ENERGY", combo=0)
    assert lua.eval("HogUIPlayer.combo.pips[1]:GetValue()") == 4
    assert lua.eval("HogUIPlayer.combo.hhSource") == "GetComboPoints"
    # a new target: read again
    lua.execute('COMBO_ON_TARGET = 0; HogHealsUnits.module.events:Fire("PLAYER_TARGET_CHANGED")')
    assert lua.eval("HogUIPlayer.combo.pips[1]:GetValue()") == 0
    assert errors(lua) == []


def test_secret_mana_and_combo_go_straight_into_the_bars(lua):
    boot(lua)
    lua.execute('HogHealsUnits.module.events:RegisterEvent("UPDATE_SHAPESHIFT_FORM"); MockState.secrets = true')
    shift(lua, "ENERGY", power=60, mana=700, combo=2)
    assert lua.eval("HogUIPlayer.formMana:GetValue()") == 700                       # the widget unwraps it, we never did
    assert lua.eval("HogUIPlayer.combo.pips[3]:GetValue()") == 2
    assert errors(lua) == []


def test_a_rogue_always_has_pips_and_never_the_mana_bar(lua):
    boot(lua, cls="ROGUE")
    lua.execute("MockUnits.player.combo = 1; HogHealsUnits.Units.UpdatePower(HogUIPlayer)")
    assert lua.eval("HogUIPlayer.combo:IsShown()") is True
    assert lua.eval("HogUIPlayer.formMana") is None
    assert errors(lua) == []


def test_a_priest_gets_neither(lua):
    boot(lua, cls="PRIEST")
    lua.execute("HogHealsUnits.Units.UpdatePower(HogUIPlayer)")
    assert lua.eval("HogUIPlayer.formMana") is None and lua.eval("HogUIPlayer.combo") is None
    assert errors(lua) == []


def test_switches_turn_them_off(lua):
    boot(lua)
    lua.execute("""
      HogHeals.db.profile.units.player.formMana.enabled = false
      HogHeals.db.profile.units.player.combo.enabled = false
      MockUnits.player.powerType = "ENERGY"; MockUnits.player.mana = 300; MockUnits.player.maxMana = 900
      HogHealsUnits.Units.UpdatePower(HogUIPlayer)
    """)
    assert lua.eval("HogUIPlayer.formMana:IsShown()") is False and lua.eval("HogUIPlayer.combo:IsShown()") is False
    assert errors(lua) == []


def test_the_hud_mana_row_stays_in_forms_for_druids_only(lua):
    boot(lua, addons=("HogTronUI", "HogTron_Units", "HogTron_HUD"))
    lua.execute('MockUnits.player.powerType = "ENERGY"; MockUnits.player.mana = 450; MockUnits.player.maxMana = 900')
    lua.execute("HogHealsHUD.Mana.Update()")
    assert lua.eval("HogHealsHUD.HUD.rows.mana:IsShown()") is True
    lua.execute("HogHeals.db.profile.hud.mana.inForms = false; HogHealsHUD.Mana.Update()")
    assert lua.eval("HogHealsHUD.HUD.rows.mana:IsShown()") is False
    assert errors(lua) == []


def test_a_warrior_keeps_no_mana_row(lua):
    boot(lua, cls="WARRIOR", addons=("HogTronUI", "HogTron_Units", "HogTron_HUD"))
    lua.execute("HogHealsHUD.Mana.Update()")
    assert lua.eval("HogHealsHUD.HUD.rows.mana:IsShown()") is False
    assert errors(lua) == []


def test_a_cast_bar_attached_to_the_player_frame_hangs_past_the_new_bars(lua):
    boot(lua, addons=("HogTronUI", "HogTron_Units", "HogTron_HUD"))
    lua.execute('HogHeals.db.profile.hud.castbar.attach = "below"; HogHealsHUD.HUD.Layout()')
    assert lua.eval("HogHealsHUD.HUD.rows.castbar._points[1][2] == HogUIPlayer.formMana") is True
    lua.execute('HogHeals.db.profile.hud.castbar.attach = "above"; HogHealsHUD.HUD.Layout()')
    assert lua.eval("HogHealsHUD.HUD.rows.castbar._points[1][2] == HogUIPlayer.combo") is True
    assert errors(lua) == []
