-- Class data tables: what each class can dispel, buff, and shield (Classic / TBC).
local ADDON, ns = ...
local HH = HogHeals

local function isClassicEra()
  return WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
end

-- Dispel types by class (Vanilla + TBC). Mage Remove Lesser Curse; Druid Abolish/Cure Poison + Remove Curse.
local DISPEL = {
  PRIEST  = { Magic = true, Disease = true },
  SHAMAN  = { Poison = true, Disease = true },
  PALADIN = { Magic = true, Poison = true, Disease = true },
  DRUID   = { Curse = true, Poison = true },
  MAGE    = { Curse = true },
}

function HH.CanDispel(class, debuffType)
  local t = DISPEL[class]
  return (t and t[debuffType]) == true
end

function HH.DispellableTypes(class)
  local out = {}
  local t = DISPEL[class]
  if t then for k in pairs(t) do out[#out + 1] = k end end
  table.sort(out)
  return out
end

-- Buffs a class can put on others; satisfiedBy = any of these names counts as present.
local BUFFS = {
  PRIEST = {
    { name = "Power Word: Fortitude", satisfiedBy = { "Power Word: Fortitude", "Prayer of Fortitude" }, icon = "Interface\\Icons\\Spell_Holy_WordFortitude" },
    { name = "Divine Spirit", satisfiedBy = { "Divine Spirit", "Prayer of Spirit" }, icon = "Interface\\Icons\\Spell_Holy_DivineSpirit", manaOnly = true },
    { name = "Shadow Protection", satisfiedBy = { "Shadow Protection", "Prayer of Shadow Protection" }, icon = "Interface\\Icons\\Spell_Shadow_AntiShadow", optional = true },
  },
  DRUID = {
    { name = "Mark of the Wild", satisfiedBy = { "Mark of the Wild", "Gift of the Wild" }, icon = "Interface\\Icons\\Spell_Nature_Regeneration" },
    { name = "Thorns", satisfiedBy = { "Thorns" }, icon = "Interface\\Icons\\Spell_Nature_Thorns", optional = true },
  },
  MAGE = {
    { name = "Arcane Intellect", satisfiedBy = { "Arcane Intellect", "Arcane Brilliance" }, icon = "Interface\\Icons\\Spell_Holy_MagicalSentry", manaOnly = true },
  },
  PALADIN = {
    { name = "Blessing", satisfiedBy = { "Blessing of Kings", "Blessing of Might", "Blessing of Wisdom", "Blessing of Salvation", "Blessing of Light", "Blessing of Sanctuary",
      "Greater Blessing of Kings", "Greater Blessing of Might", "Greater Blessing of Wisdom", "Greater Blessing of Salvation", "Greater Blessing of Light", "Greater Blessing of Sanctuary" },
      icon = "Interface\\Icons\\Spell_Magic_MageArmor" },
  },
  SHAMAN = {},
  WARLOCK = {},
  WARRIOR = {}, ROGUE = {}, HUNTER = {},
}

function HH.MissingBuffSpells(class)
  return BUFFS[class] or {}
end

-- Shields the healer applies and wants to see on frames.
function HH.ShieldSpells(class)
  if class == "PRIEST" then return { "Power Word: Shield" } end
  if class == "SHAMAN" and not isClassicEra() then return { "Earth Shield" } end
  return {}
end

HH.WEAKENED_SOUL = "Weakened Soul"

-- AoE heal scope per class: "party" = caster's party; "chain" = jump range from target.
HH.AOE_HEAL = {
  PRIEST = { spell = "Prayer of Healing", scope = "party" },
  SHAMAN = { spell = "Chain Heal", scope = "chain", range = 12.5 },
  DRUID  = { spell = "Tranquility", scope = "party" },
}

-- Mana users (power bar "healer only" mode shows for these when they are healers; for simplicity any mana class).
HH.MANA_CLASSES = { PRIEST = true, SHAMAN = true, PALADIN = true, DRUID = true, MAGE = true, WARLOCK = true, HUNTER = true }
