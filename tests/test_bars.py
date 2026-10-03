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
BINDINGS = {}
function GetBindingKey(action) local t = BINDINGS[action] or {} return unpack(t) end
function SetBinding(key, action) BINDINGS[action] = BINDINGS[action] or {} table.insert(BINDINGS[action], key) BOUND = BOUND or {} BOUND[#BOUND + 1] = { key, action } return true end
function GetCurrentBindingSet() return 2 end
SAVED = nil
function SaveBindings(set) SAVED = set end
function RegisterStateDriver(frame, state, driver) DRIVERS = DRIVERS or {} DRIVERS[#DRIVERS + 1] = { frame, state, driver } end
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
    opt = bars.eval('HogHeals.OptionsTable().args.Bars')
    assert opt is not None and bars.eval('HogHeals.OptionsTable().args.Bars.args.grid ~= nil') is True
    assert bars.eval('HogHealsBars.Bars.lastApply') == "enable"
    assert errors(bars) == []


def test_without_the_lib_the_module_stays_off_and_says_so(lua):
    lua.execute(CLIENT + 'LibStub.libs["LibActionButton-1.0"] = nil')
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Bars")
    lua.player_login()
    assert lua.eval('HogHealsBars.Bars.unavailable') is True
    assert any("LibActionButton" in e["msg"] for e in lua.eval('HogHeals.errors').values())
