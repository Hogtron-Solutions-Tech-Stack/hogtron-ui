# Forever beta diag, session 12: x56 "Range.lua:16: attempt to perform boolean test on local 'checked' (a secret
# boolean value)". UnitInRange answers with secret booleans: no `if`, no `and/or`. The client can still APPLY one:
# Region:SetAlphaFromBoolean(secret, alphaIfTrue, alphaIfFalse).

def setup(frames, in_range):
    frames.execute('MockSetSecrets(true); MockState.secretRange = true; HogHealsFrames.Compat.Init(); wipe(HogHeals.errors)')
    frames.execute(f'MockUnits.party1 = {{ name = "Ann", class = "PRIEST", health = 50, maxHealth = 100, guid = "Player-9", inRange = {in_range} }}')
    frames.execute('HH_r = HogHealsFrames.UnitButton.Create("HHRangeBtn" .. math.random(1e9), UIParent); HogHealsFrames.UnitButton.OnAttributeChanged(HH_r, "unit", "party1")')
    frames.execute('HogHealsFrames.Elements.range.Update(HH_r, "party1")')


def test_secret_range_is_applied_by_the_widget_without_any_boolean_test(frames):
    setup(frames, "false")
    assert [e["msg"] for e in frames.eval('HogHeals.errors').values()] == []
    assert frames.eval('HH_r._alpha') == frames.eval('HogHeals.db.profile.frames.appearance.outOfRangeAlpha')
    setup(frames, "true")
    assert frames.eval('HH_r._alpha') == 1


def test_a_later_health_update_does_not_undo_the_range_dimming(frames):
    setup(frames, "false")
    frames.execute('HogHealsFrames.Elements.health.Update(HH_r, "party1")')
    assert frames.eval('HH_r._alpha') < 1


def test_open_clients_keep_the_old_path(frames):
    frames.execute('MockSetSecrets(false); MockState.secretRange = false; HogHealsFrames.Compat.Init()')
    frames.execute('MockUnits.party1 = { name = "Ann", class = "PRIEST", health = 50, maxHealth = 100, guid = "Player-9", inRange = false }')
    frames.execute('HH_o = HogHealsFrames.UnitButton.Create("HHRangeOpen", UIParent); HogHealsFrames.UnitButton.OnAttributeChanged(HH_o, "unit", "party1"); HogHealsFrames.Elements.range.Update(HH_o, "party1")')
    assert frames.eval('HH_o._alphas.range') == frames.eval('HogHeals.db.profile.frames.appearance.outOfRangeAlpha')
