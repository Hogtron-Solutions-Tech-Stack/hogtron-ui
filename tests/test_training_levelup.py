# Level-up card (HogTron_Training/LevelUp.lua): what opened with the level - spells to train, dungeons now in range,
# talent points. Sean 2026-11-04: "When we level, I want a small pop-up on what's available to us now".
from test_training import TRAINER

CARD = "HogTronUILevelUpCard"


def boot(lua, level=20, atlas=True):
    lua.execute(f"MockState.playerClass = 'WARRIOR'; MockUnits.player.class = 'WARRIOR'; MockUnits.player.level = {level}")
    lua.execute(TRAINER)
    lua.load_addon("HogTronUI")
    lua.load_addon("HogTron_Skin")
    if atlas:
        lua.load_addon("HogTron_Atlas")
    lua.load_addon("HogTron_Training")
    lua.player_login()
    lua.execute("wipe(HogHeals.errors)")
    return lua


def errors(lua):
    return [e["msg"] for e in lua.eval("HogHeals.errors").values()]


def lines(lua, level):
    return [r[1] for r in lua.eval(f"HogHealsTraining.LevelUpLines(HogHealsTraining.LevelUpFacts({level}))").values()]


def test_facts_name_the_spells_that_opened_with_this_level(lua):
    boot(lua)
    lua.execute("HogHealsTraining.Learn()")
    f = lua.eval("HogHealsTraining.LevelUpFacts(22)")
    assert f["level"] == 22 and f["training"]["learned"] is True
    assert [s["name"] for s in f["training"]["new"].values()] == ["Intimidating Shout", "Sunder Armor"]
    assert f["training"]["waiting"] == 2                                 # Battle Shout + Rend, open since 20
    assert f["training"]["cost"] == 2200 + 1800 + 2400 + 2600
    first = lines(lua, 22)[0]
    assert first.startswith("Train now: Intimidating Shout, Sunder Armor (Rank 2)  (+2 still waiting)")
    assert first.endswith("90s 0c")
    assert errors(lua) == []


def test_before_the_first_trainer_visit_the_card_says_so(lua):
    boot(lua)
    assert "open your class trainer once" in lines(lua, 22)[0]
    lua.execute("HogHealsTraining.Learn()")
    assert lines(lua, 21)[0].startswith("Training: nothing new this level; 2 spells still waiting")


def test_dungeons_opening_at_this_level_for_my_faction(lua):
    boot(lua)
    keys = lambda level: [d["key"] for d in lua.eval(f"HogHealsTraining.LevelUpFacts({level}).dungeons").values()]
    k17 = keys(17)
    assert "wc" in k17 and "vc" not in k17                               # Deadmines starts at 17 too, but it is Alliance's
    assert keys(13) == ["rfc"] and keys(22) == ["sfk"]
    assert keys(18) == []
    assert lines(lua, 17)[-1].startswith("Now in range: ") and "Wailing Caverns (17-24)" in lines(lua, 17)[-1]
    assert errors(lua) == []


def test_talent_points_when_the_client_reports_them(lua):
    boot(lua)
    assert lua.eval("HogHealsTraining.LevelUpFacts(20).talents") is None
    lua.execute("function UnitCharacterPoints() return 2 end")
    assert lua.eval("HogHealsTraining.LevelUpFacts(20).talents") == 2
    assert lines(lua, 20)[-1] == "2 talent points to spend."


def test_level_up_shows_the_card_and_it_goes_away_on_its_own(lua):
    boot(lua)
    lua.execute("HogHealsTraining.Learn()")
    lua.fire("PLAYER_LEVEL_UP", 22)
    assert lua.eval(f"{CARD}:IsShown()") is True
    assert "22" in lua.eval(f"{CARD}.title._text")
    assert lua.eval(f"{CARD}.lines[1]._text").startswith("Train now: Intimidating Shout")
    assert lua.eval(f"{CARD}.lines[2]._text") == "Now in range: Shadowfang Keep (22-30)"
    assert lua.eval(f"{CARD}.lines[3]:IsShown()") is False
    assert lua.eval(f"{CARD}.next:IsShown()") is True                     # Atlas is there
    assert lua.eval("HogHealsTraining.lastCard.level") == 22
    lua.execute("MockAdvance(31)")
    assert lua.eval(f"{CARD}:IsShown()") is False                        # training.cardSeconds (30) passed
    lua.execute("HogHeals.db.profile.training.levelCard = false")
    lua.fire("PLAYER_LEVEL_UP", 23)
    assert lua.eval(f"{CARD}:IsShown()") is False
    assert errors(lua) == []


def test_the_buttons_open_train_and_where_next(lua):
    boot(lua)
    lua.execute("HogHealsTraining.ShowLevelUp(20)")
    lua.execute(f"{CARD}.train:Click()")
    assert lua.eval(f"{CARD}:IsShown()") is False and lua.eval("HogTronUITraining:IsShown()") is True
    lua.execute(f"HogHealsTraining.ShowLevelUp(20); {CARD}.next:Click()")
    assert lua.eval(f"{CARD}:IsShown()") is False
    assert errors(lua) == []


def test_slash_levelup_previews_any_level(lua):
    boot(lua)
    lua.execute('HogHeals:SlashCommand("levelup 30")')
    assert lua.eval("HogHealsTraining.lastCard.level") == 30 and "30" in lua.eval(f"{CARD}.title._text")
    lua.execute('HogHeals:SlashCommand("levelup")')
    assert lua.eval("HogHealsTraining.lastCard.level") == 20
    assert errors(lua) == []


def test_without_atlas_no_dungeon_line_and_no_where_next_button(lua):
    boot(lua, atlas=False)
    assert lua.eval("#HogHealsTraining.LevelUpFacts(17).dungeons") == 0
    lua.execute("HogHealsTraining.ShowLevelUp(17)")
    assert lua.eval(f"{CARD}.next:IsShown()") is False
    assert errors(lua) == []


def test_training_tab_carries_the_card_switches(lua):
    boot(lua)
    args = lua.eval("HogHeals.OptionsTable().args.Training.args")
    assert args["levelCard"]["type"] == "toggle" and args["nudge"]["type"] == "toggle" and args["cardSeconds"]["type"] == "range"
    assert lua.eval("HogHeals.OptionsTable().args.Training.args.levelCard.get()") is True
    assert lua.eval("HogHeals.db.profile.training.cardSeconds") == 30


def test_the_card_is_a_torn_page_in_the_parchment_look(lua):
    # Sean 2026-11-05, the Level 11 card: "the initial pop-up has not changed" - still the dark Modern strip while the
    # Training window it opens was on the page
    lua.execute('HogTronUIDB = { profiles = { Default = { look = { style = "parchment" } } } }')
    boot(lua)
    lua.execute("HogHealsTraining.ShowLevelUp(11)")
    assert lua.eval(f"{CARD}.onPage") is True and lua.eval(f"{CARD}.bg") is None
    assert lua.eval(f"{CARD}.pageTop._texture").endswith("dialog_page_light") and lua.eval(f"{CARD}.pageBot:IsShown()") is True
    assert lua.eval(f"{CARD}.pageMid:IsShown()") is False                                # the torn halves meet: no squeezed seam
    assert lua.eval(f"{CARD}.title._text") == "Level 11"
    first = lua.eval(f"{CARD}.lines[1]._text")
    assert first.startswith("Training: open your class trainer once")
    th = lua.eval("HogHeals.Parchment.Theme()")
    assert [round(v, 2) for v in list(lua.eval(f"{CARD}.lines[1]._color").values())[:3]] == [round(v, 2) for v in list(th["muted"].values())]
    assert lua.eval(f"{CARD}.lines[1]._height") == 34                                    # the long memo wraps onto two rows
    assert lua.eval(f"{CARD}._width") == 540 and lua.eval(f"{CARD}.pageHeight") > 100
    # the buttons still work, drawn as the page's key caps
    assert lua.eval(f"{CARD}.train.cap ~= nil") is True and lua.eval(f"{CARD}.next:IsShown()") is True
    lua.execute(f"{CARD}.train:Click()")
    assert lua.eval(f"{CARD}:IsShown()") is False and lua.eval("HogTronUITraining:IsShown()") is True
    assert errors(lua) == []


def test_the_modern_look_keeps_the_ink_card(lua):
    lua.execute('HogTronUIDB = { profiles = { Default = { look = { style = "hogtron" } } } }')
    boot(lua)
    lua.execute("HogHealsTraining.ShowLevelUp(11)")
    assert lua.eval(f"{CARD}.onPage") is False and lua.eval(f"{CARD}.bg ~= nil") is True
    assert lua.eval(f"{CARD}._width") == 460 and "LEVEL" in lua.eval(f"{CARD}.title._text")
    assert errors(lua) == []

