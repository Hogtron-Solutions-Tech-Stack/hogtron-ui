# In game (Forever beta, in combat): the whole unit frame turned solid pink. aggroBorder was a texture with
# SetAllPoints at 80% red: a FILL, not a border. dispelBorder had the same construction.

def test_aggro_and_dispel_borders_are_edges_not_fills(frames):
    frames.execute('HH_b = HogHealsFrames.UnitButton.Create("HHBorderBtn", UIParent)')
    for name in ("aggroBorder", "dispelBorder"):
        b = f'HH_b.{name}'
        assert frames.eval(f'#{b}.edges') == 4, name
        assert frames.eval(f'{b}.fill') is None, name
        for i in (1, 2, 3, 4):
            pts = list(frames.eval(f'{b}.edges[{i}]._points').values())
            assert not any(list(p.values())[0] == "ALL" for p in pts), (name, i)
        assert frames.eval(f'{b}:GetParent() == HH_b.overlay'), name


def test_border_api_fans_out_to_all_edges(frames):
    frames.execute('HH_b = HogHealsFrames.UnitButton.Create("HHBorderBtn2", UIParent); HH_b.aggroBorder:SetColorTexture(0.85, 0.2, 0.2, 0.8); HH_b.aggroBorder:Show()')
    assert frames.eval('HH_b.aggroBorder:IsShown()') is True
    assert all(frames.eval(f'HH_b.aggroBorder.edges[{i}]._shown') for i in (1, 2, 3, 4))
    assert frames.eval('HH_b.aggroBorder.edges[3]._color[1]') == 0.85
    frames.execute('HH_b.aggroBorder:Hide()')
    assert frames.eval('HH_b.aggroBorder:IsShown()') is False
    assert not any(frames.eval(f'HH_b.aggroBorder.edges[{i}]._shown') for i in (1, 2, 3, 4))
    frames.execute('HH_b.aggroBorder:SetShown(true)')
    assert frames.eval('HH_b.aggroBorder:IsShown()') is True
