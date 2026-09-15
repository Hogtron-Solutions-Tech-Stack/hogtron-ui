import pytest

from loader import AddonLoader


@pytest.fixture
def lua():
    """Fresh Lua 5.1 runtime with the WoW mock + LibStub + stubs loaded."""
    return AddonLoader().bootstrap()


@pytest.fixture
def core(lua):
    """HogHeals core loaded and logged in."""
    lua.load_addon("HogHeals")
    lua.player_login()
    return lua


@pytest.fixture
def frames(lua):
    """HogHeals + HogHeals_Frames loaded (WoW order: all ADDON_LOADED, then one PLAYER_LOGIN)."""
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Frames")
    lua.player_login()
    return lua
