-- Share: every new drop you discover goes to your party and guild over addon messages; theirs come to you and are
-- filed as "group". Forever's tables only exist in play, so a guild fills them many times faster than one player.
--
-- Message: "1;<dungeonKey>;<boss>;<itemID>" (prefix HHATL). Everything received is treated as hostile input:
-- fixed grammar, a dungeon Atlas already knows, a sane boss name, a numeric item id, and a cap per sender.
-- The client may refuse addon messages at times (inside encounters on restricted-API clients): every send is
-- guarded and a refusal is counted, never raised.
local A = HogHealsAtlas
local HH = HogHeals

local Share = { PREFIX = "HHATL", VERSION = 1, PER_SENDER = 10, WINDOW = 10, OUT_CAP = 10, senders = {}, out = {}, stats = { sent = 0, got = 0, dropped = 0, refused = 0 } }
A.Share = Share

local function clock() return (type(GetTime) == "function" and GetTime()) or 0 end

function Share.Encode(dkey, boss, itemID)
  if type(dkey) ~= "string" or type(boss) ~= "string" or type(itemID) ~= "number" then return nil end
  if dkey:find(";", 1, true) or boss:find(";", 1, true) then return nil end
  local msg = ("%d;%s;%s;%d"):format(Share.VERSION, dkey, boss, itemID)
  if #msg > 240 then return nil end
  return msg
end

--- dungeonKey, boss, itemID out of a message, or nil. Only dungeons Atlas already has a row for are accepted.
function Share.Decode(msg)
  if type(msg) ~= "string" or A.isSecret(msg) or #msg > 240 then return nil end
  local v, dkey, boss, id = msg:match("^(%d+);([^;]+);([^;]+);(%d+)$")
  if not v or tonumber(v) ~= Share.VERSION then return nil end
  id = tonumber(id)
  if not id or id <= 0 or id > 9999999 then return nil end
  if #boss > 60 or boss:find("[%c|]") then return nil end
  if not A.Store.Dungeon(dkey) then return nil end
  return dkey, boss, id
end

local function allow(bucket, key, cap)
  local now = clock()
  -- a guild is hundreds of names over a long session: the table of senders is emptied when it grows past 200
  if bucket[key] == nil then
    local n = 0
    for _ in pairs(bucket) do n = n + 1 end
    if n >= 200 then for k in pairs(bucket) do bucket[k] = nil end end
  end
  local list = bucket[key] or {}
  local keep = {}
  for _, t in ipairs(list) do if now - t < Share.WINDOW then keep[#keep + 1] = t end end
  bucket[key] = keep
  if #keep >= cap then return false end
  keep[#keep + 1] = now
  return true
end

function Share.Available()
  return A.fn("C_ChatInfo.SendAddonMessage") ~= nil and A.fn("C_ChatInfo.RegisterAddonMessagePrefix") ~= nil
end

--- Tell party and guild about one drop. Returns how many channels it went to.
function Share.Send(dkey, boss, itemID)
  if A.cfg().share == false or not Share.ready then return 0 end
  if boss == A.Store.TRASH then return 0 end
  local msg = Share.Encode(dkey, boss, itemID)
  if not msg then return 0 end
  if not allow(Share.out, "me", Share.OUT_CAP) then Share.stats.dropped = Share.stats.dropped + 1 return 0 end
  local send = A.fn("C_ChatInfo.SendAddonMessage")
  local n = 0
  local function to(channel)
    local ok = pcall(send, Share.PREFIX, msg, channel)
    if ok then n = n + 1 Share.stats.sent = Share.stats.sent + 1 else Share.stats.refused = Share.stats.refused + 1 end
  end
  if A.plain(A.call(rawget(_G, "IsInRaid"))) then to("RAID")
  elseif A.plain(A.call(rawget(_G, "IsInGroup"))) then to("PARTY") end
  if A.plain(A.call(rawget(_G, "IsInGuild"))) then to("GUILD") end
  return n
end

function Share.OnMessage(prefix, msg, channel, sender)
  if A.isSecret(prefix) or prefix ~= Share.PREFIX then return false end
  if A.cfg().share == false then return false end
  sender = A.str(sender)
  if not sender then return false end
  -- my own message comes back on the same channel
  local me = A.str(A.call(UnitName, "player"))
  if me and (sender == me or sender:match("^([^%-]+)") == me) then return false end
  if not allow(Share.senders, sender, Share.PER_SENDER) then Share.stats.dropped = Share.stats.dropped + 1 return false end
  local dkey, boss, id = Share.Decode(msg)
  if not dkey then Share.stats.dropped = Share.stats.dropped + 1 return false end
  A.Store.AddBoss(dkey, boss, { src = "group" })
  A.Store.Record(dkey, boss, id, "group")
  A.ItemInfo(id)
  Share.stats.got = Share.stats.got + 1
  if A.Window and A.Window.RefreshSoon then A.Window.RefreshSoon() end
  return true
end

function Share.Start()
  if Share.frame then return Share.ready end
  if not Share.Available() then Share.why = "this client has no addon-message functions" return false end
  local ok, res = pcall(A.fn("C_ChatInfo.RegisterAddonMessagePrefix"), Share.PREFIX)
  if not ok then Share.why = "prefix refused: " .. tostring(res) return false end
  local f = CreateFrame("Frame")
  Share.frame = f
  if not pcall(f.RegisterEvent, f, "CHAT_MSG_ADDON") then Share.why = "CHAT_MSG_ADDON unknown" return false end
  f:SetScript("OnEvent", function(_, _, ...)
    local good, err = pcall(Share.OnMessage, ...)
    if not good then HH:LogError("atlas share: " .. tostring(err)) end
  end)
  Share.ready = true
  return true
end

function Share.Report()
  local s = Share.stats
  return ("share: %s, sent %d, received %d, dropped %d, refused by the client %d"):format(
    Share.ready and "on" or ("off (" .. tostring(Share.why or "switched off") .. ")"), s.sent, s.got, s.dropped, s.refused)
end
