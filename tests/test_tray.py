# The HogTron UI entries in the addon-button drawer (HogHeals/Core/Tray.lua + Buttons.lua): one glyph per module,
# click = that module's settings alone in the compact window. Sean in game 2026-10-08: "our menus are getting a
# little overwhelming ... broken down into separate things and put into this tray".
import pytest

from test_quests import boot, errors
from test_minimap_buttons import MINIMAP

T = "HogHeals.Tray"
D = "HogHealsQuests.Buttons"


@pytest.fixture
def tray(lua):
    boot(lua, MINIMAP)
    lua.execute(f"{D}.Toggle(true)")
    return lua


def keys(lua):
    return [e["key"] for e in lua.eval(f"{T}.Available()").values()]


def test_available_follows_the_loaded_modules_and_their_tabs(tray):
    k = keys(tray)
    assert "quests" in k and "map" in k and "lock" in k and "all" in k          # Quests is loaded, its tabs exist
    assert "bars" not in k and "hud" not in k and "bind" not in k               # Bars / HUD are not loaded here
    tray.execute("HogHeals.modules.Quests = nil")
    k2 = keys(tray)
    assert "quests" not in k2 and "map" not in k2 and "lock" in k2


def test_with_more_modules_loaded_more_entries_appear(lua):
    lua.execute(MINIMAP)
    for a in ("HogHeals", "HogHeals_Frames", "HogHeals_HUD", "HogHeals_Quests"):
        lua.load_addon(a)
    lua.player_login()
    k = keys(lua)
    assert "hud" in k and "frames" in k and "hover" in k
    assert k.index("hud") < k.index("quests") < k.index("lock")                 # drawer order = list order


def test_own_cells_come_first_in_the_grid_then_the_collected_icons(tray):
    n_own = tray.eval(f"{D}.ownCount")
    assert n_own == len(keys(tray)) and n_own >= 4
    # first cell: our first entry, in the corner; the collected icons start on the row after ours
    first = tray.eval(f"{D}.own[1]")
    assert tray.eval(f"{D}.own[1].entry.key") == keys(tray)[0] and tray.eval(f"{D}.own[1]:IsShown()") is True
    assert tray.eval(f"{D}.own[1].letter:GetText()") == tray.eval(f"{T}.Get('{keys(tray)[0]}').letter")
    cols = tray.eval("HogHeals.db.profile.quests.buttons.columns")
    own_rows = -(-n_own // cols)
    size, pad = tray.eval("HogHeals.db.profile.quests.buttons.size"), 4
    y_first_icon = abs(list(tray.eval(f"{{ {D}.cells[1]:GetPoint() }}").values())[4])
    assert y_first_icon == pytest.approx(pad + own_rows * (size + pad), abs=1)
    # drawer tall enough for both groups
    shown = tray.eval(f"{D}.shown")
    assert tray.eval("HogHealsMinimapDrawer:GetHeight()") == pytest.approx(pad + (own_rows + -(-shown // cols)) * (size + pad), abs=1)
    assert errors(tray) == []


def test_clicking_an_entry_opens_only_that_module_compact_and_closes_the_drawer(tray):
    tray.execute(f"local c for _, x in ipairs({D}.own) do if x.entry and x.entry.key == 'map' then c = x end end; HH_c = c")
    assert tray.eval("HH_c ~= nil")
    tray.execute("HH_c:GetScript('OnClick')(HH_c)")
    P = "HogHeals.Panel"
    assert tray.eval(f"{P}.frame:IsShown()") is True and tray.eval(f"{P}.compact") is True
    assert tray.eval(f"{P}.selected") == "Quests" and tray.eval(f"{P}.selectedTab") == "minimap"
    assert tray.eval(f"{P}.frame.version:GetText()") == "Map & minimap"
    assert len(tray.eval(f"{P}.nav")) == 1                                       # one module in the sidebar list
    assert tray.eval("HogHealsMinimapDrawer:IsShown()") is False                 # auto-close
    assert tray.eval(f"{T}.seen.map") == 1
    assert errors(tray) == []


def test_actions_lock_bind_and_all(tray):
    tray.execute(f"{T}.Open('lock')")
    assert tray.eval("HogHeals.db.profile.locked") is False
    assert tray.eval(f"{T}.Title({T}.Get('lock'))") == "Lock"
    tray.execute(f"{T}.Open('lock')")
    assert tray.eval("HogHeals.db.profile.locked") is True
    tray.execute(f"{T}.Open('all')")
    assert tray.eval("HogHeals.Panel.compact") is False and tray.eval("HogHeals.Panel.frame:IsShown()") is True
    assert tray.eval(f"{T}.Open('nope')") is False


def test_option_off_hides_our_cells_and_the_tooltip_says_what_is_there(tray):
    tray.execute(f"HogHeals.db.profile.quests.buttons.hogui = false; {D}.Layout()")
    assert tray.eval(f"{D}.own[1]:IsShown()") is False
    y_first_icon = abs(list(tray.eval(f"{{ {D}.cells[1]:GetPoint() }}").values())[4])
    assert y_first_icon == 4                                                    # icons back on the first row
    tray.execute(f"HogHeals.db.profile.quests.buttons.hogui = true; {D}.Layout()")
    tray.execute('GameTooltip:ClearLines(); HogHealsMinimapButtons:GetScript("OnEnter")(HogHealsMinimapButtons)')
    lines = " ".join(tray.eval("GameTooltip._lines").values())
    assert "HogTron UI" in lines and "settings, lock, key binds" in lines
    assert "tray:" in " ".join(tray.eval(f"{T}.Lines()").values())
    assert errors(tray) == []



def test_entries_draw_their_glyph_with_the_letter_as_fallback(tray):
    import pathlib
    media = pathlib.Path(__file__).resolve().parents[1] / "HogHeals" / "Media"
    for e in tray.eval(f"{T}.ENTRIES").values():
        assert e["icon"], e["key"]
        assert (media / (e["icon"] + ".tga")).exists(), e["icon"]                  # every glyph is shipped
    c = f"{D}.own[1]"
    assert tray.eval(f"{c}.icon:IsShown()") is True and tray.eval(f"{c}.letter:IsShown()") is False
    assert tray.eval(f"{c}.glyph") == tray.eval(f"{c}.entry.icon")
    assert tray.eval(f"{c}.icon._texture").endswith(tray.eval(f"{c}.entry.icon"))
    # a client that refuses the file: the letter stands in
    tray.execute(f"{c}.icon.SetTexture = function() return false end; {D}.OwnCells()")
    assert tray.eval(f"{c}.letter:IsShown()") is True and tray.eval(f"{c}.icon:IsShown()") is False
