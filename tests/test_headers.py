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
