-- Experience bar: one flat HogTron UI row in the HUD strip, under the mana bar. Sean 2026-10-08, from the ForeverXP
-- Bar clip (@domin0gam3s, "5 more add-ons you need in WoW Forever"): "XP per hour, session playtime, and how much your
-- quest will contribute to your next level". The maths for pace and time-to-level already live in
-- HogHeals/Core/Session.lua; this row only draws them and adds the two overlays:
--   rested  - cyan at low alpha from the fill head to xp + rested bonus (what the bar will fill at double speed)
--   quests  - green from the fill head to xp + the reward XP of the quests in your log (questMode "complete" = the ones
--             ready to turn in, "all" = every quest you carry)
-- Left: level, xp / max, percent. Right: +rested, +quests, xp/h and "lvl in" from Session. Hidden at the level cap
-- (hideAtMax) and when the client says experience is turned off. Secret-safe: an opaque UnitXP shows "-" and an empty
-- bar, nothing is compared (Session does the same). Every API is looked up by name; a client without it gives 0 / nil,
-- never an error. Reward XP ladder, recorded in XPBar.path.reward for /hh xpdiag:
--   1. GetQuestLogRewardXP(questID)                  modern clients (a questID argument is honoured)
--   2. SelectQuestLogEntry(i) + GetQuestLogRewardXP() legacy clients - the player's selection is put back after
--   3. none                                           0 xp, overlay off
HogHealsHUD = HogHealsHUD or {}
local HHD = HogHealsHUD
local HH = HogHeals

local XP = { path = { reward = "none", log = "none" }, seen = {}, REFRESH = 10, elapsed = 0 }
HHD.XPBar = XP

local CYAN, GREEN = { 0.13, 0.83, 0.88 }, { 0.25, 0.80, 0.35 }

local function cfg() return HH.db.profile.hud.xp or {} end
local function hud() return HH.db.profile.hud end
local function bar() return HHD.HUD and HHD.HUD.rows and HHD.HUD.rows.xp end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function g(name) local f = rawget(_G, name) if type(f) == "function" then return f end end
local function fn(tbl, name) if type(tbl) == "table" and type(tbl[name]) == "function" then return tbl[name] end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
end
local function count(k) XP.seen[k] = (XP.seen[k] or 0) + 1 end
local function clamp(x) if x < 0 then return 0 elseif x > 1 then return 1 end return x end

-- ------------------------------------------------------------------------------------------------ pure
--- "31,700". Integers only; anything else comes back as "-".
function XP.Commas(n)
  if type(n) ~= "number" then return "-" end
  local s = ("%d"):format(math.floor(n + 0.5))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

--- Fractions of the bar. xp / max numbers, rested / quest numbers or nil. nil when there is no bar to draw.
-- fill = xp, restedTo / questTo = where each overlay ends (both start at the fill head), percents for the texts.
function XP.Compute(xp, max, rested, quest)
  if type(xp) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
  rested, quest = rested or 0, quest or 0
  local fill = clamp(xp / max)
  return {
    fill = fill, restedTo = clamp((xp + rested) / max), questTo = clamp((xp + quest) / max),
    percent = fill * 100, restedPercent = rested / max * 100, questPercent = quest / max * 100,
    remaining = math.max(0, max - xp),
  }
end

-- ------------------------------------------------------------------------------------------------ readings
local function readXP()
  local xp, max, lvl = call(g("UnitXP"), "player"), call(g("UnitXPMax"), "player"), call(g("UnitLevel"), "player")
  if isSecret(xp) or isSecret(max) then count("secretXP") end
  return num(xp), num(max), num(lvl)
end

local function readRested()
  local r = num(call(g("GetXPExhaustion")))
  return r and r > 0 and r or 0
end

--- Is this character done levelling (cap reached, or experience turned off)?
function XP.AtCap(lvl)
  if call(g("IsXPUserDisabled")) then return true end
  local cap = num(call(g("GetMaxPlayerLevel")))
  if cap and lvl and lvl >= cap then return true end
  return false
end

-- quest log, the minimum: { id, index, complete } per real quest (headers skipped)
local function logEntries()
  local out = {}
  local C = rawget(_G, "C_QuestLog")
  if fn(C, "GetNumQuestLogEntries") and fn(C, "GetInfo") then
    local n = num(call(C.GetNumQuestLogEntries)) or 0
    for i = 1, n do
      local info = call(C.GetInfo, i)
      if type(info) == "table" and not info.isHeader and not info.isHidden then
        local complete = info.questID and fn(C, "IsComplete") and call(C.IsComplete, info.questID)
        out[#out + 1] = { id = num(info.questID), index = i, complete = complete and true or false }
      end
    end
    XP.path.log = "C_QuestLog.GetInfo"
    return out
  end
  local title, numE = g("GetQuestLogTitle"), g("GetNumQuestLogEntries")
  if title and numE then
    local n = num(call(numE)) or 0
    for i = 1, n do
      local ok, t, _, _, isHeader, _, isComplete, _, questID = pcall(title, i)
      if ok and t and not isHeader then
        out[#out + 1] = { id = num(questID), index = i, complete = (isComplete == 1 or isComplete == true) }
      end
    end
    XP.path.log = "GetQuestLogTitle"
    return out
  end
  XP.path.log = "none"
  return out
end

--- Reward XP of the quests in the log: questMode "complete" (default, the ones ready to turn in) or "all".
function XP.QuestXP(mode)
  mode = mode or cfg().questMode or "complete"
  local entries = logEntries()
  local reward = g("GetQuestLogRewardXP")
  if not reward then XP.path.reward = "none" return 0 end
  local total = 0
  -- a client with SelectQuestLogEntry reads the SELECTED quest and ignores any argument (asking with a questID there
  -- would hand back one quest's xp for every entry); without it the questID form is the only one
  local select, selection = g("SelectQuestLogEntry"), g("GetQuestLogSelection")
  local legacy = select ~= nil
  local saved = legacy and selection and num(call(selection)) or nil
  for _, q in ipairs(entries) do
    if mode == "all" or q.complete then
      local v
      if legacy then
        call(select, q.index)
        v = num(call(reward))
      elseif q.id then
        v = num(call(reward, q.id))
      end
      total = total + (v or 0)
    end
  end
  if legacy and saved then call(select, saved) end
  XP.path.reward = legacy and "SelectQuestLogEntry+GetQuestLogRewardXP()" or "GetQuestLogRewardXP(questID)"
  return total
end

-- ------------------------------------------------------------------------------------------------ texts
local function pace()
  local S = HH.Session
  if not S then return nil end
  local st = S.Stats()
  if st.hidden or not st.rate then return nil end
  local s = S.FormatNumber(st.rate) .. " xp/h"
  if st.toLevel then s = s .. "  lvl in " .. S.FormatTime(st.toLevel) end
  return s
end

--- Left and right strings for the readings (pure; c = XP.Compute result or nil).
function XP.Texts(c, lvl, xp, max, quest)
  local o = cfg()
  if not c then return "-", "" end
  local left = ("Lv %s  %s / %s  %.0f%%"):format(lvl and tostring(lvl) or "?", XP.Commas(xp), XP.Commas(max), c.percent)
  local parts = {}
  if o.showRested ~= false and c.restedPercent > 0 then parts[#parts + 1] = ("+%.0f%% rested"):format(c.restedPercent) end
  if o.showQuest ~= false and (quest or 0) > 0 then parts[#parts + 1] = ("+%.0f%% quests"):format(c.questPercent) end
  if o.showPace ~= false then local p = pace() if p then parts[#parts + 1] = p end end
  return left, table.concat(parts, "   ")
end

-- ------------------------------------------------------------------------------------------------ draw
local function width(b)
  local w = b:GetWidth()
  if type(w) == "number" and not isSecret(w) then return w end
  return 0
end

local function overlay(b, tex, from, to, shown)
  if not tex then return end
  local w = width(b)
  local px = math.max(0, (to - from) * w)
  if not shown or px <= 0 then tex:Hide() return end
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", b, "TOPLEFT", from * w, 0)
  tex:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", from * w, 0)
  tex:SetWidth(px)
  tex:Show()
end

function XP.Update()
  local b = bar()
  if not b then return end
  count("updates")
  local o = cfg()
  local xp, max, lvl = readXP()
  if b.enabled == false then b:Hide() return end
  if o.hideAtMax ~= false and XP.AtCap(lvl) then b:Hide() return end
  b:Show()
  local rested = o.showRested ~= false and readRested() or 0
  local quest = o.showQuest ~= false and XP.QuestXP() or 0
  local c = XP.Compute(xp, max, rested, quest)
  local col = o.color or CYAN
  b:SetStatusBarColor(col[1], col[2], col[3])
  b:SetMinMaxValues(0, 1)
  b:SetValue(c and c.fill or 0)
  if c then
    overlay(b, b.rested, c.fill, c.restedTo, o.showRested ~= false and rested > 0)
    overlay(b, b.quest, c.fill, c.questTo, o.showQuest ~= false and quest > 0)
  else
    if b.rested then b.rested:Hide() end
    if b.quest then b.quest:Hide() end
  end
  local left, right = XP.Texts(c, lvl, xp, max, quest)
  b.left:SetText(o.text ~= false and left or "")
  b.right:SetText(o.text ~= false and right or "")
  XP.last = { xp = xp, max = max, lvl = lvl, rested = rested, quest = quest }
end

--- The pace text ages without an event: refresh every REFRESH seconds while shown.
function XP.OnUpdate(_, elapsed)
  XP.elapsed = XP.elapsed + (elapsed or 0)
  if XP.elapsed < XP.REFRESH then return end
  XP.elapsed = 0
  XP.Update()
end

function XP.Refresh()
  local b = bar()
  if not b then return end
  local o = cfg()
  local rc, qc = o.restedColor or CYAN, o.questColor or GREEN
  if b.rested then b.rested:SetColorTexture(rc[1], rc[2], rc[3], o.restedAlpha or 0.35) end
  if b.quest then b.quest:SetColorTexture(qc[1], qc[2], qc[3], o.questAlpha or 0.55) end
  local d = hud()
  local font = HH.Look and HH.Look.Font and HH.Look.Font(d.font) or nil
  local size = (o.fontSize or 0) > 0 and o.fontSize or ((d.fontSize or 11) - 1)
  if font then b.left:SetFont(font, size, "OUTLINE") b.right:SetFont(font, size, "OUTLINE") end
  XP.Update()
end

-- ------------------------------------------------------------------------------------------------ wiring
function XP.Init()
  local b = bar()
  if not b or XP.frame then XP.Refresh() return end
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "QUEST_LOG_UPDATE",
    "UNIT_QUEST_LOG_CHANGED", "QUEST_TURNED_IN", "DISABLE_XP_GAIN", "ENABLE_XP_GAIN" }) do
    pcall(f.RegisterEvent, f, e)   -- a client that lacks an event name throws
  end
  f:SetScript("OnEvent", function() XP.Update() end)
  XP.frame = f
  b:SetScript("OnUpdate", function(self, elapsed) XP.OnUpdate(self, elapsed) end)
  XP.Refresh()
end

--- Chat lines for /hh xpdiag.
function XP.Lines()
  local l = XP.last or {}
  local out = {}
  out[#out + 1] = ("xp: %s / %s at level %s, rested %s, quests %s (%s)"):format(XP.Commas(l.xp), XP.Commas(l.max),
    tostring(l.lvl or "?"), XP.Commas(l.rested), XP.Commas(l.quest), cfg().questMode or "complete")
  out[#out + 1] = ("paths: log=%s reward=%s; secret xp reads %d, updates %d"):format(XP.path.log, XP.path.reward,
    XP.seen.secretXP or 0, XP.seen.updates or 0)
  local b = bar()
  out[#out + 1] = ("row: %s, at cap %s"):format(b and (b:IsShown() and "shown" or "hidden") or "missing", tostring(XP.AtCap(l.lvl)))
  return out
end

HH:RegisterSlash("xpdiag", function()
  for _, l in ipairs(XP.Lines()) do HH:Print(l) end
end, "experience bar: readings, which quest-reward API answered, why the row is hidden")
