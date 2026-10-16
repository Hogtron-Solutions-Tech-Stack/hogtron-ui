-- HogTron Awards: who wins what, and who stands on the stage. Pure functions (no frames, no events) so every client
-- given the same inputs builds the same screen.
--
--   Winners(data, names, roles, ctx, enabled) -> { { award, name, value, detail } ... } one winner per award
--   Stage(winners, seed, opts)                 -> { headline = w, others = { w, w, w, w }, also = { w ... } }
--
-- Rules: highest value wins a "high" award, lowest a "low" one; ties go to the alphabetically first name. Stage: one
-- headline in the centre (MVP when it was won, else the best-priority headline honor), four more drawn with a
-- seeded shuffle (two honors + two roasts when roasts are on and there are enough), one award per person, no award
-- twice. The seed is the run id every client agrees on (Sync.lua), so the draw is the same for the whole group.
HogTronAwards = HogTronAwards or {}
local A = HogTronAwards
local R = {}
A.Resolve = R

--- Value a winner must reach. "high" awards default to at least 1; "low" awards need the player to have taken part
-- (a value is present at all).
local function qualifies(award, v)
  if v == nil then return false end
  if award.dir == "low" then return award.min == nil or v >= 0 end
  return v >= (award.min or 1)
end

function R.Detail(award, value, names)
  local def = A.Metrics and A.Metrics.DEFS[award.metric] or {}
  if def.src == "meter" then
    local n = #names
    local pos = n - value + 1
    if award.dir == "low" then return ("lowest %s in the group"):format(def.label or award.metric) end
    return ("#%d of %d in %s"):format(math.max(1, pos), n, def.label or award.metric)
  end
  if def.src == "derived" then return def.label or award.metric end
  local v = value
  if def.unit == "c" then
    return ("%dg %ds %dc %s"):format(math.floor(v / 10000), math.floor(v / 100) % 100, v % 100, (def.label or ""):gsub("^copper ", ""))
  end
  if def.unit == "s" and v >= 90 then return ("%dm %02ds %s"):format(math.floor(v / 60), v % 60, (def.label or ""):gsub("^seconds? ?", "")) end
  return ("%s %s"):format(tostring(v), def.label or award.metric)
end

function R.Winners(data, names, roles, ctx, enabled)
  local out = {}
  for _, award in ipairs(A.LIST) do
    if A.Eligible(award, ctx) and (enabled == nil or enabled(award)) then
      local best, bestV
      for _, n in ipairs(names) do
        local v = data[n] and data[n][award.metric]
        if type(v) == "number" and qualifies(award, v) and A.Metrics.RoleMatches(award.role, roles and roles[n]) then
          local better
          if bestV == nil then better = true
          elseif award.dir == "low" then better = v < bestV or (v == bestV and n < best)
          else better = v > bestV or (v == bestV and n < best) end
          if better then best, bestV = n, v end
        end
      end
      if best then out[#out + 1] = { award = award, name = best, value = bestV, detail = R.Detail(award, bestV, names) } end
    end
  end
  return out
end

-- ------------------------------------------------------------------------------------------------ seeded shuffle
--- 31-bit string hash (djb2 variant), same on every client.
function R.Hash(s)
  local h = 5381
  s = tostring(s or "")
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
  return h
end

function R.Rng(seed)
  local state = (R.Hash(seed) % 2147483646) + 1
  return function(n)
    state = (state * 48271) % 2147483647
    return (state % n) + 1
  end
end

local function shuffled(list, rng)
  local t = {}
  for i, v in ipairs(list) do t[i] = v end
  for i = #t, 2, -1 do
    local j = rng(i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

--- opts: { slots = 4, roasts = true }
function R.Stage(winners, seed, opts)
  opts = opts or {}
  local slots = opts.slots or 4
  local stage = { others = {}, also = {} }
  local usedName, usedAward = {}, {}
  -- headline: MVP if won, else the best headline-priority honor, else any honor, else anything
  local head
  for _, w in ipairs(winners) do
    if w.award.headline and (not head or w.award.headline < head.award.headline) then head = w end
  end
  if not head then for _, w in ipairs(winners) do if w.award.kind == "honor" then head = w break end end end
  head = head or winners[1]
  if not head then return stage end
  stage.headline = head
  usedName[head.name], usedAward[head.award.id] = true, true
  local rng = R.Rng(seed)
  local honors, roasts = {}, {}
  for _, w in ipairs(winners) do
    if not usedAward[w.award.id] then
      if w.award.kind == "roast" then roasts[#roasts + 1] = w else honors[#honors + 1] = w end
    end
  end
  honors, roasts = shuffled(honors, rng), shuffled(roasts, rng)
  local function take(pool)
    for i, w in ipairs(pool) do
      if not usedName[w.name] and not usedAward[w.award.id] then
        table.remove(pool, i)
        usedName[w.name], usedAward[w.award.id] = true, true
        stage.others[#stage.others + 1] = w
        return true
      end
    end
    return false
  end
  -- alternate honor / roast so the four spots mix praise and teasing; fall back to whatever is left
  local wantRoasts = opts.roasts ~= false
  local turn = "honor"
  while #stage.others < slots do
    local ok
    if turn == "roast" and wantRoasts then ok = take(roasts) or take(honors) else ok = take(honors) or (wantRoasts and take(roasts)) end
    if not ok then break end
    turn = (turn == "honor") and "roast" or "honor"
  end
  -- everything else this run handed out, for the "also earned" line (no one-per-person rule here)
  for _, w in ipairs(winners) do
    local onStage = (w == head)
    for _, o in ipairs(stage.others) do if o == w then onStage = true end end
    if not onStage and (wantRoasts or w.award.kind == "honor") then stage.also[#stage.also + 1] = w end
  end
  return stage
end
