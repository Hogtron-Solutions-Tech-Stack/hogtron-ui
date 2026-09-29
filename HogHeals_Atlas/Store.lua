-- Store: owns everything Atlas remembers (HogHealsDB.global.atlas, account-wide). Nothing else writes it.
--
--   bosses[dungeonKey][bossName] = { npc, enc, first, src }
--   loot[dungeonKey][bossName][itemID] = { n = times seen, first = "date", src = "seen" | "group" | "journal" }
--   dungeons[key] = { name, inst }        dungeons the shipped list does not know (found in play / in the journal)
--   npcNames[npcID] = "Name"              learned from target / mouseover inside instances
--   runs = { ... }                        loot log, newest first (Capture.lua)
--   wish[charKey][itemID] = true          wishlist (Gear.lua)
--   sets[charKey] = { { name, items } }   gear sets (Gear.lua)
--
-- Hard caps keep the saved file small: 5000 boss-item pairs (oldest evicted first), 500 npc names, 20 runs.
local A = HogHealsAtlas
local HH = HogHeals

local Store = { CAP = 5000, NPC_CAP = 500, DUNGEON_CAP = 60, TRASH = "Trash and chests" }
A.Store = Store

-- a better source replaces a weaker one on the same item; never the other way round
Store.RANK = { reported = 1, journal = 2, group = 3, seen = 4 }

function Store.db()
  local g = HH.db and HH.db.global
  if not g then Store.mem = Store.mem or {} g = Store.mem end
  local a = g.atlas
  if type(a) ~= "table" then a = {} g.atlas = a end
  a.schema = a.schema or 1
  for _, k in ipairs({ "bosses", "loot", "dungeons", "npcNames", "runs", "wish", "sets" }) do
    if type(a[k]) ~= "table" then a[k] = {} end
  end
  a.count = a.count or 0
  return a
end

-- ------------------------------------------------------------------------------------------------ dungeons
function Store.Dungeon(key)
  local d = A.Data.byKey[key]
  if d then return d end
  local e = Store.db().dungeons[key]
  if e then return { key = key, name = e.name, inst = e.inst, bosses = {}, found = true, min = e.min, max = e.max } end
end

--- Key for a dungeon by name / instance id; makes a row for one the shipped list does not know.
function Store.DungeonKey(name, inst, bossName)
  if bossName then
    local d = A.Data.FindBoss(bossName, inst)
    if d then return d.key end
  end
  name = A.str(name)
  if name and A.Data.byName[name:lower()] then return A.Data.byName[name:lower()].key end
  inst = A.num(inst)
  if inst and A.Data.byInst[inst] then
    local pool = A.Data.byInst[inst]
    if #pool == 1 then return pool[1].key end
    -- several wings behind one id and no boss to tell them apart: the wing named like the instance, else the first
    for _, d in ipairs(pool) do if name and d.name:lower():find(name:lower(), 1, true) then return d.key end end
    return pool[1].key
  end
  if not name and not inst then return nil end
  local key = inst and ("inst:" .. inst) or ("name:" .. name:lower())
  local db = Store.db()
  if not db.dungeons[key] then
    local n = 0
    for _ in pairs(db.dungeons) do n = n + 1 end
    if n >= Store.DUNGEON_CAP then return nil end
    db.dungeons[key] = { name = name or ("Instance " .. tostring(inst)), inst = inst, first = A.now() }
  end
  return key
end

--- All dungeons the window lists: the shipped ones, then the ones found in play.
function Store.ExtraDungeons()
  local out = {}
  for key in pairs(Store.db().dungeons) do out[#out + 1] = Store.Dungeon(key) end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- ------------------------------------------------------------------------------------------------ bosses
function Store.AddBoss(dkey, name, fields)
  name = A.str(name)
  if not dkey or not name or name == "" then return nil end
  local db = Store.db()
  db.bosses[dkey] = db.bosses[dkey] or {}
  local b = db.bosses[dkey][name]
  if not b then b = { first = A.now() } db.bosses[dkey][name] = b end
  for k, v in pairs(fields or {}) do if b[k] == nil then b[k] = v end end
  return b
end

--- Boss rows for the window, in kill order: shipped bosses, shipped rares, bosses found in play, then the trash row
-- when it holds anything. Each: { name, rare, found, items = count }.
function Store.Bosses(dkey)
  local d = Store.Dungeon(dkey)
  if not d then return {} end
  local db, out, seen = Store.db(), {}, {}
  local function count(name)
    local n = 0
    for _ in pairs((db.loot[dkey] or {})[name] or {}) do n = n + 1 end
    local cur = (A.Data.Curated[dkey] or {})[name]
    if cur then n = n + #cur end
    return n
  end
  local function add(name, extra)
    if seen[name] then return end
    seen[name] = true
    local row = { name = name, items = count(name) }
    for k, v in pairs(extra or {}) do row[k] = v end
    out[#out + 1] = row
  end
  for _, b in ipairs(d.bosses or {}) do add(b) end
  for _, b in ipairs(d.rares or {}) do add(b, { rare = true }) end
  local found = {}
  for name in pairs(db.bosses[dkey] or {}) do if name ~= Store.TRASH then found[#found + 1] = name end end
  for name in pairs(db.loot[dkey] or {}) do if name ~= Store.TRASH and not (db.bosses[dkey] or {})[name] then found[#found + 1] = name end end
  table.sort(found)
  for _, name in ipairs(found) do add(name, { found = true }) end
  if count(Store.TRASH) > 0 then add(Store.TRASH, { trash = true }) end
  return out
end

-- ------------------------------------------------------------------------------------------------ loot
local function evictOldest(db)
  local oldest, od, ob, oi
  for dkey, bosses in pairs(db.loot) do
    for boss, items in pairs(bosses) do
      for id, e in pairs(items) do
        local stamp = e.first or ""
        if not oldest or stamp < oldest then oldest, od, ob, oi = stamp, dkey, boss, id end
      end
    end
  end
  if od then
    db.loot[od][ob][oi] = nil
    db.count = math.max(0, db.count - 1)
  end
end

--- One drop. Returns true when the boss-item pair is new. src: "seen" | "group" | "journal".
function Store.Record(dkey, boss, itemID, src)
  itemID = A.num(itemID)
  boss = A.str(boss)
  if not dkey or not boss or boss == "" or not itemID or itemID <= 0 then return false end
  src = Store.RANK[src] and src or "seen"
  local db = Store.db()
  db.loot[dkey] = db.loot[dkey] or {}
  db.loot[dkey][boss] = db.loot[dkey][boss] or {}
  local e = db.loot[dkey][boss][itemID]
  local counts = (src == "seen" or src == "group")
  if e then
    if counts then e.n = (e.n or 0) + 1 end
    if Store.RANK[src] > (Store.RANK[e.src] or 0) then e.src = src end
    return false
  end
  if db.count >= Store.CAP then evictOldest(db) end
  db.loot[dkey][boss][itemID] = { n = counts and 1 or 0, first = A.now(), src = src }
  db.count = db.count + 1
  Store.index = nil
  return true
end

--- Drops of one boss for the window: { id, src, n }, best source first, then by item id.
function Store.GetBossLoot(dkey, boss)
  local out, have = {}, {}
  for id, e in pairs(((Store.db().loot[dkey] or {})[boss]) or {}) do
    out[#out + 1] = { id = id, src = e.src, n = e.n or 0 }
    have[id] = true
  end
  for _, id in ipairs(((A.Data.Curated[dkey] or {})[boss]) or {}) do
    if not have[id] then out[#out + 1] = { id = id, src = "reported", n = 0 } have[id] = true end
  end
  table.sort(out, function(a, b)
    local ra, rb = Store.RANK[a.src] or 0, Store.RANK[b.src] or 0
    if ra ~= rb then return ra > rb end
    return a.id < b.id
  end)
  return out
end

local function buildIndex()
  local idx = {}
  local function put(id, dkey, boss, src)
    idx[id] = idx[id] or {}
    for _, s in ipairs(idx[id]) do if s.dungeon == dkey and s.boss == boss then return end end
    table.insert(idx[id], { dungeon = dkey, boss = boss, src = src })
  end
  for dkey, bosses in pairs(Store.db().loot) do
    for boss, items in pairs(bosses) do for id, e in pairs(items) do put(id, dkey, boss, e.src) end end
  end
  for dkey, bosses in pairs(A.Data.Curated) do
    for boss, items in pairs(bosses) do for _, id in ipairs(items) do put(id, dkey, boss, "reported") end end
  end
  for _, list in pairs(idx) do
    table.sort(list, function(a, b)
      if a.dungeon ~= b.dungeon then return a.dungeon < b.dungeon end
      return a.boss < b.boss
    end)
  end
  return idx
end

--- Where an item drops: { { dungeon = key, boss = name, src }, ... } or nil.
function Store.SourceOf(itemID)
  Store.index = Store.index or buildIndex()
  return Store.index[itemID]
end

--- "Boss (Dungeon)" for the first source, "+N more" when there are others.
function Store.SourceText(itemID)
  local list = Store.SourceOf(itemID)
  if not list or #list == 0 then return nil end
  local s = list[1]
  local d = Store.Dungeon(s.dungeon)
  local text = ("%s (%s)"):format(s.boss, d and d.name or s.dungeon)
  if #list > 1 then text = text .. (" +%d more"):format(#list - 1) end
  return text, list
end

--- Every item id Atlas knows a source for.
function Store.AllItems()
  Store.index = Store.index or buildIndex()
  local out = {}
  for id in pairs(Store.index) do out[#out + 1] = id end
  table.sort(out)
  return out
end

-- ------------------------------------------------------------------------------------------------ npc names
function Store.LearnNpc(npcID, name)
  npcID, name = A.num(npcID), A.str(name)
  if not npcID or not name or name == "" then return end
  local db = Store.db()
  if db.npcNames[npcID] then return end
  local n = 0
  for _ in pairs(db.npcNames) do n = n + 1 end
  if n >= Store.NPC_CAP then return end
  db.npcNames[npcID] = name
end

function Store.NpcName(npcID) return Store.db().npcNames[A.num(npcID) or -1] end
