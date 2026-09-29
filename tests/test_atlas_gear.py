# HogUI Atlas: item stats, scoring, the upgrade finder, sets and the wishlist (the Sixty Upgrades part).
import pytest

from atlas_helpers import boot, errors, vals

A = "HogHealsAtlas"
G = "HogHealsAtlas.Gear"
ST = "HogHealsAtlas.Stats"
S = "HogHealsAtlas.Store"


@pytest.fixture
def atlas(lua):
    boot(lua)
    lua.execute('MockUnits.player.level = 30')
    return lua


def table(lua, expr):
    return dict(lua.eval(expr).items())


# ------------------------------------------------------------------------------------------------ stats
def test_parse_reads_classic_tooltip_lines(atlas):
    atlas.execute("""
      LINES = { "Seer's Cowl", "Binds when picked up", "Head", "Cloth", "30 Armor", "+10 Intellect", "+5 Spirit",
        "Durability 50 / 50", "Requires Level 25",
        "Equip: Increases healing done by spells and effects by up to 22.",
        "Equip: Restores 4 mana per 5 sec.",
        "Equip: Improves your chance to get a critical strike with spells by 1%.",
        "|cff00ff00Equip: Increases damage and healing done by magical spells and effects by up to 12.|r" }
    """)
    got = table(atlas, f"{ST}.Parse(LINES)")
    assert got == {"armor": 30, "int": 10, "spi": 5, "healing": 34, "mp5": 4, "spellcrit": 1, "spelldmg": 12}


def test_parse_melee_and_tank_lines(atlas):
    atlas.execute("""
      LINES = { "Great Maul", "Two-Hand", "60 - 90 Damage", "(25.5 damage per second)", "+12 Strength", "+7 Agility",
        "Equip: +24 Attack Power.", "Equip: Improves your chance to get a critical strike by 1%.",
        "Equip: Improves your chance to hit by 2%.", "Equip: Increased Defense +7.",
        "Equip: Increases your chance to dodge an attack by 1%.",
        "Equip: Increases damage done by Fire spells and effects by up to 14." }
    """)
    got = table(atlas, f"{ST}.Parse(LINES)")
    assert got == {"dps": 25.5, "str": 12, "agi": 7, "ap": 24, "crit": 1, "hit": 2, "defense": 7, "dodge": 1, "spelldmg": 7}


def test_parse_ignores_secrets_and_junk(atlas):
    atlas.execute('MockSetSecrets(true); LINES = { MockSecret("+10 Intellect"), 42, "", "Requires Level 25", "+3 Spirit" }')
    assert table(atlas, f"{ST}.Parse(LINES)") == {"spi": 3}
    assert table(atlas, f"{ST}.Parse(nil)") == {}


def test_stats_of_an_item_come_from_its_tooltip_and_are_cached(atlas):
    assert table(atlas, f"{ST}.Of(1001)") == {"armor": 30, "int": 10, "spi": 5, "healing": 22}
    atlas.execute("CALLS = 0; local f = C_TooltipInfo.GetHyperlink; C_TooltipInfo.GetHyperlink = function(...) CALLS = CALLS + 1 return f(...) end")
    atlas.execute(f"{ST}.Of(1001); {ST}.Of(ItemLink(1001))")
    assert atlas.eval("CALLS") == 0
    atlas.execute("ITEMS[1002].cold = true")                                       # the server has not sent it yet
    assert table(atlas, f"{ST}.Of(1002)") == {}
    atlas.execute("ITEMS[1002].cold = nil")
    assert table(atlas, f"{ST}.Of(1002)") == {"armor": 20, "int": 3}             # nothing empty was cached


def test_the_clients_stat_table_wins_for_the_same_stat(atlas):
    atlas.execute('C_Item.GetItemStats = function() return { ITEM_MOD_INTELLECT_SHORT = 11, ITEM_MOD_STAMINA_SHORT = 4, SOMETHING_ELSE = 9 } end')
    got = table(atlas, f"{ST}.Of(1001)")
    assert got["int"] == 11 and got["sta"] == 4 and got["healing"] == 22 and "SOMETHING_ELSE" not in got


def test_role_follows_the_class_until_you_pick_one(atlas):
    assert atlas.eval(f"{ST}.Role()") == "healer"                                  # shaman
    atlas.execute('MockState.playerClass = "ROGUE"')
    assert atlas.eval(f"{ST}.Role()") == "melee"
    atlas.execute(f'{A}.cfg().role = "tank"')
    assert atlas.eval(f"{ST}.Role()") == "tank"
    atlas.execute(f'{A}.cfg().role = "nonsense"')
    assert atlas.eval(f"{ST}.Role()") == "melee"


def test_score_uses_the_preset_with_your_changes_on_top(atlas):
    # healer: healing 1.0, int 0.9, spi 0.7, armor 0.01 -> 22 + 9 + 3.5 + 0.3
    assert atlas.eval(f"{ST}.Score({ST}.Of(1001), {ST}.Weights('healer'))") == pytest.approx(34.8)
    atlas.execute(f'{A}.cfg().weights.healer = {{ int = 2, spi = 0 }}')
    assert atlas.eval(f"{ST}.Score({ST}.Of(1001), {ST}.Weights('healer'))") == pytest.approx(22 + 20 + 0 + 0.3)
    assert atlas.eval(f"{ST}.PRESETS.healer.int") == 0.9                           # the preset itself is untouched
    assert atlas.eval(f"{ST}.Score({ST}.Of(1001), {ST}.Weights('melee'))") == pytest.approx(0.3)


def test_every_preset_only_uses_stats_that_exist(atlas):
    atlas.execute(f"""
      BAD = {{}}
      for role, w in pairs({ST}.PRESETS) do
        for k in pairs(w) do if not {ST}.NAMES[k] then BAD[#BAD + 1] = role .. "." .. k end end
      end
      for _, k in ipairs({ST}.ORDER) do if not {ST}.NAMES[k] then BAD[#BAD + 1] = "order." .. k end end
    """)
    assert vals(atlas.eval("BAD")) == []
    assert sorted(vals(atlas.eval(f"{ST}.ROLES"))) == sorted(atlas.eval(f"{ST}.PRESETS").keys())


# ------------------------------------------------------------------------------------------------ usable
@pytest.mark.parametrize("item,cls,level,ok", [
    (1001, "SHAMAN", 30, True),      # cloth: anyone
    (1008, "SHAMAN", 39, False),     # mail: shaman from 40
    (1008, "SHAMAN", 40, True),
    (1008, "PRIEST", 60, False),
    (1003, "WARRIOR", 39, False),    # plate from 40
    (1003, "WARRIOR", 40, True),
    (1003, "SHAMAN", 60, False),
    (1004, "PRIEST", 1, True),       # ring: anyone
    (1011, "PRIEST", 60, False),     # cloth scrap: not gear
])
def test_usable_by_class_and_level(atlas, item, cls, level, ok):
    assert atlas.eval(f'({G}.Usable({A}.ItemInfo({item}), "{cls}", {level}))') is ok


# ------------------------------------------------------------------------------------------------ upgrade finder
def known(lua, *ids):
    for i in ids:
        lua.execute(f'{S}.Record("vc", "Cookie", {i}, "journal")')


def test_upgrades_rank_by_points_better_than_what_you_wear(atlas):
    atlas.execute("WORN[1] = 1002")                                                # Plain Hood: 3 int, 20 armor = 2.9
    known(atlas, 1001, 1007, 1003, 1002)
    up = atlas.eval(f"({G}.Upgrades({{ futureLevels = 0 }}))")
    head = vals(up[1]["list"])
    assert [u["id"] for u in head] == [1001]                                       # 1007 needs 45, 1003 is plate, 1002 is worn
    assert head[0]["delta"] == pytest.approx(34.8 - 2.9)
    assert head[0]["source"] == "Cookie (The Deadmines)" and head[0]["where"] == "drop"
    assert up[1]["currentScore"] == pytest.approx(2.9)


def test_look_ahead_lists_items_you_cannot_wear_yet_after_the_ones_you_can(atlas):
    atlas.execute("WORN[1] = 1002; MockUnits.player.level = 43")
    known(atlas, 1001, 1007)
    head = vals(atlas.eval(f"({G}.Upgrades({{ futureLevels = 3 }}))")[1]["list"])
    assert [(u["id"], u["later"]) for u in head] == [(1001, None), (1007, 45)]      # the better one is later: listed second
    head = vals(atlas.eval(f"({G}.Upgrades({{ futureLevels = 1 }}))")[1]["list"])
    assert [u["id"] for u in head] == [1001]


def test_rings_are_measured_against_the_weaker_of_the_two(atlas):
    atlas.execute("WORN[11] = 1006; WORN[12] = 1005")                              # Iron 4 int = 3.6, Copper 2 sta = 0.5
    known(atlas, 1004)                                                             # Band of Waves: 6 int + 3 mp5 = 12.9
    up = atlas.eval(f"({G}.Upgrades({{ futureLevels = 0 }}))")
    assert vals(up[11]["list"]) == []
    ring2 = vals(up[12]["list"])
    assert [u["id"] for u in ring2] == [1004] and ring2[0]["delta"] == pytest.approx(12.9 - 0.5)


def test_an_item_you_already_wear_is_not_an_upgrade_for_the_other_slot(atlas):
    atlas.execute("WORN[11] = 1004")
    known(atlas, 1004)
    up = atlas.eval(f"({G}.Upgrades({{ futureLevels = 0 }}))")
    assert vals(up[11]["list"]) == [] and vals(up[12]["list"]) == []


def test_bag_items_count_and_say_where_they_are(atlas):
    atlas.execute("BAGS = { 1011, 1001 }")
    head = vals(atlas.eval(f"({G}.Upgrades({{ futureLevels = 0 }}))")[1]["list"])
    assert [(u["id"], u["where"], u["source"]) for u in head] == [(1001, "bag", "In your bags")]


def test_items_the_server_has_not_sent_are_counted_not_guessed(atlas):
    known(atlas, 1001, 1002)
    atlas.execute("ITEMS[1001].cold = true; REQUESTED = {}")
    up, unknown = atlas.eval(f"{G}.Upgrades({{ futureLevels = 0 }})")
    assert unknown == 1 and [u["id"] for u in vals(up[1]["list"])] == [1002]
    assert atlas.eval("REQUESTED[1001]") == 1                                      # asked once
    atlas.execute(f"{G}.Upgrades({{ futureLevels = 0 }})")
    assert atlas.eval("REQUESTED[1001]") == 1                                      # and not again while waiting
    atlas.execute('ITEMS[1001].cold = nil; MockFire("GET_ITEM_INFO_RECEIVED", 1001, true)')
    up, unknown = atlas.eval(f"{G}.Upgrades({{ futureLevels = 0 }})")
    assert unknown == 0 and [u["id"] for u in vals(up[1]["list"])] == [1001, 1002]


def test_upgrade_rows_have_a_header_per_slot_with_upgrades_only(atlas):
    atlas.execute("WORN[1] = 1002")
    known(atlas, 1001, 1004)
    rows = vals(atlas.eval(f"({G}.UpgradeRows({{ futureLevels = 0 }}))"))
    assert [(r["header"], r["text"] if r["header"] else r["id"]) for r in rows] == [
        (True, "Head"), (None, 1001), (True, "Ring 1"), (None, 1004)]


def test_list_per_slot_is_capped(atlas):
    atlas.execute("""
      for id = 3000, 3030 do
        ITEMS[id] = { "Hood " .. id, 2, 20, 10, "Armor", "Cloth", "INVTYPE_HEAD", 4, 1, { "+" .. (id - 2999) .. " Intellect" } }
      end
    """)
    known(atlas, *range(3000, 3031))
    head = vals(atlas.eval(f"({G}.Upgrades({{ futureLevels = 0, perSlot = 5 }}))")[1]["list"])
    assert [u["id"] for u in head] == [3030, 3029, 3028, 3027, 3026]


# ------------------------------------------------------------------------------------------------ wishlist
def test_wishlist_is_per_character_and_toggles(atlas):
    assert atlas.eval(f"{G}.ToggleWish(1001)") is True
    assert atlas.eval(f"{G}.IsWished(1001)") is True and atlas.eval(f"{G}.IsWished(1002)") is False
    atlas.execute('MockUnits.player.name = "Father"')
    assert atlas.eval(f"{G}.IsWished(1001)") is False
    atlas.execute('MockUnits.player.name = "Hognificent"')
    assert atlas.eval(f"{G}.ToggleWish(1001)") is False and atlas.eval(f"{G}.IsWished(1001)") is False
    assert atlas.eval(f"{G}.ToggleWish(nil)") is None


def test_wish_rows_say_where_it_drops_and_whether_you_have_it(atlas):
    known(atlas, 1001)
    atlas.execute(f"{G}.ToggleWish(1001); {G}.ToggleWish(1004); BAGS = {{ 1004 }}")
    rows = {r["id"]: r for r in vals(atlas.eval(f"{G}.WishRows()"))}
    assert rows[1001]["source"] == "Cookie (The Deadmines)" and rows[1001]["have"] is False
    assert rows[1004]["source"] == "source unknown" and rows[1004]["have"] is True


# ------------------------------------------------------------------------------------------------ sets
def test_set_from_what_you_wear_and_its_summary(atlas):
    atlas.execute("WORN[1] = 1001; WORN[11] = 1004")
    known(atlas, 1001)
    assert atlas.eval(f'select(2, {G}.NewSet("Healing", "equipped"))') == 1
    s = atlas.eval(f"{G}.SetSummary(1)")
    assert s["name"] == "Healing" and s["pieces"] == 2 and s["owned"] == 2
    assert s["score"] == pytest.approx(34.8 + 12.9)
    assert dict(s["stats"].items()) == {"armor": 30, "int": 16, "spi": 5, "healing": 22, "mp5": 3}
    rows = {r["slot"]: r for r in vals(s["rows"])}
    assert rows[1]["id"] == 1001 and rows[1]["source"] == "Cookie (The Deadmines)" and rows[5]["id"] is None
    assert atlas.eval(f"({G}.EquippedScore())") == pytest.approx(34.8 + 12.9)


def test_set_item_picks_the_empty_slot_and_checks_the_fit(atlas):
    atlas.execute(f'{G}.NewSet("Plan")')
    assert list(atlas.eval(f"{{ {G}.SetItem(1, 1004) }}").values()) == [True, 11]
    assert list(atlas.eval(f"{{ {G}.SetItem(1, 1006) }}").values()) == [True, 12]   # second ring: the free slot
    assert list(atlas.eval(f"{{ {G}.SetItem(1, 1005) }}").values()) == [True, 11]   # both taken: the first
    assert list(atlas.eval(f"{{ {G}.SetItem(1, 1001, 5) }}").values()) == [False, "does not fit that slot"]
    assert list(atlas.eval(f"{{ {G}.SetItem(9, 1001) }}").values()) == [False, "no such set"]
    assert list(atlas.eval(f"{{ {G}.SetItem(1, 99999) }}").values()) == [False, "item not known yet"]
    atlas.execute(f"{G}.Sets()[1].items[17] = 1004; {G}.SetItem(1, 1009)")
    assert atlas.eval(f"{G}.Sets()[1].items[16]") == 1009 and atlas.eval(f"{G}.Sets()[1].items[17]") is None   # two-hander clears the off hand
    assert atlas.eval(f"{G}.ClearSlot(1, 16)") is True and atlas.eval(f"{G}.Sets()[1].items[16]") is None


def test_sets_are_capped_named_and_deletable(atlas):
    for _ in range(12):
        atlas.execute(f"{G}.NewSet()")
    assert atlas.eval(f"#{G}.Sets()") == 12 and atlas.eval(f"{G}.Sets()[3].name") == "Set 3"
    assert list(atlas.eval(f"{{ {G}.NewSet() }}").values()) == ["set limit reached (12)"] or atlas.eval(f"({G}.NewSet())") is None
    assert atlas.eval(f"{G}.DeleteSet(2)") is True and atlas.eval(f"#{G}.Sets()") == 11
    assert atlas.eval(f"{G}.DeleteSet(40)") is False
    assert errors(atlas) == []
