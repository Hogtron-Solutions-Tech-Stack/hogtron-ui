# DoesItDie (HogHeals_Plates/DoesItDie.lua): skull when my DoT outlives the mob, red X when it ends first and soon.
import pytest

from test_plates import boot, errors

D = "HogHealsPlates.DoesItDie"


@pytest.fixture
def die(lua):
    boot(lua, quests=False)
    lua.execute("""
      MockState.time = 100
      MockPlate("nameplate1", { name = "Mottled Boar", health = 1000, maxHealth = 1000, level = 8,
        auras = { { name = "Corruption", type = "Magic", source = "player", duration = 18, expires = 118, icon = "corr" } } })
      MockFire("NAME_PLATE_UNIT_ADDED", "nameplate1")
      UF = HogHealsPlates.Plates.active.nameplate1
    """)
    return lua


def hp(lua, t, value):
    lua.execute(f"MockState.time = {t}; MockUnits.nameplate1.health = {value}; MockFire('UNIT_HEALTH', 'nameplate1')")


def test_verdict_is_pure(die):
    v = lambda ttd, rem: die.eval(f"{D}.Verdict({ttd if ttd is not None else 'nil'}, {rem if rem is not None else 'nil'}, {{ margin = 0.1, reapplyAt = 3 }})")
    assert v(None, None) is None
    assert v(None, 10) == "running"                                       # DoT up, health not dropping yet
    assert v(8, 10) == "dies" and v(9.5, 10) == "running"                 # inside the 10% margin: not called
    assert v(20, 2.5) == "reapply" and v(20, 6) == "running"


def test_health_slope_gives_time_to_die_and_the_skull_shows(die):
    assert die.eval(f"{D}.TimeToDie('nameplate1')") is None               # one sample: nothing yet
    hp(die, 101, 950); hp(die, 102, 900); hp(die, 103, 850)                # 50 hp/s -> 17 s to die
    assert die.eval(f"({D}.TimeToDie('nameplate1'))") == pytest.approx(17.0)
    die.execute("MockAdvance(0.5)")                                        # the ticker paints
    st = die.eval(f"{D}.state.nameplate1")
    assert st["verdict"] == "running"                                      # 17 s to die vs 15 s of DoT left: not yet
    hp(die, 104, 700)                                                      # a crit: 75 hp/s over the window -> ~9 s
    die.execute("MockAdvance(0.5)")
    st = die.eval(f"{D}.state.nameplate1")
    assert st["verdict"] == "dies" and st["ttd"] < st["remaining"]
    assert die.eval("UF.hh.die:IsShown()") is True
    assert "RaidTargetingIcon_8" in die.eval("UF.hh.die.icon._texture")
    assert die.eval("UF.hh.die.time._text").endswith("s")
    assert die.eval("UF.hh.die._points[1][1]") == "LEFT" and die.eval("UF.hh.die._points[1][3]") == "RIGHT"
    assert errors(die) == []


def test_dot_about_to_drop_on_a_mob_that_outlives_it_pulses_the_cross(die):
    hp(die, 101, 990); hp(die, 103, 970)                                   # 10 hp/s: ~97 s to die
    die.execute("MockUnits.nameplate1.auras[1].expires = 105.5; MockFire('UNIT_AURA', 'nameplate1'); MockAdvance(0.5)")
    st = die.eval(f"{D}.state.nameplate1")
    assert st["verdict"] == "reapply" and st["remaining"] == pytest.approx(2.0, abs=0.6)
    assert "ReadyCheck-NotReady" in die.eval("UF.hh.die.icon._texture")
    a1 = die.eval("UF.hh.die._alpha")
    die.execute("MockAdvance(0.5)")
    assert die.eval("UF.hh.die._alpha") != a1                              # pulsing
    # the DoT runs out: nothing of mine on it -> the mark goes
    die.execute("MockUnits.nameplate1.auras = {}; MockFire('UNIT_AURA', 'nameplate1'); MockAdvance(0.5)")
    assert die.eval("UF.hh.die:IsShown()") is False
    assert errors(die) == []


def test_plate_recycled_forgets_and_secret_health_is_said(die):
    hp(die, 101, 900)
    die.execute("MockFire('NAME_PLATE_UNIT_REMOVED', 'nameplate1')")
    assert die.eval(f"{D}.samples.nameplate1") is None and die.eval(f"{D}.dots.nameplate1") is None
    die.execute("""
      MockSetSecrets(true)
      MockPlate("nameplate2", { name = "Hidden", health = 500, maxHealth = 500, level = 9, auras = { { name = "Corruption", type = "Magic", source = "player", duration = 18, expires = 118 } } })
      local orig = UnitHealth
      UnitHealth = function(u) if u == "nameplate2" then return MockSecret(500) end return orig(u) end
      MockFire("NAME_PLATE_UNIT_ADDED", "nameplate2")
      MockState.time = 102; MockFire("UNIT_HEALTH", "nameplate2"); MockAdvance(0.5)
    """)
    assert die.eval(f"{D}.secret") >= 1
    assert die.eval(f"{D}.TimeToDie('nameplate2')") is None
    st = die.eval(f"{D}.state.nameplate2")
    assert st is None or st["verdict"] == "running"
    line = die.eval(f"{D}.DiagLine()")
    assert "secret health readings" in line and "hides enemy health" in line
    assert any("does it die" in l for l in die.eval("HogHealsPlates.Plates.Diagnose()").values())
    assert errors(die) == []


def test_off_switch(die):
    die.execute("HogHeals.db.profile.plates.die.enabled = false")
    hp(die, 101, 900); hp(die, 103, 500)
    die.execute("MockAdvance(0.5)")
    assert die.eval("UF.hh.die == nil or not UF.hh.die:IsShown()")
    assert "off" in die.eval(f"{D}.DiagLine()")
