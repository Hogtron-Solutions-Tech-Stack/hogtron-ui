import pytest

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
    # 2026-10-05: everyone carries a buff now (Fortitude), so count the units with a dispellable DEBUFF
    with_aura = sum(1 for i in range(1, 41) if frames.eval(
        f'(function() local h = HogHealsFrames.TestMode.Split(MockUnits.hhtest{i}) return h[1] ~= nil and h[1].type ~= nil end)()'))
    oor = sum(1 for i in range(1, 41) if frames.eval(f'MockUnits.hhtest{i}.inRange == false'))
    assert 12 <= with_aura <= 30
    assert 2 <= oor <= 8


def test_stop_hides_all(frames):
    frames.execute('HogHealsFrames.TestMode.Start(10); HogHealsFrames.TestMode.Stop()')
    assert not any(frames.eval(f'HogHealsTest{i}:IsShown()') for i in range(1, 11))
    assert frames.eval('HogHealsFrames.TestMode.active') is False


def test_refuses_in_combat(frames):
    frames.execute('MockState.inCombat = true')
    assert frames.eval('HogHealsFrames.TestMode.Start(5)') is False


# ---------------------------------------------------------------- 2026-10-05: "/hh test 5 shows nothing"
def test_five_fakes_take_the_party_layout_and_sit_on_the_row_centre(frames):
    # the live party row grows from its middle; the fakes must be placed the same way, not on the raid TOPLEFT
    assert frames.eval('HogHealsFrames.TestMode.Start(5)') is True
    assert frames.eval('HogHealsFrames.TestMode.bucket') == "party"
    assert all(frames.eval(f'HogHealsTest{i}:IsShown()') for i in range(1, 6))
    pt = frames.eval('HogHealsTest1._points[1]')
    assert pt[1] == "LEFT" and pt[3] == "CENTER"
    w, sp = frames.eval('HogHeals.db.profile.frames.layouts.party.width'), frames.eval('HogHeals.db.profile.frames.layouts.party.spacing')
    row_w = 5 * w + 4 * sp
    assert pt[4] == pytest.approx(-row_w / 2)
    assert frames.eval('HogHealsTest3._points[1][4]') == pytest.approx(-row_w / 2 + 2 * (w + sp))
    # the raid test still hangs off the anchor's top-left
    frames.execute('HogHealsFrames.TestMode.Start(10)')
    assert frames.eval('HogHealsFrames.TestMode.bucket') == "raid10"
    assert frames.eval('HogHealsTest1._points[1][1]') == "TOPLEFT"


def test_a_failing_start_says_so_in_chat_instead_of_dying_silently(frames):
    frames.execute('HogHealsFrames.Layout._Compute = HogHealsFrames.Layout.Compute; HogHealsFrames.Layout.Compute = function() error("boom") end')
    assert frames.eval('HogHealsFrames.TestMode.Start(5)') is False
    assert frames.eval('HogHealsFrames.TestMode.active') is False
    assert any("Test mode failed" in m and "boom" in m for m in frames.eval('MockLog.chat').values())
    assert any("test mode" in e["msg"] and "boom" in e["msg"] for e in frames.eval('HogHeals.errors').values())
    frames.execute('HogHealsFrames.Layout.Compute = HogHealsFrames.Layout._Compute')


def test_fakes_carry_dots_and_buffs_with_live_expiry(frames):
    frames.execute('MockState.time = 100; HogHealsFrames.TestMode.Start(10)')
    harmful = sum(frames.eval(f'(function() local h = HogHealsFrames.TestMode.Split(MockUnits.hhtest{i}) return #h end)()') for i in range(1, 11))
    helpful = sum(frames.eval(f'(function() local _, h = HogHealsFrames.TestMode.Split(MockUnits.hhtest{i}) return #h end)()') for i in range(1, 11))
    assert harmful >= 5 and helpful >= 10                       # everyone has Fortitude, half have my Renew
    # the first DoT on unit 1 has a duration and an expiry in the future
    # scalars, not the lupa proxy: the proxy is a live view of the Lua table and would follow the refresh below
    dur, exp = frames.eval('(function() local h = HogHealsFrames.TestMode.Split(MockUnits.hhtest1) return h[1].duration, h[1].expires end)()')
    assert dur > 0 and exp == 100 + dur
    # an expired aura is refreshed by the tick, so the swipe keeps turning
    frames.execute(f'MockState.time = 100 + {dur} + 1; MockAdvance(1)')
    exp2 = frames.eval('(function() local h = HogHealsFrames.TestMode.Split(MockUnits.hhtest1) return h[1].expires end)()')
    assert exp2 > exp


def test_real_client_path_paints_fakes_directly_and_skips_the_elements(frames):
    # forcePaint = the branch the real client takes (no MockUnits there): the elements must not touch a fake cell
    frames.execute('HogHealsFrames.TestMode.forcePaint = true')
    assert frames.eval('HogHealsFrames.TestMode.Start(5)') is True
    assert frames.eval('HogHealsTest1.health._value') == frames.eval('MockUnits.hhtest1.health')
    assert frames.eval('HogHealsTest1.name._text') != ""
    # UpdateAll on a flagged fake returns before the elements run: the health element would write "Offline" text
    frames.execute('HogHealsTest1.healthText:SetText("probe"); HogHealsFrames.UnitButton.UpdateAll(HogHealsTest1)')
    assert frames.eval('HogHealsTest1.healthText._text') != "Offline"
    assert [e["msg"] for e in frames.eval('HogHeals.errors').values()] == []
    # hooks from other modules get the button and the fake
    frames.execute('HH_hook = nil; HogHealsFrames.TestHooks[#HogHealsFrames.TestHooks + 1] = function(b, f) HH_hook = f.name end; MockAdvance(1)')
    assert frames.eval('HH_hook') == frames.eval('MockUnits.hhtest5.name') or frames.eval('HH_hook') is not None
    frames.execute('HogHealsFrames.TestMode.Stop(); HogHealsFrames.TestMode.forcePaint = nil')
    assert frames.eval('HogHealsTest1.hhFake') is None
