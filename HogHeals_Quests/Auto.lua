-- Auto: the quest-NPC chores Questie does without its database - accept the quest you clicked, hand in the one you
-- finished, take the only reward, pick the one quest an NPC offers from a gossip menu. Sean 2026-10-08, from the
-- Questie clip: the quality-of-life half of it ("the DB half is years of data; the rest is events").
--
-- Hold the pause key (Shift) while talking to an NPC and nothing is automatic - you read, you click.
-- Rules, each its own option:
--   accept   QUEST_DETAIL  -> AcceptQuest()                      (the detail page for a quest you clicked)
--   turnIn   QUEST_PROGRESS -> CompleteQuest() when completable   (the "are you done?" page)
--            QUEST_COMPLETE -> GetQuestReward(0 | 1) when there is no choice to make; chooseReward = false leaves a
--            real choice (2+ items) to you, always
--   gossip   GOSSIP_SHOW / QUEST_GREETING -> the ONE available quest, or every finished active quest; a menu with
--            other options (vendor, trainer, several quests) is left alone
-- Defers to Questie when it is loaded (it does the same things; two addons clicking = errors). Every call is
-- pcall'ed and counted in Auto.seen for /hh autodiag. Never closes a frame itself.
HogHealsQuests = HogHealsQuests or {}
local HHQ = HogHealsQuests
local HH = HogHeals

local Auto = { seen = {}, last = {} }
HHQ.Auto = Auto

local function cfg() return HH.db.profile.quests.auto or {} end
local function g(name) local f = rawget(_G, name) if type(f) == "function" then return f end end
local function fn(tbl, name) if type(tbl) == "table" and type(tbl[name]) == "function" then return tbl[name] end end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(f, ...)
  if ok then return a, b, c, d end
end
local function count(k) Auto.seen[k] = (Auto.seen[k] or 0) + 1 end

--- Questie loaded = it owns these chores.
function Auto.Deferring()
  local f = (type(C_AddOns) == "table" and C_AddOns.IsAddOnLoaded) or g("IsAddOnLoaded")
  local ok, loaded = pcall(f or function() end, "Questie")
  return ok and loaded == true
end

--- Pause key held? (SHIFT | CTRL | ALT | NONE)
function Auto.Paused()
  local key = cfg().pauseKey or "SHIFT"
  if key == "NONE" then return false end
  local f = key == "CTRL" and g("IsControlKeyDown") or key == "ALT" and g("IsAltKeyDown") or g("IsShiftKeyDown")
  return call(f) == true
end

local function active()
  local o = cfg()
  if o.enabled == false or Auto.Deferring() or Auto.Paused() then return nil end
  return o
end

-- ------------------------------------------------------------------------------------------------ pure
--- What to do with a reward page: "take" (no choice), "take1" (one item offered), "choose" (2+ = the player's call)
function Auto.RewardPlan(numChoices, chooseReward)
  numChoices = numChoices or 0
  if numChoices <= 0 then return "take" end
  if numChoices == 1 then return "take1" end
  return "choose"
end

--- Which gossip entries to click: finished active quests first (hand-ins), else the single available quest when the
-- menu has nothing else on it. available / activeList = { { id = ..., complete = bool } }, options = count of other
-- gossip options. Returns { kind = "active" | "available", id = ... } or nil.
function Auto.GossipPlan(available, activeList, options)
  for _, q in ipairs(activeList or {}) do
    if q.complete then return { kind = "active", id = q.id, index = q.index } end
  end
  if #(available or {}) == 1 and #(activeList or {}) == 0 and (options or 0) == 0 then
    local q = available[1]
    if not q.trivial or cfg().acceptTrivial ~= false then return { kind = "available", id = q.id, index = q.index } end
  end
  return nil
end

-- ------------------------------------------------------------------------------------------------ handlers
function Auto.OnDetail()
  local o = active()
  if not o or o.accept == false then count("skipped") return false end
  -- a quest shared by a party member or from an item pops the same page: still a yes
  local accept = g("AcceptQuest")
  if not accept then return false end
  call(accept)
  count("accepted")
  Auto.last.action = "accept"
  return true
end

function Auto.OnProgress()
  local o = active()
  if not o or o.turnIn == false then count("skipped") return false end
  local can = g("IsQuestCompletable")
  if can and not call(can) then count("notCompletable") return false end
  if g("CompleteQuest") then call(g("CompleteQuest")) count("completed") Auto.last.action = "complete" return true end
  return false
end

function Auto.OnComplete()
  local o = active()
  if not o or o.turnIn == false then count("skipped") return false end
  local n = num(call(g("GetNumQuestChoices"))) or 0
  local plan = Auto.RewardPlan(n, o.chooseReward)
  Auto.last.rewardPlan = plan
  if plan == "choose" then count("leftChoice") return false end
  local take = g("GetQuestReward")
  if not take then return false end
  call(take, plan == "take1" and 1 or 0)
  count("rewarded")
  Auto.last.action = "reward"
  return true
end

--- Modern gossip: C_GossipInfo lists; legacy: GetGossipAvailableQuests varargs (stride guessed from the count).
local function gossipLists()
  local GI = rawget(_G, "C_GossipInfo")
  if fn(GI, "GetAvailableQuests") and fn(GI, "GetActiveQuests") then
    local av, ac = {}, {}
    for i, q in ipairs(call(GI.GetAvailableQuests) or {}) do av[#av + 1] = { id = num(q.questID), index = i, trivial = q.isTrivial and true or false } end
    for i, q in ipairs(call(GI.GetActiveQuests) or {}) do ac[#ac + 1] = { id = num(q.questID), index = i, complete = q.isComplete and true or false } end
    local opts = call(fn(GI, "GetOptions"))
    local n = type(opts) == "table" and #opts or (num(call(fn(GI, "GetNumOptions"))) or 0)
    return av, ac, n, "C_GossipInfo"
  end
  local nAv, nAc = num(call(g("GetNumGossipAvailableQuests"))) or 0, num(call(g("GetNumGossipActiveQuests"))) or 0
  if g("GetGossipAvailableQuests") or g("GetGossipActiveQuests") then
    local av, ac = {}, {}
    for i = 1, nAv do av[i] = { index = i } end
    local raw = { pcall(g("GetGossipActiveQuests") or function() end) }
    table.remove(raw, 1)   -- pcall's ok flag; the rest is the flat (title, level, trivial, complete, ...) run per quest
    local stride = nAc > 0 and math.floor(#raw / nAc) or 0
    for i = 1, nAc do ac[i] = { index = i, complete = stride >= 4 and raw[(i - 1) * stride + 4] == true or false } end
    return av, ac, num(call(g("GetNumGossipOptions"))) or 0, "GetGossip*"
  end
  return nil
end

function Auto.OnGossip()
  local o = active()
  if not o or o.gossip == false then count("skipped") return false end
  local av, ac, opts, path = gossipLists()
  if not av then Auto.last.gossipPath = "none" return false end
  Auto.last.gossipPath = path
  local plan = Auto.GossipPlan(av, ac, opts)
  if not plan then count("gossipLeft") return false end
  local GI = rawget(_G, "C_GossipInfo")
  if plan.kind == "active" then
    if fn(GI, "SelectActiveQuest") and plan.id then call(GI.SelectActiveQuest, plan.id) else call(g("SelectGossipActiveQuest"), plan.index) end
  else
    if fn(GI, "SelectAvailableQuest") and plan.id then call(GI.SelectAvailableQuest, plan.id) else call(g("SelectGossipAvailableQuest"), plan.index) end
  end
  count("gossip" .. plan.kind)
  Auto.last.action = "gossip:" .. plan.kind
  return true
end

--- QUEST_GREETING: the plain (non-gossip) NPC page with its own lists.
function Auto.OnGreeting()
  local o = active()
  if not o or o.gossip == false then count("skipped") return false end
  local nAc, nAv = num(call(g("GetNumActiveQuests"))) or 0, num(call(g("GetNumAvailableQuests"))) or 0
  local ac, av = {}, {}
  for i = 1, nAc do
    local _, complete = call(g("GetActiveTitle"), i)
    ac[i] = { index = i, complete = complete == true or complete == 1 }
  end
  for i = 1, nAv do av[i] = { index = i, trivial = call(g("IsAvailableQuestTrivial"), i) == true } end
  local plan = Auto.GossipPlan(av, ac, 0)
  if not plan then count("greetingLeft") return false end
  if plan.kind == "active" then call(g("SelectActiveQuest"), plan.index) else call(g("SelectAvailableQuest"), plan.index) end
  count("greeting" .. plan.kind)
  Auto.last.action = "greeting:" .. plan.kind
  return true
end

-- ------------------------------------------------------------------------------------------------ wiring
local HANDLERS = { QUEST_DETAIL = Auto.OnDetail, QUEST_PROGRESS = Auto.OnProgress, QUEST_COMPLETE = Auto.OnComplete,
  GOSSIP_SHOW = Auto.OnGossip, QUEST_GREETING = Auto.OnGreeting }

function Auto.Start()
  if Auto.frame then return end
  local f = CreateFrame("Frame")
  Auto.unknown = {}
  for e in pairs(HANDLERS) do
    local ok = pcall(f.RegisterEvent, f, e)
    if not ok then Auto.unknown[#Auto.unknown + 1] = e end
  end
  f:SetScript("OnEvent", function(_, e)
    local h = HANDLERS[e]
    if h then
      local ok, err = pcall(h)
      if not ok then HH:LogError("quests auto " .. e .. ": " .. tostring(err)) end
    end
  end)
  Auto.frame = f
end

function Auto.Lines()
  local o = cfg()
  local out = {}
  out[#out + 1] = ("auto quests: %s%s; accept %s, turn in %s, gossip %s, pause key %s"):format(o.enabled == false and "OFF" or "on",
    Auto.Deferring() and " (deferring to Questie)" or "", tostring(o.accept ~= false), tostring(o.turnIn ~= false), tostring(o.gossip ~= false), o.pauseKey or "SHIFT")
  local parts = {}
  for k, v in pairs(Auto.seen) do parts[#parts + 1] = k .. "=" .. v end
  table.sort(parts)
  out[#out + 1] = "  counts: " .. (#parts > 0 and table.concat(parts, " ") or "nothing yet")
  if Auto.last.action then out[#out + 1] = "  last: " .. Auto.last.action .. (Auto.last.gossipPath and (" via " .. Auto.last.gossipPath) or "") end
  if Auto.unknown and #Auto.unknown > 0 then out[#out + 1] = "  events this client lacks: " .. table.concat(Auto.unknown, ",") end
  return out
end

HH:RegisterSlash("autodiag", function()
  for _, l in ipairs(Auto.Lines()) do HH:Print(l) end
end, "auto accept / turn-in / gossip: what fired, what was skipped")

--- /hh auto: the switches from chat. Sean 2026-10-08 in game: "the auto-accept works - is there a way to turn that off?"
HH:RegisterSlash("auto", function(rest)
  local o, an = HH.db.profile.quests.auto, HH.db.profile.quests.announce
  local what, val = (rest or ""):lower():match("^%s*(%a*)%s*(%a*)")
  local function say(k, v) HH:Print(("auto: %s %s"):format(k, v and "on" or "off")) end
  if what == "on" or what == "off" then o.enabled = what == "on" say("everything (accept, turn in, gossip)", o.enabled) return end
  local keys = { accept = "accept", turnin = "turnIn", gossip = "gossip" }
  if keys[what] and (val == "on" or val == "off") then o[keys[what]] = val == "on" say(what, o[keys[what]]) return end
  if what == "announce" and (val == "on" or val == "off") then an.enabled = val == "on" say("announce", an.enabled) return end
  if what == "" then for _, l in ipairs(Auto.Lines()) do HH:Print(l) end return end
  HH:Print("usage: /hh auto on|off  -  /hh auto accept|turnin|gossip|announce on|off  -  or hold Shift at the NPC")
end, "auto quests on / off: /hh auto off, /hh auto accept off, /hh auto announce off")
