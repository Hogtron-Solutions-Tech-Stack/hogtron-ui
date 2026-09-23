# Square HogHeals minimap (HogHeals_Quests/MapSkin.lua) + minimap pins defaults / art fallback.
import pytest

from test_quests import MODERN, boot, errors

DECOR = r'''
MinimapBorder = Minimap:CreateTexture("MinimapBorder")
MinimapBorder:SetTexture("Interface\\Minimap\\UI-Minimap-Border")
MinimapZoomIn = CreateFrame("Button", "MinimapZoomIn", Minimap)
MiniMapTracking = CreateFrame("Frame", "MiniMapTracking", Minimap)
function GetMinimapZoneText() return "Tirisfal Glades" end
function GetZonePVPInfo() return "friendly" end
'''


def test_pins_on_by_default_and_no_second_arrow_for_the_super_tracked_quest(lua):
    boot(lua, MODERN)
    assert lua.eval('HogHeals.db.profile.quests.minimap.enabled') is True
    lua.execute('GetMinimapShape = nil; Minimap:SetSize(140, 140)')
    assert lua.eval('HogHealsQuests.Pins.Update()') == 2          # in-range objective + far turn-in arrow
    lua.execute('C_SuperTrack = { GetSuperTrackedQuestID = function() return 9 end }')
    assert lua.eval('HogHealsQuests.Pins.Update()') == 1          # Blizzard's gold arrow already points at 9
    lua.execute('C_SuperTrack = { GetSuperTrackedQuestID = function() return 7 end }')
    assert lua.eval('HogHealsQuests.Pins.Update()') == 2          # in-range pins are never dropped


def test_pin_falls_back_to_drawn_badge_when_art_is_refused(lua):
    boot(lua, MODERN)
    lua.execute('''
      HogHeals.db.profile.quests.minimap.enabled = true; GetMinimapShape = nil; Minimap:SetSize(140, 140)
      HogHealsQuests.Pins.Update()
      local p = HogHealsQuests.Pins.pool[1]
      local st = p.icon.SetTexture
      p.icon.SetTexture = function(t, path) st(t, path) if type(path) == "string" then return false end end
      HogHealsQuests.Pins.Update()
    ''')
    p1 = 'HogHealsQuests.Pins.pool[1]'
    assert lua.eval(f'{p1}.drawn') is True and lua.eval(f'{p1}.glyph._text') == "!"
    assert lua.eval(f'{p1}.icon._color[1]') == pytest.approx(0.95)


def test_minimap_skin_square_frame_zone_and_decor(lua):
    lua.execute(DECOR)
    boot(lua, MODERN)
    assert lua.eval('Minimap._last.SetMaskTexture[1]') == "Interface\\Buttons\\WHITE8X8"
    assert lua.eval('GetMinimapShape()') == "SQUARE"
    assert lua.eval('Minimap._width') == 180
    assert lua.eval('MinimapBorder._texture') is None
    assert lua.eval('MinimapZoomIn:GetParent() == HogHealsHiddenParent')
    assert lua.eval('MiniMapTracking:GetParent() == Minimap')          # functional button left alone
    assert lua.eval('HogHealsMinimapFrame.zone._text') == "Tirisfal Glades"
    assert lua.eval('HogHealsMinimapFrame.zone._color[2]') == pytest.approx(1.0)
    assert "MinimapNorthTag" in lua.eval('table.concat(HogHealsQuests.MapSkin.missing, ",")')
    lua.execute('HogHeals.db.profile.quests.map.size = 240; HogHealsQuests.MapSkin.Refresh()')
    assert lua.eval('Minimap._width') == 240
    lua.execute('HogHealsMinimapFrame.header:Click()')                  # zone name opens the world map, no error
    assert errors(lua) == []


def test_wheel_zoom_added_only_when_the_client_has_none(lua):
    lua.execute('ZOOM = 2; function Minimap:GetZoom() return ZOOM end; function Minimap:SetZoom(z) ZOOM = z end')
    boot(lua, MODERN)
    lua.execute('Minimap:GetScript("OnMouseWheel")(Minimap, 1)')
    assert lua.eval('ZOOM') == 3


def test_probe_lists_map_names(lua):
    lua.execute(DECOR)
    boot(lua, MODERN)
    lua.execute('HogHeals:SlashCommand("questdiag")')
    q = lua.eval('HogHeals.db.global.diag.quests')
    assert "MinimapBorder=y" in q["map"]["names"] and "MinimapNorthTag=n" in q["map"]["names"]
    assert errors(lua) == []


def test_every_quests_option_getter_and_setter_runs(lua):
    boot(lua, MODERN)
    lua.execute('''
      local function walk(t)
        for _, o in pairs(t.args or {}) do
          if o.get then local v = o.get({}) if o.set and o.type ~= "execute" and o.type ~= "description" then o.set({}, v) end end
          if o.args then walk(o) end
        end
      end
      walk(HogHeals.OptionsTable().args.Quests)
    ''')
    assert lua.eval('HogHeals.OptionsTable().args.Quests.args.tracker.args.fontSize.name') == "Text size"
    assert errors(lua) == []
