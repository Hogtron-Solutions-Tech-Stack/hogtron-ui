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
  row:Hide()
  return row
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
  local seg = d.segment == "Overall" and "Overall" or "Current"
  if sessionName and sessionName ~= "" then seg = seg .. ": " .. tostring(sessionName) end
  Meter.frame.title:SetText(("%s  ·  %s"):format(modeInfo(d.mode).label, seg))
end

--- Pull the current session and repaint. Never throws: shape problems are logged once per shape.
function Meter.Update()
  if Meter.unavailable then return end
  local f = build()
  local d = cfg()
  setTitle()
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
    hiddenParent = hiddenParent or _G.HogHealsHiddenParent
    if not hiddenParent then
      hiddenParent = CreateFrame("Frame", "HogHealsHiddenParent", UIParent)
      hiddenParent:Hide()
    end
    banish(_G.DamageMeter)
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
