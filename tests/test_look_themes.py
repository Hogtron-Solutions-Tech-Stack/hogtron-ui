"""The UI's three looks (HogTronUI/Core/Look.lua look.style): Parchment (default), Modern, Blizzard. Sean 2026-11-05:
"we can do a modern look or a like wow look and then I also have the wow defaults. Those are my three things I'm
envisioning ... everything needs to match that themeing." Windows follow it (HogTron_Skin/Panels.lua skin.panels.look
= "auto"); /hh open <window> opens Blizzard's windows to check them one by one."""
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


OPENERS = r'''
OPENED = {}
function ToggleCharacter(tab) OPENED[#OPENED + 1] = "char:" .. tab end
PlayerSpellsUtil = { ToggleSpellBookFrame = function() OPENED[#OPENED + 1] = "spellbook" end }
function ToggleQuestLog() OPENED[#OPENED + 1] = "questlog" end
function ToggleGuildFrame() error("not in this client") end
function ToggleCommunitiesFrame() OPENED[#OPENED + 1] = "communities" end
'''


def test_open_names_a_window_and_says_when_the_client_lacks_it(lua):
    boot(lua, extra=OPENERS)
    for word in ("character", "spellbook", "questlog", "guild", "reputation"):
        lua.execute(f"HogHeals:SlashCommand('open {word}')")
    assert list(lua.eval("OPENED").values()) == ["char:PaperDollFrame", "spellbook", "questlog", "communities", "char:ReputationFrame"]
    lua.execute("MockLog.chat = {}; HogHeals:SlashCommand('open achievements'); HogHeals:SlashCommand('open nonsense')")
    chat = "\n".join(lua.eval("MockLog.chat").values())
    assert "open achievements: this client has no such window" in chat
    assert "open: one of " in chat and "spellbook" in chat
    assert errors(lua) == []
