# HogHeals_Bars: our own action bars on LibActionButton-1.0 (stubbed here: tests/lib_stubs.lua gives a fake lib
# whose buttons record every call). Tests cover our layer: bars built, slot mapping, layout, grid, Blizzard hidden,
# bind mode. The real lib runs only in the client.
import pytest

CLIENT = r'''
-- Blizzard's bars on a modern client: the frames and their buttons
for _, n in ipairs({ "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar" }) do
  local f = CreateFrame("Frame", n, UIParent)
  function f:HideBase() self._hideBase = true self:Hide() end
end
for _, p in ipairs({ "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }) do
  for i = 1, 12 do CreateFrame("CheckButton", p .. i, UIParent) end
end
ActionBarUpButton = CreateFrame("Button", "ActionBarUpButton", UIParent)
NUM_ACTIONBAR_BUTTONS = 12
function GetOverrideBarIndex() return 14 end
function GetVehicleBarIndex() return 12 end
function GetTempShapeshiftBarIndex() return 13 end
BINDINGS = {}
function GetBindingKey(action) local t = BINDINGS[action] or {} return unpack(t) end
function SetBinding(key, action) BINDINGS[action] = BINDINGS[action] or {} table.insert(BINDINGS[action], key) BOUND = BOUND or {} BOUND[#BOUND + 1] = { key, action } return true end
function GetCurrentBindingSet() return 2 end
SAVED = nil
function SaveBindings(set) SAVED = set end
DRIVERS = {}
function RegisterStateDriver(frame, state, driver) DRIVERS[#DRIVERS + 1] = { frame, state, driver } end
function UnregisterStateDriver() end
'''


@pytest.fixture
def bars(lua):
    lua.execute(CLIENT)
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Bars")
    lua.player_login()
    lua.execute('wipe(HogHeals.errors)')
    return lua


def errors(lua):
    return [e["msg"] for e in lua.eval('HogHeals.errors').values()]


def test_module_registers_with_the_lib_and_an_options_tab(bars):
    assert bars.eval('HogHeals.modules.Bars ~= nil') is True
    assert bars.eval('HogHealsBars.Bars.Lib() ~= nil') is True and bars.eval('HogHealsBars.Bars.unavailable') is None
    assert bars.eval('HogHeals.defaults.profile.bars.enabled') is True and bars.eval('HogHeals.defaults.profile.bars.grid') is True
    assert bars.eval('HogHeals.db.profile.bars.list[1].buttons') == 12 and bars.eval('HogHeals.db.profile.bars.list[4].perRow') == 1
    assert bars.eval('HogHeals.db.profile.bars.list[6].enabled') is False
    assert bars.eval('HogHeals.OptionsTable().args.Bars.args.grid ~= nil') is True
    assert bars.eval('HogHeals.OptionsTable().args.Bars.args.bar2.args.perRow ~= nil') is True
    assert bars.eval('HogHealsBars.Bars.lastApply') in ("enable", "enter")        # enable, then the world-enter pass
    assert errors(bars) == []


def test_without_the_lib_the_module_stays_off_and_says_so(lua):
    lua.execute(CLIENT + 'LibStub.libs["LibActionButton-1.0"] = nil')
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Bars")
    lua.player_login()
    assert lua.eval('HogHealsBars.Bars.unavailable') is True
    assert any("LibActionButton" in e["msg"] for e in lua.eval('HogHeals.errors').values())


def test_five_bars_built_on_blizzards_slots_with_their_binding_names(bars):
    assert bars.eval('HogHealsBars.Bars.built') == 5                                            # 1-5 on, 6-8 off
    assert bars.eval('HogUIBar1 ~= nil and HogUIBar5 ~= nil and HogUIBar6 == nil') is True
    assert bars.eval('HogUIBar1._template') == "SecureHandlerStateTemplate"
    # bar 2 = bottom-left slots 61-72, bar 3 = 49-60, bar 4 = 25-36, bar 5 = 37-48: every spell stays where it was
    assert bars.eval('HogUIBar2.buttons[1]._states[0][2]') == 61 and bars.eval('HogUIBar2.buttons[12]._states[0][2]') == 72
    assert bars.eval('HogUIBar3.buttons[1]._states[0][2]') == 49 and bars.eval('HogUIBar4.buttons[1]._states[0][2]') == 25 and bars.eval('HogUIBar5.buttons[1]._states[0][2]') == 37
    # bar 1 is paged: state 1 = slots 1-12, state 2 = 13-24, bonus bar 1 (state 7) = 73-84
    assert bars.eval('HogUIBar1.buttons[3]._states[1][2]') == 3 and bars.eval('HogUIBar1.buttons[3]._states[2][2]') == 15 and bars.eval('HogUIBar1.buttons[1]._states[7][2]') == 73
    assert bars.eval('HogUIBar1.driver') == "[overridebar]14;[shapeshift]13;[vehicleui]12;[possessbar]12;[bar:2]2;[bar:3]3;[bar:4]4;[bar:5]5;[bar:6]6;[bonusbar:1]7;[bonusbar:2]8;[bonusbar:3]9;[bonusbar:4]10;1"
    assert bars.eval('(function() for _, d in ipairs(DRIVERS) do if d[1] == HogUIBar1 and d[2] == "page" then return true end end return false end)()') is True
    assert bars.eval('HogUIBar1:GetAttribute("_onstate-page") ~= nil') is True
    # keybinds: Blizzard's own binding names, so the keys the player has keep firing
    assert bars.eval('HogUIBar1.buttons[1].config.keyBoundTarget') == "ACTIONBUTTON1"
    assert bars.eval('HogUIBar2.buttons[7].config.keyBoundTarget') == "MULTIACTIONBAR1BUTTON7"
    assert bars.eval('HogUIBar3.buttons[1].config.keyBoundTarget') == "MULTIACTIONBAR2BUTTON1"
    assert bars.eval('HogUIBar4.buttons[1].config.keyBoundTarget') == "MULTIACTIONBAR3BUTTON1" and bars.eval('HogUIBar5.buttons[1].config.keyBoundTarget') == "MULTIACTIONBAR4BUTTON1"
    assert bars.eval('HogUIBar1.buttons[1].config.clickOnDown') is False                        # mock cvar "0": release
    assert errors(bars) == []


def test_layout_rows_padding_anchor_and_the_vertical_right_bars(bars):
    # bar 1: 12 in one row, 36 px cells, 2 px padding
    assert bars.eval('HogUIBar1._width') == 12 * 36 + 11 * 2 and bars.eval('HogUIBar1._height') == 36
    assert bars.eval('HogUIBar1.buttons[2]._points[1][4]') == 38 and bars.eval('HogUIBar1.buttons[2]._points[1][5]') == 0
    assert bars.eval('HogUIBar1._points[1][1]') == "BOTTOM" and bars.eval('HogUIBar1._points[1][5]') == 60
    assert bars.eval('HogUIBar2._points[1][5]') == 100 and bars.eval('HogUIBar3._points[1][5]') == 140
    # bar 4: one per row on the right edge, 12 rows
    assert bars.eval('HogUIBar4._width') == 36 and bars.eval('HogUIBar4._height') == 12 * 36 + 11 * 2
    assert bars.eval('HogUIBar4.buttons[2]._points[1][4]') == 0 and bars.eval('HogUIBar4.buttons[2]._points[1][5]') == -38
    assert bars.eval('HogUIBar4._points[1][1]') == "RIGHT" and bars.eval('HogUIBar4._points[1][4]') == -40
    # two rows of six, wider padding
    bars.execute('HogHeals.db.profile.bars.list[2].perRow = 6; HogHeals.db.profile.bars.list[2].padding = 4; HogHeals.db.profile.bars.list[2].buttons = 10; HogHealsBars.Bars.Apply("test")')
    assert bars.eval('HogUIBar2._width') == 6 * 36 + 5 * 4 and bars.eval('HogUIBar2._height') == 2 * 36 + 4
    assert bars.eval('HogUIBar2.buttons[7]._points[1][4]') == 0 and bars.eval('HogUIBar2.buttons[7]._points[1][5]') == -40
    assert bars.eval('HogUIBar2.buttons[10]:IsShown()') is True and bars.eval('HogUIBar2.buttons[11]:IsShown()') is False
    # options write through and relayout
    bars.execute('HogHeals.OptionsTable().args.Bars.args.bar2.args.perRow.set(nil, 12)')
    assert bars.eval('HogHeals.db.profile.bars.list[2].perRow') == 12 and bars.eval('HogUIBar2._height') == 36
    bars.execute('HogHeals.OptionsTable().args.Bars.args.bar5.args.enabled.set(nil, false)')
    assert bars.eval('HogUIBar5:IsShown()') is False and bars.eval('HogHealsBars.Bars.built') == 4
    assert errors(bars) == []


def test_grid_shows_empty_cells_global_and_per_bar(bars):
    b = 'HogUIBar1.buttons[1]'
    assert bars.eval(f'{b}.config.showGrid') is True and bars.eval(f'{b}.hh.backdrop:IsShown()') is True      # empty slot, grid on
    bars.execute('HogHeals.OptionsTable().args.Bars.args.grid.set(nil, false)')
    assert bars.eval(f'{b}.config.showGrid') is False and bars.eval(f'{b}.hh.backdrop:IsShown()') is False and bars.eval(f'{b}.hh.edges[1]:IsShown()') is False
    bars.execute(f'{b}._hasAction = true; HogHealsBars.Bars.Lib().callbacks:Fire("OnButtonUpdate", {b})')      # a spell lands in it
    assert bars.eval(f'{b}.hh.backdrop:IsShown()') is True
    bars.execute('HogHeals.OptionsTable().args.Bars.args.bar2.args.grid.set(nil, "on")')                       # per-bar override
    assert bars.eval('HogUIBar2.buttons[1].config.showGrid') is True and bars.eval('HogUIBar2.buttons[1].hh.backdrop:IsShown()') is True
    assert bars.eval(f'HogUIBar3.buttons[1].config.showGrid') is False
    assert errors(bars) == []


def test_the_flat_look_and_blizzards_bars_gone(bars):
    b = 'HogUIBar1.buttons[1]'
    assert bars.eval(f'{b}.NormalTexture._alpha') == 0 and bars.eval(f'{b}.icon._last.SetTexCoord[1]') == pytest.approx(0.08)
    assert bars.eval(f'#{b}.hh.edges') == 4 and bars.eval(f'{b}.config.hideElements.macro') is True and bars.eval(f'{b}.config.text.hotkey.font.size') == 10
    # Blizzard: the multibars and every action button under the hidden parent, HideBase honoured; MainMenuBar left alive
    assert bars.eval('MultiBarBottomLeft:GetParent() == HogHealsBarsHider') is True and bars.eval('MultiBarBottomLeft._hideBase') is True
    assert bars.eval('ActionButton1:GetParent() == HogHealsBarsHider') is True and bars.eval('MultiBar7Button12:GetParent() == HogHealsBarsHider') is True
    assert bars.eval('MainMenuBar:GetParent() == UIParent') is True
    assert bars.eval('ActionBarUpButton:GetParent() == HogHealsBarsHider') is True
    assert bars.eval('HogHealsBars.Bars.hidden') > 90
    assert errors(bars) == []


def test_drag_under_unlock_saves_the_spot(bars):
    assert bars.eval('HogUIBar1.handle:IsShown()') is False
    bars.execute('HogHeals:SlashCommand("unlock")')
    assert bars.eval('HogUIBar1.handle:IsShown()') is True and bars.eval('HogUIBar1.handle.label._text') == "Bar 1"
    bars.execute('''
      local h = HogUIBar1.handle
      h:GetScript("OnDragStart")(h); HogUIBar1:ClearAllPoints(); HogUIBar1:SetPoint("CENTER", UIParent, "CENTER", 12, -34); h:GetScript("OnDragStop")(h)
    ''')
    assert bars.eval('HogHeals.db.profile.bars.list[1].point') == "CENTER" and bars.eval('HogHeals.db.profile.bars.list[1].y') == -34
    bars.execute('HogHeals:SlashCommand("lock")')
    assert bars.eval('HogUIBar1.handle:IsShown()') is False
    assert errors(bars) == []


def test_skins_action_bar_part_yields_to_bars(lua):
    lua.execute(CLIENT + 'MainMenuBarTexture0 = UIParent:CreateTexture("MainMenuBarTexture0"); MainMenuBarTexture0:SetTexture("art")')
    for a in ("HogHeals", "HogHeals_Bars", "HogHeals_Skin"):
        lua.load_addon(a)
    lua.player_login()
    assert lua.eval('HogHealsSkin.ActionBars.yielded') is True
    assert lua.eval('ActionButton1.hhSkinned') is None                                         # Skin never touched the hidden buttons
    assert [e["msg"] for e in lua.eval('HogHeals.errors').values()] == []


BIND_CLIENT = """
SHIFT, CTRL, ALT = false, false, false
function IsShiftKeyDown() return SHIFT end
function IsControlKeyDown() return CTRL end
function IsAltKeyDown() return ALT end
"""


def test_bind_mode_hover_a_slot_press_a_key_esc_clears_mouse_binds(bars):
    bars.execute(BIND_CLIENT + 'BOUND = {}; CLEARED = 0; HogHeals:SlashCommand("bind")')
    B = 'HogHealsBars.Bind'
    assert bars.eval(f'{B}.active') is True and bars.eval(f'{B}.count') == 80                  # 5 bars x 12 + pet 10 + stance 10
    o = f'{B}.overlays[HogUIBar1.buttons[1]]'
    assert bars.eval(f'{o}:IsShown()') is True and bars.eval(f'{o}:GetParent() == HogUIBar1.buttons[1]') is True
    assert bars.eval('HogHealsBindStrip:IsShown()') is True
    # nothing hovered: the key passes through to the game
    bars.execute(f'HogHealsBindStrip:GetScript("OnKeyDown")(HogHealsBindStrip, "W")')
    assert bars.eval('#BOUND') == 0 and bars.eval('HogHealsBindStrip._last.SetPropagateKeyboardInput[1]') is True
    # hover slot 1 of bar 1, press F -> ACTIONBUTTON1 = F, saved to the character set (2)
    bars.execute(f'{o}:GetScript("OnEnter")({o}); HogHealsBindStrip:GetScript("OnKeyDown")(HogHealsBindStrip, "F")')
    assert bars.eval('BOUND[1][1]') == "F" and bars.eval('BOUND[1][2]') == "ACTIONBUTTON1" and bars.eval('SAVED') == 2
    assert bars.eval('HogHealsBindStrip._last.SetPropagateKeyboardInput[1]') is False
    assert bars.eval(f'{o}.keys._text') == "F"                                                    # the overlay shows the key
    # a lone modifier does nothing; modifiers combine in Blizzard's order
    bars.execute('HogHealsBindStrip:GetScript("OnKeyDown")(HogHealsBindStrip, "LSHIFT")')
    assert bars.eval('#BOUND') == 1
    bars.execute('SHIFT, CTRL = true, true; HogHealsBindStrip:GetScript("OnKeyDown")(HogHealsBindStrip, "G"); SHIFT, CTRL = false, false')
    assert bars.eval('BOUND[2][1]') == "CTRL-SHIFT-G"
    # Esc clears the hovered slot; mouse 4 binds, left never does
    bars.execute('HogHealsBindStrip:GetScript("OnKeyDown")(HogHealsBindStrip, "ESCAPE")')
    assert bars.eval('CLEARED') == 1 and bars.eval(f'{B}.last[2]') == "cleared"
    o2 = f'{B}.overlays[HogUIBar2.buttons[3]]'
    bars.execute(f'{o2}:GetScript("OnMouseDown")({o2}, "Button4")')
    assert bars.eval('BOUND[3][1]') == "BUTTON4" and bars.eval('BOUND[3][2]') == "MULTIACTIONBAR1BUTTON3"
    bars.execute(f'{o2}:GetScript("OnMouseDown")({o2}, "LeftButton")')
    assert bars.eval('#BOUND') == 3
    # leaving the slot drops the target; /hh bind again ends the mode and hides the overlays
    bars.execute(f'{o2}:GetScript("OnLeave")({o2})')
    assert bars.eval(f'{B}.target') is None
    bars.execute('HogHeals:SlashCommand("bind")')
    assert bars.eval(f'{B}.active') is False and bars.eval(f'{o}:IsShown()') is False and bars.eval('HogHealsBindStrip:IsShown()') is False
    assert errors(bars) == []


def test_bind_mode_refuses_combat_and_ends_when_combat_starts(bars):
    bars.execute(BIND_CLIENT + 'MockState.inCombat = true')
    assert bars.eval('HogHealsBars.Bind.Start()') is False and bars.eval('HogHealsBars.Bind.active') is not True
    bars.execute('MockState.inCombat = false; HogHealsBars.Bind.Start()')
    assert bars.eval('HogHealsBars.Bind.active') is True
    bars.execute('HogHealsBindStrip:GetScript("OnEvent")(HogHealsBindStrip, "PLAYER_REGEN_DISABLED")')
    assert bars.eval('HogHealsBars.Bind.active') is False
    assert bars.eval('HogHeals.OptionsTable().args.Bars.args.bind.func ~= nil') is True
    assert errors(bars) == []


EXTRA_CLIENT = """
PET = { { "Attack", "Interface/Icons/Ability_GhoulFrenzy", false, true, true, true }, { "Follow", "PET_FOLLOW_TEXTURE", true, false, false, false }, { "Growl", "Interface/Icons/Growl", false, false, true, false } }
PET_FOLLOW_TEXTURE = "Interface/Icons/Ability_Tracking"
function GetPetActionInfo(i) local p = PET[i] if not p then return nil end return unpack(p) end
function GetPetActionCooldown(i) if i == 3 then return 100, 8, 1 end return 0, 0, 0 end
function PetHasActionBar() return true end
FORMS = { { "Interface/Icons/Ability_Warrior_OffensiveStance", true, true, 2457 }, { "Interface/Icons/Ability_Warrior_DefensiveStance", false, true, 71 }, { "Interface/Icons/Ability_Warrior_Berserk", false, false, 2458 } }
function GetNumShapeshiftForms() return #FORMS end
function GetShapeshiftFormInfo(i) local f = FORMS[i] if not f then return nil end return unpack(f) end
function GetShapeshiftFormCooldown() return 0, 0, 0 end
PetActionBar = CreateFrame("Frame", "PetActionBar", UIParent)
StanceBar = CreateFrame("Frame", "StanceBar", UIParent)
for i = 1, 10 do CreateFrame("CheckButton", "PetActionButton" .. i, UIParent); CreateFrame("CheckButton", "StanceButton" .. i, UIParent) end
"""


@pytest.fixture
def xbars(lua):
    lua.execute(CLIENT + EXTRA_CLIENT)
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Bars")
    lua.player_login()
    lua.execute('wipe(HogHeals.errors)')
    return lua


def test_visibility_drivers_fade_and_click_through(bars):
    # always: no driver; the choice becomes a state driver on the bar; custom = the player's own conditional
    assert bars.eval('HogUIBar2.visDriver') is None
    bars.execute('HogHeals.OptionsTable().args.Bars.args.bar2.args.visibility.set(nil, "nocombat")')
    assert bars.eval('HogUIBar2.visDriver') == "[nocombat]hide;show"
    assert bars.eval('DRIVERS[#DRIVERS][1] == HogUIBar2 and DRIVERS[#DRIVERS][2] == "vis" and DRIVERS[#DRIVERS][3] == "[nocombat]hide;show"') is True
    assert bars.eval('HogUIBar2:GetAttribute("_onstate-vis") ~= nil') is True
    bars.execute('HogHeals.OptionsTable().args.Bars.args.bar2.args.visibility.set(nil, "custom"); HogHeals.OptionsTable().args.Bars.args.bar2.args.custom.set(nil, "[mod:shift]show;hide")')
    assert bars.eval('HogUIBar2.visDriver') == "[mod:shift]show;hide"
    # fade: faded until the mouse is over a button, back after the delay
    bars.execute('HogHeals.OptionsTable().args.Bars.args.bar3.args.fade.set(nil, true)')
    assert bars.eval('HogUIBar3._alpha') == pytest.approx(0.25)
    bars.execute('local b = HogUIBar3.buttons[4]; b:GetScript("OnEnter")(b)')
    assert bars.eval('HogUIBar3._alpha') == 1
    bars.execute('local b = HogUIBar3.buttons[4]; b:GetScript("OnLeave")(b); MockAdvance(0.3)')
    assert bars.eval('HogUIBar3._alpha') == 1                                                 # delay not up yet
    bars.execute('MockAdvance(0.4)')
    assert bars.eval('HogUIBar3._alpha') == pytest.approx(0.25)
    bars.execute('HogHeals.OptionsTable().args.Bars.args.bar3.args.fade.set(nil, false)')
    assert bars.eval('HogUIBar3._alpha') == 1
    # click-through: empty slots let the mouse through, a filled slot keeps it
    bars.execute('HogHeals.OptionsTable().args.Bars.args.bar1.args.clickThrough.set(nil, true)')
    assert bars.eval('HogUIBar1.buttons[1]._last.EnableMouse[1]') is False
    bars.execute('HogUIBar1.buttons[1]._hasAction = true; HogHealsBars.Bars.UpdateCell(HogUIBar1.buttons[1])')
    assert bars.eval('HogUIBar1.buttons[1]._last.EnableMouse[1]') is True
    assert errors(bars) == []


def test_pet_bar_actions_autocast_cooldown_and_bind_targets(xbars):
    assert xbars.eval('HogUIPetBar ~= nil and #HogUIPetBar.buttons') == 10
    b = 'HogUIPetBar.buttons'
    assert xbars.eval(f'{b}[1]:GetAttribute("type")') == "pet" and xbars.eval(f'{b}[3]:GetAttribute("action")') == 3
    assert xbars.eval(f'{b}[1].icon._texture') == "Interface/Icons/Ability_GhoulFrenzy"
    assert xbars.eval(f'{b}[2].icon._texture') == "Interface/Icons/Ability_Tracking"             # token resolved
    assert xbars.eval(f'{b}[1].hh.edges[1]._color[2]') == pytest.approx(0.83)                 # autocast on = cyan edge
    assert xbars.eval(f'{b}[3].hh.edges[1]._color[2]') == pytest.approx(0.20)
    assert xbars.eval(f'{b}[3].cooldown._last.SetCooldown[1]') == 100 and xbars.eval(f'{b}[3].cooldown._last.SetCooldown[2]') == 8
    assert xbars.eval(f'{b}[4].icon._texture') is None and xbars.eval('HogHealsBars.Extra.petCount') == 3
    assert xbars.eval(f'{b}[1].keyBoundTarget') == "BONUSACTIONBUTTON1" and xbars.eval(f'{b}[1]:GetBindingAction()') == "BONUSACTIONBUTTON1"
    assert xbars.eval('HogUIPetBar.visDriver') == "[nopet]hide;show"                           # never without a pet
    assert xbars.eval('HogUIPetBar._points[1][5]') == 184 and xbars.eval('HogUIPetBar._width') == 10 * 36 + 9 * 2
    assert xbars.eval('PetActionBar:GetParent() == HogHealsBarsHider and PetActionButton1:GetParent() == HogHealsBarsHider') is True
    # bind mode reaches the pet buttons with the same four methods
    xbars.execute('BOUND = {}; HogHealsBars.Bind.Start(); local o = HogHealsBars.Bind.overlays[HogUIPetBar.buttons[2]]; o:GetScript("OnEnter")(o); HogHealsBindStrip:GetScript("OnKeyDown")(HogHealsBindStrip, "T")')
    assert xbars.eval('BOUND[1][1]') == "T" and xbars.eval('BOUND[1][2]') == "BONUSACTIONBUTTON2"
    assert xbars.eval('HogUIPetBar.buttons[2].HotKey._text') == "T"
    assert xbars.eval('HogHealsBars.Bind.count') == 80                                         # 60 + 10 pet + 10 stance
    xbars.execute('HogHealsBars.Bind.Stop("done")')
    assert errors(xbars) == []


def test_stance_bar_forms_spells_and_layout(xbars):
    b = 'HogUIStanceBar.buttons'
    assert xbars.eval('HogHealsBars.Extra.formCount') == 3
    assert xbars.eval(f'{b}[1]:GetAttribute("type")') == "spell" and xbars.eval(f'{b}[1]:GetAttribute("spell")') == 2457 and xbars.eval(f'{b}[2]:GetAttribute("spell")') == 71
    assert xbars.eval(f'{b}[1]._last.SetChecked[1]') is True and xbars.eval(f'{b}[2]._last.SetChecked[1]') is False
    assert xbars.eval(f'{b}[3]:IsShown()') is True and xbars.eval(f'{b}[4]:IsShown()') is False   # laid out for 3 forms
    assert xbars.eval('HogUIStanceBar._width') == 3 * 36 + 2 * 2
    assert xbars.eval(f'{b}[1].keyBoundTarget') == "SHAPESHIFTBUTTON1"
    assert xbars.eval('StanceBar:GetParent() == HogHealsBarsHider') is True
    # a classic-style client hands a name instead of a spell id; no forms = no bar
    xbars.execute('function GetShapeshiftFormInfo(i) local f = FORMS[i] if not f then return nil end return f[1], "Battle Stance", f[2], f[3] end; HogHealsBars.Extra.UpdateStance()')
    assert xbars.eval(f'{b}[1]:GetAttribute("spell")') == "Battle Stance"
    xbars.execute('FORMS = {}; MockFire("UPDATE_SHAPESHIFT_FORMS")')
    assert xbars.eval('HogUIStanceBar:IsShown()') is False and xbars.eval('HogHealsBars.Extra.formCount') == 0
    assert errors(xbars) == []


def test_pet_flags_as_this_client_sends_them_1_and_nil(xbars):
    # in game 2026-10-06: Attack / Follow / Move To came up blank - the client says isToken = 1, not true
    xbars.execute("""
      PET_ATTACK_TEXTURE = "Interface/Icons/Ability_GhoulFrenzy"
      PET_MOVE_TO_TEXTURE = "Interface/Icons/Ability_Hunter_Pet_Goto"
      PET = { { "Attack", "PET_ATTACK_TEXTURE", 1, nil, nil, nil },
              { "Follow", "PET_FOLLOW_TEXTURE", 1, 1, nil, nil },
              { "Move To", "PET_MOVE_TO_TEXTURE", 1, nil, nil, nil },
              { "Growl", "Interface/Icons/Growl", nil, nil, 1, 1 } }
      HogHealsBars.Extra.UpdatePet()
    """)
    b = 'HogUIPetBar.buttons'
    assert xbars.eval(f'{b}[1].icon._texture') == "Interface/Icons/Ability_GhoulFrenzy"
    assert xbars.eval(f'{b}[2].icon._texture') == "Interface/Icons/Ability_Tracking"
    assert xbars.eval(f'{b}[3].icon._texture') == "Interface/Icons/Ability_Hunter_Pet_Goto"
    assert xbars.eval(f'{b}[2]._last.SetChecked[1]') is True and xbars.eval(f'{b}[1]._last.SetChecked[1]') is False
    assert xbars.eval(f'{b}[4].hh.edges[1]._color[2]') == pytest.approx(0.83)                 # autocast 1 = on
    assert errors(xbars) == []


def test_an_unknown_event_no_longer_stops_the_bar_library_registering_the_rest():
    # in game 2026-10-06: "Attempt to register unknown event LEARNED_SPELL_IN_TAB" x28 from the REAL vendored lib
    # (the tests above use a fake one). Run the real InitializeEventHandler against a frame that throws like Forever.
    from pathlib import Path as _P
    from lupa.lua51 import LuaRuntime
    src = (_P(__file__).resolve().parents[1] / "HogHeals_Bars/Libs/LibActionButton-1.0/LibActionButton-1.0.lua").read_text(encoding="utf-8").splitlines()
    a = next(k for k, l in enumerate(src) if l.startswith("function InitializeEventHandler()"))
    b = next(k for k in range(a + 1, len(src)) if src[k] == "end")
    rt = LuaRuntime()
    rt.execute("""
      UNKNOWN = { LEARNED_SPELL_IN_TAB = true, GAME_PAD_ACTIVE_CHANGED = true }
      REG = {}
      local frame = {}
      function frame:SetScript() end
      function frame:Show() end
      function frame:Hide() end
      function frame:RegisterEvent(e) if UNKNOWN[e] then error('Attempt to register unknown event "' .. e .. '"') end REG[e] = true end
      function frame:RegisterUnitEvent(e) REG[e] = true end
      lib = { eventFrame = frame }
    """)
    rt.execute(chr(10).join(src[a:b + 1]))
    rt.execute("InitializeEventHandler()")
    assert rt.eval("lib.unknownEvents.LEARNED_SPELL_IN_TAB") is True
    for ev in ("SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "PLAYER_EQUIPMENT_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "ACTIONBAR_SLOT_CHANGED"):
        assert rt.eval(f'REG["{ev}"]') is True, ev
    rt.execute("InitializeEventHandler()")                      # second call: wrapper not stacked
    assert rt.eval("lib.eventFrame.hhSafeRegister") is True


def _lab_src():
    from pathlib import Path as _P
    return (_P(__file__).resolve().parents[1] / "HogHeals_Bars/Libs/LibActionButton-1.0/LibActionButton-1.0.lua").read_text(encoding="utf-8")


def test_duration_object_path_is_taken_wherever_the_client_has_it():
    # in game 2026-10-06: no swipes / GCD on any button - Forever is not "Retail", so the lib never used duration objects
    from lupa.lua51 import LuaRuntime
    src = _lab_src().splitlines()
    a = next(k for k, l in enumerate(src) if l.startswith("local function HHDurationObjectsAvailable()"))
    b = next(k for k in range(a, len(src)) if src[k].startswith("lib.cooldownPath ="))
    chunk = chr(10).join(src[a:b + 1])
    for has, want in ((True, "duration objects"), (False, "numbers")):
        rt = LuaRuntime()
        rt.execute(f"""
          lib = {{}}; WoWRetail = false; buildNumber = "70009"
          C_ActionBar = {{ GetActionCooldownDuration = function() end }}
          function CreateFrame(kind) local f = {{}} if {str(has).lower()} then function f:SetCooldownFromDurationObject() end end return f end
        """)
        rt.execute(chunk)
        assert rt.eval("lib.cooldownPath") == want


def test_hidden_cooldown_numbers_go_straight_to_the_swipe():
    from lupa.lua51 import LuaRuntime
    src = _lab_src().splitlines()
    a = next(k for k, l in enumerate(src) if l.startswith("\tfunction lib.hhSecretCooldown(self)"))
    b = next(k for k in range(a + 1, len(src)) if src[k] == "\tend")
    rt = LuaRuntime()
    rt.execute("""
      lib = {}
      SECRET = {}
      function issecretvalue(v) return type(v) == "table" and v.secret == true end
      local function secret(n) return { secret = true, n = n } end
      CALLS = {}
      local cd = { SetCooldown = function(self, s, d) CALLS[#CALLS + 1] = { s, d } end }
      HIDDEN = { cooldown = cd, GetCooldown = function() return secret(100), secret(1.5) end }
      PLAIN = { cooldown = cd, GetCooldown = function() return 100, 1.5 end }
    """)
    rt.execute(chr(10).join(src[a:b + 1]))
    assert rt.eval("lib.hhSecretCooldown(PLAIN)") is False and rt.eval("#CALLS") == 0     # plain numbers: the lib's own path
    assert rt.eval("lib.hhSecretCooldown(HIDDEN)") is True and rt.eval("#CALLS") == 1     # hidden: handed to the widget
    assert rt.eval("CALLS[1][2].n") == 1.5 and "hidden" in rt.eval("lib.cooldownPath")
    assert "if lib.hhSecretCooldown(self) then return end" in _lab_src()                    # wired in front of the maths
