-- Vendor automation: at a merchant, sell the grey junk and repair (own gold; guild repair optional). One chat line
-- says what happened. Capped per visit so a runaway loop can never empty a bag.
local HHS = HogHealsSkin
local Skin = HHS.Skin
local HH = HogHeals
local call, num = Skin.call, Skin.num

local Part = { name = "auto", MAX_SELL = 60 }
HHS.Auto = Part

local function cfg() return Skin.cfg().auto end

local function money(m)
  m = num(m) or 0
  local g, s, c = math.floor(m / 10000), math.floor(m / 100) % 100, m % 100
  if g > 0 then return ("%dg %ds"):format(g, s) end
  if s > 0 then return ("%ds %dc"):format(s, c) end
  return ("%dc"):format(c)
end

local function itemInfo(bag, slot)
  if type(C_Container) == "table" and type(C_Container.GetContainerItemInfo) == "function" then
    local info = call(C_Container.GetContainerItemInfo, bag, slot)
    if type(info) == "table" then return num(info.quality), num(info.stackCount) or 1, info.hyperlink, info.hasNoValue end
    return nil
  end
  local f = rawget(_G, "GetContainerItemInfo")
  if type(f) == "function" then
    local _, count, _, quality, _, _, link, _, noValue = call(f, bag, slot)
    return num(quality), num(count) or 1, link, noValue
  end
end

local function sellPrice(link)
  if not link or type(GetItemInfo) ~= "function" then return 0 end
  -- the vendor price is GetItemInfo's 11th return; Skin.call only hands back the first four
  local ok, price = pcall(function() return (select(11, GetItemInfo(link))) end)
  return ok and num(price) or 0
end

--- Sell every grey (quality 0) item with a value. Returns items sold, copper earned (estimated from item info).
function Part.SellJunk()
  local d = cfg()
  if not d or d.sellJunk == false then return 0, 0 end
  local nSlots = (type(C_Container) == "table" and C_Container.GetContainerNumSlots) or rawget(_G, "GetContainerNumSlots")
  local use = (type(C_Container) == "table" and C_Container.UseContainerItem) or rawget(_G, "UseContainerItem")
  if type(nSlots) ~= "function" or type(use) ~= "function" then return 0, 0 end
  local sold, copper = 0, 0
  for bag = 0, (rawget(_G, "NUM_BAG_SLOTS") or 4) do
    local n = num(call(nSlots, bag)) or 0
    for slot = 1, n do
      if sold >= Part.MAX_SELL then return sold, copper end
      local quality, count, link, noValue = itemInfo(bag, slot)
      if quality == 0 and not noValue then
        call(use, bag, slot)
        sold = sold + 1
        copper = copper + sellPrice(link) * count
      end
    end
  end
  return sold, copper
end

--- Repair everything if the merchant can and we can afford it. Returns copper spent (0 = nothing done).
function Part.Repair()
  local d = cfg()
  if not d or d.repair == false then return 0 end
  if not call(CanMerchantRepair) then return 0 end
  local cost, canRepair = call(GetRepairAllCost)
  cost = num(cost) or 0
  if not canRepair or cost <= 0 then return 0 end
  local useGuild = d.guildRepair and call(CanGuildBankRepair) and true or false
  if not useGuild and cost > (num(call(GetMoney)) or 0) then return -cost end
  call(RepairAllItems, useGuild)
  return cost, useGuild
end

function Part.OnMerchant()
  local d = cfg()
  if not d or (d.sellJunk == false and d.repair == false) then return end
  local sold, earned = Part.SellJunk()
  local cost, guild = Part.Repair()
  local parts = {}
  if sold > 0 then parts[#parts + 1] = ("sold %d junk for ~%s"):format(sold, money(earned)) end
  if cost and cost > 0 then parts[#parts + 1] = ("repaired for %s%s"):format(money(cost), guild and " (guild)" or "")
  elseif cost and cost < 0 then parts[#parts + 1] = ("repair costs %s, not enough gold"):format(money(-cost)) end
  if #parts > 0 then HH:Print(table.concat(parts, ", ") .. ".") end
  return sold, cost
end

function Part.Apply() end

function Part.OnEvent(e)
  if e == "MERCHANT_SHOW" then
    -- the merchant's data settles a moment after the event
    if C_Timer and C_Timer.After then C_Timer.After(0.3, function() pcall(Part.OnMerchant) end) else Part.OnMerchant() end
  end
end

Skin.Register(Part)
