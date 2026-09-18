# Tester: "when I join a party, it makes my frames a different size than when I'm solo." Solo and party were
# separate layouts (solo had a saved width of 163, party the default 90).

def test_solo_renders_with_the_party_layout_by_default(frames):
    frames.execute('local L = HogHeals.db.profile.frames.layouts; L.solo.width = 163; L.party.width = 90; L.party.growth = "CENTER"')
    frames.execute('HogHealsFrames.Headers.Apply("solo")')
    assert frames.eval('HogHealsPartyHeader:GetAttribute("hhWidth")') == 90
    assert frames.eval('HogHealsPartyHeaderUnitButton1:GetWidth()') == 90
    frames.execute('MockSetGroup(3, false); HogHealsFrames.Headers.Apply("party")')
    assert frames.eval('HogHealsPartyHeaderUnitButton1:GetWidth()') == 90


def test_show_solo_is_still_read_from_the_solo_table(frames):
    frames.execute('HogHeals.db.profile.frames.layouts.solo.showSolo = false; HogHealsFrames.Headers.Apply("solo")')
    assert frames.eval('HogHealsPartyHeader:GetAttribute("showSolo")') is False


def test_untick_gives_solo_its_own_layout_again(frames):
    frames.execute('local L = HogHeals.db.profile.frames.layouts; L.solo.width = 163; L.party.width = 90; HogHeals.db.profile.frames.soloSharesParty = false')
    frames.execute('HogHealsFrames.Headers.Apply("solo")')
    assert frames.eval('HogHealsPartyHeader:GetAttribute("hhWidth")') == 163


def test_options_edit_the_shared_layout_while_solo(frames):
    frames.execute('HogHeals.db.profile.frames.layouts.party.width = 90; HogHealsFrames.module.bucket = "solo"')
    assert frames.eval('HogHealsFrames.module:LayoutFor().width') == 90
    assert frames.eval('HogHealsFrames.module:LayoutFor() == HogHeals.db.profile.frames.layouts.party')
