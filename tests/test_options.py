def test_root_options_table_shape(frames):
    t = frames.eval('HogHeals.OptionsTable()')
    assert t["type"] == "group" and t["childGroups"] == "tab"
    args = dict(t["args"].items())
    assert "general" in args and "Frames" in args
    assert args["Frames"]["type"] == "group"


def test_frames_tab_groups(frames):
    args = dict(frames.eval('HogHeals.OptionsTable().args.Frames.args').items())
    for g in ("layout", "appearance", "indicators", "bindings", "profiles"):
        assert g in args, g


def test_set_writes_db_and_refreshes(frames):
    frames.execute('''
      HH_refreshed = 0
      local orig = HogHealsFrames.module.Refresh
      HogHealsFrames.module.Refresh = function(self) HH_refreshed = HH_refreshed + 1 return orig(self) end
      local opt = HogHeals.OptionsTable().args.Frames.args.appearance.args.healthMode
      opt.set({}, "deficit")
    ''')
    assert frames.eval('HogHeals.db.profile.frames.appearance.healthMode') == "deficit"
    assert frames.eval('HH_refreshed') >= 1
    frames.execute('local o = HogHeals.OptionsTable().args.Frames.args.layout.args.width; o.set({}, 150)')
    # while solo the shared solo&party layout is edited (soloSharesParty default), i.e. layouts.party
    assert frames.eval('HogHealsFrames.module:LayoutFor().width') == 150
    assert frames.eval('HogHeals.db.profile.frames.layouts.party.width') == 150


def test_indicator_toggle_option_exists_per_indicator(frames):
    ind = dict(frames.eval('HogHeals.OptionsTable().args.Frames.args.indicators.args').items())
    for name in ("dispel", "missingBuffs", "myShield", "thresholds", "aoeHealing", "healPrediction", "range", "aggro"):
        assert name in ind and ind[name]["type"] == "toggle"


def test_slash_commands_dispatch(frames):
    frames.execute('HogHeals:SlashCommand("test 10")')
    assert frames.eval('HogHealsFrames.TestMode.active') is True
    frames.execute('HogHeals:SlashCommand("test off")')
    assert frames.eval('HogHealsFrames.TestMode.active') is False
    frames.execute('HogHeals:SlashCommand("unlock")')
    assert frames.eval('HogHeals.db.profile.locked') is False
    assert frames.eval('HogHealsAnchor:IsShown()') is True
    frames.execute('HogHeals:SlashCommand("lock")')
    assert frames.eval('HogHeals.db.profile.locked') is True
    frames.execute('HogHeals:SlashCommand("")')                       # bare /hh = our own panel now
    assert frames.eval('HogHealsPanel:IsShown()') is True
    frames.execute('HogHeals:SlashCommand("ace")')                    # the Ace dialog stays as a fallback
    assert frames.eval('MockLibs.dialog.opened[#MockLibs.dialog.opened]') == "HogHeals"


def test_wizard_state_machine(frames):
    frames.execute('HH_w = HogHealsFrames.Wizard.New("PRIEST")')
    assert frames.eval('HH_w.step') == "class"
    frames.execute('HogHealsFrames.Wizard.Next(HH_w, { class = "PRIEST" })')
    assert frames.eval('HH_w.step') == "layout"
    frames.execute('HogHealsFrames.Wizard.Next(HH_w, { preset = "compact" })')
    assert frames.eval('HH_w.step') == "bindings"
    frames.execute('HogHealsFrames.Wizard.Next(HH_w, { bindings = "default" })')
    assert frames.eval('HH_w.step') == "gear"
    frames.execute('HogHealsFrames.Wizard.Next(HH_w, { gear = "auto" })')
    assert frames.eval('HH_w.step') == "done"
    frames.execute('HogHealsFrames.Wizard.Finish(HH_w)')
    assert frames.eval('HogHeals.db.profile.wizardDone') is True
    assert frames.eval('HogHeals.db.profile.frames.layouts.raid40.width') < frames.eval('HogHeals.defaults.profile.frames.layouts.raid40.width')
    assert frames.eval('#HogHealsFrames.ClickCast.bindings') >= 5



def test_wizard_gear_step_writes_the_atlas_role_auto_by_default(frames):
    frames.execute('''
      HH_w = HogHealsFrames.Wizard.New("PRIEST")
      HogHealsFrames.Wizard.Next(HH_w, { class = "PRIEST" })
      HogHealsFrames.Wizard.Next(HH_w, { preset = "default" })
      HogHealsFrames.Wizard.Next(HH_w, { bindings = "default" })
      HogHealsFrames.Wizard.Finish(HH_w)            -- the gear step skipped (older flow / Finish pressed early)
    ''')
    assert frames.eval('HogHeals.db.char.atlas.role') == "auto"
    frames.execute('''
      HH_w = HogHealsFrames.Wizard.New("PRIEST")
      HogHealsFrames.Wizard.Next(HH_w, { class = "PRIEST" })
      HogHealsFrames.Wizard.Next(HH_w, { preset = "default" })
      HogHealsFrames.Wizard.Next(HH_w, { bindings = "default" })
      HogHealsFrames.Wizard.Next(HH_w, { gear = "caster" })
      HogHealsFrames.Wizard.Finish(HH_w)
    ''')
    assert frames.eval('HogHeals.db.char.atlas.role') == "caster"
    frames.execute('HH_w = HogHealsFrames.Wizard.New("PRIEST"); HogHealsFrames.Wizard.Next(HH_w, { gear = "nonsense" }); HogHealsFrames.Wizard.Finish(HH_w)')
    assert frames.eval('HogHeals.db.char.atlas.role') == "auto"
    assert frames.eval('HogHealsFrames.Wizard.GEAR_ROLES.auto').startswith("Auto")

def test_wizard_accessibility_preset(frames):
    frames.execute('''
      HH_w = HogHealsFrames.Wizard.New("PRIEST")
      HogHealsFrames.Wizard.Next(HH_w, { class = "PRIEST" })
      HogHealsFrames.Wizard.Next(HH_w, { preset = "accessibility" })
      HogHealsFrames.Wizard.Next(HH_w, { bindings = "mouse" })
      HogHealsFrames.Wizard.Finish(HH_w)
    ''')
    assert frames.eval('HogHeals.db.profile.frames.layouts.party.width') >= 160
    assert frames.eval('HogHeals.db.profile.frames.indicators.thresholds') is False
    assert all(b["key"].startswith("BUTTON") for b in [dict(v.items()) for v in frames.eval('HogHealsFrames.ClickCast.bindings').values()])
