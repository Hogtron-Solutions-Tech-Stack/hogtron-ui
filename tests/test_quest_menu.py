# Right-click menu on a tracker quest (HogHeals_Quests/Menu.lua): watch, open, point, share, abandon-with-confirm.
# Left-click still opens the quest log; shift-click still toggles watch. Sean in game, 2026-10-08.
import pytest

from test_quests import MODERN, boot, errors

M = "HogHealsQuests.Menu"
T = "HogHealsQuests.Tracker"

MENU_API = '''
MENU = nil
MenuUtil = { CreateContextMenu = function(owner, gen)
  local root = { buttons = {} }
  function root:CreateTitle(t) self.title = t end
  function root:CreateButton(t, f) self.buttons[#self.buttons + 1] = { text = t, func = f } end
  gen(owner, root)
  MENU = root
end }
POPUP = nil
StaticPopupDialogs = {}
function StaticPopup_Show(which, a1, a2, data) POPUP = { which = which, arg = a1, data = data } end
ABANDONED, SELECTED, PUSHED, TRACKED = nil, nil, nil, nil
C_QuestLog.SetSelectedQuest = function(id) SELECTED = id end
C_QuestLog.SetAbandonQuest = function() end
C_QuestLog.AbandonQuest = function() ABANDONED = SELECTED end
function QuestLogPushQuest() PUSHED = SELECTED end
C_SuperTrack = { SetSuperTrackedQuestID = function(id) TRACKED = id end }
GROUPED = false
function IsInGroup() return GROUPED end
'''


@pytest.fixture
def menu(lua):
    boot(lua, MODERN + MENU_API)
    lua.execute(f"{T}.Update()")
    return lua


def test_items_pure(menu):
    items = [v["text"] for v in menu.eval(f'{M}.Items({{ title = "X", watched = false }}, {{ grouped = true }})').values()]
    assert items == ["Watch", "Open in quest log", "Point the arrow at it", "Share with party", "Abandon..."]
    items = [v["text"] for v in menu.eval(f'{M}.Items({{ watched = true }}, {{ grouped = false, canPoint = false, canAbandon = false }})').values()]
    assert items == ["Stop watching", "Open in quest log"]


def test_right_click_opens_the_menu_left_click_the_log_shift_click_toggles(menu):
    menu.execute('OPENED = nil; function QuestMapFrame_OpenToQuestDetails(id) OPENED = id end')
    menu.execute(f'{T}.titles[1]:Click("RightButton")')
    assert menu.eval("MENU.title") == "Kobold Camp Cleanup" and menu.eval(f"{M}.path") == "MenuUtil"
    texts = [b["text"] for b in menu.eval("MENU.buttons").values()]
    assert texts == ["Stop watching", "Open in quest log", "Point the arrow at it", "Abandon..."]   # watched, solo
    assert menu.eval("QWatched[7]") == 1                                                          # a right-click no longer toggles
    menu.execute(f'{T}.titles[1]:Click("LeftButton")')
    assert menu.eval("OPENED") == 7
    menu.execute(f'function IsShiftKeyDown() return true end; {T}.titles[1]:Click("RightButton"); IsShiftKeyDown = function() return false end')
    assert menu.eval("QWatched[7]") is None
    assert errors(menu) == []


def test_menu_actions(menu):
    menu.execute(f'{T}.titles[1]:Click("RightButton")')
    q = f"{T}.titles[1].quest"
    menu.execute("MENU.buttons[1].func()")                  # Stop watching
    assert menu.eval("QWatched[7]") is None
    menu.execute("MENU.buttons[3].func()")                  # Point the arrow
    assert menu.eval("TRACKED") == 7
    menu.execute(f'GROUPED = true; {T}.Update(); {T}.titles[1]:Click("RightButton")')
    texts = [b["text"] for b in menu.eval("MENU.buttons").values()]
    assert "Share with party" in texts
    menu.execute("MENU.buttons[4].func()")                  # Share
    assert menu.eval("PUSHED") == menu.eval(f"{q}.id")
    assert errors(menu) == []


def test_abandon_asks_first_then_abandons_on_accept(menu):
    menu.execute(f'{T}.titles[1]:Click("RightButton"); MENU.buttons[4].func()')   # Abandon... (solo: 4th)
    assert menu.eval("POPUP.which") == "HOGHEALS_ABANDON_QUEST" and menu.eval("POPUP.arg") == "Kobold Camp Cleanup"
    assert menu.eval("ABANDONED") is None                                         # nothing yet
    menu.execute('StaticPopupDialogs.HOGHEALS_ABANDON_QUEST.OnAccept(nil, POPUP.data)')
    assert menu.eval("ABANDONED") == 7
    assert menu.eval(f"{M}.seen.abandoned") == 1


def test_abandon_without_a_confirm_dialog_refuses(menu):
    menu.execute(f'StaticPopup_Show = nil; {T}.titles[1]:Click("RightButton"); MENU.buttons[4].func()')
    assert menu.eval("ABANDONED") is None
    assert any("no confirm dialog" in m for m in menu.eval("MockLog.chat").values())


def test_legacy_easymenu_path(lua):
    boot(lua, MODERN + MENU_API + '''
      MenuUtil = nil
      EASY = nil
      function EasyMenu(list, frame, anchor) EASY = { list = list, anchor = anchor } end
    ''')
    lua.execute(f'{T}.Update(); {T}.titles[1]:Click("RightButton")')
    assert lua.eval(f"{M}.path") == "EasyMenu" and lua.eval("EASY.anchor") == "cursor"
    assert lua.eval("EASY.list[1].isTitle") is True and lua.eval("EASY.list[2].text") == "Stop watching"
    lua.execute("EASY.list[2].func()")
    assert lua.eval("QWatched[7]") is None


def test_no_menu_system_falls_back_to_toggling_watch(lua):
    boot(lua, MODERN + "MenuUtil = nil; EasyMenu = nil; UIDropDownMenu_Initialize = nil")
    lua.execute(f'{T}.Update(); {T}.titles[1]:Click("RightButton")')
    assert lua.eval(f"{M}.path") == "none" and lua.eval("QWatched[7]") is None
    assert errors(lua) == []
