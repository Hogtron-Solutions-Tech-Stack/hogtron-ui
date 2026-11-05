# Edit mode: the minimap box moves, resizes and comes back (HogTron_Quests/MapSkin.lua Box/ApplyBox + EditMode target).
# Sean 2026-11-04: "I also can't resize the mini map when I go into edit mode like I can with the chat."
from test_edit_mode import ed, errors, target  # noqa: F401 (fixture)


def test_the_minimap_box_moves_and_resizes_and_comes_back_after_apply(ed):
    ed.execute('''
      MinimapCluster = CreateFrame("Frame", "MinimapCluster", UIParent)
      MinimapCluster:SetSize(300, 340)
      MinimapCluster:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -10, -10)
      HogHealsQuests.MapSkin.Apply()
      HogHeals.db.profile.edit.snap = false
      HogHeals:SlashCommand("unlock")
    ''')
    b = "HogHeals.EditMode.boxes['minimap']"
    assert ed.eval(f"{b}:IsShown()") is True and ed.eval(f"{b}._points[1][2] == MinimapCluster") is True
    assert ed.eval(f"{b}.label._text") == "Minimap" and ed.eval("HogHeals.EditMode.grips['minimap']:IsShown()") is True
    ed.execute(f'{b}:GetScript("OnDragStart")({b})')
    assert ed.eval("MinimapCluster._moving") is True
    ed.execute(f'MinimapCluster._points = {{ {{ "TOPRIGHT", UIParent, "TOPRIGHT", -40, -60 }} }}; {b}:GetScript("OnDragStop")({b})')
    assert ed.eval("MinimapCluster._moving") is False
    box = "HogHeals.db.profile.quests.map.box"
    assert ed.eval(f"{box}.point") == "TOPRIGHT" and ed.eval(f"{box}.x") == -40 and ed.eval(f"{box}.y") == -60
    t = target(ed, "minimap")
    ed.execute(f"{t}.resize = HogHeals.EditMode.ResizeFor({t}); HogHeals.EditMode.BeginResize({t})")
    ed.execute("HogHeals.EditMode.ResizeStep(40, -60)")                       # 40 right = wider, 60 down = taller
    assert ed.eval(f"{box}.w") == 340 and ed.eval(f"{box}.h") == 400
    assert ed.eval("MinimapCluster._width") == 340 and ed.eval("MinimapCluster._height") == 400
    ed.execute("HogHeals.EditMode.EndResize()")
    assert ed.eval("HogHeals.EditMode.lastResize") == "minimap"
    # a fresh apply (login, /reload) puts the saved box back
    ed.execute("MinimapCluster:SetSize(300, 340); MinimapCluster:ClearAllPoints(); HogHealsQuests.MapSkin.Apply()")
    assert ed.eval("MinimapCluster._width") == 340 and ed.eval("MinimapCluster._points[1][1]") == "TOPRIGHT"
    assert ed.eval("MinimapCluster._points[1][4]") == -40
    assert errors(ed) == []


def test_a_plain_minimap_without_a_cluster_sizes_the_map_itself(ed):
    ed.execute("MinimapCluster = nil; HogHeals.db.profile.quests.map.box = nil")
    assert ed.eval("HogHealsQuests.MapSkin.Box() == Minimap") is True
    ed.execute("HogHealsQuests.MapSkin.SetBoxSize(260, 200)")
    assert ed.eval("HogHeals.db.profile.quests.map.size") == 200 and ed.eval("Minimap._width") == 200
    assert errors(ed) == []
