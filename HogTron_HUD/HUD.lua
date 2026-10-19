-- HUD module entry: one strip (castbar / mana / info rows) on a draggable anchor. No secure frames.
HogHealsHUD = HogHealsHUD or {}
local HHD = HogHealsHUD
local HH = HogHeals

local HUD = { rows = {}, order = { "castbar", "swing", "mana", "xp", "info" } }
HHD.HUD = HUD

local function db() return HH.db.profile.hud end

local ROW_SHOW = { castbar = "showCastbar", swing = "showSwing", mana = "showMana", xp = "showXP", info = "showInfo" }
local ROW_HEIGHT = { castbar = "castbarHeight", swing = "swingHeight", mana = "manaHeight", xp = "xpHeight", info = "infoHeight" }
-- rows that show themselves only while something is happening (the slot stays reserved)
local SELF_SHOWING = { castbar = true, swing = true, xp = true }   -- xp hides itself at the level cap (XPBar.lua)
-- bars that can leave the strip and sit anywhere (Sean 2026-10-18, after the unlock sizes: the cast bar away from the
-- mana bar). A detached bar keeps its size; its spot is hud.<name>.point / x / y on the screen's centre.
HUD.DETACHABLE = { castbar = true, swing = true, mana = true }

--- Offset of a frame's centre from the screen's centre, in the frame's own units (what SetPoint on UIParent takes).
function HUD.CenterOffset(f)
  local cx, cy = f:GetCenter()
  local ux, uy = UIParent:GetCenter()
  if type(cx) ~= "number" or type(cy) ~= "number" or type(ux) ~= "number" or type(uy) ~= "number" then return nil end
  local fs = (f.GetEffectiveScale and f:GetEffectiveScale()) or 1
  local us = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
  if type(fs) ~= "number" or fs == 0 then fs = 1 end
  if type(us) ~= "number" then us = 1 end
  local r = us / fs
  return math.floor(cx - ux * r + 0.5), math.floor(cy - uy * r + 0.5)
end

--- Take a bar out of the strip (on = true) or put it back. Its spot starts where it is now: no jump.
function HUD.Detach(name, on)
  local d = db()
  local sub = HUD.DETACHABLE[name] and d[name] or nil
  if type(sub) ~= "table" then return false end
  if on and not sub.detached then
    local row = HUD.rows[name]
    local x, y   -- (not `row and HUD.CenterOffset(row)`: an and-expression keeps only the first value)
    if row then x, y = HUD.CenterOffset(row) end
    sub.point, sub.x, sub.y = "CENTER", x or (d.x or 0), y or ((d.y or 0) + 60)
  end
  sub.detached = on and true or false
  HUD.Refresh()
  return true
end

-- The cast bar on the player's unit frame (Sean 2026-10-18: "the ability to attach the cast bar to the unit frames";
-- target and focus already carry their own, HogTron_Units). hud.castbar.attach = "below" | "above" puts the HUD's bar
-- under / over HogUIPlayer, as wide as the frame (the spell icon in line with its left edge), and it follows the frame
-- wherever the frame is dragged. Only our bar is anchored: the unit frame is a secure button and is never touched.
-- No player frame (Units off, the player frame off) -> the bar sits where it would without the setting. The Units
-- module builds the frame after we lay out at login, so a missing frame is looked for again a few times.
HUD.ATTACH_GAP = 4
HUD.ATTACH_FRAME = "HogUIPlayer"
HUD.ATTACH_TRIES = 10

--- The frame the cast bar attaches to and the side, or nil + why ("off" | "wait" | "hidden").
function HUD.AttachFrame()
  local c = db().castbar
  local where = type(c) == "table" and c.attach
  if where ~= "below" and where ~= "above" then return nil, "off" end
  local f = rawget(_G, HUD.ATTACH_FRAME)
  if type(f) ~= "table" then return nil, "wait" end
  if f.IsShown and not f:IsShown() then return nil, "hidden" end
  return f, where
end

--- The player frame was not built yet: lay out again shortly (bounded).
function HUD.RetryAttach()
  if HUD.attachPending or (HUD.attachTries or 0) >= HUD.ATTACH_TRIES then return end
  HUD.attachTries = (HUD.attachTries or 0) + 1
  HUD.attachPending = true
  C_Timer.After(0.5, function() HUD.attachPending = nil HUD.Layout() end)
end

--- A detached bar drags itself (edit mode's box relays to these) and saves its spot when let go.
function HUD.MakeMovable(row, name)
  if row.hhMovable then return end
  row.hhMovable = true
  if row.SetMovable then row:SetMovable(true) end
  if row.SetClampedToScreen then row:SetClampedToScreen(true) end
  row:SetScript("OnDragStart", function(self) if self.detached and self.StartMoving then self:StartMoving() end end)
  row:SetScript("OnDragStop", function(self)
    if not self.detached then return end
    if self.StopMovingOrSizing then self:StopMovingOrSizing() end
    local sub = db()[name]
    local x, y = HUD.CenterOffset(self)
    if type(sub) == "table" and x then sub.point, sub.x, sub.y = "CENTER", x, y end
    HUD.Layout()
  end)
end

function HUD.Create()
  if HUD.anchor then return end
  local d = db()
  local anchor = CreateFrame("Frame", "HogHealsHUDAnchor", UIParent)
  anchor:SetSize(d.width, 40)
  anchor:SetPoint("CENTER", UIParent, "CENTER", d.x, d.y)
  anchor:SetMovable(true)
  anchor:SetClampedToScreen(true)
  anchor:EnableMouse(false)
  anchor:RegisterForDrag("LeftButton")
  anchor:SetScript("OnDragStart", function(self) self:StartMoving() end)
  anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint()
    d.x, d.y = x or d.x, y or d.y
  end)
  anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
  anchor.bg:SetAllPoints(anchor)
  anchor.bg:SetColorTexture(0.13, 0.83, 0.88, 0.25)
  anchor.label = anchor:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  anchor.label:SetPoint("CENTER", anchor, "CENTER", 0, 0)
  anchor.label:SetText("HogHeals HUD — drag, then /hh lock")
  anchor:Hide()
  HUD.anchor = anchor

  local container = CreateFrame("Frame", "HogHealsHUDFrame", UIParent)
  container:SetPoint("TOP", anchor, "TOP", 0, 0)
  container:SetSize(d.width, 40)
  HUD.container = container

  local castbar = CreateFrame("StatusBar", "HogHealsHUDCastbar", container)
  castbar:SetMinMaxValues(0, 1)
  castbar:SetValue(0)
  castbar.bg = castbar:CreateTexture(nil, "BACKGROUND")
  castbar.bg:SetAllPoints(castbar)
  castbar.bg:SetColorTexture(0.07, 0.07, 0.09, 0.7)
  castbar.icon = castbar:CreateTexture(nil, "ARTWORK")
  castbar.icon:SetPoint("RIGHT", castbar, "LEFT", -2, 0)
  castbar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- trim Blizzard's baked icon border, like the unit-frame auras
  castbar.text = castbar:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  castbar.text:SetPoint("LEFT", castbar, "LEFT", 4, 0)
  castbar.time = castbar:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  castbar.time:SetPoint("RIGHT", castbar, "RIGHT", -4, 0)
  castbar.latency = castbar:CreateTexture(nil, "OVERLAY", nil, 1)
  castbar.latency:SetPoint("TOPRIGHT", castbar, "TOPRIGHT", 0, 0)
  castbar.latency:SetPoint("BOTTOMRIGHT", castbar, "BOTTOMRIGHT", 0, 0)
  castbar.latency:SetColorTexture(0.85, 0.2, 0.2, 0.6)
  castbar.latency:SetWidth(0)
  castbar.latency:Hide()
  castbar.spark = castbar:CreateTexture(nil, "OVERLAY", nil, 2)
  castbar.spark:SetSize(8, 24)
  castbar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
  castbar.spark:Hide()
  castbar.gcd = CreateFrame("StatusBar", nil, castbar)
  castbar.gcd:SetPoint("TOPLEFT", castbar, "BOTTOMLEFT", 0, 0)
  castbar.gcd:SetPoint("TOPRIGHT", castbar, "BOTTOMRIGHT", 0, 0)
  castbar.gcd:SetHeight(2)
  castbar.gcd:SetMinMaxValues(0, 1)
  castbar.gcd:Hide()
  castbar:Hide()
  HUD.rows.castbar = castbar

  -- swing timer: flat bar, label left ("Swing" / "Auto Shot"), seconds to the next swing right (Swing.lua drives it)
  local swing = CreateFrame("StatusBar", "HogHealsHUDSwing", container)
  swing:SetMinMaxValues(0, 1)
  swing:SetValue(0)
  swing.bg = swing:CreateTexture(nil, "BACKGROUND")
  swing.bg:SetAllPoints(swing)
  swing.bg:SetColorTexture(0.07, 0.07, 0.09, 0.7)
  swing.text = swing:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  swing.text:SetPoint("LEFT", swing, "LEFT", 4, 0)
  swing.time = swing:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  swing.time:SetPoint("RIGHT", swing, "RIGHT", -4, 0)
  -- 2026-10-05: bigger and cleaner - a 1 px ink outline, a soft sheen on the top half, a bright spark on the head of
  -- the fill (Swing.lua moves it). Flat colour, so it is crisp at any resolution.
  swing.outline = {}
  -- { point1, x1, y1, point2, x2, y2, width, height }: one pixel outside the bar on every side
  local edges = {
    { "TOPLEFT", -1, 1, "TOPRIGHT", 1, 1, nil, 1 }, { "BOTTOMLEFT", -1, -1, "BOTTOMRIGHT", 1, -1, nil, 1 },
    { "TOPLEFT", -1, 1, "BOTTOMLEFT", -1, -1, 1, nil }, { "TOPRIGHT", 1, 1, "BOTTOMRIGHT", 1, -1, 1, nil },
  }
  for i, e in ipairs(edges) do
    local t = swing:CreateTexture(nil, "OVERLAY", nil, 3)
    t:SetPoint(e[1], swing, e[1], e[2], e[3])
    t:SetPoint(e[4], swing, e[4], e[5], e[6])
    if e[7] then t:SetWidth(e[7]) end
    if e[8] then t:SetHeight(e[8]) end
    t:SetColorTexture(0.20, 0.20, 0.25, 1)
    swing.outline[i] = t
  end
  swing.sheen = swing:CreateTexture(nil, "ARTWORK", nil, 2)
  swing.sheen:SetPoint("TOPLEFT", swing, "TOPLEFT", 0, 0)
  swing.sheen:SetPoint("TOPRIGHT", swing, "TOPRIGHT", 0, 0)
  swing.sheen:SetHeight(4)
  swing.sheen:SetColorTexture(1, 1, 1, 0.07)
  swing.spark = swing:CreateTexture(nil, "OVERLAY", nil, 2)
  swing.spark:SetSize(12, 32)
  swing.spark:SetTexture("Interface/CastingBar/UI-CastingBar-Spark")
  if swing.spark.SetBlendMode then swing.spark:SetBlendMode("ADD") end
  swing.spark:SetPoint("CENTER", swing, "LEFT", 0, 0)
  swing.spark:Hide()
  swing:Hide()
  HUD.rows.swing = swing

  local mana = CreateFrame("StatusBar", "HogHealsHUDMana", container)
  mana:SetMinMaxValues(0, 1)
  mana:SetValue(1)
  mana.bg = mana:CreateTexture(nil, "BACKGROUND")
  mana.bg:SetAllPoints(mana)
  mana.bg:SetColorTexture(0.07, 0.07, 0.09, 0.7)
  mana.text = mana:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  mana.text:SetPoint("CENTER", mana, "CENTER", 0, 0)
  mana.fsr = mana:CreateTexture(nil, "OVERLAY", nil, 1)
  mana.fsr:SetPoint("TOPLEFT", mana, "TOPLEFT", 0, 0)
  mana.fsr:SetPoint("BOTTOMLEFT", mana, "BOTTOMLEFT", 0, 0)
  mana.fsr:SetColorTexture(0.13, 0.83, 0.88, 0.35)
  mana.fsr:SetWidth(0)
  mana.fsr:Hide()
  mana.fsrText = mana:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  mana.fsrText:SetPoint("LEFT", mana, "LEFT", 4, 0)
  mana.fsrText:Hide()
  mana.tick = mana:CreateTexture(nil, "OVERLAY", nil, 2)
  mana.tick:SetSize(2, 12)
  mana.tick:SetColorTexture(0.96, 0.92, 0.86, 0.9)
  mana.tick:Hide()
  HUD.rows.mana = mana

  -- experience: flat fill, rested + quest overlays from the fill head (XPBar.lua draws them), level / numbers left,
  -- pace right
  local xp = CreateFrame("StatusBar", "HogHealsHUDXP", container)
  xp:SetMinMaxValues(0, 1)
  xp:SetValue(0)
  xp.bg = xp:CreateTexture(nil, "BACKGROUND")
  xp.bg:SetAllPoints(xp)
  xp.bg:SetColorTexture(0.07, 0.07, 0.09, 0.7)
  xp.rested = xp:CreateTexture(nil, "ARTWORK", nil, 1)
  xp.rested:SetColorTexture(0.13, 0.83, 0.88, 0.35)
  xp.rested:Hide()
  xp.quest = xp:CreateTexture(nil, "ARTWORK", nil, 2)
  xp.quest:SetColorTexture(0.25, 0.80, 0.35, 0.55)
  xp.quest:Hide()
  xp.left = xp:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  xp.left:SetPoint("LEFT", xp, "LEFT", 4, 0)
  xp.left:SetJustifyH("LEFT")
  xp.right = xp:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  xp.right:SetPoint("RIGHT", xp, "RIGHT", -4, 0)
  xp.right:SetJustifyH("RIGHT")
  xp:Hide()
  HUD.rows.xp = xp

  local info = CreateFrame("Frame", "HogHealsHUDInfo", container)
  info.left = info:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  info.left:SetPoint("LEFT", info, "LEFT", 2, 0)
  info.left:SetJustifyH("LEFT")
  info.right = info:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  info.right:SetPoint("RIGHT", info, "RIGHT", -2, 0)
  info.right:SetJustifyH("RIGHT")
  HUD.rows.info = info
end

--- Stack enabled rows top→bottom; returns total strip height.
function HUD.Layout()
  if not HUD.container then HUD.Create() end
  local d = db()
  local y, shown = 0, 0
  for _, name in ipairs(HUD.order) do
    local row = HUD.rows[name]
    local enabled = d[ROW_SHOW[name]] ~= false
    if name == "xp" and d.xp and (d.xp.mode or "bar") ~= "row" then enabled = false end   -- its own bar instead (XPBar.lua)
    local sub = HUD.DETACHABLE[name] and d[name] or nil
    local attachTo, side
    if name == "castbar" and enabled then
      attachTo, side = HUD.AttachFrame()          -- (two values: never `x and HUD.AttachFrame()`)
      if attachTo then HUD.attachTries = 0 elseif side == "wait" then HUD.RetryAttach() end
    end
    if attachTo then
      -- on the player frame: its width, our height, the icon hanging off the left in line with the frame's edge
      HUD.MakeMovable(row, name)
      local h = d[ROW_HEIGHT[name]] or 12
      local pad = (type(sub) == "table" and sub.icon == false) and 0 or (h + 2)
      local g = HUD.ATTACH_GAP
      row:ClearAllPoints()
      if side == "above" then
        row:SetPoint("BOTTOMLEFT", attachTo, "TOPLEFT", pad, g)
        row:SetPoint("BOTTOMRIGHT", attachTo, "TOPRIGHT", 0, g)
      else
        row:SetPoint("TOPLEFT", attachTo, "BOTTOMLEFT", pad, -g)
        row:SetPoint("TOPRIGHT", attachTo, "BOTTOMRIGHT", 0, -g)
      end
      row:SetHeight(h)
      row.attached, row.detached, row.enabled = side, nil, true
    elseif enabled and type(sub) == "table" and sub.detached then
      -- out of the strip: its own spot, its own size; the bars under it close the gap
      HUD.MakeMovable(row, name)
      local h = d[ROW_HEIGHT[name]] or 12
      local own = (sub.width or 0) > 0 and sub.width or d.width
      row:ClearAllPoints()
      row:SetPoint(sub.point or "CENTER", UIParent, sub.point or "CENTER", sub.x or 0, sub.y or 0)
      row:SetSize(own, h)
      row.detached, row.attached, row.enabled = true, nil, true
      if not SELF_SHOWING[name] then row:Show() end
    elseif enabled then
      if HUD.DETACHABLE[name] then HUD.MakeMovable(row, name) end
      row.detached, row.attached = nil, nil
      local h = d[ROW_HEIGHT[name]] or 12
      row:ClearAllPoints()
      -- cast bar, swing and mana bar may have their own width (0 = the strip's), centred on the strip
      local own = type(sub) == "table" and (sub.width or 0) > 0 and sub.width or nil
      if own then
        -- a row with its own width may be wider than the strip: centred on it, hanging out both sides
        row:SetPoint("TOP", HUD.container, "TOP", 0, -y)
        row:SetSize(own, h)
      else
        row:SetPoint("TOPLEFT", HUD.container, "TOPLEFT", 0, -y)
        row:SetSize(d.width, h)
      end
      row.enabled = true
      if not SELF_SHOWING[name] then row:Show() end
      y = y + h + (d.rowSpacing or 0)
      shown = shown + 1
    else
      row.enabled, row.attached = false, nil
      row:Hide()
    end
  end
  local total = shown > 0 and (y - (d.rowSpacing or 0)) or 0
  HUD.container:SetSize(d.width, math.max(total, 1))
  HUD.anchor:SetSize(d.width, math.max(total, 10))
  HUD.anchor:ClearAllPoints()
  HUD.anchor:SetPoint("CENTER", UIParent, "CENTER", d.x, d.y)
  HUD.height = total
  return total
end

function HUD.ApplyAppearance()
  local d = db()
  local LSM = LibStub("LibSharedMedia-3.0", true)
  local font = HH.Look.Font(d.font)
  local tex = HH.Look.Bar(d.texture)
  local size = d.fontSize or 11
  local cb, mana, info, sw, xp = HUD.rows.castbar, HUD.rows.mana, HUD.rows.info, HUD.rows.swing, HUD.rows.xp
  cb:SetStatusBarTexture(tex); cb.gcd:SetStatusBarTexture(tex); mana:SetStatusBarTexture(tex); sw:SetStatusBarTexture(tex)
  if xp then xp:SetStatusBarTexture(tex) end
  cb.text:SetFont(font, size, "OUTLINE"); cb.time:SetFont(font, size, "OUTLINE")
  local ss = (d.swing and (d.swing.fontSize or 0) > 0) and d.swing.fontSize or (size + 1)
  sw.text:SetFont(font, ss, "OUTLINE"); sw.time:SetFont(font, ss, "OUTLINE")
  if sw.spark then sw.spark:SetSize(math.max(8, math.floor((d.swingHeight or 16) * 0.75)), (d.swingHeight or 16) * 2) end
  if sw.outline then for _, t in ipairs(sw.outline) do t:SetShown(not d.swing or d.swing.outline ~= false) end end
  if sw.sheen then sw.sheen:SetHeight(math.max(2, math.floor((d.swingHeight or 16) / 4))) end
  mana.text:SetFont(font, size - 1, "OUTLINE"); mana.fsrText:SetFont(font, size - 2, "OUTLINE")
  info.left:SetFont(font, size, "OUTLINE"); info.right:SetFont(font, size, "OUTLINE")
  cb.icon:SetSize(d.castbarHeight or 18, d.castbarHeight or 18)
  cb.icon:SetShown(d.castbar.icon ~= false)
end

function HUD.Refresh()
  HUD.Layout()
  HUD.ApplyAppearance()
  for _, part in ipairs({ "Castbar", "Swing", "Mana", "XPBar", "Pacing", "RankAdvisor" }) do
    local p = HHD[part]
    if p and p.Refresh then HH:SafeCall(p, "Refresh") end
  end
end

-- ---------------------------------------------------------------- module
local Module = {}
HHD.module = Module

function Module:OnEnable()
  HUD.Create()
  HUD.Layout()
  HUD.ApplyAppearance()
  for _, part in ipairs({ "Castbar", "Swing", "Mana", "XPBar", "Pacing", "RankAdvisor" }) do
    local p = HHD[part]
    if p and p.Init then HH:SafeCall(p, "Init") end
  end
  self:SetLocked(HH.db.profile.locked)
end

function Module:OnProfileChanged() HUD.Refresh() end

function Module:SetLocked(locked)
  if HHD.XPBar and HHD.XPBar.SetUnlocked then HHD.XPBar.SetUnlocked(not locked) end
  if not HUD.anchor then return end
  HUD.anchor:EnableMouse(not locked)
  if locked then HUD.anchor:Hide() else HUD.anchor:Show() end
end

function Module:GetOptions()
  if HHD.Options and HHD.Options.Build then return HHD.Options.Build() end
  return { type = "group", name = "HUD", args = {} }
end

HH:RegisterModule("HUD", Module)
