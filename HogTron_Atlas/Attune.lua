-- Attune: what lets you into a raid or dungeon, and where you stand on it - the Attune addon's job (Sean 2026-10-08,
-- "with some of the new dungeons requiring attunement, this add-on is a must have"), done from Data/Attunements.lua
-- and three client questions, every one looked up by name and recorded in Attune.path for /hh attune:
--   done     C_QuestLog.IsQuestFlaggedCompleted(id)  (the quest is in your past)      - needs an id
--   active   the quest title in your quest log, through HogTron UI Quests when loaded  - title is enough
--   held     GetItemCount(id) > 0 (C_Item.GetItemCount on newer clients)              - needs an id
-- State per entry: "attuned" (every step done, or any step when entry.any), "progress" (something done or active),
-- "none", or "unknown" (no id and nothing in the log - the game cannot tell us). Pure State() for the tests; the
-- Window and /hh attune only format it.
local A = HogHealsAtlas
local HH = HogHeals

local At = { path = { done = "none", item = "none", log = "none" }, seen = {} }
A.Attune = At

local C = A.COLORS

local function fn(tbl, name) if type(tbl) == "table" and type(tbl[name]) == "function" then return tbl[name] end end
local function g(name) local f = rawget(_G, name) if type(f) == "function" then return f end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a = pcall(f, ...)
  if ok then return a end
end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end

-- ------------------------------------------------------------------------------------------------ client reads
--- Has this character finished quest `id`? nil when the client cannot say.
function At.QuestDone(id)
  if not id then return nil end
  local f = fn(rawget(_G, "C_QuestLog"), "IsQuestFlaggedCompleted") or g("IsQuestFlaggedCompleted")
  if not f then At.path.done = "none" return nil end
  At.path.done = fn(rawget(_G, "C_QuestLog"), "IsQuestFlaggedCompleted") and "C_QuestLog.IsQuestFlaggedCompleted" or "IsQuestFlaggedCompleted"
  local v = call(f, id)
  if v == nil or isSecret(v) then return nil end
  return v == true or v == 1
end

--- How many of item `id` you carry; nil when the client cannot say.
function At.ItemCount(id)
  if not id then return nil end
  local f = fn(rawget(_G, "C_Item"), "GetItemCount") or g("GetItemCount")
  if not f then At.path.item = "none" return nil end
  At.path.item = fn(rawget(_G, "C_Item"), "GetItemCount") and "C_Item.GetItemCount" or "GetItemCount"
  return num(call(f, id, true))
end

--- The quest log as { [lower title] = quest, [id] = quest }, through HogTron UI Quests; nil without it.
function At.Log(list)
  if not list then
    local q = rawget(_G, "HogHealsQuests")
    local L = type(q) == "table" and type(q.Data) == "table" and q.Data.List or nil
    if not L then At.path.log = "none" return nil end
    local ok, got = pcall(L)
    if not ok or type(got) ~= "table" then At.path.log = "none" return nil end
    list = got
    At.path.log = "HogHealsQuests"
  end
  local out = {}
  for _, q in ipairs(list) do
    if type(q.title) == "string" then out[q.title:lower()] = q end
    if type(q.id) == "number" then out[q.id] = q end
  end
  return out
end

-- ------------------------------------------------------------------------------------------------ pure
local function questIdFor(step, faction)
  local q = step.quest
  if type(q) == "table" then return faction and q[faction] or nil end
  return q
end

--- One step's state. ctx = { faction = "A" | "H", log = { [lower title] = quest } | nil, done = fn(id) -> bool | nil,
-- count = fn(id) -> n | nil }. Returns "done" | "ready" | "active" | "none" | "unknown".
function At.StepState(step, ctx)
  ctx = ctx or {}
  if step.item then
    local n = ctx.count and ctx.count(step.item)
    if n == nil then return "unknown" end
    return n > 0 and "done" or "none"
  end
  local id = questIdFor(step, ctx.faction)
  local known = false
  if id and ctx.done then
    local d = ctx.done(id)
    if d == true then return "done" end
    if d == false then known = true end
  end
  if ctx.log then
    local q = (id and ctx.log[id]) or (step.title and ctx.log[step.title:lower()])
    if q then return q.complete and "ready" or "active" end
    known = true
  end
  if step.kind == "kill" or step.kind == "level" then return known and "none" or "unknown" end
  return known and "none" or "unknown"
end

--- A whole entry: { state = "attuned" | "progress" | "none" | "unknown", steps = { { step, state } }, done = n,
-- total = n, mine = n (steps for your side) }. Steps for the other side are dropped.
function At.State(entry, ctx)
  ctx = ctx or {}
  local out = { steps = {}, done = 0, total = 0, active = 0, unknown = 0 }
  for _, s in ipairs(entry.steps or {}) do
    if not s.side or not ctx.faction or s.side == ctx.faction then
      local st = At.StepState(s, ctx)
      out.steps[#out.steps + 1] = { step = s, state = st }
      out.total = out.total + 1
      if st == "done" then out.done = out.done + 1
      elseif st == "ready" or st == "active" then out.active = out.active + 1
      elseif st == "unknown" then out.unknown = out.unknown + 1 end
    end
  end
  if out.total == 0 then out.state = "unknown"
  elseif entry.any and out.done > 0 then out.state = "attuned"
  elseif not entry.any and out.done == out.total then out.state = "attuned"
  elseif out.done > 0 or out.active > 0 then out.state = "progress"
  elseif out.unknown == out.total then out.state = "unknown"
  else out.state = "none" end
  return out
end

--- Entries by key, and the one for an Atlas dungeon key.
function At.ByKey(key)
  for _, e in ipairs(A.Data.Attunements or {}) do if e.key == key then return e end end
end
function At.ForDungeon(dkey)
  for _, e in ipairs(A.Data.Attunements or {}) do if e.dungeon == dkey then return e end end
end

--- Live context from the client (faction, log, the two lookups).
function At.Context(list)
  local faction = A.playerFaction and A.playerFaction() or nil
  return { faction = faction, log = At.Log(list), done = At.QuestDone, count = At.ItemCount }
end

--- Every entry with its live state: { { entry, state } } in data order.
function At.All(ctx)
  ctx = ctx or At.Context()
  local out = {}
  for _, e in ipairs(A.Data.Attunements or {}) do out[#out + 1] = { entry = e, state = At.State(e, ctx) } end
  At.seen.reads = (At.seen.reads or 0) + 1
  return out
end

-- ------------------------------------------------------------------------------------------------ rows + text
local STATE_TEXT = { attuned = "attuned", progress = "in progress", none = "not started", unknown = "cannot tell" }
local STEP_TEXT = { done = "done", ready = "ready to hand in", active = "in your log", none = "", unknown = "?" }
local function stateColor(s)
  if s == "attuned" or s == "done" then return C.green end
  if s == "progress" or s == "ready" or s == "active" then return C.amber end
  if s == "unknown" then return C.grey end
  return C.grey
end

--- Rows for the Attunements tab (header per group, entry + its steps).
function At.Rows(ctx)
  local rows = {}
  local groups = { { "raid", "Raids" }, { "key", "Keys" }, { "dungeon", "Forever dungeons" } }
  local all = At.All(ctx)
  for _, gdef in ipairs(groups) do
    local any = false
    for _, r in ipairs(all) do
      if r.entry.group == gdef[1] then
        if not any then rows[#rows + 1] = { header = true, text = gdef[2] } any = true end
        local e, s = r.entry, r.state
        local right = STATE_TEXT[s.state] or "?"
        if s.state == "progress" then right = ("%d/%d  %s"):format(s.done, s.total, right) end
        rows[#rows + 1] = { text = e.name .. (e.partial and " (partial)" or ""), right = right, rightColor = stateColor(s.state),
          color = s.state == "attuned" and C.green or C.cream, key = e.key, dungeon = e.dungeon,
          tip = e.how .. (e.unverified and "  Not verified on Forever." or "") }
        for _, st in ipairs(s.steps) do
          local step = st.step
          local text = step.title
          if step.where then text = text .. "  -  " .. step.where end
          rows[#rows + 1] = { text = text, indent = 14, right = STEP_TEXT[st.state] or "", rightColor = stateColor(st.state),
            color = st.state == "done" and C.green or (st.state == "unknown" and C.grey or C.cream) }
        end
      end
    end
  end
  rows[#rows + 1] = { text = "" }
  rows[#rows + 1] = { text = "done = the game says the quest is in your past / the item is in your bags. ? = no id to ask about (Forever's new chains are titles only until seen in play).", color = C.grey }
  return rows
end

--- Rows for a dungeon's Guide page (nil when the dungeon has no attunement entry).
function At.GuideRows(dkey, ctx)
  local e = At.ForDungeon(dkey)
  if not e then return nil end
  local s = At.State(e, ctx or At.Context())
  local rows = {}
  rows[#rows + 1] = { header = true, text = e.group == "key" and "Key" or "Attunement" }
  rows[#rows + 1] = { text = e.how, color = C.grey }
  rows[#rows + 1] = { text = "Standing", right = (STATE_TEXT[s.state] or "?") .. (s.state == "progress" and (("  %d/%d"):format(s.done, s.total)) or ""), rightColor = stateColor(s.state), color = C.grey }
  for _, st in ipairs(s.steps) do
    rows[#rows + 1] = { text = st.step.title .. (st.step.where and ("  -  " .. st.step.where) or ""), indent = 14,
      right = STEP_TEXT[st.state] or "", rightColor = stateColor(st.state), color = st.state == "done" and C.green or C.cream }
  end
  return rows
end

--- Chat lines for /hh attune.
function At.Say(ctx)
  local out = {}
  for _, r in ipairs(At.All(ctx)) do
    local e, s = r.entry, r.state
    local line = ("%s: %s"):format(e.name, STATE_TEXT[s.state] or "?")
    if s.state == "progress" then line = line .. (" (%d/%d)"):format(s.done, s.total) end
    if s.state ~= "attuned" then
      local nextStep
      for _, st in ipairs(s.steps) do if st.state ~= "done" then nextStep = st break end end
      if nextStep then line = line .. "  next: " .. nextStep.step.title .. (nextStep.step.where and (" (" .. nextStep.step.where .. ")") or "") end
    end
    out[#out + 1] = line
  end
  out[#out + 1] = ("paths: done=%s item=%s log=%s"):format(At.path.done, At.path.item, At.path.log)
  return out
end

-- ------------------------------------------------------------------------------------------------ wiring
function At.Start()
  if At.frame then return end
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "QUEST_TURNED_IN", "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE" }) do pcall(f.RegisterEvent, f, e) end
  f:SetScript("OnEvent", function()
    if A.Window and A.Window.tab == "attune" and A.Window.Refresh then pcall(A.Window.Refresh) end
  end)
  At.frame = f
end
