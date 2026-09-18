# Errors and client capability flags are mirrored into SavedVariables (HogHealsDB.global.diag) so a
# tester only has to /reload: the file on disk then carries everything needed to debug remotely.

def test_logged_errors_are_persisted_with_cap(frames):
    frames.execute('HogHeals.db.global.diag.errors = {}; for i = 1, 60 do HogHeals:LogError("boom " .. i) end')
    errs = list(frames.eval('HogHeals.db.global.diag.errors').values())
    assert len(errs) == 50
    assert errs[-1]["msg"] == "boom 60" and errs[0]["msg"] == "boom 11"
    assert errs[-1]["session"] == frames.eval('HogHeals.db.global.diag.session')


def test_safecall_error_carries_a_stack(frames):
    frames.execute('HogHeals.db.global.diag.errors = {}; HogHeals:SafeCall({ go = function() error("kaput") end }, "go")')
    msg = list(frames.eval('HogHeals.db.global.diag.errors').values())[-1]["msg"]
    assert "kaput" in msg


def test_client_snapshot_written_at_enable(frames):
    d = frames.eval('HogHeals.db.global.diag.client')
    assert d["toc"] == 20505 and d["version"] == "2.5.5"
    assert d["addon"] == frames.eval('HogHeals.version')
    probes = d["probes"]
    for k in ("loadstring_untainted", "C_UnitAuras.AddPrivateAuraAnchor", "UnitGetIncomingHeals", "C_Secrets", "issecretvalue"):
        assert k in probes, k
    assert any("auraFilterAllowed=" in line for line in d["compat"].values())


def test_session_counter_increments_per_login(frames):
    assert frames.eval('HogHeals.db.global.diag.session') >= 1


def test_repeating_error_is_counted_not_appended(frames):
    # First beta run: one 0.5 s ticker error filled all 50 slots and evicted every other failure.
    frames.execute('HogHeals.db.global.diag.errors = {}; for i = 1, 500 do HogHeals:LogError("same") end; HogHeals:LogError("other")')
    errs = list(frames.eval('HogHeals.db.global.diag.errors').values())
    assert [e["msg"] for e in errs] == ["same", "other"]
    assert errs[0]["count"] == 500 and errs[1]["count"] == 1


def test_probe_runs_again_on_first_combat(frames):
    frames.execute('MockSetSecrets(true); MockState.inCombat = true; MockFire("PLAYER_REGEN_DISABLED")')
    p = frames.eval('HogHeals.db.global.diag.combatProbe')
    assert p["inCombat"] is True and p["secret.UnitHealth"] is True


def test_meter_probe_reports_absent_api_without_error(core):
    core.execute('C_DamageMeter = nil; HogHeals:SnapshotClient()')
    m = core.eval('HogHeals.db.global.diag.client.meter')
    assert m["api"] == "nil" and m["keys"] == ""


def test_meter_probe_lists_api_and_samples_zero_arg_getters(core):
    core.execute("""C_DamageMeter = {
      GetAvailableCombatSessions = function() return { { sessionID = 1, name = "Boar" } } end,
      IsDamageMeterAvailable = function() return true end,
      GetCombatSessionFromID = function(id) error("must not be called without args") end }
    Enum = Enum or {}; Enum.DamageMeterType = { DamageDone = 0, HealingDone = 2 }
    HogHeals:SnapshotClient()""")
    m = core.eval('HogHeals.db.global.diag.client.meter')
    assert m["api"] == "table"
    assert m["keys"] == "GetAvailableCombatSessions,GetCombatSessionFromID,IsDamageMeterAvailable"
    assert m["calls"]["GetAvailableCombatSessions"].startswith("table[1]")
    assert m["calls"]["IsDamageMeterAvailable"] == "boolean"
    assert "GetCombatSessionFromID" not in dict(m["calls"])
    assert "HealingDone=2" in m["enumType"]
    core.execute('C_DamageMeter = nil')


def test_probe_never_registers_the_combat_log_event():
    # Forbidden on restricted clients; pcall does not contain it; the player gets a "Disable HogHeals?" popup.
    import pathlib, re
    src = (pathlib.Path(__file__).resolve().parent.parent / "HogHeals" / "Core.lua").read_text(encoding="utf-8")
    code = " ".join(line.split("--", 1)[0] for line in src.splitlines())   # drop Lua comments
    assert "COMBAT_LOG_EVENT_UNFILTERED" not in code


def test_blocked_and_forbidden_actions_are_logged_with_the_function_name(core):
    core.execute('HogHeals.db.global.diag.errors = {}; MockFire("ADDON_ACTION_FORBIDDEN", "HogHeals", "Frame:RegisterEvent()")')
    core.execute('MockFire("ADDON_ACTION_BLOCKED", "HogHeals_Frames", "CompactPartyFrame:SetParent()")')
    core.execute('MockFire("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "X()")')
    msgs = [e["msg"] for e in core.eval('HogHeals.db.global.diag.errors').values()]
    assert any("ADDON_ACTION_FORBIDDEN: HogHeals called Frame:RegisterEvent()" in m for m in msgs)
    assert any("HogHeals_Frames called CompactPartyFrame:SetParent()" in m for m in msgs)
    assert not any("SomeOtherAddon" in m for m in msgs)


def test_blizzard_frame_state_is_recorded_at_enable_and_combat(frames):
    frames.execute('CompactPartyFrame = CreateFrame("Frame", "CompactPartyFrame", UIParent)')
    line = frames.eval('HogHeals:BlizzardFrameState()')
    assert "CompactPartyFrame shown=true" in line and "parent=UIParent" in line
    assert "PartyFrame = nil" in line
    assert frames.eval('HogHeals.db.global.diag.blizzFrames.atEnable ~= nil')
    frames.execute('MockFire("PLAYER_REGEN_DISABLED")')
    assert "CompactPartyFrame" in frames.eval('HogHeals.db.global.diag.blizzFrames.atCombat')
