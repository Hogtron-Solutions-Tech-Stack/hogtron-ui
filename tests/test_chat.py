# HogHeals_Chat: restyle Blizzard's chat windows (never replace them). Chat text can be SECRET on restricted clients.
import pytest

CHAT = '''
NUM_CHAT_WINDOWS = 3
CHAT_FRAME_TEXTURES = { "Background", "TopLeftTexture" }
ADDED = {}
for i = 1, 3 do
  local n = "ChatFrame" .. i
  local cf = CreateFrame("ScrollingMessageFrame", n, UIParent)
  cf._font = { "Fonts\\\\ARIALN.TTF", 14, "" }
  function cf:GetFont() return unpack(self._font) end
  function cf:SetFont(f, s, o) self._font = { f, s, o } end
  function cf:AddMessage(msg) ADDED[#ADDED + 1] = { frame = self:GetName(), msg = msg } end
  local bg = cf:CreateTexture(n .. "Background", "BACKGROUND") bg:SetTexture("Interface\\\\ChatFrame\\\\ChatFrameBackground")
  cf:CreateTexture(n .. "TopLeftTexture", "BORDER"):SetTexture("x")
  local tab = CreateFrame("Button", n .. "Tab", UIParent)
  tab:CreateTexture(n .. "TabLeft", "BACKGROUND"):SetTexture("Interface\\\\ChatFrame\\\\ChatFrameTab-BGLeft")
  tab.Text = tab:CreateFontString(n .. "TabText", "OVERLAY", "GameFontNormalSmall")
  function tab.Text:GetFont() return "Fonts\\\\FRIZQT__.TTF", 10, "" end
  local eb = CreateFrame("EditBox", n .. "EditBox", UIParent)
  eb:CreateTexture(n .. "EditBoxLeft", "BACKGROUND"):SetTexture("Interface\\\\ChatFrame\\\\UI-ChatInputBorder-Left")
  function eb:GetFont() return "Fonts\\\\ARIALN.TTF", 14, "" end
  CreateFrame("Frame", n .. "ButtonFrame", UIParent)
end
SELECTED_CHAT_FRAME = ChatFrame1
CLASSED = {}
function SetChatColorNameByClass(t, on) CLASSED[t] = on end
ORIG_ADD = ChatFrame1.AddMessage
CHAT_GUILD_GET = "|Hchannel:GUILD|h[Guild]|h %s:"
CHAT_PARTY_LEADER_GET = "|Hchannel:PARTY|h[Party Leader]|h %s:"
FILTERS = {}
function ChatFrame_AddMessageEventFilter(ev, fn) FILTERS[ev] = fn end
'''


@pytest.fixture
def chat(lua):
    lua.execute(CHAT)
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Chat")
    lua.player_login()
    lua.execute('wipe(HogHeals.errors)')
    return lua


def errors(lua):
    return [e["msg"] for e in lua.eval('HogHeals.errors').values()]


@pytest.mark.parametrize("src,want", [
    ("|Hchannel:channel:1|h[1. General - Tirisfal Glades]|h |Hplayer:Father|h[Father]|h: mining", "|Hchannel:channel:1|h[1]|h |Hplayer:Father|h[Father]|h: mining"),
    ("|Hchannel:GUILD|h[Guild]|h |Hplayer:Cat|h[Cat]|h: what happened?", "|Hchannel:GUILD|h[G]|h |Hplayer:Cat|h[Cat]|h: what happened?"),
    ("|Hchannel:PARTY|h[Party Leader]|h hi", "|Hchannel:PARTY|h[PL]|h hi"),
    ("[2. Trade - City] wts", "[2] wts"),
    ("|Hplayer:Guild|h[Guild]|h says hi", "|Hplayer:Guild|h[Guild]|h says hi"),   # a PLAYER named Guild stays
    ("You receive loot: |Hitem:1|h[Linen Cloth]|h", "You receive loot: |Hitem:1|h[Linen Cloth]|h"),
])
def test_shorten(chat, src, want):
    chat.execute(f'R = HogHealsChat.Chat.Shorten({src!r})'.replace("\\\\", "\\"))
    assert chat.eval('R') == want


def test_secret_message_passes_through_untouched(chat):
    chat.execute('MockSetSecrets(true); S = MockSecret("[1. General] hi"); ChatFrame1:AddMessage(S)')
    assert chat.eval('ADDED[#ADDED].msg == S')
    assert errors(chat) == []


def test_addmessage_is_never_replaced_prefixes_shortened_through_blizzards_format_strings(chat):
    # In game 2026-10-01: a replaced AddMessage made every say / general / guild line vanish on the new client build
    # (secure Blizzard_ChatFrameBase calling a tainted method). The frame's method must be Blizzard's own.
    assert chat.eval('rawget(ChatFrame1, "AddMessage") == ORIG_ADD') is True
    chat.execute('ChatFrame1:AddMessage("[1. General - Elwynn] hi")')
    assert chat.eval('ADDED[#ADDED].msg') == "[1. General - Elwynn] hi"          # untouched on the way in
    assert chat.eval('CHAT_GUILD_GET') == "|Hchannel:GUILD|h[G]|h %s:"
    assert chat.eval('CHAT_PARTY_LEADER_GET') == "|Hchannel:PARTY|h[PL]|h %s:"
    # the option off: Blizzard's originals back
    chat.execute('HogHeals.db.profile.chat.shortChannels = false; HogHealsChat.Chat.Refresh()')
    assert chat.eval('CHAT_GUILD_GET') == "|Hchannel:GUILD|h[Guild]|h %s:"
    chat.execute('HogHeals.db.profile.chat.shortChannels = true; HogHealsChat.Chat.Refresh()')
    assert chat.eval('CHAT_GUILD_GET') == "|Hchannel:GUILD|h[G]|h %s:"
    assert errors(chat) == []


def test_event_filter_links_urls_never_touches_the_channel_string_and_leaves_secret_text_alone(chat):
    assert chat.eval('FILTERS.CHAT_MSG_SAY ~= nil and FILTERS.CHAT_MSG_CHANNEL ~= nil and FILTERS.CHAT_MSG_GUILD ~= nil')
    chat.execute('F, M, A2, A3, CH = FILTERS.CHAT_MSG_SAY(ChatFrame1, "CHAT_MSG_SAY", "look https://a.b/c", "Bob", "", "")')
    assert chat.eval('F') is False and "|Hhogurl:https://a.b/c|h" in chat.eval('M') and chat.eval('A2') == "Bob"
    # the channel string is NEVER rewritten (in game 2026-10-01: "1" instead of "1. General - Elwynn" made Blizzard drop
    # every channel line - its window test is strlen(arg4) > strlen(channel name))
    assert chat.eval('FILTERS.CHAT_MSG_CHANNEL(ChatFrame1, "CHAT_MSG_CHANNEL", "wts linen", "Bob", "", "1. General - Elwynn")') is None
    chat.execute('F, M, A2, A3, CH = FILTERS.CHAT_MSG_CHANNEL(ChatFrame1, "CHAT_MSG_CHANNEL", "see https://a.b", "Bob", "", "1. General - Elwynn")')
    assert chat.eval('F') is False and chat.eval('CH') == "1. General - Elwynn" and "|Hhogurl:" in chat.eval('M')
    # nothing to change: no return at all (Blizzard keeps its arguments)
    assert chat.eval('FILTERS.CHAT_MSG_SAY(ChatFrame1, "CHAT_MSG_SAY", "plain words", "Bob")') is None
    # secret text (restricted client): untouched, no error
    chat.execute('MockSetSecrets(true); R = { FILTERS.CHAT_MSG_CHANNEL(ChatFrame1, "CHAT_MSG_CHANNEL", MockSecret("x https://q.r"), "Bob", "", MockSecret("1. General")) }')
    assert chat.eval('#R') == 0
    assert errors(chat) == []


def test_window_tab_and_editbox_restyled(chat):
    assert chat.eval('ChatFrame1Background._texture') is None
    assert chat.eval('ChatFrame1TopLeftTexture._texture') is None
    assert chat.eval('ChatFrame1TabLeft._texture') is None
    assert chat.eval('ChatFrame1EditBoxLeft._texture') is None
    s = 'HogHealsChat.Chat.styled[ChatFrame1]'
    assert chat.eval(f'{s}.panel.bg._color[4]') == pytest.approx(0.6)
    assert chat.eval(f'{s}.eb.rule._color[2]') == pytest.approx(0.83)
    assert chat.eval('ChatFrame1ButtonFrame:IsShown()') is False
    chat.execute('ChatFrame1ButtonFrame:Show()')
    assert chat.eval('ChatFrame1ButtonFrame:IsShown()') is False      # Blizzard re-show is undone
    assert errors(chat) == []


def test_selected_tab_is_cyan_with_underline(chat):
    assert chat.eval('ChatFrame1TabText._color[2]') == pytest.approx(0.83)
    assert chat.eval('HogHealsChat.Chat.styled[ChatFrame1].rule:IsShown()') is True
    assert chat.eval('HogHealsChat.Chat.styled[ChatFrame3].rule:IsShown()') is False
    chat.execute('SELECTED_CHAT_FRAME = ChatFrame3; HogHealsChat.Chat.UpdateTabs()')
    assert chat.eval('ChatFrame1TabText._color[2]') == pytest.approx(0.92)
    assert chat.eval('HogHealsChat.Chat.styled[ChatFrame3].rule:IsShown()') is True


def test_font_size_only_changes_when_set(chat):
    assert chat.eval('(select(2, ChatFrame1:GetFont()))') == 14
    chat.execute('HogHeals.db.profile.chat.fontSize = 18; HogHealsChat.Chat.Refresh()')
    assert chat.eval('(select(2, ChatFrame1:GetFont()))') == 18
    assert chat.eval('(ChatFrame1:GetFont())') == "Fonts\\ARIALN.TTF"   # face kept


def test_class_coloured_names(chat):
    assert chat.eval('CLASSED.GUILD') is True and chat.eval('CLASSED.CHANNEL1') is True


def test_options_walk_clean(chat):
    chat.execute('''
      local t = HogHeals.OptionsTable().args.Chat
      for _, o in pairs(t.args) do if o.get then o.get({}) end end
      t.args.fontSize.set({}, 20)
      t.args.hideMenuButtons.set({}, true)
    ''')
    assert chat.eval('(select(2, ChatFrame2:GetFont()))') == 20
    assert errors(chat) == []


@pytest.mark.parametrize("src,want", [
    ("see https://hogtron-solutions.com/free-audit/ now", "see |Hhogurl:https://hogtron-solutions.com/free-audit/|h|cff21D4E0[https://hogtron-solutions.com/free-audit/]|r|h now"),
    ("go to www.wowhead.com.", "go to |Hhogurl:www.wowhead.com|h|cff21D4E0[www.wowhead.com]|r|h."),
    ("|Hitem:1|h[Linen Cloth]|h at http://x.io", "|Hitem:1|h[Linen Cloth]|h at |Hhogurl:http://x.io|h|cff21D4E0[http://x.io]|r|h"),
    ("no links here 3.5k dps e.g. this", "no links here 3.5k dps e.g. this"),
])
def test_link_urls(chat, src, want):
    chat.execute(f'R = HogHealsChat.Chat.LinkURLs({src!r})')
    assert chat.eval('R') == want


def test_clicking_a_url_opens_the_copy_box(chat):
    chat.execute('function SetItemRef() end')
    # the hook is installed at enable; re-enable to pick up the function defined above
    chat.execute('HogHealsChat.module:OnEnable()')
    chat.execute('SetItemRef("hogurl:https://example.com/a", "[https://example.com/a]", "LeftButton")')
    assert chat.eval('HogUIURLCopy:IsShown()') is True
    assert chat.eval('HogUIURLCopy.box._text') == "https://example.com/a"
    chat.execute('_, M = FILTERS.CHAT_MSG_SAY(ChatFrame1, "CHAT_MSG_SAY", "look https://a.b/c", "Bob")')
    assert "|Hhogurl:https://a.b/c|h" in chat.eval('M')
    assert errors(chat) == []
