-- HogTron UI Journal: a healer's dungeon journal for WoW: Forever. Namespace, settings, safe helpers, and the
-- answers every other file asks for: where am I, which dungeon is that, what does a healer need to know.
--
-- Why a shipped table and not the client's Encounter Journal: measured on Forever 2026-09-29 (Atlas sweep,
-- diag.atlasSweep on disk): the EJ_* functions EXIST but EJ_GetTierInfo(1) says "Invalid index", the instance list
-- is empty, and 1500 instance ids asked by EJ_GetInstanceInfo answered with nothing. Probe.lua re-measures that on
-- every login so a client that starts answering is noticed. Until then the data is hand-written (Data/Dungeons.lua)
-- and says so on screen.
--
-- Rules for this client (see HogHeals_Atlas/Atlas.lua): every RegisterEvent is pcall'd, nothing that might be a
-- secret value is compared, tested or used in arithmetic, and functions are looked up by name before use.
HogHealsJournal = HogHealsJournal or {}
local J = HogHealsJournal
local HH = HogHeals

J.COLORS = {
  cream = { 0.96, 0.92, 0.86 }, cyan = { 0.13, 0.83, 0.88 }, ink = { 0.07, 0.07, 0.09 }, panel = { 0.11, 0.11, 0.14 },
  line = { 0.20, 0.20, 0.25 }, grey = { 0.55, 0.55, 0.60 }, green = { 0.25, 0.80, 0.35 }, amber = { 0.95, 0.65, 0.15 },
  red = { 0.85, 0.20, 0.20 }, purple = { 0.64, 0.21, 0.93 }, blue = { 0.25, 0.55, 0.95 },
}

-- Settings live in the core profile under .journal (Core/Defaults.lua carries the same keys); filled here too so the
-- module stands on its own when the core's defaults are older than this file.
J.DEFAULTS = {
  enabled = true,
  autoOpen = true,        -- open the journal the first time you enter a dungeon this session
  partySummary = false,   -- one line to party chat on zone-in when somebody there has not heard it (default OFF)
  scale = 1,
}

local function fill(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      if type(v) == "table" then dst[k] = {} fill(dst[k], v) else dst[k] = v end
    end
  end
  return dst
end

function J.cfg()
  local p = HH.db and HH.db.profile
  if not p then J.mem = J.mem or fill({}, J.DEFAULTS) return J.mem end
  p.journal = p.journal or {}
  if J.filled ~= p.journal then fill(p.journal, J.DEFAULTS) J.filled = p.journal end
  return p.journal
end

--- Account-wide memory (HogHealsDB.global.journal): who has heard the party summary for which dungeon.
function J.db()
  local g = HH.db and HH.db.global
  if not g then J.gmem = J.gmem or {} g = J.gmem end
  g.journal = g.journal or {}
  g.journal.said = g.journal.said or {}
  return g.journal
end

-- ------------------------------------------------------------------------------------------------ safe values
function J.isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
function J.num(v) if type(v) == "number" and not J.isSecret(v) then return v end end
function J.str(v) if type(v) == "string" and not J.isSecret(v) then return v end end
function J.plain(v) if J.isSecret(v) then return nil end return v end

--- fn(...) without ever throwing; every return handed back. Missing function = nothing.
function J.call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local function pack(ok, ...) if ok then return ... end end
  return pack(pcall(fn, ...))
end

--- Function at a dotted path off _G ("C_EncounterJournal.GetLootInfo"), or nil.
function J.fn(path)
  local cur = _G
  for piece in path:gmatch("[^%.]+") do
    if type(cur) ~= "table" then return nil end
    cur = rawget(cur, piece)
    if cur == nil then return nil end
  end
  if type(cur) == "function" then return cur end
end

function J.now() return (type(date) == "function" and date("%Y-%m-%d %H:%M")) or "" end

function J.playerClass()
  local _, class = J.call(UnitClass, "player")
  return J.str(class) or "WARRIOR"
end
function J.playerFaction()
  local f = J.str(J.call(rawget(_G, "UnitFactionGroup"), "player"))
  if f == "Horde" then return "H" elseif f == "Alliance" then return "A" end
end

-- ------------------------------------------------------------------------------------------------ healer vocabulary
-- Who can remove what. The old game's kits (Classic): Priest magic + disease, Paladin magic (Cleanse) + disease +
-- poison, Shaman disease + poison, Druid curse + poison, Mage curse. NOT VERIFIED ON FOREVER: a class may have gained
-- or lost one. The window says "old list" next to it.
J.DISPEL = {
  magic = { "PRIEST", "PALADIN" },
  curse = { "MAGE", "DRUID" },
  disease = { "PRIEST", "PALADIN", "SHAMAN" },
  poison = { "DRUID", "PALADIN", "SHAMAN" },
}
J.SCHOOL_ORDER = { "magic", "curse", "disease", "poison" }
J.SCHOOL_COLOR = { magic = J.COLORS.blue, curse = J.COLORS.purple, disease = { 0.6, 0.4, 0.0 }, poison = J.COLORS.green }
J.CLASS_LABEL = { PRIEST = "Priest", PALADIN = "Paladin", SHAMAN = "Shaman", DRUID = "Druid", MAGE = "Mage",
  WARLOCK = "Warlock", WARRIOR = "Warrior", ROGUE = "Rogue", HUNTER = "Hunter" }
-- Vocabulary each cast may use; Data/Dungeons.lua is checked against these by the tests.
J.HITS = { tank = true, target = true, group = true }          -- who the cast lands on
J.SHIELD = { tank = true, target = true, group = true }        -- who to pre-shield before it
J.KICK = { [1] = "must", [2] = "nice" }                        -- interrupt priority
J.LOAD = { none = true, low = true, moderate = true, heavy = true }   -- damage load on tank / group

function J.Dispellers(school) return J.DISPEL[school] or {} end
function J.CanDispel(class, school)
  for _, c in ipairs(J.Dispellers(school)) do if c == class then return true end end
  return false
end
function J.ClassNames(list)
  local out = {}
  for _, c in ipairs(list or {}) do out[#out + 1] = J.CLASS_LABEL[c] or c end
  return table.concat(out, ", ")
end

-- ------------------------------------------------------------------------------------------------ the data
J.Data = J.Data or { Dungeons = {} }

--- Dungeon table by instance map id, by key, or by (lower-cased) name. nil when nothing is shipped for it.
function J.Dungeon(what)
  local D = J.Data.Dungeons
  if type(what) == "number" then
    for _, d in ipairs(D) do if d.inst == what then return d end end
    return nil
  end
  what = J.str(what)
  if not what then return nil end
  local w = what:lower()
  for _, d in ipairs(D) do if d.key == w then return d end end
  for _, d in ipairs(D) do if d.name:lower() == w then return d end end
end

function J.Dungeons() return J.Data.Dungeons end

-- ------------------------------------------------------------------------------------------------ where am I
--- The instance around the player, read without touching anything secret:
-- { kind = "party"|"raid", inst = map id or nil, name = string or nil, secret = true when the client hid them }.
-- nil when outside dungeons and raids.
function J.Where()
  local name, kind, _, _, _, _, _, inst = J.call(rawget(_G, "GetInstanceInfo"))
  kind = J.str(kind)
  if kind ~= "party" and kind ~= "raid" then
    -- the kind itself may be secret on a restricted client: IsInInstance is the second opinion
    local inside, k2 = J.call(rawget(_G, "IsInInstance"))
    k2 = J.str(k2)
    if J.plain(inside) ~= true or (k2 ~= "party" and k2 ~= "raid") then return nil end
    kind = k2
  end
  local w = { kind = kind, inst = J.num(inst), name = J.str(name) }
  w.secret = (w.inst == nil and inst ~= nil) or (w.name == nil and name ~= nil) or false
  return w
end

--- The shipped dungeon for where the player stands: id first, name second. Returns dungeon, where.
function J.Current()
  local w = J.Where()
  if not w then return nil, nil end
  return (w.inst and J.Dungeon(w.inst)) or (w.name and J.Dungeon(w.name)) or nil, w
end

-- ------------------------------------------------------------------------------------------------ compat / degrade
-- What this client offers, measured once per login (Module calls Check) and shown in the window's footer. Nothing
-- here turns the module off: a missing piece makes the window say what it cannot do instead of erroring.
J.Compat = { flags = {} }

function J.Compat.Check()
  local f = {}
  f.instanceInfo = type(rawget(_G, "GetInstanceInfo")) == "function"
  f.ej = J.fn("EJ_GetInstanceInfo") ~= nil and J.fn("EJ_GetEncounterInfoByIndex") ~= nil
  f.questLog = type(rawget(_G, "HogHealsQuests")) == "table"
  f.chat = type(rawget(_G, "SendChatMessage")) == "function"
  local w = J.Where()
  f.secretInstance = w and w.secret or false
  J.Compat.flags = f
  return f
end

--- Human lines about what is degraded. Empty = everything this version needs is there.
function J.Compat.Degraded()
  local f = J.Compat.flags
  local out = {}
  if f.instanceInfo == false then out[#out + 1] = "GetInstanceInfo is missing: the journal cannot tell which dungeon you are in. Pick one from the list." end
  if f.secretInstance then out[#out + 1] = "This client hides the instance name and id: pick the dungeon from the list." end
  if f.questLog == false then out[#out + 1] = "HogTron UI Quests is not loaded: quests show without your log's progress." end
  if f.chat == false then out[#out + 1] = "SendChatMessage is missing: the party summary is off." end
  return out
end

-- ------------------------------------------------------------------------------------------------ text helpers
--- Word-wrap by character count (the mock cannot measure text and the client's measure can be a secret number).
function J.Wrap(text, width)
  width = width or 72
  local lines, cur = {}, ""
  for word in tostring(text or ""):gmatch("%S+") do
    if cur == "" then cur = word
    elseif #cur + 1 + #word > width then lines[#lines + 1] = cur cur = word
    else cur = cur .. " " .. word end
  end
  if cur ~= "" then lines[#lines + 1] = cur end
  return lines
end

-- ------------------------------------------------------------------------------------------------ boss -> lines
local C = J.COLORS

local function schoolTag(cast, class)
  local s = cast.dispel
  if not s then return nil end
  local who = J.ClassNames(J.Dispellers(s))
  local me = J.CanDispel(class, s) and "YOU can" or "not you"
  return ("%s - dispel (%s): %s - %s"):format(cast.name, s:upper(), who, me), J.SCHOOL_COLOR[s] or C.cream
end

--- The right pane for one boss, as rows { text, color, head }. Pure: BossLines(boss, class).
function J.BossLines(boss, class)
  class = class or J.playerClass()
  local rows = {}
  local function add(text, color, head) rows[#rows + 1] = { text = text, color = color or C.cream, head = head } end
  local function para(text, color) for _, l in ipairs(J.Wrap(text)) do add(l, color) end end
  add(boss.name .. (boss.optional and "  (optional)" or ""), C.cyan, true)
  if boss.summary then para(boss.summary, C.cream) end
  local dmg = boss.damage or {}
  add(("Tank damage: %s     Group damage: %s"):format(dmg.tank or "?", dmg.group or "?"), C.grey)
  -- dispels
  local any = false
  for _, cast in ipairs(boss.casts or {}) do
    local line, color = schoolTag(cast, class)
    if line then
      if not any then add("", C.cream) add("DISPEL", C.amber, true) any = true end
      add("  " .. line, color)
      if cast.note then for _, l in ipairs(J.Wrap(cast.note, 66)) do add("      " .. l, C.grey) end end
    end
  end
  -- shields
  any = false
  for _, cast in ipairs(boss.casts or {}) do
    if cast.shield then
      if not any then add("", C.cream) add("PRE-SHIELD", C.amber, true) any = true end
      add(("  shield the %s before %s"):format(cast.shield, cast.name), C.cream)
    end
  end
  -- kicks
  local kicks = {}
  for _, cast in ipairs(boss.casts or {}) do if cast.kick then kicks[#kicks + 1] = cast end end
  table.sort(kicks, function(a, b) return (a.kick or 9) < (b.kick or 9) end)
  if #kicks > 0 then
    add("", C.cream) add("INTERRUPT", C.amber, true)
    for _, cast in ipairs(kicks) do add(("  %s  (%s)"):format(cast.name, J.KICK[cast.kick] or "?"), cast.kick == 1 and C.red or C.cream) end
  end
  -- the rest of the casts
  any = false
  for _, cast in ipairs(boss.casts or {}) do
    if not cast.dispel and not cast.shield and not cast.kick then
      if not any then add("", C.cream) add("ALSO", C.amber, true) any = true end
      add(("  %s%s%s"):format(cast.name, cast.hits and (" - hits the " .. cast.hits) or "", cast.cc and " - crowd control" or ""), C.cream)
      if cast.note then for _, l in ipairs(J.Wrap(cast.note, 66)) do add("      " .. l, C.grey) end end
    end
  end
  if boss.healer and #boss.healer > 0 then
    add("", C.cream) add("HEALER", C.amber, true)
    for _, tip in ipairs(boss.healer) do
      local lines = J.Wrap(tip, 68)
      for i, l in ipairs(lines) do add((i == 1 and "  - " or "    ") .. l, C.cream) end
    end
  end
  return rows
end

-- ------------------------------------------------------------------------------------------------ quests
--- The player's quest log through HogTron UI Quests when loaded: { [title] = { complete, objectives } }. nil = no log.
function J.LogByTitle(log)
  if log == nil then
    local q = rawget(_G, "HogHealsQuests")
    if type(q) ~= "table" or type(q.Data) ~= "table" or type(q.Data.List) ~= "function" then return nil end
    local ok, list = pcall(q.Data.List)
    if not ok or type(list) ~= "table" then return nil end
    log = list
  end
  local by = {}
  for _, e in ipairs(log) do
    local t = J.str(e.title)
    if t then by[t:lower()] = e end
  end
  return by
end

--- Quest rows for a dungeon: { quest, title, state = "ready"|"active"|"none"|"other", progress }. Faction / class
-- filtered to the player; the other side's quests are listed last and greyed. log = a list for tests.
function J.QuestRows(d, log, faction, class)
  faction = faction or J.playerFaction()
  class = class or J.playerClass()
  local by = J.LogByTitle(log)
  local rows, other = {}, {}
  for _, q in ipairs(d and d.quests or {}) do
    local mine = (not q.side or not faction or q.side == faction) and (not q.class or q.class == class)
    local e = by and by[q.title:lower()]
    local state, progress = "none", nil
    if e then
      state = e.complete and "ready" or "active"
      local done, all = 0, 0
      for _, o in ipairs(e.objectives or {}) do all = all + 1 if o.done then done = done + 1 end end
      if all > 0 then progress = ("%d/%d"):format(done, all) end
    end
    local row = { quest = q, title = q.title, state = mine and state or "other", progress = progress, listed = by ~= nil }
    if mine then rows[#rows + 1] = row else other[#other + 1] = row end
  end
  local rank = { ready = 1, active = 2, none = 3 }
  table.sort(rows, function(a, b)
    if rank[a.state] ~= rank[b.state] then return rank[a.state] < rank[b.state] end
    return (a.quest.order or 99) < (b.quest.order or 99)
  end)
  for _, r in ipairs(other) do rows[#rows + 1] = r end
  return rows
end

--- The right pane for one quest. Pure.
function J.QuestLines(q, state)
  local rows = {}
  local function add(text, color, head) rows[#rows + 1] = { text = text, color = color or C.cream, head = head } end
  local function para(label, text, color) if text then local lines = J.Wrap(text, 66) for i, l in ipairs(lines) do add((i == 1 and (label .. ": ") or string.rep(" ", #label + 2)) .. l, color or C.cream) end end end
  add(q.title, C.cyan, true)
  local who = (q.side == "A" and "Alliance" or q.side == "H" and "Horde" or "Both sides") .. (q.class and (", " .. (J.CLASS_LABEL[q.class] or q.class) .. " only") or "")
  add(who .. (state and state ~= "none" and state ~= "other" and ("   -   in your log: " .. state) or ""), C.grey)
  add("", C.cream)
  para("Goal", q.goal)
  para("From", q.giver and (q.giver .. (q.inside and "  [inside the dungeon]" or "")) or nil)
  para("Turn in", q.turnin and (q.turnin .. (q.turninInside and "  [inside the dungeon]" or "")) or nil)
  if q.prereq then para("Needs first", q.prereq, C.amber) end
  if q.next then para("Leads to", q.next, C.green) end
  if q.note then add("", C.cream) para("Note", q.note, C.grey) end
  return rows
end

-- ------------------------------------------------------------------------------------------------ party summary
--- One chat line for a dungeon: bosses, the dispel schools that matter, the must-kicks. Pure.
function J.SummaryLine(d)
  local schools, seen, kicks = {}, {}, {}
  for _, b in ipairs(d.bosses or {}) do
    for _, c in ipairs(b.casts or {}) do
      if c.dispel and not seen[c.dispel] then seen[c.dispel] = true schools[#schools + 1] = c.dispel end
      if c.kick == 1 and not seen["k:" .. c.name] then seen["k:" .. c.name] = true kicks[#kicks + 1] = c.name end
    end
  end
  local parts = { ("%s: %d bosses"):format(d.name, #(d.bosses or {})) }
  if #schools > 0 then parts[#parts + 1] = "dispel " .. table.concat(schools, "/") end
  if #kicks > 0 then parts[#parts + 1] = "kick " .. table.concat(kicks, ", ") end
  return "[HogTron UI Journal] " .. table.concat(parts, " - ") .. ". /hh journal"
end

--- Names in the party (not the player), readable ones only. Secret names come back as nil entries skipped.
function J.PartyNames()
  local out = {}
  local n = J.num(J.call(rawget(_G, "GetNumGroupMembers"))) or 0
  local raid = J.plain(J.call(rawget(_G, "IsInRaid"))) == true
  for i = 1, math.max(0, n - (raid and 0 or 1)) do
    local unit = (raid and "raid" or "party") .. i
    if J.plain(J.call(UnitExists, unit)) then
      local name = J.str(J.call(UnitName, unit))
      if name and not (raid and J.plain(J.call(rawget(_G, "UnitIsUnit"), unit, "player"))) then out[#out + 1] = name end
    end
  end
  return out
end

--- Say the summary to the group when the option is on, we are grouped, and somebody here has not heard it for
-- this dungeon (account memory). Returns true when a line went out, else false + why.
function J.SaySummary(d, names)
  if J.cfg().partySummary ~= true then return false, "off" end
  if not J.Compat.flags.chat and type(rawget(_G, "SendChatMessage")) ~= "function" then return false, "no chat" end
  if J.plain(J.call(rawget(_G, "IsInGroup"))) ~= true then return false, "not grouped" end
  names = names or J.PartyNames()
  local said = J.db().said
  local key = tostring(d.inst or d.key)
  said[key] = said[key] or {}
  local fresh = false
  if #names == 0 then
    -- names unreadable on this client: once per dungeon per session
    J.saidSession = J.saidSession or {}
    if J.saidSession[key] then return false, "already said this session" end
    J.saidSession[key] = true
    fresh = true
  else
    for _, n in ipairs(names) do if not said[key][n] then fresh = true end end
    if not fresh then return false, "everyone here has heard it" end
    local when = J.now()
    if when == "" then when = true end   -- no clock on this client: still a truthy mark
    for _, n in ipairs(names) do said[key][n] = when end
  end
  local raid = J.plain(J.call(rawget(_G, "IsInRaid"))) == true
  local ok = pcall(SendChatMessage, J.SummaryLine(d), raid and "RAID" or "PARTY")
  return ok and true or false, ok and "sent" or "SendChatMessage threw"
end
