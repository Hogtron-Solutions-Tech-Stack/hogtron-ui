# Camera (HogTronUI/Core/Camera.lua): cameraDistanceMaxZoomFactor from the profile, the client's cap read back.
# Sean 2026-11-04: "I also want to be able to zoom out further. I think the default is very close."
CVARS = '''
CV = { cameraDistanceMaxZoomFactor = "1.9" }
function SetCVar(k, v)
  if k == "cameraDistanceMaxZoomFactor" and tonumber(v) > 2.6 then v = 2.6 end   -- the client caps what it keeps
  CV[k] = tostring(v)
end
function GetCVar(k) return CV[k] end
'''


def boot(lua, extra=""):
    lua.execute(CVARS + extra)
    lua.load_addon("HogTronUI")
    lua.player_login()
    lua.execute("wipe(HogHeals.errors)")
    return lua


def errors(lua):
    return [e["msg"] for e in lua.eval("HogHeals.errors").values()]


def test_login_and_world_entry_apply_the_profiles_max_zoom(lua):
    boot(lua)
    assert lua.eval("CV.cameraDistanceMaxZoomFactor") == "2.6"            # default 2.6, applied at login
    assert lua.eval("HogHeals.Camera.last.why") == "world" and lua.eval("HogHeals.Camera.last.kept") == 2.6   # login, then the world entry the harness fires
    lua.execute("CV.cameraDistanceMaxZoomFactor = '1.9'")
    lua.fire("PLAYER_ENTERING_WORLD")
    assert lua.eval("CV.cameraDistanceMaxZoomFactor") == "2.6" and lua.eval("HogHeals.Camera.last.why") == "world"
    assert errors(lua) == []


def test_the_clients_cap_is_read_back_not_hidden(lua):
    boot(lua)
    lua.execute("HogHeals.db.profile.camera.maxZoom = 4")
    assert lua.eval('HogHeals.Camera.Apply("test")') == 2.6
    assert lua.eval("HogHeals.Camera.Say()") == "camera: max zoom-out set to 4.0, the client keeps 2.6 - this client's cap. Scroll out to use it."
    lua.execute("HogHeals.db.profile.camera.maxZoom = 2.2")
    assert lua.eval("HogHeals.Camera.Say()") == "camera: max zoom-out set to 2.2, the client keeps 2.2. Scroll out to use it."


def test_zero_leaves_the_clients_own_value_alone(lua):
    boot(lua)
    lua.execute("CV.cameraDistanceMaxZoomFactor = '1.9'; HogHeals.db.profile.camera.maxZoom = 0")
    assert lua.eval('select(2, HogHeals.Camera.Apply("test"))').startswith("off")
    assert lua.eval("CV.cameraDistanceMaxZoomFactor") == "1.9"


def test_slash_zoom_sets_the_profile_and_applies(lua):
    boot(lua)
    lua.execute('HogHeals:SlashCommand("zoom 2.2")')
    assert lua.eval("HogHeals.db.profile.camera.maxZoom") == 2.2 and lua.eval("CV.cameraDistanceMaxZoomFactor") == "2.2"
    lua.execute('HogHeals:SlashCommand("zoom")')                            # no number: just says where things stand
    assert lua.eval("HogHeals.db.profile.camera.maxZoom") == 2.2
    assert errors(lua) == []


def test_c_cvar_api_wins_when_the_client_has_it(lua):
    boot(lua, extra='C_CVar = { SetCVar = function(k, v) CC = { k, tostring(v) } end, GetCVar = function(k) return CC and CC[2] end }')
    lua.execute('HogHeals.Camera.Apply("test")')
    assert lua.eval("CC[1]") == "cameraDistanceMaxZoomFactor" and lua.eval("CC[2]") == "2.6"
    assert lua.eval("CV.cameraDistanceMaxZoomFactor") == "1.9"            # the global SetCVar was never touched


def test_no_setcvar_is_reported_not_raised(lua):
    boot(lua, extra="SetCVar = nil; GetCVar = nil")
    assert lua.eval('select(2, HogHeals.Camera.Apply("test"))') == "no SetCVar on this client"
    assert lua.eval("HogHeals.Camera.Say()") == "camera: no SetCVar on this client"
    assert errors(lua) == []


def test_general_tab_carries_the_slider_with_the_default(lua):
    boot(lua)
    args = lua.eval("HogHeals.OptionsTable().args.general.args")
    assert args["camera"]["type"] == "range" and args["camera"]["order"] == 3.5
    assert lua.eval("HogHeals.OptionsTable().args.general.args.camera.get()") == 2.6
    lua.execute("HogHeals.OptionsTable().args.general.args.camera.set(nil, 2.4)")
    assert lua.eval("CV.cameraDistanceMaxZoomFactor") == "2.4"
