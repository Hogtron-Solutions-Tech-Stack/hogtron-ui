# HogHeals_Plates: decorate Blizzard's nameplates (structure measured on the Forever beta 2026-09-18), quest-mob icons,
# target / aggro / quest highlighting. Health can be SECRET in combat, tooltip strings too.
import pytest

PLATES = '''
Enum.TooltipDataLineType = { QuestObjective = 8, QuestTitle = 17, QuestPlayer = 18 }
NP = {}
function MockPlate(unit, spec)
  local plate = CreateFrame("Frame", nil, WorldFrame)
  local uf = CreateFrame("Button", nil, plate)
  uf.healthBar = CreateFrame("StatusBar", nil, uf)
  uf.name = uf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  plate.UnitFrame, plate.unitToken = uf, unit
  NP[unit] = plate
  MockUnits[unit] = spec
  return plate
end
C_NamePlate = {
  GetNamePlateForUnit = function(u) return NP[u] end,
  GetNamePlates = function() local t = {} for _, p in pairs(NP) do t[#t + 1] = p end return t end,
}
TT = {}
C_TooltipInfo = { GetUnit = function(u) local l = TT[u] if not l then return { lines = { { leftText = UnitName(u), type = 2 } } } end return { lines = l } end }
REACT = {}
function UnitReaction(u) return REACT[u] end
function UnitIsTapDenied() return false end
THREAT = {}
function UnitThreatSituation(a, b) if b then return THREAT[b] end return 0 end
TARGET = nil
function UnitIsUnit(a, b) if b == "target" then return TARGET == a end return a == b end
local _exists = UnitExists
function UnitExists(u) if u == "target" then return TARGET ~= nil end return _exists(u) end
function UnitIsPlayer(u) local m = MockUnits[u] return m ~= nil and m.isPlayer == true end
'''

QUESTLOG = '''
C_QuestLog = {
  GetNumQuestLogEntries = function() return 1 end,
  GetInfo = function() return { title = "Kobold Camp Cleanup", questID = 7, level = 2 } end,
  IsComplete = function() return false end,
  GetQuestObjectives = function() return { { text = "Kobold Vermin slain: 3/8", numFulfilled = 3, numRequired = 8 } } end,
  GetQuestWatchType = function() return 1 end,
}
'''


def boot(lua, extra="", quests=True):
    lua.execute(PLATES + extra + (QUESTLOG if quests else ""))
    lua.load_addon("HogHeals")
    if quests:
        lua.load_addon("HogHeals_Quests")
    lua.load_addon("HogHeals_Plates")
    lua.player_login()
    lua.execute('wipe(HogHeals.errors)')
    return lua


@pytest.fixture
def plates(lua):
    return boot(lua)


def errors(lua):
    return [e["msg"] for e in lua.eval('HogHeals.errors').values()]


def add(lua, unit, spec, tooltip=None):
    lua.execute(f'MockPlate("{unit}", {spec})')
    if tooltip:
        lua.execute(f'TT["{unit}"] = {tooltip}')
    lua.execute(f'MockFire("NAME_PLATE_UNIT_ADDED", "{unit}")')
    return f'NP["{unit}"].UnitFrame'


def test_plate_is_restyled(plates):
    uf = add(plates, "nameplate1", '{ name = "Young Wolf", class = "WARRIOR", health = 50, maxHealth = 100, guid = "C-1", isPlayer = false }')
    plates.execute('REACT.nameplate1 = 2; MockFire("UNIT_FACTION", "nameplate1")')
    assert plates.eval(f'{uf}.healthBar._texture') == "Interface\\Buttons\\WHITE8X8"
    assert plates.eval(f'{uf}.hh.health._text') == "50%"
    assert plates.eval(f'{uf}.healthBar._color[1]') == pytest.approx(0.85)     # hostile red
    assert plates.eval(f'{uf}.hh.why') == "plain"
    assert errors(plates) == []


def test_blizzard_recolour_is_undone_by_the_hook(plates):
    uf = add(plates, "nameplate1", '{ name = "Young Wolf", class = "WARRIOR", health = 50, maxHealth = 100, guid = "C-1" }')
    plates.execute(f'REACT.nameplate1 = 4; {uf}.healthBar:SetStatusBarColor(1, 0, 0)')
    assert plates.eval(f'{uf}.healthBar._color[2]') == pytest.approx(0.80)      # neutral yellow back on
    assert errors(plates) == []


def test_enemy_player_class_colour(plates):
    uf = add(plates, "nameplate2", '{ name = "Zug", class = "MAGE", health = 10, maxHealth = 10, guid = "P-9", isPlayer = true }')
    assert plates.eval(f'{uf}.healthBar._color[3]') == pytest.approx(0.94, abs=0.02)


def test_quest_mob_from_tooltip_lines(plates):
    uf = add(plates, "nameplate3", '{ name = "Kobold Tunneler", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-3" }',
             '{ { leftText = "Kobold Tunneler", type = 2 }, { leftText = "Kobold Camp Cleanup", type = 17 }, { leftText = " - Kobold Tunneler slain: 1/5", type = 8 } }')
    assert plates.eval(f'{uf}.hh.questFrame:IsShown()') is True
    assert plates.eval(f'{uf}.hh.progress._text') == "1/5"
    assert plates.eval(f'{uf}.hh.why') == "quest"
    assert plates.eval(f'{uf}.hh.questInfo.source') == "tooltip"


def test_finished_objective_is_not_a_quest_mob(plates):
    uf = add(plates, "nameplate3", '{ name = "Kobold Miner", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-4" }',
             '{ { leftText = "Kobold Miner", type = 2 }, { leftText = "Kobold Camp Cleanup", type = 17 }, { leftText = " - Kobold Miner slain: 5/5", type = 8 } }')
    assert plates.eval(f'{uf}.hh.questFrame:IsShown()') is False


def test_other_players_progress_is_ignored(plates):
    uf = add(plates, "nameplate3", '{ name = "Kobold Miner", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-5" }',
             '{ { leftText = "Kobold Miner", type = 2 }, { leftText = "Partyguy", type = 18 }, { leftText = " - Kobold Miner slain: 2/5", type = 8 } }')
    assert plates.eval(f'{uf}.hh.questFrame:IsShown()') is False


def test_quest_mob_by_name_when_tooltip_has_no_quest_lines(plates):
    uf = add(plates, "nameplate4", '{ name = "Kobold Vermin", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-6" }')
    assert plates.eval(f'{uf}.hh.questInfo.source') == "name"
    assert plates.eval(f'{uf}.hh.progress._text') == "3/8"


def test_name_fallback_needs_the_quests_addon(lua):
    boot(lua, quests=False)
    uf = add(lua, "nameplate4", '{ name = "Kobold Vermin", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-6" }')
    assert lua.eval(f'{uf}.hh.questInfo') is None
    assert errors(lua) == []


def test_secret_tooltip_text_is_skipped_not_matched(plates):
    plates.execute('MockSetSecrets(true)')
    uf = add(plates, "nameplate5", '{ name = "Hogger", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-7" }',
             '{ { leftText = MockSecret("Hogger"), type = 2 }, { leftText = MockSecret(" - Hogger slain: 0/1"), type = 8 } }')
    assert plates.eval(f'{uf}.hh.questFrame:IsShown()') is False
    assert errors(plates) == []


def test_secret_health_still_prints(plates):
    plates.execute('MockSetSecrets(true); AbbreviateNumbers = function(v) return tostring(MockUnwrap(v)) end')
    plates.execute('HogHeals.db.profile.plates.healthText = "percent"')
    uf = add(plates, "nameplate6", '{ name = "Boar", class = "WARRIOR", health = 42, maxHealth = 80, guid = "C-8" }')
    # no UnitHealthPercent in the mock + secret health = no division allowed: falls back to the value
    assert plates.eval(f'{uf}.hh.health._text') == "42"
    plates.execute('CurveConstants = { ScaleTo100 = 1 }; function UnitHealthPercent(u, p, c) return MockSecret(52.5) end; MockFire("UNIT_HEALTH", "nameplate6")')
    assert plates.eval(f'{uf}.hh.health._text') == "52%"
    assert errors(plates) == []


def test_highlight_priority_aggro_over_target_over_quest(plates):
    uf = add(plates, "nameplate3", '{ name = "Kobold Tunneler", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-3" }',
             '{ { leftText = "Kobold Tunneler", type = 2 }, { leftText = " - Kobold Tunneler slain: 1/5", type = 8 } }')
    other = add(plates, "nameplate9", '{ name = "Rabbit", class = "WARRIOR", health = 1, maxHealth = 1, guid = "C-9" }')
    assert plates.eval(f'{uf}.hh.why') == "quest"
    plates.execute('TARGET = "nameplate3"; MockFire("PLAYER_TARGET_CHANGED")')
    assert plates.eval(f'{uf}.hh.why') == "target"
    assert plates.eval(f'{uf}.hh.edges[1]._color[2]') == pytest.approx(0.83)
    assert plates.eval(f'{other}._alpha') == pytest.approx(0.6) and plates.eval(f'{uf}._alpha') == 1
    plates.execute('THREAT.nameplate3 = 3; MockFire("UNIT_THREAT_SITUATION_UPDATE", "nameplate3")')
    assert plates.eval(f'{uf}.hh.why') == "aggro"
    plates.execute('TARGET = nil; MockFire("PLAYER_TARGET_CHANGED")')
    assert plates.eval(f'{other}._alpha') == 1


def test_recycled_plate_drops_the_old_units_quest_icon(plates):
    uf = add(plates, "nameplate3", '{ name = "Kobold Vermin", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-3" }')
    assert plates.eval(f'{uf}.hh.questFrame:IsShown()') is True
    plates.execute('MockFire("NAME_PLATE_UNIT_REMOVED", "nameplate3")')
    assert plates.eval(f'{uf}.hh.questFrame:IsShown()') is False
    assert plates.eval('HogHealsPlates.Plates.active.nameplate3') is None


def test_quest_log_change_refreshes_icons(plates):
    uf = add(plates, "nameplate4", '{ name = "Kobold Vermin", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-6" }')
    plates.execute('''
      C_QuestLog.GetQuestObjectives = function() return { { text = "Kobold Vermin slain: 8/8", numFulfilled = 8, numRequired = 8 } } end
      HogHealsQuests.Data.List()
      MockFire("QUEST_LOG_UPDATE"); MockAdvance(1)
    ''')
    assert plates.eval(f'{uf}.hh.questFrame:IsShown()') is False


def test_forbidden_plate_is_left_alone(plates):
    plates.execute('local p = MockPlate("nameplate7", { name = "Guard", class = "WARRIOR", guid = "C-10" }); function p:IsForbidden() return true end')
    plates.execute('MockFire("NAME_PLATE_UNIT_ADDED", "nameplate7")')
    assert plates.eval('NP.nameplate7.UnitFrame.hh') is None
    assert errors(plates) == []


def test_restyle_off_leaves_colours_to_blizzard(plates):
    plates.execute('HogHeals.db.profile.plates.enabled = false')
    uf = add(plates, "nameplate1", '{ name = "Young Wolf", class = "WARRIOR", health = 50, maxHealth = 100, guid = "C-1" }')
    plates.execute(f'REACT.nameplate1 = 2; {uf}.healthBar:SetStatusBarColor(0.1, 0.2, 0.3)')
    assert plates.eval(f'{uf}.healthBar._color[1]') == pytest.approx(0.1)
    assert plates.eval(f'{uf}.healthBar._texture') is None


def test_reload_picks_up_existing_plates_and_diag_samples(lua):
    lua.execute(PLATES + QUESTLOG + 'MockPlate("nameplate1", { name = "Kobold Vermin", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-1" })')
    for a in ("HogHeals", "HogHeals_Quests", "HogHeals_Plates"):
        lua.load_addon(a)
    lua.player_login()
    assert lua.eval('NP.nameplate1.UnitFrame.hh.questFrame:IsShown()') is True
    s = lua.eval('HogHeals.db.global.diag.plates.samples[1]')
    assert s["name"] == "Kobold Vermin" and s["quest"].startswith("name") and s["hooked"] is True
    lua.execute('HogHeals:SlashCommand("platediag")')
    assert lua.eval('#HogHeals.errors') == 0


def test_unknown_events_do_not_break_enable(lua):
    lua.execute('MockUnknownEvents.UNIT_THREAT_LIST_UPDATE = true; MockUnknownEvents.UNIT_QUEST_LOG_CHANGED = true')
    boot(lua)
    uf = add(lua, "nameplate1", '{ name = "Kobold Vermin", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-1" }')
    assert lua.eval(f'{uf}.hh.questFrame:IsShown()') is True
    assert errors(lua) == []


def test_every_options_getter_runs(lua):
    boot(lua)
    lua.execute('''
      local function walk(t)
        for _, o in pairs(t.args or {}) do
          if o.get then o.get({}) end
          if type(o.name) == "function" then o.name() end
          if o.set and o.type == "toggle" then o.set({}, o.get({})) end
          if o.args then walk(o) end
        end
      end
      walk(HogHeals.OptionsTable())
    ''')
    assert lua.eval('HogHeals.OptionsTable().args.Plates.name') == "Nameplates"
    assert lua.eval('HogHeals.OptionsTable().args.Quests.name') == "Quests"
    assert errors(lua) == []


def test_platediag_explains_missing_plates(plates):
    plates.execute('local p = MockPlate("nameplate7", { name = "Guard", class = "WARRIOR", guid = "C-10" }); function p:IsForbidden() return true end')
    plates.execute('MockFire("NAME_PLATE_UNIT_ADDED", "nameplate7"); MockFire("NAME_PLATE_UNIT_ADDED", "nameplate99")')
    plates.execute('wipe(MockLog.chat or {}); HogHeals:SlashCommand("platediag")')
    chat = "\n".join(plates.eval('MockLog.chat').values())
    assert "ADDED=2" in chat
    assert "plate forbidden x1" in chat and "GetNamePlateForUnit(nameplateN)=nil x1" in chat
    assert "on screen now (GetNamePlates): 1" in chat
    assert errors(plates) == []


def test_quest_badge_sits_left_of_the_bar_clear_of_the_level_badge(plates):
    uf = add(plates, "nameplate4", '{ name = "Wandering Spirit", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-6" }',
             '{ { leftText = "Wandering Spirit", type = 2 }, { leftText = " - Wandering Spirit slain: 7/8", type = 8 } }')
    pt = plates.eval(f'{uf}.hh.questFrame._points[1]')
    assert pt[1] == "RIGHT" and pt[3] == "LEFT"                       # badge's right edge on the bar's left edge
    assert plates.eval(f'{uf}.hh.quest._texture').endswith("HogHeals\\Media\\quest_open")
    assert plates.eval(f'{uf}.hh.questGlyph:IsShown()') is False            # art loaded: no drawn fallback
    pp = plates.eval(f'{uf}.hh.progress._points[1]')
    assert pp[1] == "RIGHT" and pp[3] == "LEFT"                       # progress further left of the badge
    assert plates.eval(f'{uf}.hh.progress._text') == "7/8"


def test_quest_badge_falls_back_to_drawn_square_when_art_is_refused(lua):
    # a client that cannot load our .tga returns false from SetTexture: the marker must still show
    boot(lua, extra='''
      local mk = CreateFrame
      function CreateFrame(...)
        local f = mk(...)
        local ct = f.CreateTexture
        f.CreateTexture = function(self, ...)
          local t = ct(self, ...)
          local st = t.SetTexture
          t.SetTexture = function(tt, path) st(tt, path) if type(path) == "string" and path:find("HogHeals") then return false end end
          return t
        end
        return f
      end
    ''')
    uf = add(lua, "nameplate4", '{ name = "Kobold Vermin", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-6" }')
    assert lua.eval(f'{uf}.hh.questDrawn') is True
    assert lua.eval(f'{uf}.hh.questGlyph._text') == "!" and lua.eval(f'{uf}.hh.questGlyph:IsShown()') is True
    assert lua.eval(f'{uf}.hh.quest._color[1]') == pytest.approx(0.95)
