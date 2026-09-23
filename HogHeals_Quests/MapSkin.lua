-- Minimap in the HogHeals panel look: square, ink frame, 1 px outline, zone name on a header strip with a cyan rule.
--
-- Restyle only: the Minimap frame, its blips and Blizzard's own quest markers are untouched; we change its mask to a
-- square, hide the ornate round border art, and draw our frame around it. The buttons that DO something (tracking,
-- mail, clock, calendar, LFG) are left where Blizzard puts them. GetMinimapShape() is defined as "SQUARE" while the
-- skin is on, the convention every minimap-button addon (LibDBIcon) and our own pins read.
-- Every Blizzard name is looked up, never assumed: names differ between client generations, a missing one is skipped
-- and listed in diag.quests.map so the next session tells us what this client calls things.
HogHealsQuests = HogHealsQuests or {}
local HHQ = HogHealsQuests
local HH = HogHeals

local Skin = {}
HHQ.MapSkin = Skin

local CREAM = { 0.96, 0.92, 0.86 }
local CYAN = { 0.13, 0.83, 0.88 }
local INK = { 0.07, 0.07, 0.09 }
local LINE = { 0.20, 0.20, 0.25 }
local HEADER_H = 20

local function cfg() return HH.db.profile.quests.map end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
end

-- Decoration only. Classic-era names first, then the modern MinimapCluster / Minimap children.
Skin.DECOR = { "MinimapBorder", "MinimapBorderTop", "MinimapNorthTag", "MinimapCompassTexture", "MinimapZoomIn",
  "MinimapZoomOut", "MiniMapWorldMapButton", "MinimapToggleButton", "MinimapZoneTextButton" }
Skin.DECOR_CHILDREN = { { "MinimapCluster", "BorderTop" }, { "MinimapCluster", "ZoneTextButton" }, { "Minimap", "ZoomIn" },
  { "Minimap", "ZoomOut" }, { "MinimapCluster", "Tracking", keep = true } }

local hiddenParent
local function banish(f)
  if type(f) ~= "table" then return false end
  hiddenParent = hiddenParent or _G.HogHealsHiddenParent
  if not hiddenParent then
    hiddenParent = CreateFrame("Frame", "HogHealsHiddenParent", UIParent)
    hiddenParent:Hide()
  end
  if f.GetObjectType and f:GetObjectType() == "Texture" then
    call(f.SetTexture, f, nil)
    call(f.Hide, f)
    return true
  end
  call(f.Hide, f)
  call(f.SetParent, f, hiddenParent)
  return true
end

local function solid(parent, layer, c, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  return t
end

local function zoneColor()
  local pvp = call(GetZonePVPInfo)
  if pvp == "sanctuary" then return 0.41, 0.8, 0.94
  elseif pvp == "friendly" then return 0.1, 1.0, 0.1
  elseif pvp == "hostile" then return 1.0, 0.1, 0.1
  elseif pvp == "contested" then return 1.0, 0.7, 0.0 end
  return CREAM[1], CREAM[2], CREAM[3]
end

local function build()
  if Skin.frame then return Skin.frame end
  local f = CreateFrame("Frame", "HogHealsMinimapFrame", Minimap)
  f:SetFrameLevel(math.max(0, ((Minimap.GetFrameLevel and Minimap:GetFrameLevel()) or 1) - 1))
  f:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -4, 4 + HEADER_H)
  f:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 4, -4)
  f.bg = solid(f, "BACKGROUND", INK, 0.92)
  f.bg:SetAllPoints(f)
  f.edges = {}
  local spec = { { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }
  for i, sp in ipairs(spec) do
    local e = solid(f, "BORDER", LINE)
    e:SetPoint(sp[1], f, sp[1], 0, 0)
    e:SetPoint(sp[2], f, sp[2], 0, 0)
    if sp[3] then e:SetWidth(sp[3]) end
    if sp[4] then e:SetHeight(sp[4]) end
    f.edges[i] = e
  end
  -- header strip: zone name + cyan rule, the same header as the tracker and the meter
  f.header = CreateFrame("Button", nil, f)
  f.header:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  f.header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
  f.header:SetHeight(HEADER_H - 2)
  f.header.bg = solid(f.header, "BACKGROUND", { 0.11, 0.11, 0.14 })
  f.header.bg:SetAllPoints(f.header)
  f.rule = solid(f.header, "ARTWORK", CYAN)
  f.rule:SetPoint("BOTTOMLEFT", f.header, "BOTTOMLEFT", 0, 0)
  f.rule:SetPoint("BOTTOMRIGHT", f.header, "BOTTOMRIGHT", 0, 0)
  f.rule:SetHeight(1)
  f.zone = f.header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.zone:SetPoint("LEFT", f.header, "LEFT", 6, 0)
  f.zone:SetPoint("RIGHT", f.header, "RIGHT", -6, 0)
  f.zone:SetJustifyH("CENTER")
  if f.zone.SetWordWrap then f.zone:SetWordWrap(false) end
  -- the zone name is also the world map button we hid
  f.header:SetScript("OnClick", function()
    if type(ToggleWorldMap) == "function" then call(ToggleWorldMap)
    elseif WorldMapFrame and type(ShowUIPanel) == "function" then call(ShowUIPanel, WorldMapFrame) end
  end)
  Skin.frame = f
  return f
end

function Skin.UpdateZone()
  local f = Skin.frame
  if not f then return end
  if cfg().zoneText == false then f.zone:Hide() return end
  local z = call(GetMinimapZoneText) or call(GetZoneText) or ""
  f.zone:SetText(z)
  f.zone:SetTextColor(zoneColor())
  f.zone:Show()
end

local function wheel(_, delta)
  local z = Minimap:GetZoom() or 0
  local max = (Minimap.GetZoomLevels and Minimap:GetZoomLevels()) or 6
  if delta > 0 and z < max - 1 then Minimap:SetZoom(z + 1)
  elseif delta < 0 and z > 0 then Minimap:SetZoom(z - 1) end
end

--- Apply everything. Returns the list of decoration names that were NOT found (for the diag log).
function Skin.Apply()
  local d = cfg()
  if d.enabled == false or not Minimap then return {} end
  local missing = {}
  if d.hideDecor ~= false then
    for _, n in ipairs(Skin.DECOR) do
      if not banish(rawget(_G, n)) then missing[#missing + 1] = n end
    end
    for _, pair in ipairs(Skin.DECOR_CHILDREN) do
      local parent = rawget(_G, pair[1])
      if not pair.keep and type(parent) == "table" then banish(parent[pair[2]]) end
    end
  end
  call(Minimap.SetMaskTexture, Minimap, "Interface\\Buttons\\WHITE8X8")
  _G.GetMinimapShape = function() return "SQUARE" end
  local s = d.size or 180
  call(Minimap.SetSize, Minimap, s, s)
  -- a resized minimap only redraws its map after a zoom change
  local z = Minimap:GetZoom() or 0
  call(Minimap.SetZoom, Minimap, z > 0 and z - 1 or z + 1)
  call(Minimap.SetZoom, Minimap, z)
  build():Show()
  if d.wheelZoom ~= false and Minimap.EnableMouseWheel then
    Minimap:EnableMouseWheel(true)
    -- only when the client has no wheel zoom of its own (a second handler would zoom two steps per click)
    if not Skin.wheelHooked and not (Minimap.GetScript and Minimap:GetScript("OnMouseWheel")) then
      Skin.wheelHooked = true
      Minimap:SetScript("OnMouseWheel", function(...) if cfg().wheelZoom ~= false then wheel(...) end end)
    end
  end
  Skin.UpdateZone()
  Skin.missing = missing
  return missing
end

function Skin.Refresh()
  if cfg().enabled == false then
    if Skin.frame then Skin.frame:Hide() end
    return
  end
  Skin.Apply()
end

function Skin.Probe()
  local names = {}
  for _, n in ipairs(Skin.DECOR) do names[#names + 1] = n .. "=" .. (rawget(_G, n) and "y" or "n") end
  for _, pair in ipairs(Skin.DECOR_CHILDREN) do
    local parent = rawget(_G, pair[1])
    names[#names + 1] = pair[1] .. "." .. pair[2] .. "=" .. ((type(parent) == "table" and parent[pair[2]]) and "y" or "n")
  end
  return { names = table.concat(names, ","), mask = (Minimap and Minimap.SetMaskTexture) and "fn" or "nil",
    size = Minimap and (tostring(Minimap:GetWidth()) .. "x" .. tostring(Minimap:GetHeight())) or "nil" }
end
