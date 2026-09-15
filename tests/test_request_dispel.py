def setup(frames):
    frames.execute('''
      MockSetGroup(5, false)
      MockUnits.party2.name = "Zugzug"
      HH_b = HogHealsFrames.UnitButton.Create("HogHealsReqBtn", UIParent)
      HH_b.unit = "party2"
    ''')


def test_incoming_request_glows_sender_frame(frames):
    setup(frames)
    frames.execute('MockFire("CHAT_MSG_ADDON", "HHREQ", "D", "PARTY", "Zugzug-Nightslayer")')
    assert frames.eval('HH_b.requestGlow:IsShown()') is True
    assert frames.eval('HH_b.requestGlow.kind') == "dispel"
    frames.execute('MockAdvance(6)')
    assert frames.eval('HH_b.requestGlow:IsShown()') is False


def test_unknown_sender_or_prefix_ignored(frames):
    setup(frames)
    frames.execute('MockFire("CHAT_MSG_ADDON", "OTHER", "D", "PARTY", "Zugzug-Nightslayer")')
    frames.execute('MockFire("CHAT_MSG_ADDON", "HHREQ", "D", "PARTY", "Nobody-Nightslayer")')
    assert frames.eval('HH_b.requestGlow:IsShown()') is False


def test_send_request_uses_addon_message(frames):
    frames.execute('''
      HH_sent = {}
      C_ChatInfo.SendAddonMessage = function(prefix, msg, channel) HH_sent[#HH_sent+1] = prefix .. "|" .. msg .. "|" .. channel return 0 end
      MockSetGroup(5, false)
      HogHeals:SlashCommand("dispelme")
      MockSetGroup(25, true)
      HogHeals:SlashCommand("dispelme")
    ''')
    assert list(frames.eval('HH_sent').values()) == ["HHREQ|D|PARTY", "HHREQ|D|RAID"]


def test_prefix_registered_on_enable(frames):
    assert frames.eval('HogHealsFrames.RequestDispel.registered') is True
