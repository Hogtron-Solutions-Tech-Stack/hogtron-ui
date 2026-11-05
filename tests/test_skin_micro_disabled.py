# A Blizzard menu button the client has disabled (Talents under level 10) says why instead of swallowing the click.
# Sean 2026-11-05: "the Talents window doesn't open up ... it should tell me something when I try to open it up."
import pytest

from test_skin import CLIENT, errors  # noqa: F401

EXTRA = '''
TalentMicroButton = CreateFrame("Button", "TalentMicroButton", UIParent)
TalentMicroButton._left = 55
function TalentMicroButton:IsEnabled() return false end
function CharacterMicroButton:IsEnabled() return true end
SHOW_TALENT_LEVEL = 10
MockLog.chat = {}
'''


@pytest.fixture
def skin(lua):
    lua.execute(CLIENT + EXTRA)
    lua.load_addon("HogTronUI")
    lua.load_addon("HogTron_Skin")
    lua.player_login()
    lua.execute("wipe(HogHeals.errors); MockLog.chat = {}")
    return lua


def test_a_disabled_talents_button_names_its_level_on_click_and_in_the_tooltip(skin):
    assert skin.eval("HogHealsSkin.Micro.Unavailable(TalentMicroButton)") == "opens at level 10"
    assert skin.eval("HogHealsSkin.Micro.Unavailable(CharacterMicroButton)") is None
    cell = skin.eval('''(function() for _, c in ipairs(HogHealsSkin.Micro.bar.cells) do if c.src == TalentMicroButton then return c:GetName() end end end)()''')
    assert cell, "no cell for the talents button"
    skin.execute(f'{cell}:GetScript("PostClick")({cell})')
    chat = list(skin.eval("MockLog.chat").values())
    assert any("opens at level 10." in m for m in chat), chat
    skin.execute("SHOW_TALENT_LEVEL = nil")
    assert skin.eval("HogHealsSkin.Micro.Unavailable(TalentMicroButton)") == "not available yet"
    assert errors(skin) == []
