# Edit mode moves Blizzard's buff / debuff frames and remembers where (HogTronUI/Core/EditMode.lua, EM.BLIZZARD).
# Sean 2026-11-04: "I also can't move buffs and debuffs up on the top right next to the map when I go into edit mode."
from test_edit_mode import ed, errors  # noqa: F401 (fixture)

FRAMES = '''
BuffFrame = CreateFrame("Frame", "BuffFrame", UIParent)
BuffFrame:SetSize(300, 60)
BuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -10)
DebuffFrame = CreateFrame("Frame", "DebuffFrame", UIParent)
DebuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -80)
DebuffFrame:Hide()
'''


def test_buffs_get_a_box_that_moves_the_frame_and_remembers_the_spot(ed):
    ed.execute(FRAMES + 'HogHeals.db.profile.edit.snap = false; HogHeals:SlashCommand("unlock")')
    b = "HogHeals.EditMode.boxes['blizzard:BuffFrame']"
    assert ed.eval(f"{b}:IsShown()") is True and ed.eval(f"{b}._points[1][2] == BuffFrame") is True
    assert ed.eval(f"{b}.label._text") == "Buffs"
    assert ed.eval("HogHeals.EditMode.boxes['blizzard:DebuffFrame']") is None        # hidden frame: no box
    ed.execute(f'{b}:GetScript("OnDragStart")({b})')
    assert ed.eval("BuffFrame._moving") is True
    ed.execute(f'BuffFrame._points = {{ {{ "TOPRIGHT", UIParent, "TOPRIGHT", -320, -40 }} }}; {b}:GetScript("OnDragStop")({b})')
    assert ed.eval("BuffFrame._moving") is False
    saved = "HogHeals.db.profile.edit.blizzard.BuffFrame"
    assert ed.eval(f"{saved}.point") == "TOPRIGHT" and ed.eval(f"{saved}.x") == -320 and ed.eval(f"{saved}.y") == -40
    # login / profile: the saved spot goes back on, behind Blizzard's own layout
    ed.execute("BuffFrame:ClearAllPoints(); BuffFrame:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', -200, -10)")
    assert ed.eval("HogHeals.EditMode.ApplyBlizzard()") == 1
    assert ed.eval("BuffFrame._points[1][4]") == -320 and ed.eval("BuffFrame._points[1][5]") == -40
    ed.execute("BuffFrame:ClearAllPoints(); HogHeals.modules.EditMode:OnProfileChanged()")
    assert ed.eval("BuffFrame._points[1][4]") == -320
    # the debuff frame shown later gets its box on the next unlock
    ed.execute('HogHeals:SlashCommand("lock"); DebuffFrame:Show(); HogHeals:SlashCommand("unlock")')
    assert ed.eval("HogHeals.EditMode.boxes['blizzard:DebuffFrame'].label._text") == "Debuffs"
    assert errors(ed) == []


def test_nothing_saved_means_nothing_touched(ed):
    ed.execute(FRAMES)
    assert ed.eval("HogHeals.EditMode.ApplyBlizzard()") == 0
    assert ed.eval("BuffFrame._points[1][4]") == -200
    ed.execute("HogHeals.db.profile.edit.blizzard = { Nope = { point = 'CENTER', x = 1, y = 2 }, BuffFrame = { point = 'TOP' } }")
    assert ed.eval("HogHeals.EditMode.ApplyBlizzard()") == 0                         # a missing frame or a half record: skipped
    assert errors(ed) == []
