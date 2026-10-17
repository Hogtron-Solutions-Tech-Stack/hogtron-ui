-- HogTron Awards: group sync over addon messages (prefix HTR_AWD).
--
-- At run end every client sends what only it can know - its own player's counters (Metrics "self") - and listens
-- for 3 seconds. Meter- and scoreboard-based metrics are NOT sent: every client reads the same Blizzard data, and
-- those amounts are secret anyway. Then each client resolves locally; same inputs + same seed = same screen.
--
-- Wire format (version 1), every message <= 255 bytes:
--   1|E|<runId>|<ctx>                      "the run ended" (lets a client whose own trigger did not fire join in)
--   1|N|<runId>|<part>/<total>|<code>=<v>,...  one player's counters; code = position in Sync.KEYS (sorted, frozen
--                                          per version), v = integer or one-decimal number. Zeros are not sent.
-- The sender's name comes from CHAT_MSG_ADDON, never from the payload. A different version is ignored.
-- No other Awards users, or solo: the window just closes with the local player's own numbers (graceful local-only).
HogTronAwards = HogTronAwards or {}
local A = HogTronAwards
local HH = HogHeals

local S = { PREFIX = "HTR_AWD", VERSION = "1", WINDOW = 3, MAX = 255 }
A.Sync = S

local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
end

--- Frozen key list for version 1: every "self" metric, sorted. Changing this list means bumping VERSION.
function S.Keys()
  if S.KEYS then return S.KEYS end
  local keys = {}
  for k, def in pairs(A.Metrics.DEFS) do if def.src == "self" then keys[#keys + 1] = k end end
  table.sort(keys)
  S.KEYS, S.CODE = keys, {}
  for i, k in ipairs(keys) do S.CODE[k] = i end
  return keys
end

local function fmt(v)
  if v == math.floor(v) then return ("%d"):format(v) end
  return ("%.1f"):format(v)
end

-- ------------------------------------------------------------------------------------------------ codec
function S.EncodeEnd(runId, ctx)
  return table.concat({ S.VERSION, "E", tostring(runId), tostring(ctx) }, "|")
end

--- Split one player's counters into as many N messages as needed. Returns a list of strings.
function S.EncodeNominations(runId, counts)
  S.Keys()
  local pairsList = {}
  for i, k in ipairs(S.KEYS) do
    local v = counts and counts[k]
    if type(v) == "number" and v == v and v ~= 0 and v > -1e9 and v < 1e12 then pairsList[#pairsList + 1] = i .. "=" .. fmt(v) end
  end
  local head = S.VERSION .. "|N|" .. tostring(runId) .. "|"
  local budget = S.MAX - #head - 6            -- room for "nn/nn|"
  local chunks, cur = {}, {}
  local len = 0
  for _, p in ipairs(pairsList) do
    if len + #p + 1 > budget and #cur > 0 then chunks[#chunks + 1] = cur cur, len = {}, 0 end
    cur[#cur + 1] = p
    len = len + #p + 1
  end
  if #cur > 0 or #chunks == 0 then chunks[#chunks + 1] = cur end
  local out = {}
  for i, c in ipairs(chunks) do out[i] = head .. i .. "/" .. #chunks .. "|" .. table.concat(c, ",") end
  return out
end

--- Parse one message. Returns { kind = "E", runId, ctx } | { kind = "N", runId, part, total, counts } | nil, why.
function S.Decode(msg)
  if type(msg) ~= "string" or #msg > S.MAX then return nil, "bad message" end
  local fields = {}
  for f in (msg .. "|"):gmatch("([^|]*)|") do fields[#fields + 1] = f end
  if fields[1] ~= S.VERSION then return nil, "version " .. tostring(fields[1]) end
  if fields[2] == "E" then
    if not fields[3] or fields[3] == "" then return nil, "no run id" end
    local ctx = fields[4]
    if ctx ~= "dungeon" and ctx ~= "raid" and ctx ~= "bg" then return nil, "bad context" end
    return { kind = "E", runId = fields[3], ctx = ctx }
  elseif fields[2] == "N" then
    local part, total = (fields[4] or ""):match("^(%d+)/(%d+)$")
    if not part or fields[3] == "" then return nil, "bad header" end
    S.Keys()
    local counts = {}
    for code, v in (fields[5] or ""):gmatch("(%d+)=([%-%d%.]+)") do
      local key, n = S.KEYS[tonumber(code)], tonumber(v)
      if key and n then counts[key] = n end
    end
    return { kind = "N", runId = fields[3], part = tonumber(part), total = tonumber(total), counts = counts }
  end
  return nil, "unknown kind"
end

-- ------------------------------------------------------------------------------------------------ transport
function S.Channel()
  local instance = LE_PARTY_CATEGORY_INSTANCE
  if instance and call(IsInGroup, instance) then return "INSTANCE_CHAT" end
  if call(IsInRaid) then return "RAID" end
  if call(IsInGroup) then return "PARTY" end
  return nil
end

function S.Send(msg)
  local ch = S.Channel()
  if not ch then return false end
  local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  if type(send) ~= "function" then return false end
  local ok = pcall(send, S.PREFIX, msg, ch)
  S.sent = (S.sent or 0) + 1
  return ok
end

function S.Register()
  local reg = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
  if type(reg) == "function" then pcall(reg, S.PREFIX) end
  if S.frame then return end
  local f = CreateFrame("Frame")
  pcall(f.RegisterEvent, f, "CHAT_MSG_ADDON")
  f:SetScript("OnEvent", function(_, _, prefix, msg, _, sender) if prefix == S.PREFIX then S.OnMessage(msg, sender) end end)
  S.frame = f
end

-- ------------------------------------------------------------------------------------------------ window
S.window = nil

--- Open the 3 s window for a run that just ended: send our counters, collect everyone's, then call onDone.
-- onDone(nominations, seed) where nominations = { [name] = counts } and seed = the agreed run id.
function S.Begin(runId, ctx, counts, onDone)
  local me = A.Metrics.Short(call(UnitName, "player")) or "me"
  S.window = { runId = runId, ctx = ctx, runIds = { [runId] = true }, nominations = { [me] = counts or {} }, parts = {}, onDone = onDone }
  S.Send(S.EncodeEnd(runId, ctx))
  for _, m in ipairs(S.EncodeNominations(runId, counts)) do S.Send(m) end
  local w = S.window
  local function finish()
    if S.window ~= w then return end
    S.window = nil
    local seed
    for id in pairs(w.runIds) do if not seed or id < seed then seed = id end end
    if w.onDone then w.onDone(w.nominations, seed, w.ctx) end
  end
  w.finish = finish
  if S.Channel() == nil then finish() return end           -- solo: nobody to wait for
  if C_Timer and C_Timer.After then C_Timer.After(S.WINDOW, finish) else finish() end
end

function S.OnMessage(msg, sender)
  local name = A.Metrics.Short(sender)
  local me = A.Metrics.Short(call(UnitName, "player"))
  if not name or name == me then return end
  local m = S.Decode(msg)
  if not m then return end
  if m.kind == "E" then
    if S.window then S.window.runIds[m.runId] = true
    elseif A.OnRemoteEnd then A.OnRemoteEnd(m.runId, m.ctx) end
  elseif m.kind == "N" then
    local w = S.window
    if not w then return end
    w.runIds[m.runId] = true
    local t = w.nominations[name] or {}
    w.nominations[name] = t
    for k, v in pairs(m.counts) do t[k] = v end
  end
end
