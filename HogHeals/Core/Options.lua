-- Options shell: one AceConfig dialog, one tab per module. /hh opens it.
local ADDON, ns = ...
local HH = HogHeals

local registered = false

local function generalTab()
  return {
    type = "group", name = "General", order = 1,
    args = {
      version = { type = "description", order = 1, name = "HogHeals " .. tostring(HH.version) .. "\nHealer-first UI for WoW: Forever / Classic.\n" },
      locked = {
        type = "toggle", order = 2, name = "Lock frames", desc = "Unlock to drag the layout anchor.",
        get = function() return HH.db.profile.locked end,
        set = function(_, v) HH:SetLocked(v) end,
      },
      minimap = {
        type = "toggle", order = 3, name = "Minimap button",
        get = function() return not HH.db.profile.minimap.hide end,
        set = function(_, v) HH.db.profile.minimap.hide = not v; HH:UpdateMinimap() end,
      },
      wizard = {
        type = "execute", order = 4, name = "Run setup wizard",
        func = function() if HH.RunWizard then HH:RunWizard() end end,
      },
      errors = {
        type = "execute", order = 5, name = "Show caught errors",
        func = function() HH:SlashCommand("errors") end,
      },
    },
  }
end

--- Build the full options table (called lazily so modules can register first).
function HH.OptionsTable()
  local t = { type = "group", name = "HogHeals", childGroups = "tab", args = { general = generalTab() } }
  local order = 10
  for name, m in pairs(HH.modules) do
    if m.GetOptions then
      local ok, tab = pcall(m.GetOptions, m)
      if ok and type(tab) == "table" then
        tab.order = tab.order or order
        t.args[name] = tab
        order = order + 1
      elseif not ok then
        HH:LogError("options for " .. name .. ": " .. tostring(tab))
      end
    end
  end
  return t
end

--- /hh opens our own window (Core/Panel.lua). The Ace dialog stays reachable as /hh ace: it is the fallback if
-- the panel is not loaded (a brand-new file needs a full client restart, /reload alone will not pick it up).
function HH:OpenOptions()
  if self.Panel and self.Panel.Toggle then self.Panel.Toggle() return end
  self:OpenAceOptions()
end

function HH:OpenAceOptions()
  local AceConfig = LibStub("AceConfig-3.0", true)
  local Dialog = LibStub("AceConfigDialog-3.0", true)
  if not AceConfig or not Dialog then self:Print("AceConfig not available.") return end
  if not registered then
    AceConfig:RegisterOptionsTable("HogHeals", HH.OptionsTable)
    if Dialog.SetDefaultSize then Dialog:SetDefaultSize("HogHeals", 720, 560) end
    registered = true
  end
  Dialog:Open("HogHeals")
end

function HH:SetLocked(locked)
  self.db.profile.locked = locked and true or false
  local Frames = self.modules.Frames
  if Frames and HogHealsFrames and HogHealsFrames.Headers and HogHealsFrames.Headers.SetLocked then
    HogHealsFrames.Headers.SetLocked(self.db.profile.locked)
  end
  for _, m in pairs(self.modules) do
    if m.SetLocked then self:SafeCall(m, "SetLocked", self.db.profile.locked) end
  end
  self:Print(self.db.profile.locked and "Frames locked." or "Frames unlocked — drag the anchor, then /hh lock.")
end

function HH:UpdateMinimap()
  local icon = LibStub("LibDBIcon-1.0", true)
  if not icon then return end
  if self.db.profile.minimap.hide then icon:Hide("HogHeals") else icon:Show("HogHeals") end
end

function HH:InitMinimap()
  local LDB = LibStub("LibDataBroker-1.1", true)
  local icon = LibStub("LibDBIcon-1.0", true)
  if not LDB or not icon then return end
  local obj = LDB:NewDataObject("HogHeals", {
    type = "launcher", text = "HogHeals", icon = "Interface\\Icons\\Spell_Holy_HolyBolt",
    OnClick = function(_, button)
      if button == "RightButton" then HH:SetLocked(not HH.db.profile.locked) else HH:OpenOptions() end
    end,
    OnTooltipShow = function(tt) tt:AddLine("HogHeals") tt:AddLine("Left: options. Right: lock/unlock.") end,
  })
  icon:Register("HogHeals", obj, self.db.profile.minimap)
end

HH:RegisterSlash("ace", function() HH:OpenAceOptions() end, "open the old Ace options window (fallback)")
HH:RegisterSlash("lock", function() HH:SetLocked(true) end, "lock the frames")
HH:RegisterSlash("unlock", function() HH:SetLocked(false) end, "unlock to drag the anchor")
HH:RegisterSlash("config", function() HH:OpenOptions() end, "open options")
HH:RegisterSlash("wizard", function() if HH.RunWizard then HH:RunWizard() end end, "run the setup wizard")
HH:RegisterSlash("version", function() HH:Print("HogHeals " .. tostring(HH.version)) end, "print version")

-- Hook into the enable cycle without editing Core.lua: wrap OnEnable once.
local origOnEnable = HH.OnEnable
function HH:OnEnable(...)
  origOnEnable(self, ...)
  self:InitMinimap()
  if self.modules.Frames and HogHealsFrames and HogHealsFrames.Headers then
    HogHealsFrames.Headers.SetLocked(self.db.profile.locked)
  end
end
