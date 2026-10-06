-- Training: what is waiting for you at the class trainer right now, what comes at the next levels and what it all
-- costs - without walking there. Sean 2026-10-06, from the "What's Training?" clip: "all the available spells for
-- you at your trainer before you even get to them... here's the coming soon, I get all these at level 22".
--
-- No shipped spell tables (rule since Atlas: never write game data from memory into the UI). The list is LEARNED at
-- the trainer: the first visit reads every service the window can show (available, not yet, already known) with
-- level and cost and keeps it per class, account-wide. From then on /hh train, the info bar text and the level-up
-- nudge answer from that memory; every later visit refreshes it. Weapon trainers by city are the old game's list,
-- labelled so (Data/WeaponTrainers.lua).
HogHealsTraining = HogHealsTraining or {}
local T = HogHealsTraining
local HH = HogHeals

local CYAN, CREAM, GREY, GREEN, AMBER = { 0.13, 0.83, 0.88 }, { 0.96, 0.92, 0.86 }, { 0.55, 0.55, 0.60 }, { 0.25, 0.80, 0.35 }, { 0.95, 0.65, 0.15 }
local INK, LINE = { 0.07, 0.07, 0.09 }, { 0.20, 0.20, 0.25 }

local function cfg() local p = HH.db and HH.db.profile return (p and p.training) or {} end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function str(v) if type(v) == "string" and not isSecret(v) then return v end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c = pcall(f, ...)
  if ok then return a, b, c end
end
local function G(name) return rawget(_G, name) end
local function today() return (type(date) == "function" and date("%Y-%m-%d")) or "" end

function T.Class()
  local _, class = call(UnitClass, "player")
  return str(class) or "UNKNOWN"
end
function T.Level() return num(call(UnitLevel, "player")) or 1 end
function T.Side()
  local f = str(call(G("UnitFactionGroup"), "player"))
  if f == "Horde" then return "H" elseif f == "Alliance" then return "A" end
end

--- What this class has learned about its trainer (account-wide, HogHealsDB.global.training[class]).
function T.db(class)
  local g = HH.db and HH.db.global
  if not g then T.mem = T.mem or {} g = T.mem end
  g.training = g.training or {}
  class = class or T.Class()
  local t = g.training[class]
  if not t then t = { spells = {}, visits = 0 } g.training[class] = t end
  return t
end

-- ------------------------------------------------------------------------------------------------ learn at the trainer
local FILTERS = { "available", "unavailable", "used" }

--- Read every service the open trainer window knows. Returns how many spells were recorded, or nil + why.
function T.Learn()
  local n = call(G("GetNumTrainerServices"))
  if not num(n) then return nil, "no trainer window" end
  if call(G("IsTradeskillTrainer")) then return nil, "profession trainer" end
  local info, cost, lvl, icon = G("GetTrainerServiceInfo"), G("GetTrainerServiceCost"), G("GetTrainerServiceLevelReq"), G("GetTrainerServiceIcon")
  if type(info) ~= "function" then return nil, "no GetTrainerServiceInfo on this client" end
  -- show everything for the read, then put the player's filters back
  local setF, getF = G("SetTrainerServiceTypeFilter"), G("GetTrainerServiceTypeFilter")
  local before = {}
  if type(setF) == "function" then
    for _, k in ipairs(FILTERS) do
      if type(getF) == "function" then local v = call(getF, k) before[k] = v and true or false end   -- not `x or nil`: false must survive
      pcall(setF, k, true)
    end
    n = num(call(G("GetNumTrainerServices"))) or n
  end
  local db = T.db()
  local recorded = 0
  for i = 1, n do
    local name, rank, category = call(info, i)
    name, rank, category = str(name), str(rank), str(category)
    if name and category and category ~= "header" then
      local key = name .. "|" .. (rank or "")
      local c = num(call(cost, i)) or 0
      local l = num(call(lvl, i)) or 0
      db.spells[key] = { name = name, rank = rank, level = l, cost = c, icon = call(icon, i), known = category == "used", seen = today() }
      recorded = recorded + 1
    end
  end
  if type(setF) == "function" then
    for _, k in ipairs(FILTERS) do if before[k] ~= nil then pcall(setF, k, before[k] and true or false) end end
  end
  db.visits = (db.visits or 0) + 1
  db.lastSeen = today()
  db.trainer = str(call(UnitName, "npc")) or db.trainer
  return recorded
end

-- ------------------------------------------------------------------------------------------------ the plan
--- Spells sorted into: now (your level, not known), soon (above your level, grouped by level), known count.
-- Pure over the memory table: T.PlanFrom(spells, level).
function T.PlanFrom(spells, level)
  local now, soon, byLevel, known = {}, {}, {}, 0
  for _, s in pairs(spells or {}) do
    if s.known then known = known + 1
    elseif (s.level or 0) <= level then now[#now + 1] = s
    else
      local g = byLevel[s.level]
      if not g then g = { level = s.level, spells = {}, cost = 0 } byLevel[s.level] = g soon[#soon + 1] = g end
      g.spells[#g.spells + 1] = s
      g.cost = g.cost + (s.cost or 0)
    end
  end
  local function byName(a, b) if a.level ~= b.level then return a.level < b.level end return a.name < b.name end
  table.sort(now, byName)
  for _, g in ipairs(soon) do table.sort(g.spells, byName) end
  table.sort(soon, function(a, b) return a.level < b.level end)
  local cost = 0
  for _, s in ipairs(now) do cost = cost + (s.cost or 0) end
  return { now = now, cost = cost, soon = soon, known = known, total = #now + known + (function() local k = 0 for _, g in ipairs(soon) do k = k + #g.spells end return k end)() }
end

function T.Plan() return T.PlanFrom(T.db().spells, T.Level()) end

local function money(copper)
  if HH.Session and HH.Session.FormatMoney then return HH.Session.FormatMoney(copper) end
  copper = math.floor((copper or 0) + 0.5)
  local g, s = math.floor(copper / 10000), math.floor(copper / 100) % 100
  if g > 0 then return ("%dg %ds"):format(g, s) end
  return ("%ds %dc"):format(s, copper % 100)
end
T.Money = money

local function label(s) return s.rank and s.rank ~= "" and (s.name .. " (" .. s.rank .. ")") or s.name end

--- Chat lines for /hh train say.
function T.Lines()
  local db, plan = T.db(), T.Plan()
  local out = {}
  if (db.visits or 0) == 0 then
    out[#out + 1] = "training: nothing learned yet - open your class trainer once and this remembers every spell, level and price."
    return out
  end
  if #plan.now > 0 then
    local names = {}
    for i, s in ipairs(plan.now) do if i <= 6 then names[#names + 1] = label(s) end end
    out[#out + 1] = ("train now: %d spell%s for %s - %s%s"):format(#plan.now, #plan.now > 1 and "s" or "", money(plan.cost), table.concat(names, ", "), #plan.now > 6 and ", ..." or "")
  else
    out[#out + 1] = "train now: nothing - you are up to date."
  end
  for i, g in ipairs(plan.soon) do
    if i > 3 then break end
    local names = {}
    for j, s in ipairs(g.spells) do if j <= 5 then names[#names + 1] = label(s) end end
    out[#out + 1] = ("at %d: %d for %s - %s%s"):format(g.level, #g.spells, money(g.cost), table.concat(names, ", "), #g.spells > 5 and ", ..." or "")
  end
  out[#out + 1] = ("%d spells known, %d visit%s, last %s%s. Prices are the trainer's base; your city's reputation takes 5-20%% off."):format(
    plan.known, db.visits or 0, (db.visits or 0) == 1 and "" or "s", db.lastSeen or "?", db.trainer and (" at " .. db.trainer) or "")
  return out
end

-- ------------------------------------------------------------------------------------------------ window
local ROWS = 34
local function fs(parent, color, justify, template)
  local t = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  t:SetTextColor(color[1], color[2], color[3])
  t:SetJustifyH(justify or "LEFT")
  if t.SetWordWrap then t:SetWordWrap(false) end
  return t
end

function T.Build()
  if T.frame then return T.frame end
  local f = CreateFrame("Frame", "HogTronUITraining", UIParent)
  f:SetSize(560, 24 + ROWS * 16 + 16)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints(f)
  f.bg:SetColorTexture(INK[1], INK[2], INK[3], 0.92)
  f.rule = f:CreateTexture(nil, "ARTWORK")
  f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -24)
  f.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -24)
  f.rule:SetHeight(1)
  f.rule:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 1)
  f.title = fs(f, CREAM, "LEFT", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -6)
  f.title:SetText("|cffF5EBDCHOG|r|cff21D4E0TRON UI|r  TRAINING")
  f.close = CreateFrame("Button", nil, f)
  f.close:SetSize(24, 20)
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -2)
  f.close.label = fs(f.close, CREAM, "CENTER")
  f.close.label:SetPoint("CENTER", f.close, "CENTER", 0, 0)
  f.close.label:SetText("x")
  f.close:SetScript("OnClick", function() f:Hide() end)
  f.rows = {}
  for i = 1, ROWS do
    local r = fs(f, CREAM, "LEFT")
    r:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30 - (i - 1) * 16)
    r:SetPoint("RIGHT", f, "RIGHT", -120, 0)
    local right = fs(f, GREY, "RIGHT")
    right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -30 - (i - 1) * 16)
    right:SetWidth(110)
    f.rows[i] = { text = r, right = right }
  end
  local special = G("UISpecialFrames")
  if type(special) == "table" then special[#special + 1] = "HogTronUITraining" end
  f:Hide()
  T.frame = f
  return f
end

--- Rows for the window: { text, right, color }. Pure given plan + memory + side: T.RowsFrom(plan, db, side).
function T.RowsFrom(plan, db, side, level)
  local rows = {}
  local function add(text, right, color) rows[#rows + 1] = { text = text, right = right or "", color = color or CREAM } end
  if (db.visits or 0) == 0 then
    add("Nothing learned yet.", "", GREY)
    add("Open your class trainer once: every spell, its level and price is remembered from then on.", "", GREY)
  else
    add(("TRAIN NOW  -  %d spell%s"):format(#plan.now, #plan.now == 1 and "" or "s"), money(plan.cost), CYAN)
    if #plan.now == 0 then add("  up to date", "", GREY) end
    for _, s in ipairs(plan.now) do add("  " .. label(s), money(s.cost), GREEN) end
    for _, g in ipairs(plan.soon) do
      add(("AT LEVEL %d  -  %d spell%s"):format(g.level, #g.spells, #g.spells == 1 and "" or "s"), money(g.cost), CYAN)
      for _, s in ipairs(g.spells) do add("  " .. label(s), money(s.cost), g.level <= (level or 0) + 2 and CREAM or GREY) end
    end
    add(("%d known. Learned at %s (%d visit%s, last %s). Base prices: your city's reputation takes off %s."):format(
      plan.known, db.trainer or "your trainer", db.visits or 0, (db.visits or 0) == 1 and "" or "s", db.lastSeen or "?",
      "5% friendly, 10% honored, 15% revered, 20% exalted"), "", GREY)
  end
  add("", "")
  add("WEAPON TRAINERS  -  old list, not verified on Forever", side and (side == "H" and "Horde" or "Alliance") or "", CYAN)
  for _, t in ipairs(T.Data.Trainers(side or "A")) do
    add(("  %s  -  %s, %s"):format(t.name, t.city, t.where), "", CREAM)
    add("      " .. table.concat(t.skills, ", "), "old list", GREY)
  end
  return rows
end

function T.Refresh()
  local f = T.frame
  if not f or not f:IsShown() then return end
  local rows = T.RowsFrom(T.Plan(), T.db(), T.Side(), T.Level())
  for i, r in ipairs(f.rows) do
    local d = rows[i]
    if d then
      r.text:SetText(d.text) r.text:SetTextColor(d.color[1], d.color[2], d.color[3]) r.text:Show()
      r.right:SetText(d.right) r.right:Show()
    else r.text:Hide() r.right:Hide() end
  end
  T.rowCount = #rows
end

function T.Toggle()
  local f = T.Build()
  if f:IsShown() then f:Hide() else f:Show() T.Refresh() end
end

-- ------------------------------------------------------------------------------------------------ info bar text
function T.Short()
  local db = T.db()
  if (db.visits or 0) == 0 then return "visit a trainer" end
  local plan = T.Plan()
  if #plan.now > 0 then return ("%d to train  %s"):format(#plan.now, money(plan.cost)) end
  local g = plan.soon[1]
  if g then return ("trained up  (%d at %d)"):format(#g.spells, g.level) end
  return "trained up"
end

function T.RegisterDatatext()
  local S = G("HogHealsSkin")
  local P = type(S) == "table" and S.InfoBar and S.InfoBar.providers
  if type(P) ~= "table" or P.train then return false end
  P.train = { label = "Training",
    value = function() return T.Short() end,
    tooltip = function(tip) for i, l in ipairs(T.Lines()) do tip:AddLine(l, i == 1 and 1 or 0.75, i == 1 and 1 or 0.75, i == 1 and 1 or 0.8, true) end tip:AddLine("Click: the training window", 0.5, 0.5, 0.55) end,
    click = function() T.Toggle() end }
  return true
end

-- ------------------------------------------------------------------------------------------------ wiring
local Module = {}
T.module = Module

function Module:OnEnable()
  if cfg().enabled == false then return end
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "PLAYER_LEVEL_UP" }) do pcall(ev.RegisterEvent, ev, e) end
  ev:SetScript("OnEvent", function(_, e, arg1)
    if e == "TRAINER_SHOW" or e == "TRAINER_UPDATE" then
      local n, why = T.Learn()
      if n and e == "TRAINER_SHOW" then HH:Print(("training: %d services remembered from this trainer."):format(n)) end
      T.lastLearn = n or why
      T.Refresh()
    elseif e == "PLAYER_LEVEL_UP" then
      local plan = T.PlanFrom(T.db().spells, num(arg1) or T.Level())
      if cfg().nudge ~= false and #plan.now > 0 then
        HH:Print(("Level %s: %d spell%s waiting at the trainer (%s). /hh train"):format(tostring(arg1), #plan.now, #plan.now == 1 and "" or "s", money(plan.cost)))
      end
      T.Refresh()
    end
  end)
  Module.events = ev
  T.RegisterDatatext()
end

HH:RegisterModule("Training", Module)

HH:RegisterSlash("train", function(rest)
  rest = (rest or ""):lower()
  if rest == "say" or rest == "chat" then for _, l in ipairs(T.Lines()) do HH:Print(l) end return end
  if rest == "forget" then local g = HH.db and HH.db.global if g and g.training then g.training[T.Class()] = nil end HH:Print("training: memory for this class cleared.") return end
  T.Toggle()
end, "what's training: spells waiting at the trainer, the ones coming, weapon trainers (/hh train say | forget)")
