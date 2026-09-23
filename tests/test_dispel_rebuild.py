# Tester: "Cell has a really cool dispel option: if it's dispellable by me, an icon pops up. Do we have that?"
# We did, but it was blocked on secret-value clients. Measured on the Forever beta: aura data carries
# canActivePlayerDispel (Blizzard decides), fields are plain out of combat and may turn secret in combat.

def mk(frames, auras, cls="PRIEST"):
    frames.execute(f'MockState.playerClass = "{cls}"; MockUnits.player.class = "{cls}"')
    frames.execute('MockUnits.party1 = { name = "Ann", class = "MAGE", health = 50, maxHealth = 100, guid = "P1", auras = ' + auras + ' }')
    frames.execute('HH_d = HogHealsFrames.UnitButton.Create("HHDispel" .. math.random(1e9), UIParent); HH_d:SetAttribute("unit", "party1"); HogHealsFrames.UnitButton.OnAttributeChanged(HH_d, "unit", "party1"); wipe(HogHeals.errors)')
    frames.execute('HogHealsFrames.Elements.dispel.Update(HH_d, "party1")')


def test_not_blocked_on_secret_clients_any_more(frames):
    frames.execute('MockSetSecrets(true); HogHealsFrames.Compat.Init()')
    assert frames.eval('HogHealsFrames.Compat.Blocked("dispel")') is None
    assert frames.eval('HogHealsFrames.Compat.Blocked("missingBuffs")') is not None


def test_modern_api_icon_shows_for_a_debuff_i_can_dispel(frames):
    frames.execute('MockEnableModernAuras(false); HogHealsFrames.Compat.Init()')
    mk(frames, '{ { name = "Curse of Weakness", type = "Curse", icon = 11 }, { name = "Shadow Word: Pain", type = "Magic", icon = 22 } }')
    assert frames.eval('HH_d.dispelIcon:IsShown()') is True
    assert frames.eval('HH_d.dispelIcon._texture') == 22          # priest: Magic yes, Curse no
    assert [e["msg"] for e in frames.eval('HogHeals.errors').values()] == []


def test_modern_api_nothing_dispellable_hides_it(frames):
    frames.execute('MockEnableModernAuras(false); HogHealsFrames.Compat.Init()')
    mk(frames, '{ { name = "Curse of Weakness", type = "Curse", icon = 11 } }')
    assert frames.eval('HH_d.dispelIcon:IsShown()') is False


def test_secret_auras_in_combat_use_one_icon_per_slot_and_the_widget_decides(frames):
    frames.execute('MockSetSecrets(true); MockEnableModernAuras(true); HogHealsFrames.Compat.Init()')
    mk(frames, '{ { name = "Curse of Weakness", type = "Curse", icon = 11 }, { name = "Shadow Word: Pain", type = "Magic", icon = 22 } }')
    assert [e["msg"] for e in frames.eval('HogHeals.errors').values()] == []
    assert frames.eval('HH_d.dispelIcons[1]:IsShown()') is True and frames.eval('HH_d.dispelIcons[1]._alpha') == 0     # Curse: not mine
    assert frames.eval('HH_d.dispelIcons[2]:IsShown()') is True and frames.eval('HH_d.dispelIcons[2]._alpha') == 1     # Magic: mine
    assert frames.eval('HH_d.dispelIcons[3]:IsShown()') is False
    assert frames.eval('HH_d.priorityIcon:IsShown()') is False


def test_legacy_client_path_unchanged(frames):
    mk(frames, '{ { name = "Shadow Word: Pain", type = "Magic", icon = 22 } }')
    assert frames.eval('HH_d.dispelIcon:IsShown()') is True and frames.eval('HH_d.dispelIcon._texture') == 22
