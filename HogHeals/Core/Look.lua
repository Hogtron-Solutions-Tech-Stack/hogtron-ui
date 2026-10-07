-- Look: the one place that decides how HogTron UI text and bars look. Sean 2026-10-06: "toggle the new UI vs the
-- classic UI styling" + "the font and sizing from Ellesmere UI - it looks a lot cleaner, higher pixel density".
--
--   style  "hogtron" (our fonts, flat bars, Blizzard's windows skinned) | "classic" (Blizzard's font, Blizzard's bar
--          texture, Blizzard's windows left alone). Features stay on in both. Changing it needs a /reload.
--   font   "Inter" | "Manrope" | "Barlow Condensed" - shipped in HogHeals/Media/Fonts (SIL Open Font License).
--   edge   "shadow" (1 px drop shadow, no outline: the cleaner look) | "outline" (WoW's 1 px outline everywhere).
--          Text drawn ON a bar (cell names, plate text, cast bars) keeps its outline in both: light class colours
--          (priest white) need it. Panel and window text follows this setting.
--   size   -2..+4 points on every panel / window text.
--   pixel  the UIParent scale saved by "Make it pixel-perfect" (nil = untouched).
--
-- Text: every CreateFontString in the suite names one of the font objects below (HogTronFont*), made here at load as
-- copies of Blizzard's, so one SetFont on the object restyles every string using it - live, no reload. Code that sets
-- a font itself asks Look.Font() for the path.
--
-- Pixel-perfect: one WoW UI unit is 768 / screen height pixels at scale 1. A UIParent scale of exactly that makes
-- every 1 px line and every glyph sit on a real pixel (EllesmereUI's and ElvUI's technique; our own code).
local HH = HogHeals

local Look = { objects = {} }
HH.Look = Look

local DIR = "Interface\\AddOns\\HogHeals\\Media\\Fonts\\"
Look.FONTS = {
  ["Inter"] = DIR .. "Inter-SemiBold.ttf",
  ["Manrope"] = DIR .. "Manrope-SemiBold.ttf",
  ["Barlow Condensed"] = DIR .. "BarlowCondensed-SemiBold.ttf",
}
Look.FONT_ORDER = { "Inter", "Manrope", "Barlow Condensed" }
Look.FLAT = "Interface\\Buttons\\WHITE8X8"
Look.BLIZZARD_BAR = "Interface\\TargetingFrame\\UI-StatusBar"
Look.FOLLOW = "HogTron"   -- a module font set to this follows the Look font (the default everywhere)

-- our font object <- the Blizzard object it starts as a copy of
Look.OBJECTS = {
  HogTronFontSmall = "GameFontHighlightSmall",
  HogTronFontHighlight = "GameFontHighlight",
  HogTronFontNormal = "GameFontNormal",
  HogTronFontNormalSmall = "GameFontNormalSmall",
  HogTronFontNormalLarge = "GameFontNormalLarge",
}

local function cfg()
  local p = HH.db and HH.db.profile
  return (p and p.look) or {}
end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c = pcall(f, ...)
  if ok then return a, b, c end
end
local function standardFont() return rawget(_G, "STANDARD_TEXT_FONT") or "Fonts\\FRIZQT__.TTF" end

function Look.Classic() return cfg().style == "classic" end

--- Path of the font to draw with. requested = a module's saved font name: nil / "HogTron" -> the Look font;
-- "HogTron Manrope" -> that one of ours; any other LibSharedMedia name (a font the player picked) -> that font.
-- Classic -> Blizzard's font for nil / "HogTron"; a font the player picked is still honoured.
function Look.Font(requested)
  if requested == nil or requested == Look.FOLLOW then
    if Look.Classic() then return standardFont() end
    return Look.FONTS[cfg().font or "Inter"] or Look.FONTS.Inter
  end
  local ours = requested:match("^HogTron (.+)$")
  if ours and Look.FONTS[ours] then return Look.FONTS[ours] end
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  local p = LSM and call(LSM.Fetch, LSM, "font", requested, true)
  return p or (Look.Classic() and standardFont()) or Look.FONTS.Inter
end

--- Status bar texture. requested = a module's saved texture name; "Solid" / nil = flat. Classic -> Blizzard's bar.
function Look.Bar(requested)
  if Look.Classic() then return Look.BLIZZARD_BAR end
  if requested and requested ~= "Solid" then
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local p = LSM and call(LSM.Fetch, LSM, "statusbar", requested, true)
    if p then return p end
  end
  return Look.FLAT
end

--- Make (or fetch) our font objects. Runs at file load so every module's CreateFontString can name them.
function Look.MakeObjects()
  for name, source in pairs(Look.OBJECTS) do
    local o = rawget(_G, name)
    if not o and type(CreateFont) == "function" then o = CreateFont(name) end
    if o then
      local src = rawget(_G, source)
      if src and o.CopyFontObject then pcall(o.CopyFontObject, o, src) end
      -- what Blizzard's object is, before we touch it: classic restores exactly this
      if src and src.GetFont and not Look.objects[name] then
        local path, size, flags = call(src.GetFont, src)
        Look.objects[name] = { path = path, size = num(size) or 12, flags = flags or "", source = source }
      elseif not Look.objects[name] then
        Look.objects[name] = { size = 12, flags = "", source = source }
      end
    end
  end
end

--- Restyle every font object from the settings. Live: every string using an object changes at once.
function Look.Apply()
  local c = cfg()
  local classic = Look.Classic()
  local path = Look.Font()
  local shadow = c.edge ~= "outline"
  local bump = num(c.size) or 0
  for name, base in pairs(Look.objects) do
    local o = rawget(_G, name)
    if o and o.SetFont then
      if classic then
        local src = rawget(_G, base.source)
        if src and o.CopyFontObject then pcall(o.CopyFontObject, o, src) end
        if base.path then pcall(o.SetFont, o, base.path, base.size + bump, base.flags) end
      else
        pcall(o.SetFont, o, path, math.max(6, base.size + bump), shadow and "" or "OUTLINE")
        if o.SetShadowOffset then pcall(o.SetShadowOffset, o, shadow and 1 or 0, shadow and -1 or 0) end
        if o.SetShadowColor then pcall(o.SetShadowColor, o, 0, 0, 0, shadow and 1 or 0) end
      end
    end
  end
  Look.applied = { style = classic and "classic" or "hogtron", font = classic and "Blizzard" or (c.font or "Inter"), edge = shadow and "shadow" or "outline", size = bump }
  return Look.applied
end

--- Ask every module that draws its own text or bars to repaint (font / texture changes that do not need a reload).
function Look.RefreshModules()
  local tries = {
    function() local F = rawget(_G, "HogHealsFrames") if F and F.module and F.module.Refresh then F.module:Refresh() end end,
    function() local D = rawget(_G, "HogHealsHUD") if D and D.HUD and D.HUD.Refresh then D.HUD.Refresh() end end,
    function() local P = rawget(_G, "HogHealsPlates") if P and P.Plates and P.Plates.Refresh then P.Plates.Refresh() end end,
    function() local U = rawget(_G, "HogHealsUnits") if U and U.Units and U.Units.Refresh then U.Units.Refresh() end end,
    function() local Q = rawget(_G, "HogHealsQuests") if Q and Q.Tracker and Q.Tracker.Refresh then Q.Tracker.Refresh() end end,
  }
  local n = 0
  for _, f in ipairs(tries) do if pcall(f) then n = n + 1 end end
  return n
end

-- ------------------------------------------------------------------------------------------------ pixel-perfect
--- The scale at which one UI unit is one screen pixel: 768 / physical screen height. nil when the client will not say.
function Look.PerfectScale()
  local _, h = call(rawget(_G, "GetPhysicalScreenSize"))
  h = num(h)
  if not h or h <= 0 then return nil end
  return 768 / h
end

function Look.CurrentScale()
  return UIParent and num(call(UIParent.GetScale, UIParent)) or 1
end

--- Set UIParent to the pixel-perfect scale (out of combat). Remembers the scale it replaced for Undo.
function Look.MakePixelPerfect()
  if InCombatLockdown and InCombatLockdown() then return false, "not in combat" end
  local s = Look.PerfectScale()
  if not s then return false, "this client does not report the screen size" end
  local c = cfg()
  if not c.pixel then c.pixelBefore = Look.CurrentScale() end
  c.pixel = s
  call(UIParent.SetScale, UIParent, s)
  return true, s
end

function Look.UndoPixelPerfect()
  if InCombatLockdown and InCombatLockdown() then return false, "not in combat" end
  local c = cfg()
  local before = c.pixelBefore
  c.pixel, c.pixelBefore = nil, nil
  if before then call(UIParent.SetScale, UIParent, before) end
  return true, before
end

--- Re-apply a saved pixel scale (login, screen size changes: Blizzard resets UIParent's scale on those).
function Look.KeepPixel()
  local c = cfg()
  if not c.pixel or (InCombatLockdown and InCombatLockdown()) then return end
  local s = Look.PerfectScale() or c.pixel
  c.pixel = s
  if math.abs(Look.CurrentScale() - s) > 0.0005 then call(UIParent.SetScale, UIParent, s) end
end

function Look.Describe()
  local a = Look.applied or Look.Apply()
  local p = Look.PerfectScale()
  return ("look: %s, font %s, %s, size %+d; UI scale %.3f%s"):format(a.style, a.font, a.edge, a.size, Look.CurrentScale(),
    p and ((" (pixel-perfect is %.3f%s)"):format(p, cfg().pixel and ", on" or ", off")) or "")
end

-- ------------------------------------------------------------------------------------------------ wiring
function Look.RegisterMedia()
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  if not LSM then return end
  for name, path in pairs(Look.FONTS) do pcall(LSM.Register, LSM, "font", "HogTron " .. name, path) end
  pcall(LSM.Register, LSM, "font", Look.FOLLOW, Look.FONTS.Inter)   -- shows in font lists; Look.Font treats it as "follow"
end

function Look.Init()
  Look.RegisterMedia()
  Look.MakeObjects()
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "PLAYER_REGEN_ENABLED" }) do
    pcall(f.RegisterEvent, f, e)
  end
  f:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_LOGIN" or e == "PLAYER_ENTERING_WORLD" then Look.Apply() end
    Look.KeepPixel()
  end)
  Look.frame = f
end

local STYLES = { hogtron = true, classic = true }
local FONT_ALIAS = { inter = "Inter", manrope = "Manrope", barlow = "Barlow Condensed" }

HH:RegisterSlash("look", function(rest)
  rest = (rest or ""):lower()
  local c = cfg()
  if STYLES[rest] then
    c.style = rest
    HH:Print(("look: %s - type /reload to switch (Blizzard's windows and bars change on a reload)."):format(rest == "classic" and "Classic" or "HogTron"))
    return
  elseif FONT_ALIAS[rest] then c.font = FONT_ALIAS[rest]
  elseif rest == "shadow" or rest == "outline" then c.edge = rest
  elseif rest == "pixel" then
    local ok, v = Look.MakePixelPerfect()
    HH:Print(ok and ("look: UI scale set to %.3f (pixel-perfect). /hh look unpixel to undo."):format(v) or ("look: cannot - " .. tostring(v)))
    return
  elseif rest == "unpixel" then
    local ok, v = Look.UndoPixelPerfect()
    HH:Print(ok and ("look: UI scale back to %s."):format(v and ("%.3f"):format(v) or "the game's own") or ("look: cannot - " .. tostring(v)))
    return
  elseif rest ~= "" then
    HH:Print("look: hogtron | classic | inter | manrope | barlow | shadow | outline | pixel | unpixel")
    return
  end
  Look.Apply()
  Look.RefreshModules()
  HH:Print(Look.Describe())
end, "how it looks: hogtron | classic, font inter | manrope | barlow, shadow | outline, pixel | unpixel")

Look.Init()
