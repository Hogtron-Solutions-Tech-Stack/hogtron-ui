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
-- friendliness like the client: an explicit flag wins, else the reaction (unset = a mob = not a friend)
function UnitIsFriend(a, b) local m = MockUnits[b] if m and m.friendly ~= nil then return m.friendly end local r = REACT[b] return r ~= nil and r >= 5 end
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
    plates.execute('HogHeals.db.profile.plates.target.fadeOthers = true')
    assert plates.eval(f'{uf}.hh.why') == "quest"
    plates.execute('TARGET = "nameplate3"; MockFire("PLAYER_TARGET_CHANGED")')
    assert plates.eval(f'{uf}.hh.why') == "target"
    assert plates.eval(f'{uf}.hh.glows[3]:IsShown()') is True                     # glow, not a box, not bigger
    assert plates.eval(f'{uf}.hh.scale') == 1
    # the glow owns the target's edge: plain dark line, no amber inside the cyan (2026-09-24); the ! badge stays
    assert plates.eval(f'{uf}.hh.edges[1]._color[2]') == pytest.approx(0.05)
    assert plates.eval(f'{uf}.hh.questFrame:IsShown()') is True
    assert plates.eval(f'{other}.hh.glows[1]:IsShown()') is False
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


def test_plate_cast_bar_flattened_once(plates):
    plates.execute("""
      local p = MockPlate("nameplate8", { name = "Caster", class = "MAGE", health = 5, maxHealth = 5, guid = "C-80" })
      p.UnitFrame.castBar = CreateFrame("StatusBar", nil, p.UnitFrame)
      p.UnitFrame.castBar.Border = p.UnitFrame.castBar:CreateTexture()
      p.UnitFrame.castBar.Text = p.UnitFrame.castBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      MockFire("NAME_PLATE_UNIT_ADDED", "nameplate8")
    """)
    uf = 'NP.nameplate8.UnitFrame'
    assert plates.eval(f'{uf}.castBar._texture').endswith("WHITE8X8")
    assert plates.eval(f'{uf}.castBar.Border._alpha') == 0
    assert plates.eval(f'#{uf}.hh.castEdges') == 4
    plates.execute('HogHealsPlates.Plates.ApplyLook(NP.nameplate8.UnitFrame)')
    assert plates.eval(f'#{uf}.hh.castEdges') == 4                       # not re-skinned
    assert errors(plates) == []


def test_friendly_player_name_in_class_colour_and_kept_after_blizzard_repaints(plates):
    plates.execute('function UnitIsFriend(a, b) return MockUnits[b] and MockUnits[b].friendly == true end')
    uf = add(plates, "nameplate10", '{ name = "Anthony", class = "PALADIN", health = 1, maxHealth = 1, isPlayer = true, friendly = true, guid = "P-10" }')
    assert plates.eval(f'{uf}.name._color[1]') == pytest.approx(0.96, abs=0.02)      # paladin pink
    plates.execute(f'{uf}.name:SetTextColor(1, 1, 1)')                                 # Blizzard repaint
    assert plates.eval(f'{uf}.name._color[2]') == pytest.approx(0.55, abs=0.02)
    # hostile player: untouched by default, coloured with "all"
    hostile = add(plates, "nameplate11", '{ name = "Zug", class = "MAGE", health = 1, maxHealth = 1, isPlayer = true, friendly = false, guid = "P-11" }')
    assert plates.eval(f'{hostile}.hh.nameClass') is None
    plates.execute('HogHeals.db.profile.plates.nameClass = "all"; HogHealsPlates.Plates.Refresh()')
    assert plates.eval(f'{hostile}.name._color[3]') == pytest.approx(0.94, abs=0.02)
    # NPCs never
    npc = add(plates, "nameplate12", '{ name = "Guard", class = "WARRIOR", health = 1, maxHealth = 1, isPlayer = false, friendly = true, guid = "C-12" }')
    assert plates.eval(f'{npc}.hh.nameClass') is None
    assert errors(plates) == []


def test_name_colour_survives_blizzard_vertex_repaint_and_cvars_set(plates):
    plates.execute('function UnitIsFriend(a, b) return true end; CV = {}; function SetCVar(k, v) CV[k] = v end; HogHealsPlates.Plates.ApplyCVars()')
    uf = add(plates, "nameplate13", '{ name = "Bob", class = "DRUID", health = 1, maxHealth = 1, isPlayer = true, guid = "P-13" }')
    plates.execute(f'{uf}.name:SetVertexColor(1, 1, 1)')                              # how Blizzard repaints plate names
    assert plates.eval(f'{uf}.name._color[1]') == pytest.approx(1.0) and plates.eval(f'{uf}.name._color[2]') == pytest.approx(0.49, abs=0.02)  # druid orange
    assert plates.eval('CV.ShowClassColorInFriendlyNameplate') == "1" and plates.eval('CV.ShowClassColorInNameplate') == "1"


def test_friendly_plates_are_name_only_by_default_and_full_when_off(plates):
    plates.execute('function UnitIsFriend(a, b) return MockUnits[b] and MockUnits[b].friendly == true end')
    uf = add(plates, "nameplate14", '{ name = "Anthony", class = "PALADIN", health = 1, maxHealth = 1, isPlayer = true, friendly = true, guid = "P-14" }')
    assert plates.eval(f'{uf}.healthBar:IsShown()') is False
    assert plates.eval(f'{uf}.hh.health:IsShown()') is False and plates.eval(f'{uf}.hh.edges[1]:IsShown()') is False
    assert plates.eval(f'{uf}.name._color[1]') == pytest.approx(0.96, abs=0.02)   # class-coloured name stays
    plates.execute(f'{uf}.healthBar:Show()')                                        # Blizzard re-shows on reuse
    assert plates.eval(f'{uf}.healthBar:IsShown()') is False
    hostile = add(plates, "nameplate15", '{ name = "Kobold", class = "WARRIOR", health = 5, maxHealth = 5, friendly = false, guid = "C-15" }')
    assert plates.eval(f'{hostile}.healthBar:IsShown()') is True
    plates.execute('HogHeals.db.profile.plates.friendlyNameOnly = false; HogHealsPlates.Plates.Refresh()')
    assert plates.eval(f'{uf}.healthBar:IsShown()') is True
    assert errors(plates) == []


def test_level_badge_hidden_by_default_kept_hidden_and_friendly_name_bigger(plates):
    plates.execute("""
      local p = MockPlate("nameplate16", { name = "Kobold", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-16" })
      p.UnitFrame.LevelFrame = CreateFrame("Frame", nil, p.UnitFrame)
      MockFire("NAME_PLATE_UNIT_ADDED", "nameplate16")
    """)
    uf = 'NP.nameplate16.UnitFrame'
    assert plates.eval(f'{uf}.LevelFrame:IsShown()') is False
    plates.execute(f'{uf}.LevelFrame:Show()')                                       # Blizzard re-show
    assert plates.eval(f'{uf}.LevelFrame:IsShown()') is False
    plates.execute('HogHeals.db.profile.plates.showLevel = true; HogHealsPlates.Plates.Refresh()')
    assert plates.eval(f'{uf}.LevelFrame:IsShown()') is True                        # hostile plate, option on
    plates.execute("""
      local p = MockPlate("nameplate17", { name = "Friend", class = "MAGE", health = 1, maxHealth = 1, isPlayer = true, friendly = true, guid = "P-17" })
      p.UnitFrame.LevelFrame = CreateFrame("Frame", nil, p.UnitFrame)
      MockFire("NAME_PLATE_UNIT_ADDED", "nameplate17")
    """)
    assert plates.eval('NP.nameplate17.UnitFrame.LevelFrame:IsShown()') is False   # never on name-only plates
    assert plates.eval('NP.nameplate17.UnitFrame.name._last.SetFont[2]') == 14      # bigger friendly name
    assert plates.eval(f'{uf}.name._last.SetFont[2]') == 13                          # hostile keeps the normal font
    assert errors(plates) == []


def test_uniform_plate_scale_cvars(plates):
    plates.execute('CV = {}; function SetCVar(k, v) CV[k] = v end; HogHeals.db.profile.plates.targetScale = 1.15; HogHealsPlates.Plates.ApplyCVars()')
    assert plates.eval('CV.nameplateMinScale') == "1" and plates.eval('CV.nameplateMinAlpha') == "1"
    assert plates.eval('CV.nameplateSelectedScale') == "1.15"
    plates.execute('wipe(CV); HogHeals.db.profile.plates.uniformScale = false; HogHealsPlates.Plates.ApplyCVars()')
    assert plates.eval('CV.nameplateMinScale') is None                              # off: the client's own rules


def test_plate_distance_cvar_and_untruncated_friendly_names(plates):
    plates.execute('CV = {}; function SetCVar(k, v) CV[k] = v end; HogHealsPlates.Plates.ApplyCVars()')
    assert plates.eval('CV.nameplateMaxDistance') == "60"
    plates.execute('HogHeals.db.profile.plates.maxDistance = 40; HogHealsPlates.Plates.ApplyCVars()')
    assert plates.eval('CV.nameplateMaxDistance') == "40"
    # name-only plate: the name string is as wide as its text (in game "Benjamin Neta..." at Blizzard's width)
    plates.execute('function UnitIsFriend(a, b) return MockUnits[b] and MockUnits[b].friendly == true end')
    uf = add(plates, "nameplate16", '{ name = "Benjamin Netanyahu", class = "PALADIN", health = 1, maxHealth = 1, isPlayer = true, friendly = true, guid = "P-16" }')
    assert plates.eval(f'{uf}.hh.nameOnly') is True
    plates.execute(f'{uf}.name:SetWidth(90); HogHealsPlates.Plates.FriendlyLook({uf})')
    assert plates.eval(f'{uf}.name._width') == 0
    assert errors(plates) == []


def test_recycled_plate_goes_back_to_a_full_plate(plates):
    # in game 2026-09-23 (picture 2): a bear on a plate that had just held a friendly player showed no bar and a big name
    plates.execute('function UnitIsFriend(a, b) return MockUnits[b] and MockUnits[b].friendly == true end')
    uf = add(plates, "nameplate20", '{ name = "Anthony", class = "PALADIN", health = 1, maxHealth = 1, isPlayer = true, friendly = true, guid = "P-20" }')
    assert plates.eval(f'{uf}.healthBar:IsShown()') is False and plates.eval(f'{uf}.name._last.SetFont[2]') == 14
    plates.execute('MockFire("NAME_PLATE_UNIT_REMOVED", "nameplate20")')
    assert plates.eval(f'{uf}.hh.nameOnly') is False and plates.eval(f'{uf}.healthBar:IsShown()') is True
    plates.execute('MockUnits.nameplate20 = { name = "Ferocious Grizzled Bear", class = "WARRIOR", health = 9, maxHealth = 9, friendly = false, guid = "C-20b" }; REACT.nameplate20 = 2; MockFire("NAME_PLATE_UNIT_ADDED", "nameplate20")')
    assert plates.eval(f'{uf}.healthBar:IsShown()') is True
    assert plates.eval(f'{uf}.hh.nameOnly') is False
    assert plates.eval(f'{uf}.name._last.SetFont[2]') == 13
    assert plates.eval(f'{uf}.name._width') == 0                                    # never truncated
    assert plates.eval(f'{uf}.hh.bar._height') == 14
    assert errors(plates) == []


def test_target_mark_styles_and_size_cvars(plates):
    uf = add(plates, "nameplate21", '{ name = "Kobold", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-21" }')
    plates.execute('TARGET = "nameplate21"; MockFire("PLAYER_TARGET_CHANGED")')
    assert plates.eval(f'{uf}.hh.glow:IsShown()') is True and plates.eval(f'{uf}.hh.scale') == 1
    assert plates.eval(f'#{uf}.hh.glows') == 8                                      # 9-slice: 4 corners + 4 edges
    assert plates.eval(f'{uf}.name._points[1][1]') == "BOTTOM" and plates.eval(f'{uf}.name._points[1][3]') == "TOP"       # name centred over the bar
    plates.execute('HogHeals.db.profile.plates.target.style = "scale"; HogHealsPlates.Plates.Refresh()')
    assert plates.eval(f'{uf}.hh.glow:IsShown()') is False and plates.eval(f'{uf}.hh.scale') == 1.25
    plates.execute('HogHeals.db.profile.plates.target.style = "outline"; HogHealsPlates.Plates.Refresh()')
    assert plates.eval(f'{uf}.hh.edges[1]._color[2]') == pytest.approx(0.83) and plates.eval(f'{uf}.hh.glow:IsShown()') is False
    plates.execute('HogHeals.db.profile.plates.target.style = "none"; HogHealsPlates.Plates.Refresh()')
    assert plates.eval(f'{uf}.hh.why') == "target" and plates.eval(f'{uf}.hh.edges[1]._color[2]') == pytest.approx(0.05)
    assert plates.eval(f'{uf}.hh.scale') == 1
    plates.execute('HogHeals.db.profile.plates.target.style = "glow"; HogHealsPlates.Plates.Refresh(); TARGET = nil; MockFire("PLAYER_TARGET_CHANGED")')
    assert plates.eval(f'{uf}.hh.glow:IsShown()') is False                          # off when untargeted
    # aggro outline sits on top of the target mark
    plates.execute('TARGET = "nameplate21"; THREAT.nameplate21 = 3; MockFire("UNIT_THREAT_SITUATION_UPDATE", "nameplate21")')
    assert plates.eval(f'{uf}.hh.why') == "aggro" and plates.eval(f'{uf}.hh.glow:IsShown()') is True
    assert plates.eval(f'{uf}.hh.edges[1]._color[1]') == pytest.approx(0.85)
    plates.execute('CV = {}; function SetCVar(k, v) CV[k] = v end; HogHealsPlates.Plates.ApplyCVars()')
    assert plates.eval('CV.nameplateHorizontalScale') == "1.3" and plates.eval('CV.nameplateSelectedScale') == "1.15"
    assert errors(plates) == []


def test_a_failing_plate_piece_is_named_and_the_rest_still_runs(plates):
    plates.execute('HogHealsPlates.Plates.UpdateHighlight = function() error("boom highlight") end')
    uf = add(plates, "nameplate22", '{ name = "Kobold", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-22" }')
    assert plates.eval(f'{uf}.hh.health:IsShown()') is True                         # health piece still ran
    assert any("plates highlight" in e for e in errors(plates))


def test_questmob_report_explains_a_target(plates):
    add(plates, "nameplate30", '{ name = "Vile Fin Shredder", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-30" }')
    plates.execute('TARGET = "nameplate30"; MockUnits.target = MockUnits.nameplate30; TT.target = { { leftText = "Vile Fin Shredder", type = 2 } }')
    lines = plates.eval('table.concat(HogHealsPlates.Plates.QuestMobReport("target"), "\\n")')
    assert "target: Vile Fin Shredder" in lines and "from tooltip: nil" in lines and "from name:" in lines and "Check() now:" in lines
    plates.execute('TT.target = { { leftText = "Vile Fin Shredder", type = 2 }, { leftText = "Wild Eyes", type = 17 }, { leftText = " - Murloc Eye: 1/3", type = 8 } }')
    lines = plates.eval('table.concat(HogHealsPlates.Plates.QuestMobReport("target"), "\\n")')
    assert "from tooltip: 1/3" in lines


# ------------------------------------------------------------------------------------------------ target glow v2
# Sean 2026-09-24: the three stacked flat rectangles "look terrible". Now one soft texture in a 9-slice around the
# bar, additive, that locks on (wide + faint -> tight + bright in 0.3 s) and then breathes.
def tick(lua, sec):
    lua.execute(f'MockAdvance({sec}); local d = HogHealsPlates.Plates.driver; if d and d:IsShown() then d._scripts.OnUpdate(d, {sec}) end')


def test_target_glow_is_a_soft_9slice_that_locks_on_then_breathes(plates):
    uf = add(plates, "nameplate40", '{ name = "Moonrage Glutton", class = "WARRIOR", health = 4, maxHealth = 10, guid = "C-40" }')
    plates.execute('TARGET = "nameplate40"; MockFire("PLAYER_TARGET_CHANGED")')
    g = f'{uf}.hh.glows'
    assert plates.eval(f'#{g}') == 8
    for i in range(1, 9):
        assert plates.eval(f'{g}[{i}]:IsShown()') is True
        assert plates.eval(f'{g}[{i}]._texture').endswith("Media\\target_glow")
        assert plates.eval(f'{g}[{i}]._blend') == "ADD"
        assert plates.eval(f'{g}[{i}]._layer') == "BACKGROUND"                     # under the bar's own frame + the name
    assert list(plates.eval(f'{g}[1]._texCoord').values()) == [0, 0.5, 0, 0.5]      # top-left corner = top-left quadrant
    assert plates.eval(f'{g}[5]._texCoord[1]') == pytest.approx(31.5 / 64)        # top edge = the centre column
    assert plates.eval(f'{uf}.hh.glowArt') == "ok"
    # lock-on: starts wide and invisible ...
    assert plates.eval(f'{uf}.hh.glowSpread') == pytest.approx(9 * 2.2)
    assert plates.eval(f'{uf}.hh.glowAlpha') == pytest.approx(0)
    assert plates.eval('HogHealsPlates.Plates.driver:IsShown()') is True
    tick(plates, 0.15)
    mid_spread = plates.eval(f'{uf}.hh.glowSpread')
    assert 9 < mid_spread < 9 * 2.2 and plates.eval(f'{uf}.hh.glowAlpha') > 0
    # ... lands on the bar at full strength ...
    tick(plates, 0.15)
    assert plates.eval(f'{uf}.hh.glowSpread') == pytest.approx(9)
    assert plates.eval(f'{uf}.hh.glowAlpha') == pytest.approx(0.8)
    assert plates.eval(f'{g}[1]._width') == pytest.approx(9) and plates.eval(f'{g}[5]._height') == pytest.approx(9)
    assert plates.eval(f'{g}[7]._width') == pytest.approx(9)
    c = list(plates.eval(f'{g}[3]._color').values())
    assert c[:3] == pytest.approx([0.13, 0.83, 0.88])
    # ... then breathes: dimmest + slightly tighter half a period later, back to full a period later
    tick(plates, 1.2)
    assert plates.eval(f'{uf}.hh.glowAlpha') == pytest.approx(0.55 * 0.8)
    assert plates.eval(f'{uf}.hh.glowSpread') == pytest.approx(9 * 0.88)
    tick(plates, 1.2)
    assert plates.eval(f'{uf}.hh.glowAlpha') == pytest.approx(0.8)
    # a threat / quest update while targeted must not restart the lock-on
    t0 = plates.eval(f'{uf}.hh.glowT0')
    plates.execute('MockFire("UNIT_THREAT_SITUATION_UPDATE", "nameplate40")')
    assert plates.eval(f'{uf}.hh.glowT0') == t0 and plates.eval(f'{uf}.hh.glowAlpha') == pytest.approx(0.8)
    # untarget: dark, driver parked (an idle plate costs nothing)
    plates.execute('TARGET = nil; MockFire("PLAYER_TARGET_CHANGED")')
    assert plates.eval(f'{g}[1]:IsShown()') is False and plates.eval(f'{g}[8]:IsShown()') is False
    assert plates.eval('HogHealsPlates.Plates.driver:IsShown()') is False
    assert plates.eval('next(HogHealsPlates.Plates.lit) == nil') is True
    # retarget = a fresh lock-on
    tick(plates, 5)
    plates.execute('TARGET = "nameplate40"; MockFire("PLAYER_TARGET_CHANGED")')
    assert plates.eval(f'{uf}.hh.glowSpread') == pytest.approx(9 * 2.2)
    assert errors(plates) == []


def test_glow_curve_is_continuous_and_bounded(plates):
    at = 'HogHealsPlates.Plates.GlowAt'
    s0, a0 = plates.eval(f'{{{at}(0, true)}}').values()
    assert s0 == pytest.approx(2.2) and a0 == pytest.approx(0)
    s1, a1 = plates.eval(f'{{{at}(0.2999, true)}}').values()
    s2, a2 = plates.eval(f'{{{at}(0.3, true)}}').values()
    assert s1 == pytest.approx(s2, abs=1e-3) and a1 == pytest.approx(a2, abs=1e-3)   # no jump where lock-on hands over
    for i in range(200):
        s, a = plates.eval(f'{{{at}({0.3 + i * 0.037}, true)}}').values()
        assert 0.88 - 1e-9 <= s <= 1 + 1e-9 and 0.55 - 1e-9 <= a <= 1 + 1e-9
    assert list(plates.eval(f'{{{at}(9, false)}}').values()) == [1, pytest.approx(0.85)]   # still: no motion


def test_still_glow_when_animation_is_off_and_live_option_changes(plates):
    uf = add(plates, "nameplate41", '{ name = "Kobold", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-41" }')
    plates.execute('HogHeals.db.profile.plates.target.animate = false')
    plates.execute('TARGET = "nameplate41"; MockFire("PLAYER_TARGET_CHANGED")')
    assert plates.eval(f'{uf}.hh.glowSpread') == pytest.approx(9) and plates.eval(f'{uf}.hh.glowAlpha') == pytest.approx(0.85 * 0.8)
    assert plates.eval('HogHealsPlates.Plates.driver == nil or not HogHealsPlates.Plates.driver:IsShown()') is True
    plates.execute('local t = HogHeals.db.profile.plates.target; t.glowSize = 11; t.color = { 1, 0.5, 0 }; HogHealsPlates.Plates.Refresh()')
    assert plates.eval(f'{uf}.hh.glowSpread') == pytest.approx(11)
    assert plates.eval(f'{uf}.hh.glows[2]._width') == pytest.approx(11)
    assert list(plates.eval(f'{uf}.hh.glows[6]._color').values())[:3] == pytest.approx([1, 0.5, 0])
    # animation back on mid-target: the driver starts
    plates.execute('HogHeals.db.profile.plates.target.animate = true; HogHealsPlates.Plates.Refresh()')
    assert plates.eval('HogHealsPlates.Plates.driver:IsShown()') is True
    assert errors(plates) == []


def test_target_glow_quiets_blizzards_selection_highlight(plates):
    uf = add(plates, "nameplate42", '{ name = "Kobold Tunneler", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-42" }',
             '{ { leftText = "Kobold Tunneler", type = 2 }, { leftText = " - Kobold Tunneler slain: 1/5", type = 8 } }')
    plates.execute(f'local u = {uf}; u.selectionHighlight = u:CreateTexture(nil, "ARTWORK"); u.selectionHighlight:SetAlpha(1); u.selectionHighlight:Show()')
    assert plates.eval(f'{uf}.hh.edges[1]._color[2]') == pytest.approx(0.65)        # quest amber when not targeted
    plates.execute('TARGET = "nameplate42"; MockFire("PLAYER_TARGET_CHANGED")')
    assert plates.eval(f'{uf}.selectionHighlight._alpha') == 0
    pieces = "\n".join(plates.eval('HogHeals.db.global.diag.plateTarget.pieces').values())
    assert "selectionHighlight shown=true" in pieces                                # diag names what Blizzard drew
    plates.execute('TARGET = nil; MockFire("PLAYER_TARGET_CHANGED")')
    assert plates.eval(f'{uf}.selectionHighlight._alpha') == 1
    assert plates.eval(f'{uf}.hh.edges[1]._color[2]') == pytest.approx(0.65)        # amber back once it is not the target
    plates.execute('HogHeals.db.profile.plates.target.hideBlizzard = false; TARGET = "nameplate42"; MockFire("PLAYER_TARGET_CHANGED")')
    assert plates.eval(f'{uf}.selectionHighlight._alpha') == 1
    lines = "\n".join(plates.eval('HogHealsPlates.Plates.Diagnose()').values())
    assert "target glow: art=ok lit=true driver=true" in lines and "blizzard selectionHighlight" in lines
    assert errors(plates) == []


def test_glow_paint_error_stops_the_animation_once_not_every_frame(plates):
    uf = add(plates, "nameplate43", '{ name = "Kobold", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-43" }')
    plates.execute('TARGET = "nameplate43"; MockFire("PLAYER_TARGET_CHANGED")')
    plates.execute('HogHealsPlates.Plates.PaintGlow = function() error("boom glow") end')
    tick(plates, 0.02)
    tick(plates, 0.02)
    assert sum("plates glow" in e for e in errors(plates)) == 1
    assert plates.eval('HogHealsPlates.Plates.driver:IsShown()') is False
    assert plates.eval(f'{uf}.hh.glows[1]:IsShown()') is True                       # still marked, just not moving
    # stays stopped: the next highlight update must not restart a driver that throws every frame
    plates.execute('MockFire("UNIT_THREAT_SITUATION_UPDATE", "nameplate43")')
    tick(plates, 0.02)
    tick(plates, 0.02)
    assert sum("plates glow" in e for e in errors(plates)) == 1
    assert plates.eval('HogHealsPlates.Plates.driver:IsShown()') is False


def test_recycled_plate_drops_the_glow(plates):
    uf = add(plates, "nameplate44", '{ name = "Kobold", class = "WARRIOR", health = 5, maxHealth = 5, guid = "C-44" }')
    plates.execute('TARGET = "nameplate44"; MockFire("PLAYER_TARGET_CHANGED")')
    plates.execute('MockFire("NAME_PLATE_UNIT_REMOVED", "nameplate44")')
    assert plates.eval(f'{uf}.hh.glows[4]:IsShown()') is False and plates.eval(f'{uf}.hh.lit') is False
    assert plates.eval('HogHealsPlates.Plates.driver:IsShown()') is False
