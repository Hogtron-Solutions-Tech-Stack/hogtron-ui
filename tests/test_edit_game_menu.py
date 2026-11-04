# Escape menu: Blizzard's "Edit Mode" button gives way to "HogTron Edit Mode" (HogTronUI/Core/GameMenu.lua).
# Sean 2026-11-03: "only put the HogTron edit mode on there". Two menu shapes: the button pool rebuilt by InitButtons
# on every open (Forever / Anniversary) and the older named-children menu.
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

POOL_MENU = '''
HUD_EDIT_MODE_MENU = "Edit Mode"
GameMenuFrame = CreateFrame("Frame", "GameMenuFrame", UIParent)
GameMenuFrame:Hide()   -- closed at login, like the client
local pool = { active = {} }
function pool:EnumerateActive() return pairs(self.active) end
GameMenuFrame.buttonPool = pool
function GameMenuFrame:InitButtons()
  self.built = (self.built or 0) + 1
  pool.active = {}
  self.byText = {}
  for _, t in ipairs({ "Edit Mode", "Options", "Logout" }) do
    local b = CreateFrame("Button", nil, self)
    b:SetText(t)
    pool.active[b] = true
    self.byText[t] = b
  end
end
'''

PLAIN_MENU = '''
HUD_EDIT_MODE_MENU = "Edit Mode"
GameMenuFrame = CreateFrame("Frame", "GameMenuFrame", UIParent)
GameMenuFrame:Hide()
GameMenuFrame.InitButtons = false   -- the mock invents any method; this menu shape has none
GameMenuButtonEditMode = CreateFrame("Button", "GameMenuButtonEditMode", GameMenuFrame)
GameMenuButtonEditMode:SetText("Edit Mode")
GameMenuButtonLogout = CreateFrame("Button", "GameMenuButtonLogout", GameMenuFrame)
GameMenuButtonLogout:SetText("Logout")
'''


def boot(lua, menu):
    lua.execute(menu)
    lua.load_addon("HogTronUI")
    lua.player_login()
    return lua


def test_pool_menu_edit_mode_button_gives_way_to_ours(lua):
    boot(lua, POOL_MENU)
    assert lua.eval("HogHeals.GameMenu.state") == "hooked via InitButtons+OnShow"
    lua.execute("GameMenuFrame:Show(); GameMenuFrame:InitButtons()")
    assert lua.eval("HogHeals.GameMenu.state") == "replaced (pool)"
    assert lua.eval('GameMenuFrame.byText["Edit Mode"]._alpha') == 0
    assert lua.eval('GameMenuFrame.byText["Edit Mode"]._last.EnableMouse[1]') is False
    assert lua.eval('GameMenuFrame.byText["Logout"]._alpha') == 1 and lua.eval('GameMenuFrame.byText["Options"]._alpha') == 1
    assert lua.eval("HogTronUIGameMenuEditButton:IsShown()") is True
    assert lua.eval("HogTronUIGameMenuEditButton:GetText()") == "HogTron Edit Mode"
    assert lua.eval("HogTronUIGameMenuEditButton:GetParent() == GameMenuFrame") is True
    assert lua.eval('HogTronUIGameMenuEditButton._points[1][2] == GameMenuFrame.byText["Edit Mode"]') is True   # its slot
    assert lua.eval("HogHeals.db.global.diag.gameMenu.how") == "pool"
    # the click: menu closes, frames unlock (= /hh unlock)
    lua.execute("HogTronUIGameMenuEditButton:Click()")
    assert lua.eval("GameMenuFrame:IsShown()") is False
    assert lua.eval("HogHeals.db.profile.locked") is False
    assert lua.eval("#HogHeals.errors") == 0


def test_rebuilt_pool_restores_the_old_button_and_mutes_the_new_one(lua):
    # a pooled button comes back under another label: alpha 0 must never stay on it
    boot(lua, POOL_MENU)
    lua.execute("GameMenuFrame:InitButtons(); OLD = GameMenuFrame.byText['Edit Mode']")
    assert lua.eval("OLD._alpha") == 0
    lua.execute("GameMenuFrame:InitButtons()")
    assert lua.eval("OLD._alpha") == 1 and lua.eval("OLD._last.EnableMouse[1]") is True
    assert lua.eval('GameMenuFrame.byText["Edit Mode"]._alpha') == 0
    assert lua.eval('HogTronUIGameMenuEditButton._points[1][2] == GameMenuFrame.byText["Edit Mode"]') is True
    assert lua.eval("HogHeals.GameMenu.applied") == 2
    assert lua.eval("#HogHeals.errors") == 0


def test_setting_off_puts_blizzards_button_back(lua):
    boot(lua, POOL_MENU)
    lua.execute("GameMenuFrame:InitButtons()")
    lua.execute("HogHeals.db.profile.edit.gameMenu = false; HogHeals.GameMenu.Apply()")
    assert lua.eval("HogHeals.GameMenu.state") == "off"
    assert lua.eval('GameMenuFrame.byText["Edit Mode"]._alpha') == 1
    assert lua.eval('GameMenuFrame.byText["Edit Mode"]._last.EnableMouse[1]') is True
    assert lua.eval("HogTronUIGameMenuEditButton:IsShown()") is False
    lua.execute("HogHeals.db.profile.edit.gameMenu = true; HogHeals.GameMenu.Apply()")
    assert lua.eval('GameMenuFrame.byText["Edit Mode"]._alpha') == 0
    assert lua.eval("HogTronUIGameMenuEditButton:IsShown()") is True


def test_menu_without_an_edit_mode_button_is_left_alone(lua):
    boot(lua, POOL_MENU.replace('"Edit Mode", ', ""))
    lua.execute("GameMenuFrame:InitButtons()")
    assert lua.eval("HogHeals.GameMenu.state").startswith("no 'Edit Mode' button (pool, 2 buttons)")
    assert lua.eval("HogTronUIGameMenuEditButton") is None
    assert lua.eval('GameMenuFrame.byText["Logout"]._alpha') == 1
    assert lua.eval("#HogHeals.errors") == 0


def test_menu_without_a_pool_uses_its_children_on_show(lua):
    boot(lua, PLAIN_MENU)
    assert lua.eval("HogHeals.GameMenu.state") == "hooked via OnShow"
    lua.execute("GameMenuFrame:Show(); GameMenuFrame:GetScript('OnShow')(GameMenuFrame)")   # mock Show() fires no OnShow
    assert lua.eval("HogHeals.GameMenu.state") == "replaced (children)"
    assert lua.eval("GameMenuButtonEditMode._alpha") == 0 and lua.eval("GameMenuButtonLogout._alpha") == 1
    assert lua.eval("HogTronUIGameMenuEditButton._points[1][2] == GameMenuButtonEditMode") is True
    assert lua.eval("#HogHeals.errors") == 0


def test_no_game_menu_frame_is_reported_not_raised(lua):
    lua.load_addon("HogTronUI")
    lua.player_login()
    assert lua.eval("HogHeals.GameMenu.state") == "no GameMenuFrame"
    lua.execute('HogHeals:SlashCommand("menudiag")')
    assert lua.eval("#HogHeals.errors") == 0


def test_menudiag_names_the_buttons(lua):
    boot(lua, POOL_MENU)
    lua.execute("GameMenuFrame:InitButtons()")
    lines = list(lua.eval("HogHeals.GameMenu.Diagnose()").values())
    assert lines[0].startswith("game menu: replaced (pool)   setting: on   applied: 1")
    assert "Edit Mode" in lines[1] and "Logout" in lines[1] and "(pool)" in lines[1]
    assert "InitButtons=function buttonPool=table" in lines[2]


def test_the_switch_sits_beside_lock_frames_in_general_and_has_a_default():
    opts = (ROOT / "HogTronUI" / "Core" / "Options.lua").read_text(encoding="utf-8")
    general = opts.split("local function generalTab()", 1)[1].split("\nend", 1)[0]
    assert re.search(r'locked = \{.*?order = 2,.*?\},\s*gameMenu = \{.*?order = 2\.5', general, re.S), "gameMenu toggle right after Lock frames"
    defaults = (ROOT / "HogTronUI" / "Core" / "Defaults.lua").read_text(encoding="utf-8")
    assert re.search(r"edit = \{[^}]*gameMenu = true", defaults)
    toc = (ROOT / "HogTronUI" / "HogTronUI.toc").read_text(encoding="utf-8")
    assert "Core\\EditMode.lua" in toc and toc.index("Core\\GameMenu.lua") > toc.index("Core\\Options.lua")
