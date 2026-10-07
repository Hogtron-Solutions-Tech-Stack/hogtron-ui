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
  t.hhOurs = true
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
  f.zone = f.header:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
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
  -- before any resize: the overlay test compares each texture with the map's CURRENT size
  local hidden = Skin.HideOverlays()
  if #hidden > 0 or not Skin.hiddenOverlays then Skin.hiddenOverlays = hidden end
  call(Minimap.SetMaskTexture, Minimap, "Interface\\Buttons\\WHITE8X8")
  _G.GetMinimapShape = function() return "SQUARE" end
  Skin.rings = Skin.HideBlobRings()
  local s = Skin.TargetSize()
  if d.fill ~= false and type(MinimapCluster) == "table" then
    -- 2026-09-22 in game: the map sat at 180 px inside a much bigger Edit Mode box. Fill the box instead, under our
    -- header, leaving FOOTER px for the client's coordinates line below the map.
    call(Minimap.ClearAllPoints, Minimap)
    call(Minimap.SetPoint, Minimap, "TOP", MinimapCluster, "TOP", 0, -(Skin.TOP_OFFSET + HEADER_H))
  end
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
  Skin.DockButtons()
  Skin.HookCluster()
  Skin.missing = missing
  return missing
end

-- The hatched circle over a square map (2026-09-22, "what is the ring"): the ENGINE's quest-area edge ring, drawn at
-- the rim of the round minimap view whenever you stand inside a quest area. Not a texture region (diag listed every
-- region: all already hidden), so it is switched off through the Minimap's own blob-ring settings, the same calls
-- square-minimap UIs (ElvUI) make. Returns the setters this client has, for diag.
function Skin.HideBlobRings()
  local found = {}
  for _, m in ipairs({ "SetQuestBlobRingScalar", "SetQuestBlobRingAlpha", "SetArchBlobRingScalar", "SetArchBlobRingAlpha",
    "SetTaskBlobRingScalar", "SetTaskBlobRingAlpha" }) do
    if type(Minimap[m]) == "function" and pcall(Minimap[m], Minimap, 0) then found[#found + 1] = m end
  end
  return found
end

Skin.TOP_OFFSET = 24   -- room above our header for the clock / mail / tracking row the client keeps there
Skin.FOOTER = 18       -- room below the map for the client's coordinates text

--- Map edge length: the whole cluster box when fill is on (default), the size slider otherwise.
function Skin.TargetSize()
  local d = cfg()
  if d.fill ~= false and type(MinimapCluster) == "table" and MinimapCluster.GetWidth then
    local w, h = MinimapCluster:GetWidth() or 0, MinimapCluster:GetHeight() or 0
    local s = math.floor(math.min(w - 12, h - Skin.TOP_OFFSET - HEADER_H - Skin.FOOTER - 8))
    if s >= 100 then return s end
  end
  return d.size or 180
end

--- Follow Edit Mode: resizing the minimap box re-fits the map.
function Skin.HookCluster()
  if Skin.clusterHooked or type(MinimapCluster) ~= "table" or not MinimapCluster.HookScript then return end
  Skin.clusterHooked = true
  MinimapCluster:HookScript("OnSizeChanged", function()
    if cfg().enabled ~= false and cfg().fill ~= false then
      local s = Skin.TargetSize()
      call(Minimap.SetSize, Minimap, s, s)
    end
    -- the quest tracker hangs under this box: its available height just changed
    if HHQ.Tracker and HHQ.Tracker.Schedule then HHQ.Tracker.Schedule() end
  end)
end

-- Round buttons that sat ON the map (2026-09-22: the Looking-for-Group eye, the day/night sun). Docked into the
-- header strip at header height instead. Several names per button: client generations call them differently.
Skin.DOCK = {
  { side = "LEFT", names = { "GameTimeFrame" } },
  { side = "RIGHT", names = { "QueueStatusButton", "MiniMapLFGFrame", "LFGMinimapFrame", "MiniMapBattlefieldFrame" } },
}

-- Flags about Blizzard's buttons are kept in side tables, never written onto the buttons (see Tracker.lua).
local docking = setmetatable({}, { __mode = "k" })
local dockHooked = setmetatable({}, { __mode = "k" })
Skin.dockHooked = dockHooked

function Skin.DockButtons()
  local f = Skin.frame
  if not f or cfg().dockButtons == false then return end
  Skin.docked = {}
  for _, slot in ipairs(Skin.DOCK) do
    for _, n in ipairs(slot.names) do
      local b = rawget(_G, n)
      if type(b) == "table" and b.ClearAllPoints then
        HH:RunOutOfCombat(function()
          docking[b] = true
          local bw = (b.GetWidth and b:GetWidth()) or 32
          local scale = (HEADER_H - 2) / math.max(bw, 1)
          call(b.SetScale, b, scale)
          call(b.ClearAllPoints, b)
          if slot.side == "LEFT" then call(b.SetPoint, b, "LEFT", f.header, "LEFT", 2 / scale, 0)
          else call(b.SetPoint, b, "RIGHT", f.header, "RIGHT", -2 / scale, 0) end
          call(b.SetFrameLevel, b, f.header:GetFrameLevel() + 3)
          docking[b] = nil
        end)
        Skin.docked[#Skin.docked + 1] = n
        -- 2026-09-22 in game: the day/night button was docked, then the client's layout put it back on the map
        if not dockHooked[b] and type(hooksecurefunc) == "function" and b.SetPoint then
          dockHooked[b] = true
          pcall(hooksecurefunc, b, "SetPoint", function(self)
            if docking[self] or cfg().enabled == false or cfg().dockButtons == false then return end
            if InCombatLockdown and InCombatLockdown() then return end
            docking[self] = true
            Skin.DockButtons()
            docking[self] = nil
          end)
        end
        break
      end
    end
  end
end

--- Big textures lying over the map (the round white ring seen 2026-09-22, name unknown): any texture region of the
-- Minimap or MinimapBackdrop that is not ours and covers most of the map. Blips and terrain are not regions, so
-- they cannot be caught by this. Returns "name|texture" of each one hidden, for diag.
function Skin.HideOverlays()
  local out = {}
  if cfg().hideDecor == false then return out end
  local mw = (Minimap.GetWidth and Minimap:GetWidth()) or 0
  for _, owner in ipairs({ Minimap, rawget(_G, "MinimapBackdrop") }) do
    if type(owner) == "table" and owner.GetRegions then
      for _, r in ipairs({ owner:GetRegions() }) do
        if r and not r.hhOurs and r.GetObjectType and r:GetObjectType() == "Texture" then
          local w = (r.GetWidth and r:GetWidth()) or 0
          if w >= mw * 0.8 and mw > 0 then
            local tex = call(r.GetTexture, r) or call(r.GetAtlas, r) or "?"
            out[#out + 1] = tostring(r.GetName and r:GetName() or "?") .. "|" .. tostring(tex)
            call(r.SetAlpha, r, 0)
            call(r.Hide, r)
          end
        end
      end
    end
  end
  return out
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
  local regions = {}
  for _, owner in ipairs({ Minimap, rawget(_G, "MinimapBackdrop"), rawget(_G, "MinimapCluster") }) do
    if type(owner) == "table" and owner.GetRegions then
      for _, r in ipairs({ owner:GetRegions() }) do
        if r and r.GetObjectType and r:GetObjectType() == "Texture" and not r.hhOurs then
          regions[#regions + 1] = tostring(r.GetName and r:GetName() or "?") .. "|" .. tostring(call(r.GetTexture, r) or call(r.GetAtlas, r))
            .. "|" .. tostring(math.floor((r.GetWidth and r:GetWidth() or 0) + 0.5)) .. "|" .. tostring(r.IsShown and r:IsShown())
        end
        if #regions >= 30 then break end
      end
    end
  end
  return { names = table.concat(names, ","), mask = (Minimap and Minimap.SetMaskTexture) and "fn" or "nil",
    regions = table.concat(regions, " ; "), hidden = table.concat(Skin.hiddenOverlays or {}, " ; "),
    docked = table.concat(Skin.docked or {}, ","), rings = table.concat(Skin.rings or {}, ","),
    cluster = (type(MinimapCluster) == "table" and MinimapCluster.GetWidth) and (math.floor(MinimapCluster:GetWidth()) .. "x" .. math.floor(MinimapCluster:GetHeight())) or "nil",
    size = Minimap and (tostring(Minimap:GetWidth()) .. "x" .. tostring(Minimap:GetHeight())) or "nil" }
end
