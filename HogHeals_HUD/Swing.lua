-- Swing timer: one flat HogUI bar for the player's auto-attack (main hand, or Auto Shot / wand when that is what
-- you are doing), right under the cast bar. On / off in the HUD options (Sean 2026-10-01).
--
-- Where the swings come from - a ladder, best source wins, every rung is recorded for /hh swingdiag:
--   1. COMBAT_LOG_EVENT_UNFILTERED  SWING_DAMAGE / SWING_MISSED / RANGE_* from the player, plus on-next-swing casts
--      (Heroic Strike, Raptor Strike, Maul, Cleave) - exact. ONLY on clients without the restricted API: on WoW:
--      Forever registering it raised the "blocked from an action only available to the Blizzard UI" popup
--      (2026-09-17), and pcall does not contain that. Never try it there.
--   2. UNIT_SPELLCAST_SUCCEEDED for Auto Shot (75), Shoot (5019) and - if this client reports it - Auto Attack
--      (6603). Ranged swings are exact everywhere this fires.
--   3. PLAYER_ENTER_COMBAT / PLAYER_LEAVE_COMBAT (auto-attack toggled on / off) + UnitAttackSpeed: a free-running
--      bar at weapon speed from the moment you start attacking. Honest estimate - it drifts when you are out of range.
-- Speeds can be secret values on restricted clients: a secret speed is ignored and the last plain one kept.
HogHealsHUD = HogHealsHUD or {}
local HHD = HogHealsHUD
local HH = HogHeals

local Swing = { state = { active = false, kind = nil, start = 0, period = 2, source = nil },
  speeds = { mh = 2.0, oh = nil, ranged = 2.0 }, seen = {} }
HHD.Swing = Swing

local CREAM = { 0.96, 0.92, 0.86 }
local RANGED_SPELLS = { [75] = "Auto Shot", [5019] = "Shoot", [7918] = "Shoot", [7919] = "Shoot", [7920] = "Shoot" }
local MELEE_SPELLS = { [6603] = "Attack" }
-- on-next-swing abilities: the swing that lands them resets the timer like a white hit
Swing.NEXT_SWING = { [78] = true, [284] = true, [285] = true, [1608] = true, [11564] = true, [11565] = true, [11566] = true,
  [11567] = true, [25286] = true, [29707] = true, [30324] = true,   -- Heroic Strike ranks
  [845] = true, [7369] = true, [11608] = true, [11609] = true, [20569] = true, [25231] = true,   -- Cleave
  [2973] = true, [14260] = true, [14261] = true, [14262] = true, [14263] = true, [14264] = true, [14265] = true, [14266] = true, [27014] = true,   -- Raptor Strike
  [6807] = true, [6808] = true, [6809] = true, [8972] = true, [9745] = true, [9880] = true, [9881] = true, [26996] = true }   -- Maul

local function cfg() return HH.db.profile.hud.swing end
local function hud() return HH.db.profile.hud end
local function bar() return HHD.HUD.rows.swing end
local function num(v) if type(v) == "number" and not HH.IsSecret(v) and v > 0 then return v end end
local function count(k) Swing.seen[k] = (Swing.seen[k] or 0) + 1 end

--- Is the combat log ours to read here? Restricted-API clients (issecretvalue exists) say no, always.
function Swing.CombatLogAllowed()
  return type(issecretvalue) ~= "function" and type(CombatLogGetCurrentEventInfo) == "function"
end

--- Weapon speeds, kept only when they are plain numbers (secret speeds leave the last known value in place).
function Swing.ReadSpeeds()
  if type(UnitAttackSpeed) == "function" then
    local ok, mh, oh = pcall(UnitAttackSpeed, "player")
    if ok then
      if num(mh) then Swing.speeds.mh = mh end
      if HH.IsSecret(mh) then Swing.seen.secretSpeed = (Swing.seen.secretSpeed or 0) + 1 end
      Swing.speeds.oh = num(oh) or nil
    end
  end
  if type(UnitRangedDamage) == "function" then
    local ok, rs = pcall(UnitRangedDamage, "player")
    if ok and num(rs) then Swing.speeds.ranged = rs end
  end
  return Swing.speeds
end

--- 0..1 fill at `now`: a swing bar fills up toward the next swing.
function Swing.Progress(state, now)
  if not state.active or (state.period or 0) <= 0 then return 0 end
  local p = (now - state.start) / state.period
  if p < 0 then p = 0 elseif p > 1 then p = 1 end
  return p
end

local function paint(label)
  local b = bar()
  if not b then return end
  local c = cfg()
  local col = c.color or CREAM
  b:SetStatusBarColor(col[1], col[2], col[3])
  b.text:SetText(c.text ~= false and (label or "") or "")
  b:SetMinMaxValues(0, 1)
  b:SetValue(0)
  if b.enabled ~= false then b:Show() end
  b:SetScript("OnUpdate", function(self) Swing.OnUpdate(self) end)
  Swing.OnUpdate(b)
end

--- A swing just happened (or auto-attack just started): the bar restarts now.
--   kind   "melee" | "ranged"
--   source "cleu" | "cast" | "toggle" | "roll"  (roll = free-running continuation)
function Swing.Start(kind, source, now, label)
  now = now or GetTime()
  local s = Swing.state
  local sp = Swing.ReadSpeeds()
  s.active, s.kind, s.start, s.source = true, kind, now, source
  s.period = (kind == "ranged" and sp.ranged or sp.mh) or 2.0
  s.label = label or (kind == "ranged" and "Ranged" or "Swing")
  s.attacking = true
  s.lastEvent = now
  paint(s.label)
  -- a per-swing source arriving means the free-running estimate is no longer needed
  if source == "cleu" or source == "cast" then Swing.exact = true end
end

function Swing.Stop()
  local s = Swing.state
  s.active, s.attacking = false, false
  local b = bar()
  if not b then return end
  b:SetScript("OnUpdate", nil)
  if cfg().hideWhenIdle ~= false then b:Hide() else b:SetValue(0) b.time:SetText("") end
end

function Swing.OnUpdate(b)
  local s = Swing.state
  if not s.active then return end
  local now = GetTime()
  local p = Swing.Progress(s, now)
  b:SetValue(p)
  local remaining = math.max(0, s.start + s.period - now)
  local places = cfg().precision or 1
  b.time:SetText(cfg().text ~= false and (("%." .. places .. "f"):format(remaining)) or "")
  if now >= s.start + s.period then
    if Swing.exact then
      -- an exact source tells us about the next swing; nothing for two periods = out of range / stopped
      if now >= s.lastEvent + 2 * s.period then Swing.Stop() end
    elseif s.attacking then
      -- free-running: the next swing starts where this one ended (phase kept, period re-read)
      local sp = Swing.ReadSpeeds()
      local period = (s.kind == "ranged" and sp.ranged or sp.mh) or s.period
      s.start, s.period, s.source = s.start + s.period, period, "roll"
      if now - s.start > period then s.start = now end   -- fell far behind (loading screen): resync
    else
      Swing.Stop()
    end
  end
end

-- ---------------------------------------------------------------- events
local handlers = {}

function handlers.PLAYER_ENTER_COMBAT()
  count("enterCombat")
  if not Swing.state.active then Swing.Start("melee", "toggle") else Swing.state.attacking = true end
end

function handlers.PLAYER_LEAVE_COMBAT()
  count("leaveCombat")
  Swing.state.attacking = false
  if not Swing.exact then Swing.Stop() end
end

function handlers.PLAYER_REGEN_ENABLED()
  -- out of combat entirely: nothing swings
  if Swing.state.active and not Swing.state.attacking then Swing.Stop() end
end

function handlers.UNIT_ATTACK_SPEED() count("attackSpeed") Swing.ReadSpeeds() end
function handlers.UNIT_RANGEDDAMAGE() Swing.ReadSpeeds() end
function handlers.PLAYER_EQUIPMENT_CHANGED() Swing.ReadSpeeds() end

function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
  if unit ~= "player" then return end
  if HH.IsSecret(spellID) then count("secretSpellID") return end
  if RANGED_SPELLS[spellID] then count("cast" .. spellID) Swing.Start("ranged", "cast", nil, RANGED_SPELLS[spellID])
  elseif MELEE_SPELLS[spellID] then count("cast6603") Swing.Start("melee", "cast", nil, "Attack") end
end

function handlers.COMBAT_LOG_EVENT_UNFILTERED()
  local _, sub, _, sourceGUID, _, _, _, _, _, _, _, spellID = CombatLogGetCurrentEventInfo()
  if sourceGUID ~= UnitGUID("player") then return end
  if sub == "SWING_DAMAGE" or sub == "SWING_MISSED" then count("cleuSwing") Swing.Start("melee", "cleu")
  elseif sub == "RANGE_DAMAGE" or sub == "RANGE_MISSED" then count("cleuRange") Swing.Start("ranged", "cleu", nil, RANGED_SPELLS[spellID] or "Ranged")
  elseif sub == "SPELL_CAST_SUCCESS" and Swing.NEXT_SWING[spellID] then count("cleuNextSwing") Swing.Start("melee", "cleu") end
end

function Swing.OnEvent(_, event, ...)
  if hud().showSwing == false then return end
  local h = handlers[event]
  if not h then return end
  local ok, err = pcall(h, ...)
  if not ok then HH:LogError("swing " .. event .. ": " .. tostring(err)) end
end

function Swing.Init()
  if Swing.frame then return end
  local f = CreateFrame("Frame")
  Swing.registered, Swing.unknown = {}, {}
  local function reg(ev, unit)
    local ok
    if unit and f.RegisterUnitEvent then ok = pcall(f.RegisterUnitEvent, f, ev, unit) else ok = pcall(f.RegisterEvent, f, ev) end
    if ok then Swing.registered[#Swing.registered + 1] = ev else Swing.unknown[#Swing.unknown + 1] = ev end
  end
  -- every one pcall-registered: the Forever beta throws on event names it does not know
  reg("PLAYER_ENTER_COMBAT") reg("PLAYER_LEAVE_COMBAT") reg("PLAYER_REGEN_ENABLED") reg("PLAYER_EQUIPMENT_CHANGED")
  reg("UNIT_ATTACK_SPEED", "player") reg("UNIT_RANGEDDAMAGE", "player") reg("UNIT_SPELLCAST_SUCCEEDED", "player")
  Swing.cleu = Swing.CombatLogAllowed()
  if Swing.cleu then reg("COMBAT_LOG_EVENT_UNFILTERED") end   -- see the header: never on a restricted client
  f:SetScript("OnEvent", Swing.OnEvent)
  Swing.frame = f
  Swing.ReadSpeeds()
  Swing.Refresh()
end

function Swing.Refresh()
  local b = bar()
  if not b then return end
  if hud().showSwing == false then Swing.Stop() b:Hide() return end
  if Swing.state.active then paint(Swing.state.label) elseif cfg().hideWhenIdle ~= false then b:Hide() else b:Show() b:SetValue(0) b.time:SetText("") b.text:SetText("") end
end

--- What this client gave us, for /hh swingdiag and diag.swing.
function Swing.Probe()
  local s = Swing.state
  local seen = {}
  for k, v in pairs(Swing.seen) do seen[#seen + 1] = k .. "=" .. tostring(v) end
  table.sort(seen)
  return {
    combatLog = Swing.cleu and "registered" or "not allowed here",
    registered = table.concat(Swing.registered or {}, ","), unknown = table.concat(Swing.unknown or {}, ","),
    speeds = ("mh=%s oh=%s ranged=%s"):format(tostring(Swing.speeds.mh), tostring(Swing.speeds.oh), tostring(Swing.speeds.ranged)),
    seen = table.concat(seen, ","), exact = Swing.exact and "yes" or "no (free-running estimate)",
    state = ("active=%s kind=%s source=%s period=%s"):format(tostring(s.active), tostring(s.kind), tostring(s.source), tostring(s.period)),
  }
end

function Swing.WriteDiag()
  local g = HH.db and HH.db.global
  if not g then return end
  g.diag = g.diag or {}
  local ok, p = pcall(Swing.Probe)
  g.diag.swing = ok and p or ("probe failed: " .. tostring(p))
  if type(g.diag.swing) == "table" then g.diag.swing.at = date and date("%Y-%m-%d %H:%M:%S") or "" end
end

HH:RegisterSlash("swingdiag", function()
  Swing.WriteDiag()
  local p = Swing.Probe()
  HH:Print(("swing: combat log %s | %s | exact: %s"):format(p.combatLog, p.speeds, p.exact))
  HH:Print("swing events seen: " .. (p.seen ~= "" and p.seen or "none yet") .. (p.unknown ~= "" and (" | unknown: " .. p.unknown) or ""))
  HH:Print("swing " .. p.state)
end, "print where the swing timer gets its swings from on this client")
