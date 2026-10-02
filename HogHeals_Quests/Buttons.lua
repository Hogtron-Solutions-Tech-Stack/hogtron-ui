-- Addon buttons: every third-party minimap icon (LibDBIcon ones and the old hand-named kind) gathered into one ink
-- drawer beside the minimap, opened from a single small HogUI "H" button (Sean 2026-10-01: left of the map, opening
-- toward the middle of the screen, a colour-themed H for a logo). Blizzard's own buttons (tracking, mail,
-- clock, LFG eye) are never touched: MapSkin docks the ones that sat on the map, and they keep handling their own
-- secrets (LANDMINE 2026-09-26: adopting a Blizzard frame taints it).
--
-- A collected button is re-parented into the drawer and laid out on a grid; LibDBIcon's round ring + disc art is
-- hidden (the ink cell is its frame now). What we remember about a button lives in side tables keyed by the button,
-- never as fields on it. Owners that move their button back (LibDBIcon re-anchors on login and on Refresh) are
-- caught by a SetPoint hook that puts it on the grid again. Turning the option off hands every button back.
HogHealsQuests = HogHealsQuests or {}
local HHQ = HogHealsQuests
local HH = HogHeals

local Drawer = { list = {}, skipped = {} }
HHQ.Buttons = Drawer

local INK = { 0.07, 0.07, 0.09 }
local LINE = { 0.20, 0.20, 0.25 }
local CYAN = { 0.13, 0.83, 0.88 }
local CREAM = { 0.96, 0.92, 0.86 }
local GREY = { 0.55, 0.55, 0.60 }
local PAD = 4          -- gap between cells and to the drawer edge
local LAUNCHER = 18    -- the H button, px (the minimap header is 20)
local AWAY = 1.0       -- seconds the cursor must be off the drawer before it closes itself

local function cfg() return HH.db.profile.quests.buttons end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d, e = pcall(f, ...)
  if ok then return a, b, c, d, e end
end

-- Side tables (weak keys): what we know about a collected button. Never written onto the button itself.
local saved = setmetatable({}, { __mode = "k" })     -- button -> original parent / points / scale / scripts / art
local placing = setmetatable({}, { __mode = "k" })   -- button -> true while WE move it (the hooks stand down)
local hooked = setmetatable({}, { __mode = "k" })
Drawer.saved = saved

-- Blizzard's minimap buttons across client generations. Never collected: not addon buttons, several handle secret
-- values, and MapSkin already places the ones that matter.
Drawer.BLIZZARD = {}
for _, n in ipairs({ "MinimapBackdrop", "MinimapZoomIn", "MinimapZoomOut", "MiniMapTracking", "MiniMapTrackingButton",
  "MiniMapTrackingFrame", "MiniMapMailFrame", "MinimapMailFrame", "GameTimeFrame", "TimeManagerClockButton",
  "QueueStatusButton", "QueueStatusMinimapButton", "MiniMapLFGFrame", "LFGMinimapFrame", "MiniMapBattlefieldFrame",
  "MiniMapWorldMapButton", "MinimapToggleButton", "MinimapZoneTextButton", "MiniMapInstanceDifficulty",
  "GuildInstanceDifficulty", "MiniMapChallengeMode", "MiniMapVoiceChatFrame", "MinimapCompassTexture",
  "ExpansionLandingPageMinimapButton", "GarrisonLandingPageMinimapButton", "AddonCompartmentFrame",
  "MiniMapRecordingButton", "MinimapPing", "MiniMapCraftingOrderIcon", "MinimapCluster", "MinimapBorder" }) do
  Drawer.BLIZZARD[n] = true
end

-- The names addon authors give minimap buttons (MinimapButtonButton's list). LibDBIcon names are matched first.
Drawer.PATTERNS = { "MinimapButton", "MinimapFrame", "MinimapIcon", "[-_]Minimap[-_]", "Minimap$" }

-- The two textures LibDBIcon draws around every icon (round ring, dark disc): fileIDs or paths depending on client.
local RING = { ["136430"] = true, ["136467"] = true }
local function isRingArt(tex)
  if tex == nil then return false end
  local s = tostring(tex):lower()
  return RING[s] == true or s:find("trackingborder", 1, true) ~= nil or s:find("minimap%-background") ~= nil
end

--- Is this frame an addon's minimap button? true, or false + why (the diag log lists the whys).
function Drawer.Wanted(f)
  if type(f) ~= "table" then return false, "not a frame" end
  local name = f.GetName and call(f.GetName, f)
  if type(name) ~= "string" or name == "" then return false, "unnamed" end
  if saved[f] then return false, "collected" end
  if Drawer.BLIZZARD[name] then return false, "blizzard" end
  if name:find("^HogHeals") then return false, "ours" end
  if type(issecurevariable) == "function" and call(issecurevariable, name) then return false, "secure" end
  if f.IsProtected and call(f.IsProtected, f) then return false, "protected" end
  local kind = f.GetObjectType and call(f.GetObjectType, f)
  if kind ~= "Button" and kind ~= "Frame" and kind ~= "CheckButton" then return false, "type " .. tostring(kind) end
  if name:find("^LibDBIcon10_") then return true end
  if name:match("%d$") then return false, "numbered" end
  for _, p in ipairs(Drawer.PATTERNS) do if name:find(p) then return true end end
  return false, "name"
end

-- ------------------------------------------------------------------------------------------------ frames
local function solid(parent, layer, c, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  t.hhOurs = true
  return t
end

local function outline(f)
  local edges = {}
  local spec = { { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
    { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }
  for i, sp in ipairs(spec) do
    local e = solid(f, "BORDER", LINE)
    e:SetPoint(sp[1], f, sp[1], 0, 0)
    e:SetPoint(sp[2], f, sp[2], 0, 0)
    if sp[3] then e:SetWidth(sp[3]) end
    if sp[4] then e:SetHeight(sp[4]) end
    edges[i] = e
  end
  return edges
end

local function paintEdges(edges, c) for _, e in ipairs(edges) do e:SetColorTexture(c[1], c[2], c[3], 1) end end

local function build()
  if Drawer.launcher then return Drawer.launcher end
  local b = CreateFrame("Button", "HogHealsMinimapButtons", Minimap)
  b:SetSize(LAUNCHER, LAUNCHER)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(((Minimap.GetFrameLevel and Minimap:GetFrameLevel()) or 1) + 6)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  b.bg = solid(b, "BACKGROUND", INK, 0.92)
  b.bg:SetAllPoints(b)
  b.edges = outline(b)
  -- the logo: an H drawn from three bars (cream uprights, cyan crossbar - the HOG / UI two-tone rule). No font
  -- involved, so it draws the same on every client.
  b.logo = {}
  for _, x in ipairs({ -3.5, 3.5 }) do
    local bar = solid(b, "ARTWORK", CREAM)
    bar:SetSize(3, 10)
    bar:SetPoint("CENTER", b, "CENTER", x, 0)
    b.logo[#b.logo + 1] = bar
  end
  b.cross = solid(b, "ARTWORK", CYAN)
  b.cross:SetSize(8, 2)
  b.cross:SetPoint("CENTER", b, "CENTER", 0, 0)
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      if HH.OpenOptions then HH:OpenOptions() end
      return
    end
    Drawer.Toggle()
  end)
  b:SetScript("OnEnter", function(self)
    paintEdges(self.edges, CYAN)
    if cfg().hover then Drawer.Toggle(true) end
    if GameTooltip and GameTooltip.SetOwner then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine("Addon buttons", CREAM[1], CREAM[2], CREAM[3])
      local n, shown = Drawer.Count()
      GameTooltip:AddLine(("%d collected, %d shown"):format(n, shown), GREY[1], GREY[2], GREY[3])
      local listed = 0
      for _, c in ipairs(Drawer.list) do
        if call(c.IsShown, c) then
          listed = listed + 1
          if listed > 12 then GameTooltip:AddLine("  ...", GREY[1], GREY[2], GREY[3]) break end
          GameTooltip:AddLine("  " .. Drawer.Label(c), CREAM[1], CREAM[2], CREAM[3])
        end
      end
      GameTooltip:AddLine("Left: open / close.  Right: HogUI options.", GREY[1], GREY[2], GREY[3])
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self)
    paintEdges(self.edges, LINE)
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
  end)
  local d = CreateFrame("Frame", "HogHealsMinimapDrawer", b)
  d:SetFrameStrata("MEDIUM")
  d:SetFrameLevel(b:GetFrameLevel() + 1)
  d.bg = solid(d, "BACKGROUND", INK, 0.92)
  d.bg:SetAllPoints(d)
  d.edges = outline(d)
  d.empty = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  d.empty:SetPoint("CENTER", d, "CENTER", 0, 0)
  d.empty:SetText("No addon buttons found")
  d.empty:SetTextColor(GREY[1], GREY[2], GREY[3])
  d:Hide()
  Drawer.launcher, Drawer.frame = b, d
  return b
end

--- Where the launcher sits, against our ink frame when the skin is on, against the bare Minimap otherwise:
--   side = "left"  (default): beside the map's top-left corner; the drawer opens leftward, toward the middle of the screen
--   side = "right": under the map's bottom-right corner; the drawer opens downward
-- Re-run after the skin or the side is changed.
function Drawer.Side() return cfg().side == "right" and "right" or "left" end

function Drawer.Anchor()
  local b, f = Drawer.launcher, Drawer.frame
  if not b then return end
  local skin = HHQ.MapSkin and HHQ.MapSkin.frame
  local to = (skin and HH.db.profile.quests.map.enabled ~= false) and skin or Minimap
  local side = Drawer.Side()
  b:ClearAllPoints()
  f:ClearAllPoints()
  if side == "left" then
    b:SetPoint("TOPRIGHT", to, "TOPLEFT", -3, 0)
    f:SetPoint("TOPRIGHT", b, "TOPLEFT", -2, 0)
  else
    b:SetPoint("TOPRIGHT", to, "BOTTOMRIGHT", 0, -3)
    f:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, -2)
  end
  Drawer.side = side
  Drawer.anchoredTo = (to == skin) and "skin" or "minimap"
end

-- ------------------------------------------------------------------------------------------------ collecting
--- Take one button into the drawer. Returns true, or false + why.
function Drawer.Collect(b)
  local ok, why = Drawer.Wanted(b)
  if not ok then return false, why end
  if not Drawer.frame then return false, "no drawer" end
  local s = { name = b:GetName(), parent = call(b.GetParent, b), points = {}, scale = call(b.GetScale, b) or 1,
    strata = call(b.GetFrameStrata, b), level = call(b.GetFrameLevel, b), art = {},
    drag = { call(b.GetScript, b, "OnDragStart"), call(b.GetScript, b, "OnDragStop") } }
  for i = 1, (call(b.GetNumPoints, b) or 0) do s.points[i] = { call(b.GetPoint, b, i) } end
  saved[b] = s
  -- the round ring + disc off: the ink cell is the frame now
  if b.GetRegions then
    for _, r in ipairs({ b:GetRegions() }) do
      if type(r) == "table" and r.GetObjectType and r:GetObjectType() == "Texture" and isRingArt(call(r.GetTexture, r)) then
        s.art[#s.art + 1] = r
        r:Hide()
      end
    end
  end
  -- dragging a button around the minimap means nothing inside a grid (LibDBIcon drags re-anchor every frame)
  if b.SetScript then call(b.SetScript, b, "OnDragStart", nil) call(b.SetScript, b, "OnDragStop", nil) end
  placing[b] = true
  call(b.SetParent, b, Drawer.frame)
  call(b.SetFrameStrata, b, "MEDIUM")
  call(b.SetFrameLevel, b, Drawer.frame:GetFrameLevel() + 2)
  placing[b] = nil
  if not hooked[b] and type(hooksecurefunc) == "function" then
    hooked[b] = true
    local function back(self)
      if placing[self] or not saved[self] or Drawer.laying then return end
      Drawer.Layout()
    end
    if b.SetPoint then pcall(hooksecurefunc, b, "SetPoint", back) end
    if b.SetParent then pcall(hooksecurefunc, b, "SetParent", back) end
    if b.Show then pcall(hooksecurefunc, b, "Show", back) end
    if b.Hide then pcall(hooksecurefunc, b, "Hide", back) end
  end
  Drawer.list[#Drawer.list + 1] = b
  table.sort(Drawer.list, function(x, y) return (saved[x] and saved[x].name or "") < (saved[y] and saved[y].name or "") end)
  return true
end

--- Hand a button back exactly as it was (parent, points, scale, drag scripts, ring art).
function Drawer.Release(b)
  local s = saved[b]
  if not s then return end
  placing[b] = true
  call(b.SetScale, b, s.scale or 1)
  call(b.ClearAllPoints, b)
  call(b.SetParent, b, s.parent or Minimap)
  if s.strata then call(b.SetFrameStrata, b, s.strata) end
  if s.level then call(b.SetFrameLevel, b, s.level) end
  for _, p in ipairs(s.points) do if p[1] then call(b.SetPoint, b, p[1], p[2], p[3], p[4], p[5]) end end
  for _, r in ipairs(s.art) do call(r.Show, r) end
  if b.SetScript then call(b.SetScript, b, "OnDragStart", s.drag[1]) call(b.SetScript, b, "OnDragStop", s.drag[2]) end
  placing[b] = nil
  saved[b] = nil
  for i, x in ipairs(Drawer.list) do if x == b then table.remove(Drawer.list, i) break end end
end

--- Find buttons: LibDBIcon's own list first, then every child of the Minimap (and MinimapBackdrop, where older
-- addons put theirs). Returns how many were new. Drawer.skipped lists what was seen and left alone, with the why.
function Drawer.Scan()
  if not Drawer.frame then return 0 end
  local added = 0
  Drawer.skipped = {}
  local function try(b)
    if type(b) ~= "table" or saved[b] then return end
    local ok, why = Drawer.Collect(b)
    if ok then
      added = added + 1
    elseif why ~= "unnamed" and why ~= "ours" and not why:find("^type") then
      local n = b.GetName and call(b.GetName, b)
      if n and #Drawer.skipped < 40 then Drawer.skipped[#Drawer.skipped + 1] = tostring(n) .. ":" .. why end
    end
  end
  local lib = LibStub and LibStub("LibDBIcon-1.0", true)
  if lib then
    local names = type(lib.GetButtonList) == "function" and call(lib.GetButtonList, lib) or nil
    if type(names) == "table" then
      for _, n in ipairs(names) do try(type(lib.GetMinimapButton) == "function" and call(lib.GetMinimapButton, lib, n) or nil) end
    elseif type(lib.objects) == "table" then
      for _, b in pairs(lib.objects) do try(b) end
    end
  end
  for _, owner in ipairs({ Minimap, rawget(_G, "MinimapBackdrop") }) do
    if type(owner) == "table" and owner.GetChildren then
      for _, child in ipairs({ owner:GetChildren() }) do try(child) end
    end
  end
  if added > 0 then Drawer.Layout() end
  return added
end

--- Grid: shown buttons only, `columns` across, every one scaled to `size` px. Cells fill from the edge nearest the
-- launcher (top-right when the drawer opens leftward, top-left when it opens downward). Returns how many are placed.
function Drawer.Layout()
  local f = Drawer.frame
  if not f or Drawer.laying then return 0 end
  Drawer.laying = true
  local d = cfg()
  local cols = math.max(1, math.floor(d.columns or 4))
  local size = d.size or 28
  local corner = Drawer.Side() == "left" and "TOPRIGHT" or "TOPLEFT"
  local dir = corner == "TOPRIGHT" and -1 or 1
  local shown = {}
  for _, b in ipairs(Drawer.list) do if call(b.IsShown, b) then shown[#shown + 1] = b end end
  for i, b in ipairs(shown) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local w = call(b.GetWidth, b)
    if type(w) ~= "number" or w <= 0 then w = 31 end
    local scale = size / w
    placing[b] = true
    if call(b.GetParent, b) ~= f then call(b.SetParent, b, f) end
    call(b.SetScale, b, scale)
    call(b.ClearAllPoints, b)
    call(b.SetPoint, b, corner, f, corner, dir * (PAD + col * (size + PAD)) / scale, -(PAD + row * (size + PAD)) / scale)
    placing[b] = nil
  end
  local n = #shown
  local c = math.min(math.max(n, 1), cols)
  local r = math.max(1, math.ceil(n / cols))
  f:SetSize(PAD + c * (size + PAD), PAD + r * (size + PAD))
  if n == 0 then
    f.empty:Show()
    f:SetWidth(150)
  else
    f.empty:Hide()
  end
  Drawer.shown = n
  Drawer.laying = nil
  return n
end

-- ------------------------------------------------------------------------------------------------ open / close
function Drawer.Toggle(show)
  local f = Drawer.frame
  if not f then return false end
  if show == nil then show = not f:IsShown() end
  if show then
    Drawer.Scan()
    Drawer.Layout()
    f:Show()
    Drawer.Watch()
  else
    f:Hide()
    Drawer.Unwatch()
  end
  return show
end

-- Close on mouse-out: a light ticker while open; the drawer closes once the cursor has been off it and the launcher
-- for AWAY seconds (moving between icons never snaps it shut).
function Drawer.Watch()
  Drawer.Unwatch()
  if cfg().autoClose == false or not (C_Timer and C_Timer.NewTicker) then return end
  Drawer.away = 0
  Drawer.ticker = C_Timer.NewTicker(0.25, function()
    local f, b = Drawer.frame, Drawer.launcher
    local over = (f and call(f.IsMouseOver, f)) or (b and call(b.IsMouseOver, b))
    if over then Drawer.away = 0 return end
    Drawer.away = (Drawer.away or 0) + 0.25
    if Drawer.away >= AWAY then Drawer.Toggle(false) end
  end)
end

function Drawer.Unwatch()
  if Drawer.ticker then Drawer.ticker:Cancel() Drawer.ticker = nil end
end

-- ------------------------------------------------------------------------------------------------ lifecycle
-- Late buttons: LibDBIcon tells us the moment one is made; hand-made ones are swept for a while after login
-- (addons create them on their own events, well after ours).
local SWEEPS = { 1, 3, 8, 20, 45 }

function Drawer.Listen()
  if Drawer.listening then return end
  local lib = LibStub and LibStub("LibDBIcon-1.0", true)
  if lib and type(lib.RegisterCallback) == "function" then
    local ok = pcall(lib.RegisterCallback, Drawer, "LibDBIcon_IconCreated", function(_, button)
      if cfg().enabled == false or not Drawer.frame then return end
      if Drawer.Collect(button) then Drawer.Layout() end
    end)
    Drawer.listening = ok or nil
  end
end

function Drawer.Sweep()
  if not (C_Timer and C_Timer.After) then return end
  Drawer.sweep = (Drawer.sweep or 0) + 1
  local gen = Drawer.sweep
  for _, s in ipairs(SWEEPS) do
    C_Timer.After(s, function()
      if gen == Drawer.sweep and cfg().enabled ~= false and Drawer.frame then Drawer.Scan() end
    end)
  end
end

function Drawer.Apply()
  if not Minimap then return end
  if cfg().enabled == false then Drawer.Disable() return end
  build()
  Drawer.Anchor()
  Drawer.launcher:Show()
  Drawer.Scan()
  Drawer.Layout()
  Drawer.Listen()
  Drawer.Sweep()
end

function Drawer.Disable()
  for i = #Drawer.list, 1, -1 do Drawer.Release(Drawer.list[i]) end
  Drawer.Unwatch()
  if Drawer.frame then Drawer.frame:Hide() end
  if Drawer.launcher then Drawer.launcher:Hide() end
end

function Drawer.Refresh() Drawer.Apply() end

-- ------------------------------------------------------------------------------------------------ reading
function Drawer.Count()
  local shown = 0
  for _, b in ipairs(Drawer.list) do if call(b.IsShown, b) then shown = shown + 1 end end
  return #Drawer.list, shown
end

function Drawer.Names()
  local out = {}
  for _, b in ipairs(Drawer.list) do out[#out + 1] = saved[b] and saved[b].name or "?" end
  return out
end

function Drawer.Label(b)
  local n = saved[b] and saved[b].name or "?"
  return (n:gsub("^LibDBIcon10_", ""))
end

function Drawer.Probe()
  local n, shown = Drawer.Count()
  return { collected = table.concat(Drawer.Names(), ","), count = n, shown = shown,
    skipped = table.concat(Drawer.skipped or {}, ","), anchor = Drawer.anchoredTo or "none", side = Drawer.side or "?",
    open = (Drawer.frame and Drawer.frame:IsShown()) and "1" or "0" }
end
