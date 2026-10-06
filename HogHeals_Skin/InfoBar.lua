-- Info bar: a slim HogTron UI strip of "datatexts" (ElvUI's word) - gold, durability, bag space, fps, latency, clock,
-- coordinates, friends, guild, experience. Each slot is a click target (bags open the bags, gold too, durability
-- the character sheet, clock the calendar, friends / guild their frames, coordinates the map).
local HHS = HogHealsSkin
local Skin = HHS.Skin
local HH = HogHeals

local Bar = { slots = {} }
HHS.InfoBar = Bar
local call, num = Skin.call, Skin.num

local function cfg() return Skin.cfg().infoBar end
local function color(hex, s) return "|cff" .. hex .. s .. "|r" end

-- ------------------------------------------------------------------------------------------------ providers
Bar.providers = {}
local P = Bar.providers

P.gold = { label = "Gold",
  value = function()
    local m = num(call(GetMoney))
    if not m then return "-" end
    local g, s, c = math.floor(m / 10000), math.floor(m / 100) % 100, m % 100
    if g > 0 then return color("ffd700", g .. "g") .. " " .. color("c7c7cf", s .. "s") end
    if s > 0 then return color("c7c7cf", s .. "s") .. " " .. color("eda55f", c .. "c") end
    return color("eda55f", c .. "c")
  end,
  click = function() call(rawget(_G, "ToggleAllBags")) end }

P.durability = { label = "Durability",
  value = function()
    local f = rawget(_G, "GetInventoryItemDurability")
    if type(f) ~= "function" then return "-" end
    local worst
    for slot = 1, 18 do
      local cur, max = call(f, slot)
      cur, max = num(cur), num(max)
      if cur and max and max > 0 then
        local pct = cur / max * 100
        if not worst or pct < worst then worst = pct end
      end
    end
    if not worst then return "-" end
    local hex = worst < 25 and "d93636" or worst < 50 and "f2a626" or "F5EBDC"
    return color(hex, ("%.0f%%"):format(worst)) .. " dur"
  end,
  click = function() call(rawget(_G, "ToggleCharacter"), "PaperDollFrame") end }

P.bags = { label = "Bag space",
  value = function()
    local free, total = 0, 0
    local nFree = (type(C_Container) == "table" and C_Container.GetContainerNumFreeSlots) or rawget(_G, "GetContainerNumFreeSlots")
    local nSlots = (type(C_Container) == "table" and C_Container.GetContainerNumSlots) or rawget(_G, "GetContainerNumSlots")
    if type(nFree) ~= "function" or type(nSlots) ~= "function" then return "-" end
    for bag = 0, (rawget(_G, "NUM_BAG_SLOTS") or 4) do
      local fr, sl = num(call(nFree, bag)), num(call(nSlots, bag))
      if fr and sl then free, total = free + fr, total + sl end
    end
    local hex = free <= 2 and "d93636" or free <= 6 and "f2a626" or "F5EBDC"
    return color(hex, tostring(free)) .. " / " .. total .. " bags"
  end,
  click = function() call(rawget(_G, "ToggleAllBags")) end }

P.fps = { label = "FPS",
  value = function()
    local f = num(call(GetFramerate))
    if not f then return "-" end
    local hex = f < 30 and "d93636" or f < 50 and "f2a626" or "F5EBDC"
    return color(hex, ("%.0f"):format(f)) .. " fps"
  end }

P.latency = { label = "Latency",
  value = function()
    local _, _, home, world = call(GetNetStats)
    home, world = num(home), num(world)
    if not world then return "-" end
    local hex = world > 300 and "d93636" or world > 150 and "f2a626" or "F5EBDC"
    return color(hex, ("%d"):format(world)) .. " ms"
  end,
  tooltip = function(tt)
    local _, _, home, world = call(GetNetStats)
    tt:AddLine("Latency")
    tt:AddLine(("Home: %s ms   World: %s ms"):format(tostring(num(home) or "?"), tostring(num(world) or "?")), 0.96, 0.92, 0.86)
  end }

P.time = { label = "Clock",
  value = function()
    local d = cfg()
    if d.serverTime and type(GetGameTime) == "function" then
      local h, m = call(GetGameTime)
      h, m = num(h), num(m)
      if h and m then
        if d.time24 then return ("%02d:%02d"):format(h, m) end
        local ap = h >= 12 and "pm" or "am"
        return ("%d:%02d %s"):format(((h + 11) % 12) + 1, m, ap)
      end
    end
    local dateFn = rawget(_G, "date") or (type(os) == "table" and os.date) or nil   -- the client has `date`; the test harness has os.date
    if type(dateFn) ~= "function" then return "-" end
    return d.time24 and dateFn("%H:%M") or (dateFn("%I:%M %p"):gsub("^0", ""))
  end,
  click = function()
    local f = rawget(_G, "ToggleCalendar")
    if type(f) == "function" then call(f) else call(rawget(_G, "ToggleTimeManager")) end
  end }

P.coords = { label = "Coordinates",
  value = function()
    if type(C_Map) ~= "table" then return "-" end
    local mapID = num(call(C_Map.GetBestMapForUnit, "player"))
    local pos = mapID and call(C_Map.GetPlayerMapPosition, mapID, "player")
    if type(pos) ~= "table" and type(pos) ~= "userdata" then return "-" end
    local x, y
    if pos.GetXY then x, y = call(pos.GetXY, pos) else x, y = pos.x, pos.y end
    x, y = num(x), num(y)
    if not x or not y then return "-" end
    return ("%.1f, %.1f"):format(x * 100, y * 100)
  end,
  click = function() call(rawget(_G, "ToggleWorldMap")) end }

P.friends = { label = "Friends",
  value = function()
    local n
    if type(C_FriendList) == "table" and C_FriendList.GetNumOnlineFriends then n = num(call(C_FriendList.GetNumOnlineFriends)) end
    if not n and type(rawget(_G, "GetNumFriends")) == "function" then local _, online = call(GetNumFriends) n = num(online) end
    if not n then return "-" end
    return tostring(n) .. " friends"
  end,
  click = function() call(rawget(_G, "ToggleFriendsFrame"), 1) end }

P.guild = { label = "Guild",
  value = function()
    local inGuild = call(IsInGuild)
    if not inGuild then return "no guild" end
    local _, online = call(GetNumGuildMembers)
    online = num(online)
    return tostring(online or "?") .. " guild"
  end,
  click = function() call(rawget(_G, "ToggleGuildFrame")) end }

P.xp = { label = "Experience",
  value = function()
    local xp, max = num(call(UnitXP, "player")), num(call(UnitXPMax, "player"))
    if not xp or not max or max <= 0 then return "-" end
    local rested = num(call(GetXPExhaustion)) or 0
    local s = ("%.0f%% xp"):format(xp / max * 100)
    if rested > 0 then s = s .. color("21D4E0", (" +%.0f%%"):format(rested / max * 100)) end
    return s
  end }

-- this sitting (HogHeals/Core/Session.lua): time + pace, time to the next level, gold an hour
local function session() return HH.Session end
P.session = { label = "Session",
  value = function()
    local S = session()
    if not S then return "-" end
    local st = S.Stats()
    local t = S.FormatTime(st.seconds)
    if st.hidden then return t end
    if not st.rate then return t .. "  " .. S.FormatNumber(st.xp) .. " xp" end
    return t .. "  " .. S.FormatNumber(st.rate) .. " xp/h"
  end,
  tooltip = function(tip)
    local S = session()
    if not S then return end
    for i, l in ipairs(S.Lines()) do tip:AddLine(l, i == 1 and 1 or 0.75, i == 1 and 1 or 0.75, i == 1 and 1 or 0.8, true) end
    tip:AddLine("Click: restart the count", 0.5, 0.5, 0.55)
  end,
  click = function() local S = session() if S then S.Reset() HH:Print("session: count restarted.") end end }

P.tolevel = { label = "Time to level",
  value = function()
    local S = session()
    if not S then return "-" end
    local st = S.Stats()
    if st.hidden or not st.level then return "-" end
    if not st.toLevel then return ("lvl %d: %s"):format(st.level + 1, st.percent and ("%.0f%%"):format(st.percent) or "-") end
    return ("lvl %d in %s"):format(st.level + 1, S.FormatTime(st.toLevel))
  end,
  tooltip = function(tip)
    local S = session()
    if not S then return end
    local st = S.Stats()
    tip:AddLine("Time to the next level", 1, 1, 1)
    if st.remaining then tip:AddLine(("%s xp to go (%.0f%% there)"):format(S.FormatNumber(st.remaining), st.percent or 0), 0.8, 0.8, 0.85) end
    tip:AddLine(st.rate and ("at %s xp/h, %s"):format(S.FormatNumber(st.rate), st.rateSource == "recent" and "your last 15 minutes" or "this session's average")
      or "needs a minute of play and some experience", 0.8, 0.8, 0.85, true)
  end }

P.goldph = { label = "Gold an hour",
  value = function()
    local S = session()
    if not S then return "-" end
    local st = S.Stats()
    if not st.goldPerHour then return S.FormatMoney(st.gold) end
    return S.FormatMoney(st.goldPerHour) .. "/h"
  end,
  tooltip = function(tip)
    local S = session()
    if not S then return end
    local st = S.Stats()
    tip:AddLine("Gold this session", 1, 1, 1)
    tip:AddLine(S.FormatMoney(st.gold) .. (st.goldPerHour and (" (" .. S.FormatMoney(st.goldPerHour) .. " an hour)") or ""), 0.8, 0.8, 0.85)
  end,
  click = function() call(rawget(_G, "ToggleAllBags")) end }

P.none = { label = "(empty)", value = function() return "" end }

-- ------------------------------------------------------------------------------------------------ frame
local function build()
  if Bar.frame then return Bar.frame end
  local d = cfg()
  local f = CreateFrame("Frame", "HogUIInfoBar", UIParent)
  f:SetSize(d.width or 640, d.height or 18)
  f:SetPoint(d.point or "BOTTOM", UIParent, d.point or "BOTTOM", d.x or 0, d.y or 0)
  f:SetFrameStrata("LOW")
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f.bg = Skin.Solid(f, "BACKGROUND", Skin.INK, d.backgroundAlpha or 0.8)
  f.bg:SetAllPoints(f)
  f.edges = Skin.Outline(f, f)
  f.rule = Skin.Solid(f, "ARTWORK", Skin.CYAN)
  f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  f.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  f.rule:SetHeight(1)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if not HH.db.profile.locked then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint(1)
    if point then local c = cfg() c.point, c.x, c.y = point, x, y end
  end)
  Bar.frame = f
  return f
end

local function slot(i)
  local s = Bar.slots[i]
  if s then return s end
  local f = Bar.frame
  s = CreateFrame("Button", nil, f)
  s.text = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  s.text:SetPoint("CENTER", s, "CENTER", 0, 0)
  s.text:SetJustifyH("CENTER")
  if s.text.SetWordWrap then s.text:SetWordWrap(false) end
  s:SetScript("OnClick", function(self)
    local p = P[self.key]
    if p and p.click then p.click() end
  end)
  s:SetScript("OnEnter", function(self)
    local p = P[self.key]
    if not GameTooltip or not p then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if p.tooltip then p.tooltip(GameTooltip) else GameTooltip:AddLine(p.label) end
    GameTooltip:Show()
  end)
  s:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  Bar.slots[i] = s
  return s
end

function Bar.Layout()
  local f, d = build(), cfg()
  local keys = d.slots or {}
  local n = 0
  for _ in ipairs(keys) do n = n + 1 end
  local w = (d.width or 640) / math.max(n, 1)
  for i = 1, n do
    local s = slot(i)
    s.key = P[keys[i]] and keys[i] or "none"
    s:SetSize(w, d.height or 18)
    s:ClearAllPoints()
    s:SetPoint("LEFT", f, "LEFT", (i - 1) * w, 0)
    Skin.SetFont(s.text, d.fontSize or 11)
    s.text:SetWidth(w - 6)
    s:Show()
  end
  for i = n + 1, #Bar.slots do Bar.slots[i]:Hide() end
  f:SetSize(d.width or 640, d.height or 18)
  f:ClearAllPoints()
  f:SetPoint(d.point or "BOTTOM", UIParent, d.point or "BOTTOM", d.x or 0, d.y or 0)
  f.bg:SetColorTexture(Skin.INK[1], Skin.INK[2], Skin.INK[3], d.backgroundAlpha or 0.8)
end

function Bar.Update()
  if not Bar.frame or not Bar.frame:IsShown() then return end
  for _, s in ipairs(Bar.slots) do
    if s:IsShown() then
      local p = P[s.key]
      local ok, v = pcall(p.value)
      s.text:SetText(ok and v or "?")
      if not ok and v ~= Bar.lastError then Bar.lastError = v HH:LogError("infobar " .. tostring(s.key) .. ": " .. tostring(v)) end
    end
  end
end

function Bar.Start()
  Bar.Stop()
  if C_Timer and C_Timer.NewTicker then Bar.ticker = C_Timer.NewTicker(cfg().refresh or 1, Bar.Update) end
  Bar.Update()
end

function Bar.Stop() if Bar.ticker then Bar.ticker:Cancel() Bar.ticker = nil end end

function Bar.Refresh()
  local d = cfg()
  if not d or d.enabled == false then if Bar.frame then Bar.frame:Hide() end Bar.Stop() return end
  build():Show()
  Bar.Layout()
  Bar.Start()
end

local Part = { name = "infobar" }
function Part.Apply() Bar.Refresh() end
Skin.Register(Part)
