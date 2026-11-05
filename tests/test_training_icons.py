# Training window pictures (Sean 2026-11-04: "visuals ... with normal pictures from in the game"): the trainer's own
# spell icons on spell rows, the client's weapon-skill icons on weapon rows; row text itself stays plain.
from test_training import tr, errors  # noqa: F401 (fixture)

T = "HogHealsTraining"


def rows_at(lua, level):
    return list(lua.eval(f"{T}.RowsFrom({T}.Plan(), {T}.db(), 'H', {level})").values())


def test_spell_rows_carry_the_icon_the_trainer_handed_over(tr):
    tr.execute(f"{T}.Learn()")
    rows = rows_at(tr, 20)
    assert rows[0]["text"].startswith("TRAIN NOW") and rows[0]["icon"] is None       # headers carry none
    first = rows[1]
    assert first["text"] == "  Battle Shout (Rank 3)" and first["icon"] == "icon1"
    assert tr.eval(f'{T}.IconTag("icon1")') == "|Ticon1:14:14:0:0|t " and tr.eval(f"{T}.IconTag(nil)") == ""
    assert tr.eval(f"{T}.RowDisplay({T}.RowsFrom({T}.Plan(), {T}.db(), 'H', 20)[2])") == "  |Ticon1:14:14:0:0|t Battle Shout (Rank 3)"
    tr.execute(f"{T}.Toggle()")
    assert tr.eval("HogTronUITraining.rows[2].text._text") == "  |Ticon1:14:14:0:0|t Battle Shout (Rank 3)"
    assert errors(tr) == []


def test_weapon_rows_show_the_clients_weapon_skill_icons_and_degrade_without(tr):
    tr.execute('GetSpellTexture = function(id) return "weapon" .. id end')
    assert tr.eval(f'{T}.WeaponIcon("Axes")') == "weapon196" and tr.eval(f'{T}.WeaponIcon("Bows")') == "weapon264"
    assert tr.eval(f'{T}.WeaponIcon("Spoons")') is None
    sayoc = next(r for r in rows_at(tr, 20) if r["text"].startswith("      Axes, Bows"))
    assert sayoc["text"] == "      Axes, Bows, Daggers, Fist Weapons, Staves, Thrown, Two-Handed Axes"   # plain text kept
    assert list(sayoc["skills"].values())[:2] == ["Axes", "Bows"]
    shown = tr.eval(f"{T}.RowDisplay({{ text = 'x', skills = {{ 'Axes', 'Bows' }} }})")
    assert shown == "      |Tweapon196:12:12:0:0|t Axes, |Tweapon264:12:12:0:0|t Bows"
    tr.execute("GetSpellTexture = nil")
    assert tr.eval(f"{T}.RowDisplay({{ text = 'x', skills = {{ 'Axes' }} }})") == "      Axes"   # no client icon = just the name
    assert errors(tr) == []
