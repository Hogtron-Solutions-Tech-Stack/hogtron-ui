-- Tooltip: on any item Atlas knows, one line saying where it drops, and one when it is on your wishlist.
-- Modern clients: TooltipDataProcessor. Older: the OnTooltipSetItem script. Neither there = the feature is off.
local A = HogHealsAtlas
local HH = HogHeals

local Tooltip = {}
A.Tooltip = Tooltip

--- The lines to add for an item: { "Drops from: ...", "On your wishlist", "+12.3 for healer, over ..." }.
-- Second return: per line, true = good news (drawn green). link = the full item link when the tooltip has one
-- (random-suffix items need it for their stats).
function Tooltip.Lines(id, link)
  local out, good = {}, {}
  if not id then return out, good end
  local c = A.cfg()
  if c.tooltip ~= false then
    local text = A.Store.SourceText(id)
    if text then out[#out + 1] = "Drops from: " .. text end
    if A.Gear.IsWished(id) then out[#out + 1] = "On your wishlist" end
  end
  if c.tooltipScore ~= false then
    local ok, cmp = pcall(A.Gear.Compare, link or id)
    local text, up = A.Gear.CompareText(ok and cmp or nil)
    if text then out[#out + 1] = text good[#out] = up end
  end
  return out, good
end

local function add(tip, id, link)
  if type(tip) ~= "table" or type(tip.AddLine) ~= "function" then return end
  local lines, good = Tooltip.Lines(id, link)
  for i, line in ipairs(lines) do
    local c = (good[i] == true and A.COLORS.green) or (good[i] == false and A.COLORS.grey) or A.COLORS.cyan
    tip:AddLine(line, c[1], c[2], c[3])
  end
end

function Tooltip.OnData(tip, data)
  if type(data) ~= "table" then return end
  local id = A.num(data.id)
  local link = A.str(data.hyperlink)
  if not id and link then id = A.ItemIDFromLink(link) end
  if id then add(tip, id, link) end
end

function Tooltip.OnLegacy(tip)
  if type(tip.GetItem) ~= "function" then return end
  local _, link = A.call(tip.GetItem, tip)
  local id = A.ItemIDFromLink(link)
  if id then add(tip, id, A.str(link)) end
end

function Tooltip.Start()
  if Tooltip.path then return Tooltip.path end
  local proc = rawget(_G, "TooltipDataProcessor")
  local kind = type(Enum) == "table" and type(Enum.TooltipDataType) == "table" and Enum.TooltipDataType.Item
  if type(proc) == "table" and type(proc.AddTooltipPostCall) == "function" and kind ~= nil then
    local ok = pcall(proc.AddTooltipPostCall, kind, function(tip, data)
      local good, err = pcall(Tooltip.OnData, tip, data)
      if not good then HH:LogError("atlas tooltip: " .. tostring(err)) end
    end)
    if ok then Tooltip.path = "processor" return Tooltip.path end
  end
  local n = 0
  for _, name in ipairs({ "GameTooltip", "ItemRefTooltip" }) do
    local tip = rawget(_G, name)
    if type(tip) == "table" and type(tip.HookScript) == "function" then
      if pcall(tip.HookScript, tip, "OnTooltipSetItem", function(self) pcall(Tooltip.OnLegacy, self) end) then n = n + 1 end
    end
  end
  Tooltip.path = n > 0 and "script" or "none"
  return Tooltip.path
end
