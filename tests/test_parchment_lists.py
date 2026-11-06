"""Lists on the light page (HogTron_Skin/Panels.lua Part.Row / Part.Lists / Part.InkText, HogTronUI/Core/Parchment.lua
InkCodes). Sean 2026-11-05 in game, the friends list on paper: "Like, what is this?" - BNet names in Blizzard's light
blue, "Baddie Xo" gold, "Lvl 18" white, "Shaman" class blue, all on the light page. Forever's rows carry no
"background" key, so the row pass skipped them, and colour codes inside the text overrode any inked colour."""
from test_parchment_own_frames import boot, errors, rgb, light

P = "HogHeals.Parchment"

LIST = r'''
local f = FriendsFrame
f:SetSize(340, 420)
local box = CreateFrame("Frame", "FriendsListFrameScrollBox", f)
box.rows = {}
function box:ForEachFrame(fn) for _, r in ipairs(self.rows) do fn(r, {}) end end
function box:Update() for _, r in ipairs(self.rows) do if r.paint then r:paint() end end end
local function row(i)
  local b = CreateFrame("Button", nil, box) b:SetSize(298, 46)
  b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.info = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.zone = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  function b:paint()
    self.name:SetText("Dane") self.name:SetTextColor(0.51, 0.77, 1)
    self.info:SetText("|cffffd100Baddie Xo|r Lvl 18 |cff0070ddShaman|r") self.info:SetTextColor(1, 1, 1)
    self.zone:SetText("Darkshore") self.zone:SetTextColor(0.5, 0.5, 0.5)
  end
  b:paint()
  box.rows[#box.rows + 1] = b
  return b
end
ROW1 = row(1)
HEAD = CreateFrame("Button", nil, box) HEAD:SetSize(298, 22)
HEAD.label = HEAD:CreateFontString(nil, "OVERLAY", "GameFontNormal")
HEAD.label:SetText("Favorites 1/1") HEAD.label:SetTextColor(0.9, 0.9, 0.9)
box.rows[#box.rows + 1] = HEAD
function MakeRow() return row(#box.rows + 1) end
'''


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def inked(page):
    page.execute("MockAdvance(1)")


def setup(lua, style=None):
    from test_skin_windows import WINDOW
    lua.execute(WINDOW)
    boot(lua, style)
    lua.execute(LIST + "ShowUIPanel(FriendsFrame); MockAdvance(1)")
    return lua


# ------------------------------------------------------------------------------------------------ the codes, pure

def test_codes_inside_text_are_inked_and_everything_else_is_kept(lua):
    boot(lua)
    s = lua.eval(f'({P}.InkCodes("|cffffd100Baddie Xo|r Lvl 18 |cFF0070DDShaman|r |Kq12|k |Tstar:0|t"))')
    assert "ffd100" not in s and "0070dd" not in s.lower()                    # gold and class blue brought down
    assert "|Kq12|k" in s and "|Tstar:0|t" in s and s.count("|r") == 2
    assert lua.eval(f'({P}.InkCodes("{s}"))') == s                               # a second pass changes nothing
    white = lua.eval(f'({P}.InkCodes("|cffffffffhi|r"))')
    t = [round(v, 2) for v in lua.eval(f"{P}.THEMES.light.text").values()][:3]
    assert white == "|cff" + "".join(f"{int(v * 255 + 0.5):02x}" for v in t) + "hi|r"   # white -> the page's ink
    lua.execute('NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0, GetRGB = function(c) return c.r, c.g, c.b end }')
    named = lua.eval(f'({P}.InkCodes("|cnNORMAL_FONT_COLOR:Lvl|r and |cnNO_SUCH_COLOR:x|r"))')
    assert named.startswith("|cff") and "|cnNO_SUCH_COLOR:x|r" in named
    assert lua.eval(f'({P}.InkCodes("plain"))') == "plain"


# ------------------------------------------------------------------------------------------------ the friends list

def test_friends_rows_without_a_background_key_are_inked_codes_and_all(lua):
    page = setup(lua)
    name = rgb(page, "ROW1.name._color")
    assert name[2] > name[0] and lum(name) < 0.36                             # BNet blue, inked
    assert rgb(page, "ROW1.info._color") == light(page, "text")                # "Lvl 18" white -> ink
    info = page.eval("ROW1.info._text")
    assert "ffd100" not in info and "0070dd" not in info.lower() and "Baddie Xo" in info
    assert rgb(page, "ROW1.zone._color") == light(page, "muted")               # grey zone -> muted ink
    assert page.eval("ROW1.name._last.SetShadowOffset[1]") == 0
    assert rgb(page, "HEAD.label._color") == [0.9, 0.9, 0.9]                   # a one-line header reads on its own bar
    assert errors(page) == []


def test_a_repaint_and_a_row_made_later_are_inked_again(lua):
    page = setup(lua)
    page.execute("ROW1:paint()")                                               # Blizzard repaints the row
    assert "ffd100" not in page.eval("ROW1.info._text")
    assert lum(rgb(page, "ROW1.name._color")) < 0.36
    page.execute("R2 = MakeRow(); FriendsListFrameScrollBox:Update()")         # scrolled: a recycled / new row
    assert lum(rgb(page, "R2.name._color")) < 0.36 and "ffd100" not in page.eval("R2.info._text")
    d = page.eval("HogHeals.db.global.diag.skin.lists.FriendsFrame")
    assert d["boxes"] == 1 and d["rows"] >= 1
    assert errors(page) == []


def test_the_older_friends_list_is_inked_through_its_row_function(lua):
    from test_skin_windows import WINDOW
    lua.execute(WINDOW)
    lua.execute('''
      FriendsFrame_UpdateFriendButton = function(b)
        b.name:SetText("Mark") b.name:SetTextColor(0.51, 0.77, 1)
        b.info:SetText("|cffffd100Mark Priest|r Lvl 10") b.info:SetTextColor(1, 1, 1)
      end''')
    boot(lua)
    lua.execute('''
      FriendsFrame:SetSize(340, 420)
      OLD = CreateFrame("Button", "FriendsFrameFriendsScrollFrameButton1", FriendsFrame) OLD:SetSize(298, 34)
      OLD.name = OLD:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      OLD.info = OLD:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      ShowUIPanel(FriendsFrame); MockAdvance(1)
      FriendsFrame_UpdateFriendButton(OLD)''')
    assert lua.eval("HogHealsSkin.Panels.friendRowsHooked") is True
    assert lum(rgb(lua, "OLD.name._color")) < 0.36 and "ffd100" not in lua.eval("OLD.info._text")
    assert errors(lua) == []


def test_plain_buttons_and_item_slots_keep_their_labels(lua):
    page = setup(lua)
    page.execute('''
      ADD = CreateFrame("Button", "FriendsFrameAddFriendButton2", FriendsFrame) ADD:SetSize(131, 22)
      ADD.label = ADD:CreateFontString(nil, "OVERLAY", "GameFontNormal") ADD.label:SetTextColor(1, 0.82, 0)
      SLOT = CreateFrame("Button", "FriendsFrameSlot1", FriendsFrame) SLOT:SetSize(37, 37)
      SLOT.Count = SLOT:CreateFontString(nil, "OVERLAY", "GameFontNormal") SLOT.Count:SetTextColor(1, 1, 1)
      SLOT.HotKey = SLOT:CreateFontString(nil, "OVERLAY", "GameFontNormal") SLOT.HotKey:SetTextColor(0.6, 0.6, 0.6)
      HogHealsSkin.Panels.Inner(FriendsFrame, "FriendsFrame")''')
    assert rgb(page, "ADD.label._color") == [1, 0.82, 0]                       # one label on its own art
    assert rgb(page, "SLOT.Count._color") == [1, 1, 1]                         # a count on an item icon
    assert errors(page) == []


def test_a_secret_text_is_never_read(lua):
    page = setup(lua)
    page.execute('''MockSetSecrets(true)
      ROW1.info:SetText(MockSecret("|cffffd100Secret|r"))''')
    assert errors(page) == []


def test_modern_leaves_lists_alone(lua):
    page = setup(lua, "hogtron")
    assert rgb(page, "ROW1.name._color") == [0.51, 0.77, 1]
    assert "ffd100" in page.eval("ROW1.info._text")
    assert errors(page) == []
