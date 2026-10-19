# /hh unlock grid + snapping (Sean 2026-10-18: "On the HH unlock, I want a grid and I want snapping elements. I just
# arranged my unit frame and then the target unit frame, and it was hard to make sure that they were lined correctly.
# We can look at the edit mode that Blizzard has").
import pytest

from test_edit_mode import ed, errors  # noqa: F401

EM = "HogHeals.EditMode"


def snap(lua, rect, others=(), cx=960, cy=540, size=32, px=10):
    def r(l, b, w, h):
        return f"{{ l = {l}, r = {l + w}, b = {b}, t = {b + h}, cx = {l + w / 2}, cy = {b + h / 2} }}"
    o = ", ".join(r(*x) for x in others)
    sz = "nil" if size is None else size
    got = lua.eval(f"""(function() local dx, dy, gx, gy, kx, ky = {EM}.SnapOffset({r(*rect)}, {{ {o} }},
      {{ cx = {cx}, cy = {cy}, size = {sz}, px = {px} }}) return {{ dx = dx, dy = dy, gx = gx, gy = gy, kx = kx, ky = ky }} end)()""")
    return [got[k] for k in ("dx", "dy", "gx", "gy", "kx", "ky")]


# ------------------------------------------------------------------------------------------------ the rule (pure)
def test_edges_and_centres_line_up_with_other_frames(ed):
    # bottom y=203 (h 40) beside a frame of the same height at bottom y=200: bottoms, middles and tops meet, 3 px down
    dx, dy, gx, gy, kx, ky = snap(ed, (101, 203, 200, 40), [(600, 200, 240, 40)], size=None)
    assert dy == -3 and gy == 200 and ky == "frame"
    # side by side: my left 6 px right of its right edge -> flush
    dx, *_ = snap(ed, (846, 400, 100, 40), [(600, 200, 240, 42)], size=None)
    assert dx == -6
    # the closest pair wins: tops 1 px apart beat bottoms 3 px apart
    dx, dy, gx, gy, kx, ky = snap(ed, (101, 203, 200, 40), [(600, 200, 240, 42)], size=None)
    assert dy == -1 and gy == 242


def test_the_screen_centre_lines_then_the_grid(ed):
    dx, dy, gx, gy, kx, ky = snap(ed, (858, 100, 200, 40), [], size=None)          # centre x 958 -> 960
    assert dx == 2 and gx == 960 and kx == "centre"
    dx, dy, gx, gy, kx, ky = snap(ed, (994, 711, 40, 40), [], size=32)           # left 994 -> grid 992 (centre 960 + 32)
    assert dx == -2 and gx == 992 and kx == "grid"
    assert snap(ed, (1000, 700, 50, 50), [], size=None)[:2] == [0, 0]               # grid off, nothing near: stays
    assert snap(ed, (1000, 700, 50, 50), [], size=None)[2] is None


def test_another_frame_wins_over_a_nearer_grid_line(ed):
    # bottom at 506: a frame bottom at 500 (6 away) and the grid line 508 (2 away) - lining up with the frame wins
    dx, dy, gx, gy, kx, ky = snap(ed, (100, 506, 40, 40), [(300, 500, 40, 40)], size=32)
    assert dy == -6 and ky == "frame"


def test_too_far_never_snaps(ed):
    assert snap(ed, (100, 300, 40, 40), [(300, 200, 40, 40)], size=None, px=10)[:2] == [0, 0]


# ------------------------------------------------------------------------------------------------ in edit mode
SETUP = """
  HogUITarget.GetCenter = function() return 1240, 250 end
  HogUIPlayer.GetCenter = function() return 680, 256 end
  HogHeals:SlashCommand("unlock")
"""


def drag(lua, frame):
    lua.execute(f'{frame}:GetScript("OnDragStart")({frame})')


def drop(lua, frame):
    lua.execute(f'{frame}:GetScript("OnDragStop")({frame})')


def test_the_player_frame_lines_up_with_the_target_frame(ed):  # noqa: F811
    ed.execute(SETUP)
    drag(ed, "HogUIPlayer")
    ed.execute(f"{EM}.ShowGuides()")
    assert ed.eval(f"{EM}.guide.h:IsShown()") is True                         # the line it will snap to, while dragging
    drop(ed, "HogUIPlayer")
    p = ed.eval("HogHeals.db.profile.units.player")
    assert p["point"] == "CENTER" and p["y"] == 250 - 540                       # level with the target frame
    assert p["x"] == 680 - 960                                                  # x already on a grid line (800 = its right edge)
    assert ed.eval(f"{EM}.lastSnap.key") == "unit:player"
    assert ed.eval(f"{EM}.guide.h:IsShown()") is False                        # guides go when you let go
    assert errors(ed) == []


def test_shift_or_snap_off_places_it_freely(ed):  # noqa: F811
    ed.execute(SETUP + "IsShiftKeyDown = function() return true end")
    drag(ed, "HogUIPlayer")
    drop(ed, "HogUIPlayer")
    assert ed.eval(f"{EM}.lastSnap") is None
    ed.execute("IsShiftKeyDown = function() return false end")
    ed.execute(f"{EM}.bar.snap:Click()")                                      # the toolbar switch
    assert ed.eval("HogHeals.db.profile.edit.snap") is False and ed.eval(f"{EM}.bar.snap.text:GetText()") == "Snap: off"
    drag(ed, "HogUIPlayer")
    drop(ed, "HogUIPlayer")
    assert ed.eval(f"{EM}.lastSnap") is None


def test_center_and_a_locked_drag_never_snap(ed):  # noqa: F811
    ed.execute(SETUP + f'for _, t in ipairs({EM}.Targets()) do if t.key == "unit:player" then HH_P = t end end')
    assert ed.eval(f"{EM}.Center(HH_P, 'h')") is True
    assert ed.eval(f"{EM}.lastSnap") is None
    ed.execute('HogHeals:SlashCommand("lock")')
    drag(ed, "HogUIPlayer")
    drop(ed, "HogUIPlayer")
    assert ed.eval(f"{EM}.lastSnap") is None


def test_the_toolbar_and_the_grid(ed):  # noqa: F811
    ed.execute('HogHeals:SlashCommand("unlock")')
    bar = f"{EM}.bar"
    assert ed.eval(f"{bar}:IsShown()") is True
    assert [ed.eval(f"{bar}.{k}.text:GetText()") for k in ("grid", "snap")] == ["Grid: on", "Snap: on"]
    assert ed.eval(f"{bar}.size:GetText()") == "32 px"
    assert ed.eval(f"{EM}.gridLines") == (1 + 2 * (960 // 32)) + (1 + 2 * (540 // 32))   # centre lines + every 32 px
    assert ed.eval(f"{EM}.gridFrame.lines[1].hhCentre") is True and ed.eval(f"{EM}.gridFrame:IsShown()") is True
    ed.execute(f"{bar}.plus:Click()")
    assert ed.eval("HogHeals.db.profile.edit.gridSize") == 48 and ed.eval(f"{bar}.size:GetText()") == "48 px"
    assert ed.eval(f"{EM}.gridLines") == (1 + 2 * (960 // 48)) + (1 + 2 * (540 // 48))
    ed.execute(f"{bar}.grid:Click()")
    assert ed.eval(f"{bar}.grid.text:GetText()") == "Grid: off" and ed.eval(f"{EM}.gridFrame:IsShown()") is False
    ed.execute(f"{bar}.lock:Click()")
    assert ed.eval("HogHeals.db.profile.locked") is True
    assert ed.eval(f"{bar}:IsShown()") is False and ed.eval(f"{EM}.gridFrame:IsShown()") is False


@pytest.mark.parametrize("key", ["hud:castbar"])
def test_a_box_drag_snaps_its_mover_too(ed, key):  # noqa: F811
    ed.execute("""
      HogHealsHUDAnchor.GetCenter = function() return 963, 300 end
      HogHeals:SlashCommand("unlock")""")
    b = f'{EM}.boxes["{key}"]'
    ed.execute(f'{b}:GetScript("OnDragStart")({b}); {b}:GetScript("OnDragStop")({b})')
    assert ed.eval(f"{EM}.lastSnap.key") == key and ed.eval(f"{EM}.lastSnap.dx") == -3   # onto the screen's centre line
    h = ed.eval("HogHeals.db.profile.hud")
    assert h["x"] == 0
