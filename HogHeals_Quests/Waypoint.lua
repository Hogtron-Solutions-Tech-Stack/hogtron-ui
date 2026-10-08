-- Waypoint: the super-tracked quest marked IN THE WORLD - a HogTron UI marker over the objective with the quest's
-- name, yards, how long at your pace, and "4/10" / "ready to turn in" under it; an arrow on the screen edge when the
-- objective is off-screen. Sean 2026-10-08, from the Waypoint UI clip: "neatly displays your active tracked quest or
-- custom map pin in real time ... how long it will take you to reach your objective".
--
-- How (the same way Waypoint UI does it): the client owns the 3D -> screen projection. Blizzard's navigation frame
-- (C_Navigation.GetFrame(), the SuperTrackedFrame) is moved by the client every frame to sit over the tracked
-- objective; an addon cannot compute that from Lua. So we anchor our own frame to its CENTER, draw our look on top
-- and turn Blizzard's icon / text transparent (never Hide() - a hidden frame may stop being positioned). Distance from
-- C_Navigation.GetDistance() (3D yards); a client without it falls back to the GO row's map yards (2D, same map only).
-- Which rung answered is in Waypoint.path for /hh wpdiag:
--   nav       "C_Navigation.GetFrame" | "SuperTrackedFrame" | "none"   (none = no world-space marker on this client)
--   distance  "C_Navigation" | "map" | "none"
-- Every API is looked up by name; a client with none of them shows nothing and logs nothing.
HogHealsQuests = HogHealsQuests or {}
local HHQ = HogHealsQuests
local HH = HogHeals

local WP = { seen = {}, path = { nav = "none", distance = "none" }, RUN_SPEED = 7, THROTTLE = 0.25, elapsed = 0 }
HHQ.Waypoint = WP

local CYAN, CREAM, GREY, GREEN, INK, LINE = { 0.13, 0.83, 0.88 }, { 0.96, 0.92, 0.86 }, { 0.70, 0.70, 0.75 },
  { 0.25, 0.80, 0.35 }, { 0.07, 0.07, 0.09 }, { 0.20, 0.20, 0.25 }
local ARROW = "Interface\\AddOns\\HogHeals\\Media\\quest_arrow"
-- Blizzard's own art on the navigation frame, made transparent while ours is on (names differ per client build)
local BLIZZ_PARTS = { "Icon", "Arrow", "DistanceText", "Time", "NavigationLabel", "Description" }

local function cfg() return HH.db.profile.quests.waypoint or {} end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function fn(tbl, name) if type(tbl) == "table" and type(tbl[name]) == "function" then return tbl[name] end end
local function g(name) local f = rawget(_G, name) if type(f) == "function" then return f end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
end
local function count(k) WP.seen[k] = (WP.seen[k] or 0) + 1 end

-- ------------------------------------------------------------------------------------------------ pure
--- Seconds to cover `yards` at `speed` yards/second; nil when either is missing or zero.
function WP.ETA(yards, speed)
  if type(yards) ~= "number" or type(speed) ~= "number" or speed <= 0 or yards < 0 then return nil end
  return yards / speed
end

--- "191 yd" / "1.2k yd"
function WP.FormatDistance(yards)
  if type(yards) ~= "number" then return nil end
  if yards >= 1000 then return ("%.1fk yd"):format(yards / 1000) end
  return ("%d yd"):format(math.floor(yards + 0.5))
end

--- "27s" / "1m 05s" / "1h 2m"
function WP.FormatETA(secs)
  if type(secs) ~= "number" or secs < 0 then return nil end
  secs = math.floor(secs + 0.5)
  if secs < 60 then return ("%ds"):format(secs) end
  if secs < 3600 then return ("%dm %02ds"):format(math.floor(secs / 60), secs % 60) end
  return ("%dh %dm"):format(math.floor(secs / 3600), math.floor((secs % 3600) / 60))
end

--- Angle (radians, 0 = straight up, clockwise positive) from (cx, cy) toward (x, y). Screen y grows upward in WoW.
function WP.Angle(cx, cy, x, y)
  return math.atan2(x - cx, y - cy)
end

--- Title / detail / colour for a quest at `yards` moving at `speed`. Pure; o = the options table.
function WP.Content(q, yards, speed, o)
  o = o or {}
  local out = { title = q and q.title and tostring(q.title) or "", color = CREAM }
  local parts = {}
  local d = WP.FormatDistance(yards)
  if d then parts[#parts + 1] = d end
  if o.eta ~= false then
    local eta = WP.FormatETA(WP.ETA(yards, speed))
    if eta then parts[#parts + 1] = eta end
  end
  if q and o.progress ~= false then
    if q.complete then
      parts[#parts + 1] = "ready to turn in"
      out.color = GREEN
    else
      local done, all = 0, 0
      for _, ob in ipairs(q.objectives or {}) do all = all + 1 if ob.done then done = done + 1 end end
      if all > 0 then parts[#parts + 1] = ("%d/%d"):format(done, all) end
    end
  end
  out.detail = table.concat(parts, "  ·  ")
  return out
end

--- Alpha for the marker: dimmed inside `near` yards (you are there - get it out of your face).
function WP.Alpha(yards, o)
  o = o or {}
  local near = o.near or 10
  if type(yards) == "number" and near > 0 and yards <= near then return o.nearAlpha or 0.5 end
  return 1
end

-- ------------------------------------------------------------------------------------------------ client
--- Blizzard's navigation frame, or nil. Records which name answered.
function WP.NavFrame()
  local nav = rawget(_G, "C_Navigation")
  local f = call(fn(nav, "GetFrame"))
  if type(f) == "table" then WP.path.nav = "C_Navigation.GetFrame" return f end
  f = rawget(_G, "SuperTrackedFrame")
  if type(f) == "table" then WP.path.nav = "SuperTrackedFrame" return f end
  WP.path.nav = "none"
  return nil
end

--- The super-tracked quest's id, or nil.
function WP.TrackedID()
  local st = rawget(_G, "C_SuperTrack")
  local any = fn(st, "IsSuperTrackingAnything")
  if any and not call(any) then return nil end
  return num(call(fn(st, "GetSuperTrackedQuestID")))
end

--- The quest record for an id from the Quests data (last read, else a fresh read).
function WP.Quest(id)
  if not id then return nil end
  local list = HHQ.Data and (HHQ.Data.last or (HHQ.Data.List and HHQ.Data.List())) or {}
  for _, q in ipairs(list) do if q.id == id then return q end end
  return nil
end

--- Yards to the tracked objective: the client's 3D distance, else the GO row's map maths.
function WP.Distance(id)
  local nav = rawget(_G, "C_Navigation")
  local d = num(call(fn(nav, "GetDistance")))
  if d and d > 0 then WP.path.distance = "C_Navigation" return d end
  if id and HHQ.Go and HHQ.Go.Yards then
    local ok, yards = pcall(HHQ.Go.Yards)
    local y = ok and type(yards) == "table" and yards[id] or nil
    if y then WP.path.distance = "map" return y end
  end
  WP.path.distance = "none"
  return nil
end

--- Yards a second: the player's speed while moving, else the last moving speed, else a run.
function WP.Speed()
  local s = num(call(g("GetUnitSpeed"), "player"))
  if s and s > 0 then WP.lastSpeed = s return s end
  return WP.lastSpeed or WP.RUN_SPEED
end

-- ------------------------------------------------------------------------------------------------ frame
local function fs(parent, color, size, justify)
  local t = parent:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  t:SetTextColor(color[1], color[2], color[3])
  t:SetJustifyH(justify or "CENTER")
  if t.SetWordWrap then t:SetWordWrap(false) end
  return t
end

function WP.Create()
  if WP.frame then return WP.frame end
  local f = CreateFrame("Frame", "HogHealsWaypoint", UIParent)
  f:SetSize(240, 48)
  f:SetFrameStrata("MEDIUM")
  f:EnableMouse(false)
  -- the marker: a flat cyan square with a one pixel ink edge (a diamond when the client can rotate textures)
  f.marker = f:CreateTexture(nil, "ARTWORK", nil, 1)
  f.marker:SetSize(14, 14)
  f.marker:SetPoint("CENTER", f, "CENTER", 0, 0)
  f.marker:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 1)
  f.edge = f:CreateTexture(nil, "ARTWORK", nil, 0)
  f.edge:SetSize(16, 16)
  f.edge:SetPoint("CENTER", f, "CENTER", 0, 0)
  f.edge:SetColorTexture(INK[1], INK[2], INK[3], 1)
  if f.marker.SetRotation then pcall(f.marker.SetRotation, f.marker, math.pi / 4) pcall(f.edge.SetRotation, f.edge, math.pi / 4) end
  -- the arrow for off-screen objectives, drawn in place of the marker and turned toward it
  f.arrow = f:CreateTexture(nil, "ARTWORK", nil, 2)
  f.arrow:SetSize(24, 24)
  f.arrow:SetPoint("CENTER", f, "CENTER", 0, 0)
  if not f.arrow:SetTexture(ARROW) then f.arrow:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 1) end
  f.arrow:Hide()
  -- texts: name above, yards / eta / progress below
  f.title = fs(f, CREAM, 12)
  f.title:SetPoint("BOTTOM", f.marker, "TOP", 0, 6)
  f.detail = fs(f, GREY, 11)
  f.detail:SetPoint("TOP", f.marker, "BOTTOM", 0, -6)
  f:Hide()
  WP.frame = f
  return f
end

--- Blizzard's art on the navigation frame: transparent while ours is on, back when it is off.
function WP.BlizzardArt(nav, shown)
  if type(nav) ~= "table" then return end
  for _, name in ipairs(BLIZZ_PARTS) do
    local part = rawget(nav, name)
    if type(part) == "table" and type(part.SetAlpha) == "function" then pcall(part.SetAlpha, part, shown and 1 or 0) end
  end
  WP.blizzardHidden = not shown
end

--- Anchor our frame to the navigation frame's centre (once per nav frame).
function WP.Attach(nav)
  local f = WP.Create()
  if WP.attachedTo == nav then return true end
  f:ClearAllPoints()
  f:SetPoint("CENTER", nav, "CENTER", 0, 0)
  WP.attachedTo = nav
  count("attach")
  return true
end

local function applyLook(f)
  local o = cfg()
  local d = HH.db.profile.quests.tracker or {}
  local font = HH.Look and HH.Look.Font and HH.Look.Font(d.font) or nil
  local size = o.fontSize or 12
  if font then pcall(f.title.SetFont, f.title, font, size, "OUTLINE") pcall(f.detail.SetFont, f.detail, font, size - 1, "OUTLINE") end
  local s = o.scale or 1
  if f.SetScale then pcall(f.SetScale, f, s) end
end

--- Repaint from the client: shown over the objective with texts, an arrow on the edge when clamped, hidden when
-- nothing is tracked or there is no navigation frame.
function WP.Update()
  local f = WP.Create()
  local o = cfg()
  count("updates")
  local id = o.enabled ~= false and WP.TrackedID() or nil
  local nav = id and WP.NavFrame() or nil
  if not id or not nav then
    f:Hide()
    if WP.blizzardHidden and WP.attachedTo then WP.BlizzardArt(WP.attachedTo, true) end
    WP.current = nil
    return false
  end
  WP.Attach(nav)
  if o.hideBlizzard ~= false then WP.BlizzardArt(nav, false) elseif WP.blizzardHidden then WP.BlizzardArt(nav, true) end
  local q = WP.Quest(id)
  local yards = WP.Distance(id)
  local c = WP.Content(q or { title = "" }, yards, WP.Speed(), o)
  f.title:SetText(o.title ~= false and c.title or "")
  f.title:SetTextColor(c.color[1], c.color[2], c.color[3])
  f.detail:SetText(c.detail)
  local navApi = rawget(_G, "C_Navigation")
  local clamped = o.arrow ~= false and call(fn(navApi, "WasClampedToScreen")) and true or false
  local valid = fn(navApi, "HasValidScreenPosition")
  if valid and not call(valid) then clamped = o.arrow ~= false end
  if clamped then
    local sw, sh = (g("GetScreenWidth") and GetScreenWidth() or 1920), (g("GetScreenHeight") and GetScreenHeight() or 1080)
    local nx, ny = nav:GetCenter()
    local angle = (type(nx) == "number" and type(ny) == "number") and WP.Angle(sw / 2, sh / 2, nx, ny) or 0
    if f.arrow.SetRotation then pcall(f.arrow.SetRotation, f.arrow, -angle) end
    f.arrow:Show()
    f.marker:Hide() f.edge:Hide()
    WP.angle = angle
  else
    f.arrow:Hide()
    f.marker:Show() f.edge:Show()
    WP.angle = nil
  end
  f:SetAlpha(WP.Alpha(yards, o))
  f:Show()
  WP.current = { id = id, title = c.title, yards = yards, clamped = clamped }
  return true
end

--- Distance and eta age while you walk: repaint every THROTTLE seconds while shown.
function WP.OnUpdate(_, elapsed)
  WP.elapsed = WP.elapsed + (elapsed or 0)
  if WP.elapsed < WP.THROTTLE then return end
  WP.elapsed = 0
  WP.Update()
end

-- ------------------------------------------------------------------------------------------------ wiring
local EVENTS = { "SUPER_TRACKING_CHANGED", "NAVIGATION_FRAME_CREATED", "NAVIGATION_FRAME_DESTROYED", "QUEST_LOG_UPDATE",
  "QUEST_POI_UPDATE", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }

function WP.Start()
  local f = WP.Create()
  applyLook(f)
  if not WP.events then
    local ev = CreateFrame("Frame")
    WP.unknown = {}
    for _, e in ipairs(EVENTS) do
      local ok = pcall(ev.RegisterEvent, ev, e)
      if not ok then WP.unknown[#WP.unknown + 1] = e end
    end
    ev:SetScript("OnEvent", function(_, e)
      if e == "NAVIGATION_FRAME_DESTROYED" then WP.attachedTo = nil end
      WP.Update()
    end)
    WP.events = ev
    f:SetScript("OnUpdate", function(self, elapsed) WP.OnUpdate(self, elapsed) end)
  end
  WP.Update()
end

function WP.Stop()
  if WP.frame then WP.frame:Hide() end
  if WP.blizzardHidden and WP.attachedTo then WP.BlizzardArt(WP.attachedTo, true) end
end

function WP.Refresh()
  if cfg().enabled == false then WP.Stop() return end
  if WP.frame then applyLook(WP.frame) end
  WP.Update()
end

--- Plain strings for /hh diag.
function WP.Probe()
  local nav = rawget(_G, "C_Navigation")
  return {
    nav = WP.path.nav, distance = WP.path.distance,
    hasGetFrame = fn(nav, "GetFrame") and true or false, hasGetDistance = fn(nav, "GetDistance") and true or false,
    hasSuperTrack = type(rawget(_G, "C_SuperTrack")) == "table", tracked = WP.TrackedID(),
    unknownEvents = table.concat(WP.unknown or {}, ","),
  }
end

function WP.Lines()
  local p = WP.Probe()
  local c = WP.current
  local out = {}
  out[#out + 1] = ("waypoint: nav frame = %s, distance = %s, super-track api %s"):format(p.nav, p.distance, p.hasSuperTrack and "yes" or "no")
  if p.nav == "none" then out[#out + 1] = "  this client gives addons no navigation frame: no marker in the world is possible (the GO row and minimap pins still work)." end
  if c then out[#out + 1] = ("  tracking %s (%s) %s%s"):format(tostring(c.title), tostring(c.id), c.yards and (WP.FormatDistance(c.yards) or "") or "distance unknown", c.clamped and ", off-screen arrow" or "")
  else out[#out + 1] = "  nothing tracked (click a quest in the tracker, or let the GO row pick)." end
  if p.unknownEvents ~= "" then out[#out + 1] = "  events this client lacks: " .. p.unknownEvents end
  return out
end

HH:RegisterSlash("wpdiag", function()
  for _, l in ipairs(WP.Lines()) do HH:Print(l) end
end, "waypoint marker: which navigation / distance API answered, what is tracked")
