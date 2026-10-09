# Addon-button drawer (HogHeals_Quests/Buttons.lua): every addon's minimap icon gathered under one HogTron UI button.
# Blizzard's buttons are left alone; owners that move their button back are caught; turning it off hands them back.
import pytest

from test_quests import MODERN, boot, errors

# Blizzard's buttons, two LibDBIcon addons, one old hand-named button, a backdrop and a protected one.
# (The HogHeals core registers its own hidden "HogHeals" LibDBIcon button on top of these.)
MINIMAP = MODERN + r'''
MiniMapTracking = CreateFrame("Button", "MiniMapTracking", Minimap)
MiniMapMailFrame = CreateFrame("Button", "MiniMapMailFrame", Minimap)
GameTimeFrame = CreateFrame("Button", "GameTimeFrame", Minimap)
MinimapBackdrop = CreateFrame("Frame", "MinimapBackdrop", Minimap)
local icon = LibStub("LibDBIcon-1.0")
icon:Register("Details", { icon = "Interface\\Icons\\INV_Misc_Note_01" }, {})
icon:Register("Bagnon", { icon = "Interface\\Icons\\INV_Misc_Bag_08" }, {})
OldAddonMinimapButton = CreateFrame("Button", "OldAddonMinimapButton", MinimapBackdrop)
OldAddonMinimapButton:SetSize(33, 33)
OldAddonMinimapButton:SetPoint("CENTER", Minimap, "CENTER", -60, 10)
ProtMinimapButton = CreateFrame("Button", "ProtMinimapButton", Minimap, "SecureActionButtonTemplate")
BuffButton3 = CreateFrame("Button", "BuffButton3", Minimap)
'''

EXPECTED = ["LibDBIcon10_Bagnon", "LibDBIcon10_Details", "LibDBIcon10_HogHeals", "OldAddonMinimapButton"]


def names(lua):
    return list(lua.eval('HogHealsQuests.Buttons.Names()').values())


def test_collects_addon_buttons_and_leaves_blizzard_alone(lua):
    boot(lua, MINIMAP)
    assert lua.eval('HogHeals.db.profile.quests.buttons.enabled') is True
    assert names(lua) == EXPECTED
    # addon buttons live in the drawer now, Blizzard's and the protected one where they were
    assert lua.eval('LibDBIcon10_Bagnon:GetParent() == HogHealsMinimapDrawer')
    assert lua.eval('OldAddonMinimapButton:GetParent() == HogHealsMinimapDrawer')
    assert lua.eval('MiniMapTracking:GetParent() == Minimap')
    assert lua.eval('GameTimeFrame:GetParent() == Minimap')
    assert lua.eval('ProtMinimapButton:GetParent() == Minimap')
    assert lua.eval('BuffButton3:GetParent() == Minimap')
    skipped = lua.eval('table.concat(HogHealsQuests.Buttons.skipped, ",")')
    assert "MiniMapTracking:blizzard" in skipped and "ProtMinimapButton:protected" in skipped and "BuffButton3:numbered" in skipped
    # the launcher sits left of the ink minimap frame's bottom corner; the drawer opens leftward from it and starts closed
    assert lua.eval('HogHealsMinimapButtons._points[1][2] == HogHealsMinimapFrame')
    assert lua.eval('HogHealsMinimapButtons._points[1][1]') == "BOTTOMRIGHT" and lua.eval('HogHealsMinimapButtons._points[1][3]') == "BOTTOMLEFT"
    assert lua.eval('HogHealsMinimapDrawer._points[1][1]') == "BOTTOMRIGHT" and lua.eval('HogHealsMinimapDrawer._points[1][3]') == "BOTTOMLEFT"
    assert lua.eval('HogHealsMinimapDrawer._points[1][2] == HogHealsMinimapButtons')
    # icons draw ABOVE the drawer: LibDBIcon pinned them at level 8, which the drawer sits over (in game 2026-10-01
    # the cells lit up and the tooltips worked but no icon was visible)
    assert lua.eval('LibDBIcon10_Bagnon:GetFrameLevel()') > lua.eval('HogHealsMinimapDrawer:GetFrameLevel()')
    assert lua.eval('LibDBIcon10_Bagnon._last.SetFixedFrameLevel[1]') is False
    assert lua.eval('LibDBIcon10_Bagnon._last.SetFixedFrameStrata[1]') is False
    # the logo: two cream uprights and a cyan crossbar
    assert lua.eval('#HogHealsMinimapButtons.logo') == 2 and lua.eval('HogHealsMinimapButtons.logo[1]._color[1]') == pytest.approx(0.96)
    assert lua.eval('HogHealsMinimapButtons.cross._color[2]') == pytest.approx(0.83)
    assert lua.eval('HogHealsMinimapButtons:IsShown()') is True
    assert lua.eval('HogHealsMinimapDrawer:IsShown()') is False
    assert errors(lua) == []


def test_grid_lays_out_shown_buttons_only_and_follows_show_hide(lua):
    boot(lua, MINIMAP)
    lua.execute('HogHeals.db.profile.quests.buttons.hogui = false')   # this test is about the icon grid; our entries (test_tray) off
    lua.execute('HogHeals.db.profile.quests.buttons.columns = 2; HogHeals.db.profile.quests.buttons.size = 28')
    assert lua.eval('HogHealsQuests.Buttons.Layout()') == 3          # HogHeals' own icon is hidden by default
    scale = lua.eval('LibDBIcon10_Bagnon._last.SetScale[1]')
    assert scale == pytest.approx(28 / 31)
    # the drawer opens leftward: cells fill from the BOTTOM RIGHT, so x offsets run negative and rows stack upward
    # sorted by name: Bagnon (0,0), Details (1,0), Old (0,1) - offsets are in the button's own scaled units
    assert lua.eval('LibDBIcon10_Bagnon._points[1][1]') == "BOTTOMRIGHT"
    assert lua.eval('LibDBIcon10_Bagnon._points[1][4]') * scale == pytest.approx(-4)
    assert lua.eval('LibDBIcon10_Details._points[1][4]') * scale == pytest.approx(-(4 + 32))
    old_scale = lua.eval('OldAddonMinimapButton._last.SetScale[1]')
    assert old_scale == pytest.approx(28 / 33)
    assert lua.eval('OldAddonMinimapButton._points[1][4]') * old_scale == pytest.approx(-4)
    assert lua.eval('OldAddonMinimapButton._points[1][5]') * old_scale == pytest.approx(4 + 32)
    # a lighter cell under every shown icon, none under the hidden one
    assert lua.eval('#HogHealsQuests.Buttons.cells') == 3
    assert lua.eval('HogHealsQuests.Buttons.cells[1]._color[1]') == pytest.approx(0.17)
    assert lua.eval('HogHealsQuests.Buttons.cells[1]._points[1][4]') == -4 and lua.eval('HogHealsQuests.Buttons.cells[1]._width') == 28
    assert lua.eval('HogHealsMinimapDrawer:GetWidth()') == 4 + 2 * 32
    assert lua.eval('HogHealsMinimapDrawer:GetHeight()') == 4 + 2 * 32
    # the owner shows a hidden button: the Show hook re-lays the grid without being asked
    lua.execute('LibStub("LibDBIcon-1.0"):Show("HogHeals")')
    assert lua.eval('HogHealsQuests.Buttons.shown') == 4
    # sorted again: Bagnon, Details, HogHeals, Old -> HogHeals takes (0,1) and Old moves to (1,1)
    assert lua.eval('LibDBIcon10_HogHeals._points[1][4]') * scale == pytest.approx(-4)
    assert lua.eval('LibDBIcon10_HogHeals._points[1][5]') * scale == pytest.approx(4 + 32)
    assert lua.eval('OldAddonMinimapButton._points[1][4]') * old_scale == pytest.approx(-(4 + 32))
    assert lua.eval('#HogHealsQuests.Buttons.cells') == 4 and lua.eval('HogHealsQuests.Buttons.cells[4]:IsShown()') is True
    assert errors(lua) == []


def test_owner_moving_or_reparenting_its_button_is_put_back_on_the_grid(lua):
    boot(lua, MINIMAP)
    # LibDBIcon re-anchors to the minimap rim on login / Refresh
    lua.execute('LibDBIcon10_Bagnon:ClearAllPoints(); LibDBIcon10_Bagnon:SetPoint("CENTER", Minimap, "CENTER", 50, 50)')
    assert lua.eval('LibDBIcon10_Bagnon._points[1][1]') == "BOTTOMRIGHT"
    assert lua.eval('LibDBIcon10_Bagnon._points[1][2] == HogHealsMinimapDrawer')
    lua.execute('OldAddonMinimapButton:SetParent(Minimap)')
    assert lua.eval('OldAddonMinimapButton:GetParent() == HogHealsMinimapDrawer')
    assert errors(lua) == []


def test_ring_art_hidden_drag_disabled_and_everything_restored_when_turned_off(lua):
    boot(lua, MINIMAP)
    assert lua.eval('LibDBIcon10_Bagnon.overlay:IsShown()') is False
    assert lua.eval('LibDBIcon10_Bagnon.background:IsShown()') is False
    assert lua.eval('LibDBIcon10_Bagnon.icon:IsShown()') is True
    assert lua.eval('LibDBIcon10_Bagnon:GetScript("OnDragStart")') is None
    lua.execute('HogHeals.db.profile.quests.buttons.enabled = false; HogHealsQuests.Buttons.Refresh()')
    assert names(lua) == []
    assert lua.eval('LibDBIcon10_Bagnon:GetParent() == Minimap')
    assert lua.eval('OldAddonMinimapButton:GetParent() == MinimapBackdrop')
    assert lua.eval('LibDBIcon10_Bagnon.overlay:IsShown()') is True
    assert lua.eval('LibDBIcon10_Bagnon:GetScript("OnDragStart")') is not None
    assert lua.eval('LibDBIcon10_Bagnon._last.SetScale[1]') == 1
    assert lua.eval('LibDBIcon10_Bagnon._last.SetFixedFrameLevel[1]') is True      # pinned again, as the library had it
    assert lua.eval('LibDBIcon10_Bagnon:GetFrameLevel()') == 8
    p = lua.eval('LibDBIcon10_Bagnon._points[1]')
    assert p[1] == "CENTER" and p[4] == 52 and p[5] == 52
    assert lua.eval('HogHealsMinimapButtons:IsShown()') is False
    # and back on again: collected once more, no doubled hooks, no errors
    lua.execute('HogHeals.db.profile.quests.buttons.enabled = true; HogHealsQuests.Buttons.Refresh()')
    assert names(lua) == EXPECTED
    lua.execute('LibDBIcon10_Bagnon:SetPoint("CENTER", Minimap, "CENTER", 1, 1)')
    assert lua.eval('LibDBIcon10_Bagnon._points[1][2] == HogHealsMinimapDrawer')
    assert errors(lua) == []


def test_buttons_made_after_login_are_collected(lua):
    boot(lua, MINIMAP)
    # LibDBIcon announces its own
    lua.execute('LibStub("LibDBIcon-1.0"):Register("LateAddon", { icon = "x" }, {})')
    assert "LibDBIcon10_LateAddon" in names(lua)
    # hand-made ones are picked up by the sweeps after login
    lua.execute('AnotherMinimapButton = CreateFrame("Button", "AnotherMinimapButton", Minimap)')
    assert "AnotherMinimapButton" not in names(lua)
    lua.execute('MockAdvance(3)')
    assert "AnotherMinimapButton" in names(lua)
    assert errors(lua) == []


def test_click_slash_hover_and_close_on_mouse_out(lua):
    boot(lua, MINIMAP)
    lua.execute('HogHealsMinimapButtons:GetScript("OnClick")(HogHealsMinimapButtons, "LeftButton")')
    assert lua.eval('HogHealsMinimapDrawer:IsShown()') is True
    lua.execute('HogHeals:SlashCommand("buttons")')
    assert lua.eval('HogHealsMinimapDrawer:IsShown()') is False
    lua.execute('HogHeals:SlashCommand("buttons list")')              # prints, no error
    # right-click opens the HogTron UI options window
    lua.execute('HogHealsMinimapButtons:GetScript("OnClick")(HogHealsMinimapButtons, "RightButton")')
    # hover-open is an opt-in
    lua.execute('HogHealsMinimapButtons:GetScript("OnEnter")(HogHealsMinimapButtons)')
    assert lua.eval('HogHealsMinimapDrawer:IsShown()') is False
    lua.execute('HogHeals.db.profile.quests.buttons.hover = true; HogHealsMinimapButtons:GetScript("OnEnter")(HogHealsMinimapButtons)')
    assert lua.eval('HogHealsMinimapDrawer:IsShown()') is True
    lua.execute('HogHealsMinimapButtons:GetScript("OnLeave")(HogHealsMinimapButtons)')
    # cursor over the drawer: stays open; off both for a second: closes itself
    lua.execute('HogHealsMinimapDrawer._mouseOver = true')
    for _ in range(6):
        lua.execute('MockAdvance(0.25)')
    assert lua.eval('HogHealsMinimapDrawer:IsShown()') is True
    lua.execute('HogHealsMinimapDrawer._mouseOver = false; HogHealsMinimapButtons._mouseOver = false')
    for _ in range(5):
        lua.execute('MockAdvance(0.25)')
    assert lua.eval('HogHealsMinimapDrawer:IsShown()') is False
    assert errors(lua) == []


def test_without_the_minimap_skin_the_launcher_hangs_under_the_bare_minimap(lua):
    boot(lua, MINIMAP)
    assert lua.eval('HogHealsQuests.Buttons.anchoredTo') == "skin"
    # the skin option is turned off: the options refresh re-anchors the launcher to the bare Minimap
    lua.execute('HogHeals.db.profile.quests.map.enabled = false')
    lua.execute('HogHeals.OptionsTable().args.Quests.args.minimap.args.look.args.enabled.set({}, false)')
    assert lua.eval('HogHealsMinimapButtons._points[1][2] == Minimap')
    assert lua.eval('HogHealsQuests.Buttons.anchoredTo') == "minimap"
    assert errors(lua) == []


def test_unlock_drag_saves_the_spot_lock_refuses_and_reset_goes_back_to_the_map(lua):
    boot(lua, MINIMAP)
    lua.execute('HogHeals:SlashCommand("lock")')
    # locked: a drag does not start; the launcher stays beside the map
    lua.execute('HogHealsMinimapButtons:GetScript("OnDragStart")(HogHealsMinimapButtons)')
    assert lua.eval('HogHealsMinimapButtons._moving') is None
    assert lua.eval('HogHealsMinimapButtons.edges[1]._color[2]') == pytest.approx(0.20)
    # unlocked: cyan edges, the drag runs, the dropped spot is kept and re-applied
    lua.execute('HogHeals:SlashCommand("unlock")')
    assert lua.eval('HogHealsMinimapButtons.edges[1]._color[2]') == pytest.approx(0.83)
    lua.execute('''
      local b = HogHealsMinimapButtons
      b:GetScript("OnDragStart")(b)
      b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 300, 200)   -- where the player dropped it
      b:GetScript("OnDragStop")(b)
    ''')
    assert lua.eval('HogHealsMinimapButtons._moving') is False
    d = lua.eval('HogHeals.db.profile.quests.buttons')
    assert d["point"] == "BOTTOMLEFT" and d["x"] == 300 and d["y"] == 200
    lua.execute('HogHealsQuests.Buttons.Refresh()')
    p = lua.eval('HogHealsMinimapButtons._points[1]')
    assert p[1] == "BOTTOMLEFT" and p[4] == 300 and lua.eval('HogHealsMinimapButtons._points[1][2] == UIParent')
    assert lua.eval('HogHealsQuests.Buttons.Probe().anchor') == "saved"
    # the drawer still opens leftward from wherever the H is
    assert lua.eval('HogHealsMinimapDrawer._points[1][2] == HogHealsMinimapButtons') and lua.eval('HogHealsMinimapDrawer._points[1][1]') == "BOTTOMRIGHT"
    # reset: back beside the map
    lua.execute('HogHeals.OptionsTable().args.Quests.args.minimap.args.buttons.args.resetPos.func()')
    assert lua.eval('HogHealsMinimapButtons._points[1][2] == HogHealsMinimapFrame')
    assert lua.eval('HogHeals.db.profile.quests.buttons.point') is None
    # opacity slider reaches the drawer background
    lua.execute('HogHeals.OptionsTable().args.Quests.args.minimap.args.buttons.args.alpha.set({}, 0.5)')
    assert lua.eval('HogHealsMinimapDrawer.bg._color[4]') == pytest.approx(0.5)
    assert errors(lua) == []


def test_right_side_puts_the_launcher_under_the_map_and_opens_down(lua):
    boot(lua, MINIMAP)
    lua.execute('HogHeals.OptionsTable().args.Quests.args.minimap.args.buttons.args.side.set({}, "right")')
    assert lua.eval('HogHealsMinimapButtons._points[1][1]') == "TOPRIGHT" and lua.eval('HogHealsMinimapButtons._points[1][3]') == "BOTTOMRIGHT"
    assert lua.eval('HogHealsMinimapDrawer._points[1][3]') == "BOTTOMRIGHT"
    scale = lua.eval('LibDBIcon10_Bagnon._last.SetScale[1]')
    assert lua.eval('LibDBIcon10_Bagnon._points[1][1]') == "TOPLEFT"
    assert lua.eval('LibDBIcon10_Details._points[1][4]') * scale == pytest.approx(4 + 32)
    assert lua.eval('HogHealsQuests.Buttons.Probe().side') == "right"
    assert errors(lua) == []


def test_probe_and_options(lua):
    boot(lua, MINIMAP)
    lua.execute('HogHeals:SlashCommand("questdiag")')
    b = lua.eval('HogHeals.db.global.diag.quests.buttons')
    assert b["count"] == 4 and b["shown"] == 3 and "LibDBIcon10_Bagnon" in b["collected"] and b["anchor"] == "skin"
    args = lua.eval('HogHeals.OptionsTable().args.Quests.args.minimap.args.buttons.args')
    assert args["columns"]["name"] == "Columns" and args["size"]["max"] == 40
    lua.execute('HogHeals.OptionsTable().args.Quests.args.minimap.args.buttons.args.columns.set({}, 1)')
    assert lua.eval('HogHeals.db.profile.quests.buttons.columns') == 1
    assert lua.eval('HogHealsMinimapDrawer:GetWidth()') == 4 + 32
    assert errors(lua) == []
