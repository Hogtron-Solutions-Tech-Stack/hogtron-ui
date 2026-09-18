# Hover-binds are set in OnEnter with SetOverrideBindingClick, a PROTECTED call: fine out of combat, blocked in
# combat (popup with a Disable button). The secure fix every other addon uses (snippet-wrapped OnEnter) cannot run
# on the Forever beta: it cannot compile secure snippets. Snippet-free alternative = "combat-safe" mode: bind each
# key ONCE out of combat to a hidden secure button that casts with a [@mouseover] fallback chain.

def clicks(frames):
    return [dict(c) for c in frames.eval('MockBindings.clicks').values()]


def test_hover_mode_never_calls_a_protected_binding_function_in_combat(frames):
    frames.execute('HogHeals.db.profile.frames.bindingMode = "hover"; MockState.inCombat = true; wipe(MockBindings.clicks); wipe(HogHeals.errors)')
    frames.execute('HH_b = HogHealsFrames.UnitButton.Create("HHCsBtn", UIParent); HogHealsFrames.UnitButton.OnEnter(HH_b)')
    assert clicks(frames) == []
    assert frames.eval('#HogHeals.errors') == 0
    frames.execute('MockState.inCombat = false; HogHealsFrames.UnitButton.OnEnter(HH_b)')
    assert len(clicks(frames)) > 0


def test_global_mode_binds_every_keyboard_key_once_to_a_secure_mouseover_button(frames):
    frames.execute('wipe(MockBindings.clicks); HogHeals.db.profile.frames.bindingMode = "global"; HogHealsFrames.ClickCast.ApplyGlobal()')
    c = clicks(frames)
    keys = sorted(x["key"] for x in c)
    assert "1" in keys and "Q" in keys and "SHIFT-1" in keys
    first = next(x for x in c if x["key"] == "1")
    assert first["name"].startswith("HogHealsKey")
    btn = first["name"]
    assert frames.eval(f'{btn}:GetAttribute("type")') == "macro"
    assert frames.eval(f'{btn}:GetAttribute("macrotext")').startswith("/cast [@mouseover,help,nodead]")
    assert frames.eval(f'{btn}._template') == "SecureActionButtonTemplate"
    # hovering a frame no longer touches bindings
    frames.execute('wipe(MockBindings.clicks); HH_g = HogHealsFrames.UnitButton.Create("HHCsBtn2", UIParent); HogHealsFrames.UnitButton.OnEnter(HH_g)')
    assert clicks(frames) == []


def test_global_mode_skips_keys_the_player_already_uses_and_says_so(frames):
    frames.execute('MockBindings.actions = { ["1"] = "ACTIONBUTTON1", ["2"] = "ACTIONBUTTON2" }; MockLog.chat = {}; wipe(MockBindings.clicks)')
    frames.execute('HogHeals.db.profile.frames.bindingMode = "global"; HogHealsFrames.ClickCast.ApplyGlobal()')
    keys = sorted(x["key"] for x in clicks(frames))
    assert "1" not in keys and "2" not in keys and "Q" in keys
    assert any("1" in l and "2" in l for l in frames.eval('MockLog.chat').values())
    frames.execute('HogHeals.db.profile.frames.bindingForce = true; wipe(MockBindings.clicks); HogHealsFrames.ClickCast.ApplyGlobal()')
    assert "1" in [x["key"] for x in clicks(frames)]
    frames.execute('MockBindings.actions = nil')


def test_global_mode_defers_to_after_combat(frames):
    frames.execute('HogHeals.db.profile.frames.bindingMode = "global"; MockState.inCombat = true; wipe(MockBindings.clicks); HogHealsFrames.ClickCast.ApplyGlobal()')
    assert clicks(frames) == []
    frames.execute('MockState.inCombat = false; MockFire("PLAYER_REGEN_ENABLED")')
    assert len(clicks(frames)) > 0


def test_switching_back_to_hover_clears_the_global_binds(frames):
    frames.execute('HogHeals.db.profile.frames.bindingMode = "global"; HogHealsFrames.ClickCast.ApplyGlobal(); wipe(MockBindings.cleared)')
    frames.execute('HogHeals.db.profile.frames.bindingMode = "hover"; HogHealsFrames.ClickCast.ApplyGlobal()')
    assert frames.eval('#MockBindings.cleared') >= 1
