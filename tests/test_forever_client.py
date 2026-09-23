# Client differences found on the Forever beta (1.60.1) by reading the persisted diag log, session 3:
#   RegisterUnitEvent(): Attempt to register unknown event "UNIT_HEALTH_FREQUENT"   -> aborted button setup
#   FontString:SetText(): Font not set  (HUD.lua:35)                                 -> aborted the whole HUD
#   Dispel.lua:17: attempt to call a nil value  (UnitAura is gone)
import pathlib, re

ROOT = pathlib.Path(__file__).resolve().parent.parent


def test_unknown_event_does_not_abort_button_setup(frames):
    frames.execute('MockUnknownEvents.UNIT_HEALTH_FREQUENT = true; MockUnknownEvents.UNIT_POWER_FREQUENT = true; wipe(HogHeals.errors)')
    frames.execute('MockUnits.party1 = { name = "Ann", class = "PRIEST", health = 40, maxHealth = 100, guid = "Player-9" }')
    frames.execute('HH_e = HogHealsFrames.UnitButton.Create("HHEvtBtn", UIParent); HogHealsFrames.UnitButton.OnAttributeChanged(HH_e, "unit", "party1")')
    assert frames.eval('HH_e.health._value') == 40          # first paint happened
    assert frames.eval('HH_e._events.UNIT_AURA') is True     # events AFTER the bad one still registered
    assert frames.eval('HH_e._events.UNIT_HEALTH') is True
    assert frames.eval('#HogHeals.errors') == 0
    unknown = list(frames.eval('HogHealsFrames.Compat.unknownEvents').keys())
    assert "UNIT_HEALTH_FREQUENT" in unknown


def test_header_children_survive_unknown_event(frames):
    frames.execute('MockUnknownEvents.UNIT_HEALTH_FREQUENT = true; wipe(HogHeals.errors); HogHealsFrames.Headers.Apply("solo")')
    assert frames.eval('#HogHeals.errors') == 0
    assert frames.eval('HogHealsPartyHeaderUnitButton1.health._value') == 100


def test_no_font_string_is_created_without_a_font():
    bad = []
    for f in list(ROOT.glob("HogHeals*/*.lua")) + list(ROOT.glob("HogHeals*/Elements/*.lua")) + list(ROOT.glob("HogHeals/Core/*.lua")):
        for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            if "CreateFontString(" in line and "GameFont" not in line:
                bad.append(f"{f.name}:{n}")
    assert bad == []


def test_strict_font_client_button_and_hud(frames):
    frames.execute('MockState.strictFonts = true; wipe(HogHeals.errors)')
    frames.execute('HH_f = HogHealsFrames.UnitButton.Create("HHFontBtn", UIParent); HH_f.name:SetText("x"); HH_f.healthText:SetText("y"); HH_f.shieldText:SetText("z")')
    assert frames.eval('#HogHeals.errors') == 0


def test_aura_elements_use_the_shim_not_the_removed_global():
    for name in ("Dispel.lua", "MissingBuffs.lua", "MyShield.lua"):
        src = (ROOT / "HogHeals_Frames" / "Elements" / name).read_text(encoding="utf-8")
        assert not re.search(r"(?<![\w.])UnitAura\(", src), name


def test_aura_shim_falls_back_to_c_unitauras(frames):
    frames.execute('HH_saved = UnitAura; UnitAura = nil; C_UnitAuras = { GetAuraDataByIndex = function(u, i, f) if i == 1 then return { name = "Curse of Pain", icon = 136, applications = 2, dispelName = "Curse", expirationTime = 9, sourceUnit = "boss1" } end end }')
    try:
        r = frames.eval('{ HogHealsFrames.Compat.UnitAura("player", 1, "HARMFUL") }')
        assert list(r.values()) == ["Curse of Pain", 136, 2, "Curse", 0, 9, "boss1"] or r[1] == "Curse of Pain" and r[4] == "Curse" and r[7] == "boss1"
        assert frames.eval('HogHealsFrames.Compat.UnitAura("player", 2, "HARMFUL")') is None
    finally:
        frames.execute('UnitAura = HH_saved; C_UnitAuras = nil')


def test_aura_elements_blocked_on_secret_clients(frames):
    frames.execute('MockSetSecrets(true); HogHealsFrames.Compat.Init()')
    for el in ("missingBuffs", "myShield"):
        assert frames.eval(f'HogHealsFrames.Compat.Blocked("{el}")') is not None, el
    assert frames.eval('HogHealsFrames.Compat.Blocked("dispel")') is None     # rebuilt on canActivePlayerDispel (test_dispel_rebuild)
