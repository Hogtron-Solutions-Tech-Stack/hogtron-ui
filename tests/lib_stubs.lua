-- LibStub stand-ins for libraries that need a real UI to load (AceGUI/AceConfig,
-- LibSharedMedia, LibRangeCheck, LibHealComm, LDB/DBIcon). Real Ace3 core
-- libs (AceAddon/AceDB/AceEvent/AceTimer/AceConsole/AceSerializer/LibDeflate)
-- load for real from HogHeals/Libs. Loaded AFTER LibStub+CallbackHandler.
assert(LibStub, "LibStub must be loaded before lib_stubs.lua")
MockLibs = {}

do -- LibSharedMedia-3.0
  local lsm = LibStub:NewLibrary("LibSharedMedia-3.0", 999999)
  lsm.MediaType = { FONT = "font", STATUSBAR = "statusbar", BORDER = "border", BACKGROUND = "background", SOUND = "sound" }
  lsm._db = { font = { ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF" }, statusbar = { Blizzard = "Interface\\TargetingFrame\\UI-StatusBar" } }
  function lsm:Register(kind, name, path) self._db[kind] = self._db[kind] or {} self._db[kind][name] = path return true end
  function lsm:Fetch(kind, name) return (self._db[kind] or {})[name] or (self._db[kind] and select(2, next(self._db[kind]))) end
  function lsm:List(kind) local t = {} for k in pairs(self._db[kind] or {}) do t[#t + 1] = k end table.sort(t) return t end
  function lsm:HashTable(kind) return self._db[kind] or {} end
  function lsm:GetDefault(kind) return (select(1, next(self._db[kind] or {}))) end
  function lsm:IsValid(kind, name) return (self._db[kind] or {})[name] ~= nil end
  lsm.RegisterCallback = function() end
end

do -- AceGUI-3.0 / AceConfig-3.0 / AceConfigDialog-3.0 / AceConfigRegistry-3.0 / AceDBOptions-3.0
  local gui = LibStub:NewLibrary("AceGUI-3.0", 999999)
  function gui:Create(kind) local w = CreateFrame("Frame") w._widget = kind
    for _, m in ipairs({ "SetTitle", "SetLayout", "AddChild", "SetCallback", "SetText", "SetLabel", "SetList", "SetValue", "SetWidth", "SetFullWidth", "SetStatusText", "SetHeight", "SetFullHeight", "SetDisabled", "SetImage", "SetImageSize" }) do
      w[m] = function(self, ...) self._last[m] = { ... } end end
    w.frame = w
    function w:Release() self._released = true end
    return w end
  local reg = LibStub:NewLibrary("AceConfigRegistry-3.0", 999999)
  reg.tables = {}
  function reg:RegisterOptionsTable(name, tbl) self.tables[name] = tbl end
  function reg:NotifyChange(name) self.notified = name end
  function reg:GetOptionsTable(name) return self.tables[name] end
  local dlg = LibStub:NewLibrary("AceConfigDialog-3.0", 999999)
  dlg.opened = {}
  function dlg:AddToBlizOptions(name, display, parent) self.bliz = self.bliz or {} self.bliz[#self.bliz + 1] = { name, display, parent } return CreateFrame("Frame"), name end
  function dlg:Open(name) self.opened[#self.opened + 1] = name end
  function dlg:Close(name) end
  function dlg:SetDefaultSize() end
  function dlg:SelectGroup(name, ...) self.selected = { name, ... } end
  local cfg = LibStub:NewLibrary("AceConfig-3.0", 999999)
  function cfg:RegisterOptionsTable(name, tbl, slash) reg:RegisterOptionsTable(name, tbl) cfg.slash = slash end
  local dbo = LibStub:NewLibrary("AceDBOptions-3.0", 999999)
  function dbo:GetOptionsTable(db) return { type = "group", name = "Profiles", args = { current = { type = "description", name = "profiles stub" } } } end
  MockLibs.registry, MockLibs.dialog = reg, dlg
end

do -- LibRangeCheck-3.0
  local rc = LibStub:NewLibrary("LibRangeCheck-3.0", 999999)
  function rc:GetRange(unit) local m = MockUnits[unit] if not m then return nil end
    if m.distance then return m.distance, m.distance end
    if m.inRange == false then return 45, nil end return 0, 40 end
  function rc:GetFriendMaxChecker(range) return function(u) local min = rc:GetRange(u) return min ~= nil and min <= range end end
  rc.RegisterCallback = function() end
  rc.CHECKERS_CHANGED = "CHECKERS_CHANGED"
end

do -- LibHealComm-4.0
  local hc = LibStub:NewLibrary("LibHealComm-4.0", 999999)
  hc.ALL_HEALS = 0x0f; hc.CASTED_HEALS = 0x01; hc.OVERTIME_HEALS = 0x02
  function hc:GetHealAmount(guid, bitFlag, time, casterGUID)
    for u, m in pairs(MockUnits) do if (m.guid or ("Player-" .. u)) == guid then
      if casterGUID then return casterGUID == "Player-0" and (m.incomingMine or 0) or (m.incomingOthers or 0) end
      return (m.incomingMine or 0) + (m.incomingOthers or 0)
    end end
    return nil
  end
  function hc:GetOthersHealAmount(guid) local all = hc:GetHealAmount(guid) or 0 local mine = hc:GetHealAmount(guid, nil, nil, "Player-0") or 0 return all - mine end
  function hc:GetHealModifier() return 1 end
  hc.RegisterCallback = function() end
  hc.UnregisterCallback = function() end
end

do -- LibDataBroker-1.1 / LibDBIcon-1.0
  local ldb = LibStub:NewLibrary("LibDataBroker-1.1", 999999)
  ldb.objects = {}
  function ldb:NewDataObject(name, obj) self.objects[name] = obj return obj end
  function ldb:GetDataObjectByName(name) return self.objects[name] end
  -- Like the real library: Register() makes a 31x31 "LibDBIcon10_<name>" button on the Minimap with the ring + disc
  -- art and a drag script, keeps it in lib.objects, fires LibDBIcon_IconCreated (the Buttons drawer listens).
  local icon = LibStub:NewLibrary("LibDBIcon-1.0", 999999)
  icon.registered = {}
  icon.objects = {}
  icon.callbacks = LibStub("CallbackHandler-1.0"):New(icon)
  function icon:Register(name, obj, db)
    self.registered[name] = { obj = obj, db = db }
    local b = CreateFrame("Button", "LibDBIcon10_" .. name, Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM") b:SetFixedFrameStrata(true)
    b:SetFrameLevel(8) b:SetFixedFrameLevel(true)          -- the real library pins both
    b.dataObject, b.db = obj, db
    b.overlay = b:CreateTexture(nil, "OVERLAY") b.overlay:SetTexture(136430)
    b.background = b:CreateTexture(nil, "BACKGROUND") b.background:SetTexture(136467)
    b.icon = b:CreateTexture(nil, "ARTWORK") b.icon:SetTexture(obj and obj.icon)
    b:SetPoint("CENTER", Minimap, "CENTER", 52, 52)
    b:SetScript("OnDragStart", function() end)
    self.objects[name] = b
    if db and db.hide then b:Hide() end
    self.callbacks:Fire("LibDBIcon_IconCreated", b, name)
  end
  function icon:Hide(name) local b = self.objects[name] if b then b:Hide() end end
  function icon:Show(name) local b = self.objects[name] if b then b:Show() end end
  function icon:Refresh() end
  function icon:IsRegistered(name) return self.objects[name] ~= nil end
  function icon:GetMinimapButton(name) return self.objects[name] end
  function icon:GetButtonList() local out = {} for n in pairs(self.objects) do out[#out + 1] = n end table.sort(out) return out end
end
