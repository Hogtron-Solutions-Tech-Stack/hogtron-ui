"""The UI's three looks (HogTronUI/Core/Look.lua look.style): Parchment (default), Modern, Blizzard. Sean 2026-11-05:
"we can do a modern look or a like wow look and then I also have the wow defaults. Those are my three things I'm
envisioning ... everything needs to match that themeing." Windows follow it (HogTron_Skin/Panels.lua skin.panels.look
= "auto"). No slash opens Blizzard's windows from our Lua (the spellbook ran tainted after one did)."""
import pytest

from test_skin_windows import WINDOW

L = "HogHeals.Look"


def boot(lua, style=None, extra=""):
    if style:
        lua.execute(f'HogTronUIDB = {{ profiles = {{ Default = {{ look = {{ style = "{style}" }} }} }} }}')
    lua.execute(WINDOW + extra)
    lua.load_addon("HogTronUI")
    lua.load_addon("HogTron_Skin")
    lua.player_login()
    lua.execute("wipe(HogHeals.errors)")
    return lua


def errors(lua):
    return [e["msg"] for e in lua.eval("HogHeals.errors").values()]


def test_parchment_is_the_default_with_the_games_font(lua):
    boot(lua)
    assert lua.eval("HogHeals.db.profile.look.style") == "parchment"
    assert lua.eval(f"{L}.Theme()") == "parchment" and lua.eval(f"{L}.Parchment()") is True and lua.eval(f"{L}.Classic()") is False
    assert lua.eval(f"{L}.Font()").upper().endswith("FRIZQT__.TTF")                     # the page's font
    assert lua.eval(f"{L}.Font('HogTron Manrope')").endswith("Manrope-SemiBold.ttf")     # a font picked by name is honoured
    assert lua.eval("HogTronFontSmall._last.SetFont[1]").upper().endswith("FRIZQT__.TTF")
    assert lua.eval(f"{L}.applied.style") == "parchment" and lua.eval(f"{L}.applied.font") == "Friz Quadrata"
    lua.execute("FriendsFrame:SetSize(500, 400); ShowUIPanel(FriendsFrame)")
    assert lua.eval("FriendsFrame.hhPanel.pageTop ~= nil")                                # windows on the page
    assert errors(lua) == []


@pytest.mark.parametrize("style,theme,page", [("hogtron", "modern", False), ("parchment", "parchment", True)])
def test_windows_follow_the_look(lua, style, theme, page):
    boot(lua, style)
    assert lua.eval(f"{L}.Theme()") == theme
    lua.execute("FriendsFrame:SetSize(500, 400); ShowUIPanel(FriendsFrame)")
    assert (lua.eval("FriendsFrame.hhPanel.pageTop") is not None) is page
    assert (lua.eval("FriendsFrame.hhPanel.bg") is not None) is (not page)               # Modern: the ink panel
    assert errors(lua) == []


def test_a_forced_window_look_wins_over_the_ui_look(lua):
    boot(lua, "hogtron")
    lua.execute('HogHeals.db.profile.skin.panels.look = "parchment"; FriendsFrame:SetSize(500, 400); ShowUIPanel(FriendsFrame)')
    assert lua.eval("FriendsFrame.hhPanel.pageTop ~= nil")
    assert errors(lua) == []


def test_blizzard_look_leaves_windows_alone_and_uses_the_games_icons(lua):
    boot(lua, "classic")
    assert lua.eval(f"{L}.Theme()") == "blizzard" and lua.eval(f"{L}.IconStyle()") == "blizzard"
    lua.execute("FriendsFrame:SetSize(500, 400); ShowUIPanel(FriendsFrame)")
    assert lua.eval("FriendsFrame.hhPanel") is None and lua.eval("FriendsFrame.NineSlice:IsShown()") is True
    assert errors(lua) == []


def test_the_look_slash_takes_the_three_names(lua):
    boot(lua)
    for word, style in (("modern", "hogtron"), ("blizzard", "classic"), ("parchment", "parchment")):
        lua.execute(f"HogHeals:SlashCommand('look {word}')")
        assert lua.eval("HogHeals.db.profile.look.style") == style
    assert any("Parchment (the WoW page)" in m for m in lua.eval("MockLog.chat").values())


# Blizzard's window openers. Called from our Lua they run the window's code tainted: 2026-11-05 a spell clicked in the
# spellbook after /hh open spellbook was ADDON_ACTION_FORBIDDEN (CastSpellBookItem). The spellbook and talents may
# only ever be opened by the player (key, or the menu bar's secure click).
NEVER_FROM_OUR_LUA = ("PlayerSpellsUtil", "ToggleSpellBook", "ToggleTalentFrame", "ToggleClassTalentOrSpecFrame", "SpellBookFrame_Update")


def test_no_slash_opens_blizzards_windows_and_no_code_calls_the_spellbooks_openers(lua):
    import pathlib
    import re
    boot(lua)
    assert lua.eval("HogHeals.slash.open") is None
    root = pathlib.Path(__file__).resolve().parents[1]
    hits = []
    for f in root.glob("*/**/*.lua"):
        if "Libs" in f.parts or f.parts[len(root.parts)] == "tests":
            continue
        for n, line in enumerate(f.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            code = line.split("--", 1)[0]
            if any(re.search("(?<![A-Za-z0-9_])" + w + "(?![A-Za-z0-9_])", code) for w in NEVER_FROM_OUR_LUA):
                hits.append(f"{f.relative_to(root)}:{n}: {line.strip()}")
    assert hits == []
