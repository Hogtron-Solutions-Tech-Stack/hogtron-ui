-- Party + raid SecureGroupHeaders. All attribute writes go through HogHeals:RunOutOfCombat.
HogHealsFrames = HogHealsFrames or {}
local HHF = HogHealsFrames
local HH = HogHeals
local Layout = HHF.Layout

local Headers = {}
HHF.Headers = Headers

local NUM_GROUPS = 8
Headers.party = nil
Headers.raid = {}

-- Secure snippet run for every child the header creates. It configures the secure
-- attributes, then asks the header (insecure Lua) to build our regions on the button.
local INITIAL_CONFIG = [[
  local header = self:GetParent()
  self:SetWidth(header:GetAttribute("hhWidth") or 100)
  self:SetHeight(header:GetAttribute("hhHeight") or 30)
  self:SetAttribute("*type1", "target")
  self:SetAttribute("*type2", "togglemenu")
  self:SetAttribute("toggleForVehicle", false)
  header:CallMethod("HogHealsSetup", self:GetName())
]]

local function onChildCreated(header, name)
  local button = _G[name]
  if not button then return end
  if button.RegisterForClicks then button:RegisterForClicks("AnyDown") end
  HHF.UnitButton.Setup(button)
  if HHF.ClickCast and HHF.ClickCast.ApplyTo then HHF.ClickCast.ApplyTo(button) end
end

local function anchorFrame()
  if Headers.anchor then return Headers.anchor end
  local a = CreateFrame("Frame", "HogHealsAnchor", UIParent)
  a:SetSize(120, 20)
  a:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
  a:SetMovable(true)
  a:SetClampedToScreen(true)
  a:EnableMouse(false)
  a:Hide()
  Headers.anchor = a
  return a
end

local function newHeader(name)
  local h = CreateFrame("Frame", name, UIParent, "SecureGroupHeaderTemplate")
  h:SetAttribute("template", "SecureUnitButtonTemplate")
  h:SetAttribute("initialConfigFunction", INITIAL_CONFIG)
  h.HogHealsSetup = onChildCreated
  h:Hide()
  return h
end

function Headers.Spawn()
  if Headers.party then return end
  anchorFrame()
  local p = newHeader("HogHealsPartyHeader")
  p:SetAttribute("showParty", true)
  p:SetAttribute("showPlayer", true)
  p:SetAttribute("showSolo", true)
  p:SetAttribute("showRaid", false)
  p:SetPoint("TOPLEFT", Headers.anchor, "TOPLEFT", 0, 0)
  Headers.party = p
  for g = 1, NUM_GROUPS do
    local r = newHeader("HogHealsRaidHeader" .. g)
    r:SetAttribute("showRaid", true)
    r:SetAttribute("showParty", false)
    r:SetAttribute("showPlayer", true)
    r:SetAttribute("showSolo", false)
    r:SetAttribute("groupFilter", tostring(g))
    r:SetPoint("TOPLEFT", Headers.anchor, "TOPLEFT", 0, 0)
    Headers.raid[g] = r
  end
end

local function configure(header, cfg)
  local a = Layout.HeaderAttributes(cfg)
  header:SetAttribute("hhWidth", cfg.width)
  header:SetAttribute("hhHeight", cfg.height)
  header:SetAttribute("point", a.point)
  header:SetAttribute("xOffset", a.xOffset)
  header:SetAttribute("yOffset", a.yOffset)
  header:SetAttribute("unitsPerColumn", a.unitsPerColumn)
  header:SetAttribute("maxColumns", a.maxColumns)
  header:SetAttribute("columnSpacing", a.columnSpacing)
  header:SetAttribute("columnAnchorPoint", a.columnAnchorPoint)
  header:SetAttribute("sortMethod", "INDEX")
end

local function applyNow(bucket)
  local frames = HH.db.profile.frames
  local cfg = frames.layouts[bucket] or frames.layouts.party
  local anchor = anchorFrame()
  anchor:ClearAllPoints()
  anchor:SetPoint(cfg.anchor.point or "CENTER", UIParent, cfg.anchor.point or "CENTER", cfg.anchor.x or 0, cfg.anchor.y or 0)
  local w, h = Layout.Extent(cfg, math.max(1, cfg.groupsShown or 1))
  anchor:SetSize(w, h)

  local isRaid = bucket ~= "solo" and bucket ~= "party"
  if Headers.party then
    configure(Headers.party, cfg)
    Headers.party:SetAttribute("showSolo", cfg.showSolo ~= false)
    Headers.party:ClearAllPoints()
    Headers.party:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    if isRaid then Headers.party:Hide() else Headers.party:Show() end
  end
  local shown = isRaid and (cfg.groupsShown or NUM_GROUPS) or 0
  for g = 1, NUM_GROUPS do
    local r = Headers.raid[g]
    if r then
      configure(r, cfg)
      local x, y = Layout.GroupOffset(cfg, g)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)
      if g <= shown then r:Show() else r:Hide() end
    end
  end
  for _, button in ipairs(HHF.UnitButton.All()) do
    button:SetSize(cfg.width, cfg.height)
  end
end

--- Apply a bucket layout; deferred until out of combat if needed.
function Headers.Apply(bucket)
  HH:RunOutOfCombat(applyNow, bucket)
end

function Headers.SetLocked(locked)
  local a = anchorFrame()
  a:EnableMouse(not locked)
  if locked then a:Hide() else a:Show() end
end
