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

# Real client icon file names (Interface\Icons\<name>), checked against Wowhead's icon CDN 2026-10-15 (404 = wrong).
ICONS = {
    "Shoot": "ability_shootwand", "Smite": "spell_holy_holysmite", "Mind Blast": "spell_shadow_unholyfrenzy",
    "Lesser Heal": "spell_holy_lesserheal", "Heal": "spell_holy_heal", "Flash Heal": "spell_holy_flashheal",
    "Greater Heal": "spell_holy_greaterheal", "Renew": "spell_holy_renew", "Power Word: Shield": "spell_holy_powerwordshield",
    "Prayer of Healing": "spell_holy_prayerofhealing02", "Dispel Magic": "spell_holy_dispelmagic",
    "Abolish Disease": "spell_nature_nullifydisease", "Power Word: Fortitude": "spell_holy_wordfortitude",
    "Divine Spirit": "spell_holy_divinespirit", "Inner Fire": "spell_holy_innerfire", "Fade": "spell_magic_lesserinvisibilty",
    "Resurrection": "spell_holy_resurrection", "Spirit Tap": "spell_shadow_requiem",
    "Holy Light": "spell_holy_holybolt", "Flash of Light": "spell_holy_flashheal", "Purify": "spell_holy_purify",
    "Cleanse": "spell_holy_renew", "Blessing of Protection": "spell_holy_sealofprotection",
    "Blessing of Freedom": "spell_holy_sealofvalor", "Redemption": "spell_holy_resurrection",
    "Seal of Righteousness": "ability_thunderbolt", "Judgement": "spell_holy_righteousfury", "Holy Shock": "spell_holy_searinglight",
    "Healing Touch": "spell_nature_healingtouch", "Regrowth": "spell_nature_resistnature", "Rejuvenation": "spell_nature_rejuvenation",
    "Remove Curse": "spell_holy_removecurse", "Cure Poison": "spell_nature_nullifypoison", "Abolish Poison": "spell_nature_nullifypoison_02",
    "Mark of the Wild": "spell_nature_regeneration", "Rebirth": "spell_nature_reincarnation", "Wrath": "spell_nature_abolishmagic",
    "Healing Wave": "spell_nature_magicimmunity", "Lesser Healing Wave": "spell_nature_healingwavelesser",
    "Chain Heal": "spell_nature_healingwavegreater", "Cure Disease": "spell_nature_removedisease",
    "Ancestral Spirit": "spell_nature_regenerate", "Lightning Bolt": "spell_nature_lightning",
    "Heroic Strike": "ability_rogue_ambush", "Battle Shout": "ability_warrior_battleshout", "Bloodrage": "ability_racial_bloodrage",
}

BOOKS = {"PRIEST": PRIEST_60, "PALADIN": PALADIN_60, "DRUID": DRUID_60, "SHAMAN": SHAMAN_60, "WARRIOR": WARRIOR_60}


def to_lua(book) -> str:
    """Lua table literal for MockState.spellbook."""
    rows = []
    for name, ranks, cast, helpful, passive in book:
        for r in (range(1, ranks + 1) if ranks else [None]):
            rank = f'"Rank {r}"' if r else "nil"
            icon = f', icon = "{ICONS[name]}"' if name in ICONS else ""
            rows.append(f'{{ "{name}", {rank}, helpful = {str(helpful).lower()}, passive = {str(passive).lower()}, castTime = {cast}{icon} }}')
    return "{ " + ", ".join(rows) + " }"


def boot(lua, cls: str = "PRIEST", book=None, before_login: str = ""):
    """Load core + Frames as character `cls` with `book` in the spellbook, then log in."""
    book = BOOKS.get(cls, []) if book is None else book
    lua.execute(f'MockState.playerClass = "{cls}"; MockUnits.player.class = "{cls}"; MockState.spellbook = {to_lua(book)}')
    lua.load_addon("HogTronUI")
    lua.load_addon("HogHeals_Frames")
    if before_login:
        lua.execute(before_login)
    lua.player_login()
    return lua
