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


def test_version_token_reads_as_dev(lua):
    # A git checkout ships the packager token unreplaced; players and bug reports should see "dev", not the token.
    lua.execute('C_AddOns.GetAddOnMetadata = function(_, k) return k == "Version" and "@project-version@" or nil end')
    lua.load_addon("HogHeals")
    assert lua.eval('HogHeals.version') == "dev"


def test_version_from_release_toc(lua):
    lua.execute('C_AddOns.GetAddOnMetadata = function(_, k) return k == "Version" and "v0.2.0-beta.1" or nil end')
    lua.load_addon("HogHeals")
    assert lua.eval('HogHeals.version') == "0.2.0-beta.1"   # tag v-prefix dropped; panel adds its own "v"
