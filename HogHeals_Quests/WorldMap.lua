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
  strip.player = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  strip.player:SetPoint("LEFT", strip, "LEFT", 8, 0)
  strip.player:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
  strip.cursor = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
  if fs and fs.SetFont then call(fs.SetFont, fs, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE") end
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
    for _, r in ipairs({ call(fr.GetRegions, fr) }) do
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

-- ------------------------------------------------------------------------------------------------ apply
function WM.OnShow()
  local f, d = frame(), cfg()
  if not f or d.enabled == false then return end
  if d.scale and f.SetScale then call(f.SetScale, f, d.scale) end
  if WM.strip then
    if d.coords ~= false and not WM.LeatrixLoaded() then WM.strip:Show() else WM.strip:Hide() end
  end
  WM.Tick()
end

function WM.Apply()
  local f, d = frame(), cfg()
  if not f or d.enabled == false then return false end
  pcall(SetCVar, "mapFade", d.fadeWhileMoving ~= false and "1" or "0")
  if not WM.LeatrixLoaded() then
    build(f)
    WM.Skin(f)
  end
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
  return out
end
