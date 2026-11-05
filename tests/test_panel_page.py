"""Our settings window and setup guide on the torn page in the Parchment look (HogTronUI/Core/Panel.lua Panel.Paint).
Sean 2026-11-05: "everything to match this paper-like theme" - the guide that opened after a reload was still dark."""
import pytest

P = "HogHeals.Parchment"


def boot(lua, style=None):
    if style:
        lua.execute(f'HogTronUIDB = {{ profiles = {{ Default = {{ look = {{ style = "{style}" }} }} }} }}')
    lua.load_addon("HogTronUI")
    lua.player_login()
    lua.execute("wipe(HogHeals.errors); HogHeals.Panel.Open()")
    return lua


def rgb(lua, expr):
    return [round(v, 2) for v in list(lua.eval(expr).values())[:3]]


def light(lua, key):
    return [round(v, 2) for v in list(lua.eval(f"{P}.THEMES.light.{key}").values())[:3]]


def test_the_window_sits_on_the_torn_page_with_the_two_tone_wordmark_in_ink(lua):
    boot(lua)
    f = "HogHealsPanel"
    assert lua.eval("HogHeals.Panel.page") is True
    assert lua.eval(f"{f}.page.pageTop._texture").endswith("dialog_page_light")
    assert lua.eval(f"{f}.fill._alpha") == 0                                      # the page shows through
    assert rgb(lua, f"{f}.titleHog._color") == light(lua, "text")                  # HOG in ink ...
    assert rgb(lua, f"{f}.titleHeals._color") == light(lua, "pick")                # ... TRON UI in the page's accent
    assert lua.eval(f"{f}.titleHog._last.SetShadowOffset[1]") == 0
    lua.execute('HogHeals.db.profile.look.menus = "art"; HogHeals.Panel.ApplyArt()')
    assert lua.eval("HogHeals.Panel.artOn") is False                               # no slate on paper
    assert [e["msg"] for e in lua.eval("HogHeals.errors").values()] == []


def test_modern_keeps_the_ink_window(lua):
    boot(lua, "hogtron")
    f = "HogHealsPanel"
    assert lua.eval("HogHeals.Panel.page") is False and lua.eval(f"{f}.page") is None
    assert rgb(lua, f"{f}.titleHeals._color") == [0.13, 0.83, 0.88]
