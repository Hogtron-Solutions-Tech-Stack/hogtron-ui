BUILDS = {"WOW_PROJECT_CLASSIC": 11508, "WOW_PROJECT_BURNING_CRUSADE_CLASSIC": 20505, "999": 0}


def flags(frames, project):
    toc = BUILDS.get(project, 0)
    frames.execute(f'GetBuildInfo = function() return "x", "1", "", {toc} end; WOW_PROJECT_ID = {project}; HogHealsFrames.Compat.Init()')
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


def test_anniversary_tbc_detected_even_under_classic_project_id(frames):
    # Anniversary-TBC may report project id 2 with a 2.5.x build; build wins.
    frames.execute('GetBuildInfo = function() return "2.5.5", "60000", "", 20505 end; WOW_PROJECT_ID = WOW_PROJECT_CLASSIC; HogHealsFrames.Compat.Init()')
    c = frames.eval('HogHealsFrames.Compat')
    assert c["isTBC"] is True and c["isEra"] is False and c["hasEarthShield"] is True
    assert list(frames.eval('HogHeals.ShieldSpells("SHAMAN")').values()) == ["Earth Shield"]


def test_apicheck_slash_prints_flags(frames):
    frames.execute('MockLog.chat = {}; HogHeals:SlashCommand("apicheck")')
    chat = list(frames.eval('MockLog.chat').values())
    assert any("auraFilterAllowed=" in line for line in chat)
