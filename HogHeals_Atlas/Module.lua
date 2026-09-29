-- Module: registers Atlas with the HogUI core, starts the pieces, owns the slash commands. Loads last.
local A = HogHealsAtlas
local HH = HogHeals

local Module = {}
A.module = Module

function Module:OnEnable()
  A.cfg()
  A.Store.db()
  HH:SafeCall(A.Capture, "Start")
  local ok, path = pcall(A.Tooltip.Start)
  Module.tooltipPath = ok and path or ("failed: " .. tostring(path))
  HH:SafeCall(A.Share, "Start")
  HH:SafeCall(A.Tracker, "Start")
  -- Group Finder and the journal are not ready at login: ask a few seconds in. One scan per session on its own;
  -- the button in the window asks again.
  local function late()
    pcall(A.Levels.Refresh)
    if A.Store.db().count == 0 or not A.Store.db().journalBuild or A.Store.db().journalBuild ~= Module.Build() then
      local ok2, res = pcall(A.Journal.Scan, "login")
      -- a scan that stopped early is not a finished one: the next login carries on
      if ok2 and type(res) == "table" and res.status == "ok" then A.Store.db().journalBuild = Module.Build() end
    end
    pcall(A.Diag.Write, "login")   -- not SafeCall: that passes the table as the first argument
  end
  -- the saved file is written at logout / reload: leave the freshest state in it
  local f = CreateFrame("Frame")
  Module.events = f
  pcall(f.RegisterEvent, f, "PLAYER_LOGOUT")
  f:SetScript("OnEvent", function() pcall(A.Diag.Write, "logout") end)
  if C_Timer and C_Timer.After then C_Timer.After(6, late) else late() end
end

function Module.Build()
  local _, build = A.call(rawget(_G, "GetBuildInfo"))
  return A.str(build) or "?"
end

function Module:OnProfileChanged()
  A.filled = nil
  if A.Window.Refresh then A.Window.Refresh() end
  if A.Tracker.Refresh then A.Tracker.Refresh() end
end

function Module:GetOptions()
  return A.Options.Build()
end

HH:RegisterModule("Atlas", Module)

HH:RegisterSlash("atlas", function(rest)
  rest = (rest or ""):lower()
  if rest == "scan" then
    A.Journal.Scan("slash")
    for _, l in ipairs(A.Journal.Report()) do HH:Print(l) end
    A.Window.Refresh()
    return
  end
  A.Window.Toggle(rest ~= "" and rest or nil)
end, "dungeon guide: loot, quests, levels (/hh atlas scan = read the game's journal)")
HH:RegisterSlash("gear", function() A.Window.Toggle("upgrades") end, "gear upgrades for your role")
HH:RegisterSlash("sets", function() A.Window.Toggle("sets") end, "saved gear sets")
HH:RegisterSlash("wish", function() A.Window.Toggle("wish") end, "your wishlist")
HH:RegisterSlash("lootlog", function() A.Window.Toggle("log") end, "loot from your last dungeon runs")
HH:RegisterSlash("dungeon", function() A.Tracker.Toggle() end, "the on-screen dungeon tracker (bosses, quests, wanted items)")
HH:RegisterSlash("atlasinfo", function()
  for _, l in ipairs(A.Journal.Report()) do HH:Print(l) end
  for _, l in ipairs(A.Capture.Report()) do HH:Print(l) end
  HH:Print(A.Share.Report())
  local st = A.Diag.Write("slash")
  local ip = st and type(st.itemProbe) == "table" and st.itemProbe or {}
  HH:Print(("item reading: slot %s, stat table %s, tooltip lines %d, parsed: %s"):format(tostring(ip.slot),
    (ip.statTable and ip.statTable ~= "nil") and "yes" or "no", #(ip.tooltipLines or {}), tostring(ip.parsed)))
  HH:Print(("atlas: %d drops known, tooltip path %s, role %s, level ranges from the game: %s"):format(
    A.Store.db().count, tostring(Module.tooltipPath), A.Stats.Role(), tostring(A.Levels.found or 0)))
end, "what Atlas could read on this client")
