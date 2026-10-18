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
