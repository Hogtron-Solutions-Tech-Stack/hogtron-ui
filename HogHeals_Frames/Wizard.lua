-- First-run wizard: class -> layout preset -> bindings preset -> done. Pure state machine + thin AceGUI UI.
HogHealsFrames = HogHealsFrames or {}
local HHF = HogHealsFrames
local HH = HogHeals

local Wizard = {}
HHF.Wizard = Wizard

local STEPS = { "class", "layout", "bindings", "done" }

Wizard.PRESETS = {
  default = { label = "Default", desc = "Balanced sizes for party and raid." },
  compact = { label = "Compact", desc = "Smaller frames, more screen. Good for 40-man." },
  large   = { label = "Large", desc = "Bigger frames and text." },
  accessibility = { label = "Accessibility", desc = "Very large frames, big text, mouse-only bindings, fewer indicators." },
}

Wizard.BINDING_PRESETS = {
  default = "Class defaults (keyboard hover-binds)",
  mouse = "Mouse-only (HealBot style)",
  none = "None — I use my own macros / Clique",
}

function Wizard.New(class)
  return { step = "class", class = class, answers = {} }
end

function Wizard.Next(w, answers)
  for k, v in pairs(answers or {}) do w.answers[k] = v end
  for i, s in ipairs(STEPS) do
    if s == w.step then
      w.step = STEPS[math.min(i + 1, #STEPS)]
      break
    end
  end
  if w.answers.class then w.class = w.answers.class end
  return w
end

local function scaleLayouts(frames, factor, minW, minH)
  for _, name in ipairs(HH.BUCKETS) do
    local l = frames.layouts[name]
    l.width = math.max(minW or 40, math.floor(l.width * factor + 0.5))
    l.height = math.max(minH or 12, math.floor(l.height * factor + 0.5))
  end
end

local function mouseBindings(class)
  local B = function(key, mod, value) return { key = key, mod = mod, type = "spell", value = value } end
  local M = {
    PRIEST = { B("BUTTON1", "", "Flash Heal"), B("BUTTON2", "", "Greater Heal"), B("BUTTON3", "", "Renew"),
               B("BUTTON1", "SHIFT", "Prayer of Healing"), B("BUTTON1", "CTRL", "Dispel Magic"), B("BUTTON1", "ALT", "Power Word: Shield") },
    SHAMAN = { B("BUTTON1", "", "Lesser Healing Wave"), B("BUTTON2", "", "Healing Wave"), B("BUTTON3", "", "Chain Heal"),
               B("BUTTON1", "CTRL", "Cure Poison"), B("BUTTON1", "ALT", "Cure Disease") },
    PALADIN = { B("BUTTON1", "", "Flash of Light"), B("BUTTON2", "", "Holy Light"), B("BUTTON1", "CTRL", "Purify") },
    DRUID = { B("BUTTON1", "", "Regrowth"), B("BUTTON2", "", "Healing Touch"), B("BUTTON3", "", "Rejuvenation"),
              B("BUTTON1", "CTRL", "Remove Curse"), B("BUTTON1", "ALT", "Cure Poison") },
  }
  return M[class] or {}
end

--- Apply answers to the live profile.
function Wizard.Finish(w)
  local frames = HH.db.profile.frames
  local preset = w.answers.preset or "default"
  -- start from defaults so re-running the wizard is predictable
  local d = HH.defaults.profile.frames
  for _, name in ipairs(HH.BUCKETS) do
    for k, v in pairs(d.layouts[name]) do
      if type(v) ~= "table" then frames.layouts[name][k] = v end
    end
  end
  frames.appearance.fontSize = d.appearance.fontSize
  for k, v in pairs(d.indicators) do frames.indicators[k] = v end

  if preset == "compact" then
    scaleLayouts(frames, 0.85)
  elseif preset == "large" then
    scaleLayouts(frames, 1.25)
    frames.appearance.fontSize = 13
  elseif preset == "accessibility" then
    scaleLayouts(frames, 1.6, 160, 40)
    frames.appearance.fontSize = 15
    frames.appearance.healthText = "percent"
    frames.indicators.thresholds = false
    frames.indicators.aoeHealing = false
    frames.indicators.statusIcons = false
    frames.dispel.style = "color"
  end

  local class = w.class or select(2, UnitClass("player"))
  local bp = w.answers.bindings or "default"
  if bp == "mouse" then
    HHF.ClickCast.SetBindings(mouseBindings(class))
  elseif bp == "none" then
    HHF.ClickCast.SetBindings({})
  else
    HHF.ClickCast.SetBindings(HHF.ClickCast.Defaults(class))
  end

  HH.db.profile.wizardDone = true
  w.step = "done"
  HHF.module:ApplyProfile(HH:CurrentBucket())
  return w
end

-- ---------------------------------------------------------------- thin UI
function Wizard.Show()
  local AceGUI = LibStub("AceGUI-3.0", true)
  if not AceGUI then HH:Print("AceGUI missing; wizard unavailable.") return end
  local _, class = UnitClass("player")
  local w = Wizard.New(class)
  w.answers.class = class
  Wizard.Next(w, {})

  local frame = AceGUI:Create("Frame")
  frame:SetTitle("HogHeals setup")
  frame:SetStatusText("Three quick choices. You can change everything later in /hh.")
  frame:SetLayout("Flow")
  frame:SetWidth(460); frame:SetHeight(360)
  frame:SetCallback("OnClose", function(widget) AceGUI:Release(widget) end)

  local presetDrop = AceGUI:Create("Dropdown")
  presetDrop:SetLabel("Layout preset")
  local pv = {}
  for k, v in pairs(Wizard.PRESETS) do pv[k] = v.label .. " — " .. v.desc end
  presetDrop:SetList(pv)
  presetDrop:SetValue("default")
  presetDrop:SetFullWidth(true)
  frame:AddChild(presetDrop)

  local bindDrop = AceGUI:Create("Dropdown")
  bindDrop:SetLabel("Bindings")
  bindDrop:SetList(Wizard.BINDING_PRESETS)
  bindDrop:SetValue("default")
  bindDrop:SetFullWidth(true)
  frame:AddChild(bindDrop)

  local go = AceGUI:Create("Button")
  go:SetText("Finish")
  go:SetFullWidth(true)
  go:SetCallback("OnClick", function()
    local preset = presetDrop.GetValue and presetDrop:GetValue() or "default"
    local bindings = bindDrop.GetValue and bindDrop:GetValue() or "default"
    Wizard.Next(w, { preset = preset })
    Wizard.Next(w, { bindings = bindings })
    Wizard.Finish(w)
    HH:Print("Setup done. /hh to fine-tune, /hh test 10 to preview, /hh unlock to move.")
    frame:Hide()
  end)
  frame:AddChild(go)
  Wizard.frame = frame
  return frame
end

function HH:RunWizard() return Wizard.Show() end

-- Auto-run once per profile on first login (after frames are up).
local origOnEnable = HHF.module.OnEnable
function HHF.module:OnEnable(...)
  origOnEnable(self, ...)
  if not HH.db.profile.wizardDone and C_Timer and C_Timer.After then
    C_Timer.After(3, function() if not HH.db.profile.wizardDone and not InCombatLockdown() then Wizard.Show() end end)
  end
end
