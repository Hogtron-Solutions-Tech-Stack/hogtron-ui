def test_register_module(core):
    core.execute('HogHeals:RegisterModule("Demo", {OnEnable=function() end})')
    assert core.eval('HogHeals.modules.Demo ~= nil')
    assert core.eval('HogHeals.modules.Demo.name') == "Demo"


def test_version_string(core):
    assert core.eval('type(HogHeals.version)') == "string"


def test_db_exists_after_login(core):
    assert core.eval('type(HogHeals.db)') == "table"
    assert core.eval('type(HogHeals.db.profile)') == "table"


def test_module_on_enable_called(lua):
    lua.load_addon("HogHeals")
    lua.execute('HogHeals:RegisterModule("Demo", {OnEnable=function(self) self.enabled = true end})')
    lua.player_login()
    assert lua.eval('HogHeals.modules.Demo.enabled') is True
