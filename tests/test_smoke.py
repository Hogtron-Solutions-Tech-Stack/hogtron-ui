"""End-to-end wiring smoke: a realistic session must produce zero caught errors."""


def errors(f):
    return f.eval('#HogHeals.errors'), f.eval('#MockLog.errors')


def test_full_session_no_errors(frames):
    f = frames
    f.execute('MockSetGroup(5, false); MockFire("GROUP_ROSTER_UPDATE")')
    f.execute('MockSetGroup(25, true); MockFire("GROUP_ROSTER_UPDATE")')
    f.execute('MockState.inCombat = true; MockFire("PLAYER_REGEN_DISABLED"); MockSetGroup(40, true); MockFire("GROUP_ROSTER_UPDATE")')
    f.execute('MockState.inCombat = false; MockFire("PLAYER_REGEN_ENABLED")')
    f.execute('HogHeals:SlashCommand(""); HogHeals:SlashCommand("test 20"); MockAdvance(3); HogHeals:SlashCommand("test off")')
    f.execute('HogHeals:SlashCommand("unlock"); HogHeals:SlashCommand("lock"); HogHeals:SlashCommand("macro Flash Heal"); HogHeals:SlashCommand("version")')
    f.execute('''
      local b = HogHealsFrames.UnitButton.Create("HogHealsSmoke", UIParent)
      MockUnits.raid3.auras = { {name="Sleep", type="Magic"}, {name="Weakened Soul", debuff=true, expires=30} }
      b:SetAttribute("unit", "raid3"); HogHealsFrames.UnitButton.OnAttributeChanged(b, "unit", "raid3")
      for _, ev in ipairs({"UNIT_HEALTH","UNIT_AURA","UNIT_POWER_UPDATE","UNIT_THREAT_SITUATION_UPDATE","RAID_TARGET_UPDATE","READY_CHECK","GROUP_ROSTER_UPDATE"}) do
        HogHealsFrames.UnitButton.OnEvent(b, ev, "raid3")
      end
      HogHealsFrames.UnitButton.OnEnter(b); HogHealsFrames.UnitButton.OnLeave(b)
      MockAdvance(1)
      local w = HogHealsFrames.Wizard.New("PRIEST")
      HogHealsFrames.Wizard.Next(w, {class="PRIEST"}); HogHealsFrames.Wizard.Next(w, {preset="compact"}); HogHealsFrames.Wizard.Next(w, {bindings="default"})
      HogHealsFrames.Wizard.Finish(w)
      local s = HogHealsFrames.ExportProfile(); HogHealsFrames.ImportProfile(s)
    ''')
    assert errors(f) == (0, 0), f.eval('HogHeals.errors[1] and HogHeals.errors[1].msg or MockLog.errors[1] or ""')


def test_options_table_every_getter_runs(frames):
    frames.execute('''
      local function walk(t)
        for k, o in pairs(t.args or {}) do
          if o.get then o.get({}) end
          if type(o.name) == "function" then o.name() end
          if type(o.values) == "function" then o.values() end
          if o.args then walk(o) end
        end
      end
      walk(HogHeals.OptionsTable())
    ''')
    assert errors(frames) == (0, 0)
