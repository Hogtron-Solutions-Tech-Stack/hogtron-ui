"""Generate HogHeals_HUD/Data/HealRanks.lua from the vendored LibHealComm-4.0 (MIT).

Runs LibHealComm's class data blocks inside lupa for each flavor (Era build 1.x, TBC build 2.x) and
each healing class, then emits a compact Lua table:

  HogHealsHUD.HealRanks[flavor][spellName] = { coeff = c, hot = bool, ranks = { {rank, level, avg}, ... } }

Usage: python dev/gen_healranks.py
"""
from __future__ import annotations

import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "HogHeals" / "Libs" / "LibHealComm-4.0" / "LibHealComm-4.0.lua"
OUT = ROOT / "HogHeals_HUD" / "Data" / "HealRanks.lua"
MOCK = ROOT / "tests" / "wow_mock.lua"

# spellId -> English name (only heals we care about; anything else becomes "spell:<id>" and is skipped)
NAMES = {
    2050: "Lesser Heal", 2054: "Heal", 2060: "Greater Heal", 2061: "Flash Heal", 139: "Renew", 596: "Prayer of Healing",
    32546: "Binding Heal", 33076: "Prayer of Mending", 34861: "Circle of Healing", 17: "Power Word: Shield",
    331: "Healing Wave", 8004: "Lesser Healing Wave", 1064: "Chain Heal", 974: "Earth Shield",
    635: "Holy Light", 19750: "Flash of Light", 20473: "Holy Shock",
    5185: "Healing Touch", 8936: "Regrowth", 774: "Rejuvenation", 740: "Tranquility", 18562: "Swiftmend", 33763: "Lifebloom",
}
FLAVORS = {"era": ("1.15.8", 11508), "tbc": ("2.5.5", 20505)}
CLASSES = ["PRIEST", "SHAMAN", "PALADIN", "DRUID"]


def run(flavor: str, cls: str) -> dict:
    version, toc = FLAVORS[flavor]
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK.read_text(encoding="utf-8"))
    names = lua.table_from({k: v for k, v in NAMES.items()})
    lua.globals()["HH_NAMES"] = names
    lua.execute(f'''
      WOW_PROJECT_ID = WOW_PROJECT_CLASSIC
      GetBuildInfo = function() return "{version}", "1", "", {toc} end
      MockState.playerClass = "{cls}"
      MockUnits.player.class = "{cls}"
      C_Seasons = {{ HasActiveSeason = function() return false end, GetActiveSeason = function() return 0 end }}
      Enum.SeasonID = {{ Placeholder = 2, SeasonOfDiscovery = 2 }}
      C_Engraving = nil
      GetSpellInfo = function(id) local n = HH_NAMES[id] if n then return n, nil, "icon", 0, 0, 40, id end return "spell:" .. tostring(id), nil, "icon", 0, 0, 40, id end
      GetTalentInfo = function() return "Talent", "icon", 1, 1, 0, 5 end
      GetSpellBonusHealing = function() return 0 end
      GetInventoryItemLink = function() return nil end
      GetItemInfo = function() return nil end
      GetSpellBaseCooldown = function() return 0 end
      GetShapeshiftForm = function() return 0 end
      UnitBuff = UnitBuff
      MockState.inCombat = false
    ''')
    libs = ROOT / "HogHeals" / "Libs"
    for rel in ("LibStub/LibStub.lua", "CallbackHandler-1.0/CallbackHandler-1.0.lua"):
        lua.execute((libs / rel).read_text(encoding="utf-8"))
    src = LIB.read_text(encoding="utf-8")
    chunk = lua.eval("function(src) return loadstring(src, '@LibHealComm') end")
    fn = chunk(src)
    if isinstance(fn, tuple):
        raise SyntaxError(fn[1])
    fn("LibHealComm-4.0", lua.table())
    lua.execute('MockFire("PLAYER_LOGIN"); MockFire("PLAYER_ENTERING_WORLD")')
    hc = lua.eval('(LibStub("LibHealComm-4.0"))')
    out = {}
    for kind, tbl in (("spell", hc.spellData), ("hot", hc.hotData)):
        for name, data in tbl.items():
            if not isinstance(name, str) or name.startswith("spell:") or name.isdigit():
                continue
            levels = data["levels"]
            averages = data["averages"]
            if levels is None or averages is None:
                continue
            levels = list(levels.values()) if hasattr(levels, "values") else []
            avgs = list(averages.values()) if hasattr(averages, "values") else []
            ranks = []
            cap = 60 if flavor == "era" else 70
            for i, lvl in enumerate(levels):
                if lvl is None or int(lvl) > cap:
                    continue
                a = avgs[i] if i < len(avgs) else None
                if a is None:
                    continue
                if hasattr(a, "values"):  # per-player-level sub-table -> take fully levelled value
                    vals = [v for v in a.values() if isinstance(v, (int, float))]
                    a = vals[-1] if vals else None
                if not isinstance(a, (int, float)) or a <= 0:
                    continue
                ranks.append((len(ranks) + 1, int(lvl), round(float(a), 1)))
            if not ranks:
                continue
            coeff = data["coeff"]
            entry = out.setdefault(name, {"coeff": None, "hot": kind == "hot", "ranks": ranks, "cls": cls})
            if isinstance(coeff, (int, float)):
                entry["coeff"] = round(float(coeff), 4)
            if kind == "hot":
                entry["hot"] = True
                if data["interval"] is not None:
                    entry["interval"] = float(data["interval"])
                if data["ticks"] is not None:
                    entry["ticks"] = int(data["ticks"])
    return out


def emit(all_data: dict) -> str:
    lines = [
        "-- GENERATED by dev/gen_healranks.py from LibHealComm-4.0 (MIT) — do not edit by hand.",
        "-- Per-rank average heal + spell-power coefficient, fully-levelled values. Sources: LibHealComm authors",
        "-- (Shadowed, Stanzilla and contributors). See HogHeals/Libs/LibHealComm-4.0 for the original data + licence.",
        "HogHealsHUD = HogHealsHUD or {}",
        "HogHealsHUD.HealRanks = {",
    ]
    for flavor in ("era", "tbc"):
        lines.append(f"  {flavor} = {{")
        for name in sorted(all_data[flavor]):
            e = all_data[flavor][name]
            coeff = "0, coeffUnknown = true" if e["coeff"] is None else f"{e['coeff']:g}"
            extra = ""
            if e["hot"]:
                extra += ", hot = true"
                if "interval" in e:
                    extra += f", interval = {e['interval']:g}"
                if "ticks" in e:
                    extra += f", ticks = {e['ticks']}"
            ranks = ", ".join(f"{{ rank = {r}, level = {l}, avg = {a:g} }}" for r, l, a in e["ranks"])
            lines.append(f'    ["{name}"] = {{ class = "{e["cls"]}", coeff = {coeff}{extra}, ranks = {{ {ranks} }} }},')
        lines.append("  },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main() -> int:
    all_data = {"era": {}, "tbc": {}}
    for flavor in FLAVORS:
        for cls in CLASSES:
            try:
                data = run(flavor, cls)
            except Exception as exc:  # loud, not silent
                print(f"FAIL {flavor}/{cls}: {exc}")
                return 1
            print(f"{flavor}/{cls}: {len(data)} spells -> {', '.join(sorted(data))}")
            all_data[flavor].update(data)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(emit(all_data), encoding="utf-8", newline="\n")
    print("wrote", OUT.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
