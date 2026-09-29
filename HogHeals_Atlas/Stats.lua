-- Stats: what an item gives, as plain numbers, and a score for a role.
--
-- Two readers, merged:
--   1. the client's stat table (C_Item.GetItemStats): exact for the basic stats
--   2. the tooltip text: the only place Classic-style items keep "Equip:" bonuses (healing, spell damage, mana per
--      5 sec, crit, hit), armour and weapon damage per second. English client text.
-- Tooltip numbers win over nothing, the stat table wins over the tooltip for the same stat.
local A = HogHealsAtlas

local Stats = { cache = {} }
A.Stats = Stats

Stats.NAMES = {
  sta = "Stamina", int = "Intellect", spi = "Spirit", str = "Strength", agi = "Agility", armor = "Armor",
  healing = "Healing", spelldmg = "Spell damage", mp5 = "Mana per 5 sec", spellcrit = "Spell crit %",
  spellhit = "Spell hit %", crit = "Crit %", hit = "Hit %", ap = "Attack power", dps = "Weapon DPS",
  defense = "Defense", dodge = "Dodge %", parry = "Parry %", block = "Block %",
}
Stats.ORDER = { "healing", "spelldmg", "int", "spi", "mp5", "spellcrit", "spellhit", "str", "agi", "ap", "crit", "hit",
  "dps", "sta", "armor", "defense", "dodge", "parry", "block" }

-- Points per 1 of each stat. Starting values, meant to be tuned in the options (weights are per role).
Stats.PRESETS = {
  healer = { healing = 1.0, spelldmg = 0.3, int = 0.9, spi = 0.7, mp5 = 2.5, spellcrit = 8, sta = 0.25, armor = 0.01 },
  caster = { spelldmg = 1.0, healing = 0.3, int = 0.5, spi = 0.2, mp5 = 1.0, spellcrit = 10, spellhit = 12, sta = 0.2, armor = 0.01 },
  melee = { str = 1.0, agi = 1.0, ap = 0.5, crit = 14, hit = 14, dps = 3.0, sta = 0.3, armor = 0.01 },
  ranged = { agi = 1.0, ap = 0.45, crit = 14, hit = 14, dps = 2.5, int = 0.2, sta = 0.3, armor = 0.01 },
  tank = { sta = 1.0, armor = 0.12, defense = 1.2, dodge = 12, parry = 12, block = 6, str = 0.5, agi = 0.5, hit = 6, dps = 1.0 },
}
Stats.ROLES = { "healer", "caster", "melee", "ranged", "tank" }
Stats.CLASS_ROLE = { PRIEST = "healer", SHAMAN = "healer", DRUID = "healer", PALADIN = "healer", MAGE = "caster",
  WARLOCK = "caster", WARRIOR = "melee", ROGUE = "melee", HUNTER = "ranged" }

-- the client's stat keys -> ours
local API_KEYS = {
  ITEM_MOD_STAMINA_SHORT = "sta", ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi",
  ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", RESISTANCE0_NAME = "armor",
  ITEM_MOD_SPELL_HEALING_DONE_SHORT = "healing", ITEM_MOD_SPELL_HEALING_DONE = "healing",
  ITEM_MOD_SPELL_POWER_SHORT = "spelldmg", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "spelldmg",
  ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_POWER_REGEN0_SHORT = "mp5",
  ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps",
  ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "defense",
}

-- tooltip lines -> stat. First capture is the number. Order matters: specific before general.
local PATTERNS = {
  { "^%+(%d+) Stamina", "sta" }, { "^%+(%d+) Intellect", "int" }, { "^%+(%d+) Spirit", "spi" },
  { "^%+(%d+) Strength", "str" }, { "^%+(%d+) Agility", "agi" },
  { "^(%d+) Armor", "armor" },
  { "%(([%d%.]+) damage per second%)", "dps" },
  { "healing done by spells and effects by up to (%d+)", "healing" },
  { "healing done by up to (%d+)", "healing" },
  { "damage and healing done by magical spells and effects by up to (%d+)", "both" },
  { "spell power by (%d+)", "both" },
  { "damage done by %a+ spells and effects by up to (%d+)", "school" },
  { "Restores (%d+) mana per 5 sec", "mp5" },
  { "critical strike with spells by (%d+)%%", "spellcrit" },
  { "chance to hit with spells by (%d+)%%", "spellhit" },
  { "chance to get a critical strike by (%d+)%%", "crit" },
  { "chance to hit by (%d+)%%", "hit" },
  { "%+(%d+) Attack Power", "ap" }, { "%+(%d+) [Aa]ttack [Pp]ower", "ap" },
  { "Increased Defense %+(%d+)", "defense" }, { "Increases [Dd]efense by (%d+)", "defense" },
  { "chance to dodge an attack by (%d+)%%", "dodge" },
  { "chance to parry an attack by (%d+)%%", "parry" },
  { "chance to block attacks with a shield by (%d+)%%", "block" },
}

--- Stats out of tooltip lines (a list of strings). Pure.
function Stats.Parse(lines)
  local out = {}
  local function add(k, v) out[k] = (out[k] or 0) + v end
  for _, line in ipairs(lines or {}) do
    if type(line) == "string" and not A.isSecret(line) then
      -- strip colour codes
      local text = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
      for _, p in ipairs(PATTERNS) do
        local n = text:match(p[1])
        if n then
          n = tonumber(n)
          if n then
            if p[2] == "both" then add("spelldmg", n) add("healing", n)
            elseif p[2] == "school" then add("spelldmg", n * 0.5)   -- one school only: worth half
            else add(p[2], n) end
          end
          break
        end
      end
    end
  end
  return out
end

local function tooltipLines(link)
  local f = A.fn("C_TooltipInfo.GetHyperlink")
  if not f then return nil end
  local data = A.call(f, link)
  if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
  local out = {}
  for _, l in ipairs(data.lines) do
    local t = type(l) == "table" and l.leftText or nil
    if A.str(t) then out[#out + 1] = t end
  end
  return out
end

--- Stats of an item (id or link): { sta = 5, ... }. Empty table when the client cannot tell yet.
function Stats.Of(item)
  local id = A.ItemIDFromLink(item)
  if not id then return {} end
  if Stats.cache[id] then return Stats.cache[id] end
  local link = (A.str(item) and item:find("item:", 1, true)) and item or ("item:" .. id)
  local out, complete = {}, false
  local lines = tooltipLines(link)
  if lines and #lines > 0 then
    out = Stats.Parse(lines)
    complete = true
  end
  local get = A.fn("C_Item.GetItemStats") or rawget(_G, "GetItemStats")
  local api = A.call(get, link)
  if type(api) == "table" then
    for k, v in pairs(api) do
      local key = API_KEYS[k]
      if key and A.num(v) then out[key] = v complete = true end
    end
  end
  if complete then Stats.cache[id] = out end
  return out
end

-- ------------------------------------------------------------------------------------------------ scoring
function Stats.Role()
  local r = A.cfg().role
  if r and r ~= "auto" and Stats.PRESETS[r] then return r end
  return Stats.CLASS_ROLE[A.playerClass()] or "melee"
end

--- Weights in force for a role: the preset with the player's own changes on top.
function Stats.Weights(role)
  role = role or Stats.Role()
  local out = {}
  for k, v in pairs(Stats.PRESETS[role] or {}) do out[k] = v end
  for k, v in pairs((A.cfg().weights or {})[role] or {}) do if type(v) == "number" then out[k] = v end end
  return out
end

function Stats.Score(stats, weights)
  local total = 0
  for k, v in pairs(stats or {}) do
    local w = weights[k]
    if w and type(v) == "number" then total = total + w * v end
  end
  return math.floor(total * 10 + 0.5) / 10
end

--- "+12 Int, +9 Spi" for a tooltip / row.
function Stats.Text(stats, max)
  local parts = {}
  for _, k in ipairs(Stats.ORDER) do
    local v = stats[k]
    if v and v ~= 0 and #parts < (max or 4) then
      parts[#parts + 1] = ("%s %s"):format(v % 1 == 0 and ("%d"):format(v) or ("%.1f"):format(v), Stats.NAMES[k])
    end
  end
  return table.concat(parts, ", ")
end
