# 2026-10-05 in game: name CENTER + deficit CENTER at 18 pt drew "Hog-55icen". Same spot -> split around it.
def test_same_spot_splits_name_up_and_number_down(frames):
    frames.execute("""
      local ap = HogHeals.db.profile.frames.appearance
      ap.namePosition, ap.healthTextPosition, ap.fontSize = "CENTER", "CENTER", 18
      B = HogHealsFrames.UnitButton.Create("HHSplit", UIParent)
      HogHealsFrames.UnitButton.ApplyAppearance(B)
    """)
    name, text = frames.eval("B.name._points[1]"), frames.eval("B.healthText._points[1]")
    assert name[1] == "CENTER" and text[1] == "CENTER"
    assert name[5] == 11 and text[5] == -11                                   # ceil(18 * 0.6) each way
    # both at the top: the name keeps the edge, the number drops a line under it
    frames.execute('local ap = HogHeals.db.profile.frames.appearance; ap.namePosition, ap.healthTextPosition = "TOP", "TOP"; HogHealsFrames.UnitButton.ApplyAppearance(B)')
    assert frames.eval("B.name._points[1][5]") == -3 and frames.eval("B.healthText._points[1][5]") == -4 - 22
    # both at the bottom: the number keeps the edge, the name rises
    frames.execute('local ap = HogHeals.db.profile.frames.appearance; ap.namePosition, ap.healthTextPosition = "BOTTOM", "BOTTOM"; HogHealsFrames.UnitButton.ApplyAppearance(B)')
    assert frames.eval("B.healthText._points[1][5]") == 4 and frames.eval("B.name._points[1][5]") == 3 + 22
    # different spots: untouched (the default TOP / BOTTOM)
    frames.execute('local ap = HogHeals.db.profile.frames.appearance; ap.namePosition, ap.healthTextPosition = "TOP", "BOTTOM"; HogHealsFrames.UnitButton.ApplyAppearance(B)')
    assert frames.eval("B.name._points[1][5]") == -3 and frames.eval("B.healthText._points[1][5]") == 4
    # same row, different sides: no split either
    frames.execute('local ap = HogHeals.db.profile.frames.appearance; ap.namePosition, ap.healthTextPosition, ap.nameAlign, ap.healthTextAlign = "CENTER", "CENTER", "LEFT", "RIGHT"; HogHealsFrames.UnitButton.ApplyAppearance(B)')
    assert frames.eval("B.name._points[1][5]") == 0 and frames.eval("B.healthText._points[1][5]") == 0
