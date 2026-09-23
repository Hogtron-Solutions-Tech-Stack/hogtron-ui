-- Quest log reader. One normalised shape for every client generation:
--   { id, index, title, level, complete, failed, watched, objectives = { { text, name, have, need, done } } }
--
-- WoW: Forever (1.60.1) ships a modern client with a Classic ruleset, and nobody has told us which quest API family
-- it carries (the 2026-09-17 probe saw C_QuestLog with 93 functions, GetQuestObjectives and GetQuestsOnMap among
-- them; the legacy globals were not probed). So every read tries the modern C_QuestLog form first, then the legacy
-- global, per FIELD, and records which one answered in Data.path for the diag log. Nothing here assumes a function
-- exists; a client with neither family gives an empty list, not an error.
HogHealsQuests = HogHealsQuests or {}
local HHQ = HogHealsQuests

local Data = { path = {} }
HHQ.Data = Data

local function fn(tbl, name)
  if type(tbl) == "table" and type(tbl[name]) == "function" then return tbl[name] end
end
local function global(name) local f = rawget(_G, name) if type(f) == "function" then return f end end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function plain(v) if v == nil or isSecret(v) then return nil end return v end

--- Call f(...) protected; first return value or nil.
local function try(f, ...)
  if not f then return nil end
  local ok, a, b, c, d, e, g, h, i = pcall(f, ...)
  if not ok then return nil end
  return a, b, c, d, e, g, h, i
end

-- --------------------------------------------------------------------------------------------- objective text
--- "Kobold Vermin slain: 3/8" | "3/8 Kobold Vermin slain" | "Linen Scrap: 2/6" -> name, have, need.
-- name is what a nameplate would read: the text with the count and a trailing " slain"/" killed" removed.
function Data.ParseObjective(text)
  if type(text) ~= "string" then return nil end
  local name, have, need = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)%s*$")
  if not name then have, need, name = text:match("^%s*(%d+)%s*/%s*(%d+)%s+(.-)%s*$") end
  if not name then name = text end
  name = name:gsub("%s+[Ss]lain$", ""):gsub("%s+[Kk]illed$", ""):gsub("^%s+", ""):gsub("%s+$", "")
  return name, tonumber(have), tonumber(need)
end

local function objective(text, finished, have, need)
  local name, h, n = Data.ParseObjective(text)
  have, need = tonumber(plain(have)) or h, tonumber(plain(need)) or n
  local done = finished == true or finished == 1
  if not done and have and need and need > 0 and have >= need then done = true end
  return { text = text or "", name = name, have = have, need = need, done = done }
end

-- --------------------------------------------------------------------------------------------- log walk
local function numEntries()
  local n = try(fn(C_QuestLog, "GetNumQuestLogEntries"))
  if type(n) == "number" then Data.path.count = "C_QuestLog" return n end
  n = try(global("GetNumQuestLogEntries"))
  if type(n) == "number" then Data.path.count = "global" return n end
  Data.path.count = "none"
  return 0
end

--- One log line -> { title, level, header, id, complete, failed } or nil.
local function entry(i)
  local info = try(fn(C_QuestLog, "GetInfo"), i)
  if type(info) == "table" then
    Data.path.info = "C_QuestLog.GetInfo"
    local complete
    if info.questID and fn(C_QuestLog, "IsComplete") then complete = try(C_QuestLog.IsComplete, info.questID) end
    return { title = plain(info.title), level = plain(info.level), header = info.isHeader and true or false,
      hidden = info.isHidden and true or false, id = plain(info.questID), complete = complete and true or false,
      failed = info.isFailed and true or false }
  end
  local f = global("GetQuestLogTitle")
  if f then
    local ok, title, level, _, isHeader, _, isComplete, _, questID = pcall(f, i)
    if ok and title then
      Data.path.info = "GetQuestLogTitle"
      return { title = plain(title), level = plain(level), header = isHeader and true or false, id = plain(questID),
        complete = isComplete == 1 or isComplete == true, failed = isComplete == -1 }
    end
  end
  return nil
end

local function objectivesFor(q)
  local out = {}
  local list = q.id and try(fn(C_QuestLog, "GetQuestObjectives"), q.id)
  if type(list) == "table" and #list > 0 then
    Data.path.objectives = "C_QuestLog.GetQuestObjectives"
    for _, o in ipairs(list) do
      if type(o) == "table" then out[#out + 1] = objective(plain(o.text), o.finished, o.numFulfilled, o.numRequired) end
    end
    return out
  end
  local count = try(global("GetNumQuestLeaderBoards"), q.index)
  if type(count) == "number" and count > 0 then
    Data.path.objectives = "GetQuestLogLeaderBoard"
    for j = 1, count do
      local text, _, finished = try(global("GetQuestLogLeaderBoard"), j, q.index)
      if text then out[#out + 1] = objective(plain(text), finished) end
    end
  end
  return out
end

local function isWatched(q)
  if q.id and fn(C_QuestLog, "GetQuestWatchType") then
    Data.path.watched = "C_QuestLog.GetQuestWatchType"
    return try(C_QuestLog.GetQuestWatchType, q.id) ~= nil
  end
  local f = global("IsQuestWatched")
  if f then Data.path.watched = "IsQuestWatched" return try(f, q.index) and true or false end
  if q.id and fn(C_QuestLog, "IsQuestWatched") then Data.path.watched = "C_QuestLog.IsQuestWatched" return try(C_QuestLog.IsQuestWatched, q.id) and true or false end
  return false
end

--- Every quest in the log (headers dropped, each quest tagged with the zone header above it).
function Data.List()
  local out, zone = {}, nil
  for i = 1, numEntries() do
    local e = entry(i)
    if e then
      if e.header then
        zone = e.title
      elseif e.title and not e.hidden then
        e.index, e.zone = i, zone
        e.objectives = objectivesFor(e)
        e.watched = isWatched(e)
        -- a quest with objectives that are all done is ready to hand in even if the client's flag lags a frame
        if not e.complete and #e.objectives > 0 then
          local all = true
          for _, o in ipairs(e.objectives) do if not o.done then all = false break end end
          e.complete = all
        end
        out[#out + 1] = e
      end
    end
  end
  Data.last = out
  return out
end

--- True when this client lets us read the quest log at all (the tracker hides Blizzard's only when this is true).
function Data.Available()
  return fn(C_QuestLog, "GetInfo") ~= nil or global("GetQuestLogTitle") ~= nil
end

--- Incomplete objectives across the log, for nameplate matching: { [lowercased name] = { quest, objective } }.
function Data.OpenObjectives(list)
  local map = {}
  for _, q in ipairs(list or Data.last or Data.List()) do
    if not q.complete then
      for _, o in ipairs(q.objectives or {}) do
        if not o.done and o.name and o.name ~= "" then map[o.name:lower()] = { quest = q, objective = o } end
      end
    end
  end
  return map
end

-- --------------------------------------------------------------------------------------------- actions
function Data.SetWatched(q, on)
  if q.id and fn(C_QuestLog, "AddQuestWatch") then
    if on then try(C_QuestLog.AddQuestWatch, q.id) else try(C_QuestLog.RemoveQuestWatch, q.id) end
    return
  end
  local f = global(on and "AddQuestWatch" or "RemoveQuestWatch")
  if f then try(f, q.index) end
  if global("QuestWatch_Update") then try(QuestWatch_Update) end
end

--- Open the quest log on this quest. Tries the modern map-side log, then the classic log frame.
function Data.Open(q)
  if q.id and global("QuestMapFrame_OpenToQuestDetails") then
    local ok = pcall(QuestMapFrame_OpenToQuestDetails, q.id)
    if ok then return end
  end
  if global("QuestLog_OpenToQuest") and q.index then try(QuestLog_OpenToQuest, q.index) return end
  if global("SelectQuestLogEntry") and q.index then try(SelectQuestLogEntry, q.index) end
  local frame = rawget(_G, "QuestLogFrame")
  if frame and global("ShowUIPanel") then try(ShowUIPanel, frame)
  elseif global("ToggleQuestLog") then try(ToggleQuestLog) end
end

--- Quest points for a map: { { id, x, y } } in 0..1 map coordinates (Blizzard's own POI: the objective area, or
-- the turn-in once the quest is complete).
function Data.PointsOnMap(mapID)
  local out, have = {}, {}
  local list = mapID and try(fn(C_QuestLog, "GetQuestsOnMap"), mapID)
  if type(list) == "table" then
    for _, p in ipairs(list) do
      if type(p) == "table" then
        local x, y = plain(p.x), plain(p.y)
        if type(x) == "number" and type(y) == "number" then
          local id = plain(p.questID)
          out[#out + 1] = { id = id, x = x, y = y }
          if id then have[id] = true end
        end
      end
    end
  end
  -- Quests whose objective / turn-in is on ANOTHER map have no point here (2026-09-22 in game: "Delivery to
  -- Silverpine Forest" had no marker). The client's GetNextWaypointForMap gives the next step on THIS map (the road
  -- out of the zone, the boat), plus a text for it.
  local wp = fn(C_QuestLog, "GetNextWaypointForMap")
  if mapID and wp then
    for _, q in ipairs(Data.last or {}) do
      if q.id and not have[q.id] then
        local a, b = try(wp, q.id, mapID)
        local x, y
        if type(a) == "table" then x, y = plain(a.x), plain(a.y) else x, y = plain(a), plain(b) end
        if type(x) == "number" and type(y) == "number" and not (x == 0 and y == 0) then
          local text = try(fn(C_QuestLog, "GetNextWaypointText"), q.id)
          out[#out + 1] = { id = q.id, x = x, y = y, waypoint = true, text = type(plain(text)) == "string" and text or nil }
          have[q.id] = true
        end
      end
    end
  end
  return out
end

--- Snapshot of which API answered and what the client has, for /hh diag. Plain strings only.
function Data.Probe()
  local keys = {}
  if type(C_QuestLog) == "table" then for k in pairs(C_QuestLog) do keys[#keys + 1] = tostring(k) end end
  table.sort(keys)
  local globals = {}
  for _, g in ipairs({ "GetNumQuestLogEntries", "GetQuestLogTitle", "GetQuestLogLeaderBoard", "GetNumQuestLeaderBoards",
    "IsQuestWatched", "AddQuestWatch", "RemoveQuestWatch", "GetNumQuestWatches", "QuestLog_OpenToQuest",
    "QuestMapFrame_OpenToQuestDetails", "GetQuestLogSelection", "SelectQuestLogEntry" }) do
    globals[#globals + 1] = g .. "=" .. (global(g) and "fn" or "nil")
  end
  local list = Data.List()
  local sample = list[1]
  local paths = {}
  for k, v in pairs(Data.path) do paths[#paths + 1] = k .. "=" .. tostring(v) end
  table.sort(paths)
  return {
    C_QuestLog = table.concat(keys, ","),
    globals = table.concat(globals, ","),
    paths = table.concat(paths, ","),
    quests = #list,
    sample = sample and (tostring(sample.title) .. " | " .. tostring(sample.id) .. " | objs " .. #sample.objectives
      .. (sample.objectives[1] and (" | " .. tostring(sample.objectives[1].text)) or "")) or "none",
  }
end
