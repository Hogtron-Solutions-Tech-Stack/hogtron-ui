-- HUD module entry: one strip (castbar / mana / info rows) on a draggable anchor. No secure frames.
HogHealsHUD = HogHealsHUD or {}
local HHD = HogHealsHUD
local HH = HogHeals

local HUD = { rows = {}, order = { "castbar", "mana", "info" } }
HHD.HUD = HUD

local function db() return HH.db.profile.hud end

local ROW_SHOW = { castbar = "showCastbar", mana = "showMana", info = "showInfo" }
local ROW_HEIGHT = { castbar = "castbarHeight", mana = "manaHeight", info = "infoHeight" }

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
  anchor.label = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
  castbar.text = castbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  castbar.text:SetPoint("LEFT", castbar, "LEFT", 4, 0)
  castbar.time = castbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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

  local mana = CreateFrame("StatusBar", "HogHealsHUDMana", container)
  mana:SetMinMaxValues(0, 1)
  mana:SetValue(1)
  mana.bg = mana:CreateTexture(nil, "BACKGROUND")
  mana.bg:SetAllPoints(mana)
  mana.bg:SetColorTexture(0.07, 0.07, 0.09, 0.7)
  mana.text = mana:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  mana.text:SetPoint("CENTER", mana, "CENTER", 0, 0)
  mana.fsr = mana:CreateTexture(nil, "OVERLAY", nil, 1)
  mana.fsr:SetPoint("TOPLEFT", mana, "TOPLEFT", 0, 0)
  mana.fsr:SetPoint("BOTTOMLEFT", mana, "BOTTOMLEFT", 0, 0)
  mana.fsr:SetColorTexture(0.13, 0.83, 0.88, 0.35)
  mana.fsr:SetWidth(0)
  mana.fsr:Hide()
  mana.fsrText = mana:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  mana.fsrText:SetPoint("LEFT", mana, "LEFT", 4, 0)
  mana.fsrText:Hide()
  mana.tick = mana:CreateTexture(nil, "OVERLAY", nil, 2)
  mana.tick:SetSize(2, 12)
  mana.tick:SetColorTexture(0.96, 0.92, 0.86, 0.9)
  mana.tick:Hide()
  HUD.rows.mana = mana

  local info = CreateFrame("Frame", "HogHealsHUDInfo", container)
  info.left = info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  info.left:SetPoint("LEFT", info, "LEFT", 2, 0)
  info.left:SetJustifyH("LEFT")
  info.right = info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
    if enabled then
      local h = d[ROW_HEIGHT[name]] or 12
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", HUD.container, "TOPLEFT", 0, -y)
      row:SetSize(d.width, h)
      row.enabled = true
      if name ~= "castbar" then row:Show() end -- castbar shows itself only while casting
      y = y + h + (d.rowSpacing or 0)
      shown = shown + 1
    else
      row.enabled = false
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
  local font = LSM and LSM:Fetch("font", d.font) or STANDARD_TEXT_FONT
  local tex = LSM and LSM:Fetch("statusbar", d.texture) or "Interface\\TargetingFrame\\UI-StatusBar"
  local size = d.fontSize or 11
  local cb, mana, info = HUD.rows.castbar, HUD.rows.mana, HUD.rows.info
  cb:SetStatusBarTexture(tex); cb.gcd:SetStatusBarTexture(tex); mana:SetStatusBarTexture(tex)
  cb.text:SetFont(font, size, "OUTLINE"); cb.time:SetFont(font, size, "OUTLINE")
  mana.text:SetFont(font, size - 1, "OUTLINE"); mana.fsrText:SetFont(font, size - 2, "OUTLINE")
  info.left:SetFont(font, size, "OUTLINE"); info.right:SetFont(font, size, "OUTLINE")
  cb.icon:SetSize(d.castbarHeight or 18, d.castbarHeight or 18)
  cb.icon:SetShown(d.castbar.icon ~= false)
end

function HUD.Refresh()
  HUD.Layout()
  HUD.ApplyAppearance()
  for _, part in ipairs({ "Castbar", "Mana", "Pacing", "RankAdvisor" }) do
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
  for _, part in ipairs({ "Castbar", "Mana", "Pacing", "RankAdvisor" }) do
    local p = HHD[part]
    if p and p.Init then HH:SafeCall(p, "Init") end
  end
  self:SetLocked(HH.db.profile.locked)
end

function Module:OnProfileChanged() HUD.Refresh() end

function Module:SetLocked(locked)
  if not HUD.anchor then return end
  HUD.anchor:EnableMouse(not locked)
  if locked then HUD.anchor:Hide() else HUD.anchor:Show() end
end

function Module:GetOptions()
  if HHD.Options and HHD.Options.Build then return HHD.Options.Build() end
  return { type = "group", name = "HUD", args = {} }
end

HH:RegisterModule("HUD", Module)
