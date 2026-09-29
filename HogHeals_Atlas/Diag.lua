-- Diag: what Atlas could and could not read on this client, written to the saved file (diag.atlasState) so it
-- can be read off disk after a /reload. Everything Atlas assumes about Forever and has not yet seen in game is a
-- line here. Measures only: nothing is changed, nothing that may be secret is compared.
local A = HogHealsAtlas
local HH = HogHeals

local Diag = { LINES = 14 }
A.Diag = Diag

local function kind(path) local f = A.fn(path) return f and "function" or "nil" end

local function describe(v)
  if A.isSecret(v) then return "SECRET(" .. type(v) .. ")" end
  if type(v) == "string" then return '"' .. (#v > 70 and (v:sub(1, 70) .. "...") or v) .. '"' end
  return tostring(v)
end

--- One worn item, read every way Atlas reads items: does the stat table answer, does the tooltip, what did the
-- parser make of it.
function Diag.ItemProbe()
  local out = {}
  for _, s in ipairs(A.Gear.SLOTS) do
    local link = A.call(rawget(_G, "GetInventoryItemLink"), "player", s.id)
    -- the secret test comes first: on this client even `secret ~= nil` throws
    if A.isSecret(link) or link ~= nil then
      out.slot, out.link = s.name, describe(link)
      if A.isSecret(link) then return out end
      local api = A.call(A.fn("C_Item.GetItemStats") or rawget(_G, "GetItemStats"), link)
      if type(api) == "table" then
        local parts = {}
        for k, v in pairs(api) do parts[#parts + 1] = tostring(k) .. "=" .. describe(v) end
        table.sort(parts)
        out.statTable = table.concat(parts, " ")
      else
        out.statTable = describe(api)
      end
      local data = A.call(A.fn("C_TooltipInfo.GetHyperlink"), link)
      local lines = {}
      if type(data) == "table" and type(data.lines) == "table" then
        for i, l in ipairs(data.lines) do
          if i > Diag.LINES then break end
          lines[#lines + 1] = describe(type(l) == "table" and l.leftText or nil)
        end
      end
      out.tooltipLines = lines
      local parsed = {}
      for k, v in pairs(A.Stats.Of(link)) do parsed[#parsed + 1] = k .. "=" .. tostring(v) end
      table.sort(parsed)
      out.parsed = table.concat(parsed, " ")
      return out
    end
  end
  out.slot = "nothing worn"
  return out
end

function Diag.Write(reason)
  local g = HH.db and HH.db.global
  if not g then return nil end
  g.diag = g.diag or {}
  local name, inst, itype = A.Capture.Instance()
  local skipped = {}
  for k, v in pairs(A.Capture.skipped) do skipped[#skipped + 1] = k .. " x" .. v end
  table.sort(skipped)
  local ok, probe = pcall(Diag.ItemProbe)
  local db = A.Store.db()
  local nBoss, nNpc = 0, 0
  for _, list in pairs(db.bosses) do for _ in pairs(list) do nBoss = nBoss + 1 end end
  for _ in pairs(db.npcNames) do nNpc = nNpc + 1 end
  local state = {
    at = A.now(), reason = reason or "?", build = A.module and A.module.Build() or "?",
    api = {
      ["C_Item.GetItemStats"] = kind("C_Item.GetItemStats"), ["GetItemStats"] = type(rawget(_G, "GetItemStats")),
      ["C_TooltipInfo.GetHyperlink"] = kind("C_TooltipInfo.GetHyperlink"),
      ["EJ_GetInstanceByIndex"] = type(rawget(_G, "EJ_GetInstanceByIndex")), ["EJ_GetNumTiers"] = type(rawget(_G, "EJ_GetNumTiers")),
      ["EJ_GetEncounterInfoByIndex"] = type(rawget(_G, "EJ_GetEncounterInfoByIndex")),
      ["C_EncounterJournal.GetLootInfoByIndex"] = kind("C_EncounterJournal.GetLootInfoByIndex"),
      ["C_Container.GetContainerItemLink"] = kind("C_Container.GetContainerItemLink"),
      ["GetQuestDifficultyColor"] = type(rawget(_G, "GetQuestDifficultyColor")),
    },
    instance = ("%s | %s | %s"):format(describe(name), describe(inst), describe(itype)),
    capture = { filed = A.Capture.filed or 0, skipped = table.concat(skipped, "; "),
      unknownEvents = table.concat(A.Capture.unknown or {}, ","), lastBoss = A.Capture.lastBoss and A.Capture.lastBoss.name or nil },
    store = { drops = db.count, bosses = nBoss, npcNames = nNpc, runs = #db.runs, extraDungeons = #A.Store.ExtraDungeons() },
    journal = A.Journal.last and A.Journal.last.status or "not scanned",
    share = A.Share.Report(),
    tooltipPath = A.module and A.module.tooltipPath or "?",
    levelsFromGame = A.Levels.found or 0,
    role = A.Stats.Role(),
    itemProbe = ok and probe or ("probe failed: " .. tostring(probe)),
    questLog = (rawget(_G, "HogHealsQuests") and "HogUI Quests loaded") or "HogUI Quests not loaded",
  }
  g.diag.atlasState = state
  return state
end
