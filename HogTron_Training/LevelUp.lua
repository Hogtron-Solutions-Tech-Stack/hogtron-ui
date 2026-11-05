-- LevelUp: a small card the moment you level (Sean 2026-11-04: "When we level, I want a small pop-up on what's
-- available to us now as far as training and other things"). Facts only, nothing from memory (the Atlas rule):
--   Training   the spells the trainer memory opens at THIS level and how many older ones still wait (T.PlanFrom);
--              before the first trainer visit the card says so instead
--   Dungeons   dungeons whose level range starts at this level (HogTron UI Atlas: its old-game list, labelled there);
--              the other faction's are left out
--   Talents    unspent talent points when the client reports them (UnitCharacterPoints / GetUnspentTalentPoints)
-- Buttons: Train (/hh train), Where next (/hh next, when Atlas is loaded), x. Goes on its own after
-- training.cardSeconds. /hh levelup [level] shows it for your level (or the one given) without levelling.
-- Off: training.levelCard = false (Training tab). The chat nudge (training.nudge) is separate and stays.
HogHealsTraining = HogHealsTraining or {}
local T = HogHealsTraining
local HH = HogHeals

local CYAN, CREAM, GREY, GREEN, AMBER = { 0.13, 0.83, 0.88 }, { 0.96, 0.92, 0.86 }, { 0.55, 0.55, 0.60 }, { 0.25, 0.80, 0.35 }, { 0.95, 0.65, 0.15 }
local INK = { 0.07, 0.07, 0.09 }

local function cfg() local p = HH.db and HH.db.profile return (p and p.training) or {} end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c = pcall(f, ...)
  if ok then return a, b, c end
end
local function G(name) return rawget(_G, name) end
local function label(s) return s.rank and s.rank ~= "" and (s.name .. " (" .. s.rank .. ")") or s.name end

-- ------------------------------------------------------------------------------------------------ facts
--- Dungeons whose level range starts at `level` (Atlas data), shared or your faction's. {} without Atlas.
function T.DungeonsOpening(level, side)
  local A = G("HogHealsAtlas")
  local out = {}
  if type(A) ~= "table" or type(A.Levels) ~= "table" or type(A.Levels.For) ~= "function" or type(A.Data) ~= "table" then return out end
  for _, d in ipairs(A.Data.Dungeons or {}) do
    local min, max = call(A.Levels.For, d)
    if num(min) == level and not (d.faction and side and d.faction ~= side) then
      out[#out + 1] = { key = d.key, name = d.name, min = min, max = num(max) or min }
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

--- Unspent talent points when the client tells; nil when it does not.
function T.TalentPoints()
  local n = num(call(G("UnitCharacterPoints"), "player"))
  if n == nil then n = num(call(G("GetUnspentTalentPoints"))) end
  return n
end

--- Everything the card says for a level, as data:
-- { level, training = { new, waiting, cost, learned }, dungeons = { { key, name, min, max } }, talents }.
function T.LevelUpFacts(level)
  level = num(level) or T.Level()
  local db = T.db()
  local plan = T.PlanFrom(db.spells, level)
  local new, waiting = {}, 0
  for _, s in ipairs(plan.now) do
    if (s.level or 0) == level then new[#new + 1] = s else waiting = waiting + 1 end
  end
  return { level = level, training = { new = new, waiting = waiting, cost = plan.cost, learned = (db.visits or 0) > 0 },
    dungeons = T.DungeonsOpening(level, T.Side()), talents = T.TalentPoints() }
end

local MAX_NAMES = 6

--- The card's lines for the facts: { { text, colour } ... }. Pure.
function T.LevelUpLines(f)
  local out = {}
  local tr = f.training
  if not tr.learned then
    out[#out + 1] = { "Training: open your class trainer once and this remembers every spell and price.", GREY }
  elseif #tr.new > 0 then
    local names = {}
    for i, s in ipairs(tr.new) do if i <= MAX_NAMES then names[#names + 1] = label(s) end end
    local line = "Train now: " .. table.concat(names, ", ") .. (#tr.new > MAX_NAMES and (" +" .. (#tr.new - MAX_NAMES)) or "")
    if tr.waiting > 0 then line = line .. ("  (+%d still waiting)"):format(tr.waiting) end
    out[#out + 1] = { line .. "  -  " .. T.Money(tr.cost), GREEN }
  elseif tr.waiting > 0 then
    out[#out + 1] = { ("Training: nothing new this level; %d spell%s still waiting at the trainer (%s)."):format(
      tr.waiting, tr.waiting == 1 and "" or "s", T.Money(tr.cost)), CREAM }
  else
    out[#out + 1] = { "Training: nothing waiting at the trainer.", GREY }
  end
  if #f.dungeons > 0 then
    local names = {}
    for _, d in ipairs(f.dungeons) do names[#names + 1] = ("%s (%d-%d)"):format(d.name, d.min, d.max) end
    out[#out + 1] = { "Now in range: " .. table.concat(names, ", "), CYAN }
  end
  if f.talents and f.talents > 0 then
    out[#out + 1] = { ("%d talent point%s to spend."):format(f.talents, f.talents == 1 and "" or "s"), AMBER }
  end
  return out
end

-- ------------------------------------------------------------------------------------------------ the card
local WIDTH, LINE_H, MAX_LINES = 460, 16, 4

local function fs(parent, color, justify, template)
  local t = parent:CreateFontString(nil, "OVERLAY", template or "HogTronFontSmall")
  t:SetTextColor(color[1], color[2], color[3])
  t:SetJustifyH(justify or "LEFT")
  if t.SetWordWrap then t:SetWordWrap(false) end
  return t
end

local function button(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, 20)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints(b)
  b.bg:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.18)
  b.label = fs(b, CREAM, "CENTER")
  b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.label:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

function T.BuildCard()
  if T.card then return T.card end
  local f = CreateFrame("Frame", "HogTronUILevelUpCard", UIParent)
  f:SetSize(WIDTH, 100)
  f:SetPoint("TOP", UIParent, "TOP", 0, -140)
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
  f.title = fs(f, CREAM, "LEFT", "HogTronFontNormal")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -6)
  f.close = button(f, "x", 22, function() f:Hide() end)
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -2)
  f.lines = {}
  for i = 1, MAX_LINES do
    local l = fs(f, CREAM, "LEFT")
    l:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30 - (i - 1) * LINE_H)
    l:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.lines[i] = l
  end
  f.train = button(f, "Train", 70, function() f:Hide() T.Toggle() end)
  f.train:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)
  f.next = button(f, "Where next", 90, function() f:Hide() HH:SlashCommand("next") end)
  f.next:SetPoint("LEFT", f.train, "RIGHT", 8, 0)
  local special = G("UISpecialFrames")
  if type(special) == "table" then special[#special + 1] = "HogTronUILevelUpCard" end
  f:Hide()
  T.card = f
  return f
end

--- Show the card for a level (yours when nil). Returns the lines it shows.
function T.ShowLevelUp(level)
  local facts = T.LevelUpFacts(level)
  local lines = T.LevelUpLines(facts)
  local f = T.BuildCard()
  f.title:SetText(("|cffF5EBDCLEVEL|r |cff21D4E0%d|r"):format(facts.level))
  for i, l in ipairs(f.lines) do
    local row = lines[i]
    if row then l:SetText(row[1]) l:SetTextColor(row[2][1], row[2][2], row[2][3]) l:Show() else l:SetText("") l:Hide() end
  end
  local n = math.max(1, math.min(#lines, MAX_LINES))
  f:SetHeight(30 + n * LINE_H + 36)
  if G("HogHealsAtlas") then f.next:Show() else f.next:Hide() end
  T.cardShows = (T.cardShows or 0) + 1
  local stamp = T.cardShows
  f.level = facts.level
  f:Show()
  local secs = num(cfg().cardSeconds) or 30
  if secs > 0 and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(secs, function() if T.cardShows == stamp and f:IsShown() then f:Hide() end end)
  end
  T.lastCard = { level = facts.level, lines = lines }
  return lines
end

HH:RegisterSlash("levelup", function(rest)
  local lv = tonumber((rest or ""):match("%d+"))
  T.ShowLevelUp(lv)
end, "the level-up card for your level (or '/hh levelup 30' for level 30)")

-- ------------------------------------------------------------------------------------------------ options tab
function T.module:GetOptions()
  local function c() return HH.db.profile.training end
  local function toggle(key, name, order, desc)
    return { type = "toggle", name = name, desc = desc, order = order,
      get = function() return c()[key] and true or false end,
      set = function(_, v) c()[key] = v and true or false end }
  end
  return {
    type = "group", name = "Training", order = 38,
    args = {
      about = { type = "description", order = 0, name = "What's training: learned at your class trainer, answered anywhere (/hh train). The level-up card shows what opened with the level: spells to train, dungeons now in range, talent points." },
      nudge = toggle("nudge", "Chat line on level-up", 1, "\"Level 22: 3 spells waiting at the trainer\" in chat."),
      levelCard = toggle("levelCard", "Level-up card", 2, "A small card when you level: what to train now, dungeons now in range, talent points. /hh levelup previews it."),
      cardSeconds = { type = "range", name = "Card stays (seconds)", order = 3, min = 5, max = 120, step = 5,
        get = function() return c().cardSeconds or 30 end, set = function(_, v) c().cardSeconds = v end },
      preview = { type = "execute", name = "Show the card now", order = 4, func = function() T.ShowLevelUp() end },
    },
  }
end
