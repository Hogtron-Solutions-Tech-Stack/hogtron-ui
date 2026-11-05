# Icon look "blizzard" (Sean 2026-11-05: "default icons for the main menu ... an OG Blizzard style for everything"):
# menu-bar cells copy the art off Blizzard's own micro buttons, the drawer entries and quest marks use Blizzard files.
from test_skin import skin, errors  # noqa: F401 (fixture)


def test_menu_cells_copy_blizzards_own_button_art(skin):
    skin.execute('''
      NT = CharacterMicroButton:CreateTexture()
      NT:SetTexture("Interface\\Buttons\\UI-MicroButton-Character-Up")
      function CharacterMicroButton:GetNormalTexture() return NT end
      HogHeals.db.profile.look.icons = "blizzard"
      HogHealsSkin.Micro.Apply()
    ''')
    c = "HogHealsSkin.Micro.bar.cells[1]"
    assert skin.eval(f"{c}.icon._texture") == skin.eval("NT._texture")
    assert skin.eval(f"{c}.art") is True and skin.eval(f"{c}.icon:IsShown()") is True
    assert skin.eval(f"{c}.tint[1]") == 1 and skin.eval(f"{c}.tint[2]") == 1       # Blizzard's picture is never tinted
    # a button the client gives no picture for falls back to our set
    c3 = "HogHealsSkin.Micro.bar.cells[3]"
    assert skin.eval(f"{c3}.icon:IsShown()") is True and "micro_" in (skin.eval(f"{c3}.icon._texture") or "")
    assert errors(skin) == []


def test_look_icon_and_quest_marks_in_the_blizzard_look(skin):
    skin.execute("HogHeals.db.profile.look.icons = 'blizzard'; T = UIParent:CreateTexture()")
    assert list(skin.eval("{ HogHeals.Look.Icon(T, 'tray_atlas') }").values()) == [True, True]
    assert skin.eval("T._texture") == "Interface\Icons\INV_Misc_Map_01"
    skin.execute("T2 = UIParent:CreateTexture(); HogHeals.Look.Icon(T2, 'micro_character')")       # no Blizzard file mapped: the painted one
    assert skin.eval("T2._texture").endswith("micro_character_art")
    assert skin.eval("HogHeals.Look.QuestMark('open')") == "Interface\GossipFrame\AvailableQuestIcon"
    assert skin.eval("HogHeals.Look.QuestMark('done', 'dialog')") == "Interface\GossipFrame\ActiveQuestIcon"
    skin.execute("HogHeals.db.profile.look.icons = 'art'")
    assert skin.eval("HogHeals.Look.QuestMark('open')").endswith("Media\quest_open")
    assert skin.eval("HogHeals.Look.QuestMark('wait', 'dialog')").endswith("Media\dialog_quest_wait")
    assert skin.eval("HogHeals.Look.IconStyle()") == "art"
    skin.execute("HogHeals.db.profile.look.icons = 'glyph'")
    assert skin.eval("HogHeals.Look.IconStyle()") == "glyph"
    vals = skin.eval("HogHeals.OptionsTable().args.general.args.look.args.icons.values")
    assert vals["blizzard"].startswith("Blizzard")
    assert errors(skin) == []
