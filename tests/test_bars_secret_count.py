# HogHeals_Bars vendored LibActionButton: action counts that come back SECRET on WoW: Forever.
# In game 2026-10-09 19:46: "LibActionButton-1.0.lua:2786: attempt to compare a secret number value (execution
# tainted by 'HogHeals_Bars')" in IsConsumableOrStackable, HogUIBar2Button8 / action 68, x5. The lib only guards
# counts when the interface number is >= 120000 (Midnight); Forever reports 16001, so the guard never ran.
# These tests run the REAL lib code (chunks cut out of the vendored file), with a mock secret = a table, which throws
# on < / > exactly like a secret does in game.
from pathlib import Path

import pytest
from lupa.lua51 import LuaRuntime, LuaError

LAB = Path(__file__).resolve().parents[1] / "HogHeals_Bars/Libs/LibActionButton-1.0/LibActionButton-1.0.lua"


def _src():
    return LAB.read_text(encoding="utf-8").splitlines()


def _chunk(start, stop_exact):
    src = _src()
    a = next(k for k, l in enumerate(src) if l.startswith(start))
    b = next(k for k in range(a + 1, len(src)) if src[k] == stop_exact)
    return chr(10).join(src[a:b + 1])


def _line(start):
    return next(l for l in _src() if l.startswith(start))


GAME = r'''
lib = {}
Generic = {}
Action = setmetatable({}, { __index = Generic })
function SECRET(n) return { secret = true, n = n } end
COUNTS, ITEM, CONSUMABLE, STACKABLE = {}, {}, {}, {}
function GetActionCount(a) return COUNTS[a] or 0 end
function IsItemAction(a) return ITEM[a] or false end
function IsConsumableAction(a) return CONSUMABLE[a] or false end
function IsStackableAction(a) return STACKABLE[a] or false end
function Generic:GetCharges() return nil end
function BTN(a) return setmetatable({ _state_action = a }, { __index = Action }) end
'''


def _runtime(midnight=False, secrets=True, truncate="ok"):
    rt = LuaRuntime()
    rt.execute(GAME)
    rt.execute(f"Midnight = {str(midnight).lower()}")
    if secrets:
        rt.execute("function issecretvalue(v) return type(v) == 'table' and v.secret == true end")
    if truncate == "ok":
        rt.execute("C_StringUtil = { TruncateWhenZero = function(v) return 'T' .. v.n end }")
    elif truncate == "throws":
        rt.execute("C_StringUtil = { TruncateWhenZero = function(v) error('secret not allowed') end }")
    # one chunk, as in the file: the Action functions must close over the lib's LOCAL GetActionCount
    rt.execute(chr(10).join([_chunk("Generic.GetDisplayCount", "end"), _chunk("local GetActionCount = GetActionCount", "end"),
                             _line("Action.GetCount "), _line("Action.IsConsumableOrStackable ")]))
    return rt


def test_mock_reproduces_the_in_game_error_without_the_patch():
    # same lib line, raw client count: the secret compare throws - proves the mock can see the bug
    rt = LuaRuntime()
    rt.execute(GAME)
    rt.execute("COUNTS[68] = SECRET(2)")
    rt.execute(_line("Action.IsConsumableOrStackable "))
    with pytest.raises(LuaError, match="compare"):
        rt.execute("return BTN(68):IsConsumableOrStackable()")


def test_secret_count_no_longer_throws_on_slot_update():
    rt = _runtime()
    rt.execute("COUNTS[68] = SECRET(2)")
    assert rt.eval("BTN(68):IsConsumableOrStackable()") is False     # was: attempt to compare a secret number value
    assert rt.eval("BTN(68):GetCount()") == 0


def test_plain_counts_behave_exactly_as_before():
    rt = _runtime()
    rt.execute("COUNTS[5] = 7; COUNTS[6] = 0")
    assert rt.eval("BTN(5):IsConsumableOrStackable()") is True       # spell with a reagent count
    assert rt.eval("BTN(5):GetDisplayCount()") == 7
    assert rt.eval("BTN(6):IsConsumableOrStackable()") is False
    assert rt.eval("BTN(6):GetDisplayCount()") == ""


def test_secret_count_on_a_potion_is_handed_to_the_font_string_untouched():
    rt = _runtime()
    rt.execute("COUNTS[9] = SECRET(4); ITEM[9] = true; CONSUMABLE[9] = true")
    assert rt.eval("BTN(9):GetDisplayCount().n") == 4                 # the secret itself; Count:SetText takes it


def test_secret_reagent_count_on_a_spell_goes_through_truncate_when_zero():
    rt = _runtime()
    rt.execute("COUNTS[68] = SECRET(3)")
    assert rt.eval("BTN(68):GetDisplayCount()") == "T3"
    rt = _runtime(truncate="throws")                                    # client refuses: blank, never an error
    rt.execute("COUNTS[68] = SECRET(3)")
    assert rt.eval("BTN(68):GetDisplayCount()") == ""
    rt = _runtime(truncate=None)                                        # helper missing: blank
    rt.execute("COUNTS[68] = SECRET(3)")
    assert rt.eval("BTN(68):GetDisplayCount()") == ""


def test_midnight_and_secretless_clients_keep_the_libs_own_behaviour():
    rt = _runtime(midnight=True)
    rt.execute("COUNTS[5] = 7")
    assert rt.eval("BTN(5):GetCount()") == 0                            # upstream Midnight stub untouched
    rt = _runtime(secrets=False)
    rt.execute("COUNTS[5] = 7")
    assert rt.eval("BTN(5):GetCount()") == 7
    assert rt.eval("rawget(Action, 'GetDisplayCount')") is None                    # no override on classic-era clients


def test_blizzards_own_display_count_still_wins_when_the_client_has_it():
    src = LAB.read_text(encoding="utf-8")
    ours = src.index("elseif type(issecretvalue) == \"function\" then")
    theirs = src.index("Action.GetDisplayCount      = function(self) return C_ActionBar.GetActionDisplayCount")
    assert ours < theirs                                                # later assignment overrides ours
