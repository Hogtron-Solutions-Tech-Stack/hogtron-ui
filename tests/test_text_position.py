# Tester: "change where the text is within the frame: centre it, top, bottom, whatever."

def pt(frames, fs):
    return list(frames.eval(f'{{ HH_t.{fs}:GetPoint(1) }}').values())


def test_defaults_name_top_centre_health_bottom_centre(frames):
    frames.execute('HH_t = HogHealsFrames.UnitButton.Create("HHTextBtn", UIParent)')
    assert pt(frames, "name")[0] == "TOP" and pt(frames, "healthText")[0] == "BOTTOM"


def test_every_combination_places_the_text(frames):
    frames.execute('HH_t = HogHealsFrames.UnitButton.Create("HHTextBtn2", UIParent)')
    ap = 'HogHeals.db.profile.frames.appearance'
    expect = { ("TOP", "LEFT"): "TOPLEFT", ("CENTER", "CENTER"): "CENTER", ("BOTTOM", "RIGHT"): "BOTTOMRIGHT",
               ("CENTER", "LEFT"): "LEFT", ("TOP", "CENTER"): "TOP", ("BOTTOM", "CENTER"): "BOTTOM" }
    for (v, h), point in expect.items():
        frames.execute(f'{ap}.namePosition = "{v}"; {ap}.nameAlign = "{h}"; HogHealsFrames.UnitButton.ApplyAppearance(HH_t)')
        p = pt(frames, "name")
        assert p[0] == point and p[2] == point, (v, h, p)
        assert frames.eval('#HH_t.name._points') == 1          # re-anchored, not piled up


def test_options_expose_the_four_selects(frames):
    args = dict(frames.eval('HogHeals.OptionsTable().args.Frames.args.appearance.args').items())
    for k in ("namePosition", "nameAlign", "healthTextPosition", "healthTextAlign"):
        assert args[k]["type"] == "select", k
