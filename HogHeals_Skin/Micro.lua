-- The bottom menu buttons (character, spellbook, ... main menu) and the bag bar: Blizzard's backdrop art cleared,
-- one ink strip behind each group, bag slots flattened like action buttons.
local HHS = HogHealsSkin
local Skin = HHS.Skin
local HH = HogHeals

local Part = { name = "micro" }
HHS.Micro = Part

Part.MICRO = { "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "AchievementMicroButton", "QuestLogMicroButton",
  "GuildMicroButton", "SocialsMicroButton", "LFDMicroButton", "LFGMicroButton", "CollectionsMicroButton", "EJMicroButton",
  "PVPMicroButton", "StoreMicroButton", "MainMenuMicroButton", "HelpMicroButton", "WorldMapMicroButton" }
Part.MICRO_ART = { "MicroButtonAndBagsBar.MicroBagBar", "MicroMenu.Background", "MicroButtonAndBagsBar.Background" }
Part.MICRO_CONTAINERS = { "MicroMenuContainer", "MicroMenu", "MicroButtonAndBagsBar" }
Part.BAGS = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
  "CharacterReagentBag0Slot", "KeyRingButton" }
Part.BAG_HIDE = { "BagBarExpandToggle" }
Part.BAG_CONTAINERS = { "BagsBar", "MicroButtonAndBagsBar" }

local function present(names)
  local out = {}
  for _, n in ipairs(names) do
    local f = Skin.G(n)
    if type(f) == "table" and f.GetLeft then out[#out + 1] = f end
  end
  return out
end

--- One ink strip behind a row of buttons: anchored to the leftmost and rightmost of them once they have a
-- position (GetLeft is nil until the first layout pass; we try again on the next event).
local function strip(key, frames, pad)
  if #frames == 0 then return nil end
  local left, right = frames[1], frames[1]
  local placed = true
  for _, f in ipairs(frames) do
    local l, r = Skin.call(f.GetLeft, f), Skin.call(f.GetRight, f)
    local ll = Skin.call(left.GetLeft, left)
    local rr = Skin.call(right.GetRight, right)
    if not l or not r then placed = false end
    if l and ll and l < ll then left = f end
    if r and rr and r > rr then right = f end
  end
  local s = Part.strips and Part.strips[key]
  if not s then
    s = CreateFrame("Frame", nil, UIParent)
    s:SetFrameStrata("LOW")
    s.bg = Skin.Solid(s, "BACKGROUND", Skin.INK, Skin.cfg().backgroundAlpha or 0.75)
    s.bg:SetAllPoints(s)
    s.edges = Skin.Outline(s, s)
    Part.strips = Part.strips or {}
    Part.strips[key] = s
  end
  s:ClearAllPoints()
  s:SetPoint("TOPLEFT", left, "TOPLEFT", -pad, pad)
  s:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", pad, -pad)
  s:SetFrameLevel(math.max(0, ((left.GetFrameLevel and left:GetFrameLevel()) or 1) - 1))
  s.placed = placed
  s:Show()
  return s
end

function Part.Apply()
  local d = Skin.cfg()
  if d.micro and d.micro.enabled ~= false then
    for _, p in ipairs(Part.MICRO_ART) do
      local v = Skin.Path(p)
      if type(v) == "table" then if v.GetObjectType and v:GetObjectType() == "Texture" then Skin.Kill(v) else Skin.KillRegions(v) end end
    end
    local micro = present(Part.MICRO)
    strip("micro", micro, 3)
    for _, n in ipairs(Part.MICRO_CONTAINERS) do
      local c = rawget(_G, n)
      if type(c) == "table" and c.SetScale then Skin.call(c.SetScale, c, d.micro.scale or 1) break end
    end
    Part.microCount = #micro
  end
  if d.bagBar and d.bagBar.enabled ~= false then
    local bags = present(Part.BAGS)
    for _, b in ipairs(bags) do Skin.IconButton(b, { hotkeySize = 10 }) end
    for _, n in ipairs(Part.BAG_HIDE) do Skin.HideFrame(Skin.G(n)) end
    strip("bags", bags, 3)
    Part.bagCount = #bags
  end
end

function Part.OnEvent(e)
  if e == "PLAYER_ENTERING_WORLD" or e == "PLAYER_REGEN_ENABLED" then
    -- strips anchored before the first layout pass need a second go
    local s = Part.strips
    if not s or not (s.micro and s.micro.placed) or not (s.bags and s.bags.placed) then Part.Apply() end
  end
end

Skin.Register(Part)
