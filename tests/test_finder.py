# Finder (HogTronUI/Core/Finder.lua): /hh find tank invites the first single player the Group Finder list shows for
# our own listing, or who whispers the role - one invite at a time.
# Sean 2026-11-14: "We're having trouble finding a tank ... auto-invite a tank when they look at the list?"
# The fake below is shaped like Forever's C_LFGList / C_PartyInfo (Blizzard_LFGVanilla_Browse.lua + the API docs):
# Search(category, filter, preferredFilters, language, crossFaction, advancedFilter, activityIDs), a listing's
# numMembers / leaderName / activityIDs / isDelisted / hasSelf / age, a player's lfgRoles { tank, healer, dps }.
GAME = '''
LFG = { order = {}, rows = {}, searches = {}, invites = {}, entry = { activityIDs = { 801 } } }
C_LFGList = {
  GetFilteredSearchResults = function() return #LFG.order, LFG.order end,
  GetSearchResultInfo = function(id) local r = LFG.rows[id] return r and r.info or nil end,
  GetSearchResultPlayerInfo = function(id, i) local r = LFG.rows[id] return r and i == 1 and r.player or nil end,
  GetSearchResultLeaderInfo = function(id) local r = LFG.rows[id] return r and r.player or nil end,
  GetSearchResultMemberCounts = function(id) local r = LFG.rows[id] return r and r.counts or nil end,
  GetActiveEntryInfo = function() return LFG.entry end,
  GetActivityInfoTable = function(id) return { categoryID = 2, fullName = "Dungeon " .. id } end,
  Search = function(...)
    if LFG.searchError then error(LFG.searchError, 0) end
    LFG.searches[#LFG.searches + 1] = { n = select("#", ...), ... }
  end,
}
C_PartyInfo = { InviteUnit = function(name)
  if name == LFG.refuse then error("no such player", 0) end
  LFG.invites[#LFG.invites + 1] = name
end }
ERR_INVITE_PLAYER_S = "You have invited %s to join your group."
ERR_JOINED_GROUP_S = "%s joins the party."
ERR_DECLINE_GROUP_S = "%s declines your group invitation."
ERR_ALREADY_IN_GROUP_S = "%s is already in a group."
ERR_GROUP_FULL = "Your party is full."
ERR_NOT_LEADER = "You are not the party leader."
ERR_INVITE_PARTY_BUSY = "Cannot invite additional players until the party is formed"
function Listing(id, name, roles, age, acts, members)
  LFG.order[#LFG.order + 1] = id
  LFG.rows[id] = {
    info = { searchResultID = id, leaderName = name, numMembers = members or 1, isDelisted = false, hasSelf = false,
             age = age or 60, activityIDs = acts or { 801 } },
    player = { name = name, level = 30, className = "Warrior", classFilename = "WARRIOR",
               lfgRoles = roles or { tank = true, healer = false, dps = false } },
  }
  return LFG.rows[id]
end
function Chat() return table.concat(MockLog.chat or {}, string.char(10)) end
'''


def boot(lua, extra=""):
    lua.execute(GAME + extra)
    lua.load_addon("HogTronUI")
    lua.player_login()
    lua.execute("wipe(HogHeals.errors); MockLog.chat = {}")
    return lua


def find(lua, words="tank"):
    lua.execute(f'HogHeals:SlashCommand("find {words}")')


def errors(lua):
    return [e["msg"] for e in lua.eval("HogHeals.errors").values()]


def invites(lua):
    return list(lua.eval("LFG.invites").values())


def chat(lua):
    return lua.eval("Chat()")


def hunting(lua):
    return lua.eval("HogHeals.Finder.hunt ~= nil")


# ---------------------------------------------------------------- the list
def test_a_single_player_offering_to_tank_our_dungeon_is_invited_at_once(lua):
    boot(lua)
    lua.execute('Listing(11, "Brakka Ironhide")')
    find(lua)
    assert invites(lua) == ["Brakka Ironhide"]                               # the name exactly as the list gave it
    s = lua.eval("LFG.searches[1]")                                        # the window's own refresh call, our activities
    assert s["n"] == 7 and s[1] == 2 and s[2] == 0 and s[3] == 0 and s[4] is None and s[5] is False and s[6] is None
    assert list(s[7].values()) == [801]
    assert "invited Brakka Ironhide (tank, level 30, Warrior) from the Group Finder list." in chat(lua)
    assert "hunting a tank" in chat(lua) and 'anyone who whispers "tank"' in chat(lua)
    assert errors(lua) == []


def test_groups_delisted_own_other_dungeons_and_other_roles_are_left_alone(lua):
    boot(lua)
    lua.execute('''
      Listing(1, "A Group", nil, 5, nil, 4)                                 -- a group: the list offers no invite for it
      Listing(2, "Gone Tank").info.isDelisted = true
      Listing(3, "Our Own Listing").info.hasSelf = true
      Listing(4, "Other Dungeon", nil, 5, { 999 })
      Listing(5, "Just Dps", { tank = false, healer = false, dps = true })
    ''')
    find(lua)
    lua.fire("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    assert invites(lua) == []
    assert "list: 5 listings, 2 single players, no tank for your dungeon among them. It only changes when refreshed: /hh find again." in chat(lua)
    assert errors(lua) == []


def test_one_invite_at_a_time_newest_listing_first_and_a_decline_moves_on(lua):
    boot(lua)
    lua.execute('Listing(1, "Old Tank", nil, 900); Listing(2, "New Tank", nil, 20); Listing(3, "Mid Tank", nil, 300)')
    find(lua)
    assert invites(lua) == ["New Tank"]                                    # just listed = still free, at the keyboard
    lua.fire("CHAT_MSG_SYSTEM", "You have invited New Tank to join your group.")
    lua.fire("CHAT_MSG_SYSTEM", "Somebody Else declines your group invitation.")   # not the one we wait on
    lua.fire("LFG_LIST_SEARCH_RESULTS_RECEIVED")                           # nor does a refresh jump the line
    assert invites(lua) == ["New Tank"]
    lua.fire("CHAT_MSG_SYSTEM", "New Tank declines your group invitation.")
    assert invites(lua) == ["New Tank", "Mid Tank"]
    assert "New Tank declined - next." in chat(lua)
    lua.fire("CHAT_MSG_SYSTEM", "Mid Tank is already in a group.")
    lua.fire("CHAT_MSG_SYSTEM", "Old Tank declines your group invitation.")
    assert invites(lua) == ["New Tank", "Mid Tank", "Old Tank"]
    lua.fire("LFG_LIST_SEARCH_RESULTS_RECEIVED")                           # all three stay on the list: nobody is asked twice
    assert invites(lua) == ["New Tank", "Mid Tank", "Old Tank"]
    assert "list: 3 single players offer to tank your dungeon, all asked already." in chat(lua)
    assert errors(lua) == []


def test_no_answer_in_time_moves_on(lua):
    boot(lua)
    lua.execute('Listing(1, "Afk Tank", nil, 10); Listing(2, "Next Tank", nil, 20)')
    find(lua)
    lua.execute("MockAdvance(44)")
    assert invites(lua) == ["Afk Tank"]
    lua.execute("MockAdvance(2)")
    assert invites(lua) == ["Afk Tank", "Next Tank"]
    assert "no answer from Afk Tank in 45 seconds - next." in chat(lua)


def test_a_listing_that_left_the_list_before_its_turn_is_skipped(lua):
    boot(lua)
    lua.execute('Listing(1, "First Tank", nil, 10); Listing(2, "Second Tank", nil, 20); Listing(3, "Third Tank", nil, 30)')
    find(lua)
    lua.execute("LFG.rows[2].info.isDelisted = true")                      # someone else got him meanwhile
    lua.fire("CHAT_MSG_SYSTEM", "First Tank declines your group invitation.")
    assert invites(lua) == ["First Tank", "Third Tank"]


def test_an_invite_the_game_throws_on_is_said_and_the_next_player_is_asked(lua):
    boot(lua, extra='LFG.refuse = "Bad Name"')
    lua.execute('Listing(1, "Bad Name", nil, 10); Listing(2, "Good Tank", nil, 20)')
    find(lua)
    assert invites(lua) == ["Good Tank"]
    assert "the game refused the invite to Bad Name: no such player" in chat(lua)
    assert errors(lua) == []


def test_classic_style_flags_and_the_member_count_fallback(lua):
    boot(lua)
    lua.execute('''
      Listing(1, "One Flag", { tank = 1 }, 10)                              -- Classic-family clients answer 1 / nil
      local counted = Listing(2, "Count Only", nil, 20)
      counted.player.lfgRoles = nil; counted.counts = { LEADER_ROLE_TANK = true, LEADER_ROLE_HEALER = false }
      local no = Listing(3, "Count No", nil, 30)
      no.player.lfgRoles = nil; no.counts = { LEADER_ROLE_TANK = false, LEADER_ROLE_DAMAGER = true }
    ''')
    find(lua)
    lua.fire("CHAT_MSG_SYSTEM", "One Flag declines your group invitation.")
    lua.fire("CHAT_MSG_SYSTEM", "Count Only declines your group invitation.")
    assert invites(lua) == ["One Flag", "Count Only"]


def test_healer_and_damage_hunts_read_their_own_flag_and_switching_starts_over(lua):
    boot(lua)
    lua.execute('''
      Listing(1, "Holy Hannah", { tank = false, healer = true, dps = false })
      Listing(2, "Stabby", { tank = false, healer = false, dps = true })
    ''')
    find(lua, "healer")
    assert invites(lua) == ["Holy Hannah"]
    lua.fire("CHAT_MSG_WHISPER", "dps lf group", "Pew Pew")                # a healer hunt: dps is not its word
    find(lua, "dps")
    assert invites(lua) == ["Holy Hannah", "Stabby"]
    assert lua.eval("HogHeals.Finder.hunt.role") == "dps"
    assert "hunting a damage dealer" in chat(lua)


# ---------------------------------------------------------------- how a hunt ends
def test_the_hunt_ends_when_the_invited_player_joins_and_then_nothing_listens(lua):
    boot(lua)
    lua.execute('Listing(1, "Brakka Ironhide", nil, 10); Listing(2, "Spare Tank", nil, 500)')
    find(lua)
    lua.fire("CHAT_MSG_SYSTEM", "Brakka Ironhide joins the party.")
    assert not hunting(lua)
    assert "Brakka Ironhide joined - you have your tank. Hunt over." in chat(lua)
    lua.fire("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    lua.fire("CHAT_MSG_WHISPER", "tank here", "Late Larry")
    lua.execute("MockAdvance(120)")
    assert invites(lua) == ["Brakka Ironhide"]
    assert errors(lua) == []


def test_a_late_yes_from_an_earlier_invite_ends_it_too(lua):
    boot(lua)
    lua.execute('Listing(1, "Slow Tank", nil, 10); Listing(2, "Next Tank", nil, 20)')
    find(lua)
    lua.execute("MockAdvance(46)")                                         # moved on to Next Tank
    lua.fire("CHAT_MSG_SYSTEM", "Slow Tank joins the party.")
    assert not hunting(lua) and "Slow Tank joined - you have your tank." in chat(lua)


def test_the_roster_shows_the_join_by_full_name_only(lua):
    boot(lua)
    lua.execute('''
      Listing(1, "Brakka Ironhide")
      UnitName = function(u) local m = MockUnits[u] if m then return m.name, m.surname end end   -- Forever: the surname is the 2nd value
    ''')
    find(lua)
    lua.execute('MockSetGroup(2); MockUnits.player.leader = true; MockUnits.party1 = { name = "Brakka", surname = "Redmane", class = "MAGE" }')
    lua.fire("GROUP_ROSTER_UPDATE")
    assert hunting(lua)                                                    # another Brakka: not the one we invited
    lua.execute('MockSetGroup(3); MockUnits.party2 = { name = "Brakka", surname = "Ironhide", class = "WARRIOR" }')
    lua.fire("GROUP_ROSTER_UPDATE")
    assert not hunting(lua) and "Brakka Ironhide joined" in chat(lua)


def test_only_the_leader_may_hunt_and_a_full_party_is_refused(lua):
    boot(lua)
    lua.execute('Listing(1, "Brakka Ironhide"); MockSetGroup(3)')            # in a party, someone else leads
    find(lua)
    assert not hunting(lua) and invites(lua) == []
    assert "only the group leader can invite" in chat(lua)
    lua.execute("MockUnits.player.leader = true; MockSetGroup(5)")
    find(lua)
    assert not hunting(lua) and "your group is full." in chat(lua)
    lua.execute("MockSetGroup(4)")
    find(lua)
    assert invites(lua) == ["Brakka Ironhide"]


def test_losing_lead_or_a_full_party_ends_the_hunt(lua):
    boot(lua)
    find(lua)
    assert hunting(lua)
    lua.execute("MockSetGroup(3)")                                         # joined someone else's group
    lua.fire("GROUP_ROSTER_UPDATE")
    assert not hunting(lua) and "you are not the group leader any more" in chat(lua)
    lua.execute("MockSetGroup(1)")
    find(lua)
    lua.fire("CHAT_MSG_SYSTEM", "Your party is full.")
    assert not hunting(lua) and "your group is full - hunt over." in chat(lua)


def test_a_hunt_stops_after_its_invites_or_its_minutes(lua):
    boot(lua)
    lua.execute("HogHeals.db.profile.finder.maxInvites = 2")
    lua.execute('Listing(1, "T One", nil, 1); Listing(2, "T Two", nil, 2); Listing(3, "T Three", nil, 3)')
    find(lua)
    lua.fire("CHAT_MSG_SYSTEM", "T One declines your group invitation.")
    lua.fire("CHAT_MSG_SYSTEM", "T Two declines your group invitation.")
    assert invites(lua) == ["T One", "T Two"] and not hunting(lua)
    assert "2 invites and nobody joined - stopped. /hh find tank starts again." in chat(lua)
    lua.execute("LFG.order = {}; LFG.rows = {}")
    find(lua)
    lua.execute("MockAdvance(1801)")
    assert not hunting(lua) and "30 minutes without a tank - stopped." in chat(lua)


def test_the_party_still_forming_line_puts_the_player_back_in_front(lua):
    boot(lua)
    lua.execute('Listing(1, "Brakka Ironhide")')
    find(lua)
    lua.fire("CHAT_MSG_SYSTEM", "Cannot invite additional players until the party is formed")
    assert lua.eval("HogHeals.Finder.hunt.pending") is None
    lua.execute("MockAdvance(2)")
    assert invites(lua) == ["Brakka Ironhide"]                               # held a moment
    lua.execute("MockAdvance(2)")
    assert invites(lua) == ["Brakka Ironhide", "Brakka Ironhide"]              # then asked again
    lua.fire("CHAT_MSG_SYSTEM", "You have invited Brakka Ironhide to join your group.")
    lua.fire("CHAT_MSG_SYSTEM", "Cannot invite additional players until the party is formed")   # about someone else now
    assert lua.eval("HogHeals.Finder.hunt.pending.name") == "Brakka Ironhide"


# ---------------------------------------------------------------- whispers
def test_a_whisper_naming_the_role_is_invited_ahead_of_the_list(lua):
    boot(lua)
    lua.execute('Listing(1, "List Tank One", nil, 10); Listing(2, "List Tank Two", nil, 20)')
    find(lua)                                                              # List Tank One is being waited on
    lua.fire("CHAT_MSG_WHISPER", "hey got room?", "Curious Carl")          # names no role
    lua.fire("CHAT_MSG_WHISPER", "TANK here, inv", "Bruno Stonefist")
    assert invites(lua) == ["List Tank One"]                               # still one at a time
    lua.fire("CHAT_MSG_SYSTEM", "List Tank One declines your group invitation.")
    assert invites(lua) == ["List Tank One", "Bruno Stonefist"]
    assert 'invited Bruno Stonefist (tank) who whispered "TANK here, inv".' in chat(lua)
    assert errors(lua) == []


def test_whispers_can_be_switched_off_and_nothing_listens_without_a_hunt(lua):
    boot(lua)
    lua.fire("CHAT_MSG_WHISPER", "tank here", "Bruno Stonefist")           # no hunt running
    assert invites(lua) == []
    lua.execute("HogHeals.db.profile.finder.whisper = false")
    find(lua)
    lua.fire("CHAT_MSG_WHISPER", "tank here", "Bruno Stonefist")
    assert invites(lua) == [] and "whispers" not in chat(lua)


def test_a_volunteer_is_invited_twice_at_most(lua):
    boot(lua)
    find(lua)
    for _ in range(4):
        lua.fire("CHAT_MSG_WHISPER", "tank", "Bruno Stonefist")
        lua.fire("CHAT_MSG_SYSTEM", "Bruno Stonefist declines your group invitation.")
    assert invites(lua) == ["Bruno Stonefist", "Bruno Stonefist"]


def test_without_a_listing_of_our_own_only_whispers_count(lua):
    boot(lua, extra="LFG.entry = nil")
    lua.execute('Listing(1, "Any Tank")')                                  # could be listed for any dungeon
    find(lua)
    lua.fire("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    assert invites(lua) == [] and lua.eval("#LFG.searches") == 0
    assert "you have no group listing" in chat(lua)
    lua.fire("CHAT_MSG_WHISPER", "i can tank", "Bruno Stonefist")
    assert invites(lua) == ["Bruno Stonefist"]


# ---------------------------------------------------------------- what the client may refuse or hide
def test_hidden_values_are_counted_and_skipped_never_compared(lua):
    boot(lua)
    lua.execute('''
      MockSetSecrets(true)
      Listing(1, "Hidden Count").info.numMembers = MockSecret(1)
      Listing(2, "Hidden Role").player.lfgRoles = { tank = MockSecret(true), healer = false, dps = false }
      local r = Listing(3, "x"); r.info.leaderName = MockSecret("Hidden Name"); r.player.name = MockSecret("Hidden Name")
    ''')
    find(lua)
    lua.fire("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    lua.execute('MockFire("CHAT_MSG_WHISPER", MockSecret("tank here"), MockSecret("Hidden Harry")); MockFire("CHAT_MSG_SYSTEM", MockSecret("x joins the party."))')
    assert invites(lua) == [] and errors(lua) == []
    assert lua.eval("HogHeals.Finder.hunt.seen.hidden") == 3
    assert "the game is hiding the Group Finder list from addons right now." in chat(lua)


def test_a_search_the_game_throws_on_is_said_and_the_hunt_goes_on(lua):
    boot(lua, extra='LFG.searchError = "Search requires a hardware event"')
    lua.execute('Listing(1, "Brakka Ironhide")')
    find(lua)
    assert "could not refresh the list myself (Search requires a hardware event). Press the list's own refresh button" in chat(lua)
    assert invites(lua) == ["Brakka Ironhide"] and errors(lua) == []         # the list it already held still counts


def test_a_forbidden_search_is_remembered_for_the_game_build(lua):
    boot(lua)
    find(lua)
    lua.fire("ADDON_ACTION_BLOCKED", "HogTron_Bars", "HogUIStanceBar:Show()")   # someone else's trouble
    assert lua.eval("HogHeals.db.global.finderNoSearch") is None
    lua.fire("ADDON_ACTION_FORBIDDEN", "HogTronUI", "C_LFGList.Search()")
    assert lua.eval("HogHeals.db.global.finderNoSearch.build") == "60000"
    assert "this game build will not let an addon refresh the list" in chat(lua)
    lua.execute('HogHeals:SlashCommand("find off"); MockAdvance(10); MockLog.chat = {}')
    find(lua)
    assert lua.eval("#LFG.searches") == 1                                  # never tried again on this build
    assert "this game build will not let an addon refresh the list" in chat(lua)
    lua.execute('HogHeals.db.global.finderNoSearch.build = "59999"; HogHeals:SlashCommand("find off"); MockAdvance(10)')
    find(lua)
    assert lua.eval("#LFG.searches") == 2                                  # a patched client gets one more try


def test_find_again_refreshes_the_list_but_not_twice_in_a_moment(lua):
    boot(lua)
    find(lua)
    assert lua.eval("#LFG.searches") == 1
    find(lua, "")
    assert lua.eval("#LFG.searches") == 1 and "the list was refreshed a moment ago." in chat(lua)
    lua.execute('MockAdvance(4); Listing(1, "Fresh Tank")')
    find(lua, "")                                                          # nothing after it = refresh while hunting
    assert lua.eval("#LFG.searches") == 2
    assert invites(lua) == ["Fresh Tank"] and "waiting on Fresh Tank, 45 seconds left." in chat(lua)


def test_results_updated_in_bursts_are_read_once_on_the_next_tick(lua):
    boot(lua)
    find(lua)
    lua.execute('Listing(1, "Changed Mind", { tank = false, healer = false, dps = true })')
    lua.fire("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    scans = lua.eval("HogHeals.Finder.hunt.scans")
    lua.execute("LFG.rows[1].player.lfgRoles.tank = true")                 # he ticks the tank box on his listing
    for _ in range(5):
        lua.fire("LFG_LIST_SEARCH_RESULT_UPDATED", 1)
    assert invites(lua) == [] and lua.eval("HogHeals.Finder.hunt.scans") == scans
    lua.execute("MockAdvance(1)")
    assert invites(lua) == ["Changed Mind"] and lua.eval("HogHeals.Finder.hunt.scans") == scans + 1


# ---------------------------------------------------------------- commands, options, diag
def test_off_stops_and_an_unknown_word_gets_the_help(lua):
    boot(lua)
    find(lua, "off")
    assert "not hunting. /hh find tank | healer | dps" in chat(lua)
    find(lua, "bananas")
    assert not hunting(lua)
    find(lua, "")                                                          # nothing after it = a tank
    assert lua.eval("HogHeals.Finder.hunt.role") == "tank"
    find(lua, "off")
    assert not hunting(lua) and "find: stopped." in chat(lua)
    assert errors(lua) == []


def test_the_options_page_starts_stops_and_sets_the_wait(lua):
    boot(lua)
    args = lua.eval("HogHeals.OptionsTable().args.Finder.args")
    assert args["tank"]["type"] == "execute" and args["whisper"]["type"] == "toggle" and args["wait"]["type"] == "range"
    assert lua.eval("HogHeals.OptionsTable().args.Finder.name") == "Group Finder"
    assert lua.eval("HogHeals.OptionsTable().args.Finder.args.wait.get()") == 45
    assert lua.eval("HogHeals.OptionsTable().args.Finder.args.whisper.get()") is True
    assert lua.eval("HogHeals.OptionsTable().args.Finder.args.stop.disabled()") is True
    lua.execute('Listing(1, "Brakka Ironhide")')
    lua.execute("HogHeals.OptionsTable().args.Finder.args.tank.func()")
    assert invites(lua) == ["Brakka Ironhide"]
    assert lua.eval("HogHeals.OptionsTable().args.Finder.args.stop.disabled()") is False
    lua.execute("HogHeals.OptionsTable().args.Finder.args.wait.set(nil, 20); MockAdvance(21)")
    assert "no answer from Brakka Ironhide in 20 seconds - next." in chat(lua)
    lua.execute("HogHeals.OptionsTable().args.Finder.args.stop.func()")
    assert not hunting(lua)


def test_finddiag_says_what_it_saw_and_did_and_keeps_it_on_disk(lua):
    boot(lua)
    lua.execute('Listing(1, "Brakka Ironhide"); Listing(2, "Holy Hannah", { tank = false, healer = true, dps = false })')
    find(lua)
    lua.fire("CHAT_MSG_SYSTEM", "You have invited Brakka Ironhide to join your group.")
    lua.execute('MockLog.chat = {}; HogHeals:SlashCommand("finddiag")')
    assert "find: hunting a tank for 0 seconds, waiting on Brakka Ironhide." in chat(lua)
    lua.fire("CHAT_MSG_SYSTEM", "Brakka Ironhide joins the party.")
    lua.execute('MockLog.chat = {}; HogHeals:SlashCommand("finddiag")')
    out = chat(lua)
    assert "find: off (last hunt: tank, ended: joined)." in out
    assert "list now: 2 listings, 2 single players, 0 hidden by the game. Offering (for your listing): tank 1, healer 1, dps 0." in out
    assert "searches I asked for: 1 (none refused), list answers: 0, whispers that counted: 0." in out
    assert "1. Brakka Ironhide (list): the game confirmed the invite -> joined" in out
    d = lua.eval("HogHeals.db.global.diag.finder")
    assert d["hunts"] == 1 and d["last"]["stopped"] == "joined" and d["last"]["searches"] == 1
    assert d["last"]["invites"][1]["name"] == "Brakka Ironhide"
    assert errors(lua) == []


def test_same_name_ignores_case_and_dash_and_takes_a_bare_first_name(core):
    same = "HogHeals.Finder.SameName"
    assert core.eval(same + '("Brakka Ironhide", "brakka-ironhide")') is True
    assert core.eval(same + '("Brakka", "Brakka Ironhide")') is True
    assert core.eval(same + '("Brakka Ironhide", "Brakka Redmane")') is False
    assert core.eval(same + '("Brak", "Brakka Ironhide")') is False
    assert core.eval(same + '(nil, "Brakka")') is False
    assert core.eval(same + '("", "Brakka")') is False


def test_defaults_and_the_toc_carry_the_finder(core):
    f = core.eval("HogHeals.db.profile.finder")
    assert f["whisper"] is True and f["wait"] == 45 and f["maxInvites"] == 10 and f["minutes"] == 30
    assert core.eval('HogHeals.slash.find ~= nil and HogHeals.slash.finddiag ~= nil')
    assert core.eval('HogHeals.modules.Finder ~= nil')
