-- WhereNext: "I'm level 22 in the Barrens - where do I go, what do I run, what could I get?" One tab and one chat
-- command (/hh next) that put the level, the zone, the quest log and the dungeon list together.
--
-- Sean 2026-10-05: "what's my next upgrade, whether it be a dungeon or a quest in the region I'm in or nearby
-- regions, to chase upgrades as we're leveling".
--
-- Three sections, every row sorted by fit for YOUR level and distance from where you STAND:
--   Dungeons   green / orange for your level; same zone first, then next door, same continent, across the sea.
--              Under each: the quests for it in your log, and what it is known to drop that fits your slots -
--              real drops Atlas has seen (scored against what you wear) above the old-game name list (labelled).
--   Quests     your log by zone, ready-to-turn-in first, each level coloured against yours; "here" on your zone.
--   Zones      zones at your level, nearest first, with the dungeons inside them.
-- Nothing here is a promise: the level ranges and the name list come from the old game and say so.
local A = HogHealsAtlas
local HH = HogHeals

local WN = {}
A.WhereNext = WN

local C = A.COLORS

-- armour a class may wear (same table as Gear.lua's, by kind name); { from level }
local WEAR = {
  cloth = { ALL = 1 },
  leather = { DRUID = 1, ROGUE = 1, HUNTER = 1, SHAMAN = 1, WARRIOR = 1, PALADIN = 1 },
  mail = { WARRIOR = 1, PALADIN = 1, HUNTER = 40, SHAMAN = 40 },
  plate = { WARRIOR = 40, PALADIN = 40 },
}
-- named-drop slot -> Gear slot id (the first of a pair; rings / trinkets / weapons compare against the weaker later)
local SLOT_ID = { Head = 1, Neck = 2, Shoulder = 3, Back = 15, Chest = 5, Wrist = 9, Hands = 10, Waist = 6, Legs = 7, Feet = 8,
  Ring = 11, Trinket = 13, Weapon = 16, TwoHand = 16, OffHand = 17, Shield = 17, Ranged = 18, Wand = 18 }
WN.SLOT_ID = SLOT_ID

--- Can this class wear armour of this kind at this level? Non-armour (nil kind) always passes.
function WN.Wearable(kind, class, level)
  if not kind then return true end
  local rule = WEAR[kind]
  if not rule then return true end
  local from = rule.ALL or rule[class]
  if not from then return false end
  return (level or 1) >= from
end

--- The zone you stand in, as the list knows it (nil when the name is secret / unknown to the list).
function WN.ZoneName()
  local f = rawget(_G, "GetRealZoneText") or rawget(_G, "GetZoneText")
  return A.str(A.call(f))
end

function WN.Zone() return A.Data.Zone(WN.ZoneName()) end

--- Distance class from zone `from` to zone name `to`: 0 same zone, 1 next door, 2 same continent, 3 elsewhere.
function WN.Distance(from, to)
  local z = A.Data.Zone(to)
  if not from or not z then return 3 end
  if from.name == z.name then return 0 end
  for _, n in ipairs(from.near or {}) do if n == z.name then return 1 end end
  if from.continent == z.continent then return 2 end
  return 3
end
WN.DISTANCE = { [0] = "here", [1] = "next door", [2] = "this continent", [3] = "across the sea" }

local BAND_RANK = { green = 0, orange = 1, red = 2, grey = 3, unknown = 4 }

-- ------------------------------------------------------------------------------------------------ dungeons
--- What you wear in a slot, or nil: { name, ilvl } (two-slot kinds take the weaker of the pair).
local function worn(slotId)
  local ids = { slotId }
  if slotId == 11 then ids = { 11, 12 } elseif slotId == 13 then ids = { 13, 14 } end
  local weakest
  for _, id in ipairs(ids) do
    local e = A.Gear.Equipped(id)
    local ilvl = e and e.info and A.num(e.info.ilvl) or 0
    if not e then return nil end   -- an empty slot is the weakest thing you can wear
    if not weakest or ilvl < weakest.ilvl then weakest = { name = e.info and e.info.name or "?", ilvl = ilvl } end
  end
  return weakest
end

--- Named drops a dungeon is known for that YOU could wear, each with what you have in that slot now.
--   { boss, name, slot, kind, now = { name, ilvl } | nil, look = "empty slot" | "below item level N" | nil }
function WN.NamedFor(dkey, class, level, max)
  local out = {}
  for _, d in ipairs(A.Data.NamedDrops(dkey)) do
    if WN.Wearable(d.kind, class, level) then
      local slotId = SLOT_ID[d.slot]
      local have = slotId and worn(slotId) or nil
      local look
      if slotId and not have then look = "empty slot"
      elseif have and max and have.ilvl > 0 and have.ilvl < max then look = ("yours is item level %d"):format(have.ilvl) end
      out[#out + 1] = { boss = d.boss, name = d.name, slot = d.slot, kind = d.kind, now = have, look = look }
    end
  end
  return out
end

--- Dungeons worth your time, best first. opts.all = include red / grey too.
--   { dungeon, min, max, band, source, distance, foreign, upgrades, best, quests, ready, named = {...} }
function WN.Dungeons(opts)
  opts = opts or {}
  local L, faction, class = A.playerLevel(), A.playerFaction(), A.playerClass()
  local here = WN.Zone()
  local out = {}
  for _, e in ipairs(A.Levels.List(L, not opts.all)) do
    local d = e.dungeon
    local row = { dungeon = d, min = e.min, max = e.max, band = e.band, source = e.source }
    row.distance = WN.Distance(here, d.zone)
    row.foreign = (d.faction and faction and d.faction ~= faction) and true or false
    local items = A.Store.DungeonItems(d.key)
    if #items > 0 then row.upgrades, row.best = A.Gear.CountUpgrades(items) else row.upgrades, row.best = 0, 0 end
    local q, active, ready = A.DungeonQuests.Summary(d.key)
    row.quests, row.active, row.ready = q, active or 0, ready or 0
    row.named = WN.NamedFor(d.key, class, L, e.max)
    out[#out + 1] = row
  end
  table.sort(out, function(a, b)
    local ra, rb = BAND_RANK[a.band] or 4, BAND_RANK[b.band] or 4
    if ra ~= rb then return ra < rb end
    local da, db = a.distance + (a.foreign and 2 or 0), b.distance + (b.foreign and 2 or 0)
    if da ~= db then return da < db end
    if a.upgrades ~= b.upgrades then return a.upgrades > b.upgrades end
    if a.min ~= b.min then return a.min < b.min end
    return a.dungeon.name < b.dungeon.name
  end)
  return out
end

-- ------------------------------------------------------------------------------------------------ quests
--- Your quest log by zone: { { zone, here, quests = { { title, level, band, ready, progress } } } }, the zone you
-- stand in first, then ready-to-turn-in zones, then by nearest. nil when HogTron UI Quests is not loaded.
function WN.Quests()
  local q = rawget(_G, "HogHealsQuests")
  if type(q) ~= "table" or type(q.Data) ~= "table" or type(q.Data.List) ~= "function" then return nil end
  local ok, list = pcall(q.Data.List)
  if not ok or type(list) ~= "table" then return nil end
  local L = A.playerLevel()
  local here = WN.Zone()
  local hereName = WN.ZoneName()
  local groups, byZone = {}, {}
  for _, e in ipairs(list) do
    local zone = A.str(e.zone) or "Elsewhere"
    local g = byZone[zone]
    if not g then
      g = { zone = zone, quests = {}, ready = 0, distance = WN.Distance(here, zone),
        here = hereName ~= nil and zone:lower() == hereName:lower() }
      byZone[zone] = g
      groups[#groups + 1] = g
    end
    local lvl = A.num(e.level)
    local band = lvl and A.Levels.Band(L, lvl - 4, lvl + 5) or "unknown"   -- green from 2 under to 5 over its level, orange 4 under, grey past that
    local done, all = 0, 0
    for _, o in ipairs(e.objectives or {}) do all = all + 1 if o.done then done = done + 1 end end
    local row = { title = e.title, level = lvl, band = band, ready = e.complete and true or false,
      progress = all > 0 and ("%d/%d"):format(done, all) or nil }
    if row.ready then g.ready = g.ready + 1 end
    g.quests[#g.quests + 1] = row
  end
  for _, g in ipairs(groups) do
    table.sort(g.quests, function(a, b)
      if a.ready ~= b.ready then return a.ready end
      if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
      return a.title < b.title
    end)
  end
  table.sort(groups, function(a, b)
    if a.here ~= b.here then return a.here end
    if (a.ready > 0) ~= (b.ready > 0) then return a.ready > 0 end
    if a.distance ~= b.distance then return a.distance < b.distance end
    return a.zone < b.zone
  end)
  return groups
end

-- ------------------------------------------------------------------------------------------------ zones
--- Zones at your level, nearest first: { zone, band, distance, foreign, dungeons = { names } }.
function WN.Zones(opts)
  opts = opts or {}
  local L, faction = A.playerLevel(), A.playerFaction()
  local here = WN.Zone()
  local inZone = {}
  for _, d in ipairs(A.Data.Dungeons) do
    if d.zone then inZone[d.zone] = inZone[d.zone] or {} table.insert(inZone[d.zone], d.name) end
  end
  local out = {}
  for _, z in ipairs(A.Data.Zones) do
    if z.min and z.max then
      local band = A.Levels.Band(L, z.min, z.max)
      if opts.all or band == "green" or band == "orange" then
        out[#out + 1] = { zone = z, band = band, distance = WN.Distance(here, z.name),
          foreign = (z.faction and faction and z.faction ~= faction) and true or false, dungeons = inZone[z.name] or {} }
      end
    end
  end
  table.sort(out, function(a, b)
    local ra, rb = BAND_RANK[a.band] or 4, BAND_RANK[b.band] or 4
    local da, db = a.distance + (a.foreign and 2 or 0), b.distance + (b.foreign and 2 or 0)
    if da ~= db then return da < db end
    if ra ~= rb then return ra < rb end
    return a.zone.name < b.zone.name
  end)
  return out
end

-- ------------------------------------------------------------------------------------------------ rows + chat
local SAY = { green = "right for you", orange = "hard", red = "too low", grey = "outgrown" }

--- Rows for the window's "Where next" tab (List rows: text / right / mid / colours / key for click-through).
function WN.Rows(opts)
  opts = opts or {}
  local rows = {}
  local L = A.playerLevel()
  local hereName = WN.ZoneName()
  local here = WN.Zone()
  rows[#rows + 1] = { header = true, text = ("Level %d, %s%s"):format(L, hereName or "somewhere the list does not know",
    (hereName and not here) and " (not in the zone list)" or ""), right = A.playerFaction() == "H" and "Horde" or A.playerFaction() == "A" and "Alliance" or "" }

  -- dungeons
  local ds = WN.Dungeons(opts)
  rows[#rows + 1] = { header = true, text = "Dungeons for you", right = ("%d"):format(#ds) }
  if #ds == 0 then rows[#rows + 1] = { text = "None fit your level right now. Turn on 'Show all' to see every dungeon.", color = C.grey } end
  for _, r in ipairs(ds) do
    local d = r.dungeon
    local c = A.COLORS[r.band] or C.cream
    local where = WN.DISTANCE[r.distance] or ""
    if r.foreign then where = where .. ", other side's land" end
    rows[#rows + 1] = { key = d.key, text = d.name, right = ("%d-%d  %s"):format(r.min, r.max, SAY[r.band] or ""), rightColor = c, color = c,
      mid = ("%s, %s"):format(d.zone or "?", where), midColor = r.distance <= 1 and C.cyan or C.grey,
      tip = (d.where or "") }
    if r.quests then
      rows[#rows + 1] = { key = d.key, text = ("quests in your log: %s"):format(r.quests), indent = 14,
        color = r.ready > 0 and C.green or C.cream }
    end
    if r.upgrades > 0 then
      rows[#rows + 1] = { key = d.key, text = ("%d known drop(s) better than what you wear (best +%.1f)"):format(r.upgrades, r.best), indent = 14, color = C.green }
    end
    local shown = 0
    for _, n in ipairs(r.named) do
      if n.look and shown < (opts.namedPerDungeon or 4) then
        shown = shown + 1
        rows[#rows + 1] = { key = d.key, text = ("%s  -  %s"):format(n.name, n.boss), indent = 14, color = C.cream,
          mid = ("%s%s: %s"):format(n.slot, n.kind and (" (" .. n.kind .. ")") or "", n.look), midColor = n.look == "empty slot" and C.amber or C.grey,
          right = "old list", rightColor = C.grey }
      end
    end
  end

  -- quests
  local groups = WN.Quests()
  rows[#rows + 1] = { text = "" }
  rows[#rows + 1] = { header = true, text = "Your quest log, by zone", right = groups and ("%d zones"):format(#groups) or "" }
  if not groups then
    rows[#rows + 1] = { text = "Turn on HogTron UI Quests to see your log here.", color = C.grey }
  elseif #groups == 0 then
    rows[#rows + 1] = { text = "Your log is empty.", color = C.grey }
  else
    for _, g in ipairs(groups) do
      rows[#rows + 1] = { text = g.zone .. (g.here and "   (here)" or ""), right = g.ready > 0 and ("%d to turn in"):format(g.ready) or ("%s"):format(WN.DISTANCE[g.distance] or ""),
        rightColor = g.ready > 0 and C.green or C.grey, color = g.here and C.cyan or C.cream }
      for _, q in ipairs(g.quests) do
        local c = q.ready and C.green or (A.COLORS[q.band] or C.cream)
        rows[#rows + 1] = { text = q.title, indent = 14, color = c, right = q.ready and "ready" or (q.progress or ""), rightColor = c,
          mid = q.level and ("level %d, %s"):format(q.level, q.ready and "turn it in" or (SAY[q.band] or "")) or "", midColor = C.grey }
      end
    end
  end

  -- zones
  local zs = WN.Zones(opts)
  rows[#rows + 1] = { text = "" }
  rows[#rows + 1] = { header = true, text = "Zones at your level, nearest first", right = ("%d"):format(#zs) }
  for _, r in ipairs(zs) do
    local c = A.COLORS[r.band] or C.cream
    local where = WN.DISTANCE[r.distance] or ""
    if r.foreign then where = where .. ", other side's land" end
    rows[#rows + 1] = { text = r.zone.name, right = ("%d-%d  %s"):format(r.zone.min, r.zone.max, SAY[r.band] or ""), rightColor = c, color = c,
      mid = where .. (#r.dungeons > 0 and ("  |  " .. table.concat(r.dungeons, ", ")) or ""), midColor = r.distance <= 1 and C.cyan or C.grey }
  end
  rows[#rows + 1] = { text = "" }
  rows[#rows + 1] = { text = "Level ranges, zones and the 'old list' drops are from the old game, not verified on Forever. What the game itself shows wins.", color = C.grey }
  return rows
end

--- Three chat lines: the nearest dungeon that fits, what is ready to turn in, the nearest zone that fits.
function WN.Say()
  local lines = {}
  local L = A.playerLevel()
  local ds = WN.Dungeons()
  local d = ds[1]
  if d then
    local n = 0
    for _, x in ipairs(d.named) do if x.look then n = n + 1 end end
    lines[#lines + 1] = ("Where next (level %d): %s (%d-%d, %s, %s)%s%s"):format(L, d.dungeon.name, d.min, d.max, SAY[d.band] or "", WN.DISTANCE[d.distance] or "",
      d.quests and ("; quests in your log: " .. d.quests) or "", n > 0 and ("; %d named drop(s) for your slots"):format(n) or "")
  else
    lines[#lines + 1] = ("Where next (level %d): no dungeon fits your level right now."):format(L)
  end
  local groups = WN.Quests()
  if groups then
    local ready, zone = 0, nil
    for _, g in ipairs(groups) do if g.ready > 0 then ready = ready + g.ready zone = zone or g.zone end end
    if ready > 0 then lines[#lines + 1] = ("%d quest(s) ready to turn in, first in %s."):format(ready, zone) end
  end
  local zs = WN.Zones()
  local near = zs[1]
  if near then lines[#lines + 1] = ("Nearest zone for you: %s (%d-%d, %s)."):format(near.zone.name, near.zone.min, near.zone.max, WN.DISTANCE[near.distance] or "") end
  lines[#lines + 1] = "/hh next for the full view. Old-game ranges, not verified on Forever."
  return lines
end

HH:RegisterSlash("next", function(rest)
  rest = (rest or ""):lower()
  if rest == "say" or rest == "chat" then
    for _, l in ipairs(WN.Say()) do HH:Print(l) end
    return
  end
  A.Window.Toggle("next")
end, "where next: dungeons, quests and zones for your level, nearest first (/hh next say = three chat lines)")
