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
-- A torn parchment page (light) or the same sheet charred (dark), the NPC's portrait in a bronze ring, the title and
-- the text in the game's own Friz Quadrata - the book-page look of the Dialogue UI clip (Sean 2026-10-14: the first,
-- flat ink box "looks absolutely terrible"). Art = HogHeals/Media/dialog_*.tga, ours (dev/icons/build_dialog_art.py).
local MEDIA = "Interface\\AddOns\\HogTronUI\\Media\\"
local ART = { page = { light = MEDIA .. "dialog_page_light", dark = MEDIA .. "dialog_page_dark" }, ring = MEDIA .. "dialog_ring",
  rule = MEDIA .. "dialog_rule", round = MEDIA .. "dialog_round", line = MEDIA .. "dialog_round_line" }
Dialog.ART = ART
-- Inline reward icons (dev/icons/build_reward_icons.py, ours). Sean 2026-10-17: "We need images for the currency
-- received instead of S or C ... a small image for XP that is slightly different" - this client has no
-- GetCoinTextureString, so the page printed "6s 0c".
Dialog.COINS = { gold = MEDIA .. "coin_gold", silver = MEDIA .. "coin_silver", copper = MEDIA .. "coin_copper" }
Dialog.XP_ICON = MEDIA .. "reward_xp"
-- The page art's torn bottom edge rises up to 46 px (of 1024) under the button row - worst at x 56, the bottom-left
-- corner. Sean 2026-10-17: the left button sat on the tear (the old 42 px bottom margin was ~40 px of art). The row
-- now clears the tear by BUTTON_CLEAR px of paper.
Dialog.TEAR, Dialog.BUTTON_CLEAR = 46, 14
-- Quest marks on the page: crimson wax seals (Sean 2026-10-18 on the parchment page: "I also dont like this '!' and
-- want one that fits more" -> "I like these"). OpenArt sheet dialog_marks, cut by dev/icons/process_ui_art.py --only
-- marks. Offered = gold "!" (greyed for a low-level quest), ready to hand in = gold "?", still in progress = the faded
-- grey seal. Nameplates and the minimap keep quest_open / quest_done.
local QUEST_OPEN = MEDIA .. "dialog_quest_open"
local QUEST_DONE = MEDIA .. "dialog_quest_done"
local QUEST_WAIT = MEDIA .. "dialog_quest_wait"
Dialog.MARKS = { open = QUEST_OPEN, done = QUEST_DONE, wait = QUEST_WAIT }
local FLAT = "Interface\\Buttons\\WHITE8X8"
local PAGE_W, PAGE_H, SLICE = 512, 1024, 160    -- the page texture, and the height of its torn top / bottom slices
local EDGE_PERIOD = 176                         -- the art's side edges repeat every 176 px (build_dialog_art.py PERIOD)
local KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9" }

Dialog.THEMES = {
  light = { text = { 0.22, 0.14, 0.07 }, title = { 0.17, 0.10, 0.04 }, muted = { 0.44, 0.34, 0.22 }, rule = { 0.36, 0.24, 0.12 },
    tag = { 0.36, 0.24, 0.12, 0.16 }, tile = { 0.36, 0.24, 0.12, 0.09 }, hover = { 0.36, 0.24, 0.12, 0.18 }, pick = { 0.72, 0.48, 0.12 },
    button = { 0.30, 0.21, 0.13, 0.92 }, buttonText = { 0.96, 0.91, 0.82 }, outline = { 0.36, 0.24, 0.12, 0.60 },
    key = { 0.12, 0.08, 0.05, 0.88 }, keyText = { 0.96, 0.92, 0.84 }, quest = { 0.62, 0.36, 0.02 }, paper = true },
  dark = { text = { 0.86, 0.82, 0.75 }, title = { 0.96, 0.92, 0.84 }, muted = { 0.60, 0.56, 0.50 }, rule = { 0.78, 0.72, 0.62 },
    tag = { 1, 1, 1, 0.08 }, tile = { 1, 1, 1, 0.05 }, hover = { 1, 1, 1, 0.10 }, pick = { 0.88, 0.66, 0.28 },
    button = { 0.22, 0.21, 0.20, 0.95 }, buttonText = { 0.95, 0.91, 0.84 }, outline = { 0.75, 0.70, 0.62, 0.45 },
    key = { 0.04, 0.04, 0.04, 0.92 }, keyText = { 0.92, 0.90, 0.86 }, quest = { 0.95, 0.70, 0.20 }, paper = false },
}
Dialog.THEME_NAMES = { light = "Parchment (light)", dark = "Charred (dark)" }
local LEGACY = { parchment = "light", ink = "dark" }   -- the first build's names

function Dialog.ThemeKey()
  local k = cfg().theme or "light"
  k = LEGACY[k] or k
  return Dialog.THEMES[k] and k or "light"
end
function Dialog.Theme() return Dialog.THEMES[Dialog.ThemeKey()] end

-- item quality colours that still read on paper (Blizzard's green / white vanish on parchment)
Dialog.PAPER_QUALITY = { [0] = { 0.44, 0.40, 0.36 }, [1] = { 0.22, 0.14, 0.07 }, [2] = { 0.08, 0.42, 0.02 }, [3] = { 0.00, 0.28, 0.62 },
  [4] = { 0.42, 0.12, 0.62 }, [5] = { 0.70, 0.35, 0.00 } }

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

--- An inline texture escape at `size` px (the font's height), nudged 2 px off the number before it.
function Dialog.Icon(path, size)
  size = math.floor((size or 14) + 0.5)
  return ("|T%s:%d:%d:2:0|t"):format(path, size, size)
end

--- Money as coin icons: "6[silver]", "1[gold] 20[silver] 5[copper]". Zero coins are left out ("6s 0c" -> "6[silver]").
local function money(copper, size)
  copper = num(copper)
  if not copper or copper <= 0 then return nil end
  local gold, silver, cop = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local parts = {}
  if gold > 0 then parts[#parts + 1] = Dialog.Thousands(gold) .. Dialog.Icon(Dialog.COINS.gold, size) end
  if silver > 0 then parts[#parts + 1] = silver .. Dialog.Icon(Dialog.COINS.silver, size) end
  if cop > 0 then parts[#parts + 1] = cop .. Dialog.Icon(Dialog.COINS.copper, size) end
  return table.concat(parts, "  ")
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
--- The quest's objectives as "- 0/10 Dun Garok Mountaineer slain" lines, when the client lists them for the quest on
-- offer (C_QuestLog.GetQuestObjectives(GetQuestID())); nil = use the objective paragraph instead.
function Dialog.ObjectiveLines()
  local qid = num(call(g("GetQuestID")))
  local CQ = rawget(_G, "C_QuestLog")
  local objs = qid and qid > 0 and call(fn(CQ, "GetQuestObjectives"), qid) or nil
  if type(objs) ~= "table" then return nil end
  local out = {}
  for _, o in ipairs(objs) do
    local t = type(o) == "table" and str(o.text)
    if t and t ~= "" then out[#out + 1] = "- " .. t end
  end
  return #out > 0 and table.concat(out, "\n") or nil
end

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
      row({ text = str(q.title) or "?", icon = QUEST_OPEN, glyph = "!", tone = q.isTrivial and "muted" or "quest", dim = q.isTrivial == true,
        act = { "available", q.questID } })
    end
    for _, q in ipairs(active) do
      if not q.isComplete then row({ text = str(q.title) or "?", icon = QUEST_WAIT, glyph = "?", tone = "muted", act = { "active", q.questID } }) end
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
      row({ text = str(title) or "?", icon = done and QUEST_DONE or QUEST_WAIT, glyph = "?", tone = done and "quest" or "muted", act = { "activeIndex", i } })
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
      m.objectives = Dialog.ObjectiveLines() or str(call(g("GetObjectiveText")))
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
      local done = can == nil or call(can) and true or false
      m.primary = { label = done and "Continue" or "Incomplete", action = "continue", key = "Space", disabled = not done }
      m.secondary = { label = "Cancel", action = "closeQuest", key = "Esc" }
    else
      m.body = str(call(g("GetRewardText"))) or ""
      m.primary = { label = "Complete Quest", action = "reward", key = "Space" }
      m.secondary = { label = "Cancel", action = "closeQuest", key = "Esc" }
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
local function friz() return rawget(_G, "STANDARD_TEXT_FONT") or "Fonts\\FRIZQT__.TTF" end

local function setFont(f, size)
  local path = friz()
  if cfg().font == "hogtron" and HH.Look and HH.Look.Font then path = call(HH.Look.Font) or path end
  if f.SetFont then pcall(f.SetFont, f, path, size, "") end
  if f.SetShadowOffset then f:SetShadowOffset(0, 0) end   -- ink on paper casts no shadow
end

local function fs(parent, template)
  local t = parent:CreateFontString(nil, "OVERLAY", template or "HogTronFontHighlight")
  t:SetJustifyH("LEFT")
  if t.SetJustifyV then t:SetJustifyV("TOP") end
  return t
end

local function rgba(t, c, a) t:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1) end

--- A rounded shape that keeps its corners at any width: left cap, stretched middle, right cap of one 64 px texture.
local function slab(parent, layer, file, sub)
  local s = { parts = {} }
  for i = 1, 3 do
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(file)
    s.parts[i] = t
  end
  s.parts[1]:SetTexCoord(0, 0.5, 0, 1)
  s.parts[2]:SetTexCoord(0.49, 0.51, 0, 1)
  s.parts[3]:SetTexCoord(0.5, 1, 0, 1)
  function s.Place(_, anchor, x, y, w, h)
    local cap = math.min(h / 2, w / 2)
    local p = s.parts
    for _, t in ipairs(p) do t:ClearAllPoints() end
    p[1]:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y) p[1]:SetSize(cap, h)
    p[2]:SetPoint("TOPLEFT", anchor, "TOPLEFT", x + cap, y) p[2]:SetSize(math.max(0.01, w - 2 * cap), h)
    p[3]:SetPoint("TOPLEFT", anchor, "TOPLEFT", x + w - cap, y) p[3]:SetSize(cap, h)
    s.box = { x = x, y = y, w = w, h = h }
  end
  function s.Color(_, c, a) for _, t in ipairs(s.parts) do rgba(t, c, a) end s.color = { c[1], c[2], c[3], a or c[4] or 1 } end
  function s.Show() for _, t in ipairs(s.parts) do t:Show() end s.shown = true end
  function s.Hide() for _, t in ipairs(s.parts) do t:Hide() end s.shown = false end
  return s
end

--- A key cap ("Esc", "Space", "1"): dark rounded chip with light text.
local function keycap(parent)
  local k = { bg = slab(parent, "ARTWORK", ART.round, 1), text = fs(parent, "HogTronFontSmall") }
  if k.text.SetJustifyH then k.text:SetJustifyH("CENTER") end
  function k.Set(_, label, x, y, size)
    if not label or label == "" then k.bg:Hide() k.text:Hide() k.w = 0 return 0 end
    local th = Dialog.Theme()
    local w = math.max(18, #label * 7 + 10)
    k.bg:Place(parent, x, y, w, 18)
    k.bg:Color(th.key)
    k.bg:Show()
    setFont(k.text, size or 10)
    k.text:SetText(label)
    k.text:SetTextColor(th.keyText[1], th.keyText[2], th.keyText[3])
    k.text:ClearAllPoints()
    k.text:SetPoint("CENTER", parent, "TOPLEFT", x + w / 2, y - 9)
    k.text:Show()
    k.w = w
    return w
  end
  return k
end

local function tag(parent)
  local t = { bg = slab(parent, "ARTWORK", ART.round), text = fs(parent) }
  return t
end

local function button(parent, name)
  local b = CreateFrame("Button", name, parent)
  b:SetSize(200, 36)
  b.bg = slab(b, "BACKGROUND", ART.round)
  b.line = slab(b, "BORDER", ART.line)
  b.label = fs(b, "HogTronFontNormal")
  if b.label.SetJustifyH then b.label:SetJustifyH("CENTER") end
  b.key = keycap(b)
  b:SetScript("OnEnter", function(self) self.hover = true Dialog.PaintButton(self) end)
  b:SetScript("OnLeave", function(self) self.hover = false Dialog.PaintButton(self) end)
  return b
end

function Dialog.Build()
  if Dialog.frame then return Dialog.frame end
  local f = CreateFrame("Frame", "HogTronUIDialog", UIParent)
  f:SetSize(cfg().width or 540, 400)
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
  f.pageTop = f:CreateTexture(nil, "BACKGROUND")
  f.pageMid = f:CreateTexture(nil, "BACKGROUND")
  f.pageBot = f:CreateTexture(nil, "BACKGROUND")
  f.portrait = f:CreateTexture(nil, "ARTWORK")
  f.ring = f:CreateTexture(nil, "OVERLAY")
  f.ring:SetTexture(ART.ring)
  f.title = fs(f, "HogTronFontNormalLarge")
  f.rule = f:CreateTexture(nil, "ARTWORK")
  f.rule:SetTexture(ART.rule)
  f.npc = fs(f, "HogTronFontSmall")
  f.body = fs(f)
  f.objTag = tag(f)
  f.objectives = fs(f)
  f.reqTag = tag(f)
  f.rewTag = tag(f)
  f.xp = fs(f)
  f.money = fs(f)
  f.chooseCap = fs(f)
  f.alsoCap = fs(f)
  f.hint = fs(f, "HogTronFontSmall")
  f.primary = button(f, "HogTronUIDialogPrimary")
  f.primary:SetScript("OnClick", function()
    local m = Dialog.model
    if m and m.primary and not m.primary.disabled and Dialog.frame:IsShown() then Dialog.Do(m.primary.action) end
  end)
  f.secondary = button(f, "HogTronUIDialogSecondary")
  f.secondary:SetScript("OnClick", function()
    local m = Dialog.model
    if m and m.secondary then
      Dialog.Do(m.secondary.action)
      Dialog.Hide()
    end
  end)
  f:SetScript("OnHide", function() Dialog.OnHide() end)
  local special = rawget(_G, "UISpecialFrames")
  if type(special) == "table" then special[#special + 1] = "HogTronUIDialog" end
  f:Hide()
  Dialog.frame = f
  return f
end

--- One pooled clickable row. mode "tile" = an item (icon, name, count) in the two-column reward grid; "row" = a
-- full-width gossip / greeting line (key cap, quest mark or gossip icon, text).
local function rowButton(i)
  local r = Dialog.rows[i]
  if r then return r end
  local f = Dialog.frame
  r = CreateFrame("Button", "HogTronUIDialogRow" .. i, f)
  r.bg = slab(r, "BACKGROUND", ART.round)
  r.sel = slab(r, "BORDER", ART.line)
  r.iconEdge = r:CreateTexture(nil, "ARTWORK")
  r.iconEdge:SetTexture(FLAT)
  r.icon = r:CreateTexture(nil, "ARTWORK", nil, 1)
  r.glyph = fs(r, "HogTronFontNormal")
  if r.glyph.SetJustifyH then r.glyph:SetJustifyH("CENTER") end
  r.count = fs(r, "HogTronFontSmall")
  r.text = fs(r)
  if r.text.SetJustifyV then r.text:SetJustifyV("MIDDLE") end
  r.key = keycap(r)
  r.num = r.key.text
  r:SetScript("OnClick", function(self) if self.pick then Dialog.Pick(self.pick) end end)
  r:SetScript("OnEnter", function(self)
    local tip = rawget(_G, "GameTooltip")
    if self.item and type(tip) == "table" and fn(tip, "SetQuestItem") and not (Dialog.model and Dialog.model.preview) then
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
  q = num(q)
  if not q then return nil end
  if Dialog.Theme().paper then return Dialog.PAPER_QUALITY[q] end
  local C = rawget(_G, "C_Item")
  local r, gg, b = call(fn(C, "GetItemQualityColor"), q)
  if not num(r) then r, gg, b = call(g("GetItemQualityColor"), q) end
  if num(r) and num(gg) and num(b) then return { r, gg, b } end
end

function Dialog.PaintRow(r)
  local th = Dialog.Theme()
  local sel = r.choose and Dialog.choice == r.choose
  local w, h = r:GetWidth() or 0, r:GetHeight() or 0
  r.bg:Place(r, 0, 0, w, h)
  r.sel:Place(r, 0, 0, w, h)
  if sel then
    r.bg:Color(th.pick, 0.22) r.sel:Color(th.pick, 0.95) r.sel:Show()
  else
    r.bg:Color((r.hover and r.pick) and th.hover or th.tile)
    r.sel:Hide()
  end
  r.bg:Show()
end

local function measure(f, text, width, size)
  local h = f.GetStringHeight and num(call(f.GetStringHeight, f))
  if not h or h <= 0 then h = Dialog.EstimateHeight(text, width, size) end
  return h
end

local function placeText(f, text, size, x, y, width, color)
  if not text or text == "" then f:Hide() return y end
  setFont(f, size)
  if f.SetSpacing then f:SetSpacing(math.floor(size * 0.25)) end
  f:SetWidth(width)
  if f.SetWordWrap then f:SetWordWrap(true) end
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", Dialog.frame, "TOPLEFT", x, y)
  f:SetText(text)
  f:SetTextColor(color[1], color[2], color[3])
  f:Show()
  return y - measure(f, text, width, size)
end

local function placeTag(t, label, size, x, y)
  local th = Dialog.Theme()
  setFont(t.text, size)
  t.text:SetText(label)
  t.text:SetTextColor(th.text[1], th.text[2], th.text[3])
  t.text:ClearAllPoints()
  t.text:SetPoint("LEFT", Dialog.frame, "TOPLEFT", x + 8, y - (size + 9) / 2)
  t.text:Show()
  local w = num(call(t.text.GetStringWidth, t.text))
  if not w or w <= 0 then w = #label * size * 0.55 end
  t.bg:Place(Dialog.frame, x, y, w + 16, size + 9)
  t.bg:Color(th.tag)
  t.bg:Show()
  return y - (size + 9)
end

local function hideTag(t) t.bg:Hide() t.text:Hide() end

local function placePage(f, w, h)
  local file = ART.page[Dialog.ThemeKey()]
  local s = w / PAGE_W
  local cap = SLICE * s
  local cut = SLICE / PAGE_H
  for _, t in ipairs({ f.pageTop, f.pageMid, f.pageBot }) do t:SetTexture(file) t:ClearAllPoints() t:Show() end
  f.pageTop:SetTexCoord(0, 1, 0, cut)
  f.pageTop:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0) f.pageTop:SetSize(w, cap)
  -- the middle is CROPPED to the height it needs (a short page squashed 700 px of paper into a sliver = streaks);
  -- only a page taller than the texture stretches it. The art's side edges carry no slow waves, so the crop is seamless.
  local midH = math.max(0.01, h - 2 * cap)
  local px = math.min(PAGE_H - 2 * SLICE, math.ceil((midH / s) / EDGE_PERIOD) * EDGE_PERIOD)   -- whole edge periods
  local want = px / PAGE_H
  f.pageMid:SetTexCoord(0, 1, cut, cut + want)
  f.pageMid:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -cap) f.pageMid:SetSize(w, math.max(0.01, h - 2 * cap))
  f.pageBot:SetTexCoord(0, 1, 1 - cut, 1)
  f.pageBot:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(h - cap)) f.pageBot:SetSize(w, cap)
  return 2 * cap
end

local function portrait(f, m)
  local ok = false
  local set = g("SetPortraitTexture")
  if set and not m.preview then ok = pcall(set, f.portrait, "npc") end
  if not ok and set then ok = pcall(set, f.portrait, "player") end
  if not ok then f.portrait:SetTexture("Interface\\Icons\\INV_Misc_Book_09") end
end

--- Lay the current page out top to bottom on the parchment. The page grows with the text.
function Dialog.Render()
  local m, f = Dialog.model, Dialog.Build()
  if not m then return end
  local o, th = cfg(), Dialog.Theme()
  local W = o.width or 540
  local s = W / PAGE_W
  local size = o.fontSize or 14
  local PADX, TOP = math.floor(46 * s + 0.5), math.floor(44 * s + 0.5)
  local BOTTOM = math.floor((Dialog.TEAR + Dialog.BUTTON_CLEAR) * s + 0.5)
  local inner = W - 2 * PADX
  f:SetWidth(W)
  if f.SetScale then f:SetScale(o.scale or 1) end
  f:SetAlpha(o.alpha or 1)
  local y = -TOP
  -- header: portrait in its ring, the title beside it, the rule under the title
  local P, RING = 50, 64
  portrait(f, m)
  f.portrait:ClearAllPoints()
  f.portrait:SetPoint("TOPLEFT", f, "TOPLEFT", PADX + (RING - P) / 2, y - (RING - P) / 2)
  f.portrait:SetSize(P, P)
  f.portrait:Show()
  f.ring:ClearAllPoints()
  f.ring:SetPoint("TOPLEFT", f, "TOPLEFT", PADX, y)
  f.ring:SetSize(RING, RING)
  f.ring:Show()
  local tx = PADX + RING + 10
  local titleBottom = placeText(f.title, m.title ~= "" and m.title or (m.npc or ""), size + 6, tx, y - 14, inner - RING - 10, th.title)
  local ruleY = math.min(titleBottom - 6, y - RING / 2 - 4)
  f.rule:ClearAllPoints()
  f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", tx - 2, ruleY + 3)
  f.rule:SetSize(inner - RING - 8, 6)
  rgba(f.rule, th.rule, 0.9)
  f.rule:Show()
  y = math.min(ruleY, y - RING) - 14
  if o.npcName == true and m.npc and m.npc ~= "" and m.npc ~= m.title then
    y = placeText(f.npc, m.npc, size - 2, PADX, y, inner, th.muted) - 8
  else f.npc:Hide() end
  -- the text
  y = placeText(f.body, m.body, size, PADX, y, inner, th.text) - 18
  -- objectives
  if m.objectives and m.objectives ~= "" then
    y = placeTag(f.objTag, "Objectives", size - 1, PADX - 8, y) - 8
    y = placeText(f.objectives, m.objectives, size, PADX, y, inner, th.text) - 14
  else hideTag(f.objTag) f.objectives:Hide() end
  -- rows: reward tiles (two columns) and gossip / greeting lines (full width)
  m.picks = {}
  local used = 0
  local function tiles(list, y0, actionable)
    local tw, thh, gap = math.floor((inner - 8) / 2), 44, 8
    for k, d in ipairs(list) do
      used = used + 1
      local r = rowButton(used)
      local col, line = (k - 1) % 2, math.floor((k - 1) / 2)
      r.mode, r.item, r.pick, r.choose, r.hover = "tile", d.item, nil, nil, false
      if actionable and d.act then
        m.picks[#m.picks + 1] = d
        r.pick = #m.picks
        r.choose = d.act[1] == "choose" and d.act[2] or nil
      end
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", f, "TOPLEFT", PADX + col * (tw + gap), y0 - line * (thh + 6))
      r:SetSize(tw, thh)
      local it = d.item or {}
      local qc = qualityColor(it.quality)
      r.iconEdge:ClearAllPoints() r.iconEdge:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -4) r.iconEdge:SetSize(36, 36)
      local edgeC = qc or th.muted
      r.iconEdge:SetVertexColor(edgeC[1], edgeC[2], edgeC[3], 0.9) r.iconEdge:Show()
      r.icon:ClearAllPoints() r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 5, -5) r.icon:SetSize(34, 34)
      r.icon:SetTexture(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark") r.icon:Show()
      if r.icon.SetDesaturated then r.icon:SetDesaturated(false) end   -- the row may have shown a greyed quest seal
      if r.icon.SetTexCoord then r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
      r.glyph:Hide()
      setFont(r.count, 11)
      r.count:ClearAllPoints() r.count:SetPoint("BOTTOMRIGHT", r, "TOPLEFT", 38, -38)
      if (it.count or 1) > 1 then r.count:SetText(tostring(it.count)) r.count:SetTextColor(1, 1, 1) r.count:Show() else r.count:Hide() end
      setFont(r.text, size - 1)
      r.text:ClearAllPoints()
      r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 46, -4)
      -- the name stops 8 px short of the number chip (Sean 2026-10-17: "Highlands Defender's" ran into its "2")
      local keyX = tw - 24
      r.text:SetSize((r.pick and (keyX - 8) or (tw - 8)) - 46, thh - 8)
      r.text:SetText(it.name or d.text or "")
      local c = qc or th.text
      r.text:SetTextColor(c[1], c[2], c[3])
      r.text:Show()
      r.key:Set(r.pick and r.pick <= 9 and tostring(r.pick) or nil, keyX, -4, 10)
      Dialog.PaintRow(r)
      r:Show()
    end
    return y0 - math.ceil(#list / 2) * (thh + 6)
  end
  if #m.required > 0 then
    y = placeTag(f.reqTag, "Required items", size - 1, PADX - 8, y) - 8
    local req = {}
    for _, it in ipairs(m.required) do req[#req + 1] = { item = it } end
    y = tiles(req, y, false) - 8
  else hideTag(f.reqTag) end
  local xpLine = Dialog.XPLine(m.xp, m.xpShare)
  if xpLine then xpLine = Dialog.Icon(Dialog.XP_ICON, size) .. " " .. xpLine end
  local cash = money(m.money, size)
  local choosing = #m.choices > 1
  if xpLine or cash or #m.rewards > 0 or #m.choices > 0 then
    y = placeTag(f.rewTag, "Rewards", size - 1, PADX - 8, y) - 8
    if choosing then
      y = placeText(f.chooseCap, "Choose one of these rewards:", size - 1, PADX, y, inner, th.muted) - 6
      local list = {}
      if m.kind == "complete" then list = m.rows else for _, it in ipairs(m.choices) do list[#list + 1] = { item = it } end end
      y = tiles(list, y, m.kind == "complete") - 4
    else f.chooseCap:Hide() end
    local plain = {}
    for _, it in ipairs(m.rewards) do plain[#plain + 1] = { item = it } end
    if not choosing then for _, it in ipairs(m.choices) do plain[#plain + 1] = { item = it } end end
    if #plain > 0 then
      y = placeText(f.alsoCap, choosing and "You will also receive:" or "You will receive:", size - 1, PADX, y, inner, th.muted) - 6
      y = tiles(plain, y, false) - 4
    else f.alsoCap:Hide() end
    y = placeText(f.xp, xpLine, size, PADX, y - 2, inner, th.text) - 4
    y = placeText(f.money, cash, size, PADX, y, inner, th.text) - 10
  else
    hideTag(f.rewTag) f.chooseCap:Hide() f.alsoCap:Hide() f.xp:Hide() f.money:Hide()
  end
  -- gossip / greeting lines
  if m.kind == "gossip" or m.kind == "greeting" then
    for _, d in ipairs(m.rows) do
      used = used + 1
      local r = rowButton(used)
      r.mode, r.item, r.choose, r.hover = "row", nil, nil, false
      m.picks[#m.picks + 1] = d
      r.pick = #m.picks
      setFont(r.text, size)
      local textW = inner - 64
      local h = math.max(32, Dialog.EstimateHeight(d.text or "", textW, size) + 12)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", f, "TOPLEFT", PADX, y)
      r:SetSize(inner, h)
      r.key:Set(r.pick <= 9 and tostring(r.pick) or nil, 8, -(h - 18) / 2, 10)
      r.iconEdge:Hide() r.count:Hide()
      r.icon:ClearAllPoints() r.icon:SetPoint("LEFT", r, "LEFT", 32, 0) r.icon:SetSize(20, 20)
      if r.icon.SetTexCoord then r.icon:SetTexCoord(0, 1, 0, 1) end
      local shown = d.icon ~= nil and call(r.icon.SetTexture, r.icon, d.icon) ~= false
      if r.icon.SetDesaturated then r.icon:SetDesaturated(d.dim == true) end   -- a low-level quest's seal goes grey
      if shown then r.icon:Show() r.glyph:Hide()
      else
        r.icon:Hide()
        setFont(r.glyph, size + 2)
        r.glyph:ClearAllPoints() r.glyph:SetPoint("CENTER", r, "LEFT", 42, 0)
        r.glyph:SetText(d.glyph or ">")
        local c = d.tone == "quest" and th.quest or d.tone == "muted" and th.muted or th.text
        r.glyph:SetTextColor(c[1], c[2], c[3]) r.glyph:Show()
      end
      r.text:ClearAllPoints()
      r.text:SetPoint("LEFT", r, "LEFT", 58, 0)
      r.text:SetSize(textW, h - 6)
      r.text:SetText(d.text or "")
      local c = d.tone == "muted" and th.muted or th.text
      r.text:SetTextColor(c[1], c[2], c[3])
      r.text:Show()
      Dialog.PaintRow(r)
      r:Show()
      y = y - h - 4
    end
    y = y - 8
  end
  for i = used + 1, #Dialog.rows do Dialog.rows[i]:Hide() end
  if m.pickHint and not Dialog.choice then
    y = placeText(f.hint, m.pickHint, size - 2, PADX, y, inner, th.muted) - 8
  else f.hint:Hide() end
  -- buttons: the main one left, the way out right (Dialogue UI's order), key caps inside
  y = y - 4
  local bw, bh = math.floor((inner - 12) / 2), 36
  f.primary:ClearAllPoints()
  f.secondary:ClearAllPoints()
  f.primary:SetPoint("TOPLEFT", f, "TOPLEFT", PADX, y)
  f.secondary:SetPoint("TOPLEFT", f, "TOPLEFT", PADX + bw + 12, y)
  for _, pair in ipairs({ { f.primary, m.primary }, { f.secondary, m.secondary } }) do
    local b, spec = pair[1], pair[2]
    b:SetSize(bw, bh)
    b.spec = spec
    if spec then Dialog.PaintButton(b) b:Show() else b:Hide() end
  end
  y = y - bh - BOTTOM
  local h = math.max(math.floor(-y + 0.5), 0)
  local minH = math.floor(2 * SLICE * s + 0.5)
  if h < minH then h = minH end
  placePage(f, W, h)
  f:SetHeight(h)
  Dialog.height = h
end

function Dialog.PaintButton(b)
  local spec, th = b.spec, Dialog.Theme()
  if not spec then return end
  local w, h = b:GetWidth() or 200, b:GetHeight() or 36
  b.bg:Place(b, 0, 0, w, h)
  b.line:Place(b, 0, 0, w, h)
  local keyLabel = cfg().keys ~= false and spec.key or nil
  local kw = b.key:Set(keyLabel, 10, -(h - 18) / 2, 10)
  setFont(b.label, (cfg().fontSize or 14))
  b.label:SetText(spec.label)
  b.label:ClearAllPoints()
  b.label:SetPoint("CENTER", b, "CENTER", kw > 0 and (kw / 2 + 4) or 0, 0)
  if spec.disabled then
    b.bg:Hide()
    b.line:Color(th.outline) b.line:Show()
    b.label:SetTextColor(th.muted[1], th.muted[2], th.muted[3])
    if b.key.bg.shown then b.key.bg:Color(th.key, 0.35) end
  else
    b.line:Hide()
    local c = th.button
    b.bg:Color(c, b.hover and math.min(1, (c[4] or 1)) or (c[4] or 1) * 0.92) b.bg:Show()
    if b.hover then b.bg:Color({ math.min(1, c[1] + 0.06), math.min(1, c[2] + 0.06), math.min(1, c[3] + 0.06) }, c[4] or 1) end
    b.label:SetTextColor(th.buttonText[1], th.buttonText[2], th.buttonText[3])
  end
  if b.SetEnabled then b:SetEnabled(not spec.disabled) end
  b.label:Show()
end

function Dialog.Place()
  local f, o = Dialog.Build(), cfg()
  f:ClearAllPoints()
  f:SetPoint(o.point or "CENTER", UIParent, o.point or "CENTER", o.x or -260, o.y or 40)
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

--- A sample page to see the look without an NPC (options button, /hh dialog preview [reward]). Buttons only close it.
-- Item icons come from what you are wearing (GetInventoryItemTexture: hands, chest, legs) - real client art, never
-- an icon name typed from memory; an empty slot falls back to the client's question-mark icon.
function Dialog.Preview(kind)
  kind = kind == "complete" and "complete" or "detail"
  local function worn(slot) return call(g("GetInventoryItemTexture"), "player", slot) end
  local choices = {
    { name = "Brawler's Gloves", count = 1, quality = 2, kind = "choice", index = 1, icon = worn(10) },
    { name = "Woodland Tunic", count = 1, quality = 2, kind = "choice", index = 2, icon = worn(5) },
    { name = "Light Leather Pants", count = 1, quality = 1, kind = "choice", index = 3, icon = worn(7) },
  }
  local who = str(call(g("UnitName"), "player")) or "adventurer"
  local m = {
    kind = kind, preview = true, npc = "Marshal Dughan", title = "Wolves Across the Border",
    xp = 1250, money = 750, rows = {}, required = {}, rewards = {}, choices = choices,
  }
  if kind == "complete" then
    m.body = "Well done, " .. who .. ". Those wolves have harried the farms of Northshire for too long.\n\nTake one of these - the town can spare it."
    m.primary = { label = "Complete Quest", action = "reward", key = "Space", disabled = true }
    m.secondary = { label = "Cancel", action = "closeQuest", key = "Esc" }
    m.pickHint = "Pick a reward: click it or press its number."
    for i, c in ipairs(choices) do m.rows[#m.rows + 1] = { text = c.name, item = c, act = { "choose", i } } end
  else
    m.body = "The wolves have grown bold, " .. who .. ". They come down from the hills at night and take what they please from the Stonefield and Maclure farms.\n\nBring me the meat of the Prowlers and Young Wolves you find along the border, and Northshire will rest easier."
    m.objectives = "- 0/8 Tough Wolf Meat"
    m.primary = { label = "Accept", action = "accept", key = "Space" }
    m.secondary = { label = "Decline", action = "decline", key = "Esc" }
  end
  m.xpShare = Dialog.XPShare(m.xp, num(call(g("UnitXPMax"), "player")) or 8800)
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
    o.theme = (w == "ink" or w == "dark") and "dark" or "light"
    Dialog.Refresh()
    HH:Print("dialog theme: " .. Dialog.THEME_NAMES[o.theme])
    return
  end
  if w == "preview" then Dialog.Preview((rest or ""):lower():find("reward") and "complete" or "detail") return end
  if w == "reset" then o.point, o.x, o.y = nil, nil, nil if Dialog.frame and Dialog.frame:IsShown() then Dialog.Place() end HH:Print("dialog: position reset") return end
  for _, l in ipairs(Dialog.Lines()) do HH:Print(l) end
  HH:Print("usage: /hh dialog on|off  -  light|dark  -  preview [reward]  -  reset")
end, "quest dialog window: on / off, light / dark, preview [reward], reset position")
