-- Extras: the player's buff / debuff icons (top right), the experience / reputation bar and the mirror timers
-- (breath, fatigue, feign death), flattened into the HogUI look. Classic-era names and the modern frames are both
-- handled; a client with neither loses nothing.
local HHS = HogHealsSkin
local Skin = HHS.Skin
local HH = HogHeals

local Part = { name = "extras", skinnedAuras = 0 }
HHS.Extras = Part

-- ------------------------------------------------------------------------------------------------ player auras
local function skinAura(b)
  if type(b) ~= "table" or b.hhSkinned then return false end
  local name = b.GetName and b:GetName()
  local icon = rawget(b, "Icon") or rawget(b, "icon") or (name and rawget(_G, name .. "Icon"))
  if type(icon) ~= "table" then return false end
  local hh = Skin.IconButton(b, {})
  local d = Skin.cfg().extras
  local dur = rawget(b, "Duration") or rawget(b, "duration") or (name and rawget(_G, name .. "Duration"))
  if type(dur) == "table" then Skin.SetFont(dur, d.durationSize or 10) end
  local cnt = rawget(b, "Count") or rawget(b, "count") or (name and rawget(_G, name .. "Count"))
  if type(cnt) == "table" then Skin.SetFont(cnt, d.durationSize or 10) end
  -- debuff type outline where the client tells us (classic: a Border texture coloured by type; we read its colour)
  local border = rawget(b, "Border") or (name and rawget(_G, name .. "Border"))
  if type(border) == "table" and border.GetVertexColor and hh and hh.edges then
    local function follow()
      local r, g, bl = Skin.call(border.GetVertexColor, border)
      if Skin.num(r) and Skin.num(g) and Skin.num(bl) then Skin.ColorEdges(hh.edges, { r, g, bl }) end
    end
    follow()
    if type(hooksecurefunc) == "function" and border.SetVertexColor then pcall(hooksecurefunc, border, "SetVertexColor", follow) end
  end
  Part.skinnedAuras = Part.skinnedAuras + 1
  return true
end

function Part.SkinAuras()
  local d = Skin.cfg().extras
  if not d or d.buffs == false then return 0 end
  local n = 0
  -- classic: named buttons created as needed
  for _, prefix in ipairs({ "BuffButton", "DebuffButton", "TempEnchant" }) do
    for i = 1, 40 do
      local b = rawget(_G, prefix .. i)
      if not b then break end
      if skinAura(b) then n = n + 1 end
    end
  end
  -- modern: pooled frames under BuffFrame.AuraContainer / DebuffFrame.AuraContainer
  for _, holder in ipairs({ "BuffFrame", "DebuffFrame" }) do
    local frame = Skin.G(holder)
    local container = type(frame) == "table" and rawget(frame, "AuraContainer")
    if type(container) == "table" and container.GetChildren then
      for _, child in ipairs({ container:GetChildren() }) do if skinAura(child) then n = n + 1 end end
    end
  end
  return n
end

-- ------------------------------------------------------------------------------------------------ xp / rep bar
Part.XP_ART = { "MainMenuXPBarTexture0", "MainMenuXPBarTexture1", "MainMenuXPBarTexture2", "MainMenuXPBarTexture3",
  "ReputationWatchBarTexture0", "ReputationWatchBarTexture1", "ReputationWatchBarTexture2", "ReputationWatchBarTexture3",
  "ReputationXPBarTexture0", "ReputationXPBarTexture1", "ReputationXPBarTexture2", "ReputationXPBarTexture3" }

local function flattenBar(bar)
  if type(bar) ~= "table" or bar.hhFlat then return false end
  if not bar.SetStatusBarTexture then return false end
  bar.hhFlat = true
  Skin.call(bar.SetStatusBarTexture, bar, Skin.FLAT)
  for _, k in ipairs({ "Background", "Overlay", "OverlayFrame", "Border" }) do
    local r = rawget(bar, k)
    if type(r) == "table" then
      if r.GetObjectType and r:GetObjectType() == "Texture" then Skin.Kill(r) else Skin.KillRegions(r) end
    end
  end
  bar.hhBg = Skin.Solid(bar, "BACKGROUND", { 0.13, 0.13, 0.16 }, 0.9, -8)
  bar.hhBg:SetAllPoints(bar)
  bar.hhEdges = Skin.Outline(bar, bar)
  return true
end

-- Modern (Dragonflight-engine, WoW: Forever included): StatusTrackingBarManager owns two containers; the gold frame
-- with the twenty divisions (in game 2026-10-01) is the container's BarFrameTexture, each bar inside has a StatusBar.
Part.XP_CONTAINERS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }
Part.XP_CONTAINER_ART = { "BarFrameTexture", "BackgroundGlow", "Background", "Overlay" }

local function skinContainer(c)
  local n = 0
  if type(c) ~= "table" then return 0 end
  for _, k in ipairs(Part.XP_CONTAINER_ART) do Skin.Kill(rawget(c, k)) end
  Skin.KillRegions(c)
  local bars = rawget(c, "bars")
  if type(bars) == "table" then
    for _, b in ipairs(bars) do
      local sb = rawget(b, "StatusBar")
      if flattenBar(type(sb) == "table" and sb or b) then n = n + 1 end
    end
  end
  if c.GetChildren then
    for _, ch in ipairs({ c:GetChildren() }) do
      local sb = type(ch) == "table" and rawget(ch, "StatusBar")
      if type(sb) == "table" and flattenBar(sb) then n = n + 1 end
    end
  end
  return n
end

function Part.SkinXP()
  local d = Skin.cfg().extras
  if not d or d.xpBar == false then return 0 end
  local n = 0
  for _, a in ipairs(Part.XP_ART) do Skin.Kill(Skin.G(a)) end
  for _, name in ipairs({ "MainMenuExpBar", "ReputationWatchBar", "ReputationWatchStatusBar" }) do
    local bar = Skin.G(name)
    if type(bar) == "table" then
      local inner = rawget(bar, "StatusBar")
      if flattenBar(type(inner) == "table" and inner or bar) then n = n + 1 end
    end
  end
  -- modern: StatusTrackingBarManager owns a list of bars, each with a StatusBar
  local mgr = Skin.G("StatusTrackingBarManager")
  local bars = type(mgr) == "table" and rawget(mgr, "bars")
  if type(bars) == "table" then
    for _, b in ipairs(bars) do
      local sb = rawget(b, "StatusBar")
      if flattenBar(type(sb) == "table" and sb or b) then n = n + 1 end
    end
  end
  if type(mgr) == "table" then
    for _, key in ipairs(Part.XP_CONTAINERS) do n = n + skinContainer(rawget(mgr, key)) end
  end
  return n
end

-- ------------------------------------------------------------------------------------------------ mirror timers
-- Breath / fatigue / feign death: MirrorTimer1..3 - classic names them MirrorTimer1StatusBar / Border / Text,
-- the modern template keeps StatusBar / Border / Text as keys under MirrorTimerContainer. Flat bar on an ink
-- panel, Blizzard's colour kept (blue breath, red fatigue), cream text. Side table, no fields on the frames.
local mirrored = setmetatable({}, { __mode = "k" })
Part.mirrored = mirrored

local function skinMirror(f)
  if type(f) ~= "table" or mirrored[f] then return false end
  local name = (f.GetName and f:GetName()) or ""
  local sb = rawget(f, "StatusBar") or Skin.G(name .. "StatusBar")
  if type(sb) ~= "table" then return false end
  mirrored[f] = true
  Skin.Kill(rawget(f, "Border") or Skin.G(name .. "Border"))
  Skin.KillRegions(f)
  flattenBar(sb)
  local text = rawget(f, "Text") or Skin.G(name .. "Text")
  if type(text) == "table" then
    Skin.SetFont(text, 11)
    if text.SetTextColor then Skin.call(text.SetTextColor, text, Skin.CREAM[1], Skin.CREAM[2], Skin.CREAM[3]) end
  end
  return true
end

function Part.SkinMirrors()
  local d = Skin.cfg().extras
  if not d or d.mirror == false then return 0 end
  local n = 0
  for i = 1, 3 do
    local f = Skin.G("MirrorTimer" .. i)
    if not f then
      local c = rawget(_G, "MirrorTimerContainer")
      f = type(c) == "table" and rawget(c, "MirrorTimer" .. i) or nil
    end
    if skinMirror(f) then n = n + 1 end
  end
  local c = rawget(_G, "MirrorTimerContainer")
  if type(c) == "table" and c.GetChildren then
    for _, ch in ipairs({ c:GetChildren() }) do if skinMirror(ch) then n = n + 1 end end
  end
  return n
end

function Part.Apply()
  Part.auras = Part.SkinAuras()
  Part.xp = Part.SkinXP()
  Part.mirrors = (Part.mirrors or 0) + Part.SkinMirrors()   -- cumulative: Apply runs more than once a session
  if not Part.hooked and type(hooksecurefunc) == "function" then
    Part.hooked = true
    -- new buff buttons appear as auras come and go
    for _, fn in ipairs({ "BuffFrame_Update", "BuffFrame_UpdateAllBuffAnchors", "AuraButton_Update" }) do
      if type(rawget(_G, fn)) == "function" then pcall(hooksecurefunc, fn, function() if Skin.cfg().enabled ~= false then Part.SkinAuras() end end) end
    end
    local bf = rawget(_G, "BuffFrame")
    if type(bf) == "table" and type(rawget(bf, "Update")) == "function" then
      pcall(hooksecurefunc, bf, "Update", function() if Skin.cfg().enabled ~= false then Part.SkinAuras() end end)
    end
    -- mirror timers are set up when they first show (classic: MirrorTimer_Show, modern: the container's SetupTimer)
    if type(rawget(_G, "MirrorTimer_Show")) == "function" then
      pcall(hooksecurefunc, "MirrorTimer_Show", function() if Skin.cfg().enabled ~= false then Part.SkinMirrors() end end)
    end
    local mc = rawget(_G, "MirrorTimerContainer")
    if type(mc) == "table" and type(rawget(mc, "SetupTimer")) == "function" then
      pcall(hooksecurefunc, mc, "SetupTimer", function() if Skin.cfg().enabled ~= false then Part.SkinMirrors() end end)
    end
    -- the XP container is rebuilt when bars come and go (level cap, reputation tracked)
    local mgr = rawget(_G, "StatusTrackingBarManager")
    if type(mgr) == "table" and type(rawget(mgr, "UpdateBarsShown")) == "function" then
      pcall(hooksecurefunc, mgr, "UpdateBarsShown", function() if Skin.cfg().enabled ~= false then Part.SkinXP() end end)
    end
  end
end

function Part.OnEvent(e)
  if e == "PLAYER_ENTERING_WORLD" then Part.Apply() end
end

Skin.Register(Part)
