# Forever beta: opening /hh threw "AceGUIWidget-CheckBox.lua:130: attempt to call a nil value" = SetDesaturation,
# a FrameXML helper this client does not ship. AceGUI v26 is the newest that exists, so we fill the hole.

def test_setdesaturation_exists_and_drives_the_texture(core):
    assert core.eval('type(SetDesaturation)') == "function"
    core.execute('HH_tex = { SetDesaturated = function(self, v) self.got = v; return true end }; SetDesaturation(HH_tex, true)')
    assert core.eval('HH_tex.got') is True
    core.execute('SetDesaturation(HH_tex, nil)')
    assert core.eval('HH_tex.got') is False


def test_falls_back_to_grey_when_the_shader_is_unsupported(core):
    core.execute('HH_tex2 = { SetDesaturated = function() return false end, SetVertexColor = function(self, r) self.r = r end }; SetDesaturation(HH_tex2, true)')
    assert core.eval('HH_tex2.r') == 0.5


def test_shim_lives_in_a_file_that_reload_rereads():
    # A brand-new toc entry can need a full client restart; the tester is behind a login queue.
    import pathlib
    root = pathlib.Path(__file__).resolve().parent.parent / "HogHeals"
    assert "function SetDesaturation(" in (root / "Core.lua").read_text(encoding="utf-8")
    assert "ClientShims" not in (root / "HogHeals.toc").read_text(encoding="utf-8")


def test_snapshot_lists_globals_this_client_lacks(core):
    core.execute('HH_keep = GetSpellInfo; GetSpellInfo = nil; HogHeals:SnapshotClient(); GetSpellInfo = HH_keep')
    missing = core.eval('HogHeals.db.global.diag.client.missingGlobals').split(",")
    assert "GetSpellInfo" in missing and "SetDesaturation" not in missing
