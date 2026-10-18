# /hh namediag: which call gives a last name on WoW: Forever (Sean 2026-10-17, first + last name on the unit frames).
def test_namediag_lists_candidates_scans_for_surname_apis_and_saves(lua):
    lua.execute('function UnitSurname(u) return "Hogfire" end; C_FakeNames = { GetFullName = function(u) return "Crispin Hogfire" end }')
    lua.load_addon("HogTronUI")
    lua.load_addon("HogTron_Units")
    lua.player_login()
    lua.execute('MockLog.chat = {}; HogHeals:SlashCommand("namediag")')
    lines = lua.eval('HogHeals.db.global.diag.names.lines')
    assert "player UnitName = " in lines
    assert "UnitSurname" in lines and 'UnitSurname("player") = "Hogfire"' in lines
    assert 'C_FakeNames.GetFullName("player") = "Crispin Hogfire"' in lines
    assert "target nameplate text = <no plate>" in lines
    assert any("namediag:" in l for l in lua.eval('MockLog.chat').values())
    assert [e["msg"] for e in lua.eval('HogHeals.errors').values()] == []


def test_namediag_never_formats_a_secret(lua):
    lua.load_addon("HogTronUI")
    lua.load_addon("HogTron_Units")
    lua.player_login()
    lua.execute('MockSetSecrets(true); MockState.secretNames = true; HogHeals:SlashCommand("namediag"); MockSetSecrets(false)')
    assert "player UnitName = <secret>" in lua.eval('HogHeals.db.global.diag.names.lines')
