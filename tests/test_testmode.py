def test_start_creates_fake_units(frames):
    assert frames.eval('HogHealsFrames.TestMode.Start(20)') is True
    assert frames.eval('HogHealsTest1 ~= nil and HogHealsTest20 ~= nil and HogHealsTest21 == nil')
    assert frames.eval('HogHealsTest5:IsShown()') is True
    assert frames.eval('HogHealsTest5.unit') == "hhtest5"
    assert frames.eval('MockUnits.hhtest5 ~= nil')
    before = [frames.eval(f'MockUnits.hhtest{i}.health') for i in range(1, 21)]
    frames.execute('MockAdvance(1)')
    after = [frames.eval(f'MockUnits.hhtest{i}.health') for i in range(1, 21)]
    assert before != after


def test_some_fakes_have_dispellable_auras_and_out_of_range(frames):
    frames.execute('HogHealsFrames.TestMode.Start(40)')
    with_aura = sum(1 for i in range(1, 41) if frames.eval(f'MockUnits.hhtest{i}.auras ~= nil and #MockUnits.hhtest{i}.auras > 0'))
    oor = sum(1 for i in range(1, 41) if frames.eval(f'MockUnits.hhtest{i}.inRange == false'))
    assert 6 <= with_aura <= 18
    assert 2 <= oor <= 8


def test_stop_hides_all(frames):
    frames.execute('HogHealsFrames.TestMode.Start(10); HogHealsFrames.TestMode.Stop()')
    assert not any(frames.eval(f'HogHealsTest{i}:IsShown()') for i in range(1, 11))
    assert frames.eval('HogHealsFrames.TestMode.active') is False


def test_refuses_in_combat(frames):
    frames.execute('MockState.inCombat = true')
    assert frames.eval('HogHealsFrames.TestMode.Start(5)') is False
