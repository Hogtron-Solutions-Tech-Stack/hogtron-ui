# Perf (2026-10-05): one aura walk per (unit, filter) per dispatch, no work on hidden cells, no tickers for blocked
# elements, range poll rate as an option.
import pytest


@pytest.fixture
def cell(frames):
    frames.execute("""
      MockState.playerClass = "PRIEST"; MockUnits.player.class = "PRIEST"
      MockUnits.party1 = { name = "Zugzug", class = "WARRIOR", health = 60, maxHealth = 100, guid = "Player-1", auras = {} }
      MockUnits.party1.auras = {
        { name = "Mark of the Wild", source = "party2", icon = "motw", duration = 1800, expires = 1880 },
        { name = "Renew", source = "player", icon = "renew", duration = 15, expires = 95 },
        { name = "Power Word: Fortitude", source = "player", icon = "fort", duration = 1800, expires = 1880 },
        { name = "Sleep", type = "Magic", icon = "sleep" },
      }
      HH_b = HogHealsFrames.UnitButton.Create("HHPerfCell", UIParent)
      HH_b:SetSize(100, 30)
      HH_b:SetAttribute("unit", "party1")
      HogHealsFrames.UnitButton.OnAttributeChanged(HH_b, "unit", "party1")
      HH_b:Show()
      UA_CALLS = 0
      local orig = UnitAura
      function UnitAura(...) UA_CALLS = UA_CALLS + 1 return orig(...) end
      wipe(HogHeals.errors)
    """)
    return frames


def errors(lua):
    return [e["msg"] for e in lua.eval("HogHeals.errors").values()]


def test_memo_hands_the_same_read_back_inside_one_dispatch(cell):
    cell.execute("UA_CALLS = 0; HogHealsFrames.Compat.AuraData('party1', 1, 'HELPFUL'); HogHealsFrames.Compat.AuraData('party1', 1, 'HELPFUL')")
    assert cell.eval("UA_CALLS") == 2                                   # no batch open: two real reads
    cell.execute("""
      UA_CALLS = 0
      HogHealsFrames.Compat.BeginAuraBatch()
      A1 = HogHealsFrames.Compat.AuraData('party1', 1, 'HELPFUL')
      A2 = HogHealsFrames.Compat.AuraData('party1', 1, 'HELPFUL')
      N1 = HogHealsFrames.Compat.UnitAura('party1', 1, 'HARMFUL')
      N2 = HogHealsFrames.Compat.UnitAura('party1', 1, 'HARMFUL')
      E1 = HogHealsFrames.Compat.UnitAura('party1', 9, 'HARMFUL')
      E2 = HogHealsFrames.Compat.UnitAura('party1', 9, 'HARMFUL')
      HogHealsFrames.Compat.EndAuraBatch()
    """)
    assert cell.eval("UA_CALLS") == 3                                   # past-the-end nil is remembered too
    assert cell.eval("A1 == A2") is True and cell.eval("N1") == "Sleep" and cell.eval("N2") == "Sleep" and cell.eval("E1 == nil and E2 == nil")
    # the batch is gone once the dispatch ends: a later read is fresh
    cell.execute("MockUnits.party1.auras[4].name = 'Fear'; UA_CALLS = 0; X = HogHealsFrames.Compat.UnitAura('party1', 1, 'HARMFUL')")
    assert cell.eval("X") == "Fear" and cell.eval("UA_CALLS") == 1
    assert cell.eval("HogHealsFrames.Compat.batch == nil and HogHealsFrames.Compat.batchDepth == 0")


def test_one_unit_aura_event_walks_each_filter_once(cell):
    # elements on UNIT_AURA here: buffs (HELPFUL|PLAYER, filter mine), dispel (HARMFUL), missingBuffs (HELPFUL),
    # myShield (HELPFUL|PLAYER). Each filter walk reads auras+1 slots: HELPFUL|PLAYER 3, HARMFUL 2, HELPFUL 4 = 9.
    # baseline: the same dispatch with the memo switched off
    cell.execute("""
      local C = HogHealsFrames.Compat
      C._Begin, C._End = C.BeginAuraBatch, C.EndAuraBatch
      C.BeginAuraBatch, C.EndAuraBatch = function() end, function() end
      UA_CALLS = 0; HogHealsFrames.UnitButton.OnEvent(HH_b, 'UNIT_AURA', 'party1'); BASE = UA_CALLS
      C.BeginAuraBatch, C.EndAuraBatch = C._Begin, C._End
    """)
    cell.execute("UA_CALLS = 0; HogHealsFrames.Compat.memoHits = 0; HogHealsFrames.UnitButton.OnEvent(HH_b, 'UNIT_AURA', 'party1')")
    base, memo = cell.eval("BASE"), cell.eval("UA_CALLS")
    assert base >= 10 and memo < base                                  # main: 10 -> 8; play (debuff row + buffs=all): 21 -> 15
    assert cell.eval("HogHealsFrames.Compat.memoHits") >= 2            # the second HELPFUL|PLAYER walk came from the memo
    assert cell.eval("HH_b.dispelIcon:IsShown()") is True
    assert errors(cell) == []


def test_hidden_cell_does_no_event_work_and_repaints_on_show(cell):
    cell.execute("MockUnits.party1.health = 40; HogHealsFrames.UnitButton.OnEvent(HH_b, 'UNIT_HEALTH', 'party1')")
    assert cell.eval("HH_b.health._value") == 40
    cell.execute("HH_b:Hide(); MockUnits.party1.health = 70; HogHealsFrames.UnitButton.OnEvent(HH_b, 'UNIT_HEALTH', 'party1')")
    assert cell.eval("HH_b.health._value") == 40                       # untouched while hidden
    cell.execute("HH_b:Show(); HogHealsFrames.UnitButton.UpdateAll(HH_b)")   # what OnShow does in the client
    assert cell.eval("HH_b.health._value") == 70


def test_blocked_elements_get_no_ticker_and_range_rate_is_an_option(cell):
    cell.execute("HogHealsFrames.UnitButton.StartTickers()")
    assert cell.eval("HogHealsFrames.UnitButton.tickers.range ~= nil and HogHealsFrames.UnitButton.tickers.healPrediction ~= nil")
    assert cell.eval("HogHealsFrames.UnitButton.tickers.range.every") == pytest.approx(0.4)
    cell.execute("""
      HogHealsFrames.Compat.blocked.healPrediction = "secret maths"
      HogHeals.db.profile.frames.appearance.rangeInterval = 0.8
      HogHealsFrames.UnitButton.StartTickers()
    """)
    assert cell.eval("HogHealsFrames.UnitButton.tickers.healPrediction") is None
    assert cell.eval("HogHealsFrames.UnitButton.tickers.range.every") == pytest.approx(0.8)
    assert cell.eval("HogHealsFrames.UnitButton.TickerInterval('range')") == pytest.approx(0.8)
    assert cell.eval("HogHealsFrames.UnitButton.TickerInterval('myShield')") == 1
