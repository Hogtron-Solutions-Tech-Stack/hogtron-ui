# In game (Forever beta): tester set "Units grow: LEFT" while solo, joined a party (grows DOWN) and the five frames
# formed a diagonal staircase. SecureGroupHeader never clears a child's old points, so each button kept
# RIGHT->prev.LEFT from the old direction AND got TOP->prev.BOTTOM from the new one.

def points(frames, n):
    return [list(p.values()) for p in frames.eval(f'HogHealsPartyHeaderUnitButton{n}._points').values()]


def test_changing_growth_direction_leaves_one_anchor_per_button(frames):
    frames.execute('HogHeals.db.profile.frames.layouts.solo.growth = "LEFT"; HogHealsFrames.Headers.Apply("solo")')
    frames.execute('MockSetGroup(5, false); HogHealsFrames.Headers.Apply("party")')
    for n in range(2, 6):
        pts = points(frames, n)
        assert len(pts) == 1, (n, pts)
        assert pts[0][0] == "TOP" and pts[0][2] == "BOTTOM"
    first = [p[0] for p in points(frames, 1)]
    assert "RIGHT" not in first and "TOP" in first


def test_same_direction_reapply_does_not_pile_up_points(frames):
    frames.execute('MockSetGroup(5, false)')
    for _ in range(4):
        frames.execute('HogHealsFrames.Headers.Apply("party")')
    assert len(points(frames, 3)) == 1
