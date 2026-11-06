-- World map (M) in the HogTron UI look: coordinates strip (you + cursor), map scale, fade while moving, border art off.
--
-- Sean 2026-09-23: "Leatrix Maps ... shows the terrain much more in-depth ... integrate that or something similar."
-- What Leatrix does that we can: coordinates, scale, fade, art removal, unlock. What it does that we can NOT:
-- revealing unexplored terrain. That needs a hand-built table of every zone's overlay texture ids (Leatrix's own
-- data, years of it) - the client only hands out the textures you have explored. If Leatrix_Maps is loaded we leave
-- the map's art to it and only add what it lacks (nothing today: it has coordinates too, so the strip stays off).
-- Every Blizzard piece is looked up by name and skipped when absent (classic / modern map frames differ).
HogHealsQuests = HogHealsQuests or {}
local HHQ = HogHealsQuests
local HH = HogHeals

local WM = {}
HHQ.WorldMap = WM

local CREAM = { 0.96, 0.92, 0.86 }
local CYAN = { 0.13, 0.83, 0.88 }
local INK = { 0.07, 0.07, 0.09 }
local LINE = { 0.20, 0.20, 0.25 }
local STRIP_H = 20

local function cfg() return HH.db.profile.quests.worldMap end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
end
local function frame() return rawget(_G, "WorldMapFrame") end

local function solid(parent, layer, c, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  t.hhOurs = true
  return t
end

function WM.LeatrixLoaded()
  local f = (type(C_AddOns) == "table" and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
  return call(f, "Leatrix_Maps") == true
end

-- ------------------------------------------------------------------------------------------------ positions
--- Player position on the current map as 0..1 fractions, or nil (instances, secrets, no map).
function WM.PlayerPosition()
  if type(C_Map) == "table" and type(C_Map.GetBestMapForUnit) == "function" and type(C_Map.GetPlayerMapPosition) == "function" then
    local mapID = num(call(C_Map.GetBestMapForUnit, "player"))
    if not mapID then return nil end
    local pos = call(C_Map.GetPlayerMapPosition, mapID, "player")
    if type(pos) ~= "table" then return nil end
    local x, y
    if type(pos.GetXY) == "function" then x, y = call(pos.GetXY, pos) else x, y = pos.x, pos.y end
    x, y = num(x), num(y)
    if x and y then return x, y end
    return nil
  end
  local x, y = call(GetPlayerMapPosition, "player")
  x, y = num(x), num(y)
  if x and y and (x > 0 or y > 0) then return x, y end
  return nil
end

--- Cursor position over the map canvas as 0..1 fractions, or nil when the cursor is off the map.
function WM.CursorPosition()
  local f = frame()
  if not f then return nil end
  local sc = rawget(f, "ScrollContainer")
  if type(sc) == "table" and type(rawget(sc, "GetNormalizedCursorPosition")) == "function" then
    local x, y = call(sc.GetNormalizedCursorPosition, sc)
    x, y = num(x), num(y)
    if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
    return nil
  end
  local canvas = (type(sc) == "table" and rawget(sc, "Child")) or rawget(_G, "WorldMapDetailFrame") or f
  if type(canvas) ~= "table" or type(canvas.GetLeft) ~= "function" then return nil end
  local l, t, w, h = call(canvas.GetLeft, canvas), call(canvas.GetTop, canvas), call(canvas.GetWidth, canvas), call(canvas.GetHeight, canvas)
  local s = call(canvas.GetEffectiveScale, canvas) or 1
  l, t, w, h, s = num(l), num(t), num(w), num(h), num(s)
  if not (l and t and w and h and s and w > 0 and h > 0 and s > 0) then return nil end
  local cx, cy = call(GetCursorPosition)
  cx, cy = num(cx), num(cy)
  if not (cx and cy) then return nil end
  cx, cy = cx / s, cy / s
  local x, y = (cx - l) / w, (t - cy) / h
  if x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
  return nil
end

function WM.Format(x, y)
  if not (x and y) then return "--" end
  return string.format("%.1f, %.1f", x * 100, y * 100)
end

-- ------------------------------------------------------------------------------------------------ strip
local function build(f)
  if WM.strip then return WM.strip end
  local strip = CreateFrame("Frame", "HogUIWorldMapStrip", f)
  strip:SetHeight(STRIP_H)
  strip:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, 0)
  strip:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, 0)
  strip:SetFrameStrata("HIGH")
  strip.bg = solid(strip, "BACKGROUND", INK, 0.92)
  strip.bg:SetAllPoints(strip)
  strip.rule = solid(strip, "BORDER", CYAN, 1)
  strip.rule:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
  strip.rule:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, 0)
  strip.rule:SetHeight(1)
  strip.edge = {}
  for i, sp in ipairs({ { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
    local e = solid(strip, "BORDER", LINE, 1)
    e:SetPoint(sp[1], strip, sp[1], 0, 0)
    e:SetPoint(sp[2], strip, sp[2], 0, 0)
    if sp[3] then e:SetWidth(sp[3]) end
    if sp[4] then e:SetHeight(sp[4]) end
    strip.edge[i] = e
  end
  strip.player = strip:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  strip.player:SetPoint("LEFT", strip, "LEFT", 8, 0)
  strip.player:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
  strip.cursor = strip:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  strip.cursor:SetPoint("RIGHT", strip, "RIGHT", -8, 0)
  strip.cursor:SetTextColor(CYAN[1], CYAN[2], CYAN[3])
  local acc = 0
  strip:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc < 0.1 then return end
    acc = 0
    WM.Tick()
  end)
  WM.strip = strip
  return strip
end

local function setFont(fs, size)
  if fs and fs.SetFont then call(fs.SetFont, fs, HogHeals.Look.Font() or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE") end
end

--- Refresh the coordinates line. Returns the two texts (tests).
function WM.Tick()
  local strip, d = WM.strip, cfg()
  if not strip then return end
  if d.coords == false then strip:Hide() return "", "" end
  local px, py = WM.PlayerPosition()
  local cx, cy = WM.CursorPosition()
  local p = "You  " .. WM.Format(px, py)
  local c = cx and ("Cursor  " .. WM.Format(cx, cy)) or ""
  strip.player:SetText(p)
  strip.cursor:SetText(c)
  return p, c
end

-- ------------------------------------------------------------------------------------------------ skin
--- Border art off, ink backdrop + outline on. Only the frame's own decoration: the map canvas, pins and pois are
-- children of ScrollContainer and never touched. Returns how many textures were hidden.
function WM.Skin(f)
  local d = cfg()
  if WM.skinned or d.skin == false then return 0 end
  WM.skinned = true
  local hidden = 0
  local function strip(fr)
    if type(fr) ~= "table" or type(fr.GetRegions) ~= "function" then return end
    -- every region: { call(...) } kept only the first two (this file's call() returns two values)
    local res = { pcall(fr.GetRegions, fr) }
    for i = 2, (res[1] and #res or 1) do
      local r = res[i]
      if type(r) == "table" and not r.hhOurs and r.GetObjectType and call(r.GetObjectType, r) == "Texture" then
        call(r.SetAlpha, r, 0)
        hidden = hidden + 1
      end
    end
  end
  local border = rawget(f, "BorderFrame")
  strip(border)
  if type(border) == "table" then strip(rawget(border, "NineSlice")) end
  strip(rawget(f, "NineSlice"))
  strip(f)
  local PM = HH.Parchment
  if PM and PM.On and PM.On() then
    -- the Parchment look (Sean 2026-11-05: "everything to match this paper-like theme"): the torn page behind the whole
    -- map window, the title in ink, the quest log beside the map stripped and inked by the window skin (only that
    -- panel - the map's own tiles are never touched)
    WM.page = PM.PageBehind(f, 1)
    local tc = type(border) == "table" and rawget(border, "TitleContainer")
    local title = (type(tc) == "table" and rawget(tc, "TitleText")) or rawget(f, "TitleText")
    local ink = PM.Palette().title
    if type(title) == "table" and title.SetTextColor then
      call(title.SetTextColor, title, ink[1], ink[2], ink[3])
      PM.Font(title, 14)
    end
    WM.InkQuestLog()
    return hidden
  end
  WM.bg = solid(f, "BACKGROUND", INK, d.alpha or 0.95)
  WM.bg:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
  WM.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
  WM.edges = {}
  for i, sp in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
    local e = solid(f, "BORDER", LINE, 1)
    e:SetPoint(sp[1], WM.bg, sp[1], 0, 0)
    e:SetPoint(sp[2], WM.bg, sp[2], 0, 0)
    if sp[3] then e:SetWidth(sp[3]) end
    if sp[4] then e:SetHeight(sp[4]) end
    WM.edges[i] = e
  end
  -- title in cream, our font size
  local tc = type(border) == "table" and rawget(border, "TitleContainer")
  local title = (type(tc) == "table" and rawget(tc, "TitleText")) or rawget(f, "TitleText")
  if type(title) == "table" and title.SetTextColor then
    call(title.SetTextColor, title, CREAM[1], CREAM[2], CREAM[3])
    setFont(title, 14)
  end
  return hidden
end

--- The quest log beside the map (QuestMapFrame) on the page: its art stripped and its text inked by the window skin
--- (HogTron_Skin/Panels.lua Part.Inner), now and as its list is rebuilt. Nothing without the Skin module.
function WM.InkQuestLog()
  local S = rawget(_G, "HogHealsSkin")
  local Panels = type(S) == "table" and S.Panels or nil
  local q = rawget(_G, "QuestMapFrame")
  if not (Panels and Panels.Inner and type(q) == "table") then return false end
  pcall(Panels.Inner, q, "QuestMapFrame")
  if not WM.questLogHooked and q.HookScript then
    WM.questLogHooked = true
    q:HookScript("OnShow", function(self) pcall(Panels.Inner, self, "QuestMapFrame") end)
  end
  return true
end

-- ------------------------------------------------------------------------------------------------ flight masters
-- Sean 2026-11-05, in Moonglade hunting for Faustron: "make it so you can see those [flight masters] on the map".
-- Forever's own map draws no flight points: its pin pools (diag.quests.offers.pinPools, 2026-11-05) are FogOfWar,
-- GroupMembers, MapExploration, MapHighlight, QuestBlob and ScenarioBlob - no FlightPointPinTemplate. So we draw our
-- own pins on the map canvas, from two sources the client itself hands out:
--   api      C_TaxiMap.GetTaxiNodesForMap(mapID) - the list Blizzard's modern flight-point pins read, if this client
--            answers it (it would include masters you have not met yet). /hh flightdiag says whether it does.
--   learned  every flight map you open (TAXIMAP_OPENED): the master you talk to (where you stand, the NPC's name) and
--            every node that flight map lists. Kept account-wide per faction (db.global.flightPoints) as WORLD
--            positions, so one pin shows on its zone map and on the continent map.
-- No bundled NPC database: the ones that exist are All Rights Reserved (Zygor) or GPL (Questie); this addon is MIT.
local FP = { why = "not drawn yet", pins = {} }
WM.Flight = FP

local PIN = 18
local NEAR = 0.012   -- two pins this close (map fractions) are one flight master
local FILE_ICON = "Interface\\TaxiFrame\\UI-Taxi-Icon-Yellow"
local ATLASES = { "TaxiNode_Neutral", "FlightMaster" }

local function str(v) if type(v) == "string" and not isSecret(v) and v ~= "" then return v end end
local function bool(v) if type(v) == "boolean" then return v end end
local function xy(p)
  if type(p) ~= "table" then return nil end
  local x, y
  if type(p.GetXY) == "function" then x, y = call(p.GetXY, p) else x, y = p.x, p.y end
  return num(x), num(y)
end
local function vec(x, y)
  local mk = rawget(_G, "CreateVector2D")
  if type(mk) == "function" then return (call(mk, x, y)) end
  return { x = x, y = y }
end
local function on() local d = cfg() return d.enabled ~= false and d.flightMasters ~= false end
local function myFaction() return str((call(rawget(_G, "UnitFactionGroup"), "player"))) or "Neutral" end
local function cmap(name) return type(C_Map) == "table" and C_Map[name] or nil end

--- Map fractions -> world position: continentID, x, y; nil when the client can't place it.
function FP.ToWorld(mapID, x, y)
  if not (mapID and x and y) then return nil end
  local cont, wp = call(cmap("GetWorldPosFromMapPos"), mapID, vec(x, y))
  local wx, wy = xy(wp)
  cont = num(cont)
  if cont and wx and wy then return cont, wx, wy end
  return nil
end

--- World position -> fractions on mapID; nil when it falls outside that map.
function FP.FromWorld(cont, wx, wy, mapID)
  if not (cont and wx and wy and mapID) then return nil end
  local _, pos = call(cmap("GetMapPosFromWorldPos"), cont, vec(wx, wy), mapID)
  local x, y = xy(pos)
  if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
  return nil
end

--- This faction's remembered flight masters: name -> { c = continentID, x, y = world position, npc, stood, at }.
function FP.Store()
  local g = HH.db and HH.db.global
  if type(g) ~= "table" then return {} end
  g.flightPoints = g.flightPoints or {}
  local f = myFaction()
  g.flightPoints[f] = g.flightPoints[f] or {}
  return g.flightPoints[f]
end

local function round(v) return math.floor(v * 10 + 0.5) / 10 end

function FP.Remember(store, name, cont, wx, wy, npc)
  if not (name and cont and wx and wy) then return false end
  local e = store[name] or {}
  e.c, e.x, e.y = cont, round(wx), round(wy)
  if npc then e.npc = npc end
  e.at = date and date("%Y-%m-%d") or e.at
  store[name] = e
  return true
end

--- TAXIMAP_OPENED: remember the master you are talking to and every node the flight map lists. Returns how many.
function FP.Learn()
  if not on() then return 0 end
  local store, n, here = FP.Store(), 0, nil
  local T = rawget(_G, "C_TaxiMap")
  local taxiMap = num((call(rawget(_G, "GetTaxiMapID"))))
  local E = rawget(_G, "Enum")
  local CURRENT = (type(E) == "table" and type(E.FlightPathState) == "table" and num(E.FlightPathState.Current)) or 0
  if taxiMap and type(T) == "table" then
    local nodes = call(T.GetAllTaxiNodes, taxiMap)
    if type(nodes) == "table" then
      for _, node in ipairs(nodes) do
        if type(node) == "table" then
          local name = str(node.name)
          if name and num(node.state) == CURRENT then here = name end
          local x, y = xy(node.position)
          local cont, wx, wy = FP.ToWorld(taxiMap, x, y)
          local old = name and store[name]
          -- where you stood beats the flight map's dot: never overwrite a master you have talked to
          if not (old and old.stood) and FP.Remember(store, name, cont, wx, wy) then n = n + 1 end
        end
      end
    end
  end
  if not here then   -- the classic flight-map globals
    local count = num((call(rawget(_G, "NumTaxiNodes"))))
    for i = 1, count or 0 do
      if str((call(rawget(_G, "TaxiNodeGetType"), i))) == "CURRENT" then here = str((call(rawget(_G, "TaxiNodeName"), i))) break end
    end
  end
  local npc = str((call(rawget(_G, "UnitName"), "npc")))
  local mapID = num((call(cmap("GetBestMapForUnit"), "player")))
  local px, py = WM.PlayerPosition()
  local cont, wx, wy = FP.ToWorld(mapID, px, py)
  local key = here or npc
  if FP.Remember(store, key, cont, wx, wy, npc) then
    store[key].stood = true
    n = n + 1
  end
  FP.learned = { at = date and date("%H:%M:%S") or "", nodes = n, here = here or "?", npc = npc or "?", taxiMap = taxiMap or 0, map = mapID or 0 }
  local f = frame()
  if f and f.IsShown and f:IsShown() then FP.Draw() end
  return n
end

--- The client's own list for mapID (this faction + neutral), or nil + why not.
function FP.ApiNodes(mapID)
  local T = rawget(_G, "C_TaxiMap")
  if type(T) ~= "table" or type(T.GetTaxiNodesForMap) ~= "function" then return nil, "no C_TaxiMap.GetTaxiNodesForMap" end
  local ok, nodes = pcall(T.GetTaxiNodesForMap, mapID)
  if not ok then return nil, "GetTaxiNodesForMap error: " .. tostring(nodes):sub(1, 60) end
  if type(nodes) ~= "table" then return nil, "GetTaxiNodesForMap gave " .. type(nodes) end
  local E = rawget(_G, "Enum")
  local F = (type(E) == "table" and type(E.FlightPathFaction) == "table" and E.FlightPathFaction) or { Neutral = 0, Horde = 1, Alliance = 2 }
  local mine, out = myFaction(), {}
  for _, node in ipairs(nodes) do
    if type(node) == "table" then
      local x, y = xy(node.position)
      local f = num(node.faction)
      if isSecret(node.faction) then x = nil end   -- can't tell whose master it is: leave it off
      local theirs = (f ~= nil and f == num(F.Horde) and "Horde") or (f ~= nil and f == num(F.Alliance) and "Alliance") or nil
      if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 and (theirs == nil or theirs == mine) then
        out[#out + 1] = { name = str(node.name) or "Flight master", x = x, y = y, source = "api", undiscovered = bool(node.isUndiscovered) == true }
      end
    end
  end
  return out
end

local function nearest(list, x, y)
  for _, n in ipairs(list) do
    if math.abs(n.x - x) < NEAR and math.abs(n.y - y) < NEAR then return n end
  end
end

--- Every flight master to draw on mapID: the client's list first, then what you have learned (same name or same
--- spot = one pin; a learned master gives its NPC name to the client's pin).
function FP.Nodes(mapID)
  local list, byName = {}, {}
  local api, why = FP.ApiNodes(mapID)
  FP.apiWhy = api and ("api " .. #api) or why
  for _, n in ipairs(api or {}) do list[#list + 1] = n byName[n.name] = n end
  local mc = FP.ToWorld(mapID, 0.5, 0.5)   -- the map's continent: a learned point elsewhere is never placed here
  if mc then
    for name, e in pairs(FP.Store()) do
      if type(e) == "table" and num(e.c) == mc then
        local x, y = FP.FromWorld(e.c, num(e.x), num(e.y), mapID)
        if x then
          local same = byName[name] or nearest(list, x, y)
          if same then
            same.npc = same.npc or e.npc
          else
            list[#list + 1] = { name = name, npc = e.npc, x = x, y = y, source = "learned" }
          end
        end
      end
    end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

local function canvasOf(f)
  local c = type(f.GetCanvas) == "function" and (call(f.GetCanvas, f)) or nil
  if type(c) ~= "table" then
    local sc = rawget(f, "ScrollContainer")
    c = type(sc) == "table" and rawget(sc, "Child") or nil
  end
  if type(c) == "table" and type(c.GetWidth) == "function" then return c end
end

local function setIcon(tex, undiscovered)
  local A = rawget(_G, "C_Texture")
  if type(A) == "table" and type(A.GetAtlasInfo) == "function" then
    for _, a in ipairs(ATLASES) do
      if call(A.GetAtlasInfo, a) then
        call(tex.SetAtlas, tex, a)
        call(tex.SetDesaturated, tex, undiscovered)
        return a
      end
    end
  end
  call(tex.SetTexture, tex, FILE_ICON)
  call(tex.SetDesaturated, tex, undiscovered)
  return FILE_ICON
end

function FP.OnEnter(pin)
  local n, tip = pin and pin.node, rawget(_G, "GameTooltip")
  if not (n and type(tip) == "table") then return end
  call(tip.SetOwner, tip, pin, "ANCHOR_RIGHT")
  call(tip.SetText, tip, n.name, 1, 0.82, 0)
  if n.npc then call(tip.AddLine, tip, "Flight master: " .. n.npc, 0.96, 0.92, 0.86) end
  if n.undiscovered then call(tip.AddLine, tip, "Not discovered yet", 0.6, 0.6, 0.6) end
  call(tip.AddLine, tip, n.source == "learned" and "Remembered from a flight map you opened" or "From the game's flight list", 0.5, 0.5, 0.5)
  call(tip.Show, tip)
end

function FP.OnLeave()
  local tip = rawget(_G, "GameTooltip")
  if type(tip) == "table" then call(tip.Hide, tip) end
end

local function newPin(layer)
  local p = CreateFrame("Frame", nil, layer)
  p:SetSize(PIN, PIN)
  p.tex = p:CreateTexture(nil, "OVERLAY")
  p.tex:SetAllPoints(p)
  call(p.EnableMouse, p, true)
  call(p.SetMouseClickEnabled, p, false)   -- hover for the tooltip; clicks go through to the map (zoom / pan)
  p:SetScript("OnEnter", FP.OnEnter)
  p:SetScript("OnLeave", FP.OnLeave)
  return p
end

local function hideFrom(i)
  for k = i, #FP.pins do FP.pins[k]:Hide() FP.pins[k].node = nil end
end

--- Pins keep one size on screen whatever the zoom: the canvas is scaled, so the pin takes the inverse.
function FP.PinScale(f)
  local cs = num((call(f.GetCanvasScale, f)))
  if cs and cs > 0 then return 1 / cs end
  return 1
end

--- Draw the flight masters for the map that is open. Returns how many pins (tests, diag).
function FP.Draw()
  FP.drawn = 0
  local f = frame()
  if not f then FP.why = "no WorldMapFrame" return 0 end
  if not on() then
    if FP.layer then FP.layer:Hide() end
    FP.why = "off (Quests > World map > Flight masters)"
    return 0
  end
  local c = canvasOf(f)
  if not c then FP.why = "no map canvas" return 0 end
  if not FP.layer then
    FP.layer = CreateFrame("Frame", nil, c)
    FP.layer:SetAllPoints(c)
    FP.layer:SetFrameLevel((num((call(c.GetFrameLevel, c))) or 0) + 600)   -- over the map's own pins and tiles
  end
  FP.layer:Show()
  local mapID = num((call(f.GetMapID, f)))
  local w, h = num((call(c.GetWidth, c))), num((call(c.GetHeight, c)))
  if not mapID then FP.why = "the map has no id" hideFrom(1) return 0 end
  if not (w and h and w > 0 and h > 0) then FP.why = "the map canvas has no size yet" hideFrom(1) return 0 end
  local s = FP.PinScale(f)
  local nodes = FP.Nodes(mapID)
  for i, n in ipairs(nodes) do
    local p = FP.pins[i] or newPin(FP.layer)
    FP.pins[i] = p
    p.node = n
    p.icon = setIcon(p.tex, n.undiscovered)
    p:SetScale(s)
    p:ClearAllPoints()
    p:SetPoint("CENTER", FP.layer, "TOPLEFT", (n.x * w) / s, -(n.y * h) / s)
    p:Show()
  end
  hideFrom(#nodes + 1)
  FP.drawn, FP.mapID = #nodes, mapID
  FP.why = ("%d on map %d (%s)"):format(#nodes, mapID, tostring(FP.apiWhy))
  return #nodes
end

--- Redraw when the map changes zone or zoom (both are methods of Blizzard's map canvas; post-hooks only).
function FP.Hook(f)
  if FP.hooked or type(f) ~= "table" then return end
  FP.hooked = true
  for _, m in ipairs({ "OnMapChanged", "OnCanvasScaleChanged" }) do
    if type(f[m]) == "function" then pcall(hooksecurefunc, f, m, function() HH:SafeCall(FP, "Draw") end) end
  end
end

function FP.Start()
  if FP.events then return end
  local ev = CreateFrame("Frame")
  local ok = pcall(ev.RegisterEvent, ev, "TAXIMAP_OPENED")
  FP.eventOK = ok
  ev:SetScript("OnEvent", function() HH:SafeCall(FP, "Learn") end)
  FP.events = ev
end
function WM.FlightStart() FP.Start() end

function FP.Probe()
  local T = rawget(_G, "C_TaxiMap")
  local keys = {}
  if type(T) == "table" then for k in pairs(T) do keys[#keys + 1] = tostring(k) end table.sort(keys) end
  local f = frame()
  local mapID = (f and num((call(f.GetMapID, f)))) or num((call(cmap("GetBestMapForUnit"), "player")))
  local api, why
  if mapID then api, why = FP.ApiNodes(mapID) end
  local learned = 0
  for _ in pairs(FP.Store()) do learned = learned + 1 end
  local A = rawget(_G, "C_Texture")
  local atl = {}
  for _, a in ipairs(ATLASES) do
    atl[#atl + 1] = a .. "=" .. ((type(A) == "table" and type(A.GetAtlasInfo) == "function" and call(A.GetAtlasInfo, a)) and "y" or "n")
  end
  return {
    C_TaxiMap = #keys > 0 and table.concat(keys, ",") or "nil",
    mapID = tostring(mapID),
    api = api and (#api .. " nodes" .. (api[1] and (" e.g. " .. api[1].name) or "")) or tostring(why),
    learned = learned,
    drawn = FP.drawn or 0,
    why = FP.why,
    event = FP.eventOK and "TAXIMAP_OPENED" or "TAXIMAP_OPENED refused",
    last = FP.learned and ("%s %d nodes, here %s, npc %s, taxi map %d, map %d"):format(FP.learned.at, FP.learned.nodes, FP.learned.here, FP.learned.npc, FP.learned.taxiMap, FP.learned.map) or "no flight map opened this session",
    worldPos = cmap("GetWorldPosFromMapPos") and "fn" or "nil",
    mapPos = cmap("GetMapPosFromWorldPos") and "fn" or "nil",
    atlases = table.concat(atl, ","),
  }
end

-- ------------------------------------------------------------------------------------------------ apply
function WM.OnShow()
  local f, d = frame(), cfg()
  if not f or d.enabled == false then return end
  if d.scale and f.SetScale then call(f.SetScale, f, d.scale) end
  if WM.strip then
    if d.coords ~= false and not WM.LeatrixLoaded() then WM.strip:Show() else WM.strip:Hide() end
  end
  if WM.page then WM.InkQuestLog() end
  WM.Tick()
  FP.Draw()
end

function WM.Apply()
  local f, d = frame(), cfg()
  if not f or d.enabled == false then return false end
  pcall(SetCVar, "mapFade", d.fadeWhileMoving ~= false and "1" or "0")
  if not WM.LeatrixLoaded() then
    build(f)
    WM.Skin(f)
  end
  FP.Hook(f)
  if not WM.hooked and f.HookScript then
    WM.hooked = true
    call(f.HookScript, f, "OnShow", function() HH:SafeCall(WM, "OnShow") end)
  end
  if f.IsShown and f:IsShown() then WM.OnShow() end
  return true
end

function WM.Refresh()
  local f = frame()
  WM.Apply()
  if f and WM.strip and not (f.IsShown and f:IsShown()) then WM.strip:Hide() end
  if f and f.SetScale and cfg().scale then call(f.SetScale, f, cfg().scale) end

  if f and (not on() or (f.IsShown and f:IsShown())) then FP.Draw() end
end

function WM.Probe()
  local f = frame()
  local out = { frame = f and true or false, leatrix = WM.LeatrixLoaded(), skinned = WM.skinned or false }
  if f then
    out.border = rawget(f, "BorderFrame") ~= nil
    out.scrollContainer = rawget(f, "ScrollContainer") ~= nil
    out.cursorAPI = type(rawget(f, "ScrollContainer")) == "table" and rawget(f.ScrollContainer, "GetNormalizedCursorPosition") ~= nil
  end
  out.playerPos = WM.Format(WM.PlayerPosition())
  out.flightPins = FP.why
  return out
end
