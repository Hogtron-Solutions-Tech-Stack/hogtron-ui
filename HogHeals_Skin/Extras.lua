-- Extras: the player's buff / debuff icons (top right) and the experience / reputation bar, flattened.
-- Classic-era names and the modern pooled frames are both handled; a client with neither loses nothing.
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
  return n
end

function Part.Apply()
  Part.auras = Part.SkinAuras()
  Part.xp = Part.SkinXP()
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
  end
end

function Part.OnEvent(e)
  if e == "PLAYER_ENTERING_WORLD" then Part.Apply() end
end

Skin.Register(Part)
