-- HogTron Awards: what each metric is and how it is measured on WoW: Forever.
--
-- Three sources, chosen by what Forever actually lets an addon see (measured in diag 2026-10-15, see the research doc):
--   meter  Blizzard's own damage meter, C_DamageMeter. Covers the whole group. Amounts are SECRET (no compare, no
--          send), but the client returns each list already ranked, so a player's value here is a RANK SCORE:
--          n - position + 1 for the n players listed, 0 for a group member who is not listed (did none of it).
--          Every client reads the same meter, so these need no syncing.
--   self   plain counters each client keeps about its OWN player (jumps, loot, drinks, emotes, rezzes ...). Shared
--          with the group over addon messages (Sync.lua) - the only way another player's counter is known.
--   score  the battleground scoreboard (killing blows, honorable kills, deaths, objectives). Same for everyone.
-- Plus "derived" metrics computed from the above (MVP, survivors, clean feet).
HogTronAwards = HogTronAwards or {}
local A = HogTronAwards
local HH = HogHeals

local M = {}
A.Metrics = M

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function str(v) if type(v) == "string" and not isSecret(v) and v ~= "" then return v end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d, e = pcall(f, ...)
  if ok then return a, b, c, d, e end
end
M.num, M.str, M.isSecret = num, str, isSecret

--- "Name-Realm" -> "Name"
function M.Short(name)
  name = str(name)
  if not name then return nil end
  return (name:match("^([^%-]+)")) or name
end

-- ------------------------------------------------------------------------------------------------ definitions
M.DEFS = {
  -- meter (rank scores)
  damage = { src = "meter", mode = "DamageDone", seg = "Overall", label = "damage done" },
  dps = { src = "meter", mode = "Dps", seg = "Overall", label = "damage per second" },
  healing = { src = "meter", mode = "HealingDone", seg = "Overall", label = "healing done" },
  hps = { src = "meter", mode = "Hps", seg = "Overall", label = "healing per second" },
  absorbs = { src = "meter", mode = "Absorbs", seg = "Overall", label = "damage absorbed" },
  interrupts = { src = "meter", mode = "Interrupts", seg = "Overall", label = "interrupts" },
  dispels = { src = "meter", mode = "Dispels", seg = "Overall", label = "dispels" },
  taken = { src = "meter", mode = "DamageTaken", seg = "Overall", label = "damage taken" },
  avoidable = { src = "meter", mode = "AvoidableDamageTaken", seg = "Overall", label = "avoidable damage taken" },
  deaths = { src = "meter", mode = "Deaths", seg = "Overall", label = "deaths", fallback = "selfDeaths" },
  bossDamage = { src = "meter", mode = "DamageDone", seg = "Current", label = "damage in the final fight" },
  bossHealing = { src = "meter", mode = "HealingDone", seg = "Current", label = "healing in the final fight" },
  -- derived
  mvp = { src = "derived", label = "rank points (damage, healing, absorbs, interrupts, dispels, minus deaths)" },
  survivorTaken = { src = "derived", label = "damage taken without dying" },
  cleanFeet = { src = "derived", label = "best contribution with no avoidable damage" },
  deathless = { src = "derived", label = "best contribution without dying" },
  greaseFire = { src = "derived", label = "avoidable damage taken and died" },
  bgSurvivor = { src = "derived", label = "fewest deaths among fighters" },
  -- battleground scoreboard
  killingBlows = { src = "score", label = "killing blows" },
  honorableKills = { src = "score", label = "honorable kills" },
  objectives = { src = "score", label = "objectives" },
  bgDeaths = { src = "score", label = "battleground deaths" },
  -- self (own client counts, shared via Sync)
  selfDeaths = { src = "self", label = "deaths" },
  firstDeath = { src = "self", label = "seconds into the run at first death", unit = "s" },
  timeDead = { src = "self", label = "seconds spent dead", unit = "s" },
  ghostRuns = { src = "self", label = "corpse runs" },
  afkTime = { src = "self", label = "seconds AFK", unit = "s" },
  jumps = { src = "self", label = "jumps" },
  movingTime = { src = "self", label = "seconds on the move", unit = "s" },
  swimTime = { src = "self", label = "seconds swimming", unit = "s" },
  lootItems = { src = "self", label = "items looted" },
  lootJunk = { src = "self", label = "junk items looted" },
  lootRare = { src = "self", label = "rare-or-better items looted" },
  lootGold = { src = "self", label = "copper picked up", unit = "c" },
  goldSpent = { src = "self", label = "copper spent", unit = "c" },
  needRolls = { src = "self", label = "Need rolls" },
  rollsLost = { src = "self", label = "loot rolls lost" },
  foodDrink = { src = "self", label = "food and drink breaks" },
  drinks = { src = "self", label = "drink breaks" },
  foodKinds = { src = "self", label = "different foods eaten" },
  rezCombat = { src = "self", label = "resurrections cast in combat" },
  rezOOC = { src = "self", label = "resurrections cast out of combat" },
  potions = { src = "self", label = "potions and healthstones used" },
  bandages = { src = "self", label = "bandages applied" },
  taunts = { src = "self", label = "taunts" },
  ccCast = { src = "self", label = "crowd-control spells cast" },
  snaresCast = { src = "self", label = "slows and roots cast" },
  chargeCast = { src = "self", label = "charges, blinks and sprints" },
  disenchants = { src = "self", label = "items disenchanted" },
  uniqueSpells = { src = "self", label = "different spells cast" },
  castsTotal = { src = "self", label = "spells cast" },
  castsFailed = { src = "self", label = "failed casts" },
  castsInterrupted = { src = "self", label = "casts cut short" },
  emotes = { src = "self", label = "emotes" },
  emotesPositive = { src = "self", label = "friendly emotes" },
  emotesRomantic = { src = "self", label = "romantic emotes" },
  chatSent = { src = "self", label = "chat messages sent" },
  uiErrors = { src = "self", label = "error messages" },
  rangeErrors = { src = "self", label = "out-of-range errors" },
  targetChanges = { src = "self", label = "target changes" },
  ccTaken = { src = "self", label = "loss-of-control effects taken" },
  levelUps = { src = "self", label = "levels gained" },
  xpGained = { src = "self", label = "experience gained" },
  readyTime = { src = "self", label = "average seconds to answer a ready check", unit = "s" },
  marksSet = { src = "self", label = "raid marks set" },
  questProgress = { src = "self", label = "quest objectives completed" },
  latency = { src = "self", label = "world latency (ms)", unit = "ms" },
  level = { src = "self", label = "character level" },
  bagFree = { src = "self", label = "free bag slots at the end" },
  wipeDeaths = { src = "self", label = "deaths in failed boss fights" },
  earlyBossDeaths = { src = "self", label = "deaths in the first minute of a boss fight" },
  tankPulls = { src = "self", label = "fights started before the tank" },
}

-- Spell-name groups for the self counters (enUS names; a non-English client counts only casts by spell id it can
-- name in English - see the research doc's open questions).
local function set(list) local t = {} for _, v in ipairs(list) do t[v] = true end return t end
M.SPELLS = {
  rez = set({ "Resurrection", "Redemption", "Ancestral Spirit", "Rebirth", "Revive" }),
  taunt = set({ "Taunt", "Growl", "Mocking Blow", "Challenging Shout", "Challenging Roar", "Righteous Defense", "Hand of Reckoning" }),
  cc = set({ "Polymorph", "Sap", "Shackle Undead", "Hibernate", "Banish", "Fear", "Howl of Terror", "Freezing Trap", "Scare Beast",
    "Seduction", "Repentance", "Hex", "Gouge", "Blind", "Psychic Scream", "Intimidating Shout", "Wyvern Sting", "Scatter Shot",
    "Turn Undead", "Hammer of Justice", "Kidney Shot", "Cheap Shot", "Bash", "War Stomp", "Concussion Blow", "Mind Control" }),
  snare = set({ "Hamstring", "Frost Nova", "Wing Clip", "Concussive Shot", "Earthbind Totem", "Frost Shock", "Cone of Cold",
    "Piercing Howl", "Entangling Roots", "Crippling Poison", "Mind Flay" }),
  charge = set({ "Charge", "Intercept", "Feral Charge", "Blink", "Sprint", "Dash", "Intervene", "Shadowstep" }),
  bandage = set({ "First Aid" }),
  disenchant = set({ "Disenchant" }),
  food = set({ "Food", "Refreshment", "Food & Drink" }),
  drink = set({ "Drink", "Refreshment", "Food & Drink" }),
}
M.EMOTES_POSITIVE = set({ "THANK", "CHEER", "APPLAUD", "BOW", "HUG", "WAVE", "CONGRATULATE", "GRATZ", "SALUTE", "PRAISE" })
M.EMOTES_ROMANTIC = set({ "KISS", "LOVE", "FLIRT", "SEXY", "CUDDLE", "BLUSH" })

function M.IsPotion(name)
  return name ~= nil and (name:find("Potion", 1, true) or name:find("Healthstone", 1, true) or name == "Restore Mana") and true or false
end

-- ------------------------------------------------------------------------------------------------ meter (rank scores)
local function enumValue(enumName, key, fallback)
  local e = Enum and Enum[enumName]
  if type(e) == "table" and e[key] ~= nil then return e[key] end
  return fallback
end

--- Ranked player names for one meter list, best first. nil when the client has no meter / no such list.
function M.MeterList(mode, seg)
  local api = C_DamageMeter
  if type(api) ~= "table" or type(api.GetCombatSessionFromType) ~= "function" then return nil end
  local meterType = enumValue("DamageMeterType", mode, nil)
  if meterType == nil then return nil end
  local sessionType = enumValue("DamageMeterSessionType", seg, nil)
  if sessionType == nil then return nil end
  local session = call(api.GetCombatSessionFromType, sessionType, meterType)
  local list = type(session) == "table" and session.combatSources
  if type(list) ~= "table" or isSecret(list) then return nil end
  local out = {}
  for _, src in ipairs(list) do
    local name = type(src) == "table" and M.Short(src.name)
    if name then out[#out + 1] = name end
  end
  return out
end

--- Group member names (short), self included.
function M.Roster()
  local out, seen = {}, {}
  local function add(unit)
    local n = M.Short(call(UnitName, unit))
    if n and not seen[n] then seen[n] = true out[#out + 1] = n end
  end
  add("player")
  local raid = call(IsInRaid)
  local count = num(call(GetNumGroupMembers)) or 0
  if raid then for i = 1, count do add("raid" .. i) end
  else for i = 1, math.max(0, count - 1) do add("party" .. i) end end
  return out
end

--- Unit token for a short name in the current group, or nil.
function M.UnitFor(name)
  local function is(unit) return M.Short(call(UnitName, unit)) == name end
  if is("player") then return "player" end
  local count = num(call(GetNumGroupMembers)) or 0
  if call(IsInRaid) then for i = 1, count do if is("raid" .. i) then return "raid" .. i end end end
  for i = 1, 4 do if is("party" .. i) then return "party" .. i end end
  return nil
end

--- Read every meter metric into data[name][metric] = rank score. Returns the set of metric keys that had a list.
function M.ReadMeter(data, roster)
  local got = {}
  for key, def in pairs(M.DEFS) do
    if def.src == "meter" then
      local list = M.MeterList(def.mode, def.seg)
      if list then
        got[key] = true
        local n = #list
        for _, name in ipairs(roster or {}) do data[name] = data[name] or {} data[name][key] = 0 end
        for i, name in ipairs(list) do
          data[name] = data[name] or {}
          data[name][key] = n - i + 1
        end
      end
    end
  end
  return got
end

-- ------------------------------------------------------------------------------------------------ battleground score
--- Scoreboard into data[name].{killingBlows,honorableKills,bgDeaths,objectives}. Modern C_PvP first, legacy second.
function M.ReadScore(data)
  local rows = 0
  local nScores = num(call(GetNumBattlefieldScores)) or 0
  for i = 1, nScores do
    local info = C_PvP and type(C_PvP.GetScoreInfo) == "function" and call(C_PvP.GetScoreInfo, i)
    local name, kb, hk, deaths, obj
    if type(info) == "table" then
      name, kb, hk, deaths = info.name, info.killingBlows, info.honorableKills, info.deaths
      local total = 0
      for _, s in ipairs(type(info.stats) == "table" and info.stats or {}) do total = total + (num(s.pvpStatValue) or 0) end
      obj = total
    else
      local n2, k2, h2, d2 = call(GetBattlefieldScore, i)
      name, kb, hk, deaths = n2, k2, h2, d2
      local total = 0
      for s = 1, (num(call(GetNumBattlefieldStats)) or 0) do total = total + (num(call(GetBattlefieldStatData, i, s)) or 0) end
      obj = total
    end
    name = M.Short(name)
    if name then
      rows = rows + 1
      local d = data[name] or {}
      data[name] = d
      d.killingBlows, d.honorableKills, d.bgDeaths, d.objectives = num(kb), num(hk), num(deaths), num(obj)
    end
  end
  return rows
end

-- ------------------------------------------------------------------------------------------------ roles
--- Role per name: the group tool's assigned role when there is one, else inferred from the meter ranks
-- (healer = top of the healing list where healing outranks damage; tank = top damage taken among the rest).
function M.Roles(data, names)
  local roles, groupSize = {}, #names
  local slots = math.max(1, math.floor(groupSize / 5 + 0.5))
  for _, n in ipairs(names) do
    local unit = M.UnitFor(n)
    local r = unit and str(call(UnitGroupRolesAssigned, unit))
    if r == "TANK" then roles[n] = "tank" elseif r == "HEALER" then roles[n] = "healer" elseif r == "DAMAGER" then roles[n] = "dps" end
  end
  local function ranked(key, filter)
    local t = {}
    for _, n in ipairs(names) do
      local v = data[n] and data[n][key]
      if v and v > 0 and not roles[n] and (not filter or filter(n)) then t[#t + 1] = n end
    end
    table.sort(t, function(a, b) return data[a][key] > data[b][key] or (data[a][key] == data[b][key] and a < b) end)
    return t
  end
  -- infer only the roles nobody holds by assignment (an assigned tank means the meter must not crown a second one)
  local assigned = {}
  for _, r in pairs(roles) do assigned[r] = true end
  if groupSize >= 2 and not assigned.healer then
    local h = ranked("healing", function(n) return (data[n].healing or 0) > (data[n].damage or 0) end)
    for i = 1, math.min(slots, #h) do roles[h[i]] = "healer" end
  end
  if groupSize >= 3 and not assigned.tank then
    local t = ranked("taken")
    for i = 1, math.min(slots, #t) do roles[t[i]] = "tank" end
  end
  for _, n in ipairs(names) do roles[n] = roles[n] or "dps" end
  return roles
end

function M.RoleMatches(want, role)
  if not want then return true end
  if want == "nontank" then return role ~= "tank" end
  return want == role
end

-- ------------------------------------------------------------------------------------------------ derived
function M.Derive(data, names)
  for _, n in ipairs(names) do
    local d = data[n] or {}
    data[n] = d
    if d.deaths == nil and d.selfDeaths ~= nil then d.deaths = d.selfDeaths end
    local contrib = math.max(d.damage or 0, d.healing or 0)
    local died = (d.deaths or 0) > 0
    local any = d.damage ~= nil or d.healing ~= nil
    if any then
      d.mvp = (d.damage or 0) + (d.healing or 0) + (d.absorbs or 0) + (d.interrupts or 0) + (d.dispels or 0) - (d.deaths or 0)
      if not died then d.deathless = contrib end
      if not died and d.taken then d.survivorTaken = d.taken end
      if d.avoidable == 0 and contrib > 0 then d.cleanFeet = contrib end
      if died and (d.avoidable or 0) > 0 then d.greaseFire = (d.avoidable or 0) + (d.deaths or 0) end
    end
    if (d.honorableKills or 0) > 0 and d.bgDeaths then d.bgSurvivor = 1000 - d.bgDeaths end
  end
end

-- ------------------------------------------------------------------------------------------------ self counters
M.self = nil

function M.ResetSelf(now)
  M.self = { startedAt = now or (num(call(GetTime)) or 0), spells = {}, foods = {}, readyTimes = {}, counts = {} }
  local c = M.self.counts
  for key, def in pairs(M.DEFS) do if def.src == "self" then c[key] = 0 end end
  c.firstDeath = nil
  c.readyTime = nil
  M.self.startMoney = num(call(GetMoney))
  M.self.startXP = num(call(UnitXP, "player"))
  M.self.startXPMax = num(call(UnitXPMax, "player"))
  return M.self
end

local function bump(key, by)
  local s = M.self
  if not s then return end
  s.counts[key] = (s.counts[key] or 0) + (by or 1)
end
M.Bump = bump

local function now() return num(call(GetTime)) or 0 end

--- A spell cast by the player finished (UNIT_SPELLCAST_SUCCEEDED, unit "player").
function M.OnOwnCast(spellID)
  local s = M.self
  if not s then return end
  local name
  if C_Spell and type(C_Spell.GetSpellName) == "function" then name = str(call(C_Spell.GetSpellName, spellID)) end
  if not name and C_Spell and type(C_Spell.GetSpellInfo) == "function" then
    local info = call(C_Spell.GetSpellInfo, spellID)
    name = type(info) == "table" and str(info.name) or nil
  end
  if not name and type(GetSpellInfo) == "function" then name = str(call(GetSpellInfo, spellID)) end
  bump("castsTotal")
  local id = num(spellID)
  if id and not s.spells[id] then s.spells[id] = true bump("uniqueSpells") end
  if not name then return end
  local S = M.SPELLS
  if S.rez[name] then bump((call(InCombatLockdown) or call(UnitAffectingCombat, "player")) and "rezCombat" or "rezOOC") end
  if S.taunt[name] then bump("taunts") end
  if S.cc[name] then bump("ccCast") end
  if S.snare[name] then bump("snaresCast") end
  if S.charge[name] then bump("chargeCast") end
  if S.bandage[name] then bump("bandages") end
  if S.disenchant[name] then bump("disenchants") end
  if M.IsPotion(name) then bump("potions") end
  if S.food[name] or S.drink[name] then
    bump("foodDrink")
    if S.food[name] then M.OnFood(spellID) end
    if S.drink[name] then bump("drinks") end
  end
end

--- A food buff/cast with its own spell id counts as a different food (Charcuterie Board).
function M.OnFood(spellID)
  local s = M.self
  local id = num(spellID)
  if not s or not id or s.foods[id] then return end
  s.foods[id] = true
  bump("foodKinds")
end

function M.OnDeath()
  local s = M.self
  if not s then return end
  bump("selfDeaths")
  local t = now()
  if s.counts.firstDeath == nil then s.counts.firstDeath = math.floor(t - s.startedAt) end
  s.deadSince = t
  if s.encounter then
    s.encounter.deaths = (s.encounter.deaths or 0) + 1
    if t - s.encounter.startedAt <= 60 then bump("earlyBossDeaths") end
  end
end

function M.OnAlive(fromGhost)
  local s = M.self
  if not s then return end
  if s.deadSince then bump("timeDead", math.floor(now() - s.deadSince)) s.deadSince = nil end
  if fromGhost then bump("ghostRuns") end
end

function M.OnEncounterStart() if M.self then M.self.encounter = { startedAt = now(), deaths = 0 } end end
function M.OnEncounterEnd(success)
  local s = M.self
  if not s then return end
  if s.encounter and num(success) == 0 then bump("wipeDeaths", s.encounter.deaths or 0) end
  s.encounter = nil
end

--- Loot line for the player (CHAT_MSG_LOOT). quality from the item id when the client can tell.
function M.OnLoot(msg)
  msg = str(msg)
  if not msg then return end
  local selfPat = LOOT_ITEM_SELF and LOOT_ITEM_SELF:gsub("%%s.*", "") or "You receive loot:"
  local pushed = LOOT_ITEM_PUSHED_SELF and LOOT_ITEM_PUSHED_SELF:gsub("%%s.*", "") or "You receive item:"
  if msg:sub(1, #selfPat) ~= selfPat and msg:sub(1, #pushed) ~= pushed then return end
  bump("lootItems")
  local itemID = tonumber(msg:match("|Hitem:(%d+)"))
  local q = itemID and C_Item and type(C_Item.GetItemQualityByID) == "function" and num(call(C_Item.GetItemQualityByID, itemID))
  q = q or tonumber(msg:match("|cnIQ(%d)")) or nil
  if q == 0 then bump("lootJunk") elseif q and q >= 3 then bump("lootRare") end
end

function M.OnMoney()
  local s = M.self
  local m = num(call(GetMoney))
  if not s or not m then return end
  if s.lastMoney == nil then s.lastMoney = s.startMoney or m end
  local d = m - s.lastMoney
  if d > 0 then bump("lootGold", d) elseif d < 0 then bump("goldSpent", -d) end
  s.lastMoney = m
end

function M.OnXP()
  local s = M.self
  local xp, max = num(call(UnitXP, "player")), num(call(UnitXPMax, "player"))
  if not s or not xp then return end
  local last, lastMax = s.lastXP or s.startXP or xp, s.lastXPMax or s.startXPMax or max
  local d = xp - last
  if d < 0 and lastMax then d = (lastMax - last) + xp end       -- levelled up: the bar wrapped
  if d > 0 then bump("xpGained", d) end
  s.lastXP, s.lastXPMax = xp, max
end

function M.OnRoll(rollType)
  local s = M.self
  if not s then return end
  s.rolls = (s.rolls or 0) + 1
  if num(rollType) == 1 then bump("needRolls") end
end
function M.OnRollWon() if M.self then M.self.rollsWon = (M.self.rollsWon or 0) + 1 end end

function M.OnEmote(token)
  token = str(token)
  if not token then return end
  token = token:upper()
  bump("emotes")
  if M.EMOTES_POSITIVE[token] then bump("emotesPositive") end
  if M.EMOTES_ROMANTIC[token] then bump("emotesRomantic") end
end

function M.OnUIError(message)
  bump("uiErrors")
  message = str(message)
  if message and ((ERR_OUT_OF_RANGE and message == ERR_OUT_OF_RANGE) or (SPELL_FAILED_OUT_OF_RANGE and message == SPELL_FAILED_OUT_OF_RANGE)
      or message:lower():find("out of range", 1, true)) then
    bump("rangeErrors")
  end
end

function M.OnReadyCheck() if M.self then M.self.readyAsked = now() end end
function M.OnReadyConfirm()
  local s = M.self
  if not s or not s.readyAsked then return end
  s.readyTimes[#s.readyTimes + 1] = now() - s.readyAsked
  s.readyAsked = nil
end

--- Combat began for the player: a non-tank who starts while the group's tank is still out of combat "pulled".
function M.OnCombatStart(myRole, tankUnit)
  if not M.self or myRole == "tank" or not tankUnit then return end
  local inCombat = call(UnitAffectingCombat, tankUnit)
  if isSecret(inCombat) then return end
  if not inCombat then bump("tankPulls") end
end

--- Ticker (1 s): AFK, moving, swimming.
function M.Tick(dt)
  local s = M.self
  if not s then return end
  dt = dt or 1
  if call(UnitIsAFK, "player") then bump("afkTime", dt) end
  if s.moving then bump("movingTime", dt) end
  if call(IsSwimming) then bump("swimTime", dt) end
end

--- Plain-number snapshot of the player's own counters at run end.
function M.SelfSnapshot()
  local s = M.self
  if not s then return {} end
  local c = {}
  for k, v in pairs(s.counts) do c[k] = v end
  if s.deadSince then c.timeDead = (c.timeDead or 0) + math.floor(now() - s.deadSince) end
  c.rollsLost = math.max(0, (s.rolls or 0) - (s.rollsWon or 0))
  if #s.readyTimes > 0 then
    local sum = 0
    for _, t in ipairs(s.readyTimes) do sum = sum + t end
    c.readyTime = math.floor(sum / #s.readyTimes * 10 + 0.5) / 10
  end
  local _, _, _, world = call(GetNetStats)
  c.latency = num(world)
  c.level = num(call(UnitLevel, "player"))
  local free, api = 0, C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
  local okBags = false
  for bag = 0, 4 do
    local f = num(call(api, bag))
    if f then free = free + f okBags = true end
  end
  c.bagFree = okBags and free or nil
  if (c.selfDeaths or 0) == 0 then c.firstDeath = nil end
  if #s.readyTimes == 0 then c.readyTime = nil end
  return c
end

--- Everything known about everyone, ready for Resolve: data[name][metric], plus the roster and roles.
-- nominations = { [name] = { metric = value } } from Sync (own snapshot included).
function M.Collect(nominations, ctx)
  local roster = M.Roster()
  local data, seen = {}, {}
  for _, n in ipairs(roster) do seen[n] = true end
  M.ReadMeter(data, roster)
  if ctx == "bg" then M.ReadScore(data) end
  for name, vals in pairs(nominations or {}) do
    data[name] = data[name] or {}
    for k, v in pairs(vals) do
      if M.DEFS[k] and M.DEFS[k].src == "self" and num(v) then data[name][k] = v end
    end
    if not seen[name] then seen[name] = true roster[#roster + 1] = name end
  end
  local names = {}
  for name in pairs(data) do if seen[name] then names[#names + 1] = name end end
  table.sort(names)
  M.Derive(data, names)
  return data, names, M.Roles(data, names)
end
