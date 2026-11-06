"""Our own frames in the Parchment look (HogTronUI/Core/Parchment.lua Palette / Backdrop / Hue, and the quest tracker,
info bar, menu bar, bags and windows that use them). Sean 2026-11-05: "I want things like the quest menus on the side
changed. I want the bars at the bottom that shows how much gold and different things we have changed. I want
everything to match this paper-like theme ... We even need to make new icons in the line." Modern stays as it was
(tests/test_skin.py, tests/test_quests.py pin it)."""
import pathlib

import pytest

from test_quests import MODERN as QUEST_API
from test_skin import CLIENT

P = "HogHeals.Parchment"
MEDIA = pathlib.Path(__file__).resolve().parents[1] / "HogTronUI" / "Media"


def boot(lua, style=None):
    if style:
        lua.execute(f'HogTronUIDB = {{ profiles = {{ Default = {{ look = {{ style = "{style}" }} }} }} }}')
    lua.execute(CLIENT + QUEST_API)
    for a in ("HogTronUI", "HogTron_Skin", "HogTron_Quests"):
        lua.load_addon(a)
    lua.player_login()
    lua.execute("wipe(HogHeals.errors)")
    return lua


@pytest.fixture
def page(lua):
    return boot(lua)


def errors(lua):
    return [e["msg"] for e in lua.eval("HogHeals.errors").values()]


def rgb(lua, expr):
    return [round(v, 2) for v in list(lua.eval(expr).values())[:3]]


def light(lua, key):
    return [round(v, 2) for v in list(lua.eval(f"{P}.THEMES.light.{key}").values())[:3]]


# ------------------------------------------------------------------------------------------------ core
def test_palette_and_hues_follow_the_look(lua):
    boot(lua)
    assert lua.eval(f"{P}.On()") is True and lua.eval(f"{P}.Palette().paper") is True
    assert rgb(lua, f"{P}.Palette().text") == light(lua, "text")
    r, g, b = lua.eval(f"{{ {P}.Hue(1, 0.82, 0) }}").values()                   # quest-yellow -> amber ink, hue kept
    assert r > g > b and r < 0.6
    assert lua.eval(f"{P}.HueHex('ffd700')") != "ffd700" and len(lua.eval(f"{P}.HueHex('ffd700')")) == 6
    assert lua.eval(f"{P}.HueHex('nothex')") == "nothex"


def test_modern_palette_and_hues_are_untouched(lua):
    boot(lua, "hogtron")
    assert lua.eval(f"{P}.On()") is False and lua.eval(f"{P}.Palette().paper") is False
    assert rgb(lua, f"{P}.Palette().accent") == [0.13, 0.83, 0.88]
    assert list(lua.eval(f"{{ {P}.Hue(1, 0.82, 0) }}").values()) == [1, 0.82, 0]
    assert lua.eval(f"{P}.HueHex('ffd700')") == "ffd700"


def test_backdrop_is_paper_cropped_to_the_frames_shape(page):
    page.execute(f"F = CreateFrame('Frame', nil, UIParent); F:SetSize(640, 18); B = {P}.Backdrop(F, 0.5)")
    assert page.eval("B.paper") is True and page.eval("B.bg._texture").endswith("dialog_page_light")
    assert page.eval("B.bg._alpha") == pytest.approx(0.9)                         # ink needs solid paper: at least 0.9
    l, r, t, b = page.eval("B.bg._texCoord").values()
    assert (r - l) * 512 / ((b - t) * 1024) == pytest.approx(640 / 18, rel=0.01)  # never stretched
    assert 40 / 512 - 1e-6 <= l and r <= 472 / 512 + 1e-6                          # inside the torn margins
    assert len(list(page.eval("B.edges").values())) == 4


# ------------------------------------------------------------------------------------------------ our frames
def test_the_quest_tracker_is_on_paper_with_ink_and_darkened_difficulty(page):
    page.execute("HogHealsQuests.Tracker.Update()")
    f = "HogHealsQuestTracker"
    assert page.eval(f"{f}.paper") is True and page.eval(f"{f}.bg._texture").endswith("dialog_page_light")
    assert rgb(page, f"{f}.title._color") == light(page, "pick")                   # the header title in the page's accent
    r, g, b = page.eval("{ HogHealsQuests.Tracker.LevelColor(2) }").values()      # a difficulty colour, inked to read
    raw = list(page.eval("{ HogHealsQuests.Tracker.RawLevelColor(2) }").values())
    assert 0.299 * r + 0.587 * g + 0.114 * b < 0.36 and (r, g, b) != tuple(raw)
    page.execute("HogHealsQuests.Tracker.Update()")                                # an update keeps the paper
    assert page.eval(f"{f}.bg._texture").endswith("dialog_page_light")
    assert errors(page) == []


def test_the_info_bar_is_a_paper_strip_with_ink_readings(page):
    bar, B = "HogUIInfoBar", "HogHealsSkin.InfoBar"
    assert page.eval(f"{bar}.paper") is True and page.eval(f"{bar}.plate") is None   # no slate plaque
    s = f"{B}.slots[1].text"
    assert rgb(page, f"{s}._color") == light(page, "text")
    assert page.eval(f"{s}._last.SetShadowOffset[1]") == 0
    assert page.eval(f"{s}._last.SetFont[3]") == ""                                # no black rim round the ink (in game: a smudge)
    page.execute(f"{B}.Update()")
    texts = " ".join(page.eval(f"{B}.slots[{i}] and {B}.slots[{i}].text._text or ''") for i in range(1, 8))
    assert "|cff" in texts and "ffd700" not in texts.lower() and "c7c7cf" not in texts.lower()   # gold / silver codes darkened
    assert errors(page) == []


def test_the_menu_bar_wears_ink_stamps_on_paper(page):
    bar = "HogHealsMicroBar"
    assert page.eval(f"{bar}.paper") is True
    c = f"{bar}.cells[1]"
    assert page.eval(f"{c}.page") is True and page.eval(f"{c}.icon._texture").endswith("_page")
    assert page.eval(f"{c}.accent:IsShown()") is False and page.eval(f"{c}.bg:IsShown()") is False
    page.execute(f'{c}:GetScript("OnEnter")({c})')
    assert page.eval(f"{c}.bg:IsShown()") is True                                   # hover: a soft plate behind the stamp
    page.execute(f'{c}:GetScript("OnLeave")({c})')
    assert page.eval(f"{c}.bg:IsShown()") is False
    assert errors(page) == []


def test_every_glyph_has_an_ink_stamp_and_the_look_picks_it(page):
    for art in MEDIA.glob("*_art.tga"):
        glyph = MEDIA / (art.name[:-8] + ".tga")
        if glyph.exists():
            assert (MEDIA / (art.name[:-8] + "_page.tga")).exists(), art.name
    assert page.eval("HogHeals.Look.IconStyle()") == "page"
    page.execute("T = UIParent:CreateTexture()")
    assert list(page.eval("{ HogHeals.Look.Icon(T, 'micro_character') }").values()) == [True, True]
    assert page.eval("T._texture").endswith("micro_character_page")
    page.execute("HogHeals.db.profile.look.icons = 'glyph'")                      # an explicit choice still wins
    assert page.eval("HogHeals.Look.IconStyle()") == "glyph"


def test_a_bag_is_on_paper_with_an_ink_title(page):
    page.execute('''
      B = CreateFrame("Frame", "ContainerFrame1", UIParent) B:SetSize(200, 240)
      B.TitleText = B:CreateFontString(nil, "OVERLAY", "GameFontNormal") B.TitleText:SetTextColor(1, 1, 1)
      HogHealsSkin.Bags.Style(B)
    ''')
    assert page.eval("B.hh.page") is True and page.eval("B.hh.panel.bg._texture").endswith("dialog_page_light")
    assert rgb(page, "B.TitleText._color") == light(page, "title")
    assert page.eval("B.TitleText._last.SetFont[3]") == ""
    assert errors(page) == []


# ------------------------------------------------------------------------------------------------ windows, round 3
FRIENDS = r'''
local f = FriendsFrame
local row = CreateFrame("Button", "FriendsListButton1", f)
row.background = row:CreateTexture() row.background:SetColorTexture(0.05, 0.1, 0.25, 1)
row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal") row.name:SetTextColor(0.51, 0.77, 1)
row.name._font = nil
row.info = row:CreateFontString(nil, "OVERLAY", "GameFontNormal") row.info:SetTextColor(0.5, 0.5, 0.5)
local plain = CreateFrame("Button", "FriendsFrameAddFriendButton", f)
plain.label = plain:CreateFontString(nil, "OVERLAY", "GameFontNormal") plain.label:SetTextColor(1, 0.82, 0)
f.Level = f:CreateFontString(nil, "OVERLAY", "GameFontNormal") f.Level:SetTextColor(1, 0.82, 0)
function f.Level:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "OUTLINE" end
f:SetSize(500, 400)
'''


def test_list_rows_lose_their_bars_and_inked_text_loses_outline_and_shadow(lua):
    from test_skin_windows import WINDOW
    lua.execute(WINDOW)
    boot(lua)
    lua.execute(FRIENDS + "ShowUIPanel(FriendsFrame); MockAdvance(1)")
    assert lua.eval("FriendsListButton1.background._alpha") == 0                   # the navy bar
    nm = rgb(lua, "FriendsListButton1.name._color")
    assert nm[2] > nm[0] and 0.299 * nm[0] + 0.587 * nm[1] + 0.114 * nm[2] < 0.36   # a BNet blue, inked
    assert rgb(lua, "FriendsFrameAddFriendButton.label._color") == [1, 0.82, 0]      # a plain button keeps its label
    assert lua.eval("FriendsFrame.Level._last.SetFont[3]") == ""                     # outline off
    assert lua.eval("FriendsFrame.Level._last.SetShadowOffset[1]") == 0              # shadow off
    assert lua.eval("FriendsFrame.hhPanel._alpha") == 1                              # solid paper
    assert errors(lua) == []


# ------------------------------------------------------------------------------------------------ batch 3: charred + maps
def test_tooltips_wear_the_charred_page_and_keep_their_opacity(page):
    page.execute("HogHealsSkin.Tooltip.Style(GameTooltip)")
    p = "GameTooltip.hh.panel"
    assert page.eval(f"{p}.paper") is True and page.eval(f"{p}.bg._texture").endswith("dialog_page_dark")
    page.execute("HogHeals.db.profile.skin.tooltips.alpha = 0.7; HogHealsSkin.Tooltip.Style(GameTooltip)")
    assert page.eval(f"{p}.bg._alpha") == pytest.approx(0.7)                      # charred may be see-through
    assert errors(page) == []


def test_chat_windows_wear_the_charred_page(lua):
    from test_chat import CHAT
    lua.execute(CHAT)
    for a in ("HogTronUI", "HogTron_Chat"):
        lua.load_addon(a)
    lua.player_login()
    s = "HogHealsChat.Chat.styled[ChatFrame1].panel"
    assert lua.eval(f"{s}.paper") is True and lua.eval(f"{s}.bg._texture").endswith("dialog_page_dark")
    assert errors(lua) == []


def test_the_damage_meter_wears_the_charred_page(lua):
    from test_meter import MOCK_API
    lua.execute(MOCK_API)
    for a in ("HogTronUI", "HogHeals_Frames", "HogTron_HUD", "HogTron_Meter"):
        lua.load_addon(a)
    lua.player_login()
    f = "HogHealsMeter.Meter.frame"
    assert lua.eval(f"{f}.paper") is True and lua.eval(f"{f}.bg._texture").endswith("dialog_page_dark")
    assert errors(lua) == []


def test_the_minimap_is_framed_in_paper_with_an_ink_zone_name(page):
    page.execute("HogHealsQuests.MapSkin.Apply(); HogHealsQuests.MapSkin.UpdateZone()")
    f = "HogHealsMinimapFrame"
    assert page.eval(f"{f}.paper") is True and page.eval(f"{f}.bg._texture").endswith("dialog_page_light")
    assert rgb(page, f"{f}.zone._color") == light(page, "text")                    # no PvP info: the page's ink
    page.execute("function GetZonePVPInfo() return 'hostile' end; HogHealsQuests.MapSkin.UpdateZone()")
    r, g, b = (page.eval(f"{f}.zone._color[{i}]") for i in (1, 2, 3))
    assert r > 3 * g and 0.299 * r + 0.587 * g + 0.114 * b < 0.36                    # hostile red, dark enough for paper
    assert errors(page) == []


def test_the_world_map_sits_on_the_torn_page_and_its_quest_log_is_inked(lua):
    from test_world_map import MAP
    lua.execute(CLIENT + QUEST_API + MAP + r'''
      WorldMapFrame:SetSize(1000, 700)
      WorldMapFrame.BorderFrame.TitleContainer = CreateFrame("Frame", nil, WorldMapFrame.BorderFrame)
      WorldMapFrame.BorderFrame.TitleContainer.TitleText = WorldMapFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      QuestMapFrame = CreateFrame("Frame", "QuestMapFrame", WorldMapFrame)
      QuestMapFrame.Background = QuestMapFrame:CreateTexture() QuestMapFrame.Background:SetTexture("questlog-bg")
      QuestMapFrame.Line = QuestMapFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal") QuestMapFrame.Line:SetTextColor(1, 1, 1)
      WorldMapFrame.ScrollContainer.Tile = WorldMapFrame.ScrollContainer:CreateTexture() WorldMapFrame.ScrollContainer.Tile:SetTexture("map-tile")
    ''')
    for a in ("HogTronUI", "HogTron_Skin", "HogTron_Quests"):
        lua.load_addon(a)
    lua.player_login()
    lua.execute("WorldMapFrame:Show(); HogHealsQuests.WorldMap.Refresh(); HogHealsQuests.WorldMap.OnShow()")
    WM = "HogHealsQuests.WorldMap"
    assert lua.eval(f"{WM}.page ~= nil") and lua.eval(f"{WM}.page.pageTop._texture").endswith("dialog_page_light")
    assert lua.eval(f"{WM}.bg") is None                                              # no ink slab
    assert rgb(lua, "WorldMapFrame.BorderFrame.TitleContainer.TitleText._color") == light(lua, "title")
    assert lua.eval("QuestMapFrame.Background._alpha") == 0 and rgb(lua, "QuestMapFrame.Line._color") == light(lua, "text")
    assert lua.eval("WorldMapFrame.ScrollContainer.Tile._alpha") == 1                # the map itself untouched
    assert errors(lua) == []
