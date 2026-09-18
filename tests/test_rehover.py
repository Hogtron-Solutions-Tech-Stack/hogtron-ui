# In game: hover keys worked during the fight and died the moment combat ended, until the mouse moved off and
# back. Cause: the post-combat layout pass hides/re-shows every header button; hide-under-cursor fires OnLeave
# (keys cleared), OnEnter does not fire again by itself.

def test_reshow_under_the_cursor_restores_hover_keys(frames):
    frames.execute("""
      HH_b = HogHealsFrames.UnitButton.Create("HHRehoverBtn", UIParent)
      HogHealsFrames.ClickCast.SetBindings({ { key = "1", mod = "", type = "spell", value = "Healing Wave" } })
      HogHealsFrames.ClickCast.Apply(HH_b)
      HH_b._mouseOver = true
      HogHealsFrames.UnitButton.OnEnter(HH_b)
      HogHealsFrames.UnitButton.OnLeave(HH_b)          -- what the client does when the frame hides under the cursor
      wipe(MockBindings.clicks)
      HH_b:GetScript("OnShow")(HH_b)                   -- the re-show
    """)
    clicks = list(frames.eval('MockBindings.clicks').values())
    assert any(c["key"] == "1" and c["name"] == "HHRehoverBtn" for c in clicks)


def test_reshow_without_the_cursor_does_nothing(frames):
    frames.execute("""
      HH_c = HogHealsFrames.UnitButton.Create("HHRehoverBtn2", UIParent)
      HH_c._mouseOver = false
      wipe(MockBindings.clicks)
      HH_c:GetScript("OnShow")(HH_c)
    """)
    assert list(frames.eval('MockBindings.clicks').values()) == []


def test_reshow_in_combat_does_not_call_the_protected_function(frames):
    frames.execute("""
      HH_d = HogHealsFrames.UnitButton.Create("HHRehoverBtn3", UIParent)
      HH_d._mouseOver = true
      MockState.inCombat = true
      wipe(MockBindings.clicks)
      HH_d:GetScript("OnShow")(HH_d)
      MockState.inCombat = false
    """)
    assert list(frames.eval('MockBindings.clicks').values()) == []
