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
def frames(core):
    """HogHeals + HogHeals_Frames loaded and logged in."""
    core.load_addon("HogHeals_Frames")
    core.player_login()
    return core
