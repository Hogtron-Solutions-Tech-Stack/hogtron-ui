# HogHeals_Plates/Castbar.lua: our own cast bar under every nameplate (HUD look), Blizzard's quiet, secret-safe.
# Sean 2026-10-03 (screenshot: Windfury Matriarch casting Lightning Bolt in Blizzard's art): "style this just
# like ours". Mock plates come from test_plates.py.
import pytest

from test_plates import boot, add


@pytest.fixture
def plates(lua):
    return boot(lua)


def errors(lua):
    return [e["msg"] for e in lua.eval("HogHeals.errors").values()]


CAST = '{ "Lightning Bolt", "Lightning Bolt", "icon-lb", 1000, 3000, false, 7, false }'
LOCKED = '{ "Lightning Bolt", "Lightning Bolt", "icon-lb", 1000, 3000, false, 7, true }'
MOB = '{ name = "Windfury Matriarch", class = "WARRIOR", health = 50, maxHealth = 100, guid = "C-1", isPlayer = false }'


def bar(lua, uf):
    return lua.eval(f"HogHealsPlates.Castbar.For({uf})")


def shown(lua, uf):
    return lua.eval(f"HogHealsPlates.Castbar.For({uf}):IsShown()")


def start(lua, unit="nameplate1", spec=CAST, channel=False):
    key = "channeling" if channel else "casting"
    ev = "UNIT_SPELLCAST_CHANNEL_START" if channel else "UNIT_SPELLCAST_START"
    lua.execute(f'MockUnits.{unit}.{key} = {spec}; MockFire("{ev}", "{unit}")')


# ---------------------------------------------------------------- build + geometry

def test_defaults_present(plates):
    c = plates.eval("HogHeals.db.profile.plates.cast")
    assert c["height"] == 10 and c["icon"] is True and c["time"] is True
    assert list(c["castColor"].values()) == [0.13, 0.83, 0.88]
    assert plates.eval("HogHeals.db.profile.plates.castbar") is True


def test_built_on_add_hidden_under_the_bar(plates):
    uf = add(plates, "nameplate1", MOB)
    assert bar(plates, uf) is not None and shown(plates, uf) is False
    p = plates.eval(f"{{ {uf}.hh.castbar:GetPoint(1) }}")
    point = list(p.values())
    assert point[0] == "TOPLEFT" and point[2] == "BOTTOMLEFT" and point[4] == -3
    assert plates.eval(f"{uf}.hh.castbar:GetPoint(1) ~= nil and select(2, {uf}.hh.castbar:GetPoint(1)) == {uf}.hh.bar")
    assert plates.eval(f"{uf}.hh.castbar:GetHeight()") == 10
    assert plates.eval(f"{uf}.hh.castbar._texture").endswith("WHITE8X8")
    assert plates.eval(f"{uf}.hh.castbar.icon._texCoord ~= nil or true")   # icon exists
    assert plates.eval(f"{uf}.hh.castbar.icon:GetWidth()") == 10


def test_not_built_when_option_off(plates):
    plates.execute("HogHeals.db.profile.plates.castbar = false")
    uf = add(plates, "nameplate1", MOB)
    assert bar(plates, uf) is None


def test_built_lazily_when_option_turned_on_later(plates):
    plates.execute("HogHeals.db.profile.plates.castbar = false")
    uf = add(plates, "nameplate1", MOB)
    assert bar(plates, uf) is None
    plates.execute(f"HogHeals.db.profile.plates.castbar = true; HogHealsPlates.Plates.Update({uf})")
    assert bar(plates, uf) is not None


# ---------------------------------------------------------------- Blizzard's bar

def test_blizzard_container_quiet_on_add_and_again_on_update(plates):
    plates.execute('''
      local p = MockPlate("nameplate1", ''' + MOB + ''')
      p.UnitFrame.CastBarsContainer = CreateFrame("Frame", nil, p.UnitFrame)
      p.UnitFrame.CastBarsContainer:SetAlpha(1)
      MockFire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    ''')
    uf = 'NP["nameplate1"].UnitFrame'
    assert plates.eval(f"{uf}.CastBarsContainer:GetAlpha()") == 0
    plates.execute(f"{uf}.CastBarsContainer:SetAlpha(1); HogHealsPlates.Plates.Update({uf})")
    assert plates.eval(f"{uf}.CastBarsContainer:GetAlpha()") == 0
    assert plates.eval("HogHealsPlates.Castbar.blizzKey") == "CastBarsContainer"


def test_blizzard_castbar_under_other_names_quiet_too_and_never_retextured(plates):
    plates.execute('''
      local p = MockPlate("nameplate1", ''' + MOB + ''')
      p.UnitFrame.castBar = CreateFrame("StatusBar", nil, p.UnitFrame)
      p.UnitFrame.castBar:SetStatusBarTexture("blizz")
      MockFire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    ''')
    uf = 'NP["nameplate1"].UnitFrame'
    assert plates.eval(f"{uf}.castBar:GetAlpha()") == 0
    assert plates.eval(f"{uf}.castBar._texture") == "blizz"          # SkinCastbar no longer runs from ApplyLook
    assert plates.eval(f"rawget({uf}.castBar, 'hh')") is None         # nothing written on Blizzard's frame


def test_blizzard_quiet_again_on_every_cast_event(plates):
    plates.execute('''
      local p = MockPlate("nameplate1", ''' + MOB + ''')
      p.UnitFrame.CastBarsContainer = CreateFrame("Frame", nil, p.UnitFrame)
      MockFire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    ''')
    uf = 'NP["nameplate1"].UnitFrame'
    plates.execute(f"{uf}.CastBarsContainer:SetAlpha(1)")
    start(plates)
    assert plates.eval(f"{uf}.CastBarsContainer:GetAlpha()") == 0


def test_option_off_gives_blizzard_back(plates):
    plates.execute('''
      local p = MockPlate("nameplate1", ''' + MOB + ''')
      p.UnitFrame.CastBarsContainer = CreateFrame("Frame", nil, p.UnitFrame)
      MockFire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    ''')
    uf = 'NP["nameplate1"].UnitFrame'
    plates.execute(f"HogHeals.db.profile.plates.castbar = false; HogHealsPlates.Plates.Update({uf})")
    assert plates.eval(f"{uf}.CastBarsContainer:GetAlpha()") == 1
    assert shown(plates, uf) is False


# ---------------------------------------------------------------- casts

def test_cast_start_shows_name_icon_range_and_cast_colour(plates):
    uf = add(plates, "nameplate1", MOB)
    plates.execute("MockState.time = 1.5")
    start(plates)
    assert shown(plates, uf) is True
    assert plates.eval(f"{uf}.hh.castbar.text:GetText()") == "Lightning Bolt"
    assert plates.eval(f"{uf}.hh.castbar.icon:GetTexture()") == "icon-lb"
    assert plates.eval(f"{{ {uf}.hh.castbar:GetMinMaxValues() }}").values() and list(plates.eval(f"{{ {uf}.hh.castbar:GetMinMaxValues() }}").values()) == [1000, 3000]
    assert plates.eval(f"{uf}.hh.castbar:GetValue()") == 1500
    assert list(plates.eval(f"{{ {uf}.hh.castbar:GetStatusBarColor() }}").values())[:3] == [0.13, 0.83, 0.88]
    assert plates.eval(f"{uf}.hh.castbar.locked:GetAlpha()") == 0
    assert plates.eval(f"{uf}.hh.castbar.time:GetText()") == "1.5"


def test_uninterruptible_cast_shows_the_grey_lock(plates):
    uf = add(plates, "nameplate1", MOB)
    start(plates, spec=LOCKED)
    assert plates.eval(f"{uf}.hh.castbar.locked:GetAlpha()") == 1


def test_channel_uses_channel_colour_and_drains(plates):
    uf = add(plates, "nameplate1", MOB)
    plates.execute("MockState.time = 1.5")
    start(plates, spec='{ "Drain Life", "Drain Life", "icon-dl", 1000, 3000, false, false }', channel=True)
    assert list(plates.eval(f"{{ {uf}.hh.castbar:GetStatusBarColor() }}").values())[:3] == [0.25, 0.80, 0.35]
    assert plates.eval(f"{uf}.hh.castbar:GetValue()") == 1000 + 3000 - 1500


def test_stop_failed_interrupted_hide(plates):
    uf = add(plates, "nameplate1", MOB)
    for ev in ("UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED"):
        start(plates)
        assert shown(plates, uf) is True
        plates.execute(f'MockUnits.nameplate1.casting = nil; MockFire("{ev}", "nameplate1")')
        assert shown(plates, uf) is False, ev


def test_events_for_units_without_a_plate_are_ignored(plates):
    add(plates, "nameplate1", MOB)
    plates.execute('MockUnits.target = { name = "x" }; MockUnits.target.casting = ' + CAST + '; MockFire("UNIT_SPELLCAST_START", "target")')
    assert plates.eval('NP["nameplate1"].UnitFrame.hh.castbar:IsShown()') is False
    assert errors(plates) == []


def test_secret_cast_values_still_render_without_errors(plates):
    uf = add(plates, "nameplate1", MOB)
    plates.execute('MockSetSecrets(true)')
    plates.execute('''
      MockUnits.nameplate1.casting = { MockSecret("Lightning Bolt"), MockSecret("Lightning Bolt"), MockSecret("icon-lb"),
        MockSecret(1000), MockSecret(3000), false, 7, MockSecret(true) }
      MockFire("UNIT_SPELLCAST_START", "nameplate1")
    ''')
    assert shown(plates, uf) is True
    assert plates.eval(f"MockUnwrap({uf}.hh.castbar.text:GetText())") == "Lightning Bolt"
    assert list(plates.eval(f"{{ {uf}.hh.castbar:GetMinMaxValues() }}").values()) == [1000, 3000]
    assert plates.eval(f"{uf}.hh.castbar.locked:GetAlpha()") == 1       # SetAlphaFromBoolean resolved it
    assert plates.eval(f"{uf}.hh.castbar.time:GetText()") == ""         # no arithmetic on a secret end time
    assert errors(plates) == []
    d = plates.eval("HogHeals.db.global.diag.plateCast")
    assert d["secretName"] is True and d["secretTimes"] is True and d["secretLock"] is True


def test_tick_moves_the_fill_and_repolls_the_client(plates):
    uf = add(plates, "nameplate1", MOB)
    plates.execute("MockState.time = 1.0")
    start(plates)
    plates.execute(f"MockState.time = 2.0; {uf}.hh.castbar._scripts.OnUpdate({uf}.hh.castbar, 0.1)")
    assert plates.eval(f"{uf}.hh.castbar:GetValue()") == 2000
    assert plates.eval(f"{uf}.hh.castbar.time:GetText()") == "1.0"
    # the stop event never came; the poll notices the client has no cast any more
    plates.execute(f"MockUnits.nameplate1.casting = nil; {uf}.hh.castbar._scripts.OnUpdate({uf}.hh.castbar, 0.3)")
    assert shown(plates, uf) is False


def test_tick_error_latches_the_bar_off_and_logs_once(plates):
    uf = add(plates, "nameplate1", MOB)
    start(plates)
    plates.execute(f"{uf}.hh.castbar.time.SetText = function() error('boom') end")
    plates.execute(f"{uf}.hh.castbar._scripts.OnUpdate({uf}.hh.castbar, 0.1)")
    plates.execute(f"{uf}.hh.castbar._scripts.OnUpdate({uf}.hh.castbar, 0.1)")
    assert plates.eval(f"{uf}.hh.castbar.broken") is True
    assert shown(plates, uf) is False
    assert len([e for e in errors(plates) if "boom" in e]) == 1


def test_plate_removed_hides_and_clears(plates):
    uf = add(plates, "nameplate1", MOB)
    start(plates)
    plates.execute('MockFire("NAME_PLATE_UNIT_REMOVED", "nameplate1")')
    assert shown(plates, uf) is False
    assert plates.eval(f"{uf}.hh.castbar.casting") is None


def test_name_only_friendly_plate_has_no_cast_bar(plates):
    uf = add(plates, "nameplate1", '{ name = "Friendly Priest", class = "PRIEST", health = 50, maxHealth = 100, guid = "C-2", isPlayer = true, friendly = true }')
    plates.execute("REACT.nameplate1 = 6")
    plates.execute(f"HogHealsPlates.Plates.Update({uf})")
    assert plates.eval(f"{uf}.hh.nameOnly") is True
    start(plates)
    assert shown(plates, uf) is False


def test_recycled_plate_shows_the_new_occupants_cast(plates):
    uf = add(plates, "nameplate1", MOB)
    start(plates)
    plates.execute('MockFire("NAME_PLATE_UNIT_REMOVED", "nameplate1")')
    plates.execute('MockUnits.nameplate1 = { name = "Other Mob", class = "WARRIOR", health = 50, maxHealth = 100, guid = "C-3", isPlayer = false }; MockFire("NAME_PLATE_UNIT_ADDED", "nameplate1")')
    start(plates, spec='{ "Frostbolt", "Frostbolt", "icon-fb", 1000, 3000, false, 8, false }')
    assert plates.eval(f"{uf}.hh.castbar.text:GetText()") == "Frostbolt"
    assert shown(plates, uf) is True


# ---------------------------------------------------------------- options + diag

def test_option_changes_land_on_live_bars(plates):
    uf = add(plates, "nameplate1", MOB)
    plates.execute("HogHeals.db.profile.plates.cast.height = 14; HogHeals.db.profile.plates.cast.icon = false; HogHealsPlates.Plates.Refresh()")
    assert plates.eval(f"{uf}.hh.castbar:GetHeight()") == 14
    assert plates.eval(f"{uf}.hh.castbar.icon:IsShown()") is False


def test_options_group_exists(plates):
    args = plates.eval("HogHealsPlates.Options.Build().args.castbar.args")
    keys = set(args.keys())
    assert {"enabled", "height", "icon", "time", "fontSize", "castColor", "channelColor", "lockedColor"} <= keys


def test_platediag_names_the_cast_bar(plates):
    uf = add(plates, "nameplate1", MOB)
    start(plates)
    lines = list(plates.eval("HogHealsPlates.Plates.Diagnose()").values())
    cast = [l for l in lines if l.startswith("cast bar:")]
    assert cast and "built=1" in cast[0] and "shown=1" in cast[0]
