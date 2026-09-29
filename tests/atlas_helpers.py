"""Shared mocks for the HogUI Atlas tests: an item database the way the Forever client serves it (C_Item only, no
global GetItemInfo), tooltip lines, an instance, a loot window, the quest log."""

CLIENT = r'''
GetItemInfo = nil                                   -- measured on Forever: the global is gone
GetItemInfoInstant = nil
REQUESTED = {}
ITEMS = {
  -- id = { name, quality, ilvl, minLevel, type, subType, equipLoc, classID, subClassID, tooltip lines }
  [1001] = { "Seer's Cowl", 3, 30, 25, "Armor", "Cloth", "INVTYPE_HEAD", 4, 1,
    { "Seer's Cowl", "Head", "Cloth", "30 Armor", "+10 Intellect", "+5 Spirit", "Equip: Increases healing done by spells and effects by up to 22." } },
  [1002] = { "Plain Hood", 2, 20, 15, "Armor", "Cloth", "INVTYPE_HEAD", 4, 1, { "Plain Hood", "20 Armor", "+3 Intellect" } },
  [1003] = { "Warlord's Helm", 3, 45, 40, "Armor", "Plate", "INVTYPE_HEAD", 4, 4, { "Warlord's Helm", "300 Armor", "+20 Strength", "+15 Stamina" } },
  [1004] = { "Band of Waves", 3, 30, 26, "Armor", "Miscellaneous", "INVTYPE_FINGER", 4, 0, { "Band of Waves", "+6 Intellect", "Equip: Restores 3 mana per 5 sec." } },
  [1005] = { "Copper Ring", 2, 12, 10, "Armor", "Miscellaneous", "INVTYPE_FINGER", 4, 0, { "Copper Ring", "+2 Stamina" } },
  [1006] = { "Iron Ring", 2, 14, 10, "Armor", "Miscellaneous", "INVTYPE_FINGER", 4, 0, { "Iron Ring", "+4 Intellect" } },
  [1007] = { "Elder's Crown", 4, 50, 45, "Armor", "Cloth", "INVTYPE_HEAD", 4, 1,
    { "Elder's Crown", "60 Armor", "+20 Intellect", "Equip: Increases healing done by spells and effects by up to 40." } },
  [1008] = { "Chain Hauberk", 3, 30, 25, "Armor", "Mail", "INVTYPE_CHEST", 4, 3, { "Chain Hauberk", "200 Armor", "+10 Intellect" } },
  [1009] = { "Great Maul", 3, 30, 25, "Weapon", "Two-Handed Maces", "INVTYPE_2HWEAPON", 2, 5,
    { "Great Maul", "Two-Hand", "60 - 90 Damage", "(25.0 damage per second)", "+12 Strength" } },
  [1010] = { "Grey Rag", 0, 5, 1, "Armor", "Cloth", "INVTYPE_CHEST", 4, 1, { "Grey Rag", "5 Armor" } },
  [1011] = { "Linen Cloth", 1, 5, 0, "Trade Goods", "Cloth", "INVTYPE_NON_EQUIP_IGNORE", 7, 5, { "Linen Cloth" } },
}
local function idOf(x)
  if type(x) == "number" then return x end
  return tonumber(tostring(x):match("item:(%d+)"))
end
function ItemLink(id) local i = ITEMS[id] return "|cnIQ" .. i[2] .. ":|Hitem:" .. id .. "::::::::7:1485:::::::::|h[" .. i[1] .. "]|h|r" end
C_Item = {
  GetItemInfo = function(x)
    local id = idOf(x)
    local i = id and ITEMS[id]
    if not i or i.cold then return nil end
    return i[1], ItemLink(id), i[2], i[3], i[4], i[5], i[6], 1, i[7], 130000 + id, 50, i[8], i[9]
  end,
  GetItemInfoInstant = function(x)
    local id = idOf(x)
    local i = id and ITEMS[id]
    if not i then return nil end
    return id, i[5], i[6], i[7], 130000 + id, i[8], i[9]
  end,
  GetItemQualityByID = function(id) local i = ITEMS[id] return i and i[2] or nil end,
  RequestLoadItemDataByID = function(id) REQUESTED[id] = (REQUESTED[id] or 0) + 1 end,
}
C_TooltipInfo = C_TooltipInfo or {}
C_TooltipInfo.GetHyperlink = function(link)
  local id = idOf(link)
  local i = id and ITEMS[id]
  if not i or i.cold then return nil end
  local lines = {}
  for n, l in ipairs(i[10]) do lines[n] = { leftText = l } end
  return { lines = lines }
end

-- where am I
INST = nil
function GetInstanceInfo()
  if not INST then return "Kalimdor", "none", 0, "", 0, 0, false, 1 end
  return INST.name, INST.kind or "party", 1, "Normal", 5, 0, false, INST.id
end

-- loot window
LOOT = {}
function GetNumLootItems() return #LOOT end
function GetLootSlotType(i) return LOOT[i] and (LOOT[i].kind or 1) or 0 end
function GetLootSlotLink(i) return LOOT[i] and LOOT[i].link end
function GetLootSourceInfo(i) return LOOT[i] and LOOT[i].guid, 1 end
function GetLootRollItemLink(id) return ROLLS and ROLLS[id] end
function NpcGUID(npc, n) return "Creature-0-4615-0-2065-" .. npc .. "-00003" .. (n or 1) .. "B0DA" end

-- gear
WORN = {}
function GetInventoryItemLink(unit, slot) local id = WORN[slot] return id and ItemLink(id) or nil end
BAGS = {}
C_Container = C_Container or {}
C_Container.GetContainerNumSlots = function(bag) return bag == 0 and #BAGS or 0 end
C_Container.GetContainerItemLink = function(bag, slot) local id = bag == 0 and BAGS[slot] return id and ItemLink(id) or nil end
function GetRealmName() return "Classic Beta PvP" end
function UnitFactionGroup() return FACTION or "Horde", FACTION or "Horde" end
'''


def boot(lua, quests=False, extra=""):
    lua.execute(CLIENT + extra)
    lua.load_addon("HogHeals")
    if quests:
        lua.load_addon("HogHeals_Quests")
    lua.load_addon("HogHeals_Atlas")
    lua.execute('MockState.playerClass = MockState.playerClass or "SHAMAN"')
    lua.player_login()
    lua.execute("wipe(HogHeals.errors)")
    return lua


def errors(lua):
    return [e["msg"] for e in lua.eval("HogHeals.errors").values()]


def vals(t):
    return list(t.values()) if t is not None else []
