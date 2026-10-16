-- Our own cast bar under every nameplate. Sean 2026-10-03 (screenshot: Windfury Matriarch casting Lightning Bolt
-- in Blizzard's art): "it looks like the old Blizzard style - style it just like ours". Same look as the HUD player
-- bar and the Units target bar: flat fill, ink backing, 1 px edges, spell icon left, name left, time right, grey
-- over the fill while the cast cannot be interrupted.
--
-- Why not re-skin Blizzard's: Plates.SkinCastbar never found the bar on Forever (plain Blizzard art in the shot),
-- and writing onto a Blizzard frame whose code handles secrets is the taint that killed the adopted target bar
-- (PR #51). Blizzard's container only goes to alpha 0; nothing of ours is written on it (side table + uf.hh).
--
-- Secrets: name / icon / start / end can be SECRET in combat on this client. They are handed to the widgets
-- (SetMinMaxValues, SetText, SetTexture, SetAlphaFromBoolean) and never compared, added or formatted. The fill
-- moves with OUR clock (GetTime * 1000) between the client's ends; a channel drains only when both ends are plain.
--
-- Self-wired like Hots.lua: hooks on Plates.Skin / Update / Reset / Refresh / Diagnose, guarded - Plates.lua
-- differs between branches and an unguarded hook on a nil function throws at file load.
HogHealsPlates = HogHealsPlates or {}
local HHP = HogHealsPlates
local HH = HogHeals

local Castbar = { bars = setmetatable({}, { __mode = "k" }), built = 0 }
HHP.Castbar = Castbar

local FLAT = "Interface\\Buttons\\WHITE8X8"
local LINE = { 0.05, 0.05, 0.06 }
local INK = { 0.07, 0.07, 0.09 }
local CREAM = { 0.96, 0.92, 0.86 }
local CYAN = { 0.13, 0.83, 0.88 }
local GREEN = { 0.25, 0.80, 0.35 }
local GREY = { 0.55, 0.55, 0.60 }
Castbar.POLL = 0.25                                            -- seconds between re-reads of the client while shown
Castbar.BLIZZ = { "CastBarsContainer", "castBar", "CastBar" }  -- Blizzard's bar on the plate, by the names seen so far

local function cfg() return HH.db.profile.plates end
local function ccfg() return HH.db.profile.plates.cast or {} end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function present(v) return isSecret(v) or v ~= nil end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
end

local function fontPath()
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  local p = HogHeals.Look.Font(cfg().font)
  return p or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end
local function setFont(fs, size) call(fs.SetFont, fs, fontPath(), size, "OUTLINE") end
local function solid(parent, layer, c, a)
  local t = parent:CreateTexture(nil, layer)
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  return t
end

--- Our bar for a plate's UnitFrame, or nil.
function Castbar.For(uf) return Castbar.bars[uf] end

-- ------------------------------------------------------------------------------------------------ build
function Castbar.Build(uf)
  local hh = uf.hh
  if not hh then return nil end
  if Castbar.bars[uf] then return Castbar.bars[uf] end
  if cfg().castbar == false then return nil end
  local parent = hh.overlay or uf
  local bar = CreateFrame("StatusBar", nil, parent)
  bar.uf = uf
  bar:SetStatusBarTexture(HogHeals.Look.Bar())          -- texture first, anchors after (Units.lua header: texture-first bars)
  bar:SetStatusBarColor(CYAN[1], CYAN[2], CYAN[3])
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  bar:SetFrameLevel(((parent.GetFrameLevel and parent:GetFrameLevel()) or 1) + 1)
  bar.bg = solid(bar, "BACKGROUND", INK, 0.85)
  bar.bg:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
  bar.bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
  bar.edges = {}
  local spec = { { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
    { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }
  for i, s in ipairs(spec) do
    local e = solid(bar, "BORDER", LINE)
    e:SetPoint(s[1], bar.bg, s[1], 0, 0)
    e:SetPoint(s[2], bar.bg, s[2], 0, 0)
    if s[3] then e:SetWidth(s[3]) end
    if s[4] then e:SetHeight(s[4]) end
    bar.edges[i] = e
  end
  -- grey over the fill while the cast cannot be interrupted; its alpha is the only thing that boolean ever drives
  bar.locked = solid(bar, "ARTWORK", GREY, 1)
  if bar.locked.SetDrawLayer then call(bar.locked.SetDrawLayer, bar.locked, "ARTWORK", 1) end
  local fill = call(bar.GetStatusBarTexture, bar)
  bar.locked:SetAllPoints(type(fill) == "table" and fill or bar)
  bar.locked:SetAlpha(0)
  bar.icon = bar:CreateTexture(nil, "ARTWORK")
  bar.icon:SetPoint("RIGHT", bar, "LEFT", -3, 0)
  if bar.icon.SetTexCoord then call(bar.icon.SetTexCoord, bar.icon, 0.08, 0.92, 0.08, 0.92) end
  bar.text = bar:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  bar.text:SetPoint("LEFT", bar, "LEFT", 3, 0)
  bar.text:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
  bar.text:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
  if bar.text.SetJustifyH then call(bar.text.SetJustifyH, bar.text, "LEFT") end
  if bar.text.SetWordWrap then call(bar.text.SetWordWrap, bar.text, false) end
  bar.time = bar:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
  bar.time:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
  bar.time:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
  if bar.time.SetJustifyH then call(bar.time.SetJustifyH, bar.time, "RIGHT") end
  bar:SetScript("OnUpdate", Castbar.Tick)
  bar:Hide()
  Castbar.bars[uf] = bar
  hh.castbar = bar
  Castbar.built = Castbar.built + 1
  Castbar.Place(uf)
  return bar
end

--- Geometry + option-driven looks; re-read on every call so option changes land at once.
function Castbar.Place(uf)
  local bar, hh = Castbar.bars[uf], uf.hh
  if not bar or not hh then return end
  local c = ccfg()
  local anchor = hh.bar or uf
  local h, gap = c.height or 10, c.gap or 3
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
  bar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -gap)
  bar:SetHeight(h)
  bar:SetStatusBarTexture(HogHeals.Look.Bar())
  bar.icon:SetSize(h, h)
  bar.icon:SetShown(c.icon ~= false)
  bar.time:SetShown(c.time ~= false)
  local lc = c.lockedColor or GREY
  bar.locked:SetColorTexture(lc[1], lc[2], lc[3], 1)
  setFont(bar.text, c.fontSize or 10)
  setFont(bar.time, c.fontSize or 10)
end

-- ------------------------------------------------------------------------------------------------ Blizzard's bar
--- Blizzard's cast bar on the plate to alpha 0 (quiet) or back to 1. Re-applied on every Update and every cast
-- event: Blizzard re-shows it on plate reuse and on its own cast events (its handlers run before ours).
function Castbar.Quiet(uf, quiet)
  for _, k in ipairs(Castbar.BLIZZ) do
    local f = rawget(uf, k)
    if type(f) == "table" and f.SetAlpha then
      call(f.SetAlpha, f, quiet and 0 or 1)
      if quiet and not Castbar.blizzKey then Castbar.blizzKey = k end
    end
  end
end

-- ------------------------------------------------------------------------------------------------ casts
local function castInfo(fn, unit)
  if type(fn) ~= "function" then return nil end
  local ok, name, _, texture, startMS, endMS, _, r7, r8 = pcall(fn, unit)
  if not ok then return nil end
  return name, texture, startMS, endMS, r7, r8
end

--- Where the fill stands now: our clock between the client's (maybe secret) ends; a channel drains when plain.
local function value(bar)
  local now = (call(GetTime) or 0) * 1000
  if bar.channel and bar.plainStart and bar.plainEnd then return bar.plainStart + bar.plainEnd - now end
  return now
end

local function lock(bar, notInt)
  if isSecret(notInt) then
    if type(bar.locked.SetAlphaFromBoolean) == "function" then
      if not pcall(bar.locked.SetAlphaFromBoolean, bar.locked, notInt, 1, 0) then bar.locked:SetAlpha(0) end
    else
      bar.locked:SetAlpha(0)   -- without the resolver the marker stays off rather than guess
    end
  else
    bar.locked:SetAlpha(notInt and 1 or 0)
  end
end

--- Seconds left, from a PLAIN end time only; a secret end time shows no number (no arithmetic on secrets).
local function timeText(bar)
  local c = ccfg()
  if not bar.plainEnd or c.time == false then bar.time:SetText("") return end
  local remaining = math.max(0, (bar.plainEnd - (call(GetTime) or 0) * 1000) / 1000)
  local places = c.precision or 1
  bar.time:SetText(("%." .. places .. "f"):format(remaining))
end

local function diag(name, startMS, notInt)
  if Castbar.diagDone then return end
  Castbar.diagDone = true
  local g = HH.db and HH.db.global
  if not g then return end
  g.diag = g.diag or {}
  g.diag.plateCast = { secretName = isSecret(name), secretTimes = isSecret(startMS), secretLock = isSecret(notInt),
    blizzKey = Castbar.blizzKey or "none" }
end

function Castbar.HideBar(bar)
  bar.casting, bar.channel, bar.plainStart, bar.plainEnd, bar.poll = nil, nil, nil, nil, nil
  bar:Hide()
end

--- Read the client for this plate's unit and paint: shown while a cast / channel is up, hidden otherwise.
function Castbar.Refresh(uf)
  local hh = uf.hh
  if not hh then return end
  if cfg().castbar == false then
    Castbar.Quiet(uf, false)
    local b = Castbar.bars[uf]
    if b then Castbar.HideBar(b) end
    return
  end
  local bar = Castbar.Build(uf)
  if not bar then return end
  Castbar.Quiet(uf, true)
  if bar.broken or hh.nameOnly or not hh.unit then Castbar.HideBar(bar) return end
  local unit = hh.unit
  local name, texture, startMS, endMS, r7, r8 = castInfo(rawget(_G, "UnitCastingInfo"), unit)
  local notInt, channel = r8, false
  if not present(name) then
    name, texture, startMS, endMS, r7 = castInfo(rawget(_G, "UnitChannelInfo"), unit)
    notInt, channel = r7, true
  end
  if not (present(name) and present(startMS) and present(endMS)) then Castbar.HideBar(bar) return end
  bar.casting, bar.channel = true, channel
  bar.plainStart, bar.plainEnd = num(startMS), num(endMS)
  bar:SetMinMaxValues(startMS, endMS)
  bar:SetValue(value(bar))
  bar.text:SetText(name)
  call(bar.icon.SetTexture, bar.icon, texture)
  local c = ccfg()
  local col = channel and (c.channelColor or GREEN) or (c.castColor or CYAN)
  bar:SetStatusBarColor(col[1], col[2], col[3])
  lock(bar, notInt)
  timeText(bar)
  diag(name, startMS, notInt)
  bar:Show()
end

--- OnUpdate of a shown bar: move the fill, the time text, and re-read the client every POLL seconds so a cast
-- whose stop event never reached us still ends. A throw latches this bar off and logs once, never per frame.
function Castbar.Tick(bar, elapsed)
  if bar.broken or not bar.casting then return end
  local ok, err = xpcall(function()
    bar:SetValue(value(bar))
    timeText(bar)
    bar.poll = (bar.poll or 0) + (num(elapsed) or 0)
    if bar.poll >= Castbar.POLL then
      bar.poll = 0
      Castbar.Refresh(bar.uf)
    end
  end, HH.Trace or tostring)
  if not ok then
    bar.broken = true
    Castbar.HideBar(bar)
    HH:LogError("plates castbar " .. tostring(bar.uf.hh and bar.uf.hh.unit) .. ": " .. tostring(err))
  end
end

function Castbar.DiagLine()
  local shown = 0
  for _, b in pairs(Castbar.bars) do if b:IsShown() then shown = shown + 1 end end
  return ("cast bar: built=%d shown=%d blizzKey=%s"):format(Castbar.built, shown, tostring(Castbar.blizzKey or "none"))
end

-- ------------------------------------------------------------------------------------------------ wiring
local Plates = HHP.Plates
if type(Plates) == "table" and type(hooksecurefunc) == "function" then
  if type(Plates.Skin) == "function" then
    hooksecurefunc(Plates, "Skin", function(uf) pcall(Castbar.Build, uf) end)
  end
  if type(Plates.Update) == "function" then
    hooksecurefunc(Plates, "Update", function(uf)
      local ok, err = pcall(Castbar.Refresh, uf)
      if not ok then HH:LogError("plates castbar update: " .. tostring(err)) end
    end)
  end
  if type(Plates.Reset) == "function" then   -- newer Plates.lua; older ones are covered by NAME_PLATE_UNIT_REMOVED below
    hooksecurefunc(Plates, "Reset", function(uf) local b = Castbar.bars[uf] if b then Castbar.HideBar(b) end end)
  end
  if type(Plates.Refresh) == "function" then
    hooksecurefunc(Plates, "Refresh", function() for uf in pairs(Castbar.bars) do pcall(Castbar.Place, uf) end end)
  end
  if type(Plates.Diagnose) == "function" then
    local orig = Plates.Diagnose
    Plates.Diagnose = function(...)
      local lines = orig(...)
      if type(lines) == "table" then lines[#lines + 1] = Castbar.DiagLine() end
      return lines
    end
  end
end

local EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
  "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
  "NAME_PLATE_UNIT_REMOVED" }
local ev = CreateFrame("Frame")
for _, e in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, e, unit)
  if type(Plates) ~= "table" or type(unit) ~= "string" then return end
  if e == "NAME_PLATE_UNIT_REMOVED" then
    -- Plates.Removed ran first (its frame registered earlier) and dropped the unit from active: find the plate itself
    local uf = Plates.FrameFor and Plates.FrameFor(unit)
    local bar = uf and Castbar.bars[uf]
    if bar then Castbar.HideBar(bar) end
    return
  end
  local uf = Plates.active and Plates.active[unit]
  if uf and uf.hh and uf.hh.unit then
    local ok, err = pcall(Castbar.Refresh, uf)
    if not ok and err ~= Castbar.lastError then
      Castbar.lastError = err
      HH:LogError("plates castbar " .. tostring(e) .. ": " .. tostring(err))
    end
  end
end)
Castbar.events = ev
