-- Hover + target marks on the party / raid cells. Sean 2026-10-03: "I don't like the current highlighting. I want
-- a white outline, a red outline, corners, things like that" - picked: hover = white 1 px outline, target = white
-- corners, each with its own style / colour / thickness in Frames > Highlight.
--
-- A mark = four edge textures (outline), eight corner arms (corners) and one fill; the style picks which set shows.
-- Marks sit OUTSIDE the cell rect (gap + thickness) so the red aggro border inside the cell stays visible. A cell
-- that is both hovered and targeted shows both marks; when both styles are "outline" only the target's shows.
-- The target is read through UnitIsUnit(unit, "target"); a SECRET answer (restricted client in combat) = no mark,
-- never a guess. The AoE-scope fill (AoEHealing.lua) is a separate element, off by default since this landed.
local HHF = HogHealsFrames
local HH = HogHeals

local E = { Events = { "PLAYER_TARGET_CHANGED" }, EventSet = { PLAYER_TARGET_CHANGED = true } }
local WHITE = { 1, 1, 1 }
local hovered = nil

local function cfg()
  local d = HH.db and HH.db.profile.frames
  return d and d.highlight or {}
end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function bool(v) if isSecret(v) then return nil end return v and true or false end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a = pcall(f, ...)
  if ok then return a end
end
local function whole(v, low) return math.max(low or 0, math.floor((tonumber(v) or 0) + 0.5)) end

-- ---------------------------------------------------------------- mark
local Mark = {}
Mark.__index = Mark
E.Mark = Mark

-- outline edges: { point1, point2, x1, y1, x2, y2, "h" | "v" } multiplied by `out` (gap + thickness)
local EDGES = { { "TOPLEFT", "TOPRIGHT", -1, 1, 1, 1, "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", -1, -1, 1, -1, "h" },
  { "TOPLEFT", "BOTTOMLEFT", -1, 1, -1, -1, "v" }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 1, 1, -1, "v" } }
local CORNERS = { { "TOPLEFT", -1, 1 }, { "TOPRIGHT", 1, 1 }, { "BOTTOMLEFT", -1, -1 }, { "BOTTOMRIGHT", 1, -1 } }

local function mkMark(button)
  local parent = button.overlay or button
  local m = setmetatable({ button = button, edges = {}, corners = {}, shown = false }, Mark)
  for i = 1, 4 do
    local t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    t:Hide()
    m.edges[i] = t
  end
  for i = 1, 8 do
    local t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    t:Hide()
    m.corners[i] = t
  end
  m.fill = parent:CreateTexture(nil, "OVERLAY", nil, 7)
  m.fill:SetAllPoints(button)
  m.fill:Hide()
  return m
end

function Mark:Hide()
  for _, t in ipairs(self.edges) do t:Hide() end
  for _, t in ipairs(self.corners) do t:Hide() end
  self.fill:Hide()
  self.shown, self.style = false, nil
end
function Mark:IsShown() return self.shown == true end

--- Paint the mark in style `c.style` with `c.color` / `c.thick` / `c.gap` / `c.size` / `c.alpha`; "none" hides.
function Mark:Apply(c)
  c = c or {}
  local style = c.style or "outline"
  self:Hide()
  if style == "none" then return nil end
  local col = c.color or WHITE
  local thick = whole(c.thick or 1, 1)
  local out = whole(c.gap or 0, 0) + thick
  local b = self.button
  if style == "outline" then
    for i, s in ipairs(EDGES) do
      local t = self.edges[i]
      t:ClearAllPoints()
      t:SetPoint(s[1], b, s[1], s[3] * out, s[4] * out)
      t:SetPoint(s[2], b, s[2], s[5] * out, s[6] * out)
      if s[7] == "h" then t:SetHeight(thick) else t:SetWidth(thick) end
      t:SetColorTexture(col[1], col[2], col[3], 1)
      t:Show()
    end
  elseif style == "corners" then
    local armH = whole(c.size or 8, thick + 1)
    -- the vertical arms never meet whatever the cell height: at least 2 px of air between them
    local h = tonumber(b.GetHeight and b:GetHeight()) or (armH * 4)
    local armV = math.max(thick + 1, math.min(armH, math.floor((h + 2 * out) / 2) - 1))
    for ci, corner in ipairs(CORNERS) do
      for arm = 1, 2 do
        local t = self.corners[(ci - 1) * 2 + arm]
        t:ClearAllPoints()
        t:SetPoint(corner[1], b, corner[1], corner[2] * out, corner[3] * out)
        if arm == 1 then t:SetSize(armH, thick) else t:SetSize(thick, armV) end
        t:SetColorTexture(col[1], col[2], col[3], 1)
        t:Show()
      end
    end
  elseif style == "fill" then
    self.fill:SetColorTexture(col[1], col[2], col[3], c.alpha or 0.25)
    self.fill:Show()
  else
    return nil
  end
  self.shown, self.style = true, style
  return style
end

local function mark(button, key)
  button[key] = button[key] or mkMark(button)
  return button[key]
end

-- ---------------------------------------------------------------- element
--- Is this cell the player's target? nil when the client will not say (secret), false/true otherwise.
function E.IsTarget(button)
  local unit = button.unit
  if not unit then return false end
  if not call(UnitExists, "target") then return false end
  return bool(call(UnitIsUnit, unit, "target"))
end

function E.Paint(button)
  local c = cfg()
  local hover, target = c.hover or {}, c.target or {}
  local isHover = hovered == button
  local isTarget = E.IsTarget(button) == true
  if isHover and isTarget and (hover.style or "outline") == "outline" and (target.style or "corners") == "outline" then
    isHover = false   -- two outlines on one cell fight; the target's wins
  end
  if isHover then mark(button, "hoverMark"):Apply(hover) elseif button.hoverMark then button.hoverMark:Hide() end
  if isTarget then mark(button, "targetMark"):Apply(target) elseif button.targetMark then button.targetMark:Hide() end
  return isHover, isTarget
end

function E.OnEnter(button)
  hovered = button
  E.Paint(button)
end

function E.OnLeave(button)
  if hovered == button then hovered = nil end
  E.Paint(button)
end

function E.Update(button, unit) E.Paint(button) end

function E.Hide(button)
  if button.hoverMark then button.hoverMark:Hide() end
  if button.targetMark then button.targetMark:Hide() end
end

function E.Hovered() return hovered end

HHF.UnitButton.RegisterElement("highlight", E)
