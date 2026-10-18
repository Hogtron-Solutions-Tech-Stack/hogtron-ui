"""Blizzard windows, second pass (Sean 2026-10-15: Friends and Looking For Group still showed Blizzard's gold border,
portrait ring and red X next to a skinned Character window). Built like the modern window template: NineSlice border
frame, PortraitContainer, TitleContainer, an Inset with its own NineSlice, a close button whose art is its normal /
pushed textures, and a tab strip."""
import pytest

WINDOW = r'''
function MakeWindow(name)
  local f = CreateFrame("Frame", name, UIParent)
  f.NineSlice = CreateFrame("Frame", nil, f)
  f.NineSlice.TopLeftCorner = f.NineSlice:CreateTexture(); f.NineSlice.TopLeftCorner:SetTexture("gold-corner")
  f.NineSlice.TopEdge = f.NineSlice:CreateTexture(); f.NineSlice.TopEdge:SetTexture("gold-edge")
  f.PortraitContainer = CreateFrame("Frame", nil, f)
  f.PortraitContainer.portrait = f.PortraitContainer:CreateTexture(); f.PortraitContainer.portrait:SetTexture("friends-portrait")
  f.TitleContainer = CreateFrame("Frame", nil, f)
  f.TitleContainer.TitleText = f.TitleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.Bg = f:CreateTexture(); f.Bg:SetTexture("parchment-bg")
  f.Inset = CreateFrame("Frame", name .. "Inset", f)
  f.Inset.NineSlice = CreateFrame("Frame", nil, f.Inset)
  f.Inset.NineSlice.Edge = f.Inset.NineSlice:CreateTexture(); f.Inset.NineSlice.Edge:SetTexture("inset-edge")
  f.Inset.Bg = f.Inset:CreateTexture(); f.Inset.Bg:SetTexture("inset-bg")
  f.CloseButton = CreateFrame("Button", nil, f)
  f.CloseButton._normal = f.CloseButton:CreateTexture(); f.CloseButton._normal:SetTexture("red-x")
  function f.CloseButton:GetNormalTexture() return self._normal end
  for i = 1, 3 do
    local t = CreateFrame("Button", name .. "Tab" .. i, f)
    t.Left = t:CreateTexture(); t.Left:SetTexture("tab-left")
    t.Middle = t:CreateTexture(); t.Middle:SetTexture("tab-mid")
    t.Right = t:CreateTexture(); t.Right:SetTexture("tab-right")
  end
  f:Hide()
  return f
end
FriendsFrame = MakeWindow("FriendsFrame")
LFGParentFrame = MakeWindow("LFGParentFrame")
SocialUIFrame = MakeWindow("SocialUIFrame")     -- WoW: Forever's Friends window (/hh under, 2026-10-17)
function ShowUIPanel(f) f:Show() local s = f:GetScript("OnShow") if s then s(f) end end
'''


@pytest.fixture
def win(lua):
    lua.execute(WINDOW)
    lua.load_addon("HogTronUI")
    lua.load_addon("HogTron_Skin")
    lua.player_login()
    lua.execute('wipe(HogHeals.errors)')
    return lua


def errors(lua):
    return [e["msg"] for e in lua.eval('HogHeals.errors').values()]


@pytest.mark.parametrize("name", ["FriendsFrame", "LFGParentFrame", "SocialUIFrame"])
def test_border_portrait_inset_close_and_tabs_are_all_handled(win, name):
    win.execute(f'ShowUIPanel({name})')
    f = name
    assert win.eval(f'{f}.hhPanel ~= nil')
    assert win.eval(f'{f}.NineSlice:IsShown()') is False                        # the gold border frame: hidden whole
    assert win.eval(f'{f}.PortraitContainer:IsShown()') is False                # the portrait ring
    assert win.eval(f'{f}.Bg._alpha') == 0
    assert win.eval(f'{f}.Inset.NineSlice:IsShown()') is False and win.eval(f'{f}.Inset.Bg._alpha') == 0
    assert win.eval(f'{f}.CloseButton._normal._alpha') == 0                     # the red X art
    assert win.eval(f'{f}.CloseButton.hhX._text') == "x"
    for i in (1, 2, 3):
        assert win.eval(f'{f}Tab{i}.Left._alpha') == 0 and win.eval(f'{f}Tab{i}.Middle._alpha') == 0
        assert win.eval(f'{f}Tab{i}.hhTabPanel ~= nil')
    assert errors(win) == []


def test_art_blizzard_brings_back_on_show_is_stripped_again(win):
    win.execute('ShowUIPanel(FriendsFrame); FriendsFrame:Hide()')
    win.execute('FriendsFrame.NineSlice:Show()')                                  # Blizzard re-applies its border
    assert win.eval('FriendsFrame.NineSlice:IsShown()') is False
    win.execute('FriendsFrame.Fresh = FriendsFrame:CreateTexture(); FriendsFrame.Fresh:SetTexture("new-art")')
    win.execute('ShowUIPanel(FriendsFrame)')                                      # every show strips, not only the first
    assert win.eval('FriendsFrame.Fresh._alpha') == 0


def test_a_failing_window_is_logged_by_name_and_reported(win):
    win.execute('HogHealsSkin.Panels.Tabs = function() error("boom in tabs") end; ShowUIPanel(LFGParentFrame)')
    msgs = errors(win)
    assert any("skin window LFGParentFrame" in m and "boom in tabs" in m for m in msgs)
    rep = win.eval('HogHeals.db.global.diag.skin.windows.LFGParentFrame')
    assert "boom in tabs" in rep["error"]


def test_leftover_blizzard_art_is_named_in_the_report(win):
    win.execute('''
      FriendsFrame.Odd = CreateFrame("Frame", nil, FriendsFrame)
      FriendsFrame.Odd.Gold = FriendsFrame.Odd:CreateTexture(); FriendsFrame.Odd.Gold:SetTexture("Interface/odd-gold"); FriendsFrame.Odd.Gold:SetSize(40, 12)
      ShowUIPanel(FriendsFrame); MockAdvance(1)
    ''')
    rep = win.eval('HogHeals.db.global.diag.skin.windows.FriendsFrame')
    assert rep["styled"] is True and rep["leftovers"] == 1
    assert "FriendsFrame.Odd.Gold Interface/odd-gold 40x12" in rep["left"]
    win.execute('MockLog.chat = {}; HogHeals:SlashCommand("skindiag")')
    chat = list(win.eval('MockLog.chat').values())
    assert any("window FriendsFrame: styled, 1 Blizzard piece(s) still showing" in l and "odd-gold" in l for l in chat)


def test_buttons_and_icons_are_not_reported_as_leftovers(win):
    win.execute('''
      local b = CreateFrame("Button", "FriendsFrameAddFriendButton", FriendsFrame)
      b.Art = b:CreateTexture(); b.Art:SetTexture("button-art")
      FriendsFrame.SomeIcon = FriendsFrame:CreateTexture("FriendsFrameStatusIcon"); FriendsFrame.SomeIcon:SetTexture("status")
      ShowUIPanel(FriendsFrame); MockAdvance(1)
    ''')
    assert win.eval('HogHeals.db.global.diag.skin.windows.FriendsFrame.leftovers') == 0


# ---------------------------------------------------------------- the Group Finder's panes (Sean 2026-10-17, /hh under)
# The window under the mouse was LFGListingFrame, a CHILD of the styled LFGParentFrame, with its own metal frame,
# bg, streaks, inset and role art; three side tabs with common-sidetab plates. Built here as the client reported it.
LFG = r'''
local p = LFGParentFrame
local function tex(parent, key, art, name) local t = parent:CreateTexture(name) t:SetAtlas(art) t:SetSize(40, 40) parent[key] = t return t end
local l = CreateFrame("Frame", "LFGListingFrame", p)
l.NineSlice = CreateFrame("Frame", nil, l)
tex(l.NineSlice, "TopLeftCorner", "UI-Frame-PortraitMetal-CornerTopLeft")
tex(l.NineSlice, "TopEdge", "_UI-Frame-Metal-EdgeTop")
tex(l, "Bg", "374155", "LFGListingFrameBg")
tex(l, "TopTileStreaks", "_UI-Frame-TopTileStreaks")
tex(l, "RoleBackground", "groupfinder-roles-background", "LFGListingFrameRoleBackground")
l.Inset = CreateFrame("Frame", nil, l)
tex(l.Inset, "CustomBG", "groupfinder-background")
tex(l.Inset, "Border", "common-insideframe")
l.DividerFrame = CreateFrame("Frame", nil, l)
tex(l.DividerFrame, "Divider", "common-framedivider")
local b = CreateFrame("Frame", "LFGBrowseFrame", p)
b.NineSlice = CreateFrame("Frame", nil, b)
tex(b.NineSlice, "LeftEdge", "!UI-Frame-Metal-EdgeLeft")
b:Hide()
local plain = CreateFrame("Frame", "LFGParentFramePlainChild", p)       -- no frame art: not a pane
tex(plain, "Art", "keep-me")
for _, k in ipairs({ "ListingTab", "BrowsingTab", "WhoListingTab" }) do
  local t = CreateFrame("Frame", nil, p)
  tex(t, "Background", "common-sidetab")
  t.Icon = t:CreateTexture(); t.Icon:SetTexture(8197096); t.Icon:SetSize(40, 40)
  tex(t, "SelectedTexture", "common-sidetab-selected")
  tex(t, "HighlightTexture", "common-sidetab-hover")
  p[k] = t
end
'''


def test_group_finder_panes_and_side_tabs_are_skinned(win):
    win.execute(LFG + 'ShowUIPanel(LFGParentFrame); MockAdvance(1)')
    l = "LFGListingFrame"
    assert win.eval(f'{l}.NineSlice:IsShown()') is False                          # the metal frame, hidden whole
    assert win.eval(f'{l}.TopTileStreaks:IsShown()') is False
    for piece in ("Bg", "RoleBackground", "Inset.CustomBG", "Inset.Border"):
        assert win.eval(f'{l}.{piece}._alpha') == 0, piece
    assert win.eval(f'{l}.DividerFrame.Divider._alpha') == 1                      # the divider stays, in our line colour
    assert [round(v, 2) for v in list(win.eval(f'{l}.DividerFrame.Divider._color').values())[:3]] == [0.2, 0.2, 0.25]
    assert win.eval('LFGBrowseFrame.NineSlice:IsShown()') is False                # a pane not shown yet: stripped too
    assert win.eval('LFGParentFramePlainChild.Art._alpha') == 1                   # a child without frame art: untouched
    for k in ("ListingTab", "BrowsingTab", "WhoListingTab"):
        t = f'LFGParentFrame.{k}'
        assert win.eval(f'{t}.Background._alpha') == 0
        assert win.eval(f'{t}.Icon._alpha') == 1
        assert [round(v, 2) for v in list(win.eval(f'{t}.SelectedTexture._color').values())[:3]] == [0.13, 0.83, 0.88]
        assert win.eval(f'HogHealsSkin.Panels.sideTabPanels[{t}] ~= nil')
    rep = win.eval('HogHeals.db.global.diag.skin.windows.LFGParentFrame')
    assert rep["leftovers"] == 1 and "keep-me" in rep["left"], rep["left"]   # only the piece left alone on purpose
    assert "LFGListingFrame" in rep["panes"] and "LFGBrowseFrame" in rep["panes"]
    assert errors(win) == []


def test_a_pane_shown_by_its_tab_is_stripped_again(win):
    win.execute(LFG + 'ShowUIPanel(LFGParentFrame); MockAdvance(1)')
    win.execute('''
      LFGBrowseFrame.Fresh = LFGBrowseFrame:CreateTexture(); LFGBrowseFrame.Fresh:SetAtlas("groupfinder-background")
      LFGBrowseFrame:Show(); LFGBrowseFrame:GetScript("OnShow")(LFGBrowseFrame); MockAdvance(1)
    ''')
    assert win.eval('LFGBrowseFrame.Fresh._alpha') == 0
    assert errors(win) == []


# ---------------------------------------------------------------- the Friends window's last Blizzard pieces (Sean 2026-10-17)
# diag.skin.windows.SocialUIFrame listed the Battle.net bar's backgrounds and the list's dividers after the strip.
def test_the_friends_windows_named_leftovers_are_cleared_and_its_scroll_track_stays(win):
    win.execute('''
      local f = SocialUIFrame
      f.BattleNetBar = CreateFrame("Frame", nil, f)
      f.BattleNetBar.Background = f.BattleNetBar:CreateTexture(); f.BattleNetBar.Background:SetAtlas("friends-frame-infoBG")
      f.BattleNetBar.ControlsContainer = CreateFrame("Frame", nil, f.BattleNetBar)
      f.BattleNetBar.ControlsContainer.BattleNetBackground = f.BattleNetBar.ControlsContainer:CreateTexture(); f.BattleNetBar.ControlsContainer.BattleNetBackground:SetTexture(632259)
      f.FriendsList = CreateFrame("Frame", nil, f)
      f.FriendsList.TopDivider = f.FriendsList:CreateTexture(); f.FriendsList.TopDivider:SetAtlas("perks-divider-short")
      f.FriendsList.BottomDivider = f.FriendsList:CreateTexture(); f.FriendsList.BottomDivider:SetAtlas("perks-divider-short")
      f.FriendsList.ScrollBar = CreateFrame("Frame", nil, f.FriendsList)
      f.FriendsList.ScrollBar.Track = f.FriendsList.ScrollBar:CreateTexture(); f.FriendsList.ScrollBar.Track:SetAtlas("minimal-scrollbar-track-middle")
      ShowUIPanel(SocialUIFrame)
    ''')
    for path in ("BattleNetBar.Background", "BattleNetBar.ControlsContainer.BattleNetBackground", "FriendsList.TopDivider", "FriendsList.BottomDivider"):
        assert win.eval(f"SocialUIFrame.{path}._alpha") == 0, path
    assert win.eval("SocialUIFrame.FriendsList.ScrollBar.Track._alpha") == 1
    assert errors(win) == []


# ---------------------------------------------------------------- reports never vanish (2026-10-17)
# Sean: the Friends window looked stock and left no trace in diag.skin.windows - the leftovers walk ran inside the
# report's pcall, so a throw there lost the whole record.
def test_a_throwing_leftovers_walk_still_leaves_the_record(win):
    win.execute('HogHealsSkin.Panels.Leftovers = function() error("forbidden child") end; ShowUIPanel(LFGParentFrame); MockAdvance(1)')
    rep = win.eval('HogHeals.db.global.diag.skin.windows.LFGParentFrame')
    assert rep is not None and rep["styled"] is True and "forbidden child" in rep["leftoversError"]
    assert rep["shown"] is True


def test_skindiag_keeps_the_window_records_and_counts_shows(win):
    win.execute('local f = LFGParentFrame; f:GetScript("OnShow")(f); MockAdvance(1)')
    assert win.eval('HogHealsSkin.Panels.shows.LFGParentFrame') >= 1
    win.execute('MockLog.chat = {}; HogHeals:SlashCommand("skindiag")')
    assert win.eval('HogHeals.db.global.diag.skin.windows.LFGParentFrame ~= nil')       # not wiped by the diag itself
    assert "LFGParentFrame=" in win.eval('HogHeals.db.global.diag.skin.shows')
    assert any("windows shown this session" in l for l in win.eval('MockLog.chat').values())
