# Blizzard's tips on its own menu buttons ("You have unopened items in your collection") float over the bags once the
# glyph strip stands in for those buttons (Sean 2026-11-04 screenshot). Hidden by default while the strip is on.
import pytest

from test_skin import CLIENT

ALERTS = '''
HelpTip = { shown = {}, hidden = {} }
function HelpTip:Show(parent, info) self.shown[#self.shown + 1] = { parent, info and info.text } return true end
function HelpTip:HideAll(parent) self.hidden[#self.hidden + 1] = parent end
CollectionsMicroButton = CreateFrame("Button", "CollectionsMicroButton", UIParent)
Elsewhere = CreateFrame("Frame", "Elsewhere", UIParent)
function MainMenuMicroButton_ShowAlert(btn, text) ALERT = { btn, text } end
function MainMenuMicroButton_HideAlert(btn) HIDDEN = btn end
CollectionsMicroButtonAlert = CreateFrame("Frame", "CollectionsMicroButtonAlert", UIParent)
'''


@pytest.fixture
def skin(lua):
    lua.execute(CLIENT + ALERTS)
    lua.load_addon("HogTronUI")
    lua.load_addon("HogTron_Skin")
    lua.player_login()
    lua.execute("wipe(HogHeals.errors)")
    return lua


def errors(lua):
    return [e["msg"] for e in lua.eval("HogHeals.errors").values()]


def test_tips_on_blizzards_menu_buttons_are_hidden_the_moment_they_show(skin):
    assert skin.eval("HogHeals.db.profile.skin.micro.alerts") is False
    assert "HelpTip.Show" in list(skin.eval("HogHealsSkin.Micro.alertsHooked").values())
    skin.execute('HelpTip:Show(CollectionsMicroButton, { text = "You have unopened items in your collection." })')
    assert skin.eval("HelpTip.hidden[1] == CollectionsMicroButton") is True
    skin.execute('HelpTip:Show(Elsewhere, { text = "a tip on something else" })')
    assert skin.eval("#HelpTip.hidden") == 1                                   # only the menu buttons' tips
    skin.execute('MainMenuMicroButton_ShowAlert(CollectionsMicroButton, "x")')
    assert skin.eval("HIDDEN == CollectionsMicroButton") is True
    assert skin.eval("HogHealsSkin.Micro.alertsMuted") >= 2
    assert errors(skin) == []


def test_an_alert_already_up_at_login_goes_too(skin):
    assert skin.eval("CollectionsMicroButtonAlert:IsShown()") is False        # hidden by the login sweep (mock frames start shown)


def test_the_switch_lets_them_through(skin):
    skin.execute("HogHeals.db.profile.skin.micro.alerts = true")
    skin.execute('HelpTip:Show(CollectionsMicroButton, { text = "tip" }); MainMenuMicroButton_ShowAlert(CollectionsMicroButton, "x"); HIDDEN = nil')
    assert skin.eval("#HelpTip.hidden") == 0 and skin.eval("HIDDEN") is None
    skin.execute("HogHeals.db.profile.skin.micro.strip = false; HogHeals.db.profile.skin.micro.alerts = false")
    skin.execute('HelpTip:Show(CollectionsMicroButton, { text = "tip" })')
    assert skin.eval("#HelpTip.hidden") == 0                                   # Blizzard's own buttons on screen: their tips stay
    assert errors(skin) == []


def test_the_option_sits_in_the_menu_bar_group_and_reads_the_default():
    from pathlib import Path
    import re
    opts = (Path(__file__).resolve().parents[1] / "HogTron_Skin" / "Options.lua").read_text(encoding="utf-8")
    assert re.search(r'strip = toggle\(sub\("micro"\), "strip".*?\n\s*alerts = toggle\(sub\("micro"\), "alerts"', opts)
