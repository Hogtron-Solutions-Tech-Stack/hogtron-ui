"""Blizzard's windows on the parchment page (Sean 2026-11-05: "re-skin all of the windows to kind of match that same
aesthetic" - the Training page / quest dialog; "We need to reskin all of this, including this" over Guild & Communities).
HogTron_Skin/Panels.lua: skin.panels.look = "parchment" (default) | "ink"; the page's theme follows Quests > Dialog > Theme."""
import pytest
from test_skin_windows import win, errors, WINDOW  # noqa: F401 (fixture)


def rgb(lua, expr):
    return [round(v, 2) for v in list(lua.eval(expr).values())[:3]]


def theme(lua, key):
    return {k: [round(v, 2) for v in list(c.values())] for k, c in lua.eval(f"HogHeals.Parchment.THEMES.{key}").items() if k != "paper"}


def test_a_window_wears_the_page_by_default(win):
    win.execute('FriendsFrame:SetSize(600, 450); FriendsFrame.TitleContainer.TitleText:SetText("Friends"); ShowUIPanel(FriendsFrame)')
    f, th = "FriendsFrame", theme(win, "light")
    assert win.eval(f"{f}.hhPanel ~= nil") and win.eval(f"{f}.hhPanel.pageTop._texture").endswith("dialog_page_light")
    assert win.eval(f"{f}.hhPanel.bg") is None                                                           # the page, no ink slab
    px = 32 * 600 / 448                                                                                  # the art's side margin, scaled
    assert win.eval(f"{f}.hhPanel.pageMid._width") == pytest.approx(600 + 2 * px)                       # wider than the window by the torn margins
    assert win.eval(f"{f}.hhPanel._points[1][4]") == pytest.approx(-px) and win.eval(f"{f}.hhPanel._points[1][5]") == pytest.approx(46 * 600 / 448)
    assert win.eval(f"{f}.hhPanel._points[2][5]") == pytest.approx(-(48 * 600 / 448 + 34))              # room for the tab strip under it
    assert win.eval(f"{f}.hhPanel.rule._points[1][2] == {f}") is True
    assert win.eval(f"{f}.hhPanel._alpha") == pytest.approx(1)                                           # solid paper (0.9 let things show through)
    assert win.eval(f"{f}.hhPanel.rule._texture").endswith("dialog_rule")
    assert rgb(win, f"{f}.TitleContainer.TitleText._color") == th["title"]
    assert win.eval(f"{f}.CloseButton.hhX._text") == "x" and rgb(win, f"{f}.CloseButton.hhX._color") == th["keyText"]
    assert [round(v, 2) for v in list(win.eval(f"{f}.CloseButton.hhCap.color").values())] == th["key"]   # the key cap
    assert win.eval(f"{f}Tab1.hhTabPanel.parts ~= nil") and win.eval(f"{f}Tab1.hhTabPanel.bg") is None  # tabs: rounded slabs
    assert [round(v, 2) for v in list(win.eval(f"{f}Tab1.hhTabPanel.color").values())] == th["tag"]
    assert errors(win) == []


def test_the_light_page_inks_blizzards_text_but_keeps_its_hues(win):
    win.execute('''
      local f = FriendsFrame
      local function fs(k, r, g, b) f[k] = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f[k]:SetText(k); f[k]:SetTextColor(r, g, b) end
      fs("White", 1, 1, 1); fs("Gold", 1, 0.82, 0); fs("Red", 1, 0.1, 0.1); fs("Green", 0, 1, 0); fs("Grey", 0.5, 0.5, 0.5); fs("Black", 0, 0, 0)
      fs("Mage", 0.25, 0.78, 0.92)
      f.Deep = CreateFrame("Frame", nil, f); f.Deep.S = f.Deep:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); f.Deep.S:SetTextColor(1, 1, 1)
      local b = CreateFrame("Button", nil, f); b.T = b:CreateFontString(nil, "OVERLAY", "GameFontNormal"); b.T:SetTextColor(1, 1, 1); f.Btn = b
      ShowUIPanel(f); MockAdvance(1)
    ''')
    th = theme(win, "light")
    assert rgb(win, "FriendsFrame.White._color") == th["text"] and rgb(win, "FriendsFrame.Deep.S._color") == th["text"]
    assert rgb(win, "FriendsFrame.Grey._color") == th["muted"]
    assert rgb(win, "FriendsFrame.Black._color") == [0, 0, 0]                            # already ink: left alone
    assert rgb(win, "FriendsFrame.Btn.T._color") == [1, 1, 1]                            # a button's label is the button's
    r = rgb(win, "FriendsFrame.Red._color"); assert r[0] > 3 * r[1]                      # red stays red
    g = rgb(win, "FriendsFrame.Green._color"); assert g[1] > 3 * g[0] and g[1] < 0.7     # green, brought down to read on paper
    gd = rgb(win, "FriendsFrame.Gold._color"); assert gd[0] > gd[1] > gd[2] and gd[0] < 0.6   # gold -> amber
    m = rgb(win, "FriendsFrame.Mage._color"); assert m[2] > m[0] and m[2] < 0.6           # a class colour keeps its hue
    win.execute("FriendsFrame.White:SetTextColor(1, 1, 1)")                              # Blizzard repaints it: inked again
    assert rgb(win, "FriendsFrame.White._color") == th["text"]
    assert errors(win) == []


def test_the_dark_page_keeps_blizzards_light_text_and_the_ink_look_still_exists(win):
    win.execute('HogHeals.db.profile.quests = { dialog = { theme = "dark" } }')
    win.execute('FriendsFrame:SetSize(600, 450); FriendsFrame.W = FriendsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); FriendsFrame.W:SetTextColor(1, 1, 1); ShowUIPanel(FriendsFrame); MockAdvance(1)')
    assert win.eval("FriendsFrame.hhPanel.pageTop._texture").endswith("dialog_page_dark")
    assert rgb(win, "FriendsFrame.W._color") == [1, 1, 1]
    assert rgb(win, "FriendsFrame.TitleContainer.TitleText._color") == theme(win, "dark")["title"]
    win.execute('HogHeals.db.profile.skin.panels.look = "ink"; ShowUIPanel(LFGParentFrame)')
    assert win.eval("LFGParentFrame.hhPanel.bg ~= nil") and win.eval("LFGParentFrame.hhPanel.pageTop") is None
    assert win.eval("LFGParentFrameTab1.hhTabPanel.bg ~= nil")
    assert errors(win) == []


COMMUNITIES = r'''
CommunitiesFrame = MakeWindow("CommunitiesFrame")
for _, k in ipairs({ "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }) do
  local t = CreateFrame("Button", nil, CommunitiesFrame)
  t.Background = t:CreateTexture(); t.Background:SetAtlas("common-sidetab")
  t.Icon = t:CreateTexture(); t.Icon:SetTexture("Interface/Icons/chat")
  t.SelectedTexture = t:CreateTexture(); t.SelectedTexture:SetAtlas("common-sidetab-selected")
  CommunitiesFrame[k] = t
end
'''


def test_guild_and_communities_is_skinned_with_its_side_tabs(win):
    win.execute(COMMUNITIES + "ShowUIPanel(CommunitiesFrame); MockAdvance(1)")
    assert "CommunitiesFrame" in list(win.eval("HogHealsSkin.Panels.NAMES").values())
    assert win.eval("CommunitiesFrame.hhPanel ~= nil") and win.eval("CommunitiesFrame.NineSlice:IsShown()") is False
    th = theme(win, "light")
    for k in ("ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab"):
        t = f"CommunitiesFrame.{k}"
        assert win.eval(f"{t}.Background._alpha") == 0 and win.eval(f"{t}.Icon._alpha") == 1
        assert rgb(win, f"{t}.SelectedTexture._color") == th["pick"]
        assert win.eval(f"HogHealsSkin.Panels.sideTabPanels[{t}] ~= nil")
    assert errors(win) == []
