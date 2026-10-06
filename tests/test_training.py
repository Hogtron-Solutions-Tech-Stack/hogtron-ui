# Training (HogHeals_Training): learned at the trainer, answered anywhere - train now / coming soon / cost, weapon trainers.
import pytest

T = "HogHealsTraining"

TRAINER = """
SERVICES = {
  { "Battle Shout", "Rank 3", "available", 2200, 20 },
  { "Rend", "Rank 3", "available", 1800, 20 },
  { "Heroic Strike", "Rank 4", "unavailable", 3000, 24 },
  { "Sunder Armor", "Rank 2", "unavailable", 2400, 22 },
  { "Intimidating Shout", nil, "unavailable", 2600, 22 },
  { "Charge", "Rank 1", "used", 0, 1 },
  { "Available", nil, "header", 0, 0 },
}
FILTER = { available = true, unavailable = false, used = false }
function GetNumTrainerServices() return #SERVICES end
function GetTrainerServiceInfo(i) local s = SERVICES[i] return s[1], s[2], s[3] end
function GetTrainerServiceCost(i) return SERVICES[i][4] end
function GetTrainerServiceLevelReq(i) return SERVICES[i][5] end
function GetTrainerServiceIcon(i) return "icon" .. i end
function GetTrainerServiceTypeFilter(k) return FILTER[k] end
function SetTrainerServiceTypeFilter(k, v) FILTER[k] = v end
function IsTradeskillTrainer() return false end
MockUnits.npc = { name = "Grezz Ragefist" }
function UnitFactionGroup() return "Horde" end
"""


@pytest.fixture
def tr(lua):
    lua.execute("MockState.playerClass = 'WARRIOR'; MockUnits.player.class = 'WARRIOR'; MockUnits.player.level = 20")
    lua.execute(TRAINER)
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Skin")
    lua.load_addon("HogHeals_Training")
    lua.player_login()
    lua.execute("wipe(HogHeals.errors)")
    return lua


def errors(lua):
    return [e["msg"] for e in lua.eval("HogHeals.errors").values()]


def test_nothing_known_until_a_trainer_is_opened(tr):
    assert tr.eval(f"{T}.Short()") == "visit a trainer"
    assert "nothing learned yet" in tr.eval(f"{T}.Lines()[1]")
    rows = tr.eval(f"{T}.RowsFrom({T}.Plan(), {T}.db(), 'H', 20)")
    assert rows[1]["text"] == "Nothing learned yet."
    assert any("WEAPON TRAINERS" in r["text"] for r in rows.values()) and any("Sayoc" in r["text"] for r in rows.values())


def test_a_trainer_visit_is_remembered_with_filters_restored(tr):
    tr.execute("MockFire('TRAINER_SHOW')")
    assert tr.eval(f"{T}.lastLearn") == 6                                   # the header row is not a spell
    assert tr.eval("FILTER.unavailable") is False and tr.eval("FILTER.used") is False   # put back as they were
    db = tr.eval(f"{T}.db()")
    assert db["visits"] == 1 and db["trainer"] == "Grezz Ragefist"
    assert db["spells"]["Battle Shout|Rank 3"]["cost"] == 2200 and db["spells"]["Charge|Rank 1"]["known"] is True
    assert any("6 services remembered" in m for m in tr.eval("MockLog.chat").values())
    plan = tr.eval(f"{T}.Plan()")
    assert [s["name"] for s in plan["now"].values()] == ["Battle Shout", "Rend"] and plan["cost"] == 4000
    soon = list(plan["soon"].values())
    assert [g["level"] for g in soon] == [22, 24]
    assert [s["name"] for s in soon[0]["spells"].values()] == ["Intimidating Shout", "Sunder Armor"] and soon[0]["cost"] == 5000
    assert plan["known"] == 1 and plan["total"] == 6
    assert tr.eval(f"{T}.Short()") == "2 to train  40s 0c"
    lines = tr.eval(f"{T}.Lines()")
    assert lines[1].startswith("train now: 2 spells for 40s 0c - Battle Shout (Rank 3), Rend (Rank 3)")
    assert lines[2].startswith("at 22: 2 for 50s 0c")
    assert "1 spells known, 1 visit" in lines[4]
    assert errors(tr) == []


def test_level_up_nudges_and_the_window_lists_it(tr):
    tr.execute("MockFire('TRAINER_SHOW'); wipe(MockLog.chat); MockUnits.player.level = 22; MockFire('PLAYER_LEVEL_UP', 22)")
    chat = "\n".join(tr.eval("MockLog.chat").values())
    assert "Level 22: 4 spells waiting at the trainer (90s 0c)" in chat
    tr.execute(f"{T}.Toggle()")
    assert tr.eval("HogTronUITraining:IsShown()") is True
    texts = [r["text"] for r in tr.eval(f"{T}.RowsFrom({T}.Plan(), {T}.db(), 'H', 22)").values()]
    assert texts[0].startswith("TRAIN NOW  -  4 spells")
    assert any("AT LEVEL 24" in t for t in texts) and not any("AT LEVEL 22" in t for t in texts)
    assert tr.eval(f"{T}.rowCount") > 10
    tr.execute("HogHeals.db.profile.training.nudge = false; wipe(MockLog.chat); MockFire('PLAYER_LEVEL_UP', 23)")
    assert not any("waiting at the trainer" in m for m in tr.eval("MockLog.chat").values())
    assert errors(tr) == []


def test_profession_trainer_is_ignored_and_memory_can_be_forgotten(tr):
    tr.execute("function IsTradeskillTrainer() return true end; MockFire('TRAINER_SHOW')")
    assert tr.eval(f"{T}.lastLearn") == "profession trainer" and tr.eval(f"{T}.db().visits") == 0
    tr.execute("function IsTradeskillTrainer() return false end; MockFire('TRAINER_SHOW'); HogHeals:SlashCommand('train forget')")
    assert tr.eval(f"{T}.db().visits") == 0
    assert tr.eval(f"{T}.Short()") == "visit a trainer"


def test_info_bar_text_and_weapon_trainer_lookup(tr):
    assert tr.eval("HogHealsSkin.InfoBar.providers.train ~= nil")
    tr.execute("MockFire('TRAINER_SHOW')")
    assert tr.eval("HogHealsSkin.InfoBar.providers.train.value()") == "2 to train  40s 0c"
    axes = tr.eval(f"{T}.Data.Trainers('H', 'axes')")
    assert sorted(t["name"] for t in axes.values()) == ["Hanashi", "Sayoc"]
    assert [t["name"] for t in tr.eval(f"{T}.Data.Trainers('A', 'polearm')").values()] == ["Woo Ping"]
