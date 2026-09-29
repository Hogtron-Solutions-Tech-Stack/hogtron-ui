-- DungeonQuests: the quest tracker for dungeons. For one dungeon it answers "which quests send me in there, and
-- where do I stand on each?"
--
-- Two sources, merged by title:
--   your quest log   every quest the game files under the dungeon (log header = the dungeon's name) - always right
--   the shipped list titles from the old game (Data/Quests.lua) - a reminder of what exists, not verified on Forever
-- The quest log is read through HogUI Quests when that addon is loaded; without it the shipped list still shows,
-- without progress.
local A = HogHealsAtlas

local DQ = {}
A.DungeonQuests = DQ

local function logList()
  local q = rawget(_G, "HogHealsQuests")
  if type(q) ~= "table" or type(q.Data) ~= "table" or type(q.Data.List) ~= "function" then return nil end
  local ok, list = pcall(q.Data.List)
  if ok and type(list) == "table" then return list end
end

--- Does a log header belong to this dungeon? "Scarlet Monastery" covers all four wings.
function DQ.HeaderMatches(header, dungeon)
  if type(header) ~= "string" or header == "" then return false end
  local h, n = header:lower(), dungeon.name:lower()
  if h == n then return true end
  local base = n:match("^(.-):") -- "scarlet monastery: library" -> "scarlet monastery"
  if base and h == base then return true end
  if n:gsub("^the ", "") == h:gsub("^the ", "") then return true end
  return false
end

--- Rows for a dungeon: { title, state = "ready" | "active" | "none", progress = "2/5", objectives, listed, mine,
-- side, class }. Ready first, then active, then the rest of the list. log = a quest list for tests.
function DQ.For(dkey, log)
  local d = A.Store.Dungeon(dkey)
  if not d then return {}, false end
  log = log or logList()
  local haveLog = log ~= nil
  local faction, class = A.playerFaction(), A.playerClass()
  local rows, byTitle = {}, {}

  local function progress(q)
    local done, all = 0, 0
    for _, o in ipairs(q.objectives or {}) do
      all = all + 1
      if o.done then done = done + 1 end
    end
    if all == 0 then return nil end
    return ("%d/%d"):format(done, all)
  end

  local inLog = {}
  for _, q in ipairs(log or {}) do if type(q.title) == "string" then inLog[q.title:lower()] = q end end

  for _, e in ipairs(A.Data.Quests[dkey] or {}) do
    local mine = (not e.side or not faction or e.side == faction) and (not e.class or e.class == class)
    local q = inLog[e.title:lower()]
    if mine or q then
      local row = { title = e.title, listed = true, side = e.side, class = e.class, state = "none" }
      if q then
        row.state = q.complete and "ready" or "active"
        row.progress, row.objectives, row.level, row.quest = progress(q), q.objectives, q.level, q
      end
      rows[#rows + 1] = row
      byTitle[e.title:lower()] = row
    end
  end

  for _, q in ipairs(log or {}) do
    if type(q.title) == "string" and not byTitle[q.title:lower()] and DQ.HeaderMatches(q.zone, d) then
      local row = { title = q.title, listed = false, state = q.complete and "ready" or "active", progress = progress(q),
        objectives = q.objectives, level = q.level, quest = q }
      rows[#rows + 1] = row
      byTitle[q.title:lower()] = row
    end
  end

  local rank = { ready = 1, active = 2, none = 3 }
  table.sort(rows, function(a, b)
    if rank[a.state] ~= rank[b.state] then return rank[a.state] < rank[b.state] end
    return a.title < b.title
  end)
  return rows, haveLog
end

--- "3 active, 1 ready" for the dungeon list, or nil when nothing is in the log.
function DQ.Summary(dkey, log)
  local rows = DQ.For(dkey, log)
  local active, ready = 0, 0
  for _, r in ipairs(rows) do
    if r.state == "active" then active = active + 1 elseif r.state == "ready" then ready = ready + 1 end
  end
  if active + ready == 0 then return nil, 0, 0 end
  local parts = {}
  if ready > 0 then parts[#parts + 1] = ready .. " ready" end
  if active > 0 then parts[#parts + 1] = active .. " active" end
  return table.concat(parts, ", "), active, ready
end
