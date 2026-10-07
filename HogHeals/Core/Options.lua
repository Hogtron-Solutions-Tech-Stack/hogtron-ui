-- Options shell: one AceConfig dialog, one tab per module. /hh opens it.
local ADDON, ns = ...
local HH = HogHeals

local registered = false

local function generalTab()
  return {
    type = "group", name = "General", order = 1,
    args = {
      version = { type = "description", order = 1, name = "HogTron UI " .. tostring(HH.version) .. "\nHogTron's UI suite for WoW: Forever / Classic - HogHeals (healer frames), HUD, meter, quests & map, nameplates, chat, unit frames, skin.\n" },
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
      look = {
        type = "group", inline = true, order = 10, name = "Look",
        args = {
          about = { type = "description", order = 0, name = "HogTron: our fonts, flat bars, Blizzard's windows in the same look. Classic: Blizzard's font, bars and windows - every feature stays. Font, text edge and size change live; the style needs a /reload." },
          style = { type = "select", order = 1, name = "Style", values = { hogtron = "HogTron", classic = "Classic (Blizzard look)" },
            get = function() return HH.db.profile.look.style or "hogtron" end,
            set = function(_, v) HH.db.profile.look.style = v; HH:Print("look: type /reload (or press Apply) to switch.") end },
          apply = { type = "execute", order = 1.5, name = "Apply (reload)", desc = "Reloads the UI so the style takes effect.",
            func = function() if type(ReloadUI) == "function" then ReloadUI() end end },
          font = { type = "select", order = 2, name = "Font", values = { ["Inter"] = "Inter", ["Manrope"] = "Manrope", ["Barlow Condensed"] = "Barlow Condensed" },
            disabled = function() return HH.Look.Classic() end,
            get = function() return HH.db.profile.look.font or "Inter" end,
            set = function(_, v) HH.db.profile.look.font = v; HH.Look.Apply(); HH.Look.RefreshModules() end },
          edge = { type = "select", order = 3, name = "Text edge", values = { shadow = "Soft shadow (cleaner)", outline = "Outline" },
            desc = "Window and panel text. Text drawn on a bar (names on frames, plate text) keeps its outline either way.",
            disabled = function() return HH.Look.Classic() end,
            get = function() return HH.db.profile.look.edge or "shadow" end,
            set = function(_, v) HH.db.profile.look.edge = v; HH.Look.Apply() end },
          size = { type = "range", order = 4, name = "Text size", min = -2, max = 4, step = 1,
            get = function() return HH.db.profile.look.size or 0 end,
            set = function(_, v) HH.db.profile.look.size = v; HH.Look.Apply(); HH.Look.RefreshModules() end },
          scale = { type = "description", order = 5, name = function()
            local p = HH.Look.PerfectScale()
            return ("UI scale now %.3f. Pixel-perfect for your screen: %s."):format(HH.Look.CurrentScale(), p and ("%.3f"):format(p) or "unknown")
          end },
          pixel = { type = "execute", order = 6, name = "Make it pixel-perfect",
            desc = "Sets the whole UI scale so every line and letter lands on a real screen pixel (Blizzard's UI resizes too). Undo puts your old scale back.",
            func = function() HH:SlashCommand("look pixel") end },
          unpixel = { type = "execute", order = 7, name = "Undo pixel scale",
            disabled = function() return not HH.db.profile.look.pixel end,
            func = function() HH:SlashCommand("look unpixel") end },
        },
      },
    },
  }
end

--- Build the full options table (called lazily so modules can register first).
function HH.OptionsTable()
  local t = { type = "group", name = "HogTron UI", childGroups = "tab", args = { general = generalTab() } }
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
HH:RegisterSlash("version", function() HH:Print("HogTron UI " .. tostring(HH.version)) end, "print version")

-- Hook into the enable cycle without editing Core.lua: wrap OnEnable once.
local origOnEnable = HH.OnEnable
function HH:OnEnable(...)
  origOnEnable(self, ...)
  self:InitMinimap()
  if self.modules.Frames and HogHealsFrames and HogHealsFrames.Headers then
    HogHealsFrames.Headers.SetLocked(self.db.profile.locked)
  end
end
