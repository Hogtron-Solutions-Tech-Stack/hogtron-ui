def L(frames, code):
    return frames.eval(code)


def test_party_vertical_positions(frames):
    pts = frames.eval('HogHealsFrames.Layout.Compute({width=120,height=30,spacing=2,growth="DOWN",groupsPerRow=1,groupsShown=1}, 5)')
    ys = [pts[i]["y"] for i in range(1, 6)]
    xs = [pts[i]["x"] for i in range(1, 6)]
    assert ys == [0, -32, -64, -96, -128]
    assert xs == [0, 0, 0, 0, 0]


def test_party_horizontal_positions(frames):
    pts = frames.eval('HogHealsFrames.Layout.Compute({width=120,height=30,spacing=2,growth="RIGHT",groupsPerRow=1,groupsShown=1}, 3)')
    assert [pts[i]["x"] for i in range(1, 4)] == [0, 122, 244]
    assert [pts[i]["y"] for i in range(1, 4)] == [0, 0, 0]


def test_raid_groups_wrap(frames):
    # 3 groups of 5, 2 groups per row, units grow DOWN, groups RIGHT then wrap under.
    pts = frames.eval('HogHealsFrames.Layout.Compute({width=80,height=20,spacing=2,growth="DOWN",groupsPerRow=2,groupsShown=3,groupGrowth="RIGHT",groupSpacing=6}, 15)')
    g1 = (pts[1]["x"], pts[1]["y"])
    g2 = (pts[6]["x"], pts[6]["y"])
    g3 = (pts[11]["x"], pts[11]["y"])
    assert g1 == (0, 0)
    assert g2 == (86, 0)              # 80 + 6 group spacing
    assert g3 == (0, -(5 * 22 - 2 + 6))  # under group 1: bottom of 5th unit (-108) minus group spacing


def test_header_attributes_down(frames):
    a = frames.eval('HogHealsFrames.Layout.HeaderAttributes({width=120,height=30,spacing=2,growth="DOWN",groupsPerRow=1,groupsShown=1})')
    assert a["point"] == "TOP"
    assert a["xOffset"] == 0 and a["yOffset"] == -2
    assert a["unitsPerColumn"] == 5
    assert a["maxColumns"] == 1
    assert a["columnAnchorPoint"] == "LEFT"


def test_header_attributes_right(frames):
    a = frames.eval('HogHealsFrames.Layout.HeaderAttributes({width=120,height=30,spacing=2,growth="RIGHT",groupsPerRow=1,groupsShown=1})')
    assert a["point"] == "LEFT"
    assert a["xOffset"] == 2 and a["yOffset"] == 0
    assert a["columnAnchorPoint"] == "TOP"
