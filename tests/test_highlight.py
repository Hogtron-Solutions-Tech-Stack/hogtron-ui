# HogHeals_Frames/Elements/Highlight.lua: hover + target marks on the cells (outline / corners / fill / none),
# each with its own style and colour. Sean 2026-10-03: "white outline, red outline, corners". AoE-scope fill is
# off by default from here on.
import pytest


@pytest.fixture
def cells(frames):
    frames.execute('''
      MockUnits.party1 = { name = "Zugzug", class = "PRIEST", health = 40, maxHealth = 100, guid = "Player-1" }
      MockUnits.party2 = { name = "Grok", class = "SHAMAN", health = 90, maxHealth = 100, guid = "Player-2" }
      HH_a = HogHealsFrames.UnitButton.Create("HogHealsHlA", UIParent)
      HH_a:SetAttribute("unit", "party1"); HogHealsFrames.UnitButton.OnAttributeChanged(HH_a, "unit", "party1")
      HH_b = HogHealsFrames.UnitButton.Create("HogHealsHlB", UIParent)
      HH_b:SetAttribute("unit", "party2"); HogHealsFrames.UnitButton.OnAttributeChanged(HH_b, "unit", "party2")
      HH_a:SetSize(90, 60); HH_b:SetSize(90, 60)
      wipe(HogHeals.errors)
    ''')
    return frames


def errors(lua):
    return [e["msg"] for e in lua.eval("HogHeals.errors").values()]


def target(lua, guid):
    if guid is None:
        lua.execute('MockUnits.target = nil; MockFire("PLAYER_TARGET_CHANGED")')
    else:
        lua.execute(f'MockUnits.target = {{ name = "t", class = "PRIEST", guid = "{guid}" }}; MockFire("PLAYER_TARGET_CHANGED")')


def shown(lua, btn, key):
    return lua.eval(f"{btn}.{key} ~= nil and {btn}.{key}:IsShown()")


def enter(lua, btn):
    lua.execute(f"HogHealsFrames.UnitButton.OnEnter({btn})")


def leave(lua, btn):
    lua.execute(f"HogHealsFrames.UnitButton.OnLeave({btn})")


# ---------------------------------------------------------------- defaults

def test_defaults(cells):
    h = cells.eval("HogHeals.db.profile.frames.highlight")
    assert h["hover"]["style"] == "outline" and list(h["hover"]["color"].values()) == [1, 1, 1] and h["hover"]["thick"] == 1
    assert h["target"]["style"] == "corners" and list(h["target"]["color"].values()) == [1, 1, 1] and h["target"]["thick"] == 2
    assert cells.eval("HogHeals.db.profile.frames.indicators.aoeHealing") is False
    assert cells.eval("HogHeals.db.profile.frames.indicators.highlight") is True


# ---------------------------------------------------------------- hover

def test_hover_white_outline_outside_the_rect_on_that_cell_only(cells):
    enter(cells, "HH_a")
    assert shown(cells, "HH_a", "hoverMark") is True
    assert cells.eval("HH_a.hoverMark.style") == "outline"
    top = cells.eval("HH_a.hoverMark.edges[1]")
    assert list(cells.eval("{ HH_a.hoverMark.edges[1]:GetVertexColor() }").values())[:3] == [1, 1, 1]
    assert cells.eval("HH_a.hoverMark.edges[1]:GetHeight()") == 1
    p = list(cells.eval("{ HH_a.hoverMark.edges[1]:GetPoint(1) }").values())
    assert p[0] == "TOPLEFT" and p[3] == -1 and p[4] == 1          # 1 px outside the cell
    assert cells.eval("HH_a.hoverMark.edges[3]:GetWidth()") == 1
    assert all(cells.eval(f"HH_a.hoverMark.corners[{i}]:IsShown()") is False for i in range(1, 9))
    assert cells.eval("HH_b.hoverMark") is None
    leave(cells, "HH_a")
    assert shown(cells, "HH_a", "hoverMark") is False
    assert errors(cells) == []


def test_hover_moves_with_the_mouse(cells):
    enter(cells, "HH_a")
    leave(cells, "HH_a")
    enter(cells, "HH_b")
    assert shown(cells, "HH_a", "hoverMark") is False
    assert shown(cells, "HH_b", "hoverMark") is True


def test_hover_styles(cells):
    cells.execute('HogHeals.db.profile.frames.highlight.hover.style = "corners"; HogHeals.db.profile.frames.highlight.hover.thick = 2')
    enter(cells, "HH_a")
    assert cells.eval("HH_a.hoverMark.style") == "corners"
    assert all(cells.eval(f"HH_a.hoverMark.corners[{i}]:IsShown()") is True for i in range(1, 9))
    assert all(cells.eval(f"HH_a.hoverMark.edges[{i}]:IsShown()") is False for i in range(1, 5))
    assert list(cells.eval("{ HH_a.hoverMark.corners[1]:GetSize() }").values()) == [8, 2]   # horizontal arm
    assert list(cells.eval("{ HH_a.hoverMark.corners[2]:GetSize() }").values()) == [2, 8]   # vertical arm
    cells.execute('HogHeals.db.profile.frames.highlight.hover.style = "fill"; HogHeals.db.profile.frames.highlight.hover.color = { 1, 0.2, 0.2 }')
    leave(cells, "HH_a"); enter(cells, "HH_a")
    assert cells.eval("HH_a.hoverMark.style") == "fill"
    assert cells.eval("HH_a.hoverMark.fill:IsShown()") is True
    assert list(cells.eval("{ HH_a.hoverMark.fill:GetVertexColor() }").values()) == [1, 0.2, 0.2, 0.25]
    cells.execute('HogHeals.db.profile.frames.highlight.hover.style = "none"')
    leave(cells, "HH_a"); enter(cells, "HH_a")
    assert shown(cells, "HH_a", "hoverMark") is False


def test_thickness_and_gap_push_the_outline_out(cells):
    cells.execute('HogHeals.db.profile.frames.highlight.hover.thick = 2; HogHeals.db.profile.frames.highlight.hover.gap = 1')
    enter(cells, "HH_a")
    p = list(cells.eval("{ HH_a.hoverMark.edges[1]:GetPoint(1) }").values())
    assert p[3] == -3 and p[4] == 3
    assert cells.eval("HH_a.hoverMark.edges[1]:GetHeight()") == 2


# ---------------------------------------------------------------- target

def test_target_corners_follow_the_target(cells):
    target(cells, "Player-1")
    assert shown(cells, "HH_a", "targetMark") is True and cells.eval("HH_a.targetMark.style") == "corners"
    assert cells.eval("HH_b.targetMark") is None
    assert list(cells.eval("{ HH_a.targetMark.corners[1]:GetSize() }").values()) == [8, 2]
    p = list(cells.eval("{ HH_a.targetMark.corners[1]:GetPoint(1) }").values())
    assert p[0] == "TOPLEFT" and p[3] == -3 and p[4] == 3        # gap 1 + thick 2 outside
    target(cells, "Player-2")
    assert shown(cells, "HH_a", "targetMark") is False
    assert shown(cells, "HH_b", "targetMark") is True
    target(cells, None)
    assert shown(cells, "HH_b", "targetMark") is False
    assert errors(cells) == []


def test_target_colour_and_style_write_through(cells):
    cells.execute('HogHeals.db.profile.frames.highlight.target.style = "outline"; HogHeals.db.profile.frames.highlight.target.color = { 0.85, 0.2, 0.2 }')
    target(cells, "Player-1")
    assert cells.eval("HH_a.targetMark.style") == "outline"
    assert list(cells.eval("{ HH_a.targetMark.edges[2]:GetVertexColor() }").values())[:3] == [0.85, 0.2, 0.2]
    assert cells.eval("HH_a.targetMark.edges[2]:GetHeight()") == 2


def test_secret_target_answer_means_no_mark_and_no_error(cells):
    cells.execute('MockSetSecrets(true); UnitIsUnit = function() return MockSecret(true) end')
    target(cells, "Player-1")
    assert shown(cells, "HH_a", "targetMark") is False
    assert shown(cells, "HH_b", "targetMark") is False
    assert errors(cells) == []


def test_hover_and_target_on_one_cell(cells):
    target(cells, "Player-1")
    enter(cells, "HH_a")
    assert shown(cells, "HH_a", "hoverMark") is True and shown(cells, "HH_a", "targetMark") is True
    # both outline: the target's wins
    cells.execute('HogHeals.db.profile.frames.highlight.target.style = "outline"')
    leave(cells, "HH_a"); enter(cells, "HH_a")
    assert shown(cells, "HH_a", "hoverMark") is False and shown(cells, "HH_a", "targetMark") is True
    leave(cells, "HH_a")
    assert shown(cells, "HH_a", "targetMark") is True


def test_indicator_off_hides_everything(cells):
    target(cells, "Player-1")
    enter(cells, "HH_a")
    cells.execute('HogHeals.db.profile.frames.indicators.highlight = false; HogHealsFrames.UnitButton.UpdateAll(HH_a)')
    assert shown(cells, "HH_a", "hoverMark") is False and shown(cells, "HH_a", "targetMark") is False
    leave(cells, "HH_a"); enter(cells, "HH_a")
    assert shown(cells, "HH_a", "hoverMark") is False


def test_refresh_repaints_live_marks(cells):
    target(cells, "Player-1")
    cells.execute('HogHeals.db.profile.frames.highlight.target.style = "outline"; HogHealsFrames.module:Refresh()')
    assert cells.eval("HH_a.targetMark.style") == "outline"


# ---------------------------------------------------------------- AoE scope fill

def test_aoe_scope_fill_off_by_default_and_coloured_from_options_when_on(cells):
    cells.execute('MockState.playerClass = "PRIEST"')
    enter(cells, "HH_a")
    assert cells.eval("HH_a.aoeGlow:IsShown()") is False
    leave(cells, "HH_a")
    cells.execute('HogHeals.db.profile.frames.indicators.aoeHealing = true; HogHeals.db.profile.frames.highlight.aoe = { color = { 1, 0.5, 0 }, alpha = 0.4 }')
    enter(cells, "HH_a")
    assert cells.eval("HH_a.aoeGlow:IsShown()") is True
    assert list(cells.eval("{ HH_a.aoeGlow:GetVertexColor() }").values()) == [1, 0.5, 0, 0.4]


# ---------------------------------------------------------------- options

def test_options_group_and_presets(cells):
    args = cells.eval("HogHealsFrames.module:GetOptions().args.highlight.args")
    keys = set(args.keys())
    assert {"hoverStyle", "hoverColor", "hoverThick", "targetStyle", "targetColor", "targetThick", "targetSize",
            "aoe", "aoeColor", "aoeAlpha", "presetWhite", "presetRed", "presetCorners"} <= keys
    cells.execute('HogHealsFrames.module:GetOptions().args.highlight.args.presetRed.func()')
    h = cells.eval("HogHeals.db.profile.frames.highlight")
    assert h["target"]["style"] == "outline" and list(h["target"]["color"].values())[:3] == [0.85, 0.2, 0.2]
    cells.execute('HogHealsFrames.module:GetOptions().args.highlight.args.presetCorners.func()')
    h = cells.eval("HogHeals.db.profile.frames.highlight")
    assert h["hover"]["style"] == "corners" and h["target"]["style"] == "corners"
    cells.execute('HogHealsFrames.module:GetOptions().args.highlight.args.presetWhite.func()')
    h = cells.eval("HogHeals.db.profile.frames.highlight")
    assert h["hover"]["style"] == "outline" and list(h["hover"]["color"].values()) == [1, 1, 1] and h["target"]["style"] == "corners"
