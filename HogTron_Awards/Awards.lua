-- HogTron Awards: end-of-run awards for the whole HogTron UI suite (every class, not a HogHeals module).
-- Finish a dungeon, raid or battleground -> a golden VIEW AWARDS prompt -> five players on stage with their award.
-- End-of-run awards screen pattern from Podium (Dalorrian, All Rights Reserved): patterns only, no code taken.
--
-- Flow: entering an instance starts a run (counters reset) -> a run-end trigger fires (last boss, LFG reward, PvP
-- match over) or someone types /hh awards end -> Sync collects the group's counters for 3 s -> Resolve picks the
-- winners and the stage -> prompt. Which trigger events Forever really fires is UNPROVEN: every one is registered
-- under pcall and counted in HogHealsDB.global.diag.awards (/hh awards probe), and /hh awards end always works.
HogTronAwards = HogTronAwards or {}
local A = HogTronAwards
local HH = HogHeals

A.DEFAULTS = {
  enabled = true,
  contexts = { dungeon = true, raid = true, bg = true },
  solo = false,             -- awards when you ran it alone (group of 1)
  roasts = true,
  layout = "arc",           -- "arc" | "corners"  (Sean picks; both rendered in docs/mockups/awards/)
  disabled = {},            -- [awardId] = true
  promptSeconds = 60,
  stageSeconds = 45,
}

local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d, e, f2, g, h = pcall(f, ...)
  if ok then return a, b, c, d, e, f2, g, h end
end

local function fill(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      fill(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end

--- This profile's settings, defaults filled in.
function A.Cfg()
  local p = HH.db and HH.db.profile
  if not p then return fill({}, A.DEFAULTS) end
  p.awards = p.awards or {}
  return fill(p.awards, A.DEFAULTS)
end

function A.AwardEnabled(award)
  local c = A.Cfg()
  if c.disabled[award.id] then return false end
  if award.kind == "roast" and not c.roasts then return false end
  return true
end

-- ------------------------------------------------------------------------------------------------ run tracking
A.run = nil

function A.ContextOf(instanceType)
  if instanceType == "party" then return "dungeon" end
  if instanceType == "raid" then return "raid" end
  if instanceType == "pvp" or instanceType == "arena" then return "bg" end
  return nil
end

function A.StartRun(ctx, instanceName, instanceID)
  A.run = { ctx = ctx, instance = instanceName, instanceID = instanceID, killed = {}, startedAt = call(GetTime) or 0 }
  A.Metrics.ResetSelf()
  return A.run
end

function A.OnZone()
  local name, itype, _, _, _, _, _, instID = call(GetInstanceInfo)
  local ctx = A.ContextOf(itype)
  if not ctx then return end
  local r = A.run
  if r and not r.ended and r.instanceID == instID and r.ctx == ctx then return end     -- same run, e.g. after a corpse run
  A.StartRun(ctx, A.Metrics.str(name), instID)
end

-- ------------------------------------------------------------------------------------------------ probe
-- Every run-end candidate event, registered under pcall (Forever throws on events it does not know) and counted.
A.TRIGGERS = { "BOSS_KILL", "ENCOUNTER_START", "ENCOUNTER_END", "LFG_COMPLETION_REWARD", "CHALLENGE_MODE_COMPLETED",
  "PVP_MATCH_COMPLETE", "UPDATE_BATTLEFIELD_SCORE", "SCENARIO_COMPLETED" }

local function diag()
  local g = HH.db and HH.db.global
  if not g then return nil end
  g.diag = g.diag or {}
  g.diag.awards = g.diag.awards or { fired = {}, last = {} }
  return g.diag.awards
end

local function plain(v)
  if A.Metrics.isSecret(v) then return "SECRET" end
  if type(v) == "string" or type(v) == "number" or type(v) == "boolean" or v == nil then return tostring(v) end
  return type(v)
end

function A.Probe(event, ...)
  local d = diag()
  if not d then return end
  d.fired[event] = (d.fired[event] or 0) + 1
  local args = {}
  for i = 1, math.min(5, select("#", ...)) do args[i] = plain((select(i, ...))) end
  d.last[event] = (date and date("%Y-%m-%d %H:%M:%S") or "") .. " " .. table.concat(args, " | ")
end

-- ------------------------------------------------------------------------------------------------ end of run
local function groupSize() return math.max(1, A.Metrics.num(call(GetNumGroupMembers)) or 1) end

--- Why a run end would be skipped, or nil to go ahead.
function A.SkipReason(ctx)
  local c = A.Cfg()
  if not c.enabled then return "disabled" end
  if not c.contexts[ctx] then return "off for " .. tostring(ctx) end
  if groupSize() <= 1 and not c.solo then return "solo (turn on 'Awards when solo')" end
  return nil
end

--- A run ended. reason: "boss" | "lfg" | "challenge" | "pvp" | "manual" | "remote". remoteRunId: a groupmate's run id.
function A.EndRun(reason, remoteRunId, remoteCtx)
  local r = A.run
  if not r then
    local name, itype, _, _, _, _, _, instID = call(GetInstanceInfo)
    local ctx = remoteCtx or A.ContextOf(itype) or ((reason == "manual") and "dungeon" or nil)
    if not ctx then return false, "not in an instance" end
    r = A.StartRun(ctx, A.Metrics.str(name), instID)
  end
  if r.ended then return false, "already ended" end
  local skip = A.SkipReason(r.ctx)
  if skip then r.ended = true return false, skip end
  r.ended, r.reason = true, reason
  local me = A.Metrics.Short(call(UnitName, "player")) or "me"
  local runId = me .. "-" .. tostring(A.Metrics.num(call(GetServerTime)) or math.floor(call(GetTime) or 0))
  A.Sync.Begin(runId, r.ctx, A.Metrics.SelfSnapshot(), function(nominations, seed, ctx) A.Finish(nominations, seed, ctx, r) end)
  if remoteRunId and A.Sync.window then A.Sync.window.runIds[remoteRunId] = true end
  return true
end

function A.OnRemoteEnd(runId, ctx) return A.EndRun("remote", runId, ctx) end

--- Window closed: resolve, remember, prompt.
function A.Finish(nominations, seed, ctx, run)
  local data, names, roles = A.Metrics.Collect(nominations, ctx)
  local winners = A.Resolve.Winners(data, names, roles, ctx, A.AwardEnabled)
  local solo = #names <= 1
  local stage = A.Resolve.Stage(winners, seed, { slots = solo and 0 or 4, roasts = A.Cfg().roasts })
  A.last = { stage = stage, ctx = ctx, where = run and run.instance or "", seed = seed, names = names, at = call(GetTime) }
  local d = diag()
  if d then d.lastRun = { ctx = ctx, where = A.last.where, players = #names, winners = #winners, headline = stage.headline and stage.headline.award.id } end
  if stage.headline then A.UI.ShowPrompt(A.last.where, A.Cfg().promptSeconds) end
  return stage
end

-- ------------------------------------------------------------------------------------------------ preview
local FAKE = { "Hognificent", "Zugzug", "Brianna", "Anthony", "Scoop" }

--- A fake awards screen: you and four made-up players with a fixed honor/roast mix. Models use your character.
function A.PreviewStage(seed)
  local rng = A.Resolve.Rng(seed or "preview")
  local me = A.Metrics.Short(call(UnitName, "player")) or FAKE[1]
  local honors, roasts = {}, {}
  for _, a in ipairs(A.LIST) do
    if A.AwardEnabled(a) and a.id ~= "mvp" then if a.kind == "roast" then roasts[#roasts + 1] = a else honors[#honors + 1] = a end end
  end
  local function pick(pool) return table.remove(pool, rng(#pool)) end
  local names = { me, FAKE[2], FAKE[3], FAKE[4], FAKE[5] }
  local function w(award, i) return { award = award, name = names[i], unit = "player", value = 1, detail = "preview: " .. award.flavor } end
  local stage = { headline = w(A.BY_ID.mvp, 1), others = {}, also = {} }
  local order = { honors, roasts, honors, roasts }
  for i = 1, 4 do
    local pool = order[i]
    if #pool == 0 then pool = (pool == honors) and roasts or honors end
    if #pool > 0 then stage.others[i] = w(pick(pool), i + 1) end
  end
  return stage
end

function A.Preview()
  return A.UI.ShowStage(A.PreviewStage(tostring(call(GetTime) or 0)), { preview = true, where = "Preview - nothing here is real" })
end

-- ------------------------------------------------------------------------------------------------ events
local Module = {}
A.module = Module

function A.OnEvent(event, ...)
  if event ~= "UNIT_SPELLCAST_SUCCEEDED" and event ~= "PLAYER_TARGET_CHANGED" and event ~= "UI_ERROR_MESSAGE"
    and event ~= "PLAYER_STARTED_MOVING" and event ~= "PLAYER_STOPPED_MOVING" then
    A.Probe(event, ...)
  end
  local M = A.Metrics
  local a1, a2, a3, a4, a5 = ...
  if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then A.OnZone()
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then if a1 == "player" then M.OnOwnCast(a3) end
  elseif event == "UNIT_SPELLCAST_FAILED" then if a1 == "player" then M.Bump("castsFailed") end
  elseif event == "UNIT_SPELLCAST_INTERRUPTED" then if a1 == "player" then M.Bump("castsInterrupted") end
  elseif event == "PLAYER_DEAD" then M.OnDeath()
  elseif event == "PLAYER_ALIVE" then if not call(UnitIsDeadOrGhost, "player") then M.OnAlive(false) end
  elseif event == "PLAYER_UNGHOST" then M.OnAlive(true)
  elseif event == "CHAT_MSG_LOOT" then M.OnLoot(a1)
  elseif event == "PLAYER_MONEY" then M.OnMoney()
  elseif event == "PLAYER_XP_UPDATE" then M.OnXP()
  elseif event == "PLAYER_LEVEL_UP" then M.Bump("levelUps")
  elseif event == "LOOT_ITEM_ROLL_WON" then M.OnRollWon()
  elseif event == "UI_ERROR_MESSAGE" then M.OnUIError(a2)
  elseif event == "PLAYER_TARGET_CHANGED" then M.Bump("targetChanges")
  elseif event == "PLAYER_STARTED_MOVING" then if M.self then M.self.moving = true end
  elseif event == "PLAYER_STOPPED_MOVING" then if M.self then M.self.moving = false end
  elseif event == "LOSS_OF_CONTROL_ADDED" then M.Bump("ccTaken")
  elseif event == "READY_CHECK" then M.OnReadyCheck()
  elseif event == "READY_CHECK_CONFIRM" then if a1 == "player" then M.OnReadyConfirm() end
  elseif event == "QUEST_WATCH_UPDATE" or event == "QUEST_LOG_CRITERIA_UPDATE" then M.Bump("questProgress")
  elseif event == "PLAYER_REGEN_DISABLED" then A.OnCombat()
  elseif event == "ENCOUNTER_START" then M.OnEncounterStart()
  elseif event == "ENCOUNTER_END" then
    M.OnEncounterEnd(a5)
    if A.run and M.str(a2) then if M.num(a5) == 1 then A.run.killed[a2] = true end end
    if M.num(a5) == 1 and A.run and A.IsFinalKill(A.run.instance, M.str(a2), A.run.killed) then A.EndRun("boss") end
  elseif event == "BOSS_KILL" then
    if A.run and M.str(a2) then A.run.killed[a2] = true end
    if A.run and A.IsFinalKill(A.run.instance, M.str(a2), A.run.killed) then A.EndRun("boss") end
  elseif event == "LFG_COMPLETION_REWARD" then A.EndRun("lfg")
  elseif event == "CHALLENGE_MODE_COMPLETED" then A.EndRun("challenge")
  elseif event == "PVP_MATCH_COMPLETE" then A.EndRun("pvp")
  elseif event == "UPDATE_BATTLEFIELD_SCORE" then
    local winner = call(GetBattlefieldWinner)
    if winner ~= nil and not M.isSecret(winner) and A.run and A.run.ctx == "bg" then A.EndRun("pvp") end
  end
end

--- Combat started: tell Metrics who the tank is (for the "started it before the tank" roast).
function A.OnCombat()
  local M = A.Metrics
  if not M.self then return end
  local tankUnit, myRole
  local raid = call(IsInRaid)
  for i = 1, raid and 40 or 4 do
    local u = (raid and "raid" or "party") .. i
    if call(UnitExists, u) and M.str(call(UnitGroupRolesAssigned, u)) == "TANK" then tankUnit = u break end
  end
  myRole = M.str(call(UnitGroupRolesAssigned, "player")) == "TANK" and "tank" or "other"
  M.OnCombatStart(myRole, tankUnit)
end

local EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
  "UNIT_SPELLCAST_INTERRUPTED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "CHAT_MSG_LOOT", "PLAYER_MONEY",
  "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "LOOT_ITEM_ROLL_WON", "UI_ERROR_MESSAGE", "PLAYER_TARGET_CHANGED",
  "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "LOSS_OF_CONTROL_ADDED", "READY_CHECK", "READY_CHECK_CONFIRM",
  "QUEST_WATCH_UPDATE", "QUEST_LOG_CRITERIA_UPDATE", "PLAYER_REGEN_DISABLED" }

--- Hooks on the player's own actions (post-hooks; nothing is replaced, nothing protected is called).
local function hookAll()
  local M = A.Metrics
  local function hook(name, fn) if type(_G[name]) == "function" then pcall(hooksecurefunc, name, fn) end end
  hook("JumpOrAscendStart", function() M.Bump("jumps") end)
  hook("DoEmote", function(token) M.OnEmote(token) end)
  hook("RollOnLoot", function(_, rollType) M.OnRoll(rollType) end)
  hook("SetRaidTarget", function() M.Bump("marksSet") end)
  local function chat(_, chatType)
    if chatType == "PARTY" or chatType == "RAID" or chatType == "INSTANCE_CHAT" or chatType == "SAY" or chatType == "YELL" then M.Bump("chatSent") end
  end
  hook("SendChatMessage", chat)
  if C_ChatInfo and type(C_ChatInfo.SendChatMessage) == "function" then pcall(hooksecurefunc, C_ChatInfo, "SendChatMessage", chat) end
end

function Module:OnEnable()
  A.Sync.Register()
  local f = CreateFrame("Frame")
  local d = diag()
  local failed = {}
  for _, e in ipairs(EVENTS) do pcall(f.RegisterEvent, f, e) end
  for _, e in ipairs(A.TRIGGERS) do
    local ok = pcall(f.RegisterEvent, f, e)
    if not ok then failed[#failed + 1] = e end
  end
  if d then d.registered, d.failed = table.concat(A.TRIGGERS, ","), table.concat(failed, ",") end
  f:SetScript("OnEvent", function(_, event, ...) A.OnEvent(event, ...) end)
  A.events = f
  hookAll()
  if C_Timer and C_Timer.NewTicker then A.ticker = C_Timer.NewTicker(1, function() A.Metrics.Tick(1) end) end
  A.OnZone()
end

-- ------------------------------------------------------------------------------------------------ options
local function toggleFor(a, order)
  return {
    type = "toggle", order = order, name = a.name, width = "full",
    desc = a.flavor .. (a.note and ("\n\n" .. a.note) or ""),
    get = function() return not A.Cfg().disabled[a.id] end,
    set = function(_, v) A.Cfg().disabled[a.id] = (not v) or nil end,
  }
end

function Module:GetOptions()
  local c = A.Cfg
  local honors, roasts = {}, {}
  local nh, nr = 0, 0
  for _, a in ipairs(A.LIST) do
    if a.kind == "roast" then nr = nr + 1 roasts[a.id] = toggleFor(a, nr) else nh = nh + 1 honors[a.id] = toggleFor(a, nh) end
  end
  roasts.mute = { type = "toggle", order = 0, width = "full", name = "Show roasts at all",
    desc = "Off = honors only, every roast muted.", get = function() return c().roasts end, set = function(_, v) c().roasts = v and true or false end }
  return {
    type = "group", name = "Awards", childGroups = "tab",
    args = {
      general = { type = "group", name = "General", order = 1, args = {
        intro = { type = "description", order = 0, name =
          "End-of-run awards: finish a dungeon, raid or battleground and a gold VIEW AWARDS button appears. Five players take "
          .. "the stage with an award each: one headline in the middle, four more around it - honors and roasts. Everyone "
          .. "in the group running HogTron Awards sees the same screen." },
        enabled = { type = "toggle", order = 1, name = "Enable HogTron Awards", width = "full",
          get = function() return c().enabled end, set = function(_, v) c().enabled = v and true or false end },
        ctxHead = { type = "header", order = 10, name = "When" },
        dungeon = { type = "toggle", order = 11, name = "Dungeons", get = function() return c().contexts.dungeon end, set = function(_, v) c().contexts.dungeon = v and true or false end },
        raid = { type = "toggle", order = 12, name = "Raids", get = function() return c().contexts.raid end, set = function(_, v) c().contexts.raid = v and true or false end },
        bg = { type = "toggle", order = 13, name = "Battlegrounds", get = function() return c().contexts.bg end, set = function(_, v) c().contexts.bg = v and true or false end },
        solo = { type = "toggle", order = 14, name = "Awards when solo", desc = "Show your own awards when you ran it alone.",
          get = function() return c().solo end, set = function(_, v) c().solo = v and true or false end },
        lookHead = { type = "header", order = 20, name = "Stage" },
        layout = { type = "select", order = 21, name = "Layout", values = A.UI.LAYOUT_LABELS,
          get = function() return c().layout end, set = function(_, v) c().layout = v end },
        roastsOn = { type = "toggle", order = 22, name = "Show roasts", get = function() return c().roasts end, set = function(_, v) c().roasts = v and true or false end },
        preview = { type = "execute", order = 23, name = "Preview", desc = "A fake awards screen with your character.", func = function() A.Preview() end },
        last = { type = "execute", order = 24, name = "Show the last screen", func = function() A.UI.ShowStage(A.last and A.last.stage, A.last) end },
        endRun = { type = "execute", order = 25, name = "End run now", desc = "For a run with no last boss, or a trigger that did not fire. Tells the group too.",
          func = function() local ok, why = A.EndRun("manual") if not ok then HH:Print("HogTron Awards: " .. tostring(why)) end end },
      } },
      honors = { type = "group", name = "Honors", order = 2, args = honors },
      roasts = { type = "group", name = "Roasts", order = 3, args = roasts },
    },
  }
end

HH:RegisterModule("Awards", Module)

-- ------------------------------------------------------------------------------------------------ slash
function A.Slash(rest)
  rest = ((rest or ""):match("^%s*(.-)%s*$") or ""):lower()
  if rest == "preview" or rest == "test" then A.Preview() return end
  if rest == "end" then local ok, why = A.EndRun("manual") if not ok then HH:Print("HogTron Awards: " .. tostring(why)) end return end
  if rest == "last" then A.UI.ShowStage(A.last and A.last.stage, A.last) return end
  if rest == "probe" then
    local d = diag() or {}
    HH:Print("HogTron Awards probe: registered " .. tostring(d.registered) .. "; refused: " .. ((d.failed or "") ~= "" and d.failed or "none"))
    for _, e in ipairs(A.TRIGGERS) do
      HH:Print(("  %s fired %d%s"):format(e, (d.fired or {})[e] or 0, (d.last or {})[e] and ("  last: " .. d.last[e]) or ""))
    end
    return
  end
  local P = HH.Panel
  if P and P.Open then P.Open() P.Select("Awards") else HH:OpenOptions() end
end
HH:RegisterSlash("awards", A.Slash, "HogTron Awards: settings (/hh awards preview | end | last | probe)")

-- /htr = the HogTron UI command: "/htr awards preview" == "/hh awards preview". Only claimed if nobody else has it.
if not SlashCmdList.HOGTRON and not rawget(_G, "SLASH_HOGTRON1") then
  SLASH_HOGTRON1 = "/htr"
  SlashCmdList.HOGTRON = function(msg) HH:SlashCommand(msg) end
end
