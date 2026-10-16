-- Bags: Blizzard's container frames (and the modern combined bag) in the HogTron UI panel, item slots flattened with
-- a quality-coloured outline. Restyle only: sorting, searching, the money line and every click stay Blizzard's.
local HHS = HogHealsSkin
local Skin = HHS.Skin
local HH = HogHeals

local Part = { name = "bags", frames = {} }
HHS.Bags = Part

Part.NAMES = { "ContainerFrameCombinedBags" }
for i = 1, 13 do Part.NAMES[#Part.NAMES + 1] = "ContainerFrame" .. i end
Part.ART = { "BackgroundTop", "BackgroundMiddle1", "BackgroundMiddle2", "BackgroundBottom", "Portrait", "Background" }

local function qualityColor(q)
  q = Skin.num(q)
  if not q then return nil end
  if type(C_Item) == "table" and type(C_Item.GetItemQualityColor) == "function" then
    local r, g, b = Skin.call(C_Item.GetItemQualityColor, q)
    if r then return r, g, b end
  end
  local t = rawget(_G, "ITEM_QUALITY_COLORS")
  local c = type(t) == "table" and t[q]
  if type(c) == "table" and c.r then return c.r, c.g, c.b end
  return nil
end

local function itemQuality(bag, slot)
  if type(C_Container) == "table" and type(C_Container.GetContainerItemInfo) == "function" then
    local info = Skin.call(C_Container.GetContainerItemInfo, bag, slot)
    if type(info) == "table" then return info.quality end
    return nil
  end
  local f = rawget(_G, "GetContainerItemInfo")
  if type(f) == "function" then
    local _, _, _, quality = Skin.call(f, bag, slot)
    return quality
  end
end

--- Item buttons of a container frame: modern `frame.Items`, else the classic named children.
function Part.Items(frame)
  if type(frame.Items) == "table" then return frame.Items end
  local out = {}
  local name = frame:GetName()
  if not name then return out end
  for i = 1, 40 do
    local b = rawget(_G, name .. "Item" .. i)
    if not b then break end
    out[i] = b
  end
  return out
end

--- Outline colour per slot from the item's quality (uncommon and up by default; empty / common = plain line).
function Part.ColorItems(frame)
  local d = Skin.cfg().bags
  local bagID = frame.GetBagID and Skin.call(frame.GetBagID, frame) or (frame.GetID and frame:GetID()) or 0
  local n = 0
  for _, b in ipairs(Part.Items(frame)) do
    if b.hh and b.hh.edges then
      local bag = (b.GetBagID and Skin.call(b.GetBagID, b)) or bagID
      local slot = (b.GetID and b:GetID()) or 0
      local q = itemQuality(bag, slot)
      local r, g, bl
      if q and Skin.num(q) and q >= (d.qualityMin or 2) then r, g, bl = qualityColor(q) end
      if r then Skin.ColorEdges(b.hh.edges, { r, g, bl }) else Skin.ColorEdges(b.hh.edges, Skin.LINE) end
      n = n + 1
    end
  end
  return n
end

function Part.Style(frame)
  local d = Skin.cfg().bags
  if not frame.hh then
    local name = frame:GetName() or ""
    for _, k in ipairs(Part.ART) do Skin.Kill(rawget(frame, k) or rawget(_G, name .. k)) end
    Skin.KillRegions(frame)
    for _, k in ipairs({ "NineSlice", "Bg", "PortraitContainer" }) do
      local child = rawget(frame, k)
      if type(child) == "table" then Skin.KillRegions(child) end
    end
    local pb = rawget(frame, "PortraitButton") or rawget(_G, name .. "PortraitButton")
    if type(pb) == "table" and pb.SetAlpha then Skin.call(pb.SetAlpha, pb, 0) end
    frame.hh = { panel = Skin.Panel(frame, frame, 0, d.backgroundAlpha or Skin.cfg().backgroundAlpha or 0.85) }
    local title = rawget(frame, "Title") or rawget(frame, "TitleText") or rawget(_G, name .. "Name") or (frame.TitleContainer and frame.TitleContainer.TitleText)
    if type(title) == "table" then
      Skin.SetFont(title, d.fontSize or 12)
      if title.SetTextColor then Skin.call(title.SetTextColor, title, Skin.CREAM[1], Skin.CREAM[2], Skin.CREAM[3]) end
    end
    local close = rawget(frame, "CloseButton") or rawget(_G, name .. "CloseButton")
    if type(close) == "table" then
      Skin.KillRegions(close)
      close.hhX = close:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
      close.hhX:SetPoint("CENTER", close, "CENTER", 0, 0)
      close.hhX:SetText("x")
      close.hhX:SetTextColor(Skin.CREAM[1], Skin.CREAM[2], Skin.CREAM[3])
      Skin.SetFont(close.hhX, 14)
    end
    for _, b in ipairs(Part.Items(frame)) do Skin.IconButton(b, { hotkeySize = d.fontSize or 12 }) end
    if type(hooksecurefunc) == "function" and type(frame.UpdateItems) == "function" then
      pcall(hooksecurefunc, frame, "UpdateItems", function(self) if Skin.cfg().enabled ~= false then Part.ColorItems(self) end end)
    end
  end
  Part.ColorItems(frame)
end

function Part.Apply()
  local d = Skin.cfg().bags
  if not d or d.enabled == false then return end
  for _, n in ipairs(Part.NAMES) do
    local f = Skin.G(n)
    if type(f) == "table" and not Part.frames[f] then
      Part.frames[f] = true
      f:HookScript("OnShow", function(self) if Skin.cfg().enabled ~= false and Skin.cfg().bags.enabled ~= false then Part.Style(self) end end)
      if f.IsShown and f:IsShown() then Part.Style(f) end
    end
  end
  -- classic clients recolour through this global; modern ones through the frame method hooked in Style
  if not Part.hookedUpdate and type(hooksecurefunc) == "function" and type(rawget(_G, "ContainerFrame_Update")) == "function" then
    Part.hookedUpdate = true
    pcall(hooksecurefunc, "ContainerFrame_Update", function(frame)
      if type(frame) == "table" and frame.hh and Skin.cfg().enabled ~= false then Part.ColorItems(frame) end
    end)
  end
end

function Part.OnEvent(e)
  if e == "BAG_UPDATE_DELAYED" or e == "BAG_UPDATE" then
    for f in pairs(Part.frames) do if f.hh and f:IsShown() then Part.ColorItems(f) end end
  elseif e == "PLAYER_ENTERING_WORLD" then
    Part.Apply()
  end
end

Skin.Register(Part)
