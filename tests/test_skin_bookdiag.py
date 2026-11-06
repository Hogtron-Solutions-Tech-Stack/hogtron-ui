# /hh bookdiag (HogTron_Skin/Panels.lua). Sean 2026-11-06, Forever druid on the Balance tab: "Spell book is broken. I
# can't see a lot of spells" - gaps and General spells on the page. The probe records, per spell slot on the page, what
# the frame shows against what the client holds there, plus the skill lines' slot ranges.
BOOK = r'''
SLOTS = { [1] = "Attack", [2] = "Cultivation", [9] = "Wrath", [10] = "Moonfire", [11] = "Entangling Roots" }
C_SpellBook = {
  GetNumSpellBookSkillLines = function() return 2 end,
  GetSpellBookSkillLineInfo = function(i) return ({ { name = "General", itemIndexOffset = 0, numSpellBookItems = 8 },
    { name = "Balance", itemIndexOffset = 8, numSpellBookItems = 3 } })[i] end,
  GetSpellBookItemInfo = function(slot) return SLOTS[slot] and { name = SLOTS[slot] } or nil end,
}
local function item(slot, shows, valid)
  local f = CreateFrame("Frame")
  f.elementData = { slotIndex = slot, spellBank = 0 }
  f.Name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.Name:SetText(shows)
  f.HasValidData = function() return valid end
  return f
end
FRAMES = { item(11, "Entangling Roots", true), item(9, "Cultivation", false), item(10, "", false) }
PlayerSpellsFrame = CreateFrame("Frame", "PlayerSpellsFrame", UIParent)
PlayerSpellsFrame.SpellBookFrame = CreateFrame("Frame", nil, PlayerSpellsFrame)
local sb = PlayerSpellsFrame.SpellBookFrame
sb.GetTab = function() return 3 end
sb.GetActiveCategoryMixin = function() return { GetName = function() return "Balance" end } end
sb.PagedSpellsFrame = { EnumerateFrames = function() return ipairs(FRAMES) end }
'''


def boot(lua):
    lua.execute(BOOK)
    for a in ("HogTronUI", "HogTron_Skin"):
        lua.load_addon(a)
    lua.player_login()
    return lua


def test_bookdiag_names_the_slots_that_show_the_wrong_spell(lua):
    boot(lua)
    lua.execute('HogHeals:SlashCommand("bookdiag")')
    chat = "\n".join(lua.eval("MockLog.chat").values())
    assert "tab 3 (Balance)" in chat
    assert "General 0+8, Balance 8+3" in chat
    assert "3 spell slots on the page, 2 not showing what the client holds" in chat
    assert '0:9 shows "Cultivation", client "Wrath" INVALID' in chat
    rec = lua.eval("HogHeals.db.global.diag.book")
    assert rec["bad"] == 2 and rec["category"] == "Balance"
    assert [e["msg"] for e in lua.eval("HogHeals.errors").values()] == []


def test_bookdiag_without_a_spellbook_says_so(lua):
    for a in ("HogTronUI", "HogTron_Skin"):
        lua.load_addon(a)
    lua.player_login()
    lua.execute('HogHeals:SlashCommand("bookdiag")')
    assert "no PlayerSpellsFrame.SpellBookFrame" in "\n".join(lua.eval("MockLog.chat").values())
