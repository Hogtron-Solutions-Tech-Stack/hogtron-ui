-- /hh test N - fake party/raid with simulated health, auras, dispels, range (Danders pattern).
--
-- Sean 2026-10-05: "/hh test 5 shows nothing" while 10 worked. 5 takes the PARTY layout, whose row grows from its
-- CENTRE (Headers re-anchors the live header on the anchor's middle); the fakes were pinned to the anchor's TOPLEFT
-- like a raid group. They are now placed exactly as the live row is. And a test that fails now says so in chat
-- instead of dying silently: every step is pcall-ed and the error printed + logged.
--
-- On the real client fake units have no unit API, so the elements must NOT run on them (UnitHealth("hhtest1") is
-- nothing, the range poll would fade them, the health element writes "Offline"): the buttons are flagged hhFake and
-- painted directly from the fake table. In the test harness MockUnits carries the fakes, and the elements run as
-- they would on real units.
HogHealsFrames = HogHealsFrames or {}
local HHF = HogHealsFrames
local HH = HogHeals

local TestMode = { active = false, units = {}, buttons = {} }
HHF.TestMode = TestMode
HHF.TestHooks = HHF.TestHooks or {}   -- fn(button, fake): other modules paint their own pieces on a fake cell

local CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "SHAMAN", "DRUID", "HUNTER", "WARLOCK", "PALADIN" }
local NAMES = { "Hognificent", "Zugzug", "Brianna", "Anthony", "Restohog", "Fable", "Penny", "Scoop", "Boar", "Tusk" }
-- harmful: what a healer sees on the party - DoTs, curses, poisons, disease. type nil = not dispellable (bleed).
local DEBUFFS = {
  { name = "Corruption", type = "Magic", icon = "Interface\\Icons\\Spell_Shadow_AbominationExplosion", duration = 18 },
  { name = "Curse of Agony", type = "Curse", icon = "Interface\\Icons\\Spell_Shadow_CurseOfSargeras", duration = 24 },
  { name = "Deadly Poison", type = "Poison", icon = "Interface\\Icons\\Ability_Rogue_DualWeild", duration = 12, count = 3 },
  { name = "Plague", type = "Disease", icon = "Interface\\Icons\\Spell_Shadow_CallofBone", duration = 30 },
  { name = "Rend", icon = "Interface\\Icons\\Ability_Gouge", duration = 9 },
  { name = "Sleep", type = "Magic", icon = "Interface\\Icons\\Spell_Nature_Sleep", duration = 20 },
}
-- helpful: mine (source player) and other people's
local BUFFS = {
  { name = "Renew", source = "player", icon = "Interface\\Icons\\Spell_Holy_Renew", duration = 15 },
  { name = "Power Word: Shield", source = "player", icon = "Interface\\Icons\\Spell_Holy_PowerWordShield", duration = 30 },
  { name = "Power Word: Fortitude", source = "party2", icon = "Interface\\Icons\\Spell_Holy_WordFortitude", duration = 1800 },
  { name = "Mark of the Wild", source = "party3", icon = "Interface\\Icons\\Spell_Nature_Regeneration", duration = 1800 },
  { name = "Rejuvenation", source = "party3", icon = "Interface\\Icons\\Spell_Nature_Rejuvenation", duration = 12 },
}

local function now() return (type(GetTime) == "function" and GetTime()) or 0 end

--- A fresh copy of an aura template with a live expiry.
local function aura(t)
  local a = {}
  for k, v in pairs(t) do a[k] = v end
  if a.duration then a.expires = now() + a.duration end
  return a
end

local function makeFake(i)
  local f = {
    name = NAMES[(i - 1) % #NAMES + 1] .. (i > #NAMES and tostring(i) or ""),
    class = CLASSES[(i - 1) % #CLASSES + 1],
    health = 30 + ((i * 37) % 70), maxHealth = 100, power = 100 - ((i * 13) % 60), maxPower = 100,
    powerType = (i % 3 == 0) and "RAGE" or "MANA",
    guid = "Fake-" .. i, auras = {}, inRange = (i % 10 ~= 0), threat = (i % 7 == 0) and 3 or 0,
    subgroup = math.ceil(i / 5),
  }
  local r = i % 10
  -- the old spread (every unit 1, 4, 7 carries a dispellable one) kept; the rest get a DoT, a bleed or nothing
  if r == 1 or r == 4 or r == 7 then f.auras[#f.auras + 1] = aura(DEBUFFS[(i % 4) + 1]) end
  if r == 2 or r == 5 then f.auras[#f.auras + 1] = aura(DEBUFFS[1]) f.auras[#f.auras + 1] = aura(DEBUFFS[5]) end
  if r == 3 then f.auras[#f.auras + 1] = aura(DEBUFFS[2]) end
  -- buffs: everyone has Fortitude, some have my HoT / shield, a druid's mark here and there
  f.auras[#f.auras + 1] = aura(BUFFS[3])
  if i % 2 == 0 then f.auras[#f.auras + 1] = aura(BUFFS[1]) end
  if i % 8 == 2 then f.auras[#f.auras + 1] = aura(BUFFS[2]) end
  if i % 3 == 0 then f.auras[#f.auras + 1] = aura(BUFFS[4]) end
  if i % 5 == 0 then f.auras[#f.auras + 1] = aura(BUFFS[5]) end
  return f
end

local function mirror(i, f)
  if MockUnits then MockUnits["hhtest" .. i] = f end
end

--- Harmful / helpful halves of a fake's aura list (a debuff carries `type` or no `source`; a buff has a source).
function TestMode.Split(f)
  local harmful, helpful = {}, {}
  for _, a in ipairs(f.auras or {}) do
    if a.source then helpful[#helpful + 1] = a else harmful[#harmful + 1] = a end
  end
  return harmful, helpful
end

--- Direct painter for the real client (no unit API for fake units).
local function paint(button, f)
  button.health:SetMinMaxValues(0, f.maxHealth)
  button.health:SetValue(f.health)
  local c = RAID_CLASS_COLORS[f.class]
  if c then button.health:SetStatusBarColor(c.r, c.g, c.b) end
  local ap = HH.db.profile.frames.appearance
  button.name:SetText(f.name:sub(1, ap.nameLength or 8))
  button.healthText:SetText(f.health < f.maxHealth and ("-" .. (f.maxHealth - f.health)) or "")
  if f.powerType == "MANA" or not ap.powerHealerOnly then
    button.power:SetMinMaxValues(0, f.maxPower); button.power:SetValue(f.power); button.power:Show()
  else button.power:Hide() end
  local class = HHF.Compat and HHF.Compat.ClassOf and HHF.Compat.ClassOf("player")
  if not class then local _, c2 = UnitClass("player") class = c2 end
  local harmful, helpful = TestMode.Split(f)
  local d = harmful[1]
  if d and d.type and HH.CanDispel(class, d.type) then
    button.dispelIcon:SetTexture(d.icon); button.dispelIcon:Show()
  else button.dispelIcon:Hide() end
  local shield = false
  for _, a in ipairs(helpful) do if a.name == "Power Word: Shield" then shield = true end end
  button.shieldIcon:SetShown(shield and class == "PRIEST")
  button.aggroBorder:SetShown(f.threat >= 2)
  button:SetAlpha(f.inRange and 1 or (ap.outOfRangeAlpha or 0.4))
  for _, hook in ipairs(HHF.TestHooks) do
    local ok, err = pcall(hook, button, f)
    if not ok then HH:LogError("test mode hook: " .. tostring(err)) end
  end
end

--- Called by UnitButton.UpdateAll for a flagged fake button. True = painted here, the elements must not run.
-- In the harness (MockUnits present) the elements run instead, unless forcePaint asks for the real-client path.
function TestMode.PaintFake(button)
  if MockUnits and not TestMode.forcePaint then return false end
  local f = button.hhFake and TestMode.units[button.hhFake]
  if not f then return true end
  local ok, err = pcall(paint, button, f)
  if not ok then HH:LogError("test mode paint: " .. tostring(err)) end
  return true
end

local function tick()
  if not TestMode.active then return end
  local t = now()
  for i, f in ipairs(TestMode.units) do
    local delta = ((i * 7 + math.floor(t)) % 21) - 10
    if delta == 0 then delta = 5 end
    f.health = math.max(1, math.min(f.maxHealth, f.health + delta))
    -- an expired aura comes straight back, so the swipes keep turning for as long as the test runs
    for _, a in ipairs(f.auras) do
      if a.duration and a.expires and t >= a.expires then a.expires = t + a.duration end
    end
    mirror(i, f)
    local b = TestMode.buttons[i]
    if b then
      if MockUnits and not TestMode.forcePaint then HHF.UnitButton.UpdateAll(b) else paint(b, f) end
    end
  end
end

--- Where fake i goes. The party row grows from its middle (Headers: LEFT of the row on the anchor's CENTRE); every
-- other layout hangs off the anchor's TOPLEFT. Pure, for the tests: returns point, relativePoint, x, y.
function TestMode.Place(cfg, pts, i, n)
  local p = pts[i]
  if cfg.growth == "CENTER" then
    local rowW = n * (cfg.width or 0) + math.max(0, n - 1) * (cfg.spacing or 0)
    return "LEFT", "CENTER", -rowW / 2 + p.x, p.y
  end
  return "TOPLEFT", "TOPLEFT", p.x, p.y
end

local function start(n)
  TestMode.Stop(true)
  TestMode.active = true
  TestMode.count = n
  local bucket = HH.BucketForSize(n, n > 5)
  TestMode.bucket = bucket
  local cfg = HHF.module and HHF.module.ResolveLayout and HHF.module.ResolveLayout(bucket) or HH.db.profile.frames.layouts[bucket]
  if type(cfg) ~= "table" then error("no layout for bucket " .. tostring(bucket)) end
  local pts = HHF.Layout.Compute(cfg, n)
  local anchor = HHF.Headers and HHF.Headers.anchor or UIParent
  for i = 1, n do
    local f = makeFake(i)
    TestMode.units[i] = f
    mirror(i, f)
    local name = "HogHealsTest" .. i
    local b = _G[name] or HHF.UnitButton.Create(name, UIParent, false)
    TestMode.buttons[i] = b
    b.hhFake = i
    b.unit = "hhtest" .. i
    b:SetSize(cfg.width, cfg.height)
    b:ClearAllPoints()
    local point, rel, x, y = TestMode.Place(cfg, pts, i, n)
    b:SetPoint(point, anchor, rel, x, y)
    b:Show()
    if MockUnits and not TestMode.forcePaint then HHF.UnitButton.UpdateAll(b) else paint(b, f) end
  end
  -- hide the real headers while testing so they don't overlap
  HH:RunOutOfCombat(function()
    if HHF.Headers and HHF.Headers.party then HHF.Headers.party:Hide() end
    for _, r in pairs(HHF.Headers and HHF.Headers.raid or {}) do r:Hide() end
  end)
  if TestMode.ticker then TestMode.ticker:Cancel() end
  TestMode.ticker = C_Timer.NewTicker(1, tick)
  HH:Print(("Test mode: %d fake units (%s layout). /hh test off to stop."):format(n, bucket))
end

function TestMode.Start(n)
  n = tonumber(n) or 10
  if InCombatLockdown() then
    HH:Print("Test mode can't start in combat.")
    return false
  end
  if n < 1 then n = 1 elseif n > 40 then n = 40 end
  local ok, err = pcall(start, n)
  if not ok then
    TestMode.active = false
    HH:Print("Test mode failed: " .. tostring(err))
    HH:LogError("test mode: " .. tostring(err))
    return false
  end
  return true
end

function TestMode.Stop(silent)
  local was = TestMode.active
  TestMode.active = false
  if TestMode.ticker then TestMode.ticker:Cancel(); TestMode.ticker = nil end
  for i, b in ipairs(TestMode.buttons) do
    b:Hide()
    b.unit = nil
    b.hhFake = nil
    if MockUnits then MockUnits["hhtest" .. i] = nil end
  end
  wipe(TestMode.units)
  if was and HHF.module then HHF.module:ApplyProfile(HH:CurrentBucket()) end
  if was and not silent then HH:Print("Test mode off.") end
  return true
end

HH:RegisterSlash("test", function(rest)
  rest = strtrim(rest or "")
  if rest == "off" or rest == "stop" then TestMode.Stop() return end
  TestMode.Start(tonumber(rest) or 10)
end, "test [N|off] - show N fake units (5 = party layout, 10/25/40 = raid)")
