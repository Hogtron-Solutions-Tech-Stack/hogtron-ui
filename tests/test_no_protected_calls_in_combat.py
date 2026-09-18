# diag log, session 18: ADDON_ACTION_BLOCKED x25 "HogHeals_Frames called HogHealsPartyHeaderUnitButtonN:SetSize()
# (in combat)". Frames:Refresh -> ApplyAppearance ran immediately in combat while only the header write was queued.

def test_appearance_refresh_in_combat_never_resizes_a_secure_button(frames):
    frames.execute("""
      MockSetGroup(3, false); HogHealsFrames.Headers.Apply("party")
      HH_btn = HogHealsPartyHeaderUnitButton1
      HH_btn._width, HH_btn._height = 1, 1
      MockState.inCombat = true
      HogHeals.db.profile.frames.appearance.fontSize = 14
      HogHealsFrames.module:Refresh()
    """)
    assert frames.eval('HH_btn:GetWidth()') == 1        # untouched in combat
    frames.execute('MockState.inCombat = false; HogHealsFrames.module:Refresh()')
    assert frames.eval('HH_btn:GetWidth()') == frames.eval('HogHeals.db.profile.frames.layouts.party.width')
