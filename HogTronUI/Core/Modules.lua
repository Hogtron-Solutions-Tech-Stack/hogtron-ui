-- Modules: which parts of HogTron UI load at all. Sean 2026-11-05: "merge everything into one. In the setup, they can
-- pick what they want on or off as far as submodules" (CurseForge wants ONE project, so the package carries every
-- module and the player chooses here). Each module is its own addon folder; off = the client does not load it at all
-- (nothing of it runs, no cost), from the next /reload. Per character, like the game's own addon list. Shown on the
-- guide's "Pick your parts" page and under General > Modules; /hh modules lists them. The core (HogTronUI + HogHeals) is not
-- on the list. Client API probed in order: C_AddOns.* (newer clients), then the EnableAddOn / DisableAddOn /
-- GetAddOnEnableState globals; a client with neither is reported, never raised.
local HH = HogHeals

local Modules = {}
HH.Modules = Modules

Modules.LIST = {
  { name = "HogTron_Units", title = "Unit frames", desc = "Player, target, pet and focus frames." },
  { name = "HogHeals_Frames", title = "Healer frames (HogHeals)", desc = "Party / raid frames with hover-key healing." },
  { name = "HogTron_Bars", title = "Action bars", desc = "Our action bars, pet and stance bars." },
  { name = "HogTron_HUD", title = "HUD", desc = "Cast bar, swing timer, mana and experience bars." },
  { name = "HogTron_Plates", title = "Nameplates", desc = "Flat bars, quest marks, threat colours, cast bars on nameplates." },
  { name = "HogTron_Quests", title = "Quests & map", desc = "Quest tracker, quest dialog, minimap, world map." },
  { name = "HogTron_Skin", title = "Skin", desc = "Blizzard's bags, menu bar, tooltips and windows in the HogTron look; the info bar." },
  { name = "HogTron_Chat", title = "Chat", desc = "Chat windows and tabs restyled." },
  { name = "HogTron_Meter", title = "Meter", desc = "Healing / damage meter." },
  { name = "HogTron_Atlas", title = "Atlas", desc = "Dungeon guide: loot, quests, attunements, where next." },
  { name = "HogTron_Training", title = "Training", desc = "What's training at your class trainer; the level-up card." },
  { name = "HogTron_Journal", title = "Journal", desc = "Healer's dungeon journal." },
  { name = "HogTron_Awards", title = "Awards", desc = "End-of-dungeon awards screen." },
}

local function g(n) return rawget(_G, n) end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
end
local function C() local c = g("C_AddOns") return type(c) == "table" and c or nil end
local function me() local n = call(g("UnitName"), "player") return type(n) == "string" and n or nil end

--- Is this addon folder in the client's list? true / false, nil when the client cannot say.
function Modules.Installed(name)
  local c = C()
  local f = (c and type(c.GetAddOnInfo) == "function" and c.GetAddOnInfo) or g("GetAddOnInfo")
  if type(f) ~= "function" then return nil end
  local ok, n = pcall(f, name)
  return (ok and n ~= nil and n ~= false) and true or false
end

--- On for this character? C_AddOns.GetAddOnEnableState(name, character) on newer clients, GetAddOnEnableState(character,
-- name) on older ones (0 off, 1 some characters, 2 all); a client with neither answers "loaded now".
function Modules.Enabled(name)
  local c, who = C(), me()
  if c and type(c.GetAddOnEnableState) == "function" then
    local ok, state = pcall(c.GetAddOnEnableState, name, who)
    if ok and type(state) == "number" then return state > 0 end
  end
  local f = g("GetAddOnEnableState")
  if type(f) == "function" then
    local ok, state = pcall(f, who, name)
    if ok and type(state) == "number" then return state > 0 end
  end
  return call(g("IsAddOnLoaded"), name) and true or false
end

--- Switch an addon folder on / off for this character (takes effect on /reload). true, or false + why.
function Modules.Set(name, on)
  local c, who = C(), me()
  local f = c and (on and c.EnableAddOn or c.DisableAddOn)
  if type(f) ~= "function" then f = g(on and "EnableAddOn" or "DisableAddOn") end
  if type(f) ~= "function" then return false, "this client has no EnableAddOn / DisableAddOn" end
  local ok, err = pcall(f, name, who)
  if not ok then return false, tostring(err) end
  Modules.changed = Modules.changed or {}
  Modules.changed[name] = on and "on" or "off"
  return true
end

--- The rows the guide and General show: { name, title, desc, installed, enabled } for every module the client knows.
function Modules.Rows()
  local out = {}
  for _, m in ipairs(Modules.LIST) do
    local inst = Modules.Installed(m.name)
    if inst ~= false then
      out[#out + 1] = { name = m.name, title = m.title, desc = m.desc, installed = inst, enabled = Modules.Enabled(m.name) }
    end
  end
  return out
end

--- Options args: one toggle per module + Apply (reload). after(name, on) runs after a change (the guide marks a reload).
function Modules.Args(after, startOrder)
  local args, o = {}, startOrder or 1
  args.about = { type = "description", order = o, fontSize = "medium",
    name = "Every part of HogTron UI is its own addon folder. Off = the game does not load it at all (nothing of it runs). Changes take effect on the next /reload." }
  for _, m in ipairs(Modules.LIST) do
    if Modules.Installed(m.name) ~= false then
      o = o + 1
      args[m.name] = { type = "toggle", order = o, name = m.title, desc = m.desc, width = "full",
        get = function() return Modules.Enabled(m.name) end,
        set = function(_, v)
          local ok, why = Modules.Set(m.name, v and true or false)
          if not ok then HH:Print("modules: " .. tostring(why)) end
          if after then after(m.name, v and true or false) end
        end }
    end
  end
  o = o + 1
  args.reload = { type = "execute", order = o, name = "Apply (reload)", desc = "Reloads the interface so the choices take effect.",
    func = function() local r = g("ReloadUI") if type(r) == "function" then r() end end }
  return args
end

--- /hh modules lines.
function Modules.Lines()
  local out = {}
  for _, r in ipairs(Modules.Rows()) do
    out[#out + 1] = ("%s: %s%s"):format(r.title, r.enabled and "on" or "off", (Modules.changed and Modules.changed[r.name]) and ("  -> " .. Modules.changed[r.name] .. " after /reload") or "")
  end
  if #out == 0 then out[1] = "modules: this client lists none of the module folders (are they installed?)" end
  return out
end

HH:RegisterSlash("modules", function()
  for _, l in ipairs(Modules.Lines()) do HH:Print(l) end
end, "which parts of HogTron UI load (also step 2 of /hh setup, and General > Modules)")

-- The guide's "Pick your parts" page already switches modules off at the profile level (instant, shared by every
-- character, Blizzard's own version comes back). This adds the stronger switch under it: not loaded at all, per
-- character, from the next /reload - what the one-package install needs.
local S = HH.Setup
if type(S) == "table" and type(S.STEPS) == "table" then
  for _, s in ipairs(S.STEPS) do
    if s.key == "modules" and type(s.build) == "function" and not s.hhLoadSwitches then
      s.hhLoadSwitches = true
      local orig = s.build
      s.build = function()
        local a = orig() or {}
        a.loadHead = { type = "header", order = 900, name = "Load at all (this character)" }
        a.loadIntro = { type = "description", order = 901, fontSize = "medium",
          name = "The switches above keep a part installed and stand it down. These stop the game loading it at all - per character, from the next /reload. Everything is on to start with." }
        local mine = Modules.Args(function() S.pendingReload = true end, 902)
        mine.about = nil
        for k, v in pairs(mine) do a[k] = v end
        return a
      end
    end
  end
end
