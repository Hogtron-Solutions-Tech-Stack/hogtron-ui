# HogUI Atlas: the Store (what is remembered) and Capture (how a drop finds its boss), plus the journal reader.
import pytest

from atlas_helpers import boot, errors, vals

A = "HogHealsAtlas"
S = "HogHealsAtlas.Store"
CAP = "HogHealsAtlas.Capture"


@pytest.fixture
def atlas(lua):
    return boot(lua)


def in_deadmines(lua):
    lua.execute('INST = { name = "The Deadmines", id = 36 }; MockFire("PLAYER_ENTERING_WORLD", false, false)')


def loot(lua, *slots):
    rows = ", ".join("{ link = %s, guid = %s, kind = %d }" % s for s in slots)
    lua.execute("LOOT = { %s }; MockFire('LOOT_OPENED', true)" % rows)


# ------------------------------------------------------------------------------------------------ store
def test_record_counts_pairs_once_and_sightings_every_time(atlas):
    assert atlas.eval(f'{S}.Record("vc", "Cookie", 1001, "seen")') is True
    assert atlas.eval(f'{S}.Record("vc", "Cookie", 1001, "seen")') is False
    assert atlas.eval(f'{S}.db().count') == 1
    assert atlas.eval(f'{S}.db().loot.vc.Cookie[1001].n') == 2
    assert atlas.eval(f'{S}.Record("vc", "Cookie", 0, "seen")') is False          # not an item
    assert atlas.eval(f'{S}.Record("vc", "", 1001, "seen")') is False             # no boss
    assert atlas.eval(f'{S}.Record(nil, "Cookie", 1001, "seen")') is False
    assert atlas.eval(f'{S}.db().count') == 1


def test_a_better_source_replaces_a_weaker_one_never_the_reverse(atlas):
    atlas.execute(f'{S}.Record("vc", "Cookie", 1001, "journal")')
    assert atlas.eval(f'{S}.db().loot.vc.Cookie[1001].src') == "journal" and atlas.eval(f'{S}.db().loot.vc.Cookie[1001].n') == 0
    atlas.execute(f'{S}.Record("vc", "Cookie", 1001, "seen")')
    assert atlas.eval(f'{S}.db().loot.vc.Cookie[1001].src') == "seen" and atlas.eval(f'{S}.db().loot.vc.Cookie[1001].n') == 1
    atlas.execute(f'{S}.Record("vc", "Cookie", 1001, "journal")')
    assert atlas.eval(f'{S}.db().loot.vc.Cookie[1001].src') == "seen"


def test_boss_loot_merges_curated_and_sorts_seen_first(atlas):
    atlas.execute(f"""
      {A}.Data.Curated.vc = {{ Cookie = {{ 1004, 1001 }} }}
      {S}.Record("vc", "Cookie", 1002, "journal")
      {S}.Record("vc", "Cookie", 1001, "seen")
    """)
    rows = vals(atlas.eval(f'{S}.GetBossLoot("vc", "Cookie")'))
    assert [(r["id"], r["src"]) for r in rows] == [(1001, "seen"), (1002, "journal"), (1004, "reported")]   # 1001 not twice
    assert vals(atlas.eval(f'{S}.GetBossLoot("vc", "Nobody")')) == []


def test_source_of_and_its_text(atlas):
    atlas.execute(f'{S}.Record("vc", "Cookie", 1001, "seen"); {S}.Record("wc", "Kresh", 1001, "seen")')
    text = atlas.eval(f'({S}.SourceText(1001))')
    assert text == "Cookie (The Deadmines) +1 more"
    assert atlas.eval(f'{S}.SourceText(9999)') is None
    atlas.execute(f'{S}.Record("vc", "Gilnid", 1002, "seen")')                     # the index follows new records
    assert atlas.eval(f'({S}.SourceText(1002))') == "Gilnid (The Deadmines)"
    assert vals(atlas.eval(f'{S}.AllItems()')) == [1001, 1002]


def test_cap_evicts_the_oldest_pair(atlas):
    atlas.execute(f"""
      {S}.CAP = 3
      local now = {A}.now
      local t = 0
      {A}.now = function() t = t + 1 return ("2026-01-%02d"):format(t) end
      for id = 1, 5 do {S}.Record("vc", "Cookie", id, "seen") end
      {A}.now = now
    """)
    assert atlas.eval(f'{S}.db().count') == 3
    assert sorted(atlas.eval(f'{S}.db().loot.vc.Cookie').keys()) == [3, 4, 5]


def test_boss_rows_keep_kill_order_then_rares_then_found_then_trash(atlas):
    atlas.execute(f"""
      {S}.AddBoss("vc", "Brand New Boss", {{ npc = 99 }})
      {S}.Record("vc", "Brand New Boss", 1001, "seen")
      {S}.Record("vc", {S}.TRASH, 1002, "seen")
      {S}.Record("vc", "Cookie", 1004, "seen")
    """)
    rows = vals(atlas.eval(f'{S}.Bosses("vc")'))
    names = [r["name"] for r in rows]
    assert names[:7] == ["Rhahk'Zor", "Sneed's Shredder", "Gilnid", "Mr. Smite", "Cookie", "Captain Greenskin", "Edwin VanCleef"]
    assert names[7:] == ["Miner Johnson", "Brand New Boss", "Trash and chests"]
    by = {r["name"]: r for r in rows}
    assert by["Cookie"]["items"] == 1 and by["Gilnid"]["items"] == 0
    assert by["Miner Johnson"]["rare"] is True and by["Brand New Boss"]["found"] is True and by["Trash and chests"]["trash"] is True
    assert "Trash and chests" not in [r["name"] for r in vals(atlas.eval(f'{S}.Bosses("wc")'))]   # only when it holds something


def test_unknown_dungeon_gets_a_row_of_its_own(atlas):
    key = atlas.eval(f'{S}.DungeonKey("Crypt of Tomorrow", 4242)')
    assert key == "inst:4242"
    assert atlas.eval(f'{S}.Dungeon("inst:4242").name') == "Crypt of Tomorrow"
    assert [d["name"] for d in vals(atlas.eval(f'{S}.ExtraDungeons()'))] == ["Crypt of Tomorrow"]
    assert atlas.eval(f'{S}.DungeonKey("Ruins of Lordaeron", 2999)') == "lordaeron"
    assert atlas.eval(f'{S}.DungeonKey("Scarlet Monastery", 189, "Herod")') == "sm_arm"
    assert atlas.eval(f'{S}.DungeonKey(nil, nil)') is None


def test_npc_names_are_capped(atlas):
    atlas.execute(f'{S}.NPC_CAP = 2; {S}.LearnNpc(1, "One"); {S}.LearnNpc(2, "Two"); {S}.LearnNpc(3, "Three"); {S}.LearnNpc(1, "Renamed")')
    assert atlas.eval(f'{S}.NpcName(1)') == "One" and atlas.eval(f'{S}.NpcName(3)') is None


# ------------------------------------------------------------------------------------------------ capture
def test_npc_id_from_the_guid_shape_measured_on_forever(atlas):
    assert atlas.eval(f'{CAP}.NpcFromGUID("Creature-0-4615-0-2065-1530-000039B0DA")') == 1530
    assert atlas.eval(f'{CAP}.NpcFromGUID("Player-4615-00A1B2C3")') is None
    assert atlas.eval(f'{CAP}.NpcFromGUID(nil)') is None


def test_nothing_is_recorded_outside_an_instance(atlas):
    loot(atlas, ("ItemLink(1001)", "NpcGUID(645)", 1))
    assert atlas.eval(f'{S}.db().count') == 0
    assert atlas.eval(f'{CAP}.skipped["outside an instance"]') == 1
    assert atlas.eval(f'#{S}.db().runs') == 0


def test_boss_drop_is_filed_under_the_boss_whose_corpse_it_is(atlas):
    in_deadmines(atlas)
    atlas.execute('MockUnits.target = { name = "Cookie", guid = NpcGUID(645), health = 1, maxHealth = 1, isPlayer = false }; MockFire("PLAYER_TARGET_CHANGED")')
    assert atlas.eval(f'{S}.NpcName(645)') == "Cookie"
    loot(atlas, ("ItemLink(1001)", "NpcGUID(645)", 1), ("ItemLink(1010)", "NpcGUID(645)", 1), ("nil", "NpcGUID(645)", 2))
    assert vals(atlas.eval(f'{S}.GetBossLoot("vc", "Cookie")'))[0]["id"] == 1001
    assert atlas.eval(f'{S}.db().count') == 1                                       # the grey and the coin are not loot
    assert atlas.eval(f'{CAP}.skipped["below quality"]') == 1
    assert atlas.eval(f'{S}.db().bosses.vc.Cookie.npc') == 645
    assert errors(atlas) == []


def test_reopening_the_same_corpse_counts_once(atlas):
    in_deadmines(atlas)
    atlas.execute('MockUnits.target = { name = "Cookie", guid = NpcGUID(645), health = 1, maxHealth = 1, isPlayer = false }; MockFire("PLAYER_TARGET_CHANGED")')
    for _ in range(3):                                                              # LOOT_READY / LOOT_OPENED doubles, measured
        loot(atlas, ("ItemLink(1001)", "NpcGUID(645)", 1))
    assert atlas.eval(f'{S}.db().loot.vc.Cookie[1001].n') == 1
    assert atlas.eval(f'#{S}.db().runs[1].drops') == 1
    loot(atlas, ("ItemLink(1001)", "NpcGUID(645, 2)", 1))                           # another Cookie, another run's corpse
    assert atlas.eval(f'{S}.db().loot.vc.Cookie[1001].n') == 2


def test_encounter_end_names_the_boss_for_thirty_seconds(atlas):
    atlas.execute('INST = { name = "Ruins of Lordaeron", id = 2999 }; MockFire("PLAYER_ENTERING_WORLD", false, false)')
    atlas.execute('MockFire("ENCOUNTER_END", 3001, "The Abandoned", 1, 5, 1)')
    loot(atlas, ("ItemLink(1004)", "NpcGUID(77001)", 1))                            # corpse never targeted: no name for it
    assert [r["id"] for r in vals(atlas.eval(f'{S}.GetBossLoot("lordaeron", "The Abandoned")'))] == [1004]
    assert atlas.eval(f'{S}.db().bosses.lordaeron["The Abandoned"].enc') == 3001
    atlas.execute("MockAdvance(31)")
    loot(atlas, ("ItemLink(1001)", "NpcGUID(77002)", 1))
    assert [r["id"] for r in vals(atlas.eval(f'{S}.GetBossLoot("lordaeron", "Trash and chests")'))] == [1001]
    names = [r["name"] for r in vals(atlas.eval(f'{S}.Bosses("lordaeron")'))]
    assert names == ["The Abandoned", "Trash and chests"]                           # the new dungeon fills from play


def test_a_wipe_does_not_name_a_boss(atlas):
    in_deadmines(atlas)
    atlas.execute('MockFire("ENCOUNTER_END", 1, "Edwin VanCleef", 1, 5, 0)')
    assert atlas.eval(f'{CAP}.lastBoss') is None


def test_secret_link_is_skipped_and_counted_never_compared(atlas):
    in_deadmines(atlas)
    atlas.execute('MockSetSecrets(true)')
    loot(atlas, ('MockSecret(ItemLink(1001))', "NpcGUID(645)", 1))
    assert atlas.eval(f'{S}.db().count') == 0
    assert atlas.eval(f'{CAP}.skipped["secret link"]') == 1
    assert errors(atlas) == []


def test_group_loot_roll_and_other_players_chat(atlas):
    in_deadmines(atlas)
    atlas.execute('MockFire("ENCOUNTER_END", 1, "Mr. Smite", 1, 5, 1)')
    atlas.execute('ROLLS = { [7] = ItemLink(1001) }; MockFire("START_LOOT_ROLL", 7, 60000)')
    assert [r["id"] for r in vals(atlas.eval(f'{S}.GetBossLoot("vc", "Mr. Smite")'))] == [1001]
    atlas.execute('MockFire("CHAT_MSG_LOOT", "Thrall receives loot: " .. ItemLink(1001) .. ".", "Thrall")')     # same drop, said again
    assert atlas.eval(f'{S}.db().loot.vc["Mr. Smite"][1001].n') == 1
    atlas.execute('MockAdvance(16); MockFire("CHAT_MSG_LOOT", "Thrall receives loot: " .. ItemLink(1004) .. ".", "Thrall")')
    assert atlas.eval(f'{S}.db().loot.vc["Mr. Smite"][1004].src') == "group"
    atlas.execute('MockFire("CHAT_MSG_LOOT", "You receive loot: " .. ItemLink(1008) .. ".", "Hog")')            # mine: loot window covers it
    assert atlas.eval(f'{S}.db().loot.vc["Mr. Smite"][1008]') is None
    drops = vals(atlas.eval(f'{S}.db().runs[1].drops'))
    assert [(d["id"], d["who"]) for d in drops] == [(1001, "roll:7"), (1004, "Thrall")]


def test_run_log_opens_on_entry_closes_on_exit_and_drops_empty_runs(atlas):
    in_deadmines(atlas)
    assert atlas.eval(f'{S}.db().runs[1].open') is True
    atlas.execute('INST = nil; MockFire("ZONE_CHANGED_NEW_AREA")')
    assert atlas.eval(f'#{S}.db().runs') == 0                                       # nothing dropped: not kept
    in_deadmines(atlas)
    atlas.execute('MockFire("ENCOUNTER_END", 1, "Gilnid", 1, 5, 1)')
    loot(atlas, ("ItemLink(1001)", "NpcGUID(1763)", 1))
    atlas.execute('INST = nil; MockFire("ZONE_CHANGED_NEW_AREA")')
    assert atlas.eval(f'#{S}.db().runs') == 1 and atlas.eval(f'{S}.db().runs[1].open') is None
    assert atlas.eval(f'{S}.db().runs[1].name') == "The Deadmines"
    atlas.execute(f'{CAP}.RUN_CAP = 2')
    for i in range(4):
        atlas.execute('INST = { name = "Run %d", id = %d }; MockFire("PLAYER_ENTERING_WORLD")' % (i, 5000 + i))
        atlas.execute('MockFire("ENCOUNTER_END", 1, "Boss", 1, 5, 1)')
        loot(atlas, ("ItemLink(1001)", "NpcGUID(%d)" % (9000 + i), 1))
    assert atlas.eval(f'#{S}.db().runs') == 2


def test_wishlist_item_dropping_prints_one_line(atlas):
    in_deadmines(atlas)
    atlas.execute(f'{A}.Gear.ToggleWish(1001); MockLog.chat = {{}}; MockFire("ENCOUNTER_END", 1, "Cookie", 1, 5, 1)')
    loot(atlas, ("ItemLink(1001)", "NpcGUID(645)", 1), ("ItemLink(1004)", "NpcGUID(645)", 1))
    chat = [c for c in vals(atlas.eval("MockLog.chat")) if "Wishlist" in c]
    assert len(chat) == 1 and "Seer's Cowl" in chat[0] and "Cookie" in chat[0]
    atlas.execute(f'{A}.cfg().wishAlerts = false; MockLog.chat = {{}}')
    loot(atlas, ("ItemLink(1001)", "NpcGUID(645, 3)", 1))
    assert [c for c in vals(atlas.eval("MockLog.chat")) if "Wishlist" in c] == []


def test_recording_can_be_switched_off(atlas):
    in_deadmines(atlas)
    atlas.execute(f'{A}.cfg().enabled = false; MockFire("ENCOUNTER_END", 1, "Cookie", 1, 5, 1)')
    loot(atlas, ("ItemLink(1001)", "NpcGUID(645)", 1))
    assert atlas.eval(f'{S}.db().count') == 0


def test_combat_log_is_never_registered(atlas):
    # a FORBIDDEN action on this client (the popup with the Disable button)
    assert atlas.eval(f'{CAP}.frame:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED")') is False


# ------------------------------------------------------------------------------------------------ journal
JOURNAL = r'''
EJ = {
  { id = 63, name = "The Deadmines", bosses = { { "Cookie", 2001, { 1001, 1004 } }, { "Edwin VanCleef", 2002, { 1008 } } } },
  { id = 900, name = "Ruins of Lordaeron", bosses = { { "The Abandoned", 2101, { 1007 } } } },
  { id = 901, name = "Hall of Nowhere", bosses = { { "Warden Null", 2201, { 1002 } } } },
}
local cur, enc
function EJ_GetNumTiers() return 1 end
function EJ_SelectTier() end
function EJ_GetInstanceByIndex(i, raid) if raid then return nil end local e = EJ[i] if e then return e.id, e.name end end
function EJ_SelectInstance(id) for _, e in ipairs(EJ) do if e.id == id then cur = e end end enc = nil end
function EJ_GetEncounterInfoByIndex(i) local b = cur and cur.bosses[i] if b then return b[1], "desc", b[2] end end
function EJ_SelectEncounter(id) enc = nil for _, b in ipairs(cur and cur.bosses or {}) do if b[2] == id then enc = b end end end
function EJ_GetNumLoot() return enc and #enc[3] or 0 end
C_EncounterJournal = { GetLootInfoByIndex = function(i) local id = enc and enc[3][i] if id then return { itemID = id, encounterID = enc[2] } end end }
'''


def test_journal_absent_says_so_and_changes_nothing(atlas):
    r = atlas.eval(f'{A}.Journal.Scan("test")')
    assert r["status"] == "no journal functions on this client"
    assert atlas.eval(f'{S}.db().count') == 0
    assert atlas.eval('HogHeals.db.global.diag.atlasJournal.status') == "no journal functions on this client"


def test_journal_fills_known_new_and_unlisted_dungeons(lua):
    boot(lua, extra=JOURNAL)
    lua.execute("MockAdvance(7)")                                                   # the login scan
    assert lua.eval(f'{A}.Journal.last.status') == "ok"
    assert lua.eval(f'{A}.Journal.last.instances') == 3 and lua.eval(f'{A}.Journal.last.items') == 5
    assert [(r["id"], r["src"]) for r in vals(lua.eval(f'{S}.GetBossLoot("vc", "Cookie")'))] == [(1001, "journal"), (1004, "journal")]
    assert [r["name"] for r in vals(lua.eval(f'{S}.Bosses("lordaeron")'))] == ["The Abandoned"]
    key = "name:hall of nowhere"
    assert lua.eval(f'{S}.Dungeon("{key}").name') == "Hall of Nowhere"
    assert [r["id"] for r in vals(lua.eval(f'{S}.GetBossLoot("{key}", "Warden Null")'))] == [1002]
    assert lua.eval(f'({S}.SourceText(1007))') == "The Abandoned (Ruins of Lordaeron)"
    assert lua.eval('HogHeals.db.global.diag.atlasJournal.bosses') == 4
    again = lua.eval(f'{A}.Journal.Scan("again")')
    assert again["items"] == 0 and lua.eval(f'{S}.db().count') == 5               # a rescan adds nothing twice
    assert errors(lua) == []


def test_journal_never_scans_in_combat_or_with_its_window_open(lua):
    boot(lua, extra=JOURNAL)
    lua.execute("MockState.inCombat = true")
    assert lua.eval(f'{A}.Journal.Scan("t").status') == "in combat, not scanned"
    lua.execute('MockState.inCombat = false; EncounterJournal = CreateFrame("Frame", nil, UIParent); EncounterJournal:Show()')
    assert lua.eval(f'{A}.Journal.Scan("t").status') == "journal window open, not scanned"
    assert lua.eval(f'{S}.db().count') == 0


def test_a_journal_that_throws_is_reported_not_raised(lua):
    boot(lua, extra=JOURNAL + 'function EJ_GetEncounterInfoByIndex() error("journal boom") end')
    r = lua.eval(f'{A}.Journal.Scan("t")')
    assert r["status"] == "ok" and r["bosses"] == 0                               # the call is guarded: no boss, no crash
    assert errors(lua) == []


def test_late_loot_data_rescans_a_bounded_number_of_times(lua):
    boot(lua, extra=JOURNAL)
    lua.execute("MockAdvance(7)")
    lua.execute(f'SCANS = 0; local s = {A}.Journal.Scan; {A}.Journal.Scan = function(...) SCANS = SCANS + 1 return s(...) end')
    for _ in range(10):
        lua.execute('MockFire("EJ_LOOT_DATA_RECIEVED", 1001); MockAdvance(3)')
    assert lua.eval("SCANS") == 3


def test_a_journal_listing_hundreds_of_instances_stops_at_its_caps(lua):
    boot(lua, extra=JOURNAL + """
      EJ = {}
      for i = 1, 150 do EJ[i] = { id = 1000 + i, name = "Instance " .. i, bosses = { { "Boss " .. i, 5000 + i, { 1001 } } } } end
    """)
    lua.execute(f"{A}.Journal.MAX_INSTANCES = 40")
    r = lua.eval(f'{A}.Journal.Scan("t")')
    assert r["instances"] == 40 and r["status"].startswith("stopped early (instance cap)")
    assert len(vals(lua.eval(f"{S}.ExtraDungeons()"))) == 40
    r = lua.eval(f'{A}.Journal.Scan("again")')                                       # carries on where it stopped
    assert r["instances"] == 40 and len(vals(lua.eval(f"{S}.ExtraDungeons()"))) == 60   # the dungeon cap holds
    lua.execute(f"{A}.Journal.Scan('more'); {A}.Journal.Scan('more')")
    assert len(vals(lua.eval(f"{S}.ExtraDungeons()"))) == 60
    assert lua.eval(f'{A}.Journal.Scan("last").status') == "ok"                      # everything listed was read
    assert errors(lua) == []


def test_a_slow_journal_stops_on_its_time_budget(lua):
    boot(lua, extra=JOURNAL + """
      NOW = 0
      function debugprofilestop() NOW = NOW + 50 return NOW end                      -- every look at the clock costs 50 ms
    """)
    r = lua.eval(f'{A}.Journal.Scan("t")')
    assert r["status"].startswith("stopped early (time budget)") and 1 <= r["instances"] < 3
    assert lua.eval("HogHeals.db.global.diag.atlasJournal.listed") >= 1
    assert lua.eval(f"{S}.db().journalBuild") is None                               # not marked as done
