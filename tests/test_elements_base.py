import pytest


@pytest.fixture
def btn(frames):
    frames.execute('''
      MockUnits.party1 = { name = "Zugzug", class = "PRIEST", health = 40, maxHealth = 100, power = 50, maxPower = 100, guid = "Player-1" }
      HH_b = HogHealsFrames.UnitButton.Create("HogHealsElBtn", UIParent)
      HH_b:SetAttribute("unit", "party1")
      HogHealsFrames.UnitButton.OnAttributeChanged(HH_b, "unit", "party1")
    ''')
    return frames


def upd(f, name):
    f.execute(f'HogHealsFrames.Elements.{name}.Update(HH_b, "party1")')


def test_health_values_and_class_colour(btn):
    upd(btn, "health")
    assert btn.eval('HH_b.health:GetValue()') == 40
    assert list(btn.eval('{HH_b.health:GetMinMaxValues()}').values()) == [0, 100]
    r, g, b = list(btn.eval('{HH_b.health:GetStatusBarColor()}').values())[:3]
    assert (r, g, b) == (1, 1, 1)  # PRIEST class colour


def test_health_deficit_mode_gradient(btn):
    btn.execute('HogHeals.db.profile.frames.appearance.healthMode = "deficit"')
    upd(btn, "health")
    r, g, b = list(btn.eval('{HH_b.health:GetStatusBarColor()}').values())[:3]
    assert r > g  # 40% health -> reddish


def test_health_text_modes(btn):
    btn.execute('HogHeals.db.profile.frames.appearance.healthText = "percent"'); upd(btn, "health")
    assert btn.eval('HH_b.healthText:GetText()') == "40%"
    btn.execute('HogHeals.db.profile.frames.appearance.healthText = "deficit"'); upd(btn, "health")
    assert btn.eval('HH_b.healthText:GetText()') == "-60"
    btn.execute('HogHeals.db.profile.frames.appearance.healthText = "none"'); upd(btn, "health")
    assert btn.eval('HH_b.healthText:GetText()') == ""


def test_health_state_text(btn):
    btn.execute('MockUnits.party1.dead = true'); upd(btn, "health")
    assert btn.eval('HH_b.healthText:GetText()') == "Dead"
    btn.execute('MockUnits.party1.dead = false; MockUnits.party1.ghost = true'); upd(btn, "health")
    assert btn.eval('HH_b.healthText:GetText()') == "Ghost"
    btn.execute('MockUnits.party1.ghost = false; MockUnits.party1.connected = false'); upd(btn, "health")
    assert btn.eval('HH_b.healthText:GetText()') == "Offline"


def test_power_hidden_for_non_mana_when_healer_only(btn):
    btn.execute('MockUnits.party1.powerType = "RAGE"; MockUnits.party1.class = "WARRIOR"'); upd(btn, "power")
    assert btn.eval('HH_b.power:IsShown()') is False
    btn.execute('MockUnits.party1.powerType = "MANA"; MockUnits.party1.class = "PRIEST"'); upd(btn, "power")
    assert btn.eval('HH_b.power:IsShown()') is True
    assert btn.eval('HH_b.power:GetValue()') == 50


def test_name_truncation(btn):
    btn.execute('MockUnits.party1.name = "Hognificentlylong"; HogHeals.db.profile.frames.appearance.nameLength = 8'); upd(btn, "name")
    assert btn.eval('HH_b.name:GetText()') == "Hognific"


def test_range_alpha(btn):
    btn.execute('MockUnits.party1.inRange = false'); upd(btn, "range")
    assert btn.eval('HH_b:GetAlpha()') == 0.4
    btn.execute('MockUnits.party1.inRange = true'); upd(btn, "range")
    assert btn.eval('HH_b:GetAlpha()') == 1


def test_aggro_border(btn):
    btn.execute('MockUnits.party1.threat = 3'); upd(btn, "aggro")
    assert btn.eval('HH_b.aggroBorder:IsShown()') is True
    btn.execute('MockUnits.party1.threat = 0'); upd(btn, "aggro")
    assert btn.eval('HH_b.aggroBorder:IsShown()') is False


def test_raid_icon(btn):
    btn.execute('MockUnits.party1.raidIcon = 8'); upd(btn, "raidIcon")
    assert btn.eval('HH_b.raidIcon:IsShown()') is True
    btn.execute('MockUnits.party1.raidIcon = nil'); upd(btn, "raidIcon")
    assert btn.eval('HH_b.raidIcon:IsShown()') is False


def test_status_icons(btn):
    btn.execute('MockUnits.party1.readyCheck = "waiting"'); upd(btn, "statusIcons")
    assert btn.eval('HH_b.statusIcon:IsShown()') is True and btn.eval('HH_b.statusIcon.kind') == "readyCheck"
    btn.execute('MockUnits.party1.readyCheck = nil; MockUnits.party1.incomingRes = true'); upd(btn, "statusIcons")
    assert btn.eval('HH_b.statusIcon.kind') == "res"
    btn.execute('MockUnits.party1.incomingRes = false; MockUnits.party1.incomingSummon = true'); upd(btn, "statusIcons")
    assert btn.eval('HH_b.statusIcon.kind') == "summon"
    btn.execute('MockUnits.party1.incomingSummon = false; MockUnits.party1.leader = true'); upd(btn, "statusIcons")
    assert btn.eval('HH_b.statusIcon.kind') == "leader"
    btn.execute('MockUnits.party1.leader = false'); upd(btn, "statusIcons")
    assert btn.eval('HH_b.statusIcon:IsShown()') is False


def test_elements_registered_in_order(frames):
    order = list(frames.eval('HogHealsFrames.ElementOrder').values())
    for name in ["health", "power", "name", "range", "aggro", "raidIcon", "statusIcons"]:
        assert name in order
