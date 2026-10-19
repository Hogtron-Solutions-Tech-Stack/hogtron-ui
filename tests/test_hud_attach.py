# The HUD cast bar on the player unit frame (Sean 2026-10-18: "the ability to attach the cast bar to the unit frames").
# hud.castbar.attach = "below" | "above": HogTron_HUD/HUD.lua anchors our bar to HogUIPlayer (the frame itself is a
# secure button and is never touched), as wide as the frame, following it; no frame -> the bar stays in the HUD.
from test_edit_mode import errors, target  # noqa: F401
from test_edit_mode import ed  # noqa: F401  (fixture)

CB = "HogHealsHUD.HUD.rows.castbar"


def points(f, frame=CB):
    out = []
    for p in f.eval(f"{frame}._points").values():
        v = list(p.values())
        out.append((v[0], v[2], v[3], v[4]))
    return out


def attach(f, where):
    f.execute(f'HogHeals.db.profile.hud.castbar.attach = "{where}"; HogHealsHUD.HUD.Refresh()')


def test_under_the_player_frame_as_wide_as_it_and_the_strip_closes_up(ed):  # noqa: F811
    ed.execute("local d = HogHeals.db.profile.hud d.castbarHeight, d.rowSpacing, d.showSwing = 18, 2, true")
    attach(ed, "below")
    assert ed.eval(f"{CB}.attached") == "below" and ed.eval(f"{CB}.detached") is None
    assert ed.eval(f"{CB}._points[1][2] == HogUIPlayer") and ed.eval(f"{CB}._points[2][2] == HogUIPlayer")
    # the icon (18 px + 2) hangs off the left in line with the frame's edge; 4 px under the frame
    assert sorted(points(ed)) == [("TOPLEFT", "BOTTOMLEFT", 20, -4), ("TOPRIGHT", "BOTTOMRIGHT", 0, -4)]
    assert ed.eval(f"{CB}:GetHeight()") == 18
    assert ed.eval("HogHealsHUD.HUD.rows.swing._points[1][5]") == 0        # the swing bar takes the cast bar's row
    assert errors(ed) == []


def test_over_the_player_frame_and_without_the_icon(ed):  # noqa: F811
    ed.execute("HogHeals.db.profile.hud.castbar.icon = false")
    attach(ed, "above")
    assert ed.eval(f"{CB}.attached") == "above"
    assert sorted(points(ed)) == [("BOTTOMLEFT", "TOPLEFT", 0, 4), ("BOTTOMRIGHT", "TOPRIGHT", 0, 4)]


def test_back_in_the_hud_when_off_or_when_there_is_no_player_frame(ed):  # noqa: F811
    attach(ed, "below")
    attach(ed, "none")
    assert ed.eval(f"{CB}.attached") is None and ed.eval(f"{CB}._points[1][2] == HogHealsHUD.HUD.container")
    ed.execute("HogUIPlayer:Hide()")
    attach(ed, "below")                                                     # player frame switched off
    assert ed.eval(f"{CB}.attached") is None and ed.eval(f"{CB}._points[1][2] == HogHealsHUD.HUD.container")
    ed.execute("HogUIPlayer:Show(); HogHealsHUD.HUD.Refresh()")
    assert ed.eval(f"{CB}.attached") == "below"
    # attaching wins over "move it on its own"; letting go puts it back at its own spot
    ed.execute('local c = HogHeals.db.profile.hud.castbar c.detached, c.point, c.x, c.y = true, "CENTER", 50, 60; HogHealsHUD.HUD.Refresh()')
    assert ed.eval(f"{CB}.attached") == "below"
    attach(ed, "none")
    assert ed.eval(f"{CB}.detached") is True and ed.eval(f"{CB}._points[1][2] == UIParent")


def test_the_player_frame_built_after_the_hud_is_found_and_the_wait_is_bounded(ed):  # noqa: F811
    ed.execute("HH_PF = HogUIPlayer; HogUIPlayer = nil")
    attach(ed, "below")                                                     # login: the HUD lays out before Units
    assert ed.eval(f"{CB}.attached") is None
    ed.execute("HogUIPlayer = HH_PF; MockAdvance(0.6)")
    assert ed.eval(f"{CB}.attached") == "below"
    # a frame that never comes: a few looks, then it stops
    ed.execute("HogUIPlayer = nil; HogHealsHUD.HUD.Refresh(); for i = 1, 30 do MockAdvance(0.6) end")
    assert ed.eval("HogHealsHUD.HUD.attachTries") == ed.eval("HogHealsHUD.HUD.ATTACH_TRIES")
    assert ed.eval("HogHealsHUD.HUD.attachPending") is None
    ed.execute("HogUIPlayer = HH_PF")


def test_edit_mode_box_follows_the_frame_keeps_height_and_refuses_to_move(ed):  # noqa: F811
    attach(ed, "below")
    ed.execute('HogHeals:SlashCommand("unlock")')
    t = target(ed, "hud:castbar")
    assert ed.eval(f"{t}.title") == "Cast bar (on the player frame)" and ed.eval(f"{t}.mover == {CB}")
    ok = ed.eval(f"{{HogHeals.EditMode.Center({t}, 'h')}}")
    assert list(ok.values()) == [False, "it follows the player frame: move the player frame"]
    spec = f"HogHeals.EditMode.ResizeFor({t})"
    assert ed.eval(f"{spec}.w") is None and ed.eval(f"{spec}.h ~= nil")
    ed.execute('HogHeals:SlashCommand("lock")')
    assert errors(ed) == []


def test_the_option_sets_it(ed):  # noqa: F811
    ed.execute('HogHeals.OptionsTable().args.HUD.args.castbar.args.attach.set({}, "above")')
    assert ed.eval("HogHeals.db.profile.hud.castbar.attach") == "above" and ed.eval(f"{CB}.attached") == "above"
    assert ed.eval("HogHeals.OptionsTable().args.HUD.args.castbar.args.attach.get({})") == "above"
