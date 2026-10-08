-- Announce: objective progress to the party ("Boars slain 4/10", "Boars slain - done") the moment the log changes,
-- the way Questie's party announce does - without its database: the quest log itself says what moved. Sean
-- 2026-10-08, Questie clip (quality-of-life half).
--
-- Each log read is diffed against the one before (pure Announce.Diff): an objective whose `have` went up, or that
-- just finished, is one line. Options: party (SendChatMessage PARTY / RAID when grouped), self (your own chat
-- frame), accepted / turnedIn (one line per quest). Nothing is sent solo unless `self` is on. Defers to Questie
-- when it is loaded. Rate: one line per objective per change, never a repeat (the diff is the gate).
HogHealsQuests = HogHealsQuests or {}
local HHQ = HogHealsQuests
local HH = HogHeals

local An = { seen = {}, sent = {} }
HHQ.Announce = An

local function cfg() return HH.db.profile.quests.announce or {} end
local function g(name) local f = rawget(_G, name) if type(f) == "function" then return f end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a = pcall(f, ...)
  if ok then return a end
end
local function count(k) An.seen[k] = (An.seen[k] or 0) + 1 end

function An.Deferring()
  local f = (type(C_AddOns) == "table" and C_AddOns.IsAddOnLoaded) or g("IsAddOnLoaded")
  local ok, loaded = pcall(f or function() end, "Questie")
  return ok and loaded == true
end

-- ------------------------------------------------------------------------------------------------ pure
--- Snapshot a log list into { [questID] = { title, complete, obj = { [i] = { have, need, done, name } } } }.
function An.Snapshot(list)
  local out = {}
  for _, q in ipairs(list or {}) do
    if q.id then
      local obj = {}
      for i, o in ipairs(q.objectives or {}) do obj[i] = { have = o.have, need = o.need, done = o.done and true or false, name = o.name or o.text } end
      out[q.id] = { title = q.title, complete = q.complete and true or false, obj = obj }
    end
  end
  return out
end

--- Lines for what changed between two snapshots: { { id, title, text } } in quest-id order.
-- A quest missing from `prev` is new (no lines - accepting is announced separately); one missing from `cur` is gone.
function An.Diff(prev, cur)
  local out = {}
  local ids = {}
  for id in pairs(cur or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local a, b = prev and prev[id], cur[id]
    if a then
      for i, o in ipairs(b.obj) do
        local p = a.obj[i]
        if p then
          local progressed = o.have and p.have and o.have > p.have
          local finished = o.done and not p.done
          if finished and o.need and o.have then
            out[#out + 1] = { id = id, title = b.title, text = ("%s %d/%d - done"):format(o.name or "?", o.have, o.need) }
          elseif finished then
            out[#out + 1] = { id = id, title = b.title, text = ("%s - done"):format(o.name or "?") }
          elseif progressed and o.need then
            out[#out + 1] = { id = id, title = b.title, text = ("%s %d/%d"):format(o.name or "?", o.have, o.need) }
          end
        end
      end
      if b.complete and not a.complete and #b.obj == 0 then
        out[#out + 1] = { id = id, title = b.title, text = "ready to turn in" }
      end
    end
  end
  return out
end

--- "Kobold Camp Cleanup - Kobold Vermin slain 4/8"
function An.Format(line)
  return ("%s - %s"):format(tostring(line.title or "?"), line.text)
end

-- ------------------------------------------------------------------------------------------------ sending
local function channel()
  if call(g("IsInRaid")) then return "RAID" end
  if call(g("IsInGroup")) then return "PARTY" end
  return nil
end

function An.Send(text)
  local o = cfg()
  local sent = false
  if o.party ~= false then
    local ch = channel()
    if ch and g("SendChatMessage") then call(g("SendChatMessage"), text, ch) count("party") sent = true end
  end
  if o.self == true then HH:Print(text) count("self") sent = true end
  An.sent[#An.sent + 1] = text
  if #An.sent > 20 then table.remove(An.sent, 1) end
  return sent
end

--- Called after every quest-log read. Diffs against the last snapshot; sends what moved.
function An.OnLog(list)
  local o = cfg()
  list = list or HHQ.Data.last or {}
  local cur = An.Snapshot(list)
  local prev = An.prev
  An.prev = cur
  if not prev then return 0 end   -- first read: a baseline, not news
  if o.enabled == false or An.Deferring() then return 0 end
  local n = 0
  for _, line in ipairs(An.Diff(prev, cur)) do
    An.Send(An.Format(line))
    n = n + 1
  end
  return n
end

function An.OnAccepted(id)
  local o = cfg()
  if o.enabled == false or o.accepted ~= true or An.Deferring() then return end
  local q = id and HHQ.Waypoint and HHQ.Waypoint.Quest and HHQ.Waypoint.Quest(id) or nil
  local title = q and q.title or (id and ("quest " .. tostring(id))) or "a quest"
  An.Send(("accepted %s"):format(tostring(title)))
end

function An.OnTurnedIn(id)
  local o = cfg()
  if o.enabled == false or o.turnedIn ~= true or An.Deferring() then return end
  local title = An.prev and An.prev[id] and An.prev[id].title or (id and ("quest " .. tostring(id))) or "a quest"
  An.Send(("turned in %s"):format(tostring(title)))
end

-- ------------------------------------------------------------------------------------------------ wiring
function An.Start()
  if An.frame then return end
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_WATCH_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "PLAYER_ENTERING_WORLD" }) do
    pcall(f.RegisterEvent, f, e)
  end
  f:SetScript("OnEvent", function(_, e, a1, a2)
    local ok, err = pcall(function()
      if e == "QUEST_ACCEPTED" then
        An.OnLog(HHQ.Data.List())
        An.OnAccepted((type(a2) == "number" and a2) or (type(a1) == "number" and a1) or nil)
      elseif e == "QUEST_TURNED_IN" then
        An.OnTurnedIn(type(a1) == "number" and a1 or nil)
        An.OnLog(HHQ.Data.List())
      else
        An.OnLog(HHQ.Data.List())
      end
    end)
    if not ok then HH:LogError("quests announce " .. e .. ": " .. tostring(err)) end
  end)
  An.frame = f
  An.prev = An.Snapshot(HHQ.Data.last or HHQ.Data.List())
end

function An.Lines()
  local o = cfg()
  local out = {}
  out[#out + 1] = ("announce: %s%s; party %s, self %s, accepted %s, turned in %s"):format(o.enabled == false and "OFF" or "on",
    An.Deferring() and " (deferring to Questie)" or "", tostring(o.party ~= false), tostring(o.self == true), tostring(o.accepted == true), tostring(o.turnedIn == true))
  out[#out + 1] = ("  sent to party %d, to self %d; grouped: %s"):format(An.seen.party or 0, An.seen.self or 0, channel() or "no")
  if #An.sent > 0 then out[#out + 1] = "  last: " .. An.sent[#An.sent] end
  return out
end

HH:RegisterSlash("announcediag", function()
  for _, l in ipairs(An.Lines()) do HH:Print(l) end
end, "party announce: what has been sent, where")
