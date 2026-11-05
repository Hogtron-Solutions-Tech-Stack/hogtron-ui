# Info bar: each slot as wide as its reading, the bar as wide as all of them (HogTron_Skin/InfoBar.lua Bar.Fit).
# Sean 2026-11-04 (screenshot, "14 / 3..." and "lvl 5 in..." cut off): "should auto be defaulted to see everything".
from test_skin import skin, errors  # noqa: F401 (fixture)

BAR = "HogHealsSkin.InfoBar"


def shown(lua):
    out = []
    for i in range(1, 12):
        if lua.eval(f"{BAR}.slots[{i}] ~= nil and {BAR}.slots[{i}]:IsShown()"):
            out.append(i)
    return out


def test_slots_fit_their_readings_and_the_bar_grows(skin):
    assert skin.eval("HogHeals.db.profile.skin.infoBar.fit") is True
    skin.execute(f"{BAR}.Update()")
    total = 0
    for i in shown(skin):
        s = f"{BAR}.slots[{i}]"
        text = skin.eval(f"{s}.text._text") or ""
        w = skin.eval(f"{s}._width")
        need = len(text) * 6 + (skin.eval(f"{s}.icon:GetWidth()") + 4 if skin.eval(f"{s}.icon:IsShown()") else 0) + 14
        assert w >= need and w % 10 == 0 and w >= 40, (i, text, w, need)
        assert skin.eval(f"{s}._points[1][4]") == total                       # laid out left to right, no gaps
        total += w
    assert skin.eval("HogUIInfoBar._width") == total and total > 0
    # the text box inside the slot is the slot minus the emblem: nothing left to cut off
    s = f"{BAR}.slots[1]"
    assert skin.eval(f"{s}.text._width") >= len(skin.eval(f"{s}.text._text") or "") * 6
    assert errors(skin) == []


def test_fit_off_splits_the_width_evenly_as_before(skin):
    skin.execute(f"HogHeals.db.profile.skin.infoBar.fit = false; {BAR}.Refresh()")
    n = len(shown(skin))
    for i in shown(skin):
        assert skin.eval(f"{BAR}.slots[{i}]._width") == 640 / n
    assert skin.eval("HogUIInfoBar._width") == 640
    assert errors(skin) == []


def test_a_secret_reading_keeps_the_width_it_had(skin):
    skin.execute(f"{BAR}.Update()")
    before = skin.eval(f"{BAR}.slots[1]._width")
    skin.execute(f"{BAR}.slots[1].text._secretText = true; {BAR}.slots[1].text:SetText('a much longer reading than before'); {BAR}.Update()")
    assert skin.eval(f"{BAR}.slots[1]._width") == before
    assert errors(skin) == []
