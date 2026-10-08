# Edit mode (HogHeals/Core/EditMode.lua): /hh unlock -> click a box or a gear -> that frame's settings beside it, with
# Center horizontally / vertically saved through the frame's own drag-stop handler.
import pytest

from test_bars import CLIENT, EXTRA_CLIENT


@pytest.fixture
def ed(lua):
    lua.execute(CLIENT + EXTRA_CLIENT)
    for a in ("HogHeals", "HogHeals_Frames", "HogHeals_HUD", "HogHeals_Units", "HogHeals_Quests", "HogHeals_Skin", "HogHeals_Bars", "HogHeals_Meter"):
        lua.load_addon(a)
    lua.player_login()
    lua.execute("""
      UIParent._cx, UIParent._cy = 960, 540
      function UIParent:GetCenter() return 960, 540 end
      wipe(HogHeals.errors)
    """)
    return lua


def errors(lua):
    return [e["msg"] for e in lua.eval("HogHeals.errors").values()]


def test_unlock_lists_targets_gears_on_clickable_frames(ed):
    ed.execute('HogHeals:SlashCommand("unlock")')
    keys = [t["key"] for t in ed.eval("HogHeals.EditMode.Targets()").values()]
    for k in ("bar:1", "bar:2", "bar:pet", "frames", "hud", "tracker", "unit:player", "unit:target"):
        assert k in keys, k
    assert ed.eval("HogHeals.EditMode.cogs.tracker:IsShown()") is True
    assert ed.eval("HogHeals.EditMode.cogs['unit:player'] ~= nil")
    assert any("edit mode: click a cyan box" in m for m in ed.eval("MockLog.chat").values())
    ed.execute('HogHeals:SlashCommand("lock")')
    assert ed.eval("HogHeals.EditMode.cogs.tracker:IsShown()") is False
    assert errors(ed) == []


def test_clicking_a_bar_box_opens_its_settings_compact_beside_it(ed):
    ed.execute('HogHeals:SlashCommand("unlock")')
    h = "HogHealsBars.Bars.bars[2].handle"
    ed.execute(f'{h}:GetScript("OnMouseUp")({h}, "LeftButton")')
    P = "HogHeals.Panel"
    assert ed.eval(f"{P}.frame:IsShown()") is True and ed.eval(f"{P}.compact") is True
    assert ed.eval(f"{P}.frame._width") == 400 and ed.eval(f"{P}.frame.side:IsShown()") is False
    assert ed.eval(f"{P}.frame.version._text") == "Action bar 2"
    controls = list(ed.eval(f"{P}.controls").keys())
    assert "edit.scale" in controls and "edit.perRow" in controls                               # the bar's own options
    assert "edit.hhPosition.centerH" in controls and "edit.hhPosition.centerV" in controls
    # a drag is a drag, not a click
    ed.execute(f'{P}.frame:Hide(); {h}:GetScript("OnDragStart")({h}); {h}:GetScript("OnDragStop")({h}); {h}:GetScript("OnMouseUp")({h}, "LeftButton")')
    assert ed.eval(f"{P}.frame:IsShown()") is False
    # locked: clicks do nothing
    ed.execute(f'HogHeals:SlashCommand("lock"); {h}:GetScript("OnMouseUp")({h}, "LeftButton")')
    assert ed.eval(f"{P}.frame:IsShown()") is False
    # the full window comes back full size
    ed.execute(f"{P}.Open()")
    assert ed.eval(f"{P}.compact") is False and ed.eval(f"{P}.frame._width") == 860 and ed.eval(f"{P}.frame.side:IsShown()") is True
    assert errors(ed) == []


def test_center_horizontally_and_vertically_save_through_the_frames_own_handler(ed):
    ed.execute("""
      HogUIBar2.GetCenter = function() return 700, 120 end
      HogHealsHUDAnchor.GetCenter = function() return 900, 300 end
      HogHeals:SlashCommand("unlock")
    """)
    ed.execute("""
      for _, t in ipairs(HogHeals.EditMode.Targets()) do
        if t.key == "bar:2" then BAR2 = t elseif t.key == "hud" then HUDT = t end
      end
    """)
    assert ed.eval("HogHeals.EditMode.Center(BAR2, 'h')") is True
    bd = ed.eval("HogHeals.db.profile.bars.list[2]")
    assert bd["point"] == "CENTER" and bd["x"] == 0 and bd["y"] == -420                       # 120 - 540: kept its height
    ed.execute("HogHealsBars.Bars.Layout(HogUIBar2)")
    assert ed.eval("HogUIBar2._points[1][1]") == "CENTER" and ed.eval("HogUIBar2._points[1][4]") == 0   # lays out where it was put
    assert ed.eval("HogHeals.EditMode.Center(HUDT, 'v')") is True
    assert ed.eval("HogHeals.db.profile.hud.y") == 0 and ed.eval("HogHeals.db.profile.hud.x") == -60   # 900 - 960
    ed.execute("MockState.inCombat = true")
    assert ed.eval("(HogHeals.EditMode.Center(BAR2, 'v'))") is False
    assert errors(ed) == []


def test_a_gear_opens_the_unit_frames_settings_and_all_settings_opens_the_full_tab(ed):
    ed.execute('HogHeals:SlashCommand("unlock")')
    ed.execute("local b = HogHeals.EditMode.cogs['unit:player']; b:GetScript('OnClick')(b)")
    assert ed.eval("HogHeals.Panel.frame.version._text") == "Player frame"
    ed.execute("HogHeals.EditMode.OpenFull('Units.player')")
    assert ed.eval("HogHeals.Panel.selected") == "Units" and ed.eval("HogHeals.Panel.selectedTab") == "player"
    assert ed.eval("HogHeals.Panel.compact") is False
    assert errors(ed) == []


def test_drag_boxes_say_a_click_opens_settings(ed):
    ed.execute('HogHeals:SlashCommand("unlock")')
    assert ed.eval("HogHealsBars.Bars.bars[2].handle.label._text") == "Action bar 2  -  drag, or click for settings"
    assert ed.eval("HogHealsAnchor.label._text") == "Party / raid frames  -  drag, or click for settings"
    assert ed.eval("HogHealsHUDAnchor.label._text") == "HUD  -  drag, or click for settings"



def test_compact_window_opens_toward_the_middle_of_the_screen(ed):
    # Sean 2026-10-08: "should not open over the bars ... open towards the center of the screen"
    P = "HogHeals.Panel"
    side = lambda cx, cy, aw=0, ah=0: ed.eval(f"{P}.Side({cx}, {cy}, {aw}, {ah}, 1920, 1080)")
    assert side(960, 100, 500, 40) == "above"       # bar along the bottom -> above it
    assert side(1880, 540, 40, 500) == "left"       # bar down the right edge -> left of it
    assert side(40, 540, 40, 500) == "right"
    assert side(960, 1000, 500, 40) == "below"
    assert side(600, 400) == "right"                # unit frame left of centre, nearer the middle vertically
    assert side(960, 540) == "above"                # dead centre: ties go vertical
    assert side(960, 300, 500, 40) == "above"       # 300 from the bottom: a 460 window fits above, not below
    assert side(960, 540, 40, 1000) == "right"      # as tall as the screen: no room above, so beside it
    assert ed.eval(f"{P}.Side(nil, 1)") is None
    # live: bar 2 sits at the bottom centre -> the window hangs above it, not beside it
    ed.execute('HogHeals:SlashCommand("unlock")')
    h = "HogHealsBars.Bars.bars[2].handle"
    ed.execute(f"HogUIBar2._cx, HogUIBar2._cy = 960, 100; {h}:GetScript('OnMouseUp')({h}, 'LeftButton')")   # the mover is the bar itself
    pt = ed.eval(f"{{ {P}.frame:GetPoint() }}")
    assert ed.eval(f"{P}.side") == "above"
    assert pt[1] == "BOTTOM" and pt[3] == "TOP" and pt[4] == 0 and pt[5] == 12
    assert ed.eval(f"select(2, {P}.frame:GetPoint()) == HogUIBar2") is True
    # a frame hugging the right edge: window to its left
    ed.execute(f"{P}.frame:Hide(); HogUIBar2._cx, HogUIBar2._cy = 1880, 540; {h}:GetScript('OnMouseUp')({h}, 'LeftButton')")
    pt = ed.eval(f"{{ {P}.frame:GetPoint() }}")
    assert pt[1] == "RIGHT" and pt[3] == "LEFT" and pt[4] == -12
    # no centre known: the middle of the screen
    ed.execute(f"{P}.frame:Hide(); HogUIBar2.GetCenter = function() return nil end; {h}:GetScript('OnMouseUp')({h}, 'LeftButton')")
    assert ed.eval(f"{P}.side") is None and ed.eval(f"({P}.frame:GetPoint())") == "CENTER"
    assert errors(ed) == []
