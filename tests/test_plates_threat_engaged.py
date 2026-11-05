# A mob fighting the group with no threat on us (the client answers nil): its target says what we are to it.
# Sean 2026-11-05 (screenshot: the mob on a party member, Sean drinking): "Threat is also not working by default."
from test_plates_threat import lua_plates, mob, colour, errors, HOSTILE, GREEN, RED  # noqa: F401 (fixture)

NO_TABLE = '''
UnitThreatSituation = function() return nil end        -- not on its threat table at all
DT.nameplate1 = nil
MockState.inCombat = true
MockUnits.nameplate1target = { name = "Anub", class = "DRUID", guid = "Player-9" }
UnitInParty = function(u) return u == "nameplate1target" or u == "player" end
UnitIsUnit = function(a, b) return a == b or (MockUnits[a] ~= nil and MockUnits[b] ~= nil and MockUnits[a].guid == MockUnits[b].guid) end   -- the plates client fakes it by token
'''


def test_a_mob_on_a_groupmate_reads_safe_and_on_me_reads_aggro(lua_plates):
    lua = lua_plates
    uf = mob(lua)
    assert colour(lua, uf) == HOSTILE
    lua.execute(NO_TABLE + 'MockFire("UNIT_TARGET", "nameplate1")')
    assert colour(lua, uf) == GREEN and lua.eval(f"{uf}.hh.threat") == "safe"
    lua.execute('MockUnits.nameplate1target.guid = "Player-0"; MockFire("UNIT_TARGET", "nameplate1")')   # now it turns on me
    assert colour(lua, uf) == RED and lua.eval(f"{uf}.hh.threat") == "aggro"
    assert lua.eval("HogHeals.db.global.diag.threat.counts.engaged") >= 2
    lua.execute('MockState.inCombat = false; MockFire("PLAYER_REGEN_ENABLED")')                       # fight over
    assert colour(lua, uf) == HOSTILE and lua.eval(f"{uf}.hh.threat") is None
    assert errors(lua) == []


def test_a_tank_reads_the_engaged_mob_the_other_way_round(lua_plates):
    lua = lua_plates
    lua.execute('HogHeals.db.profile.plates.threat.mode = "tank"')
    uf = mob(lua)
    lua.execute(NO_TABLE + 'MockFire("UNIT_TARGET", "nameplate1")')
    assert colour(lua, uf) == RED and lua.eval(f"{uf}.hh.threat") == "lost"           # on someone else: lost it
    lua.execute('MockUnits.nameplate1target.guid = "Player-0"; MockFire("UNIT_TARGET", "nameplate1")')
    assert colour(lua, uf) == GREEN and lua.eval(f"{uf}.hh.threat") == "secure"
    assert errors(lua) == []


def test_a_mob_on_a_stranger_or_without_a_target_stays_normal(lua_plates):
    lua = lua_plates
    uf = mob(lua)
    lua.execute(NO_TABLE + 'UnitInParty = function() return false end; MockFire("UNIT_TARGET", "nameplate1")')
    assert colour(lua, uf) == HOSTILE and lua.eval(f"{uf}.hh.threat") is None         # fighting somebody not ours
    lua.execute('MockUnits.nameplate1target = nil; MockFire("UNIT_TARGET", "nameplate1")')
    assert colour(lua, uf) == HOSTILE
    assert lua.eval("HogHeals.db.global.diag.threat.counts.none") >= 1
    assert errors(lua) == []
