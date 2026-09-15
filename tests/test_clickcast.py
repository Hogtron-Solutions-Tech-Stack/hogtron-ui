def test_attributes_for_mouse_bindings(frames):
    attrs = frames.eval('''HogHealsFrames.ClickCast.AttributesFor({
      { key = "BUTTON1", mod = "SHIFT", type = "spell", value = "Prayer of Healing" },
      { key = "BUTTON2", mod = "", type = "spell", value = "Renew" },
      { key = "BUTTON3", mod = "CTRL", type = "macro", value = "/cast Dispel Magic" },
      { key = "1", mod = "", type = "spell", value = "Greater Heal" },
    })''')
    d = dict(attrs.items())
    assert d["shift-type1"] == "spell" and d["shift-spell1"] == "Prayer of Healing"
    assert d["type2"] == "spell" and d["spell2"] == "Renew"
    assert d["ctrl-type3"] == "macro" and d["ctrl-macrotext3"] == "/cast Dispel Magic"
    assert not any("Greater" in str(v) for v in d.values())


def test_apply_sets_attributes_through_queue(frames):
    frames.execute('''
      HH_b = HogHealsFrames.UnitButton.Create("HogHealsCCBtn", UIParent)
      wipe(MockLog.attributes); MockState.inCombat = true
      HogHealsFrames.ClickCast.Apply(HH_b, { { key = "BUTTON2", mod = "", type = "spell", value = "Renew" } })
    ''')
    assert frames.eval('#MockLog.attributes') == 0
    frames.execute('MockState.inCombat = false; MockFire("PLAYER_REGEN_ENABLED")')
    assert frames.eval('HH_b:GetAttribute("spell2")') == "Renew"


def test_hover_keys_bound_on_enter_and_cleared_on_leave(frames):
    frames.execute('''
      HH_b = HogHealsFrames.UnitButton.Create("HogHealsHoverBtn", UIParent)
      HogHealsFrames.ClickCast.SetBindings({ { key = "1", mod = "", type = "spell", value = "Greater Heal" },
                                            { key = "Q", mod = "CTRL", type = "spell", value = "Dispel Magic" } })
      HogHealsFrames.ClickCast.Apply(HH_b)
      HogHealsFrames.ClickCast.OnEnter(HH_b)
    ''')
    clicks = list(frames.eval('MockBindings.clicks').values())
    keys = {c["key"]: c["button"] for c in clicks}
    assert keys["1"] == "hhkey1" and keys["CTRL-Q"] == "hhkey2"
    assert all(c["name"] == "HogHealsHoverBtn" for c in clicks)
    assert frames.eval('HH_b:GetAttribute("type-hhkey1")') == "spell"
    assert frames.eval('HH_b:GetAttribute("spell-hhkey1")') == "Greater Heal"
    frames.execute('HogHealsFrames.ClickCast.OnLeave(HH_b)')
    assert frames.eval('#MockBindings.cleared') == 1


def test_defaults_match_seans_priest_layout(frames):
    b = [dict(v.items()) for v in frames.eval('HogHealsFrames.ClickCast.Defaults("PRIEST")').values()]
    look = {(x["mod"], x["key"]): x["value"] for x in b}
    assert look[("", "1")] == "Greater Heal"
    assert look[("", "3")] == "Flash Heal"
    assert look[("", "4")] == "Renew"
    assert look[("", "F")] == "Power Word: Shield"
    assert look[("", "Q")] == "Dispel Magic"
    assert look[("SHIFT", "1")] == "Prayer of Healing"
    assert look[("CTRL", "2")] == "Power Word: Fortitude"
    assert frames.eval('#HogHealsFrames.ClickCast.Defaults("WARRIOR")') == 0


def test_macro_fallback_chain(frames):
    m = frames.eval('HogHealsFrames.ClickCast.Macro("Flash Heal", { mouseover = true, focus = true, target = true, player = true })')
    assert m == "/cast [@mouseover,help,nodead][@focus,help,nodead][help,nodead][@player] Flash Heal"
    m2 = frames.eval('HogHealsFrames.ClickCast.Macro("Flash Heal", { mouseover = true, focus = false, target = false, player = false })')
    assert m2 == "/cast [@mouseover,help,nodead] Flash Heal"


def test_clique_takes_control(frames):
    frames.execute('''
      MockState.cliqueLoaded = true
      Clique = { header = CreateFrame("Frame") }
      HogHealsFrames.ClickCast.Init()
      HH_b = HogHealsFrames.UnitButton.Create("HogHealsCliqueBtn", UIParent)
      wipe(MockLog.attributes)
      HogHealsFrames.ClickCast.Apply(HH_b, { { key = "BUTTON2", mod = "", type = "spell", value = "Renew" } })
    ''')
    assert frames.eval('HogHealsFrames.ClickCast.controlledBy') == "Clique"
    assert frames.eval('#MockLog.attributes') == 0
