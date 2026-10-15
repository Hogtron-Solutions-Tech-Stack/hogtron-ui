-- ObjectGlow: ore veins, herbs, chests, quest objects and your fishing bobber light up as you come near. Sean
-- 2026-10-14, from the WoW Forever add-on clip (#4 Lueur): "highlight herb and ore nodes on your screen as well as
-- chests and items that you need to pick up from quests".
--
-- How - Blizzard's soft targeting, the route the Forever build of Lueur takes too (our own code and art):
--   * SoftTargetInteract = 3: the game keeps ONE interactable object near you picked (the "softinteract" unit),
--     out to SoftTargetInteractRange yards;
--   * SoftTargetNameplateInteract = 1 + SoftTargetIconGameObject = 1: that object gets a nameplate (the Forever beta
--     resets SoftTargetIconGameObject after loading screens - re-applied on every PLAYER_ENTERING_WORLD);
--   * our glow sits on that nameplate (parented to it: it follows, fades and hides with it), tinted by kind.
--   One object at a time - the one the game picked - never a scan of everything on screen.
-- Kind = the cursor the game would show over the object (SetUnitCursorTexture onto a hidden texture): Mine = ore,
-- GatherHerbs = herb, Quest* = quest, PickLock / LootAll / Pickup = chest, an "Unable..." cursor = you cannot use it
-- yet (grey, still). Then: object 35591 = your bobber; a quest line on its tooltip or its name in an open objective
-- (QuestMobs) = quest; a chest word in its name = chest; a service cursor (mailbox) never turns into a chest.
-- The cvars are remembered (account-wide) and given back when the glow is turned off and at logout, so the client is
-- never left on our values if HogTron UI goes away. Never written in combat (queued until it ends).
-- Game-object plates are not skinned as unit plates (Plates.Added skips them). The glow never takes the mouse.
HogHealsPlates = HogHealsPlates or {}
local HHP = HogHealsPlates
local HH = HogHeals

local G = { cursorIDs = {}, seen = {}, objectUnits = {}, last = {} }
HHP.ObjectGlow = G

local SOFT = "softinteract"
local MEDIA = "Interface\\AddOns\\HogHeals\\Media\\"
local HALO, RING, SPARK = MEDIA .. "target_glow", MEDIA .. "object_ring", MEDIA .. "object_spark"
local TWO_PI = 2 * math.pi

local function cfg() local pr = HH.db and HH.db.profile return (pr and pr.plates and pr.plates.objectGlow) or {} end
local function g(name) local f = rawget(_G, name) if type(f) == "function" then return f end end
local function fn(tbl, name) if type(tbl) == "table" and type(tbl[name]) == "function" then return tbl[name] end end
local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function str(v) if type(v) == "string" and not isSecret(v) then return v end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(f, ...)
  if ok then return a, b, c, d end
end
local function count(k) G.seen[k] = (G.seen[k] or 0) + 1 end

-- ------------------------------------------------------------------------------------------------ kinds
G.COLORS = { herb = { 0.35, 0.90, 0.40 }, ore = { 0.95, 0.55, 0.20 }, chest = { 1.00, 0.80, 0.25 },
  quest = { 0.13, 0.83, 0.88 }, bobber = { 0.70, 0.85, 1.00 }, other = { 0.96, 0.92, 0.86 } }
G.BLOCKED = { 0.55, 0.55, 0.60 }
G.KINDS = { "herb", "ore", "chest", "quest", "bobber", "other" }
G.KIND_NAMES = { herb = "Herbs", ore = "Ore veins", chest = "Chests and crates", quest = "Quest objects",
  bobber = "Your fishing bobber", other = "Anything else you can use (levers, doors, books)" }

-- Interface\Cursor\<name> -> kind (Forever cursor names as Lueur read them from WowB.exe; the same set modern clients
-- use). "service" = the cursor says what the object is (a mailbox): never re-read as a chest or quest by its name.
G.CURSORS = { Mine = "ore", GatherHerbs = "herb",
  Quest = "quest", QuestRepeatable = "quest", QuestTurnIn = "quest", QuestInteract = "quest",
  PickLock = "chest", LootAll = "chest", Pickup = "chest", Fishing = "bobber",
  Interact = "other", Inspect = "other", GamepadInteract = "other",
  Mail = "service", Speak = "service", Buy = "service", Trainer = "service", Taxi = "service", Innkeeper = "service",
  Repair = "service", Stablemaster = "service" }
-- when the client hands back a path or an atlas name instead of a known file id: substrings, lowercase, in order
G.CURSOR_WORDS = { { "gatherherb", "herb" }, { "herb", "herb" }, { "mine", "ore" }, { "mining", "ore" }, { "quest", "quest" },
  { "picklock", "chest" }, { "lootall", "chest" }, { "pickup", "chest" }, { "fishing", "bobber" }, { "mail", "service" } }
G.CHEST_WORDS = { "chest", "coffer", "strongbox", "lockbox", "footlocker", "trunk", "crate", "cache", "stash", "barrel",
  "box", "sack", "casket", "satchel", "basket" }
G.BOBBER = { [35591] = true }

--- Pure: a cursor (file id, path, file name or atlas) -> kind, blocked. blocked = the "Unable..." variant.
function G.CursorKind(c)
  if type(c) == "number" then
    local hit = G.cursorIDs[c]
    if hit then return hit[1], hit[2] end
    return nil, false
  end
  if type(c) ~= "string" or c == "" then return nil, false end
  local base = (c:match("([^\\/]+)$") or c):gsub("%.[bB][lL][pP]$", "")
  local blocked = false
  if base:sub(1, 6) == "Unable" then blocked, base = true, base:sub(7) end
  if G.CURSORS[base] then return G.CURSORS[base], blocked end
  local low = c:lower()
  if low:find("unable", 1, true) then blocked = true end
  for _, w in ipairs(G.CURSOR_WORDS) do
    if low:find(w[1], 1, true) then return w[2], blocked end
  end
  return nil, blocked
end

--- Pure: does an object's name read like a container? Whole words only ("Battered Chest", "Food Crate"), plus a
-- word that ends in one ("Strongbox", "Lockbox").
function G.ChestName(name)
  name = str(name)
  if not name then return false end
  for word in name:lower():gmatch("[%a']+") do
    for _, w in ipairs(G.CHEST_WORDS) do
      if word == w or word == w .. "s" or (#word > #w and word:sub(-#w) == w) then return true end
    end
  end
  return false
end

--- Pure: the object id inside a GameObject GUID ("GameObject-0-1-2-3-<id>-<spawn>").
function G.ObjectID(guid)
  guid = str(guid)
  return guid and tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)")) or nil
end

--- Pure: what kind of object this is -> kind, blocked. cursor as for CursorKind; id = object id; quest = true when
-- QuestMobs found it in an open objective; name = the object's name.
function G.Classify(cursor, id, quest, name)
  local kind, blocked = G.CursorKind(cursor)
  if id and G.BOBBER[id] then return "bobber", false end
  if kind == "ore" or kind == "herb" or kind == "bobber" then return kind, blocked end
  if kind == "service" then return "other", blocked end
  if quest or kind == "quest" then return "quest", blocked end
  if (kind == nil or kind == "other" or kind == "chest") and G.ChestName(name) then return "chest", blocked end
  return kind or "other", blocked
end

-- ------------------------------------------------------------------------------------------------ reading the object
function G.BuildCursorIDs()
  local f = g("GetFileIDFromPath")
  if not f then return 0 end
  local n = 0
  for name, kind in pairs(G.CURSORS) do
    for _, prefix in ipairs({ "", "Unable" }) do
      local path = "Interface\\Cursor\\" .. prefix .. name
      local id = call(f, path) or call(f, path .. ".blp")
      if type(id) == "number" and not isSecret(id) then G.cursorIDs[id] = { kind, prefix ~= "" } n = n + 1 end
    end
  end
  return n
end

--- The cursor the game would show over a unit: file id when known, else the texture path / atlas. nil = none.
function G.ReadCursor(unit)
  local set = g("SetUnitCursorTexture")
  if not set then G.last.cursorPath = "no SetUnitCursorTexture" return nil end
  if not G.probe then
    G.probe = UIParent:CreateTexture(nil, "BACKGROUND")
    G.probe:Hide()
  end
  local ok, res = pcall(set, G.probe, unit, nil, true)
  if not ok or res == false then G.last.cursorPath = ok and "none" or "error" return nil end
  local tex = G.probe:GetTexture()
  local atlas = G.probe.GetAtlas and call(G.probe.GetAtlas, G.probe) or nil
  if isSecret(tex) then tex = nil end
  if isSecret(atlas) then atlas = nil end
  if type(tex) == "number" and not G.cursorIDs[tex] and type(atlas) == "string" then return atlas end
  return tex or atlas
end

--- The nameplate the game gave the picked object: "softinteract" directly, else any game-object plate that is it.
function G.PlateFor()
  local get = fn(rawget(_G, "C_NamePlate"), "GetNamePlateForUnit")
  if not get then return nil end
  local function usable(p) return type(p) == "table" and not (p.IsForbidden and call(p.IsForbidden, p)) end
  local plate = call(get, SOFT)
  if usable(plate) then G.via = "direct" return plate end
  for unit in pairs(G.objectUnits) do
    if call(g("UnitIsUnit"), unit, SOFT) == true then
      plate = call(get, unit)
      if usable(plate) then G.via = "sweep" return plate end
    end
  end
end

-- ------------------------------------------------------------------------------------------------ the glow
local function layer(f, file, level)
  local t = f:CreateTexture(nil, level)
  t:SetPoint("CENTER", f, "CENTER", 0, 0)
  local ok = t:SetTexture(file)
  if t.SetBlendMode then t:SetBlendMode("ADD") end
  if ok == false then t:SetColorTexture(1, 1, 1, 0.25) G.artMissing = true end
  return t
end

function G.Build()
  if G.frame then return G.frame end
  local f = CreateFrame("Frame", "HogTronUIObjectGlow", UIParent)
  f:SetSize(64, 64)
  if f.EnableMouse then f:EnableMouse(false) end   -- never between you and the right-click that loots it
  f.halo = layer(f, HALO, "BACKGROUND")
  f.ring = layer(f, RING, "ARTWORK")
  f.spark = layer(f, SPARK, "OVERLAY")
  f.label = f:CreateFontString(nil, "OVERLAY", "HogTronFontNormal")
  f.label:SetPoint("BOTTOM", f, "TOP", 0, 2)
  f:SetScript("OnUpdate", function(self, elapsed) G.Tick(elapsed) end)
  f:Hide()
  G.frame = f
  return f
end

--- Pure: one animation frame at t seconds after the glow appeared. Returns halo / ring / spark alpha, ring turn,
-- spark offset (fractions of the ring radius) and the lock-on scale (0.6 -> 1 over the first quarter second).
function G.Frame(t, intensity, blocked)
  intensity = intensity or 0.9
  local grow = math.min(1, (t or 0) / 0.25)
  local scale = 0.6 + 0.4 * (1 - (1 - grow) ^ 2)
  if blocked then
    return { halo = 0.25 * intensity, ring = 0.45 * intensity, spark = 0, turn = 0, sx = 0, sy = 0, scale = scale }
  end
  local breath = math.sin(t * TWO_PI / 2.4)
  local a = t * 1.1
  return { halo = intensity * (0.45 + 0.15 * breath), ring = intensity * (0.80 + 0.15 * breath),
    spark = intensity * (0.55 + 0.45 * math.abs(math.sin(t * 2.6))), turn = t * 0.6,
    sx = math.cos(a) * 0.72, sy = math.sin(a) * 0.72, scale = scale }
end

function G.Paint()
  local f, s = G.frame, G.shown
  if not f or not s then return end
  local o = cfg()
  local size = o.size or 56
  local fr = G.Frame(s.t, o.intensity, s.blocked)
  local c = s.blocked and G.BLOCKED or G.COLORS[s.kind] or G.COLORS.other
  local sz = size * fr.scale
  f:SetSize(sz, sz)
  f.halo:SetSize(sz * 1.7, sz * 1.7)
  f.ring:SetSize(sz, sz)
  f.spark:SetSize(sz * 0.42, sz * 0.42)
  f.halo:SetVertexColor(c[1], c[2], c[3], fr.halo)
  f.ring:SetVertexColor(c[1], c[2], c[3], fr.ring)
  f.spark:SetVertexColor(math.min(1, c[1] + 0.35), math.min(1, c[2] + 0.35), math.min(1, c[3] + 0.35), fr.spark)
  if f.ring.SetRotation then pcall(f.ring.SetRotation, f.ring, fr.turn) end
  f.spark:ClearAllPoints()
  f.spark:SetPoint("CENTER", f, "CENTER", fr.sx * sz / 2, fr.sy * sz / 2)
  G.lastFrame = fr
end

function G.Tick(elapsed)
  local s = G.shown
  if not s then return end
  s.t = s.t + (elapsed or 0)
  G.Paint()
end

function G.ShowGlow(plate, kind, blocked, name)
  local f, o = G.Build(), cfg()
  local same = G.shown and G.shown.plate == plate and G.shown.kind == kind
  if f:GetParent() ~= plate then f:SetParent(plate) end
  f:ClearAllPoints()
  f:SetPoint("CENTER", plate, "CENTER", 0, o.offset or 0)
  G.shown = { plate = plate, kind = kind, blocked = blocked, name = name, t = same and G.shown.t or 0 }
  if o.label ~= false and name then
    local c = blocked and G.BLOCKED or G.COLORS[kind] or G.COLORS.other
    f.label:SetText(name)
    f.label:SetTextColor(c[1], c[2], c[3])
    f.label:Show()
  else f.label:Hide() end
  G.Paint()
  f:Show()
  if not same then count("show:" .. kind) end
end

function G.HideGlow()
  G.shown = nil
  local f = G.frame
  if not f then return end
  f:Hide()
  f:ClearAllPoints()
  if f:GetParent() ~= UIParent then f:SetParent(UIParent) end
end

--- Look at what the game picked and show / move / hide the glow. Runs on every soft-target or plate change.
function G.Evaluate()
  local o = cfg()
  if o.enabled == false or G.previewing then if not G.previewing then G.HideGlow() end return end
  if call(g("UnitIsGameObject"), SOFT) ~= true then
    G.HideGlow()
    G.last.why = "nothing picked"
    return
  end
  local plate = G.PlateFor()
  if not plate then
    G.HideGlow()
    G.last.why = "the object has no nameplate (yet)"
    count("noPlate")
    return
  end
  local name = str(call(g("UnitName"), SOFT))
  local id = G.ObjectID(call(g("UnitGUID"), SOFT))
  local cursor = G.ReadCursor(SOFT)
  local QM = HHP.QuestMobs
  local quest = QM and QM.Check and call(QM.Check, SOFT) ~= nil or false
  local kind, blocked = G.Classify(cursor, id, quest, name)
  G.last = { name = name, kind = kind, blocked = blocked, cursor = tostring(cursor), id = id, via = G.via, cursorPath = G.last.cursorPath }
  local kinds = o.kinds or {}
  if kinds[kind] == false or (kind == "other" and kinds.other ~= true) or (blocked and o.hideBlocked) then
    G.HideGlow()
    G.last.why = "kind " .. kind .. " is switched off"
    count("filtered:" .. kind)
    return
  end
  G.last.why = nil
  G.ShowGlow(plate, kind, blocked, name)
end

-- ------------------------------------------------------------------------------------------------ cvars
G.MANAGED = { "SoftTargetInteract", "SoftTargetInteractRange", "SoftTargetNameplateInteract", "SoftTargetIconGameObject",
  "SoftTargetInteractOnlyInRange", "nameplateGameObjectMaxDistance" }

local function getCVar(k)
  local C = rawget(_G, "C_CVar")
  local v
  if fn(C, "GetCVar") then v = call(C.GetCVar, k) else v = call(g("GetCVar"), k) end
  if v == nil or isSecret(v) then return nil end
  return tostring(v)
end
local function setCVar(k, v)
  local C = rawget(_G, "C_CVar")
  if fn(C, "SetCVar") then return pcall(C.SetCVar, k, v) end
  return pcall(g("SetCVar") or function() error("no SetCVar") end, k, v)
end

function G.Store()
  local gl = HH.db and HH.db.global
  if not gl then G.mem = G.mem or {} return G.mem end
  gl.objectGlow = gl.objectGlow or {}
  return gl.objectGlow
end

--- The values we want, given the player's own originals (never shrink a plate distance they set wider).
function G.Wanted(saved)
  local r = math.floor(cfg().range or 15)
  local far = tonumber(saved and saved.nameplateGameObjectMaxDistance) or 0
  return { SoftTargetInteract = "3", SoftTargetInteractRange = tostring(r), SoftTargetNameplateInteract = "1",
    SoftTargetIconGameObject = "1", SoftTargetInteractOnlyInRange = "0", nameplateGameObjectMaxDistance = tostring(math.max(r, far)) }
end

--- Put our values on (originals remembered once, kept until the glow is turned off). Out of combat only.
function G.ApplyCVars()
  if InCombatLockdown() then G.pending = "apply" return false end
  local st = G.Store()
  if not st.saved then
    st.saved = {}
    for _, k in ipairs(G.MANAGED) do st.saved[k] = getCVar(k) or false end
  end
  G.missing = {}
  local wanted = G.Wanted(st.saved)
  for _, k in ipairs(G.MANAGED) do
    local want = wanted[k]
    if getCVar(k) == nil then G.missing[#G.missing + 1] = k
    elseif getCVar(k) ~= want then setCVar(k, want) end
  end
  st.applied, G.pending = true, nil
  return true
end

--- Give the player's values back. forget = also drop the memory (the glow was turned off); a logout keeps it so the
-- next login does not mistake our own values for the player's.
function G.RestoreCVars(forget)
  if InCombatLockdown() then G.pending = forget and "restore" or nil return false end
  local st = G.Store()
  if st.saved then
    for _, k in ipairs(G.MANAGED) do
      local v = st.saved[k]
      if v and getCVar(k) ~= nil then setCVar(k, v) end
    end
  end
  st.applied = false
  if forget then st.saved = nil end
  G.pending = nil
  return true
end

-- ------------------------------------------------------------------------------------------------ wiring
function G.Apply()
  if cfg().enabled == false then
    G.RestoreCVars(true)
    G.HideGlow()
  else
    G.ApplyCVars()
    G.Evaluate()
  end
end

function G.OnEvent(_, e, unit)
  if e == "PLAYER_LOGOUT" then
    G.WriteDiag()
    if G.Store().applied then G.RestoreCVars(false) end
    return
  end
  if e == "PLAYER_REGEN_ENABLED" then
    if G.pending == "apply" then G.ApplyCVars() elseif G.pending == "restore" then G.RestoreCVars(true) end
    return
  end
  if cfg().enabled == false then return end
  if e == "PLAYER_ENTERING_WORLD" then
    -- the Forever beta puts SoftTargetIconGameObject back to 0 after a loading screen: no object plates without it
    G.ApplyCVars()
    if type(C_Timer) == "table" and C_Timer.After then C_Timer.After(2, function() if cfg().enabled ~= false then G.ApplyCVars() G.Evaluate() end end) end
    G.Evaluate()
  elseif e == "NAME_PLATE_UNIT_ADDED" then
    if type(unit) == "string" and call(g("UnitIsGameObject"), unit) == true then G.objectUnits[unit] = true G.Evaluate() end
  elseif e == "NAME_PLATE_UNIT_REMOVED" then
    if G.objectUnits[unit] then G.objectUnits[unit] = nil G.Evaluate() end
  elseif e == "PLAYER_SOFT_INTERACT_CHANGED" or e == "QUEST_LOG_UPDATE" then
    G.Evaluate()
  end
end

--- Each kind on screen for 1.5 s, centred, no object needed (options button, /hh glow preview).
function G.Preview()
  local f = G.Build()
  G.previewing = true
  local names = { herb = "Peacebloom", ore = "Copper Vein", chest = "Battered Chest", quest = "Sack of Kobold Candles", bobber = "Fishing Bobber" }
  local order = { "herb", "ore", "chest", "quest", "bobber" }
  local function step(i)
    if i > #order then G.previewing = false G.HideGlow() G.Evaluate() return end
    G.HideGlow()
    f:SetParent(UIParent)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    G.shown = { plate = UIParent, kind = order[i], blocked = false, name = names[order[i]] .. " (preview)", t = 0 }
    if cfg().label ~= false then f.label:SetText(G.shown.name) local c = G.COLORS[order[i]] f.label:SetTextColor(c[1], c[2], c[3]) f.label:Show() else f.label:Hide() end
    G.Paint()
    f:Show()
    if type(C_Timer) == "table" and C_Timer.After then C_Timer.After(1.5, function() step(i + 1) end) end
  end
  step(1)
end

function G.Lines()
  local o, st = cfg(), G.Store()
  local out = {}
  out[#out + 1] = ("object glow: %s, range %d yd; cvars %s%s"):format(o.enabled == false and "off" or "on", o.range or 15,
    st.applied and "ours" or "the player's", G.pending and (" (" .. G.pending .. " queued after combat)") or "")
  local cv = {}
  for _, k in ipairs(G.MANAGED) do cv[#cv + 1] = k:gsub("SoftTarget", "ST") .. "=" .. tostring(getCVar(k)) end
  out[#out + 1] = "  " .. table.concat(cv, " ")
  if G.missing and #G.missing > 0 then out[#out + 1] = "  this client lacks: " .. table.concat(G.missing, ", ") end
  local apis = {}
  for _, n in ipairs({ "UnitIsGameObject", "SetUnitCursorTexture", "GetFileIDFromPath" }) do if not g(n) then apis[#apis + 1] = n end end
  if #apis > 0 then out[#out + 1] = "  missing calls: " .. table.concat(apis, ", ") end
  local l = G.last or {}
  out[#out + 1] = ("  last: %s -> %s%s (cursor %s, id %s, plate via %s)%s"):format(tostring(l.name), tostring(l.kind),
    l.blocked and " [cannot use yet]" or "", tostring(l.cursor), tostring(l.id), tostring(l.via), l.why and (" - " .. l.why) or "")
  local c = {}
  for k, v in pairs(G.seen) do c[#c + 1] = k .. "=" .. v end
  table.sort(c)
  out[#out + 1] = "  counts: " .. (#c > 0 and table.concat(c, " ") or "nothing yet") .. (G.artMissing and " | art missing: drawn squares" or "")
  return out
end

function G.WriteDiag()
  local gl = HH.db and HH.db.global
  if not gl then return end
  gl.diag = gl.diag or {}
  gl.diag.objectGlow = { at = date and date("%Y-%m-%d %H:%M:%S") or "", lines = G.Lines(), last = G.last, cursorIDs = G.cursorCount }
end

function G.Start()
  if G.events then return end
  G.cursorCount = G.BuildCursorIDs()
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT", "QUEST_LOG_UPDATE" }) do
    if not pcall(f.RegisterEvent, f, e) then G.unknown = (G.unknown or "") .. e .. " " end
  end
  f:SetScript("OnEvent", function(...)
    local ok, err = pcall(G.OnEvent, ...)
    if not ok and err ~= G.lastError then G.lastError = err HH:LogError("object glow: " .. tostring(err)) end
  end)
  G.events = f
  G.Apply()
end

HH:RegisterSlash("glowdiag", function()
  G.Evaluate()
  G.WriteDiag()
  for _, l in ipairs(G.Lines()) do HH:Print(l) end
end, "object glow: cvars, what the game picked, what kind it read")

--- /hh glow on | off | preview | range N
HH:RegisterSlash("glow", function(rest)
  local o = HH.db.profile.plates.objectGlow
  local w, n = (rest or ""):lower():match("^%s*(%a*)%s*(%d*)")
  if w == "on" or w == "off" then o.enabled = w == "on" G.Apply() HH:Print("object glow: " .. w) return end
  if w == "preview" then G.Preview() return end
  if w == "range" and tonumber(n) then
    o.range = math.max(5, math.min(40, tonumber(n)))
    G.ApplyCVars()
    HH:Print(("object glow: range %d yd"):format(o.range))
    return
  end
  for _, l in ipairs(G.Lines()) do HH:Print(l) end
  HH:Print("usage: /hh glow on|off  -  preview  -  range 15")
end, "object glow on ore / herbs / chests / quest objects: on, off, preview, range N")

-- started by the Plates module's OnEnable (saved settings ready); one line in /hh platediag
local Plates = HHP.Plates
if type(Plates) == "table" and type(Plates.Diagnose) == "function" then
  local orig = Plates.Diagnose
  Plates.Diagnose = function(...)
    local lines = orig(...)
    if type(lines) == "table" then lines[#lines + 1] = G.Lines()[1] end
    return lines
  end
end
