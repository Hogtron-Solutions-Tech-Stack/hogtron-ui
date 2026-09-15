-- /hh test N — fake party/raid with simulated health, auras, dispels, range (Danders pattern).
HogHealsFrames = HogHealsFrames or {}
local HHF = HogHealsFrames
local HH = HogHeals

local TestMode = { active = false, units = {}, buttons = {} }
HHF.TestMode = TestMode

local CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "SHAMAN", "DRUID", "HUNTER", "WARLOCK", "PALADIN" }
local NAMES = { "Hognificent", "Zugzug", "Brianna", "Anthony", "Restohog", "Fable", "Penny", "Scoop", "Boar", "Tusk" }
local DEBUFFS = {
  { name = "Sleep", type = "Magic", icon = "Interface\\Icons\\Spell_Nature_Sleep" },
  { name = "Curse of Weakness", type = "Curse", icon = "Interface\\Icons\\Spell_Shadow_CurseOfMannoroth" },
  { name = "Deadly Poison", type = "Poison", icon = "Interface\\Icons\\Ability_Rogue_DualWeild" },
  { name = "Plague", type = "Disease", icon = "Interface\\Icons\\Spell_Shadow_CallofBone" },
}

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
  if r == 1 or r == 4 or r == 7 then f.auras[1] = DEBUFFS[(i % #DEBUFFS) + 1] end
  if i % 8 == 2 then f.auras[#f.auras + 1] = { name = "Power Word: Shield", source = "player", expires = 15 } end
  return f
end

local function mirror(i, f)
  if MockUnits then MockUnits["hhtest" .. i] = f end
end

local function paint(button, f)
  -- Direct painter for the real client (no unit API for fake units).
  button.health:SetMinMaxValues(0, f.maxHealth)
  button.health:SetValue(f.health)
  local c = RAID_CLASS_COLORS[f.class]
  if c then button.health:SetStatusBarColor(c.r, c.g, c.b) end
  button.name:SetText(f.name:sub(1, HH.db.profile.frames.appearance.nameLength or 8))
  button.healthText:SetText(f.health < f.maxHealth and ("-" .. (f.maxHealth - f.health)) or "")
  if f.powerType == "MANA" or not HH.db.profile.frames.appearance.powerHealerOnly then
    button.power:SetMinMaxValues(0, f.maxPower); button.power:SetValue(f.power); button.power:Show()
  else button.power:Hide() end
  local _, class = UnitClass("player")
  local d = f.auras[1]
  if d and d.type and HH.CanDispel(class, d.type) then
    button.dispelIcon:SetTexture(d.icon); button.dispelIcon:Show()
  else button.dispelIcon:Hide() end
  button.shieldIcon:SetShown(f.auras[2] ~= nil and class == "PRIEST")
  button.aggroBorder:SetShown(f.threat >= 2)
  button:SetAlpha(f.inRange and 1 or (HH.db.profile.frames.appearance.outOfRangeAlpha or 0.4))
end

local function tick()
  if not TestMode.active then return end
  for i, f in ipairs(TestMode.units) do
    local delta = ((i * 7 + math.floor(GetTime())) % 21) - 10
    if delta == 0 then delta = 5 end
    f.health = math.max(1, math.min(f.maxHealth, f.health + delta))
    mirror(i, f)
    local b = TestMode.buttons[i]
    if b then
      if MockUnits then HHF.UnitButton.UpdateAll(b) else paint(b, f) end
    end
  end
end

function TestMode.Start(n)
  n = tonumber(n) or 10
  if InCombatLockdown() then
    HH:Print("Test mode can't start in combat.")
    return false
  end
  if n < 1 then n = 1 elseif n > 40 then n = 40 end
  TestMode.Stop(true)
  TestMode.active = true
  TestMode.count = n
  local bucket = HH.BucketForSize(n, n > 5)
  local cfg = HH.db.profile.frames.layouts[bucket]
  local pts = HHF.Layout.Compute(cfg, n)
  local anchor = HHF.Headers and HHF.Headers.anchor or UIParent
  for i = 1, n do
    local f = makeFake(i)
    TestMode.units[i] = f
    mirror(i, f)
    local name = "HogHealsTest" .. i
    local b = _G[name] or HHF.UnitButton.Create(name, UIParent, false)
    TestMode.buttons[i] = b
    b.unit = "hhtest" .. i
    b:SetSize(cfg.width, cfg.height)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", anchor, "TOPLEFT", pts[i].x, pts[i].y)
    b:Show()
    if MockUnits then HHF.UnitButton.UpdateAll(b) else paint(b, f) end
  end
  -- hide the real headers while testing so they don't overlap
  HH:RunOutOfCombat(function()
    if HHF.Headers and HHF.Headers.party then HHF.Headers.party:Hide() end
    for _, r in pairs(HHF.Headers and HHF.Headers.raid or {}) do r:Hide() end
  end)
  if TestMode.ticker then TestMode.ticker:Cancel() end
  TestMode.ticker = C_Timer.NewTicker(1, tick)
  HH:Print(("Test mode: %d fake units. /hh test off to stop."):format(n))
  return true
end

function TestMode.Stop(silent)
  local was = TestMode.active
  TestMode.active = false
  if TestMode.ticker then TestMode.ticker:Cancel(); TestMode.ticker = nil end
  for i, b in ipairs(TestMode.buttons) do
    b:Hide()
    b.unit = nil
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
end, "test [N|off] — show N fake units")
