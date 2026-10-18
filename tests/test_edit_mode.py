# Edit mode (HogHeals/Core/EditMode.lua): /hh unlock -> click a box or a gear -> that frame's settings beside it, with
# Center horizontally / vertically saved through the frame's own drag-stop handler.
import pytest

from test_bars import CLIENT, EXTRA_CLIENT


@pytest.fixture
def ed(lua):
    lua.execute(CLIENT + EXTRA_CLIENT)
    for a in ("HogTronUI", "HogHeals_Frames", "HogTron_HUD", "HogTron_Units", "HogTron_Quests", "HogTron_Skin", "HogTron_Bars", "HogTron_Meter"):
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
    # the HUD strip: a gear (its bars' own boxes cover it - Sean 2026-10-18), each bar a labelled box
    assert ed.eval("HogHeals.EditMode.cogs.hud:IsShown()") is True
    assert ed.eval("HogHeals.EditMode.boxes['hud:castbar'].label._text") == "Cast bar"



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
def test_the_frames_settings_carry_test_buttons_in_the_footer(ed):
    ed.execute('HogHeals:SlashCommand("unlock")')
    ed.execute("HogHeals.EditMode.Open((function() for _, t in ipairs(HogHeals.EditMode.Targets()) do if t.key == 'frames' then return t end end end)())")
    P = "HogHeals.Panel"
    assert ed.eval(f"{P}.frame.footer:IsShown()") is True
    labels = [ed.eval(f"{P}.frame.footer.buttons[{i}].label:GetText()") for i in (1, 2, 3)]
    assert labels == ["Test 5", "Test 25", "Stop test"]
    ed.execute(f"{P}.frame.footer.buttons[1]:Click()")
    assert ed.eval("HogHealsFrames.TestMode.active") is True
    ed.execute(f"{P}.frame.footer.buttons[3]:Click()")
    assert ed.eval("HogHealsFrames.TestMode.active") is not True
    assert ed.eval(f"{P}.ActionsFor('plates')") is None
    assert errors(ed) == []



# ---------------------------------------------------------------- sizes in /hh unlock (Sean 2026-10-18)
# "Do we have a way right now to easily change the size of the cast bar, the manabar, different things? Can we add all
# of that to HH unlock?" - each HUD bar is its own box (click = its size), and a corner grip resizes by dragging.
def target(ed, key):
    ed.execute(f'for _, t in ipairs(HogHeals.EditMode.Targets()) do if t.key == "{key}" then HH_T = t end end')
    return "HH_T"


def test_each_hud_bar_is_its_own_box_with_its_own_size_settings(ed):
    ed.execute('HogHeals:SlashCommand("unlock")')
    keys = [t["key"] for t in ed.eval("HogHeals.EditMode.Targets()").values()]
    for k in ("hud:castbar", "hud:swing", "hud:mana", "hud:info"):
        assert k in keys, k
        assert ed.eval(f"HogHeals.EditMode.boxes['{k}']:IsShown()") is True
        assert ed.eval(f"HogHeals.EditMode.grips['{k}']:IsShown()") is True
    b = "HogHeals.EditMode.boxes['hud:castbar']"
    ed.execute(f'{b}:GetScript("OnMouseUp")({b}, "LeftButton")')
    controls = list(ed.eval("HogHeals.Panel.controls").keys())
    assert "edit.width" in controls and "edit.height" in controls                 # the cast bar's own width + height
    assert errors(ed) == []


def test_dragging_a_bars_box_moves_the_whole_strip(ed):
    ed.execute('HogHeals:SlashCommand("unlock")')
    b = "HogHeals.EditMode.boxes['hud:mana']"
    ed.execute(f'HH_moved = 0; HogHealsHUDAnchor.StartMoving = function() HH_moved = HH_moved + 1 end; {b}:GetScript("OnDragStart")({b})')
    assert ed.eval("HH_moved") == 1
    ed.execute(f'{b}:GetScript("OnDragStop")({b}); {b}:GetScript("OnMouseUp")({b}, "LeftButton")')
    assert ed.eval("HogHeals.Panel.frame == nil or not HogHeals.Panel.frame:IsShown()") is True   # a drag is not a click
    assert errors(ed) == []


def test_the_grip_resizes_the_cast_bar_wider_and_taller(ed):
    ed.execute('HogHeals:SlashCommand("unlock"); HogHeals.db.profile.hud.width = 300; HogHeals.db.profile.hud.castbarHeight = 18')
    t = target(ed, "hud:castbar")
    ed.execute(f'{t}.resize = HogHeals.EditMode.ResizeFor({t}); HogHeals.EditMode.BeginResize({t})')
    ed.execute('HogHeals.EditMode.ResizeStep(20, -5)')                           # 20 right, 5 down
    d = "HogHeals.db.profile.hud"
    assert ed.eval(f"{d}.castbar.width") == 340                                  # grows both ways from the centre
    assert ed.eval(f"{d}.castbarHeight") == 23
    assert ed.eval("HogHealsHUD.HUD.rows.castbar:GetWidth()") == 340             # applied live
    ed.execute('HogHeals.EditMode.ResizeStep(-1000, 1000)')                      # clamped to the range
    assert ed.eval(f"{d}.castbar.width") == 60 and ed.eval(f"{d}.castbarHeight") == 4
    ed.execute('HogHeals.EditMode.EndResize()')
    assert ed.eval("HogHeals.EditMode.resizing") is None and ed.eval("HogHeals.EditMode.lastResize") == "hud:castbar"
    assert errors(ed) == []


def test_the_grip_resizes_unit_frames_and_scales_action_bars_out_of_combat(ed):
    ed.execute('HogHeals:SlashCommand("unlock")')
    t = target(ed, "unit:player")
    ed.execute(f'{t}.resize = HogHeals.EditMode.ResizeFor({t}); HogHeals.EditMode.BeginResize({t}); HogHeals.EditMode.ResizeStep(10, -10); HogHeals.EditMode.EndResize()')
    u = "HogHeals.db.profile.units.player"
    assert ed.eval(f"{u}.width") == 260 and ed.eval(f"{u}.height") == 52       # 240 + 2x10, 42 + 10
    t = target(ed, "bar:1")
    ed.execute(f'{t}.resize = HogHeals.EditMode.ResizeFor({t}); HogHeals.db.profile.bars.list[1].scale = 1')
    ed.execute(f'HogHeals.EditMode.BeginResize({t}); HogHeals.EditMode.ResizeStep(HogHeals.EditMode.resizing.ref / 2, 0); HogHeals.EditMode.EndResize()')
    assert ed.eval("HogHeals.db.profile.bars.list[1].scale") == 1.5
    # in combat: refused (bars and unit frames are secure)
    ed.execute(f'MockState.inCombat = true; HH_ok = HogHeals.EditMode.BeginResize({t}); MockState.inCombat = false')
    assert ed.eval("HH_ok") is False and ed.eval("HogHeals.EditMode.resizing") is None
    assert errors(ed) == []


def test_locking_hides_every_box_and_grip(ed):
    ed.execute('HogHeals:SlashCommand("unlock")')
    assert ed.eval("HogHeals.EditMode.grips['unit:player']:IsShown()") is True
    ed.execute('HogHeals:SlashCommand("lock")')
    for k in ("hud:castbar", "hud:mana"):
        assert ed.eval(f"HogHeals.EditMode.boxes['{k}']:IsShown()") is False
    assert ed.eval("HogHeals.EditMode.grips['unit:player']:IsShown()") is False
    assert ed.eval("HogHeals.EditMode.grips['hud:castbar']:IsShown()") is False
    assert errors(ed) == []


def test_the_party_frames_grip_resizes_the_cells_of_the_current_layout(ed):
    # backlog 2026-10-18: party / raid frames size per group layout (solo shares party's by default)
    ed.execute('HogHeals:SlashCommand("unlock")')
    assert ed.eval("HogHeals.EditMode.grips.frames:IsShown()") is True
    t = target(ed, "frames")
    ed.execute(f'HH_lay = HogHealsFrames.module:LayoutFor(); HH_w, HH_h = HH_lay.width, HH_lay.height')
    ed.execute(f'{t}.resize = HogHeals.EditMode.ResizeFor({t}); HogHeals.EditMode.BeginResize({t}); HogHeals.EditMode.ResizeStep(12, -6); HogHeals.EditMode.EndResize()')
    assert ed.eval("HogHealsFrames.module:LayoutFor().width") == ed.eval("HH_w") + 12
    assert ed.eval("HogHealsFrames.module:LayoutFor().height") == ed.eval("HH_h") + 6
    ed.execute(f'HogHeals.EditMode.BeginResize({t}); HogHeals.EditMode.ResizeStep(-1000, 1000); HogHeals.EditMode.EndResize()')
    assert ed.eval("HogHealsFrames.module:LayoutFor().width") == 40 and ed.eval("HogHealsFrames.module:LayoutFor().height") == 12
    assert errors(ed) == []
