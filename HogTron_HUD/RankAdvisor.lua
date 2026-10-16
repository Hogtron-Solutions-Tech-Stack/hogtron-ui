-- Rank advisor: lowest spell rank that covers the hovered unit's missing health. Advisory only —
-- secure buttons cannot change rank in combat; /hh rankmacros prints the per-rank macros.
HogHealsHUD = HogHealsHUD or {}
local HHD = HogHealsHUD
local HH = HogHeals

local RankAdvisor = { known = {} }
HHD.RankAdvisor = RankAdvisor

local DEFAULT_SPELLS = {
  PRIEST = { "Greater Heal", "Flash Heal" },
  SHAMAN = { "Healing Wave", "Lesser Healing Wave" },
  PALADIN = { "Holy Light", "Flash of Light" },
  DRUID = { "Healing Touch", "Regrowth" },
}

local function cfg() return HH.db.profile.hud.advisor end

local function flavor()
  local C = HogHealsFrames and HogHealsFrames.Compat
  if C and C.isTBC ~= nil then return C.isTBC and "tbc" or "era" end
  local _, _, _, toc = GetBuildInfo()
  return (math.floor((tonumber(toc) or 0) / 10000) == 2) and "tbc" or "era"
end

local function data(spell)
  local tbl = HHD.HealRanks and HHD.HealRanks[flavor()]
  return tbl and tbl[spell] or nil
end

function RankAdvisor.ParseRank(sub)
  if type(sub) ~= "string" then return nil end
  local n = sub:match("(%d+)")
  return n and tonumber(n) or nil
end

--- Scan the spellbook for known ranks of spells we have data for.
function RankAdvisor.Scan()
  local known = {}
  local i = 1
  -- The global was removed from modern clients (Forever beta: nil call at this line).
  local getName = GetSpellBookItemName
  local book = BOOKTYPE_SPELL or "spell"
  if type(getName) ~= "function" and C_SpellBook and C_SpellBook.GetSpellBookItemName then
    getName = C_SpellBook.GetSpellBookItemName
    book = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
  end
  if type(getName) ~= "function" then RankAdvisor.known = known return known end
  while true do
    local name, sub = getName(i, book)
    if not name then break end
    if data(name) then
      local rank = RankAdvisor.ParseRank(sub) or 1
      known[name] = known[name] or {}
      known[name][#known[name] + 1] = rank
    end
    i = i + 1
    if i > 1024 then break end
  end
  for _, ranks in pairs(known) do table.sort(ranks) end
  RankAdvisor.known = known
  return known
end

local function playerLevel() return UnitLevel("player") or 60 end

--- Expected heal for spell rank with +healing bonus (level penalties applied), or nil if unknown.
function RankAdvisor.Amount(spell, rank, bonus)
  local d = data(spell)
  if not d or not rank or rank < 1 then return nil end
  local r = d.ranks[rank]
  if not r then return nil end
  local coeff = d.coeff or 0
  local penalty = 1
  if r.level < 20 then penalty = penalty * math.max(0, 1 - (20 - r.level) * 0.0375) end
  if flavor() == "tbc" then
    -- TBC downranking: spell-power contribution scales by (spellLevel + 11) / casterLevel, capped at 1.
    penalty = penalty * math.min(1, (r.level + 11) / playerLevel())
  end
  return r.avg + coeff * (bonus or 0) * penalty
end

--- Lowest KNOWN rank whose expected heal >= missing * margin. Falls back to the highest known rank (capped=true).
function RankAdvisor.Pick(spell, missing, bonus, margin)
  if not missing or missing <= 0 then return nil end
  local ranks = RankAdvisor.known[spell]
  if not ranks or #ranks == 0 or not data(spell) then return nil end
  margin = margin or (cfg().margin or 0.9)
  local need = missing * margin
  for _, rank in ipairs(ranks) do
    local amt = RankAdvisor.Amount(spell, rank, bonus)
    if amt and amt >= need then return { rank = rank, amount = amt } end
  end
  local top = ranks[#ranks]
  return { rank = top, amount = RankAdvisor.Amount(spell, top, bonus) or 0, capped = true }
end

local function spellsForClass()
  local _, class = UnitClass("player")
  local c = cfg()
  local list = c.spells and c.spells[class]
  if list and #list > 0 then return list end
  return DEFAULT_SPELLS[class] or {}
end

local function abbrev(name)
  local out = ""
  for word in name:gmatch("%a+") do out = out .. word:sub(1, 1):upper() end
  return out
end

local function fmtAmount(a)
  if a >= 1000 then return ("%.1fk"):format(a / 1000) end
  return tostring(math.floor(a + 0.5))
end

--- Build the advice string for a unit, or "" when nothing to advise.
function RankAdvisor.Advice(unit)
  if not cfg().enabled or not unit or not UnitExists(unit) then return "" end
  -- Picking a rank means comparing heal size with missing health; impossible when health is secret.
  if HH.IsSecret(UnitHealth(unit)) or HH.IsSecret(UnitHealthMax(unit)) then return "" end
  local missing = (UnitHealthMax(unit) or 0) - (UnitHealth(unit) or 0)
  if missing <= 0 or UnitIsDeadOrGhost(unit) then return "" end
  local bonus = GetSpellBonusHealing and GetSpellBonusHealing() or 0
  local parts = {}
  for _, spell in ipairs(spellsForClass()) do
    local pick = RankAdvisor.Pick(spell, missing, bonus, cfg().margin)
    if pick then
      parts[#parts + 1] = ("%s r%d%s (%s)"):format(abbrev(spell), pick.rank, pick.capped and "+" or "", fmtAmount(pick.amount))
    end
  end
  return table.concat(parts, " · ")
end

local function setInfo(text)
  local i = HHD.HUD.rows.info
  if i then i.right:SetText(text or "") end
end

function RankAdvisor.OnHover(button)
  setInfo(RankAdvisor.Advice(button and button.unit))
end

function RankAdvisor.OnUnhover()
  setInfo("")
end

function RankAdvisor.Init()
  if RankAdvisor.frame then return end
  local f = CreateFrame("Frame")
  f:RegisterEvent("SPELLS_CHANGED")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:SetScript("OnEvent", function() pcall(RankAdvisor.Scan) end)
  RankAdvisor.frame = f
  RankAdvisor.Scan()
  -- hook the frames' hover if Frames is loaded
  local UB = HogHealsFrames and HogHealsFrames.UnitButton
  if UB and not RankAdvisor.hooked then
    RankAdvisor.hooked = true
    local origEnter, origLeave = UB.OnEnter, UB.OnLeave
    UB.OnEnter = function(button, ...) if origEnter then origEnter(button, ...) end pcall(RankAdvisor.OnHover, button) end
    UB.OnLeave = function(button, ...) if origLeave then origLeave(button, ...) end pcall(RankAdvisor.OnUnhover) end
  end
end

function RankAdvisor.Refresh() RankAdvisor.Scan() end

HH:RegisterSlash("rankmacros", function()
  RankAdvisor.Scan()
  local any = false
  for _, spell in ipairs(spellsForClass()) do
    for _, rank in ipairs(RankAdvisor.known[spell] or {}) do
      HH:Print(("/cast %s(Rank %d)"):format(spell, rank))
      any = true
    end
  end
  if not any then HH:Print("No known ranks found for your advisor spells.") end
end, "print /cast macros for every known rank of your heals")
