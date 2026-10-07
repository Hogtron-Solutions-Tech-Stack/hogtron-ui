# Look (HogHeals/Core/Look.lua): HogTron / Classic style, the shipped fonts, text edge, size, pixel-perfect scale.
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
L = "HogHeals.Look"


@pytest.fixture
def look(lua):
    lua.execute("function GetPhysicalScreenSize() return 2560, 1440 end")
    # the mock's GetScale is always 1; a real pair for UIParent so the pixel-perfect scale can be read back
    lua.execute("function UIParent:SetScale(s) self._scale = s end; function UIParent:GetScale() return self._scale or 1 end")
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Frames")
    lua.load_addon("HogHeals_HUD")
    lua.player_login()
    lua.execute("wipe(HogHeals.errors)")
    return lua


def errors(lua):
    return [e["msg"] for e in lua.eval("HogHeals.errors").values()]


def test_fonts_ship_with_their_licences():
    d = ROOT / "HogHeals" / "Media" / "Fonts"
    for f in ("Inter-SemiBold.ttf", "Manrope-SemiBold.ttf", "BarlowCondensed-SemiBold.ttf"):
        assert (d / f).stat().st_size > 50_000, f
    for f in ("OFL-inter.txt", "OFL-manrope.txt", "OFL-barlowcondensed.txt"):
        assert "SIL OPEN FONT LICENSE" in (d / f).read_text(encoding="utf-8").upper(), f


def test_defaults_are_hogtron_inter_shadow(look):
    c = look.eval("HogHeals.db.profile.look")
    assert c["style"] == "hogtron" and c["font"] == "Inter" and c["edge"] == "shadow" and c["size"] == 0
    assert look.eval(f"{L}.Font()").endswith("Inter-SemiBold.ttf")
    assert look.eval(f"{L}.Font('HogTron')").endswith("Inter-SemiBold.ttf")              # module default = follow
    assert look.eval(f"{L}.Font('HogTron Manrope')").endswith("Manrope-SemiBold.ttf")    # one of ours, picked by name
    assert look.eval(f"{L}.Bar()") == "Interface\\Buttons\\WHITE8X8"


def test_font_objects_restyle_live_with_shadow_or_outline(look):
    o = "HogTronFontSmall"
    path, size, flags = look.eval(f"{o}._last.SetFont[1]"), look.eval(f"{o}._last.SetFont[2]"), look.eval(f"{o}._last.SetFont[3]")
    assert path.endswith("Inter-SemiBold.ttf") and flags == ""
    assert look.eval(f"{o}._last.SetShadowOffset[1]") == 1 and look.eval(f"{o}._last.SetShadowOffset[2]") == -1
    look.execute("HogHeals:SlashCommand('look barlow'); HogHeals:SlashCommand('look outline')")
    assert look.eval(f"{o}._last.SetFont[1]").endswith("BarlowCondensed-SemiBold.ttf")
    assert look.eval(f"{o}._last.SetFont[3]") == "OUTLINE" and look.eval(f"{o}._last.SetShadowOffset[1]") == 0
    assert "look: hogtron, font Barlow Condensed, outline, size +0" in "\n".join(look.eval("MockLog.chat").values())
    look.execute("HogHeals.db.profile.look.size = 2; HogHeals.Look.Apply()")
    assert look.eval(f"{o}._last.SetFont[2]") == size + 2
    assert errors(look) == []


def test_classic_uses_blizzard_font_and_bars_and_keeps_a_picked_font(look):
    look.execute("HogHeals:SlashCommand('look classic')")
    assert any("type /reload" in m for m in look.eval("MockLog.chat").values())
    look.execute("HogHeals.Look.Apply()")
    assert look.eval(f"{L}.Classic()") is True
    assert look.eval(f"{L}.Font()") == look.eval("STANDARD_TEXT_FONT")
    assert look.eval(f"{L}.Bar('Solid')") == "Interface\\TargetingFrame\\UI-StatusBar"
    # the frames and HUD build with whatever Look says
    look.execute("HogHealsHUD.HUD.Refresh()")
    assert look.eval("HogHealsHUD.HUD.rows.castbar._texture") == "Interface\\TargetingFrame\\UI-StatusBar"
    look.execute("HogHeals:SlashCommand('look hogtron'); HogHeals.Look.Apply(); HogHealsHUD.HUD.Refresh()")
    assert look.eval("HogHealsHUD.HUD.rows.castbar._texture") == "Interface\\Buttons\\WHITE8X8"
    assert look.eval("HogHealsHUD.HUD.rows.castbar.text._last.SetFont[1]").endswith("Inter-SemiBold.ttf")


def test_pixel_perfect_sets_and_undoes_the_scale(look):
    assert look.eval(f"{L}.PerfectScale()") == pytest.approx(768 / 1440)
    look.execute("UIParent:SetScale(0.9); HogHeals:SlashCommand('look pixel')")
    assert look.eval("UIParent:GetScale()") == pytest.approx(768 / 1440)
    assert look.eval("HogHeals.db.profile.look.pixelBefore") == pytest.approx(0.9)
    look.execute("UIParent:SetScale(1); MockFire('UI_SCALE_CHANGED')")                   # the game resets it: we put it back
    assert look.eval("UIParent:GetScale()") == pytest.approx(768 / 1440)
    look.execute("HogHeals:SlashCommand('look unpixel')")
    assert look.eval("UIParent:GetScale()") == pytest.approx(0.9) and look.eval("HogHeals.db.profile.look.pixel") is None
    look.execute("MockState.inCombat = true")
    assert look.eval(f"({L}.MakePixelPerfect())") is False                                 # never in combat
    assert errors(look) == []


def test_options_look_group_runs(look):
    args = look.eval("HogHeals.OptionsTable().args.general.args.look.args")
    for k in ("style", "font", "edge", "size", "pixel", "unpixel", "scale", "apply"):
        assert args[k] is not None, k
    look.execute("""
      local a = HogHeals.OptionsTable().args.general.args.look.args
      a.font.set(nil, "Manrope"); a.edge.set(nil, "outline"); a.size.set(nil, 1)
      SCALE_TEXT = a.scale.name()
    """)
    assert look.eval("HogHeals.db.profile.look.font") == "Manrope" and look.eval("HogHeals.db.profile.look.size") == 1
    assert "Pixel-perfect for your screen: 0.533" in look.eval("SCALE_TEXT")
    assert errors(look) == []
