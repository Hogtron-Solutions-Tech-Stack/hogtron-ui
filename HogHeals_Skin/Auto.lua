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
    -- nine returns on classic clients; Skin.call would drop everything after the fourth
    local ok, _, count, _, quality, _, _, link, _, noValue = pcall(f, bag, slot)
    if not ok then return nil end
    return num(quality), num(count) or 1, link, noValue
  end
end

--- Vendor price of one item, or nil when the client cannot say (item not cached, no item API).
-- Forever and other modern-engine clients have NO global GetItemInfo (measured: nil), only C_Item.GetItemInfo.
local function sellPrice(link)
  if not link then return nil end
  local f = (type(C_Item) == "table" and C_Item.GetItemInfo) or rawget(_G, "GetItemInfo")
  if type(f) ~= "function" then return nil end
  -- the vendor price is the 11th return; Skin.call only hands back the first four
  local ok, price = pcall(function() return (select(11, f(link))) end)
  if ok then return num(price) end
end
Part.SellPrice = sellPrice

--- Sell every grey (quality 0) item with a value. Returns items sold, copper earned (estimated from item info),
-- and how many sold items had no known price (so the caller never prints a made-up total).
function Part.SellJunk()
  local d = cfg()
  if not d or d.sellJunk == false then return 0, 0, 0 end
  local nSlots = (type(C_Container) == "table" and C_Container.GetContainerNumSlots) or rawget(_G, "GetContainerNumSlots")
  local use = (type(C_Container) == "table" and C_Container.UseContainerItem) or rawget(_G, "UseContainerItem")
  if type(nSlots) ~= "function" or type(use) ~= "function" then return 0, 0, 0 end
  local sold, copper, unpriced = 0, 0, 0
  for bag = 0, (rawget(_G, "NUM_BAG_SLOTS") or 4) do
    local n = num(call(nSlots, bag)) or 0
    for slot = 1, n do
      if sold >= Part.MAX_SELL then return sold, copper, unpriced end
      local quality, count, link, noValue = itemInfo(bag, slot)
      if quality == 0 and not noValue then
        call(use, bag, slot)
        sold = sold + 1
        local price = sellPrice(link)
        if price then copper = copper + price * count else unpriced = unpriced + 1 end
      end
    end
  end
  return sold, copper, unpriced
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
  local sold, earned, unpriced = Part.SellJunk()
  local cost, guild = Part.Repair()
  local parts = {}
  if sold > 0 then
    -- no known price = say so by leaving the amount out; never print "~0c" for items that had a value
    if earned > 0 and unpriced == 0 then parts[#parts + 1] = ("sold %d junk for ~%s"):format(sold, money(earned))
    elseif earned > 0 then parts[#parts + 1] = ("sold %d junk for at least %s"):format(sold, money(earned))
    else parts[#parts + 1] = ("sold %d junk"):format(sold) end
  end
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
