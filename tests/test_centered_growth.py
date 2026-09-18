# Tester: "I want to be centred when I'm the only one, and as I add people it offsets" -> growth = "CENTER":
# the row is centred on the anchor and grows outward both ways as the group grows.

def party_point(frames):
    return list(frames.eval('{ HogHealsPartyHeader:GetPoint(1) }').values())


def test_center_growth_puts_a_solo_player_on_the_anchor_centre(frames):
    frames.execute('local l = HogHeals.db.profile.frames.layouts.solo; l.growth = "CENTER"; l.width = 90; l.spacing = 2; HogHealsFrames.Headers.Apply("solo")')
    p = party_point(frames)
    assert p[0] == "LEFT" and p[2] == "CENTER" and p[3] == -45 and p[4] == 0
    assert frames.eval('HogHealsPartyHeader:GetAttribute("point")') == "LEFT"


def test_center_growth_widens_symmetrically_as_people_join(frames):
    frames.execute('local l = HogHeals.db.profile.frames.layouts.party; l.growth = "CENTER"; l.width = 90; l.spacing = 2')
    frames.execute('MockSetGroup(3, false); MockFire("GROUP_ROSTER_UPDATE")')
    assert frames.eval('HogHealsFrames.module.bucket') == "party"
    assert party_point(frames)[3] == -(3 * 90 + 2 * 2) / 2
    frames.execute('MockSetGroup(5, false); MockFire("GROUP_ROSTER_UPDATE")')     # same bucket, more people: re-centred
    assert party_point(frames)[3] == -(5 * 90 + 4 * 2) / 2


def test_other_growths_unchanged(frames):
    frames.execute('HogHeals.db.profile.frames.layouts.solo.growth = "DOWN"; HogHealsFrames.Headers.Apply("solo")')
    p = party_point(frames)
    assert p[0] == "TOPLEFT" and p[2] == "TOPLEFT"


def test_option_offers_centered(frames):
    frames.execute('HH_v = nil; local function walk(t) for k, o in pairs(t.args or {}) do if k == "growth" and o.values then HH_v = o.values end if o.type == "group" then walk(o) end end end walk(HogHeals.OptionsTable())')
    assert "CENTER" in dict(frames.eval('HH_v'))


def test_layout_math_treats_center_like_right(frames):
    pts = frames.eval('HogHealsFrames.Layout.Compute({width=90,height=60,spacing=2,growth="CENTER",groupsPerRow=1,groupsShown=1}, 3)')
    assert [p["x"] for p in pts.values()] == [0, 92, 184]
