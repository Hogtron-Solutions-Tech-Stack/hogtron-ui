-- Quest chains. Sean 2026-11-05 (backlog #27): "in Questie, you can shift-click a Quest and it will show you the
-- chain. I want that too." The chain comes from Polestar's quest database while Polestar runs (Core/Polestar.lua,
-- Sean 2026-11-06 "work alongside it"): each quest record lists its prerequisites - `pre` (any one) and `preAll`
-- (every one); what a quest unlocks is the reverse of that, indexed once, the first time a chain is asked for.
-- Shift-click a quest in the tracker: its chain in a tooltip beside it - the ones done greyed, the one(s) in your log
-- marked, the rest after. Without Polestar (or with its quest database off) shift-click watches / unwatches as before.
-- Read only, every call pcall'd; nothing of Polestar's is copied (docs/superpowers/research/polestar.md).
HogHealsQuests = HogHealsQuests or {}
local HHQ = HogHealsQuests
local HH = HogHeals

local Chain = { MAX = 12 }
HHQ.Chain = Chain

local CYAN, CREAM, GREY, GREEN = { 0.13, 0.83, 0.88 }, { 0.96, 0.92, 0.86 }, { 0.55, 0.55, 0.60 }, { 0.25, 0.80, 0.35 }

local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
  return nil
end

--- Polestar's quest database, loaded (it loads on demand; never in combat). nil without it.
function Chain.DB()
  local PS = HH.Polestar
  if not (PS and PS.Leads("quests")) then return nil end
  local ns = PS.NS()
  local Q = ns and ns.QuestDB
  if type(Q) ~= "table" then return nil end
  if try(Q.IsLoaded) ~= true then
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return nil end
    try(Q.Load)
    if try(Q.IsLoaded) ~= true then return nil end
  end
  return Q
end

--- Polestar leads quests and has a quest database (loaded or not - nothing is loaded to answer this).
function Chain.Available()
  local PS = HH.Polestar
  if not (PS and PS.Leads("quests")) then return false end
  local ns = PS.NS()
  return type(ns and ns.QuestDB) == "table"
end

local function quest(Q, id)
  local q = try(Q.GetQuest, id)
  return type(q) == "table" and q or nil
end

local function firstId(list)
  if type(list) ~= "table" then return nil end
  for _, v in ipairs(list) do if type(v) == "number" then return v end end
  return nil
end

--- The quests that need `id` done first (the reverse of every record's pre / preAll), lowest id first.
function Chain.Next(Q, id)
  if Chain.indexOf ~= Q then
    local idx = {}
    for _, qid in ipairs(try(Q.QuestIds) or {}) do
      local q = quest(Q, qid)
      if q then
        for _, key in ipairs({ "pre", "preAll" }) do
          for _, p in ipairs(type(q[key]) == "table" and q[key] or {}) do
            if type(p) == "number" then idx[p] = idx[p] or {} table.insert(idx[p], qid) end
          end
        end
      end
    end
    for _, l in pairs(idx) do table.sort(l) end
    Chain.index, Chain.indexOf = idx, Q
  end
  return Chain.index[id] or {}
end

--- The chain through quest `id`: { quests = { q, ... } (first to last), here = index of `id`, branches = n } or nil.
--- Back along the first prerequisite, forward along the first quest it unlocks; at most MAX each way.
function Chain.Build(id)
  local Q = Chain.DB()
  if not Q or type(id) ~= "number" then return nil end
  local q = quest(Q, id)
  if not q then return nil end
  local seen, back, cur = { [id] = true }, {}, q
  while #back < Chain.MAX do
    local p = firstId(cur.pre) or firstId(cur.preAll)
    if not p or seen[p] then break end
    local pq = quest(Q, p)
    if not pq then break end
    seen[p] = true
    table.insert(back, 1, pq)
    cur = pq
  end
  local fwd, at, branches = {}, id, 0
  while #fwd < Chain.MAX do
    local nexts = Chain.Next(Q, at)
    if #nexts > 1 then branches = branches + #nexts - 1 end
    local n = nexts[1]
    if not n or seen[n] then break end
    local nq = quest(Q, n)
    if not nq then break end
    seen[n] = true
    fwd[#fwd + 1] = nq
    at = n
  end
  local list = {}
  for _, x in ipairs(back) do list[#list + 1] = x end
  list[#list + 1] = q
  local here = #list
  for _, x in ipairs(fwd) do list[#list + 1] = x end
  return { quests = list, here = here, branches = branches }
end

--- "done" | "log" | "later" for a quest id.
function Chain.State(id)
  local QL = rawget(_G, "C_QuestLog")
  local done = (type(QL) == "table" and try(QL.IsQuestFlaggedCompleted, id)) or try(rawget(_G, "IsQuestFlaggedCompleted"), id)
  if done == true then return "done" end
  local idx = type(QL) == "table" and try(QL.GetLogIndexForQuestID, id) or nil
  if type(idx) == "number" and idx > 0 then return "log" end
  for _, q in ipairs(HHQ.Data and HHQ.Data.last or {}) do if q.id == id then return "log" end end
  return "later"
end

--- The tooltip lines: { text, r, g, b } ... (pure enough to test).
function Chain.Lines(c)
  local out = {}
  local n = #c.quests
  out[#out + 1] = { ("Quest chain: %d of %d"):format(c.here, n), CYAN }
  for i, q in ipairs(c.quests) do
    local st = Chain.State(q.id)
    local lvl = type(q.level) == "number" and ("[%d] "):format(q.level) or ""
    local mark = st == "done" and "done  " or (st == "log" and "> " or "   ")
    local col = st == "done" and GREY or (st == "log" and (i == c.here and CYAN or GREEN) or CREAM)
    out[#out + 1] = { mark .. lvl .. tostring(q.title or ("quest " .. tostring(q.id))), col }
  end
  if c.branches > 0 then out[#out + 1] = { ("(+%d other quest%s branch off this chain)"):format(c.branches, c.branches == 1 and "" or "s"), GREY } end
  out[#out + 1] = { "From Polestar's quest database", GREY }
  return out
end

--- Shift-click: the chain beside `owner`. true when there was one to show (else the caller does its old shift-click).
function Chain.Show(owner, q)
  if not GameTooltip or type(q) ~= "table" then return false end
  local c = Chain.Build(q.id)
  if not c then return false end
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  if #c.quests == 1 then
    GameTooltip:AddLine(tostring(q.title or "?"), CYAN[1], CYAN[2], CYAN[3])
    GameTooltip:AddLine("No chain: this quest stands on its own.", GREY[1], GREY[2], GREY[3])
  else
    for _, l in ipairs(Chain.Lines(c)) do GameTooltip:AddLine(l[1], l[2][1], l[2][2], l[2][3]) end
  end
  GameTooltip:Show()
  Chain.last = { id = q.id, n = #c.quests, here = c.here }
  return true
end
