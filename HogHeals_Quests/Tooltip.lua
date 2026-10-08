-- Tooltip: "needed for <quest>" on the mob or item under your mouse - the Questie tooltip, without its database:
-- the quest log's own objective text names the mob ("Kobold Vermin slain: 3/8") and the item ("Boar Meat: 2/6"),
-- so a name match against the log is all it takes. Sean 2026-10-08, Questie clip (quality-of-life half).
--
-- Unit tooltips: GameTooltip OnTooltipSetUnit (classic) or TooltipDataProcessor (modern) - whichever the client has;
-- item tooltips the same way. Lines are cyan "<quest title>  3/8" (green "done" when finished). Match = the
-- objective name equals the unit / item name, case-insensitive, with a trailing "s" forgiven either way (the log
-- says "Kobold Vermin", the mob says "Kobold Vermin"; the log says "Boar Meat", the item says "Boar Meat"). Defers to
-- Questie when loaded. Pure matcher (Tooltip.Matches) for the tests; nothing here touches the tooltip on a miss.
HogHealsQuests = HogHealsQuests or {}
local HHQ = HogHealsQuests
local HH = HogHeals

local TT = { seen = {} }
HHQ.Tooltip = TT

local CYAN, GREEN = "21D4E0", "40CC59"

local function cfg() return HH.db.profile.quests.tooltip or {} end
local function g(name) local f = rawget(_G, name) if type(f) == "function" then return f end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
end
local function count(k) TT.seen[k] = (TT.seen[k] or 0) + 1 end

function TT.Deferring()
  local f = (type(C_AddOns) == "table" and C_AddOns.IsAddOnLoaded) or g("IsAddOnLoaded")
  local ok, loaded = pcall(f or function() end, "Questie")
  return ok and loaded == true
end

-- ------------------------------------------------------------------------------------------------ pure
local function norm(s)
  if type(s) ~= "string" then return nil end
  s = s:lower():gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

--- Does objective name `a` name the thing called `b`? Equal, or equal with one trailing s forgiven.
function TT.SameName(a, b)
  a, b = norm(a), norm(b)
  if not a or not b or a == "" or b == "" then return false end
  if a == b then return true end
  if a:sub(-1) == "s" and a:sub(1, -2) == b then return true end
  if b:sub(-1) == "s" and b:sub(1, -2) == a then return true end
  return false
end

--- Quests in `list` with an objective naming `name`: { { title, have, need, done } }.
function TT.Matches(name, list)
  local out = {}
  for _, q in ipairs(list or {}) do
    for _, o in ipairs(q.objectives or {}) do
      if TT.SameName(o.name, name) then
        out[#out + 1] = { title = q.title, have = o.have, need = o.need, done = o.done and true or false }
        break
      end
    end
  end
  return out
end

--- The tooltip line for one match.
function TT.Line(m)
  local status
  if m.done then status = "|cff" .. GREEN .. "done|r"
  elseif m.have and m.need then status = ("%d/%d"):format(m.have, m.need)
  else status = "" end
  return ("|cff%s%s|r  %s"):format(CYAN, tostring(m.title or "?"), status)
end

-- ------------------------------------------------------------------------------------------------ hooks
local function add(tip, name, kind)
  local o = cfg()
  if o.enabled == false or TT.Deferring() then return 0 end
  if kind == "unit" and o.units == false then return 0 end
  if kind == "item" and o.items == false then return 0 end
  local list = HHQ.Data and (HHQ.Data.last or (HHQ.Data.List and HHQ.Data.List())) or {}
  local matches = TT.Matches(name, list)
  for _, m in ipairs(matches) do
    if tip.AddLine then tip:AddLine(TT.Line(m)) end
  end
  if #matches > 0 then count(kind) if tip.Show then pcall(tip.Show, tip) end end
  return #matches
end

function TT.OnUnit(tip)
  tip = tip or GameTooltip
  local name = call(tip.GetUnit, tip)
  if type(name) ~= "string" then
    -- no GetUnit on this tooltip: the mouseover unit is the next best thing
    name = call(g("UnitName"), "mouseover")
  end
  if type(name) ~= "string" then return 0 end
  return add(tip, name, "unit")
end

function TT.OnItem(tip)
  tip = tip or GameTooltip
  local name = call(tip.GetItem, tip)
  if type(name) ~= "string" then return 0 end
  return add(tip, name, "item")
end

function TT.Start()
  if TT.hooked then return end
  local tip = rawget(_G, "GameTooltip")
  if type(tip) ~= "table" then TT.path = "no GameTooltip" return end
  local TDP = rawget(_G, "TooltipDataProcessor")
  local Enum_ = rawget(_G, "Enum")
  if type(TDP) == "table" and type(TDP.AddTooltipPostCall) == "function" and type(Enum_) == "table" and type(Enum_.TooltipDataType) == "table" then
    pcall(TDP.AddTooltipPostCall, Enum_.TooltipDataType.Unit, function(t) if t == GameTooltip then pcall(TT.OnUnit, t) end end)
    pcall(TDP.AddTooltipPostCall, Enum_.TooltipDataType.Item, function(t) if t == GameTooltip then pcall(TT.OnItem, t) end end)
    TT.path = "TooltipDataProcessor"
  elseif type(tip.HookScript) == "function" then
    pcall(tip.HookScript, tip, "OnTooltipSetUnit", function(t) pcall(TT.OnUnit, t) end)
    pcall(tip.HookScript, tip, "OnTooltipSetItem", function(t) pcall(TT.OnItem, t) end)
    TT.path = "HookScript"
  else
    TT.path = "no hook"
    return
  end
  TT.hooked = true
end

function TT.Lines()
  local o = cfg()
  return { ("quest tooltips: %s%s; units %s, items %s; hook = %s; shown on units %d, items %d"):format(o.enabled == false and "OFF" or "on",
    TT.Deferring() and " (deferring to Questie)" or "", tostring(o.units ~= false), tostring(o.items ~= false), tostring(TT.path), TT.seen.unit or 0, TT.seen.item or 0) }
end
