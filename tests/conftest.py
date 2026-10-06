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
def hud(lua):
    """HogHeals + Frames + HUD loaded, one PLAYER_LOGIN."""
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Frames")
    lua.load_addon("HogHeals_HUD")
    lua.player_login()
    # the solo frame is off by default since 2026-09-23 (HogTron UI Units draws the player); the older frame tests
    # were written around it, so they opt back in
    lua.execute('HogHeals.db.profile.frames.layouts.solo.showSolo = true; HogHealsFrames.module:ApplyProfile(HogHeals:CurrentBucket())')
    return lua


@pytest.fixture
def frames(lua):
    """HogHeals + HogHeals_Frames loaded (WoW order: all ADDON_LOADED, then one PLAYER_LOGIN)."""
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Frames")
    lua.player_login()
    # the solo frame is off by default since 2026-09-23 (HogTron UI Units draws the player); the older frame tests
    # were written around it, so they opt back in
    lua.execute('HogHeals.db.profile.frames.layouts.solo.showSolo = true; HogHealsFrames.module:ApplyProfile(HogHeals:CurrentBucket())')
    return lua
