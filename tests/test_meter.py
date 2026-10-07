# HogHeals_Meter: our window over Blizzard's damage-meter data (C_DamageMeter). Restricted clients give addons no
# combat log, only these sessions, and the amounts are SECRET: no sorting or dividing by us. The widget does it:
# StatusBar min 0 / max = top amount / value = this amount, text via format/AbbreviateNumbers.
import pytest

MOCK_API = '''
MockSetSecrets(true)
HH_sources = {
  { name = "Hog Tistic", classFilename = "SHAMAN", totalAmount = MockSecret(7439), amountPerSecond = MockSecret(48), sourceGUID = "Player-1" },
  { name = "lol Fried",  classFilename = "WARLOCK", totalAmount = MockSecret(44),   amountPerSecond = MockSecret(0.3) },
  { name = "Vanco Sh",   classFilename = "ROGUE",  totalAmount = MockSecret(18),   amountPerSecond = MockSecret(0.1) },
}
HH_calls = {}
C_DamageMeter = {
  IsDamageMeterAvailable = function() return true end,
  GetAvailableCombatSessions = function() return { { sessionID = 3, encounterName = "Clattering Scorpid" } } end,
  GetCombatSessionFromType = function(a, b)
    HH_calls[#HH_calls + 1] = { a, b }
    return { sessionID = 3, encounterName = "Clattering Scorpid", combatSources = HH_sources, totalAmount = MockSecret(7501), maxAmount = MockSecret(7439), durationSeconds = 155 }
  end,
  GetSessionDurationSeconds = function() return MockSecret(155) end,
  GetCombatSessionSourceFromType = function(a, b, guid)
    HH_srcCalls = (HH_srcCalls or 0) + 1
    if guid ~= "Player-1" then return nil end
    return { sourceGUID = guid, name = "Hog Tistic", maxAmount = MockSecret(5000), totalAmount = MockSecret(7439),
      combatSpells = { { spellID = 1064, spellName = "Chain Heal", spellIcon = 136042, totalAmount = MockSecret(5000), hitCount = MockSecret(12) },
                       { spellID = 331, spellName = "Healing Wave", spellIcon = 136043, totalAmount = MockSecret(2439), hitCount = MockSecret(9) } } }
  end,
  ResetAllCombatSessions = function() HH_reset = true end,
}
Enum = Enum or {}
Enum.DamageMeterType = { DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4, Interrupts = 5, Dispels = 6, DamageTaken = 7, Deaths = 9 }
Enum.DamageMeterSessionType = { Current = 0, Overall = 1 }
DamageMeter = CreateFrame("Frame", "DamageMeter", UIParent)
AbbreviateNumbers = function(v) v = MockUnwrap(v) if v >= 1000 then return ("%.1fk"):format(v / 1000) end return tostring(v) end
'''


@pytest.fixture
def meter(lua):
    lua.execute(MOCK_API)
    for a in ("HogHeals", "HogHeals_Frames", "HogHeals_HUD", "HogHeals_Meter"):
        lua.load_addon(a)
    lua.player_login()
    lua.execute('wipe(HogHeals.errors)')
    return lua


def errors(lua):
    return [e["msg"] for e in lua.eval('HogHeals.errors').values()]


def test_module_registers_and_window_exists(meter):
    assert meter.eval('HogHeals.modules.Meter ~= nil')
    assert meter.eval('HogHealsMeterFrame ~= nil and type(HogHealsMeter) == "table"')
    assert meter.eval('HogHeals.defaults.profile.meter.enabled') is True
    assert errors(meter) == []


def test_rows_render_from_secret_amounts_without_any_maths(meter):
    meter.execute('HogHealsMeter.Meter.Update()')
    assert errors(meter) == []
    rows = meter.eval('HogHealsMeter.Meter.rows')
    r1 = 'HogHealsMeter.Meter.rows[1]'
    assert meter.eval(f'{r1}:IsShown()') is True
    assert meter.eval(f'{r1}.name._text') == "1. Hog Tistic"
    assert meter.eval(f'{r1}.bar._value') == 7439 and meter.eval(f'{r1}.bar._max') == 7439   # widget scales, we do not divide
    assert meter.eval('HogHealsMeter.Meter.rows[2].bar._value') == 44 and meter.eval('HogHealsMeter.Meter.rows[2].bar._max') == 7439
    assert "7.4k" in meter.eval(f'{r1}.value._text') and "48" in meter.eval(f'{r1}.value._text')
    assert meter.eval(f'{r1}.bar._color[3]') == pytest.approx(0.87, abs=0.01)   # shaman blue
    assert meter.eval('HogHeals.defaults.profile.meter.width') >= 300 and meter.eval('HogHeals.defaults.profile.meter.barHeight') >= 22


def test_class_colour_falls_back_to_the_group_roster_when_the_session_has_no_class(meter):
    # measured on the beta: names are not secret; the per-player class field name is still unknown
    meter.execute("""
      MockSetGroup(3, false)
      MockUnits.party1 = { name = "lol Fried", class = "WARLOCK", health = 1, maxHealth = 1, guid = "P1" }
      MockUnits.player.name = "Hog Tistic"; MockState.playerClass = "SHAMAN"
      HH_sources = { { name = "Hog Tistic", totalAmount = MockSecret(10) }, { name = "lol Fried", totalAmount = MockSecret(5) }, { name = "Stranger", totalAmount = MockSecret(1) } }
      HogHealsMeter.Meter.Update()
    """)
    r = 'HogHealsMeter.Meter.rows'
    assert meter.eval(f'{r}[1].bar._color[3]') == pytest.approx(0.87, abs=0.01)     # player: shaman
    assert meter.eval(f'{r}[2].bar._color[1]') == pytest.approx(0.53, abs=0.02)     # party1: warlock
    assert meter.eval(f'{r}[3].bar._color[1]') == pytest.approx(0.55, abs=0.02)     # unknown: grey


def test_class_id_is_accepted(meter):
    meter.execute("""
      GetClassInfo = function(id) if id == 7 then return "Shaman", "SHAMAN" end end
      HH_sources = { { name = "Someone", class = 7, totalAmount = MockSecret(10) } }
      HogHealsMeter.Meter.Update()
    """)
    assert meter.eval('HogHealsMeter.Meter.rows[1].bar._color[3]') == pytest.approx(0.87, abs=0.01)
    assert meter.eval('HogHealsMeter.Meter.rows[4]') is None or meter.eval('HogHealsMeter.Meter.rows[4]:IsShown()') is False


def test_default_mode_and_segment_are_asked_for_in_the_documented_order(meter):
    meter.execute('wipe(HH_calls); HogHealsMeter.Meter.Update()')
    call = list(meter.eval('HH_calls[1]').values())
    assert call == [0, 0]      # (Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageDone)


def test_mode_and_segment_switch_and_persist(meter):
    meter.execute('HogHealsMeter.Meter.SetMode("HealingDone"); HogHealsMeter.Meter.SetSegment("Overall")')
    assert meter.eval('HogHeals.db.profile.meter.mode') == "HealingDone"
    assert meter.eval('HogHeals.db.profile.meter.segment') == "Overall"
    call = list(meter.eval('HH_calls[#HH_calls]').values())
    assert call == [1, 2]
    assert "Healing" in meter.eval('HogHealsMeter.Meter.frame.title._text')
    assert "Overall" in meter.eval('HogHealsMeter.Meter.frame.title._text')


def test_shape_it_does_not_recognise_is_reported_once_not_thrown(meter):
    meter.execute('C_DamageMeter.GetCombatSessionFromType = function() return { weird = true, stuff = { 1, 2, 3 } } end')
    meter.execute('HogHealsMeter.Meter.Update(); HogHealsMeter.Meter.Update()')
    msgs = errors(meter)
    assert len(msgs) == 1 and "meter" in msgs[0].lower() and "shape" in msgs[0].lower()
    assert meter.eval('HogHealsMeter.Meter.rows[1]:IsShown()') is False


def test_no_api_means_module_stands_down_quietly(lua):
    lua.execute('C_DamageMeter = nil')
    for a in ("HogHeals", "HogHeals_Meter"):
        lua.load_addon(a)
    lua.player_login()
    assert lua.eval('HogHealsMeter.Meter.unavailable') is True
    assert lua.eval('HogHealsMeter ~= nil and (HogHealsMeter.Meter.frame == nil or HogHealsMeter.Meter.frame:IsShown() == false)')
    assert [e["msg"] for e in lua.eval('HogHeals.errors').values()] == []


def test_blizzard_meter_hidden_while_ours_is_on(meter):
    assert meter.eval('DamageMeter:IsShown()') is False
    assert meter.eval('DamageMeter:GetParent():GetName()') == "HogHealsHiddenParent"


def test_option_to_keep_blizzard_meter(meter):
    # Hiding is one-way per session (same as the party frames); with the option off we simply never touch it.
    meter.execute('DamageMeter2 = CreateFrame("Frame", "DamageMeter", UIParent); DamageMeter = DamageMeter2')
    meter.execute('HogHeals.db.profile.meter.hideBlizzard = false; HogHealsMeter.Meter.ApplyBlizzard(); HogHealsMeter.Meter.Refresh()')
    assert meter.eval('DamageMeter:IsShown()') is True
    assert meter.eval('DamageMeter:GetParent() == UIParent')


def test_reset_goes_through_blizzard(meter):
    meter.execute('HogHealsMeter.Meter.Reset()')
    assert meter.eval('HH_reset') is True


def test_options_tab_exists_and_panel_renders_it(meter):
    meter.execute('wipe(HogHeals.errors); HogHeals.Panel.Open(); HogHeals.Panel.Select("Meter")')
    assert meter.eval('HogHeals.Panel.selected') == "Meter"
    assert meter.eval('HogHeals.Panel.controls["Meter.enabled"] ~= nil')
    assert errors(meter) == []


def test_slash_toggles_window(meter):
    meter.execute('HogHeals:SlashCommand("meter")')
    shown1 = meter.eval('HogHealsMeterFrame:IsShown()')
    meter.execute('HogHeals:SlashCommand("meter")')
    assert meter.eval('HogHealsMeterFrame:IsShown()') != shown1


def test_panel_keeps_its_full_height_with_one_or_no_rows(meter):
    meter.execute('HogHealsMeter.Meter.Update()')
    h_with_rows = meter.eval('HogHealsMeter.Meter.frame:GetHeight()')
    meter.execute('HH_sources = {}; HogHealsMeter.Meter.Update()')
    assert meter.eval('HogHealsMeter.Meter.frame:GetHeight()') == h_with_rows
    d = 'HogHeals.db.profile.meter'
    assert h_with_rows == 20 + 2 + meter.eval(f'{d}.maxBars') * (meter.eval(f'{d}.barHeight') + 1) + 2
    assert meter.eval('#HogHealsMeter.Meter.frame.edges') == 4 and meter.eval('HogHealsMeter.Meter.frame.edges[1]:IsShown()') is True


def test_shrink_to_fit_when_fixed_height_is_off(meter):
    meter.execute('HogHeals.db.profile.meter.fixedHeight = false; HogHeals.db.profile.meter.border = false; HogHealsMeter.Meter.Update()')
    d = 'HogHeals.db.profile.meter'
    assert meter.eval('HogHealsMeter.Meter.frame:GetHeight()') == 20 + 2 + 3 * (meter.eval(f'{d}.barHeight') + 1) + 2
    assert meter.eval('HogHealsMeter.Meter.frame.edges[1]:IsShown()') is False


def test_rows_carry_class_icons_and_title_carries_the_session_name(meter):
    meter.execute('CLASS_ICON_TCOORDS = { SHAMAN = { 0.25, 0.49, 0.25, 0.49 } }; HogHealsMeter.Meter.Update()')
    r1 = 'HogHealsMeter.Meter.rows[1]'
    assert meter.eval(f'{r1}.icon:IsShown()') is True
    assert "CHARACTERCREATE-CLASSES" in meter.eval(f'{r1}.icon._texture')
    assert "Clattering Scorpid" in meter.eval('HogHealsMeter.Meter.frame.title._text')
    assert meter.eval('HogHealsMeter.Meter.rows[2].icon:IsShown()') is False        # warlock has no coords in this mock


def test_empty_session_is_no_data_not_a_shape_error(meter):
    # measured: before any fight the session comes back with combatSources = {} (an empty table, not nil)
    meter.execute('wipe(HogHeals.errors); HH_sources = {}; HogHealsMeter.Meter.Update()')
    assert errors(meter) == []
    assert meter.eval('HogHealsMeter.Meter.frame.empty:IsShown()') is True


def test_bar_max_comes_from_the_sessions_own_maxamount(meter):
    meter.execute('HogHealsMeter.Meter.Update()')
    assert meter.eval('HogHealsMeter.Meter.rows[2].bar._max') == 7439


def test_hover_a_row_lists_the_spells_behind_it(meter):
    # Sean 2026-10-02: "hover over or click the damage and healing meters and see what spells contributed"
    meter.execute('HogHealsMeter.Meter.Update()')
    r1 = 'HogHealsMeter.Meter.rows[1]'
    assert meter.eval(f'{r1}._last.EnableMouse[1]') is True
    # the mock tooltip's line methods are plain no-ops: record them here
    meter.execute("""
      HH_tt, HH_ttShown, HH_ttHidden = {}, 0, 0
      function GameTooltip:AddLine(t) HH_tt[#HH_tt + 1] = { "L", t } end
      function GameTooltip:AddDoubleLine(l, r) HH_tt[#HH_tt + 1] = { "D", l, r } end
      function GameTooltip:Show() HH_ttShown = HH_ttShown + 1 end
      function GameTooltip:Hide() HH_ttHidden = HH_ttHidden + 1 end
    """)
    meter.execute(f'{r1}:GetScript("OnEnter")({r1})')
    assert meter.eval('#HH_tt') == 4 and meter.eval('HH_tt[1][2]').startswith("Hog Tistic")           # title, 2 spells, hint
    assert meter.eval('HH_tt[2][2]').endswith("Chain Heal") and meter.eval('HH_tt[3][2]').endswith("Healing Wave")   # icon tag in front when the client gives one
    assert meter.eval('HH_tt[2][2]').startswith("|T") or meter.eval('HH_tt[2][2]') == "Chain Heal"
    assert "2.4k" in meter.eval('MockUnwrap(HH_tt[3][3])') and "(9)" in meter.eval('MockUnwrap(HH_tt[3][3])')   # a secret count makes the line a secret string: shown, never read
    assert meter.eval('HH_ttShown') >= 1 and meter.eval('HogHealsMeter.Meter.sourceForm') == "type3"
    # the first shape seen is written to the diag so the SV tells us what the client really sends
    assert "combatSpells" in meter.eval('HogHeals.db.global.diag.meter.source') and "spellName" in meter.eval('HogHeals.db.global.diag.meter.source')
    meter.execute(f'{r1}:GetScript("OnLeave")({r1})')
    assert meter.eval('HH_ttHidden') >= 1
    # a source the client has no detail for says so instead of erroring
    meter.execute('wipe(HH_tt); HogHealsMeter.Meter.rows[2]:GetScript("OnEnter")(HogHealsMeter.Meter.rows[2])')
    assert meter.eval('#HH_tt') == 2 and meter.eval('HH_tt[2][1]') == "L" and "No spell breakdown" in meter.eval('HH_tt[2][2]')
    assert errors(meter) == []


def test_click_a_row_drills_into_spell_bars_and_the_header_comes_back(meter):
    meter.execute('HogHealsMeter.Meter.Update()')
    r = 'HogHealsMeter.Meter.rows'
    meter.execute(f'{r}[1]:GetScript("OnMouseUp")({r}[1], "LeftButton")')
    assert meter.eval('HogHealsMeter.Meter.drill.name') == "Hog Tistic"
    assert meter.eval(f'{r}[1].name._text') == "1. Chain Heal" and meter.eval(f'{r}[2].name._text') == "2. Healing Wave"
    assert meter.eval(f'{r}[1].bar._value') == 5000 and meter.eval(f'{r}[1].bar._max') == 5000     # widget scales the secrets
    assert meter.eval(f'{r}[2].bar._value') == 2439 and meter.eval(f'{r}[2].bar._max') == 5000
    assert meter.eval(f'{r}[1].icon._texture') == 136042 and meter.eval(f'{r}[1].icon:IsShown()') is True
    assert meter.eval(f'{r}[3]:IsShown()') is False
    assert meter.eval('HogHealsMeterFrame.title._text').startswith("< Hog Tistic") and meter.eval('HogHealsMeterFrame.hint._text') == "click: back"
    # the ticker keeps the drill view, a header click comes back to the players
    meter.execute('HogHealsMeter.Meter.Update()')
    assert meter.eval(f'{r}[1].name._text') == "1. Chain Heal"
    meter.execute('HogHealsMeterFrame.header:GetScript("OnClick")(HogHealsMeterFrame.header, "LeftButton")')
    assert meter.eval('HogHealsMeter.Meter.drill') is None and meter.eval(f'{r}[1].name._text') == "1. Hog Tistic"
    assert meter.eval('HogHealsMeterFrame.hint._text') == "L: mode  R: segment"
    # right-click on a row also comes back; a source without detail drills into a plain message, no error
    meter.execute(f'{r}[1]:GetScript("OnMouseUp")({r}[1], "LeftButton"); {r}[1]:GetScript("OnMouseUp")({r}[1], "RightButton")')
    assert meter.eval('HogHealsMeter.Meter.drill') is None
    meter.execute(f'{r}[2]:GetScript("OnMouseUp")({r}[2], "LeftButton")')
    assert meter.eval('HogHealsMeterFrame.empty:IsShown()') is True and "No spell breakdown" in meter.eval('HogHealsMeterFrame.empty._text')
    meter.execute('HogHealsMeter.Meter.DrillOut()')
    assert meter.eval('HogHealsMeterFrame.empty:IsShown()') is False
    assert errors(meter) == []


def test_blizzards_session_windows_are_banished_with_the_manager(meter):
    # Sean 2026-10-02 (screenshot): a minimised "0" box still on screen after the manager frame was hidden
    meter.execute("""
      HH_hidAll = false
      function DamageMeter:HideAllSessionWindows() HH_hidAll = true end
      DamageMeterSessionWindow1 = CreateFrame("Frame", "DamageMeterSessionWindow1", UIParent)
      Elsewhere = CreateFrame("Frame", "Elsewhere", UIParent)
      local list = { DamageMeter, DamageMeterSessionWindow1, Elsewhere, HogHealsMeterFrame }
      function EnumerateFrames(prev)
        if prev == nil then return list[1] end
        for i, f in ipairs(list) do if f == prev then return list[i + 1] end end
      end
      HogHealsMeter.Meter.ApplyBlizzard()
    """)
    assert meter.eval('HH_hidAll') is True
    assert meter.eval('DamageMeterSessionWindow1:GetParent():GetName()') == "HogHealsHiddenParent"
    assert meter.eval('Elsewhere:GetParent() == UIParent') is True and meter.eval('HogHealsMeterFrame:GetParent() == UIParent') is True
    assert meter.eval('HogHealsMeter.Meter.blizzBanished') == "DamageMeterSessionWindow1"
    assert errors(meter) == []


def test_source_call_falls_back_to_the_list_index_and_keeps_every_failure(meter):
    # in game 2026-10-02: the GUID shapes answered "bad argument #2"; the client's usage text must survive in full
    meter.execute("""
      C_DamageMeter.GetCombatSessionSourceFromType = function(a, b, c)
        if type(c) ~= "number" then error("bad argument #2 to '?' (Usage: local sessionSource = C_DamageMeter.GetCombatSessionSourceFromType(sessionType, meterType, sourceIndex))") end
        return { combatSpells = { { spellName = "Lightning Bolt", totalAmount = MockSecret(90) } }, maxAmount = MockSecret(90) }
      end
      HogHealsMeter.Meter.sourceForm = nil
      HogHealsMeter.Meter.Update()
    """)
    r1 = 'HogHealsMeter.Meter.rows[1]'
    meter.execute(f'{r1}:GetScript("OnMouseUp")({r1}, "LeftButton")')
    assert meter.eval('HogHealsMeter.Meter.sourceForm') == "type3i" and meter.eval(f'{r1}.name._text') == "1. Lightning Bolt"
    tries = meter.eval('HogHealsMeter.Meter.sourceTries')
    assert tries.startswith("type3: ") and "sourceIndex))" in tries and "type2: " in tries          # full usage text, both failures
    assert "sourceIndex))" in meter.eval('HogHeals.db.global.diag.meter.sourceTries') and "guid=Player-1" in meter.eval('HogHeals.db.global.diag.meter.sourceArgs')
    meter.execute('HogHealsMeter.Meter.DrillOut(); wipe(MockLog.chat or {}); HogHeals:SlashCommand("meterdiag")')
    chat = " | ".join(meter.eval('MockLog.chat').values())
    assert "per-source form type3i" in chat and "sourceIndex))" in chat
    assert errors(meter) == []


def test_icon_tag_for_tooltip_lines(meter):
    M = "HogHealsMeter.Meter"
    assert meter.eval(f'{M}.IconTag(135812)') == "|T135812:14:14:0:0:64:64:5:59:5:59|t "
    assert meter.eval(f'{M}.IconTag("Interface/Icons/Ability_Hunter_SwiftStrike", 16)').startswith("|TInterface/Icons/Ability_Hunter_SwiftStrike:16:16")
    assert meter.eval(f'{M}.IconTag(nil)') == "" and meter.eval(f'{M}.IconTag({{}})') == ""
    meter.execute('MockSetSecrets(true)')
    assert meter.eval(f'{M}.IconTag(MockSecret(135812))') == ""
