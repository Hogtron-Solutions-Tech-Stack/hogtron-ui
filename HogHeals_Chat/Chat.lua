-- HogHeals chat: Blizzard's chat windows in the HogHeals panel language (ink body, 1 px outline, cyan accent).
--
-- We restyle Blizzard's frames, never replace them: every chat setting, tab, whisper window and /command keeps
-- working, and a client update that renames one piece costs us that piece, not the chat.
--   window    Blizzard's backdrop textures cleared (SetTexture(nil), so their own fade/colour code has nothing to
--             show), our always-on panel behind the text instead
--   tabs      flat: Blizzard's tab art cleared, text cream, the selected tab cyan with a 1 px cyan underline
--   edit box  flat ink bar with a cyan top rule
--   text      optional size / outline, short channel names ([1. General - Tirisfal Glades] -> [1], [Guild] -> [G]),
--             player names in class colours
-- Chat messages can be SECRET on restricted clients: Shorten never touches a secret message, it passes it through.
HogHealsChat = HogHealsChat or {}
local HHC = HogHealsChat
local HH = HogHeals

local Chat = { styled = {} }
HHC.Chat = Chat

local CREAM = { 0.96, 0.92, 0.86 }
local CYAN = { 0.13, 0.83, 0.88 }
local INK = { 0.07, 0.07, 0.09 }
local LINE = { 0.20, 0.20, 0.25 }

local function cfg() return HH.db.profile.chat end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c = pcall(f, ...)
  if ok then return a, b, c end
end

-- ------------------------------------------------------------------------------------------------ text
Chat.SHORT = {
  Guild = "G", Officer = "O", Party = "P", ["Party Leader"] = "PL", Raid = "R", ["Raid Leader"] = "RL",
  ["Raid Warning"] = "RW", Instance = "I", ["Instance Leader"] = "IL",
}

--- "[1. General - Tirisfal Glades]" -> "[1]", "[Guild]" -> "[G]". Only inside a |Hchannel: link (or a bare
-- "[N. Name]" at the very start of a line), so a player called "Guild" or an item link is never touched.
function Chat.Shorten(msg)
  if type(msg) ~= "string" or isSecret(msg) then return msg end
  local out, n = msg:gsub("(|Hchannel:[^|]*|h)%[(%d+)%. [^%]]-%]|h", "%1[%2]|h", 1)
  if n == 0 then out, n = msg:gsub("^%[(%d+)%. [^%]]-%]", "[%1]", 1) end
  if n == 0 then
    out = msg:gsub("(|Hchannel:[^|]*|h)%[([^%]]+)%]|h", function(link, name)
      local s = Chat.SHORT[name]
      if s then return link .. "[" .. s .. "]|h" end
    end, 1)
  end
  return out
end

local function isCombatLog(cf)
  return cf == rawget(_G, "COMBATLOG") or (cf.GetName and cf:GetName() == "ChatFrame2")
end

-- ------------------------------------------------------------------------------------------------ pieces
local function solid(parent, layer, c, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  return t
end

local function outline(parent, anchor, pad)
  local edges = {}
  local spec = { { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }
  for i, sp in ipairs(spec) do
    local e = solid(parent, "BORDER", LINE)
    e:SetPoint(sp[1], anchor, sp[1], 0, 0)
    e:SetPoint(sp[2], anchor, sp[2], 0, 0)
    if sp[3] then e:SetWidth(sp[3]) end
    if sp[4] then e:SetHeight(sp[4]) end
    edges[i] = e
  end
  return edges
end

--- Clear every texture region of a Blizzard frame (tab / edit box art). Font strings and child frames are kept.
local function clearArt(frame)
  if not frame or not frame.GetRegions then return 0 end
  local n = 0
  for _, r in ipairs({ frame:GetRegions() }) do
    if r and r.GetObjectType and r:GetObjectType() == "Texture" and not r.hhOurs then
      call(r.SetTexture, r, nil)
      call(r.SetAlpha, r, 0)
      n = n + 1
    end
  end
  return n
end

local BACKDROP = { "Background", "TopLeftTexture", "TopRightTexture", "BottomLeftTexture", "BottomRightTexture",
  "TopTexture", "BottomTexture", "LeftTexture", "RightTexture" }

local function styleWindow(cf, s)
  local name = cf:GetName()
  for _, suffix in ipairs(rawget(_G, "CHAT_FRAME_TEXTURES") or BACKDROP) do
    local t = _G[name .. suffix]
    if t then call(t.SetTexture, t, nil) end
  end
  if not s.panel then
    local p = CreateFrame("Frame", nil, cf)
    p:SetPoint("TOPLEFT", cf, "TOPLEFT", -5, 5)
    p:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 5, -5)
    p:SetFrameLevel(math.max(0, ((cf.GetFrameLevel and cf:GetFrameLevel()) or 1) - 1))
    p.bg = solid(p, "BACKGROUND", INK, 0.6)
    p.bg.hhOurs = true
    p.bg:SetAllPoints(p)
    p.edges = outline(p, p)
    s.panel = p
  end
  s.panel.bg:SetColorTexture(INK[1], INK[2], INK[3], cfg().backgroundAlpha or 0.6)
end

local function styleTab(cf, s)
  local tab = _G[cf:GetName() .. "Tab"]
  if not tab then return end
  clearArt(tab)
  if not s.rule then
    s.rule = tab:CreateTexture(nil, "OVERLAY")
    s.rule.hhOurs = true
    s.rule:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 1)
    s.rule:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 6, 2)
    s.rule:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -6, 2)
    s.rule:SetHeight(1)
  end
  s.tab = tab
end

local function styleEditBox(cf, s)
  local eb = _G[cf:GetName() .. "EditBox"]
  if not eb then return end
  clearArt(eb)
  if not s.eb then
    local bg = eb:CreateTexture(nil, "BACKGROUND")
    bg.hhOurs = true
    bg:SetPoint("TOPLEFT", eb, "TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", -2, 2)
    bg:SetColorTexture(INK[1], INK[2], INK[3], 0.9)
    local rule = eb:CreateTexture(nil, "BORDER")
    rule.hhOurs = true
    rule:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 1)
    rule:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
    rule:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 0, 0)
    rule:SetHeight(1)
    s.eb = { frame = eb, bg = bg, rule = rule }
  end
end

local function hideForever(f)
  if not f or f.hhHidden then return end
  f.hhHidden = true
  call(f.Hide, f)
  if type(hooksecurefunc) == "function" and f.Show then
    pcall(hooksecurefunc, f, "Show", function(self) if cfg().enabled ~= false and self.hhHidden then self:Hide() end end)
  end
end

local function applyFont(cf)
  local d = cfg()
  if not d.fontSize and not d.outline then return end
  local font, size = cf:GetFont()
  if not font then return end
  call(cf.SetFont, cf, font, d.fontSize or size, d.outline and "OUTLINE" or "")
  local eb = _G[cf:GetName() .. "EditBox"]
  if eb and eb.GetFont and eb.SetFont then
    local ef = eb:GetFont()
    if ef then call(eb.SetFont, eb, ef, d.fontSize or size, "") end
  end
end

local function hookMessages(cf, s)
  if s.hooked or isCombatLog(cf) or type(cf.AddMessage) ~= "function" then return end
  local orig = cf.AddMessage
  s.hooked = true
  cf.AddMessage = function(self, msg, ...)
    if cfg().shortChannels ~= false then
      local ok, m = pcall(Chat.Shorten, msg)
      if ok then msg = m end
    end
    return orig(self, msg, ...)
  end
end

-- ------------------------------------------------------------------------------------------------ tabs state
local function selectedFrame()
  local dock = rawget(_G, "GENERAL_CHAT_DOCK")
  if dock and type(FCFDock_GetSelectedWindow) == "function" then
    local f = call(FCFDock_GetSelectedWindow, dock)
    if f then return f end
  end
  return rawget(_G, "SELECTED_CHAT_FRAME")
end

--- Cyan text + underline on the selected tab, cream on the rest. Re-run after Blizzard recolours tabs.
function Chat.UpdateTabs()
  local sel = selectedFrame()
  local size = cfg().fontSize
  for cf, s in pairs(Chat.styled) do
    local tab = s.tab
    if tab then
      local fs = tab.Text or _G[tab:GetName() .. "Text"] or (tab.GetFontString and tab:GetFontString())
      local on = (cf == sel)
      if fs then
        local c = on and CYAN or CREAM
        call(fs.SetTextColor, fs, c[1], c[2], c[3])
        if size and fs.GetFont then
          local font = fs:GetFont()
          if font then call(fs.SetFont, fs, font, math.max(9, size - 1), "") end
        end
      end
      if on then s.rule:Show() else s.rule:Hide() end
    end
  end
end

-- ------------------------------------------------------------------------------------------------ class colours
local CHAT_TYPES = { "SAY", "YELL", "EMOTE", "WHISPER", "WHISPER_INFORM", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER",
  "RAID_WARNING", "GUILD", "OFFICER", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "CHANNEL", "CHANNEL1", "CHANNEL2",
  "CHANNEL3", "CHANNEL4", "CHANNEL5", "CHANNEL6", "CHANNEL7", "CHANNEL8", "CHANNEL9", "CHANNEL10" }

function Chat.ApplyClassNames()
  if cfg().classNames == false then return 0 end
  local set = rawget(_G, "SetChatColorNameByClass")
  local n = 0
  if type(set) == "function" then
    for _, t in ipairs(CHAT_TYPES) do if pcall(set, t, true) then n = n + 1 end end
  else
    -- older clients keep the flag on ChatTypeInfo
    local info = rawget(_G, "ChatTypeInfo")
    if type(info) == "table" then
      for _, t in ipairs(CHAT_TYPES) do if type(info[t]) == "table" then info[t].colorNameByClass = true n = n + 1 end end
    end
  end
  return n
end

-- ------------------------------------------------------------------------------------------------ all windows
function Chat.Frames()
  local out = {}
  for i = 1, (rawget(_G, "NUM_CHAT_WINDOWS") or 10) do
    local cf = _G["ChatFrame" .. i]
    if type(cf) == "table" and cf.GetName then out[#out + 1] = cf end
  end
  return out
end

function Chat.Style(cf)
  local s = Chat.styled[cf] or {}
  Chat.styled[cf] = s
  styleWindow(cf, s)
  styleTab(cf, s)
  styleEditBox(cf, s)
  applyFont(cf)
  hookMessages(cf, s)
  if cf.SetFading then call(cf.SetFading, cf, cfg().fade ~= false) end
  local d = cfg()
  if d.hideButtons ~= false then hideForever(_G[cf:GetName() .. "ButtonFrame"]) end
end

function Chat.StyleAll()
  if cfg().enabled == false then return end
  for _, cf in ipairs(Chat.Frames()) do
    local ok, err = xpcall(Chat.Style, HH.Trace, cf)
    if not ok then HH:LogError("chat style " .. tostring(cf:GetName()) .. ": " .. tostring(err)) end
  end
  if cfg().hideMenuButtons then
    for _, n in ipairs({ "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton", "FriendsMicroButton" }) do
      hideForever(_G[n])
    end
  end
  Chat.UpdateTabs()
end

function Chat.Refresh()
  Chat.StyleAll()
  Chat.ApplyClassNames()
end

local Module = {}
HHC.module = Module

function Module:OnEnable()
  if cfg().enabled == false then return end
  Chat.StyleAll()
  Chat.ApplyClassNames()
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS", "PLAYER_ENTERING_WORLD" }) do pcall(ev.RegisterEvent, ev, e) end
  ev:SetScript("OnEvent", function() Chat.StyleAll() end)
  Module.events = ev
  -- Blizzard recolours tabs and opens new windows on its own; follow it
  if type(hooksecurefunc) == "function" then
    for _, fn in ipairs({ "FCF_Tab_OnClick", "FCFDock_SelectWindow", "FCFTab_UpdateColors", "FCF_FadeInChatFrame", "FCF_FadeOutChatFrame" }) do
      if type(rawget(_G, fn)) == "function" then pcall(hooksecurefunc, fn, function() pcall(Chat.UpdateTabs) end) end
    end
    for _, fn in ipairs({ "FCF_OpenTemporaryWindow", "FCF_OpenNewWindow", "FCF_DockFrame", "FCF_SetChatWindowFontSize" }) do
      if type(rawget(_G, fn)) == "function" then pcall(hooksecurefunc, fn, function() pcall(Chat.StyleAll) end) end
    end
  end
end

function Module:OnProfileChanged() Chat.Refresh() end

function Module:GetOptions()
  if HHC.Options and HHC.Options.Build then return HHC.Options.Build() end
end

HH:RegisterModule("Chat", Module)
