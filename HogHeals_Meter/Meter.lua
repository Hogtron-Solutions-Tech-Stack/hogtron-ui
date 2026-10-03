-- HogHeals Meter: our window over Blizzard's damage-meter data.
--
-- On restricted-API clients (WoW: Forever beta) addons get no combat log; the only meter data is what the client
-- exposes through C_DamageMeter, and every amount in it is a SECRET value: we may show it, we may not sort it,
-- compare it or divide by it. So this module never does arithmetic on amounts. Blizzard hands the sources back
-- already ranked; bar lengths come from a StatusBar whose max is the top amount and whose value is this row's
-- amount (the client scales secrets itself); numbers are printed with AbbreviateNumbers / format.
--
-- The exact table shape of a session is read defensively (see readSession) and reported ONCE to the diag log if
-- nothing usable is found, so a client with a different layout degrades to an empty window, not an error storm.
HogHealsMeter = HogHealsMeter or {}
local HHM = HogHealsMeter
local HH = HogHeals
local ns = select(2, ...)
local P = ns and ns.palette or {}

local Meter = { rows = {} }
HHM.Meter = Meter

local CREAM = P.cream or { 0.96, 0.92, 0.86 }
local CYAN = P.cyan or { 0.13, 0.83, 0.88 }
local INK = P.ink or { 0.07, 0.07, 0.09 }
local GREY = P.grey or { 0.45, 0.45, 0.5 }
local LINE = { 0.20, 0.20, 0.25 }

-- Blizzard's meter types, in the order they appear in our mode menu.
Meter.MODES = {
  { key = "DamageDone", label = "Damage", per = "Dps" },
  { key = "Dps", label = "DPS" },
  { key = "HealingDone", label = "Healing", per = "Hps" },
  { key = "Hps", label = "HPS" },
  { key = "Absorbs", label = "Absorbs" },
  { key = "DamageTaken", label = "Damage taken" },
  { key = "Interrupts", label = "Interrupts" },
  { key = "Dispels", label = "Dispels" },
  { key = "Deaths", label = "Deaths" },
}
Meter.SEGMENTS = { { key = "Current", label = "Current" }, { key = "Overall", label = "Overall" } }

local function cfg() return HH.db.profile.meter end

local function modeInfo(key)
  for _, m in ipairs(Meter.MODES) do if m.key == key then return m end end
  return Meter.MODES[1]
end

-- ------------------------------------------------------------------------------------------------ data
local function isSecret(v) return HH.IsSecret and HH.IsSecret(v) or false end

--- Enum lookups that survive a client where the enum is missing or named differently.
local function enumValue(enumName, key, fallback)
  local e = Enum and Enum[enumName]
  if type(e) == "table" and e[key] ~= nil then return e[key] end
  return fallback
end

--- Fetch a session for (segment, mode). Tries the documented two-argument form (sessionType, meterType) first,
-- then meterType alone, and remembers which one the client accepted.
local function fetchSession(segmentKey, modeKey)
  local api = C_DamageMeter
  if type(api) ~= "table" or type(api.GetCombatSessionFromType) ~= "function" then return nil, "no C_DamageMeter" end
  local meterType = enumValue("DamageMeterType", modeKey, nil)
  if meterType == nil then return nil, "no Enum.DamageMeterType." .. tostring(modeKey) end
  local sessionType = enumValue("DamageMeterSessionType", segmentKey, segmentKey == "Overall" and 1 or 0)
  if Meter.callForm ~= "single" then
    local ok, r = pcall(api.GetCombatSessionFromType, sessionType, meterType)
    if ok and type(r) == "table" then Meter.callForm = "double" return r end
    if Meter.callForm == "double" then return nil, "call failed: " .. tostring(r) end
  end
  local ok, r = pcall(api.GetCombatSessionFromType, meterType)
  if ok and type(r) == "table" then Meter.callForm = "single" return r end
  return nil, "call failed: " .. tostring(r)
end

local NAME_KEYS = { "name", "sourceName", "unitName", "playerName" }
local CLASS_KEYS = { "classFilename", "classFile", "class", "className" }
local AMOUNT_KEYS = { "totalAmount", "amount", "total", "value" }
local PER_KEYS = { "amountPerSecond", "perSecond", "rate", "dps", "hps" }

local function pick(t, keys)
  for _, k in ipairs(keys) do if t[k] ~= nil then return t[k] end end
end

--- Find the per-player list inside a session table without assuming its field name: the first array whose
-- elements are tables carrying something name-like.
-- Measured on the Forever beta 2026-09-17 (diag.client.meter):
--   GetCombatSessionFromType(sessionType, type) -> { combatSources = { { name, classFilename, totalAmount,
--   amountPerSecond, sourceGUID, specIconID, isLocalPlayer, classification, deathRecapID, deathTimeSeconds,
--   sourceDisplayType } ... }, durationSeconds, maxAmount, totalAmount }
--   Enum.DamageMeterSessionType = { Overall = 0, Current = 1, Expired = 2 }
local function findSources(session)
  if type(session) ~= "table" then return nil end
  for _, key in ipairs({ "combatSources", "sources", "entries", "players" }) do
    local v = session[key]
    if type(v) == "table" and not isSecret(v) then return v, key end      -- may legitimately be EMPTY (no fight yet)
  end
  for key, v in pairs(session) do
    if type(v) == "table" and not isSecret(v) and type(v[1]) == "table" and pick(v[1], NAME_KEYS) ~= nil then return v, key end
  end
  return nil
end

--- Normalise one session into { title, sources = { { name, class, amount, per } } }.
-- Returns nil, reason when the shape is not understood.
function Meter.ReadSession(session)
  local list, key = findSources(session)
  if not list then return nil, "no source list in session (fields: " .. Meter.DescribeKeys(session) .. ")" end
  local out = {}
  for i, src in ipairs(list) do
    if type(src) == "table" then
      local name = pick(src, NAME_KEYS)
      out[#out + 1] = {
        name = name ~= nil and tostring(name) or ("#" .. i),
        class = pick(src, CLASS_KEYS),
        amount = pick(src, AMOUNT_KEYS),
        per = pick(src, PER_KEYS),
        guid = src.sourceGUID or src.guid or src.GUID,
        index = i,
      }
    end
  end
  return { sources = out, listKey = key, encounter = session.encounterName or session.name, maxAmount = session.maxAmount }
end

function Meter.DescribeKeys(t)
  local keys = {}
  if type(t) == "table" then for k, v in pairs(t) do keys[#keys + 1] = tostring(k) .. ":" .. type(v) end end
  table.sort(keys)
  return table.concat(keys, ",")
end

-- ------------------------------------------------------------------------------------------------ one source
-- Sean 2026-10-02: "hover over or click the damage and healing meters and see what spells contributed". The client
-- has GetCombatSessionSourceFromType / FromID (keys measured 2026-10-02); the shape of what they return is NOT
-- measured, so it is read the way sessions are: the spell list is the first array of tables carrying a spell-like
-- name, every field is picked from a list of candidate names, amounts stay secrets (printed, never compared),
-- and the first shape seen is written to diag.meter.source so the SV tells us what the client really sends.
local SPELL_LIST_KEYS = { "combatSpells", "spells", "abilities", "entries", "sources" }
local SPELL_NAME_KEYS = { "spellName", "name", "abilityName" }
local SPELL_ID_KEYS = { "spellID", "spellId", "id" }
local SPELL_ICON_KEYS = { "spellIcon", "icon", "iconFileID", "iconID", "texture" }
local SPELL_COUNT_KEYS = { "hitCount", "count", "casts", "numHits", "hits" }

--- The client's detail table for one source of the current (segment, mode), or nil, reason.
function Meter.FetchSource(segmentKey, modeKey, src, session)
  local api = C_DamageMeter
  if type(api) ~= "table" then return nil, "no C_DamageMeter" end
  local guid = src and (src.guid or src.sourceGUID)
  if guid == nil then return nil, "source has no GUID" end
  local meterType = enumValue("DamageMeterType", modeKey, nil)
  local sessionType = enumValue("DamageMeterSessionType", segmentKey, segmentKey == "Overall" and 1 or 0)
  -- in game 2026-10-02 (tooltip): both GUID shapes answered "bad argument #2" - the client wants something else
  -- there; the source's position in the list and its name are tried too, and every failure is kept IN FULL
  -- (the client's usage string names the real signature) in Meter.sourceTries / diag.meter.sourceTries.
  local tries = {}
  local idx, name = src.index, src.name
  if type(api.GetCombatSessionSourceFromType) == "function" then
    local f = api.GetCombatSessionSourceFromType
    tries[#tries + 1] = { "type3", f, sessionType, meterType, guid }
    tries[#tries + 1] = { "type2", f, meterType, guid }
    if idx then tries[#tries + 1] = { "type3i", f, sessionType, meterType, idx } tries[#tries + 1] = { "type2i", f, meterType, idx } end
    tries[#tries + 1] = { "typeG2", f, sessionType, guid }
    if name then tries[#tries + 1] = { "type3n", f, sessionType, meterType, name } end
  end
  local sid = type(session) == "table" and (session.sessionID or session.id) or nil
  if sid ~= nil and type(api.GetCombatSessionSourceFromID) == "function" then
    local f = api.GetCombatSessionSourceFromID
    tries[#tries + 1] = { "id3", f, sid, meterType, guid }
    tries[#tries + 1] = { "id2", f, sid, guid }
    if idx then tries[#tries + 1] = { "id3i", f, sid, meterType, idx } end
  end
  if Meter.sourceForm then
    for _, t in ipairs(tries) do
      if t[1] == Meter.sourceForm then
        local ok, r = pcall(t[2], t[3], t[4], t[5])
        if ok and type(r) == "table" then return r end
        break
      end
    end
  end
  local last, errs = nil, {}
  local function record()   -- what failed and with which arguments: in memory and, once, on disk
    if #errs == 0 then return end
    Meter.sourceTries = table.concat(errs, " | ")
    local g = HH.db and HH.db.global
    if g and not Meter.sourceTriesLogged then
      Meter.sourceTriesLogged = true
      g.diag = g.diag or {} g.diag.meter = g.diag.meter or {}
      g.diag.meter.sourceTries = Meter.sourceTries
      g.diag.meter.sourceArgs = ("sessionType=%s meterType=%s guid=%s idx=%s name=%s sessionKeys=%s"):format(tostring(sessionType), tostring(meterType), tostring(guid), tostring(idx), tostring(name), Meter.DescribeKeys(session))
    end
  end
  for _, t in ipairs(tries) do
    local ok, r = pcall(t[2], t[3], t[4], t[5])
    if ok and type(r) == "table" then
      Meter.sourceForm = t[1]
      record()
      return r
    end
    last = ok and ("returned " .. type(r)) or tostring(r)
    errs[#errs + 1] = t[1] .. ": " .. last
  end
  record()
  return nil, (#tries == 0) and "no per-source call on this client" or ("call failed: " .. tostring(last))
end

local function findSpells(detail)
  if type(detail) ~= "table" then return nil end
  for _, key in ipairs(SPELL_LIST_KEYS) do
    local v = detail[key]
    if type(v) == "table" and not isSecret(v) then return v, key end
  end
  for key, v in pairs(detail) do
    if type(v) == "table" and not isSecret(v) and type(v[1]) == "table" and (pick(v[1], SPELL_NAME_KEYS) ~= nil or pick(v[1], SPELL_ID_KEYS) ~= nil) then return v, key end
  end
  return nil
end

local function spellIcon(entry)
  local icon = pick(entry, SPELL_ICON_KEYS)
  if icon ~= nil then return icon end
  local id = pick(entry, SPELL_ID_KEYS)
  if type(id) == "number" and not isSecret(id) then
    if type(C_Spell) == "table" and type(C_Spell.GetSpellTexture) == "function" then
      local ok, t = pcall(C_Spell.GetSpellTexture, id)
      if ok and t ~= nil then return t end
    end
    if type(GetSpellTexture) == "function" then
      local ok, t = pcall(GetSpellTexture, id)
      if ok and t ~= nil then return t end
    end
  end
  return nil
end

--- Normalise a detail table into { spells = { { name, icon, amount, per, count } }, maxAmount }. nil, reason otherwise.
function Meter.ReadSource(detail)
  local list, key = findSpells(detail)
  if not list then return nil, "no spell list in source (fields: " .. Meter.DescribeKeys(detail) .. ")" end
  local out = {}
  for i, e in ipairs(list) do
    if type(e) == "table" then
      local name = pick(e, SPELL_NAME_KEYS)
      if name == nil then
        local id = pick(e, SPELL_ID_KEYS)
        if type(id) == "number" and not isSecret(id) and type(C_Spell) == "table" and type(C_Spell.GetSpellName) == "function" then
          local ok, n = pcall(C_Spell.GetSpellName, id) if ok then name = n end
        end
      end
      out[#out + 1] = { name = name ~= nil and tostring(name) or ("spell #" .. i), icon = spellIcon(e), amount = pick(e, AMOUNT_KEYS), per = pick(e, PER_KEYS), count = pick(e, SPELL_COUNT_KEYS) }
    end
  end
  return { spells = out, listKey = key, maxAmount = detail.maxAmount, totalAmount = detail.totalAmount }
end

--- The spells of one row's source: { spells, maxAmount } or nil, reason. Records the first shape seen to the diag.
function Meter.SpellsFor(src)
  local d = cfg()
  local session = fetchSession(d.segment or "Current", d.mode or "DamageDone")
  local detail, why = Meter.FetchSource(d.segment or "Current", d.mode or "DamageDone", src, session)
  if not detail then return nil, why end
  local data, reason = Meter.ReadSource(detail)
  local g = HH.db and HH.db.global
  if g and not Meter.sourceShapeLogged then
    Meter.sourceShapeLogged = true
    g.diag = g.diag or {} g.diag.meter = g.diag.meter or {}
    local first = data and data.spells[1] and findSpells(detail)
    g.diag.meter.source = ("form=%s keys=%s spell1=%s"):format(tostring(Meter.sourceForm), Meter.DescribeKeys(detail), first and Meter.DescribeKeys(first[1]) or "-")
  end
  return data, reason
end

-- ------------------------------------------------------------------------------------------------ text
local function fmtAmount(v)
  if v == nil then return "" end
  if type(AbbreviateNumbers) == "function" then
    local ok, s = pcall(AbbreviateNumbers, v)
    if ok and s ~= nil then return tostring(s) end
  end
  if isSecret(v) then return tostring(v) end
  v = tonumber(v) or 0
  if v >= 1e6 then return ("%.1fm"):format(v / 1e6) end
  if v >= 1e3 then return ("%.1fk"):format(v / 1e3) end
  return ("%d"):format(v)
end

local function fmtPer(v)
  if v == nil then return nil end
  if isSecret(v) then
    local ok, s = pcall(string.format, "%.0f", v)
    if ok then return s end
    return tostring(v)
  end
  return ("%.0f"):format(tonumber(v) or 0)
end

-- ------------------------------------------------------------------------------------------------ window
local function solid(parent, layer, c, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  return t
end

local function text(parent, template, c, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  fs:SetTextColor(c[1], c[2], c[3])
  if justify then fs:SetJustifyH(justify) end
  return fs
end

local function applyFont(fs, size)
  local font, _, flags = fs:GetFont()
  if font and fs.SetFont then fs:SetFont(font, size, flags or "OUTLINE") end
end

--- Class token for a meter row. The session may carry it under several names or as a class ID; when it carries
-- nothing usable, look the player up in the group by name (names are not secret on this client).
local function classToken(src)
  local c = src.class
  if type(c) == "number" and type(GetClassInfo) == "function" then
    local ok, _, file = pcall(GetClassInfo, c)
    if ok and file then return file end
  end
  if type(c) == "string" and c ~= "" then
    local up = c:upper():gsub(" ", "")
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[up] then return up end
  end
  local name = src.name
  if type(name) ~= "string" then return nil end
  local short = name:match("^([^%-]+)") or name
  local function try(unit)
    if UnitExists and UnitExists(unit) then
      local n = UnitName(unit)
      if n == name or n == short then
        local _, file = UnitClass(unit)
        return file
      end
    end
  end
  local r = try("player")
  if r then return r end
  local n = type(GetNumGroupMembers) == "function" and GetNumGroupMembers() or 0
  local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
  for i = 1, math.max(n, 4) do
    r = try(prefix .. i)
    if r then return r end
  end
  return nil
end

local function classColor(class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return c.r, c.g, c.b end
  return 0.55, 0.55, 0.6
end

local function newRow(i)
  local f = Meter.frame
  local d = cfg()
  local row = CreateFrame("Frame", nil, f.body)
  row:SetHeight(d.barHeight or 18)
  row:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -(i - 1) * ((d.barHeight or 18) + 1))
  row:SetPoint("RIGHT", f.body, "RIGHT", 0, 0)
  row.bar = CreateFrame("StatusBar", nil, row)
  row.bar:SetAllPoints(row)
  row.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  row.bar:SetMinMaxValues(0, 1)
  row.bar:SetValue(0)
  row.bar.bg = solid(row.bar, "BACKGROUND", { 0.11, 0.11, 0.14 }, 0.9)
  row.bar.bg:SetAllPoints(row.bar)
  row.overlay = CreateFrame("Frame", nil, row)
  row.overlay:SetAllPoints(row)
  row.overlay:SetFrameLevel(row.bar:GetFrameLevel() + 2)
  row.icon = row.overlay:CreateTexture(nil, "ARTWORK")
  row.icon:SetPoint("LEFT", row.overlay, "LEFT", 2, 0)
  row.icon:SetSize((d.barHeight or 18) - 4, (d.barHeight or 18) - 4)
  row.icon:Hide()
  row.name = text(row.overlay, "GameFontHighlightSmall", CREAM, "LEFT")
  row.name:SetPoint("LEFT", row.overlay, "LEFT", 4, 0)
  row.value = text(row.overlay, "GameFontHighlightSmall", CREAM, "RIGHT")
  row.value:SetPoint("RIGHT", row.overlay, "RIGHT", -4, 0)
  applyFont(row.name, d.fontSize or 12)
  applyFont(row.value, d.fontSize or 12)
  row.index = i
  row:EnableMouse(true)
  row:SetScript("OnEnter", function(self)
    row.bar.bg:SetColorTexture(0.16, 0.16, 0.20, 0.95)
    Meter.ShowTooltip(self)
  end)
  row:SetScript("OnLeave", function()
    row.bar.bg:SetColorTexture(0.11, 0.11, 0.14, 0.9)
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
  end)
  row:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" or Meter.drill then Meter.DrillOut() else Meter.DrillIn(self.src) end
  end)
  row:Hide()
  return row
end

--- Tooltip for a player row: the spells behind the number. In the drill view a spell row gets its own line.
function Meter.ShowTooltip(row)
  if not GameTooltip or not GameTooltip.SetOwner then return end
  if Meter.drill then
    local sp = row.spell
    if not sp then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(sp.name, CREAM[1], CREAM[2], CREAM[3])
    local cnt = fmtPer(sp.count)
    if cnt then GameTooltip:AddDoubleLine("Hits / ticks", cnt, GREY[1], GREY[2], GREY[3], CREAM[1], CREAM[2], CREAM[3]) end
    GameTooltip:Show()
    return
  end
  local src = row.src
  if not src then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(("%s  ·  %s"):format(src.name, modeInfo(cfg().mode).label), CYAN[1], CYAN[2], CYAN[3])
  local data, why = Meter.SpellsFor(src)
  if not data or #data.spells == 0 then
    GameTooltip:AddLine(data and "No spells recorded" or ("No spell breakdown: " .. tostring(why)), GREY[1], GREY[2], GREY[3], true)
  else
    for i, sp in ipairs(data.spells) do
      if i > (cfg().tooltipSpells or 8) then break end
      local right = fmtAmount(sp.amount)
      local cnt = fmtPer(sp.count)
      if cnt then right = right .. "  (" .. cnt .. ")" end
      GameTooltip:AddDoubleLine(sp.name, right, CREAM[1], CREAM[2], CREAM[3], CREAM[1], CREAM[2], CREAM[3])
    end
    GameTooltip:AddLine("click: spell bars    right-click: back", GREY[1], GREY[2], GREY[3])
  end
  GameTooltip:Show()
end

local function build()
  if Meter.frame then return Meter.frame end
  local d = cfg()
  -- NOT "HogHeals Meter": a named frame becomes a global of that name and would overwrite the namespace table.
  local f = CreateFrame("Frame", "HogHealsMeterFrame", UIParent)
  f:SetSize(d.width or 240, 200)
  f:SetPoint(d.point or "CENTER", UIParent, d.point or "CENTER", d.x or 400, d.y or -200)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:SetFrameStrata("MEDIUM")
  f.bg = solid(f, "BACKGROUND", INK, d.backgroundAlpha or 0.85)
  f.bg:SetAllPoints(f)
  -- 1 px outline (Details-style panel). Four edge textures; no BackdropTemplate (differs between client generations).
  f.edges = {}
  local spec = { { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }
  for i, sp in ipairs(spec) do
    local e = solid(f, "BORDER", LINE)
    e:SetPoint(sp[1], f, sp[1], 0, 0)
    e:SetPoint(sp[2], f, sp[2], 0, 0)
    if sp[3] then e:SetWidth(sp[3]) end
    if sp[4] then e:SetHeight(sp[4]) end
    f.edges[i] = e
  end

  local header = CreateFrame("Button", nil, f)
  header:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  header:SetHeight(20)
  header.bg = solid(header, "BACKGROUND", { 0.11, 0.11, 0.14 })
  header.bg:SetAllPoints(header)
  header.rule = solid(header, "ARTWORK", CYAN)
  header.rule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
  header.rule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
  header.rule:SetHeight(1)
  header:RegisterForDrag("LeftButton")
  header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  header:SetScript("OnDragStart", function() if not HH.db.profile.locked then f:StartMoving() end end)
  header:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local point, _, _, x, y = f:GetPoint(1)
    if point then d.point, d.x, d.y = point, x, y end
  end)
  header:SetScript("OnClick", function(_, button)
    if Meter.drill then Meter.DrillOut() return end
    if button == "RightButton" then Meter.CycleSegment() else Meter.CycleMode() end
  end)
  f.header = header
  f.title = text(header, "GameFontHighlightSmall", CYAN, "LEFT")
  f.title:SetPoint("LEFT", header, "LEFT", 6, 0)
  f.hint = text(header, "GameFontHighlightSmall", GREY, "RIGHT")
  f.hint:SetPoint("RIGHT", header, "RIGHT", -6, 0)
  f.hint:SetText("L: mode  R: segment")

  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 2, -2)
  f.body:SetPoint("RIGHT", f, "RIGHT", -2, 0)
  f.body:SetHeight(10)

  f.empty = text(f.body, "GameFontHighlightSmall", GREY, "CENTER")
  f.empty:SetPoint("TOP", f.body, "TOP", 0, -6)
  f.empty:SetText("No data yet")
  f.empty:Hide()

  Meter.frame = f
  return f
end

local function layout(count)
  local f, d = Meter.frame, cfg()
  local h = d.barHeight or 18
  -- Details-style panel: a fixed number of slots whether or not anyone is on the meter (tester: "a full background
  -- outline, not only when people are in my party").
  local n = (d.fixedHeight ~= false) and (d.maxBars or 10) or math.max(count, 1)
  f.body:SetHeight(n * (h + 1))
  f:SetSize(d.width or 240, 20 + 2 + n * (h + 1) + 2)
  for _, e in ipairs(f.edges or {}) do if d.border ~= false then e:Show() else e:Hide() end end
  local iconSize = h - 4
  for i, row in ipairs(Meter.rows) do
    applyFont(row.name, d.fontSize or 12)
    applyFont(row.value, d.fontSize or 12)
    row.icon:SetSize(iconSize, iconSize)
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row.overlay, "LEFT", (d.classIcons ~= false) and (iconSize + 6) or 4, 0)
    row:SetHeight(h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -(i - 1) * (h + 1))
    row:SetPoint("RIGHT", f.body, "RIGHT", 0, 0)
  end
end

-- ------------------------------------------------------------------------------------------------ update
local function setTitle(sessionName)
  local d = cfg()
  local f = Meter.frame
  if Meter.drill then
    f.title:SetText(("< %s  ·  %s"):format(tostring(Meter.drill.name), modeInfo(d.mode).label))
    f.hint:SetText("click: back")
    return
  end
  f.hint:SetText("L: mode  R: segment")
  local seg = d.segment == "Overall" and "Overall" or "Current"
  if sessionName and sessionName ~= "" then seg = seg .. ": " .. tostring(sessionName) end
  f.title:SetText(("%s  ·  %s"):format(modeInfo(d.mode).label, seg))
end

--- Drill into one player: the rows become that player's spells until DrillOut (header / right-click).
function Meter.DrillIn(src)
  if not src then return end
  Meter.drill = { name = src.name, guid = src.guid, src = src }
  if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
  Meter.Update()
end

function Meter.DrillOut()
  Meter.drill = nil
  if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
  Meter.Update()
end

--- One spell per row: icon, name, amount; bar scaled by the widget against the biggest spell.
local function paintSpellRows(data)
  local f, d = Meter.frame, cfg()
  local max = d.maxBars or 10
  local top = data.maxAmount or (data.spells[1] and data.spells[1].amount)
  local shown = 0
  for i, sp in ipairs(data.spells) do
    if i > max then break end
    local row = Meter.rows[i] or newRow(i)
    Meter.rows[i] = row
    row.src, row.spell = nil, sp
    row.name:SetText(("%d. %s"):format(i, sp.name))
    local amount = fmtAmount(sp.amount)
    local cnt = fmtPer(sp.count)
    row.value:SetText(cnt and (amount .. "  (" .. cnt .. ")") or amount)
    row.bar:SetStatusBarColor(CYAN[1] * 0.8, CYAN[2] * 0.8, CYAN[3] * 0.8)
    if d.classIcons ~= false and sp.icon ~= nil then
      row.icon:SetTexture(sp.icon)
      row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      row.icon:Show()
    else
      row.icon:Hide()
    end
    if sp.amount ~= nil and top ~= nil then
      row.bar:SetMinMaxValues(0, top)
      row.bar:SetValue(sp.amount)
    else
      row.bar:SetMinMaxValues(0, 1)
      row.bar:SetValue(0)
    end
    row:Show()
    shown = shown + 1
  end
  for i = shown + 1, #Meter.rows do Meter.rows[i]:Hide() end
  return shown
end

--- The drill view: this player's spells, or the reason there are none.
function Meter.UpdateDrill()
  local f = build()
  setTitle()
  local data, why = Meter.SpellsFor(Meter.drill.src)
  if not data or #data.spells == 0 then
    for _, row in ipairs(Meter.rows) do row:Hide() end
    f.empty:SetText(data and "No spells recorded" or ("No spell breakdown: " .. tostring(why)))
    f.empty:Show()
    layout(1)
    return 0
  end
  f.empty:Hide()
  local shown = paintSpellRows(data)
  layout(shown)
  return shown
end

--- Pull the current session and repaint. Never throws: shape problems are logged once per shape.
function Meter.Update()
  if Meter.unavailable then return end
  if Meter.drill then return Meter.UpdateDrill() end
  local f = build()
  local d = cfg()
  setTitle()
  f.empty:SetText("No data yet")
  local session, why = fetchSession(d.segment or "Current", d.mode or "DamageDone")
  local data, reason
  if session then data, reason = Meter.ReadSession(session) else reason = why end
  local max = d.maxBars or 10
  if not data or #data.sources == 0 then
    for _, row in ipairs(Meter.rows) do row:Hide() end
    f.empty:Show()
    layout(1)
    if reason and reason ~= Meter.lastShapeError then
      Meter.lastShapeError = reason
      if not reason:find("^call failed") or not Meter.reportedCallFail then
        Meter.reportedCallFail = reason:find("^call failed") and true or Meter.reportedCallFail
        HH:LogError("meter: session shape not understood: " .. reason)
      end
    end
    return
  end
  f.empty:Hide()
  setTitle(data.encounter)
  local top = data.maxAmount or data.sources[1].amount      -- the session reports its own top amount
  local shown = 0
  for i, src in ipairs(data.sources) do
    if i > max then break end
    local row = Meter.rows[i] or newRow(i)
    Meter.rows[i] = row
    row.src, row.spell = src, nil
    row.name:SetText(("%d. %s"):format(i, src.name))
    local per = fmtPer(src.per)
    local amount = fmtAmount(src.amount)
    row.value:SetText(per and (amount .. "  (" .. per .. ")") or amount)
    local class = classToken(src)
    row.bar:SetStatusBarColor(classColor(class))
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if d.classIcons ~= false and coords then
      row.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
      row.icon:SetTexCoord(unpack(coords))
      row.icon:Show()
    else
      row.icon:Hide()
    end
    if src.amount ~= nil and top ~= nil then
      row.bar:SetMinMaxValues(0, top)
      row.bar:SetValue(src.amount)
    else
      row.bar:SetMinMaxValues(0, 1)
      row.bar:SetValue(0)
    end
    row:Show()
    shown = shown + 1
  end
  for i = shown + 1, #Meter.rows do Meter.rows[i]:Hide() end
  layout(shown)
end

function Meter.SetMode(key)
  cfg().mode = modeInfo(key).key
  Meter.Update()
end

function Meter.SetSegment(key)
  cfg().segment = (key == "Overall") and "Overall" or "Current"
  Meter.Update()
end

function Meter.CycleMode()
  local cur = cfg().mode or "DamageDone"
  for i, m in ipairs(Meter.MODES) do
    if m.key == cur then Meter.SetMode(Meter.MODES[i % #Meter.MODES + 1].key) return end
  end
  Meter.SetMode(Meter.MODES[1].key)
end

function Meter.CycleSegment()
  Meter.SetSegment(cfg().segment == "Overall" and "Current" or "Overall")
end

function Meter.Reset()
  local api = C_DamageMeter
  if type(api) == "table" and type(api.ResetAllCombatSessions) == "function" then
    local ok, err = pcall(api.ResetAllCombatSessions)
    if not ok then HH:LogError("meter reset: " .. tostring(err)) end
  end
  Meter.Update()
end

-- ------------------------------------------------------------------------------------------------ Blizzard's meter
-- Ours on = theirs off (same rule as the castbar and the party frames). Same method as the party frames.
local hiddenParent
local function banish(f)
  if type(f) ~= "table" then return end
  if f.UnregisterAllEvents then pcall(f.UnregisterAllEvents, f) end
  if f.Hide then pcall(f.Hide, f) end
  if f.SetParent then pcall(f.SetParent, f, hiddenParent) end
end

function Meter.ApplyBlizzard()
  local d = cfg()
  if d.enabled == false or d.hideBlizzard == false then return end
  HH:RunOutOfCombat(function()
    hiddenParent = _G.HogHealsHiddenParent or hiddenParent   -- the shared one when another module made it
    if not hiddenParent then
      hiddenParent = CreateFrame("Frame", "HogHealsHiddenParent", UIParent)
      hiddenParent:Hide()
    end
    banish(_G.DamageMeter)
    -- The manager frame is one thing; its session windows are separate frames (SetSessionWindowMinimized et al
    -- on the mixin) and one stayed on screen minimised. Ask the mixin to hide them, then banish anything named
    -- after it that is not ours.
    local dm = _G.DamageMeter
    if type(dm) == "table" and type(dm.HideAllSessionWindows) == "function" then pcall(dm.HideAllSessionWindows, dm) end
    local names = {}
    if type(EnumerateFrames) == "function" then
      local f, n = EnumerateFrames(), 0
      while type(f) == "table" and n < 20000 do
        n = n + 1
        local ok, name = pcall(f.GetName, f)
        if ok and type(name) == "string" and name:find("^DamageMeter") and f ~= dm and not (f.IsForbidden and pcall(f.IsForbidden, f) and f:IsForbidden()) then
          banish(f)
          names[#names + 1] = name
        end
        f = EnumerateFrames(f)
      end
    end
    Meter.blizzBanished = table.concat(names, ",")
  end)
end

-- ------------------------------------------------------------------------------------------------ lifecycle
function Meter.Show()
  if Meter.unavailable then HH:Print("This client has no damage-meter data (C_DamageMeter).") return end
  build():Show()
  Meter.Update()
  Meter.StartTicker()
end

function Meter.Hide()
  if Meter.frame then Meter.frame:Hide() end
  Meter.StopTicker()
end

function Meter.Toggle()
  if Meter.frame and Meter.frame:IsShown() then Meter.Hide() else Meter.Show() end
end

function Meter.StartTicker()
  Meter.StopTicker()
  if C_Timer and C_Timer.NewTicker then
    Meter.ticker = C_Timer.NewTicker(cfg().refresh or 1, function()
      if Meter.frame and Meter.frame:IsShown() then Meter.Update() end
    end)
  end
end

function Meter.StopTicker()
  if Meter.ticker then Meter.ticker:Cancel(); Meter.ticker = nil end
end

function Meter.Refresh()
  if Meter.unavailable then return end
  local d = cfg()
  if d.enabled == false then Meter.Hide() return end
  Meter.ApplyBlizzard()
  if Meter.frame then
    Meter.frame.bg:SetColorTexture(INK[1], INK[2], INK[3], d.backgroundAlpha or 0.85)
    Meter.frame:SetWidth(d.width or 240)
  end
  Meter.Show()
end

HH:RegisterSlash("meterdiag", function()
  HH:Print(("meter: session call form %s; per-source form %s"):format(tostring(Meter.callForm), tostring(Meter.sourceForm)))
  if Meter.sourceTries then for line in Meter.sourceTries:gmatch("[^|]+") do HH:Print("  " .. (line:gsub("^%s+", ""))) end end
  local g = HH.db and HH.db.global
  if g and g.diag and g.diag.meter then HH:Print("  args: " .. tostring(g.diag.meter.sourceArgs)) HH:Print("  shape: " .. tostring(g.diag.meter.source)) end
end, "how the meter talks to this client's damage-meter API (every call shape tried, with the client's own usage text)")

local Module = {}
HHM.module = Module

function Module:OnEnable()
  Meter.unavailable = not (type(C_DamageMeter) == "table" and type(C_DamageMeter.GetCombatSessionFromType) == "function")
  if Meter.unavailable then return end
  if cfg().enabled == false then return end
  Meter.ApplyBlizzard()
  Meter.Show()
  -- refresh on the boundaries Blizzard's own meter reacts to; the ticker covers the rest
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "DAMAGE_METER_SESSION_UPDATED", "DAMAGE_METER_SESSIONS_UPDATED" }) do
    pcall(ev.RegisterEvent, ev, e)
  end
  ev:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_ENTERING_WORLD" then Meter.ApplyBlizzard() end
    if Meter.frame and Meter.frame:IsShown() then Meter.Update() end
  end)
  Meter.events = ev
end

function Module:OnProfileChanged() Meter.Refresh() end

function Module:SetLocked(locked)
  -- the header is always the drag handle; locked just refuses the drag (see OnDragStart)
end

function Module:GetOptions()
  if HHM.Options and HHM.Options.Build then return HHM.Options.Build() end
  return { type = "group", name = "Meter", args = {} }
end

HH:RegisterSlash("meter", function() Meter.Toggle() end, "show / hide the damage meter")
HH:RegisterSlash("meterreset", function() Meter.Reset() end, "reset Blizzard's meter data")

HH:RegisterModule("Meter", Module)
