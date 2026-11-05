# Blizzard's Quick Keybind Mode sees HogTron UI bar slots (HogTron_Bars/Bind.lua QuickEnter / QuickLeave).
# Sean 2026-11-05: "I can't quick edit my action bar keybinds."
from test_bars import xbars, errors  # noqa: F401 (fixture)

QUICK = '''
QuickKeybindFrame = CreateFrame("Frame", "QuickKeybindFrame", UIParent)
QKB = true
function KeybindFrames_InQuickKeybindMode() return QKB end
'''


def hover(lua, btn, on=True):
    lua.execute(f'{btn}:GetScript("{"OnEnter" if on else "OnLeave"}")({btn})')


def test_hovering_a_slot_in_quick_keybind_mode_hands_blizzard_the_button_and_its_command(xbars):
    xbars.execute(QUICK)
    b = "HogUIBar1Button1"
    assert xbars.eval(f"{b}.hhQuickHooked") is True
    hover(xbars, b)
    assert xbars.eval(f"QuickKeybindFrame.mouseOverButton == {b}") is True
    assert xbars.eval(f"{b}.commandName") == "ACTIONBUTTON1"
    hover(xbars, b, on=False)
    assert xbars.eval("QuickKeybindFrame.mouseOverButton") is None
    # the pet bar's buttons hand over their own binding name
    p = "HogUIPetBar.buttons[2]"
    hover(xbars, p)
    assert xbars.eval(f"QuickKeybindFrame.mouseOverButton == {p}") is True and xbars.eval(f"{p}.commandName") == "BONUSACTIONBUTTON2"
    hover(xbars, p, on=False)
    assert xbars.eval("HogHealsBars.Bind.quickEntered") == 2
    assert errors(xbars) == []


def test_outside_the_mode_nothing_is_handed_over(xbars):
    xbars.execute(QUICK + "QKB = false")
    hover(xbars, "HogUIBar1Button1")
    assert xbars.eval("QuickKeybindFrame.mouseOverButton") is None
    assert xbars.eval("HogHealsBars.Bind.quickEntered") is None
    xbars.execute("KeybindFrames_InQuickKeybindMode = nil; QuickKeybindFrame = nil")
    hover(xbars, "HogUIBar1Button1")                                            # a client without the mode: no error
    assert errors(xbars) == []


def test_blizzards_setter_methods_are_used_when_the_frame_has_them(xbars):
    xbars.execute(QUICK + '''
      SETS = {}
      function QuickKeybindFrame:SetMouseOverButton(b) SETS[#SETS + 1] = { "set", b:GetName() } self.mouseOverButton = b end
      function QuickKeybindFrame:ClearMouseOverButton(b) SETS[#SETS + 1] = { "clear", b:GetName() } self.mouseOverButton = nil end
    ''')
    hover(xbars, "HogUIBar1Button3"); hover(xbars, "HogUIBar1Button3", on=False)
    assert [list(v.values()) for v in xbars.eval("SETS").values()] == [["set", "HogUIBar1Button3"], ["clear", "HogUIBar1Button3"]]
    assert errors(xbars) == []
