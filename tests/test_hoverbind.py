# HogHeals_Frames/HoverBind.lua: `/hh bind heals` - hover a spell in the panel, press a key = hover-heal binding.
# Sean 2026-10-03: "quick binding on the hover over heals".
import pytest

KEYS = '''
ALT, CTRL, SHIFT = false, false, false
function IsAltKeyDown() return ALT end
function IsControlKeyDown() return CTRL end
function IsShiftKeyDown() return SHIFT end
'''


@pytest.fixture
def hb(frames):
    frames.execute('MockState.playerClass = "PRIEST"; HogHealsFrames.ClickCast.SetBindings(HogHealsFrames.ClickCast.Defaults("PRIEST"))' + KEYS)
    frames.execute("wipe(HogHeals.errors)")
    return frames


def bindings(lua):
    out = {}
    for b in lua.eval("HogHealsFrames.ClickCast.bindings").values():
        mod = b["mod"] or ""
        out[(mod + "-" if mod else "") + b["key"]] = b["value"]
    return out


def row_for(lua, spell):
    return lua.eval(f'''(function()
      for _, r in ipairs(HogHealsFrames.HoverBind.rows) do if r.spell == "{spell}" and r:IsShown() then return r end end
    end)()''')


def hover(lua, spell):
    lua.execute(f'''
      for _, r in ipairs(HogHealsFrames.HoverBind.rows) do if r.spell == "{spell}" then r:GetScript("OnEnter")(r) end end
    ''')


def press(lua, key):
    lua.execute(f'HogHealsHoverBind:GetScript("OnKeyDown")(HogHealsHoverBind, "{key}")')


def errors(lua):
    return [e["msg"] for e in lua.eval("HogHeals.errors").values()]


# ---------------------------------------------------------------- keys + catalogue

def test_key_string_and_split(hb):
    assert hb.eval('HogHealsFrames.HoverBind.KeyString("F", false, false, false)') == "F"
    assert hb.eval('HogHealsFrames.HoverBind.KeyString("G", true, true, false)') == "ALT-CTRL-G"
    assert hb.eval('HogHealsFrames.HoverBind.KeyString("3", false, true, true)') == "CTRL-SHIFT-3"
    assert hb.eval('HogHealsFrames.HoverBind.KeyString("LSHIFT", false, false, true)') is None
    assert list(hb.eval('{ HogHealsFrames.HoverBind.Split("ALT-CTRL-G") }').values()) == ["G", "ALT-CTRL"]
    assert list(hb.eval('{ HogHealsFrames.HoverBind.Split("F") }').values()) == ["F", ""]


def test_catalogue_is_defaults_plus_bound_plus_typed_without_duplicates(hb):
    names = list(hb.eval('HogHealsFrames.HoverBind.Catalog("PRIEST", { { key = "5", mod = "", type = "spell", value = "Holy Nova" }, { key = "6", mod = "", type = "spell", value = "Renew" } })').values())
    assert names[:4] == ["Greater Heal", "Flash Heal", "Renew", "Power Word: Shield"]
    assert "Holy Nova" in names and names.count("Renew") == 1 and names.count("Greater Heal") == 1


def test_icon_ladder(hb):
    assert list(hb.eval('{ HogHealsFrames.HoverBind.Icon("Renew") }').values()) == ["Interface\\Icons\\Renew", "C_Spell.GetSpellTexture"]
    hb.execute("C_Spell = nil")
    assert list(hb.eval('{ HogHealsFrames.HoverBind.Icon("Renew") }').values())[1] == "GetSpellTexture"
    hb.execute("GetSpellTexture = nil")
    assert list(hb.eval('{ HogHealsFrames.HoverBind.Icon("Renew") }').values()) == ["none"]


# ---------------------------------------------------------------- panel

def test_open_builds_a_row_per_spell_with_its_keys(hb):
    assert hb.eval("HogHealsFrames.HoverBind.Open()") is True
    assert hb.eval("HogHealsHoverBind:IsShown()") is True
    n = hb.eval("HogHealsFrames.HoverBind.count")
    assert n == len(hb.eval('HogHealsFrames.HoverBind.Catalog("PRIEST", HogHealsFrames.ClickCast.bindings)'))
    r = row_for(hb, "Greater Heal")
    assert r is not None
    assert hb.eval("(" + f'''(function() for _, r in ipairs(HogHealsFrames.HoverBind.rows) do if r.spell == "Greater Heal" then return r.keys:GetText() end end end)()''' + ")") == "1  2"
    assert hb.eval("HogHeals.db.global.diag.hoverBind.iconApi") == "C_Spell.GetSpellTexture"
    assert errors(hb) == []


def test_hover_a_spell_press_a_key_binds_it_and_moves_the_key(hb):
    hb.execute("HogHealsFrames.HoverBind.Open()")
    hover(hb, "Renew")
    press(hb, "F")                                      # F was Power Word: Shield
    b = bindings(hb)
    assert b["F"] == "Renew"
    assert "Power Word: Shield" not in b.values()
    last = hb.eval("HogHealsFrames.HoverBind.last")
    assert last["key"] == "F" and last["moved"] == "Power Word: Shield"
    assert hb.eval('HogHeals.db.profile.frames.bindings.PRIEST ~= nil') is True
    assert hb.eval(f'''(function() for _, r in ipairs(HogHealsFrames.HoverBind.rows) do if r.spell == "Renew" then return r.keys:GetText() end end end)()''') == "4  F"


def test_modifiers_combine(hb):
    hb.execute("HogHealsFrames.HoverBind.Open()")
    hover(hb, "Flash Heal")
    hb.execute("CTRL, SHIFT = true, true")
    press(hb, "G")
    hb.execute("CTRL, SHIFT = false, false")
    b = bindings(hb)
    assert b["CTRL-SHIFT-G"] == "Flash Heal"
    raw = [x for x in hb.eval("HogHealsFrames.ClickCast.bindings").values() if x["value"] == "Flash Heal" and x["key"] == "G"][0]
    assert raw["mod"] == "CTRL-SHIFT"


def test_lone_modifier_and_nothing_hovered_change_nothing(hb):
    hb.execute("HogHealsFrames.HoverBind.Open()")
    before = bindings(hb)
    press(hb, "F")                                      # nothing hovered
    hover(hb, "Renew")
    press(hb, "LSHIFT")
    assert bindings(hb) == before


def test_escape_clears_only_that_spell(hb):
    hb.execute("HogHealsFrames.HoverBind.Open()")
    hover(hb, "Greater Heal")
    press(hb, "ESCAPE")
    b = bindings(hb)
    assert "Greater Heal" not in b.values()
    assert b["3"] == "Flash Heal" and b["F"] == "Power Word: Shield"
    assert hb.eval("HogHealsFrames.HoverBind.last.key") == "cleared"


def test_mouse_buttons_bind_too_but_left_and_right_never(hb):
    hb.execute("HogHealsFrames.HoverBind.Open()")
    hb.execute('''
      for _, r in ipairs(HogHealsFrames.HoverBind.rows) do if r.spell == "Renew" then
        r:GetScript("OnMouseDown")(r, "LeftButton"); r:GetScript("OnMouseDown")(r, "RightButton"); r:GetScript("OnMouseDown")(r, "Button4")
      end end
    ''')
    b = bindings(hb)
    assert b["BUTTON4"] == "Renew"
    assert "BUTTON1" not in b and "BUTTON2" not in b


def test_typed_spell_gets_a_row_and_binds(hb):
    hb.execute("HogHealsFrames.HoverBind.Open()")
    n = hb.eval("HogHealsFrames.HoverBind.count")
    assert hb.eval('HogHealsFrames.HoverBind.AddSpell("Holy Nova")') is True
    assert hb.eval('HogHealsFrames.HoverBind.AddSpell("Holy Nova")') is False
    assert hb.eval("HogHealsFrames.HoverBind.count") == n + 1
    hover(hb, "Holy Nova")
    press(hb, "5")
    assert bindings(hb)["5"] == "Holy Nova"
    hb.execute('HogHealsHoverBindEdit._text = "Prayer of Mending"; HogHealsHoverBindEdit:GetScript("OnEnterPressed")(HogHealsHoverBindEdit)')
    assert row_for(hb, "Prayer of Mending") is not None


# ---------------------------------------------------------------- combat / Clique / slash

def test_refused_in_combat_and_closes_when_combat_starts(hb):
    hb.execute("MockState.inCombat = true")
    assert hb.eval("HogHealsFrames.HoverBind.Open()") is False
    hb.execute("MockState.inCombat = false")
    assert hb.eval("HogHealsFrames.HoverBind.Open()") is True
    hb.execute('MockFire("PLAYER_REGEN_DISABLED")')
    assert hb.eval("HogHealsFrames.HoverBind.active") is False
    assert hb.eval("HogHealsHoverBind:IsShown()") is False


def test_refused_when_clique_controls_bindings(hb):
    hb.execute('HogHealsFrames.ClickCast.controlledBy = "Clique"')
    assert hb.eval("HogHealsFrames.HoverBind.Open()") is False
    hb.execute('HogHealsFrames.ClickCast.controlledBy = nil')


def test_slash_bind_heals_without_a_bars_addon(hb):
    hb.execute('HogHeals:SlashCommand("bind heals")')
    assert hb.eval("HogHealsFrames.HoverBind.active") is True
    hb.execute('HogHeals:SlashCommand("bind heals")')
    assert hb.eval("HogHealsFrames.HoverBind.active") is False
    hb.execute('HogHeals:SlashCommand("bind")')        # help line, no toggle
    assert hb.eval("HogHealsFrames.HoverBind.active") is False
    hb.execute('HogHeals:SlashCommand("hoverbind")')
    assert hb.eval("HogHealsFrames.HoverBind.active") is True
    assert errors(hb) == []


def test_slash_bind_heals_on_top_of_an_existing_bind_owner(hb):
    hb.execute('''
      BARS_GOT = nil
      HogHeals.slash.bind = nil
      HogHeals:RegisterSlash("bind", function(rest) BARS_GOT = rest end, "bars")
      HogHealsFrames.HoverBind.inited = false
      HogHealsFrames.HoverBind.Init()
      HogHeals:SlashCommand("bind")
    ''')
    assert hb.eval("BARS_GOT") == "" and not hb.eval("HogHealsFrames.HoverBind.active")
    hb.execute('HogHeals:SlashCommand("bind heals")')
    assert hb.eval("HogHealsFrames.HoverBind.active") is True
    assert hb.eval("HogHeals.slash.bind.help").startswith("bars")


def test_options_button_opens_the_panel(hb):
    hb.execute("HogHealsFrames.module:GetOptions().args.bindings.args.quick.func()")
    assert hb.eval("HogHealsFrames.HoverBind.active") is True
