# World map (HogHeals_Quests/WorldMap.lua): coordinates strip, scale, fade cvar, border art off, Leatrix deference.
import pytest

from test_quests import MODERN, boot, errors

MAP = r'''
WorldMapFrame = CreateFrame("Frame", "WorldMapFrame", UIParent)
WorldMapFrame.BorderFrame = CreateFrame("Frame", nil, WorldMapFrame)
WMArt = { WorldMapFrame.BorderFrame:CreateTexture(), WorldMapFrame.BorderFrame:CreateTexture() }
WorldMapFrame.BorderFrame.GetRegions = function() return WMArt[1], WMArt[2] end
WorldMapFrame.ScrollContainer = CreateFrame("Frame", nil, WorldMapFrame)
WorldMapFrame.ScrollContainer.GetNormalizedCursorPosition = function() return CURSOR[1], CURSOR[2] end
CURSOR = { 0.25, 0.5 }
C_Map = C_Map or {}
C_Map.GetBestMapForUnit = function() return 1429 end
C_Map.GetPlayerMapPosition = function() return { GetXY = function() return PPOS[1], PPOS[2] end } end
PPOS = { 0.321, 0.458 }
CV = {}
function SetCVar(k, v) CV[k] = v end
'''


def test_strip_shows_you_and_cursor_and_the_art_is_hidden(lua):
    boot(lua, MODERN + MAP)
    assert lua.eval('CV.mapFade') == "1"
    assert lua.eval('HogHealsQuests.WorldMap.strip ~= nil') is True
    lua.execute('WorldMapFrame:Show()')
    p, c = lua.eval('HogHealsQuests.WorldMap.Tick()')
    assert p == "You  32.1, 45.8" and c == "Cursor  25.0, 50.0"
    assert lua.eval('HogHealsQuests.WorldMap.strip.player._text') == "You  32.1, 45.8"
    lua.execute('CURSOR = { 1.2, 0.5 }')                                        # off the canvas
    assert lua.eval('select(2, HogHealsQuests.WorldMap.Tick())') == ""
    assert lua.eval('WMArt[1]._alpha') == 0 and lua.eval('WMArt[2]._alpha') == 0  # Blizzard's border art off
    assert lua.eval('HogHealsQuests.WorldMap.bg ~= nil') is True
    assert errors(lua) == []


def test_scale_and_options_and_no_coords(lua):
    boot(lua, MODERN + MAP)
    lua.execute('HogHeals.db.profile.quests.worldMap.scale = 0.8; HogHealsQuests.WorldMap.Refresh()')
    assert lua.eval('WorldMapFrame._last.SetScale[1]') == 0.8
    lua.execute('HogHeals.db.profile.quests.worldMap.coords = false; WorldMapFrame:Show(); HogHealsQuests.WorldMap.OnShow()')
    assert lua.eval('HogHealsQuests.WorldMap.strip:IsShown()') is False
    lua.execute('HogHeals.db.profile.quests.worldMap.fadeWhileMoving = false; HogHealsQuests.WorldMap.Refresh()')
    assert lua.eval('CV.mapFade') == "0"
    # every option getter / setter runs
    lua.execute('''
      local o = HogHealsQuests.Options.Build().args.worldmap.args
      for k, v in pairs(o) do if v.get then v.get({}) end if v.set then v.set({}, v.type == "range" and 1 or true) end end
    ''')
    assert errors(lua) == []


def test_secret_position_prints_dashes_not_errors(lua):
    boot(lua, MODERN + MAP)
    lua.execute('MockSetSecrets(true); PPOS = { MockSecret(0.3), MockSecret(0.4) }; WorldMapFrame:Show()')
    p, _ = lua.eval('HogHealsQuests.WorldMap.Tick()')
    assert p == "You  --"
    assert errors(lua) == []


def test_leatrix_maps_loaded_leaves_the_map_alone(lua):
    boot(lua, MODERN + MAP + 'C_AddOns = C_AddOns or {}; C_AddOns.IsAddOnLoaded = function(n) return n == "Leatrix_Maps" end')
    assert lua.eval('HogHealsQuests.WorldMap.skinned') is None or lua.eval('HogHealsQuests.WorldMap.skinned') is False
    assert lua.eval('WMArt[1]._alpha') != 0
    assert lua.eval('HogHealsQuests.WorldMap.strip') is None
    assert lua.eval('CV.mapFade') == "1"                                          # the cvar is still ours to set
    assert errors(lua) == []


def test_no_world_map_frame_is_fine(lua):
    boot(lua, MODERN)
    assert lua.eval('HogHealsQuests.WorldMap.Apply()') is False
    assert lua.eval('HogHealsQuests.WorldMap.Probe().frame') is False
    assert errors(lua) == []
