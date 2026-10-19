# Portraits beside the unit frames (Sean 2026-10-18: "If somebody wants pictures next to the unit frames of their
# character and the mob of their fighting, we can add that"): off by default, per frame; 2D picture or 3D model.
import pytest

from test_units import boot

PORTRAIT_API = '''
function SetPortraitTexture(tex, unit) tex:SetTexture("portrait:" .. unit) end
'''


@pytest.fixture
def units(lua):
    b = boot(lua, extra=PORTRAIT_API)
    b.execute('''
      MockUnits.target = { name = "Kobold", class = "WARRIOR", isPlayer = false, health = 30, maxHealth = 60, guid = "C-70" }
      MockFire("PLAYER_TARGET_CHANGED")''')
    return b


def on(lua, unit):
    lua.execute(f"HogHeals.db.profile.units.{unit}.portrait = true; HogHealsUnits.Units.Refresh()")


def test_off_by_default(units):
    for unit, frame in (("player", "HogUIPlayer"), ("target", "HogUITarget")):
        assert units.eval(f"HogHeals.db.profile.units.{unit}.portrait") in (None, False)
        assert units.eval(f"{frame}.portrait:IsShown()") is False
    assert units.eval("HogUITargetOfTarget.portrait") is None                  # player / target / focus only


def test_player_left_target_right_as_tall_as_the_frame(units):
    on(units, "player")
    on(units, "target")
    p = list(units.eval("HogUIPlayer.portrait._points[1]").values())
    assert p[0] == "TOPRIGHT" and p[2] == "TOPLEFT" and p[3] == -2               # outer side, 2 px gap
    t = list(units.eval("HogUITarget.portrait._points[1]").values())
    assert t[0] == "TOPLEFT" and t[2] == "TOPRIGHT" and t[3] == 2
    h = units.eval("HogHeals.db.profile.units.player.height")
    assert units.eval("HogUIPlayer.portrait:GetWidth()") == h and units.eval("HogUIPlayer.portrait:GetHeight()") == h
    assert units.eval("HogUIPlayer.portrait.tex:GetTexture()") == "portrait:player"
    assert units.eval("HogUITarget.portrait.tex:GetTexture()") == "portrait:target"
    assert units.eval("HogUIPlayer.portrait:IsMouseEnabled()") in (None, False)  # never takes the click


def test_a_new_target_or_a_portrait_event_redraws_it(units):
    on(units, "target")
    units.execute('''SetPortraitTexture = function(tex, unit) tex:SetTexture("portrait:" .. UnitName(unit)) end
      MockUnits.target = { name = "Wolf", class = "WARRIOR", isPlayer = false, health = 1, maxHealth = 1, guid = "C-71" }
      MockFire("PLAYER_TARGET_CHANGED")''')
    assert units.eval("HogUITarget.portrait.tex:GetTexture()") == "portrait:Wolf"
    units.execute('MockUnits.target.name = "Dire Wolf"; MockFire("UNIT_PORTRAIT_UPDATE", "target")')
    assert units.eval("HogUITarget.portrait.tex:GetTexture()") == "portrait:Dire Wolf"


def test_3d_uses_a_live_model_and_falls_back_to_the_picture(units):
    units.execute('''
      local m = HogUIPlayer.portrait.model
      function m:SetUnit(u) self._unit = u end
      function m:SetPortraitZoom(z) self._zoom = z end
      HogHeals.OptionsTable().args.Units.args.general.args.portraitStyle.set({}, "3D")''')
    on(units, "player")
    assert units.eval("HogUIPlayer.portrait.model:IsShown()") is True and units.eval("HogUIPlayer.portrait.model._unit") == "player"
    assert units.eval("HogUIPlayer.portrait.model._zoom") == 1 and units.eval("HogUIPlayer.portrait.tex:IsShown()") is False
    # a client with no model frames (the mock answers every method name, so the model itself goes)
    units.execute("HH_M = HogUIPlayer.portrait.model; HogUIPlayer.portrait.model = nil; HogHealsUnits.Units.Refresh()")
    assert units.eval("HogUIPlayer.portrait.tex:IsShown()") is True and units.eval("HogUIPlayer.portrait.tex:GetTexture()") == "portrait:player"
    units.execute("HogUIPlayer.portrait.model = HH_M; HogHeals.db.profile.units.portraitStyle = '2D'; HogHealsUnits.Units.Refresh()")
    assert units.eval("HogUIPlayer.portrait.model:IsShown()") is False and units.eval("HogUIPlayer.portrait.tex:IsShown()") is True


def test_no_portrait_call_leaves_it_empty_and_says_so(units):
    units.execute("SetPortraitTexture = nil")
    on(units, "player")
    assert units.eval("HogUIPlayer.portrait:IsShown()") is True and units.eval("HogUIPlayer.portrait.tex:IsShown()") is False
    assert any("no SetPortraitTexture" in l for l in units.eval("HogHealsUnits.Units.Diagnose()").values())
    assert units.eval("HogHeals.errors[1]") is None


def test_the_per_frame_switch_and_a_frame_turned_off(units):
    units.execute('HogHeals.OptionsTable().args.Units.args.player.args.portrait.set({}, true)')
    assert units.eval("HogUIPlayer.portrait:IsShown()") is True
    units.execute("HogHeals.db.profile.units.player.enabled = false; HogHealsUnits.Units.Refresh()")
    assert units.eval("HogUIPlayer.portrait:IsShown()") is False
