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


-- Load-order trace: every ADDON_LOADED / PLAYER_LOGIN this frame sees, with whether HogHealsDB was a table at
-- that moment. Copied into diag.init by the DB init below. Exists because the profile came up EMPTY twice
-- (2026-09-17 23:55, 2026-09-18 00:21, Forever beta) on a valid on-disk file and nothing on disk said why.
local loadTrace = {}
local traceFrame = CreateFrame("Frame")
traceFrame:RegisterEvent("ADDON_LOADED")
traceFrame:RegisterEvent("PLAYER_LOGIN")
traceFrame:SetScript("OnEvent", function(_, event, name)
  if #loadTrace < 40 then
    loadTrace[#loadTrace + 1] = (event == "ADDON_LOADED" and ("ADDON_LOADED:" .. tostring(name)) or event)
      .. (type(rawget(_G, "HogHealsDB")) == "table" and "+sv" or "-sv")
  end
  if event == "PLAYER_LOGIN" then traceFrame:UnregisterAllEvents() end
end)

local AceAddon = LibStub("AceAddon-3.0")
HogHeals = AceAddon:NewAddon("HogHeals", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local HH = HogHeals
HH.ns = ns

-- Chat prefix: the umbrella brand. (AceConsole would print "HogHeals:"; the addon object keeps that internal name
-- because SavedVariables, junctions and every module namespace key off it.)
HH.BRAND = "|cffF5EBDCHog|r|cff21D4E0UI|r"
function HH:Print(...)
  local n = select("#", ...)
  local parts = {}
  for i = 1, n do parts[i] = tostring((select(i, ...))) end
  local frame = rawget(_G, "DEFAULT_CHAT_FRAME")
  if frame and frame.AddMessage then frame:AddMessage(HH.BRAND .. ": " .. table.concat(parts, " ")) end
end
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
--- "AnyDown" or "AnyUp": the ONE click edge a secure button should answer on this client. Since 10.0 the secure
-- OnClick skips any click that does not match the ActionButtonUseKeyDown cvar (default 1 = act on press); a
-- button registered for the other edge never acts. Seen in game 2026-10-02 on Forever: the menu bar glyphs did
-- nothing (registered "AnyUp"). Registering both edges would fire twice on clients without the cvar check.
function HH.SecureClick()
  local v = type(GetCVar) == "function" and GetCVar("ActionButtonUseKeyDown") or nil
  if v == nil then return "AnyUp" end
  return (v == "1" or v == 1 or v == true) and "AnyDown" or "AnyUp"
end

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

local function addonLoaded(name)
  local f = (type(C_AddOns) == "table" and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if type(f) ~= "function" then return true end   -- no way to ask: never hold the init hostage
  local ok, r = pcall(f, name)
  return (ok and r) and true or false
end

--- Plain-data deep copy: strings, numbers, booleans, tables. Functions, userdata and secret values are dropped,
-- so nothing in the copy can upset the SavedVariables writer.
local function copyPlain(t, depth)
  depth = depth or 0
  if depth > 12 then return nil end
  local out = {}
  for k, v in pairs(t) do
    local tv = type(v)
    if tv == "table" then out[k] = copyPlain(v, depth + 1)
    elseif tv == "string" or tv == "number" or tv == "boolean" then out[k] = v end
  end
  return out
end

local function hasProfiles(t)
  return type(t) == "table" and type(t.profiles) == "table" and next(t.profiles) ~= nil
end

--- Diag-free copy of the profiles into a second SavedVariable (HogHealsDBBackup). Refreshed at init and at logout.
-- If HogHealsDB ever comes up empty again, RealInitialize re-seeds from this one and says so in diag.init. Defaults
-- are stripped for the copy the same way AceDB strips them at logout, so a restore pins nothing.
function HH:WriteBackup(reason)
  local db = self.db
  local raw = db and rawget(db, "sv")
  if type(raw) ~= "table" or type(raw.profiles) ~= "table" then return end
  local defaults = rawget(db, "defaults")
  if defaults then db:RegisterDefaults(nil) end
  local ok, err = pcall(function()
    HogHealsDBBackup = {
      at = date and date("%Y-%m-%d %H:%M:%S") or "", reason = reason or "", addon = self.version,
      session = raw.global and raw.global.diag and raw.global.diag.session,
      schema = raw.global and raw.global.schema,
      profileKeys = copyPlain(raw.profileKeys or {}),
      profiles = copyPlain(raw.profiles),
    }
  end)
  if defaults then db:RegisterDefaults(defaults) end
  if not ok then self:LogError("backup: " .. tostring(err)) end
end

function HH:OnInitialize()
  local sv = rawget(_G, "HogHealsDB")
  if type(sv) == "table" then return self:RealInitialize("direct") end
  -- No SavedVariables at this event. Two known ways that happens, one rule: do not build an empty DB yet.
  --  (a) AceAddon fired us from ANOTHER addon's ADDON_LOADED before ours (client says we are not loaded yet).
  --  (b) The client fired OUR event without the table (Forever beta, 2026-09-18: every load since 23:55, while
  --      the same client writes the file fine at logout). Whether the table shows up later is what diag.init
  --      and /hh svinfo now record.
  -- Wait for our own ADDON_LOADED (a), then for PLAYER_LOGIN via OnEnable (b). Whatever is there then is used,
  -- else the backup, else fresh. Every module reads HH.db lazily, nothing needs the DB before OnEnable.
  self._initDeferredBy = tostring(self.baseName)
  self._svAtEvent = { event = tostring(self.baseName), rawget = type(sv), index = type(_G.HogHealsDB),
    loaded = addonLoaded(ADDON), gMeta = getmetatable(_G) ~= nil }
  if not addonLoaded(ADDON) then
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, _, name)
      if name == ADDON then
        f:UnregisterAllEvents()
        local now = type(rawget(_G, "HogHealsDB"))
        HH._svAtEvent.ownEvent = now
        if now == "table" then HH:RealInitialize("deferred:ADDON_LOADED") end
      end
    end)
  end
end

--- Is the SavedVariables global still the table AceDB holds? Called 5 s and 30 s after login. A "SWAPPED" here
-- means the client assigned HogHealsDB AFTER we built the DB (late/async load): everything the session saves
-- would then be written from the wrong table.
function HH:CheckSVSwap(tag)
  local e = self._initEntry
  if not e or not self.db then return end
  local cur = rawget(_G, "HogHealsDB")
  local same = rawequal(cur, rawget(self.db, "sv"))
  e["sv@" .. tag] = type(cur) .. (same and ":same" or ":SWAPPED")
  if not same then self:LogError("HogHealsDB global replaced under AceDB at " .. tag) end
end

--- The real DB init. `how` records which path got us here (direct / deferred / enable fallback).
function HH:RealInitialize(how)
  if self.db then return end
  local sv, backup = rawget(_G, "HogHealsDB"), rawget(_G, "HogHealsDBBackup")
  local svPresent, hadProfiles, restored = type(sv), hasProfiles(sv), false
  if not hadProfiles and hasProfiles(backup) then
    HogHealsDB = {
      profileKeys = copyPlain(backup.profileKeys or {}),
      global = { schema = backup.schema },
      profiles = copyPlain(backup.profiles),
    }
    restored = true
  end
  local defaults = self.defaults or { profile = {}, global = {} }
  self.db = LibStub("AceDB-3.0"):New("HogHealsDB", defaults, true)
  if self.Migrate then self.Migrate.Run(self.db) end
  local g = self.db.global
  g.diag = g.diag or {}
  g.diag.errors = g.diag.errors or {}
  g.diag.session = (g.diag.session or 0) + 1
  -- What this init saw. Read off disk after the next wipe: svPresent/hadProfiles say whether the client handed us
  -- the file, baseName/trace say which event AceAddon fired us from, restored says the backup did its job.
  g.diag.init = g.diag.init or {}
  g.diag.init[#g.diag.init + 1] = {
    at = date and date("%Y-%m-%d %H:%M:%S") or "", session = g.diag.session, how = how or "direct",
    svPresent = svPresent, hadProfiles = hadProfiles, restored = restored,
    backup = type(backup), backupAt = type(backup) == "table" and tostring(backup.at) or nil,
    loaded = addonLoaded(ADDON), loggedIn = (type(IsLoggedIn) == "function" and IsLoggedIn()) and true or false,
    baseName = tostring(self.baseName), deferredBy = self._initDeferredBy, trace = table.concat(loadTrace, ","),
    svAtEvent = self._svAtEvent, late = (self._svAtEvent ~= nil and svPresent == "table") or false,
    stack = type(debugstack) == "function" and debugstack(2, 6, 0) or "",
  }
  while #g.diag.init > 8 do table.remove(g.diag.init, 1) end
  self._initEntry = g.diag.init[#g.diag.init]
  for _, e in ipairs(self.errors) do  -- anything caught before the DB existed
    g.diag.errors[#g.diag.errors + 1] = { msg = e.msg, session = g.diag.session, at = "pre-db" }
  end
  self:WriteBackup(restored and "init-restored" or "init")
  self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
  self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
  self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
  for _, m in pairs(self.modules) do self:SafeCall(m, "OnInitialize") end
  self:RegisterChatCommand("hh", "SlashCommand")
  self:RegisterChatCommand("hogheals", "SlashCommand")
  self:RegisterSlash("svinfo", function()
    local e = self._initEntry
    self:Print(("session %d via %s | SV at init: %s, profiles=%s | restored from backup: %s | backup: %s (%s)"):format(
      g.diag.session, e.how, e.svPresent, tostring(e.hadProfiles), tostring(e.restored), e.backup, tostring(e.backupAt)))
    local a = e.svAtEvent
    if a then
      self:Print(("at ADDON_LOADED(%s): rawget=%s index=%s loaded=%s ownEvent=%s -> arrived late: %s"):format(
        tostring(a.event), tostring(a.rawget), tostring(a.index), tostring(a.loaded), tostring(a.ownEvent), tostring(e.late)))
    else
      self:Print("SV was present at ADDON_LOADED(" .. e.baseName .. ")")
    end
    self:Print(("after login: 5s=%s 30s=%s"):format(tostring(e["sv@5s"]), tostring(e["sv@30s"])))
    local live = table.concat(loadTrace, ",")
    self:Print("load trace: " .. (live ~= "" and live or "(empty)"))
  end, "why the profile is what it is (SavedVariables forensics)")
end

function HH:OnEnable()
  if not self.db then self:RealInitialize("enable:" .. tostring(self._initDeferredBy)) end
  self._enabled = true
  if C_Timer and C_Timer.After then
    C_Timer.After(5, function() self:CheckSVSwap("5s") end)
    C_Timer.After(30, function() self:CheckSVSwap("30s") end)
  end
  -- Own frame, created after every library's, so AceDB has already stripped defaults when this runs. Fires on
  -- /reload and on logout: the backup on disk is never older than the main file.
  local logoutFrame = CreateFrame("Frame")
  logoutFrame:RegisterEvent("PLAYER_LOGOUT")
  logoutFrame:SetScript("OnEvent", function() HH:WriteBackup("logout") end)
  if self.InitGroupSize then self:InitGroupSize() end
  if self.InitQueue then self:InitQueue() end
  for _, m in pairs(self.modules) do self:SafeCall(m, "OnEnable") end
  -- The client tells us when tainted code (ours) touched something protected or Blizzard-only, and WHICH function.
  -- Without this the only evidence is a popup the player has to describe.
  for _, ev in ipairs({ "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" }) do
    pcall(self.RegisterEvent, self, ev, function(event, addon, func)
      if type(addon) == "string" and addon:find("^HogHeals") then
        self:LogError(("%s: %s called %s%s"):format(event, addon, tostring(func), InCombatLockdown() and " (in combat)" or ""))
      end
    end)
  end
  self:SafeCall(self, "SnapshotClient")
  -- Blizzard frame state over time: at enable, 10 s after entering the world (Edit Mode has applied its layout by
  -- then), and at first combat. If something re-shows the frames we hid, this says when.
  self.db.global.diag.blizzFrames = { atEnable = self:BlizzardFrameState() }
  self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if C_Timer and C_Timer.After then
      C_Timer.After(10, function() self.db.global.diag.blizzFrames.after10s = self:BlizzardFrameState() end)
    end
  end)
  -- Values may only turn secret once combat starts: probe again on the first pull of the session.
  self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    if self:SafeCall(self, "SnapshotClient") then
      local d = self.db.global.diag
      d.combatProbe = d.client and d.client.secretProbe
      d.blizzFrames = d.blizzFrames or {}
      d.blizzFrames.atCombat = self:BlizzardFrameState()
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

--- One line per Blizzard group frame: shown? visible (parents included)? who is the parent? Answers "we hid it,
-- why is it still there" without a screenshot.
function HH:BlizzardFrameState()
  local out = {}
  for _, name in ipairs({ "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer", "CompactRaidFrameManager", "PlayerCastingBarFrame" }) do
    local f = _G[name]
    if type(f) == "table" then
      local parent = f.GetParent and f:GetParent()
      local pname = parent and ((parent.GetName and parent:GetName()) or "(unnamed)") or "nil"
      out[#out + 1] = ("%s shown=%s visible=%s parent=%s"):format(name, tostring(f.IsShown and f:IsShown()), tostring(f.IsVisible and f:IsVisible()), pname)
      if name == "PartyFrame" and type(f.PartyMemberFramePool) == "table" and f.PartyMemberFramePool.EnumerateActive then
        local n, vis = 0, 0
        for m in f.PartyMemberFramePool:EnumerateActive() do n = n + 1; if m.IsVisible and m:IsVisible() then vis = vis + 1 end end
        out[#out + 1] = ("PartyFrame members active=%d visible=%d"):format(n, vis)
      end
    else
      out[#out + 1] = name .. " = " .. type(f)
    end
  end
  return table.concat(out, " ; ")
end

--- Write what this client IS into SavedVariables (read off disk after a /reload; see docs/TESTING-BETA.md).
function HH:SnapshotClient()
  local diag = self.db.global.diag
  local version, build, builddate, toc = GetBuildInfo()
  local probes = {}
  for _, path in ipairs({
    "loadstring_untainted", "C_UnitAuras.AddPrivateAuraAnchor", "C_UnitAuras.GetAuraDataByIndex", "UnitAura",
    "UnitGetIncomingHeals", "C_Secrets", "issecretvalue", "C_RestrictedActions", "SecureHandlerWrapScript",
    "C_GamePad", "PlayerCastingBarFrame", "CastingBarFrame", "PartyFrame", "PartyMemberFrame1", "CompactPartyFrame", "CompactRaidFrameContainer", "CompactRaidFrameManager", "C_AddOns.GetAddOnMetadata", "C_Spell.GetSpellInfo", "GetSpellInfo", "C_EditMode", "Settings.OpenToCategory",
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
    -- widget methods that resolve a secret for us (Range.lua depends on the first one)
    for _, m in ipairs({ "SetAlphaFromBoolean", "SetShownFromBoolean", "SetVertexColorFromBoolean" }) do
      sp["method." .. m] = type(UIParent[m])
    end
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
  -- Damage-meter feasibility (asked 2026-09-17). On restricted-API clients addons lose the combat log and are meant
  -- to re-display Blizzard's own meter through C_DamageMeter. Record what THIS client really offers.
  local meter = { api = probe("C_DamageMeter"), combatLogFn = probe("CombatLogGetCurrentEventInfo"), cCombatLog = probe("C_CombatLog"),
    blizzFrame = probe("DamageMeter"), enumType = "", keys = "", calls = {} }
  do
    -- Do NOT test-register COMBAT_LOG_EVENT_UNFILTERED here. On a restricted client that is a FORBIDDEN action:
    -- pcall does not contain it, the player gets "HogHeals has been blocked from an action only available to the
    -- Blizzard UI" with a Disable button (happened 2026-09-17, first build of this probe). Whether the combat log
    -- is open is inferred instead: CombatLogGetCurrentEventInfo present = classic-style access.
    local names = {}
    if type(C_DamageMeter) == "table" then
      for k, v in pairs(C_DamageMeter) do
        names[#names + 1] = tostring(k)
        -- zero-argument getters only, under pcall: what comes back, and is it secret?
        if type(v) == "function" and (tostring(k):match("^GetAvailable") or tostring(k):match("^Is")) then
          local r = { pcall(v) }
          local isv = type(issecretvalue) == "function" and issecretvalue or function() return false end
          local first = r[2]
          local desc = r[1] and (type(first) .. (isv(first) and ":secret" or "")) or ("ERR " .. tostring(first):sub(1, 80))
          if r[1] and type(first) == "table" and not isv(first) then
            local n, sample = 0, {}
            for kk, vv in pairs(first) do
              n = n + 1
              if n <= 12 then sample[#sample + 1] = tostring(kk) .. "=" .. type(vv) .. (isv(vv) and ":secret" or "") end
            end
            desc = desc .. "[" .. n .. "] " .. table.concat(sample, " ")
          end
          meter.calls[tostring(k)] = desc
        end
      end
    end
    table.sort(names)
    meter.keys = table.concat(names, ",")
    -- Shape of one session: GetCombatSessionFromType(type) is a read-only one-argument getter. Record the field
    -- names and types of the result, which are secret, and the first element of any nested list. This is what the
    -- meter UI will be written against, so it has to come from the client, not from memory of retail.
    local isv = type(issecretvalue) == "function" and issecretvalue or function() return false end
    local function describe(t, depth)
      local keys, n = {}, 0
      for k, v in pairs(t) do
        n = n + 1
        if n <= 24 then
          local d = tostring(k) .. "=" .. type(v) .. (isv(v) and ":secret" or "")
          if type(v) == "table" and not isv(v) and depth < 2 then
            local first = v[1]
            if first ~= nil then d = d .. "[" .. #v .. "]{" .. describe(type(first) == "table" and first or { value = first }, depth + 1) .. "}"
            else d = d .. "{" .. describe(v, depth + 1) .. "}" end
          end
          keys[#keys + 1] = d
        end
      end
      table.sort(keys)
      return table.concat(keys, " ")
    end
    if type(C_DamageMeter) == "table" and type(C_DamageMeter.GetCombatSessionFromType) == "function" and Enum and Enum.DamageMeterType then
      local st, stKeys = Enum.DamageMeterSessionType, {}
      if type(st) == "table" then for k, v in pairs(st) do stKeys[#stKeys + 1] = tostring(k) .. "=" .. tostring(v) end table.sort(stKeys) end
      meter.enumSessionType = table.concat(stKeys, ",")
      local sessionType = (type(st) == "table" and (st.Current or st.Overall or st.Latest)) or 0
      for _, tname in ipairs({ "DamageDone", "HealingDone" }) do
        local ty = Enum.DamageMeterType[tname]
        if ty ~= nil then
          -- measured 2026-09-17: usage is GetCombatSessionFromType(sessionType, type)
          local ok, r = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, ty)
          meter["session." .. tname] = ok and (type(r) == "table" and describe(r, 0) or (type(r) .. (isv(r) and ":secret" or ""))) or ("ERR " .. tostring(r):sub(1, 120))
        end
      end
      local ok, r = pcall(C_DamageMeter.GetAvailableCombatSessions)
      if ok and type(r) == "table" and type(r[1]) == "table" then meter["availableSession[1]"] = describe(r[1], 0) end
    end
    if type(DamageMeter) == "table" then
      local fn = {}
      for k, v in pairs(DamageMeter) do if type(v) == "function" then fn[#fn + 1] = tostring(k) end end
      table.sort(fn)
      meter.blizzFrameFns = table.concat(fn, ",")
    end
    local e, en = Enum and Enum.DamageMeterType, {}
    if type(e) == "table" then for k, v in pairs(e) do en[#en + 1] = tostring(k) .. "=" .. tostring(v) end table.sort(en) end
    meter.enumType = table.concat(en, ",")
  end
  -- Aura data secrecy (for rebuilding the Cell-style "dispellable by me" icon). Read-only: first HELPFUL aura on
  -- the player and the first HARMFUL|RAID (= dispellable by my class, Blizzard's own filter) aura on the player.
  local aura = { api = probe("C_UnitAuras.GetAuraDataByIndex"), unitAuras = probe("C_UnitAuras.GetUnitAuras"),
    shouldBeSecret = probe("C_Secrets.ShouldAurasBeSecret") }
  do
    local get = type(C_UnitAuras) == "table" and C_UnitAuras.GetAuraDataByIndex
    local isv = type(issecretvalue) == "function" and issecretvalue or function() return false end
    if type(get) == "function" then
      for _, filter in ipairs({ "HELPFUL", "HARMFUL", "HARMFUL|RAID" }) do
        local ok, a = pcall(get, "player", 1, filter)
        if not ok then aura[filter] = "ERR " .. tostring(a):sub(1, 100)
        elseif type(a) ~= "table" then aura[filter] = "none (" .. type(a) .. ")"
        else
          local keys = {}
          for k, v in pairs(a) do keys[#keys + 1] = tostring(k) .. "=" .. type(v) .. (isv(v) and ":secret" or "") end
          table.sort(keys)
          aura[filter] = table.concat(keys, " ")
        end
      end
    end
    if type(C_Secrets) == "table" and type(C_Secrets.ShouldAurasBeSecret) == "function" then
      local ok, r = pcall(C_Secrets.ShouldAurasBeSecret)
      aura.shouldAurasBeSecretNow = ok and tostring(r) or ("ERR " .. tostring(r):sub(1, 80))
    end
  end
  -- Nameplate / quest feasibility (asked 2026-09-17): quest icon on enemy nameplates, nameplate customisation,
  -- minimap quest blips. Read-only: table key lists + a few cvars. No frames touched.
  local np = {}
  do
    local function keysOf(tname)
      local t = _G[tname]
      if type(t) ~= "table" then return type(t) end
      local k = {}
      for name in pairs(t) do k[#k + 1] = tostring(name) end
      table.sort(k)
      return table.concat(k, ",")
    end
    np.C_NamePlate = keysOf("C_NamePlate")
    np.C_TooltipInfo = keysOf("C_TooltipInfo")
    np.C_QuestLog_count = (type(C_QuestLog) == "table") and (function() local n = 0 for _ in pairs(C_QuestLog) do n = n + 1 end return n end)() or "nil"
    np.C_QuestLog_sample = (type(C_QuestLog) == "table") and table.concat((function()
      local k = {}
      for name in pairs(C_QuestLog) do if tostring(name):match("Objective") or tostring(name):match("Quests") then k[#k + 1] = tostring(name) end end
      table.sort(k) return k end)(), ",") or "nil"
    np.C_Minimap = keysOf("C_Minimap")
    np.C_Map_HasQuestPOI = probe("C_QuestLog.GetQuestsOnMap") .. "/" .. probe("C_Map.GetMapInfo")
    np.NamePlateDriverFrame = probe("NamePlateDriverFrame")
    np.ShouldUnitHealthMaxBeSecret = probe("C_Secrets.ShouldUnitHealthMaxBeSecret")
    for _, cv in ipairs({ "nameplateShowEnemies", "nameplateShowFriends", "nameplateShowAll", "nameplateShowQuestObjectives", "minimapShowQuestBlobs", "questPOI" }) do
      local ok, v = pcall(GetCVar, cv)
      np["cvar." .. cv] = ok and tostring(v) or ("ERR " .. tostring(v):sub(1, 60))
    end
    -- what a nameplate looks like right now, if any is on screen
    if type(C_NamePlate) == "table" and type(C_NamePlate.GetNamePlates) == "function" then
      local ok, plates = pcall(C_NamePlate.GetNamePlates)
      if ok and type(plates) == "table" then
        np.platesOnScreen = #plates
        local pl = plates[1]
        if type(pl) == "table" then
          local parts = {}
          for k, v in pairs(pl) do parts[#parts + 1] = tostring(k) .. "=" .. type(v) end
          table.sort(parts)
          np.plate1 = table.concat(parts, " ")
          local uf = pl.UnitFrame
          if type(uf) == "table" then
            local u = {}
            for k, v in pairs(uf) do if type(v) == "table" then u[#u + 1] = tostring(k) end end
            table.sort(u)
            np.plate1UnitFrameChildren = table.concat(u, ",")
          end
        end
      else
        np.platesOnScreen = "ERR " .. tostring(plates):sub(1, 60)
      end
    end
  end
  diag.client = {
    nameplates = np,
    aura = aura,
    meter = meter,
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
