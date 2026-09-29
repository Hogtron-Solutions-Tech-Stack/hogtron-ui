# HogUI Atlas: the window, the dungeon quest tracker, the tooltip line, slash commands, options.
import pytest

from atlas_helpers import boot, errors, vals

A = "HogHealsAtlas"
W = "HogHealsAtlas.Window"
S = "HogHealsAtlas.Store"
G = "HogHealsAtlas.Gear"
DQ = "HogHealsAtlas.DungeonQuests"

LOG = '''
LOGQ = {
  { title = "Wailing Caverns", header = true },
  { title = "Leaders of the Fang", level = 22, id = 914, objectives = { { text = "Gem of Cobrahn: 1/1", done = true }, { text = "Gem of Anacondra: 0/1", done = false } } },
  { title = "A Quest Nobody Listed", level = 20, id = 5, objectives = {} },
  { title = "The Barrens", header = true },
  { title = "Deviate Hides", level = 17, id = 1486, complete = true, objectives = { { text = "Deviate Hide: 20/20", done = true } } },
  { title = "Plainstrider Menace", level = 12, id = 844, objectives = {} },
}
function FakeLog()
  local out, zone = {}, nil
  for _, q in ipairs(LOGQ) do
    if q.header then zone = q.title else
      out[#out + 1] = { title = q.title, level = q.level, id = q.id, zone = zone, objectives = q.objectives, complete = q.complete }
    end
  end
  return out
end
'''


@pytest.fixture
def atlas(lua):
    boot(lua, extra=LOG)
    lua.execute('MockUnits.player.level = 20')
    return lua


def texts(lua, name):
    return [r["text"] for r in vals(lua.eval(f"{W}.lists.{name}.data"))]


def click(lua, name, index, button="LeftButton"):
    lua.execute(f'{W}.lists.{name}.rows[{index}]:Click("{button}")')


# ------------------------------------------------------------------------------------------------ dungeon quests
def test_dungeon_quests_merge_the_list_with_your_log(atlas):
    rows = vals(atlas.eval(f'({DQ}.For("wc", FakeLog()))'))
    got = [(r["title"], r["state"], r["progress"], r["listed"]) for r in rows]
    assert got[0] == ("Deviate Hides", "ready", "1/1", True)                       # ready to hand in comes first
    assert got[1] == ("A Quest Nobody Listed", "active", None, False)              # filed under the dungeon by the game
    assert got[2] == ("Leaders of the Fang", "active", "1/2", True)
    rest = [g[0] for g in got[3:]]
    assert rest == sorted(rest) and "Serpentbloom" in rest and all(g[1] == "none" for g in got[3:])
    assert "Plainstrider Menace" not in [g[0] for g in got]                         # a zone quest is not a dungeon quest


def test_dungeon_quests_hide_the_other_side_and_other_classes(atlas):
    atlas.execute('FACTION = "Alliance"')
    titles = [r["title"] for r in vals(atlas.eval(f'({DQ}.For("wc", {{}}))'))]
    assert "Serpentbloom" not in titles and "Deviate Hides" in titles
    vc = [r["title"] for r in vals(atlas.eval(f'({DQ}.For("vc", {{}}))'))]
    assert "Red Silk Bandanas" in vc and "The Test of Righteousness" not in vc      # paladin only, we are a shaman
    atlas.execute('FACTION = "Horde"')
    assert vals(atlas.eval(f'({DQ}.For("vc", {{}}))')) == []
    # a quest in your log shows whatever the list says about sides
    atlas.execute('L2 = { { title = "Red Silk Bandanas", zone = "The Deadmines", objectives = {} } }')
    assert [r["title"] for r in vals(atlas.eval(f'({DQ}.For("vc", L2))'))] == ["Red Silk Bandanas"]


def test_header_match_covers_wings_and_the_article(atlas):
    m = lambda header, key: atlas.eval(f'{DQ}.HeaderMatches("{header}", {A}.Data.byKey.{key})')
    assert m("Scarlet Monastery", "sm_lib") is True and m("Scarlet Monastery", "sm_cath") is True
    assert m("Deadmines", "vc") is True and m("The Deadmines", "vc") is True
    assert m("Westfall", "vc") is False and m("", "vc") is False


def test_summary_counts_active_and_ready(atlas):
    assert list(atlas.eval(f'{{ {DQ}.Summary("wc", FakeLog()) }}').values()) == ["1 ready, 2 active", 2, 1]
    assert atlas.eval(f'({DQ}.Summary("scholo", FakeLog()))') is None


def test_without_the_quests_addon_the_list_still_shows(atlas):
    rows, have = atlas.eval(f'{DQ}.For("wc")')
    assert have is False and len(vals(rows)) >= 5
    assert {r["state"] for r in vals(rows)} == {"none"}


def test_with_the_quests_addon_the_real_log_is_read(lua):
    boot(lua, quests=True, extra=LOG)
    lua.execute("HogHealsQuests.Data.List = FakeLog")
    rows, have = lua.eval(f'{DQ}.For("wc")')
    assert have is True and vals(rows)[0]["title"] == "Deviate Hides" and vals(rows)[0]["state"] == "ready"


# ------------------------------------------------------------------------------------------------ window
def test_slash_opens_toggles_and_jumps_to_tabs(atlas):
    assert atlas.eval("HogUIAtlasWindow") is None                                  # nothing is built until asked for
    atlas.execute('HogHeals:SlashCommand("atlas")')
    assert atlas.eval("HogUIAtlasWindow:IsShown()") is True and atlas.eval(f"{W}.tab") == "dungeons"
    atlas.execute('HogHeals:SlashCommand("gear")')
    assert atlas.eval("HogUIAtlasWindow:IsShown()") is True and atlas.eval(f"{W}.tab") == "upgrades"
    atlas.execute('HogHeals:SlashCommand("gear")')
    assert atlas.eval("HogUIAtlasWindow:IsShown()") is False
    for word, tab in [("sets", "sets"), ("wish", "wish"), ("lootlog", "log")]:
        atlas.execute(f'HogHeals:SlashCommand("{word}")')
        assert atlas.eval(f"{W}.tab") == tab and atlas.eval(f"{W}.panes.{tab}:IsShown()") is True
    assert atlas.eval(f"{W}.panes.dungeons:IsShown()") is False
    assert errors(atlas) == []


def test_window_is_named_apart_from_the_namespace_and_closes_on_escape(atlas):
    atlas.execute('UISpecialFrames = {}; HogHeals:SlashCommand("atlas")')
    assert atlas.eval("type(HogHealsAtlas.Store)") == "table"                      # the frame did not overwrite the namespace
    assert vals(atlas.eval("UISpecialFrames")) == ["HogUIAtlasWindow"]


def test_dungeon_list_is_level_coloured_and_opens_on_one_for_your_level(atlas):
    atlas.execute('HogHeals:SlashCommand("atlas")')
    rows = {r["text"]: r for r in vals(atlas.eval(f"{W}.lists.dungeons.data"))}
    assert list(rows["The Deadmines"]["color"].values()) == pytest.approx([0.25, 0.80, 0.35])     # 20 in 17-26: green
    assert list(rows["Shadowfang Keep"]["color"].values()) == pytest.approx([0.85, 0.20, 0.20])   # 22-30: too low
    assert list(rows["Ragefire Chasm"]["color"].values()) == pytest.approx([0.55, 0.55, 0.60])    # 13-18: outgrown
    assert rows["The Deadmines"]["right"] == "17-26"
    assert "Ruins of Lordaeron (new)" in rows
    assert atlas.eval(f"{W}.dungeon") in ("wc", "vc", "lordaeron")
    assert atlas.eval(f"{A}.Levels.Band(20, {A}.Data.byKey[{W}.dungeon].min, {A}.Data.byKey[{W}.dungeon].max)") in ("green", "orange")


def test_window_opens_on_the_dungeon_you_stand_in(atlas):
    atlas.execute('INST = { name = "Shadowfang Keep", id = 33 }; HogHeals:SlashCommand("atlas")')
    assert atlas.eval(f"{W}.dungeon") == "sfk"


def test_for_my_level_button_filters_and_is_remembered(atlas):
    atlas.execute('HogHeals:SlashCommand("atlas")')
    full = len(texts(atlas, "dungeons"))
    atlas.execute(f"{W}.forMe:Click()")
    mine = texts(atlas, "dungeons")
    assert 0 < len(mine) < full and "Scholomance" not in mine and "The Deadmines" in mine
    assert atlas.eval(f"{A}.cfg().forMeNow") is True and atlas.eval(f"{W}.forMe.on") is True


def test_click_dungeon_then_boss_then_see_its_loot(atlas):
    atlas.execute(f'{S}.Record("vc", "Cookie", 1001, "seen"); {S}.Record("vc", "Cookie", 1001, "seen"); {S}.Record("vc", "Gilnid", 1004, "journal")')
    atlas.execute(f'HogHeals:SlashCommand("atlas"); {W}.dungeon = "vc"; {W}.Refresh()')
    bosses = texts(atlas, "bosses")
    assert bosses[0] == "All bosses" and bosses[1:4] == ["Rhahk'Zor", "Sneed's Shredder", "Gilnid"] and "Miner Johnson (rare)" in bosses
    detail = vals(atlas.eval(f"{W}.lists.detail.data"))
    assert [(r["header"], r["text"]) for r in detail] == [(True, "Gilnid"), (None, "Band of Waves"), (True, "Cookie"), (None, "Seer's Cowl")]
    assert [r["right"] for r in detail if not r["header"]] == ["journal", "seen x2"]
    click(atlas, "bosses", bosses.index("Cookie") + 1)
    assert atlas.eval(f"{W}.boss") == "Cookie"
    detail = vals(atlas.eval(f"{W}.lists.detail.data"))
    assert [r["text"] for r in detail] == ["Seer's Cowl"] and detail[0]["item"] == 1001
    assert list(detail[0]["color"].values()) == pytest.approx([0, 0.44, 0.87])       # blue quality
    click(atlas, "bosses", 1)                                                       # "All bosses"
    assert atlas.eval(f"{W}.boss") is None
    wc = texts(atlas, "dungeons").index("Wailing Caverns") + 1
    click(atlas, "dungeons", wc)
    assert atlas.eval(f"{W}.dungeon") == "wc" and vals(atlas.eval(f"{W}.lists.detail.data")) == []
    assert "No drops known" in atlas.eval(f"{W}.lists.detail.empty:GetText()")
    assert errors(atlas) == []


def test_item_not_sent_by_the_server_yet_shows_a_placeholder_then_its_name(atlas):
    atlas.execute(f'ITEMS[1001].cold = true; {S}.Record("vc", "Cookie", 1001, "seen"); HogHeals:SlashCommand("atlas"); {W}.dungeon = "vc"; {W}.boss = "Cookie"; {W}.Refresh()')
    assert texts(atlas, "detail") == ["item 1001 (asking the server...)"]
    atlas.execute('ITEMS[1001].cold = nil; MockFire("GET_ITEM_INFO_RECEIVED", 1001, true); MockAdvance(1)')
    assert texts(atlas, "detail") == ["Seer's Cowl"]


def test_quests_and_guide_panes(atlas):
    atlas.execute(f'{A}.DungeonQuests.For = (function(f) return function(k, log) return f(k, log or FakeLog()) end end)({A}.DungeonQuests.For)')
    atlas.execute(f'HogHeals:SlashCommand("atlas"); {W}.dungeon = "wc"; {W}.detailButtons.quests:Click()')
    rows = vals(atlas.eval(f"{W}.lists.detail.data"))
    assert (rows[0]["text"], rows[0]["right"]) == ("Deviate Hides", "ready to hand in")
    assert (rows[1]["text"], rows[1]["right"]) == ("A Quest Nobody Listed (from your log)", "in your log")
    assert (rows[2]["text"], rows[2]["right"]) == ("Leaders of the Fang", "1/2 done")
    assert [r["text"] for r in rows[3:5]] == ["Gem of Cobrahn: 1/1", "Gem of Anacondra: 0/1"] and rows[3]["indent"] == 14
    atlas.execute(f"{W}.detailButtons.guide:Click()")
    guide = {r["text"]: r["right"] for r in vals(atlas.eval(f"{W}.lists.detail.data"))}
    assert guide["Levels"] == "17-24  (right for your level)"
    assert guide["Level range from"] == "the old game's list"
    assert guide["Entrance"] == "The Barrens, Kalimdor" and guide["Bosses"] == "9"
    assert guide["Quests in your log"] == "1 ready, 2 active"
    assert "1. Lady Anacondra" in guide and "8. Mutanus the Devourer" in guide and "9. Deviate Faerie Dragon (rare, not always there)" in guide
    atlas.execute(f'{W}.dungeon = "lordaeron"; {W}.Refresh()')
    lines = texts(atlas, "detail")
    assert "No bosses known yet. They appear here as you kill them." in lines
    assert any("New in Forever" in l for l in lines)
    assert errors(atlas) == []


def test_wrap_breaks_on_words(atlas):
    assert vals(atlas.eval(f'{W}.wrap("one two three four five", 9)')) == ["one two", "three", "four five"]
    assert vals(atlas.eval(f'{W}.wrap("", 9)')) == []


def test_upgrades_tab_roles_and_status(atlas):
    atlas.execute(f'MockUnits.player.level = 30; WORN[1] = 1002; {S}.Record("vc", "Cookie", 1001, "journal"); {S}.Record("vc", "Cookie", 1003, "journal")')
    atlas.execute('HogHeals:SlashCommand("gear")')
    rows = vals(atlas.eval(f"{W}.lists.upgrades.data"))
    assert rows[0]["header"] is True and rows[0]["text"] == "Head   -   now: Plain Hood" and rows[0]["right"] == "score 2.9"
    assert rows[1]["text"] == "Seer's Cowl" and rows[1]["right"] == "+31.9" and "Cookie (The Deadmines)" in rows[1]["tip"]
    assert rows[1]["mid"] == "Cookie (The Deadmines)   |   22 Healing, 10 Intellect, 5 Spirit"      # where it drops, in the row
    assert atlas.eval(f"{W}.lists.upgrades.rows[2].mid:GetText()") == rows[1]["mid"]
    assert atlas.eval(f"{W}.lists.upgrades.rows[1].mid:IsShown()") is False                        # headers have no middle column
    assert len(rows) == 2
    assert "Scored for: healer" in atlas.eval("HogUIAtlasWindow.status:GetText()")
    assert atlas.eval(f"{W}.roleButtons.auto.on") is True
    atlas.execute(f"{W}.roleButtons.tank:Click()")
    assert atlas.eval(f"{A}.cfg().role") == "tank" and atlas.eval(f"{W}.roleButtons.tank.on") is True
    rows = vals(atlas.eval(f"{W}.lists.upgrades.data"))
    assert [r["text"] for r in rows if not r["header"]] == ["Seer's Cowl"]          # plate helm: a shaman cannot wear it
    assert "Scored for: tank" in atlas.eval("HogUIAtlasWindow.status:GetText()")


def test_right_click_wishlists_alt_click_goes_into_the_set(atlas):
    atlas.execute(f'{S}.Record("vc", "Cookie", 1001, "seen"); HogHeals:SlashCommand("atlas"); {W}.dungeon = "vc"; {W}.boss = "Cookie"; {W}.Refresh()')
    click(atlas, "detail", 1, "RightButton")
    assert atlas.eval(f"{G}.IsWished(1001)") is True and texts(atlas, "detail") == ["* Seer's Cowl"]
    atlas.execute('HogHeals:SlashCommand("wish")')
    assert texts(atlas, "wish") == ["* Seer's Cowl"]
    assert vals(atlas.eval(f"{W}.lists.wish.data"))[0]["right"] == "Cookie (The Deadmines)"
    click(atlas, "wish", 1, "RightButton")
    assert atlas.eval(f"{G}.IsWished(1001)") is False and texts(atlas, "wish") == []
    assert "wishlist is empty" in atlas.eval(f"{W}.lists.wish.empty:GetText()")
    atlas.execute("function IsAltKeyDown() return true end")
    atlas.execute(f'{W}.ItemClick(1001, "LeftButton")')                            # no set yet: one is made
    assert atlas.eval(f"#{G}.Sets()") == 1 and atlas.eval(f"{G}.Sets()[1].items[1]") == 1001
    assert errors(atlas) == []


def test_shift_click_links_and_ctrl_click_tries_on(atlas):
    atlas.execute("""
      LINKED, DRESSED = nil, nil
      function ChatEdit_InsertLink(l) LINKED = l return true end
      function DressUpItemLink(l) DRESSED = l end
      function IsShiftKeyDown() return true end
    """)
    atlas.execute(f'{W}.ItemClick(1001, "LeftButton")')
    assert atlas.eval("LINKED") == atlas.eval("ItemLink(1001)") and atlas.eval("DRESSED") is None
    atlas.execute("function IsShiftKeyDown() return false end function IsControlKeyDown() return true end")
    atlas.execute(f'{W}.ItemClick(1004, "LeftButton")')
    assert atlas.eval("DRESSED") == atlas.eval("ItemLink(1004)")


def test_sets_tab_buttons_and_removing_a_piece(atlas):
    atlas.execute(f'MockUnits.player.level = 30; WORN[1] = 1001; WORN[11] = 1004; {S}.Record("vc", "Cookie", 1001, "seen")')
    atlas.execute(f'HogHeals:SlashCommand("sets"); {G}.NewSet("Healing", "equipped"); {W}.Refresh()')
    assert texts(atlas, "setList") == ["Healing"] and vals(atlas.eval(f"{W}.lists.setList.data"))[0]["right"] == "2 pc"
    rows = vals(atlas.eval(f"{W}.lists.set.data"))
    assert rows[0]["text"] == "Healing" and rows[0]["right"] == "score 47.7"
    assert rows[1]["right"] == "+0.0" and rows[2]["right"] == "2 of 2"
    assert rows[3]["text"] == "22 Healing, 16 Intellect, 5 Spirit, 3 Mana per 5 sec, 30 Armor"
    items = [r for r in rows if r["item"]]
    assert [(r["text"], r["mid"], r["right"]) for r in items] == [("Seer's Cowl", "Head", "owned"), ("Band of Waves", "Ring 1", "owned")]
    assert ("(empty)", "Chest") in [(r["text"], r["mid"]) for r in rows]
    idx = [r["item"] for r in rows].index(1004) + 1
    click(atlas, "set", idx, "RightButton")
    assert atlas.eval(f"{G}.Sets()[1].items[11]") is None and atlas.eval(f"{G}.IsWished(1004)") is False


def test_loot_log_tab_shows_runs_and_drops(atlas):
    atlas.execute('INST = { name = "The Deadmines", id = 36 }; MockFire("PLAYER_ENTERING_WORLD"); MockFire("ENCOUNTER_END", 1, "Cookie", 1, 5, 1)')
    atlas.execute('LOOT = { { link = ItemLink(1001), guid = NpcGUID(645) } }; MockFire("LOOT_OPENED", true)')
    atlas.execute('MockAdvance(20); MockFire("CHAT_MSG_LOOT", "Thrall receives loot: " .. ItemLink(1004) .. ".", "Thrall")')
    atlas.execute('HogHeals:SlashCommand("lootlog")')
    assert texts(atlas, "runs") == ["The Deadmines"]
    rows = vals(atlas.eval(f"{W}.lists.drops.data"))
    assert [(r["text"], r["right"]) for r in rows] == [("Cookie", None), ("Seer's Cowl", ""), ("Band of Waves", "Thrall")]


def test_list_scrolls_inside_its_bounds(atlas):
    atlas.execute('HogHeals:SlashCommand("atlas")')
    L = f"{W}.lists.dungeons"
    total, shown = atlas.eval(f"#{L}.data"), atlas.eval(f"{L}.opts.rows")
    assert total > shown
    atlas.execute(f"{L}:Scroll(-5)")
    assert atlas.eval(f"{L}.offset") == 0
    atlas.execute(f"{L}:Scroll(1000)")
    assert atlas.eval(f"{L}.offset") == total - shown
    assert atlas.eval(f"{L}.rows[{shown}].data.text") == vals(atlas.eval(f"{L}.data"))[-1]["text"]
    atlas.execute(f"{L}.frame:GetScript('OnMouseWheel')({L}.frame, 1)")            # wheel up = back 3 rows
    assert atlas.eval(f"{L}.offset") == total - shown - 3


def test_window_position_is_saved_on_drag(atlas):
    atlas.execute('HogHeals:SlashCommand("atlas")')
    atlas.execute("""
      local f = HogUIAtlasWindow
      f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 120, -80)
      for _, c in ipairs({ f:GetChildren() }) do
        local stop = c.GetScript and c:GetScript("OnDragStop")
        if stop then stop(c) end
      end
    """)
    c = atlas.eval(f"{A}.cfg()")
    assert (c["point"], c["x"], c["y"]) == ("TOPLEFT", 120, -80)


# ------------------------------------------------------------------------------------------------ tooltip
def test_tooltip_lines_for_known_wished_and_unknown_items(atlas):
    T = f"{A}.Tooltip"
    atlas.execute(f"{A}.cfg().tooltipScore = false")                                # this test is about the drop lines
    atlas.execute(f'{S}.Record("vc", "Cookie", 1001, "seen")')
    assert vals(atlas.eval(f"({T}.Lines(1001))")) == ["Drops from: Cookie (The Deadmines)"]
    atlas.execute(f"{G}.ToggleWish(1001); {G}.ToggleWish(1004)")
    assert vals(atlas.eval(f"({T}.Lines(1001))")) == ["Drops from: Cookie (The Deadmines)", "On your wishlist"]
    assert vals(atlas.eval(f"({T}.Lines(1004))")) == ["On your wishlist"]
    assert vals(atlas.eval(f"({T}.Lines(1002))")) == [] and vals(atlas.eval(f"({T}.Lines(nil))")) == []
    atlas.execute(f"{A}.cfg().tooltip = false")
    assert vals(atlas.eval(f"({T}.Lines(1001))")) == []


def test_tooltip_uses_the_modern_processor_when_the_client_has_it(lua):
    boot(lua, extra='''
      POST = {}
      Enum = Enum or {}
      Enum.TooltipDataType = { Item = 0 }
      TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) POST[#POST + 1] = { kind = kind, fn = fn } end }
    ''')
    assert lua.eval(f"{A}.module.tooltipPath") == "processor" and lua.eval("#POST") == 1 and lua.eval("POST[1].kind") == 0
    lua.execute(f"{A}.cfg().tooltipScore = false")
    lua.execute(f'{S}.Record("vc", "Cookie", 1001, "seen"); GameTooltip:ClearLines(); POST[1].fn(GameTooltip, {{ id = 1001 }})')
    assert vals(lua.eval("GameTooltip._lines")) == ["Drops from: Cookie (The Deadmines)"]
    lua.execute('GameTooltip:ClearLines(); POST[1].fn(GameTooltip, { hyperlink = ItemLink(1001) }); POST[1].fn(GameTooltip, nil); POST[1].fn(GameTooltip, { id = 5 })')
    assert vals(lua.eval("GameTooltip._lines")) == ["Drops from: Cookie (The Deadmines)"]
    assert errors(lua) == []


def test_tooltip_falls_back_to_the_script_hook(atlas):
    assert atlas.eval(f"{A}.module.tooltipPath") == "script"


# ------------------------------------------------------------------------------------------------ options
def test_options_table_reads_and_writes_the_settings(atlas):
    atlas.execute(f"OPT = {A}.module:GetOptions()")
    assert atlas.eval("OPT.type") == "group" and atlas.eval("OPT.name") == "Atlas"
    assert atlas.eval("OPT.args.tooltip.get()") is True
    atlas.execute("OPT.args.tooltip.set(nil, false); OPT.args.futureLevels.set(nil, 5); OPT.args.role.set(nil, 'caster')")
    c = atlas.eval(f"{A}.cfg()")
    assert c["tooltip"] is False and c["futureLevels"] == 5 and c["role"] == "caster"
    assert atlas.eval("OPT.args.weights.args.spelldmg.get()") == 1.0
    atlas.execute("OPT.args.weights.args.spelldmg.set(nil, 2.5)")
    assert atlas.eval(f"{A}.Stats.Weights('caster').spelldmg") == 2.5 and atlas.eval(f"{A}.Stats.Weights('healer').spelldmg") == 0.3
    atlas.execute("OPT.args.weights.args.reset.func()")
    assert atlas.eval(f"{A}.Stats.Weights('caster').spelldmg") == 1.0
    n = sum(1 for _ in atlas.eval("OPT.args.weights.args").keys())
    assert n == atlas.eval(f"#{A}.Stats.ORDER") + 2


def test_settings_survive_without_touching_the_core_defaults_file(atlas):
    c = atlas.eval(f"{A}.cfg()")
    assert c["enabled"] is True and c["minQuality"] == 2 and c["role"] == "auto" and c["futureLevels"] == 3
    atlas.execute(f"{A}.cfg().minQuality = 3")
    assert atlas.eval("HogHeals.db.profile.atlas.minQuality") == 3                  # it lives in the saved profile


def test_atlasinfo_prints_what_was_read(atlas):
    atlas.execute('MockLog.chat = {}; HogHeals:SlashCommand("atlasinfo")')
    chat = "\n".join(vals(atlas.eval("MockLog.chat")))
    assert "journal:" in chat and "capture:" in chat and "drops known" in chat and "role healer" in chat
    assert errors(atlas) == []


# ------------------------------------------------------------------------------------------------ diag
def test_state_is_written_for_the_next_read_off_disk(atlas):
    atlas.execute(f'WORN[1] = 1001; {S}.Record("vc", "Cookie", 1001, "seen"); MockAdvance(7)')
    assert atlas.eval("HogHeals.db.global.diag.atlasState.reason") == "login"
    atlas.execute('MockLog.chat = {}; HogHeals:SlashCommand("atlasinfo")')
    st = atlas.eval("HogHeals.db.global.diag.atlasState")
    assert st["reason"] == "slash" and st["role"] == "healer" and st["store"]["drops"] == 1
    assert st["api"]["GetItemStats"] == "nil" and st["api"]["C_TooltipInfo.GetHyperlink"] == "function"
    assert st["journal"] == "no journal functions on this client"
    ip = st["itemProbe"]
    assert ip["slot"] == "Head" and ip["parsed"] == "armor=30 healing=22 int=10 spi=5"
    assert vals(ip["tooltipLines"])[4] == '"+10 Intellect"'
    assert "item reading: slot Head, stat table no, tooltip lines 7" in "\n".join(vals(atlas.eval("MockLog.chat")))
    atlas.execute('MockFire("PLAYER_LOGOUT")')
    assert atlas.eval("HogHeals.db.global.diag.atlasState.reason") == "logout"
    assert errors(atlas) == []


def test_item_probe_names_a_secret_link_and_touches_nothing(atlas):
    atlas.execute("MockSetSecrets(true); function GetInventoryItemLink() return MockSecret(ItemLink(1001)) end")
    ip = atlas.eval(f"{A}.Diag.ItemProbe()")
    assert ip["link"] == "SECRET(userdata)" and ip["parsed"] is None
    atlas.execute("function GetInventoryItemLink() return nil end")
    assert atlas.eval(f"{A}.Diag.ItemProbe().slot") == "nothing worn"


# ------------------------------------------------------------------------------------------------ browsing with your gear in mind
def test_loot_rows_mark_what_is_better_than_what_you_wear(atlas):
    atlas.execute(f"""
      MockUnits.player.level = 30; WORN[1] = 1002; WORN[11] = 1004
      for _, id in ipairs({{ 1001, 1003, 1004, 1007, 1002 }}) do {S}.Record("vc", "Cookie", id, "seen") end
      HogHeals:SlashCommand("atlas"); {W}.dungeon = "vc"; {W}.boss = "Cookie"; {W}.Refresh()
    """)
    rows = {r["item"]: r for r in vals(atlas.eval(f"{W}.lists.detail.data"))}
    assert rows[1001]["mid"] == "+31.9" and list(rows[1001]["midColor"].values()) == pytest.approx([0.25, 0.80, 0.35])
    assert rows[1007]["mid"] == "+55.7 at 45" and list(rows[1007]["midColor"].values()) == pytest.approx([0.95, 0.65, 0.15])
    assert rows[1002]["mid"] == "worn" and rows[1004]["mid"] == "worn"
    assert rows[1003]["mid"] is None                                                # plate: not for a shaman, nothing said
    assert atlas.eval(f"{W}.lists.detail.rows[1].mid:IsShown()") is True
    atlas.execute(f"{W}.detailButtons.guide:Click()")
    guide = {r["text"]: r["right"] for r in vals(atlas.eval(f"{W}.lists.detail.data"))}
    assert guide["Drops known"] == "5" and guide["Upgrades for you here"] == "1  (best +31.9)"
    atlas.execute(f'{W}.dungeon = "wc"; {W}.Refresh()')
    assert "Upgrades for you here" not in [r["text"] for r in vals(atlas.eval(f"{W}.lists.detail.data"))]   # nothing known: no line


def test_dungeon_items_lists_each_item_once(atlas):
    atlas.execute(f"""
      {A}.Data.Curated.vc = {{ Cookie = {{ 1004, 1001 }} }}
      {S}.Record("vc", "Cookie", 1001, "seen"); {S}.Record("vc", "Gilnid", 1001, "seen"); {S}.Record("vc", "Gilnid", 1002, "seen")
    """)
    assert vals(atlas.eval(f'{S}.DungeonItems("vc")')) == [1001, 1002, 1004]
    assert vals(atlas.eval(f'{S}.DungeonItems("wc")')) == []


def test_the_quest_log_is_read_once_per_repaint_not_once_per_dungeon(lua):
    boot(lua, quests=True, extra=LOG)
    lua.execute("HogHealsQuests.Data.List = FakeLog")
    reads = lambda: lua.eval(f"{DQ}.reads or 0")                                   # Atlas's own reads (HogUI Quests reads too)
    before = reads()
    lua.execute('HogHeals:SlashCommand("atlas")')
    assert lua.eval(f"#{W}.lists.dungeons.data") >= 28
    assert reads() - before == 1
    lua.execute(f"{W}.Refresh(); {W}.detailButtons.quests:Click(); {W}.detailButtons.guide:Click()")
    assert reads() - before == 1                                                    # same moment: still the one read
    lua.execute(f"MockAdvance(2); {W}.Refresh()")
    assert reads() - before == 2                                                    # a moment later: read again
    lua.execute(f'MockFire("QUEST_LOG_UPDATE"); {W}.Refresh()')
    assert reads() - before == 3                                                    # the log changed: read again at once
