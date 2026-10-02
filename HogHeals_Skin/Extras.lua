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

-- Blizzard's XP colours, used when a bar's own colour reads white (its colour was baked into the atlas we removed).
Part.XP_PURPLE = { 0.58, 0.0, 0.55 }
Part.RESTED_BLUE = { 0.0, 0.39, 0.88, 0.35 }
local reflat = setmetatable({}, { __mode = "k" })

--- The fill texture flat again, after Blizzard put its own back. Modern bars re-apply their fill atlas on every
-- update (the XP bar swaps rested / normal fills, both with a rounded end - in game 2026-10-01, "that rounded edge").
local function reflatten(bar)
  if reflat[bar] then return end
  reflat[bar] = true
  Skin.call(bar.SetStatusBarTexture, bar, Skin.FLAT)
  local r, g, b = Skin.call(bar.GetStatusBarColor, bar)
  if r == 1 and g == 1 and b == 1 then Skin.call(bar.SetStatusBarColor, bar, Part.XP_PURPLE[1], Part.XP_PURPLE[2], Part.XP_PURPLE[3]) end
  reflat[bar] = nil
end

local function flattenBar(bar)
  if type(bar) ~= "table" or bar.hhFlat then return false end
  if not bar.SetStatusBarTexture then return false end
  bar.hhFlat = true
  reflatten(bar)
  for _, k in ipairs({ "Background", "Overlay", "OverlayFrame", "Border" }) do
    local r = rawget(bar, k)
    if type(r) == "table" then
      if r.GetObjectType and r:GetObjectType() == "Texture" then Skin.Kill(r) else Skin.KillRegions(r) end
    end
  end
  -- the rested-XP extent is its own rounded fill: a flat translucent blue block instead
  local rested = rawget(bar, "ExhaustionLevelFillBar")
  if type(rested) == "table" and rested.SetTexture then
    Skin.call(rested.SetTexture, rested, Skin.FLAT)
    Skin.call(rested.SetVertexColor, rested, Part.RESTED_BLUE[1], Part.RESTED_BLUE[2], Part.RESTED_BLUE[3], Part.RESTED_BLUE[4])
  end
  -- rounded ends drawn through a mask on the fill: take the masks off
  local fill = bar.GetStatusBarTexture and Skin.call(bar.GetStatusBarTexture, bar)
  if type(fill) == "table" and fill.RemoveMaskTexture and bar.GetRegions then
    for _, r in ipairs({ bar:GetRegions() }) do
      if r ~= fill and r.GetObjectType and r:GetObjectType() == "MaskTexture" then pcall(fill.RemoveMaskTexture, fill, r) end
    end
  end
  -- and stay flat: Blizzard's next SetStatusBarTexture / SetStatusBarAtlas is undone on the spot
  if type(hooksecurefunc) == "function" then
    for _, m in ipairs({ "SetStatusBarTexture", "SetStatusBarAtlas" }) do
      if type(bar[m]) == "function" then pcall(hooksecurefunc, bar, m, reflatten) end
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
      if type(sb) == "table" then Skin.KillRegions(b) end   -- the bar frame's own art (texture regions only)
      if flattenBar(type(sb) == "table" and sb or b) then n = n + 1 end
    end
  end
  if c.GetChildren then
    for _, ch in ipairs({ c:GetChildren() }) do
      local sb = type(ch) == "table" and rawget(ch, "StatusBar")
      if type(sb) == "table" then Skin.KillRegions(ch) end
      if type(sb) == "table" and flattenBar(sb) then n = n + 1 end
    end
  end
  return n
end

--- Every texture on the XP containers and their bars, for /hh skindiag (name | atlas or file | shown): the next
-- rounded edge gets named instead of guessed.
function Part.ProbeXP()
  local out = {}
  local function dump(label, f)
    if type(f) ~= "table" or not f.GetRegions then return end
    for _, r in ipairs({ f:GetRegions() }) do
      if r and r.GetObjectType then
        local kind = r:GetObjectType()
        if kind == "Texture" or kind == "MaskTexture" then
          local tex = (r.GetAtlas and Skin.call(r.GetAtlas, r)) or (r.GetTexture and Skin.call(r.GetTexture, r))
          out[#out + 1] = ("%s:%s|%s|%s%s"):format(label, tostring(r.GetName and r:GetName() or "?"), tostring(tex),
            tostring(r.IsShown and r:IsShown()), kind == "MaskTexture" and "|MASK" or "")
        end
      end
    end
  end
  local mgr = rawget(_G, "StatusTrackingBarManager")
  if type(mgr) == "table" then
    for _, key in ipairs(Part.XP_CONTAINERS) do
      local c = rawget(mgr, key)
      dump(key, c)
      local bars = type(c) == "table" and rawget(c, "bars") or nil
      for i, b in ipairs(type(bars) == "table" and bars or {}) do
        dump(key .. ".bar" .. i, b)
        dump(key .. ".bar" .. i .. ".StatusBar", rawget(b, "StatusBar"))
      end
    end
  end
  dump("MainMenuExpBar", rawget(_G, "MainMenuExpBar"))
  return out
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
