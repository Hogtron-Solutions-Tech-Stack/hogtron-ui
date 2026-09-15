def test_runtime_has_wow_globals(lua):
    assert lua.eval("type(CreateFrame)") == "function"
    assert lua.eval("type(UnitHealth)") == "function"
    assert lua.eval("_VERSION") == "Lua 5.1"


def test_can_load_core(core):
    assert core.eval("type(HogHeals)") == "table"
