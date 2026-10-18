-- Pet bar and stance / shapeshift bar: our own secure buttons on the same layout engine, flat look, bind mode
-- targets (BONUSACTIONBUTTON<i> / SHAPESHIFTBUTTON<i>). Blizzard's PetActionBar / StanceBar hidden.
--
-- Secret-safe: icons, checked state and autocast come straight from the client; the cooldown swipe is drawn only
-- when start and duration are plain numbers. Attributes (the spell behind a stance) are set out of combat only.
HogHealsBars = HogHealsBars or {}
local HHB = HogHealsBars
local HH = HogHeals
local Bars = HHB.Bars

local Extra = {}
HHB.Extra = Extra

local CYAN = { 0.13, 0.83, 0.88 }
local LINE = { 0.20, 0.20, 0.25 }
local function cfg() return HH.db.profile.bars end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
-- Classic-family clients answer flags with 1 / nil, newer ones with true / false; a secret is never a yes we can read.
local function yes(v) return v ~= nil and v ~= false and v ~= 0 and not isSecret(v) end
-- Every return value, nils included. The old { pcall(...) } + unpack(r) stopped at the first nil: this client answers
-- "no" with nil, so GetPetActionInfo's later flags (autocast allowed / on) were dropped in game (2026-10-06).
local function pass(ok, ...) if ok then return ... end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  return pass(pcall(f, ...))
end

-- ------------------------------------------------------------------------------------------------ bindings mixin
--- What bind mode needs from a button that is not the lib's: the same four methods, over one binding name.
local function bindMixin(b, target)
  b.keyBoundTarget = target
  function b:GetBindingAction() return self.keyBoundTarget end
  function b:GetBindings()
    local out = {}
    local n = select("#", GetBindingKey(self.keyBoundTarget))
    for i = 1, n do
      local k = select(i, GetBindingKey(self.keyBoundTarget))
      out[#out + 1] = (type(GetBindingText) == "function" and call(GetBindingText, k)) or k
    end
    return table.concat(out, ", ")
  end
  function b:SetKey(key) call(SetBinding, key, self.keyBoundTarget) end
  function b:ClearBindings()
    for _ = 1, 8 do
      local k = GetBindingKey(self.keyBoundTarget)
      if not k then break end
      local ok = pcall(SetBinding, k, nil)
      if not ok then break end
    end
  end
  function b:UpdateHotkeys()
    local k = GetBindingKey(self.keyBoundTarget)
    local text = k and ((type(GetBindingText) == "function" and call(GetBindingText, k, 1)) or k) or ""
    self.HotKey:SetText(text)
  end
end

local function newButton(bar, name, i, target)
  local b = CreateFrame("CheckButton", name, bar, "SecureActionButtonTemplate")
  b.id, b.hhBar = i, bar
  if b.RegisterForClicks then b:RegisterForClicks(HH.SecureClick and HH.SecureClick() or "AnyUp") end
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints(b)
  b.HotKey = b:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  b.HotKey:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
  b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cooldown:SetAllPoints(b)
  bindMixin(b, target)
  Bars.Dress(b)
  Extra.MakeStateLayers(b)
  if b.HotKey.SetFont then call(b.HotKey.SetFont, b.HotKey, HogHeals.Look.Font() or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", cfg().hotkeySize or 10, "OUTLINE") end
  return b
end

-- ------------------------------------------------------------------------------------------------ active / autocast
-- In game 2026-10-06 (Sean): "these aren't glowing when they are active". These are CheckButtons with no Blizzard art
-- (Bars.Dress strips it), so SetChecked drew nothing, and autocast was a 1 px cyan edge nobody could see. Our own marks:
--   active (Follow, Assist, the stance you are in)  cyan wash + 2 px cyan border inside the button
--   autocast on                                     a cyan glow around the button, pulsing
--   autocast available but off                      a small cyan corner, like Blizzard's corner arrows
local function edgesOn(parent, layer, sub, inset, thick, color, alpha)
  local out = {}
  local spec = { { "TOPLEFT", "TOPRIGHT", nil, thick }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, thick },
    { "TOPLEFT", "BOTTOMLEFT", thick, nil }, { "TOPRIGHT", "BOTTOMRIGHT", thick, nil } }
  local off = { TOPLEFT = { inset, -inset }, TOPRIGHT = { -inset, -inset }, BOTTOMLEFT = { inset, inset }, BOTTOMRIGHT = { -inset, inset } }
  for i, sp in ipairs(spec) do
    local e = parent:CreateTexture(nil, layer, nil, sub)
    e:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    e:SetPoint(sp[1], parent, sp[1], off[sp[1]][1], off[sp[1]][2])
    e:SetPoint(sp[2], parent, sp[2], off[sp[2]][1], off[sp[2]][2])
    if sp[3] then e:SetWidth(sp[3]) end
    if sp[4] then e:SetHeight(sp[4]) end
    out[i] = e
  end
  return out
end

function Extra.MakeStateLayers(b)
  local hh = b.hh
  if not hh or hh.active then return end
  hh.activeFill = b:CreateTexture(nil, "OVERLAY", nil, 1)
  hh.activeFill:SetAllPoints(b)
  hh.activeFill:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.22)
  hh.active = edgesOn(b, "OVERLAY", 2, 1, 2, CYAN, 1)
  -- the glow sits on a child frame so one alpha animation pulses all four sides
  local g = CreateFrame("Frame", nil, b)
  g:SetPoint("TOPLEFT", b, "TOPLEFT", -3, 3)
  g:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -3)
  g:SetFrameLevel(((b.GetFrameLevel and b:GetFrameLevel()) or 1) + 2)
  hh.glowEdges = edgesOn(g, "OVERLAY", 3, 0, 2, CYAN, 0.95)
  local ag = g.CreateAnimationGroup and g:CreateAnimationGroup()
  if ag then
    local a = ag:CreateAnimation("Alpha")
    if a then
      if a.SetFromAlpha then a:SetFromAlpha(1) a:SetToAlpha(0.3) end
      if a.SetDuration then a:SetDuration(0.7) end
    end
    if ag.SetLooping then ag:SetLooping("BOUNCE") end
  end
  hh.glow, hh.pulse = g, ag
  g:Hide()
  hh.canAuto = b:CreateTexture(nil, "OVERLAY", nil, 4)
  hh.canAuto:SetSize(6, 6)
  hh.canAuto:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1)
  hh.canAuto:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.85)
  Extra.SetState(b, false, false, false)
end

-- ------------------------------------------------------------------------------------------------ marks on every bar
-- Sean 2026-10-08 in game, after resizing the bars: "the highlighting is slightly off ... just do the highlighting
-- that's in the pet bar". Blizzard's hover / active box is pinned by the lib to 52 x 51 at a fixed offset (and
-- re-pinned on every update), so any other button size shows it askew. Off, and the pet bar's marks everywhere:
--   hover    cyan edges at half strength
--   pressed  cyan wash while the mouse is down
--   active   the lib's SetChecked (current action, auto-repeat): full edges + wash, as a pet command
--- Blizzard's state art transparent (called at dress and after every lib update, which re-pins it).
function Extra.HideStateArt(b)
  for _, getter in ipairs({ "GetHighlightTexture", "GetCheckedTexture", "GetPushedTexture" }) do
    local t = call(b[getter], b)
    if type(t) == "table" and t.SetAlpha then call(t.SetAlpha, t, 0) end
  end
  for _, k in ipairs({ "HighlightTexture", "CheckedTexture", "PushedTexture" }) do
    local t = rawget(b, k)
    if type(t) == "table" and t.SetAlpha then call(t.SetAlpha, t, 0) end
  end
end

function Extra.SetHover(b, on)
  local hh = b.hh
  if not hh or not hh.hover then return end
  local show = on and not (hh.state and hh.state.active) and hh.backdrop and hh.backdrop:IsShown()
  for _, e in ipairs(hh.hover) do e:SetShown(show and true or false) end
  hh.hovered = on and true or false
end

function Extra.SetPressed(b, on)
  local hh = b.hh
  if hh and hh.pressFill then hh.pressFill:SetShown(on and true or false) end
end

--- The lib's checked state -> the active mark (1 / true both mean on).
function Extra.SetActive(b, on)
  local hh = b.hh
  if not hh or not hh.active then return end
  on = on == true or on == 1
  Extra.SetState(b, on, hh.state and hh.state.autoAllowed, hh.state and hh.state.autoOn)
  if on then for _, e in ipairs(hh.hover or {}) do e:Hide() end elseif hh.hovered then Extra.SetHover(b, true) end
end

--- Give a bar button the marks and the hooks that drive them. Once per button.
function Extra.MakeMarks(b)
  local hh = b.hh
  if not hh or hh.hover then return end
  Extra.MakeStateLayers(b)
  hh.hover = edgesOn(b, "OVERLAY", 1, 1, 2, CYAN, 0.55)
  for _, e in ipairs(hh.hover) do e:Hide() end
  hh.pressFill = b:CreateTexture(nil, "OVERLAY", nil, 0)
  hh.pressFill:SetAllPoints(b)
  hh.pressFill:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.30)
  hh.pressFill:Hide()
  Extra.HideStateArt(b)
  if b.HookScript then
    pcall(b.HookScript, b, "OnEnter", function(self) Extra.SetHover(self, true) end)
    pcall(b.HookScript, b, "OnLeave", function(self) Extra.SetHover(self, false) Extra.SetPressed(self, false) end)
    pcall(b.HookScript, b, "OnMouseDown", function(self) Extra.SetPressed(self, true) end)
    pcall(b.HookScript, b, "OnMouseUp", function(self) Extra.SetPressed(self, false) end)
  end
  Extra.HookChecked(b)
end

--- The lib's SetChecked -> our active mark. Lazy: a button may grow SetChecked after it is dressed.
function Extra.HookChecked(b)
  local hh = b.hh
  if not hh or hh.checkedHooked then return end
  if type(b.SetChecked) == "function" and type(hooksecurefunc) == "function" then
    local ok = pcall(hooksecurefunc, b, "SetChecked", function(self, on) Extra.SetActive(self, on) end)
    hh.checkedHooked = ok and true or nil
  end
end

--- Show the marks for one button. Pure on the button: no API reads.
function Extra.SetState(b, active, autoAllowed, autoOn)
  local hh = b.hh
  if not hh or not hh.active then return end
  hh.activeFill:SetShown(active and true or false)
  for _, e in ipairs(hh.active) do e:SetShown(active and true or false) end
  if autoOn then
    hh.glow:Show()
    if hh.pulse and hh.pulse.Play and not (hh.pulse.IsPlaying and hh.pulse:IsPlaying()) then hh.pulse:Play() end
  else
    if hh.pulse and hh.pulse.Stop then hh.pulse:Stop() end
    hh.glow:Hide()
  end
  hh.canAuto:SetShown((autoAllowed and not autoOn) and true or false)
  hh.state = { active = active and true or false, autoAllowed = autoAllowed and true or false, autoOn = autoOn and true or false }
end

local function paintCooldown(b, start, duration, enable)
  local s, d = num(start), num(duration)
  if s and d and d > 0 and enable ~= 0 and enable ~= false and b.cooldown.SetCooldown then
    b.cooldown:SetCooldown(s, d)
    b.cooldown:Show()
  else
    b.cooldown:Hide()
  end
end

-- ------------------------------------------------------------------------------------------------ pet bar
function Extra.CreatePet()
  if Bars.bars.pet then return Bars.bars.pet end
  local bar = CreateFrame("Frame", "HogUIPetBar", UIParent, "SecureHandlerStateTemplate")
  bar.n, bar.buttons, bar.spec = "pet", {}, { label = "Pet bar" }
  bar:SetMovable(true)
  bar:SetClampedToScreen(true)
  bar:SetFrameStrata("MEDIUM")
  bar.hhOurs = true
  for i = 1, 10 do
    local b = newButton(bar, "HogUIPetButton" .. i, i, "BONUSACTIONBUTTON" .. i)
    b:SetAttribute("type", "pet")
    b:SetAttribute("action", i)
    function b:HasAction() return call(GetPetActionInfo, self.id) ~= nil end
    b:SetScript("OnEnter", function(self)
      if GameTooltip and GameTooltip.SetPetAction then GameTooltip:SetOwner(self, "ANCHOR_RIGHT") call(GameTooltip.SetPetAction, GameTooltip, self.id) GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
    bar.buttons[i] = b
  end
  bar.visPrefix = "[nopet]hide;"   -- no pet, no bar - whatever the visibility option says
  bar.handle = Bars.DragHandle(bar, "Pet bar")
  bar.describe = function() return ("pet bar: %d actions, %s"):format(Extra.petCount or 0, Bars.bars.pet:IsShown() and "shown" or "hidden") end
  Bars.bars.pet = bar
  return bar
end

--- Icons, checked state, autocast and cooldowns from the client. Returns how many actions the pet has.
function Extra.UpdatePet()
  local bar = Bars.bars.pet
  if not bar then return 0 end
  local n = 0
  for i, b in ipairs(bar.buttons) do
    local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled = call(GetPetActionInfo, i)
    if name ~= nil then
      n = n + 1
      local icon = texture
      if yes(isToken) and type(texture) == "string" then icon = rawget(_G, texture) or texture end
      b.icon:SetTexture(icon)
      if b.SetChecked then call(b.SetChecked, b, yes(isActive)) end
      Extra.SetState(b, yes(isActive), yes(autoCastAllowed), yes(autoCastEnabled))
      paintCooldown(b, call(GetPetActionCooldown, i))
    else
      b.icon:SetTexture(nil)
      if b.SetChecked then call(b.SetChecked, b, false) end
      Extra.SetState(b, false, false, false)
      b.cooldown:Hide()
    end
    b:UpdateHotkeys()
    Bars.UpdateCell(b)
  end
  Extra.petCount = n
  return n
end

-- ------------------------------------------------------------------------------------------------ stance bar
function Extra.CreateStance()
  if Bars.bars.stance then return Bars.bars.stance end
  local bar = CreateFrame("Frame", "HogUIStanceBar", UIParent, "SecureHandlerStateTemplate")
  bar.n, bar.buttons, bar.spec = "stance", {}, { label = "Stance / form bar" }
  bar:SetMovable(true)
  bar:SetClampedToScreen(true)
  bar:SetFrameStrata("MEDIUM")
  bar.hhOurs = true
  for i = 1, 10 do
    local b = newButton(bar, "HogUIStanceButton" .. i, i, "SHAPESHIFTBUTTON" .. i)
    b:SetAttribute("type", "spell")
    function b:HasAction() return self.id <= (num(call(GetNumShapeshiftForms)) or 0) end
    b:SetScript("OnEnter", function(self)
      if GameTooltip and GameTooltip.SetShapeshift then GameTooltip:SetOwner(self, "ANCHOR_RIGHT") call(GameTooltip.SetShapeshift, GameTooltip, self.id) GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
    bar.buttons[i] = b
  end
  bar.handle = Bars.DragHandle(bar, "Stance bar")
  bar.describe = function() return ("stance bar: %d forms"):format(Extra.formCount or 0) end
  Bars.bars.stance = bar
  return bar
end

--- Forms from the client: icon, active, castable, and the spell behind each (modern clients hand a spell id,
-- older ones a name - both cast through type = "spell"). Attributes only out of combat. Returns the form count.
function Extra.UpdateStance()
  local bar = Bars.bars.stance
  if not bar then return 0 end
  local n = num(call(GetNumShapeshiftForms)) or 0
  Extra.formCount = n
  bar.countOverride = n > 0 and n or 1
  for i, b in ipairs(bar.buttons) do
    if i <= n then
      local icon, a2, a3, a4 = call(GetShapeshiftFormInfo, i)
      -- modern: icon, isActive, isCastable, spellID; classic: icon, name, isActive, isCastable
      local isActive, spell
      if type(a2) == "string" then spell, isActive = a2, yes(a3) else isActive, spell = yes(a2), a4 end
      b.icon:SetTexture(icon)
      if b.SetChecked then call(b.SetChecked, b, isActive) end
      Extra.SetState(b, isActive, false, false)
      if spell ~= nil and not (type(InCombatLockdown) == "function" and InCombatLockdown()) then
        if b:GetAttribute("spell") ~= spell then b:SetAttribute("spell", spell) end
      end
      paintCooldown(b, call(GetShapeshiftFormCooldown, i))
    else
      b.icon:SetTexture(nil)
      Extra.SetState(b, false, false, false)
      b.cooldown:Hide()
    end
    b:UpdateHotkeys()
    Bars.UpdateCell(b)
  end
  if n == 0 then bar:Hide() elseif cfg().list.stance.enabled ~= false then bar:Show() end
  return n
end

-- ------------------------------------------------------------------------------------------------ build / events
Extra.BLIZZARD = { "PetActionBar", "PetActionBarFrame", "StanceBar", "StanceBarFrame", "ShapeshiftBarFrame", "PossessBarFrame" }
Extra.BLIZZARD_BUTTONS = { "PetActionButton", "StanceButton", "ShapeshiftButton", "PossessButton" }

function Extra.HideBlizzard()
  local n = 0
  for _, name in ipairs(Extra.BLIZZARD) do
    local f = rawget(_G, name)
    if f then Bars.found[name] = true if Bars.Banish(f) then n = n + 1 end else Bars.missing[name] = true end
  end
  for _, p in ipairs(Extra.BLIZZARD_BUTTONS) do
    for i = 1, 10 do local b = rawget(_G, p .. i) if b and Bars.Banish(b) then n = n + 1 end end
  end
  return n
end

--- Called from Bars.Build (out of combat): both bars built / laid out / updated as the profile says.
function Extra.Build()
  local d = cfg()
  Extra.HideBlizzard()
  local pet = Extra.CreatePet()
  if d.list.pet.enabled ~= false then Bars.Layout(pet) pet:Show() else pet:Hide() end
  Extra.UpdatePet()
  local st = Extra.CreateStance()
  if d.list.stance.enabled ~= false then Bars.Layout(st) else st:Hide() end
  Extra.UpdateStance()
  if not Extra.events then
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PET_BAR_UPDATE", "PET_BAR_UPDATE_COOLDOWN", "UNIT_PET", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PET_UI_UPDATE",
      "UPDATE_SHAPESHIFT_FORMS", "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_USABLE", "UPDATE_SHAPESHIFT_COOLDOWN", "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS" }) do
      pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, e)
      local ok, err = pcall(function()
        if e:find("^PET") or e == "UNIT_PET" or e:find("^PLAYER_CONTROL") or e == "PLAYER_ENTERING_WORLD" or e == "UPDATE_BINDINGS" then Extra.UpdatePet() end
        if e:find("^UPDATE_SHAPESHIFT") or e == "PLAYER_ENTERING_WORLD" or e == "UPDATE_BINDINGS" then Extra.UpdateStance() end
      end)
      if not ok and err ~= Extra.lastError then Extra.lastError = err HH:LogError("bars extra " .. e .. ": " .. tostring(err)) end
    end)
    Extra.events = ev
  end
  return 2
end

-- ------------------------------------------------------------------------------------------------ state refresh
-- In game 2026-10-15 (Sean): the Hearthstone looked greyed before it was clicked, and after the cast was cancelled
-- the button stayed lit (our cyan "active" mark = the lib's checked state). The lib clears checked state on
-- ACTIONBAR_UPDATE_STATE only - its player spellcast events are registered on retail builds only - and recolours
-- usability on ACTIONBAR_UPDATE_USABLE / SPELL_UPDATE_USABLE. Forever does not fire those for every case (an item
-- cast cancelled), so a state can go stale. Our own pass: after any cast end, spell change, bag change, zoning or the
-- end of combat, every action button on our bars gets its checked + usable state read again (the lib's own rules:
-- usable white, no mana = the lib's mana colour, else grey 0.4), debounced, plus one re-check a beat later because the
-- client's state can trail the event. Secret values are never tested - a button whose answer is secret is left as is.
-- What fired is counted for /hh btndiag.
Extra.REFRESH_EVENTS = { "ACTIONBAR_UPDATE_STATE", "ACTIONBAR_UPDATE_USABLE", "SPELL_UPDATE_USABLE", "CURRENT_SPELL_CAST_CHANGED",
  "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED",
  "UNIT_SPELLCAST_CHANNEL_STOP", "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "BAG_UPDATE_DELAYED",
  "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }
Extra.UNIT_EVENTS = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true,
  UNIT_SPELLCAST_SUCCEEDED = true, UNIT_SPELLCAST_CHANNEL_STOP = true }
Extra.seen, Extra.refreshes, Extra.refused = {}, 0, {}

local function flag(v)
  if isSecret(v) then return nil end
  return v == true or v == 1
end

--- Read one button's state again. Returns true when it was refreshed (an action button with an action).
function Extra.RefreshButton(b)
  if type(b) ~= "table" or b._state_type ~= "action" or type(b.HasAction) ~= "function" then return false end
  if not flag(call(b.HasAction, b)) then return false end
  local active = flag(call(b.IsCurrentlyActive, b))
  local auto = flag(call(b.IsAutoRepeat, b))
  if active ~= nil and b.SetChecked then call(b.SetChecked, b, (active or auto) and true or false) end
  if b.icon and b.icon.SetVertexColor and not (b.config and b.config.outOfRangeColoring == "button" and b.outOfRange) then
    local usable, noMana = call(b.IsUsable, b)
    local lab = Bars.Lib and Bars.Lib()
    if isSecret(usable) then
      -- hidden answer (WoW: Forever, 2026-10-17): the lib's dim layer resolves it; the old grey never stays
      if lab and type(lab.hhSecretUsable) == "function" then call(lab.hhSecretUsable, b, usable, noMana)
      else b.icon:SetVertexColor(1, 1, 1) end
      Extra.secretUsable = (Extra.secretUsable or 0) + 1
    else
      if lab and type(lab.hhClearDim) == "function" then call(lab.hhClearDim, b) end
      if flag(usable) then b.icon:SetVertexColor(1, 1, 1)
      elseif flag(noMana) and b.config and b.config.colors and b.config.colors.mana then b.icon:SetVertexColor(unpack(b.config.colors.mana))
      else b.icon:SetVertexColor(0.4, 0.4, 0.4) end
    end
  end
  return true
end

--- Every bar button we own (bars 1-10 + pet / stance), refreshed. Returns how many.
function Extra.RefreshAll()
  local n = 0
  for _, bar in pairs(Bars.bars or {}) do
    if type(bar) == "table" and type(bar.buttons) == "table" then
      for _, b in ipairs(bar.buttons) do if Extra.RefreshButton(b) then n = n + 1 end end
    end
  end
  Extra.refreshes = Extra.refreshes + 1
  Extra.lastRefreshed = n
  return n
end

local pending = false
function Extra.QueueRefresh()
  if pending then return end
  pending = true
  local function now() pending = false Extra.RefreshAll() end
  if type(C_Timer) == "table" and C_Timer.After then
    C_Timer.After(0.05, now)
    C_Timer.After(0.35, function() Extra.RefreshAll() end)   -- the client's state can trail the event
  else now() end
end

function Extra.StartRefresh()
  if Extra.refreshFrame then return end
  local f = CreateFrame("Frame")
  for _, e in ipairs(Extra.REFRESH_EVENTS) do
    local ok
    if Extra.UNIT_EVENTS[e] and f.RegisterUnitEvent then ok = pcall(f.RegisterUnitEvent, f, e, "player")
    else ok = pcall(f.RegisterEvent, f, e) end
    if not ok then Extra.refused[#Extra.refused + 1] = e end
  end
  f:SetScript("OnEvent", function(_, e)
    Extra.seen[e] = (Extra.seen[e] or 0) + 1
    Extra.QueueRefresh()
  end)
  Extra.refreshFrame = f
  if C_Timer and C_Timer.NewTicker then
    -- the lib's own counters, saved every 3 s (Sean 2026-10-17: no command to type - the next /reload carries them)
    Extra.liveTicker = C_Timer.NewTicker(3, function() pcall(Extra.SaveLive) end)
  end
end

--- Evidence for "no cooldowns on the bars" (Sean 2026-10-17, fourth report - the lib reports no errors, so the question
-- is what the client returns and what the swipe widget does). Per bar button with an action: the client's cooldown
-- answer (C_ActionBar.GetActionCooldown: isActive / startTime / duration; the legacy GetActionCooldown too), whether a
-- duration object comes back, and the widget: shown / visible / alpha / level against the button / size / its own
-- duration / swipe on. Hidden values are written "S", never used. Buttons cooling down first; at most `max` lines.
local function desc(v)
  if isSecret(v) then return "S" end
  if v == nil then return "nil" end
  local t = type(v)
  if t == "boolean" then return v and "T" or "F" end
  if t == "number" then return ("%.1f"):format(v) end
  return t
end

function Extra.CooldownLines(max)
  max = max or 6
  local hot, cold = {}, {}
  local CAB = rawget(_G, "C_ActionBar")
  local getInfo = type(CAB) == "table" and type(CAB.GetActionCooldown) == "function" and CAB.GetActionCooldown or nil
  local getDur = type(CAB) == "table" and type(CAB.GetActionCooldownDuration) == "function" and CAB.GetActionCooldownDuration or nil
  for n = 1, 3 do
    local bar = Bars.bars and Bars.bars[n]
    for i, b in ipairs(bar and bar.buttons or {}) do
      local slot = num(rawget(b, "_state_action"))
      if rawget(b, "_state_type") == "action" and slot and flag(call(b.HasAction, b)) then
        local info = getInfo and call(getInfo, slot) or nil
        local active = type(info) == "table" and info.isActive or nil
        local ls, ld = call(rawget(_G, "GetActionCooldown"), slot)
        local dur = getDur and call(getDur, slot) or nil
        local cd = rawget(b, "cooldown")
        local function cdv(m) return type(cd) == "table" and type(cd[m]) == "function" and call(cd[m], cd) or nil end
        local line = ("b%d#%d slot %d: isActive=%s start=%s dur=%s | legacy %s/%s | durObj=%s | widget shown=%s vis=%s a=%s lvl %s/%s %sx%s ms=%s swipe=%s"):format(
          n, i, slot, desc(active), desc(type(info) == "table" and info.startTime or nil), desc(type(info) == "table" and info.duration or nil),
          desc(ls), desc(ld), dur == nil and "nil" or (isSecret(dur) and "S" or type(dur)),
          desc(cdv("IsShown")), desc(cdv("IsVisible")), desc(cdv("GetAlpha")), desc(cdv("GetFrameLevel")), desc(call(b.GetFrameLevel, b)),
          desc(cdv("GetWidth")), desc(cdv("GetHeight")), desc(cdv("GetCooldownDuration")), desc(cdv("GetDrawSwipe")))
        -- "usable" too (Sean 2026-10-17: every icon grey): the lib's own answer, both client calls, the icon's colour now
        local lu, lm = call(b.IsUsable, b)
        local gu = call(rawget(_G, "IsUsableAction"), slot)
        local cu = type(CAB) == "table" and type(CAB.IsUsableAction) == "function" and call(CAB.IsUsableAction, slot) or nil
        local r, gg, bb = call(rawget(b, "icon") and b.icon.GetVertexColor, b.icon)
        local dim = rawget(b, "hhUnusableDim")
        line = line .. (" | usable lib=%s/%s global=%s C_=%s icon=%s,%s,%s dim=%s"):format(desc(lu), desc(lm),
          rawget(_G, "IsUsableAction") and desc(gu) or "nofn", type(CAB) == "table" and type(CAB.IsUsableAction) == "function" and desc(cu) or "nofn",
          desc(r), desc(gg), desc(bb), dim and desc(call(dim.IsShown, dim)) or "none")
        local cooling = isSecret(active) or active == true or ((num(ld) or 0) > 1.6)
        if cooling then hot[#hot + 1] = line else cold[#cold + 1] = line end
      end
    end
  end
  local out = {}
  for _, l in ipairs(hot) do if #out < max then out[#out + 1] = "COOLING " .. l end end
  for _, l in ipairs(cold) do if #out < max then out[#out + 1] = l end end
  Extra.cooling = #hot
  return out
end

--- The raw "is there an action here" answers for bar 1's first buttons, whatever they are (the recorder above only
-- lists buttons the lib believes hold an action - it found none on 2026-10-17 while the bars were full).
function Extra.RawLines(max)
  local out = {}
  local bar = Bars.bars and Bars.bars[1]
  local CAB = rawget(_G, "C_ActionBar")
  for i, b in ipairs(bar and bar.buttons or {}) do
    if i > (max or 4) then break end
    local slot = rawget(b, "_state_action")
    local g = rawget(_G, "HasAction")
    local gv = g and call(g, slot)
    local cv = type(CAB) == "table" and type(CAB.HasAction) == "function" and call(CAB.HasAction, slot) or nil
    local tex = call(rawget(_G, "GetActionTexture"), slot)
    out[#out + 1] = ("b1#%d type=%s slot=%s HasAction=%s C_.HasAction=%s tex=%s lib=%s"):format(i, tostring(rawget(b, "_state_type")),
      desc(slot), g and desc(gv) or "nofn", (type(CAB) == "table" and type(CAB.HasAction) == "function") and desc(cv) or "nofn",
      desc(tex), desc(call(b.HasAction, b)))
  end
  return out
end

function Extra.SaveLive()
  local lab = Bars.Lib and Bars.Lib()
  local g = HH.db and HH.db.global
  if not lab or not g then return nil end
  g.diag = g.diag or {}
  g.diag.barsLive = { at = date and date("%Y-%m-%d %H:%M:%S") or "?", path = lab.cooldownPath,
    cooldownErrors = lab.hhCooldownErrors or 0, lastCooldownError = lab.hhLastCooldownError,
    cooldownFallback = lab.hhCooldownFallback or 0, secretUsable = lab.hhSecretUsableCount or 0,
    updateErrors = lab.hhUpdateErrors or 0, lastUpdateError = lab.hhLastUpdateError, secretUsableRefresh = Extra.secretUsable or 0 }
  local ok, lines = pcall(Extra.CooldownLines, 6)
  g.diag.barsLive.cooldowns = ok and table.concat(lines, " || ") or ("probe error: " .. tostring(lines))
  g.diag.barsLive.cooling = Extra.cooling
  local okR, raw = pcall(Extra.RawLines, 4)
  g.diag.barsLive.raw = okR and table.concat(raw, " || ") or ("raw error: " .. tostring(raw))
  g.diag.barsLive.hasActionHidden = lab.hhHasActionHidden or 0
  g.diag.barsLive.hasActionMissing = lab.hhHasActionMissing and true or false
  return g.diag.barsLive
end

function Extra.BtnDiagLines()
  local out = {}
  local ev = {}
  for _, e in ipairs(Extra.REFRESH_EVENTS) do ev[#ev + 1] = e:gsub("UNIT_SPELLCAST_", "CAST_"):gsub("ACTIONBAR_UPDATE_", "AB_") .. "=" .. (Extra.seen[e] or 0) end
  out[#out + 1] = "bar state events seen: " .. table.concat(ev, " ")
  out[#out + 1] = ("refresh passes %d, last refreshed %s buttons%s"):format(Extra.refreshes, tostring(Extra.lastRefreshed or 0),
    #Extra.refused > 0 and (" | client refused: " .. table.concat(Extra.refused, ",")) or "")
  local bar = Bars.bars and Bars.bars[1]
  for i, b in ipairs(bar and bar.buttons or {}) do
    if b._state_type == "action" and flag(call(b.HasAction, b)) then
      local a = call(b.IsCurrentlyActive, b)
      local u, m = call(b.IsUsable, b)
      local checked = b.GetChecked and call(b.GetChecked, b)
      local r, g = b.icon and b.icon.GetVertexColor and call(b.icon.GetVertexColor, b.icon)
      out[#out + 1] = ("  bar1 #%d action %s: current=%s usable=%s nomana=%s checked=%s icon=%.2f"):format(i, tostring(b._state_action),
        isSecret(a) and "SECRET" or tostring(a), isSecret(u) and "SECRET" or tostring(u), isSecret(m) and "SECRET" or tostring(m),
        tostring(checked), num(r) or -1)
    end
  end
  return out
end

HH:RegisterSlash("btndiag", function()
  for _, l in ipairs(Extra.BtnDiagLines()) do HH:Print(l) end
end, "action bar buttons: which state events fired, each bar-1 slot's current / usable / checked state")
