-- HogTron UI setup guide: the first-run wizard for the whole suite.
--
-- Sean 2026-10-15: "update the startup wizard ... give them a lot of options to turn things on or off ... really step
-- them through the whole setup process and settings." The old wizard (HogHeals_Frames/Wizard.lua, 2026-09-13) asked
-- four Frames questions in a stock Blizzard dialog. This one walks every module, in the HogTron options window itself:
-- Panel.Open(Setup.Table) - the sidebar lists the steps (and shows where you are), every page ends in Back / Next, and
-- every switch writes the REAL setting and repaints at once (the module's own OnProfileChanged). A step whose module is
-- not installed is skipped. Things that only fully change after a /reload are marked, and the last page offers one.
--
-- Two ways through: "Quick start" (recommended settings, straight to the end) or "Walk me through it" (every page).
-- Opens by itself once on a profile's first login; /hh setup (or /hh wizard) any time after.
local ADDON, ns = ...
local HH = HogHeals

local Setup = { pendingReload = false }
HH.Setup = Setup

-- ------------------------------------------------------------------------------------------------ settings access
local function root() return HH.db and HH.db.profile end

--- Read "plates.target.style" from the profile.
function Setup.Get(path)
  local t = root()
  for part in path:gmatch("[^%.]+") do
    if type(t) ~= "table" then return nil end
    local n = tonumber(part)
    t = t[n or part]
  end
  return t
end

function Setup.Set(path, value)
  local t, last = root(), nil
  local parts = {}
  for part in path:gmatch("[^%.]+") do parts[#parts + 1] = tonumber(part) or part end
  for i = 1, #parts - 1 do
    if type(t[parts[i]]) ~= "table" then t[parts[i]] = {} end
    t = t[parts[i]]
  end
  last = parts[#parts]
  t[last] = value
end

local function has(module) return HH.modules and HH.modules[module] ~= nil end

--- Repaint after a change: the module's own profile hook (same thing /hh profile switches use).
function Setup.Refresh(module)
  if module == "Look" then
    local L = HH.Look
    if L then HH:SafeCall(L, "Apply") HH:SafeCall(L, "RefreshModules") end
    if HH.Panel and HH.Panel.ApplyArt and HH.Panel.frame then pcall(HH.Panel.ApplyArt, HH.Panel.frame) end
    return
  end
  local m = module and HH.modules and HH.modules[module]
  if m then HH:SafeCall(m, "OnProfileChanged") end
end

-- ------------------------------------------------------------------------------------------------ option builders
local order = 0
local function nexto() order = order + 1 return order end

local RELOAD = " |cffF5A623(full effect after a /reload)|r"

--- A switch bound to a profile path. o = { module, reload, desc, invert, width }
local function toggle(path, name, o)
  o = o or {}
  return { type = "toggle", order = nexto(), name = name, width = o.width or "full",
    desc = (o.desc or "") .. (o.reload and RELOAD or ""),
    get = function() local v = Setup.Get(path) if o.invert then return not v end return v ~= false and v ~= nil end,
    set = function(_, v)
      if o.invert then v = not v end
      Setup.Set(path, v and true or false)
      if o.reload then Setup.pendingReload = true end
      Setup.Refresh(o.module)
    end }
end

local function choose(path, name, values, o)
  o = o or {}
  return { type = "select", order = nexto(), name = name, values = values, desc = (o.desc or "") .. (o.reload and RELOAD or ""),
    get = function() local v = Setup.Get(path) if v == nil then return o.default end return v end,
    set = function(_, v) Setup.Set(path, v) if o.reload then Setup.pendingReload = true end Setup.Refresh(o.module) end }
end

local function range(path, name, min, max, step, o)
  o = o or {}
  return { type = "range", order = nexto(), name = name, min = min, max = max, step = step, desc = o.desc,
    get = function() return Setup.Get(path) or o.default or min end,
    set = function(_, v) Setup.Set(path, v) Setup.Refresh(o.module) end }
end

local function text(s) return { type = "description", order = nexto(), name = s, fontSize = "medium" } end
local function header(s) return { type = "header", order = nexto(), name = s } end
local function button(name, func, desc) return { type = "execute", order = nexto(), name = name, desc = desc, func = func } end

-- ------------------------------------------------------------------------------------------------ steps
-- Each step: key, title, module (skipped when not installed), build() -> args. Order of this list = order of the guide.
Setup.STEPS = {}
local function step(key, title, module, build) Setup.STEPS[#Setup.STEPS + 1] = { key = key, title = title, module = module, build = build } end

local function classInfo()
  local name = UnitName and UnitName("player") or "you"
  local okL, level = pcall(UnitLevel, "player")
  local okC, className = pcall(UnitClass, "player")
  local sName = type(name) == "string" and not (HH.IsSecret and HH.IsSecret(name)) and name or "you"
  return sName, okL and tonumber(level) or nil, okC and className or nil
end

step("welcome", "Welcome", nil, function()
  local name, level, className = classInfo()
  return {
    hello = text(("Hi %s%s. HogTron UI replaces most of the default interface: unit frames, healer party and raid frames, action bars, "
      .. "a cast / mana / XP HUD, nameplates, a quest tracker and dialog, a dungeon guide, a damage meter, chat and a skin for "
      .. "Blizzard's windows.\n\nThis guide goes through all of it, one page at a time. Everything you pick here applies at once and "
      .. "can be changed later in /hh."):format(name, level and className and (" (level " .. level .. " " .. className .. ")") or "")),
    quickHead = header("Two ways through"),
    quick = button("Quick start - use the recommended setup", function() Setup.QuickStart() end,
      "Keeps every recommended setting and jumps to the last page."),
    walk = button("Walk me through it  >", function() Setup.Go(2) end, "Every page, every choice."),
  }
end)

step("look", "Look", nil, function()
  return {
    intro = text("How everything is drawn. HogTron is our own dark, flat look with painted art; Classic keeps Blizzard's style "
      .. "but every HogTron UI feature still works."),
    style = choose("look.style", "Style", { hogtron = "HogTron (recommended)", classic = "Classic (Blizzard's look)" },
      { reload = true, module = "Look", default = "hogtron" }),
    menus = choose("look.menus", "Menus and windows", { flat = "Flat (recommended)", art = "Painted (brass frame)" }, { module = "Look", default = "flat" }),
    icons = choose("look.icons", "Menu icons", { art = "Painted", glyph = "Simple glyphs" }, { module = "Look", default = "art" }),
    font = choose("look.font", "Font", { Inter = "Inter (recommended)", Manrope = "Manrope", ["Barlow Condensed"] = "Barlow Condensed" },
      { module = "Look", default = "Inter" }),
    size = range("look.size", "Text size (+/- from normal)", -2, 4, 1, { module = "Look", default = 0 }),
    edge = choose("look.edge", "Text edge", { shadow = "Soft shadow", outline = "Outline" }, { module = "Look", default = "shadow" }),
  }
end)

step("modules", "Pick your parts", nil, function()
  local a = { intro = text("Turn whole parts of HogTron UI on or off. Off = Blizzard's own version comes back. The next pages "
    .. "only show the parts you keep.") }
  local list = {
    { "Units", "units.enabled", "Unit frames (you, target, target of target, pet, focus)" },
    { "Bars", "bars.enabled", "Action bars (HogTron bars instead of Blizzard's)" },
    { "Plates", "plates.enabled", "Nameplates" },
    { "Quests", "quests.tracker.enabled", "Quest tracker" },
    { "Meter", "meter.enabled", "Damage and healing meter" },
    { "Chat", "chat.enabled", "Chat restyle" },
    { "Skin", "skin.enabled", "Skin for Blizzard's windows, bags, tooltips and menu bar" },
    { "Training", "training.enabled", "What's training (spells waiting at your trainer)" },
    { "Awards", "awards.enabled", "End-of-run awards" },
  }
  for _, m in ipairs(list) do
    if has(m[1]) then a[m[2]:gsub("%.", "_")] = toggle(m[2], m[3], { module = m[1], reload = true }) end
  end
  a.always = text("Always on: the core, the HUD (its rows are picked on its own page) and the healer party / raid frames.")
  return a
end)

step("frames", "Party & raid", "Frames", function()
  local W = HogHealsFrames and HogHealsFrames.Wizard
  local presets = {}
  for k, v in pairs(W and W.PRESETS or {}) do presets[k] = v.label .. " - " .. v.desc end
  return {
    intro = text("The healer frames: one cell per group member, built for healing - incoming heals, debuffs you can remove, "
      .. "missing buffs, range. Every class can use them."),
    preset = { type = "select", order = nexto(), name = "Size preset", values = presets,
      get = function() return Setup.framesPreset or "default" end,
      set = function(_, v) Setup.framesPreset = v if W and W.ApplyPreset then W.ApplyPreset(v) end Setup.Refresh("Frames") end },
    hideBlizzard = toggle("frames.hideBlizzard", "Hide Blizzard's party and raid frames", { module = "Frames", reload = true }),
    solo = toggle("frames.layouts.solo.showSolo", "Show my own cell when I'm alone", { module = "Frames" }),
    lookHead = header("What each cell shows"),
    healthMode = choose("frames.appearance.healthMode", "Health colour", { class = "Class colour", deficit = "Green to red by health", custom = "One colour" }, { module = "Frames" }),
    healthText = choose("frames.appearance.healthText", "Health text", { deficit = "Missing health (-1.2k)", percent = "Percent", none = "None" }, { module = "Frames" }),
    healPrediction = toggle("frames.indicators.healPrediction", "Incoming heals", { module = "Frames", width = "normal" }),
    dispel = toggle("frames.indicators.dispel", "Debuffs I can remove", { module = "Frames", width = "normal" }),
    missingBuffs = toggle("frames.indicators.missingBuffs", "Buffs I can cast that are missing", { module = "Frames", width = "normal" }),
    aggro = toggle("frames.indicators.aggro", "Red edge when they have aggro", { module = "Frames", width = "normal" }),
    range = toggle("frames.indicators.range", "Fade when out of range", { module = "Frames", width = "normal" }),
    buffs = toggle("frames.indicators.buffs", "Buff icons", { module = "Frames", width = "normal" }),
    debuffs = toggle("frames.indicators.debuffs", "Debuff icons", { module = "Frames", width = "normal" }),
    aoe = toggle("frames.indicators.aoeHealing", "Light up who my group heal reaches", { module = "Frames", width = "normal" }),
  }
end)

step("bindings", "Clicks and keys", "Frames", function()
  local W = HogHealsFrames and HogHealsFrames.Wizard
  local G = HogHealsFrames and HogHealsFrames.ClickGrid
  local a = {
    intro = text("Cast on a party member by hovering their cell. Two ways, and you can use both: KEYS (hover a cell, press a key) "
      .. "and CLICKS (click a cell with a mouse button + modifier). If you use Clique, HogTron UI steps aside."),
    keyHead = header("Keys while hovering"),
    keys = { type = "select", order = nexto(), name = "Key layout", values = W and W.BINDING_PRESETS or {},
      get = function() return Setup.bindPreset or "default" end,
      set = function(_, v) Setup.bindPreset = v if W and W.ApplyBindings then W.ApplyBindings(v) end end },
    mode = choose("frames.bindingMode", "When keys work", { hover = "Only while hovering a cell", global = "Combat-safe (always bound; casts on the hovered cell)" },
      { desc = "On WoW: Forever keys set while hovering are blocked in combat; combat-safe binds them once.", default = "hover" }),
  }
  if G then
    a.clickHead = header("Clicks on a cell")
    a.clickInfo = text("Your class has a suggested click layout (plain click = rank 1 heal, Shift-click = your strongest). "
      .. "Edit it any time in /hh click-cast.")
    a.clickSuggest = button("Use the suggested click layout", function() HH:SafeCall(G, "ResetToDefaults") end)
    a.clickNone = button("No clicks (keep click = target)", function() HH:SafeCall(G, "ClearAll") end)
  end
  return a
end)

step("units", "Unit frames", "Units", function()
  return {
    intro = text("Your own frame, your target and the small ones around them."),
    player = toggle("units.player.enabled", "My frame", { module = "Units", width = "normal" }),
    target = toggle("units.target.enabled", "Target", { module = "Units", width = "normal" }),
    tot = toggle("units.targettarget.enabled", "Target of target", { module = "Units", width = "normal" }),
    pet = toggle("units.pet.enabled", "Pet", { module = "Units", width = "normal" }),
    focus = toggle("units.focus.enabled", "Focus", { module = "Units", width = "normal" }),
    castbar = toggle("units.target.castbar", "Target's cast bar", { module = "Units", width = "normal" }),
    debuffs = choose("units.target.debuffFilter", "Debuffs on the target", { ["mine-first"] = "Mine first, then the rest", mine = "Only mine", all = "All" }, { module = "Units" }),
    healthText = choose("units.healthText", "Health text", { ["current-max"] = "343 / 343", percent = "Percent", current = "Current", ["current-percent"] = "Current + percent", none = "None" }, { module = "Units" }),
    hideBlizzard = toggle("units.hideBlizzard", "Hide Blizzard's player and target frames", { module = "Units", reload = true }),
  }
end)

step("hud", "Cast bar and mana", "HUD", function()
  return {
    intro = text("A strip under your character: what you are casting, your mana with the five-second rule, your swing, and info."),
    castbar = toggle("hud.showCastbar", "Cast bar", { module = "HUD", width = "normal" }),
    themes = toggle("hud.castbar.themes.enabled", "Cast bar takes on what you cast (fire, frost, holy, mining...)", { module = "HUD", width = "normal" }),
    swing = toggle("hud.showSwing", "Swing timer", { module = "HUD", width = "normal" }),
    mana = toggle("hud.showMana", "Mana bar with the five-second rule", { module = "HUD", width = "normal" }),
    xp = toggle("hud.showXP", "Experience bar (rested, quests ready, time to level)", { module = "HUD", width = "normal" }),
    info = toggle("hud.showInfo", "Info line (time to out-of-mana, best heal rank)", { module = "HUD", width = "normal" }),
    pacing = toggle("hud.pacing.enabled", "Mana pacing (will I last the fight?)", { module = "HUD", width = "normal" }),
    advisor = toggle("hud.advisor.enabled", "Heal rank advisor", { module = "HUD", width = "normal" }),
    hideBlizzard = toggle("hud.castbar.hideBlizzard", "Hide Blizzard's cast bar", { module = "HUD", reload = true }),
  }
end)

step("bars", "Action bars", "Bars", function()
  return {
    intro = text("Your buttons. Three bars at the bottom, two along the right edge; keybinds and paging keep working."),
    b1 = toggle("bars.list.1.enabled", "Bar 1 (main)", { module = "Bars", width = "normal" }),
    b2 = toggle("bars.list.2.enabled", "Bar 2", { module = "Bars", width = "normal" }),
    b3 = toggle("bars.list.3.enabled", "Bar 3", { module = "Bars", width = "normal" }),
    b4 = toggle("bars.list.4.enabled", "Right bar", { module = "Bars", width = "normal" }),
    b5 = toggle("bars.list.5.enabled", "Second right bar", { module = "Bars", width = "normal" }),
    grid = toggle("bars.grid", "Show empty slots", { module = "Bars", width = "normal" }),
    cooldowns = toggle("bars.cooldownNumbers", "Cooldown numbers on buttons", { module = "Bars", width = "normal" }),
    names = toggle("bars.hideNames", "Hide macro names", { module = "Bars", width = "normal" }),
    hotkey = range("bars.hotkeySize", "Keybind text size", 6, 18, 1, { module = "Bars" }),
    move = text("Move any bar later with /hh unlock."),
  }
end)

step("plates", "Nameplates", "Plates", function()
  return {
    intro = text("The bars over heads: flat, readable, with quest mobs and your target marked."),
    target = choose("plates.target.style", "Mark my target with", { glow = "A soft glow (recommended)", brackets = "Sharp corner brackets", scale = "A bigger plate", outline = "An outline", none = "Nothing" },
      { module = "Plates", default = "glow" }),
    healthText = choose("plates.healthText", "Health text", { percent = "Percent", value = "Value", none = "None" }, { module = "Plates" }),
    castbar = toggle("plates.castbar", "Their cast bars", { module = "Plates", width = "normal" }),
    quest = toggle("plates.quest.icon", "Quest mobs: ! and progress (2/7)", { module = "Plates", width = "normal" }),
    die = toggle("plates.die.enabled", "Does it die? (skull when your DoT outlasts the mob)", { module = "Plates", width = "normal" }),
    glow = toggle("plates.objectGlow.enabled", "Glow on ore, herbs, chests and quest objects nearby", { module = "Plates", width = "normal" }),
    glowAround = toggle("plates.objectGlow.anyDirection", "... the nearest one in any direction, not only straight ahead", { module = "Plates", width = "normal" }),
    aggro = toggle("plates.aggro.warn", "Red outline when a mob is on you", { module = "Plates", width = "normal" }),
    friendlyName = toggle("plates.friendlyNameOnly", "Friendly players: name only", { module = "Plates", width = "normal" }),
    pets = toggle("plates.friendlyPets", "Plates for pets and minions", { module = "Plates", width = "normal", reload = true }),
  }
end)

step("quests", "Questing", "Quests", function()
  return {
    intro = text("Tracker, the quest to do next, and how quest givers talk to you."),
    go = toggle("quests.go.enabled", "GO row: the quest to do next, with distance and time to level", { module = "Quests" }),
    rule = choose("quests.go.rule", "GO picks by", { fastest = "Fastest XP", balanced = "Balanced (recommended)", travel = "Least walking" }, { module = "Quests" }),
    waypoint = toggle("quests.waypoint.enabled", "Marker in the world over your tracked quest", { module = "Quests" }),
    dialogHead = header("Talking to quest givers"),
    dialog = toggle("quests.dialog.enabled", "Quest text on a page in our own window (Space accepts, 1-9 picks)", { module = "Quests" }),
    theme = choose("quests.dialog.theme", "Page", { light = "Parchment", dark = "Ink" }, { module = "Quests" }),
    auto = toggle("quests.auto.enabled", "Accept and turn in quests automatically (hold Shift to stop it)", { module = "Quests",
      desc = "New players: with this on you never see the quest text. Turn it off to read every quest." }),
    gossip = toggle("quests.auto.gossip", "Skip gossip to the quest automatically", { module = "Quests" }),
    announce = toggle("quests.announce.enabled", "Tell my party about quest progress", { module = "Quests" }),
    mapHead = header("Map"),
    pins = toggle("quests.minimap.enabled", "Quest pins on the minimap", { module = "Quests", width = "normal" }),
    square = toggle("quests.map.enabled", "Square minimap", { module = "Quests", width = "normal", reload = true }),
    drawer = toggle("quests.buttons.enabled", "Addon buttons in one drawer", { module = "Quests", width = "normal", reload = true }),
    fade = toggle("quests.worldMap.fadeWhileMoving", "World map fades while you move", { module = "Quests", width = "normal" }),
  }
end)

step("dungeons", "Dungeons & gear", "Atlas", function()
  local W = HogHealsFrames and HogHealsFrames.Wizard
  local roles = W and W.GEAR_ROLES or { auto = "Auto - by my class" }
  local a = {
    intro = text("The dungeon guide (levels, bosses, loot, quests) scores gear for you. Tell it what to score for."),
    role = { type = "select", order = nexto(), name = "Score gear for (this character)", values = roles,
      get = function() local c = HH.db.char and HH.db.char.atlas return c and c.role or "auto" end,
      set = function(_, v)
        if W and W.SetGearRole then W.SetGearRole(v) else HH.db.char.atlas = HH.db.char.atlas or {} HH.db.char.atlas.role = v end
        Setup.Refresh("Atlas")
      end },
  }
  if has("Training") then a.train = toggle("training.nudge", "Tell me when spells are waiting at the trainer", { module = "Training" }) end
  if has("Meter") then a.meterHide = toggle("meter.hideBlizzard", "Hide Blizzard's damage meter (ours replaces it)", { module = "Meter", reload = true }) end
  return a
end)

step("chatskin", "Chat & windows", nil, function()
  local a = { intro = text("Chat, Blizzard's own windows, bags, tooltips and the bar along the bottom.") }
  if has("Chat") then
    a.chatHead = header("Chat")
    a.short = toggle("chat.shortChannels", "Short channel names ([G] instead of [Guild])", { module = "Chat", width = "normal" })
    a.class = toggle("chat.classNames", "Names in class colour", { module = "Chat", width = "normal" })
    a.url = toggle("chat.urlCopy", "Click links to copy them", { module = "Chat", width = "normal" })
    a.fade = toggle("chat.fade", "Fade old lines", { module = "Chat", width = "normal" })
  end
  if not has("Skin") then return a end
  a.skinHead = header("Windows and bags")
  a.panels = toggle("skin.panels.enabled", "Blizzard's windows in the HogTron look", { module = "Skin", width = "normal", reload = true })
  a.bags = toggle("skin.bags.enabled", "Bags", { module = "Skin", width = "normal", reload = true })
  a.tooltips = toggle("skin.tooltips.enabled", "Tooltips", { module = "Skin", width = "normal" })
  a.micro = toggle("skin.micro.enabled", "Menu bar as HogTron icons", { module = "Skin", width = "normal", reload = true })
  a.info = toggle("skin.infoBar.enabled", "Info bar (gold, durability, bags, fps, time)", { module = "Skin", width = "normal" })
  a.autoHead = header("At vendors")
  a.junk = toggle("skin.auto.sellJunk", "Sell grey items automatically", { module = "Skin", width = "normal" })
  a.repair = toggle("skin.auto.repair", "Repair automatically", { module = "Skin", width = "normal" })
  a.guild = toggle("skin.auto.guildRepair", "Use guild money for repairs", { module = "Skin", width = "normal" })
  return a
end)

step("awards", "Awards", "Awards", function()
  return {
    intro = text("Finish a dungeon, raid or battleground and five players take the stage with an award: honors and roasts."),
    dungeon = toggle("awards.contexts.dungeon", "After dungeons", { module = "Awards", width = "normal" }),
    raid = toggle("awards.contexts.raid", "After raids", { module = "Awards", width = "normal" }),
    bg = toggle("awards.contexts.bg", "After battlegrounds", { module = "Awards", width = "normal" }),
    roasts = toggle("awards.roasts", "Include roasts", { module = "Awards", width = "normal" }),
  }
end)

step("done", "All set", nil, function()
  return {
    done = text("That's everything. All of it stays in /hh, and this guide is /hh setup any time."),
    reloadNote = { type = "description", order = nexto(), name = function()
      return Setup.pendingReload and "|cffF5A623Some choices finish on a reload (Blizzard's own frames come and go then).|r" or "" end },
    reload = button("Reload now", function() Setup.Finish() if ReloadUI then ReloadUI() end end),
    test = button("Preview the party frames (/hh test 5)", function() HH:SlashCommand("test 5") end),
    unlock = button("Move things around (/hh unlock)", function() Setup.Finish() if HH.SetLocked then HH:SetLocked(false) end end),
    finish = button("Finish", function() Setup.Finish() end),
  }
end)

-- ------------------------------------------------------------------------------------------------ the table
--- Steps that apply to this install (module present), in order.
function Setup.Visible()
  local out = {}
  for _, s in ipairs(Setup.STEPS) do if not s.module or has(s.module) then out[#out + 1] = s end end
  return out
end

--- The options table the window renders: one top-level group per step (the sidebar), Back / Next on each page.
function Setup.Table()
  local steps = Setup.Visible()
  local t = { type = "group", name = "Setup", args = {} }
  for i, s in ipairs(steps) do
    order = 0
    local ok, args = pcall(s.build)
    if not ok then HH:LogError("setup " .. s.key .. ": " .. tostring(args)) args = {} end
    -- step count and Back / Next at the TOP: a long page scrolls, and buttons at its foot scrolled out of sight
    args.navHead = { type = "header", order = -3, name = ("Step %d of %d: %s"):format(i, #steps, s.title) }
    if i > 1 then args.back = { type = "execute", order = -2, name = "<  Back", func = function() Setup.Go(i - 1) end } end
    if i < #steps and s.key ~= "welcome" then
      args.next = { type = "execute", order = -1, name = ("Next: %s  >"):format(steps[i + 1].title), func = function() Setup.Go(i + 1) end }
    end
    t.args[s.key] = { type = "group", order = i, name = ("%d. %s"):format(i, s.title), args = args }
  end
  return t
end

--- Show step i (1-based, visible steps).
function Setup.Go(i)
  local steps = Setup.Visible()
  local s = steps[math.max(1, math.min(i, #steps))]
  Setup.current = s and s.key
  if HH.Panel and s then HH.Panel.Select(s.key) end
end

function Setup.Open()
  if not (HH.Panel and HH.Panel.Open) then HH:Print("The options window is not loaded; /reload and try /hh setup again.") return nil end
  Setup.open = true
  local f = HH.Panel.Open(Setup.Table)
  Setup.Go(1)
  return f
end

--- Recommended settings for the whole suite: the shipped defaults, kept; the Frames preset and the class layouts applied.
function Setup.QuickStart()
  local W = HogHealsFrames and HogHealsFrames.Wizard
  if W and W.ApplyPreset then pcall(W.ApplyPreset, "default") end
  if W and W.ApplyBindings then pcall(W.ApplyBindings, "default") end
  if W and W.SetGearRole then pcall(W.SetGearRole, "auto") end
  Setup.quick = true
  Setup.Go(#Setup.Visible())
end

function Setup.Finish()
  local p = root()
  if p then p.wizardDone = true p.setupVersion = Setup.VERSION end
  Setup.open = false
  if HH.Panel and HH.Panel.frame then HH.Panel.frame:Hide() end
  HH:Print("Setup saved. /hh for every setting, /hh setup to run this again.")
end

Setup.VERSION = 2

function HH:RunWizard() return Setup.Open() end
HH:RegisterSlash("setup", function() Setup.Open() end, "the setup guide (every part of HogTron UI, step by step)")

-- First login on a profile: open once, a few seconds after the world is up, never in combat. Profiles that finished
-- the OLD wizard get one chat line pointing here instead of the window popping up (they already set things up).
local boot = CreateFrame("Frame")
pcall(boot.RegisterEvent, boot, "PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  local p = root()
  if not p or not C_Timer or not C_Timer.After then return end
  C_Timer.After(4, function()
    p = root()
    if not p or InCombatLockdown() then return end
    if not p.wizardDone then Setup.Open()
    elseif (p.setupVersion or 1) < Setup.VERSION and not p.setupNoticed then
      p.setupNoticed = true
      HH:Print("New: a step-by-step setup guide for every part of HogTron UI. Type /hh setup.")
    end
  end)
end)
