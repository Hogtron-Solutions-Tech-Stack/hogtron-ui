-- Gear: the upgrade finder, gear sets and the wishlist (the Sixty Upgrades part, in game).
--
-- Upgrade finder: for every gear slot, what you wear now against every item Atlas knows a source for (journal,
-- seen drops, curated) plus what sits in your bags, scored with the weights of your role. It can only rank items
-- the client will describe; an item the server has not sent yet is asked for and appears on the next refresh.
local A = HogHealsAtlas

local Gear = {}
A.Gear = Gear

Gear.SLOTS = {
  { id = 1, name = "Head" }, { id = 2, name = "Neck" }, { id = 3, name = "Shoulder" }, { id = 15, name = "Back" },
  { id = 5, name = "Chest" }, { id = 9, name = "Wrist" }, { id = 10, name = "Hands" }, { id = 6, name = "Waist" },
  { id = 7, name = "Legs" }, { id = 8, name = "Feet" }, { id = 11, name = "Ring 1" }, { id = 12, name = "Ring 2" },
  { id = 13, name = "Trinket 1" }, { id = 14, name = "Trinket 2" }, { id = 16, name = "Main hand" },
  { id = 17, name = "Off hand" }, { id = 18, name = "Ranged" },
}
Gear.SLOT_NAME = {}
for _, s in ipairs(Gear.SLOTS) do Gear.SLOT_NAME[s.id] = s.name end

-- where an item can go
Gear.EQUIP = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_WAIST = { 6 },
  INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_SHIELD = { 17 },
  INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

-- armour a class may wear: subclass 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield; { from level }
local ARMOR = {
  [1] = { ALL = 1 },
  [2] = { DRUID = 1, ROGUE = 1, HUNTER = 1, SHAMAN = 1, WARRIOR = 1, PALADIN = 1 },
  [3] = { WARRIOR = 1, PALADIN = 1, HUNTER = 40, SHAMAN = 40 },
  [4] = { WARRIOR = 40, PALADIN = 40 },
  [6] = { WARRIOR = 1, PALADIN = 1, SHAMAN = 1 },
}
-- who may hold an off-hand weapon
local DUAL = { ROGUE = 1, WARRIOR = 20, HUNTER = 20 }

--- Can this class wear it at this level? false, "why" when not. Weapon skills are not checked (the client has no
-- plain list of them here): weapons pass, and the tooltip shows red text if you cannot use one.
function Gear.Usable(info, class, level)
  if not info or not info.equipLoc or not Gear.EQUIP[info.equipLoc] then return false, "not gear" end
  if info.classID == 4 and info.equipLoc ~= "INVTYPE_CLOAK" then
    local rule = ARMOR[info.subClassID or 0]
    if rule then
      local from = rule.ALL or rule[class]
      if not from then return false, "armour type" end
      if level < from then return false, "armour type until " .. from end
    end
  end
  if info.equipLoc == "INVTYPE_WEAPONOFFHAND" and info.classID == 2 then
    local from = DUAL[class]
    if not from or level < from then return false, "cannot dual wield" end
  end
  return true
end

-- ------------------------------------------------------------------------------------------------ what you wear
function Gear.Equipped(slot)
  local link = A.str(A.call(rawget(_G, "GetInventoryItemLink"), "player", slot))
  if not link then return nil end
  local id = A.ItemIDFromLink(link)
  return { id = id, link = link, info = A.ItemInfo(link), stats = A.Stats.Of(link) }
end

function Gear.BagItems()
  local out = {}
  local slots = A.fn("C_Container.GetContainerNumSlots") or rawget(_G, "GetContainerNumSlots")
  local link = A.fn("C_Container.GetContainerItemLink") or rawget(_G, "GetContainerItemLink")
  if not slots or not link then return out end
  for bag = 0, (rawget(_G, "NUM_BAG_SLOTS") or 4) do
    for slot = 1, A.num(A.call(slots, bag)) or 0 do
      local l = A.str(A.call(link, bag, slot))
      local id = l and A.ItemIDFromLink(l)
      if id then out[#out + 1] = { id = id, link = l } end
    end
  end
  return out
end

-- ------------------------------------------------------------------------------------------------ upgrade finder
--- Upgrades per slot, best first: { [slotId] = { current = {...}|nil, currentScore, list = { { id, info, score,
-- delta, source, where = "bag"|"drop", level } } } }. opts: role, futureLevels, perSlot.
function Gear.Upgrades(opts)
  opts = opts or {}
  local class, level = A.playerClass(), A.playerLevel()
  local weights = A.Stats.Weights(opts.role)
  local future = opts.futureLevels or A.cfg().futureLevels or 0
  local perSlot = opts.perSlot or 8
  local out, unknown = {}, 0

  for _, s in ipairs(Gear.SLOTS) do
    local cur = Gear.Equipped(s.id)
    out[s.id] = { slot = s.id, name = s.name, current = cur, currentScore = cur and A.Stats.Score(cur.stats, weights) or 0, list = {} }
  end

  local pool, seen = {}, {}
  for _, b in ipairs(Gear.BagItems()) do
    if not seen[b.id] then seen[b.id] = true pool[#pool + 1] = { id = b.id, link = b.link, where = "bag" } end
  end
  for _, id in ipairs(A.Store.AllItems()) do
    if not seen[id] then seen[id] = true pool[#pool + 1] = { id = id, where = "drop" } end
  end

  for _, c in ipairs(pool) do
    local info = A.ItemInfo(c.link or c.id)
    if not info or info.partial then
      unknown = unknown + 1
    elseif Gear.Usable(info, class, level) and info.minLevel <= level + future then
      local stats = A.Stats.Of(c.link or info.link or c.id)
      local score = A.Stats.Score(stats, weights)
      local slots = Gear.EQUIP[info.equipLoc]
      -- two slots (rings, trinkets, one-handers): measured against the weaker of the two
      local target
      for _, sid in ipairs(slots) do
        local row = out[sid]
        local wearing = row.current and row.current.id == info.id
        if not wearing and (not target or row.currentScore < out[target].currentScore) then target = sid end
        if wearing then target = nil break end
      end
      if target then
        local delta = math.floor((score - out[target].currentScore) * 10 + 0.5) / 10
        if delta > 0 then
          table.insert(out[target].list, { id = info.id, info = info, stats = stats, score = score, delta = delta,
            where = c.where, source = c.where == "bag" and "In your bags" or A.Store.SourceText(info.id),
            later = info.minLevel > level and info.minLevel or nil })
        end
      end
    end
  end

  for _, row in pairs(out) do
    table.sort(row.list, function(a, b)
      if (a.later ~= nil) ~= (b.later ~= nil) then return a.later == nil end   -- wearable now first
      if a.delta ~= b.delta then return a.delta > b.delta end
      return a.id < b.id
    end)
    while #row.list > perSlot do table.remove(row.list) end
  end
  return out, unknown
end

--- The finder as one flat list for the window: a slot header row, then its upgrades.
function Gear.UpgradeRows(opts)
  local up, unknown = Gear.Upgrades(opts)
  local rows = {}
  for _, s in ipairs(Gear.SLOTS) do
    local row = up[s.id]
    if #row.list > 0 then
      rows[#rows + 1] = { header = true, slot = s.id, text = s.name, current = row.current, score = row.currentScore }
      for _, u in ipairs(row.list) do u.slot = s.id rows[#rows + 1] = u end
    end
  end
  return rows, unknown
end

-- ------------------------------------------------------------------------------------------------ wishlist
local function wish()
  local db = A.Store.db()
  local key = A.charKey()
  db.wish[key] = db.wish[key] or {}
  return db.wish[key]
end

function Gear.IsWished(id) return wish()[A.num(id) or -1] == true end

function Gear.ToggleWish(id)
  id = A.num(id)
  if not id then return nil end
  local w = wish()
  if w[id] then w[id] = nil else w[id] = true end
  return w[id] == true
end

--- Wishlist rows: { id, info, source, have } sorted by dungeon then name. have = you wear or carry it.
function Gear.WishRows()
  local carried = {}
  for _, b in ipairs(Gear.BagItems()) do carried[b.id] = true end
  for _, s in ipairs(Gear.SLOTS) do local e = Gear.Equipped(s.id) if e and e.id then carried[e.id] = true end end
  local rows = {}
  for id in pairs(wish()) do
    local info = A.ItemInfo(id)
    rows[#rows + 1] = { id = id, info = info, source = A.Store.SourceText(id) or "source unknown", have = carried[id] == true }
  end
  table.sort(rows, function(a, b)
    if a.source ~= b.source then return a.source < b.source end
    return a.id < b.id
  end)
  return rows
end

-- ------------------------------------------------------------------------------------------------ sets
local function sets()
  local db = A.Store.db()
  local key = A.charKey()
  db.sets[key] = db.sets[key] or {}
  return db.sets[key]
end

Gear.MAX_SETS = 12

function Gear.Sets() return sets() end

--- New set. from = "equipped" copies what you wear now; anything else starts empty.
function Gear.NewSet(name, from)
  local list = sets()
  if #list >= Gear.MAX_SETS then return nil, "set limit reached (" .. Gear.MAX_SETS .. ")" end
  name = (A.str(name) and name ~= "") and name or ("Set " .. (#list + 1))
  local set = { name = name, items = {}, made = A.now() }
  if from == "equipped" then
    for _, s in ipairs(Gear.SLOTS) do
      local e = Gear.Equipped(s.id)
      if e and e.id then set.items[s.id] = e.id end
    end
  end
  list[#list + 1] = set
  return set, #list
end

function Gear.DeleteSet(index)
  local list = sets()
  if list[index] then table.remove(list, index) return true end
  return false
end

--- Put an item in a set. slot may be nil: the first slot the item fits that is empty, else its first slot.
function Gear.SetItem(index, itemID, slot)
  local set = sets()[index]
  itemID = A.num(itemID)
  if not set or not itemID then return false, "no such set" end
  local info = A.ItemInfo(itemID)
  local fits = info and Gear.EQUIP[info.equipLoc or ""]
  if not slot then
    if not fits then return false, "item not known yet" end
    slot = fits[1]
    for _, sid in ipairs(fits) do if not set.items[sid] then slot = sid break end end
  elseif fits then
    local ok = false
    for _, sid in ipairs(fits) do if sid == slot then ok = true end end
    if not ok then return false, "does not fit that slot" end
  end
  if info and info.equipLoc == "INVTYPE_2HWEAPON" then set.items[17] = nil end
  set.items[slot] = itemID
  return true, slot
end

function Gear.ClearSlot(index, slot)
  local set = sets()[index]
  if set then set.items[slot] = nil return true end
  return false
end

--- Totals of a set: stats summed, score for the role, how many pieces you already own, what is still missing.
-- gain = what finishing the set is worth: the set as you would wear it (your current item stays in every slot
-- the set leaves empty) against what you wear now. A half-filled set is not judged as if you went naked.
function Gear.SetSummary(index, role)
  local set = sets()[index]
  if not set then return nil end
  local weights = A.Stats.Weights(role)
  local carried = {}
  for _, b in ipairs(Gear.BagItems()) do carried[b.id] = true end
  for _, s in ipairs(Gear.SLOTS) do local e = Gear.Equipped(s.id) if e and e.id then carried[e.id] = true end end
  local total, pieces, owned, rows, unknown = {}, 0, 0, {}, 0
  local worn, wornTotal = {}, {}
  for _, s in ipairs(Gear.SLOTS) do
    local id = set.items[s.id]
    local row = { slot = s.id, slotName = s.name, id = id }
    local e = Gear.Equipped(s.id)
    for k, v in pairs(e and e.stats or {}) do
      wornTotal[k] = (wornTotal[k] or 0) + v
      if not id then worn[k] = (worn[k] or 0) + v end
    end
    row.worn = e and e.info and e.info.name or nil
    if id then
      pieces = pieces + 1
      row.info = A.ItemInfo(id)
      row.have = carried[id] == true
      if row.have then owned = owned + 1 end
      row.source = A.Store.SourceText(id)
      local stats = A.Stats.Of(id)
      if next(stats) == nil then unknown = unknown + 1 end
      row.score = A.Stats.Score(stats, weights)
      for k, v in pairs(stats) do total[k] = (total[k] or 0) + v end
    end
    rows[#rows + 1] = row
  end
  local asWorn = {}
  for k, v in pairs(total) do asWorn[k] = v end
  for k, v in pairs(worn) do asWorn[k] = (asWorn[k] or 0) + v end
  local score, now = A.Stats.Score(total, weights), A.Stats.Score(wornTotal, weights)
  local gain = math.floor((A.Stats.Score(asWorn, weights) - now) * 10 + 0.5) / 10
  return { name = set.name, rows = rows, stats = total, score = score, pieces = pieces,
    owned = owned, unknown = unknown, gain = gain, wornScore = now }
end

--- Score of what you wear now, for comparing against a set.
function Gear.EquippedScore(role)
  local weights = A.Stats.Weights(role)
  local total = {}
  for _, s in ipairs(Gear.SLOTS) do
    local e = Gear.Equipped(s.id)
    for k, v in pairs(e and e.stats or {}) do total[k] = (total[k] or 0) + v end
  end
  return A.Stats.Score(total, weights), total
end
