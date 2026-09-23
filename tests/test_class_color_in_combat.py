# 2026-09-22 in game (Forever beta): the class-coloured health bar went GREY in combat. The client can hide unit
# identity in combat (C_Secrets.ShouldUnitIdentityBeSecret): UnitClass comes back secret / empty, and "no readable
# class" fell through to the grey default. A class never changes, so the frames remember it (Compat.ClassOf).
import pytest

HIDE_CLASS = '''
local realUnitClass = UnitClass
MockHideClass = false
function UnitClass(u)
  if MockHideClass == "secret" then local a, b = realUnitClass(u) return MockSecret(a), MockSecret(b) end
  if MockHideClass == "nil" then return nil end
  return realUnitClass(u)
end
'''


def make(f, unit):
    f.execute(f'''
      B = HogHealsFrames.UnitButton.Create("HogHealsCC_{unit}", UIParent)
      B:SetAttribute("unit", "{unit}"); HogHealsFrames.UnitButton.OnAttributeChanged(B, "unit", "{unit}")
    ''')


@pytest.mark.parametrize("hidden", ["secret", "nil"])
def test_health_bar_keeps_class_colour_when_class_is_hidden_in_combat(frames, hidden):
    frames.execute('MockSetSecrets(true)' + HIDE_CLASS)
    frames.execute('MockSetGroup(2, false); MockUnits.party1 = { name = "Zugzug", class = "MAGE", health = 50, maxHealth = 100, guid = "Player-7" }')
    make(frames, "party1")
    assert frames.eval('B.health._color[3]') == pytest.approx(0.94, abs=0.02)     # mage blue out of combat
    frames.execute(f'MockHideClass = "{hidden}"; MockState.inCombat = true; HogHealsFrames.UnitButton.OnEvent(B, "UNIT_HEALTH", "party1")')
    assert frames.eval('B.health._color[3]') == pytest.approx(0.94, abs=0.02)     # still mage blue, not grey 0.6
    assert frames.eval('B.health._color[1]') != pytest.approx(0.6)
    assert frames.eval('#HogHeals.errors') == 0


def test_player_class_survives_for_my_own_class_checks(frames):
    frames.execute('MockSetSecrets(true)' + HIDE_CLASS)
    assert frames.eval('HogHealsFrames.Compat.ClassOf("player")') == frames.eval('MockState.playerClass')
    frames.execute('MockHideClass = "secret"')
    assert frames.eval('HogHealsFrames.Compat.ClassOf("player")') == frames.eval('MockState.playerClass')


def test_never_seen_unit_with_hidden_class_is_nil_not_an_error(frames):
    frames.execute('MockSetSecrets(true)' + HIDE_CLASS + '; MockHideClass = "secret"')
    frames.execute('MockUnits.party3 = { name = "Stranger", class = "ROGUE", guid = "Player-99" }')
    assert frames.eval('HogHealsFrames.Compat.ClassOf("party3")') is None


def test_secret_incoming_heals_hide_the_overlay_instead_of_erroring(frames):
    # measured on the beta: secret.UnitGetIncomingHeals = true, secret.UnitHealth = true
    frames.execute('MockSetSecrets(true); MockSetGroup(2, false); MockUnits.party1 = { name = "Zugzug", class = "MAGE", health = 50, maxHealth = 100, guid = "Player-7", incoming = 30 }')
    make(frames, "party1")
    frames.execute('wipe(HogHeals.errors); MockState.inCombat = true; HogHealsFrames.UnitButton.OnEvent(B, "UNIT_HEALTH", "party1")')
    assert frames.eval('#HogHeals.errors') == 0
    assert frames.eval('B.healPred:IsShown()') is False
