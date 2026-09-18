# "How do I move the frames?" -> /hh unlock showed an anchor that had no texture, no label, no drag scripts and
# never saved a position. It could not be seen, grabbed or remembered.

def test_unlock_shows_a_visible_draggable_handle(frames):
    frames.execute('HogHeals:SetLocked(false)')
    a = 'HogHealsAnchor'
    assert frames.eval(f'{a}:IsShown()') is True
    assert frames.eval(f'{a}.bg ~= nil and {a}.label ~= nil')
    assert "drag" in frames.eval(f'{a}.label._text').lower()
    assert frames.eval(f'{a}._scripts.OnDragStart ~= nil and {a}._scripts.OnDragStop ~= nil')
    frames.execute('HogHeals:SetLocked(true)')
    assert frames.eval(f'{a}:IsShown()') is False


def test_drag_saves_position_for_every_group_size_and_survives_relayout(frames):
    frames.execute('HogHeals:SetLocked(false)')
    frames.execute('UIParent._cx, UIParent._cy = 960, 540; HogHealsAnchor._cx, HogHealsAnchor._cy = 660, 700')
    frames.execute('HogHealsAnchor._scripts.OnDragStop(HogHealsAnchor)')
    for bucket in ("solo", "party", "raid10", "raid20", "raid40"):
        a = f'HogHeals.db.profile.frames.layouts.{bucket}.anchor'
        assert frames.eval(f'{a}.point') == "CENTER" and frames.eval(f'{a}.x') == -300 and frames.eval(f'{a}.y') == 160, bucket
    frames.execute('HogHealsFrames.Headers.Apply("party")')
    pt = frames.eval('HogHealsAnchor._points[1]')
    assert pt is not None


def test_drag_is_refused_in_combat(frames):
    frames.execute('HogHeals:SetLocked(false); MockState.inCombat = true; HogHealsAnchor._moving = nil')
    frames.execute('HogHealsAnchor._scripts.OnDragStart(HogHealsAnchor)')
    assert frames.eval('HogHealsAnchor._moving') is None


def test_solo_slash_toggles_and_reports(frames):
    frames.execute('MockLog.chat = {}; HogHeals:SlashCommand("solo")')
    assert frames.eval('HogHeals.db.profile.frames.layouts.solo.showSolo') is False
    assert frames.eval('HogHealsPartyHeader:GetAttribute("showSolo")') is False
    frames.execute('HogHeals:SlashCommand("solo")')
    assert frames.eval('HogHeals.db.profile.frames.layouts.solo.showSolo') is True
    assert any("solo" in l.lower() for l in frames.eval('MockLog.chat').values())
