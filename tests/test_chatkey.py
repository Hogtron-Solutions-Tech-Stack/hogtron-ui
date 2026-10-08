# Enter belongs to chat (HogHeals/Core/ChatKey.lua + the two binders). Sean in game 2026-10-08: "Enter isn't
# opening the chat window, but / lets me type" - ENTER had been bound away from OPENCHAT.
import pytest

CK = "HogHeals.ChatKey"

BIND_API = '''
MockBindings.actions = { ENTER = "OPENCHAT" }
SETB = {}
function SetBinding(key, action) SETB[#SETB + 1] = { key, action } MockBindings.actions[key] = action return true end
SAVED = nil
function SaveBindings(which) SAVED = which end
function GetCurrentBindingSet() return 2 end
'''


def chat(lua):
    log = lua.eval("MockLog.chat")
    return list(log.values()) if log is not None else []


def test_check_fix_and_slash(core):
    core.execute(BIND_API)
    assert list(core.eval(f"{{ {CK}.Check() }}").values()) == ["ok", "OPENCHAT"]
    core.execute('MockBindings.actions.ENTER = "CLICK HogUIBar1Button1:LeftButton"')
    assert core.eval(f"({CK}.Check())") == "taken"
    core.execute('HogHeals:SlashCommand("enter")')
    assert any("chat will not open on Enter" in m and "/hh enter fix" in m for m in chat(core))
    core.execute('HogHeals:SlashCommand("enter fix")')
    assert core.eval("SETB[1][1]") == "ENTER" and core.eval("SETB[1][2]") == "OPENCHAT" and core.eval("SAVED") == 2
    assert core.eval(f"({CK}.Check())") == "ok"
    core.execute('MockBindings.actions.ENTER = ""')
    assert core.eval(f"({CK}.Check())") == "unbound"
    core.execute('GetBindingAction = nil')
    assert core.eval(f"({CK}.Check())") == "unknown"


def test_fix_without_setbinding_says_why(core):
    core.execute("SetBinding = nil")
    ok, why = list(core.eval(f"{{ {CK}.Fix() }}").values())
    assert ok is False and "SetBinding" in why


def test_login_check_warns_only_when_enter_is_taken(lua):
    lua.execute(BIND_API + 'MockBindings.actions.ENTER = "SPELL Renew"')
    lua.load_addon("HogHeals")
    lua.player_login()
    lua.execute("MockAdvance(4)")
    assert any("chat will not open on Enter" in m for m in chat(lua))


def test_login_check_is_silent_when_enter_is_chat(lua):
    lua.execute(BIND_API)
    lua.load_addon("HogHeals")
    lua.player_login()
    lua.execute("MockAdvance(4)")
    assert not any("Enter" in m for m in chat(lua))


def test_strip_pure(core):
    out, gone = list(core.eval(f'{{ {CK}.Strip({{ {{ key = "1" }}, {{ key = "ENTER" }}, {{ key = "escape" }}, {{ key = "F" }} }}) }}').values())
    assert [v["key"] for v in out.values()] == ["1", "F"]
    assert [v["key"] for v in gone.values()] == ["ENTER", "escape"]


# ---------------------------------------------------------------- the binders refuse Enter
def test_hover_heal_panel_never_binds_enter(frames):
    frames.execute('MockState.playerClass = "PRIEST"; HogHealsFrames.ClickCast.SetBindings(HogHealsFrames.ClickCast.Defaults("PRIEST"))')
    frames.execute("HogHealsFrames.HoverBind.Open()")
    frames.execute('for _, r in ipairs(HogHealsFrames.HoverBind.rows) do if r.spell == "Renew" then r:GetScript("OnEnter")(r) end end')
    before = frames.eval("#HogHealsFrames.ClickCast.bindings")
    frames.execute('HogHealsHoverBind:GetScript("OnKeyDown")(HogHealsHoverBind, "ENTER")')
    assert frames.eval("#HogHealsFrames.ClickCast.bindings") == before
    assert not any(b["key"] == "ENTER" for b in frames.eval("HogHealsFrames.ClickCast.bindings").values())
    assert any("Enter is for opening chat" in m for m in chat(frames))
    frames.execute("HogHealsFrames.HoverBind.Close('done')")


def test_saved_hover_heal_bindings_lose_enter_at_load(lua):
    lua.execute('''
      MockState.playerClass = "PRIEST"
      HogHealsDB = { profiles = { Default = { frames = { bindings = { PRIEST = {
        { key = "1", mod = "", type = "spell", value = "Greater Heal" },
        { key = "ENTER", mod = "", type = "spell", value = "Renew" } } } } } } }
    ''')
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Frames")
    lua.player_login()
    keys = [b["key"] for b in lua.eval("HogHealsFrames.ClickCast.bindings").values()]
    assert keys == ["1"]
    assert any("ENTER" in m and "dropped" in m for m in chat(lua))


def test_bar_bind_mode_never_binds_enter(lua):
    lua.execute('BOUND = {}; function SetBinding(k, a) BOUND[#BOUND + 1] = { k, a } return true end')
    for a in ("HogHeals", "HogHeals_Frames", "HogHeals_Bars"):
        lua.load_addon(a)
    lua.player_login()
    lua.execute('''
      HogHealsBars.Bind.Start()
      local b = HogHealsBars.Bars.bars[1].buttons[1]
      local o = HogHealsBars.Bind.overlays[b]
      o:GetScript("OnEnter")(o)
      HogHealsBindStrip:GetScript("OnKeyDown")(HogHealsBindStrip, "ENTER")
    ''')
    assert lua.eval("HogHealsBars.Bind.last") is None or lua.eval("HogHealsBars.Bind.last[2]") != "ENTER"
    assert not any(v[1] == "ENTER" for v in lua.eval("BOUND").values())
    assert any("Enter is for opening chat" in m for m in chat(lua))
    lua.execute('HogHealsBars.Bind.Stop("done")')
