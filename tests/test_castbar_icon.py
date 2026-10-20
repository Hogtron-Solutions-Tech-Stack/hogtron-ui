# The HUD cast bar's icon inside the bar and the spell name centred (Sean 2026-10-18: "I want to put the spell icon
# inside of the cast bar. You see how it's kind of hanging off the left-hand side ... And then I also want to center
# the text for the actual spell name, just like the mana is below."), and the target / focus bars alike.
import pytest

from test_castbar import cb, start_cast  # noqa: F401  (fixture)

C = "HogHealsHUD.Castbar"


def pts(f, region):
    return sorted(tuple(list(p.values())[i] for i in (0, 2, 3, 4)) for p in f.eval(f"{region}._points").values())


def test_the_icon_sits_inside_the_bar_and_the_fill_starts_after_it(cb):  # noqa: F811
    start_cast(cb)                                              # 2.5 s cast at t=100, bar 200 px, icon 18 px
    assert pts(cb, "HH_cb.icon") == [("LEFT", "LEFT", 0, 0)]    # inside, at the bar's left end
    assert cb.eval("HH_cb.icon:GetWidth()") == 18 and cb.eval("HH_cb.icon._layer") == "OVERLAY"
    assert cb.eval("HH_cb:GetValue()") == pytest.approx(18 / 200)      # at the start the fill reaches the icon's edge
    cb.execute(f"MockState.time = 101.25; {C}.OnUpdate(HH_cb)")       # half way
    assert cb.eval("HH_cb:GetValue()") == pytest.approx((18 + 182 * 0.5) / 200)
    spark = list(cb.eval("HH_cb.spark._points[1]").values())
    assert spark[3] == pytest.approx(18 + 182 * 0.5)                   # the spark rides the same head
    cb.execute(f"MockState.time = 102.5; {C}.OnUpdate(HH_cb)")
    assert cb.eval("HH_cb:GetValue()") == pytest.approx(1)


def test_the_spell_name_is_centred_clear_of_the_icon_and_the_seconds(cb):  # noqa: F811
    start_cast(cb)
    assert cb.eval("HH_cb.text._justifyH") == "CENTER"
    left, right = pts(cb, "HH_cb.text")
    assert left == ("LEFT", "LEFT", 34, 0) and right == ("RIGHT", "RIGHT", -34, 0)   # same margin both sides: true centre


def test_the_old_look_on_request(cb):  # noqa: F811
    cb.execute('''local c = HogHeals.db.profile.hud.castbar
      HogHeals.OptionsTable().args.HUD.args.castbar.args.iconInside.set({}, "outside")
      HogHeals.OptionsTable().args.HUD.args.castbar.args.textAlign.set({}, "LEFT")''')
    start_cast(cb)
    assert pts(cb, "HH_cb.icon") == [("RIGHT", "LEFT", -2, 0)]  # hanging off the left again
    assert cb.eval("HH_cb:GetValue()") == 0                     # the fill is the plain progress
    assert cb.eval("HH_cb.text._justifyH") == "LEFT"
    assert pts(cb, "HH_cb.text")[0] == ("LEFT", "LEFT", 4, 0)
    assert cb.eval("HogHeals.OptionsTable().args.HUD.args.castbar.args.iconInside.get({})") == "outside"


def test_no_icon_means_no_inset(cb):  # noqa: F811
    cb.execute("HogHeals.db.profile.hud.castbar.icon = false; HogHealsHUD.HUD.Refresh()")
    start_cast(cb)
    assert cb.eval("HH_cb:GetValue()") == 0
    assert cb.eval("HogHeals.OptionsTable().args.HUD.args.castbar.args.iconInside.hidden()") is True


def test_the_target_cast_bar_keeps_its_icon_inside_the_frame_width_and_centres_its_text(lua):
    from test_units import boot
    u = boot(lua)
    u.execute('''MockUnits.target = { name = "Kobold", class = "WARRIOR", isPlayer = false, health = 1, maxHealth = 1, guid = "C-1" }
      MockFire("PLAYER_TARGET_CHANGED")''')
    h = u.eval("HogHeals.db.profile.units.target.castbarHeight")
    left = [p for p in pts(u, "HogUITarget.castbar") if p[0] == "BOTTOMLEFT"][0]
    assert left == ("BOTTOMLEFT", "TOPLEFT", h + 2, 6)                  # the bar starts after the icon ...
    assert pts(u, "HogUITarget.castbar.icon") == [("RIGHT", "LEFT", -3, 0)]   # ... which sits inside the frame's width
    assert u.eval("HogUITarget.castbar.text._justifyH") == "CENTER"
