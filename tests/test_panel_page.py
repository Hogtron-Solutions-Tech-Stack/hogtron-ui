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


SAMPLE = '''HogHeals.Panel.Open(function() return { type = "group", name = "x", args = { g = { type = "group", name = "G", order = 1, args = {
  about = { type = "description", order = 1, name = "Hi there. This is the body text." },
  who = { type = "input", order = 2, name = "Name", get = function() return "Hog" end, set = function() end },
} } } } end)'''


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def test_every_part_of_the_window_reads_on_paper(lua):
    """Sean 2026-11-05 in game, the guide on paper: "the coloring here is all messed up" - a navy sidebar under ink
    labels, light grey body text on the page, a flat card strip for a title bar."""
    boot(lua)
    lua.execute(SAMPLE)
    f = "HogHealsPanel"
    side = rgb(lua, f"{f}.side.fill._color")
    assert lum(side) > 0.6 and lua.eval(f"{f}.side.fill._color[4]") < 0.5              # a faint shade of the page, not navy
    assert lua.eval(f"{f}.side.rule") is not None                                     # a ruled margin
    assert lua.eval(f"{f}.bar.fill._color[4]") == 0                                      # the title sits on the page
    body = rgb(lua, 'HogHeals.Panel.controls["g.about"].text._color')
    assert body == light(lua, "text") and lum(body) < 0.3                              # ink, not light grey
    well = rgb(lua, 'HogHeals.Panel.controls["g.who"].well.fill._color')
    assert lum(well) > 0.7                                                            # a paper well under ink text
    picked = rgb(lua, 'HogHeals.Panel.nav[1].label._color')                         # the picked page: inked amber
    assert picked[0] > picked[2] and lum(picked) < 0.36
    assert lum(rgb(lua, f"{f}.side.fill._color")) - lum(picked) > 0.35
    assert [e["msg"] for e in lua.eval("HogHeals.errors").values()] == []


def test_modern_keeps_the_dark_sidebar_and_light_body_text(lua):
    boot(lua, "hogtron")
    lua.execute(SAMPLE)
    f = "HogHealsPanel"
    assert rgb(lua, f"{f}.side.fill._color") == [0.09, 0.09, 0.12] or rgb(lua, f"{f}.side.fill._color") == [0.09, 0.09, 0.11]
    assert lua.eval(f"{f}.side.fill._color[4]") == 1 and lua.eval(f"{f}.side.rule") is None
    assert rgb(lua, 'HogHeals.Panel.controls["g.about"].text._color') == [0.78, 0.75, 0.7]
    assert rgb(lua, 'HogHeals.Panel.controls["g.who"].well.fill._color') == [0.05, 0.05, 0.07] or \
        rgb(lua, 'HogHeals.Panel.controls["g.who"].well.fill._color') == [0.05, 0.05, 0.06]
