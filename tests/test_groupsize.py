import pytest

CASES = [
    (1, False, "solo"), (0, False, "solo"), (2, False, "party"), (5, False, "party"),
    (5, True, "raid10"), (6, True, "raid10"), (10, True, "raid10"),
    (11, True, "raid20"), (20, True, "raid20"), (21, True, "raid40"), (40, True, "raid40"),
]


@pytest.mark.parametrize("n,is_raid,expected", CASES)
def test_bucket_for_size(core, n, is_raid, expected):
    assert core.eval(f'HogHeals.BucketForSize({n}, {"true" if is_raid else "false"})') == expected


def test_current_bucket_and_change_event(core):
    core.execute('HH_seen = {}; HogHeals.RegisterCallback({}, "BUCKET_CHANGED", function(_, new, old) HH_seen[#HH_seen+1] = new .. "<" .. tostring(old) end)')
    assert core.eval('HogHeals:CurrentBucket()') == "solo"
    core.execute('MockSetGroup(5, false); MockFire("GROUP_ROSTER_UPDATE")')
    assert core.eval('HogHeals:CurrentBucket()') == "party"
    core.execute('MockSetGroup(25, true); MockFire("GROUP_ROSTER_UPDATE")')
    assert core.eval('HogHeals:CurrentBucket()') == "raid40"
    assert list(core.eval('HH_seen').values()) == ["party<solo", "raid40<party"]
