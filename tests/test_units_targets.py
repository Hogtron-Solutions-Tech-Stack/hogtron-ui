# Who a unit frame's unit is targeting (Sean 2026-10-18: "add targets to unit frame as a default" - both: a line on
# the target / focus frame and "Spell » who" on their cast bars) - while the HUD's own cast bar shows just the spell.
import pytest

from test_units import boot

TGT = "HogUITarget"
U = "HogHealsUnits.Units"


@pytest.fixture
def units(lua):
    b = boot(lua)
    b.execute('''
      MockUnits.target = { name = "Kobold", class = "WARRIOR", isPlayer = false, health = 30, maxHealth = 60, guid = "C-70" }
      MockFire("PLAYER_TARGET_CHANGED")''')
    return b


def line(lua, frame=TGT):
    return lua.eval(f"{frame}.targetOf:IsShown() and {frame}.targetOf:GetText() or nil")


def colour(lua, frame=TGT):
    return list(lua.eval(f"{frame}.targetOf._color").values())[:3]


def test_the_target_frame_says_who_it_is_attacking(units):
    assert line(units) is None                                                  # targets nobody: no line
    units.execute('''MockUnits.targettarget = { name = "Bramble", class = "DRUID", health = 1, maxHealth = 1, guid = "P-9" }
      MockFire("UNIT_TARGET", "target")''')
    assert line(units) == "» Bramble"
    assert colour(units) == pytest.approx([1.0, 0.49, 0.04], abs=0.01)         # a player: class colour (druid orange)
    p = list(units.eval(f"{TGT}.targetOf._points[1]").values())
    assert p[0] == "BOTTOMLEFT" and p[2] == "BOTTOMLEFT"                        # bottom-left, under the name
    units.execute('MockUnits.targettarget = { name = "Hognificent", class = "MAGE", guid = "Player-0" }; MockFire("UNIT_TARGET", "target")')
    assert line(units) == "» You" and colour(units) == pytest.approx([1.0, 0.36, 0.25])   # you: red, by name
    units.execute('MockUnits.targettarget = nil; MockFire("UNIT_TARGET", "target")')
    assert line(units) is None


def test_a_mob_target_is_cream_and_the_ticker_catches_a_silent_switch(units):
    units.execute('MockUnits.targettarget = { name = "Wolf", class = "WARRIOR", isPlayer = false, guid = "C-71" }; MockFire("UNIT_TARGET", "target")')
    assert line(units) == "» Wolf" and colour(units) == pytest.approx([0.96, 0.92, 0.86], abs=0.01)
    units.execute('MockUnits.targettarget = { name = "Bramble", class = "DRUID", guid = "P-9" }; MockAdvance(0.6)')   # no event
    assert line(units) == "» Bramble"


def test_hidden_names_still_show_and_nothing_is_compared(units):
    units.execute('''MockUnits.targettarget = { name = "Bramble", class = "DRUID", guid = "P-9" }
      MockState.secretNames = true; MockFire("UNIT_TARGET", "target")''')
    assert units.eval(f"MockUnwrap({TGT}.targetOf:GetText())") == "» Bramble"
    assert units.eval("HogHeals.errors[1]") is None


def test_switched_off_and_compact_frames_have_no_line(units):
    units.execute('''MockUnits.targettarget = { name = "Bramble", class = "DRUID", guid = "P-9" }
      HogHeals.OptionsTable().args.Units.args.target.args.targetLine.set({}, false)''')
    assert line(units) is None
    units.execute('HogHeals.db.profile.units.target.targetLine = true; HogHeals.db.profile.units.target.height = 28; HogHealsUnits.Units.Refresh()')
    assert units.eval(f"{TGT}.compact") is True and line(units) is None
    assert units.eval("HogUITargetOfTarget.targetOf") is None                   # only target / focus get one


def test_the_target_cast_bar_says_who_the_cast_is_aimed_at(units):
    units.execute('''MockUnits.targettarget = { name = "Hognificent", class = "MAGE", guid = "Player-0" }
      MockState.time = 80
      MockUnits.target.casting = { "Fireball", "Fireball", "icon", 80000, 82500, false, 1, false, 133 }
      MockFire("UNIT_SPELLCAST_START", "target")''')
    assert units.eval(f"{TGT}.castbar.text:GetText()") == "Fireball » You"
    units.execute('HogHeals.db.profile.units.target.castTarget = false; MockFire("UNIT_SPELLCAST_START", "target")')
    assert units.eval(f"{TGT}.castbar.text:GetText()") == "Fireball"
    units.execute('''HogHeals.db.profile.units.target.castTarget = true; MockUnits.targettarget = nil
      MockFire("UNIT_SPELLCAST_START", "target")''')
    assert units.eval(f"{TGT}.castbar.text:GetText()") == "Fireball"             # aimed at nobody: just the spell


def test_a_hidden_cast_name_with_a_hidden_target_still_reads(units):
    units.execute('''MockUnits.targettarget = { name = "Bramble", class = "DRUID", guid = "P-9" }
      MockState.secretNames = true; MockState.time = 80
      MockUnits.target.casting = { MockSecret("Fireball"), "Fireball", "icon", 80000, 82500, false, 1, false, 133 }
      MockFire("UNIT_SPELLCAST_START", "target")''')
    assert units.eval(f"MockUnwrap({TGT}.castbar.text:GetText())") == "Fireball » Bramble"
    assert units.eval("HogHeals.errors[1]") is None


def test_the_target_of_text_is_pure_and_names_you(units):
    units.execute('MockUnits.targettarget = { name = "Hognificent", guid = "Player-0", class = "MAGE" }')
    assert units.eval(f'({U}.TargetOfText("target", " » "))') == " » You"
    assert units.eval(f'({U}.TargetOfText("player"))') is None                  # the player frame has none
