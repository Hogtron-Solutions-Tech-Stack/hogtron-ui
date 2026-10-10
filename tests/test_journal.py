# Journal (HogHeals_Journal): a healer's dungeon journal. Shipped pages, where-am-I, auto-open once per session,
# the probe of the client's Encounter Journal, the party summary (default off), and the window's two panes.
import pytest

J = "HogHealsJournal"

CLIENT = r'''
INST = nil
function GetInstanceInfo()
  if not INST then return "Kalimdor", "none", 0, "", 0, 0, false, 1 end
  return INST.name, INST.kind or "party", 1, "Normal", 5, 0, false, INST.id
end
function IsInInstance() if INST then return true, INST.kind or "party" end return false, "none" end
SENT = {}
function SendChatMessage(msg, channel) SENT[#SENT + 1] = { msg = msg, channel = channel } end
function UnitFactionGroup() return FACTION or "Horde", FACTION or "Horde" end
'''

EJ_EMPTY = r'''
function EJ_GetNumTiers() return 0 end
function EJ_GetCurrentTier() return nil end
function EJ_GetTierInfo(i) error("Usage: EJ_GetTierInfo(index) Invalid index " .. tostring(i)) end
function EJ_SelectTier() end
function EJ_GetInstanceByIndex() return nil end
function EJ_SelectInstance() end
function EJ_GetInstanceInfo() return nil end
function EJ_GetEncounterInfoByIndex() return nil end
C_EncounterJournal = { GetEncountersOnMap = function() return {} end }
'''

EJ_LIVE = EJ_EMPTY + r'''
function EJ_GetInstanceInfo(id) if id == 240 then return "Wailing Caverns", "desc", 1, 2, 3, 4, 5, 6, 7, 43 end return nil end
function EJ_GetEncounterInfoByIndex(i, inst) if inst == 240 and i == 1 then return "Lady Anacondra", "desc", 1001 end return nil end
'''


@pytest.fixture
def jr(lua):
    lua.execute("MockState.playerClass = 'PRIEST'; MockUnits.player.class = 'PRIEST'; MockUnits.player.level = 20")
    lua.execute(CLIENT)
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Journal")
    lua.player_login()
    lua.execute("MockAdvance(2)")   # the login zone-in wait runs out (outside, nothing happens)
    lua.execute("wipe(HogHeals.errors)")
    return lua


def errors(lua):
    return [e["msg"] for e in lua.eval("HogHeals.errors").values()]


def vals(t):
    return list(t.values()) if t is not None else []


def chat(lua):
    return "\n".join(lua.eval("MockLog.chat").values())


def enter(lua, inst=43, name="Wailing Caverns", kind="party"):
    lua.execute(f'INST = {{ id = {inst}, name = "{name}", kind = "{kind}" }}; MockFire("PLAYER_ENTERING_WORLD", false, true); MockAdvance(2)')


# ------------------------------------------------------------------------------------------------ the shipped data
def test_shipped_data_follows_the_schema(jr):
    dungeons = vals(jr.eval(f"{J}.Data.Dungeons"))
    assert dungeons, "no dungeon shipped"
    hits, shield, load = {"tank", "target", "group"}, {"tank", "target", "group"}, {"none", "low", "moderate", "heavy"}
    schools = set(vals(jr.eval(f"{J}.SCHOOL_ORDER")))
    for d in dungeons:
        assert d["key"] and d["name"] and isinstance(d["inst"], (int, float)) and d["levels"], d["key"]
        bosses = vals(d["bosses"])
        assert bosses, d["key"]
        for b in bosses:
            assert b["name"] and b["summary"], b["name"]
            assert b["damage"]["tank"] in load and b["damage"]["group"] in load, b["name"]
            for c in vals(b["casts"]):
                assert c["name"], b["name"]
                assert c["dispel"] is None or c["dispel"] in schools, (b["name"], c["name"])
                assert c["shield"] is None or c["shield"] in shield, (b["name"], c["name"])
                assert c["hits"] is None or c["hits"] in hits, (b["name"], c["name"])
                assert c["kick"] is None or c["kick"] in (1, 2), (b["name"], c["name"])
        for q in vals(d["quests"]):
            assert q["title"] and q["goal"] and q["giver"] and q["turnin"], q["title"]
            assert q["side"] in (None, "A", "H")


def test_wailing_caverns_is_the_proof_of_concept(jr):
    d = jr.eval(f"{J}.Dungeon(43)")
    assert d["key"] == "wc" and d["name"] == "Wailing Caverns"
    names = [b["name"] for b in vals(d["bosses"])]
    assert names[:4] == ["Lady Anacondra", "Lord Cobrahn", "Kresh", "Lord Pythas"]
    assert "Mutanus the Devourer" in names and "Verdan the Everliving" in names
    assert jr.eval(f"{J}.Dungeon('wc').inst") == 43
    assert jr.eval(f"{J}.Dungeon('wailing caverns').key") == "wc"
    assert jr.eval(f"{J}.Dungeon(36)") is None and jr.eval(f"{J}.Dungeon('deadmines')") is None
    assert "not verified on Forever" in jr.eval(f"{J}.Data.SOURCE")


def test_dispel_vocabulary(jr):
    assert jr.eval(f"{J}.CanDispel('PRIEST', 'magic')") is True
    assert jr.eval(f"{J}.CanDispel('MAGE', 'magic')") is False
    assert jr.eval(f"{J}.CanDispel('SHAMAN', 'poison')") is True and jr.eval(f"{J}.CanDispel('SHAMAN', 'magic')") is False
    assert jr.eval(f"{J}.ClassNames({J}.Dispellers('curse'))") == "Mage, Druid"
    assert jr.eval(f"{J}.Dispellers('bleed')") is not None and len(vals(jr.eval(f"{J}.Dispellers('bleed')"))) == 0


# ------------------------------------------------------------------------------------------------ boss lines
def test_boss_lines_carry_the_healer_fields(jr):
    rows = vals(jr.eval(f"{J}.BossLines({J}.Dungeon('wc').bosses[1], 'PRIEST')"))
    text = "\n".join(r["text"] for r in rows)
    assert rows[0]["text"] == "Lady Anacondra" and rows[0]["head"] is True
    assert "Tank damage: moderate     Group damage: low" in text
    assert "Sleep - dispel (MAGIC): Priest, Paladin - YOU can" in text
    assert "shield the target before Lightning Bolt" in text
    assert "INTERRUPT" in text and "Lightning Bolt  (nice)" in text
    assert "HEALER" in text and "Thorns punishes melee" in text
    # a class that cannot dispel magic is told so
    rows = vals(jr.eval(f"{J}.BossLines({J}.Dungeon('wc').bosses[1], 'WARRIOR')"))
    assert any("Sleep - dispel (MAGIC)" in r["text"] and "not you" in r["text"] for r in rows)


def test_must_kicks_sort_first_and_colour_red(jr):
    rows = vals(jr.eval(f"{J}.BossLines({J}.Dungeon('wc').bosses[4], 'SHAMAN')"))   # Lord Pythas
    kicks = [r for r in rows if r["text"].startswith("  ") and "(must)" in r["text"] or "(nice)" in r["text"]]
    assert kicks[0]["text"].strip() == "Healing Touch  (must)"
    assert list(kicks[0]["color"].values()) == pytest.approx([0.85, 0.20, 0.20])


def test_wrap_is_by_character_count(jr):
    lines = vals(jr.eval(f"{J}.Wrap('one two three four five six seven eight nine ten', 15)"))
    assert lines == ["one two three", "four five six", "seven eight", "nine ten"]
    assert vals(jr.eval(f"{J}.Wrap('', 10)")) == []


# ------------------------------------------------------------------------------------------------ where am I
def test_where_reads_the_instance_without_touching_secrets(jr):
    assert jr.eval(f"{J}.Where()") is None
    jr.execute('INST = { id = 43, name = "Wailing Caverns" }')
    w = jr.eval(f"{J}.Where()")
    assert w["kind"] == "party" and w["inst"] == 43 and w["name"] == "Wailing Caverns" and w["secret"] is False
    d, w2 = jr.eval(f"{J}.Current()")
    assert d["key"] == "wc" and w2["inst"] == 43


def test_secret_instance_parts_are_named_not_compared(jr):
    jr.execute('MockSetSecrets(true)')
    jr.execute('function GetInstanceInfo() return MockSecret("Wailing Caverns"), "party", 1, "Normal", 5, 0, false, MockSecret(43) end')
    w = jr.eval(f"{J}.Where()")
    assert w["kind"] == "party" and w["inst"] is None and w["name"] is None and w["secret"] is True
    assert jr.eval(f"({J}.Current())") is None
    jr.execute(f"{J}.Compat.Check()")
    assert any("hides the instance" in l for l in vals(jr.eval(f"{J}.Compat.Degraded()")))
    assert errors(jr) == []


# ------------------------------------------------------------------------------------------------ auto-open
def test_first_dungeon_entry_opens_the_journal_once_per_session(jr):
    assert jr.eval(f"{J}.Window.frame") is None
    enter(jr)
    assert jr.eval(f"{J}.module.last") == "opened, summary: off"
    assert jr.eval(f"{J}.Window.frame:IsShown()") is True
    assert jr.eval(f"{J}.Window.dungeon.key") == "wc"
    jr.execute(f"{J}.Window.frame:Hide()")
    enter(jr)   # back in after a wipe: stays closed
    assert jr.eval(f"{J}.module.last") == "seen"
    assert jr.eval(f"{J}.Window.frame:IsShown()") is False
    jr.execute('HogHeals:SlashCommand("journal reset")')
    enter(jr)
    assert jr.eval(f"{J}.Window.frame:IsShown()") is True
    assert errors(jr) == []


def test_auto_open_option_off_keeps_it_closed(jr):
    jr.execute("HogHeals.db.profile.journal.autoOpen = false")
    enter(jr)
    assert jr.eval(f"{J}.module.last") == "summary: off"
    assert jr.eval(f"{J}.Window.frame") is None


def test_unknown_dungeon_says_so_once_and_does_not_open(jr):
    enter(jr, inst=36, name="The Deadmines")
    assert jr.eval(f"{J}.module.last") == "no data"
    assert "no page for The Deadmines yet (instance 36)" in chat(jr)
    assert jr.eval(f"{J}.Window.frame") is None
    jr.execute("wipe(MockLog.chat)")
    enter(jr, inst=36, name="The Deadmines")
    assert "no page for" not in chat(jr)   # once per session (the core's own zone-in lines may print)


def test_outside_an_instance_nothing_happens(jr):
    jr.execute('MockFire("PLAYER_ENTERING_WORLD", false, false); MockAdvance(2)')
    assert jr.eval(f"{J}.module.last") == "outside"
    assert jr.eval(f"{J}.Window.frame") is None


def test_default_profile_carries_the_journal_keys(jr):
    c = jr.eval("HogHeals.db.profile.journal")
    assert c["autoOpen"] is True and c["partySummary"] is False and c["enabled"] is True


# ------------------------------------------------------------------------------------------------ the window
def test_window_lists_bosses_left_and_detail_right(jr):
    jr.execute('HogHeals:SlashCommand("journal wc")')
    left = vals(jr.eval(f"{J}.Window.leftRows"))
    assert [r["text"] for r in left][:3] == ["Lady Anacondra", "Lord Cobrahn", "Kresh"]
    assert any(r["kind"] == "trash" for r in left)
    assert left[0]["selected"] is True
    right = vals(jr.eval(f"{J}.Window.rightRows"))
    assert right[0]["text"] == "Lady Anacondra"
    assert jr.eval(f"{J}.Window.frame.right[1]:GetText()") == "Lady Anacondra"
    assert jr.eval(f"{J}.Window.frame.left[1].label:GetText()") == "Lady Anacondra"
    assert "not verified on Forever" in jr.eval(f"{J}.Window.frame.footer:GetText()")
    # click a boss: the right pane follows
    jr.execute(f"{J}.Window.ClickLeft(4)")
    assert jr.eval(f"{J}.Window.rightRows[1].text") == "Lord Pythas"
    assert jr.eval(f"{J}.Window.rightOverflow") == 0, "Pythas page does not fit the pane"
    assert errors(jr) == []


def test_every_shipped_page_fits_the_right_pane(jr):
    jr.execute('HogHeals:SlashCommand("journal wc")')
    n = jr.eval(f"#{J}.Window.leftRows")
    for i in range(1, n + 1):
        jr.execute(f"{J}.Window.ClickLeft({i})")
        assert jr.eval(f"{J}.Window.rightOverflow") == 0, jr.eval(f"{J}.Window.leftRows[{i}].text")
    jr.execute(f'{J}.Window.SetTab("quests")')
    n = jr.eval(f"#{J}.Window.leftRows")
    for i in range(1, n + 1):
        jr.execute(f"{J}.Window.ClickLeft({i})")
        assert jr.eval(f"{J}.Window.rightOverflow") == 0, jr.eval(f"{J}.Window.leftRows[{i}].text")


def test_no_dungeon_shows_the_list_and_the_stub(jr):
    jr.execute('HogHeals:SlashCommand("journal")')
    left = vals(jr.eval(f"{J}.Window.leftRows"))
    assert left[0]["kind"] == "dungeon" and left[0]["text"] == "Wailing Caverns" and left[0]["right"] == "17-24"
    assert jr.eval(f"{J}.Window.rightRows[1].text") == "Pick a dungeon on the left."
    jr.execute(f"{J}.Window.ClickLeft(1)")
    assert jr.eval(f"{J}.Window.dungeon.key") == "wc"
    # inside an unknown dungeon the stub names it
    jr.execute(f'{J}.Window.SetDungeon(nil); INST = {{ id = 36, name = "The Deadmines" }}; {J}.Window.Refresh()')
    text = "\n".join(r["text"] for r in vals(jr.eval(f"{J}.Window.rightRows")))
    assert "You are in The Deadmines (id 36): no data for this dungeon yet" in text


def test_slash_toggles_and_unknown_names_are_told(jr):
    assert jr.eval(f"{J}.Window.Toggle()") is True and jr.eval(f"{J}.Window.frame:IsShown()") is True
    jr.execute('HogHeals:SlashCommand("journal")')
    assert jr.eval(f"{J}.Window.frame:IsShown()") is False
    jr.execute('HogHeals:SlashCommand("boss nowhere")')
    assert "no page called 'nowhere'" in chat(jr)
    jr.execute('HogHeals:SlashCommand("journal list")')
    assert "wc  Wailing Caverns  (17-24, id 43" in chat(jr)
    assert errors(jr) == []


# ------------------------------------------------------------------------------------------------ quests
def test_quest_rows_filter_by_side_and_mark_the_log(jr):
    log = 'HH_LOG = { { title = "Deviate Hides", complete = false, objectives = { { done = true }, { done = false } } }, { title = "Serpentbloom", complete = true, objectives = {} } }'
    jr.execute(log)
    rows = vals(jr.eval(f"{J}.QuestRows({J}.Dungeon('wc'), HH_LOG, 'H', 'PRIEST')"))
    by = {r["title"]: r for r in rows}
    assert by["Serpentbloom"]["state"] == "ready" and rows[0]["title"] == "Serpentbloom"
    assert by["Deviate Hides"]["state"] == "active" and by["Deviate Hides"]["progress"] == "1/2" and rows[1]["title"] == "Deviate Hides"
    assert by["Trouble at the Docks"]["state"] == "none"
    # Alliance sees the Horde quests last, greyed as "other"
    rows = vals(jr.eval(f"{J}.QuestRows({J}.Dungeon('wc'), HH_LOG, 'A', 'PRIEST')"))
    assert rows[-1]["state"] == "other" and rows[-1]["title"] in ("Serpentbloom", "Leaders of the Fang")
    assert all(r["state"] != "other" for r in rows[:-2])


def test_quests_tab_in_the_window(jr):
    jr.execute('HogHeals:SlashCommand("journal wc")')
    jr.execute(f'{J}.Window.SetTab("quests")')
    left = vals(jr.eval(f"{J}.Window.leftRows"))
    assert left[0]["kind"] == "quest" and left[0]["text"] == "Deviate Hides"
    right = "\n".join(r["text"] for r in vals(jr.eval(f"{J}.Window.rightRows")))
    assert right.startswith("Deviate Hides") and "Goal: Collect 20 Deviate Hides" in right and "[inside the dungeon]" in right
    # the Glowing Shard carries its chain
    idx = [r["text"] for r in left].index("The Glowing Shard") + 1
    jr.execute(f"{J}.Window.ClickLeft({idx})")
    right = "\n".join(r["text"] for r in vals(jr.eval(f"{J}.Window.rightRows")))
    assert "Leads to: In Nightmares" in right
    assert errors(jr) == []


def test_quest_log_through_hogtron_quests_when_loaded(jr):
    # HogHealsQuests present with a List(): rows read it without the test passing a log
    jr.execute('HogHealsQuests = { Data = { List = function() return { { title = "Smart Drinks", complete = true, objectives = {} } } end } }')
    rows = vals(jr.eval(f"{J}.QuestRows({J}.Dungeon('wc'), nil, 'H', 'PRIEST')"))
    assert rows[0]["title"] == "Smart Drinks" and rows[0]["state"] == "ready" and rows[0]["listed"] is True
    jr.execute("HogHealsQuests = nil")
    rows = vals(jr.eval(f"{J}.QuestRows({J}.Dungeon('wc'), nil, 'H', 'PRIEST')"))
    assert rows[0]["listed"] is False


# ------------------------------------------------------------------------------------------------ party summary
def test_summary_line_is_one_line_with_schools_and_must_kicks(jr):
    line = jr.eval(f"{J}.SummaryLine({J}.Dungeon('wc'))")
    assert line == "[HogTron UI Journal] Wailing Caverns: 9 bosses - dispel magic/poison - kick Healing Touch. /hh journal"
    assert "\n" not in line


def test_party_summary_is_off_by_default(jr):
    jr.execute('MockState.numGroup = 3; MockUnits.party1 = { name = "Ann", class = "MAGE" }; MockUnits.party2 = { name = "Bob", class = "WARRIOR" }')
    enter(jr)
    assert jr.eval("#SENT") == 0
    assert jr.eval(f"{J}.module.last") == "opened, summary: off"


def test_party_summary_goes_once_per_person_per_dungeon(jr):
    jr.execute('HogHeals.db.profile.journal.partySummary = true')
    jr.execute('MockState.numGroup = 3; MockUnits.party1 = { name = "Ann", class = "MAGE" }; MockUnits.party2 = { name = "Bob", class = "WARRIOR" }')
    enter(jr)
    assert jr.eval(f"{J}.module.last") == "opened, said"
    sent = vals(jr.eval("SENT"))
    assert len(sent) == 1 and sent[0]["channel"] == "PARTY" and sent[0]["msg"].startswith("[HogTron UI Journal] Wailing Caverns")
    said = jr.eval("HogHeals.db.global.journal.said['43']")
    assert said["Ann"] and said["Bob"]
    # same people, new session: nothing more
    jr.execute(f"{J}.seen = {{}}")
    enter(jr)
    assert jr.eval("#SENT") == 1 and jr.eval(f"{J}.module.last").endswith("everyone here has heard it")
    # a new face: once more
    jr.execute('MockUnits.party2 = { name = "Cal", class = "DRUID" }')
    jr.execute(f"{J}.seen = {{}}")
    enter(jr)
    assert jr.eval("#SENT") == 2
    assert errors(jr) == []


def test_party_summary_needs_a_group(jr):
    jr.execute('HogHeals.db.profile.journal.partySummary = true')
    enter(jr)
    assert jr.eval("#SENT") == 0 and jr.eval(f"{J}.module.last") == "opened, summary: not grouped"


def test_party_summary_with_secret_names_once_per_session(jr):
    jr.execute('HogHeals.db.profile.journal.partySummary = true; MockState.secretNames = true')
    jr.execute('MockState.numGroup = 2; MockUnits.party1 = { name = "Ann", class = "MAGE" }')
    enter(jr)
    assert jr.eval("#SENT") == 1
    jr.execute(f"{J}.seen = {{}}")
    enter(jr)
    assert jr.eval("#SENT") == 1
    assert errors(jr) == []


# ------------------------------------------------------------------------------------------------ the probe
def test_probe_with_no_ej_api(jr):
    jr.execute("MockAdvance(10)")   # the login probe
    p = jr.eval("HogHeals.db.global.journal_probe")
    assert p["reason"] == "login" and p["present"] == 0
    assert p["verdict"].startswith("NO EJ API")
    assert p["fns"]["EJ_GetInstanceInfo"] == "nil"
    assert p["where"] == "not in an instance"
    assert errors(jr) == []


def test_probe_with_an_empty_journal_like_forever(jr):
    jr.execute(EJ_EMPTY)
    jr.execute('HogHeals:SlashCommand("journal probe")')
    p = jr.eval("HogHeals.db.global.journal_probe")
    assert p["present"] >= 8 and p["oldIdsAnswered"] == 0
    assert p["verdict"].startswith("EJ PRESENT BUT EMPTY")
    assert p["tier1"].startswith("ERR") and "Invalid index" in p["tier1"]
    assert p["listedDungeon1"] == "(nothing)" or p["listedDungeon1"] == "nil"
    assert "journal probe (" in chat(jr) and "EJ PRESENT BUT EMPTY" in chat(jr)
    assert "HogHealsDB.global.journal_probe" in chat(jr)
    assert errors(jr) == []


def test_probe_notices_a_journal_that_answers(jr):
    jr.execute(EJ_LIVE)
    p = jr.eval(f"{J}.Probe.Run('test')")
    assert p["oldIdsAnswered"] == 1
    assert p["verdict"].startswith("EJ ANSWERS: 1 of")
    lines = vals(p["oldIds"])
    assert any(l.startswith('240 Wailing Caverns -> "Wailing Caverns"') and 'boss1="Lady Anacondra"' in l for l in lines)


def test_probe_names_secrets_and_skips_in_combat(jr):
    jr.execute(EJ_EMPTY)
    jr.execute('MockSetSecrets(true)')
    jr.execute('function GetInstanceInfo() return MockSecret("X"), "party", 1, "Normal", 5, 0, false, MockSecret(9) end')
    p = jr.eval(f"{J}.Probe.Run('test')")
    assert "SECRET(" in p["whereRaw"] and "(SECRET parts)" in p["where"]
    jr.execute("MockState.inCombat = true")
    p = jr.eval(f"{J}.Probe.Run('test')")
    assert p["skipped"] and "combat" in p["verdict"]
    assert errors(jr) == []


# ------------------------------------------------------------------------------------------------ wiring
def test_module_registered_with_options_and_slash(jr):
    assert jr.eval('HogHeals.modules.Journal ~= nil') is True
    opts = jr.eval('HogHeals.modules.Journal:GetOptions()')
    assert opts["type"] == "group" and opts["args"]["autoOpen"]["type"] == "toggle" and opts["args"]["partySummary"]["type"] == "toggle"
    assert jr.eval('HogHeals.slash.journal ~= nil and HogHeals.slash.boss ~= nil') is True
    assert jr.eval('HogHeals.slash.dungeon') is None   # /hh dungeon stays Atlas's tracker


def test_strict_font_client_draws_the_window(jr):
    jr.execute("MockState.strictFonts = true")
    jr.execute('HogHeals:SlashCommand("journal wc")')
    assert jr.eval(f"{J}.Window.frame:IsShown()") is True
    assert errors(jr) == []


def test_two_zone_events_schedule_one_wait(jr):
    jr.execute('INST = { id = 43, name = "Wailing Caverns" }; MockFire("PLAYER_ENTERING_WORLD", false, true); MockFire("ZONE_CHANGED_NEW_AREA")')
    assert jr.eval(f"{J}.module.pending") is True
    jr.execute("MockAdvance(2)")
    assert jr.eval(f"{J}.module.last") == "opened, summary: off"   # not overwritten by a second "seen"
    assert jr.eval(f"{J}.module.pending") is None


def test_cfg_stands_without_the_core_defaults(jr):
    # in game the core may be served from an older checkout than the journal (junction per addon folder)
    jr.execute("HogHeals.db.profile.journal = nil")
    c = jr.eval(f"{J}.cfg()")
    assert c["autoOpen"] is True and c["partySummary"] is False and c["scale"] == 1
    assert jr.eval("HogHeals.db.profile.journal.autoOpen") is True
