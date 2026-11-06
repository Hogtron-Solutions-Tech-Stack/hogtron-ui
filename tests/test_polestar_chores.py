# Polestar alongside, chores + gear (Core/Polestar.lua). Where Polestar and HogTron UI would both do the same job, ours
# stands aside while Polestar's own switch for it is on: quest lines on tooltips, selling junk, repairing, the
# "upgrade looted" chat line. Polestar's verdict on quest rewards is carried into our quest dialog (its own marks sit
# on Blizzard's reward panel, which our dialog stands in for).
import pytest

import atlas_helpers
import test_quest_dialog as qd
from test_polestar_guide import FAKE_POLESTAR
from test_quest_qol import NPC
from test_quests import MODERN, boot, errors

CHORES = r'''
PS_SETTINGS["qol.questTooltips"] = true
PS_SETTINGS["qol.sellJunk"] = true
PS_SETTINGS["qol.autoRepair"] = true
PS_SETTINGS["qol.wearOffer"] = true
'''


def test_tooltip_quest_lines_stand_aside_for_polestars(lua):
    boot(lua, MODERN + NPC + FAKE_POLESTAR + CHORES)
    tip = '''function GameTooltip:GetUnit() return "Kobold Vermin", "mouseover" end
      GameTooltip:ClearLines(); GameTooltip:GetScript("OnTooltipSetUnit")(GameTooltip)'''
    lua.execute(tip)
    assert lua.eval("#GameTooltip._lines") == 0
    assert "deferring to Polestar" in " ".join(lua.eval("HogHealsQuests.Tooltip.Lines()").values())
    # Polestar's lines off: ours come back
    lua.execute('PS_SETTINGS["qol.questTooltips"] = false')
    lua.execute(tip)
    assert lua.eval("#GameTooltip._lines") == 1
    # our chores switch off: ours stay even with Polestar's on
    lua.execute('PS_SETTINGS["qol.questTooltips"] = true; HogHeals.db.profile.interop.polestar.chores = false')
    lua.execute(tip)
    assert lua.eval("#GameTooltip._lines") == 1
    assert errors(lua) == []


def test_junk_and_repair_stand_aside_for_polestars(lua):
    lua.execute(FAKE_POLESTAR + CHORES + '''
      USED, REPAIRED = 0, 0
      C_Container = { GetContainerNumSlots = function(b) return b == 0 and 1 or 0 end,
        UseContainerItem = function() USED = USED + 1 end,
        GetContainerItemInfo = function() return { quality = 0, stackCount = 1, hyperlink = "junk", hasNoValue = false } end }
      function CanMerchantRepair() return true end
      function GetRepairAllCost() return 500, true end
      function GetMoney() return 100000 end
      function RepairAllItems() REPAIRED = REPAIRED + 1 end
    ''')
    for a in ("HogTronUI", "HogTron_Skin"):
        lua.load_addon(a)
    lua.player_login()
    P = "HogHealsSkin.Auto"
    lua.execute(f"{P}.OnMerchant()")
    assert lua.eval("USED") == 0 and lua.eval("REPAIRED") == 0
    assert lua.eval(f"{P}.deferred") == "Polestar"
    # Polestar's own switches off: ours do the job
    lua.execute(f'PS_SETTINGS["qol.sellJunk"] = false; PS_SETTINGS["qol.autoRepair"] = false; {P}.OnMerchant()')
    assert lua.eval("USED") == 1 and lua.eval("REPAIRED") == 1
    assert [e["msg"] for e in lua.eval("HogHeals.errors").values()] == []


def test_upgrade_chat_line_stands_aside_while_polestar_offers_upgrades(lua):
    atlas_helpers.boot(lua, extra=FAKE_POLESTAR + CHORES)
    lua.execute("COMPARED = 0; local real = HogHealsAtlas.Gear.Compare; HogHealsAtlas.Gear.Compare = function(...) COMPARED = COMPARED + 1 return real(...) end")
    lua.execute('HogHealsAtlas.Capture.UpgradeAlert("|Hitem:1234|h[Thing]|h")')
    assert lua.eval("COMPARED") == 0 and lua.eval("HogHealsAtlas.Capture.upgradeDeferred") == 1
    lua.execute('HogHeals.db.profile.interop.polestar.gear = false; HogHealsAtlas.Capture.UpgradeAlert("|Hitem:1234|h[Thing]|h"); MockAdvance(2)')
    assert lua.eval("HogHealsAtlas.Capture.upgradeDeferred") == 1 and lua.eval("COMPARED") >= 1   # ours ran this time
    assert atlas_helpers.errors(lua) == []


RANKS = r'''
LINKS = { "|Hitem:10|h[Brawler Gloves]|h", "|Hitem:11|h[Woodland Tunic]|h", "|Hitem:12|h[Light Pants]|h" }
function GetQuestItemLink(kind, i) if kind == "choice" then return LINKS[i] end end
RANKED = nil
Polestar.Gear = { RankChoices = function(links)
  RANKED = links
  return { { index = 1, upgrade = false }, { index = 2, upgrade = true, pct = 12.4 }, { index = 3, upgrade = true, pct = 3 } }, 2, 2
end }
'''


def test_quest_dialog_carries_polestars_reward_verdict(lua):
    qd.boot(lua, before=FAKE_POLESTAR + RANKS, auto=True)
    lua.execute('CHOICES = { { "Brawler Gloves", 132939 }, { "Woodland Tunic", 132721 }, { "Light Pants", 134586 } }; MockFire("QUEST_COMPLETE")')
    assert qd.shown(lua)
    assert list(lua.eval("RANKED").values())[1] == "|Hitem:11|h[Woodland Tunic]|h"
    rows = [r["text"] for r in lua.eval(f"{qd.D}.model.rows").values()]
    assert rows == ["Brawler Gloves", "Woodland Tunic  (upgrade +12%, Polestar's pick)", "Light Pants  (upgrade +3%)"]
    assert lua.eval(f"{qd.D}.model.pickHint") == "Polestar's pick: Woodland Tunic (2). Click a reward or press its number."
    assert lua.eval(f"{qd.D}.model.primary.disabled") is True                     # still your pick: nothing chosen for you
    assert qd.calls(lua) == []
    assert [e["msg"] for e in lua.eval("HogHeals.errors").values()] == []


def test_quest_dialog_without_polestar_gear_is_unchanged(lua):
    qd.boot(lua, before=FAKE_POLESTAR, auto=True)                               # Polestar, but no Gear table
    lua.execute('CHOICES = { { "Brawler Gloves", 132939 }, { "Woodland Tunic", 132721 } }; MockFire("QUEST_COMPLETE")')
    rows = [r["text"] for r in lua.eval(f"{qd.D}.model.rows").values()]
    assert rows == ["Brawler Gloves", "Woodland Tunic"]
    assert lua.eval(f"{qd.D}.model.pickHint") == "Pick a reward: click it or press its number."


def test_diag_lists_what_stands_aside(lua):
    boot(lua, MODERN + FAKE_POLESTAR + CHORES)
    text = "\n".join(lua.eval("HogHeals.Polestar.Diagnose()").values())
    assert "ours standing aside for Polestar's: tooltips, sellJunk, repair, upgradeLine" in text
