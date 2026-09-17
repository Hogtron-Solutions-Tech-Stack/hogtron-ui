# WoW: Forever beta (1.60.1, 2026-09-17) hands addons SECRET values for unit health / power / names /
# incoming heals: arithmetic, comparison, # and concat on them throw. Widgets accept them. First in-game
# run drew an empty bar because Health, Name and Power all did maths on them.
import pytest


def btn(frames, secrets=True, **unit):
    frames.execute(f'MockSetSecrets({"true" if secrets else "false"})')
    frames.execute('HogHealsFrames.Compat.Init()')
    frames.execute('MockUnits.party1 = { name = "Thrallsbane", class = "PRIEST", health = 40, maxHealth = 100, power = 30, maxPower = 60, guid = "Player-9" }')
    for k, v in unit.items():
        frames.execute(f'MockUnits.party1.{k} = {v}')
    frames.execute('wipe(HogHeals.errors); HH_s = HogHealsFrames.UnitButton.Create("HHSecretBtn" .. math.random(1e9), UIParent); HH_s:SetAttribute("unit", "party1"); HogHealsFrames.UnitButton.OnAttributeChanged(HH_s, "unit", "party1")')
    return frames


def errors(frames):
    return [e["msg"] for e in frames.eval('HogHeals.errors').values()]


def test_mock_secret_behaves_like_the_client(frames):
    frames.execute('MockSetSecrets(true)')
    # exactly what diag.secretProbe measured on the beta client
    for expr in ('UnitHealth("player") + 1', 'UnitHealth("player") < 5', 'UnitHealth("player") / UnitHealthMax("player")', 'UnitPower("player") + 0'):
        with pytest.raises(Exception):
            frames.eval(expr)
    assert frames.eval('("%d"):format(UnitHealth("player"))') == "100"
    assert frames.eval('"x" .. UnitHealth("player")') == "x100"
    assert frames.eval('tostring(UnitHealth("player"))') == "100"
    assert frames.eval('issecretvalue(UnitHealthMax("player"))') is False
    assert frames.eval('issecretvalue(UnitName("player"))') is False
    assert frames.eval('issecretvalue(UnitHealth("player"))') is True
    assert frames.eval('issecretvalue(5)') is False


def test_health_name_power_draw_with_secret_values(frames):
    f = btn(frames)
    assert errors(f) == []
    assert f.eval('HH_s.health._value') == 40 and f.eval('HH_s.health._max') == 100
    assert f.eval('HH_s.power._value') == 30 and f.eval('HH_s.power._max') == 60
    assert f.eval('HH_s.name._text') == "Thrallsb"      # names are not secret on the beta: normal truncation


def test_secret_name_is_clipped_by_the_widget_not_by_lua(frames):
    # C_Secrets.ShouldUnitIdentityBeSecret exists, so names CAN go secret; then we may not measure them.
    frames.execute('MockState.secretNames = true')
    f = btn(frames)
    assert errors(f) == []
    assert f.eval('HH_s.name._text') == "Thrallsbane"


def test_compat_reports_secret_values(frames):
    f = btn(frames)
    assert f.eval('HogHealsFrames.Compat.secretValues') is True
    assert any(l == "secretValues=true" for l in f.eval('HogHealsFrames.Compat.Describe()').values())
    f.execute('MockSetSecrets(false); HogHealsFrames.Compat.Init()')
    assert f.eval('HogHealsFrames.Compat.secretValues') is False


def test_elements_that_need_maths_are_blocked_not_erroring(frames):
    f = btn(frames, incomingMine=25)
    assert f.eval('HogHealsFrames.UnitButton.ElementEnabled("healPrediction")') is False
    assert f.eval('HogHealsFrames.UnitButton.ElementEnabled("health")') is True
    # the user's saved profile is NOT rewritten: on an open client the indicator comes straight back
    assert f.eval('HogHeals.db.profile.frames.indicators.healPrediction') is not False
    f.execute('MockSetSecrets(false); HogHealsFrames.Compat.Init()')
    assert f.eval('HogHealsFrames.UnitButton.ElementEnabled("healPrediction")') is True


def test_open_client_unchanged(frames):
    f = btn(frames, secrets=False)
    assert errors(f) == []
    assert f.eval('HH_s.health._value') == 40
    assert f.eval('HH_s.name._text') == "Thrallsb"   # default nameLength 8 still applies when we may measure it
    assert f.eval('HH_s.healthText._text') == "-60"


def test_secret_probe_recorded_for_remote_debugging(frames):
    frames.execute('MockSetSecrets(true); HogHeals:SnapshotClient()')
    p = frames.eval('HogHeals.db.global.diag.client.secretProbe')
    assert p["secret.UnitHealth"] is True and p["secret.UnitHealthMax"] is False
    assert p["op.hp+0"] is False and p["op.format%d"] is True
    assert "api.UnitHealthPercent" in p
