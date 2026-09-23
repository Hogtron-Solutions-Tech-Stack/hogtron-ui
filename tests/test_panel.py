# HogHeals' own options window ("like ElvUI: not the Blizzard default, a little nicer"). It renders the SAME
# AceConfig-style options table the Ace dialog used, with our own flat, branded widgets. No AceGUI involved, so
# nothing another addon (or a client that drops a FrameXML helper) can break.
import pytest

SAMPLE = '''
HH_log = {}
HH_state = { on = true, size = 40, mode = "b", text = "hi", col = { 1, 0, 0, 1 }, secret = false }
HH_sample = function()
  return { type = "group", name = "HogHeals", childGroups = "tab", args = {
    general = { type = "group", name = "General", order = 1, args = {
      about = { type = "description", order = 1, name = "About text" },
      head  = { type = "header", order = 2, name = "Basics" },
      on    = { type = "toggle", order = 3, name = "Enable thing", desc = "Tooltip here",
                get = function() return HH_state.on end, set = function(_, v) HH_state.on = v end },
      size  = { type = "range", order = 4, name = "Size", min = 10, max = 100, step = 5,
                get = function() return HH_state.size end, set = function(_, v) HH_state.size = v end },
      mode  = { type = "select", order = 5, name = "Mode", values = { a = "Alpha", b = "Bravo", c = "Charlie" },
                get = function() return HH_state.mode end, set = function(_, v) HH_state.mode = v end },
      go    = { type = "execute", order = 6, name = "Do it", func = function() HH_log[#HH_log + 1] = "go" end },
      text  = { type = "input", order = 7, name = "Text", get = function() return HH_state.text end,
                set = function(_, v) HH_state.text = v end },
      col   = { type = "color", order = 8, name = "Colour", hasAlpha = true,
                get = function() return unpack(HH_state.col) end, set = function(_, r, g, b, a) HH_state.col = { r, g, b, a } end },
      gone  = { type = "toggle", order = 9, name = "Hidden one", hidden = function() return not HH_state.secret end,
                get = function() return false end, set = function() end },
      grey  = { type = "execute", order = 10, name = "Disabled one", disabled = true, func = function() HH_log[#HH_log + 1] = "NO" end },
    } },
    frames = { type = "group", name = "Frames", order = 2, childGroups = "tab", args = {
      layout = { type = "group", name = "Layout", order = 1, args = {
        w = { type = "range", order = 1, name = "Width", min = 1, max = 9, step = 1, get = function() return 3 end, set = function() end } } },
      look = { type = "group", name = "Look", order = 2, args = {
        t = { type = "toggle", order = 1, name = "Flat", get = function() return true end, set = function() end },
        deep = { type = "group", name = "Deeper", order = 2, inline = true, args = {
          d = { type = "toggle", order = 1, name = "Deep toggle", get = function() return true end, set = function() end } } } } },
    } },
  } }
end
'''


@pytest.fixture
def panel(core):
    core.execute(SAMPLE)
    core.execute('HogHeals.Panel.Open(HH_sample)')
    return core


def ctl(panel, key):
    return f'HogHeals.Panel.controls["{key}"]'


def test_window_is_ours_and_closes_on_escape(panel):
    assert panel.eval('HogHealsPanel ~= nil and HogHealsPanel:IsShown()') is True
    assert panel.eval('HogHeals.Panel.usesAceGUI') is False
    names = list(panel.eval('UISpecialFrames').values())
    assert "HogHealsPanel" in names
    # two-tone wordmark: HOG cream, HEALS cyan (brand rule)
    assert panel.eval('HogHeals.Panel.frame.titleHog._text') == "HOG"
    assert panel.eval('HogHeals.Panel.frame.titleHeals._text') == "UI"          # HogUI umbrella brand


def test_sidebar_lists_top_level_groups_in_order(panel):
    nav = [panel.eval(f'HogHeals.Panel.nav[{i}].label._text') for i in (1, 2)]
    assert nav == ["General", "Frames"]
    assert panel.eval('HogHeals.Panel.selected') == "general"


def test_every_control_type_renders_with_its_current_value(panel):
    assert panel.eval(ctl(panel, "general.on") + '.checked') is True
    assert panel.eval(ctl(panel, "general.size") + '.slider._value') == 40
    assert panel.eval(ctl(panel, "general.size") + '.valueText._text') == "40"
    assert panel.eval(ctl(panel, "general.mode") + '.button.label._text') == "Bravo"
    assert panel.eval(ctl(panel, "general.text") + '.edit._text') == "hi"
    assert panel.eval(ctl(panel, "general.about") + '.text._text') == "About text"
    assert panel.eval(ctl(panel, "general.head") + '.text._text') == "BASICS"
    assert panel.eval(ctl(panel, "general.col") + ' ~= nil')


def test_hidden_is_absent_and_disabled_does_nothing(panel):
    assert panel.eval(ctl(panel, "general.gone")) is None
    panel.execute(ctl(panel, "general.grey") + '.button:Click()')
    assert list(panel.eval('HH_log').values()) == []
    panel.execute('HH_state.secret = true; HogHeals.Panel.Refresh()')
    assert panel.eval(ctl(panel, "general.gone") + ' ~= nil')


def test_toggle_execute_input_select_write_through_and_refresh(panel):
    panel.execute(ctl(panel, "general.on") + '.button:Click()')
    assert panel.eval('HH_state.on') is False
    assert panel.eval(ctl(panel, "general.on") + '.checked') is False

    panel.execute(ctl(panel, "general.go") + '.button:Click()')
    assert list(panel.eval('HH_log').values()) == ["go"]

    panel.execute('local e = ' + ctl(panel, "general.text") + '.edit; e:SetText("typed"); e:GetScript("OnEnterPressed")(e)')
    assert panel.eval('HH_state.text') == "typed"

    panel.execute(ctl(panel, "general.mode") + '.button:Click()')
    items = [panel.eval(f'HogHeals.Panel.menu.items[{i}].label._text') for i in (1, 2, 3)]
    assert items == ["Alpha", "Bravo", "Charlie"]          # sorted by label
    panel.execute('HogHeals.Panel.menu.items[3]:Click()')
    assert panel.eval('HH_state.mode') == "c"
    assert panel.eval('HogHeals.Panel.menu:IsShown()') is False
    assert panel.eval(ctl(panel, "general.mode") + '.button.label._text') == "Charlie"


def test_slider_snaps_to_step_and_writes(panel):
    panel.execute('local s = ' + ctl(panel, "general.size") + '.slider; s:GetScript("OnValueChanged")(s, 57.4, true)')
    assert panel.eval('HH_state.size') == 55
    assert panel.eval(ctl(panel, "general.size") + '.valueText._text') == "55"


def test_tabs_for_child_groups_and_inline_groups_flatten(panel):
    panel.execute('HogHeals.Panel.Select("frames")')
    tabs = [panel.eval(f'HogHeals.Panel.tabs[{i}].label._text') for i in (1, 2)]
    assert tabs == ["Layout", "Look"]
    assert panel.eval(ctl(panel, "frames.layout.w") + ' ~= nil')
    assert panel.eval(ctl(panel, "frames.look.t")) is None
    panel.execute('HogHeals.Panel.SelectTab("look")')
    assert panel.eval(ctl(panel, "frames.look.t") + ' ~= nil')
    assert panel.eval(ctl(panel, "frames.look.deep.d") + ' ~= nil')       # inline group rendered in place
    assert panel.eval(ctl(panel, "frames.layout.w")) is None


def test_a_throwing_option_is_logged_not_fatal(panel):
    panel.execute('wipe(HogHeals.errors)')
    panel.execute('''HogHeals.Panel.Open(function() return { type = "group", name = "x", args = { g = { type = "group", name = "G", order = 1, args = {
      bad = { type = "toggle", order = 1, name = "Bad", get = function() error("kaboom") end, set = function() end },
      ok  = { type = "toggle", order = 2, name = "Fine", get = function() return true end, set = function() end } } } } } end)''')
    assert panel.eval('HogHeals.Panel.controls["g.ok"] ~= nil')
    assert any("kaboom" in e["msg"] for e in panel.eval('HogHeals.errors').values())


def test_hh_opens_our_panel_and_ace_stays_reachable(core):
    core.execute('HogHeals:SlashCommand("")')
    assert core.eval('HogHealsPanel ~= nil and HogHealsPanel:IsShown()') is True
    assert core.eval('HogHeals.slash.ace ~= nil')


def test_real_options_table_renders_every_tab_without_errors(frames):
    frames.execute('wipe(HogHeals.errors); HogHeals.Panel.Open()')
    n = frames.eval('#HogHeals.Panel.nav')
    assert n >= 2
    for i in range(1, n + 1):
        frames.execute(f'HogHeals.Panel.Select(HogHeals.Panel.nav[{i}].key)')
        for t in range(1, (frames.eval('#HogHeals.Panel.tabs') or 0) + 1):
            frames.execute(f'HogHeals.Panel.SelectTab(HogHeals.Panel.tabs[{t}].key)')
    assert [e["msg"] for e in frames.eval('HogHeals.errors').values()] == []


def test_handler_method_names_resolve_like_aceconfig(core):
    # AceDBOptions style: handler object + string method names, inherited down the group tree.
    core.execute("""
    HH_h = { picked = nil, resets = 0,
      ListProfiles = function(self, info) return { Default = "Default", Healer = "Healer" } end,
      GetCurrent = function(self, info) return "Default" end,
      SetProfile = function(self, info, v) self.picked = v end,
      Reset = function(self, info) self.resets = self.resets + 1 end,
      Title = function(self, info) return "Current: " .. self:GetCurrent(info) end }
    HogHeals.Panel.Open(function() return { type = "group", name = "x", args = {
      profiles = { type = "group", name = "Profiles", order = 1, handler = HH_h, args = {
        title  = { type = "description", order = 1, name = "Title" },
        choose = { type = "select", order = 2, name = "Existing", values = "ListProfiles", get = "GetCurrent", set = "SetProfile" },
        reset  = { type = "execute", order = 3, name = "Reset", func = "Reset" } } } } } end)
    wipe(HogHeals.errors)
    HogHeals.Panel.Refresh()""")
    assert [e["msg"] for e in core.eval('HogHeals.errors').values()] == []
    assert core.eval('HogHeals.Panel.controls["profiles.title"].text._text') == "Title"     # text fields are never method names
    assert core.eval('HogHeals.Panel.controls["profiles.choose"].button.label._text') == "Default"
    core.execute('HogHeals.Panel.controls["profiles.choose"].button:Click(); HogHeals.Panel.menu.items[2]:Click()')
    assert core.eval('HH_h.picked') == "Healer"
    core.execute('HogHeals.Panel.controls["profiles.reset"].button:Click()')
    assert core.eval('HH_h.resets') == 1


def test_real_profiles_tab_renders_without_errors(frames):
    frames.execute('wipe(HogHeals.errors); HogHeals.Panel.Open(); HogHeals.Panel.Select("Frames"); HogHeals.Panel.SelectTab("profiles")')
    assert [e["msg"] for e in frames.eval('HogHeals.errors').values()] == []
