-- Frames module entry: registers with core, spawns headers, applies profiles.
HogHealsFrames = HogHealsFrames or {}
local HHF = HogHealsFrames
local HH = HogHeals

local Frames = {}
HHF.module = Frames

function Frames:OnInitialize()
  self.db = HH.db.profile.frames
end

function Frames:OnEnable()
  self.db = HH.db.profile.frames
  HHF.UnitButton.FinalizeElements()
  if HHF.Compat and HHF.Compat.Init then HHF.Compat.Init() end
  if HHF.ClickCast and HHF.ClickCast.Init then HHF.ClickCast.Init() end
  if HHF.HoverBind and HHF.HoverBind.Init then HHF.HoverBind.Init() end
  if HHF.RequestDispel and HHF.RequestDispel.Init then HHF.RequestDispel.Init() end
  HH:RunOutOfCombat(function()
    if HHF.Headers and HHF.Headers.Spawn then HHF.Headers.Spawn() end
    self:ApplyProfile(HH:CurrentBucket())
  end)
  HH.RegisterCallback(self, "BUCKET_CHANGED", function(_, new) self:ApplyProfile(new) end)
end

function Frames:OnProfileChanged()
  self.db = HH.db.profile.frames
  self:ApplyProfile(HH:CurrentBucket())
end

--- Apply the layout profile for a bucket (queued if in combat).
function Frames:ApplyProfile(bucket)
  self.bucket = bucket or HH:CurrentBucket()
  if HHF.Headers and HHF.Headers.Apply then HHF.Headers.Apply(self.bucket) end
  self:Refresh()
end

--- Re-run appearance + every element on every live button.
function Frames:Refresh()
  if not HHF.UnitButton then return end
  for _, button in ipairs(HHF.UnitButton.All()) do
    HHF.UnitButton.ApplyAppearance(button)
    HHF.UnitButton.UpdateAll(button)
  end
end

--- The layout table a bucket edits and renders. With soloSharesParty (default) the solo bucket uses the party
-- layout, so being alone and being in a group never changes size, direction or position ("when I join a party it
-- makes my frames a different size"). showSolo is read from the solo table separately.
function Frames.ResolveLayout(bucket)
  local db = HH.db.profile.frames
  bucket = bucket or (HHF.module and HHF.module.bucket) or "party"
  if bucket == "solo" and db.soloSharesParty ~= false then return db.layouts.party, "party" end
  return db.layouts[bucket] or db.layouts.party, bucket
end

function Frames:LayoutFor(bucket)
  return (Frames.ResolveLayout(bucket or self.bucket or "party"))
end

-- ------------------------------------------------------------------------------------------------ frame snapshot
-- 2026-09-22: "my health goes grey in combat", no caught error, and a class-colour fix did not change it. Instead of a
-- third guess: record exactly what the bar IS. Taken automatically 3 s into every fight (the player cannot type then)
-- and on /hh framediag; kept in diag.frameSnapshots (last 4), written to disk at the next /reload or logout.
local function describe(v)
  if v == nil then return "nil" end
  if HHF.Compat.IsSecret(v) then return "SECRET" end
  if type(v) == "number" then return ("%.2f"):format(v) end
  return tostring(v)
end

function Frames.Snapshot(reason)
  local out = { at = date and date("%H:%M:%S") or "", reason = reason, inCombat = tostring(InCombatLockdown and InCombatLockdown()),
    classOfLoaded = tostring(HHF.Compat.ClassOf ~= nil), buttons = {} }
  local n = 0
  for _, b in ipairs(HHF.UnitButton.All()) do
    if b.unit and b.IsVisible and b:IsVisible() and n < 3 then
      n = n + 1
      local h = b.health
      local r, g, bl, a = h:GetStatusBarColor()
      local mn, mx = h:GetMinMaxValues()
      local tex = h.GetStatusBarTexture and h:GetStatusBarTexture()
      local okC, cName, cToken = pcall(UnitClass, b.unit)
      local alphas = {}
      for k, v in pairs(b._alphas or {}) do alphas[#alphas + 1] = k .. "=" .. describe(v) end
      out.buttons[n] = {
        unit = b.unit,
        color = describe(r) .. "," .. describe(g) .. "," .. describe(bl) .. "," .. describe(a),
        value = describe(h:GetValue()), min = describe(mn), max = describe(mx),
        UnitHealth = describe(UnitHealth(b.unit)), UnitHealthMax = describe(UnitHealthMax(b.unit)),
        UnitClass = okC and (describe(cName) .. "/" .. describe(cToken)) or "error",
        ClassOf = describe(HHF.Compat.ClassOf(b.unit)),
        healthDead = describe(b.healthDead), dispelColored = describe(b.dispelColored),
        buttonAlpha = describe(b:GetAlpha()), healthAlpha = describe(h:GetAlpha()), healthShown = describe(h:IsShown()),
        barTexture = tex and describe(tex.GetTexture and tex:GetTexture()) or "nil",
        barTextureAlpha = tex and describe(tex.GetAlpha and tex:GetAlpha()) or "nil",
        secretRange = describe(b._secretRange), alphaReasons = table.concat(alphas, ","),
        healthMode = describe(HH.db.profile.frames.appearance.healthMode),
        -- geometry: /hh healthtest showed hidden values draw fine on a FRESH bar, so the real bar's state is suspect
        barSize = describe(h:GetWidth()) .. "x" .. describe(h:GetHeight()),
        buttonSize = describe(b:GetWidth()) .. "x" .. describe(b:GetHeight()),
        barPoints = describe(h.GetNumPoints and h:GetNumPoints()),
        fillSize = tex and (describe(tex.GetWidth and tex:GetWidth()) .. "x" .. describe(tex.GetHeight and tex:GetHeight())) or "nil",
        fillShown = tex and describe(tex.IsShown and tex:IsShown()) or "nil",
        bgShown = describe(h.bg and h.bg:IsShown()),
        healPredShown = describe(b.healPred and b.healPred:IsShown()),
        barLevel = describe(h:GetFrameLevel()) .. "/" .. describe(b:GetFrameLevel()),
      }
    end
  end
  local g = HH.db and HH.db.global
  if g then
    g.diag = g.diag or {}
    g.diag.frameSnapshots = g.diag.frameSnapshots or {}
    table.insert(g.diag.frameSnapshots, 1, out)
    while #g.diag.frameSnapshots > 4 do table.remove(g.diag.frameSnapshots) end
  end
  return out
end

local snapFrame = CreateFrame("Frame")
pcall(snapFrame.RegisterEvent, snapFrame, "PLAYER_REGEN_DISABLED")
snapFrame:SetScript("OnEvent", function()
  if C_Timer and C_Timer.After then
    C_Timer.After(3, function() pcall(Frames.Snapshot, "combat+3s") end)
  end
end)

-- ------------------------------------------------------------------------------------------------ health render test
-- 2026-09-22: the unit frame health bar draws EMPTY (colour + alpha measured fine, value SECRET) while the HUD mana
-- bar, fed the same way with a SECRET UnitPower, fills fine. Difference: the health bar is a child of a SECURE unit
-- button. One screenshot of these five bars decides the fix (15 s, then they are removed).
function Frames.HealthTest()
  local secureParent
  for _, b in ipairs(HHF.UnitButton.All()) do if b.unit == "player" then secureParent = b break end end
  secureParent = secureParent or (HHF.UnitButton.All()[1])
  local holder = CreateFrame("Frame", nil, UIParent)
  holder:SetSize(320, 150)
  holder:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  holder:SetFrameStrata("DIALOG")
  local bg = holder:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(holder)
  bg:SetColorTexture(0, 0, 0, 0.7)
  local made = {}
  local function bar(i, label, parent, fill)
    local sb = CreateFrame("StatusBar", nil, parent or holder)
    sb:SetSize(200, 18)
    sb:ClearAllPoints()
    sb:SetPoint("TOPLEFT", holder, "TOPLEFT", 110, -8 - (i - 1) * 27)
    sb:SetFrameStrata("DIALOG")
    sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    sb:SetStatusBarColor(0.53, 0.53, 0.93)
    local sbg = sb:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints(sb)
    sbg:SetColorTexture(0.2, 0.2, 0.2, 1)
    local ok, err = pcall(fill, sb)
    local fs = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("RIGHT", sb, "LEFT", -6, 0)
    fs:SetText(label .. (ok and "" or " ERR"))
    if not ok then HH:Print("healthtest " .. label .. ": " .. tostring(err)) end
    made[#made + 1] = sb
  end
  local max = UnitHealthMax("player")
  bar(1, "A secure+hidden", secureParent, function(sb) sb:SetMinMaxValues(0, max) sb:SetValue(UnitHealth("player")) end)
  bar(2, "B free+hidden", nil, function(sb) sb:SetMinMaxValues(0, max) sb:SetValue(UnitHealth("player")) end)
  bar(3, "C free+50%", nil, function(sb) sb:SetMinMaxValues(0, 1) sb:SetValue(0.5) end)
  bar(4, "D secure+50%", secureParent, function(sb) sb:SetMinMaxValues(0, 1) sb:SetValue(0.5) end)
  bar(5, "E free+percent", nil, function(sb)
    local curve = type(CurveConstants) == "table" and CurveConstants.ScaleTo100 or nil
    sb:SetMinMaxValues(0, curve and 100 or 1)
    sb:SetValue(UnitHealthPercent("player", true, curve))
  end)
  HH:Print("healthtest: 5 bars for 15 s. Screenshot them. Which ones are filled?")
  local function remove()
    for _, sb in ipairs(made) do sb:Hide() sb:SetParent(holder) end
    holder:Hide()
  end
  if C_Timer and C_Timer.After then C_Timer.After(15, remove) end
  return made
end

--- Replace every button's health StatusBar with a fresh one built exactly like /hh healthtest bar A (which filled),
-- then re-run the elements. Trial cure: if the frame fills after this, the old bar's state was the fault.
function Frames.RebuildHealthBars()
  local n = 0
  for _, b in ipairs(HHF.UnitButton.All()) do
    if Frames.RebuildHealthBar(b) then n = n + 1 end
  end
  return n
end

--- Collapsed-bar guard (called from the Health element). A bar can read 0 wide for a moment right after it is built,
-- before the client lays it out, so a zero reading only schedules a re-check 1 s later; still 0 wide inside a button
-- that is not -> rebuilt (out of combat), at most 3 times per button per session, each logged to diag.healthRebuilds.
local function collapsed(b)
  local h = b.health
  if not h or not h.GetWidth then return false end
  local bw, hw = b:GetWidth() or 0, h:GetWidth() or 0
  if HHF.Compat.IsSecret(bw) or HHF.Compat.IsSecret(hw) then return false end
  return bw > 4 and hw < 1, bw
end

function Frames.HealIfCollapsed(b)
  if b.hhHealPending or (b.hhRebuilds or 0) >= 3 or not collapsed(b) then return end
  b.hhHealPending = true
  local function recheck()
    b.hhHealPending = nil
    local still, bw = collapsed(b)
    if not still or (b.hhRebuilds or 0) >= 3 then return end
    b.hhRebuilds = (b.hhRebuilds or 0) + 1
    HH:RunOutOfCombat(function()
      if Frames.RebuildHealthBar(b) then
        local g = HH.db and HH.db.global
        if g then
          g.diag = g.diag or {}
          g.diag.healthRebuilds = g.diag.healthRebuilds or {}
          local list = g.diag.healthRebuilds
          list[#list + 1] = (date and date("%Y-%m-%d %H:%M:%S") or "") .. " " .. tostring(b.unit) .. " button " .. ("%.0f"):format(bw or 0) .. " wide, bar 0"
          while #list > 20 do table.remove(list, 1) end
        end
      end
    end)
  end
  if C_Timer and C_Timer.After then C_Timer.After(1, recheck) else recheck() end
end

function Frames.RebuildHealthBar(b)
  do
    local old = b.health
    if old then
      local fresh = CreateFrame("StatusBar", nil, b)
      fresh:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
      fresh:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
      fresh:SetFrameLevel(old:GetFrameLevel())
      fresh:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
      fresh:SetMinMaxValues(0, 1)
      fresh:SetValue(1)
      fresh.bg = fresh:CreateTexture(nil, "BACKGROUND")
      fresh.bg:SetAllPoints(fresh)
      fresh.bg:SetColorTexture(0.15, 0.15, 0.17, 0.8)
      -- incoming-heal overlays hang off the bar's fill texture: move them to the new one
      for _, k in ipairs({ "healPred", "healPredOthers" }) do
        local t = b[k]
        if t and t.SetParent then
          t:SetParent(fresh)
          t:ClearAllPoints()
          t:SetPoint("TOPLEFT", fresh:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
          t:SetPoint("BOTTOMLEFT", fresh:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
          t:Hide()
        end
      end
      old:Hide()
      old:ClearAllPoints()
      b.health = fresh
      if HHF.UnitButton.ApplyAppearance then pcall(HHF.UnitButton.ApplyAppearance, b) end
      if b.unit then HHF.UnitButton.UpdateAll(b) end
      return true
    end
  end
  return false
end

HH:RegisterSlash("healthfix", function()
  local ok, n = pcall(Frames.RebuildHealthBars)
  if ok then HH:Print(("healthfix: rebuilt %d health bar(s). Is your frame filled now?"):format(n))
  else HH:Print("healthfix failed: " .. tostring(n)) end
end, "trial: rebuild the unit frames' health bars from scratch")

HH:RegisterSlash("healthtest", function()
  local ok, err = pcall(Frames.HealthTest)
  if not ok then HH:Print("healthtest failed: " .. tostring(err)) end
end, "15 s test: which way of drawing your health bar works on this client")

HH:RegisterSlash("framediag", function()
  local ok, s = pcall(Frames.Snapshot, "slash")
  if not ok then HH:Print("framediag failed: " .. tostring(s)) return end
  HH:Print(("frames: combat=%s classOf=%s, %d button(s) (saved to diag.frameSnapshots)"):format(s.inCombat, s.classOfLoaded, #s.buttons))
  for _, b in ipairs(s.buttons) do
    HH:Print(("  %s colour=%s value=%s/%s alpha=%s texAlpha=%s class=%s dead=%s"):format(b.unit, b.color, b.value, b.max, b.buttonAlpha, b.barTextureAlpha, b.ClassOf, b.healthDead))
    HH:Print(("    bar %s (button %s) points=%s fill %s shown=%s bg=%s level=%s"):format(b.barSize, b.buttonSize, b.barPoints, b.fillSize, b.fillShown, b.bgShown, b.barLevel))
  end
end, "record what the unit frames look like right now (colour, fill, alpha)")

HH:RegisterModule("Frames", Frames)
