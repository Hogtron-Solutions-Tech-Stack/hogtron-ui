import pytest

DISPEL = [
    ("PRIEST", "Magic", True), ("PRIEST", "Disease", True), ("PRIEST", "Poison", False), ("PRIEST", "Curse", False),
    ("SHAMAN", "Poison", True), ("SHAMAN", "Disease", True), ("SHAMAN", "Magic", False),
    ("PALADIN", "Magic", True), ("PALADIN", "Poison", True), ("PALADIN", "Disease", True), ("PALADIN", "Curse", False),
    ("DRUID", "Curse", True), ("DRUID", "Poison", True), ("DRUID", "Magic", False),
    ("MAGE", "Curse", True), ("MAGE", "Magic", False),
    ("WARRIOR", "Magic", False), ("ROGUE", "Poison", False),
]


@pytest.mark.parametrize("cls,kind,expected", DISPEL)
def test_can_dispel(core, cls, kind, expected):
    assert core.eval(f'HogHeals.CanDispel("{cls}", "{kind}")') is expected


def test_dispellable_types_list(core):
    assert sorted(core.eval('HogHeals.DispellableTypes("PALADIN")').values()) == ["Disease", "Magic", "Poison"]
    assert list(core.eval('HogHeals.DispellableTypes("WARRIOR")').values()) == []


def test_missing_buff_spells(core):
    fort = core.eval('HogHeals.MissingBuffSpells("PRIEST")')
    names = [v["name"] for v in fort.values()]
    assert "Power Word: Fortitude" in names
    entry = [v for v in fort.values() if v["name"] == "Power Word: Fortitude"][0]
    assert "Prayer of Fortitude" in list(entry["satisfiedBy"].values())
    assert list(core.eval('HogHeals.MissingBuffSpells("ROGUE")').values()) == []


def test_shield_spells_gated_by_project(core):
    assert list(core.eval('HogHeals.ShieldSpells("PRIEST")').values()) == ["Power Word: Shield"]
    core.execute('GetBuildInfo = function() return "2.5.5", "1", "", 20505 end')
    assert list(core.eval('HogHeals.ShieldSpells("SHAMAN")').values()) == ["Earth Shield"]
    core.execute('GetBuildInfo = function() return "1.15.8", "1", "", 11508 end')
    assert list(core.eval('HogHeals.ShieldSpells("SHAMAN")').values()) == []
