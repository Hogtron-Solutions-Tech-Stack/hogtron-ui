def test_runs_immediately_out_of_combat(core):
    core.execute('HH_ran = 0; HogHeals:RunOutOfCombat(function() HH_ran = HH_ran + 1 end)')
    assert core.eval('HH_ran') == 1


def test_queues_in_combat_and_drains_in_order(core):
    core.execute('''
      MockState.inCombat = true
      HH_order = {}
      HogHeals:RunOutOfCombat(function() HH_order[#HH_order+1] = "a" end)
      HogHeals:RunOutOfCombat(function() HH_order[#HH_order+1] = "b" end)
    ''')
    assert core.eval('#HH_order') == 0
    assert core.eval('HogHeals:QueuedCount()') == 2
    core.execute('MockState.inCombat = false; MockFire("PLAYER_REGEN_ENABLED")')
    assert list(core.eval('HH_order').values()) == ["a", "b"]
    assert core.eval('HogHeals:QueuedCount()') == 0


def test_throwing_fn_does_not_stop_drain(core):
    core.execute('''
      MockState.inCombat = true
      HH_order = {}
      HogHeals:RunOutOfCombat(function() error("boom") end)
      HogHeals:RunOutOfCombat(function() HH_order[#HH_order+1] = "after" end)
      MockState.inCombat = false; MockFire("PLAYER_REGEN_ENABLED")
    ''')
    assert list(core.eval('HH_order').values()) == ["after"]
    assert core.eval('#HogHeals.errors') == 1
    assert "boom" in core.eval('HogHeals.errors[1].msg')
