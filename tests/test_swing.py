# HUD swing timer (HogHeals_HUD/Swing.lua): auto-attack bar under the cast bar, source ladder per client.
import pytest


def errors(lua):
    return [e["msg"] for e in lua.eval('HogHeals.errors').values()]


@pytest.fixture
def sw(hud):
    hud.execute('''
      HH_sw = HogHealsHUD.HUD.rows.swing
      MockState.time = 100
      function UnitAttackSpeed(u) return 2.6, 1.8 end
      function UnitRangedDamage(u) return 3.0, 10, 20 end
      HogHealsHUD.Swing.ReadSpeeds()
    ''')
    return hud


def test_row_sits_under_the_castbar_and_hides_when_idle(sw):
    assert sw.eval('HH_sw ~= nil') and sw.eval('HH_sw:IsShown()') is False
    y = list(sw.eval('{HH_sw:GetPoint()}').values())[4]
    d = sw.eval('HogHeals.db.profile.hud')
    assert y == -(d["castbarHeight"] + d["rowSpacing"])
    assert sw.eval('HogHeals.db.profile.hud.showSwing') is True
    assert sw.eval('HogHealsHUD.Swing.speeds.mh') == 2.6 and sw.eval('HogHealsHUD.Swing.speeds.oh') == 1.8


def test_auto_attack_on_runs_a_free_running_bar_at_weapon_speed(sw):
    # the mock has no restricted API, so the combat log is allowed - but nothing has come from it yet: estimate mode
    sw.execute('MockFire("PLAYER_ENTER_COMBAT")')
    assert sw.eval('HH_sw:IsShown()') is True
    assert sw.eval('HH_sw.text:GetText()') == "Swing"
    assert sw.eval('HogHealsHUD.Swing.state.period') == 2.6 and sw.eval('HogHealsHUD.Swing.state.source') == "toggle"
    sw.execute('MockState.time = 101.3; HogHealsHUD.Swing.OnUpdate(HH_sw)')
    assert sw.eval('HH_sw:GetValue()') == pytest.approx(0.5)
    assert sw.eval('HH_sw.time:GetText()') == "1.3"
    # the swing lands: the next one starts where this one ended (phase kept)
    sw.execute('MockState.time = 102.7; HogHealsHUD.Swing.OnUpdate(HH_sw)')
    assert sw.eval('HogHealsHUD.Swing.state.start') == pytest.approx(102.6)
    assert sw.eval('HogHealsHUD.Swing.state.source') == "roll"
    # a new weapon speed is picked up at the roll-over
    sw.execute('function UnitAttackSpeed() return 3.4, nil end; MockFire("UNIT_ATTACK_SPEED", "player"); MockState.time = 105.3; HogHealsHUD.Swing.OnUpdate(HH_sw)')
    assert sw.eval('HogHealsHUD.Swing.state.period') == 3.4
    # auto-attack off: bar gone
    sw.execute('MockFire("PLAYER_LEAVE_COMBAT")')
    assert sw.eval('HH_sw:IsShown()') is False
    assert errors(sw) == []


def test_combat_log_swings_from_the_player_reset_the_bar_and_others_are_ignored(sw):
    assert sw.eval('HogHealsHUD.Swing.frame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED")') is True
    sw.execute('''
      MockFire("PLAYER_ENTER_COMBAT")
      MockState.time = 101
      function CombatLogGetCurrentEventInfo() return 0, "SWING_DAMAGE", false, "Player-0", "Hognificent", 0, 0, "Creature-1", "Boar", 0, 0 end
      MockFire("COMBAT_LOG_EVENT_UNFILTERED")
    ''')
    assert sw.eval('HogHealsHUD.Swing.state.start') == 101 and sw.eval('HogHealsHUD.Swing.state.source') == "cleu"
    assert sw.eval('HogHealsHUD.Swing.exact') is True
    sw.execute('''
      MockState.time = 102
      function CombatLogGetCurrentEventInfo() return 0, "SWING_DAMAGE", false, "Player-9", "Someone", 0, 0, "Creature-1", "Boar", 0, 0 end
      MockFire("COMBAT_LOG_EVENT_UNFILTERED")
    ''')
    assert sw.eval('HogHealsHUD.Swing.state.start') == 101           # not ours
    # Heroic Strike landing is a swing too
    sw.execute('''
      MockState.time = 103
      function CombatLogGetCurrentEventInfo() return 0, "SPELL_CAST_SUCCESS", false, "Player-0", "Hognificent", 0, 0, "Creature-1", "Boar", 0, 0, 78, "Heroic Strike" end
      MockFire("COMBAT_LOG_EVENT_UNFILTERED")
    ''')
    assert sw.eval('HogHealsHUD.Swing.state.start') == 103
    # exact mode does not roll over on its own; two silent periods = stopped / out of range -> hides
    sw.execute('MockState.time = 104; HogHealsHUD.Swing.OnUpdate(HH_sw)')
    assert sw.eval('HH_sw:IsShown()') is True
    sw.execute('MockState.time = 103 + 2 * 2.6 + 0.1; HogHealsHUD.Swing.OnUpdate(HH_sw)')
    assert sw.eval('HH_sw:IsShown()') is False
    assert errors(sw) == []


def test_restricted_client_never_touches_the_combat_log_and_uses_casts_and_toggles(lua):
    lua.execute('MockSetSecrets(true)')
    lua.load_addon("HogHeals"); lua.load_addon("HogHeals_Frames"); lua.load_addon("HogHeals_HUD"); lua.player_login()
    lua.execute('''
      HH_sw = HogHealsHUD.HUD.rows.swing
      MockState.time = 100
      function UnitAttackSpeed(u) return 2.0, nil end
      function UnitRangedDamage(u) return 2.9, 10, 20 end
    ''')
    assert lua.eval('HogHealsHUD.Swing.cleu') is False
    assert lua.eval('HogHealsHUD.Swing.frame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED")') is False
    assert "not allowed" in lua.eval('HogHealsHUD.Swing.Probe().combatLog')
    # a hunter's Auto Shot is reported as a successful cast: exact ranged timing
    lua.execute('MockFire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 75)')
    assert lua.eval('HH_sw:IsShown()') is True and lua.eval('HH_sw.text:GetText()') == "Auto Shot"
    assert lua.eval('HogHealsHUD.Swing.state.period') == 2.9 and lua.eval('HogHealsHUD.Swing.state.kind') == "ranged"
    # a secret speed is ignored, the last plain one kept; a secret spell id is counted, not compared
    lua.execute('function UnitAttackSpeed(u) return MockSecret(2.4), nil end; MockFire("UNIT_ATTACK_SPEED", "player")')
    assert lua.eval('HogHealsHUD.Swing.speeds.mh') == 2.0
    lua.execute('MockFire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", MockSecret(75))')
    assert lua.eval('HogHealsHUD.Swing.seen.secretSpellID') == 1
    assert errors(lua) == []


def test_off_switch_hides_the_row_and_ignores_events(sw):
    sw.execute('HogHeals.db.profile.hud.showSwing = false; HogHealsHUD.HUD.Refresh()')
    assert sw.eval('HH_sw:IsShown()') is False
    sw.execute('MockFire("PLAYER_ENTER_COMBAT")')
    assert sw.eval('HH_sw:IsShown()') is False and sw.eval('HogHealsHUD.Swing.state.active') is False
    sw.execute('HogHeals.db.profile.hud.showSwing = true; HogHealsHUD.HUD.Refresh(); MockFire("PLAYER_ENTER_COMBAT")')
    assert sw.eval('HH_sw:IsShown()') is True
    # hideWhenIdle off keeps an empty bar on screen
    sw.execute('MockFire("PLAYER_LEAVE_COMBAT"); HogHeals.db.profile.hud.swing.hideWhenIdle = false; HogHealsHUD.HUD.Refresh()')
    assert sw.eval('HH_sw:IsShown()') is True and sw.eval('HH_sw:GetValue()') == 0
    # options tab + slash
    sw.execute('HogHeals:SlashCommand("swingdiag")')
    assert sw.eval('HogHeals.db.global.diag.swing.speeds') == "mh=2.6 oh=1.8 ranged=3"
    args = sw.eval('HogHeals.OptionsTable().args.HUD.args.swing.args')
    assert args["enabled"]["name"] == "Swing timer on" and args["color"]["type"] == "color"
    assert errors(sw) == []
