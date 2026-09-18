-- HogHeals core: addon object, module registry, DB, slash entry.
local ADDON, ns = ...

-- Blizzard FrameXML helpers that vendored libraries still call but some clients no longer ship.
-- Lives in Core.lua on purpose: AceGUI resolves these names at CALL time, so load order does not matter, and an
-- existing file is re-read by /reload while a brand-new file can need a full client restart (= another queue).
-- Only ever fills a hole: if the client has the function, it is left alone.
-- These names do not exist in the client's own code when we define them, so nothing secure can call into them.
--
-- SetDesaturation: AceGUI-3.0 CheckBox (v26, the newest there is; retail addons ship the same file) calls it on
-- every checkbox refresh. Missing on the WoW: Forever beta 1.60.1 -> the options window threw on the first tab
-- that contains a toggle ("AceGUIWidget-CheckBox.lua:130: attempt to call a nil value").
if type(SetDesaturation) ~= "function" then
  function SetDesaturation(texture, desaturate)
    if not texture then return end
    local supported = texture.SetDesaturated and texture:SetDesaturated(desaturate and true or false)
    if supported == false and texture.SetVertexColor then
      if desaturate then texture:SetVertexColor(0.5, 0.5, 0.5) else texture:SetVertexColor(1, 1, 1) end
    end
  end
end


local AceAddon = LibStub("AceAddon-3.0")
HogHeals = AceAddon:NewAddon("HogHeals", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local HH = HogHeals
HH.ns = ns
HH.modules = {}
HH.errors = {}
HH.callbacks = LibStub("CallbackHandler-1.0"):New(HH)

local function metadata(key)
  if C_AddOns and C_AddOns.GetAddOnMetadata then return C_AddOns.GetAddOnMetadata(ADDON, key) end
  if GetAddOnMetadata then return GetAddOnMetadata(ADDON, key) end
end
HH.version = metadata("Version") or "dev"

--- Register a child module. tbl may define OnInitialize(), OnEnable(), OnProfileChanged(), GetOptions().
function HH:RegisterModule(name, tbl)
  assert(type(name) == "string" and type(tbl) == "table", "RegisterModule(name, table)")
  tbl.name = name
  self.modules[name] = tbl
  if self._enabled and tbl.OnEnable then self:SafeCall(tbl, "OnEnable") end
  return tbl
end

--- True when v is a secret value (restricted-API clients: WoW: Forever beta, Midnight). Widgets accept
-- secrets and tostring/format/concat work; arithmetic, comparison and boolean tests throw.
function HH.IsSecret(v)
  local f = issecretvalue
  if type(f) ~= "function" then return false end
  return f(v) and true or false
end

--- xpcall handler: keep the stack, a bare pcall message is useless from a tester's machine.
function HH.Trace(err)
  local stack = type(debugstack) == "function" and debugstack(2, 12, 0) or ""
  return tostring(err) .. (stack ~= "" and (string.char(10) .. stack) or "")
end

--- Call obj[method](obj, ...) capturing any error into HH.errors instead of breaking the caller.
function HH:SafeCall(obj, method, ...)
  local fn = type(obj) == "table" and obj[method] or nil
  if type(fn) ~= "function" then return true end
  local ok, err = xpcall(fn, HH.Trace, obj, ...)
  if not ok then self:LogError(tostring(err)) end
  return ok, err
end

function HH:LogError(msg)
  self.errors[#self.errors + 1] = { time = GetTime and GetTime() or 0, msg = msg }
  if #self.errors > 200 then table.remove(self.errors, 1) end
  local diag = self.db and self.db.global and self.db.global.diag
  if diag then
    diag.errors = diag.errors or {}
    local now = date and date("%Y-%m-%d %H:%M:%S") or ""
    for _, e in ipairs(diag.errors) do
      if e.msg == msg and e.session == diag.session then
        e.count = (e.count or 1) + 1
        e.last = now
        return
      end
    end
    diag.errors[#diag.errors + 1] = { msg = msg, session = diag.session, at = now, count = 1 }
    while #diag.errors > 50 do table.remove(diag.errors, 1) end
  end
  if not self._errorNoticeShown then
    self._errorNoticeShown = true
    self:Print("An error was caught and logged. Type /hh errors to see it.")
  end
end

function HH:OnInitialize()
  local defaults = self.defaults or { profile = {}, global = {} }
  self.db = LibStub("AceDB-3.0"):New("HogHealsDB", defaults, true)
  if self.Migrate then self.Migrate.Run(self.db) end
  local g = self.db.global
  g.diag = g.diag or {}
  g.diag.errors = g.diag.errors or {}
  g.diag.session = (g.diag.session or 0) + 1
  for _, e in ipairs(self.errors) do  -- anything caught before the DB existed
    g.diag.errors[#g.diag.errors + 1] = { msg = e.msg, session = g.diag.session, at = "pre-db" }
  end
  self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
  self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
  self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
  for _, m in pairs(self.modules) do self:SafeCall(m, "OnInitialize") end
  self:RegisterChatCommand("hh", "SlashCommand")
  self:RegisterChatCommand("hogheals", "SlashCommand")
end

function HH:OnEnable()
  self._enabled = true
  if self.InitGroupSize then self:InitGroupSize() end
  if self.InitQueue then self:InitQueue() end
  for _, m in pairs(self.modules) do self:SafeCall(m, "OnEnable") end
  self:SafeCall(self, "SnapshotClient")
  -- Values may only turn secret once combat starts: probe again on the first pull of the session.
  self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    if self:SafeCall(self, "SnapshotClient") then
      local d = self.db.global.diag
      d.combatProbe = d.client and d.client.secretProbe
    end
  end)
end

local function probe(path)
  local v = _G
  for part in path:gmatch("[^%.]+") do
    if type(v) ~= "table" then return "nil" end
    v = v[part]
  end
  return type(v)
end

HH.GLOBALS_USED = "Ambiguate,CastingInfo,ClearCursor,ClearOverrideBindings,CreateFont,GetActiveSeason,GetAddOnMetadata,GetCurrentRegion,GetCurrentRegionName,GetCursorInfo,GetCursorPosition,GetFramerate,GetInventoryItemLink,GetInventorySlotInfo,GetLocale,GetMacroInfo,GetMinimapShape,GetNetStats,GetNumGroupMembers,GetNumSpellTabs,GetNumTalentTabs,GetNumTalents,GetRaidRosterInfo,GetRaidTargetIndex,GetReadyCheckStatus,GetRealmName,GetSpellBonusHealing,GetSpellBookItemInfo,GetSpellBookItemName,GetSpellCooldown,GetSpellCritChance,GetSpellInfo,GetSpellTabInfo,GetTalentInfo,GetZonePVPInfo,HasActiveSeason,IsAddOnLoaded,IsAltKeyDown,IsControlKeyDown,IsEquippedItem,IsInGroup,IsInInstance,IsInRaid,IsShiftKeyDown,IsSpellBookItemInRange,IsSpellInRange,PlaySound,RegisterAddonMessagePrefix,SendAddonMessage,SetDesaturation,SetOverrideBindingClick,SpellIsTargeting,UnitAura,UnitBuff,UnitDebuff,UnitCanAssist,UnitCanAttack,UnitCastingInfo,UnitChannelInfo,UnitFactionGroup,UnitGUID,UnitGetIncomingHeals,UnitHasIncomingResurrection,UnitHasVehicleUI,UnitInParty,UnitInRaid,UnitInRange,UnitIsAFK,UnitIsCharmed,UnitIsConnected,UnitIsGroupAssistant,UnitIsGroupLeader,UnitIsVisible,UnitLevel,UnitPlayerControlled,UnitPowerType,UnitRace,UnitThreatSituation,InterfaceOptions_AddCategory,InterfaceOptionsFrame_OpenToCategory,UIDropDownMenu_Initialize,ToggleDropDownMenu,EasyMenu,GetMouseFocus,GetMouseFoci,C_Timer,hooksecurefunc,securecallfunction"

--- Write what this client IS into SavedVariables (read off disk after a /reload; see docs/TESTING-BETA.md).
function HH:SnapshotClient()
  local diag = self.db.global.diag
  local version, build, builddate, toc = GetBuildInfo()
  local probes = {}
  for _, path in ipairs({
    "loadstring_untainted", "C_UnitAuras.AddPrivateAuraAnchor", "C_UnitAuras.GetAuraDataByIndex", "UnitAura",
    "UnitGetIncomingHeals", "C_Secrets", "issecretvalue", "C_RestrictedActions", "SecureHandlerWrapScript",
    "C_GamePad", "C_AddOns.GetAddOnMetadata", "C_Spell.GetSpellInfo", "GetSpellInfo", "C_EditMode", "Settings.OpenToCategory",
  }) do probes[path] = probe(path) end
  local compat
  local C = HogHealsFrames and HogHealsFrames.Compat
  if C and C.Init and C.Describe then C.Init(); compat = C.Describe() end
  local sp = {}
  do
    local isv = type(issecretvalue) == "function" and issecretvalue or function() return false end
    local hp, max, name = UnitHealth("player"), UnitHealthMax("player"), UnitName("player")
    local pw = UnitPower("player")
    local inc = type(UnitGetIncomingHeals) == "function" and UnitGetIncomingHeals("player") or nil
    local rng = UnitInRange and UnitInRange("player")
    sp["secret.UnitHealth"], sp["secret.UnitHealthMax"], sp["secret.UnitName"] = isv(hp) and true or false, isv(max) and true or false, isv(name) and true or false
    sp["secret.UnitPower"], sp["secret.UnitGetIncomingHeals"], sp["secret.UnitInRange"] = isv(pw) and true or false, isv(inc) and true or false, isv(rng) and true or false
    sp["inCombat"] = InCombatLockdown() and true or false
    local ops = {
      ["hp+0"] = function() return hp + 0 end, ["hp/max"] = function() return hp / max end,
      ["hp<max"] = function() return hp < max end, ["hp==0"] = function() return hp == 0 end,
      ["tostring(hp)"] = function() return tostring(hp) end, ["format%d"] = function() return ("%d"):format(hp) end,
      ["concat hp"] = function() return "x" .. hp end, ["#name"] = function() return #name end,
      ["name:sub"] = function() return name:sub(1, 3) end, ["concat name"] = function() return name .. "x" end,
      ["format%s name"] = function() return ("%s"):format(name) end, ["if rng"] = function() if rng then return 1 end return 0 end,
      ["pw+0"] = function() return pw + 0 end,
    }
    for k, f in pairs(ops) do sp["op." .. k] = pcall(f) and true or false end
    for _, path in ipairs({ "UnitHealthPercent", "UnitHealthMissing", "UnitPowerPercent", "UnitPowerMissing", "C_CurveUtil",
      "CreateUnitHealPredictionCalculator", "AbbreviateNumbers", "AbbreviateLargeNumbers", "C_StringUtil", "canaccessvalue",
      "canaccesssecrets", "scrubsecretvalues", "hasanysecretvalues", "secretwrap", "C_UnitAuras.GetUnitAuras",
      "C_UnitAuras.IsAuraFilteredOutByInstanceID", "UnitCastingDuration", "C_DurationUtil" }) do sp["api." .. path] = probe(path) end
    for _, tname in ipairs({ "C_Secrets", "C_RestrictedActions", "C_CurveUtil", "C_StringUtil" }) do
      local t, keys = _G[tname], {}
      if type(t) == "table" then for k in pairs(t) do keys[#keys + 1] = tostring(k) end table.sort(keys) end
      sp["keys." .. tname] = table.concat(keys, ",")
    end
  end
  -- Every WoW global our code or the vendored libs call (generated by scanning the source). Whatever is nil on
  -- this client is the to-do list for shims, found in one pass instead of one error report at a time.
  local missing = {}
  for name in (HH.GLOBALS_USED or ""):gmatch("[^,]+") do
    if _G[name] == nil then missing[#missing + 1] = name end
  end
  diag.client = {
    missingGlobals = table.concat(missing, ","),
    secretProbe = sp,
    version = version, build = build, builddate = builddate, toc = toc, project = WOW_PROJECT_ID,
    addon = self.version, at = date and date("%Y-%m-%d %H:%M:%S") or "", probes = probes, compat = compat,
  }
end

function HH:OnProfileChanged()
  for _, m in pairs(self.modules) do self:SafeCall(m, "OnProfileChanged") end
end

--- Slash dispatcher. Modules may register subcommands via HH:RegisterSlash(word, fn, help).
HH.slash = {}
function HH:RegisterSlash(word, fn, help)
  self.slash[word] = { fn = fn, help = help or "" }
end

function HH:SlashCommand(input)
  input = strtrim(input or "")
  local word, rest = input:match("^(%S+)%s*(.-)$")
  if not word or word == "" then
    if self.OpenOptions then self:OpenOptions() else self:Print("Options not loaded.") end
    return
  end
  word = word:lower()
  if word == "errors" then
    if #self.errors == 0 then self:Print("No errors logged.") return end
    for i, e in ipairs(self.errors) do self:Print(("%d. %s"):format(i, e.msg)) end
    return
  end
  local entry = self.slash[word]
  if entry then
    local ok, err = pcall(entry.fn, rest)
    if not ok then self:LogError(err) end
    return
  end
  self:Print("Unknown command '" .. word .. "'. Commands:")
  self:Print("  /hh            open options")
  self:Print("  /hh errors     show caught errors")
  for w, e in pairs(self.slash) do self:Print(("  /hh %-10s %s"):format(w, e.help)) end
end
