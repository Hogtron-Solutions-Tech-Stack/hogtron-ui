# HogTron_Plates/ObjectGlow.lua: the ore vein / herb / chest / quest object / bobber the game picked for the interact
# key glows, tinted by kind (Sean 2026-10-14, from the WoW Forever add-on clip #4 "Lueur"). The cvars live in a real
# table here so "given back" is checked by value, and cursors come back through SetUnitCursorTexture like the client.
import pytest

from test_plates import PLATES, QUESTLOG

G = "HogHealsPlates.ObjectGlow"

GLOW = r'''
CV = { SoftTargetInteract = "1", SoftTargetInteractRange = "10", SoftTargetNameplateInteract = "0", SoftTargetIconGameObject = "0",
       SoftTargetInteractOnlyInRange = "1", nameplateGameObjectMaxDistance = "20" }
ORIGINAL = {}
for k, v in pairs(CV) do ORIGINAL[k] = v end
function GetCVar(k) return CV[k] end
function SetCVar(k, v) if CV[k] == nil then error("unknown cvar " .. k) end CV[k] = tostring(v) end
OBJ = {}
function UnitIsGameObject(u) return OBJ[u] == true end
CURSOR = {}
function SetUnitCursorTexture(tex, unit) local c = CURSOR[unit] if not c then return false end tex:SetTexture(c) return true end
FILEIDS = { ["Interface\\Cursor\\Mine"] = 9001, ["Interface\\Cursor\\UnableMine"] = 9002, ["Interface\\Cursor\\GatherHerbs"] = 9003 }
function GetFileIDFromPath(p) return FILEIDS[p] end
SAMEAS = {}
local plainIsUnit = UnitIsUnit
function UnitIsUnit(a, b) if SAMEAS[a] == b then return true end return plainIsUnit(a, b) end
function Soft(name, cursor, guid, plate)
  OBJ.softinteract = true
  if plate ~= false then MockPlate("softinteract", { name = name, guid = guid or "GameObject-0-1-2-3-1731-99" })
  else MockUnits.softinteract = { name = name, guid = guid or "GameObject-0-1-2-3-1731-99" } end
  CURSOR.softinteract = cursor
  MockFire("PLAYER_SOFT_INTERACT_CHANGED")
end
'''


def boot(lua, extra=""):
    lua.execute(PLATES + GLOW + extra + QUESTLOG)
    lua.load_addon("HogTronUI")
    lua.load_addon("HogTron_Quests")
    lua.load_addon("HogTron_Plates")
    lua.player_login()
    lua.execute("wipe(HogHeals.errors)")
    return lua


@pytest.fixture
def og(lua):
    return boot(lua)


def cv(lua, k):
    return lua.eval(f"CV.{k}")


def shown(lua):
    return lua.eval("HogTronUIObjectGlow ~= nil and HogTronUIObjectGlow:IsShown()") is True


def colour(lua, layer="halo"):
    return list(lua.eval(f"HogTronUIObjectGlow.{layer}._color").values())[:3]


# ================================================================================================ classify (pure)
@pytest.mark.parametrize("cursor,kind,blocked", [
    ("Interface/Cursor/GatherHerbs", "herb", False),
    ("Interface\\Cursor\\Mine.blp", "ore", False),
    ("Interface/Cursor/UnableMine", "ore", True),
    ("UnableGatherHerbs", "herb", True),
    ("Interface/Cursor/QuestInteract", "quest", False),
    ("Interface/Cursor/PickLock", "chest", False),
    ("Interface/Cursor/Fishing", "bobber", False),
    ("cursor-gatherherbs-atlas", "herb", False),
    ("Interface/Cursor/Mail", "other", False),
    ("Interface/Cursor/Interact", "other", False),
])
def test_cursor_decides_the_kind(og, cursor, kind, blocked):
    k, b = og.eval(f'{G}.Classify("{cursor}", nil, false, "Thing")')
    assert (k, b) == (kind, blocked)


def test_the_rest_of_the_classifier(og):
    assert og.eval(f'{G}.Classify("Interface/Cursor/Interact", 35591, false, "Fishing Bobber")')[0] == "bobber"
    assert og.eval(f'{G}.Classify("Interface/Cursor/Pickup", nil, true, "Sack of Candles")')[0] == "quest"
    assert og.eval(f'{G}.Classify("Interface/Cursor/Interact", nil, false, "Battered Chest")')[0] == "chest"
    assert og.eval(f'{G}.Classify(nil, nil, false, "Food Crate")')[0] == "chest"
    assert og.eval(f'{G}.Classify(nil, nil, false, "Iron Strongbox")')[0] == "chest"
    # a mailbox says what it is: never a chest because its name ends in "box"
    assert og.eval(f'{G}.Classify("Interface/Cursor/Mail", nil, false, "Mailbox")')[0] == "other"
    # gathering beats a quest match: a herb you need for a quest is still a herb
    assert og.eval(f'{G}.Classify("Interface/Cursor/GatherHerbs", nil, true, "Peacebloom")')[0] == "herb"
    assert og.eval(f'{G}.Classify(nil, nil, false, "Lever")')[0] == "other"
    assert og.eval(f'{G}.ObjectID("GameObject-0-4170-0-12-35591-0000B1")') == 35591
    assert og.eval(f'{G}.ObjectID("Creature-0-1-2-3-35591-9")') is None
    assert og.eval(f'{G}.ChestName("Boxer Shorts")') is False
    assert og.eval(f'{G}.ChestName("Treasure Chests")') is True


def test_file_ids_from_the_client_map_to_kinds(og):
    assert og.eval(f"{G}.cursorCount") >= 3
    assert og.eval(f"{G}.CursorKind(9001)")[0] == "ore"
    k, b = og.eval(f"{G}.CursorKind(9002)")
    assert (k, b) == ("ore", True)
    assert og.eval(f"{G}.CursorKind(424242)")[0] is None


# ================================================================================================ cvars
def test_cvars_on_at_login_and_originals_remembered(og):
    assert cv(og, "SoftTargetInteract") == "3"
    assert cv(og, "SoftTargetNameplateInteract") == "1"
    assert cv(og, "SoftTargetIconGameObject") == "1"
    assert cv(og, "SoftTargetInteractRange") == "15"
    assert cv(og, "SoftTargetInteractOnlyInRange") == "0"
    assert cv(og, "nameplateGameObjectMaxDistance") == "20"   # the player's wider value is kept
    saved = og.eval("HogHeals.db.global.objectGlow.saved")
    assert saved["SoftTargetInteract"] == "1" and saved["SoftTargetIconGameObject"] == "0"


def test_off_gives_every_value_back_and_forgets(og):
    og.execute('HogHeals:SlashCommand("glow off")')
    for k, v in og.eval("ORIGINAL").items():
        assert cv(og, k) == v, k
    assert og.eval("HogHeals.db.global.objectGlow.saved") is None
    og.execute('HogHeals:SlashCommand("glow on")')
    assert cv(og, "SoftTargetInteract") == "3"


def test_logout_gives_back_but_remembers_and_ours_are_never_taken_for_the_players(og):
    og.execute('MockFire("PLAYER_LOGOUT")')
    assert cv(og, "SoftTargetInteract") == "1"
    assert og.eval("HogHeals.db.global.objectGlow.saved.SoftTargetInteract") == "1"
    # next session (or a crash that skipped the logout): our values are on again, the memory still says the player's
    og.execute(f"{G}.ApplyCVars(); {G}.ApplyCVars()")
    assert cv(og, "SoftTargetInteract") == "3"
    assert og.eval("HogHeals.db.global.objectGlow.saved.SoftTargetInteract") == "1"


def test_never_in_combat_queued_until_it_ends(og):
    og.execute('MockState.inCombat = true; HogHeals:SlashCommand("glow off")')
    assert cv(og, "SoftTargetInteract") == "3"
    assert og.eval(f"{G}.pending") == "restore"
    og.execute('MockState.inCombat = false; MockFire("PLAYER_REGEN_ENABLED")')
    assert cv(og, "SoftTargetInteract") == "1"


def test_apply_in_combat_waits_too(og):
    og.execute('HogHeals:SlashCommand("glow off"); MockState.inCombat = true; HogHeals:SlashCommand("glow on")')
    assert cv(og, "SoftTargetInteract") == "1" and og.eval(f"{G}.pending") == "apply"
    og.execute('MockState.inCombat = false; MockFire("PLAYER_REGEN_ENABLED")')
    assert cv(og, "SoftTargetInteract") == "3"


def test_loading_screen_reset_of_the_object_icon_is_repaired(og):
    og.execute('CV.SoftTargetIconGameObject = "0"; MockFire("PLAYER_ENTERING_WORLD")')
    assert cv(og, "SoftTargetIconGameObject") == "1"


def test_range_from_chat(og):
    og.execute('HogHeals:SlashCommand("glow range 25")')
    assert cv(og, "SoftTargetInteractRange") == "25"
    assert cv(og, "nameplateGameObjectMaxDistance") == "25"


def test_a_cvar_the_client_lacks_is_listed_not_forced(lua):
    boot(lua, extra="CV.SoftTargetInteractOnlyInRange = nil; ORIGINAL.SoftTargetInteractOnlyInRange = nil")
    assert lua.eval("#HogHeals.errors") == 0
    assert any("SoftTargetInteractOnlyInRange" in l for l in lua.eval(f"{G}.Lines()").values())


# ================================================================================================ the glow
def test_herb_glows_green_on_its_own_plate(og):
    og.execute('Soft("Peacebloom", "Interface/Cursor/GatherHerbs")')
    assert shown(og)
    assert og.eval("HogTronUIObjectGlow:GetParent() == NP.softinteract") is True
    assert og.eval(f"{G}.last.kind") == "herb"
    assert colour(og) == pytest.approx([0.35, 0.90, 0.40])
    assert og.eval("HogTronUIObjectGlow.label:GetText()") == "Peacebloom"


def test_file_id_cursor_and_the_grey_cannot_use_yet(og):
    og.execute('Soft("Copper Vein", 9001)')
    assert og.eval(f"{G}.last.kind") == "ore" and colour(og) == pytest.approx([0.95, 0.55, 0.20])
    og.execute('Soft("Tin Vein", 9002)')
    assert og.eval(f"{G}.last.blocked") is True
    assert colour(og) == pytest.approx([0.55, 0.55, 0.60])
    assert og.eval(f"{G}.lastFrame.spark") == 0            # still, no twinkle
    og.execute('HogHeals.db.profile.plates.objectGlow.hideBlocked = true; MockFire("PLAYER_SOFT_INTERACT_CHANGED")')
    assert not shown(og)


def test_quest_object_from_its_tooltip_is_cyan(og):
    og.execute('TT.softinteract = { { leftText = "Sack of Candles", type = 2 }, { leftText = "Kobold Candles: 2/6", type = 8 } }')
    og.execute('Soft("Sack of Candles", "Interface/Cursor/Pickup")')
    assert og.eval(f"{G}.last.kind") == "quest"
    assert colour(og) == pytest.approx([0.13, 0.83, 0.88])


def test_chest_by_name_and_mailbox_stays_dark(og):
    og.execute('Soft("Battered Chest", "Interface/Cursor/Interact")')
    assert shown(og) and og.eval(f"{G}.last.kind") == "chest"
    og.execute('Soft("Mailbox", "Interface/Cursor/Mail")')
    assert not shown(og)                                     # "other" is off by default
    assert og.eval(f"{G}.seen['filtered:other']") == 1
    og.execute('HogHeals.db.profile.plates.objectGlow.kinds.other = true; MockFire("PLAYER_SOFT_INTERACT_CHANGED")')
    assert shown(og) and og.eval(f"{G}.last.kind") == "other"


def test_other_stays_dark_on_a_profile_that_never_had_the_switch(og):
    og.execute('HogHeals.db.profile.plates.objectGlow.kinds = { herb = true }; Soft("Lever", "Interface/Cursor/Interact")')
    assert not shown(og)
    og.execute('Soft("Battered Chest", "Interface/Cursor/Interact")')
    assert shown(og)                                         # a missing key elsewhere means on


def test_each_object_is_judged_on_its_own(og):
    # QuestMobs caches per GUID: a chest seen first must not decide what the quest sack next to it is
    og.execute('Soft("Battered Chest", "Interface/Cursor/Interact", "GameObject-0-1-2-3-2843-3")')
    og.execute('TT.softinteract = { { leftText = "Sack of Candles", type = 2 }, { leftText = "Kobold Candles: 2/6", type = 8 } }')
    og.execute('Soft("Sack of Candles", "Interface/Cursor/Pickup", "GameObject-0-1-2-3-105570-4")')
    assert og.eval(f"{G}.last.kind") == "quest"


def test_bobber_by_object_id(og):
    og.execute('Soft("Fishing Bobber", "Interface/Cursor/Interact", "GameObject-0-1-2-3-35591-77")')
    assert og.eval(f"{G}.last.kind") == "bobber"


def test_a_kind_switched_off_does_not_glow(og):
    og.execute('HogHeals.db.profile.plates.objectGlow.kinds.herb = false; Soft("Peacebloom", "Interface/Cursor/GatherHerbs")')
    assert not shown(og)


def test_nothing_picked_or_an_npc_hides_it(og):
    og.execute('Soft("Peacebloom", "Interface/Cursor/GatherHerbs")')
    og.execute('OBJ.softinteract = false; MockFire("PLAYER_SOFT_INTERACT_CHANGED")')
    assert not shown(og)
    assert og.eval("HogTronUIObjectGlow:GetParent() == UIParent") is True   # never left hanging on a recycled plate


def test_plate_that_arrives_late_and_the_sweep(og):
    og.execute('Soft("Peacebloom", "Interface/Cursor/GatherHerbs", nil, false)')
    assert not shown(og) and og.eval(f"{G}.seen.noPlate") == 1
    # the game hands the object's plate out under a nameplateN token, not "softinteract"
    og.execute('MockPlate("nameplate7", { name = "Peacebloom" }); OBJ.nameplate7 = true; SAMEAS.nameplate7 = "softinteract"')
    og.execute('MockFire("NAME_PLATE_UNIT_ADDED", "nameplate7")')
    assert shown(og) and og.eval(f"{G}.via") == "sweep"
    assert og.eval("HogTronUIObjectGlow:GetParent() == NP.nameplate7") is True
    og.execute('MockFire("NAME_PLATE_UNIT_REMOVED", "nameplate7"); NP.nameplate7 = nil; MockFire("PLAYER_SOFT_INTERACT_CHANGED")')
    assert not shown(og)


def test_object_plates_are_not_skinned_as_unit_plates(og):
    og.execute('MockPlate("nameplate5", { name = "Copper Vein" }); OBJ.nameplate5 = true; MockFire("NAME_PLATE_UNIT_ADDED", "nameplate5")')
    og.execute('MockPlate("nameplate6", { name = "Kobold Vermin" }); MockFire("NAME_PLATE_UNIT_ADDED", "nameplate6")')
    assert og.eval("HogHealsPlates.Plates.active.nameplate5") is None
    assert og.eval("HogHealsPlates.Plates.active.nameplate6") is not None
    assert og.eval("HogHealsPlates.Plates.skips['game object']") == 1


def test_the_glow_never_takes_the_mouse(og):
    og.execute('Soft("Peacebloom", "Interface/Cursor/GatherHerbs")')
    last = og.eval("HogTronUIObjectGlow._last.EnableMouse")
    assert last is not None and list(last.values()) == [False]


def test_animation_frames(og):
    f0 = og.eval(f"{G}.Frame(0, 1, false)")
    f1 = og.eval(f"{G}.Frame(0.25, 1, false)")
    assert f0["scale"] == pytest.approx(0.6) and f1["scale"] == pytest.approx(1.0)
    for t in (0.3, 1.1, 2.0, 5.7):
        fr = og.eval(f"{G}.Frame({t}, 0.9, false)")
        assert 0 < fr["halo"] <= 0.9 and 0 < fr["ring"] <= 0.9 and 0 <= fr["spark"] <= 0.9
        assert (fr["sx"] ** 2 + fr["sy"] ** 2) ** 0.5 == pytest.approx(0.72)
    b = og.eval(f"{G}.Frame(3, 1, true)")
    assert b["spark"] == 0 and b["turn"] == 0
    og.execute(f'Soft("Peacebloom", "Interface/Cursor/GatherHerbs"); {G}.Tick(0.5)')
    assert og.eval(f"{G}.lastFrame.turn") == pytest.approx(0.3)
    # the same object picked again does not restart the lock-on
    og.execute('MockFire("PLAYER_SOFT_INTERACT_CHANGED")')
    assert og.eval(f"{G}.shown.t") == pytest.approx(0.5)


def test_preview_walks_every_kind_then_hands_back(og):
    og.execute(f"{G}.Preview()")
    assert shown(og) and og.eval(f"{G}.shown.kind") == "herb"
    og.execute("MockAdvance(1.6)")
    assert og.eval(f"{G}.shown.kind") == "ore"
    og.execute("MockAdvance(1.6); MockAdvance(1.6); MockAdvance(1.6); MockAdvance(1.6)")
    assert not shown(og) and og.eval(f"{G}.previewing") is False


def test_without_cursor_api_it_still_reads_names(lua):
    boot(lua, extra="SetUnitCursorTexture = nil")
    lua.execute('Soft("Battered Chest", nil)')
    assert lua.eval(f"{G}.last.kind") == "chest"
    assert any("SetUnitCursorTexture" in l for l in lua.eval(f"{G}.Lines()").values())


def test_off_hides_and_options_and_diag(og):
    og.execute('Soft("Peacebloom", "Interface/Cursor/GatherHerbs")')
    og.execute('HogHeals:SlashCommand("glow off")')
    assert not shown(og)
    og.execute('HogHeals:SlashCommand("glow on"); MockFire("PLAYER_SOFT_INTERACT_CHANGED")')
    assert shown(og)
    opts = og.eval("HogHealsPlates.Options.Build()")["args"]["objectGlow"]["args"]
    assert opts["kind_herb"]["type"] == "toggle" and opts["kind_other"]["get"]() is False
    og.execute('HogHeals:SlashCommand("glowdiag")')
    d = og.eval("HogHeals.db.global.diag.objectGlow")
    assert d["last"]["kind"] == "herb"
    assert "object glow: on" in d["lines"][1]
    assert any("object glow" in l for l in og.eval("HogHealsPlates.Plates.Diagnose()").values())
    assert og.eval("#HogHeals.errors") == 0



# ---------------------------------------------------------------- any direction (Sean 2026-10-17)
# "it only shows up if I'm looking directly at it, which kind of defeats the purpose"
def test_the_nearest_object_in_any_direction_is_picked(lua):
    boot(lua, 'CV.SoftTargetInteractArc = "0"; ORIGINAL.SoftTargetInteractArc = "0" ')
    assert lua.eval('CV.SoftTargetInteractArc') == "2"
    assert lua.eval("HogHeals.db.global.objectGlow.saved.SoftTargetInteractArc") == "0"      # the player's, kept
    lua.execute('HogHeals.db.profile.plates.objectGlow.anyDirection = false; HogHealsPlates.ObjectGlow.Apply()')
    assert lua.eval('CV.SoftTargetInteractArc') == "0"
    lua.execute('HogHeals:SlashCommand("glow off")')
    assert lua.eval('CV.SoftTargetInteractArc') == "0"


def test_a_client_without_the_arc_cvar_just_records_it(og):
    assert "SoftTargetInteractArc" in list(og.eval("HogHealsPlates.ObjectGlow.missing").values())


# ================================================================================================ the object's icon
# Sean 2026-10-18 (screenshot: "Ripe Stormapple" over a cyan ring, the game's gear icon under the name): "I don't like
# that the gear is blocked by the text. Can we put the gear inside of the circle". Ours sits in the ring; the game's
# copy is faded (alpha only) while the glow is on its plate, and given back after.
GAME_ICON = '''
function GameIcon(where)   -- the game's icon on the soft-target plate: "frame" (SoftTargetFrame.Icon) | "loose" | nil
  local uf = NP.softinteract.UnitFrame
  if where == "frame" then
    uf.SoftTargetFrame = CreateFrame("Frame", nil, uf)
    uf.SoftTargetFrame.Icon = uf.SoftTargetFrame:CreateTexture(nil, "ARTWORK")
    HH_GI = uf.SoftTargetFrame.Icon
  else
    local holder = CreateFrame("Frame", nil, uf)
    holder:CreateTexture(nil, "BACKGROUND"):SetTexture("Interface/Something/Else")
    HH_GI = holder:CreateTexture(nil, "ARTWORK")
  end
  SetUnitCursorTexture(HH_GI, "softinteract")
  MockFire("PLAYER_SOFT_INTERACT_CHANGED")
end
'''


def label_y(lua):
    return lua.eval("HogTronUIObjectGlow.label._points[1][5]")


def test_the_games_icon_moves_into_the_ring_and_comes_back_after(og):
    og.execute(GAME_ICON + 'Soft("Ripe Stormapple", "Interface/Cursor/Interact"); HogHeals.db.profile.plates.objectGlow.kinds.other = true; GameIcon("frame")')
    assert shown(og)
    assert og.eval("HogTronUIObjectGlow.icon:IsShown()") is True
    assert og.eval("HogTronUIObjectGlow.icon:GetTexture()") == "Interface/Cursor/Interact"     # the same art as the game's
    p = list(og.eval("HogTronUIObjectGlow.icon._points[1]").values())
    assert p[0] == "CENTER" and p[2] == "CENTER" and p[3] == 0 and p[4] == 0                  # dead centre of the ring
    assert og.eval("HogTronUIObjectGlow.icon:GetWidth()") == pytest.approx(og.eval("HogTronUIObjectGlow.ring:GetWidth()") * 0.42)
    assert og.eval("HH_GI:GetAlpha()") == 0 and og.eval(f"{G}.last.icon") == "SoftTargetFrame.Icon"
    assert label_y(og) == 2                                                                   # the name sits on the ring
    og.execute("HH_GI:SetAlpha(1); HogHealsPlates.ObjectGlow.Tick(0.1)")                     # the game puts it back up
    assert og.eval("HH_GI:GetAlpha()") == 0
    og.execute('OBJ.softinteract = nil; MockFire("PLAYER_SOFT_INTERACT_CHANGED")')            # walked away
    assert not shown(og) and og.eval("HH_GI:GetAlpha()") == 1
    assert "game's icon: SoftTargetFrame.Icon" in "".join(og.eval(f"{G}.Lines()").values())
    assert og.eval("HogHeals.errors[1]") is None


def test_a_loose_icon_is_found_by_its_art_and_none_lifts_the_name(og):
    og.execute(GAME_ICON + 'Soft("Peacebloom", "Interface/Cursor/GatherHerbs"); GameIcon("loose")')
    assert og.eval(f"{G}.last.icon") == "search" and og.eval("HH_GI:GetAlpha()") == 0 and label_y(og) == 2
    og.execute('Soft("Silverleaf", "Interface/Cursor/GatherHerbs")')                          # a plate with no game icon
    assert og.eval(f"{G}.last.icon") == "not found"
    assert og.eval("HogTronUIObjectGlow.icon:IsShown()") is True and label_y(og) == 2 + 22   # the name clears the gear


def test_switched_off_leaves_the_games_icon_alone(og):
    og.execute(GAME_ICON + 'HogHeals.db.profile.plates.objectGlow.icon = false; Soft("Peacebloom", "Interface/Cursor/GatherHerbs"); GameIcon("frame")')
    assert shown(og) and og.eval("HogTronUIObjectGlow.icon:IsShown()") is False
    assert og.eval("HH_GI:GetAlpha()") == 1 and og.eval(f"{G}.last.icon") == "off" and label_y(og) == 2 + 22
    og.execute('HogHeals.OptionsTable().args.Plates.args.objectGlow.args.icon.set({}, true)')
    assert og.eval("HogTronUIObjectGlow.icon:IsShown()") is True and og.eval("HH_GI:GetAlpha()") == 0


def test_moving_to_another_object_gives_the_first_plate_its_icon_back(og):
    og.execute(GAME_ICON + 'Soft("Peacebloom", "Interface/Cursor/GatherHerbs"); GameIcon("frame"); HH_FIRST = HH_GI')
    og.execute('Soft("Copper Vein", "Interface/Cursor/Mine"); GameIcon("frame")')
    assert og.eval("HH_FIRST:GetAlpha()") == 1 and og.eval("HH_GI:GetAlpha()") == 0


def test_the_preview_shows_a_sample_icon_per_kind(og):
    og.execute(f"{G}.Preview()")
    assert og.eval("HogTronUIObjectGlow.icon:GetTexture()") == r"Interface\Cursor\GatherHerbs"
    assert og.eval("HogTronUIObjectGlow.icon:IsShown()") is True and label_y(og) == 2
