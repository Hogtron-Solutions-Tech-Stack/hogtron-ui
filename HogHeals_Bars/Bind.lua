-- Bind mode: /hh bind (or Options > Bars > Key bindings), hover a slot, press a key. Esc clears. Modifiers combine
-- (SHIFT-CTRL-F), mouse buttons 3-5 bind too. Saved to the character's own binding set when that is the active
-- one. Sean 2026-10-02: "click a button to quick bind, and then I hover over it and then hit the key bind".
--
-- How: while the mode is on, every bar button wears an overlay (a plain Button above it) that takes the mouse -
-- so hovering picks the target and clicking never casts - and one keyboard frame turns presses into Blizzard's
-- binding strings. Keys pressed with nothing hovered pass through (movement keeps working). Combat ends the mode.
HogHealsBars = HogHealsBars or {}
local HHB = HogHealsBars
local HH = HogHeals

local Bind = { overlays = {} }
HHB.Bind = Bind

local CREAM = { 0.96, 0.92, 0.86 }
local CYAN = { 0.13, 0.83, 0.88 }
local GREY = { 0.55, 0.55, 0.60 }
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, UNKNOWN = true }
local MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a = pcall(f, ...)
  if ok then return a end
end

--- Blizzard's binding string for a press: modifiers in Blizzard's order, then the key. nil for a lone modifier.
function Bind.KeyString(key, alt, ctrl, shift)
  if type(key) ~= "string" or key == "" or MODIFIER_KEYS[key] then return nil end
  local s = ""
  if alt then s = s .. "ALT-" end
  if ctrl then s = s .. "CTRL-" end
  if shift then s = s .. "SHIFT-" end
  return s .. key
end

local function mods()
  return call(IsAltKeyDown) == true, call(IsControlKeyDown) == true, call(IsShiftKeyDown) == true
end

local function save()
  local set = call(GetCurrentBindingSet)
  if type(SaveBindings) == "function" then pcall(SaveBindings, (set == 2) and 2 or 1) end
end

--- Hotkey text on every bar button after a change (the lib repaints on UPDATE_BINDINGS in game; here as well).
function Bind.Repaint()
  for _, bar in pairs(HHB.Bars.bars) do
    for _, b in ipairs(bar.buttons) do
      if b.UpdateHotkeys then call(b.UpdateHotkeys, b) end
      local o = Bind.overlays[b]
      if o and o.keys then o.keys:SetText(call(b.GetBindings, b) or "") end
    end
  end
end

--- Bind `key` to the target's slot (or clear it on ESCAPE). Returns what was done, for the chat line and tests.
function Bind.Press(key)
  local b = Bind.target
  if not b then return nil end
  if key == "ESCAPE" then
    call(b.ClearBindings, b)
    save()
    Bind.Repaint()
    Bind.last = { b, "cleared" }
    return "cleared"
  end
  local s = Bind.KeyString(key, mods())
  if not s then return nil end
  call(b.SetKey, b, s)
  save()
  Bind.Repaint()
  Bind.last = { b, s }
  return s
end

local function overlayFor(b)
  local o = Bind.overlays[b]
  if o then return o end
  o = CreateFrame("Button", nil, b)
  o:SetAllPoints(b)
  o:SetFrameLevel((b.GetFrameLevel and b:GetFrameLevel() or 1) + 10)
  o:EnableMouse(true)
  o:RegisterForClicks("AnyUp")
  o.bg = o:CreateTexture(nil, "BACKGROUND")
  o.bg:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.0)
  o.bg:SetAllPoints(o)
  o.keys = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.keys:SetPoint("CENTER", o, "CENTER", 0, 0)
  o.keys:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
  o.button = b
  o:SetScript("OnEnter", function(self)
    Bind.target = self.button
    self.bg:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.35)
    self.keys:SetText(call(self.button.GetBindings, self.button) or "")
  end)
  o:SetScript("OnLeave", function(self)
    if Bind.target == self.button then Bind.target = nil end
    self.bg:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.0)
  end)
  o:SetScript("OnMouseDown", function(self, button)
    local key = MOUSE[button]
    if key then Bind.target = self.button Bind.Press(key) end   -- left / right never bind (Blizzard forbids them)
  end)
  o:Hide()
  Bind.overlays[b] = o
  return o
end

local function stripFrame()
  if Bind.strip then return Bind.strip end
  local f = CreateFrame("Frame", "HogHealsBindStrip", UIParent)
  f:SetSize(520, 26)
  f:SetPoint("TOP", UIParent, "TOP", 0, -120)
  f:SetFrameStrata("DIALOG")
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetColorTexture(0.07, 0.07, 0.09, 0.9)
  f.bg:SetAllPoints(f)
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
  f.text:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
  f.text:SetText("Key bindings: hover a slot, press a key. Esc clears it. Mouse 3-5 bind too. /hh bind to finish.")
  -- the keyboard: one frame takes every press while the mode is on; with nothing hovered the press passes through
  f:EnableKeyboard(true)
  f:SetScript("OnKeyDown", function(self, key)
    if not Bind.active or not Bind.target or MODIFIER_KEYS[key] then
      if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
      return
    end
    if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
    Bind.Press(key)
  end)
  f:SetScript("OnEvent", function(_, e) if e == "PLAYER_REGEN_DISABLED" then Bind.Stop("combat") end end)
  pcall(f.RegisterEvent, f, "PLAYER_REGEN_DISABLED")
  f:Hide()
  Bind.strip = f
  return f
end

function Bind.Start()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then HH:Print("Key bindings: not in combat.") return false end
  if HHB.Bars.unavailable or not next(HHB.Bars.bars) then HH:Print("Key bindings: HogUI Bars are off.") return false end
  Bind.active = true
  local n = 0
  for _, bar in pairs(HHB.Bars.bars) do
    for _, b in ipairs(bar.buttons) do
      local o = overlayFor(b)
      o.keys:SetText(call(b.GetBindings, b) or "")
      o:Show()
      n = n + 1
    end
  end
  stripFrame():Show()
  HH:Print("Key bindings on: hover a slot, press a key. /hh bind to finish.")
  Bind.count = n
  return true
end

function Bind.Stop(why)
  if not Bind.active then return false end
  Bind.active, Bind.target = false, nil
  for _, o in pairs(Bind.overlays) do o:Hide() end
  if Bind.strip then Bind.strip:Hide() end
  Bind.Repaint()
  HH:Print(why == "combat" and "Key bindings off (combat)." or "Key bindings saved.")
  return true
end

function Bind.Toggle()
  if Bind.active then return Bind.Stop("done") end
  return Bind.Start()
end

HH:RegisterSlash("bind", function() Bind.Toggle() end, "key bindings: hover a slot on the HogUI bars and press a key (Esc clears)")
