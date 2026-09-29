# HogUI Atlas: the on-screen dungeon tracker and drop sharing with party / guild.
import pytest

from atlas_helpers import boot, errors, vals

A = "HogHealsAtlas"
T = "HogHealsAtlas.Tracker"
SH = "HogHealsAtlas.Share"
S = "HogHealsAtlas.Store"
G = "HogHealsAtlas.Gear"

COMMS = '''
SENT = {}
C_ChatInfo = {
  RegisterAddonMessagePrefix = function(p) PREFIX = p return true end,
  SendAddonMessage = function(prefix, msg, channel) if REFUSE then error("blocked") end SENT[#SENT + 1] = { prefix, msg, channel } return true end,
}
GROUPED, GUILDED, RAIDED = true, true, false
function IsInGroup() return GROUPED end
function IsInRaid() return RAIDED end
function IsInGuild() return GUILDED end
'''


@pytest.fixture
def atlas(lua):
    boot(lua, extra=COMMS)
    lua.execute("MockUnits.player.level = 20")
    return lua


def enter(lua, name="The Deadmines", inst=36):
    lua.execute('INST = { name = "%s", id = %d }; MockFire("PLAYER_ENTERING_WORLD", false, false); MockAdvance(1)' % (name, inst))


def kill(lua, boss, enc=1):
    lua.execute('MockFire("ENCOUNTER_END", %d, "%s", 1, 5, 1); MockAdvance(1)' % (enc, boss))


def rows(lua):
    return vals(lua.eval(f"{T}.list.data"))


# ------------------------------------------------------------------------------------------------ tracker
def test_tracker_is_hidden_outside_and_shows_when_you_walk_in(atlas):
    atlas.execute("MockAdvance(1)")
    assert atlas.eval("HogUIAtlasTracker") is None                                 # not even built outside a dungeon
    enter(atlas)
    assert atlas.eval("HogUIAtlasTracker:IsShown()") is True
    assert atlas.eval("HogUIAtlasTracker.title:GetText()") == "The Deadmines   17-26"
    got = rows(atlas)
    assert (got[0]["text"], got[0]["right"], got[0]["header"]) == ("Bosses", "0 / 7", True)
    assert [r["text"] for r in got[1:8]] == ["Rhahk'Zor", "Sneed's Shredder", "Gilnid", "Mr. Smite", "Cookie", "Captain Greenskin", "Edwin VanCleef"]
    assert "Miner Johnson" not in [r["text"] for r in got]                          # a rare that may not be up is not a task
    atlas.execute('INST = nil; MockFire("ZONE_CHANGED_NEW_AREA"); MockAdvance(1)')
    assert atlas.eval("HogUIAtlasTracker:IsShown()") is False
    assert errors(atlas) == []


def test_bosses_tick_off_as_they_die_by_event_or_by_loot(atlas):
    enter(atlas)
    kill(atlas, "Rhahk'Zor")
    atlas.execute('MockUnits.target = { name = "Gilnid", guid = NpcGUID(1763), health = 1, maxHealth = 1, isPlayer = false }; MockFire("PLAYER_TARGET_CHANGED")')
    atlas.execute('MockAdvance(60); LOOT = { { link = ItemLink(1001), guid = NpcGUID(1763) } }; MockFire("LOOT_OPENED", true); MockAdvance(1)')
    got = {r["text"]: r for r in rows(atlas)}
    assert got["Bosses"]["right"] == "2 / 7"
    assert got["Rhahk'Zor"]["right"] == "done" and got["Gilnid"]["right"] == "done" and got["Cookie"]["right"] == ""
    assert list(got["Gilnid"]["color"].values()) == pytest.approx([0.55, 0.55, 0.60])      # done = greyed
    kill(atlas, "Miner Johnson")                                                   # the rare was up and died: now it is listed
    assert {r["text"]: r for r in rows(atlas)}["Miner Johnson"]["right"] == "done"
    assert rows(atlas)[0]["right"] == "2 / 7"                                      # and does not count toward the total


def test_a_new_run_starts_with_nothing_ticked(atlas):
    enter(atlas)
    kill(atlas, "Cookie")
    atlas.execute('INST = nil; MockFire("ZONE_CHANGED_NEW_AREA"); MockAdvance(1)')
    enter(atlas)
    assert rows(atlas)[0]["right"] == "0 / 7"


def test_a_dead_boss_tells_the_wing_apart(atlas):
    enter(atlas, "Scarlet Monastery", 189)
    assert atlas.eval(f"({T}.Here())") == "sm_gy"                                  # nothing dead yet: the first wing
    kill(atlas, "Herod")
    assert atlas.eval(f"({T}.Here())") == "sm_arm"
    assert atlas.eval("HogUIAtlasTracker.title:GetText()") == "Scarlet Monastery: Armory   32-42"
    assert rows(atlas)[0]["right"] == "1 / 1"


def test_new_dungeon_with_no_known_bosses_says_so_then_learns(atlas):
    enter(atlas, "Ruins of Lordaeron", 2999)
    assert [r["text"] for r in rows(atlas)] == ["Bosses", "None known yet: they appear as they die."]
    kill(atlas, "The Abandoned", 3001)
    got = rows(atlas)
    assert (got[0]["right"], got[1]["text"], got[1]["right"]) == ("1 / 1", "The Abandoned", "done")


def test_quests_and_wanted_items_show_below_the_bosses(atlas):
    atlas.execute(f"""
      FAKE = {{
        {{ title = "Red Silk Bandanas", state = "active", progress = "0/1", objectives = {{ {{ text = "Red Silk Bandana: 4/10", done = false }}, {{ text = "done part", done = true }} }} }},
        {{ title = "Collecting Memories", state = "ready", progress = "1/1", objectives = {{ {{ text = "x", done = true }} }} }},
        {{ title = "Oh Brother. . .", state = "none" }},
      }}
      {S}.Record("vc", "Cookie", 1001, "journal"); {S}.Record("wc", "Kresh", 1004, "journal")
      {G}.ToggleWish(1001); {G}.ToggleWish(1004); {G}.ToggleWish(1002)
    """)
    got = vals(atlas.eval(f'({T}.Rows("vc", {{ Cookie = true }}, FAKE))'))
    texts = [r["text"] for r in got]
    q = texts.index("Quests")
    assert got[q]["right"] == "2"
    assert texts[q + 1:q + 4] == ["Red Silk Bandanas", "Red Silk Bandana: 4/10", "Collecting Memories"]   # open objectives only
    assert got[q + 3]["right"] == "ready" and "Oh Brother. . ." not in texts
    w = texts.index("Wanted here")
    assert got[w]["right"] == "1" and texts[w + 1:] == ["Seer's Cowl"]              # 1004 drops elsewhere, 1002 has no source
    assert got[w + 1]["right"] == "Cookie" and got[w + 1]["item"] == 1001
    atlas.execute("BAGS = { 1001 }")
    assert "Wanted here" not in [r["text"] for r in vals(atlas.eval(f'({T}.Rows("vc", {{}}, FAKE))'))]    # you have it now


def test_slash_toggles_and_a_closed_panel_stays_closed_for_this_run_only(atlas):
    atlas.execute('MockLog.chat = {}; HogHeals:SlashCommand("dungeon")')
    assert "not in one" in "\n".join(vals(atlas.eval("MockLog.chat")))
    enter(atlas)
    atlas.execute('HogHeals:SlashCommand("dungeon")')
    assert atlas.eval("HogUIAtlasTracker:IsShown()") is False
    kill(atlas, "Cookie")
    assert atlas.eval("HogUIAtlasTracker:IsShown()") is False                       # closed means closed
    atlas.execute('INST = nil; MockFire("ZONE_CHANGED_NEW_AREA"); MockAdvance(1)')
    enter(atlas)
    assert atlas.eval("HogUIAtlasTracker:IsShown()") is True                        # next run: back


def test_option_off_keeps_it_away_but_the_slash_still_works(atlas):
    atlas.execute(f"{A}.cfg().tracker.enabled = false")
    enter(atlas)
    assert atlas.eval("HogUIAtlasTracker") is None
    atlas.execute('HogHeals:SlashCommand("dungeon")')
    assert atlas.eval("HogUIAtlasTracker:IsShown()") is True
    kill(atlas, "Cookie")
    assert atlas.eval("HogUIAtlasTracker:IsShown()") is True and rows(atlas)[0]["right"] == "1 / 7"


def test_panel_height_follows_its_rows_and_title_click_opens_the_window_here(atlas):
    enter(atlas)
    n = len(rows(atlas))
    assert atlas.eval("HogUIAtlasTracker:GetHeight()") == 20 + n * 16
    atlas.execute("""
      for _, c in ipairs({ HogUIAtlasTracker:GetChildren() }) do
        if c:GetScript("OnDragStop") then c:Click() end
      end
    """)
    assert atlas.eval("HogUIAtlasWindow:IsShown()") is True and atlas.eval(f"{A}.Window.dungeon") == "vc"


def test_defaults_added_later_reach_a_profile_saved_earlier(lua):
    lua.execute("HogHealsDB = { profileKeys = {}, profiles = { Default = { atlas = { _filled = true, enabled = true, minQuality = 3 } } } }")
    boot(lua, extra=COMMS)
    c = lua.eval(f"{A}.cfg()")
    assert c["minQuality"] == 3                                                     # what was saved stays
    assert c["share"] is True and c["tracker"]["enabled"] is True and c["_filled"] is None


# ------------------------------------------------------------------------------------------------ share
def test_encode_and_decode_round_trip(atlas):
    assert atlas.eval(f'{SH}.Encode("vc", "Edwin VanCleef", 1001)') == "1;vc;Edwin VanCleef;1001"
    assert list(atlas.eval(f'{{ {SH}.Decode("1;vc;Edwin VanCleef;1001") }}').values()) == ["vc", "Edwin VanCleef", 1001]
    assert atlas.eval(f'{SH}.Encode("vc", "Bad;Name", 1)') is None
    assert atlas.eval(f'{SH}.Encode("vc", "Boss", "12")') is None


@pytest.mark.parametrize("msg", [
    "",                                    # nothing
    "2;vc;Cookie;1001",                    # a version we do not speak
    "1;nowhere;Cookie;1001",               # a dungeon Atlas has no row for
    "1;vc;Cookie;abc",                     # not a number
    "1;vc;Cookie;0",                       # not an item
    "1;vc;Cookie;99999999",                # out of range
    "1;vc;Cookie",                         # too short
    "1;vc;Cookie;1001;extra",              # too long
    "1;vc;" + "B" * 61 + ";1001",          # a name no boss has
    "1;vc;Coo|cffff0000kie;1001",          # colour codes do not belong in a name
    "1;vc;Coo\\nkie;1001",                  # nor control characters
    "x" * 300,
])
def test_decode_refuses_anything_off_grammar(atlas, msg):
    atlas.execute('MSG = "%s"' % msg)
    assert atlas.eval(f"{SH}.Decode(MSG)") is None
    assert atlas.eval(f"{SH}.Decode(nil)") is None and atlas.eval(f"{SH}.Decode(42)") is None


def test_a_new_boss_drop_goes_to_party_and_guild_once(atlas):
    assert atlas.eval("PREFIX") == "HHATL" and atlas.eval(f"{SH}.ready") is True
    enter(atlas)
    kill(atlas, "Cookie")
    atlas.execute('LOOT = { { link = ItemLink(1001), guid = NpcGUID(645) } }; MockFire("LOOT_OPENED", true)')
    sent = [list(s.values()) for s in vals(atlas.eval("SENT"))]
    assert sent == [["HHATL", "1;vc;Cookie;1001", "PARTY"], ["HHATL", "1;vc;Cookie;1001", "GUILD"]]
    atlas.execute('LOOT = { { link = ItemLink(1001), guid = NpcGUID(645, 2) } }; MockFire("LOOT_OPENED", true)')
    assert len(vals(atlas.eval("SENT"))) == 2                                       # known already: nothing to tell


def test_trash_group_drops_and_the_switch_send_nothing(atlas):
    enter(atlas)
    atlas.execute('LOOT = { { link = ItemLink(1001), guid = NpcGUID(5555) } }; MockFire("LOOT_OPENED", true)')     # trash
    kill(atlas, "Cookie")
    atlas.execute('MockFire("CHAT_MSG_LOOT", "Thrall receives loot: " .. ItemLink(1004) .. ".", "Thrall")')         # his to tell
    assert vals(atlas.eval("SENT")) == []
    atlas.execute(f"{A}.cfg().share = false; MockAdvance(20)")
    atlas.execute('LOOT = { { link = ItemLink(1008), guid = NpcGUID(645) } }; MockFire("LOOT_OPENED", true)')
    assert vals(atlas.eval("SENT")) == [] and atlas.eval(f'{S}.db().loot.vc.Cookie[1008].src') == "seen"


def test_raid_channel_when_in_a_raid_and_solo_goes_nowhere(atlas):
    atlas.execute("RAIDED = true; GUILDED = false")
    assert atlas.eval(f'{SH}.Send("vc", "Cookie", 1001)') == 1
    assert list(vals(atlas.eval("SENT"))[0].values())[2] == "RAID"
    atlas.execute("RAIDED, GROUPED, GUILDED = false, false, false; SENT = {}")
    assert atlas.eval(f'{SH}.Send("vc", "Cookie", 1002)') == 0 and vals(atlas.eval("SENT")) == []


def test_received_drops_are_filed_as_group_and_my_own_echo_is_ignored(atlas):
    atlas.execute('MockFire("CHAT_MSG_ADDON", "HHATL", "1;lordaeron;The Abandoned;1007", "GUILD", "Thrall-ClassicBetaPvP")')
    assert atlas.eval(f'{S}.db().loot.lordaeron["The Abandoned"][1007].src') == "group"
    assert [r["name"] for r in vals(atlas.eval(f'{S}.Bosses("lordaeron")'))] == ["The Abandoned"]
    atlas.execute('MockFire("CHAT_MSG_ADDON", "HHATL", "1;vc;Cookie;1001", "PARTY", "Hognificent-ClassicBetaPvP")')
    atlas.execute('MockFire("CHAT_MSG_ADDON", "HHATL", "1;vc;Cookie;1002", "PARTY", "Hognificent")')
    assert atlas.eval(f'{S}.db().loot.vc') is None
    atlas.execute('MockFire("CHAT_MSG_ADDON", "OTHER", "1;vc;Cookie;1001", "PARTY", "Thrall")')                   # not our prefix
    assert atlas.eval(f'{S}.db().loot.vc') is None
    assert vals(atlas.eval("SENT")) == []                                           # what was received is never sent on
    assert atlas.eval(f"{SH}.stats.got") == 1


def test_one_sender_cannot_flood(atlas):
    for i in range(15):
        atlas.execute('MockFire("CHAT_MSG_ADDON", "HHATL", "1;vc;Cookie;%d", "GUILD", "Spammer")' % (5000 + i))
    assert len(list(atlas.eval(f'{S}.db().loot.vc.Cookie').keys())) == 10
    atlas.execute('MockFire("CHAT_MSG_ADDON", "HHATL", "1;vc;Cookie;6000", "GUILD", "Someone Else")')
    assert atlas.eval(f'{S}.db().loot.vc.Cookie[6000]') is not None                # the cap is per sender
    atlas.execute('MockAdvance(11); MockFire("CHAT_MSG_ADDON", "HHATL", "1;vc;Cookie;5014", "GUILD", "Spammer")')
    assert atlas.eval(f'{S}.db().loot.vc.Cookie[5014]') is not None                # and lifts after the window


def test_my_own_sends_are_capped_too(atlas):
    for i in range(14):
        atlas.execute(f'{SH}.Send("vc", "Cookie", {7000 + i})')
    assert len(vals(atlas.eval("SENT"))) == 20 and atlas.eval(f"{SH}.stats.dropped") == 4      # 10 drops x 2 channels


def test_a_client_that_refuses_the_message_is_counted_not_raised(atlas):
    atlas.execute("REFUSE = true")
    assert atlas.eval(f'{SH}.Send("vc", "Cookie", 1001)') == 0
    assert atlas.eval(f"{SH}.stats.refused") == 2 and errors(atlas) == []


def test_secret_message_or_sender_is_dropped(atlas):
    atlas.execute("MockSetSecrets(true)")
    atlas.execute('MockFire("CHAT_MSG_ADDON", "HHATL", MockSecret("1;vc;Cookie;1001"), "PARTY", "Thrall")')
    atlas.execute('MockFire("CHAT_MSG_ADDON", "HHATL", "1;vc;Cookie;1001", "PARTY", MockSecret("Thrall"))')
    atlas.execute('MockFire("CHAT_MSG_ADDON", MockSecret("HHATL"), "1;vc;Cookie;1001", "PARTY", "Thrall")')
    assert atlas.eval(f'{S}.db().loot.vc') is None and errors(atlas) == []


def test_no_addon_message_functions_means_sharing_is_off_and_says_why(lua):
    boot(lua, extra="C_ChatInfo = nil")                                             # no addon-message API at all
    assert lua.eval(f"{SH}.ready") is None
    assert lua.eval(f'{SH}.Send("vc", "Cookie", 1001)') == 0
    assert "off (this client has no addon-message functions)" in lua.eval(f"{SH}.Report()")
    assert errors(lua) == []
