"""Click-cast grid (HogHeals_Frames/ClickGrid.lua): spellbook picker, rank resolution, per-character seeding,
resurrect-if-dead macros, Clique hand-off, and the options tab / widget that edits it."""
import pytest

from spellbooks import PRIEST_60, PRIEST_NO_REZ, SHAMAN_LOW, SHAMAN_60, boot, to_lua

G = "HogHealsFrames.ClickGrid"


def lst(v):
    return list(v.values()) if v is not None else []


def btn(lua, name="HHGridBtn"):
    lua.execute(f'HH_gb = HogHealsFrames.UnitButton.Create("{name}", UIParent); {G}.Apply(HH_gb)')
    return "HH_gb"


@pytest.fixture
def priest(lua):
    return boot(lua, "PRIEST")


# ---------------------------------------------------------------- picker enumeration (live spellbook, mocked)
def test_scan_groups_every_rank_under_one_spell(priest):
    assert lst(priest.eval(f'{G}.Book().byName["Flash Heal"].ranks')) == [1, 2, 3, 4, 5, 6, 7]
    assert lst(priest.eval(f'{G}.Book().byName["Renew"].ranks')) == list(range(1, 11))
    assert priest.eval(f'{G}.Book().byName["Abolish Disease"].ranks[1]') is None     # unranked spell


def test_picker_lists_helpful_spells_only_no_harmful_no_passive(priest):
    names = [e["name"] for e in lst(priest.eval(f'{G}.PickerEntries()'))]
    assert "Flash Heal" in names and "Power Word: Shield" in names and "Dispel Magic" in names
    assert "Smite" not in names and "Mind Blast" not in names and "Shoot" not in names     # harmful
    assert "Spirit Tap" not in names                                                        # passive
    assert names == sorted(names)


def test_picker_entry_carries_rank_span(priest):
    e = {x["name"]: x for x in lst(priest.eval(f'{G}.PickerEntries()'))}
    assert e["Flash Heal"]["rankText"] == "Rank 1-7"
    assert e["Abolish Disease"]["rankText"] == ""


def test_picker_follows_the_live_spellbook_not_a_list(priest):
    priest.execute(f'MockState.spellbook = {to_lua([("Holy Nova", 6, 0, True, False)])}; MockFire("SPELLS_CHANGED")')
    names = [e["name"] for e in lst(priest.eval(f'{G}.PickerEntries()'))]
    assert names == ["Holy Nova"]


def test_modern_spellbook_api_when_legacy_globals_are_gone(lua):
    boot(lua, "PRIEST", before_login='''
      GetSpellBookItemName = nil
      C_SpellBook = { GetSpellBookItemInfo = function(i)
        local b = { { "Flash Heal", "Rank 1" }, { "Flash Heal", "Rank 2" }, { "Smite", "Rank 1" } }
        local e = b[i] if not e then return nil end
        return { name = e[1], subName = e[2], spellID = 900 + i, iconID = 1, isPassive = false, itemType = 1 }
      end }
      C_Spell.IsSpellHelpful = function(id) return id ~= 903 end
    ''')
    names = [e["name"] for e in lst(lua.eval(f'{G}.PickerEntries()'))]
    assert names == ["Flash Heal"]
    assert lst(lua.eval(f'{G}.Book().byName["Flash Heal"].ranks')) == [1, 2]


# ---------------------------------------------------------------- Highest vs exact rank
def test_highest_rank_casts_the_bare_name(priest):
    r = priest.eval(f'{G}.Resolve({{ spell = "Flash Heal", rank = "highest" }})')
    assert r["known"] and r["highest"] and r["rank"] == 7 and r["cast"] == "Flash Heal"


def test_exact_rank_pins_the_rank(priest):
    r = priest.eval(f'{G}.Resolve({{ spell = "Flash Heal", rank = 3 }})')
    assert r["known"] and not r["highest"] and r["cast"] == "Flash Heal(Rank 3)"


def test_exact_rank_not_learned_is_not_cast(priest):
    r = priest.eval(f'{G}.Resolve({{ spell = "Flash Heal", rank = 9 }})')
    assert not r["known"] and r["missingRank"]
    assert priest.eval(f'{G}.SlotMacro({{ spell = "Flash Heal", rank = 9 }}, "PRIEST")') is None


def test_rank_choices_highest_first_then_descending(priest):
    priest.execute(f'{G}.Pick("LEFT:SHIFT", "Flash Heal")')
    ch = lst(priest.eval(f'{G}.RankChoices("LEFT:SHIFT")'))
    assert ch[0]["key"] == "highest" and "now Rank 7" in ch[0]["label"]
    assert [c["key"] for c in ch[1:]] == [7, 6, 5, 4, 3, 2, 1]


def test_new_rank_learned_upgrades_highest_silently(priest):
    priest.execute(f'{G}.Pick("LEFT:SHIFT", "Flash Heal")')
    priest.execute('table.insert(MockState.spellbook, { "Flash Heal", "Rank 8", helpful = true, castTime = 1500 }); MockFire("LEARNED_SPELL_IN_TAB")')
    vm = priest.eval(f'{G}.ViewModel()')
    cell = lst(lst(vm["rows"])[0]["cells"])[1]
    assert cell["rankText"] == "Highest (8)"
    assert priest.eval(f'{G}.Resolve({G}.slots["LEFT:SHIFT"]).rank') == 8


def test_alternate_spell_upgrades_when_learned(lua):
    boot(lua, "SHAMAN", book=SHAMAN_LOW)
    b = btn(lua)
    assert lua.eval(f'{b}:GetAttribute("shift-macrotext1")') == "/cast [@mouseover,help,nodead] Healing Wave"
    lua.execute(f'MockState.spellbook = {to_lua(SHAMAN_60)}; MockFire("SPELLS_CHANGED")')
    assert lua.eval(f'{b}:GetAttribute("shift-macrotext1")') == \
        "/cast [@mouseover,dead,nocombat] Ancestral Spirit; [@mouseover,help,nodead] Lesser Healing Wave"


def test_set_rank_then_back_to_highest_persists_per_character(priest):
    priest.execute(f'{G}.Pick("LEFT:SHIFT", "Flash Heal"); {G}.SetRank("LEFT:SHIFT", 4)')
    assert priest.eval('HogHealsFramesCharDB.slots["LEFT:SHIFT"].rank') == 4
    priest.execute(f'{G}.SetRank("LEFT:SHIFT", "highest")')
    assert priest.eval('HogHealsFramesCharDB.slots["LEFT:SHIFT"].rank') == "highest"
    assert priest.eval('HogHeals.db.profile.frames.clickGrid') is None      # not in the (shared) profile


# ---------------------------------------------------------------- first-login seeding
def test_first_login_seeds_priest_layout_and_toasts(priest):
    slots = priest.eval('HogHealsFramesCharDB.slots')
    assert slots["LEFT:SHIFT"]["spell"] == "Flash Heal" and slots["LEFT:SHIFT"]["rank"] == "highest"
    assert slots["RIGHT:SHIFT"]["spell"] == "Greater Heal"
    assert slots["MIDDLE:NONE"]["spell"] == "Renew"
    assert slots["LEFT:NONE"] is None and slots["RIGHT:NONE"] is None      # target / menu stay
    assert priest.eval(f'{G}.lastToast') == "HogHeals suggested a healer click-cast layout. Open /hh click-cast to edit."
    assert priest.eval('HogHealsFramesCharDB.seededFor') == "PRIEST"


@pytest.mark.parametrize("cls", ["PALADIN", "DRUID", "SHAMAN"])
def test_first_login_seeds_other_healers(lua, cls):
    boot(lua, cls)
    assert lua.eval('HogHealsFramesCharDB.slots["LEFT:SHIFT"] ~= nil')
    assert lua.eval(f'{G}.lastToast').startswith("HogHeals suggested a healer click-cast layout")


def test_non_healer_gets_empty_grid_and_setup_toast(lua):
    boot(lua, "WARRIOR")
    assert lua.eval('next(HogHealsFramesCharDB.slots) == nil')
    assert lua.eval(f'{G}.lastToast') == "HogHeals: open /hh click-cast to set up click-casting."


def test_existing_character_data_is_not_reseeded(lua):
    boot(lua, "PRIEST", before_login='HogHealsFramesCharDB = { schema = 1, slots = { ["MIDDLE:ALT"] = { spell = "Renew", rank = "highest" } } }')
    assert lua.eval('HogHealsFramesCharDB.slots["LEFT:SHIFT"]') is None
    assert lua.eval(f'{G}.lastToast') is None


def test_lost_character_file_is_restored_from_the_mirror_not_reseeded(priest):
    priest.execute(f'{G}.ClearAll(); {G}.Pick("MIDDLE:ALT", "Renew")')
    priest.execute(f'HogHealsFramesCharDB = nil; {G}.lastToast = nil; {G}.Init()')
    assert priest.eval('HogHealsFramesCharDB.slots["MIDDLE:ALT"].spell') == "Renew"
    assert priest.eval('HogHealsFramesCharDB.slots["LEFT:SHIFT"]') is None
    assert priest.eval(f'{G}.restoredNow') and priest.eval(f'{G}.lastToast') is None


def test_default_files_use_spell_names_never_ranks(frames):
    for cls in ("PRIEST", "PALADIN", "DRUID", "SHAMAN"):
        for d in lst(frames.eval(f'HogHealsFrames.ClickGridDefaults.{cls}')):
            names = lst(d["spell"]) if not isinstance(d["spell"], str) else [d["spell"]]
            assert all("Rank" not in n and "(" not in n for n in names), (cls, names)
            assert d["button"] in ("LEFT", "RIGHT", "MIDDLE", "BUTTON4", "BUTTON5")
            assert not (d["mod"] == "NONE" and d["button"] in ("LEFT", "RIGHT")), cls


# ---------------------------------------------------------------- resurrect if dead
@pytest.mark.parametrize("cls,rez,heal", [
    ("PRIEST", "Resurrection", "Flash Heal"),
    ("PALADIN", "Redemption", "Flash of Light"),
    ("DRUID", "Rebirth", "Regrowth"),
    ("SHAMAN", "Ancestral Spirit", "Lesser Healing Wave"),
])
def test_rez_macro_per_class(lua, cls, rez, heal):
    boot(lua, cls)
    m = lua.eval(f'{G}.SlotMacro({G}.slots["LEFT:SHIFT"], "{cls}")')
    assert m == f"/cast [@mouseover,dead,nocombat] {rez}; [@mouseover,help,nodead] {heal}"


def test_rez_clause_omitted_when_rez_not_learned(lua):
    boot(lua, "PRIEST", book=PRIEST_NO_REZ)
    assert lua.eval(f'{G}.SlotMacro({G}.slots["LEFT:SHIFT"], "PRIEST")') == "/cast [@mouseover,help,nodead] Flash Heal"
    assert lua.eval(f'{G}.ViewModel().rezSpell') is None
    assert lua.eval('#HogHeals.errors') == 0


def test_rez_default_on_for_direct_heal_off_for_instant(priest):
    priest.execute(f'{G}.Pick("MIDDLE:ALT", "Greater Heal"); {G}.Pick("BUTTON4:ALT", "Renew"); {G}.Pick("BUTTON5:ALT", "Resurrection")')
    assert priest.eval(f'{G}.slots["MIDDLE:ALT"].rez') is True
    assert priest.eval(f'{G}.slots["BUTTON4:ALT"].rez') is False
    assert priest.eval(f'{G}.slots["BUTTON5:ALT"].rez') is False        # a rez is not a "direct heal"


def test_rez_checkbox_off_drops_the_clause(priest):
    priest.execute(f'{G}.SetRez("LEFT:SHIFT", false)')
    assert priest.eval(f'{G}.SlotMacro({G}.slots["LEFT:SHIFT"], "PRIEST")') == "/cast [@mouseover,help,nodead] Flash Heal"


def test_exact_rank_inside_rez_macro(priest):
    priest.execute(f'{G}.SetRank("LEFT:SHIFT", 2)')
    assert priest.eval(f'{G}.SlotMacro({G}.slots["LEFT:SHIFT"], "PRIEST")') == \
        "/cast [@mouseover,dead,nocombat] Resurrection; [@mouseover,help,nodead] Flash Heal(Rank 2)"


# ---------------------------------------------------------------- secure attributes
def test_attributes_cover_buttons_and_modifiers(priest):
    b = btn(priest)
    assert priest.eval(f'{b}:GetAttribute("shift-type1")') == "macro"
    assert priest.eval(f'{b}:GetAttribute("shift-type2")') == "macro"
    assert priest.eval(f'{b}:GetAttribute("type3")') == "macro"
    assert priest.eval(f'{b}:GetAttribute("macrotext3")') == "/cast [@mouseover,help,nodead] Renew"
    assert priest.eval(f'{b}:GetAttribute("type4")') == "macro"
    assert priest.eval(f'{b}:GetAttribute("type1")') is None              # plain left stays *type1 = target
    priest.execute(f'{G}.Pick("BUTTON5:META", "Renew")')
    assert priest.eval(f'{b}:GetAttribute("meta-type5")') == "macro"


def test_header_children_get_the_grid(priest):
    priest.execute('MockSetGroup(3, false); HogHealsFrames.Headers.Apply("party")')
    assert priest.eval('HogHealsPartyHeaderUnitButton1:GetAttribute("shift-type1")') == "macro"


def test_edit_in_combat_waits_for_combat_end(priest):
    b = btn(priest)
    priest.execute(f'MockState.inCombat = true; {G}.Pick("MIDDLE:ALT", "Renew")')
    assert priest.eval(f'{b}:GetAttribute("alt-type3")') is None
    priest.execute('MockState.inCombat = false; MockFire("PLAYER_REGEN_ENABLED")')
    assert priest.eval(f'{b}:GetAttribute("alt-macrotext3")') == "/cast [@mouseover,help,nodead] Renew"


def test_clearing_a_slot_removes_its_attributes(priest):
    b = btn(priest)
    priest.execute(f'{G}.Clear("LEFT:SHIFT")')
    assert priest.eval(f'{b}:GetAttribute("shift-type1")') is None
    assert priest.eval(f'{b}:GetAttribute("shift-macrotext1")') is None


def test_no_restricted_snippets_used(priest):
    src = open(__import__("pathlib").Path(__file__).parents[1] / "HogHeals_Frames" / "ClickGrid.lua", encoding="utf-8").read()
    code = "\n".join(l for l in src.splitlines() if not l.strip().startswith("--"))
    assert "SecureHandlerExecute" not in code and "SecureHandlerWrapScript" not in code and "WrapScript" not in code


def test_both_input_layers_coexist_grid_wins_shared_mouse_slot(priest):
    b = btn(priest)
    priest.execute('''HogHealsFrames.ClickCast.SetBindings({
        { key = "1", mod = "", type = "spell", value = "Greater Heal" },
        { key = "BUTTON1", mod = "SHIFT", type = "spell", value = "Heal" } })''')
    # keyboard layer intact
    assert priest.eval(f'{b}:GetAttribute("type-hhkey1")') == "spell"
    assert priest.eval(f'{b}:GetAttribute("spell-hhkey1")') == "Greater Heal"
    # shared mouse slot: grid (applied after the engine) wins
    assert priest.eval(f'{b}:GetAttribute("shift-type1")') == "macro"
    assert "Flash Heal" in priest.eval(f'{b}:GetAttribute("shift-macrotext1")')


# ---------------------------------------------------------------- Clique
def test_clique_detected_disables_grid(lua):
    boot(lua, "PRIEST", before_login='MockState.cliqueLoaded = true')
    b = btn(lua)
    assert lua.eval(f'{G}.controlledBy') == "Clique"
    assert lua.eval(f'{b}:GetAttribute("shift-type1")') is None
    assert lua.eval('HogHealsFramesCharDB') is None                      # not seeded under Clique
    assert lua.eval(f'{G}.ViewModel().disabled') == "Clique detected — HogHeals click-cast disabled"
    assert lua.eval(f'{G}.OpenPicker("LEFT:SHIFT")') is False
    assert lua.eval(f'{G}.Pick("LEFT:SHIFT", "Flash Heal")') is False


def test_clique_tab_text_and_buttons_disabled(lua):
    boot(lua, "PRIEST", before_login='MockState.cliqueLoaded = true')
    tab = lua.eval('HogHealsFrames.module:GetOptions().args.clickcast.args')
    assert "Clique detected" in tab["clique"]["name"]()
    assert tab["clique"]["hidden"]() is False
    assert tab["reset"]["disabled"]() is True


# ---------------------------------------------------------------- options tab + widget
def test_tab_documents_both_layers_and_is_ace_valid(priest):
    tab = priest.eval('HogHealsFrames.module:GetOptions().args.clickcast')
    assert tab["name"] == "Click-cast"
    intro = tab["args"]["intro"]["name"]
    assert "hover-binds" in intro and "Click-cast" in intro and "both fire" in intro
    assert tab["args"]["grid"]["type"] == "description"                   # valid for the Ace fallback dialog
    assert tab["args"]["clique"]["hidden"]() is True


def test_slash_opens_panel_on_click_cast_tab(priest):
    priest.execute('HogHeals:SlashCommand("click-cast")')
    assert priest.eval('HogHeals.Panel.selected') == "Frames"
    assert priest.eval('HogHeals.Panel.selectedTab') == "clickcast"
    assert priest.eval('HogHeals.Panel.controls["Frames.clickcast.grid"].kind') == "widget"
    assert priest.eval('HogHeals.Panel.controls["Frames.clickcast.grid"]:GetHeight()') > 200
    assert priest.eval('#HogHeals.errors') == 0


def test_widget_right_click_picks_and_left_click_edits(priest):
    priest.execute('HogHeals:SlashCommand("click-cast")')
    # row 5 = Button 5, col 4 = Alt: empty slot
    priest.execute('HH_c = HogHealsFrames.ClickGridUI.frame.cells[5][4]; HH_c:GetScript("OnClick")(HH_c, "RightButton")')
    assert priest.eval(f'{G}.ui.pickerFor') == "BUTTON5:ALT"
    assert priest.eval('HogHealsFrames.ClickGridUI.picker:IsShown()')
    rows = priest.eval('HogHealsFrames.ClickGridUI.picker.rows')
    labels = [r.label._text for r in lst(rows) if r._shown]
    assert labels[0].startswith("(empty") and "Abolish Disease" in labels
    idx = labels.index("Abolish Disease") + 1
    priest.execute(f'HH_r = HogHealsFrames.ClickGridUI.picker.rows[{idx}]; HH_r:GetScript("OnClick")(HH_r)')
    assert priest.eval('HogHealsFramesCharDB.slots["BUTTON5:ALT"].spell') == "Abolish Disease"
    assert priest.eval(f'{G}.ui.selected') == "BUTTON5:ALT"
    assert priest.eval('HogHealsFrames.ClickGridUI.frame.editor:IsShown()')


def test_viewmodel_marks_target_and_menu_fallbacks(priest):
    vm = priest.eval(f'{G}.ViewModel()')
    rows = lst(vm["rows"])
    assert lst(rows[0]["cells"])[0]["fallback"] == "Target"
    assert lst(rows[1]["cells"])[0]["fallback"] == "Menu"
    assert [c["label"] for c in lst(vm["columns"])] == ["None", "Shift", "Ctrl", "Alt", "Meta"]


def test_mac_client_labels_meta_as_cmd(lua):
    boot(lua, "PRIEST", before_login='MockState.mac = true')
    assert [c["label"] for c in lst(lua.eval(f'{G}.ViewModel().columns'))][-1] == "Cmd"


def test_clique_suppresses_existing_character_bindings(lua):
    boot(lua, "PRIEST", before_login='''MockState.cliqueLoaded = true
      HogHealsFramesCharDB = { schema = 1, slots = { ["LEFT:SHIFT"] = { spell = "Flash Heal", rank = "highest", rez = true } } }''')
    b = btn(lua)
    assert lua.eval(f'{b}:GetAttribute("shift-type1")') is None
    assert lua.eval(f'{b}:GetAttribute("shift-macrotext1")') is None
    assert lua.eval('HogHealsFramesCharDB.slots["LEFT:SHIFT"].spell') == "Flash Heal"     # kept for later, not deleted
