def flags(frames, project):
    frames.execute(f'WOW_PROJECT_ID = {project}; HogHealsFrames.Compat.Init()')
    return frames.eval('HogHealsFrames.Compat')


def test_classic_era_flags(frames):
    c = flags(frames, "WOW_PROJECT_CLASSIC")
    assert c["hasNativeIncoming"] is False and c["hasEarthShield"] is False and c["auraFilterAllowed"] is True


def test_tbc_flags(frames):
    c = flags(frames, "WOW_PROJECT_BURNING_CRUSADE_CLASSIC")
    assert c["hasNativeIncoming"] is True and c["hasEarthShield"] is True and c["auraFilterAllowed"] is True


def test_unknown_project_is_conservative(frames):
    frames.execute('UnitGetIncomingHeals = nil')
    c = flags(frames, "999")
    assert c["hasNativeIncoming"] is False
    assert c["auraFilterAllowed"] is True
    frames.execute('C_UnitAuras = { AddPrivateAuraAnchor = function() end }')
    c = flags(frames, "999")
    assert c["auraFilterAllowed"] is False


def test_degrade_disables_aura_indicators(frames):
    frames.execute('HogHealsFrames.Compat.auraFilterAllowed = false; HogHealsFrames.Compat.Degrade(HogHeals.db.profile.frames)')
    ind = frames.eval('HogHeals.db.profile.frames.indicators')
    assert ind["dispel"] is False and ind["missingBuffs"] is False and ind["myShield"] is False and ind["healPrediction"] is False
    assert ind["health"] is True and ind["range"] is True
