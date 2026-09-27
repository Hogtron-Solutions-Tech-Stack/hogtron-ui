# HogHeals_Units cast bar: our own bar for target / focus. In game 2026-09-26 the Blizzard bar we used to adopt
# threw on every target cast ("boolean test on local 'notInterruptible' (a secret boolean value, while execution
# tainted by 'HogHeals_Units')"): re-parenting it onto our frame tainted Blizzard's cast code. These tests pin the
# replacement: Blizzard's bar is never touched, and ours never tests / compares / computes with a client value.
import pathlib
import re

from test_units import boot, errors  # noqa: F401  (boot builds the Blizzard frames the module hides)
import pytest

UNITS_LUA = pathlib.Path(__file__).resolve().parent.parent / "HogHeals_Units" / "Units.lua"
BAR = "HogUITarget.castbar"
TARGET = 'MockUnits.target = { name = "Kobold", class = "WARRIOR", health = 30, maxHealth = 60, guid = "C-70" }'


@pytest.fixture
def units(lua):
    return boot(lua)


def cast(lua, fields, event="UNIT_SPELLCAST_START", key="casting", now=80):
    lua.execute(f'{TARGET}; MockState.time = {now}; MockUnits.target.{key} = {fields}; MockFire("{event}", "target")')


def tick(lua, elapsed):
    lua.execute(f'{BAR}:GetScript("OnUpdate")({BAR}, {elapsed})')


def test_blizzards_spell_bar_is_never_touched(units):
    assert units.eval('TargetFrame:GetParent() == HogHealsHiddenParent')            # its parent is hidden, so it is unseen
    assert units.eval('TargetFrameSpellBar:GetParent() == TargetFrame') is True      # never re-parented
    for field in ("hhBg", "hhEdges", "hhAnchorHooked", "hhPlacing"):
        assert units.eval(f'rawget(TargetFrameSpellBar, "{field}")') is None         # no fields written on it
    assert units.eval('TargetFrameSpellBar._texture') is None                        # never restyled
    assert units.eval('rawget(HogUITarget, "UpdateAuras")') is None                  # no stub methods for Blizzard to call
    assert errors(units) == []


def test_source_never_names_a_blizzard_cast_bar_in_code():
    code = "\n".join(line.split("--", 1)[0] for line in UNITS_LUA.read_text(encoding="utf-8").splitlines())
    assert re.search(r"SpellBar|CastingBarFrame", code) is None


def test_own_bar_exists_for_target_and_focus_only(units):
    assert units.eval(f'{BAR} ~= nil') and units.eval('HogUIFocus.castbar ~= nil')
    assert units.eval('HogUIPlayer.castbar') is None and units.eval('HogUIPet.castbar') is None
    assert units.eval(f'{BAR}:GetParent() == HogUITarget') and units.eval(f'{BAR}:IsShown()') is False
    assert units.eval(f'{BAR}._points[1][1]') == "BOTTOMLEFT" and units.eval(f'{BAR}._points[1][3]') == "TOPLEFT"
    assert units.eval(f'{BAR}._texture') is not None
    assert units.eval('HogUITarget._scripts.OnUpdate') is None                       # never on the secure button


def test_cast_shows_fills_with_our_clock_and_ends_on_stop(units):
    cast(units, '{ "Fireball", "Fireball", "icon_fire", 80000, 83000, false, "cid", false, 133 }')
    assert units.eval(f'{BAR}:IsShown()') is True
    assert units.eval(f'{BAR}._min') == 80000 and units.eval(f'{BAR}._max') == 83000
    assert units.eval(f'{BAR}._value') == 80000
    assert units.eval(f'{BAR}.text._text') == "Fireball" and units.eval(f'{BAR}.icon._texture') == "icon_fire"
    assert units.eval(f'{BAR}.locked._alpha') == 0
    units.execute('MockState.time = 81.5')
    tick(units, 0.1)
    assert units.eval(f'{BAR}._value') == 81500
    units.execute('MockUnits.target.casting = nil; MockFire("UNIT_SPELLCAST_STOP", "target")')
    assert units.eval(f'{BAR}:IsShown()') is False
    assert errors(units) == []


def test_cast_with_no_stop_event_still_ends_at_the_next_poll(units):
    cast(units, '{ "Fireball", "Fireball", "icon_fire", 80000, 83000, false, "cid", false, 133 }')
    units.execute('MockUnits.target.casting = nil')
    tick(units, 0.1)
    assert units.eval(f'{BAR}:IsShown()') is True                                    # under the poll interval
    tick(units, 0.2)
    assert units.eval(f'{BAR}:IsShown()') is False


def test_uninterruptible_cast_is_marked(units):
    cast(units, '{ "Pyroblast", "Pyroblast", "icon_pyro", 80000, 86000, false, "cid", true, 11366 }')
    assert units.eval(f'{BAR}.locked._alpha') == 1
    units.execute('MockUnits.target.casting[8] = false; MockFire("UNIT_SPELLCAST_INTERRUPTIBLE", "target")')
    assert units.eval(f'{BAR}.locked._alpha') == 0


def test_channel_drains_and_reads_its_own_interrupt_slot(units):
    cast(units, '{ "Drain Life", "Drain Life", "icon_drain", 80000, 85000, false, true, 689 }',
         event="UNIT_SPELLCAST_CHANNEL_START", key="channeling")
    assert units.eval(f'{BAR}:IsShown()') is True and units.eval(f'{BAR}.channel') is True
    assert units.eval(f'{BAR}._value') == 85000                                       # full, then drains
    assert units.eval(f'{BAR}.locked._alpha') == 1                                    # 7th return for a channel
    units.execute('MockState.time = 84')
    tick(units, 0.1)
    assert units.eval(f'{BAR}._value') == 81000
    units.execute('MockUnits.target.channeling = nil; MockFire("UNIT_SPELLCAST_CHANNEL_STOP", "target")')
    assert units.eval(f'{BAR}:IsShown()') is False


def test_every_cast_value_secret_draws_without_an_error(units):
    units.execute('MockSetSecrets(true)')
    cast(units, '{ MockSecret("Shadow Bolt"), MockSecret("Shadow Bolt"), MockSecret("icon_sb"), MockSecret(80000), MockSecret(82500), false, MockSecret("cid"), MockSecret(true), MockSecret(686) }')
    assert errors(units) == []
    assert units.eval(f'{BAR}:IsShown()') is True
    assert units.eval(f'{BAR}._min') == 80000 and units.eval(f'{BAR}._max') == 82500  # the widget took the secrets
    assert units.eval(f'{BAR}.locked._alpha') == 1                                    # resolved by the widget, not by us
    assert units.eval(f'{BAR}.plainStart') is None and units.eval(f'{BAR}.plainEnd') is None
    units.execute('MockState.time = 81')
    tick(units, 0.3)
    assert units.eval(f'{BAR}._value') == 81000                                       # our clock, a plain number
    assert units.eval(f'{BAR}.broken') is None
    assert units.eval('HogHeals.db.global.diag.unitsCast.secretTimes') is True
    assert units.eval('HogHeals.db.global.diag.unitsCast.secretLock') is True
    assert errors(units) == []


def test_secret_channel_grows_instead_of_computing_with_secrets(units):
    units.execute('MockSetSecrets(true)')
    cast(units, '{ MockSecret("Drain Life"), MockSecret("x"), MockSecret("i"), MockSecret(80000), MockSecret(85000), false, MockSecret(false), MockSecret(689) }',
         event="UNIT_SPELLCAST_CHANNEL_START", key="channeling")
    assert units.eval(f'{BAR}:IsShown()') is True and units.eval(f'{BAR}._value') == 80000
    assert units.eval(f'{BAR}.locked._alpha') == 0
    assert errors(units) == []


def test_secret_lock_without_the_widget_helper_stays_off(units):
    units.execute(f'MockSetSecrets(true); {BAR}.locked.SetAlphaFromBoolean = false')
    cast(units, '{ MockSecret("X"), MockSecret("X"), MockSecret("i"), MockSecret(80000), MockSecret(82000), false, MockSecret("c"), MockSecret(true), MockSecret(1) }')
    assert units.eval(f'{BAR}:IsShown()') is True and units.eval(f'{BAR}.locked._alpha') == 0
    assert errors(units) == []


def test_new_target_mid_cast_shows_it_and_no_target_hides_it(units):
    units.execute(f'{TARGET}; MockState.time = 80; MockUnits.target.casting = {{ "Heal", "Heal", "icon_heal", 79000, 82000, false, "cid", false, 2050 }}; MockFire("PLAYER_TARGET_CHANGED")')
    assert units.eval(f'{BAR}:IsShown()') is True and units.eval(f'{BAR}.text._text') == "Heal"
    units.execute('MockUnits.target = nil; MockFire("PLAYER_TARGET_CHANGED")')
    assert units.eval(f'{BAR}:IsShown()') is False


def test_option_off_keeps_the_bar_hidden(units):
    units.execute('HogHeals.db.profile.units.target.castbar = false; HogHealsUnits.Units.Refresh()')
    cast(units, '{ "Fireball", "Fireball", "icon_fire", 80000, 83000, false, "cid", false, 133 }')
    assert units.eval(f'{BAR}:IsShown()') is False
    units.execute('HogHeals.db.profile.units.target.castbar = true; HogHeals.db.profile.units.target.castbarHeight = 20; HogHealsUnits.Units.Refresh()')
    assert units.eval(f'{BAR}:IsShown()') is True and units.eval(f'{BAR}._height') == 20


def test_a_failing_tick_latches_the_bar_off(units):
    cast(units, '{ "Fireball", "Fireball", "icon_fire", 80000, 83000, false, "cid", false, 133 }')
    units.execute(f'{BAR}.SetValue = function() error("boom") end')
    tick(units, 0.1)
    assert units.eval(f'{BAR}.broken') is True and units.eval(f'{BAR}:IsShown()') is False
    assert len([e for e in errors(units) if "units castbar target" in e]) == 1
    tick(units, 0.1)
    assert len([e for e in errors(units) if "units castbar target" in e]) == 1       # once, not every frame


def test_cast_events_of_other_units_are_ignored(units):
    units.execute(f'{TARGET}; MockUnits.player.casting = {{ "Hearthstone", "x", "i", 80000, 90000, false, "c", false, 8690 }}; MockFire("UNIT_SPELLCAST_START", "player")')
    assert units.eval(f'{BAR}:IsShown()') is False
    assert errors(units) == []
