-- Finder: invite the role the group is missing the moment the Group Finder shows one.
-- Sean 2026-11-14: "We're having trouble finding a tank. Is there some way ... to auto-invite a tank when they look at
-- the list?" - with far more groups than tanks looking that night, the first invite wins.
--
-- What the client allows - read from Forever 1.60.1's own interface code and API docs, not assumed:
--   * The Group Finder's Invite button is C_PartyInfo.InviteUnit(leaderName) on a listing of ONE player
--     (Blizzard_LFGVanilla_Browse.lua: LFGBrowseUtil_GetInviteActionForResult). InviteUnit carries no restriction
--     flag, so it may be called the moment the list changes.
--   * Refreshing the list is C_LFGList.Search, flagged HasRestrictions: a key press or click of the player must be
--     behind it. Nothing here polls. A search rides on /hh find (the Enter key) or the options button, and every
--     search the Group Finder window runs itself is read too.
--   * A listed GROUP cannot be joined from the list (its only action is Send Message), so players who see OUR
--     listing whisper. A whisper that names the role counts as a volunteer (profile.finder.whisper).
-- One invite at a time; the next candidate after an answer or profile.finder.wait seconds. From the list only single
-- players listed for an activity of OUR listing are invited - without a listing of our own only whispers count (the
-- list could hold any dungeon). A value the client hides (a secret) is counted and skipped, never compared.
-- Unseen in game until /hh finddiag says otherwise: diag.finder keeps what the client answered.
local HH = HogHeals

local F = {
  SEARCH_EVERY = 3,   -- seconds between two searches of ours (the server throttles them)
  -- the word typed -> the key the list's lfgRoles table uses
  ROLE = { tank = "tank", tanks = "tank", healer = "healer", heal = "healer", heals = "healer", healers = "healer",
           dps = "dps", dd = "dps", damage = "dps" },
  LABEL = { tank = "tank", healer = "healer", dps = "damage dealer" },
  VERB = { tank = "tank", healer = "heal", dps = "deal damage in" },
  COUNT = { tank = "LEADER_ROLE_TANK", healer = "LEADER_ROLE_HEALER", dps = "LEADER_ROLE_DAMAGER" },   -- GetSearchResultMemberCounts keys
  WORDS = { tank = { "tank" }, healer = { "heal" }, dps = { "dps", "damage" } },   -- a whisper holding one volunteers
  -- the game's own chat lines after an invite (GlobalStrings): which one arrives says how it went
  ANSWERS = {
    { "ERR_INVITE_PLAYER_S", "sent" }, { "ERR_JOINED_GROUP_S", "joined" }, { "ERR_RAID_MEMBER_ADDED_S", "joined" },
    { "ERR_DECLINE_GROUP_S", "declined" }, { "ERR_ALREADY_IN_GROUP_S", "grouped" }, { "ERR_PLAYER_BUSY_S", "busy" },
    { "ERR_IGNORING_YOU_S", "ignoring" }, { "ERR_BAD_PLAYER_NAME_S", "unknown" },
    { "ERR_PARTY_LFG_INVITE_RAID_LOCKED", "locked" }, { "ERR_GROUP_FULL", "full" }, { "ERR_NOT_LEADER", "leader" },
    { "ERR_INVITE_PARTY_BUSY", "forming" },
  },
  SAID = { declined = "declined", grouped = "is already in a group", busy = "is busy", ignoring = "is ignoring you",
           unknown = "cannot be found", locked = "is locked to another instance" },
  EVENTS = { "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_RESULT_UPDATED", "LFG_LIST_SEARCH_FAILED",
             "LFG_LIST_ACTIVE_ENTRY_UPDATE", "CHAT_MSG_WHISPER", "CHAT_MSG_SYSTEM", "GROUP_ROSTER_UPDATE",
             "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" },
  WHY = {   -- why no search of ours went out
    nolisting = "you have no group listing, so I do not know which dungeon: list your group in the Group Finder, then /hh find again. Whispers still count.",
    refused = "this game build will not let an addon refresh the list. Press the list's own refresh button - I still invite the moment one shows.",
    nocategory = "could not read your listing's category. Press the list's own refresh button - I still invite the moment one shows.",
    nosearch = "this client has no Group Finder search. Whispers still count.",
  },
  HELP = "/hh find tank | healer | dps - invites the first one the Group Finder list shows for your listing, or who whispers it. /hh find again = refresh the list, /hh find off = stop.",
}
HH.Finder = F

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
--- v when the client lets us read it, else nil. A secret is never compared.
local function plain(v) if v == nil or isSecret(v) then return nil end return v end
--- A client flag: true / 1 count, false / nil / 0 do not (Classic-family clients answer 1 / nil).
local function yes(v)
  v = plain(v)
  return v ~= nil and v ~= false and v ~= 0
end
local function g(n) return rawget(_G, n) end
local function fn(t, k) return type(t) == "table" and type(t[k]) == "function" and t[k] or nil end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
end
local function now() return (type(GetTime) == "function" and GetTime()) or 0 end
local function stamp() return type(date) == "function" and date("%Y-%m-%d %H:%M:%S") or "" end
local function cfg()
  local p = HH.db and HH.db.profile
  if not p then return {} end
  p.finder = p.finder or {}
  return p.finder
end
local function say(text) HH:Print("find: " .. text) end
local function build()
  local _, b = call(g("GetBuildInfo"))
  return plain(b)
end

function F.Wait() local v = tonumber(cfg().wait) or 45 if v < 5 then v = 5 end return v end
function F.Max() return tonumber(cfg().maxInvites) or 10 end
function F.Minutes() return tonumber(cfg().minutes) or 30 end

-- ---------------------------------------------------------------- names
local function norm(s)
  s = s:lower():gsub("[%s%-]+", " ")
  s = s:gsub("^ ", "")
  s = s:gsub(" $", "")
  return s
end

--- The same player? Case, and space vs dash, do not matter ("Brakka Ironhide" = "brakka-ironhide"); a bare first name
-- matches the full one (a client that only hands over the first name of a group member).
function F.SameName(a, b)
  if isSecret(a) or isSecret(b) then return false end
  if type(a) ~= "string" or type(b) ~= "string" then return false end
  local x, y = norm(a), norm(b)
  if x == "" or y == "" then return false end
  if x == y then return true end
  if #x > #y then x, y = y, x end
  return y:sub(1, #x + 1) == x .. " "
end

local MARK = string.char(1)
local patterns = {}
--- "%s declines your group invitation." -> "^(.+) declines your group invitation%.$"
local function pattern(fmt)
  if isSecret(fmt) or type(fmt) ~= "string" or fmt == "" then return nil end
  local p = patterns[fmt]
  if not p then
    p = fmt:gsub("%%%d*%$?s", MARK)
    p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    p = "^" .. p:gsub(MARK, "(.+)") .. "$"
    patterns[fmt] = p
  end
  return p
end

--- Names of the group's other members as the client spells them. Forever hands the surname as UnitName's second
-- value (elsewhere it is the realm); with one, only the full name is offered so two "Storm ..." never match.
local function groupNames()
  local out = {}
  local prefix, count = "party", 4
  if yes(call(g("IsInRaid"))) then prefix, count = "raid", tonumber(plain(call(g("GetNumGroupMembers")))) or 0 end
  local exists, unitName = g("UnitExists"), g("UnitName")
  for i = 1, count do
    local unit = prefix .. i
    if yes(call(exists, unit)) then
      local name, second = call(unitName, unit)
      name, second = plain(name), plain(second)
      if type(name) == "string" and name ~= "" then
        if type(second) == "string" and second ~= "" then out[#out + 1] = name .. " " .. second else out[#out + 1] = name end
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------- what the group may do
--- May this character invite? The game's own rule (LFGBrowseUtil_GetInviteActionForResult). true, or false + why.
function F.CanInvite()
  if not yes(call(g("IsInGroup"))) then return true end
  if yes(call(g("UnitIsGroupLeader"), "player")) or yes(call(g("UnitIsGroupAssistant"), "player")) then return true end
  return false, "only the group leader can invite. Ask for lead, or have the leader type /hh find."
end

--- A party of five has no seat left (a raid is left alone).
function F.Full()
  if yes(call(g("IsInRaid"))) then return false end
  local n = plain(call(g("GetNumGroupMembers")))
  return type(n) == "number" and n >= 5
end

--- The activity ids of our own listing, or nil when we have none.
function F.Activities()
  local L = g("C_LFGList")
  local entry = fn(L, "GetActiveEntryInfo") and call(L.GetActiveEntryInfo) or nil
  local ids = type(entry) == "table" and plain(entry.activityIDs) or nil
  if type(ids) ~= "table" then return nil end
  local out = {}
  for i = 1, #ids do
    local id = plain(ids[i])
    if type(id) == "number" and id ~= 0 then out[#out + 1] = id end
  end
  if #out == 0 then return nil end
  return out
end

-- ---------------------------------------------------------------- the list
-- One listing -> a candidate, or nil + why not ("hidden", "self", "delisted", "group", "role", "activity", "name").
local function read(L, id, info, role, want)
  if isSecret(id) or isSecret(info.numMembers) then return nil, "hidden" end
  local members = info.numMembers
  if yes(info.hasSelf) then return nil, "self" end
  if yes(info.isDelisted) then return nil, "delisted" end
  if type(members) ~= "number" or members ~= 1 then return nil, "group" end
  local player = fn(L, "GetSearchResultPlayerInfo") and call(L.GetSearchResultPlayerInfo, id, 1) or nil
  if type(player) ~= "table" then player = fn(L, "GetSearchResultLeaderInfo") and call(L.GetSearchResultLeaderInfo, id) or nil end
  if type(player) ~= "table" then player = {} end
  local roles = plain(player.lfgRoles)
  local flag
  if type(roles) == "table" then
    flag = roles[role]
  else
    local counts = fn(L, "GetSearchResultMemberCounts") and call(L.GetSearchResultMemberCounts, id) or nil
    flag = type(counts) == "table" and counts[F.COUNT[role]] or nil
  end
  if isSecret(flag) then return nil, "hidden" end
  if not yes(flag) then return nil, "role" end
  if want then
    local acts = plain(info.activityIDs)
    local hit = false
    if type(acts) == "table" then
      for i = 1, #acts do
        local a = plain(acts[i])
        if a ~= nil and want[a] then hit = true break end
      end
    end
    if not hit then return nil, "activity" end
  end
  local name = plain(info.leaderName)
  if type(name) ~= "string" or name == "" then name = plain(player.name) end
  if type(name) ~= "string" or name == "" then return nil, (isSecret(info.leaderName) and "hidden" or "name") end
  local age = plain(info.age)
  local class = plain(player.className)
  return { id = id, name = name, from = "list", level = tonumber(plain(player.level)),
           class = type(class) == "string" and class or nil, age = type(age) == "number" and age or 0 }
end

--- Every single player on the list who offers the role (for an activity of our listing, when we have one), the
-- newest listing first: with more groups than tanks, whoever just listed is the one still free and at the keyboard.
-- Also returns what was seen: { results, solo, match, hidden, ... }. Looking sends nothing.
function F.Candidates(role)
  local seen = { results = 0, solo = 0, match = 0, hidden = 0 }
  local out = {}
  local L = g("C_LFGList")
  local list = fn(L, "GetFilteredSearchResults") or fn(L, "GetSearchResults")
  if not list or not fn(L, "GetSearchResultInfo") then seen.why = "this client has no Group Finder list an addon can read." return out, seen end
  local _, ids = call(list)
  if type(ids) ~= "table" then return out, seen end
  local mine = F.Activities()
  local want
  if mine then
    want = {}
    for i = 1, #mine do want[mine[i]] = true end
  end
  for i = 1, #ids do
    local id = ids[i]
    local info = call(L.GetSearchResultInfo, id)
    if type(info) == "table" then
      seen.results = seen.results + 1
      local c, why = read(L, id, info, role, want)
      if c then
        out[#out + 1] = c
      else
        seen[why] = (seen[why] or 0) + 1
      end
      if why ~= "hidden" and why ~= "group" and why ~= "self" and why ~= "delisted" then seen.solo = seen.solo + 1 end
    end
  end
  seen.match = #out
  table.sort(out, function(a, b)
    if a.age ~= b.age then return a.age < b.age end
    return a.id < b.id
  end)
  return out, seen
end

--- Ask the game for a fresh list of our listing's activities. The client wants the player's key press or click
-- behind a search, so this is only ever called from /hh find and the options buttons - never from a timer.
-- true, or nil + why ("nolisting", "refused", "throttle", "nocategory", "nosearch", or the client's error text).
function F.Search()
  local h = F.hunt
  local L = g("C_LFGList")
  if not fn(L, "Search") then return nil, "nosearch" end
  local acts = F.Activities()
  if not acts then return nil, "nolisting" end
  local no = HH.db and HH.db.global and HH.db.global.finderNoSearch
  if type(no) == "table" and no.build == build() then return nil, "refused" end
  local t = now()
  if h and h.searchAt and t - h.searchAt < F.SEARCH_EVERY then return nil, "throttle" end
  local info = fn(L, "GetActivityInfoTable") and call(L.GetActivityInfoTable, acts[1]) or nil
  local category = type(info) == "table" and plain(info.categoryID) or nil
  if type(category) ~= "number" then return nil, "nocategory" end
  if h then h.searchAt = t; h.searches = h.searches + 1 end
  -- the same call the window's own refresh makes (LFGBrowse_DoSearch): category, no filters, our activities
  local ok, err = pcall(L.Search, category, 0, 0, nil, false, nil, acts)
  if not ok then
    if h then h.searchErr = tostring(err) end
    return nil, tostring(err)
  end
  return true
end

-- ---------------------------------------------------------------- inviting
local function describe(h, c)
  local bits = { F.LABEL[h.role] }
  if c.level then bits[#bits + 1] = "level " .. c.level end
  if c.class then bits[#bits + 1] = c.class end
  local who = table.concat(bits, ", ")
  if c.from == "whisper" then return ('invited %s (%s) who whispered "%s".'):format(c.name, who, c.said or "") end
  return ("invited %s (%s) from the Group Finder list."):format(c.name, who)
end

--- Still worth an invite? A volunteer always is; a list entry must still be listed and still be the same player.
function F.Fresh(c)
  if c.from ~= "list" then return true end
  local L = g("C_LFGList")
  local info = fn(L, "GetSearchResultInfo") and call(L.GetSearchResultInfo, c.id) or nil
  if type(info) ~= "table" or yes(info.isDelisted) then return false end
  local name = plain(info.leaderName)
  if name ~= nil and name ~= c.name then return false end
  return true
end

--- Send the invite. true when it went out and we now wait on an answer.
function F.Invite(c)
  local h = F.hunt
  if not h then return false end
  local P = g("C_PartyInfo")
  local invite = fn(P, "InviteUnit") or g("InviteUnit")
  if type(invite) ~= "function" then F.Stop("noapi") return false end
  local key = norm(c.name)
  h.tried[key] = true
  h.invites = h.invites + 1
  local rec = { name = c.name, from = c.from, said = c.said, secs = math.floor(now() - h.started) }
  h.log[#h.log + 1] = rec
  local ok, err = pcall(invite, c.name)   -- the name exactly as the client gave it
  rec.ok = ok
  if not ok then
    rec.err = tostring(err)
    say(("the game refused the invite to %s: %s"):format(c.name, rec.err))
    return false
  end
  h.pending = { name = c.name, key = key, at = now(), rec = rec, cand = c }
  h.sent[key] = c.name
  say(describe(h, c))
  return true
end

--- Invite the next one in line, when nobody is being waited on.
function F.Next()
  local h = F.hunt
  if not h or h.pending then return end
  if h.hold and now() < h.hold then return end
  if not F.CanInvite() then return F.Stop("leader") end
  if F.Full() then return F.Stop("full") end
  while #h.queue > 0 do
    local c = table.remove(h.queue, 1)
    if F.Fresh(c) then
      if h.invites >= F.Max() then return F.Stop("cap") end
      if F.Invite(c) then return end
    end
    if F.hunt ~= h then return end
  end
end

--- Read the list as it stands: volunteers keep their place in front, the list's candidates are taken fresh.
function F.Scan()
  local h = F.hunt
  if not h then return 0 end
  h.scans = h.scans + 1
  if not F.Activities() then h.noListing = true return 0 end
  h.noListing = nil
  local list, seen = F.Candidates(h.role)
  h.seen = seen
  local queue, have = {}, {}
  for _, c in ipairs(h.queue) do
    if c.from == "whisper" then queue[#queue + 1] = c; have[norm(c.name)] = true end
  end
  local fresh = 0
  for _, c in ipairs(list) do
    local key = norm(c.name)
    if not h.tried[key] and not have[key] then queue[#queue + 1] = c; have[key] = true; fresh = fresh + 1 end
  end
  h.queue = queue
  F.Next()
  return fresh
end

--- One line on what the list held, or nil when there is nothing to say.
function F.Summary()
  local h = F.hunt
  local s = h and h.seen
  if not s then return nil end
  if s.why then return s.why end
  if s.results > 0 and s.hidden >= s.results then return "the game is hiding the Group Finder list from addons right now." end
  if s.match == 0 then
    return ("list: %d listings, %d single players, no %s for your dungeon among them. It only changes when refreshed: /hh find again."):format(s.results, s.solo, F.LABEL[h.role])
  end
  return ("list: %d single players offer to %s your dungeon, all asked already. /hh find again refreshes it."):format(s.match, F.VERB[h.role])
end

--- Does this whisper volunteer for the role?
function F.Volunteers(role, text)
  if isSecret(text) or type(text) ~= "string" then return false end
  local low = text:lower()
  for _, word in ipairs(F.WORDS[role] or {}) do
    if low:find(word, 1, true) then return true end
  end
  return false
end

--- A whisper came in (CHAT_MSG_WHISPER text, sender).
function F.Whisper(text, sender)
  local h = F.hunt
  if not h or cfg().whisper == false then return end
  if isSecret(text) or isSecret(sender) then h.hiddenWhispers = (h.hiddenWhispers or 0) + 1 return end
  if type(sender) ~= "string" or sender == "" or not F.Volunteers(h.role, text) then return end
  local key = norm(sender)
  if h.pending and h.pending.key == key then return end
  h.asks[key] = (h.asks[key] or 0) + 1
  if h.asks[key] > 2 then return end   -- a volunteer is invited twice at most
  h.whispers = h.whispers + 1
  local queue = {}
  local at = 1
  for _, c in ipairs(h.queue) do
    if norm(c.name) ~= key then queue[#queue + 1] = c end   -- the list's entry for the same player gives way
  end
  while queue[at] and queue[at].from == "whisper" do at = at + 1 end
  local said = text:gsub("|", "")
  table.insert(queue, at, { name = sender, from = "whisper", said = said:sub(1, 60) })
  h.queue = queue
  F.Next()
end

--- The game answered an invite. what = an ANSWERS word, who = the name in the game's line.
function F.Answer(what, who)
  local h = F.hunt
  if not h then return end
  local p = h.pending
  if what == "joined" then
    local mine = p and F.SameName(who, p.name) and p.name or nil
    if not mine then
      for _, name in pairs(h.sent) do
        if F.SameName(who, name) then mine = name break end
      end
    end
    if not mine then return end
    if p and mine == p.name then p.rec.answer = "joined" end
    return F.Stop("joined", mine)
  end
  if what == "sent" then
    if p and F.SameName(who, p.name) then p.rec.acked = true end
    return
  end
  if what == "full" then return F.Stop("full") end
  if what == "leader" then return F.Stop("leader") end
  if what == "forming" then
    -- "Cannot invite additional players until the party is formed": ours did not go out. Same player again shortly.
    if p and not p.rec.acked then
      local c = p.cand
      c.retries = (c.retries or 0) + 1
      p.rec.answer = "the party was still forming"
      h.pending = nil
      h.sent[p.key] = nil
      if c.retries <= 3 then
        h.tried[p.key] = nil
        h.invites = h.invites - 1
        table.insert(h.queue, 1, c)
        h.hold = now() + 3
      end
    end
    return
  end
  -- declined / grouped / busy / ignoring / unknown / locked: only the player being waited on moves the line
  if p and F.SameName(who, p.name) then
    p.rec.answer = what
    h.pending = nil
    say(("%s %s - next."):format(p.name, F.SAID[what] or what))
    F.Next()
    if F.hunt == h and not h.pending then
      local line = F.Summary()
      if line then say(line) end
    end
  end
end

--- A system chat line: is it the game's answer to an invite?
function F.System(msg)
  if not F.hunt or isSecret(msg) or type(msg) ~= "string" then return end
  for _, a in ipairs(F.ANSWERS) do
    local p = pattern(g(a[1]))
    if p then
      local who = msg:match(p)
      if who then return F.Answer(a[2], who) end
    end
  end
end

--- The group changed: did someone we invited arrive, may we still invite, is there a seat left?
function F.Roster()
  local h = F.hunt
  if not h then return end
  for _, name in ipairs(groupNames()) do
    for key, sent in pairs(h.sent) do
      if F.SameName(name, sent) then
        if h.pending and h.pending.key == key then h.pending.rec.answer = "joined" end
        return F.Stop("joined", sent)
      end
    end
  end
  if not F.CanInvite() then return F.Stop("leader") end
  if F.Full() then return F.Stop("full") end
end

--- The client named us for an action it refuses. Right after a search of ours = searches are not for addons here:
-- remembered for this game build so it is never tried again.
function F.Blocked(event, _, func)
  local h = F.hunt
  if not h or not h.searchAt or now() - h.searchAt > 2 then return end
  if isSecret(func) or type(func) ~= "string" or not func:find("Search", 1, true) then return end
  h.searchErr = event
  local gl = HH.db and HH.db.global
  if gl then gl.finderNoSearch = { why = event .. " " .. func, build = build(), at = stamp() } end
  say(F.WHY.refused)
end

--- Once a second while hunting: give up on an invite nobody answered, pick up list changes, end an old hunt.
function F.Tick()
  local h = F.hunt
  if not h then return end
  local t = now()
  local p = h.pending
  if p and t - p.at >= F.Wait() then
    p.rec.answer = "no answer"
    h.pending = nil
    say(("no answer from %s in %d seconds - next."):format(p.name, F.Wait()))
    F.Next()
  elseif not p and #h.queue > 0 then
    F.Next()
  end
  if F.hunt == h and h.dirty then
    h.dirty = nil
    F.Scan()
  end
  if F.hunt == h and t - h.started >= F.Minutes() * 60 then F.Stop("time") end
end

function F.OnEvent(event, ...)
  local h = F.hunt
  if not h then return end
  if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
    h.answers = h.answers + 1
    F.Scan()
    if F.hunt == h and not h.pending then
      local line = h.noListing and F.WHY.nolisting or F.Summary()
      if line and (line ~= h.lastLine or now() - (h.lastLineAt or 0) > 10) then
        h.lastLine, h.lastLineAt = line, now()
        say(line)
      end
    end
  elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" or event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
    h.dirty = true   -- they come in bursts: read once, on the next tick
  elseif event == "LFG_LIST_SEARCH_FAILED" then
    h.failed = (h.failed or 0) + 1
  elseif event == "CHAT_MSG_WHISPER" then
    F.Whisper(...)
  elseif event == "CHAT_MSG_SYSTEM" then
    F.System((...))
  elseif event == "GROUP_ROSTER_UPDATE" then
    F.Roster()
  elseif event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
    F.Blocked(event, ...)
  end
end

-- ---------------------------------------------------------------- on / off
local function listen(on)
  local f = F.frame
  if not f then
    f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, event, ...)
      local ok, err = pcall(F.OnEvent, event, ...)
      if not ok then HH:LogError("finder " .. tostring(event) .. ": " .. tostring(err)) end
    end)
    F.frame = f
  end
  for _, e in ipairs(F.EVENTS) do
    if on then pcall(f.RegisterEvent, f, e) else pcall(f.UnregisterEvent, f, e) end
  end
end

local function tick()
  local ok, err = pcall(F.Tick)
  if not ok then HH:LogError("finder tick: " .. tostring(err)) end
end
local function clock(on)
  if F.ticker and F.ticker.Cancel then pcall(F.ticker.Cancel, F.ticker) end
  F.ticker = nil
  if not on then return end
  local T = g("C_Timer")
  if fn(T, "NewTicker") then F.ticker = T.NewTicker(1, tick) end
end

--- Keep what happened where it survives to disk (diag.finder). why = how the hunt ended, nil = still running.
function F.Record(h, why)
  local gl = HH.db and HH.db.global
  if not gl then return end
  gl.diag = gl.diag or {}
  local d = gl.diag.finder or { hunts = 0 }
  gl.diag.finder = d
  if why then d.hunts = (d.hunts or 0) + 1 end
  local log = {}
  for i = math.max(1, #h.log - 11), #h.log do log[#log + 1] = h.log[i] end
  d.last = { at = stamp(), role = h.role, stopped = why, secs = math.floor(now() - h.started), searches = h.searches,
             searchErr = h.searchErr, answers = h.answers, failed = h.failed, scans = h.scans, whispers = h.whispers,
             hiddenWhispers = h.hiddenWhispers, noListing = h.noListing, seen = h.seen, invites = log }
end

--- Start hunting a role. true, or false + why not.
function F.Start(role)
  role = F.ROLE[role or ""] or "tank"
  local ok, why = F.CanInvite()
  if not ok then say(why) return false, why end
  if F.Full() then say("your group is full.") return false, "full" end
  if F.hunt then F.Stop("switch") end
  local h = { role = role, started = now(), queue = {}, tried = {}, sent = {}, asks = {}, log = {}, invites = 0, searches = 0,
              answers = 0, scans = 0, whispers = 0 }
  F.hunt = h
  listen(true)
  clock(true)
  local searched, sWhy = F.Search()
  local word = F.WORDS[role][1]
  say(("hunting a %s: the first single player on the Group Finder list who offers to %s your dungeon gets an invite%s. One at a time, %d seconds for an answer. /hh find = refresh the list, /hh find off = stop."):format(
    F.LABEL[role], F.VERB[role], cfg().whisper ~= false and (', and so does anyone who whispers "' .. word .. '"') or "", F.Wait()))
  if not searched and sWhy ~= "throttle" then
    say(F.WHY[sWhy] or ("could not refresh the list myself (" .. tostring(sWhy) .. "). Press the list's own refresh button - I still invite the moment one shows."))
  end
  F.Scan()   -- whatever the list already holds
  return true
end

--- End the hunt. why: joined | off | full | leader | cap | time | noapi | switch (switch says nothing).
function F.Stop(why, who)
  local h = F.hunt
  if not h then return end
  F.hunt = nil
  listen(false)
  clock(false)
  why = why or "off"
  F.Record(h, why)
  local label = F.LABEL[h.role]
  if why == "switch" then return
  elseif why == "joined" then say(("%s joined - you have your %s. Hunt over."):format(tostring(who), label))
  elseif why == "full" then say("your group is full - hunt over.")
  elseif why == "leader" then say("you are not the group leader any more - hunt over (only the leader can invite).")
  elseif why == "cap" then say(("%d invites and nobody joined - stopped. /hh find %s starts again."):format(h.invites, h.role))
  elseif why == "time" then say(("%d minutes without a %s - stopped. /hh find %s starts again."):format(F.Minutes(), label, h.role))
  elseif why == "noapi" then say("this client has no invite function an addon may call - stopped.")
  else say("stopped.") end
end

--- /hh find again while hunting: a fresh list (the key press behind the command is what the client wants), a read
-- of it, and where things stand.
function F.Refresh()
  local h = F.hunt
  if not h then return end
  local ok, why = F.Search()
  F.Scan()
  if F.hunt ~= h then return end
  if h.pending then
    say(("waiting on %s, %d seconds left."):format(h.pending.name, math.max(0, math.ceil(F.Wait() - (now() - h.pending.at)))))
  elseif ok then
    say("asked the game for a fresh list.")
  elseif why == "throttle" then
    say("the list was refreshed a moment ago.")
  else
    say(F.WHY[why] or ("could not refresh the list myself (" .. tostring(why) .. "). Press the list's own refresh button - I still invite the moment one shows."))
  end
end

--- /hh find [tank | healer | dps | off]. Nothing after it = a tank, or a refresh while a hunt runs.
function F.Command(rest)
  local word = (rest or ""):lower():match("^%s*(%S+)")
  if word == "off" or word == "stop" or word == "cancel" then
    if F.hunt then F.Stop("off") else say("not hunting. " .. F.HELP) end
    return
  end
  local role = word and F.ROLE[word] or nil
  if word and not role then say(F.HELP) return end
  if F.hunt and (not role or role == F.hunt.role) then return F.Refresh() end
  F.Start(role or "tank")
end

--- What the finder saw and did, as chat lines (/hh finddiag). Looking at the list sends nothing.
function F.Diag()
  local out = {}
  local h = F.hunt
  if h then F.Record(h, nil) end
  local gl = HH.db and HH.db.global
  local d = gl and gl.diag and gl.diag.finder
  local last = d and d.last
  if h then
    out[#out + 1] = ("find: hunting a %s for %d seconds%s."):format(F.LABEL[h.role], math.floor(now() - h.started), h.pending and (", waiting on " .. h.pending.name) or "")
  else
    out[#out + 1] = "find: off" .. (last and (" (last hunt: " .. tostring(last.role) .. ", ended: " .. tostring(last.stopped) .. ")") or "") .. "."
  end
  local mine = F.Activities()
  local parts, seen = {}, nil
  for _, role in ipairs({ "tank", "healer", "dps" }) do
    local list, s = F.Candidates(role)
    seen = s
    parts[#parts + 1] = ("%s %d"):format(role, #list)
  end
  if seen.why then
    out[#out + 1] = "list now: " .. seen.why
  else
    out[#out + 1] = ("list now: %d listings, %d single players, %d hidden by the game. Offering (%s): %s."):format(
      seen.results, seen.solo, seen.hidden, mine and "for your listing" or "any dungeon - you have no listing", table.concat(parts, ", "))
  end
  if last then
    out[#out + 1] = ("searches I asked for: %d (%s), list answers: %d, whispers that counted: %d."):format(
      last.searches or 0, last.searchErr and ("refused: " .. tostring(last.searchErr)) or "none refused", last.answers or 0, last.whispers or 0)
    for i, r in ipairs(last.invites or {}) do
      local sent = "the game refused it: " .. tostring(r.err)
      if r.ok then sent = r.acked and "the game confirmed the invite" or "sent, no confirming line seen" end
      out[#out + 1] = ("%d. %s (%s): %s%s"):format(i, tostring(r.name), tostring(r.from), sent, r.answer and (" -> " .. tostring(r.answer)) or "")
    end
  end
  local no = gl and gl.finderNoSearch
  if type(no) == "table" then out[#out + 1] = "the game refused a search an addon started: " .. tostring(no.why) end
  return out
end

HH:RegisterSlash("find", function(rest) F.Command(rest) end,
  "invite the first tank the Group Finder shows: /hh find tank | healer | dps | off (again = refresh the list)")
HH:RegisterSlash("finddiag", function()
  for _, line in ipairs(F.Diag()) do HH:Print(line) end
end, "what /hh find saw on the list and did")

local Module = {}
function Module:GetOptions()
  return {
    type = "group", name = "Group Finder", order = 60,
    args = {
      about = { type = "description", order = 1, name = "Short a tank? Find a tank invites the first single player on the Group Finder list who offers to tank a dungeon you listed your group for - and anyone who whispers \"tank\" - one at a time, the moment they show. The game only refreshes the list on your own click or key press, so press the button (or type /hh find) again to look again; nothing here refreshes on a timer. Only the group leader can invite.\n" },
      tank = { type = "execute", order = 2, name = "Find a tank", desc = "Start, or refresh the list while it runs. Same as /hh find tank.",
        func = function() F.Command("tank") end },
      healer = { type = "execute", order = 3, name = "Find a healer", desc = "Same as /hh find healer.",
        func = function() F.Command("healer") end },
      dps = { type = "execute", order = 4, name = "Find a damage dealer", desc = "Same as /hh find dps.",
        func = function() F.Command("dps") end },
      stop = { type = "execute", order = 5, name = "Stop", desc = "Same as /hh find off.",
        disabled = function() return F.hunt == nil end,
        func = function() F.Command("off") end },
      whisper = { type = "toggle", order = 6, name = "Whispers count",
        desc = "While a hunt runs, a whisper with the role in it (\"tank\", \"heal\", \"dps\") gets an invite, ahead of the list.",
        get = function() return cfg().whisper ~= false end,
        set = function(_, v) cfg().whisper = v and true or false end },
      wait = { type = "range", order = 7, name = "Seconds to wait for an answer", min = 15, max = 90, step = 5,
        desc = "How long one invite may sit unanswered before the next player is asked.",
        get = function() return F.Wait() end,
        set = function(_, v) cfg().wait = v end },
    },
  }
end
function Module:OnProfileChanged() end

HH:RegisterModule("Finder", Module)
