# Tester feedback, Forever beta 2026-09-17: "I'm not sure what this bar is. I want a clean square with names on it.
# I don't know what these lines are." Root cause of the missing name: name/healthText/icons were regions of the
# BUTTON while the health bar is a CHILD FRAME of it; child frames draw above their parent's regions.
import re, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
ABOVE_BAR = ["name", "healthText", "dispelBorder", "dispelIcon", "priorityIcon", "aggroBorder", "raidIcon",
             "statusIcon", "missingBuff", "shieldIcon", "shieldText", "aoeGlow", "requestGlow"]


def test_everything_that_must_be_seen_lives_on_an_overlay_above_the_bars(frames):
    frames.execute('HH_c = HogHealsFrames.UnitButton.Create("HHCleanBtn", UIParent)')
    assert frames.eval('HH_c.overlay ~= nil and HH_c.overlay:GetParent() == HH_c')
    for r in ABOVE_BAR:
        assert frames.eval(f'HH_c.{r}:GetParent() == HH_c.overlay'), r
    assert frames.eval('HH_c.overlay._frameLevel > HH_c.health._frameLevel')
    assert frames.eval('HH_c.overlay._frameLevel > HH_c.power._frameLevel')


def test_setup_source_never_parents_a_visible_region_to_the_bare_button():
    src = (ROOT / "HogHeals_Frames" / "UnitButton.lua").read_text(encoding="utf-8")
    assert not re.search(r"button:CreateFontString\(", src)
    assert re.findall(r'mkTexture\(button, "(\w+)"', src) == ["BACKGROUND"]     # only the backdrop


def test_defaults_are_square_flat_and_without_marker_lines(frames):
    d = 'HogHeals.defaults.profile.frames'
    for bucket in ("solo", "party", "raid10", "raid20", "raid40"):
        w, h = frames.eval(f'{d}.layouts.{bucket}.width'), frames.eval(f'{d}.layouts.{bucket}.height')
        assert 1.2 <= w / h <= 1.7, (bucket, w, h)
    assert frames.eval(f'{d}.appearance.texture') == "Solid"
    assert frames.eval(f'{d}.indicators.thresholds') is False
    assert frames.eval('HogHeals.defaults.profile.hud.texture') == "Solid"


def test_migration_2_reshapes_old_wide_layouts_but_keeps_deliberate_ones(frames):
    frames.execute('''
      local p = HogHeals.db.profile.frames
      p.layouts.party.width, p.layouts.party.height = 150, 40      -- old default x wizard 1.25
      p.layouts.raid10.width, p.layouts.raid10.height = 70, 60     -- user made this one square already
      HogHeals.db.global.schema = 1
      HogHeals.Migrate.Run(HogHeals.db)
    ''')
    dw = frames.eval('HogHeals.defaults.profile.frames.layouts.party.width')
    assert frames.eval('HogHeals.db.profile.frames.layouts.party.width') == dw
    assert frames.eval('HogHeals.db.profile.frames.layouts.raid10.width') == 70
    assert frames.eval('HogHeals.db.global.schema') == 3
