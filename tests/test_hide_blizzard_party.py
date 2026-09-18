# Tester: "It should be default that when our party frames are on, the Blizzard ones are hidden."
# There was no code for this at all. What the screenshot shows (green block titled "Party") is CompactPartyFrame,
# the raid-style party frames; the classic PartyMemberFrame1-4 / modern PartyFrame pool are handled as well.

SETUP = '''
for _, n in ipairs({ "CompactPartyFrame", "CompactRaidFrameContainer", "PartyFrame", "PartyMemberFrame1", "PartyMemberFrame2" }) do
  local f = CreateFrame("Frame", n, UIParent); f:RegisterEvent("GROUP_ROSTER_UPDATE"); f:Show()
end
HH_pool = { CreateFrame("Frame", "HHPoolMember1", PartyFrame) }
PartyFrame.PartyMemberFramePool = { EnumerateActive = function() local i = 0 return function() i = i + 1 return HH_pool[i] end end }
'''
NAMES = ["CompactPartyFrame", "CompactRaidFrameContainer", "PartyFrame", "PartyMemberFrame1", "PartyMemberFrame2", "HHPoolMember1"]


def test_default_on_hides_every_blizzard_group_frame(frames):
    assert frames.eval('HogHeals.defaults.profile.frames.hideBlizzard') is True
    frames.execute(SETUP)
    frames.execute('MockSetGroup(3, false); HogHealsFrames.Headers.Apply("party")')
    for n in NAMES:
        assert frames.eval(f'{n}:IsShown()') is False, n
        assert frames.eval(f'{n}:GetParent() ~= UIParent and {n}:GetParent():IsShown() == false'), n
    assert frames.eval('CompactPartyFrame._events.GROUP_ROSTER_UPDATE') is None


def test_frames_created_later_are_caught_on_the_next_roster_update(frames):
    frames.execute('MockSetGroup(3, false); HogHealsFrames.Headers.Apply("party")')      # nothing exists yet: no error
    frames.execute(SETUP)
    frames.execute('MockSetGroup(4, false); MockFire("GROUP_ROSTER_UPDATE"); HogHealsFrames.Headers.Apply("party")')
    assert frames.eval('CompactPartyFrame:IsShown()') is False


def test_option_off_leaves_blizzard_alone(frames):
    frames.execute('HogHeals.db.profile.frames.hideBlizzard = false')
    frames.execute(SETUP)
    frames.execute('MockSetGroup(3, false); HogHealsFrames.Headers.Apply("party")')
    assert frames.eval('CompactPartyFrame:IsShown()') is True
    assert frames.eval('CompactPartyFrame:GetParent() == UIParent')


def test_never_touched_in_combat(frames):
    frames.execute(SETUP)
    frames.execute('MockState.inCombat = true; HogHealsFrames.Headers.HideBlizzard()')
    assert frames.eval('CompactPartyFrame:IsShown()') is True
    frames.execute('MockState.inCombat = false; MockFire("PLAYER_REGEN_ENABLED")')
    assert frames.eval('CompactPartyFrame:IsShown()') is False


def test_there_is_a_toggle_that_says_reload_is_needed_to_bring_them_back(frames):
    frames.execute('HH_found = nil; local function walk(t) for k, o in pairs(t.args or {}) do if k == "hideBlizzard" then HH_found = o end if o.type == "group" then walk(o) end end end walk(HogHeals.OptionsTable())')
    assert frames.eval('HH_found ~= nil and HH_found.type') == "toggle"
    assert "reload" in frames.eval('HH_found.desc').lower()
