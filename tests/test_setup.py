"""The suite-wide setup guide (HogHeals/Core/Setup.lua). Sean 2026-10-15: "update the startup wizard ... a lot of
options to turn things on or off ... really step them through the whole setup process and settings"."""
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
S = "HogHeals.Setup"


def all_modules():
    mods = sorted(p.name for pat in ("HogHeals*", "HogTron*") for p in ROOT.glob(pat) if p.is_dir())
    mods.remove("HogTronUI")
    return ["HogTronUI"] + mods


@pytest.fixture
def full(lua):
    for m in all_modules():
        lua.load_addon(m)
    lua.player_login()
    lua.execute('wipe(HogHeals.errors)')
    return lua


def lst(v):
    return list(v.values()) if v is not None and hasattr(v, "values") else []


def errors(lua):
    return [e["msg"] for e in lst(lua.eval('HogHeals.errors'))]


def steps(lua):
    return [s["key"] for s in lst(lua.eval(f'{S}.Visible()'))]


# ------------------------------------------------------------------ opening
def test_opens_by_itself_on_a_new_profile_after_login(full):
    assert not full.eval(f'{S}.open')
    full.execute('MockAdvance(5)')
    assert full.eval(f'{S}.open') and full.eval('HogHealsPanel:IsShown()')
    assert full.eval('HogHeals.Panel.selected') == "welcome"


def test_not_in_combat_and_not_twice(lua):
    for m in all_modules():
        lua.load_addon(m)
    lua.player_login()
    lua.execute('MockState.inCombat = true; MockAdvance(5)')
    assert not lua.eval(f'{S}.open')


def test_a_profile_that_did_the_old_wizard_gets_a_chat_line_not_the_window(lua):
    for m in all_modules():
        lua.load_addon(m)
    lua.player_login()
    lua.execute('HogHeals.db.profile.wizardDone = true; HogHeals.db.profile.setupVersion = nil; MockLog.chat = {}; MockAdvance(5)')
    assert not lua.eval(f'{S}.open')
    assert any("/hh setup" in l for l in lst(lua.eval('MockLog.chat')))
    lua.execute('MockLog.chat = {}; MockFire("PLAYER_LOGIN"); MockAdvance(5)')
    assert not any("/hh setup" in l for l in lst(lua.eval('MockLog.chat')))           # once


def test_slash_setup_and_wizard_and_options_button_all_open_the_guide(full):
    for cmd in ('HogHeals:SlashCommand("setup")', 'HogHeals:SlashCommand("wizard")', 'HogHeals:RunWizard()'):
        full.execute(f'{S}.open = false; if HogHealsPanel then HogHealsPanel:Hide() end; {cmd}')
        assert full.eval(f'{S}.open') and full.eval('HogHeals.Panel.selected') == "welcome"


# ------------------------------------------------------------------ the pages
def test_every_part_has_a_page_in_order(full):
    want = ["welcome", "look", "modules", "frames", "bindings", "units", "hud", "bars", "plates", "quests", "dungeons", "chatskin"]
    if (ROOT / "HogTron_Awards").is_dir():
        want.append("awards")                                # its page shows when the module is installed
    assert steps(full) == want + ["done"]


def test_a_missing_module_skips_its_page(lua):
    lua.load_addon("HogTronUI")
    lua.load_addon("HogHeals_Frames")
    lua.player_login()
    keys = steps(lua)
    assert "plates" not in keys and "bars" not in keys and "frames" in keys and keys[0] == "welcome" and keys[-1] == "done"
    t = lua.eval(f'{S}.Table().args.modules.args')                 # the parts page lists only what is installed
    assert "plates_enabled" not in t.keys() and "units_enabled" not in t.keys()


def test_every_page_renders_with_back_next_and_a_step_count(full):
    full.execute(f'{S}.Open()')
    n = len(steps(full))
    for i in range(1, n + 1):
        full.execute(f'{S}.Go({i})')
        key = full.eval('HogHeals.Panel.selected')
        args = full.eval(f'{S}.Table().args.{key}.args')
        assert args["navHead"]["name"].startswith(f"Step {i} of {n}: ")
        assert args["navHead"]["order"] < 0                              # at the top, never scrolled away
        assert (args["back"] is not None) == (i > 1)
        assert (args["next"] is not None) == (1 < i < n)              # welcome has its own two buttons; done has none
    assert errors(full) == []


def test_lots_of_switches(full):
    t = full.eval(f'{S}.Table().args')
    count = 0
    for key in steps(full):
        for opt in lst(t[key]["args"]):
            if opt["type"] in ("toggle", "select", "range"):
                count += 1
    assert count >= 80


def test_every_setting_the_guide_points_at_exists(full):
    src = (ROOT / "HogTronUI" / "Core" / "Setup.lua").read_text(encoding="utf-8")
    paths = set(re.findall(r'(?:toggle|choose|range)\("([a-zA-Z0-9_.]+)"', src))
    assert len(paths) > 60
    missing = []
    for p in sorted(paths):
        if p.startswith("awards."):
            continue                                         # HogTron_Awards lives on its own branch for now
        # read through the live profile, exactly as the guide does (AceDB resolves "**" defaults such as bars.list)
        v = full.eval(f'HogHeals.Setup.Get("{p}")')
        if v is None:
            missing.append(p)
    assert missing == []


# ------------------------------------------------------------------ switches do the real thing
def test_a_switch_writes_the_real_setting_and_repaints(full):
    full.execute(f'{S}.Open(); {S}.Go(9)')
    assert full.eval('HogHeals.Panel.selected') == "plates"
    full.execute('HH_refreshed = 0; local P = HogHealsPlates.Plates; local orig = P.Refresh; P.Refresh = function(...) HH_refreshed = HH_refreshed + 1 return orig(...) end')
    full.execute(f'{S}.Table().args.plates.args.target.set(nil, "brackets")')
    assert full.eval('HogHeals.db.profile.plates.target.style') == "brackets"
    assert full.eval('HH_refreshed') >= 1
    full.execute(f'{S}.Table().args.plates.args.die.set(nil, false)')
    assert full.eval('HogHeals.db.profile.plates.die.enabled') is False
    assert errors(full) == []


def test_reload_marked_switch_shows_the_reload_note(full):
    assert not full.eval(f'{S}.pendingReload')
    full.execute(f'{S}.Table().args.modules.args.bars_enabled.set(nil, false)')
    assert full.eval('HogHeals.db.profile.bars.enabled') is False and full.eval(f'{S}.pendingReload') is True
    note = full.eval(f'{S}.Table().args.done.args.reloadNote.name')()
    assert "reload" in note


def test_frames_preset_and_binding_and_gear_choices_apply(full):
    full.execute(f'local a = {S}.Table().args.frames.args; a.preset.set(nil, "large")')
    assert full.eval('HogHeals.db.profile.frames.layouts.party.width') > full.eval('HogHeals.defaults.profile.frames.layouts.party.width')
    full.execute(f'{S}.Table().args.bindings.args.keys.set(nil, "none")')
    assert full.eval('#HogHealsFrames.ClickCast.bindings') == 0
    full.execute(f'{S}.Table().args.dungeons.args.role.set(nil, "caster")')
    assert full.eval('HogHeals.db.char.atlas.role') == "caster"


def test_click_layout_buttons_drive_the_click_cast_grid(full):
    full.execute(f'{S}.Table().args.bindings.args.clickNone.func()')
    assert full.eval('next(HogHealsFrames.ClickGrid.slots) == nil')
    full.execute(f'{S}.Table().args.bindings.args.clickSuggest.func()')
    assert full.eval('HogHealsFrames.ClickGrid.slots["LEFT:SHIFT"] ~= nil')


# ------------------------------------------------------------------ the two ways through + finish
def test_quick_start_jumps_to_the_end_with_recommended_settings(full):
    full.execute(f'{S}.Open(); {S}.Table().args.welcome.args.quick.func()')
    assert full.eval('HogHeals.Panel.selected') == "done"


def test_finish_saves_and_closes(full):
    full.execute(f'{S}.Open(); {S}.Go(99)')
    assert full.eval('HogHeals.Panel.selected') == "done"
    full.execute(f'{S}.Table().args.done.args.finish.func()')
    assert full.eval('HogHeals.db.profile.wizardDone') is True and full.eval('HogHeals.db.profile.setupVersion') == 2
    assert not full.eval('HogHealsPanel:IsShown()')
    full.execute('MockFire("PLAYER_LOGIN"); MockAdvance(5)')
    assert not full.eval(f'{S}.open')                         # never pops up again


def test_old_frames_wizard_finish_still_works(full):
    full.execute('local W = HogHealsFrames.Wizard; local w = W.New("PRIEST"); w.answers = { preset = "compact", bindings = "none", gear = "melee" }; W.Finish(w)')
    assert full.eval('HogHeals.db.profile.frames.layouts.party.width') < full.eval('HogHeals.defaults.profile.frames.layouts.party.width')
    assert full.eval('HogHeals.db.char.atlas.role') == "melee" and full.eval('HogHeals.db.profile.wizardDone') is True


def test_walk_me_through_it_goes_to_the_first_real_page(full):
    # Sean 2026-10-16 in game: "Walk me through it also doesn't do anything" - it went to step 1, the welcome page itself
    full.execute(f'{S}.Open(); {S}.Table().args.welcome.args.walk.func()')
    assert full.eval('HogHeals.Panel.selected') == "look"


def test_step_names_fit_the_sidebar(full):
    for s in lst(full.eval(f'{S}.Visible()')):
        assert len(s["title"]) <= 18, s["title"]                  # "13. " + title must fit the 170 px sidebar


def test_a_page_without_tabs_has_no_empty_tab_row(full):
    full.execute(f'{S}.Open(); {S}.Go(2)')
    assert full.eval('#HogHeals.Panel.tabs') == 0 and full.eval('HogHealsPanel.tabbar:GetHeight()') <= 1
