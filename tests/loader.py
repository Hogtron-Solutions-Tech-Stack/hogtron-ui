"""Load WoW addons (.toc / .xml / .lua) into a lupa Lua 5.1 runtime.

Mirrors the client's load order: .toc lines in order, .xml <Script>/<Include>
in document order, each .lua executed with (addonName, addonTable) varargs.
Libraries listed in STUBBED are skipped (tests/lib_stubs.lua provides them).
"""
from __future__ import annotations

import re
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
TESTS = Path(__file__).resolve().parent

# Libraries whose real files need a live UI; lib_stubs.lua provides LibStub entries.
STUBBED = {
    "AceGUI-3.0", "AceConfig-3.0", "AceDBOptions-3.0", "LibSharedMedia-3.0",
    "LibRangeCheck-3.0", "LibHealComm-4.0", "LibDataBroker-1.1", "LibDBIcon-1.0",
}

_SCRIPT_RE = re.compile(r'<(Script|Include)\s+file="([^"]+)"', re.IGNORECASE)


class AddonLoader:
    def __init__(self, lua: LuaRuntime | None = None):
        self.lua = lua or LuaRuntime(unpack_returned_tuples=True)
        self.loaded: list[str] = []
        self._addon_tables: dict[str, object] = {}

    # ---- public -------------------------------------------------------
    def bootstrap(self) -> "AddonLoader":
        self.run_file(TESTS / "wow_mock.lua", "Mock")
        libs = ROOT / "HogHeals" / "Libs"
        self.run_file(libs / "LibStub" / "LibStub.lua", "HogHeals")
        self.run_file(libs / "CallbackHandler-1.0" / "CallbackHandler-1.0.lua", "HogHeals")
        self.run_file(TESTS / "lib_stubs.lua", "Mock")
        return self

    def load_addon(self, folder: str, fire: bool = True) -> "AddonLoader":
        """Execute the addon's files. fire=True then mirrors the client: mark it loaded, fire ADDON_LOADED.
        fire=False leaves it half-loaded so a test can fire other events in between (early-init scenarios)."""
        toc = ROOT / folder / f"{folder}.toc"
        if not toc.exists():
            raise FileNotFoundError(toc)
        self._addon_tables.setdefault(folder, self.lua.table())
        for line in toc.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            self._load_path(toc.parent / line.replace("\\", "/"), folder)
        if fire:
            self.mark_loaded(folder)
            self.fire("ADDON_LOADED", folder)
        return self

    def mark_loaded(self, folder: str) -> None:
        """IsAddOnLoaded(folder) -> true from here on (the client sets this before ADDON_LOADED fires)."""
        self.lua.execute(f'MockState.loadedAddons = MockState.loadedAddons or {{}}; MockState.loadedAddons["{folder}"] = true')

    def fire(self, event: str, *args) -> None:
        """MockFire(event, ...) with Python strings / numbers / booleans as Lua literals."""
        def lit(a):
            if isinstance(a, bool):
                return "true" if a else "false"
            if isinstance(a, (int, float)):
                return str(a)
            return '"' + str(a).replace("\\", "\\\\").replace('"', '\\"') + '"'
        tail = "".join(", " + lit(a) for a in args)
        self.lua.execute(f'MockFire("{event}"{tail})')

    def player_login(self) -> None:
        # WoW: IsLoggedIn() is false during startup ADDON_LOADED; addons enable on PLAYER_LOGIN.
        self.lua.execute('MockState.loggedIn = true; MockFire("PLAYER_LOGIN"); MockFire("PLAYER_ENTERING_WORLD", true, false)')

    def eval(self, code: str):
        return self.lua.eval(code)

    def execute(self, code: str):
        return self.lua.execute(code)

    # ---- internals ----------------------------------------------------
    def _load_path(self, path: Path, addon: str) -> None:
        rel = path.relative_to(ROOT).as_posix()
        if any(f"/Libs/{s}/" in f"/{rel}" or f"/Libs/{s}" == f"/{rel}".rstrip("/")[-len(s) - 6:] for s in STUBBED):
            return
        if path.suffix.lower() == ".xml":
            self._load_xml(path, addon)
        elif path.suffix.lower() == ".lua":
            self.run_file(path, addon)
        else:
            raise ValueError(f"unsupported include: {path}")

    def _load_xml(self, path: Path, addon: str) -> None:
        text = path.read_text(encoding="utf-8", errors="ignore")
        for _kind, file in _SCRIPT_RE.findall(text):
            self._load_path(path.parent / file.replace("\\", "/"), addon)

    def run_file(self, path: Path, addon: str) -> None:
        if not path.exists():
            raise FileNotFoundError(path)
        src = path.read_text(encoding="utf-8", errors="ignore")
        if src.startswith("﻿"):
            src = src[1:]
        chunk = self.lua.eval("function(src, name) return loadstring(src, '@' .. name) end")
        fn, err = self._call2(chunk, src, path.relative_to(ROOT).as_posix() if path.is_relative_to(ROOT) else path.name)
        if fn is None:
            raise SyntaxError(f"{path}: {err}")
        table = self._addon_tables.setdefault(addon, self.lua.table())
        fn(addon, table)
        self.loaded.append(path.as_posix())

    def _call2(self, chunk, src, name):
        res = chunk(src, name)
        if isinstance(res, tuple):
            return (res + (None, None))[:2]
        return res, None
