-- Minimal WoW API mock for HogHeals unit tests (Lua 5.1 under lupa).
-- Philosophy: record what the addon does (attributes, points, bindings) and
-- serve unit data from MockUnits so element Update() functions are testable.

MockState = { inCombat = false, numGroup = 1, inRaid = false, projectId = 5, time = 0,
              playerClass = "PRIEST", locale = "enUS", cliqueLoaded = false }
MockUnits = {}
MockBindings = { clicks = {}, cleared = {} }
MockLog = { attributes = {}, errors = {} }
MockTimers = {}

-- WoW's xpcall forwards varargs; vanilla Lua 5.1 does not. Ace3 depends on the WoW behaviour.
do
  local _xpcall, _unpack, _select = xpcall, unpack, select
  function xpcall(f, h, ...)
    local n, args = _select("#", ...), { ... }
    return _xpcall(function() return f(_unpack(args, 1, n)) end, h)
  end
end

-- ---------- constants ----------
WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_CLASSIC = 2
WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
WOW_PROJECT_WRATH_CLASSIC = 11
WOW_PROJECT_CATACLYSM_CLASSIC = 14
WOW_PROJECT_MISTS_CLASSIC = 19
WOW_PROJECT_ID = MockState.projectId
LE_PARTY_CATEGORY_HOME = 1
DebuffTypeColor = {
  Magic = { r = 0.2, g = 0.6, b = 1.0 }, Curse = { r = 0.6, g = 0, b = 1 },
  Disease = { r = 0.6, g = 0.4, b = 0 }, Poison = { r = 0, g = 0.6, b = 0 }, none = { r = 0.8, g = 0, b = 0 },
}
RAID_CLASS_COLORS = {
  PRIEST = { r = 1, g = 1, b = 1 }, SHAMAN = { r = 0, g = 0.44, b = 0.87 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
  DRUID = { r = 1, g = 0.49, b = 0.04 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
  ROGUE = { r = 1, g = 0.96, b = 0.41 }, HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
GAME_LOCALE = "enUS"
DEAD = "Dead"; PLAYER_OFFLINE = "Offline"; AFK = "AFK"; UNKNOWN = "Unknown"
NUM_RAID_GROUPS = 8; MAX_RAID_MEMBERS = 40; MEMBERS_PER_RAID_GROUP = 5

-- ---------- string/table helpers ----------
floor, ceil, max, min, abs, sqrt, mod = math.floor, math.ceil, math.max, math.min, math.abs, math.sqrt, math.fmod
strmatch = string.match; strfind = string.find; strsub = string.sub; strlen = string.len
strlower = string.lower; strupper = string.upper; strrep = string.rep; strbyte = string.byte; strchar = string.char
format = string.format; gsub = string.gsub; gmatch = string.gmatch
tinsert = table.insert; tremove = table.remove; tconcat = table.concat; sort = table.sort
getn = table.getn or function(t) return #t end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(delim, s, n)
  local out = {}
  for piece in (s .. delim):gmatch("(.-)" .. delim:gsub("%p", "%%%0")) do out[#out + 1] = piece end
  return unpack(out)
end
function strjoin(delim, ...) return table.concat({ ... }, delim) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function tContains(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
function tInvert(t) local o = {} for k, v in pairs(t) do o[v] = k end return o end
function CopyTable(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == "table" and CopyTable(v) or v end return o end
function Mixin(o, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do o[k] = v end end return o end
function CreateFromMixins(...) return Mixin({}, ...) end
function debugstack() return "" end
function debugprofilestop() return 0 end
function geterrorhandler() return function(e) MockLog.errors[#MockLog.errors + 1] = tostring(e) end end
function seterrorhandler() end
function securecall(f, ...) return f(...) end
function securecallfunction(f, ...) return f(...) end
function issecurevariable() return false end
function forceinsecure() end
function hooksecurefunc(a, b, c)
  if type(a) == "table" then local orig = a[b]; a[b] = function(...) local r = { orig(...) }; c(...); return unpack(r) end
  else local orig = _G[a]; _G[a] = function(...) local r = { orig(...) }; b(...); return unpack(r) end end
end
function GetTime() return MockState.time end
function GetLocale() return MockState.locale end
function GetBuildInfo() return "2.5.5", "60000", "Jan 1 2026", 20505 end
function IsLoggedIn() return MockState.loggedIn == true end
function InCombatLockdown() return MockState.inCombat end
function IsInRaid() return MockState.inRaid end
function IsInGroup() return MockState.numGroup > 1 end
function GetNumGroupMembers() return MockState.numGroup end
function GetNumSubgroupMembers() return math.max(0, math.min(4, MockState.numGroup - 1)) end
function IsAddOnLoaded(n) return n == "Clique" and MockState.cliqueLoaded end
C_AddOns = { IsAddOnLoaded = IsAddOnLoaded, GetAddOnMetadata = function(_, k) return k == "Version" and "0.1.0-test" or nil end,
             GetNumAddOns = function() return 0 end }
function GetAddOnMetadata(_, k) return C_AddOns.GetAddOnMetadata(_, k) end
function GetSpellInfo(id) if type(id) == "string" then return id, nil, "Interface\\Icons\\" .. id:gsub("%s", ""), 0, 0, 40, 0 end return "Spell" .. id, nil, "icon", 0, 0, 40, id end
function IsSpellKnown() return true end
function GetSpellTexture(s) return "Interface\\Icons\\" .. tostring(s) end
C_Spell = { GetSpellInfo = function(s) local n, _, i = GetSpellInfo(s) return { name = n, iconID = i } end, GetSpellTexture = GetSpellTexture }
C_Timer = { After = function(sec, fn) MockTimers[#MockTimers + 1] = { at = MockState.time + sec, fn = fn } end,
            NewTicker = function(sec, fn) local t = { cancelled = false, fn = fn, every = sec }
              function t:Cancel() t.cancelled = true end
              MockTimers[#MockTimers + 1] = t return t end }
function MockAdvance(sec)
  MockState.time = MockState.time + sec
  for i = #MockTimers, 1, -1 do local t = MockTimers[i]
    if t.every then if not t.cancelled then t.fn() end
    elseif t.at <= MockState.time then table.remove(MockTimers, i); t.fn() end
  end
end
function SetBindingClick(priority, key, name, button)
  MockBindings.clicks[#MockBindings.clicks + 1] = { key = key, name = name, button = button, priority = priority } return true
end
function SetOverrideBindingClick(owner, priority, key, name, button)
  MockBindings.clicks[#MockBindings.clicks + 1] = { owner = owner, key = key, name = name, button = button, priority = priority } return true
end
function ClearOverrideBindings(owner) MockBindings.cleared[#MockBindings.cleared + 1] = owner end
function GetBindingKey() return nil end
function GetCVar() return "0" end
function SetCVar() end
function GetScreenWidth() return 1920 end
function GetScreenHeight() return 1080 end
function PlaySound() end
function RegisterStateDriver() end
function UnregisterStateDriver() end
function RegisterAttributeDriver() end
function SecureHandlerSetFrameRef() end
function SecureHandlerExecute() end
function SecureHandlerWrapScript() end
function ClearOverrideBindings_() end
SlashCmdList = {}
hash_SlashCmdList = {}
function SendChatMessage() end
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end, SendAddonMessage = function() return 0 end }
function UnitGUID(u) local m = MockUnits[u] return m and (m.guid or ("Player-" .. u)) or nil end
function GetRealmName() return "Nightslayer" end
function UnitFactionGroup() return "Horde", "Horde" end
function GetInstanceInfo() return "Azeroth", "none", 0, "", 0, 0, false, 0, 0 end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
function GetMouseFocus() return nil end
function GetCursorPosition() return 0, 0 end
function GetReadyCheckStatus(u) local m = MockUnits[u] return m and m.readyCheck or nil end
function UnitHasIncomingResurrection(u) local m = MockUnits[u] return m and m.incomingRes or false end
C_IncomingSummon = { HasIncomingSummon = function(u) local m = MockUnits[u] return m and m.incomingSummon or false end,
                     IncomingSummonStatus = function(u) local m = MockUnits[u] return (m and m.incomingSummon) and 1 or 0 end }
Enum = { SummonStatus = { None = 0, Pending = 1, Accepted = 2, Declined = 3 }, PowerType = { Mana = 0, Rage = 1, Energy = 3 } }

-- ---------- unit API ----------
local function U(u) return MockUnits[u] end
function UnitExists(u) return U(u) ~= nil end
function UnitIsUnit(a, b) return a == b or (U(a) and U(b) and U(a).guid ~= nil and U(a).guid == U(b).guid) end
function UnitName(u) local m = U(u) return m and (m.name or u) or nil end
function UnitClass(u) local m = U(u) if not m then return nil end return m.class:sub(1, 1) .. m.class:sub(2):lower(), m.class end
function UnitHealth(u) local m = U(u) return m and m.health or 0 end
function UnitHealthMax(u) local m = U(u) return m and (m.maxHealth or 100) or 0 end
function UnitPower(u) local m = U(u) return m and (m.power or 100) or 0 end
function UnitPowerMax(u) local m = U(u) return m and (m.maxPower or 100) or 0 end
local CLASS_POWER = { WARRIOR = "RAGE", ROGUE = "ENERGY", DRUID = "MANA" }
function UnitPowerType(u) local m = U(u) local t = (m and (m.powerType or CLASS_POWER[m.class])) or "MANA"
  local ids = { MANA = 0, RAGE = 1, ENERGY = 3, FOCUS = 2 } return ids[t] or 0, t end
function UnitIsDead(u) local m = U(u) return m and m.dead or false end
function UnitIsGhost(u) local m = U(u) return m and m.ghost or false end
function UnitIsDeadOrGhost(u) return UnitIsDead(u) or UnitIsGhost(u) end
function UnitIsConnected(u) local m = U(u) if not m then return false end if m.connected == nil then return true end return m.connected end
function UnitIsAFK(u) local m = U(u) return m and m.afk or false end
function UnitInRange(u) local m = U(u) if not m then return false, false end if m.inRange == nil then return true, true end return m.inRange, true end
function UnitThreatSituation(u) local m = U(u) return m and m.threat or 0 end
function GetRaidTargetIndex(u) local m = U(u) return m and m.raidIcon or nil end
function UnitIsPlayer(u) local m = U(u) return m and (m.isPlayer ~= false) end
function UnitIsFriend(a, b) return true end
function UnitCanAttack() return false end
function UnitInParty(u) return u:match("^party") ~= nil or u == "player" end
function UnitInRaid(u) local n = u:match("^raid(%d+)") return n and tonumber(n) or nil end
function UnitIsGroupLeader(u) local m = U(u) return m and m.leader or false end
function UnitIsGroupAssistant(u) local m = U(u) return m and m.assistant or false end
function UnitGroupRolesAssigned() return "NONE" end
function UnitIsCharmed(u) local m = U(u) return m and m.charmed or false end
function UnitPlayerControlled() return true end
function UnitLevel(u) local m = U(u) return m and (m.level or 60) or 0 end
function UnitGetIncomingHeals(u, src) local m = U(u) if not m then return 0 end
  if src == "player" then return m.incomingMine or 0 end return (m.incomingMine or 0) + (m.incomingOthers or 0) end
function UnitGetTotalAbsorbs(u) local m = U(u) return m and m.absorbs or 0 end
function UnitAura(u, i, filter)
  local m = U(u) if not m or not m.auras then return nil end
  local harmful = filter and filter:find("HARMFUL")
  local n = 0
  for _, a in ipairs(m.auras) do
    local isDebuff = a.type ~= nil or a.debuff
    if (harmful and isDebuff) or (not harmful and not isDebuff) then
      n = n + 1
      if n == i then
        return a.name, a.icon or "icon", a.count or 0, a.type, a.duration or 0, a.expires or 0, a.source or "unknown", false, false, a.spellId or 0
      end
    end
  end
  return nil
end
function UnitBuff(u, i) return UnitAura(u, i, "HELPFUL") end
function UnitDebuff(u, i) return UnitAura(u, i, "HARMFUL") end
function GetRaidRosterInfo(i)
  local u = "raid" .. i local m = U(u) if not m then return nil end
  return m.name or u, 0, m.subgroup or math.ceil(i / 5), m.level or 60, UnitClass(u), m.class, "", true, m.dead, nil, false, nil
end
function CheckInteractDistance(u, idx) local m = U(u) if not m then return false end
  if m.inRange == false then return false end return true end
function IsSpellInRange(spell, u) local m = U(u) if not m then return nil end if m.inRange == false then return 0 end return 1 end
function UnitDistanceSquared(u) local m = U(u) if not m or not m.distance then return 0, false end return m.distance ^ 2, true end
function GetPlayerClass() return MockState.playerClass end
MockUnits.player = { name = "Hognificent", class = MockState.playerClass, health = 100, maxHealth = 100, guid = "Player-0" }
local _unitClass = UnitClass
function UnitClass(u) if u == "player" then MockUnits.player.class = MockState.playerClass end return _unitClass(u) end

-- ---------- frame mock ----------
local Region = {}
Region.__index = function(t, k)
  if rawget(Region, k) then return rawget(Region, k) end
  -- Only method-like names (Uppercase first letter) get a recording no-op; plain fields read as nil.
  if type(k) == "string" and k:match("^[A-Z]") then
    return function(self, ...) self._calls[k] = (self._calls[k] or 0) + 1; self._last[k] = { ... } end
  end
  return nil
end
local regionCounter = 0
local function newRegion(kind, name, parent)
  regionCounter = regionCounter + 1
  local r = setmetatable({ _kind = kind, _name = name or (kind .. regionCounter), _parent = parent, _calls = {}, _last = {},
    _shown = true, _alpha = 1, _points = {}, _attrs = {}, _events = {}, _scripts = {}, _text = "", _color = {},
    _value = 0, _min = 0, _max = 1, _width = 0, _height = 0, _children = {}, _texture = nil, _id = 0 }, Region)
  if name then _G[name] = r end
  if parent and parent._children then parent._children[#parent._children + 1] = r end
  return r
end
function Region:GetName() return self._name end
function Region:GetParent() return self._parent end
function Region:SetParent(p) self._parent = p end
function Region:GetObjectType() return self._kind end
function Region:IsObjectType(k) return self._kind == k end
function Region:Show() self._shown = true end
function Region:Hide() self._shown = false end
function Region:SetShown(b) self._shown = b and true or false end
function Region:IsShown() return self._shown end
function Region:IsVisible() return self._shown end
function Region:SetAlpha(a) self._alpha = a end
function Region:GetAlpha() return self._alpha end
function Region:SetSize(w, h) self._width, self._height = w, h end
function Region:SetWidth(w) self._width = w end
function Region:SetHeight(h) self._height = h end
function Region:GetWidth() return self._width end
function Region:GetHeight() return self._height end
function Region:GetSize() return self._width, self._height end
function Region:SetPoint(p, a, b, c, d)
  if type(a) == "number" then self._points[#self._points + 1] = { p, nil, p, a, b }
  else self._points[#self._points + 1] = { p, a, b, c or 0, d or 0 } end
end
function Region:GetPoint(i) local p = self._points[i or 1] if p then return unpack(p) end end
function Region:GetNumPoints() return #self._points end
function Region:ClearAllPoints() self._points = {} end
function Region:SetAllPoints(t) self._points = { { "ALL", t } } end
function Region:SetAttribute(k, v) self._attrs[k] = v; MockLog.attributes[#MockLog.attributes + 1] = { frame = self._name, key = k, value = v } end
function Region:GetAttribute(k) return self._attrs[k] end
function Region:RegisterEvent(e) self._events[e] = true end
function Region:RegisterUnitEvent(e) self._events[e] = true end
function Region:UnregisterEvent(e) self._events[e] = nil end
function Region:UnregisterAllEvents() self._events = {} end
function Region:IsEventRegistered(e) return self._events[e] == true end
function Region:SetScript(h, f) self._scripts[h] = f end
function Region:GetScript(h) return self._scripts[h] end
function Region:HookScript(h, f) local o = self._scripts[h] self._scripts[h] = function(...) if o then o(...) end f(...) end end
function Region:SetText(t) self._text = t == nil and "" or tostring(t) end
function Region:GetText() return self._text end
function Region:GetStringWidth() return #self._text * 6 end
function Region:SetTextColor(r, g, b, a) self._color = { r, g, b, a } end
function Region:SetVertexColor(r, g, b, a) self._color = { r, g, b, a } end
function Region:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
function Region:GetVertexColor() return unpack(self._color) end
function Region:SetTexture(t) self._texture = t end
function Region:GetTexture() return self._texture end
function Region:SetStatusBarTexture(t) self._texture = t end
function Region:GetStatusBarTexture() return self end
function Region:SetStatusBarColor(r, g, b, a) self._color = { r, g, b, a } end
function Region:GetStatusBarColor() return unpack(self._color) end
function Region:SetMinMaxValues(a, b) self._min, self._max = a, b end
function Region:GetMinMaxValues() return self._min, self._max end
function Region:SetValue(v) self._value = v end
function Region:GetValue() return self._value end
function Region:SetID(i) self._id = i end
function Region:GetID() return self._id end
function Region:GetChildren() return unpack(self._children) end
function Region:GetRegions() return unpack(self._children) end
function Region:CreateTexture(name, layer) local r = newRegion("Texture", name, self) r._layer = layer return r end
function Region:CreateFontString(name, layer) local r = newRegion("FontString", name, self) return r end
function Region:CreateAnimationGroup() local g = newRegion("AnimationGroup", nil, self)
  function g:CreateAnimation(kind) return newRegion(kind or "Animation", nil, g) end return g end
function Region:GetEffectiveScale() return 1 end
function Region:GetScale() return 1 end
function Region:GetCenter() return 0, 0 end
function Region:GetLeft() return 0 end
function Region:GetTop() return 0 end
function Region:IsProtected() return self._protected or false end
function Region:CanChangeProtectedState() return not MockState.inCombat end
function Region:Fire(event, ...) local f = self._scripts.OnEvent if f and self._events[event] then f(self, event, ...) end end
function Region:Click(button) local f = self._scripts.OnClick if f then f(self, button or "LeftButton", false) end end

MockFrames = {}
function CreateFrame(kind, name, parent, template)
  local f = newRegion(kind or "Frame", name, parent)
  f._template = template
  f._protected = template ~= nil and (template:find("Secure") ~= nil)
  MockFrames[#MockFrames + 1] = f
  return f
end
function MockFire(event, ...) for _, f in ipairs(MockFrames) do f:Fire(event, ...) end end
function MockReset()
  wipe(MockUnits); wipe(MockBindings.clicks); wipe(MockBindings.cleared); wipe(MockLog.attributes); wipe(MockLog.errors); wipe(MockTimers)
  MockState.inCombat = false; MockState.numGroup = 1; MockState.inRaid = false; MockState.time = 0; MockState.cliqueLoaded = false
  MockUnits.player = { name = "Hognificent", class = MockState.playerClass, health = 100, maxHealth = 100, guid = "Player-0" }
end
function MockSetGroup(n, isRaid)
  MockState.numGroup = n; MockState.inRaid = isRaid and true or false
  for i = 1, n - 1 do
    local u = (isRaid and "raid" or "party") .. i
    MockUnits[u] = MockUnits[u] or { name = "Unit" .. i, class = "WARRIOR", health = 100, maxHealth = 100, guid = "Player-" .. i }
  end
  if isRaid then MockUnits["raid" .. n] = MockUnits["raid" .. n] or { name = "Hognificent", class = MockState.playerClass, health = 100, maxHealth = 100, guid = "Player-0" } end
end
UIParent = CreateFrame("Frame", "UIParent")
WorldFrame = CreateFrame("Frame", "WorldFrame")
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
function GameTooltip:SetOwner() end
function GameTooltip:AddLine(t) self._lines = self._lines or {} self._lines[#self._lines + 1] = t end
function GameTooltip:AddDoubleLine(a, b) self:AddLine(a .. " " .. b) end
function GameTooltip:ClearLines() self._lines = {} end
function GameTooltip:SetUnit() end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) MockLog.chat = MockLog.chat or {} MockLog.chat[#MockLog.chat + 1] = m end }
ChatFrame1 = DEFAULT_CHAT_FRAME
function print(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end DEFAULT_CHAT_FRAME:AddMessage(table.concat(t, " ")) end
InterfaceOptionsFrame = CreateFrame("Frame", "InterfaceOptionsFrame")
function InterfaceOptions_AddCategory() end
Settings = { RegisterCanvasLayoutCategory = function(f, n) return { ID = n, name = n } end, RegisterAddOnCategory = function() end, OpenToCategory = function() end }
function InterfaceOptionsFrame_OpenToCategory() end
CreateFont = function(n) return newRegion("Font", n) end
GameFontNormal = newRegion("Font", "GameFontNormal"); GameFontHighlight = newRegion("Font", "GameFontHighlight")
GameFontNormalSmall = GameFontNormal; GameFontHighlightSmall = GameFontHighlight; NumberFontNormal = GameFontNormal
function GameFontNormal:GetFont() return STANDARD_TEXT_FONT, 12, "" end
GameFontHighlight.GetFont = GameFontNormal.GetFont
Minimap = CreateFrame("Frame", "Minimap")
function Minimap:GetZoom() return 0 end

function UnitRace(u) return "Undead", "Scourge" end
function UnitSex() return 2 end
function GetCurrentRegion() return 1 end
function GetNormalizedRealmName() return "Nightslayer" end
function GetSpecialization() return nil end
function GetActiveSpecGroup() return 1 end
function UnitClassBase(u) return select(2, UnitClass(u)) end
function GetNumTalentTabs() return 3 end
function GetTalentTabInfo(i) return "Tab" .. i, "", 0 end
function ChatEdit_GetActiveWindow() return nil end
function ChatEdit_GetLastActiveWindow() return nil end
function ChatFrame_AddMessageEventFilter() end
ChatFontNormal = GameFontNormal

-- WoW ships a `bit` library (LuaJIT-style). PUC Lua 5.1 has none; provide a small pure-Lua one.
bit = bit or {}
local function tobits(n) n = math.floor(n) if n < 0 then n = n + 4294967296 end return n % 4294967296 end
function bit.band(a, b) a, b = tobits(a), tobits(b) local r, p = 0, 1
  while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + p end a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2 end return r end
function bit.bor(a, b) a, b = tobits(a), tobits(b) local r, p = 0, 1
  while a > 0 or b > 0 do if a % 2 == 1 or b % 2 == 1 then r = r + p end a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2 end return r end
function bit.bxor(a, b) a, b = tobits(a), tobits(b) local r, p = 0, 1
  while a > 0 or b > 0 do if (a % 2) ~= (b % 2) then r = r + p end a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2 end return r end
function bit.bnot(a) return 4294967295 - tobits(a) end
function bit.lshift(a, n) return (tobits(a) * 2 ^ n) % 4294967296 end
function bit.rshift(a, n) return math.floor(tobits(a) / 2 ^ n) end
function CombatLogGetCurrentEventInfo() return 0, "SPELL_HEAL", false, "Player-0", "Hognificent", 0, 0, "Player-1", "Zugzug", 0, 0 end
function UnitIsVisible() return true end
function UnitIsDeadOrGhost_() return false end
function GetSpellBonusHealing() return 0 end
function GetSpellBonusDamage() return 0 end
function GetSpellCritChance() return 0 end
function UnitInVehicle() return false end
function GetInventoryItemLink() return nil end
function GetItemInfo() return nil end
function GetItemGem() return nil end
function GetInventorySlotInfo() return 1 end
function GetShapeshiftForm() return 0 end
function GetShapeshiftFormInfo() return nil end
function IsPlayerSpell() return true end
function GetSpellCooldown() return 0, 0, 1 end
function GetSpellCharges() return nil end
function UnitCastingInfo(u) local m = MockUnits[u] if m and m.casting then return unpack(m.casting) end return nil end
function UnitChannelInfo(u) local m = MockUnits[u] if m and m.channeling then return unpack(m.channeling) end return nil end
function GetNetStats() return 0, 0, MockState.latencyHome or 50, MockState.latencyWorld or 250 end
function GetSpellBookItemName(i, book) local s = MockState.spellbook and MockState.spellbook[i] if s then return s[1], s[2] end return nil end
function GetSpellBookItemInfo(i) return "SPELL", i end
BOOKTYPE_SPELL = "spell"
function GetNumSpellTabs() return 1 end
function GetSpellTabInfo() return "General", "", 0, (MockState.spellbook and #MockState.spellbook or 0) end
function UnitIsFeignDeath() return false end
function UnitPlayerOrPetInParty() return true end
function UnitPlayerOrPetInRaid() return true end
function GetNumPartyMembers() return math.max(0, MockState.numGroup - 1) end
function GetNumRaidMembers() return MockState.inRaid and MockState.numGroup or 0 end
function GetPlayerInfoByGUID() return nil end
function GetGlyphSocketInfo() return false end
function GetPrimaryTalentTree() return nil end
function UnitGetIncomingHeals_() end
MAX_PARTY_MEMBERS = 4
COMBATLOG_OBJECT_AFFILIATION_MINE = 1
function Ambiguate(name) return (name:match("^([^%-]+)")) or name end
function CastingInfo() return UnitCastingInfo("player") end
function ChannelInfo() return UnitChannelInfo("player") end
function GetNumTalents() return 0 end
function GetZonePVPInfo() return nil end
function IsEquippedItem() return false end
function IsInInstance() return false, "none" end
function SpellIsTargeting() return false end
function UnitCanAssist() return true end
function UnitCanCooperate() return true end
function UnitIsEnemy() return false end
AuraUtil = AuraUtil or {}
function AuraUtil.FindAuraByName(name, unit, filter)
  local i = 1
  while true do local n, icon, count, dtype, dur, exp, src, _, _, id = UnitAura(unit, i, filter)
    if not n then return nil end
    if n == name then return n, icon, count, dtype, dur, exp, src, false, false, id end
    i = i + 1 end
end
function AuraUtil.ForEachAura(unit, filter, max, fn)
  local i = 1
  while true do local r = { UnitAura(unit, i, filter) } if not r[1] then return end if fn(unpack(r)) then return end i = i + 1 end
end
C_UnitAuras = C_UnitAuras or nil
function GetSpellSubtext() return nil end
function UnitIsPVP() return false end
