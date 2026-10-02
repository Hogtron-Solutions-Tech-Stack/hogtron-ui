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

-- ------------------------------------------------------------------------------------------------ HogUI micro bar
-- Blizzard's menu buttons are one atlas each - the gold frame is baked into the picture, there is nothing to strip
-- (Sean 2026-10-01: "needs to be customized to fit the UI"). So they go invisible and a row of ink letter buttons
-- stands in. Every letter is a SecureActionButton with type="click" / clickbutton=<the real button>: the client
-- itself presses Blizzard's button, so each window opens exactly the way this client opens it, no taint, in combat
-- too. Letters, not icons: no art to ship, same look on every client.
Part.LABELS = {
  CharacterMicroButton = { "C", "Character" }, ProfessionMicroButton = { "P", "Professions" },
  SpellbookMicroButton = { "S", "Spellbook" }, PlayerSpellsMicroButton = { "S", "Spellbook & Talents" },
  TalentMicroButton = { "T", "Talents" }, AchievementMicroButton = { "A", "Achievements" },
  QuestLogMicroButton = { "Q", "Quest Log" }, GuildMicroButton = { "G", "Guild & Communities" },
  SocialsMicroButton = { "O", "Social" }, LFDMicroButton = { "L", "Group Finder" }, LFGMicroButton = { "L", "Group Finder" },
  CollectionsMicroButton = { "J", "Collections" }, EJMicroButton = { "E", "Adventure Guide" }, PVPMicroButton = { "V", "PvP" },
  StoreMicroButton = { "$", "Shop" }, HelpMicroButton = { "?", "Help" }, MainMenuMicroButton = { "M", "Game Menu" },
  WorldMapMicroButton = { "W", "World Map" },
}

local silenced = setmetatable({}, { __mode = "k" })   -- Blizzard buttons we faded; weak keys, no fields on them
local fading = setmetatable({}, { __mode = "k" })

--- Blizzard's micro buttons on this client, in Blizzard's left-to-right order when they have one.
function Part.MicroButtons()
  local seen, out = {}, {}
  local function take(f)
    if type(f) ~= "table" or seen[f] or not f.GetName then return end
    local n = f:GetName()
    if type(n) ~= "string" or not n:find("MicroButton$") then return end
    seen[f] = true
    out[#out + 1] = f
  end
  for _, n in ipairs(Part.MICRO) do take(rawget(_G, n)) end
  for _, cn in ipairs(Part.MICRO_CONTAINERS) do
    local c = rawget(_G, cn)
    if type(c) == "table" and c.GetChildren then for _, ch in ipairs({ c:GetChildren() }) do take(ch) end end
  end
  -- our order, always: in game 2026-10-01 Blizzard's menu was a grid, and sorting by GetLeft scrambled the letters
  local order = {}
  for i, n in ipairs(Part.MICRO) do order[n] = i end
  table.sort(out, function(a, b)
    local oa, ob = order[a:GetName()] or 99, order[b:GetName()] or 99
    if oa ~= ob then return oa < ob end
    return a:GetName() < b:GetName()
  end)
  return out
end

local function silence(src)
  if silenced[src] then return end
  silenced[src] = true
  Skin.call(src.SetAlpha, src, 0)
  if src.EnableMouse then Skin.call(src.EnableMouse, src, false) end
  if type(hooksecurefunc) == "function" and src.SetAlpha then
    pcall(hooksecurefunc, src, "SetAlpha", function(self)
      if fading[self] or not silenced[self] then return end
      fading[self] = true
      Skin.call(self.SetAlpha, self, 0)
      fading[self] = nil
    end)
  end
end

local function unsilence(src)
  if not silenced[src] then return end
  silenced[src] = nil
  Skin.call(src.SetAlpha, src, 1)
  if src.EnableMouse then Skin.call(src.EnableMouse, src, true) end
end

local function barFrame()
  if Part.bar then return Part.bar end
  local bar = CreateFrame("Frame", "HogHealsMicroBar", UIParent)
  bar:SetFrameStrata("MEDIUM")   -- above the bag strip (LOW): in game 2026-10-01 the cells hid behind it
  bar:SetMovable(true)
  bar:SetClampedToScreen(true)
  bar.bg = Skin.Solid(bar, "BACKGROUND", Skin.INK, Skin.cfg().backgroundAlpha or 0.75)
  bar.bg:SetAllPoints(bar)
  bar.edges = Skin.Outline(bar, bar)
  bar.cells = {}
  -- /hh unlock: drag the bar; the spot is kept
  bar:EnableMouse(false)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function(self) if HH.db.profile.locked == false then self:StartMoving() end end)
  bar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint(1)
    if point then local m = Skin.cfg().micro m.point, m.x, m.y = point, x, y end
  end)
  Part.bar = bar
  return bar
end

local function cell(i, bar)
  local c = bar.cells[i]
  if c then return c end
  c = CreateFrame("Button", "HogHealsMicroBarButton" .. i, bar, "SecureActionButtonTemplate")
  if c.RegisterForClicks then c:RegisterForClicks("AnyUp") end
  c.bg = Skin.Solid(c, "BACKGROUND", { 0.10, 0.10, 0.12 }, 0.9)
  c.bg:SetAllPoints(c)
  c.edges = Skin.Outline(c, c)
  c.letter = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  c.letter:SetPoint("CENTER", c, "CENTER", 0, 0)
  c.letter:SetTextColor(Skin.CREAM[1], Skin.CREAM[2], Skin.CREAM[3])
  c:SetScript("OnEnter", function(self)
    Skin.ColorEdges(self.edges, Skin.CYAN)
    if GameTooltip and GameTooltip.SetOwner and self.label then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(self.label, Skin.CREAM[1], Skin.CREAM[2], Skin.CREAM[3])
      GameTooltip:Show()
    end
  end)
  c:SetScript("OnLeave", function(self)
    Skin.ColorEdges(self.edges, Skin.LINE)
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
  end)
  bar.cells[i] = c
  return c
end

function Part.AnchorBar()
  local bar, m = Part.bar, Skin.cfg().micro
  if not bar then return end
  bar:ClearAllPoints()
  if type(m.point) == "string" and type(m.x) == "number" and type(m.y) == "number" then
    bar:SetPoint(m.point, UIParent, m.point, m.x, m.y)
    Part.barAnchor = "saved"
    return
  end
  -- default: right above the bag strip (in game 2026-10-01 Blizzard's container sat ON the bag bar and the letters
  -- landed across the bag slots); without a bag strip, the screen's bottom-right corner
  local bags = Part.strips and Part.strips.bags
  if bags and bags.placed then
    bar:SetPoint("BOTTOMRIGHT", bags, "TOPRIGHT", 0, 4)
    Part.barAnchor = "bags"
    return
  end
  bar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -4, 4)
  Part.barAnchor = "screen"
end

--- Build / refresh the letter bar from whatever micro buttons this client has. Returns how many.
function Part.Strip()
  local m = Skin.cfg().micro
  local srcs = Part.MicroButtons()
  local bar = barFrame()
  local size, pad = m.size or 24, 3
  local n = 0
  for i, src in ipairs(srcs) do
    n = n + 1
    local c = cell(i, bar)
    local name = src:GetName()
    local lab = Part.LABELS[name]
    local letter = lab and lab[1] or name:gsub("MicroButton$", ""):sub(1, 1):upper()
    c.label = lab and lab[2] or name:gsub("MicroButton$", "")
    c.letter:SetText(letter)
    Skin.SetFont(c.letter, math.max(9, math.floor(size * 0.5)))
    c:SetSize(size, size - 4)
    c:ClearAllPoints()
    c:SetPoint("LEFT", bar, "LEFT", pad + (i - 1) * (size + pad), 0)
    c:SetAttribute("type", "click")
    c:SetAttribute("clickbutton", src)
    c.source = src
    c:Show()
    silence(src)
  end
  for i = n + 1, #bar.cells do bar.cells[i]:Hide() end
  bar:SetSize(pad + n * (size + pad), size + 2)
  bar:SetScale(1)   -- never the "Menu buttons scale" (that shrinks Blizzard's menu; it made these letters 10 px apart)
  bar.bg:SetColorTexture(Skin.INK[1], Skin.INK[2], Skin.INK[3], Skin.cfg().backgroundAlpha or 0.75)
  Part.AnchorBar()
  if n > 0 then bar:Show() else bar:Hide() end
  Part.microCount = n
  return n
end

--- Back to Blizzard's buttons (strip option off): theirs visible again, our bar gone.
function Part.Unstrip()
  for _, src in ipairs(Part.MicroButtons()) do unsilence(src) end
  if Part.bar then Part.bar:Hide() end
end

function Part.SetUnlocked(unlocked)
  local bar = Part.bar
  if not bar then return end
  bar:EnableMouse(unlocked and true or false)
  Skin.ColorEdges(bar.edges, unlocked and Skin.CYAN or Skin.LINE)
end

--- Bag slots: the named ones plus anything bag-like under the bag containers (this client may name them differently).
function Part.BagButtons()
  local seen, out = {}, {}
  local function take(f)
    if type(f) ~= "table" or seen[f] or not f.GetName or not f.GetLeft then return end
    local n = f:GetName()
    if type(n) ~= "string" or not (n:find("Bag") or n:find("Backpack")) or n:find("ExpandToggle") then return end
    seen[f] = true
    out[#out + 1] = f
  end
  for _, n in ipairs(Part.BAGS) do take(Skin.G(n)) end
  for _, cn in ipairs(Part.BAG_CONTAINERS) do
    local c = rawget(_G, cn)
    if type(c) == "table" and c.GetChildren then for _, ch in ipairs({ c:GetChildren() }) do take(ch) end end
  end
  return out
end

function Part.Apply()
  local d = Skin.cfg()
  if d.bagBar and d.bagBar.enabled ~= false then
    local bags = Part.BagButtons()
    for _, b in ipairs(bags) do Skin.IconButton(b, { hotkeySize = 10 }) end
    for _, n in ipairs(Part.BAG_HIDE) do Skin.HideFrame(Skin.G(n)) end
    strip("bags", bags, 3)
    Part.bagCount = #bags
    local names = {}
    for _, b in ipairs(bags) do names[#names + 1] = b:GetName() end
    Part.bagNames = table.concat(names, ",")
  end
  if d.micro and d.micro.enabled ~= false then
    for _, p in ipairs(Part.MICRO_ART) do
      local v = Skin.Path(p)
      if type(v) == "table" then if v.GetObjectType and v:GetObjectType() == "Texture" then Skin.Kill(v) else Skin.KillRegions(v) end end
    end
    if d.micro.strip ~= false then
      Part.Strip()
      if Part.strips and Part.strips.micro then Part.strips.micro:Hide() end
      if not Part.lockHooked and type(hooksecurefunc) == "function" and type(HH.SetLocked) == "function" then
        Part.lockHooked = true
        pcall(hooksecurefunc, HH, "SetLocked", function(_, locked) Part.SetUnlocked(not locked) end)
      end
      Part.SetUnlocked(HH.db.profile.locked == false)
    else
      Part.Unstrip()
      local micro = present(Part.MICRO)
      strip("micro", micro, 3)
      for _, n in ipairs(Part.MICRO_CONTAINERS) do
        local c = rawget(_G, n)
        if type(c) == "table" and c.SetScale then Skin.call(c.SetScale, c, d.micro.scale or 1) break end
      end
      Part.microCount = #micro
    end
  end
end

function Part.OnEvent(e)
  if e == "PLAYER_ENTERING_WORLD" or e == "PLAYER_REGEN_ENABLED" then
    -- strips anchored before the first layout pass need a second go; late micro buttons too
    local s = Part.strips
    if not s or not (s.bags and s.bags.placed) or (Skin.cfg().micro.strip ~= false and (Part.microCount or 0) < 3) then Part.Apply() end
  end
end

Skin.Register(Part)
