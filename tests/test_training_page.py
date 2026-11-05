# The Training window as a parchment page (Core/Parchment.lua + Training.lua). Sean 2026-11-05: "design the menu to
# look like the dialogue menu for quests."
from test_training import tr, errors  # noqa: F401 (fixture)

T = "HogHealsTraining"
F = "HogTronUITraining"


def test_the_page_wears_the_dialogs_art_and_follows_its_theme(tr):
    tr.execute(f"{T}.Learn(); {T}.Toggle()")
    assert tr.eval(f"{F}:IsShown()") is True
    assert tr.eval(f"{F}.pageTop._texture").endswith("dialog_page_light") and tr.eval(f"{F}.pageBot._texture").endswith("dialog_page_light")
    assert tr.eval(f"{F}.ring._texture").endswith("dialog_ring") and tr.eval(f"{F}.rule._texture").endswith("dialog_rule")
    assert tr.eval(f"{F}.title._text") == "Training"
    assert tr.eval(f"{F}.sub._text").startswith("Learned at Grezz Ragefist")
    assert tr.eval(f"{F}._height") == tr.eval(f"{T}.pageHeight") and tr.eval(f"{T}.pageHeight") > 300
    # the theme follows the quest dialog's
    tr.execute(f'HogHeals.db.profile.quests = HogHeals.db.profile.quests or {{}}; HogHeals.db.profile.quests.dialog = {{ theme = "dark" }}; {T}.Refresh()')
    assert tr.eval("HogHeals.Parchment.ThemeKey()") == "dark" and tr.eval(f"{F}.pageMid._texture").endswith("dialog_page_dark")
    assert errors(tr) == []


def test_rows_are_inked_by_tone_and_headers_get_a_tag(tr):
    tr.execute(f"{T}.Learn(); {T}.Toggle()")
    rows = list(tr.eval(f"{T}.RowsFrom({T}.Plan(), {T}.db(), 'H', 20)").values())
    assert rows[0]["tone"] == "head" and rows[1]["tone"] == "now"
    th = tr.eval("HogHeals.Parchment.THEMES.light")
    r1 = f"{F}.rows[1]"
    assert tr.eval(f"{r1}.tag.shown") is True and tr.eval(f"{r1}.text._color[1]") == th["title"][1]
    r2 = f"{F}.rows[2]"
    assert tr.eval(f"{r2}.tag.shown") is False and tr.eval(f"{r2}.text._color[2]") == th["good"][2]
    blank = next(i for i, r in enumerate(rows, 1) if r["tone"] == "blank")
    assert tr.eval(f"{F}.rows[{blank}].text:IsShown()") is False
    assert tr.eval(f"{F}.rows[{len(rows) + 1}].text:IsShown()") is False
    assert errors(tr) == []


def test_before_the_first_visit_the_page_says_so_and_the_close_cap_hides_it(tr):
    tr.execute(f"{T}.Toggle()")
    assert tr.eval(f"{F}.sub._text").startswith("Your class trainer teaches this page")
    assert tr.eval(f"{F}.rows[1].text._text") == "Nothing learned yet."
    tr.execute("HogTronUITrainingClose:Click()")
    assert tr.eval(f"{F}:IsShown()") is False
    assert errors(tr) == []


def test_parchment_stands_alone_without_quests(lua):
    lua.load_addon("HogTronUI")
    lua.player_login()
    assert lua.eval("HogHeals.Parchment.ThemeKey()") == "light"
    lua.execute('T = UIParent:CreateTexture(); CLASS_ICON_TCOORDS = { DRUID = { 0.75, 1, 0, 0.25 } }')
    assert lua.eval('HogHeals.Parchment.ClassPortrait(T, "DRUID")') is True and lua.eval("T._texture").endswith("UI-Classes-Circles")
    assert lua.eval('HogHeals.Parchment.ClassPortrait(T, "NOPE")') is False
