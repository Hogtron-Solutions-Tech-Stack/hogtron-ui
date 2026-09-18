# "If I have our addon and the castbar on, does it turn off the WoW default one?" It was meant to, but it looked
# for CastingBarFrame (classic name) while modern-engine clients, Forever included, call it PlayerCastingBarFrame;
# and it hid Blizzard's bar even when OUR castbar row was switched off, leaving no castbar at all.
import pytest


def blizz(hud, name):
    hud.execute(f'CastingBarFrame = nil; PlayerCastingBarFrame = nil; {name} = CreateFrame("StatusBar", "{name}", UIParent); {name}:RegisterEvent("UNIT_SPELLCAST_START")')
    hud.execute('HogHealsHUD.Castbar.blizzHidden = nil')
    return name


@pytest.mark.parametrize("name", ["CastingBarFrame", "PlayerCastingBarFrame"])
def test_ours_on_hides_theirs_under_either_name(hud, name):
    f = blizz(hud, name)
    hud.execute('HogHeals.db.profile.hud.showCastbar = true; HogHeals.db.profile.hud.castbar.hideBlizzard = true; HogHealsHUD.Castbar.ApplyBlizzard()')
    assert hud.eval(f'{f}:IsShown()') is False
    assert hud.eval(f'{f}._events.UNIT_SPELLCAST_START') is None


def test_ours_off_gives_theirs_back(hud):
    f = blizz(hud, "PlayerCastingBarFrame")
    hud.execute('HogHeals.db.profile.hud.showCastbar = true; HogHeals.db.profile.hud.castbar.hideBlizzard = true; HogHealsHUD.Castbar.ApplyBlizzard()')
    hud.execute('HogHeals.db.profile.hud.showCastbar = false; HogHealsHUD.Castbar.ApplyBlizzard()')
    assert hud.eval(f'{f}._events.UNIT_SPELLCAST_START') is True
    assert hud.eval('HogHealsHUD.Castbar.blizzHidden') is False


def test_never_hidden_when_our_row_was_off_from_the_start(hud):
    f = blizz(hud, "PlayerCastingBarFrame")
    hud.execute('HogHeals.db.profile.hud.showCastbar = false; HogHeals.db.profile.hud.castbar.hideBlizzard = true; HogHealsHUD.Castbar.ApplyBlizzard()')
    assert hud.eval(f'{f}._events.UNIT_SPELLCAST_START') is True


def test_restore_survives_events_this_client_refuses(hud):
    f = blizz(hud, "PlayerCastingBarFrame")
    hud.execute('MockUnknownEvents.UNIT_SPELLCAST_DELAYED = true; wipe(HogHeals.errors)')
    hud.execute('HogHeals.db.profile.hud.showCastbar = true; HogHealsHUD.Castbar.ApplyBlizzard(); HogHeals.db.profile.hud.castbar.hideBlizzard = false; HogHealsHUD.Castbar.ApplyBlizzard()')
    assert hud.eval(f'{f}._events.UNIT_SPELLCAST_STOP') is True
    hud.execute('HogHeals.db.profile.hud.castbar.hideBlizzard = true')
