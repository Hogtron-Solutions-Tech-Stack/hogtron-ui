"""On the parchment page a window's own inner boxes go, so text only ever lands on paper (HogTron_Skin/Panels.lua
Part.Inner / KEEP_INNER / BOOK). Sean 2026-11-05 in game, over the exit popup: "We need to remove that inner box and
change the coloring of the letters. Like, you can't see this at all." - and over the character window: "Some look fine
and some look like this. We need to remove those like inner windows." Names below are the ones the client reported
(diag.skin.windows: StaticPopup1.BG.Top / .Bottom, GameMenuFrame.Header.*, CharacterFrame panes and stat rows)."""
from test_skin_windows import win, errors  # noqa: F401 (fixture)

SCENE = r'''
local function tex(parent, key, file) local t = parent:CreateTexture() t:SetTexture(file) parent[key] = t return t end
local function text(parent, key, r, g, b) local s = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal") s:SetText(key) s:SetTextColor(r, g, b) parent[key] = s return s end

StaticPopup1 = CreateFrame("Frame", "StaticPopup1", UIParent) StaticPopup1:SetSize(320, 90) StaticPopup1:Hide()
StaticPopup1.BG = CreateFrame("Frame", nil, StaticPopup1)
tex(StaticPopup1.BG, "Top", "UI-DiamondDialogBox-Border") tex(StaticPopup1.BG, "Bottom", "UI-DialogBox-Background-Dark")
StaticPopup1Text = text(StaticPopup1, "Msg", 1, 0.82, 0)
StaticPopup1Button1 = CreateFrame("Button", "StaticPopup1Button1", StaticPopup1)
tex(StaticPopup1Button1, "Art", "UI-DialogBox-Button-Up") text(StaticPopup1Button1, "Label", 1, 0.82, 0)

GameMenuFrame = CreateFrame("Frame", "GameMenuFrame", UIParent) GameMenuFrame:SetSize(200, 300) GameMenuFrame:Hide()
GameMenuFrame.Header = CreateFrame("Frame", nil, GameMenuFrame)
tex(GameMenuFrame.Header, "LeftBG", "UI-Frame-DiamondMetal-Header-CornerLeft") tex(GameMenuFrame.Header, "CenterBG", "_UI-Frame-DiamondMetal-Header-Tile")
text(GameMenuFrame.Header, "Text", 1, 0.82, 0)

CharacterFrame = CreateFrame("Frame", "CharacterFrame", UIParent) CharacterFrame:SetSize(560, 460) CharacterFrame:Hide()
local left = CreateFrame("Frame", "CharacterFrameLeftPaneHost", CharacterFrame) tex(left, "Bg", "UI-Character-Info-General-BG")
left.NineSlice = CreateFrame("Frame", nil, left) tex(left.NineSlice, "Edge", "common-insideframe")
local stats = CreateFrame("Frame", "CharacterStatsPaneScrollBox", left) tex(stats, "ClassBackground", "UI-Character-Info-Druid-BG")
local row = CreateFrame("Frame", nil, stats) tex(row, "Background", "UI-Character-Info-Line-Bounce2") text(row, "Label", 1, 1, 1) text(row, "Value", 0.1, 1, 0.1)
stats.Row = row
stats.ScrollBar = CreateFrame("Frame", nil, stats) stats.ScrollBar.Track = CreateFrame("Frame", nil, stats.ScrollBar)
tex(stats.ScrollBar.Track, "Middle", "!minimal-scrollbar-track-middle") stats.ScrollBar.Thumb = CreateFrame("Button", nil, stats.ScrollBar)
local slot = CreateFrame("Button", "CharacterHeadSlot", left) tex(slot, "Frame", "UI-Character-Slot") CharacterFrame.Slot = slot
CharacterFrame.Model = CreateFrame("PlayerModel", "CharacterModelScene", left)
text(CharacterFrame, "Level", 1, 0.82, 0)
CharacterFrame.Left = left

PlayerSpellsFrame = CreateFrame("Frame", "PlayerSpellsFrame", UIParent) PlayerSpellsFrame:SetSize(600, 700) PlayerSpellsFrame:Hide()
PlayerSpellsFrame.Book = CreateFrame("Frame", nil, PlayerSpellsFrame) tex(PlayerSpellsFrame.Book, "BookBGHalved", "spellbook-Page-Right-C60")
text(PlayerSpellsFrame.Book, "Spell", 0.18, 0.12, 0.06)

AchievementFrame = CreateFrame("Frame", "AchievementFrame", UIParent) AchievementFrame:SetSize(700, 500) AchievementFrame:Hide()
AchievementFrame.Tree = CreateFrame("Frame", nil, AchievementFrame) tex(AchievementFrame.Tree, "Art", "achievement-parchment")
text(AchievementFrame.Tree, "Points", 1, 1, 1)
'''


def alpha(lua, expr):
    return lua.eval(f"{expr}._alpha")


def rgb(lua, expr):
    return [round(v, 2) for v in list(lua.eval(f"{expr}._color").values())[:3]]


def ink(lua):
    return [round(v, 2) for v in list(lua.eval("HogHeals.Parchment.THEMES.light.text").values())]


def test_the_exit_popups_inner_box_goes_and_its_text_is_inked_on_paper(win):
    win.execute(SCENE + "ShowUIPanel(StaticPopup1); MockAdvance(1)")
    assert win.eval("StaticPopup1.hhPanel.pageTop ~= nil")
    assert win.eval("StaticPopup1.hhPanel.rule:IsShown()") is False                                 # no title row: no rule across the message
    top, bot = win.eval("StaticPopup1.hhPanel.pageTop._height"), win.eval("StaticPopup1.hhPanel.pageBot._height")
    bot_starts = -win.eval("StaticPopup1.hhPanel.pageBot._points[1][5]")                            # how far down the bottom slice begins
    assert top == bot and top <= bot_starts + 1e-6                                                    # short page: the slices meet, never overlap
    assert alpha(win, "StaticPopup1.BG.Top") == 0 and alpha(win, "StaticPopup1.BG.Bottom") == 0      # the dark diamond box
    t = rgb(win, "StaticPopup1Text")
    assert t[0] < 0.6 and t[0] > t[2]                                                             # gold -> amber ink, readable on paper
    assert alpha(win, "StaticPopup1Button1.Art") == 1 and rgb(win, "StaticPopup1Button1.Label") == [1, 0.82, 0]   # a button keeps its art and label
    assert errors(win) == []


def test_the_escape_menus_metal_header_goes_and_keeps_its_title(win):
    win.execute(SCENE + "ShowUIPanel(GameMenuFrame); MockAdvance(1)")
    assert alpha(win, "GameMenuFrame.Header.LeftBG") == 0 and alpha(win, "GameMenuFrame.Header.CenterBG") == 0
    assert win.eval("GameMenuFrame.Header.Text:IsShown()") is True and rgb(win, "GameMenuFrame.Header.Text")[0] < 0.6
    assert errors(win) == []


def test_the_character_windows_inner_panes_go_and_its_controls_stay(win):
    win.execute(SCENE + "ShowUIPanel(CharacterFrame); MockAdvance(1)")
    L = "CharacterFrame.Left"
    for piece in (f"{L}.Bg", f"{L}.NineSlice.Edge", "CharacterStatsPaneScrollBox.ClassBackground", "CharacterStatsPaneScrollBox.Row.Background"):
        assert alpha(win, piece) == 0, piece
    assert rgb(win, "CharacterStatsPaneScrollBox.Row.Label") == ink(win)                           # white label -> ink, on paper now
    v = rgb(win, "CharacterStatsPaneScrollBox.Row.Value")
    assert v[1] > 3 * v[0] and v[1] < 0.7                                                         # green kept, darkened to read
    assert alpha(win, "CharacterStatsPaneScrollBox.ScrollBar.Track.Middle") == 1                     # the scroll rail is a control
    assert alpha(win, "CharacterFrame.Slot.Frame") == 1                                              # an item slot keeps its frame
    assert rgb(win, "CharacterFrame.Level")[0] < 0.6
    assert errors(win) == []


def test_late_rows_are_caught_by_the_next_pass(win):
    win.execute(SCENE + '''
      ShowUIPanel(CharacterFrame)
      local r = CreateFrame("Frame", nil, CharacterStatsPaneScrollBox)
      r.Background = r:CreateTexture() r.Background:SetTexture("UI-Character-Info-Title")
      r.Label = r:CreateFontString(nil, "OVERLAY", "GameFontNormal") r.Label:SetTextColor(1, 1, 1)
      LATE = r
      MockAdvance(0.3)
    ''')
    assert alpha(win, "LATE.Background") == 0 and rgb(win, "LATE.Label") == ink(win)
    assert errors(win) == []


def test_the_spellbook_keeps_its_own_book_page(win):
    win.execute(SCENE + "ShowUIPanel(PlayerSpellsFrame); MockAdvance(1)")
    assert win.eval("PlayerSpellsFrame.hhPanel.pageTop ~= nil")                                     # our page behind
    assert alpha(win, "PlayerSpellsFrame.Book.BookBGHalved") == 1                                    # Blizzard's book stays (Sean: "looks fine")
    assert rgb(win, "PlayerSpellsFrame.Book.Spell") == [0.18, 0.12, 0.06]                            # its dark text untouched
    assert errors(win) == []


def test_a_window_whose_art_is_its_content_keeps_the_ink_panel(win):
    win.execute(SCENE + "ShowUIPanel(AchievementFrame); MockAdvance(1)")
    assert win.eval("AchievementFrame.hhPanel.bg ~= nil") and win.eval("AchievementFrame.hhPanel.pageTop") is None
    assert alpha(win, "AchievementFrame.Tree.Art") == 1 and rgb(win, "AchievementFrame.Tree.Points") == [1, 1, 1]
    assert errors(win) == []
