-- Go: "GO: <quest>" at the top of the tracker - the one quest to do next, picked by your rule, with how far it is
-- and how long to the next level at your pace. Sean 2026-10-06, from the Quest Pilot clip: "continually evaluates
-- your active quests and recommends an efficient route to your next objective", "191 yd  ETA TO LVL".
--
-- Rules (profile.quests.go.rule): "fastest" = most experience for the time, "balanced", "travel" = the least
-- walking. Pure scoring in Go.Score so the tests can argue with it; distance from the same map maths the minimap
-- pins use (Pins.PlayerPosition / MapSize + Data.PointsOnMap). No point on this map = distance unknown (counted
-- as "far-ish", never as zero).
HogHealsQuests = HogHealsQuests or {}
local HHQ = HogHealsQuests
local HH = HogHeals

local Go = {}
HHQ.Go = Go

Go.RULES = { fastest = "Fastest experience", balanced = "Balanced", travel = "Least walking" }
-- weights per rule: experience, travel, progress (multiplicative score, each factor raised to its weight)
Go.WEIGHTS = { fastest = { 2, 0.5, 1 }, balanced = { 1, 1, 1 }, travel = { 0.5, 2, 1 } }
Go.UNKNOWN_YARDS = 400   -- what a quest with no point on this map counts as

local CYAN, CREAM, GREY, GREEN = { 0.13, 0.83, 0.88 }, { 0.96, 0.92, 0.86 }, { 0.55, 0.55, 0.60 }, { 0.25, 0.80, 0.35 }

local function cfg() return HH.db.profile.quests.go or {} end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
end

--- Grey to you (no experience) at this level: the old game's rule, 5 + level/10 under you.
function Go.IsGrey(questLevel, playerLevel)
  if not questLevel or not playerLevel then return false end
  return questLevel <= playerLevel - (5 + math.floor(playerLevel / 10))
end

--- Score one quest. q = { level, complete, objectives }, ctx = { level, yards | nil, rule }. Higher = do it next.
-- Returns score, and the three factors (experience, travel, progress) for the tooltip.
function Go.Score(q, ctx)
  local L = ctx.level or 1
  local w = Go.WEIGHTS[ctx.rule or "balanced"] or Go.WEIGHTS.balanced
  local ql = num(q.level)
  local xp
  if ql and Go.IsGrey(ql, L) then xp = 0.1
  elseif ql then xp = math.max(0.2, math.min(2, 1 + 0.15 * (ql - L)))
  else xp = 1 end
  local yards = ctx.yards or Go.UNKNOWN_YARDS
  local travel = 1 / (1 + yards / 300)
  local progress
  if q.complete then progress = 2
  else
    local done, all = 0, 0
    for _, o in ipairs(q.objectives or {}) do all = all + 1 if o.done then done = done + 1 end end
    progress = 1 + 0.5 * (all > 0 and done / all or 0)
  end
  local score = (xp ^ w[1]) * (travel ^ w[2]) * (progress ^ w[3])
  return score, xp, travel, progress
end

--- Distance in yards from the player to each quest's point on the current map: { [questID] = yards }.
function Go.Yards()
  local Pins = HHQ.Pins
  if not Pins or not Pins.PlayerPosition then return {} end
  local mapID, px, py = Pins.PlayerPosition()
  if not mapID then return {} end
  local w, h = Pins.MapSize(mapID)
  if not w then return {} end
  local out = {}
  for _, pt in ipairs(HHQ.Data.PointsOnMap(mapID)) do
    if pt.id then
      local dx, dy = (pt.x - px) * w, (pt.y - py) * h
      local yd = math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)
      if out[pt.id] == nil or yd < out[pt.id] then out[pt.id] = yd end
    end
  end
  return out
end

--- The quest to do next from a log list. Returns pick = { quest, yards, score, xp, travel, progress } or nil.
function Go.Pick(list, yardsById, rule, level)
  local best
  level = level or num(try(UnitLevel, "player")) or 1
  for _, q in ipairs(list or {}) do
    if not q.failed and not q.hidden then
      local yd = q.id and yardsById and yardsById[q.id] or nil
      local s, xp, travel, progress = Go.Score(q, { level = level, yards = yd, rule = rule })
      if not best or s > best.score or (s == best.score and (q.title or "") < (best.quest.title or "")) then
        best = { quest = q, yards = yd, score = s, xp = xp, travel = travel, progress = progress }
      end
    end
  end
  return best
end

--- Pick for the live log (cached per quest-log generation + player position bucket, the tracker repaints often).
function Go.Current(list)
  local d = cfg()
  if d.enabled == false then return nil end
  list = list or HHQ.Data.last or HHQ.Data.List()
  local yards = Go.Yards()
  local pick = Go.Pick(list, yards, d.rule or "balanced")
  if pick and d.superTrack ~= false and pick.quest.id and Go.lastTracked ~= pick.quest.id then
    local st = rawget(_G, "C_SuperTrack")
    if type(st) == "table" and type(st.SetSuperTrackedQuestID) == "function" then
      pcall(st.SetSuperTrackedQuestID, pick.quest.id)
      Go.lastTracked = pick.quest.id
    end
  end
  Go.last = pick
  return pick
end

--- "191 yd" / "4/10" / "ready" pieces for the line under the title.
function Go.Detail(pick)
  local parts = {}
  if pick.yards then parts[#parts + 1] = ("%d yd"):format(pick.yards) end
  local q = pick.quest
  if q.complete then parts[#parts + 1] = "ready to turn in"
  else
    local done, all = 0, 0
    for _, o in ipairs(q.objectives or {}) do all = all + 1 if o.done then done = done + 1 end end
    if all > 0 then parts[#parts + 1] = ("%d/%d"):format(done, all) end
  end
  local S = HH.Session
  if S then
    local st = S.Stats()
    if st.toLevel and st.level then parts[#parts + 1] = ("lvl %d in %s"):format(st.level + 1, S.FormatTime(st.toLevel)) end
  end
  return table.concat(parts, "  -  ")
end

-- ------------------------------------------------------------------------------------------------ tracker row
local function fs(parent, color, justify)
  local t = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  t:SetTextColor(color[1], color[2], color[3])
  t:SetJustifyH(justify or "LEFT")
  if t.SetWordWrap then t:SetWordWrap(false) end
  return t
end

local function row(f)
  if f.go then return f.go end
  local b = CreateFrame("Button", nil, f.body)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.tag = fs(b, CYAN, "LEFT")
  b.tag:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  b.title = fs(b, CREAM, "LEFT")
  b.title:SetPoint("TOPLEFT", b.tag, "TOPRIGHT", 4, 0)
  b.title:SetPoint("RIGHT", b, "RIGHT", 0, 0)
  b.detail = fs(b, GREY, "LEFT")
  b.detail:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  b.detail:SetPoint("RIGHT", b, "RIGHT", 0, 0)
  b.rule = b:CreateTexture(nil, "ARTWORK")
  b.rule:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, -2)
  b.rule:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, -2)
  b.rule:SetHeight(1)
  b.rule:SetColorTexture(0.20, 0.20, 0.25, 1)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints(b)
  b.hl:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.12)
  b:SetScript("OnClick", function(self, button)
    local q = self.quest
    if not q then return end
    if button == "RightButton" then Go.CycleRule() return end
    HHQ.Data.Open(q)
  end)
  b:SetScript("OnEnter", function(self)
    if not GameTooltip or not self.pick then return end
    local p = self.pick
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("GO: " .. tostring(p.quest.title))
    GameTooltip:AddLine(("Rule: %s. Experience %.2f, travel %.2f, progress %.2f -> %.2f"):format(Go.RULES[cfg().rule or "balanced"] or "?", p.xp, p.travel, p.progress, p.score), 0.6, 0.6, 0.6, true)
    GameTooltip:AddLine("Left: open in quest log   Right: change the rule", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  f.go = b
  return b
end

--- Draw the GO row at the top of the tracker body. Returns the height it took (0 when off / nothing to do).
function Go.Draw(f, d, size, list)
  local b = row(f)
  local pick = (not d.collapsed) and Go.Current(list) or nil
  if not pick then b:Hide() b.quest, b.pick = nil, nil return 0 end
  b.quest, b.pick = pick.quest, pick
  local titleH, lineH = size + 6, size + 3
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, 0)
  b:SetPoint("RIGHT", f.body, "RIGHT", 0, 0)
  b:SetHeight(titleH + lineH)
  local font = f.title.GetFont and f.title:GetFont()
  for _, t in ipairs({ b.tag, b.title }) do if font and t.SetFont then pcall(t.SetFont, t, font, size, "") end end
  if font and b.detail.SetFont then pcall(b.detail.SetFont, b.detail, font, size - 1, "") end
  b.tag:SetText("GO:")
  b.title:SetText(tostring(pick.quest.title))
  local c = pick.quest.complete and GREEN or CREAM
  b.title:SetTextColor(c[1], c[2], c[3])
  b.detail:SetText(Go.Detail(pick))
  b:Show()
  return titleH + lineH + 6
end

function Go.CycleRule()
  local order = { "fastest", "balanced", "travel" }
  local d = cfg()
  local cur = d.rule or "balanced"
  for i, r in ipairs(order) do
    if r == cur then d.rule = order[i % #order + 1] break end
  end
  HH:Print("GO rule: " .. (Go.RULES[d.rule] or d.rule))
  if HHQ.Tracker and HHQ.Tracker.Schedule then HHQ.Tracker.Schedule() end
end

HH:RegisterSlash("go", function(rest)
  rest = (rest or ""):lower()
  if Go.RULES[rest] then cfg().rule = rest HH:Print("GO rule: " .. Go.RULES[rest]) if HHQ.Tracker then HHQ.Tracker.Schedule() end return end
  local pick = Go.Current()
  if not pick then HH:Print("GO: nothing to do next (empty log, or the GO line is off).") return end
  HH:Print(("GO: %s  -  %s"):format(tostring(pick.quest.title), Go.Detail(pick)))
end, "the quest to do next (/hh go fastest | balanced | travel = change the rule)")
