-- HogHeals core: addon object, module registry, DB, slash entry.
local ADDON, ns = ...

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

--- Call obj[method](obj, ...) capturing any error into HH.errors instead of breaking the caller.
function HH:SafeCall(obj, method, ...)
  local fn = type(obj) == "table" and obj[method] or nil
  if type(fn) ~= "function" then return true end
  local ok, err = pcall(fn, obj, ...)
  if not ok then self:LogError(tostring(err)) end
  return ok, err
end

function HH:LogError(msg)
  self.errors[#self.errors + 1] = { time = GetTime and GetTime() or 0, msg = msg }
  if #self.errors > 200 then table.remove(self.errors, 1) end
  if not self._errorNoticeShown then
    self._errorNoticeShown = true
    self:Print("An error was caught and logged. Type /hh errors to see it.")
  end
end

function HH:OnInitialize()
  local defaults = self.defaults or { profile = {}, global = {} }
  self.db = LibStub("AceDB-3.0"):New("HogHealsDB", defaults, true)
  if self.Migrate then self.Migrate.Run(self.db) end
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
