-- Quest markers on the minimap.
--
-- Not Questie: Questie ships a hand-built database of every quest giver and mob spawn. We draw what the CLIENT
-- knows: C_QuestLog.GetQuestsOnMap(mapID) gives one point per active quest (Blizzard's own POI: the objective area,
-- then the turn-in once complete). Forever has no Blizzard setting that puts those on the minimap (the
-- minimapShowQuestBlobs cvar is nil there, probe 2026-09-17), so we place pins ourselves:
--   yards  = (quest - player) in map units * map size in yards
--   pixels = yards / minimap view radius * (minimap width / 2), rotated by facing when the minimap rotates.
-- Out of range pins stick to the rim (dimmed) so you still know which way to walk.
HogHealsQuests = HogHealsQuests or {}
local HHQ = HogHealsQuests
local HH = HogHeals

local Pins = { pool = {}, sizeCache = {} }
HHQ.Pins = Pins

-- ON by default. 2026-09-22 in game: Forever draws only the shaded quest AREAS and one gold rim arrow for the
-- super-tracked quest, no point markers; the "clutter" was our old drawn squares on top of each other. So: our pins
-- mark the points, and the super-tracked quest gets no rim arrow from us (Blizzard's gold one is already there).
-- Art = HogHeals/Media/quest_*.tga (dev/icons/build_icons.py); a client that refuses the file (SetTexture -> false)
-- gets a drawn square + glyph instead, never an invisible pin. Far quests show a rotated arrow on the rim.
local OPEN = { art = "Interface\\AddOns\\HogHeals\\Media\\quest_open", glyph = "!", color = { 0.95, 0.65, 0.15 } }
local DONE = { art = "Interface\\AddOns\\HogHeals\\Media\\quest_done", glyph = "?", color = { 0.25, 0.80, 0.35 } }
local ARROW = "Interface\\AddOns\\HogHeals\\Media\\quest_arrow"

-- Classic minimap diameters in yards per zoom level (HereBeDragons-Pins table) - only used when the client has no
-- C_Minimap.GetViewRadius.
local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }

local function cfg() return HH.db.profile.quests.minimap end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end

local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c = pcall(f, ...)
  if ok then return a, b, c end
end

-- ------------------------------------------------------------------------------------------------ geometry
--- Player's map and 0..1 position on it, or nil (instances / restricted: no position = no pins).
function Pins.PlayerPosition()
  if type(C_Map) ~= "table" then return nil end
  local mapID = num(try(C_Map.GetBestMapForUnit, "player"))
  if not mapID then return nil end
  local pos = try(C_Map.GetPlayerMapPosition, mapID, "player")
  if type(pos) ~= "table" and type(pos) ~= "userdata" then return nil end
  local x, y
  if pos.GetXY then x, y = try(pos.GetXY, pos) else x, y = pos.x, pos.y end
  x, y = num(x), num(y)
  if not x or not y or (x == 0 and y == 0) then return nil end
  return mapID, x, y
end

--- Map width and height in yards. C_Map.GetMapWorldSize when present, else two corner lookups.
function Pins.MapSize(mapID)
  local c = Pins.sizeCache[mapID]
  if c then return c[1], c[2] end
  local w, h
  if type(C_Map) == "table" and type(C_Map.GetMapWorldSize) == "function" then
    w, h = try(C_Map.GetMapWorldSize, mapID)
  end
  if not (num(w) and num(h) and w > 0 and h > 0) and type(C_Map) == "table" and type(C_Map.GetWorldPosFromMapPos) == "function" then
    local mk = rawget(_G, "CreateVector2D")
    local v0 = mk and mk(0, 0) or { x = 0, y = 0 }
    local v1 = mk and mk(1, 1) or { x = 1, y = 1 }
    local _, a = try(C_Map.GetWorldPosFromMapPos, mapID, v0)
    local _, b = try(C_Map.GetWorldPosFromMapPos, mapID, v1)
    if a and b then
      local ax, ay = a.x, a.y
      local bx, by = b.x, b.y
      if a.GetXY then ax, ay = a:GetXY() end
      if b.GetXY then bx, by = b:GetXY() end
      -- world coordinates are (north, west): map width comes from the y delta and vice versa
      if num(ax) and num(bx) and num(ay) and num(by) then w, h = math.abs(ay - by), math.abs(ax - bx) end
    end
  end
  if num(w) and num(h) and w > 0 and h > 0 then
    Pins.sizeCache[mapID] = { w, h }
    return w, h
  end
  return nil
end

--- Minimap view radius in yards.
function Pins.ViewRadius()
  if type(C_Minimap) == "table" and type(C_Minimap.GetViewRadius) == "function" then
    local r = num(try(C_Minimap.GetViewRadius))
    if r and r > 0 then return r end
  end
  local zoom = (Minimap and Minimap.GetZoom and Minimap:GetZoom()) or 0
  local indoor = type(IsIndoors) == "function" and try(IsIndoors) and true or false
  local t = indoor and INDOOR or OUTDOOR
  return (t[zoom] or t[0]) / 2
end

local function rotating()
  return type(GetCVar) == "function" and GetCVar("rotateMinimap") == "1"
end

--- Pure placement: yards offset (east +, south +) -> pixel offset from minimap centre, and whether it is on the rim.
-- facing = radians counter-clockwise from north (GetPlayerFacing), only applied when the minimap rotates.
function Pins.Place(dxYards, dyYards, radius, halfWidth, facing, square)
  local sx, sy = dxYards, -dyYards                     -- screen: east = +x, north = +y
  if facing then
    local c, s = math.cos(facing), math.sin(facing)
    sx, sy = sx * c + sy * s, -sx * s + sy * c         -- turn the world so the facing direction points up
  end
  local px, py = sx / radius * halfWidth, sy / radius * halfWidth
  local edge = false
  if square then
    local m = math.max(math.abs(px), math.abs(py))
    if m > halfWidth then px, py, edge = px / m * halfWidth, py / m * halfWidth, true end
  else
    local d = math.sqrt(px * px + py * py)
    if d > halfWidth then px, py, edge = px / d * halfWidth, py / d * halfWidth, true end
  end
  return px, py, edge
end

-- ------------------------------------------------------------------------------------------------ pins
local function pin(i)
  local p = Pins.pool[i]
  if p then return p end
  p = CreateFrame("Button", nil, Minimap)
  p:SetFrameStrata("MEDIUM")
  p:SetFrameLevel(((Minimap.GetFrameLevel and Minimap:GetFrameLevel()) or 1) + 5)
  p.edge = p:CreateTexture(nil, "BACKGROUND")
  p.edge:SetPoint("TOPLEFT", p, "TOPLEFT", -1, 1)
  p.edge:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 1, -1)
  p.edge:SetColorTexture(0.05, 0.05, 0.06, 1)
  p.icon = p:CreateTexture(nil, "ARTWORK")
  p.icon:SetAllPoints(p)
  p.arrow = p:CreateTexture(nil, "OVERLAY")
  p.arrow:SetAllPoints(p)
  p.arrow:Hide()
  p.glyph = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  p.glyph:SetPoint("CENTER", p, "CENTER", 0, 0)
  p.glyph:SetTextColor(0.07, 0.07, 0.09)
  p:SetScript("OnEnter", function(self)
    local q = self.quest
    if not GameTooltip or not q then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine(q.title or "?")
    if q.complete then GameTooltip:AddLine("Ready to turn in", 0.25, 0.8, 0.35)
    else
      for _, o in ipairs(q.objectives or {}) do
        if not o.done then GameTooltip:AddLine("- " .. tostring(o.text), 0.96, 0.92, 0.86) end
      end
    end
    if self.waypoint then GameTooltip:AddLine(self.waypoint, 0.13, 0.83, 0.88, true) end
    if self.yards then GameTooltip:AddLine(("%d yards"):format(self.yards), 0.55, 0.55, 0.6) end
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  p:SetScript("OnClick", function(self) if self.quest then HHQ.Data.Open(self.quest) end end)
  Pins.pool[i] = p
  return p
end

function Pins.HideAll() for _, p in ipairs(Pins.pool) do p:Hide() end end

--- Art when the client takes our texture, drawn square + glyph when it does not. On the rim: the arrow art, turned
-- to point from the minimap centre toward the quest (arrow art points up = angle 0).
function Pins.Paint(p, look, edge, ox, oy, s)
  local drawn
  if edge then
    p.icon:Hide()
    local ok = p.arrow:SetTexture(ARROW)
    drawn = (ok == false)
    if not drawn then
      p.arrow:Show()
      if p.arrow.SetRotation then pcall(p.arrow.SetRotation, p.arrow, math.atan2(oy, ox) - math.pi / 2) end
    else
      p.arrow:Hide()
    end
  else
    p.arrow:Hide()
    p.icon:Show()
    local ok = p.icon:SetTexture(look.art)
    drawn = (ok == false)
  end
  p.drawn = drawn
  if drawn then
    p.icon:Show()
    p.icon:SetColorTexture(look.color[1], look.color[2], look.color[3], 1)
    p.glyph:SetText(look.glyph)
    local font = p.glyph.GetFont and p.glyph:GetFont()
    if font and p.glyph.SetFont then pcall(p.glyph.SetFont, p.glyph, font, math.max(7, s - 3), "") end
    p.glyph:Show()
    p.edge:Show()
  else
    p.glyph:Hide()
    p.edge:Hide()
  end
end

--- Place every pin for the player's current map. Returns the number shown (tests read it).
function Pins.Update()
  local d = cfg()
  if d.enabled == false or not Minimap then Pins.HideAll() return 0 end
  local mapID, px, py = Pins.PlayerPosition()
  if not mapID then Pins.HideAll() Pins.why = "no player position" return 0 end
  local w, h = Pins.MapSize(mapID)
  if not w then Pins.HideAll() Pins.why = "no map size for " .. tostring(mapID) return 0 end
  local points = HHQ.Data.PointsOnMap(mapID)
  local byId = {}
  for _, q in ipairs(HHQ.Data.last or HHQ.Data.List()) do if q.id then byId[q.id] = q end end
  local radius = Pins.ViewRadius()
  local half = ((Minimap.GetWidth and Minimap:GetWidth()) or 140) / 2
  local facing = rotating() and type(GetPlayerFacing) == "function" and num(try(GetPlayerFacing)) or nil
  local square = type(GetMinimapShape) == "function" and try(GetMinimapShape) == "SQUARE"
  local size = d.size or 14
  local superTracked = type(C_SuperTrack) == "table" and num(try(C_SuperTrack.GetSuperTrackedQuestID)) or nil
  local n = 0
  for _, pt in ipairs(points) do
    local q = pt.id and byId[pt.id] or { title = "Quest " .. tostring(pt.id), objectives = {} }
    if not (d.watchedOnly and not q.watched) then
      local dx, dy = (pt.x - px) * w, (pt.y - py) * h
      local ox, oy, edge = Pins.Place(dx, dy, radius, half - size / 3, facing, square)
      if (not edge or d.edge ~= false) and not (edge and pt.id ~= nil and pt.id == superTracked) then
        n = n + 1
        local p = pin(n)
        p.quest, p.yards = q, math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)
        p.waypoint = pt.waypoint and ("Next step: " .. (pt.text or "follow the marker")) or nil
        local look = q.complete and DONE or OPEN
        local s = edge and math.floor(size * 0.85) or size
        p.kind = look.glyph
        Pins.Paint(p, look, edge, ox, oy, s)
        p:SetSize(s, s)
        p:SetAlpha(edge and 0.6 or 1)
        p:ClearAllPoints()
        p:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
        p:Show()
      end
    end
  end
  for i = n + 1, #Pins.pool do Pins.pool[i]:Hide() end
  Pins.why = nil
  Pins.shown = n
  return n
end

function Pins.Start()
  Pins.Stop()
  if cfg().enabled == false then return end
  if C_Timer and C_Timer.NewTicker then
    Pins.ticker = C_Timer.NewTicker(0.2, function()
      local ok, err = xpcall(Pins.Update, HH.Trace)
      if not ok and err ~= Pins.lastError then Pins.lastError = err HH:LogError("minimap pins: " .. tostring(err)) end
    end)
  end
  Pins.Update()
end

function Pins.Stop()
  if Pins.ticker then Pins.ticker:Cancel() Pins.ticker = nil end
end

function Pins.Refresh()
  if cfg().enabled == false then Pins.Stop() Pins.HideAll() return end
  Pins.Start()
end

--- What the minimap side can see on this client, for the diag log.
function Pins.Probe()
  local mapID, x, y = Pins.PlayerPosition()
  local w, h
  if mapID then w, h = Pins.MapSize(mapID) end
  local pts = mapID and HHQ.Data.PointsOnMap(mapID) or {}
  return {
    mapID = mapID or "nil", pos = x and (("%.3f,%.3f"):format(x, y)) or "nil",
    size = w and (("%.0fx%.0f"):format(w, h)) or "nil",
    radius = Pins.ViewRadius(), points = #pts,
    GetMapWorldSize = (type(C_Map) == "table" and type(C_Map.GetMapWorldSize) == "function") and "fn" or "nil",
    GetWorldPosFromMapPos = (type(C_Map) == "table" and type(C_Map.GetWorldPosFromMapPos) == "function") and "fn" or "nil",
    GetViewRadius = (type(C_Minimap) == "table" and type(C_Minimap.GetViewRadius) == "function") and "fn" or "nil",
    rotate = rotating() and "1" or "0",
  }
end
