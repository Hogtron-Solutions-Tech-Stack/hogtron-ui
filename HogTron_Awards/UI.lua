-- HogTron Awards: the golden VIEW AWARDS prompt and the full-screen awards stage.
--
-- Plain (insecure) frames only. Nothing here calls a protected function, so it all works in combat: Escape closes the
-- stage through UISpecialFrames, a click on the dark background closes it, and it closes on its own after 45 s.
-- The prompt closes on its own after 60 s. PlayerModel:SetUnit / SetAnimation are not protected.
HogTronAwards = HogTronAwards or {}
local A = HogTronAwards
local HH = HogHeals

local UI = {}
A.UI = UI

local GOLD, GOLD_HI, BRONZE = { 0.85, 0.64, 0.18 }, { 1.0, 0.86, 0.42 }, { 0.55, 0.37, 0.18 }
local CREAM, CYAN, INK, GREY = { 0.96, 0.92, 0.86 }, { 0.13, 0.83, 0.88 }, { 0.07, 0.07, 0.09 }, { 0.55, 0.55, 0.60 }
local ROAST = { 0.95, 0.45, 0.25 }

--- Award emote -> character animation id (the client's AnimationData order; same ids on every 1.x/2.x client).
A.EMOTES = { talk = 60, eat = 61, bow = 66, wave = 67, cheer = 68, dance = 69, laugh = 70, sleep = 71, sit = 72, rude = 73,
  roar = 74, kneel = 75, kiss = 76, cry = 77, chicken = 78, beg = 79, applaud = 80, shout = 81, flex = 82, shy = 83,
  point = 84, dead = 6 }

A.ICON_PATH = "Interface\\AddOns\\HogTron_Awards\\assets\\awards\\"

function A.IconFor(award) return A.ICON_PATH .. award.id end

-- ------------------------------------------------------------------------------------------------ layouts
--- Where the five players stand, as fractions of the screen from its centre: { x, y, scale } for the headline first,
-- then the four others. Two layouts for Sean to choose between (mockups in docs/mockups/awards/):
--   arc      headline in front, the other four on a shallow arc behind it (podium / end-of-match screen)
--   corners  headline in the middle, the other four in a 2x2 around it
UI.LAYOUTS = {
  arc = { { 0, 0.04, 1.0 }, { -0.21, 0.0, 0.8 }, { 0.21, 0.0, 0.8 }, { -0.40, -0.05, 0.7 }, { 0.40, -0.05, 0.7 } },
  corners = { { 0, 0.0, 1.0 }, { -0.32, 0.20, 0.7 }, { 0.32, 0.20, 0.7 }, { -0.32, -0.20, 0.7 }, { 0.32, -0.20, 0.7 } },
}
UI.LAYOUT_LABELS = { arc = "Centre + arc (podium)", corners = "Centre + 2x2 corners" }

function UI.Positions(layout, w, h)
  local spec = UI.LAYOUTS[layout] or UI.LAYOUTS.arc
  local out = {}
  for i, p in ipairs(spec) do out[i] = { x = p[1] * w, y = p[2] * h, scale = p[3] } end
  return out
end

-- ------------------------------------------------------------------------------------------------ helpers
local function solid(parent, layer, c, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  return t
end

local function text(parent, font, c, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "HogTronFontSmall")
  c = c or CREAM
  fs:SetTextColor(c[1], c[2], c[3])
  if justify then fs:SetJustifyH(justify) end
  return fs
end

local function classColor(name)
  local unit = A.Metrics.UnitFor(name)
  local _, class
  if unit then local ok, a, b = pcall(UnitClass, unit) if ok then _, class = a, b end end
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c and not A.Metrics.isSecret(c.r) then return { c.r, c.g, c.b } end
  return CREAM
end

local function later(sec, fn)
  if C_Timer and C_Timer.After then C_Timer.After(sec, fn) end
end

-- ------------------------------------------------------------------------------------------------ prompt
function UI.Prompt()
  if UI.prompt then return UI.prompt end
  local b = CreateFrame("Button", "HogTronAwardsPrompt", UIParent)
  b:SetSize(280, 58)
  b:SetPoint("TOP", UIParent, "TOP", 0, -150)
  b:SetFrameStrata("DIALOG")
  b.rim = solid(b, "BACKGROUND", BRONZE)
  b.rim:SetAllPoints(b)
  b.fill = solid(b, "BORDER", GOLD)
  b.fill:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
  b.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
  b.shine = solid(b, "ARTWORK", GOLD_HI, 0.55)
  b.shine:SetPoint("TOPLEFT", b.fill, "TOPLEFT", 0, 0)
  b.shine:SetPoint("TOPRIGHT", b.fill, "TOPRIGHT", 0, 0)
  b.shine:SetHeight(22)
  b.label = text(b, "HogTronFontNormalLarge", INK, "CENTER")
  b.label:SetPoint("CENTER", b, "CENTER", 0, 4)
  b.label:SetText("VIEW AWARDS")
  b.sub = text(b, "HogTronFontSmall", { 0.22, 0.14, 0.05 }, "CENTER")
  b.sub:SetPoint("BOTTOM", b, "BOTTOM", 0, 7)
  b:SetScript("OnClick", function() UI.HidePrompt() UI.ShowStage(A.last and A.last.stage, A.last) end)
  b:SetScript("OnUpdate", function(self, dt)
    self.t = (self.t or 0) + (dt or 0)
    self.shine:SetAlpha(0.35 + 0.3 * math.abs(math.sin(self.t * 2.4)))
  end)
  b:Hide()
  UI.prompt = b
  return b
end

function UI.ShowPrompt(sub, seconds)
  local b = UI.Prompt()
  b.sub:SetText(sub or "")
  b:Show()
  local token = {}
  UI.promptToken = token
  later(seconds or 60, function() if UI.promptToken == token then UI.HidePrompt() end end)
  return b
end

function UI.HidePrompt()
  UI.promptToken = nil
  if UI.prompt then UI.prompt:Hide() end
end

-- ------------------------------------------------------------------------------------------------ stage
local CONFETTI = 48
local CONFETTI_COLORS = { GOLD, GOLD_HI, CYAN, CREAM, BRONZE }

local function buildSlot(parent, i)
  local s = CreateFrame("Frame", nil, parent)
  s:SetSize(240, 420)
  s.model = CreateFrame("PlayerModel", "HogTronAwardsModel" .. i, s)
  s.model:SetPoint("TOP", s, "TOP", 0, 0)
  s.model:SetSize(240, 260)
  s.card = CreateFrame("Frame", nil, s)
  s.card:SetPoint("TOP", s.model, "BOTTOM", 0, -4)
  s.card:SetSize(240, 150)
  s.card:EnableMouse(true)
  s.card.rim = solid(s.card, "BACKGROUND", BRONZE)
  s.card.rim:SetAllPoints(s.card)
  s.card.bg = solid(s.card, "BORDER", INK, 0.95)
  s.card.bg:SetPoint("TOPLEFT", s.card, "TOPLEFT", 2, -2)
  s.card.bg:SetPoint("BOTTOMRIGHT", s.card, "BOTTOMRIGHT", -2, 2)
  s.icon = s.card:CreateTexture(nil, "ARTWORK")
  s.icon:SetSize(72, 72)
  s.icon:SetPoint("TOPLEFT", s.card, "TOPLEFT", 10, -10)
  s.kind = text(s.card, "HogTronFontSmall", GOLD, "LEFT")
  s.kind:SetPoint("TOPLEFT", s.icon, "TOPRIGHT", 10, -2)
  s.award = text(s.card, "HogTronFontNormalLarge", GOLD_HI, "LEFT")
  s.award:SetPoint("TOPLEFT", s.kind, "BOTTOMLEFT", 0, -4)
  s.award:SetPoint("RIGHT", s.card, "RIGHT", -8, 0)
  s.player = text(s.card, "HogTronFontNormal", CREAM, "LEFT")
  s.player:SetPoint("TOPLEFT", s.award, "BOTTOMLEFT", 0, -4)
  s.flavor = text(s.card, "HogTronFontSmall", CREAM, "LEFT")
  s.flavor:SetPoint("TOPLEFT", s.icon, "BOTTOMLEFT", 0, -8)
  s.flavor:SetPoint("RIGHT", s.card, "RIGHT", -10, 0)
  if s.flavor.SetWordWrap then s.flavor:SetWordWrap(true) end
  s.card:SetScript("OnEnter", function(self)
    local w = s.winner
    if not w or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(w.award.name, GOLD_HI[1], GOLD_HI[2], GOLD_HI[3])
    GameTooltip:AddLine(w.name .. ": " .. tostring(w.detail or ""), CREAM[1], CREAM[2], CREAM[3], true)
    if w.award.note then GameTooltip:AddLine(w.award.note, GREY[1], GREY[2], GREY[3], true) end
    GameTooltip:Show()
  end)
  s.card:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return s
end

function UI.Stage()
  if UI.stage then return UI.stage end
  local f = CreateFrame("Frame", "HogTronAwardsStage", UIParent)
  f:SetAllPoints(UIParent)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:EnableMouse(true)
  f.shade = solid(f, "BACKGROUND", INK, 0.78)
  f.shade:SetAllPoints(f)
  f.title = text(f, "HogTronFontNormalLarge", GOLD_HI, "CENTER")
  f.title:SetPoint("TOP", f, "TOP", 0, -48)
  f.where = text(f, "HogTronFontNormal", CREAM, "CENTER")
  f.where:SetPoint("TOP", f.title, "BOTTOM", 0, -8)
  f.also = text(f, "HogTronFontSmall", GREY, "CENTER")
  f.also:SetPoint("BOTTOM", f, "BOTTOM", 0, 40)
  f.hint = text(f, "HogTronFontSmall", GREY, "CENTER")
  f.hint:SetPoint("BOTTOM", f.also, "TOP", 0, 8)
  f.hint:SetText("Esc or click anywhere to close")
  f.slots = {}
  for i = 1, 5 do f.slots[i] = buildSlot(f, i) end
  f.confetti = {}
  for i = 1, CONFETTI do
    local c = f:CreateTexture(nil, "ARTWORK")
    local col = CONFETTI_COLORS[(i % #CONFETTI_COLORS) + 1]
    c:SetColorTexture(col[1], col[2], col[3], 0.9)
    f.confetti[i] = c
  end
  -- click outside a card closes (cards have mouse enabled, so they swallow their own clicks)
  f:SetScript("OnMouseDown", function() UI.HideStage() end)
  f:SetScript("OnUpdate", function(self, dt) UI.Confetti(self, dt or 0) end)
  f:Hide()
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "HogTronAwardsStage") end
  UI.stage = f
  return f
end

--- Confetti: small slips falling and swaying from the top, recycled. Pure arithmetic on our own numbers.
function UI.Confetti(f, dt)
  local w, h = (UIParent.GetWidth and UIParent:GetWidth()) or 1920, (UIParent.GetHeight and UIParent:GetHeight()) or 1080
  f.t = (f.t or 0) + dt
  for i, c in ipairs(f.confetti) do
    c.x = c.x or ((i * 137) % 1000) / 1000 * w
    c.y = c.y or -(((i * 71) % 1000) / 1000) * h
    c.v = c.v or (60 + (i * 13) % 90)
    c.y = c.y + c.v * dt
    if c.y > h + 20 then c.y = -20 end
    local sway = math.sin(f.t * 1.7 + i) * 18
    c:ClearAllPoints()
    c:SetPoint("CENTER", f, "TOPLEFT", c.x + sway, -c.y)
    c:SetSize(4 + (i % 3) * 2, 8 + (i % 4) * 2)
  end
end

local function fillSlot(s, w, pos, cx, cy)
  s.winner = w
  if not w then s:Hide() return end
  s:ClearAllPoints()
  s:SetPoint("CENTER", s:GetParent(), "CENTER", pos.x, pos.y)
  s:SetScale(pos.scale)
  local unit = A.Metrics.UnitFor(w.name) or w.unit
  if unit and (not UnitExists or UnitExists(unit)) then
    s.model:SetUnit(unit)
    local anim = A.EMOTES[w.award.emote] or A.EMOTES.cheer
    s.model:SetScript("OnModelLoaded", function(m) m:SetAnimation(anim) end)
    s.model:SetAnimation(anim)
    s.model.anim = anim
    s.model:Show()
  else
    s.model:Hide()                                   -- left the group: card only
  end
  s.icon:SetTexture(A.IconFor(w.award))
  s.kind:SetText(w.award.kind == "roast" and "ROAST" or "HONOR")
  local kc = w.award.kind == "roast" and ROAST or GOLD
  s.kind:SetTextColor(kc[1], kc[2], kc[3])
  s.award:SetText(w.award.name)
  local c = classColor(w.name)
  s.player:SetText(w.name)
  s.player:SetTextColor(c[1], c[2], c[3])
  s.flavor:SetText(w.award.flavor)
  s:Show()
end

--- Show a stage (from Resolve.Stage). info = { ctx, where, preview }.
function UI.ShowStage(stage, info)
  if not stage or not stage.headline then
    if HH and HH.Print then HH:Print("HogTron Awards: nothing to show yet.") end
    return nil
  end
  local f = UI.Stage()
  local w, h = (UIParent.GetWidth and UIParent:GetWidth()) or 1920, (UIParent.GetHeight and UIParent:GetHeight()) or 1080
  local layout = (A.Cfg and A.Cfg().layout) or "arc"
  local pos = UI.Positions(layout, w, h)
  local list = { stage.headline }
  for _, o in ipairs(stage.others or {}) do list[#list + 1] = o end
  for i = 1, 5 do fillSlot(f.slots[i], list[i], pos[i]) end
  f.title:SetText(info and info.preview and "HOGTRON AWARDS  (preview)" or "HOGTRON AWARDS")
  f.where:SetText(info and info.where or "")
  local also = {}
  for _, a in ipairs(stage.also or {}) do also[#also + 1] = a.award.name .. ": " .. a.name end
  f.also:SetText(#also > 0 and ("Also earned: " .. table.concat(also, "  -  ")) or "")
  f.shown = list
  f:Show()
  local token = {}
  UI.stageToken = token
  later((A.Cfg and A.Cfg().stageSeconds) or 45, function() if UI.stageToken == token then UI.HideStage() end end)
  return f
end

function UI.HideStage()
  UI.stageToken = nil
  if UI.stage then UI.stage:Hide() end
end
