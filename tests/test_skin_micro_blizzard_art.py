# Menu bar only: Blizzard's own pictures (micro.blizzardArt, Anthony 2026-11-05: "an option to make these the normal
# blizzard buttons JUST THESE BUTTONS"). The bar's cells copy Blizzard's micro-button art and the Bags cell the
# backpack's icon; General > Icons (drawer, quest marks) is left as it is.
from test_skin import skin, errors  # noqa: F401 (fixture)

BAR = "HogHealsSkin.Micro.bar"
GIVE_ART = '''
  NT = CharacterMicroButton:CreateTexture()
  NT:SetTexture("Interface\\Buttons\\UI-MicroButton-Character-Up")
  function CharacterMicroButton:GetNormalTexture() return NT end
'''


def test_off_by_default_and_the_bar_keeps_our_painted_set(skin):
    assert skin.eval("HogHeals.db.profile.skin.micro.blizzardArt") is False
    skin.execute(GIVE_ART + "HogHealsSkin.Micro.Apply()")
    assert "micro_character" in skin.eval(f"{BAR}.cells[1].icon._texture")
    assert errors(skin) == []


def test_switch_on_puts_blizzards_pictures_on_this_bar_only(skin):
    skin.execute(GIVE_ART + "HogHeals.db.profile.skin.micro.blizzardArt = true; HogHealsSkin.Micro.Apply()")
    c1 = f"{BAR}.cells[1]"
    assert skin.eval(f"{c1}.icon._texture") == skin.eval("NT._texture")              # Blizzard's own button art
    assert skin.eval(f"{c1}.art") is True and skin.eval(f"{c1}.tint[1]") == 1          # never tinted
    assert skin.eval(f"{c1}:GetAttribute('clickbutton') == CharacterMicroButton")     # still presses Blizzard's button
    # a button the client gives no picture for falls back to our set (never a blank cell)
    c3 = f"{BAR}.cells[3]"
    assert skin.eval(f"{c3}.icon:IsShown()") is True and "micro_" in (skin.eval(f"{c3}.icon._texture") or "")
    # the Bags cell wears the backpack's own icon
    assert skin.eval(f"{BAR}.bagCell.icon._texture") == "backpack"
    # only this bar: the general icon look is untouched, the drawer keeps the painted set
    assert skin.eval("HogHeals.Look.IconStyle()") == "art"
    skin.execute("T = UIParent:CreateTexture(); HogHeals.Look.Icon(T, 'tray_atlas')")
    assert skin.eval("T._texture").endswith("tray_atlas_art")
    assert errors(skin) == []


def test_switch_off_again_brings_our_set_back(skin):
    skin.execute(GIVE_ART + "HogHeals.db.profile.skin.micro.blizzardArt = true; HogHealsSkin.Micro.Apply()")
    skin.execute("HogHeals.db.profile.skin.micro.blizzardArt = false; HogHealsSkin.Micro.Apply()")
    assert "micro_character" in skin.eval(f"{BAR}.cells[1].icon._texture")
    assert "micro_bags" in skin.eval(f"{BAR}.bagCell.icon._texture")
    assert errors(skin) == []


def test_the_option_sits_in_the_menu_bar_group_and_applies(skin):
    opt = "HogHealsSkin.Options.Build().args.micro.args.blizzardArt"
    assert skin.eval(f"{opt}.type") == "toggle" and "this bar only" in skin.eval(f"{opt}.name")
    assert skin.eval(f"{opt}.get()") is False
    skin.execute(GIVE_ART + f"{opt}.set(nil, true)")
    assert skin.eval("HogHeals.db.profile.skin.micro.blizzardArt") is True
    assert skin.eval(f"{BAR}.cells[1].icon._texture") == skin.eval("NT._texture")
    assert errors(skin) == []
