BUCKETS = ["solo", "party", "raid10", "raid20", "raid40"]


def test_layout_profiles_exist(core):
    for b in BUCKETS:
        lay = core.eval(f'HogHeals.db.profile.frames.layouts.{b}')
        for key in ("width", "height", "spacing", "growth", "groupsPerRow", "groupsShown"):
            assert key in lay, f"{b} missing {key}"


def test_groups_shown_per_bucket(core):
    assert core.eval('HogHeals.db.profile.frames.layouts.raid10.groupsShown') == 2
    assert core.eval('HogHeals.db.profile.frames.layouts.raid20.groupsShown') == 4
    assert core.eval('HogHeals.db.profile.frames.layouts.raid40.groupsShown') == 8


def test_indicator_toggles_are_booleans(core):
    ind = core.eval('HogHeals.db.profile.frames.indicators')
    items = list(ind.items())
    assert len(items) >= 10
    for k, v in items:
        assert isinstance(v, bool), f"{k} is {type(v)}"


def test_thresholds_and_health_fade(core):
    assert list(core.eval('HogHeals.db.profile.frames.thresholds').values()) == [35, 50]
    assert core.eval('HogHeals.db.profile.frames.healthFade.enabled') is False
    assert core.eval('HogHeals.db.profile.frames.healthFade.above') == 90


def test_migration_sets_schema_and_is_idempotent(core):
    assert core.eval('HogHeals.db.global.schema') == 4
    core.execute('HogHeals.Migrate.Run(HogHeals.db); HogHeals.Migrate.Run(HogHeals.db)')
    assert core.eval('HogHeals.db.global.schema') == 4
    core.execute('HogHeals.db.global.schema = nil; HogHeals.Migrate.Run(HogHeals.db)')
    assert core.eval('HogHeals.db.global.schema') == 4


def test_solo_frame_off_by_default_and_migrated_off(lua):
    lua.execute('HogHealsDB = { profileKeys = {}, profiles = { Default = { frames = { layouts = { solo = { showSolo = true } } } } }, global = { schema = 3 } }')
    lua.load_addon("HogHeals"); lua.player_login()
    assert lua.eval('HogHeals.defaults.profile.frames.layouts.solo.showSolo') is False
    assert lua.eval('HogHeals.db.profile.frames.layouts.solo.showSolo') is False      # migration 4 flipped the saved true
    assert lua.eval('HogHeals.db.global.schema') == 4
