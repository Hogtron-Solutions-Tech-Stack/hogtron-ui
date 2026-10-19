import pytest


@pytest.fixture
def btn(frames):
    frames.execute('''
      MockUnits.party1 = { name = "Zugzug", class = "PRIEST", health = 40, maxHealth = 100, power = 50, maxPower = 100, guid = "Player-1" }
      HH_b = HogHealsFrames.UnitButton.Create("HogHealsElBtn", UIParent)
      HH_b:SetAttribute("unit", "party1")
      HogHealsFrames.UnitButton.OnAttributeChanged(HH_b, "unit", "party1")
    ''')
    return frames


def upd(f, name):
    f.execute(f'HogHealsFrames.Elements.{name}.Update(HH_b, "party1")')


def test_health_values_and_class_colour(btn):
    upd(btn, "health")
    assert btn.eval('HH_b.health:GetValue()') == 40
    assert list(btn.eval('{HH_b.health:GetMinMaxValues()}').values()) == [0, 100]
    r, g, b = list(btn.eval('{HH_b.health:GetStatusBarColor()}').values())[:3]
    assert (r, g, b) == (1, 1, 1)  # PRIEST class colour


def test_health_deficit_mode_gradient(btn):
    btn.execute('HogHeals.db.profile.frames.appearance.healthMode = "deficit"')
    upd(btn, "health")
    r, g, b = list(btn.eval('{HH_b.health:GetStatusBarColor()}').values())[:3]
    assert r > g  # 40% health -> reddish


def test_health_text_modes(btn):
    btn.execute('HogHeals.db.profile.frames.appearance.healthText = "percent"'); upd(btn, "health")
    assert btn.eval('HH_b.healthText:GetText()') == "40%"
    btn.execute('HogHeals.db.profile.frames.appearance.healthText = "deficit"'); upd(btn, "health")
    assert btn.eval('HH_b.healthText:GetText()') == "-60"
    btn.execute('HogHeals.db.profile.frames.appearance.healthText = "none"'); upd(btn, "health")
    assert btn.eval('HH_b.healthText:GetText()') == ""


def test_health_state_text(btn):
    btn.execute('MockUnits.party1.dead = true'); upd(btn, "health")
    assert btn.eval('HH_b.healthText:GetText()') == "Dead"
    btn.execute('MockUnits.party1.dead = false; MockUnits.party1.ghost = true'); upd(btn, "health")
    assert btn.eval('HH_b.healthText:GetText()') == "Ghost"
    btn.execute('MockUnits.party1.ghost = false; MockUnits.party1.connected = false'); upd(btn, "health")
    assert btn.eval('HH_b.healthText:GetText()') == "Offline"


def test_power_hidden_for_non_mana_when_healer_only(btn):
    btn.execute('MockUnits.party1.powerType = "RAGE"; MockUnits.party1.class = "WARRIOR"'); upd(btn, "power")
    assert btn.eval('HH_b.power:IsShown()') is False
    btn.execute('MockUnits.party1.powerType = "MANA"; MockUnits.party1.class = "PRIEST"'); upd(btn, "power")
    assert btn.eval('HH_b.power:IsShown()') is True
    assert btn.eval('HH_b.power:GetValue()') == 50


def test_name_truncation(btn):
    btn.execute('MockUnits.party1.name = "Hognificentlylong"; HogHeals.db.profile.frames.appearance.nameLength = 8'); upd(btn, "name")
    assert btn.eval('HH_b.name:GetText()') == "Hognific"


def test_range_alpha(btn):
    btn.execute('MockUnits.party1.inRange = false'); upd(btn, "range")
    assert btn.eval('HH_b:GetAlpha()') == 0.4
    btn.execute('MockUnits.party1.inRange = true'); upd(btn, "range")
    assert btn.eval('HH_b:GetAlpha()') == 1


def test_aggro_border(btn):
    btn.execute('MockUnits.party1.threat = 3'); upd(btn, "aggro")
    assert btn.eval('HH_b.aggroBorder:IsShown()') is True
    btn.execute('MockUnits.party1.threat = 0'); upd(btn, "aggro")
    assert btn.eval('HH_b.aggroBorder:IsShown()') is False


def test_raid_icon(btn):
    btn.execute('MockUnits.party1.raidIcon = 8'); upd(btn, "raidIcon")
    assert btn.eval('HH_b.raidIcon:IsShown()') is True
    btn.execute('MockUnits.party1.raidIcon = nil'); upd(btn, "raidIcon")
    assert btn.eval('HH_b.raidIcon:IsShown()') is False


def test_status_icons(btn):
    btn.execute('MockUnits.party1.readyCheck = "waiting"'); upd(btn, "statusIcons")
    assert btn.eval('HH_b.statusIcon:IsShown()') is True and btn.eval('HH_b.statusIcon.kind') == "readyCheck"
    btn.execute('MockUnits.party1.readyCheck = nil; MockUnits.party1.incomingRes = true'); upd(btn, "statusIcons")
    assert btn.eval('HH_b.statusIcon.kind') == "res"
    btn.execute('MockUnits.party1.incomingRes = false; MockUnits.party1.incomingSummon = true'); upd(btn, "statusIcons")
    assert btn.eval('HH_b.statusIcon.kind') == "summon"
    btn.execute('MockUnits.party1.incomingSummon = false; MockUnits.party1.leader = true'); upd(btn, "statusIcons")
    assert btn.eval('HH_b.statusIcon.kind') == "leader"
    btn.execute('MockUnits.party1.leader = false'); upd(btn, "statusIcons")
    assert btn.eval('HH_b.statusIcon:IsShown()') is False


def test_elements_registered_in_order(frames):
    order = list(frames.eval('HogHealsFrames.ElementOrder').values())
    for name in ["health", "power", "name", "range", "aggro", "raidIcon", "statusIcons"]:
        assert name in order



# ---------------------------------------------------------------- the client refusing auras (Sean 2026-10-17, in a party)
# "Auras cannot be accessed when secret while tainted by 'HogHeals_Frames'" x9: clear the element, count, log once.
def test_an_aura_refusal_clears_the_element_counts_and_logs_once(btn):
    btn.execute("""
      wipe(HogHeals.errors)
      HH_hid = 0
      local el = HogHealsFrames.Elements.buffs
      HH_origUpdate, HH_origHide = el.Update, el.Hide
      el.Update = function() error("GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'HogHeals_Frames'") end
      el.Hide = function() HH_hid = HH_hid + 1 end
      for i = 1, 3 do HogHealsFrames.UnitButton.UpdateElement(HH_b, "buffs") end
      el.Update, el.Hide = HH_origUpdate, HH_origHide
    """)
    assert btn.eval("HH_hid") == 3                                                   # cleared each time: no stale icons
    msgs = [e["msg"] for e in btn.eval("HogHeals.errors").values()]
    assert len([m for m in msgs if "refused this unit's auras" in m]) == 1           # logged once
    assert btn.eval("HogHealsFrames.UnitButton.auraRefused.buffs") == 3
    assert "buffs=3" in btn.eval("HogHeals.db.global.diag.frames.auraRefused")


def test_any_other_element_error_is_still_logged_every_time(btn):
    btn.execute("""
      wipe(HogHeals.errors)
      local el = HogHealsFrames.Elements.buffs
      local orig = el.Update
      el.Update = function() error("something else broke") end
      HogHealsFrames.UnitButton.UpdateElement(HH_b, "buffs")
      el.Update = orig
    """)
    assert any("something else broke" in e["msg"] for e in btn.eval("HogHeals.errors").values())


# ---------------------------------------------------------------- which aura reader answers instead (probe, 2026-10-18)
def test_a_refusal_records_what_every_other_aura_reader_gives_back(btn):
    btn.execute("""
      MockSetSecrets(true)
      local refuse = function() error("GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'HogHeals_Frames'") end
      C_UnitAuras = {
        GetAuraDataByIndex = refuse,
        GetUnitAuras = function(u, f) return { { name = MockSecret("Corruption"), dispelName = MockSecret("Magic"), auraInstanceID = 7 } } end,
        GetAuraSlots = function(u, f) return nil, 3 end,
        GetAuraDataBySlot = function(u, s) return { name = MockSecret("Corruption"), auraInstanceID = 7 } end,
        GetDebuffDataByIndex = refuse,
      }
      local el = HogHealsFrames.Elements.debuffs
      HH_orig = el.Update
      el.Update = refuse
      HogHealsFrames.UnitButton.UpdateElement(HH_b, "debuffs")
      HogHealsFrames.UnitButton.UpdateElement(HH_b, "debuffs")      -- rate-limited: still one record
      el.Update = HH_orig
    """)
    recs = btn.eval("HogHeals.db.global.diag.auraReaders")
    assert len(recs) == 1
    lines = list(recs[1]["lines"].values())
    text = " || ".join(lines)
    assert "GetAuraDataByIndex: ERR" in text and "GetDebuffDataByIndex: ERR" in text
    assert "GetUnitAuras: ok table(1)" in text
    assert "GetAuraDataBySlot: ok table(2)" in text and "name=secret" in text
    assert "GetAuraSlots: ok 2 value(s), first slot number" in text
    assert recs[1]["unit"] == "party1" and recs[1]["filter"] == "HARMFUL"


def test_the_probe_never_runs_more_than_its_session_cap(btn):
    btn.execute("""
      C_UnitAuras = { GetAuraDataByIndex = function() return nil end }
      local C = HogHealsFrames.Compat
      for i = 1, 12 do MockAdvance(61); C.ProbeAuraReaders("party1", "HARMFUL") end
    """)
    assert btn.eval("HogHealsFrames.Compat.probes") == 5
    assert len(btn.eval("HogHeals.db.global.diag.auraReaders")) == 5



# ---------------------------------------------------------------- by instance id (probe, 2026-10-18 second round)
# First data: every index / slot reader refused in combat. The probe now also tries the instance-id readers with an id
# taken from the unit's last UNIT_AURA payload, and lists the client's whole C_UnitAuras once.
def test_the_probe_tries_the_instance_id_readers_with_an_id_from_the_last_aura_event(btn):
    btn.execute("""
      MockSetSecrets(true)
      local refuse = function() error("GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'HogHeals_Frames'") end
      C_UnitAuras = {
        GetAuraDataByIndex = refuse, GetUnitAuras = refuse, GetDebuffDataByIndex = refuse,
        GetAuraDataByAuraInstanceID = function(u, id) if id ~= 42 then return nil end return { icon = MockSecret(136207), auraInstanceID = 42 } end,
        IsAuraFilteredOutByInstanceID = function(u, id, f) return id == 42 and false end,
      }
      C_Secrets = { ShouldAurasBeSecret = function() return true end }
      canaccesssecrets = function() return false end
      MockFire("UNIT_AURA", "party1", { addedAuras = { { auraInstanceID = 42, name = MockSecret("Corruption") } } })
      MockFire("UNIT_AURA", "target", { addedAuras = { { auraInstanceID = 9 } } })          -- not a group unit: ignored
      HogHealsFrames.Compat.ProbeAuraReaders("party1", "HARMFUL")
    """)
    text = " || ".join(btn.eval("HogHeals.db.global.diag.auraReaders[1].lines").values())
    assert "last UNIT_AURA payload: table(1) addedAuras=table" in text
    assert "instance id from it: 42" in text
    assert "GetAuraDataByAuraInstanceID: ok table(2) auraInstanceID=number icon=secret" in text
    assert "IsAuraFilteredOutByInstanceID: ok boolean" in text
    assert "GetUnitAuraInstanceIDs: absent" in text
    assert "canaccesssecrets: ok boolean" in text and "C_Secrets.ShouldAurasBeSecret: ok boolean" in text
    assert "C_UnitAuras: GetAuraDataByAuraInstanceID,GetAuraDataByIndex,GetDebuffDataByIndex,GetUnitAuras,IsAuraFilteredOutByInstanceID" in text
    assert btn.eval("HogHealsFrames.Compat.lastAuraInfo.target") is None


def test_ids_come_from_updated_ids_too_and_hidden_ones_are_never_used(btn):
    C = "HogHealsFrames.Compat"
    assert btn.eval(f"{C}.AuraIDFrom({{ updatedAuraInstanceIDs = {{ 17, 18 }} }})") == 17
    assert btn.eval(f"{C}.AuraIDFrom({{ addedAuras = {{ {{ auraInstanceID = MockSecret(5) }} }}, updatedAuraInstanceIDs = {{ 6 }} }})") == 6
    assert btn.eval(f"{C}.AuraIDFrom(MockSecret({{}}))") is None and btn.eval(f"{C}.AuraIDFrom(nil)") is None
    assert btn.eval(f"{C}.AuraIDFrom({{ addedAuras = MockSecret({{ {{ auraInstanceID = 3 }} }}) }})") is None


def test_the_listener_stops_once_the_probe_has_its_records(btn):
    btn.execute("""
      C_UnitAuras = { GetAuraDataByIndex = function() return nil end }
      local C = HogHealsFrames.Compat
      for i = 1, 6 do MockAdvance(61); C.ProbeAuraReaders("party1", "HARMFUL") end
      MockFire("UNIT_AURA", "party2", { addedAuras = {} })
    """)
    assert btn.eval("HogHealsFrames.Compat.lastAuraInfo.party2") is None
    assert btn.eval("next(HogHealsFrames.Compat.auraNotes._events or {}) == nil") is True
