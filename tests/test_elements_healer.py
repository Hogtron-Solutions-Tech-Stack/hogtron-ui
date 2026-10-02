import pytest


@pytest.fixture
def btn(frames):
    frames.execute('''
      MockState.playerClass = "PRIEST"; MockUnits.player.class = "PRIEST"
      MockUnits.party1 = { name = "Zugzug", class = "WARRIOR", health = 60, maxHealth = 100, guid = "Player-1", auras = {} }
      HH_b = HogHealsFrames.UnitButton.Create("HogHealsHealBtn", UIParent)
      HH_b:SetSize(100, 30)
      HH_b:SetAttribute("unit", "party1")
      HogHealsFrames.UnitButton.OnAttributeChanged(HH_b, "unit", "party1")
    ''')
    return frames


def upd(f, name):
    f.execute(f'HogHealsFrames.Elements.{name}.Update(HH_b, "party1")')


def test_dispel_shows_only_my_types(btn):
    btn.execute('MockUnits.party1.auras = { {name="Curse of Weakness", type="Curse"}, {name="Sleep", type="Magic", icon="magicicon"} }')
    upd(btn, "dispel")
    assert btn.eval('HH_b.dispelIcon:IsShown()') is True
    assert btn.eval('HH_b.dispelIcon:GetTexture()') == "magicicon"
    assert btn.eval('HH_b.dispelIcon.debuffType') == "Magic"
    btn.execute('MockState.playerClass = "WARRIOR"; MockUnits.player.class = "WARRIOR"')
    upd(btn, "dispel")
    assert btn.eval('HH_b.dispelIcon:IsShown()') is False


def test_dispel_style_color_and_border(btn):
    btn.execute('MockUnits.party1.auras = { {name="Sleep", type="Magic"} }')
    btn.execute('HogHeals.db.profile.frames.dispel.style = "border"'); upd(btn, "dispel")
    assert btn.eval('HH_b.dispelBorder:IsShown()') is True and btn.eval('HH_b.dispelIcon:IsShown()') is False
    btn.execute('HogHeals.db.profile.frames.dispel.style = "color"'); upd(btn, "dispel")
    r, g, b = list(btn.eval('{HH_b.health:GetStatusBarColor()}').values())[:3]
    assert (round(r, 2), round(g, 2), round(b, 2)) == (0.2, 0.6, 1.0)  # DebuffTypeColor.Magic
    assert btn.eval('HH_b.dispelColored') is True
    btn.execute('MockUnits.party1.auras = {}'); upd(btn, "dispel")
    assert btn.eval('HH_b.dispelColored') is False


def test_priority_debuff_slot(btn):
    btn.execute('HogHeals.db.profile.frames.dispel.priorityDebuffs = { "Mortal Strike" }')
    btn.execute('MockUnits.party1.auras = { {name="Mortal Strike", debuff=true, icon="msicon"} }')
    upd(btn, "dispel")
    assert btn.eval('HH_b.priorityIcon:IsShown()') is True and btn.eval('HH_b.priorityIcon:GetTexture()') == "msicon"


def test_missing_buffs(btn):
    upd(btn, "missingBuffs")
    assert btn.eval('HH_b.missingBuff:IsShown()') is True
    assert btn.eval('HH_b.missingBuff.spell') == "Power Word: Fortitude"
    btn.execute('MockUnits.party1.auras = { {name="Prayer of Fortitude"} }'); upd(btn, "missingBuffs")
    assert btn.eval('HH_b.missingBuff:IsShown()') is False
    btn.execute('MockState.playerClass = "ROGUE"; MockUnits.player.class = "ROGUE"; MockUnits.party1.auras = {}'); upd(btn, "missingBuffs")
    assert btn.eval('HH_b.missingBuff:IsShown()') is False


def test_missing_buffs_mana_only_skips_warriors(btn):
    btn.execute('MockUnits.party1.auras = { {name="Power Word: Fortitude"} }'); upd(btn, "missingBuffs")
    assert btn.eval('HH_b.missingBuff:IsShown()') is False  # Divine Spirit is manaOnly; warrior has no mana


def test_my_shield_and_weakened_soul(btn):
    btn.execute('MockUnits.party1.auras = { {name="Power Word: Shield", source="player", expires=25} }; MockState.time = 20')
    upd(btn, "myShield")
    assert btn.eval('HH_b.shieldIcon:IsShown()') is True
    btn.execute('MockUnits.party1.auras = { {name="Power Word: Shield", source="party2"} }'); upd(btn, "myShield")
    assert btn.eval('HH_b.shieldIcon:IsShown()') is False
    btn.execute('MockUnits.party1.auras = { {name="Weakened Soul", debuff=true, expires=27} }'); upd(btn, "myShield")
    assert btn.eval('HH_b.shieldText:IsShown()') is True and btn.eval('HH_b.shieldText:GetText()') == "7"


def test_thresholds_ticks(btn):
    upd(btn, "thresholds")
    assert btn.eval('#HH_b.thresholds') == 2
    p1 = list(btn.eval('{HH_b.thresholds[1]:GetPoint()}').values())
    assert p1[3] == 35.0  # x offset = 0.35 * 100 width
    assert btn.eval('HH_b.thresholds[1]:IsShown()') is True
    btn.execute('HogHeals.db.profile.frames.thresholds = { 20 }'); upd(btn, "thresholds")
    assert btn.eval('HH_b.thresholds[1]:IsShown()') is True and btn.eval('HH_b.thresholds[2]:IsShown()') is False


def test_aoe_healing_priest_party(frames):
    frames.execute('''
      MockState.playerClass = "PRIEST"; MockUnits.player.class = "PRIEST"
      MockSetGroup(5, false)
      HH_btns = {}
      for i = 1, 4 do
        local b = HogHealsFrames.UnitButton.Create("HogHealsAoE"..i, UIParent)
        b.unit = "party"..i; HH_btns[i] = b
      end
      HogHealsFrames.Elements.aoeHealing.OnEnter(HH_btns[2])
    ''')
    assert all(frames.eval(f'HH_btns[{i}].aoeGlow:IsShown()') for i in range(1, 5))
    frames.execute('HogHealsFrames.Elements.aoeHealing.OnLeave(HH_btns[2])')
    assert not any(frames.eval(f'HH_btns[{i}].aoeGlow:IsShown()') for i in range(1, 5))


def test_aoe_healing_shaman_chain_uses_subgroup(frames):
    # Addons cannot read unit-to-unit distance in instances; Chain Heal scope = hovered unit's subgroup.
    frames.execute('''
      MockState.playerClass = "SHAMAN"; MockUnits.player.class = "SHAMAN"
      MockSetGroup(10, true)
      HH_r = {}
      for i = 1, 10 do local b = HogHealsFrames.UnitButton.Create("HogHealsAoER"..i, UIParent); b.unit = "raid"..i; HH_r[i] = b end
      HogHealsFrames.Elements.aoeHealing.OnEnter(HH_r[7])
    ''')
    assert [frames.eval(f'HH_r[{i}].aoeGlow:IsShown()') for i in range(1, 11)] == [False] * 5 + [True] * 5
    frames.execute('HogHealsFrames.Elements.aoeHealing.OnLeave(HH_r[7])')
    assert not any(frames.eval(f'HH_r[{i}].aoeGlow:IsShown()') for i in range(1, 11))


def test_heal_prediction_native_split(btn):
    btn.execute('MockUnits.party1.incomingMine = 20; MockUnits.party1.incomingOthers = 10; HogHealsFrames.Compat.hasNativeIncoming = true')
    btn.execute('HogHeals.db.profile.frames.healPrediction.show = "all"'); upd(btn, "healPrediction")
    assert btn.eval('HH_b.healPred:IsShown()') is True
    assert btn.eval('HH_b.healPred:GetWidth()') == 30.0  # 30/100 * 100px
    btn.execute('HogHeals.db.profile.frames.healPrediction.show = "mine"'); upd(btn, "healPrediction")
    assert btn.eval('HH_b.healPred:GetWidth()') == 20.0
    btn.execute('MockUnits.party1.incomingMine = 0; MockUnits.party1.incomingOthers = 0'); upd(btn, "healPrediction")
    assert btn.eval('HH_b.healPred:IsShown()') is False


def test_heal_prediction_overheal_clamps(btn):
    btn.execute('MockUnits.party1.incomingMine = 90; HogHealsFrames.Compat.hasNativeIncoming = true; HogHeals.db.profile.frames.healPrediction.show = "all"')
    upd(btn, "healPrediction")
    assert btn.eval('HH_b.healPred:GetWidth()') == 40.0  # clamps to missing health (100-60)
    assert btn.eval('HH_b.healPred.overheal') is True


def test_heal_prediction_libhealcomm_path(btn):
    btn.execute('MockUnits.party1.incomingMine = 25; HogHealsFrames.Compat.hasNativeIncoming = false; HogHeals.db.profile.frames.healPrediction.show = "all"')
    upd(btn, "healPrediction")
    assert btn.eval('HH_b.healPred:GetWidth()') == 25.0


def test_buffs_row_on_the_cell_mine_first_with_swipe(btn):
    # Sean 2026-10-02: Fortitude-type buffs belong on the party frame; the cell shows a short row, mine by default
    btn.execute('''
      MockState.time = 80
      MockUnits.party1.auras = {
        { name = "Mark of the Wild", source = "party2", icon = "motw", duration = 1800, expires = 1880 },
        { name = "Renew", source = "player", icon = "renew", duration = 15, expires = 95, count = 3 },
        { name = "Power Word: Fortitude", source = "player", icon = "fort", duration = 1800, expires = 1880 },
        { name = "Sleep", type = "Magic" },
      }
    ''')
    upd(btn, "buffs")
    assert btn.eval('HH_b.buffCount') == 2                                                 # mine only: Renew + Fortitude
    assert btn.eval('HH_b.buffs[1].icon._texture') == "renew" and btn.eval('HH_b.buffs[2].icon._texture') == "fort"
    assert btn.eval('HH_b.buffs[1].count._text') == "3"
    assert btn.eval('HH_b.buffs[1].cd._last.SetCooldown[1]') == 80 and btn.eval('HH_b.buffs[1].cd._last.SetCooldown[2]') == 15
    assert btn.eval('HH_b.buffs[1]._last.EnableMouse[1]') is False                        # hover-cast on the cell survives
    assert btn.eval('HH_b.buffs[1]._points[1][1]') == "BOTTOMLEFT" and btn.eval('HH_b.buffs[2]._points[1][4]') == 2 + 13
    assert btn.eval('HH_b.buffs[1]._width') == 12
    # everyone's: mine first (cyan edge), then the druid's mark (plain edge); never the debuff
    btn.execute('HogHeals.db.profile.frames.buffs.filter = "all"'); upd(btn, "buffs")
    assert btn.eval('HH_b.buffCount') == 3 and btn.eval('HH_b.buffs[3].icon._texture') == "motw"
    assert btn.eval('HH_b.buffs[1].edge._color[2]') == pytest.approx(0.83) and btn.eval('HH_b.buffs[3].edge._color[2]') == pytest.approx(0.20)
    # cap + size options
    btn.execute('HogHeals.db.profile.frames.buffs.max = 2; HogHeals.db.profile.frames.buffs.size = 16'); upd(btn, "buffs")
    assert btn.eval('HH_b.buffCount') == 2 and btn.eval('HH_b.buffs[3]:IsShown()') is False and btn.eval('HH_b.buffs[1]._width') == 16
    # gone when the buffs go; off when the indicator is off
    btn.execute('MockUnits.party1.auras = {}'); upd(btn, "buffs")
    assert btn.eval('HH_b.buffCount') == 0 and btn.eval('HH_b.buffs[1]:IsShown()') is False
    btn.execute('MockUnits.party1.auras = { { name = "Renew", source = "player" } }; HogHeals.db.profile.frames.indicators.buffs = false')
    btn.execute('HogHealsFrames.UnitButton.UpdateAll(HH_b)')
    assert btn.eval('HH_b.buffs[1]:IsShown()') is False
    assert [e["msg"] for e in btn.eval('HogHeals.errors').values()] == []


def test_buffs_row_secret_fields_drawn_not_compared(btn):
    btn.execute('''
      MockSetSecrets(true); MockEnableModernAuras(true)
      MockUnits.party1.auras = { { name = "Renew", source = "player", icon = "renew", duration = 15, expires = 95, count = 2 } }
    ''')
    upd(btn, "buffs")
    assert btn.eval('HH_b.buffCount') == 1 and btn.eval('HH_b.buffs[1]:IsShown()') is True
    assert btn.eval('HH_b.buffs[1].count._text') == "2"                                   # %s on a secret, never compared
    assert [e["msg"] for e in btn.eval('HogHeals.errors').values()] == []
