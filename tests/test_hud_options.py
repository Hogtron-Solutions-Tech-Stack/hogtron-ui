def test_hud_tab_groups(hud):
    args = dict(hud.eval('HogHeals.OptionsTable().args.HUD.args').items())
    for g in ("layout", "castbar", "mana", "pacing", "advisor"):
        assert g in args, g


def test_setters_write_profile_and_refresh(hud):
    hud.execute('''
      HH_ref = 0
      local orig = HogHealsHUD.HUD.Refresh
      HogHealsHUD.HUD.Refresh = function() HH_ref = HH_ref + 1 return orig() end
      local o = HogHeals.OptionsTable().args.HUD.args
      o.layout.args.width.set({}, 300)
      o.castbar.args.showTarget.set({}, false)
      o.mana.args.textMode.set({}, "percent")
      o.pacing.args.targetLength.set({}, 420)
      o.advisor.args.margin.set({}, 0.8)
    ''')
    d = hud.eval('HogHeals.db.profile.hud')
    assert d["width"] == 300 and d["castbar"]["showTarget"] is False and d["mana"]["textMode"] == "percent"
    assert d["pacing"]["targetLength"] == 420 and abs(d["advisor"]["margin"] - 0.8) < 1e-9
    assert hud.eval('HH_ref') >= 5
    assert hud.eval('HogHealsHUDFrame:GetWidth()') == 300


def test_hud_session_smoke_no_errors(hud):
    f = hud
    f.execute('''
      MockState.time = 100; MockState.latencyWorld = 200
      MockUnits.player.power = 1000; MockUnits.player.maxPower = 1000
      MockUnits.target = { name = "Zugzug", class = "WARRIOR", health = 50, maxHealth = 100 }
      MockState.spellbook = { { "Greater Heal", "Rank 4" }, { "Flash Heal", "Rank 7" } }
      HogHealsHUD.RankAdvisor.Scan()
      MockFire("PLAYER_REGEN_DISABLED")
      MockUnits.player.casting = { "Greater Heal", "Greater Heal", "icon", 100000, 102500, false, 1, false }
      MockFire("UNIT_SPELLCAST_START", "player", 1, 2060)
      MockState.time = 101; HogHealsHUD.Castbar.OnUpdate(HogHealsHUD.HUD.rows.castbar)
      MockUnits.player.casting = nil; MockUnits.player.power = 700
      MockFire("UNIT_SPELLCAST_SUCCEEDED", "player", 1, 2060); MockFire("UNIT_SPELLCAST_STOP", "player", 1, 2060)
      MockFire("UNIT_POWER_UPDATE", "player", "MANA")
      for t = 102, 110 do MockState.time = t; MockUnits.player.power = 700 - (t - 101) * 30; HogHealsHUD.Pacing.Tick(); HogHealsHUD.Mana.OnUpdate(HogHealsHUD.HUD.rows.mana) end
      MockUnits.party1 = { name = "Zug", class = "WARRIOR", health = 1000, maxHealth = 3000, guid = "Player-1" }
      local b = HogHealsFrames.UnitButton.Create("HogHealsHUDSmoke", UIParent); b.unit = "party1"
      HogHealsFrames.UnitButton.OnEnter(b); HogHealsFrames.UnitButton.OnLeave(b)
      MockFire("PLAYER_REGEN_ENABLED"); MockAdvance(12)
      HogHeals:SlashCommand("rankmacros"); HogHeals:SlashCommand("unlock"); HogHeals:SlashCommand("lock")
      local function walk(t) for _, o in pairs(t.args or {}) do if o.get then o.get({}) end if type(o.name) == "function" then o.name() end if type(o.values) == "function" then o.values() end if o.args then walk(o) end end end
      walk(HogHeals.OptionsTable())
    ''')
    assert (f.eval('#HogHeals.errors'), f.eval('#MockLog.errors')) == (0, 0), f.eval('HogHeals.errors[1] and HogHeals.errors[1].msg or MockLog.errors[1] or ""')
