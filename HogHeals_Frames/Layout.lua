-- Pure layout math. No frames touched here; fully unit-tested.
HogHealsFrames = HogHealsFrames or {}
local HHF = HogHealsFrames
local Layout = {}
HHF.Layout = Layout

local UNITS_PER_GROUP = 5
Layout.UNITS_PER_GROUP = UNITS_PER_GROUP

local DIR = { DOWN = { 0, -1 }, UP = { 0, 1 }, RIGHT = { 1, 0 }, LEFT = { -1, 0 }, CENTER = { 1, 0 } }   -- CENTER: a RIGHT row, re-anchored on its middle by Headers

--- Compute {x=,y=} offsets (from the layout anchor) for n units.
--- Units 1..5 = group 1, 6..10 = group 2, ... Groups lay out along cfg.groupGrowth,
--- wrapping to a new row every cfg.groupsPerRow groups.
function Layout.Compute(cfg, n)
  local w, h, sp = cfg.width or 0, cfg.height or 0, cfg.spacing or 0
  local gs = cfg.groupSpacing or 0
  local ud = DIR[cfg.growth or "DOWN"] or DIR.DOWN
  local gd = DIR[cfg.groupGrowth or "RIGHT"] or DIR.RIGHT
  local groupsPerRow = math.max(1, cfg.groupsPerRow or 1)

  -- Per-axis extents of one group (x axis, y axis).
  local unitAxisIsX = ud[1] ~= 0
  local extX = unitAxisIsX and (UNITS_PER_GROUP * (w + sp) - sp) or w
  local extY = unitAxisIsX and h or (UNITS_PER_GROUP * (h + sp) - sp)

  -- Row direction = perpendicular to group growth. Prefer the unit-growth direction when it is
  -- perpendicular; otherwise default RIGHT (x) / DOWN (y).
  local rowDir
  if gd[1] ~= 0 then rowDir = (ud[2] ~= 0) and { 0, ud[2] } or { 0, -1 }
  else rowDir = (ud[1] ~= 0) and { ud[1], 0 } or { 1, 0 } end

  local out = {}
  for i = 1, n do
    local g = math.ceil(i / UNITS_PER_GROUP)
    local k = (i - 1) % UNITS_PER_GROUP
    local col = (g - 1) % groupsPerRow
    local row = math.floor((g - 1) / groupsPerRow)
    local x = ud[1] * k * (w + sp) + gd[1] * col * (extX + gs) + rowDir[1] * row * (extX + gs)
    local y = ud[2] * k * (h + sp) + gd[2] * col * (extY + gs) + rowDir[2] * row * (extY + gs)
    out[i] = { x = x, y = y }
  end
  return out
end

--- SecureGroupHeader attributes for a layout config.
function Layout.HeaderAttributes(cfg)
  local growth = cfg.growth or "DOWN"
  local spacing = cfg.spacing or 0
  local a = { unitsPerColumn = UNITS_PER_GROUP, maxColumns = 1, columnSpacing = cfg.groupSpacing or 0 }
  if growth == "DOWN" then
    a.point, a.xOffset, a.yOffset, a.columnAnchorPoint = "TOP", 0, -spacing, "LEFT"
  elseif growth == "UP" then
    a.point, a.xOffset, a.yOffset, a.columnAnchorPoint = "BOTTOM", 0, spacing, "LEFT"
  elseif growth == "RIGHT" or growth == "CENTER" then
    a.point, a.xOffset, a.yOffset, a.columnAnchorPoint = "LEFT", spacing, 0, "TOP"
  else
    a.point, a.xOffset, a.yOffset, a.columnAnchorPoint = "RIGHT", -spacing, 0, "TOP"
  end
  return a
end

--- Offset of group header g (1-based) relative to the layout anchor.
function Layout.GroupOffset(cfg, g)
  local pts = Layout.Compute(cfg, g * UNITS_PER_GROUP)
  local p = pts[(g - 1) * UNITS_PER_GROUP + 1]
  return p.x, p.y
end

--- Bounding size of a layout with `groups` groups (for the drag anchor).
function Layout.Extent(cfg, groups)
  local pts = Layout.Compute(cfg, math.max(1, groups) * UNITS_PER_GROUP)
  local w, h = cfg.width or 0, cfg.height or 0
  local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
  for _, p in ipairs(pts) do
    minX = math.min(minX, p.x); maxX = math.max(maxX, p.x + w)
    minY = math.min(minY, p.y - h); maxY = math.max(maxY, p.y)
  end
  return maxX - minX, maxY - minY
end
