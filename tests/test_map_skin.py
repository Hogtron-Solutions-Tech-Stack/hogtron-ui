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
      HogHealsQuests.Pins.lastKey = nil   -- a client refusing a texture mid-session is not a state the key tracks
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


def test_quest_offers_probe_records_apis_pools_and_counts(lua):
    lua.execute(DECOR)
    boot(lua, MODERN)
    lua.execute("""
      C_QuestLine = { RequestQuestLinesForMap = function() end,
        GetAvailableQuestLines = function(mapID) return { { questID = 55, questLineID = 7, x = 0.4, y = 0.6, isHidden = false } } end }
      WorldMapFrame = CreateFrame("Frame", "WorldMapFrame", UIParent)
      WorldMapFrame.pinPools = { QuestLinePinTemplate = {}, QuestPinTemplate = {} }
      function WorldMapFrame:GetMapID() return 1429 end
    """)
    lua.execute('HogHeals:SlashCommand("questdiag")')
    o = lua.eval('HogHeals.db.global.diag.quests.offers')
    assert "C_QuestLine{GetAvailableQuestLines RequestQuestLinesForMap}" in o["apis"] and "C_QuestOffer=nil" in o["apis"]
    assert "questLines=1[isHidden questID questLineID x y]" in o["counts"] and "questOffers=nil" in o["counts"]
    assert "questsOnMap=2[" in o["counts"]
    assert o["pinPools"] == "QuestLinePinTemplate,QuestPinTemplate" and o["mapOpenID"] == "1429"
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


CLUSTER = r'''
MinimapCluster = CreateFrame("Frame", "MinimapCluster", UIParent)
MinimapCluster:SetSize(300, 340)
Minimap:SetSize(140, 140)
RING = Minimap:CreateTexture(nil, "OVERLAY")
RING:SetSize(140, 140)
RING:SetTexture("Interface\Minimap\Ring")
SMALL = Minimap:CreateTexture(nil, "OVERLAY")
SMALL:SetSize(12, 12)
GameTimeFrame = CreateFrame("Button", "GameTimeFrame", Minimap)
GameTimeFrame:SetSize(40, 40)
QueueStatusButton = CreateFrame("Button", "QueueStatusButton", Minimap)
QueueStatusButton:SetSize(36, 36)
'''


def test_map_fills_the_edit_mode_box_and_follows_resizes(lua):
    lua.execute(CLUSTER)
    boot(lua, MODERN)
    # 340 tall box: 340 - 24 top row - 20 header - 18 coords footer - 8 = 270; 300 wide - 12 = 288 -> 270
    assert lua.eval('Minimap._width') == 270
    assert lua.eval('Minimap._points[1][1]') == "TOP" and lua.eval('Minimap._points[1][2] == MinimapCluster')
    lua.execute('MinimapCluster:SetSize(260, 400); MinimapCluster:GetScript("OnSizeChanged")(MinimapCluster)')
    assert lua.eval('Minimap._width') == 248
    lua.execute('HogHeals.db.profile.quests.map.fill = false; HogHeals.db.profile.quests.map.size = 200; HogHealsQuests.MapSkin.Refresh()')
    assert lua.eval('Minimap._width') == 200
    assert errors(lua) == []


def test_round_ring_hidden_small_regions_kept(lua):
    lua.execute(CLUSTER)
    boot(lua, MODERN)
    assert lua.eval('RING:IsShown()') is False
    assert lua.eval('SMALL:IsShown()') is True
    assert lua.eval('HogHealsMinimapFrame.bg:IsShown()') is True          # our own panel never caught
    assert "Ring" in lua.eval('HogHealsQuests.MapSkin.hiddenOverlays[1]')


def test_buttons_on_the_map_are_docked_into_the_header(lua):
    lua.execute(CLUSTER)
    boot(lua, MODERN)
    assert lua.eval('GameTimeFrame._points[1][1]') == "LEFT" and lua.eval('GameTimeFrame._points[1][2] == HogHealsMinimapFrame.header')
    assert lua.eval('QueueStatusButton._points[1][1]') == "RIGHT"
    assert lua.eval('GameTimeFrame._last.SetScale[1]') == pytest.approx(18 / 40)
    lua.execute('HogHeals:SlashCommand("questdiag")')
    m = lua.eval('HogHeals.db.global.diag.quests.map')
    assert "GameTimeFrame" in m["docked"] and "Ring" in m["hidden"] and m["cluster"] == "300x340"


def test_engine_quest_ring_switched_off(lua):
    lua.execute("""
      RINGSET = {}
      function Minimap:SetQuestBlobRingScalar(v) RINGSET.qs = v end
      function Minimap:SetQuestBlobRingAlpha(v) RINGSET.qa = v end
      function Minimap:SetArchBlobRingScalar(v) RINGSET.as = v end
    """)
    boot(lua, MODERN)
    assert lua.eval('RINGSET.qs') == 0 and lua.eval('RINGSET.qa') == 0 and lua.eval('RINGSET.as') == 0
    lua.execute('HogHeals:SlashCommand("questdiag")')
    assert "SetQuestBlobRingScalar" in lua.eval('HogHeals.db.global.diag.quests.map.rings')
    assert errors(lua) == []


def test_docked_button_stays_docked_when_the_client_moves_it_back(lua):
    lua.execute(CLUSTER)
    boot(lua, MODERN)
    lua.execute('GameTimeFrame:ClearAllPoints(); GameTimeFrame:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 0, 0)')
    assert lua.eval('GameTimeFrame._points[1][2] == HogHealsMinimapFrame.header')
    assert errors(lua) == []


def test_nearby_turn_in_left_to_blizzard_far_one_keeps_its_arrow(lua):
    boot(lua, MODERN)
    lua.execute('GetMinimapShape = nil; Minimap:SetSize(140, 140)')
    # quest 9 (complete) moved next to the player: Blizzard's own ? marks that NPC -> no pin from us
    # quest points only move with the quest log in game (QUEST_LOG_UPDATE -> Data.List): re-read to mirror that
    lua.execute('QPoints = { { questID = 7, x = 0.50, y = 0.40 }, { questID = 9, x = 0.52, y = 0.52 } }; HogHealsQuests.Data.List()')
    assert lua.eval('HogHealsQuests.Pins.Update()') == 1
    assert lua.eval('HogHealsQuests.Pins.pool[1].quest.id') == 7
    # far away: Blizzard shows nothing, our rim arrow stays
    lua.execute('QPoints = { { questID = 9, x = 0.95, y = 0.95 } }; HogHealsQuests.Data.List()')
    assert lua.eval('HogHealsQuests.Pins.Update()') == 1
    assert lua.eval('HogHealsQuests.Pins.pool[1].arrow:IsShown()') is True
    # option: mark nearby turn-ins too
    lua.execute('HogHeals.db.profile.quests.minimap.turnInInRange = true; QPoints = { { questID = 9, x = 0.52, y = 0.52 } }; HogHealsQuests.Data.List()')
    assert lua.eval('HogHealsQuests.Pins.Update()') == 1


def test_pins_skip_work_while_nothing_changed(lua):
    boot(lua, MODERN)
    lua.execute("""
      GetMinimapShape = nil; Minimap:SetSize(140, 140)
      QCALLS = 0
      local orig = C_QuestLog.GetQuestsOnMap
      C_QuestLog.GetQuestsOnMap = function(...) QCALLS = QCALLS + 1 return orig(...) end
    """)
    assert lua.eval('HogHealsQuests.Pins.Update()') == 2
    n = lua.eval('QCALLS')
    for _ in range(10):
        assert lua.eval('HogHealsQuests.Pins.Update()') == 2
    assert lua.eval('QCALLS') == n                                     # nothing re-queried while standing still
    lua.execute('C_Map.GetPlayerMapPosition = function() return { x = 0.51, y = 0.50 } end')
    lua.eval('HogHealsQuests.Pins.Update()')
    assert lua.eval('QCALLS') == n + 1                                 # moved: recomputed once
    lua.execute('HogHealsQuests.Data.List(); HogHealsQuests.Pins.Update()')
    assert lua.eval('QCALLS') == n + 2                                 # quest log re-read: recomputed once
