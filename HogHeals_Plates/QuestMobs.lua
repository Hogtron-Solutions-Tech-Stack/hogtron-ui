-- Is this nameplate unit part of an open quest objective?
--
-- Two sources, OR-ed:
--  1. The unit's tooltip (C_TooltipInfo.GetUnit): modern clients print quest lines under a quest mob
--     ("- Kobold Vermin slain: 3/8"). This also catches item-drop objectives the mob's NAME never mentions.
--  2. Name match against the quest log's open objectives ("Kobold Vermin slain: 3/8" -> "kobold vermin"), for a
--     client whose tooltips carry no quest lines. Needs HogHeals_Quests (its Data module); skipped without it.
-- Every string is checked for secrecy first: a secret string cannot be matched, so it is skipped, never touched.
-- Results are cached per GUID and dropped whenever the quest log changes.
HogHealsPlates = HogHealsPlates or {}
local HHP = HogHealsPlates

local QM = { cache = {}, gen = 0 }
HHP.QuestMobs = QM

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function str(v) if isSecret(v) or type(v) ~= "string" then return nil end return v end
local function bool(v) if isSecret(v) then return nil end return v and true or false end

local function lineType(key)
  local e = Enum and Enum.TooltipDataLineType
  return type(e) == "table" and e[key] or nil
end

--- Plain { { text, type } } for a unit's tooltip, or nil when the client has no tooltip data API.
function QM.TooltipLines(unit)
  if type(C_TooltipInfo) ~= "table" or type(C_TooltipInfo.GetUnit) ~= "function" then return nil end
  local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
  if not ok or type(data) ~= "table" or isSecret(data) or type(data.lines) ~= "table" then return nil end
  local out = {}
  for _, line in ipairs(data.lines) do
    if type(line) == "table" then
      if line.leftText == nil and type(TooltipUtil) == "table" and type(TooltipUtil.SurfaceArgs) == "function" then
        pcall(TooltipUtil.SurfaceArgs, line)
      end
      local t = str(line.leftText)
      if t then out[#out + 1] = { text = t, type = line.type } end
    end
  end
  return out
end

--- Pure: tooltip lines -> { progress, title } when an open objective is on them, else nil.
-- Line 1 is the unit's own name and is skipped. Lines under another player's name (QuestPlayer) are that
-- player's progress, not ours, and are skipped until the next quest title.
function QM.FromLines(lines, titles)
  if type(lines) ~= "table" then return nil end
  local QO, QT, QP = lineType("QuestObjective"), lineType("QuestTitle"), lineType("QuestPlayer")
  local found, progress, title, others = false, nil, nil, false
  for i = 2, #lines do
    local l = lines[i]
    local text = l.text
    if QP and l.type == QP then others = true
    elseif (QT and l.type == QT) or (titles and titles[text]) then
      others = false
      title = title or text
    elseif not others then
      local have, need = text:match("(%d+)%s*/%s*(%d+)")
      have, need = tonumber(have), tonumber(need)
      if have and need and need > 0 then
        if have < need then found = true; progress = progress or (have .. "/" .. need) end
      elseif QO and l.type == QO then
        found = true                                 -- objective without a count ("Slay Hogger")
      end
    end
  end
  if found then return { progress = progress, title = title, source = "tooltip" } end
  return nil
end

local function logData()
  local HHQ = rawget(_G, "HogHealsQuests")
  return type(HHQ) == "table" and HHQ.Data or nil
end

--- Name match against the open objectives. Pure apart from the Data lookup.
function QM.FromName(name, open)
  name = str(name)
  if not name or type(open) ~= "table" then return nil end
  local hit = open[name:lower()]
  if not hit then return nil end
  local o = hit.objective
  local progress = (o.have and o.need) and (o.have .. "/" .. o.need) or nil
  return { progress = progress, title = hit.quest and hit.quest.title, source = "name" }
end

--- Quest info for a nameplate unit, or nil. Players are never quest mobs.
function QM.Check(unit)
  if bool(UnitIsPlayer and UnitIsPlayer(unit)) ~= false then return nil end   -- player or unknown (secret)
  local guid = str(UnitGUID and UnitGUID(unit))
  local c = guid and QM.cache[guid]
  if c and c.gen == QM.gen then return c.info or nil end
  local Data = logData()
  local titles
  if Data and Data.last then
    titles = {}
    for _, q in ipairs(Data.last) do if q.title and not q.complete then titles[q.title] = true end end
  end
  local info = QM.FromLines(QM.TooltipLines(unit), titles)
  if not info and Data then
    local ok, open = pcall(Data.OpenObjectives)
    if ok then info = QM.FromName(UnitName and UnitName(unit), open) end
  end
  if guid then QM.cache[guid] = { gen = QM.gen, info = info or false } end
  return info
end

--- Quest log changed: every cached answer is stale.
function QM.Invalidate()
  QM.gen = QM.gen + 1
  if QM.gen % 50 == 0 then wipe(QM.cache) end
end
