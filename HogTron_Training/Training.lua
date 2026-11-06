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
T.CATEGORIES = { available = true, unavailable = true, used = true, header = true }

--- One trainer service, whichever layout this client's GetTrainerServiceInfo returns: Classic's
-- (name, rank / subtext, category, expanded) or the modern trainer window's (name, category, icon, required level).
-- In game 2026-11-05 (Sean, druid, "I've opened up my class trainer multiple times, and this is not updated"):
-- diag training.DRUID visits 0, spells {} - every read found no category where the Classic layout keeps it, so
-- nothing was recorded and no visit counted. The category is now found by its value wherever it sits.
-- Returns { name, rank, category, icon, level } or nil.
function T.ServiceInfo(i)
  local info = G("GetTrainerServiceInfo")
  if type(info) ~= "function" then return nil end
  local function pack(ok, ...) if ok then return { n = select("#", ...), ... } end end
  local r = pack(pcall(info, i))
  if not r then return nil end
  local name = str(r[1])
  if not name then return nil end
  local out = { name = name }
  for k = 2, math.min(r.n, 5) do
    local v = r[k]
    local s = str(v)
    if s and T.CATEGORIES[s] and not out.category then out.category = s
    elseif s and s ~= "" and not out.rank and not out.category then out.rank = s       -- the subtext ahead of the category
    elseif num(v) and out.category and k == 3 then out.icon = v                       -- modern: icon after the category
    elseif num(v) and out.category and k == 4 then out.level = v end                   -- modern: required level
  end
  return out
end

--- Read every service the open trainer window knows. Returns how many spells were recorded, or nil + why.
function T.Learn()
  local n = call(G("GetNumTrainerServices"))
  if not num(n) then T.SaveRead({ why = "no trainer window (GetNumTrainerServices = " .. tostring(n) .. ")" }) return nil, "no trainer window" end
  if call(G("IsTradeskillTrainer")) then T.SaveRead({ n = n, why = "profession trainer" }) return nil, "profession trainer" end
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
  local sample = {}
  for i = 1, n do
    local s = T.ServiceInfo(i)
    if i <= 3 then sample[#sample + 1] = T.RawService(i) end
    if s and s.category and s.category ~= "header" then
      local l = num(call(lvl, i)) or s.level or 0
      -- no rank on this client: the level keeps two ranks of one spell apart (Healing Touch at 14 and at 20)
      local key = s.name .. "|" .. (s.rank or ("L" .. l))
      local c = num(call(cost, i)) or 0
      db.spells[key] = { name = s.name, rank = s.rank, level = l, cost = c, icon = call(icon, i) or s.icon, known = s.category == "used", seen = today() }
      recorded = recorded + 1
    end
  end
  T.SaveRead({ n = n, recorded = recorded, sample = table.concat(sample, " || ") })
  if type(setF) == "function" then
    for _, k in ipairs(FILTERS) do if before[k] ~= nil then pcall(setF, k, before[k] and true or false) end end
  end
  if recorded == 0 then return 0 end                     -- nothing read yet: not a visit (the list is still coming)
  db.visits = (db.visits or 0) + 1
  db.lastSeen = today()
  db.trainer = str(call(UnitName, "npc")) or db.trainer
  return recorded
end

--- What GetTrainerServiceInfo(i) really returned, as "type:value" per return (for diag.trainerRead).
function T.RawService(i)
  local info = G("GetTrainerServiceInfo")
  if type(info) ~= "function" then return "no GetTrainerServiceInfo" end
  local function pack(ok, ...) return ok, { n = select("#", ...), ... } end
  local ok, r = pack(pcall(info, i))
  if not ok then return ("%d: error %s"):format(i, tostring(r[1])) end
  local parts = {}
  for k = 1, math.min(r.n, 6) do
    local v = r[k]
    parts[#parts + 1] = isSecret(v) and "secret" or (type(v) .. ":" .. tostring(v):sub(1, 30))
  end
  return ("%d: %s"):format(i, table.concat(parts, ", "))
end

--- The last trainer read, for /hh traindiag (saved with the next /reload or logout): what the window held, what was
-- recorded, the first services exactly as the client returned them, and which trainer functions exist.
function T.SaveRead(r)
  local g = HH.db and HH.db.global
  if not g then return nil end
  g.diag = g.diag or {}
  local fns = {}
  for _, f in ipairs({ "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceCost", "GetTrainerServiceLevelReq",
    "GetTrainerServiceIcon", "SetTrainerServiceTypeFilter", "GetTrainerServiceTypeFilter", "IsTradeskillTrainer" }) do
    if type(G(f)) ~= "function" then fns[#fns + 1] = f end
  end
  r.at = (type(date) == "function" and date("%Y-%m-%d %H:%M:%S")) or "?"
  r.class = T.Class()
  r.trainer = str(call(UnitName, "npc"))
  r.missing = #fns > 0 and table.concat(fns, ",") or "none"
  r.events = ("show %d, update %d, echoes %d, reads %d"):format(T.shows or 0, T.updates or 0, T.echoes or 0, T.reads or 0)
  g.diag.trainerRead = r
  return r
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
local ROW_H, HEAD_H, GAP = 18, 24, 8
local W = 560

--- The window is the quest dialog's parchment page (Sean 2026-11-05: "design the menu to look like the dialogue
-- menu for quests"): torn page, the class circle in the bronze ring, a title with its rule, rounded tags for the
-- sections, ink text, Friz Quadrata. Core/Parchment.lua carries the art and the themes; the page follows
-- Quests > Dialog > Theme (light parchment / charred dark). The rows keep the same model as before (text, right,
-- colour by tone) so the chat form and the tests see one list.
local function pageFont(t, size)
  local P = HH.Parchment
  if P then P.Font(t, size) elseif t.SetFont then pcall(t.SetFont, t, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "") end
end

local function fs(parent, color, justify, template)
  local t = parent:CreateFontString(nil, "OVERLAY", template or "HogTronFontHighlight")
  t:SetTextColor(color[1], color[2], color[3])
  t:SetJustifyH(justify or "LEFT")
  if t.SetJustifyV then t:SetJustifyV("TOP") end
  if t.SetWordWrap then t:SetWordWrap(false) end
  return t
end

function T.Theme()
  local P = HH.Parchment
  if P then return P.Theme() end
  return { text = CREAM, title = CREAM, muted = GREY, rule = CYAN, tag = { 1, 1, 1, 0.08 }, key = INK, keyText = CREAM, quest = AMBER, good = GREEN }
end

function T.Build()
  if T.frame then return T.frame end
  local P = HH.Parchment
  local f = CreateFrame("Frame", "HogTronUITraining", UIParent)
  f:SetSize(W, 400)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  f:SetFrameStrata("DIALOG")
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  if P then P.MakePage(f) else
    f.bg = f:CreateTexture(nil, "BACKGROUND") f.bg:SetAllPoints(f) f.bg:SetColorTexture(INK[1], INK[2], INK[3], 0.92)
  end
  f.portrait = f:CreateTexture(nil, "ARTWORK")
  f.ring = f:CreateTexture(nil, "OVERLAY")
  if P then f.ring:SetTexture(P.ART.ring) end
  f.title = fs(f, CREAM, "LEFT", "HogTronFontNormalLarge")
  f.sub = fs(f, GREY, "LEFT", "HogTronFontSmall")
  f.rule = f:CreateTexture(nil, "ARTWORK")
  if P then f.rule:SetTexture(P.ART.rule) else f.rule:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 1) end
  -- close: a key cap at the top-right corner ("x"); Esc closes too (UISpecialFrames)
  f.close = CreateFrame("Button", "HogTronUITrainingClose", f)
  f.close:SetSize(24, 20)
  f.close.cap = P and P.Slab(f.close, "ARTWORK") or nil
  f.close.label = fs(f.close, CREAM, "CENTER", "HogTronFontSmall")
  f.close.label:SetPoint("CENTER", f.close, "CENTER", 0, 0)
  f.close.label:SetText("x")
  f.close:SetScript("OnClick", function() f:Hide() end)
  f.rows = {}
  for i = 1, ROWS do
    local r = { text = fs(f, CREAM, "LEFT"), right = fs(f, GREY, "RIGHT"), tag = P and P.Slab(f, "ARTWORK") or nil }
    f.rows[i] = r
  end
  local special = G("UISpecialFrames")
  if type(special) == "table" then special[#special + 1] = "HogTronUITraining" end
  f:Hide()
  T.frame = f
  return f
end

--- Rows for the window: { text, right, color }. Pure given plan + memory + side: T.RowsFrom(plan, db, side).
-- ------------------------------------------------------------------------------------------------ icons
-- Sean 2026-11-04: "I want visuals added to this with normal pictures from in the game." Spell rows show the icon the
-- trainer window handed over (recorded with the spell); weapon rows show the client's weapon-skill icons. The skill
-- ids are the old game's: only the ICON is read from them, through the client, so a wrong id shows no icon, never a
-- wrong fact. Row text stays plain (chat lines, tests); the window composes the picture in front of it.
T.WEAPON_SKILL_SPELL = { ["Axes"] = 196, ["Two-Handed Axes"] = 197, ["Maces"] = 198, ["Two-Handed Maces"] = 199,
  ["Polearms"] = 200, ["Swords"] = 201, ["Two-Handed Swords"] = 202, ["Staves"] = 227, ["Bows"] = 264, ["Guns"] = 266,
  ["Daggers"] = 1180, ["Thrown"] = 2567, ["Crossbows"] = 5011, ["Wands"] = 5009, ["Fist Weapons"] = 15590 }

function T.WeaponIcon(skill)
  local id = T.WEAPON_SKILL_SPELL[skill]
  if not id then return nil end
  local tex = call(G("GetSpellTexture"), id)
  if type(tex) == "string" or type(tex) == "number" then return tex end
end

--- "|Ticon:14:14:0:0|t " for a texture path or file id; "" without one.
function T.IconTag(icon, size)
  if type(icon) ~= "string" and type(icon) ~= "number" then return "" end
  size = size or 14
  return ("|T%s:%d:%d:0:0|t "):format(tostring(icon), size, size)
end

--- The text a row shows: its icon (or its skills' icons) in front of the plain text.
function T.RowDisplay(d)
  if d.skills then
    local parts = {}
    for _, sk in ipairs(d.skills) do parts[#parts + 1] = T.IconTag(T.WeaponIcon(sk), 12) .. sk end
    return "      " .. table.concat(parts, ", ")
  end
  if d.icon then
    local lead = d.text:match("^%s*") or ""
    return lead .. T.IconTag(d.icon) .. (d.text:gsub("^%s+", ""))
  end
  return d.text
end

function T.RowsFrom(plan, db, side, level)
  local rows = {}
  local function add(text, right, color, icon, skills, tone)
    rows[#rows + 1] = { text = text, right = right or "", color = color or CREAM, icon = icon, skills = skills, tone = tone or (text == "" and "blank") or "text" }
  end
  if (db.visits or 0) == 0 then
    add("Nothing learned yet.", "", GREY, nil, nil, "muted")
    add("Open your class trainer once: every spell, its level and price is remembered from then on.", "", GREY, nil, nil, "muted")
  else
    add(("TRAIN NOW  -  %d spell%s"):format(#plan.now, #plan.now == 1 and "" or "s"), money(plan.cost), CYAN, nil, nil, "head")
    if #plan.now == 0 then add("  up to date", "", GREY, nil, nil, "muted") end
    for _, s in ipairs(plan.now) do add("  " .. label(s), money(s.cost), GREEN, s.icon, nil, "now") end
    for _, g in ipairs(plan.soon) do
      add(("AT LEVEL %d  -  %d spell%s"):format(g.level, #g.spells, #g.spells == 1 and "" or "s"), money(g.cost), CYAN, nil, nil, "head")
      local near = g.level <= (level or 0) + 2
      for _, s in ipairs(g.spells) do add("  " .. label(s), money(s.cost), near and CREAM or GREY, s.icon, nil, near and "text" or "muted") end
    end
    add(("%d known. Learned at %s (%d visit%s, last %s). Base prices: your city's reputation takes off %s."):format(
      plan.known, db.trainer or "your trainer", db.visits or 0, (db.visits or 0) == 1 and "" or "s", db.lastSeen or "?",
      "5% friendly, 10% honored, 15% revered, 20% exalted"), "", GREY, nil, nil, "memo")
  end
  add("", "")
  add("WEAPON TRAINERS  -  old list, not verified on Forever", side and (side == "H" and "Horde" or "Alliance") or "", CYAN, nil, nil, "head")
  for _, t in ipairs(T.Data.Trainers(side or "A")) do
    add(("  %s  -  %s, %s"):format(t.name, t.city, t.where), "", CREAM, nil, nil, "title")
    add("      " .. table.concat(t.skills, ", "), "old list", GREY, nil, t.skills, "muted")
  end
  return rows
end

--- The ink for a row's tone on the current theme.
function T.ToneColor(tone)
  local th = T.Theme()
  if tone == "head" or tone == "title" then return th.title end
  if tone == "now" then return th.good or th.text end
  if tone == "muted" or tone == "memo" then return th.muted end
  return th.text
end

function T.Refresh()
  local f = T.frame
  if not f or not f:IsShown() then return end
  local P, th = HH.Parchment, T.Theme()
  local rows = T.RowsFrom(T.Plan(), T.db(), T.Side(), T.Level())
  local s = W / (P and P.PAGE_W or 512)
  local PADX, TOP = math.floor(46 * s + 0.5), math.floor(44 * s + 0.5)
  local inner = W - 2 * PADX
  -- header: the class circle in its ring, the title, the trainer line, the rule
  local RING, PIC = 64, 50
  local _, class = call(UnitClass, "player")
  if P then P.ClassPortrait(f.portrait, class) end
  f.portrait:ClearAllPoints() f.portrait:SetPoint("TOPLEFT", f, "TOPLEFT", PADX + (RING - PIC) / 2, -TOP - (RING - PIC) / 2) f.portrait:SetSize(PIC, PIC) f.portrait:Show()
  f.ring:ClearAllPoints() f.ring:SetPoint("TOPLEFT", f, "TOPLEFT", PADX, -TOP) f.ring:SetSize(RING, RING) f.ring:Show()
  local tx = PADX + RING + 10
  pageFont(f.title, 20)
  f.title:SetText("Training")
  f.title:SetTextColor(th.title[1], th.title[2], th.title[3])
  f.title:ClearAllPoints() f.title:SetPoint("TOPLEFT", f, "TOPLEFT", tx, -TOP - 4) f.title:SetWidth(inner - RING - 10) f.title:Show()
  local db = T.db()
  pageFont(f.sub, 12)
  f.sub:SetText((db.visits or 0) > 0 and ("Learned at %s  -  %d visit%s, last %s"):format(db.trainer or "your trainer", db.visits or 0, (db.visits or 0) == 1 and "" or "s", db.lastSeen or "?")
    or "Your class trainer teaches this page: open one once and it remembers every spell, level and price.")
  f.sub:SetTextColor(th.muted[1], th.muted[2], th.muted[3])
  f.sub:ClearAllPoints() f.sub:SetPoint("TOPLEFT", f, "TOPLEFT", tx, -TOP - 30) f.sub:SetWidth(inner - RING - 10) f.sub:Show()
  f.rule:ClearAllPoints() f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", tx - 2, -TOP - RING + 8) f.rule:SetSize(inner - RING - 8, 6)
  if P then P.Tint(f.rule, th.rule, 0.9) end
  f.rule:Show()
  -- the close cap
  f.close:ClearAllPoints() f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PADX + 8, -TOP + 6)
  if f.close.cap then f.close.cap:Place(f.close, 0, 0, 24, 20) f.close.cap:Color(th.key) f.close.cap:Show() end
  pageFont(f.close.label, 11)
  f.close.label:SetTextColor(th.keyText[1], th.keyText[2], th.keyText[3])
  -- the rows
  local y = -TOP - RING - 16
  for i, r in ipairs(f.rows) do
    local d = rows[i]
    if d then
      local tone = d.tone or "text"
      local c = T.ToneColor(tone)
      if tone == "blank" then
        r.text:Hide() r.right:Hide() if r.tag then r.tag:Hide() end
        y = y - GAP
      else
        -- the memo and a long weapon-skill list wrap onto more lines (the preview showed them running over the next row)
        local wrap = tone == "memo" or (d.skills ~= nil and #d.text > 44)
        local lines = tone == "memo" and 3 or (wrap and 2 or 1)
        local size = tone == "head" and 13 or (tone == "memo" and 11 or 13)
        local h = tone == "head" and HEAD_H or (wrap and (lines * (size + 3) + 4) or ROW_H)
        if r.tag then
          if tone == "head" then r.tag:Place(f, PADX - 8, y, inner + 16, h) r.tag:Color(th.tag) r.tag:Show() else r.tag:Hide() end
        end
        pageFont(r.text, size)
        if r.text.SetWordWrap then r.text:SetWordWrap(wrap) end
        r.text:SetText(T.RowDisplay(d))
        r.text:SetTextColor(c[1], c[2], c[3])
        r.text:ClearAllPoints()
        r.text:SetPoint("TOPLEFT", f, "TOPLEFT", PADX, y - (tone == "head" and 5 or 2))
        r.text:SetSize(inner - 120, wrap and (h - 4) or ROW_H)
        r.text:Show()
        pageFont(r.right, size)
        r.right:SetText(d.right or "")
        local rc = tone == "head" and th.quest or th.muted
        r.right:SetTextColor(rc[1], rc[2], rc[3])
        r.right:ClearAllPoints()
        r.right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PADX, y - (tone == "head" and 5 or 2))
        r.right:SetWidth(110)
        r.right:Show()
        y = y - h
      end
    else r.text:Hide() r.right:Hide() if r.tag then r.tag:Hide() end end
  end
  local BOTTOM = math.floor(((P and P.TEAR or 46) + 14) * s + 0.5)
  local h = -y + BOTTOM
  f:SetSize(W, h)
  if P then P.PlacePage(f, W, h) end
  T.rowCount = #rows
  T.pageHeight = h
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

-- ------------------------------------------------------------------------------------------------ reading safely
-- Sean 2026-10-17, new character: "Whenever I click 'I'd like training', the game freezes. And I have to restart."
-- Learn() ran on every TRAINER_UPDATE, and Learn() flips the trainer's filters to read every service (and puts them
-- back) - each flip makes the client send another TRAINER_UPDATE, which ran Learn() again: an event storm that never
-- ended (the harness counted 1,602 filter flips in two seconds and climbing). Now: one read a frame after
-- TRAINER_SHOW; TRAINER_UPDATE re-reads only when it is not our own echo (QUIET seconds after our read) and debounced;
-- at most MAX_READS reads per visit.
T.QUIET = 1.0
T.MAX_READS = 4
T.reads = 0

function T.Now() return (type(GetTime) == "function" and num(GetTime())) or 0 end

function T.Schedule(why)
  if T.pending then return false end
  if (T.reads or 0) >= T.MAX_READS then T.capped = true return false end
  T.pending = true
  local function run()
    if not T.pending then return end
    T.pending = false
    if (T.reads or 0) >= T.MAX_READS then T.capped = true return end
    T.reads = (T.reads or 0) + 1
    T.learning = true
    local ok, n, whyNot = pcall(T.Learn)
    T.learning = false
    -- an EMPTY read (in game 2026-10-17: mage trainer, 4 visits, 0 spells - the list arrives a moment after the window)
    -- starts no quiet window, so the client's real TRAINER_UPDATE with the list is read (still capped per visit)
    T.quietUntil = (ok and (n or 0) > 0) and (T.Now() + T.QUIET) or 0
    if not ok then HH:LogError("training read: " .. tostring(n)) n, whyNot = nil, "error" end
    if n and why == "show" then HH:Print(("training: %d services remembered from this trainer."):format(n)) end
    T.lastLearn = n or whyNot
    T.Refresh()
  end
  if C_Timer and C_Timer.After then C_Timer.After(why == "show" and 0 or T.QUIET, run) else run() end
  return true
end

-- ------------------------------------------------------------------------------------------------ wiring
local Module = {}
T.module = Module

function Module:OnEnable()
  if cfg().enabled == false then return end
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "PLAYER_LEVEL_UP" }) do pcall(ev.RegisterEvent, ev, e) end
  pcall(ev.RegisterEvent, ev, "TRAINER_CLOSED")
  ev:SetScript("OnEvent", function(_, e, arg1)
    if e == "TRAINER_SHOW" then
      T.shows = (T.shows or 0) + 1
      T.reads, T.quietUntil, T.capped = 0, 0, false
      T.Schedule("show")
    elseif e == "TRAINER_UPDATE" then
      T.updates = (T.updates or 0) + 1
      -- our own read flips the filters and the client answers each flip with TRAINER_UPDATE: never read on that echo
      if T.learning or T.Now() < (T.quietUntil or 0) then T.echoes = (T.echoes or 0) + 1 return end
      T.Schedule("update")
    elseif e == "TRAINER_CLOSED" then
      T.pending = false
    elseif e == "PLAYER_LEVEL_UP" then
      local plan = T.PlanFrom(T.db().spells, num(arg1) or T.Level())
      if cfg().nudge ~= false and #plan.now > 0 then
        HH:Print(("Level %s: %d spell%s waiting at the trainer (%s). /hh train"):format(tostring(arg1), #plan.now, #plan.now == 1 and "" or "s", money(plan.cost)))
      end
      -- the level-up card (LevelUp.lua): what opened with this level
      if cfg().levelCard ~= false and type(T.ShowLevelUp) == "function" then
        local ok, err = pcall(T.ShowLevelUp, num(arg1) or T.Level())
        if not ok then HH:LogError("level-up card: " .. tostring(err)) end
      end
      T.Refresh()
    end
  end)
  Module.events = ev
  T.RegisterDatatext()
end

HH:RegisterModule("Training", Module)

HH:RegisterSlash("traindiag", function()
  local g = HH.db and HH.db.global
  local r = g and g.diag and g.diag.trainerRead
  if type(r) ~= "table" then HH:Print("traindiag: no trainer read yet this session - talk to your class trainer and open its list.") return end
  HH:Print(("traindiag %s: %s at %s - services %s, recorded %s%s"):format(tostring(r.class), tostring(r.trainer), tostring(r.at),
    tostring(r.n), tostring(r.recorded), r.why and (" (" .. r.why .. ")") or ""))
  HH:Print(("events: %s | missing: %s"):format(tostring(r.events), tostring(r.missing)))
  if r.sample and r.sample ~= "" then HH:Print("first services: " .. r.sample) end
end, "what the last class-trainer read got from the client (open the trainer first)")

HH:RegisterSlash("train", function(rest)
  rest = (rest or ""):lower()
  if rest == "say" or rest == "chat" then for _, l in ipairs(T.Lines()) do HH:Print(l) end return end
  if rest == "forget" then local g = HH.db and HH.db.global if g and g.training then g.training[T.Class()] = nil end HH:Print("training: memory for this class cleared.") return end
  T.Toggle()
end, "what's training: spells waiting at the trainer, the ones coming, weapon trainers (/hh train say | forget)")
