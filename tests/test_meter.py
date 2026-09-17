# HogHeals_Meter: our window over Blizzard's damage-meter data (C_DamageMeter). Restricted clients give addons no
# combat log, only these sessions, and the amounts are SECRET: no sorting or dividing by us. The widget does it:
# StatusBar min 0 / max = top amount / value = this amount, text via format/AbbreviateNumbers.
import pytest

MOCK_API = '''
MockSetSecrets(true)
HH_sources = {
  { name = "Hog Tistic", classFilename = "SHAMAN", totalAmount = MockSecret(7439), amountPerSecond = MockSecret(48) },
  { name = "lol Fried",  classFilename = "WARLOCK", totalAmount = MockSecret(44),   amountPerSecond = MockSecret(0.3) },
  { name = "Vanco Sh",   classFilename = "ROGUE",  totalAmount = MockSecret(18),   amountPerSecond = MockSecret(0.1) },
}
HH_calls = {}
C_DamageMeter = {
  IsDamageMeterAvailable = function() return true end,
  GetAvailableCombatSessions = function() return { { sessionID = 3, encounterName = "Clattering Scorpid" } } end,
  GetCombatSessionFromType = function(a, b)
    HH_calls[#HH_calls + 1] = { a, b }
    return { sessionID = 3, encounterName = "Clattering Scorpid", combatSources = HH_sources, totalAmount = MockSecret(7501) }
  end,
  GetSessionDurationSeconds = function() return MockSecret(155) end,
  ResetAllCombatSessions = function() HH_reset = true end,
}
Enum = Enum or {}
Enum.DamageMeterType = { DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4, Interrupts = 5, Dispels = 6, DamageTaken = 7, Deaths = 9 }
Enum.DamageMeterSessionType = { Current = 0, Overall = 1 }
DamageMeter = CreateFrame("Frame", "DamageMeter", UIParent)
AbbreviateNumbers = function(v) v = MockUnwrap(v) if v >= 1000 then return ("%.1fk"):format(v / 1000) end return tostring(v) end
'''


@pytest.fixture
def meter(lua):
    lua.execute(MOCK_API)
    for a in ("HogHeals", "HogHeals_Frames", "HogHeals_HUD", "HogHeals_Meter"):
        lua.load_addon(a)
    lua.player_login()
    lua.execute('wipe(HogHeals.errors)')
    return lua


def errors(lua):
    return [e["msg"] for e in lua.eval('HogHeals.errors').values()]


def test_module_registers_and_window_exists(meter):
    assert meter.eval('HogHeals.modules.Meter ~= nil')
    assert meter.eval('HogHealsMeterFrame ~= nil and type(HogHealsMeter) == "table"')
    assert meter.eval('HogHeals.defaults.profile.meter.enabled') is True
    assert errors(meter) == []


def test_rows_render_from_secret_amounts_without_any_maths(meter):
    meter.execute('HogHealsMeter.Meter.Update()')
    assert errors(meter) == []
    rows = meter.eval('HogHealsMeter.Meter.rows')
    r1 = 'HogHealsMeter.Meter.rows[1]'
    assert meter.eval(f'{r1}:IsShown()') is True
    assert meter.eval(f'{r1}.name._text') == "1. Hog Tistic"
    assert meter.eval(f'{r1}.bar._value') == 7439 and meter.eval(f'{r1}.bar._max') == 7439   # widget scales, we do not divide
    assert meter.eval('HogHealsMeter.Meter.rows[2].bar._value') == 44 and meter.eval('HogHealsMeter.Meter.rows[2].bar._max') == 7439
    assert "7.4k" in meter.eval(f'{r1}.value._text') and "48" in meter.eval(f'{r1}.value._text')
    assert meter.eval(f'{r1}.bar._color[3]') == pytest.approx(0.87, abs=0.01)   # shaman blue
    assert meter.eval('HogHealsMeter.Meter.rows[4]') is None or meter.eval('HogHealsMeter.Meter.rows[4]:IsShown()') is False


def test_default_mode_and_segment_are_asked_for_in_the_documented_order(meter):
    meter.execute('wipe(HH_calls); HogHealsMeter.Meter.Update()')
    call = list(meter.eval('HH_calls[1]').values())
    assert call == [0, 0]      # (Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageDone)


def test_mode_and_segment_switch_and_persist(meter):
    meter.execute('HogHealsMeter.Meter.SetMode("HealingDone"); HogHealsMeter.Meter.SetSegment("Overall")')
    assert meter.eval('HogHeals.db.profile.meter.mode') == "HealingDone"
    assert meter.eval('HogHeals.db.profile.meter.segment') == "Overall"
    call = list(meter.eval('HH_calls[#HH_calls]').values())
    assert call == [1, 2]
    assert "Healing" in meter.eval('HogHealsMeter.Meter.frame.title._text')
    assert "Overall" in meter.eval('HogHealsMeter.Meter.frame.title._text')


def test_shape_it_does_not_recognise_is_reported_once_not_thrown(meter):
    meter.execute('C_DamageMeter.GetCombatSessionFromType = function() return { weird = true, stuff = { 1, 2, 3 } } end')
    meter.execute('HogHealsMeter.Meter.Update(); HogHealsMeter.Meter.Update()')
    msgs = errors(meter)
    assert len(msgs) == 1 and "meter" in msgs[0].lower() and "shape" in msgs[0].lower()
    assert meter.eval('HogHealsMeter.Meter.rows[1]:IsShown()') is False


def test_no_api_means_module_stands_down_quietly(lua):
    lua.execute('C_DamageMeter = nil')
    for a in ("HogHeals", "HogHeals_Meter"):
        lua.load_addon(a)
    lua.player_login()
    assert lua.eval('HogHealsMeter.Meter.unavailable') is True
    assert lua.eval('HogHealsMeter ~= nil and (HogHealsMeter.Meter.frame == nil or HogHealsMeter.Meter.frame:IsShown() == false)')
    assert [e["msg"] for e in lua.eval('HogHeals.errors').values()] == []


def test_blizzard_meter_hidden_while_ours_is_on(meter):
    assert meter.eval('DamageMeter:IsShown()') is False
    assert meter.eval('DamageMeter:GetParent():GetName()') == "HogHealsHiddenParent"


def test_option_to_keep_blizzard_meter(meter):
    # Hiding is one-way per session (same as the party frames); with the option off we simply never touch it.
    meter.execute('DamageMeter2 = CreateFrame("Frame", "DamageMeter", UIParent); DamageMeter = DamageMeter2')
    meter.execute('HogHeals.db.profile.meter.hideBlizzard = false; HogHealsMeter.Meter.ApplyBlizzard(); HogHealsMeter.Meter.Refresh()')
    assert meter.eval('DamageMeter:IsShown()') is True
    assert meter.eval('DamageMeter:GetParent() == UIParent')


def test_reset_goes_through_blizzard(meter):
    meter.execute('HogHealsMeter.Meter.Reset()')
    assert meter.eval('HH_reset') is True


def test_options_tab_exists_and_panel_renders_it(meter):
    meter.execute('wipe(HogHeals.errors); HogHeals.Panel.Open(); HogHeals.Panel.Select("Meter")')
    assert meter.eval('HogHeals.Panel.selected') == "Meter"
    assert meter.eval('HogHeals.Panel.controls["Meter.enabled"] ~= nil')
    assert errors(meter) == []


def test_slash_toggles_window(meter):
    meter.execute('HogHeals:SlashCommand("meter")')
    shown1 = meter.eval('HogHealsMeterFrame:IsShown()')
    meter.execute('HogHeals:SlashCommand("meter")')
    assert meter.eval('HogHealsMeterFrame:IsShown()') != shown1
