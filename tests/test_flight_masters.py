# Flight masters on the world map (HogTron_Quests/WorldMap.lua, WM.Flight). Sean 2026-11-05 in Moonglade: the map
# showed no flight masters (Forever's map registers no FlightPointPinTemplate pool). Two sources: the client's
# C_TaxiMap.GetTaxiNodesForMap, and what TAXIMAP_OPENED teaches us (kept as world positions per faction).
from test_quests import MODERN, boot, errors

# Three fake maps on two continents. A map is a rectangle of world space: world = origin + fraction * size.
MAP = r'''
function CreateVector2D(x, y) return { x = x, y = y, GetXY = function(s) return s.x, s.y end } end
MAPS = {
  [1450] = { c = 1, x0 = 1000, y0 = 2000, w = 1000, h = 700 },     -- Moonglade
  [1414] = { c = 1, x0 = 0, y0 = 0, w = 10000, h = 7000 },         -- Kalimdor (the flight map's map)
  [1429] = { c = 0, x0 = 1000, y0 = 2000, w = 1000, h = 700 },     -- Elwynn: same numbers, OTHER continent
}
C_Map = C_Map or {}
C_Map.GetBestMapForUnit = function() return PLAYER_MAP end
C_Map.GetPlayerMapPosition = function() return CreateVector2D(PPOS[1], PPOS[2]) end
C_Map.GetWorldPosFromMapPos = function(id, v)
  local m = MAPS[id] if not m then return nil end
  return m.c, CreateVector2D(m.x0 + v.x * m.w, m.y0 + v.y * m.h)
end
-- like the client with an override map: placed relative to that map, no continent check (the addon must do it)
C_Map.GetMapPosFromWorldPos = function(c, v, id)
  local m = MAPS[id] if not m then return nil end
  return id, CreateVector2D((v.x - m.x0) / m.w, (v.y - m.y0) / m.h)
end
PLAYER_MAP = 1450
PPOS = { 0.321, 0.666 }

WorldMapFrame = CreateFrame("Frame", "WorldMapFrame", UIParent)
WorldMapFrame.BorderFrame = CreateFrame("Frame", nil, WorldMapFrame)
WorldMapFrame.BorderFrame.GetRegions = function() end
WorldMapFrame.ScrollContainer = CreateFrame("Frame", nil, WorldMapFrame)
WorldMapFrame.ScrollContainer.GetNormalizedCursorPosition = function() return 0.5, 0.5 end
CANVAS = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer)
CANVAS:SetSize(1000, 700)
OPEN_MAP = 1450
CS = 1
WorldMapFrame.GetCanvas = function() return CANVAS end
WorldMapFrame.GetMapID = function() return OPEN_MAP end
WorldMapFrame.GetCanvasScale = function() return CS end
'''

API = r'''
C_TaxiMap = { GetTaxiNodesForMap = function(id)
  if id ~= 1450 then return {} end
  return {
    { nodeID = 1, name = "Moonglade", position = CreateVector2D(0.32, 0.66), faction = 1 },               -- Horde
    { nodeID = 2, name = "Moonglade (Alliance)", position = CreateVector2D(0.48, 0.67), faction = 2 },    -- not ours
    { nodeID = 3, name = "Nighthaven", position = CreateVector2D(0.44, 0.46), faction = 0, isUndiscovered = true },
  }
end }
'''

TAXI = r'''
C_TaxiMap = { GetAllTaxiNodes = function(id)
  return {
    -- Moonglade's dot on the Kalimdor flight map = world 1321, 2426.2 (Moonglade map 0.321, 0.609)
    { name = "Moonglade", position = CreateVector2D(0.1321, 0.3466), state = 0 },
    { name = "Thunder Bluff, Mulgore", position = CreateVector2D(0.45, 0.60), state = 1 },
  }
end }
function GetTaxiMapID() return 1414 end
MockUnits.npc = { name = "Faustron", class = "WARRIOR" }
'''


def pins(lua):
    return [lua.eval(f'HogHealsQuests.WorldMap.Flight.pins[{i}].node.name')
            for i in range(1, lua.eval('#HogHealsQuests.WorldMap.Flight.pins') + 1)
            if lua.eval(f'HogHealsQuests.WorldMap.Flight.pins[{i}]:IsShown()')]


def test_game_list_pins_this_faction_and_neutral_not_the_other(lua):
    boot(lua, MODERN + MAP + API)
    lua.execute('WorldMapFrame:Show(); HogHealsQuests.WorldMap.OnShow()')
    assert lua.eval('HogHealsQuests.WorldMap.Flight.drawn') == 2
    assert pins(lua) == ["Moonglade", "Nighthaven"]                              # Alliance's master left off
    # pin centre = fraction * canvas size, from the layer's top left
    p = lua.eval('{ HogHealsQuests.WorldMap.Flight.pins[1]:GetPoint(1) }')
    assert p[1] == "CENTER" and p[3] == "TOPLEFT"
    assert abs(p[4] - 320) < 1e-6 and abs(p[5] + 462) < 1e-6
    assert lua.eval('HogHealsQuests.WorldMap.Flight.pins[2].tex._desat') is True  # undiscovered = grey
    assert lua.eval('HogHealsQuests.WorldMap.Flight.pins[1].tex._desat') is False
    assert errors(lua) == []


def test_pins_keep_their_size_when_the_map_zooms(lua):
    boot(lua, MODERN + MAP + API)
    lua.execute('WorldMapFrame:Show(); HogHealsQuests.WorldMap.OnShow(); CS = 2; WorldMapFrame:OnCanvasScaleChanged()')
    assert lua.eval('HogHealsQuests.WorldMap.Flight.pins[1]._last.SetScale[1]') == 0.5
    p = lua.eval('{ HogHealsQuests.WorldMap.Flight.pins[1]:GetPoint(1) }')
    assert abs(p[4] - 640) < 1e-6                                               # offset in the pin's own (half) scale
    assert errors(lua) == []


def test_map_change_redraws(lua):
    boot(lua, MODERN + MAP + API)
    lua.execute('WorldMapFrame:Show(); HogHealsQuests.WorldMap.OnShow()')
    assert lua.eval('HogHealsQuests.WorldMap.Flight.drawn') == 2
    lua.execute('OPEN_MAP = 1429; WorldMapFrame:OnMapChanged()')
    assert lua.eval('HogHealsQuests.WorldMap.Flight.drawn') == 0 and pins(lua) == []
    assert errors(lua) == []


def test_opening_a_flight_map_teaches_the_master_and_every_stop(lua):
    boot(lua, MODERN + MAP + TAXI)                                               # no GetTaxiNodesForMap on this client
    lua.execute('MockFire("TAXIMAP_OPENED")')
    store = 'HogHeals.db.global.flightPoints.Horde'
    assert lua.eval(f'{store}["Moonglade"].npc') == "Faustron"
    assert lua.eval(f'{store}["Moonglade"].stood') is True
    # where you stood (Moonglade 0.321, 0.666 -> world 1321, 2466.2), not the flight map's dot
    assert lua.eval(f'{store}["Moonglade"].x') == 1321 and lua.eval(f'{store}["Moonglade"].y') == 2466.2
    assert lua.eval(f'{store}["Thunder Bluff, Mulgore"].c') == 1
    assert lua.eval(f'{store}["Thunder Bluff, Mulgore"].stood') is None
    # opened again later: the flight map's dot never moves a master you talked to
    lua.execute('MockUnits.npc = nil; PPOS = { 0.9, 0.9 }; PLAYER_MAP = 9999; MockFire("TAXIMAP_OPENED")')
    assert lua.eval(f'{store}["Moonglade"].x') == 1321
    # the map: Moonglade's pin where you stood; Thunder Bluff is on Kalimdor but off the Moonglade map
    lua.execute('WorldMapFrame:Show(); HogHealsQuests.WorldMap.OnShow()')
    assert pins(lua) == ["Moonglade"]
    assert lua.eval('HogHealsQuests.WorldMap.Flight.pins[1].node.npc') == "Faustron"
    # the continent map shows both
    lua.execute('OPEN_MAP = 1414; WorldMapFrame:OnMapChanged()')
    assert pins(lua) == ["Moonglade", "Thunder Bluff, Mulgore"]
    assert errors(lua) == []


def test_a_learned_point_never_lands_on_another_continent(lua):
    boot(lua, MODERN + MAP + TAXI)
    lua.execute('MockFire("TAXIMAP_OPENED"); OPEN_MAP = 1429; WorldMapFrame:Show(); HogHealsQuests.WorldMap.OnShow()')
    # Elwynn has Moonglade's numbers on continent 0: the fake client would place it, the addon must not
    assert pins(lua) == []
    assert errors(lua) == []


def test_learned_and_listed_master_is_one_pin_with_the_npc_name(lua):
    boot(lua, MODERN + MAP + TAXI)
    lua.execute('MockFire("TAXIMAP_OPENED")')
    lua.execute(API)                                                             # the client now lists nodes too
    lua.execute('WorldMapFrame:Show(); HogHealsQuests.WorldMap.OnShow()')
    assert pins(lua) == ["Moonglade", "Nighthaven"]
    assert lua.eval('HogHealsQuests.WorldMap.Flight.pins[1].node.source') == "api"
    assert lua.eval('HogHealsQuests.WorldMap.Flight.pins[1].node.npc') == "Faustron"
    assert errors(lua) == []


def test_tooltip_names_the_master(lua):
    boot(lua, MODERN + MAP + TAXI)
    lua.execute('MockFire("TAXIMAP_OPENED"); WorldMapFrame:Show(); HogHealsQuests.WorldMap.OnShow()')
    lua.execute('local p = HogHealsQuests.WorldMap.Flight.pins[1]; p._scripts.OnEnter(p); p._scripts.OnLeave(p)')
    assert lua.eval('GameTooltip:GetText()') == "Moonglade"
    lines = list(lua.eval('GameTooltip._lines').values())
    assert lines[-2:] == ["Flight master: Faustron", "Remembered from a flight map you opened"]
    assert lua.eval('GameTooltip:IsShown()') is False                             # Region:Hide on leave
    assert errors(lua) == []


def test_secret_names_and_positions_are_skipped_not_errors(lua):
    boot(lua, MODERN + MAP + r'''
      C_TaxiMap = { GetTaxiNodesForMap = function()
        return { { name = MockSecret("Moonglade"), position = CreateVector2D(MockSecret(0.3), MockSecret(0.6)), faction = 1 },
                 { name = MockSecret("Nighthaven"), position = CreateVector2D(0.44, 0.46), faction = 0 },
                 { name = "Secret side", position = CreateVector2D(0.5, 0.5), faction = MockSecret(2) } }
      end, GetAllTaxiNodes = function() return { { name = MockSecret("X"), position = CreateVector2D(0.1, 0.1), state = MockSecret(0) } } end }
      function GetTaxiMapID() return 1414 end''')
    lua.execute('MockSetSecrets(true); MockState.secretNames = true; MockUnits.npc = { name = "Faustron", class = "WARRIOR" }')
    lua.execute('MockFire("TAXIMAP_OPENED"); WorldMapFrame:Show(); HogHealsQuests.WorldMap.OnShow()')
    assert pins(lua) == ["Flight master"]            # placeable, name hidden -> generic; secret faction -> left off
    assert errors(lua) == []


def test_off_draws_nothing_and_learns_nothing(lua):
    boot(lua, MODERN + MAP + API + '''
      C_TaxiMap.GetAllTaxiNodes = function() return { { name = "Moonglade", position = CreateVector2D(0.1321, 0.3466), state = 0 } } end
      function GetTaxiMapID() return 1414 end
      MockUnits.npc = { name = "Faustron", class = "WARRIOR" }''')
    lua.execute('WorldMapFrame:Show(); HogHealsQuests.WorldMap.OnShow()')
    assert lua.eval('HogHealsQuests.WorldMap.Flight.drawn') == 2
    lua.execute('HogHeals.db.profile.quests.worldMap.flightMasters = false; HogHealsQuests.WorldMap.Refresh()')
    assert lua.eval('HogHealsQuests.WorldMap.Flight.layer:IsShown()') is False
    assert lua.eval('HogHealsQuests.WorldMap.Flight.Learn()') == 0
    assert lua.eval('next(HogHealsQuests.WorldMap.Flight.Store())') is None      # nothing remembered while off
    assert errors(lua) == []


def test_no_taxi_api_at_all_is_fine_and_the_diag_says_so(lua):
    boot(lua, MODERN + MAP)
    lua.execute('WorldMapFrame:Show(); HogHealsQuests.WorldMap.OnShow(); MockFire("TAXIMAP_OPENED")')
    assert lua.eval('HogHealsQuests.WorldMap.Flight.drawn') == 0
    lua.execute('HogHeals:SlashCommand("flightdiag")')
    f = 'HogHeals.db.global.diag.quests.flight'
    assert lua.eval(f'{f}.api') == "no C_TaxiMap.GetTaxiNodesForMap"
    assert lua.eval(f'{f}.C_TaxiMap') == "nil"
    assert lua.eval(f'{f}.event') == "TAXIMAP_OPENED"
    assert errors(lua) == []


def test_unknown_event_is_recorded_not_thrown(lua):
    lua.execute('MockUnknownEvents.TAXIMAP_OPENED = true')
    boot(lua, MODERN + MAP)
    assert lua.eval('HogHealsQuests.WorldMap.Flight.eventOK') is False
    assert errors(lua) == []
