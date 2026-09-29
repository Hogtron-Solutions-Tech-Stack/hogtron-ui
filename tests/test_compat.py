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


def test_blocked_is_runtime_only_and_empty_on_open_clients(frames):
    # Replaces Compat.Degrade: it rewrote the saved profile and, worse, nothing ever called it.
    frames.execute('HogHealsFrames.Compat.Init()')
    assert frames.eval('HogHealsFrames.Compat.Blocked("healPrediction")') is None
    assert frames.eval('HogHealsFrames.Compat.Degrade') is None


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


# --- WoW: Forever beta (first seen 2026-09-17: .build.info 1.60.1.69893, product wow_classic_beta) ---
# Its major version is 1, same as Classic Era, so "major == 1" alone would call it Era and skip the
# restricted-API probe. Era is 1.13-1.15 (toc 113xx-115xx); Forever starts at 1.60 (toc 160xx).

def forever(frames, project="WOW_PROJECT_CLASSIC"):
    frames.execute(f'GetBuildInfo = function() return "1.60.1", "69893", "", 16001 end; WOW_PROJECT_ID = {project}; HogHealsFrames.Compat.Init()')
    return frames.eval('HogHealsFrames.Compat')


def test_forever_build_is_not_era(frames):
    c = forever(frames)
    assert c["isForever"] is True and c["isEra"] is False and c["isTBC"] is False


def test_forever_probes_instead_of_assuming_open_api(frames):
    frames.execute('C_UnitAuras = { AddPrivateAuraAnchor = function() end }; UnitGetIncomingHeals = nil')
    c = forever(frames)
    assert c["auraFilterAllowed"] is False and c["hasNativeIncoming"] is False
    frames.execute('C_UnitAuras = nil; UnitGetIncomingHeals = function() return 0 end')
    c = forever(frames)
    assert c["auraFilterAllowed"] is True and c["hasNativeIncoming"] is True


def test_forever_detected_under_unknown_project_id(frames):
    assert forever(frames, "999")["isForever"] is True


def test_era_still_era_after_patch_bump(frames):
    frames.execute('GetBuildInfo = function() return "1.15.9", "69722", "", 11509 end; WOW_PROJECT_ID = WOW_PROJECT_CLASSIC; HogHealsFrames.Compat.Init()')
    c = frames.eval('HogHealsFrames.Compat')
    assert c["isEra"] is True and c["isForever"] is False and c["auraFilterAllowed"] is True


def test_apicheck_reports_forever_flag(frames):
    frames.execute('MockLog.chat = {}; HogHeals:SlashCommand("apicheck")')
    assert any("isForever=" in line for line in frames.eval('MockLog.chat').values())


def test_every_toc_lists_every_installed_client():
    import pathlib, re
    root = pathlib.Path(__file__).resolve().parent.parent
    want = {"11508", "11509", "20505", "20506", "16001"}
    tocs = sorted(root.glob("HogHeals*/HogHeals*.toc"))
    assert len(tocs) == 10
    for toc in tocs:
        line = next(l for l in toc.read_text(encoding="utf-8").splitlines() if l.startswith("## Interface:"))
        assert want <= set(re.findall(r"\d+", line)), toc.name
