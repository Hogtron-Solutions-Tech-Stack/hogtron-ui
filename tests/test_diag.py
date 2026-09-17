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
