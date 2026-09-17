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

-- NO secure snippets here. An initialConfigFunction is compiled by Blizzard's RestrictedExecution.lua,
-- and the WoW: Forever beta (1.60.1.69893) cannot compile any: "RestrictedExecution.lua:79: attempt to
-- call a nil value" (loadstring_untainted == nil) on the header's first child, which kills the header.
-- Instead: children are configured from plain Lua, which is legal out of combat, and every header
-- pre-creates a full group of buttons so the header never has to create one during combat.
local GROUP_SIZE = 5

local function setupChild(button, cfg)
  if not button then return end
  if not button._hhSetup then
    button:SetAttribute("*type1", "target")
    button:SetAttribute("*type2", "togglemenu")
    button:SetAttribute("toggleForVehicle", false)
    if button.RegisterForClicks then button:RegisterForClicks("AnyDown") end
    HHF.UnitButton.Setup(button)
    if HHF.ClickCast and HHF.ClickCast.ApplyTo then HHF.ClickCast.ApplyTo(button) end
  end
  button:SetSize(cfg.width, cfg.height)
  -- The header assigned "unit" before our OnAttributeChanged handler existed; replay it.
  HHF.UnitButton.OnAttributeChanged(button, "unit", button:GetAttribute("unit"))
end

local function child(header, n)
  return header:GetAttribute("child" .. n) or header[n]
end

--- Force a shown header to create GROUP_SIZE buttons now, then configure them. Out of combat only.
local function ensureChildren(header, cfg)
  if not child(header, GROUP_SIZE) then
    header:SetAttribute("startingIndex", 1 - GROUP_SIZE)
    header:SetAttribute("startingIndex", 1)
  end
  local n = 1
  while child(header, n) do
    setupChild(child(header, n), cfg)
    n = n + 1
  end
  -- The header measured its children while they were still 0x0; make it lay out again now they are sized.
  header:SetAttribute("startingIndex", 1)
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
    if isRaid then Headers.party:Hide() else Headers.party:Show(); ensureChildren(Headers.party, cfg) end
  end
  local shown = isRaid and (cfg.groupsShown or NUM_GROUPS) or 0
  for g = 1, NUM_GROUPS do
    local r = Headers.raid[g]
    if r then
      configure(r, cfg)
      local x, y = Layout.GroupOffset(cfg, g)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)
      if g <= shown then r:Show(); ensureChildren(r, cfg) else r:Hide() end
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
