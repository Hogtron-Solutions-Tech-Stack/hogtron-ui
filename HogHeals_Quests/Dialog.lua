-- Dialog: the quest giver's pages in a HogTron UI window instead of Blizzard's parchment. Sean 2026-10-14, from the
-- "5 add-ons you can't live without in WoW Forever" clip (#5, Dialogue UI): Space accepts, Esc declines, the XP a
-- quest is worth shown as a share of your level, dark (ink) or light (parchment).
--
-- How Blizzard's window is kept shut: QuestFrame stops listening to its page events and GossipFrame to GOSSIP_SHOW /
-- GOSSIP_CLOSED - only the events each one had, remembered in a side table - so neither ever opens. The same NPC
-- session is then driven through the plain API (AcceptQuest, DeclineQuest, CompleteQuest, GetQuestReward,
-- SelectActiveQuest / SelectAvailableQuest, C_GossipInfo.Select*, CloseQuest, C_GossipInfo.CloseGossip). The Forever
-- build of Dialogue UI keeps Blizzard's frames shut the same way. Turning the window off registers the events again:
-- no /reload.
-- Capability gate: a frame is muted only when this client has every call its pages need, and only when the frame
-- really listens to its "open" event; otherwise Blizzard's window stays and /hh dialogdiag says why.
-- Failsafe: a page that throws while we draw it is handed to Blizzard's frame (its OnEvent runs the event), every
-- frame is unmuted and the window stands down until /reload - never a quest giver with no window at all.
--
-- Auto.lua answers each page first (it owns the event frame and calls Dialog.Page after its own handler): a page it
-- acted on (accepted, handed in, picked the only gossip quest) is already gone, so nothing shows here.
-- Keys: Space = the main button, 1-9 = the numbered rows (gossip lines, quests, reward choices), Esc = decline /
-- goodbye. Override bindings, set out of combat only and dropped as combat starts (PLAYER_REGEN_DISABLED runs before
-- the lockdown does), so Space is never stuck as a dialog key while you need it to jump in a fight.
-- Steps aside when Dialogue UI or Immersion is loaded (two addons muting the same frames = no window at all).
HogHealsQuests = HogHealsQuests or {}
local HHQ = HogHealsQuests
local HH = HogHeals

local Dialog = { muted = {}, seen = {}, rows = {}, gen = 0, active = { quest = false, gossip = false }, why = {} }
HHQ.Dialog = Dialog

local function cfg() local q = HH.db and HH.db.profile and HH.db.profile.quests return (q and q.dialog) or {} end
local function g(name) local f = rawget(_G, name) if type(f) == "function" then return f end end
local function fn(tbl, name) if type(tbl) == "table" and type(tbl[name]) == "function" then return tbl[name] end end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function str(v) if type(v) == "string" and not isSecret(v) then return v end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d, e, f6 = pcall(f, ...)
  if ok then return a, b, c, d, e, f6 end
end
local function count(k) Dialog.seen[k] = (Dialog.seen[k] or 0) + 1 end
local function gossipAPI() local GI = rawget(_G, "C_GossipInfo") return type(GI) == "table" and GI or nil end

-- ------------------------------------------------------------------------------------------------ look
Dialog.THEMES = {
  ink = { bg = { 0.07, 0.07, 0.09 }, text = { 0.96, 0.92, 0.86 }, muted = { 0.60, 0.60, 0.66 }, accent = { 0.13, 0.83, 0.88 },
          title = { 0.96, 0.92, 0.86 }, edge = { 0.20, 0.20, 0.25 }, button = { 0.14, 0.14, 0.17 }, quest = { 0.95, 0.65, 0.15 },
          primaryText = { 0.07, 0.07, 0.09 }, shadow = true },
  parchment = { bg = { 0.93, 0.89, 0.80 }, text = { 0.18, 0.13, 0.08 }, muted = { 0.45, 0.39, 0.30 }, accent = { 0.04, 0.47, 0.53 },
          title = { 0.12, 0.09, 0.05 }, edge = { 0.62, 0.55, 0.42 }, button = { 0.85, 0.80, 0.69 }, quest = { 0.72, 0.42, 0.04 },
          primaryText = { 0.97, 0.95, 0.90 }, shadow = false },
}
Dialog.THEME_NAMES = { ink = "Ink (dark)", parchment = "Parchment (light)" }
local QUEST_OPEN = "Interface\\AddOns\\HogHeals\\Media\\quest_open"
local QUEST_DONE = "Interface\\AddOns\\HogHeals\\Media\\quest_done"
local FLAT = "Interface\\Buttons\\WHITE8X8"
local PAD, GAP, ROW_MIN, ICON = 16, 8, 26, 20
local KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9" }

function Dialog.Theme() return Dialog.THEMES[cfg().theme or "ink"] or Dialog.THEMES.ink end

-- ------------------------------------------------------------------------------------------------ pure
--- XP a quest is worth as a whole-number share of the level bar, or nil (no XP, no bar, unreadable).
function Dialog.XPShare(xp, xpMax)
  xp, xpMax = num(xp), num(xpMax)
  if not xp or not xpMax or xp <= 0 or xpMax <= 0 then return nil end
  return math.floor(xp / xpMax * 100 + 0.5)
end

--- 12345 -> "12,345"
function Dialog.Thousands(n)
  local s = tostring(math.floor(n or 0))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

--- "+1,250 XP  (14% of a level)" / "+1,250 XP"
function Dialog.XPLine(xp, share)
  if not num(xp) or xp <= 0 then return nil end
  local s = "+" .. Dialog.Thousands(xp) .. " XP"
  if share then s = s .. ("  (%d%% of a level)"):format(share) end
  return s
end

--- Rough wrapped height of text in a box `width` wide at font `size`: the stand-in when the client cannot measure.
function Dialog.EstimateHeight(text, width, size)
  size = size or 14
  if type(text) ~= "string" or text == "" then return 0 end
  local perLine = math.max(10, math.floor((width or 400) / (size * 0.52)))
  local lines = 0
  for para in (text .. "\n"):gmatch("(.-)\n") do lines = lines + math.max(1, math.ceil(#para / perLine)) end
  return lines * math.floor(size * 1.3 + 0.5)
end

local function money(copper)
  copper = num(copper)
  if not copper or copper <= 0 then return nil end
  local coins = g("GetCoinTextureString")
  local s = coins and str(call(coins, copper))
  if s then return s end
  local gold, silver = math.floor(copper / 10000), math.floor(copper / 100) % 100
  if gold > 0 then return ("%dg %ds %dc"):format(gold, silver, copper % 100) end
  if silver > 0 then return ("%ds %dc"):format(silver, copper % 100) end
  return ("%dc"):format(copper)
end
Dialog.Money = money

local function atMaxLevel()
  local lvl, max = num(call(g("UnitLevel"), "player")), num(call(g("GetMaxPlayerLevel")))
  return lvl and max and lvl >= max or false
end

-- ------------------------------------------------------------------------------------------------ capability + mute
Dialog.QUEST_NEEDS = { "GetTitleText", "GetQuestText", "AcceptQuest", "CompleteQuest", "GetQuestReward", "CloseQuest" }
Dialog.GOSSIP_NEEDS = { "GetText", "GetOptions", "SelectOption", "CloseGossip", "GetAvailableQuests", "GetActiveQuests",
  "SelectAvailableQuest", "SelectActiveQuest" }

--- What this client lacks for a page family ("quest" | "gossip"); empty = everything is there.
function Dialog.Missing(family)
  local out = {}
  if family == "quest" then
    for _, n in ipairs(Dialog.QUEST_NEEDS) do if not g(n) then out[#out + 1] = n end end
    return out
  end
  local GI = gossipAPI()
  if not GI then return { "C_GossipInfo" } end
  for _, n in ipairs(Dialog.GOSSIP_NEEDS) do if not fn(GI, n) then out[#out + 1] = "C_GossipInfo." .. n end end
  return out
end

-- frame -> the family it serves, the event that opens it, the events it loses while ours is on
Dialog.MUTE = {
  QuestFrame = { family = "quest", open = "QUEST_DETAIL",
    events = { "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_ITEM_UPDATE" } },
  GossipFrame = { family = "gossip", open = "GOSSIP_SHOW", events = { "GOSSIP_SHOW", "GOSSIP_CLOSED" } },
  CustomGossipFrameManager = { family = "gossip", open = "GOSSIP_SHOW", events = { "GOSSIP_SHOW", "GOSSIP_CLOSED" } },
}
Dialog.MUTE_ORDER = { "QuestFrame", "GossipFrame", "CustomGossipFrameManager" }

local function registered(f, e)
  local ok, on = pcall(f.IsEventRegistered, f, e)
  return ok and on and true or false
end

--- Take a Blizzard frame's page events away. Only a frame that really listens to its open event is touched; what was
-- taken is remembered so Unmute can give back exactly that.
function Dialog.Mute(name)
  if Dialog.muted[name] then return true end
  local spec, f = Dialog.MUTE[name], rawget(_G, name)
  if not spec or type(f) ~= "table" or not fn(f, "IsEventRegistered") or not fn(f, "UnregisterEvent") then return false end
  if not registered(f, spec.open) then return false end
  local took = {}
  for _, e in ipairs(spec.events) do
    if registered(f, e) and pcall(f.UnregisterEvent, f, e) then took[#took + 1] = e end
  end
  Dialog.muted[name] = took
  return true
end

function Dialog.Unmute(name)
  local took = Dialog.muted[name]
  if not took then return end
  local f = rawget(_G, name)
  if type(f) == "table" and fn(f, "RegisterEvent") then
    for _, e in ipairs(took) do pcall(f.RegisterEvent, f, e) end
  end
  Dialog.muted[name] = nil
end

function Dialog.Deferring()
  local f = (type(C_AddOns) == "table" and C_AddOns.IsAddOnLoaded) or g("IsAddOnLoaded")
  if not f then return nil end
  for _, a in ipairs({ "DialogueUI", "Immersion" }) do
    local ok, loaded = pcall(f, a)
    if ok and loaded then return a end
  end
end

--- Mute what we can serve, unmute the rest. Re-run on login, profile change, option change, late Blizzard loads.
function Dialog.Apply()
  Dialog.active = { quest = false, gossip = false }
  Dialog.why = {}
  local o = cfg()
  local defer = Dialog.Deferring()
  if o.enabled == false or Dialog.broken or defer then
    for _, n in ipairs(Dialog.MUTE_ORDER) do Dialog.Unmute(n) end
    Dialog.why.all = o.enabled == false and "off" or Dialog.broken and ("stood down after an error: " .. Dialog.broken) or ("steps aside for " .. defer)
    Dialog.Close()
    Dialog.WriteDiag()
    return
  end
  for _, n in ipairs(Dialog.MUTE_ORDER) do
    local spec = Dialog.MUTE[n]
    local missing = Dialog.Missing(spec.family)
    if #missing > 0 then
      Dialog.Unmute(n)
      Dialog.why[spec.family] = "this client lacks " .. table.concat(missing, ", ")
    elseif Dialog.Mute(n) then
      Dialog.active[spec.family] = true
    end
  end
  for _, fam in ipairs({ "quest", "gossip" }) do
    if not Dialog.active[fam] and not Dialog.why[fam] then Dialog.why[fam] = "Blizzard's frame is not there yet / does not listen" end
  end
  Dialog.WriteDiag()
end

-- ------------------------------------------------------------------------------------------------ reading a page
local function questItems(kind, n)
  local out = {}
  local info = g("GetQuestItemInfo")
  for i = 1, math.min(n or 0, 10) do
    local name, tex, cnt, quality, usable = call(info, kind, i)
    out[#out + 1] = { name = str(name) or "...", icon = tex, count = num(cnt) or 1, quality = num(quality),
      usable = usable ~= false, kind = kind, index = i }
  end
  return out
end

--- Everything one page shows, as data: { kind, npc, title, body, objectives, xp, xpShare, money, rewards, choices,
-- required, rows = { { text, icon, glyph, item, act } }, primary, secondary }. kind = detail | progress | complete |
-- greeting | gossip.
function Dialog.Read(kind)
  local o = cfg()
  local m = { kind = kind, npc = str(call(g("UnitName"), "npc")), rows = {}, rewards = {}, choices = {}, required = {} }
  local function row(r) m.rows[#m.rows + 1] = r end
  if kind == "gossip" then
    local GI = gossipAPI()
    m.title = m.npc or ""
    m.body = str(call(GI.GetText)) or ""
    local active = call(GI.GetActiveQuests) or {}
    for _, q in ipairs(active) do
      if q.isComplete then row({ text = str(q.title) or "?", icon = QUEST_DONE, glyph = "?", tone = "quest", act = { "active", q.questID } }) end
    end
    for _, q in ipairs(call(GI.GetAvailableQuests) or {}) do
      row({ text = str(q.title) or "?", icon = QUEST_OPEN, glyph = "!", tone = q.isTrivial and "muted" or "quest", act = { "available", q.questID } })
    end
    for _, q in ipairs(active) do
      if not q.isComplete then row({ text = str(q.title) or "?", glyph = "?", tone = "muted", act = { "active", q.questID } }) end
    end
    local opts = call(GI.GetOptions) or {}
    table.sort(opts, function(a, b) return (num(a.orderIndex) or 0) < (num(b.orderIndex) or 0) end)
    for _, op in ipairs(opts) do
      row({ text = str(op.name) or "...", icon = num(op.icon), glyph = ">", tone = "text", act = { "option", op.gossipOptionID } })
    end
    m.secondary = { label = "Goodbye", action = "closeGossip", key = "Esc" }
  elseif kind == "greeting" then
    m.title = m.npc or ""
    m.body = str(call(g("GetGreetingText"))) or ""
    local nAc, nAv = num(call(g("GetNumActiveQuests"))) or 0, num(call(g("GetNumAvailableQuests"))) or 0
    for i = 1, nAc do
      local title, done = call(g("GetActiveTitle"), i)
      done = done == true or done == 1
      row({ text = str(title) or "?", icon = done and QUEST_DONE or nil, glyph = "?", tone = done and "quest" or "muted", act = { "activeIndex", i } })
    end
    for i = 1, nAv do
      local title = call(g("GetAvailableTitle"), i)
      row({ text = str(title) or "?", icon = QUEST_OPEN, glyph = "!", tone = "quest", act = { "availableIndex", i } })
    end
    m.secondary = { label = "Goodbye", action = "closeQuest", key = "Esc" }
  else
    m.title = str(call(g("GetTitleText"))) or ""
    if kind == "detail" then
      m.body = str(call(g("GetQuestText"))) or ""
      m.objectives = str(call(g("GetObjectiveText")))
      m.primary = { label = "Accept", action = "accept", key = "Space" }
      m.secondary = { label = "Decline", action = "decline", key = "Esc" }
      if call(g("QuestGetAutoAccept")) == true then
        m.primary = { label = "Okay", action = "closeQuest", key = "Space" }
        m.secondary = nil
      end
    elseif kind == "progress" then
      m.body = str(call(g("GetProgressText"))) or ""
      m.required = questItems("required", num(call(g("GetNumQuestItems"))) or 0)
      local can = g("IsQuestCompletable")
      m.primary = { label = "Continue", action = "continue", key = "Space", disabled = can ~= nil and not call(can) }
      m.secondary = { label = "Goodbye", action = "closeQuest", key = "Esc" }
    else
      m.body = str(call(g("GetRewardText"))) or ""
      m.primary = { label = "Complete", action = "reward", key = "Space" }
      m.secondary = { label = "Goodbye", action = "closeQuest", key = "Esc" }
    end
    if kind ~= "progress" then
      m.rewards = questItems("reward", num(call(g("GetNumQuestRewards"))) or 0)
      m.choices = questItems("choice", num(call(g("GetNumQuestChoices"))) or 0)
      m.money = num(call(g("GetRewardMoney")))
      m.xp = num(call(g("GetRewardXP")))
      if m.xp and o.xpShare ~= false and not atMaxLevel() then
        m.xpShare = Dialog.XPShare(m.xp, num(call(g("UnitXPMax"), "player")))
      end
    end
    if kind == "complete" and #m.choices > 1 then
      for i, c in ipairs(m.choices) do row({ text = c.name, item = c, act = { "choose", i } }) end
      m.primary.disabled = true
      m.pickHint = "Pick a reward: click it or press its number."
    end
  end
  return m
end

-- ------------------------------------------------------------------------------------------------ actions
--- Run one of the page's actions. Returns true when something was sent to the game.
function Dialog.Do(action)
  local m = Dialog.model
  if m and m.preview then Dialog.Hide() return false end
  if action == "accept" then call(g("AcceptQuest")) count("accept")
  elseif action == "decline" then
    if g("DeclineQuest") then call(g("DeclineQuest")) else call(g("CloseQuest")) end
    count("decline")
  elseif action == "continue" then
    if m and m.primary and m.primary.disabled then return false end
    call(g("CompleteQuest")) count("continue")
  elseif action == "reward" then
    local n = m and #(m.choices or {}) or 0
    local pick = n == 0 and 0 or n == 1 and 1 or Dialog.choice
    if not pick then return false end
    call(g("GetQuestReward"), pick) count("reward")
  elseif action == "closeQuest" then call(g("CloseQuest")) count("close")
  elseif action == "closeGossip" then call(fn(gossipAPI(), "CloseGossip")) count("close")
  else return false end
  Dialog.last = action
  return true
end

--- A numbered row was picked (click or key). i = its number among the rows you can pick.
function Dialog.Pick(i)
  local m = Dialog.model
  local r = m and m.picks and m.picks[i]
  if not r or not r.act then return false end
  local kind, id = r.act[1], r.act[2]
  if kind == "choose" then
    Dialog.choice = id
    if m.primary then m.primary.disabled = false end
    Dialog.Render()
    return not m.preview
  end
  if m.preview then return false end
  local GI = gossipAPI()
  if kind == "active" then call(fn(GI, "SelectActiveQuest"), id)
  elseif kind == "available" then call(fn(GI, "SelectAvailableQuest"), id)
  elseif kind == "option" then call(fn(GI, "SelectOption"), id)
  elseif kind == "activeIndex" then call(g("SelectActiveQuest"), id)
  elseif kind == "availableIndex" then call(g("SelectAvailableQuest"), id)
  else return false end
  count("pick:" .. kind)
  Dialog.last = "pick:" .. kind
  return true
end

-- ------------------------------------------------------------------------------------------------ window
local function setFont(fs, size)
  local look = HH.Look
  local font = look and look.Font and call(look.Font) or nil
  if font and fs.SetFont then pcall(fs.SetFont, fs, font, size, "") end
end

local function fs(parent, template)
  local t = parent:CreateFontString(nil, "OVERLAY", template or "HogTronFontHighlight")
  t:SetJustifyH("LEFT")
  if t.SetJustifyV then t:SetJustifyV("TOP") end
  return t
end

local function edge(f)
  local e = {}
  for i, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
    local t = f:CreateTexture(nil, "BORDER")
    t:SetPoint(spec[1], f, spec[1], 0, 0)
    t:SetPoint(spec[2], f, spec[2], 0, 0)
    if spec[3] then t:SetWidth(spec[3]) else t:SetHeight(spec[4]) end
    e[i] = t
  end
  return e
end

local function button(parent, name)
  local b = CreateFrame("Button", name, parent)
  b:SetSize(120, 28)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints(b)
  b.label = fs(b, "HogTronFontNormal")
  b.label:SetPoint("CENTER", b, "CENTER", 0, 1)
  if b.label.SetJustifyH then b.label:SetJustifyH("CENTER") end
  b.key = fs(b, "HogTronFontSmall")
  b.key:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 2)
  return b
end

function Dialog.Build()
  if Dialog.frame then return Dialog.frame end
  local f = CreateFrame("Frame", "HogTronUIDialog", UIParent)
  f:SetSize(cfg().width or 460, 240)
  f:SetFrameStrata("DIALOG")
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if cfg().locked ~= true then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, _, x, y = self:GetPoint()
    local o = cfg()
    if type(p) == "string" and num(x) and num(y) then o.point, o.x, o.y = p, math.floor(x + 0.5), math.floor(y + 0.5) end
  end)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints(f)
  f.edge = edge(f)
  f.npc = fs(f, "HogTronFontSmall")
  f.title = fs(f, "HogTronFontNormalLarge")
  f.rule = f:CreateTexture(nil, "ARTWORK")
  f.rule:SetHeight(1)
  f.body = fs(f)
  f.objHead = fs(f, "HogTronFontSmall")
  f.objectives = fs(f)
  f.rewHead = fs(f, "HogTronFontSmall")
  f.xp = fs(f)
  f.money = fs(f)
  f.hint = fs(f, "HogTronFontSmall")
  f.primary = button(f, "HogTronUIDialogPrimary")
  f.primary:SetScript("OnClick", function()
    local m = Dialog.model
    if m and m.primary and Dialog.frame:IsShown() then Dialog.Do(m.primary.action) end
  end)
  f.secondary = button(f, "HogTronUIDialogSecondary")
  f.secondary:SetScript("OnClick", function()
    local m = Dialog.model
    if m and m.secondary then
      Dialog.Do(m.secondary.action)
      Dialog.Hide()
    end
  end)
  f.close = CreateFrame("Button", nil, f)
  f.close:SetSize(22, 22)
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  f.close.label = fs(f.close, "HogTronFontNormal")
  f.close.label:SetPoint("CENTER", f.close, "CENTER", 0, 0)
  f.close.label:SetText("x")
  f.close:SetScript("OnClick", function() f:Hide() Dialog.OnHide() end)
  f:SetScript("OnHide", function() Dialog.OnHide() end)
  local special = rawget(_G, "UISpecialFrames")
  if type(special) == "table" then special[#special + 1] = "HogTronUIDialog" end
  f:Hide()
  Dialog.frame = f
  return f
end

local function rowButton(i)
  local r = Dialog.rows[i]
  if r then return r end
  local f = Dialog.frame
  r = CreateFrame("Button", "HogTronUIDialogRow" .. i, f)
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints(r)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(ICON, ICON)
  r.icon:SetPoint("LEFT", r, "LEFT", 22, 0)
  r.glyph = fs(r, "HogTronFontNormal")
  r.glyph:SetPoint("CENTER", r.icon, "CENTER", 0, 0)
  r.num = fs(r, "HogTronFontSmall")
  r.num:SetPoint("LEFT", r, "LEFT", 4, 0)
  r.text = fs(r)
  if r.text.SetJustifyV then r.text:SetJustifyV("MIDDLE") end
  r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
  r.text:SetPoint("RIGHT", r, "RIGHT", -6, 0)
  r:SetScript("OnClick", function(self) if self.pick then Dialog.Pick(self.pick) end end)
  r:SetScript("OnEnter", function(self)
    local tip = rawget(_G, "GameTooltip")
    if self.item and type(tip) == "table" and fn(tip, "SetQuestItem") then
      pcall(tip.SetOwner, tip, self, "ANCHOR_RIGHT")
      pcall(tip.SetQuestItem, tip, self.item.kind, self.item.index)
      pcall(tip.Show, tip)
    end
    self.hover = true
    Dialog.PaintRow(self)
  end)
  r:SetScript("OnLeave", function(self)
    local tip = rawget(_G, "GameTooltip")
    if type(tip) == "table" and fn(tip, "Hide") then pcall(tip.Hide, tip) end
    self.hover = false
    Dialog.PaintRow(self)
  end)
  Dialog.rows[i] = r
  return r
end

local function qualityColor(q)
  if not num(q) then return nil end
  local C = rawget(_G, "C_Item")
  local r, gg, b = call(fn(C, "GetItemQualityColor"), q)
  if not num(r) then r, gg, b = call(g("GetItemQualityColor"), q) end
  if num(r) and num(gg) and num(b) then return { r, gg, b } end
end

function Dialog.PaintRow(r)
  local th = Dialog.Theme()
  local sel = r.choose and Dialog.choice == r.choose
  if sel then r.bg:SetColorTexture(th.accent[1], th.accent[2], th.accent[3], 0.28)
  elseif r.hover and r.pick then r.bg:SetColorTexture(th.accent[1], th.accent[2], th.accent[3], 0.14)
  else r.bg:SetColorTexture(th.button[1], th.button[2], th.button[3], r.pick and 0.55 or 0) end
end

local function placeText(fsx, text, size, width, y, color)
  if not text or text == "" then fsx:Hide() return y end
  setFont(fsx, size)
  fsx:SetWidth(width)
  if fsx.SetWordWrap then fsx:SetWordWrap(true) end
  fsx:ClearAllPoints()
  fsx:SetPoint("TOPLEFT", Dialog.frame, "TOPLEFT", PAD, y)
  fsx:SetText(text)
  fsx:SetTextColor(color[1], color[2], color[3])
  if fsx.SetShadowOffset then if Dialog.Theme().shadow then fsx:SetShadowOffset(1, -1) else fsx:SetShadowOffset(0, 0) end end
  fsx:Show()
  local h = fsx.GetStringHeight and num(call(fsx.GetStringHeight, fsx))
  if not h or h <= 0 then h = Dialog.EstimateHeight(text, width, size) end
  return y - h - GAP
end

--- Lay the current page out top to bottom. The window grows with the page.
function Dialog.Render()
  local m, f = Dialog.model, Dialog.Build()
  if not m then return end
  local o, th = cfg(), Dialog.Theme()
  local W = o.width or 460
  local size = o.fontSize or 14
  local inner = W - PAD * 2
  f:SetWidth(W)
  if f.SetScale then f:SetScale(o.scale or 1) end
  f.bg:SetColorTexture(th.bg[1], th.bg[2], th.bg[3], o.alpha or 0.95)
  for _, t in ipairs(f.edge) do t:SetColorTexture(th.edge[1], th.edge[2], th.edge[3], 1) end
  f.close.label:SetTextColor(th.muted[1], th.muted[2], th.muted[3])
  local y = -PAD
  if o.npcName ~= false and m.npc and m.npc ~= "" and m.npc ~= m.title then
    y = placeText(f.npc, m.npc:upper(), size - 3, inner - 24, y, th.accent) + GAP - 4
  else f.npc:Hide() end
  y = placeText(f.title, m.title, size + 4, inner - 24, y, th.title) + GAP - 4
  f.rule:ClearAllPoints()
  f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
  f.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
  f.rule:SetColorTexture(th.accent[1], th.accent[2], th.accent[3], 0.9)
  y = y - 1 - GAP
  y = placeText(f.body, m.body, size, inner, y, th.text)
  if m.objectives and m.objectives ~= "" then
    y = placeText(f.objHead, "OBJECTIVES", size - 3, inner, y, th.accent) + GAP - 4
    y = placeText(f.objectives, m.objectives, size, inner, y, th.text)
  else f.objHead:Hide() f.objectives:Hide() end
  local xpLine = Dialog.XPLine(m.xp, m.xpShare)
  local cash = money(m.money)
  local hasRewards = xpLine or cash or #m.rewards > 0 or #m.choices > 0
  if hasRewards then
    y = placeText(f.rewHead, "REWARDS", size - 3, inner, y, th.accent) + GAP - 4
  else f.rewHead:Hide() end
  y = placeText(f.xp, xpLine, size, inner, y, th.text)
  y = placeText(f.money, cash, size, inner, y, th.text)
  -- rows: item lists (not picked) + numbered rows (picked with a click or 1-9)
  local list = {}
  local function add(r) list[#list + 1] = r end
  -- Blizzard's order: the choice first, then what comes with it anyway
  local choosing = #m.choices > 1
  if choosing then add({ text = "Choose one of these:", header = true }) end
  if m.kind == "complete" and choosing then
    for _, r in ipairs(m.rows) do add(r) end
  else
    for _, it in ipairs(m.choices) do add({ text = it.name, item = it }) end
  end
  if choosing and #m.rewards > 0 then add({ text = "You also receive:", header = true }) end
  for _, it in ipairs(m.rewards) do add({ text = it.name, item = it }) end
  if #m.required > 0 then add({ text = "Bring:", header = true }) end
  for _, it in ipairs(m.required) do add({ text = it.name, item = it }) end
  if not (m.kind == "complete" and choosing) then for _, r in ipairs(m.rows) do add(r) end end
  m.picks = {}
  local used = 0
  for _, d in ipairs(list) do
    used = used + 1
    local r = rowButton(used)
    r.item, r.pick, r.choose, r.hover = d.item, nil, nil, false
    if d.act then
      m.picks[#m.picks + 1] = d
      r.pick = #m.picks
      if d.act[1] == "choose" then r.choose = d.act[2] end
    end
    r:SetWidth(inner)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    r.num:SetText(r.pick and r.pick <= 9 and (r.pick .. ".") or "")
    r.num:SetTextColor(th.muted[1], th.muted[2], th.muted[3])
    local icon = d.icon or (d.item and d.item.icon)
    r.glyph:SetText("")
    if d.header then
      r.icon:Hide()
    else
      r.icon:Show()
      local shown = icon ~= nil and call(r.icon.SetTexture, r.icon, icon) ~= false
      if not shown or icon == nil then
        r.icon:SetTexture(nil)
        r.glyph:SetText(d.glyph or "")
        local c = d.tone == "quest" and th.quest or d.tone == "muted" and th.muted or th.text
        r.glyph:SetTextColor(c[1], c[2], c[3])
      end
    end
    local label = d.text or ""
    if d.item and (d.item.count or 1) > 1 then label = label .. "  x" .. d.item.count end
    setFont(r.text, size)
    r.text:SetText(label)
    local c = (d.header and th.muted) or (d.item and qualityColor(d.item.quality)) or (d.tone == "muted" and th.muted) or th.text
    if d.item and Dialog.Theme() == Dialog.THEMES.parchment and d.item.quality and d.item.quality <= 1 then c = th.text end
    r.text:SetTextColor(c[1], c[2], c[3])
    local h = math.max(ROW_MIN, Dialog.EstimateHeight(label, inner - ICON - 36, size) + 8)
    if d.header then h = math.floor(size * 1.5) end
    r:SetHeight(h)
    Dialog.PaintRow(r)
    r:Show()
    y = y - h - 2
  end
  for i = used + 1, #Dialog.rows do Dialog.rows[i]:Hide() end
  if m.pickHint and not Dialog.choice then
    y = placeText(f.hint, m.pickHint, size - 2, inner, y - 4, th.muted)
  else f.hint:Hide() end
  -- footer
  y = y - 6
  local function paintButton(b, spec, primary)
    if not spec then b:Hide() return end
    b:ClearAllPoints()
    b.label:SetText(spec.label)
    b.key:SetText(cfg().keys ~= false and spec.key or "")
    local bg = primary and th.accent or th.button
    local fg = primary and th.primaryText or th.text
    local a = spec.disabled and 0.35 or 1
    b.bg:SetColorTexture(bg[1], bg[2], bg[3], a)
    b.label:SetTextColor(fg[1], fg[2], fg[3])
    b.key:SetTextColor(fg[1], fg[2], fg[3])
    if b.SetEnabled then b:SetEnabled(not spec.disabled) end
    b:Show()
  end
  paintButton(f.primary, m.primary, true)
  paintButton(f.secondary, m.secondary, false)
  if m.primary then
    f.primary:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    if m.secondary then f.secondary:SetPoint("RIGHT", f.primary, "LEFT", -8, 0) end
  elseif m.secondary then
    f.secondary:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
  end
  y = y - 28 - PAD
  f:SetHeight(math.floor(-y + 0.5))
  Dialog.height = math.floor(-y + 0.5)
end

function Dialog.Place()
  local f, o = Dialog.Build(), cfg()
  f:ClearAllPoints()
  f:SetPoint(o.point or "CENTER", UIParent, o.point or "CENTER", o.x or 320, o.y or 40)
end

-- ------------------------------------------------------------------------------------------------ keys
function Dialog.BindKeys()
  local f, m = Dialog.frame, Dialog.model
  if not f or not m or cfg().keys == false then return false end
  if InCombatLockdown() then Dialog.keysWanted = true return false end
  pcall(ClearOverrideBindings, f)
  local n = 0
  if m.primary then
    pcall(SetOverrideBindingClick, f, true, "SPACE", "HogTronUIDialogPrimary") n = n + 1
  elseif #(m.picks or {}) == 1 then
    pcall(SetOverrideBindingClick, f, true, "SPACE", "HogTronUIDialogRow" .. Dialog.SlotOfPick(1)) n = n + 1
  end
  for i = 1, math.min(9, #(m.picks or {})) do
    pcall(SetOverrideBindingClick, f, true, KEYS[i], "HogTronUIDialogRow" .. Dialog.SlotOfPick(i)) n = n + 1
  end
  Dialog.keysBound, Dialog.keysWanted = n > 0, false
  return n > 0
end

--- The row button (slot) that carries pick number i.
function Dialog.SlotOfPick(i)
  for slot, r in ipairs(Dialog.rows) do if r.pick == i and r:IsShown() then return slot end end
  return i
end

function Dialog.UnbindKeys()
  Dialog.keysWanted = false
  if not Dialog.keysBound or not Dialog.frame then return end
  if InCombatLockdown() then Dialog.unbindLater = true return end
  pcall(ClearOverrideBindings, Dialog.frame)
  Dialog.keysBound, Dialog.unbindLater = false, false
end

-- ------------------------------------------------------------------------------------------------ show / hide
--- Draw a page. refresh = the same page re-read (item names arrived): not a new page, so a close the game already
-- asked for is not cancelled by it.
function Dialog.ShowPage(kind, refresh)
  local f = Dialog.Build()
  local wasShown = f:IsShown()
  local same = Dialog.model and Dialog.model.kind == kind
  Dialog.model = Dialog.Read(kind)
  if not (same and kind == "complete") then Dialog.choice = nil end
  if kind == "complete" and Dialog.choice and Dialog.model.primary then Dialog.model.primary.disabled = false end
  if not refresh then Dialog.gen = Dialog.gen + 1 Dialog.closing = false end
  if not wasShown then Dialog.Place() end
  Dialog.Render()
  f:Show()
  Dialog.BindKeys()
  count("show:" .. kind)
  Dialog.shownKind = kind
end

--- Our own hide: keys off, the NPC session left alone (the game already closed it, or a button just did).
function Dialog.Hide()
  if not Dialog.frame then return end
  Dialog.hiding = true
  Dialog.UnbindKeys()
  Dialog.frame:Hide()
  Dialog.hiding = false
  Dialog.model = nil
  Dialog.choice = nil
  Dialog.closing = false
end
Dialog.Close = Dialog.Hide

--- The player closed the window (Esc via UISpecialFrames, the x): back out of the NPC the way Blizzard's would.
function Dialog.OnHide()
  Dialog.UnbindKeys()
  if Dialog.hiding then return end
  local m = Dialog.model
  Dialog.model, Dialog.choice = nil, nil
  if not m or m.preview then return end
  Dialog.model = m   -- Do reads the page it is backing out of
  if m.kind == "detail" and m.secondary then Dialog.Do("decline")
  elseif m.kind == "gossip" then Dialog.Do("closeGossip")
  else Dialog.Do("closeQuest") end
  Dialog.model = nil
  count("backOut")
end

--- The game closed a session (QUEST_FINISHED / GOSSIP_CLOSED). The next page often follows a moment later (gossip ->
-- quest, progress -> complete), so the window waits a beat and hides only if no page came in between.
function Dialog.Finished(family)
  local m = Dialog.model
  if not m or not Dialog.frame or not Dialog.frame:IsShown() then return end
  if (m.kind == "gossip") ~= (family == "gossip") then return end
  local gen = Dialog.gen
  Dialog.closing = true
  local function later() if Dialog.gen == gen and Dialog.model then Dialog.Hide() count("finished") end end
  if type(C_Timer) == "table" and C_Timer.After then C_Timer.After(0.2, later) else later() end
end

Dialog.PAGES = { QUEST_DETAIL = "detail", QUEST_PROGRESS = "progress", QUEST_COMPLETE = "complete", QUEST_GREETING = "greeting", GOSSIP_SHOW = "gossip" }

--- Called by Auto's event frame for each page event, after Auto had its go. acted = Auto already answered the page.
function Dialog.Page(event, acted, ...)
  local kind = Dialog.PAGES[event]
  if not kind then return end
  local family = kind == "gossip" and "gossip" or "quest"
  if not Dialog.active[family] then return end
  if acted then count("autoAnswered") return end
  local ok, err = pcall(Dialog.ShowPage, kind)
  if not ok then Dialog.Fail(event, err, ...) end
end

--- A page we could not draw: stand down, give the frames back, and let Blizzard's own window show this very page.
function Dialog.Fail(event, err, ...)
  HH:LogError("quests dialog " .. tostring(event) .. ": " .. tostring(err))
  count("failed")
  Dialog.broken = tostring(err):sub(1, 160)
  pcall(Dialog.Hide)
  Dialog.Apply()
  local name = "QuestFrame"
  if event == "GOSSIP_SHOW" then
    name = rawget(_G, "CustomGossipFrameManager") and "CustomGossipFrameManager" or "GossipFrame"
  end
  local f = rawget(_G, name)
  local h = type(f) == "table" and fn(f, "GetScript") and call(f.GetScript, f, "OnEvent")
  if type(h) == "function" then
    local ok = pcall(h, f, event, ...)
    Dialog.handedBack = name .. (ok and "" or " (its handler failed too)")
  end
end

--- A sample page to see the look without an NPC (options button, /hh dialog preview). Buttons only close it.
function Dialog.Preview()
  local m = {
    kind = "complete", preview = true, npc = "Marshal Dughan", title = "Wolves Across the Border",
    body = "Well done, $N. Those wolves have harried the farms of Northshire for too long. Take one of these - the town can spare it.",
    xp = 1250, money = 750, rows = {}, required = {},
    rewards = {},
    choices = {
      { name = "Brawler's Gloves", count = 1, quality = 2, kind = "choice", index = 1 },
      { name = "Woodland Tunic", count = 1, quality = 2, kind = "choice", index = 2 },
      { name = "Light Leather Pants", count = 1, quality = 1, kind = "choice", index = 3 },
    },
    primary = { label = "Complete", action = "reward", key = "Space", disabled = true },
    secondary = { label = "Goodbye", action = "closeQuest", key = "Esc" },
    pickHint = "Pick a reward: click it or press its number.",
  }
  m.body = m.body:gsub("%$N", str(call(g("UnitName"), "player")) or "adventurer")
  m.xpShare = Dialog.XPShare(m.xp, num(call(g("UnitXPMax"), "player")) or 8800)
  for i, c in ipairs(m.choices) do m.rows[#m.rows + 1] = { text = c.name, item = c, act = { "choose", i } } end
  Dialog.Build()
  Dialog.model, Dialog.choice = m, nil
  Dialog.gen = Dialog.gen + 1
  Dialog.Place()
  Dialog.Render()
  Dialog.frame:Show()
end

-- ------------------------------------------------------------------------------------------------ diag + wiring
function Dialog.Lines()
  local o = cfg()
  local out = {}
  out[#out + 1] = ("dialog: %s; theme %s; keys %s"):format(Dialog.why.all or "on", o.theme or "ink", o.keys == false and "off" or "on")
  local parts = {}
  for _, n in ipairs(Dialog.MUTE_ORDER) do
    local took = Dialog.muted[n]
    if took then parts[#parts + 1] = n .. "(" .. table.concat(took, ",") .. ")" end
  end
  out[#out + 1] = "  muted: " .. (#parts > 0 and table.concat(parts, " ") or "nothing - Blizzard's windows show")
  out[#out + 1] = ("  quest pages: %s | gossip: %s"):format(Dialog.active.quest and "ours" or ("Blizzard's - " .. tostring(Dialog.why.quest or Dialog.why.all)),
    Dialog.active.gossip and "ours" or ("Blizzard's - " .. tostring(Dialog.why.gossip or Dialog.why.all)))
  local c = {}
  for k, v in pairs(Dialog.seen) do c[#c + 1] = k .. "=" .. v end
  table.sort(c)
  out[#out + 1] = "  counts: " .. (#c > 0 and table.concat(c, " ") or "nothing yet")
  if Dialog.handedBack then out[#out + 1] = "  last failure handed the page to " .. Dialog.handedBack end
  return out
end

function Dialog.WriteDiag()
  local gl = HH.db and HH.db.global
  if not gl then return end
  gl.diag = gl.diag or {}
  local muted = {}
  for n, took in pairs(Dialog.muted) do muted[n] = table.concat(took, ",") end
  gl.diag.dialog = { at = date and date("%Y-%m-%d %H:%M:%S") or "", active = { quest = Dialog.active.quest, gossip = Dialog.active.gossip },
    why = Dialog.why, muted = muted, broken = Dialog.broken }
end

function Dialog.Start()
  if Dialog.events then Dialog.Apply() return end
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "QUEST_FINISHED", "GOSSIP_CLOSED", "QUEST_ITEM_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTERING_WORLD", "ADDON_LOADED" }) do pcall(ev.RegisterEvent, ev, e) end
  ev:SetScript("OnEvent", function(_, e, arg1)
    if e == "QUEST_FINISHED" then Dialog.Finished("quest")
    elseif e == "GOSSIP_CLOSED" then Dialog.Finished("gossip")
    elseif e == "QUEST_ITEM_UPDATE" then
      if Dialog.model and not Dialog.model.preview and not Dialog.closing and Dialog.frame and Dialog.frame:IsShown() then
        local ok, err = pcall(Dialog.ShowPage, Dialog.model.kind, true)
        if not ok then Dialog.Fail("QUEST_ITEM_UPDATE", err) end
      end
    elseif e == "PLAYER_REGEN_DISABLED" then
      -- still allowed here: the lockdown starts after this event. Space / 1-9 go back to the action bar for the fight.
      if Dialog.keysBound then pcall(ClearOverrideBindings, Dialog.frame) Dialog.keysBound = false Dialog.keysWanted = Dialog.frame and Dialog.frame:IsShown() end
    elseif e == "PLAYER_REGEN_ENABLED" then
      if Dialog.unbindLater then Dialog.unbindLater = false Dialog.keysBound = true Dialog.UnbindKeys() end
      if Dialog.keysWanted and Dialog.frame and Dialog.frame:IsShown() then Dialog.BindKeys() end
    elseif e == "PLAYER_ENTERING_WORLD" or (e == "ADDON_LOADED" and type(arg1) == "string" and (arg1:find("^Blizzard_") or arg1 == "DialogueUI" or arg1 == "Immersion")) then
      Dialog.Apply()
    end
  end)
  Dialog.events = ev
  Dialog.Apply()
end

function Dialog.Refresh()
  Dialog.Apply()
  if Dialog.model and Dialog.frame and Dialog.frame:IsShown() then Dialog.Render() end
end

HH:RegisterSlash("dialogdiag", function()
  Dialog.Apply()
  for _, l in ipairs(Dialog.Lines()) do HH:Print(l) end
end, "quest dialog window: which Blizzard frames are muted, why not, what fired")

--- /hh dialog on | off | ink | parchment | preview | reset
HH:RegisterSlash("dialog", function(rest)
  local o = HH.db.profile.quests.dialog
  local w = (rest or ""):lower():match("^%s*(%a*)")
  if w == "on" or w == "off" then o.enabled = w == "on" Dialog.Refresh() HH:Print("dialog window: " .. w) return end
  if w == "ink" or w == "parchment" or w == "dark" or w == "light" then
    o.theme = (w == "ink" or w == "dark") and "ink" or "parchment"
    Dialog.Refresh()
    HH:Print("dialog theme: " .. Dialog.THEME_NAMES[o.theme])
    return
  end
  if w == "preview" then Dialog.Preview() return end
  if w == "reset" then o.point, o.x, o.y = nil, nil, nil if Dialog.frame and Dialog.frame:IsShown() then Dialog.Place() end HH:Print("dialog: position reset") return end
  for _, l in ipairs(Dialog.Lines()) do HH:Print(l) end
  HH:Print("usage: /hh dialog on|off  -  ink|parchment  -  preview  -  reset")
end, "quest dialog window: on / off, ink / parchment, preview, reset position")
