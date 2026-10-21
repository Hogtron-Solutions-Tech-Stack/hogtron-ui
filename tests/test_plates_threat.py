# Threat colours on the nameplate health bar (Sean 2026-10-20: "changing the color of the plates as aggro goes up ...
# yellow, orange, red"). Forever can hand threat over SECRET (C_Secrets.ShouldUnitThreatStateBeSecret): then nothing is
# compared, a colour curve may paint it, and diag.threat records what came back.
import pytest

from test_plates import boot, add, errors

DETAILED = '''
DT = {}
function UnitDetailedThreatSituation(a, u) local t = DT[u] if t then return t[1], t[2], t[3] end end
'''

GREEN, YELLOW, ORANGE, RED = (0.30, 0.72, 0.38), (0.95, 0.82, 0.20), (1.00, 0.50, 0.10), (0.85, 0.20, 0.20)
HOSTILE = (0.85, 0.20, 0.20)


@pytest.fixture
def lua_plates(lua):
    """Style "bar": the whole health bar takes the threat colour."""
    boot(lua, DETAILED)
    lua.execute('HogHeals.db.profile.plates.threat.style = "bar"')
    return lua


@pytest.fixture
def border_plates(lua):
    """The default style: the bar keeps red / yellow, the border shows threat."""
    return boot(lua, DETAILED)


def colour(lua, uf):
    return tuple(round(lua.eval(f'{uf}.healthBar._color[{i}]'), 2) for i in (1, 2, 3))


def mob(lua, unit="nameplate1"):
    uf = add(lua, unit, '{ name = "Defias Thug", class = "WARRIOR", health = 50, maxHealth = 100, guid = "C-1" }')
    lua.execute(f'REACT.{unit} = 2; MockFire("UNIT_FACTION", "{unit}")')
    return uf


def threat(lua, unit, tanking, status, pct):
    lua.execute(f'DT.{unit} = {{ {str(tanking).lower()}, {status}, {pct} }}; MockFire("UNIT_THREAT_LIST_UPDATE", "{unit}")')


def test_damage_dealer_goes_green_yellow_orange_red_as_threat_climbs(lua_plates):
    lua = lua_plates
    uf = mob(lua)
    assert colour(lua, uf) == HOSTILE                      # not fighting me: the normal colour
    threat(lua, "nameplate1", False, 0, 30)
    assert colour(lua, uf) == GREEN and lua.eval(f'{uf}.hh.threat') == "safe"
    threat(lua, "nameplate1", False, 0, 60)
    assert colour(lua, uf) == YELLOW
    threat(lua, "nameplate1", False, 0, 85)
    assert colour(lua, uf) == ORANGE
    threat(lua, "nameplate1", False, 1, 40)                 # status 1 = over the tank, not tanking: about to pull
    assert colour(lua, uf) == ORANGE
    threat(lua, "nameplate1", True, 3, 100)
    assert colour(lua, uf) == RED and lua.eval(f'{uf}.hh.threat') == "aggro"
    threat(lua, "nameplate1", False, 0, 60)
    assert colour(lua, uf) == YELLOW
    lua.execute('DT.nameplate1 = nil; MockFire("PLAYER_REGEN_ENABLED")')
    assert colour(lua, uf) == HOSTILE                      # fight over: normal colour back
    assert errors(lua) == []


def test_tank_reads_it_the_other_way_round(lua_plates):
    lua = lua_plates
    lua.execute('HogHeals.db.profile.plates.threat.mode = "tank"')
    uf = mob(lua)
    threat(lua, "nameplate1", True, 3, 100)
    assert colour(lua, uf) == GREEN and lua.eval(f'{uf}.hh.threat') == "secure"
    threat(lua, "nameplate1", True, 2, 100)
    assert colour(lua, uf) == ORANGE
    threat(lua, "nameplate1", False, 0, 70)
    assert colour(lua, uf) == RED and lua.eval(f'{uf}.hh.threat') == "lost"
    assert errors(lua) == []


def test_auto_mode_knows_a_tank_by_stance_or_form(lua_plates):
    lua = lua_plates
    lua.execute('FORM = nil; function GetShapeshiftFormID() return FORM end')
    assert lua.eval('(HogHealsPlates.Plates.IsTank())') is False
    lua.execute('FORM = 18')                                # Defensive Stance
    assert lua.eval('(HogHealsPlates.Plates.IsTank())') is True
    lua.execute('FORM = 5')                                 # Bear Form
    assert lua.eval('(HogHealsPlates.Plates.IsTank())') is True
    lua.execute('FORM = nil; function UnitGroupRolesAssigned() return "TANK" end')
    assert lua.eval('(HogHealsPlates.Plates.IsTank())') is True
    lua.execute('HogHeals.db.profile.plates.threat.mode = "dps"')
    assert lua.eval('(HogHealsPlates.Plates.IsTank())') is False   # the setting wins over the guess


def test_safe_can_keep_the_normal_colour_and_the_feature_can_be_off(lua_plates):
    lua = lua_plates
    lua.execute('HogHeals.db.profile.plates.threat.colorSafe = false')
    uf = mob(lua)
    threat(lua, "nameplate1", False, 0, 20)
    assert colour(lua, uf) == HOSTILE
    threat(lua, "nameplate1", False, 0, 60)
    assert colour(lua, uf) == YELLOW
    lua.execute('HogHeals.db.profile.plates.threat.enabled = false; HogHealsPlates.Plates.Refresh()')
    assert colour(lua, uf) == HOSTILE


def test_blizzard_repaint_gets_the_threat_colour_back(lua_plates):
    lua = lua_plates
    uf = mob(lua)
    threat(lua, "nameplate1", False, 0, 85)
    lua.execute(f'{uf}.healthBar:SetStatusBarColor(1, 0, 0)')
    assert colour(lua, uf) == ORANGE


def test_players_are_never_threat_coloured(lua_plates):
    lua = lua_plates
    uf = add(lua, "nameplate2", '{ name = "Zug", class = "MAGE", health = 10, maxHealth = 10, guid = "P-9", isPlayer = true }')
    threat(lua, "nameplate2", True, 3, 100)
    assert lua.eval(f'{uf}.healthBar._color[3]') == pytest.approx(0.94, abs=0.02)   # class colour stays


def test_secret_threat_is_never_compared_and_is_recorded(lua_plates):
    lua = lua_plates
    uf = mob(lua)
    lua.execute('''MockSetSecrets(true)
      C_Secrets = { ShouldUnitThreatStateBeSecret = function() return true end, ShouldUnitThreatValuesBeSecret = function() return true end }
      DT.nameplate1 = { MockSecret(true), MockSecret(3), MockSecret(100) }
      MockFire("UNIT_THREAT_LIST_UPDATE", "nameplate1")''')
    # no curve API in this client: the bar keeps its normal colour, and nothing threw
    assert colour(lua, uf) == HOSTILE and lua.eval(f'{uf}.hh.threat') == "secret"
    assert errors(lua) == []
    t = lua.eval('HogHeals.db.global.diag.threat')
    assert t["counts"]["secret"] >= 1
    assert t["last"]["secret"]["stateSecret"] == "true" and t["last"]["secret"]["status"] == "secret"
    assert "no curve" in t["last"]["curve"]["result"]


def test_secret_threat_paints_through_a_colour_curve_when_the_client_has_one(lua_plates):
    lua = lua_plates
    lua.execute('''
      C_CurveUtil = { CreateColorCurve = function()
        local c = { pts = {} }
        function c:SetType(t) self.type = t end
        function c:AddPoint(x, col) self.pts[x] = col end
        function c:Evaluate(v) return self.pts[MockUnwrap(v)] end
        return c
      end }
      Enum.LuaCurveType = { Step = 1 }
      CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, GetRGB = function(s) return s.r, s.g, s.b end } end''')
    uf = mob(lua)
    lua.execute('MockSetSecrets(true); DT.nameplate1 = { MockSecret(false), MockSecret(1), MockSecret(90) }; MockFire("UNIT_THREAT_LIST_UPDATE", "nameplate1")')
    assert colour(lua, uf) == ORANGE                       # status 1 -> about to pull, never compared by us
    lua.execute('DT.nameplate1 = { MockSecret(true), MockSecret(3), MockSecret(100) }; MockFire("UNIT_THREAT_LIST_UPDATE", "nameplate1")')
    assert colour(lua, uf) == RED
    assert lua.eval('HogHeals.db.global.diag.threat.counts.curveDrew') >= 2
    assert errors(lua) == []


def test_a_refused_threat_call_falls_back_and_is_logged(lua_plates):
    lua = lua_plates
    lua.execute('function UnitDetailedThreatSituation() error("Threat cannot be accessed while tainted") end')
    uf = mob(lua)
    lua.execute('THREAT.nameplate1 = 2; MockFire("UNIT_THREAT_SITUATION_UPDATE", "nameplate1")')
    assert colour(lua, uf) == RED                          # UnitThreatSituation answered
    assert "tainted" in lua.eval('HogHeals.db.global.diag.threat.last.error.err')
    assert errors(lua) == []


def test_threatdiag_prints(lua_plates):
    lua = lua_plates
    mob(lua)
    threat(lua, "nameplate1", False, 0, 60)
    lua.execute('PRINTED = {}; local p = HogHeals.Print; HogHeals.Print = function(self, m) PRINTED[#PRINTED + 1] = m end; HogHeals:SlashCommand("threatdiag"); HogHeals.Print = p')
    out = "\n".join(lua.eval('PRINTED').values())
    assert "threat colours: on" in out and "seen:" in out and "plain=" in out and "rising" in out


# ---- style "border" (the default): Sean 2026-10-20 "I still want to be able to differentiate between aggressive mobs
# and non-aggressive mobs" - the bar keeps red (hostile) / yellow (neutral), the border carries the threat colour.

NEUTRAL = (0.95, 0.80, 0.20)


def edge_line(lua, uf):
    return tuple(round(lua.eval(f'{uf}.hh.edges[1]._color[{i}]'), 2) for i in (1, 2, 3))


def edge(lua, uf):
    """The threat ring's colour, or the plain line colour when the ring is hidden."""
    if lua.eval(f'{uf}.hh.tring ~= nil and {uf}.hh.tring[1]:IsShown()'):
        return tuple(round(lua.eval(f'{uf}.hh.tring[1]._color[{i}]'), 2) for i in (1, 2, 3))
    return tuple(round(lua.eval(f'{uf}.hh.edges[1]._color[{i}]'), 2) for i in (1, 2, 3))


def test_border_style_keeps_hostile_red_and_neutral_yellow_bars(border_plates):
    lua = border_plates
    assert lua.eval('HogHeals.db.profile.plates.threat.style') == "border"
    hostile = mob(lua, "nameplate1")
    neutral = add(lua, "nameplate2", '{ name = "Plainstrider", class = "WARRIOR", health = 50, maxHealth = 100, guid = "C-2" }')
    lua.execute('REACT.nameplate2 = 4; MockFire("UNIT_FACTION", "nameplate2")')
    threat(lua, "nameplate1", False, 0, 60)
    threat(lua, "nameplate2", True, 3, 100)
    assert colour(lua, hostile) == HOSTILE and colour(lua, neutral) == NEUTRAL      # bars: who the mob is
    assert edge(lua, hostile) == YELLOW and edge(lua, neutral) == RED              # borders: threat on me
    assert lua.eval(f'{hostile}.hh.tring[1]._height') == 2                          # a 2 px ring ...
    assert edge_line(lua, hostile) == (0.05, 0.05, 0.06)                            # ... outside the dark line
    assert lua.eval(f'{neutral}.hh.why') == "aggro" and lua.eval(f'{hostile}.hh.why') == "threat"
    threat(lua, "nameplate1", False, 0, 85)
    assert edge(lua, hostile) == ORANGE
    lua.execute('DT.nameplate1 = nil; DT.nameplate2 = nil; MockFire("UNIT_THREAT_LIST_UPDATE")')
    assert edge(lua, hostile) == (0.05, 0.05, 0.06)                                 # fight over: plain line back
    assert errors(lua) == []


def test_border_safe_is_green_or_plain(border_plates):
    lua = border_plates
    uf = mob(lua)
    threat(lua, "nameplate1", False, 0, 20)
    assert edge(lua, uf) == GREEN and colour(lua, uf) == HOSTILE
    lua.execute('HogHeals.db.profile.plates.threat.colorSafe = false; HogHealsPlates.Plates.Refresh()')
    assert edge(lua, uf) == (0.05, 0.05, 0.06)


def test_border_from_a_secret_status_goes_through_the_curve(border_plates):
    lua = border_plates
    lua.execute('''
      C_CurveUtil = { CreateColorCurve = function()
        local c = { pts = {} }
        function c:AddPoint(x, col) self.pts[x] = col end
        function c:Evaluate(v) return self.pts[MockUnwrap(v)] end
        return c
      end }
      CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, GetRGB = function(s) return s.r, s.g, s.b end } end''')
    uf = mob(lua)
    lua.execute('MockSetSecrets(true); DT.nameplate1 = { MockSecret(false), MockSecret(1), MockSecret(90) }; MockFire("UNIT_THREAT_LIST_UPDATE", "nameplate1")')
    assert edge(lua, uf) == ORANGE and colour(lua, uf) == HOSTILE
    assert lua.eval('HogHeals.db.global.diag.threat.last.curveDrew.result') == "border from a secret status"
    assert errors(lua) == []
