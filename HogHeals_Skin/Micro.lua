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
    s.hhOurs = true
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

-- Our glyphs (HogHeals/Media/micro_*.tga, drawn in dev/icons/icons.html). A client that refuses the file gets the letter.
Part.ICONS = {
  CharacterMicroButton = "micro_character", ProfessionMicroButton = "micro_professions", SpellbookMicroButton = "micro_spellbook",
  PlayerSpellsMicroButton = "micro_spellbook", TalentMicroButton = "micro_talents", AchievementMicroButton = "micro_achievements",
  QuestLogMicroButton = "micro_quests", GuildMicroButton = "micro_guild", SocialsMicroButton = "micro_social",
  LFDMicroButton = "micro_lfg", LFGMicroButton = "micro_lfg", CollectionsMicroButton = "micro_collections", EJMicroButton = "micro_ej",
  PVPMicroButton = "micro_pvp", StoreMicroButton = "micro_shop", HelpMicroButton = "micro_help", MainMenuMicroButton = "micro_menu",
  WorldMapMicroButton = "micro_map",
}
Part.MEDIA = "Interface\\AddOns\\HogHeals\\Media\\"
-- The one Bags cell at the end of the bar (Sean 2026-10-02: "the bag icons look terrible... just have one to open all
-- the bags at once"). A plain button: ToggleAllBags is not protected, so it works in combat without a secure path.
Part.BAG_CELL = { icon = "micro_bags", letter = "B", label = "Bags" }

-- A colour per glyph (the art is cream, so SetVertexColor tints it; the ink stroke stays ink). Applied at
-- micro.tintStrength between cream (0) and the full colour (1); hover = the full colour. Sean 2026-10-02:
-- "colorize them a little bit".
Part.TINT = {
  micro_character = { 1.00, 0.80, 0.40 }, micro_professions = { 0.85, 0.65, 0.40 }, micro_spellbook = Skin.CYAN,
  micro_talents = { 1.00, 0.80, 0.40 }, micro_achievements = { 1.00, 0.85, 0.30 }, micro_quests = { 1.00, 0.72, 0.25 },
  micro_guild = { 0.40, 0.85, 0.50 }, micro_social = Skin.CYAN, micro_lfg = { 0.70, 0.55, 0.95 },
  micro_collections = { 0.35, 0.80, 0.75 }, micro_ej = { 0.95, 0.55, 0.35 }, micro_pvp = { 0.90, 0.35, 0.35 },
  micro_shop = { 1.00, 0.85, 0.30 }, micro_help = Skin.CREAM, micro_menu = Skin.CREAM, micro_map = { 0.55, 0.80, 0.40 },
}

--- Cream pulled `s` of the way to the glyph's colour (0 = cream, 1 = the colour).
function Part.Tint(id, s)
  local t = Part.TINT[id] or Skin.CREAM
  s = math.max(0, math.min(1, tonumber(s) or 0))
  local c = Skin.CREAM
  return { c[1] + (t[1] - c[1]) * s, c[2] + (t[2] - c[2]) * s, c[3] + (t[3] - c[3]) * s }
end

local silenced = setmetatable({}, { __mode = "k" })   -- Blizzard frames we faded; weak keys, no fields on them
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

-- ------------------------------------------------------------------------------------------------ Blizzard's art
-- In game 2026-10-02 (Sean's screenshot): the buttons were gone but a gold-trimmed panel still stood behind the bar
-- and the bags - art we have no name for on this client. So: walk up from every micro button (3 levels, never
-- UIParent). A plain Frame whose name says Micro (or that holds nothing but micro buttons) and no bag slot is
-- faded like the buttons - everything it draws goes with it. Any other ancestor gets its textures cleared
-- (Skin.KillArt: regions + plain-Frame children such as a NineSlice; buttons / bars untouched).

local function parentOf(f) return Skin.call(f.GetParent, f) end

--- True when any of `bags` descends from `f`.
local function holdsBag(f, bags)
  for _, b in ipairs(bags) do
    local p, d = parentOf(b), 0
    while type(p) == "table" and d < 6 do
      if p == f then return true end
      p, d = parentOf(p), d + 1
    end
  end
  return false
end

--- A frame whose button children are all micro buttons (and there is at least one).
local function microOnly(f)
  local n = 0
  for _, ch in ipairs({ Skin.call(f.GetChildren, f) }) do
    local kind = type(ch) == "table" and Skin.call(ch.GetObjectType, ch)
    if kind == "Button" or kind == "CheckButton" then
      local name = Skin.call(ch.GetName, ch)
      if type(name) ~= "string" or not name:find("MicroButton$") then return false end
      n = n + 1
    end
  end
  return n > 0
end

--- Fade / strip whatever Blizzard draws around the micro buttons. Returns a diag string per ancestor.
function Part.SilenceContainers(srcs, bags)
  local done, out = {}, {}
  Part.containers = Part.containers or {}
  for _, src in ipairs(srcs) do
    local p, d = parentOf(src), 0
    while type(p) == "table" and p ~= UIParent and not p.hhOurs and d < 3 and not done[p] do
      done[p] = true
      local name = Skin.call(p.GetName, p)
      name = type(name) == "string" and name or "?"
      local kind = Skin.call(p.GetObjectType, p)
      if kind == "Frame" and (name:find("Micro") or microOnly(p)) and not holdsBag(p, bags) then
        silence(p)
        Part.containers[#Part.containers + 1] = p
        out[#out + 1] = name .. ":faded"
      else
        out[#out + 1] = name .. ":art" .. Skin.KillArt(p)
      end
      p, d = parentOf(p), d + 1
    end
  end
  Part.containerDiag = table.concat(out, " ")
  return out
end

local function barFrame()
  if Part.bar then return Part.bar end
  local bar = CreateFrame("Frame", "HogHealsMicroBar", UIParent)
  bar.hhOurs = true
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

--- The look every cell shares: ink backdrop, outline, letter, glyph, cyan edges + full tint + tooltip on hover.
local function dress(c)
  c.hhOurs = true
  c.bg = Skin.Solid(c, "BACKGROUND", { 0.10, 0.10, 0.12 }, 0.9)
  c.bg:SetAllPoints(c)
  c.edges = Skin.Outline(c, c)
  c.letter = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  c.letter:SetPoint("CENTER", c, "CENTER", 0, 0)
  c.letter:SetTextColor(Skin.CREAM[1], Skin.CREAM[2], Skin.CREAM[3])
  c.icon = c:CreateTexture(nil, "ARTWORK")
  c.icon:SetPoint("CENTER", c, "CENTER", 0, 0)
  c.icon.hhOurs = true
  c:SetScript("OnEnter", function(self)
    Skin.ColorEdges(self.edges, Skin.CYAN)
    if self.tintFull then self.icon:SetVertexColor(self.tintFull[1], self.tintFull[2], self.tintFull[3]) end
    if GameTooltip and GameTooltip.SetOwner and self.label then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(self.label, Skin.CREAM[1], Skin.CREAM[2], Skin.CREAM[3])
      GameTooltip:Show()
    end
  end)
  c:SetScript("OnLeave", function(self)
    Skin.ColorEdges(self.edges, Skin.LINE)
    if self.tint then self.icon:SetVertexColor(self.tint[1], self.tint[2], self.tint[3]) end
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
  end)
  return c
end

local function cell(i, bar)
  local c = bar.cells[i]
  if c then return c end
  c = CreateFrame("Button", "HogHealsMicroBarButton" .. i, bar, "SecureActionButtonTemplate")
  if c.RegisterForClicks then c:RegisterForClicks(HH.SecureClick()) end   -- the edge this client acts on (cvar); "AnyUp" alone was dead on Forever
  dress(c)
  bar.cells[i] = c
  return c
end

--- Open / close every bag. The global exists on every client we run on; the older pair is the fallback.
function Part.ToggleBags()
  if type(ToggleAllBags) == "function" then ToggleAllBags() return true end
  if type(OpenAllBags) == "function" then OpenAllBags() return true end
  return false
end

local function bagCell(bar)
  if bar.bagCell then return bar.bagCell end
  local c = CreateFrame("Button", "HogHealsMicroBarBags", bar)
  dress(c)
  c:SetScript("OnClick", function() Part.ToggleBags() end)
  bar.bagCell = c
  return c
end

--- The bar carries the Bags cell and Blizzard's slots are hidden (bagBar.mode "button", the default) - unless the
-- bar itself is off (strip = false), then the slots stay.
function Part.BagsAsButton()
  local d = Skin.cfg()
  return (d.bagBar and d.bagBar.enabled ~= false and (d.bagBar.mode or "button") ~= "slots" and d.micro and d.micro.strip ~= false) and true or false
end

--- Glyph / letter / size / tint for one cell.
local function paintCell(c, size, id, letter, label, strength)
  c.label = label
  c.letter:SetText(letter)
  Skin.SetFont(c.letter, math.max(9, math.floor(size * 0.5)))
  c:SetSize(size, size - 4)
  local took = id and (c.icon:SetTexture(Part.MEDIA .. id) ~= false)
  c.icon:SetSize(size - 4, size - 4)   -- glyphs fill the cell (was size - 6; Sean 2026-10-02: "a little bigger")
  if took then c.icon:Show() c.letter:Hide() else c.icon:Hide() c.letter:Show() end
  c.glyph = took and id or nil
  c.tint = Part.Tint(id, strength)
  c.tintFull = Part.Tint(id, strength > 0 and 1 or 0)
  c.icon:SetVertexColor(c.tint[1], c.tint[2], c.tint[3])
  c.letter:SetTextColor(c.tint[1], c.tint[2], c.tint[3])
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
  -- default: right above the rightmost bag button (in game 2026-10-01: anchored to a strip that had not been laid
  -- out yet, the bar fell to the screen corner - under the bag slots). No placed bag button yet: above where the
  -- bag bar lives, and OnEvent tries again after the first layout pass.
  local right, rr
  for _, b in ipairs(Part.BagButtons()) do
    local r = Skin.call(b.GetRight, b)
    if Skin.num(r) and (not rr or r > rr) then right, rr = b, r end
  end
  if right then
    -- with the Bags cell in the bar the slots are hidden: the bar takes their place; otherwise it sits above them
    if Part.BagsAsButton() then bar:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)
    else bar:SetPoint("BOTTOMRIGHT", right, "TOPRIGHT", 0, 8) end
    Part.barAnchor = "bags"
    return
  end
  bar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -4, 64)
  Part.barAnchor = "screen"
end

--- Build / refresh the letter bar from whatever micro buttons this client has. Returns how many.
function Part.Strip()
  local m = Skin.cfg().micro
  local srcs = Part.MicroButtons()
  local bar = barFrame()
  local size, pad = m.size or 30, 3
  local strength = m.tint == false and 0 or (m.tintStrength or 0.6)
  local n = 0
  for i, src in ipairs(srcs) do
    n = n + 1
    local c = cell(i, bar)
    local name = src:GetName()
    local lab = Part.LABELS[name]
    -- the glyph when the client takes the file, the letter when it does not
    paintCell(c, size, Part.ICONS[name], lab and lab[1] or name:gsub("MicroButton$", ""):sub(1, 1):upper(), lab and lab[2] or name:gsub("MicroButton$", ""), strength)
    c:ClearAllPoints()
    c:SetPoint("LEFT", bar, "LEFT", pad + (i - 1) * (size + pad), 0)
    c:SetAttribute("type", "click")
    c:SetAttribute("clickbutton", src)
    c.source = src
    c:Show()
    silence(src)
  end
  for i = n + 1, #bar.cells do bar.cells[i]:Hide() end
  local total = n
  if n > 0 and Part.BagsAsButton() then
    total = n + 1
    local c = bagCell(bar)
    paintCell(c, size, Part.BAG_CELL.icon, Part.BAG_CELL.letter, Part.BAG_CELL.label, strength)
    c:ClearAllPoints()
    c:SetPoint("LEFT", bar, "LEFT", pad + n * (size + pad), 0)
    c:Show()
  elseif bar.bagCell then
    bar.bagCell:Hide()
  end
  bar:SetSize(pad + total * (size + pad), size + 2)
  bar:SetScale(1)   -- never the "Menu buttons scale" (that shrinks Blizzard's menu; it made these letters 10 px apart)
  bar.bg:SetColorTexture(Skin.INK[1], Skin.INK[2], Skin.INK[3], Skin.cfg().backgroundAlpha or 0.75)
  Part.SilenceContainers(srcs, Part.BagButtons())
  Part.AnchorBar()
  if n > 0 then bar:Show() else bar:Hide() end
  Part.microCount = n
  return n
end

--- Back to Blizzard's buttons (strip option off): theirs visible again, our bar gone.
function Part.Unstrip()
  for _, src in ipairs(Part.MicroButtons()) do unsilence(src) end
  for _, c in ipairs(Part.containers or {}) do unsilence(c) end
  Part.containers = {}
  if Part.bar then Part.bar:Hide() end
end

function Part.SetUnlocked(unlocked)
  local bar = Part.bar
  if not bar then return end
  bar:EnableMouse(unlocked and true or false)
  Skin.ColorEdges(bar.edges, unlocked and Skin.CYAN or Skin.LINE)
end

--- Bag slots: the named ones, anything bag-like under the bag containers, and - in game 2026-10-02 on Forever one
-- slot matched no name we know and stayed on screen beside seven faded ones - any button-kind frame that sits in
-- a bag container or beside a found slot (its parent named after bags; never a classic action-bar parent).
local BUTTON_KINDS = { Button = true, CheckButton = true, ItemButton = true }
local function bagLike(f, loose)
  if type(f) ~= "table" or not f.GetName or not f.GetLeft then return false end
  local n = Skin.call(f.GetName, f)
  if type(n) == "string" then
    if n:find("ExpandToggle") or n:find("MicroButton$") or n:find("^ActionButton") or n:find("^MultiBar") or n:find("^HogHeals") then return false end
    if n:find("Bag") or n:find("Backpack") then return true end
  end
  if loose then return BUTTON_KINDS[Skin.call(f.GetObjectType, f)] == true end
  return false
end

function Part.BagButtons()
  local seen, out = {}, {}
  local function take(f, loose)
    if not seen[f] and bagLike(f, loose) then seen[f] = true out[#out + 1] = f end
  end
  for _, n in ipairs(Part.BAGS) do take(Skin.G(n), true) end   -- our own list: taken as named (KeyRingButton has no Bag in it)
  for _, cn in ipairs(Part.BAG_CONTAINERS) do
    local c = rawget(_G, cn)
    if type(c) == "table" then for _, ch in ipairs(Skin.all(c.GetChildren, c)) do take(ch, true) end end
  end
  -- neighbours: every button in the parent of a found slot, when that parent is a bag bar by name
  local parents, found = {}, {}
  for i, b in ipairs(out) do found[i] = b end
  for _, b in ipairs(found) do
    local p = Skin.call(b.GetParent, b)
    local pn = type(p) == "table" and Skin.call(p.GetName, p)
    if type(p) == "table" and p ~= UIParent and not parents[p] and type(pn) == "string" and pn:find("Bag") then
      parents[p] = true
      for _, ch in ipairs(Skin.all(p.GetChildren, p)) do take(ch, true) end
    end
  end
  return out
end

local function screenRect(f)
  local s = Skin.num(Skin.call(f.GetEffectiveScale, f)) or 1
  local l, r, t, b = Skin.num(Skin.call(f.GetLeft, f)), Skin.num(Skin.call(f.GetRight, f)), Skin.num(Skin.call(f.GetTop, f)), Skin.num(Skin.call(f.GetBottom, f))
  if not (l and r and t and b) then return nil end
  return l * s, r * s, t * s, b * s
end

--- Whatever Blizzard still draws over the faded slots. In game 2026-10-02 (Sean, screenshot 6): the slots' icons
-- were gone but a slot border and the backpack's gold highlight stayed - decorations on frames of their own, not
-- regions of the slot. Every small visible frame (<= 120 px) whose rect sits inside a faded slot's rect, that is
-- not ours, not a tooltip and not the slot itself, is faded like the slot. Names kept in Part.bagOverlayDiag.
function Part.SweepBagOverlays(bags)
  if type(EnumerateFrames) ~= "function" then Part.bagOverlayDiag = "no EnumerateFrames" return 0 end
  local rects, slot = {}, {}
  for _, b in ipairs(bags) do
    local l, r, t, bt = screenRect(b)
    if l then rects[#rects + 1] = { l - 4, r + 4, t + 4, bt - 4 } slot[b] = true end
  end
  if #rects == 0 then Part.bagOverlayDiag = "no slot rects yet" return 0 end
  Part.overlays = Part.overlays or {}
  local names, n, f, count = {}, 0, EnumerateFrames(), 0
  while type(f) == "table" and count < 20000 do
    count = count + 1
    if not slot[f] and not f.hhOurs and not silenced[f] then
      local name = Skin.call(f.GetName, f)
      local kind = Skin.call(f.GetObjectType, f)
      local skip = type(name) == "string" and (name:find("^HogHeals") or name:find("Tooltip"))
      if not skip and (kind == "Frame" or BUTTON_KINDS[kind]) and Skin.call(f.IsVisible, f) then
        local l, r, t, bt = screenRect(f)
        if l and (r - l) <= 120 and (t - bt) <= 120 then
          for _, rc in ipairs(rects) do
            if l >= rc[1] and r <= rc[2] and t <= rc[3] and bt >= rc[4] then
              silence(f)
              Part.overlays[#Part.overlays + 1] = f
              names[#names + 1] = type(name) == "string" and name or (tostring(kind) .. "?")
              n = n + 1
              break
            end
          end
        end
      end
    end
    f = EnumerateFrames(f)
  end
  Part.bagOverlayDiag = (#names > 0) and table.concat(names, ",") or "none"
  return n
end

--- The bag slots in the micro bar's look: flat cell, scaled up, cyan outline under the mouse, the art around
-- them cleared (same walk as the micro buttons: the slot's ancestors, 3 levels, never UIParent).
function Part.StyleBags(bags, d)
  local scale = d.scale or 1.2
  for _, b in ipairs(bags) do
    Skin.IconButton(b, { hotkeySize = 10 })
    Skin.call(b.SetScale, b, scale)
    if not b.hhHover and b.HookScript then
      b.hhHover = true
      b:HookScript("OnEnter", function(self) if self.hh and self.hh.edges then Skin.ColorEdges(self.hh.edges, Skin.CYAN) end end)
      b:HookScript("OnLeave", function(self) if self.hh and self.hh.edges then Skin.ColorEdges(self.hh.edges, Skin.LINE) end end)
    end
  end
  return Part.SweepBagArt(bags)
end

--- The art around the bag slots cleared (their ancestors, 3 levels, never UIParent, plus the bag containers).
function Part.SweepBagArt(bags)
  local done, out = {}, {}
  for _, b in ipairs(bags) do
    local p, depth = parentOf(b), 0
    while type(p) == "table" and p ~= UIParent and not p.hhOurs and depth < 3 and not done[p] do
      done[p] = true
      local name = Skin.call(p.GetName, p)
      out[#out + 1] = (type(name) == "string" and name or "?") .. ":art" .. Skin.KillArt(p)
      p, depth = parentOf(p), depth + 1
    end
  end
  for _, cn in ipairs(Part.BAG_CONTAINERS) do
    local c = rawget(_G, cn)
    if type(c) == "table" and not done[c] then done[c] = true out[#out + 1] = cn .. ":art" .. Skin.KillArt(c) end
  end
  Part.bagDiag = table.concat(out, " ")
  return out
end

function Part.Apply()
  local d = Skin.cfg()
  if d.bagBar and d.bagBar.enabled ~= false then
    local bags = Part.BagButtons()
    for _, n in ipairs(Part.BAG_HIDE) do Skin.HideFrame(Skin.G(n)) end
    if Part.BagsAsButton() then
      -- the Bags cell in the bar stands in: Blizzard's slots faded and kept faded, their art cleared, no strip
      Part.SweepBagArt(bags)
      for _, b in ipairs(bags) do silence(b) end
      if Part.strips and Part.strips.bags then Part.strips.bags:Hide() end
      Part.bagMode = "button"
      Part.SweepBagOverlays(bags)
      if C_Timer and C_Timer.After then
        C_Timer.After(1, function() if Part.BagsAsButton() then Part.SweepBagOverlays(Part.BagButtons()) end end)
      end
    else
      for _, b in ipairs(bags) do unsilence(b) end
      for _, f in ipairs(Part.overlays or {}) do unsilence(f) end
      Part.overlays = {}
      Part.StyleBags(bags, d.bagBar)
      strip("bags", bags, 3)
      Part.bagMode = "slots"
    end
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
    for _, n in ipairs(Part.MICRO_CONTAINERS) do
      local c = rawget(_G, n)
      if type(c) == "table" then Skin.KillArt(c) end
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
    local stripPending = not Part.BagsAsButton() and not (s and s.bags and s.bags.placed)
    if stripPending or Part.barAnchor == "screen" or (Skin.cfg().micro.strip ~= false and (Part.microCount or 0) < 3) then Part.Apply()
    elseif e == "PLAYER_ENTERING_WORLD" and Part.BagsAsButton() then Part.SweepBagOverlays(Part.BagButtons()) end
  end
end

Skin.Register(Part)
