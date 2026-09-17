REGIONS = ["health", "power", "name", "healPred", "dispelIcon", "dispelBorder", "aggroBorder", "raidIcon",
           "statusIcon", "missingBuff", "shieldIcon", "aoeGlow", "thresholds", "healthText"]


def test_unit_button_regions_and_attributes(frames):
    frames.execute('HH_b = HogHealsFrames.UnitButton.Create("HogHealsTestBtn", UIParent)')
    for r in REGIONS:
        assert frames.eval(f'HH_b.{r} ~= nil'), f"missing region {r}"
    assert frames.eval('HH_b:GetAttribute("*type1")') == "target"
    assert frames.eval('HH_b:GetAttribute("*type2")') == "togglemenu"
    assert frames.eval('HH_b._template') == "SecureUnitButtonTemplate"


def test_headers_spawned_with_group_filters(frames):
    assert frames.eval('HogHealsPartyHeader ~= nil')
    assert frames.eval('HogHealsPartyHeader:GetAttribute("showParty")') is True
    assert frames.eval('HogHealsPartyHeader:GetAttribute("showPlayer")') is True
    assert frames.eval('HogHealsPartyHeader:GetAttribute("showRaid")') is False
    for g in range(1, 9):
        assert frames.eval(f'HogHealsRaidHeader{g}:GetAttribute("groupFilter")') == str(g)
        assert frames.eval(f'HogHealsRaidHeader{g}:GetAttribute("showRaid")') is True


def test_apply_bucket_shows_right_headers(frames):
    frames.execute('HogHealsFrames.Headers.Apply("party")')
    assert frames.eval('HogHealsPartyHeader:IsShown()') is True
    assert frames.eval('HogHealsRaidHeader1:IsShown()') is False
    frames.execute('HogHealsFrames.Headers.Apply("raid10")')
    assert frames.eval('HogHealsPartyHeader:IsShown()') is False
    assert [frames.eval(f'HogHealsRaidHeader{g}:IsShown()') for g in range(1, 9)] == [True, True] + [False] * 6
    frames.execute('HogHealsFrames.Headers.Apply("raid20")')
    assert [frames.eval(f'HogHealsRaidHeader{g}:IsShown()') for g in range(1, 9)] == [True] * 4 + [False] * 4
    frames.execute('HogHealsFrames.Headers.Apply("raid40")')
    assert all(frames.eval(f'HogHealsRaidHeader{g}:IsShown()') for g in range(1, 9))


def test_apply_is_deferred_in_combat(frames):
    frames.execute('wipe(MockLog.attributes); MockState.inCombat = true; HogHealsFrames.Headers.Apply("raid20")')
    assert frames.eval('#MockLog.attributes') == 0
    assert frames.eval('HogHeals:QueuedCount()') >= 1
    frames.execute('MockState.inCombat = false; MockFire("PLAYER_REGEN_ENABLED")')
    assert frames.eval('#MockLog.attributes') > 0
    assert frames.eval('HogHealsRaidHeader4:IsShown()') is True


def test_bucket_change_reapplies(frames):
    frames.execute('MockSetGroup(5, false); MockFire("GROUP_ROSTER_UPDATE")')
    assert frames.eval('HogHealsPartyHeader:IsShown()') is True
    frames.execute('MockSetGroup(18, true); MockFire("GROUP_ROSTER_UPDATE")')
    assert frames.eval('HogHealsRaidHeader3:IsShown()') is True
    assert frames.eval('HogHealsRaidHeader5:IsShown()') is False


# --- Header children (first in-game run, Forever beta 2026-09-17) ---
# RestrictedExecution.lua:79 "attempt to call a nil value" (loadstring_untainted == nil): the client
# cannot compile ANY secure snippet, so an initialConfigFunction kills the header on its first child.
# Children are configured from plain Lua out of combat and pre-created so none is ever born in combat.

def test_no_secure_snippet_on_any_header(frames):
    names = ["HogHealsPartyHeader"] + [f"HogHealsRaidHeader{g}" for g in range(1, 9)]
    for n in names:
        assert frames.eval(f'{n}:GetAttribute("initialConfigFunction")') is None, n


def test_children_built_when_client_cannot_compile_snippets(frames):
    frames.execute('MockState.secureSnippetsBroken = true; wipe(HogHeals.errors); HogHealsFrames.Headers.Apply("solo")')
    assert frames.eval('#HogHeals.errors') == 0
    b = 'HogHealsPartyHeaderUnitButton1'
    assert frames.eval(f'{b} ~= nil and {b}.health ~= nil and {b}.name ~= nil')
    assert frames.eval(f'{b}:GetAttribute("*type1")') == "target"
    assert frames.eval(f'{b}:GetAttribute("*type2")') == "togglemenu"
    assert frames.eval(f'{b}.unit') == "player"
    w = frames.eval('HogHeals.db.profile.frames.layouts.solo.width')
    assert frames.eval(f'{b}:GetWidth()') == w and w > 0


def test_party_children_precreated_so_none_is_born_in_combat(frames):
    frames.execute('HogHealsFrames.Headers.Apply("solo")')
    for n in range(1, 6):
        assert frames.eval(f'HogHealsPartyHeaderUnitButton{n} ~= nil and HogHealsPartyHeaderUnitButton{n}.health ~= nil'), n
    assert frames.eval('HogHealsPartyHeader:GetAttribute("startingIndex")') == 1
    # four people join mid-pull: header must only re-use buttons (mock errors on in-combat creation)
    frames.execute('MockState.inCombat = true; MockSetGroup(5, false); MockHeaderUpdate(HogHealsPartyHeader)')
    assert frames.eval('HogHealsPartyHeaderUnitButton5.unit') == "party4"
    assert frames.eval('HogHealsPartyHeaderUnitButton5:IsShown()') is True


def test_raid_group_children_precreated(frames):
    frames.execute('MockSetGroup(12, true); HogHealsFrames.Headers.Apply("raid20")')
    for g in (1, 2, 3, 4):
        assert frames.eval(f'HogHealsRaidHeader{g}UnitButton5 ~= nil and HogHealsRaidHeader{g}UnitButton5.health ~= nil'), g
    assert frames.eval('HogHealsRaidHeader3UnitButton2.unit') == "raid12"
    assert frames.eval('HogHealsRaidHeader3UnitButton3.unit') is None
