"""Mock spellbooks for the click-cast grid tests and the binding-UI mockups.

Each entry: (name, max_rank or None, cast_ms, helpful, passive). Expanded to one spellbook item per rank, like the
Classic client lists them. Rank counts follow Classic Era / TBC trainers closely enough for UI tests; they are test
data, not used by the addon (the addon reads the live spellbook).
"""
from __future__ import annotations

PRIEST_60 = [
    ("Shoot", None, 0, False, False),
    ("Smite", 8, 2500, False, False),
    ("Mind Blast", 9, 1500, False, False),
    ("Lesser Heal", 3, 2500, True, False),
    ("Heal", 4, 3000, True, False),
    ("Flash Heal", 7, 1500, True, False),
    ("Greater Heal", 5, 3000, True, False),
    ("Renew", 10, 0, True, False),
    ("Power Word: Shield", 10, 0, True, False),
    ("Prayer of Healing", 5, 3000, True, False),
    ("Dispel Magic", 2, 0, True, False),
    ("Abolish Disease", None, 0, True, False),
    ("Power Word: Fortitude", 6, 0, True, False),
    ("Divine Spirit", 4, 0, True, False),
    ("Inner Fire", 6, 0, True, False),
    ("Fade", 6, 0, True, False),
    ("Resurrection", 5, 10000, True, False),
    ("Spirit Tap", None, 0, True, True),
]

PRIEST_NO_REZ = [e for e in PRIEST_60 if e[0] != "Resurrection"]

PALADIN_60 = [
    ("Holy Light", 9, 2500, True, False), ("Flash of Light", 6, 1500, True, False), ("Purify", None, 0, True, False),
    ("Cleanse", None, 0, True, False), ("Blessing of Protection", 3, 0, True, False), ("Blessing of Freedom", None, 0, True, False),
    ("Redemption", 5, 10000, True, False), ("Seal of Righteousness", 8, 0, True, False), ("Judgement", None, 0, False, False),
]

DRUID_60 = [
    ("Healing Touch", 11, 3500, True, False), ("Regrowth", 9, 2000, True, False), ("Rejuvenation", 11, 0, True, False),
    ("Remove Curse", None, 0, True, False), ("Cure Poison", None, 0, True, False), ("Abolish Poison", None, 0, True, False),
    ("Mark of the Wild", 7, 0, True, False), ("Rebirth", 5, 2000, True, False), ("Wrath", 8, 2000, False, False),
]

SHAMAN_LOW = [   # level 18: no Lesser Healing Wave yet, no Ancestral Spirit trained
    ("Healing Wave", 4, 2500, True, False), ("Cure Poison", None, 0, True, False), ("Lightning Bolt", 4, 2500, False, False),
]

SHAMAN_60 = [
    ("Healing Wave", 10, 3000, True, False), ("Lesser Healing Wave", 6, 1500, True, False), ("Chain Heal", 3, 2500, True, False),
    ("Cure Poison", None, 0, True, False), ("Cure Disease", None, 0, True, False), ("Ancestral Spirit", 5, 10000, True, False),
    ("Lightning Bolt", 10, 3000, False, False),
]

WARRIOR_60 = [
    ("Heroic Strike", 9, 0, False, False), ("Battle Shout", 7, 0, True, False), ("Bloodrage", None, 0, True, False),
]

BOOKS = {"PRIEST": PRIEST_60, "PALADIN": PALADIN_60, "DRUID": DRUID_60, "SHAMAN": SHAMAN_60, "WARRIOR": WARRIOR_60}


def to_lua(book) -> str:
    """Lua table literal for MockState.spellbook."""
    rows = []
    for name, ranks, cast, helpful, passive in book:
        for r in (range(1, ranks + 1) if ranks else [None]):
            rank = f'"Rank {r}"' if r else "nil"
            rows.append(f'{{ "{name}", {rank}, helpful = {str(helpful).lower()}, passive = {str(passive).lower()}, castTime = {cast} }}')
    return "{ " + ", ".join(rows) + " }"


def boot(lua, cls: str = "PRIEST", book=None, before_login: str = ""):
    """Load core + Frames as character `cls` with `book` in the spellbook, then log in."""
    book = BOOKS.get(cls, []) if book is None else book
    lua.execute(f'MockState.playerClass = "{cls}"; MockUnits.player.class = "{cls}"; MockState.spellbook = {to_lua(book)}')
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Frames")
    if before_login:
        lua.execute(before_login)
    lua.player_login()
    return lua
