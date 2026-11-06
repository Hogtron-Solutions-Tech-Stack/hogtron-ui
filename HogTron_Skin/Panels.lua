-- Blizzard's windows (character sheet, spellbook, quest log, escape menu, vendor, mail, trade, bank, ...) in the
-- HogTron UI panel: their art, portrait and border switched off, an ink panel with a 1 px outline behind them, the title
-- in our font, a flat close button. Styled when first shown (many are load-on-demand), caught through OnShow, the
-- ShowUIPanel hook and Blizzard_* addon loads. Each window can be excluded in the options.
local HHS = HogHealsSkin
local Skin = HHS.Skin
local HH = HogHeals

local Part = { name = "panels", styled = {}, hooked = {}, shows = {}, subHooked = {}, subs = {}, sideTabPanels = {} }
HHS.Panels = Part

Part.NAMES = {
  "GameMenuFrame", "CharacterFrame", "SpellBookFrame", "PlayerSpellsFrame", "QuestLogFrame", "QuestLogDetailFrame", "FriendsFrame",
  "MerchantFrame", "MailFrame", "OpenMailFrame", "TradeFrame", "TaxiFrame", "GossipFrame", "QuestFrame", "LootFrame",
  "DressUpFrame", "PetStableFrame", "BankFrame", "GuildFrame", "TalentFrame", "PlayerTalentFrame", "ClassTalentFrame",
  "ItemTextFrame", "HelpFrame", "MacroFrame", "KeyBindingFrame", "LFGParentFrame", "PVPFrame", "RaidFrame",
  "GuildBankFrame", "AuctionFrame", "AuctionHouseFrame", "CraftFrame", "TradeSkillFrame", "ProfessionsFrame", "ClassTrainerFrame",
  "TabardFrame", "GuildRegistrarFrame", "PetitionFrame", "ReadyCheckFrame", "StaticPopup1", "StaticPopup2", "StaticPopup3",
  "InterfaceOptionsFrame", "SettingsPanel", "VideoOptionsFrame", "ChatConfigFrame", "TimeManagerFrame", "CalendarFrame",
  "AchievementFrame", "EncounterJournal", "CollectionsJournal", "GroupFinderFrame", "PVEFrame", "StopwatchFrame",
  -- WoW: Forever's social window (Friends / Who / Raid tabs down its right side): SocialUIFrame, not FriendsFrame - named
  -- by /hh under in game 2026-10-17 (Sean: "the Friends list ... I don't know that we ever did that" - it never was)
  "SocialUIFrame",
  -- Guild & Communities (Blizzard_Communities, load-on-demand). Sean 2026-11-05 over it: "We need to reskin all of this, including this."
  "CommunitiesFrame",
}
local wanted = {}
for _, n in ipairs(Part.NAMES) do wanted[n] = true end

local function skipped(name)
  local d = Skin.cfg().panels
  return d and type(d.skip) == "table" and d.skip[name] == true
end

-- ------------------------------------------------------------------------------------------------ the look
-- Sean 2026-11-05, after the Training page: "re-skin all of the windows to kind of match that same aesthetic" - and over
-- Guild & Communities: "We need to reskin all of this, including this." skin.panels.look: "parchment" (default) = the
-- quest dialog's torn page behind the window (HH.Parchment; light or charred after Quests > Dialog > Look), its title
-- in Friz Quadrata ink, a bronze rule, a key-cap close, tabs as rounded slabs, and on the LIGHT page every text inked
-- so it reads on paper (Part.Ink); "ink" = the flat panel with an outline, as before.
function Part.Look()
  local d = Skin.cfg().panels
  local v = d and d.look
  if v == "ink" then return "ink" end
  if v ~= "parchment" then                             -- "auto": the UI's look (General > Look > Style)
    local L = HH.Look
    if L and L.Theme and L.Theme() ~= "parchment" then return "ink" end
  end
  return HH.Parchment and "parchment" or "ink"
end
function Part.Theme() return Part.Look() == "parchment" and HH.Parchment.Theme() or nil end

-- Windows whose inner art IS the content (talent trees, models, journals, the auction house, recipe schematics, the
-- calendar grid): the deep strip would take meaning with it, and inked text on their dark art cannot be read. They
-- keep the ink panel in either look - Blizzard's art and Blizzard's light text, as before.
Part.KEEP_INNER = { TalentFrame = true, PlayerTalentFrame = true, ClassTalentFrame = true, DressUpFrame = true,
  PetStableFrame = true, AchievementFrame = true, EncounterJournal = true, CollectionsJournal = true, CalendarFrame = true,
  AuctionFrame = true, AuctionHouseFrame = true, MacroFrame = true, ProfessionsFrame = true, TradeSkillFrame = true, CraftFrame = true,
  KeyBindingFrame = true }
-- Windows whose inner art is kept under our page. Empty: the spellbook was here (its book is paper with dark text) but
-- Sean 2026-11-05 in game: "The spellbook is still messed up" - its dark top bar and the book's frame sat inside our
-- page. Its text is already dark, so the deep strip leaves it reading on our paper like the rest.
Part.BOOK = {}
--- The page theme for one window (nil = the ink panel: the ink look, or a window that keeps its inner art).
function Part.ThemeFor(name)
  if Part.KEEP_INNER[name or ""] then return nil end
  return Part.Theme()
end
--- true on the light page: Blizzard's (white / gold / grey) text must be inked to read.
function Part.Paper()
  local th = Part.Theme()
  return th ~= nil and th.paper == true
end

--- The page behind a window: the dialog's torn page, larger than the window by the art's torn margins so the window's
-- box (title, close, content, a tab strip under it) is all on paper; laid again when the window is resized; the
-- bronze rule under the title row. Our frame, one level under the window; f.hhPanel in both looks.
-- Margins measured on the 512 x 1024 art (2026-11-05): over the page body the tears stay within 46 px of the top,
-- 48 of the bottom and 32 of either side (only the outermost columns tear deeper).
Part.PAGE_SIDE, Part.PAGE_TOP, Part.PAGE_BOTTOM, Part.TAB_ROOM = 32, 46, 48, 34
function Part.Page(f, alpha, tabRoom, titled)
  local P = HH.Parchment
  local p = CreateFrame("Frame", nil, f)
  p.hhOurs = true
  p:SetFrameLevel(math.max(0, ((f.GetFrameLevel and f:GetFrameLevel()) or 1) - 1))
  P.MakePage(p)
  for _, t in ipairs({ p.pageTop, p.pageMid, p.pageBot }) do t.hhOurs = true end
  p.rule = p:CreateTexture(nil, "ARTWORK")
  p.rule.hhOurs = true
  p.rule:SetTexture(P.ART.rule)
  p.rule:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30)
  p.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -30)
  p.rule:SetHeight(6)
  if titled == false then p.rule:Hide() end        -- no title row (a popup): a rule would cross its message
  p:SetAlpha(alpha or 0.9)
  p.window, p.tabRoom = f, tabRoom or 0
  p:SetScript("OnSizeChanged", function(self) Part.Relay(self) end)
  Part.Relay(p)
  return p
end

--- The page frame placed around its window (the margins scale with the window's width) and the art laid over it.
function Part.Relay(p)
  if type(p) ~= "table" or not p.pageTop or not HH.Parchment or p.relaying then return false end
  local f = p.window
  local w = type(f) == "table" and Skin.num(Skin.call(f.GetWidth, f)) or 0
  local h = type(f) == "table" and Skin.num(Skin.call(f.GetHeight, f)) or 0
  if w <= 0 or h <= 0 then return false end
  local s = w / (HH.Parchment.PAGE_W - 2 * Part.PAGE_SIDE)
  local px, pt, pb = Part.PAGE_SIDE * s, Part.PAGE_TOP * s, Part.PAGE_BOTTOM * s + (p.tabRoom or 0)
  p.relaying = true
  p:ClearAllPoints()
  p:SetPoint("TOPLEFT", f, "TOPLEFT", -px, pt)
  p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", px, -pb)
  HH.Parchment.PlacePage(p, w + 2 * px, h + pt + pb)
  p.relaying = false
  return true
end

-- ------------------------------------------------------------------------------------------------ ink on paper
local function near(r, g, b, c) return math.abs(r - c[1]) + math.abs(g - c[2]) + math.abs(b - c[3]) < 0.02 end

--- A Blizzard text colour on the light page. Neutral (low saturation): bright -> the theme's ink, dim grey -> its
-- muted ink, already dark -> left. A hue (gold, red, green, a class colour): kept, brought down to a luminance that
-- reads on paper. One of the theme's own inks comes back unchanged (a second pass changes nothing). Pure maths.
Part.INK_LUM = 0.34
function Part.InkColor(r, g, b, th) return HH.Parchment.InkColor(r, g, b, th) end   -- the maths lives in core (our own frames use it too)

--- One string inked for the light page, and hooked once so a Blizzard repaint (hover, rebuild, tab select) is inked
-- again. Nothing happens off the light page (the hook checks each time, so a look change needs no unhooking).
function Part.Ink(fs)
  local th = Part.Theme()
  if not (th and th.paper) then return false end
  local r, g, b = Skin.call(fs.GetTextColor, fs)
  if not (Skin.num(r) and Skin.num(g) and Skin.num(b)) then return false end
  local nr, ng, nb = Part.InkColor(r, g, b, th)
  local changed = false
  if (math.abs(nr - r) + math.abs(ng - g) + math.abs(nb - b)) > 0.002 and not fs.hhInking then
    fs.hhInking = true
    Skin.call(fs.SetTextColor, fs, nr, ng, nb)
    fs.hhInking = false
    changed = true
  end
  Part.Clean(fs)
  if Part.InkText(fs) then changed = true end
  if not fs.hhInkHooked and type(hooksecurefunc) == "function" then
    fs.hhInkHooked = true
    pcall(hooksecurefunc, fs, "SetTextColor", function(self)
      if self.hhInking or Skin.cfg().enabled == false or Skin.cfg().panels.enabled == false or not Part.Paper() then return end
      Part.Ink(self)
    end)
    -- new text brings new colour codes (a friends row repainted, a stat line updated): ink them as they come
    for _, m in ipairs({ "SetText", "SetFormattedText" }) do
      if type(fs[m]) == "function" then
        pcall(hooksecurefunc, fs, m, function(self)
          if Skin.cfg().enabled == false or Skin.cfg().panels.enabled == false or not Part.Paper() then return end
          Part.InkText(self)
        end)
      end
    end
  end
  return changed
end

--- The colour codes inside a string's text inked (HH.Parchment.InkCodes), on the light page. A secret text is left
--- (never read or compared); text without codes is untouched. Our own SetText comes back through the hook and
--- changes nothing the second time.
local texting = setmetatable({}, { __mode = "k" })
Part.codesInked = 0
function Part.InkText(fs)
  if texting[fs] or not Part.Paper() or type(fs.GetText) ~= "function" then return false end
  local t = Skin.call(fs.GetText, fs)
  if HH.IsSecret(t) or type(t) ~= "string" then return false end
  local inked, n = HH.Parchment.InkCodes(t, Part.Theme())
  if inked == t then return false end
  texting[fs] = true
  Skin.call(fs.SetText, fs, inked)
  texting[fs] = nil
  Part.codesInked = Part.codesInked + (n or 0)
  return true
end

--- Ink on paper casts no shadow and has no outline: both off on an inked string (in game 2026-11-05 "Level 10 Druid"
--- kept Blizzard's black outline under the ink and read as a smudge). Method calls only.
function Part.Clean(fs)
  if fs.SetShadowOffset then Skin.call(fs.SetShadowOffset, fs, 0, 0) end
  local path, size, flags = Skin.call(fs.GetFont, fs)
  if type(path) == "string" and Skin.num(size) and type(flags) == "string" and flags:find("OUTLINE") and fs.SetFont then
    Skin.call(fs.SetFont, fs, path, size, "")
  end
end

--- A list row (a Button carrying its own background texture: the Friends list's entries): on the page its background
--- goes and its text is inked like the window's. In game 2026-11-05 the friends rows stayed Blizzard's navy bars.
Part.ROW_BG = { "background", "Background", "BG", "Bg", "bg" }
local function strings(b)
  local out = {}
  for _, r in ipairs(Skin.all(b.GetRegions, b)) do
    if type(r) == "table" and Skin.call(r.GetObjectType, r) == "FontString" and not r.hhOurs then out[#out + 1] = r end
  end
  return out
end
--- A Button that is a list entry rather than a plain button: two or more lines of text (a name and a zone) and, outside
--- a scroll list, wider than tall. A plain button (one label on its own art), a tab or an item slot is not. In game
--- 2026-11-05 Forever's friends rows were never inked ("Dane Bolash" stayed Blizzard's light blue on the page).
function Part.IsRow(b, inList)
  if #strings(b) < 2 then return false end
  if inList then return true end
  local w, h = Skin.num(Skin.call(b.GetWidth, b)), Skin.num(Skin.call(b.GetHeight, b))
  return w ~= nil and h ~= nil and h > 0 and w >= 2.5 * h
end
function Part.Row(b, inList)
  local found = false
  for _, k in ipairs(Part.ROW_BG) do
    local t = rawget(b, k)
    if type(t) == "table" and Skin.call(t.GetObjectType, t) == "Texture" and not t.hhOurs then Skin.Kill(t) found = true end
  end
  if not found and not Part.IsRow(b, inList) then return 0 end
  local n = 0
  for _, r in ipairs(strings(b)) do if Part.Ink(r) then n = n + 1 end end
  return n
end

--- Lists that fill as you scroll (Blizzard's ScrollBox: friends, who, guild roster, mail ...) hand out recycled rows
--- and repaint them on every update. A post-hook on each list's Update inks its rows every time (light page only);
--- single-line entries (a "Favorites 1/1" header on its own dark bar) are left - they read on their art. The older
--- friends list: a post-hook on FriendsFrame_UpdateFriendButton does the same per row.
Part.lists = setmetatable({}, { __mode = "k" })
Part.listRows = 0
local function inkRow(row)
  if type(row) ~= "table" or row.hhOurs then return 0 end
  Part.listRows = Part.listRows + 1
  return Part.Row(row, true)
end
local function inkList(box)
  if Skin.cfg().enabled == false or Skin.cfg().panels.enabled == false or not Part.Paper() then return end
  pcall(box.ForEachFrame, box, inkRow)
end
function Part.Lists(f, depth, found)
  depth, found = depth or 0, found or {}
  if type(f) ~= "table" or depth > 6 or f.hhOurs then return found end
  -- a ScrollBox: its mixin's methods are copied onto the frame itself (rawget: a plain frame has neither)
  if type(rawget(f, "ForEachFrame")) == "function" and type(rawget(f, "Update")) == "function" then
    found[#found + 1] = f
    if not Part.lists[f] and type(hooksecurefunc) == "function" then
      Part.lists[f] = true
      pcall(hooksecurefunc, f, "Update", inkList)
    end
    inkList(f)
    return found
  end
  for _, c in ipairs(Skin.all(f.GetChildren, f)) do Part.Lists(c, depth + 1, found) end
  return found
end
function Part.HookFriendRows()
  if Part.friendRowsHooked or type(hooksecurefunc) ~= "function" then return Part.friendRowsHooked or false end
  if type(rawget(_G, "FriendsFrame_UpdateFriendButton")) ~= "function" then return false end
  Part.friendRowsHooked = true
  pcall(hooksecurefunc, "FriendsFrame_UpdateFriendButton", function(button)
    if Skin.cfg().enabled == false or Skin.cfg().panels.enabled == false or not Part.Paper() then return end
    inkRow(button)
  end)
  return true
end

--- What the list inking found in a window, for /hh skindiag (diag.skin.lists): scroll lists, rows, codes inked.
function Part.ListReport(name, boxes)
  local g = HH.db and HH.db.global
  if not g then return end
  g.diag = g.diag or {}
  g.diag.skin = g.diag.skin or {}
  g.diag.skin.lists = g.diag.skin.lists or {}
  g.diag.skin.lists[name] = { boxes = #boxes, rows = Part.listRows, codes = Part.codesInked,
    friendRowsHook = Part.friendRowsHooked and true or false, at = date and date("%H:%M:%S") or "" }
end

--- Every text in a window inked (depth 7). A Button's label is left: its art is Blizzard's and the label reads on it
-- (tabs are inked by Part.Tabs). Budgeted at `budget.n` strings a pass; a long list is inked as it shows.
function Part.InkAll(frame, depth, budget)
  depth = depth or 0
  budget = budget or { n = 500 }
  if type(frame) ~= "table" or depth > 7 or budget.n <= 0 or frame.hhOurs then return 0 end
  local kind = Skin.call(frame.GetObjectType, frame) or "Frame"
  if depth > 0 and (kind == "Button" or kind == "CheckButton") then return Part.Row(frame) end
  local n = 0
  for _, r in ipairs(Skin.all(frame.GetRegions, frame)) do
    if type(r) == "table" and Skin.call(r.GetObjectType, r) == "FontString" and not r.hhOurs then
      budget.n = budget.n - 1
      if Part.Ink(r) then n = n + 1 end
      if budget.n <= 0 then return n end
    end
  end
  for _, c in ipairs(Skin.all(frame.GetChildren, frame)) do n = n + Part.InkAll(c, depth + 1, budget) end
  return n
end

--- A window on the page: every decorative texture inside it cleared (not in buttons, bars, edit boxes, scroll bars,
--- icons or selection marks), then on the light page its text inked. Lists that build late are caught by the
--- timed passes in Part.Style.
function Part.Inner(f, name)
  local n = 0
  if not Part.BOOK[name or ""] then n = Part.DeepKill(f) end
  if Part.Paper() then
    Part.InkAll(f)
    Part.HookFriendRows()
    local boxes = Part.Lists(f)
    pcall(Part.ListReport, name or "?", boxes)
  end
  return n
end

--- A tab's own label inked (regions only), on the light page.
function Part.InkLabel(tab)
  if not Part.Paper() then return 0 end
  local n = 0
  for _, r in ipairs(Skin.all(tab.GetRegions, tab)) do
    if type(r) == "table" and Skin.call(r.GetObjectType, r) == "FontString" and not r.hhOurs and Part.Ink(r) then n = n + 1 end
  end
  return n
end

-- Parchment windows: their text is BLACK on parchment art that sits a layer or two below the window itself.
-- Treatment (Sean 2026-09-23: "I do like the darker if we can recolour it properly"): recolour Blizzard's shared
-- quest / book / mail font objects once (cream body, amber titles), then strip texture regions through the child
-- frames too - but never inside Buttons, Sliders (scroll bars), EditBoxes or CheckButtons, and never an icon.
Part.PARCHMENT = { GossipFrame = true, QuestFrame = true, QuestLogFrame = true, QuestLogDetailFrame = true, ItemTextFrame = true,
  OpenMailFrame = true, QuestLogPopupDetailFrame = true }
Part.BODY_FONTS = { "QuestFont", "QuestFontNormalSmall", "QuestFontLeft", "QuestFontHighlight", "ItemTextFontNormal", "MailTextFontNormal",
  "InvoiceTextFontNormal", "InvoiceTextFontSmall", "MailFont_Large", "GossipGreetingText" }
Part.TITLE_FONTS = { "QuestTitleFont", "QuestTitleFontBlack", "QuestFontNormalHuge", "QuestFontNormalLarge", "QuestFont_Huge", "QuestFont_Large", "QuestFont_Enormous" }
local KEEP_TYPES = { Button = true, CheckButton = true, Slider = true, ScrollBar = true, EditBox = true, StatusBar = true, Model = true, PlayerModel = true }

function Part.RecolorFonts()
  if Part.fontsDone then return 0 end
  Part.fontsDone = true
  local n = 0
  local th = Part.Paper() and Part.Theme() or nil                 -- the light page: ink; the dark page / ink panel: cream, amber
  local body, title = th and th.text or Skin.CREAM, th and th.title or { 0.95, 0.65, 0.15 }
  for _, fn in ipairs(Part.BODY_FONTS) do
    local f = rawget(_G, fn)
    if type(f) == "table" and f.SetTextColor then Skin.call(f.SetTextColor, f, body[1], body[2], body[3]) n = n + 1 end
  end
  for _, fn in ipairs(Part.TITLE_FONTS) do
    local f = rawget(_G, fn)
    if type(f) == "table" and f.SetTextColor then Skin.call(f.SetTextColor, f, title[1], title[2], title[3]) n = n + 1 end
  end
  return n
end

local function isIcon(t)
  local n = t.GetName and t:GetName()
  return (type(n) == "string" and (n:find("Icon") or n:find("Portrait"))) or t.hhOurs
end

-- Art that MEANS something is not decoration. In game 2026-10-01: picking a quest reward showed no selection -
-- Blizzard's QuestInfoItemHighlight is a plain Frame holding one texture, and the parchment pass had wiped it
-- (and Skin.Kill's hooks kept its alpha at 0 every time Blizzard showed it). Highlight / selection / check art is
-- recognised by the texture's name, its parent's name, or the file it draws, and left alone.
local FUNCTIONAL = { "Highlight", "Selected", "Selection", "Check", "Glow", "Branch", "Arrow" }
local function isFunctional(t)
  local names = { t.GetName and t:GetName() }
  local parent = t.GetParent and t:GetParent()
  if type(parent) == "table" and parent.GetName then names[#names + 1] = parent:GetName() end
  for _, n in ipairs(names) do
    if type(n) == "string" then for _, w in ipairs(FUNCTIONAL) do if n:find(w, 1, true) then return true end end end
  end
  local tex = t.GetTexture and Skin.call(t.GetTexture, t)
  if tex ~= nil and tostring(tex):lower():find("highlight", 1, true) then return true end
  return false
end

--- One string: dark (black, brown, dark grey - the quest option lines were ~0.35 grey) -> cream, and hooked once so a
-- Blizzard repaint (hover, rebuild) is lifted again. Light text (gold, white) is left alone.
function Part.Lift(fs)
  local cr, cg, cb = Skin.call(fs.GetTextColor, fs)
  if not (Skin.num(cr) and Skin.num(cg) and Skin.num(cb)) then return false end
  local lifted = false
  if (cr + cg + cb) < 1.6 and not fs.hhLifting then
    fs.hhLifting = true
    Skin.call(fs.SetTextColor, fs, Skin.CREAM[1], Skin.CREAM[2], Skin.CREAM[3])
    fs.hhLifting = false
    lifted = true
  end
  if not fs.hhLiftHooked and type(hooksecurefunc) == "function" then
    fs.hhLiftHooked = true
    pcall(hooksecurefunc, fs, "SetTextColor", function(self)
      if self.hhLifting or Skin.cfg().enabled == false or Skin.cfg().panels.enabled == false or Part.Paper() then return end
      Part.Lift(self)
    end)
  end
  return lifted
end

--- Dark text inside a parchment window lifted to cream. In game 2026-09-23 the gossip greeting stayed dark brown
-- after the font objects were recoloured: that text is coloured directly by Blizzard's code, so the strings
-- themselves are walked (light text, e.g. gold option lines, is left alone).
function Part.DeepRecolor(frame, depth)
  depth = depth or 0
  if depth == 0 and Part.Paper() then return Part.InkAll(frame) end   -- the light page: ink, not cream
  if type(frame) ~= "table" or depth > 7 then return 0 end
  local n = 0
  if frame.GetRegions then
    for _, r in ipairs({ frame:GetRegions() }) do
      if r and r.GetObjectType and r:GetObjectType() == "FontString" and r.GetTextColor and not r.hhOurs then
        if Part.Lift(r) then n = n + 1 end
      end
    end
  end
  if frame.GetChildren then
    for _, c in ipairs({ frame:GetChildren() }) do n = n + Part.DeepRecolor(c, depth + 1) end
  end
  return n
end

--- Strip + recolour a parchment window now and a moment later (its text is built after the show / event).
function Part.Parchment(f)
  if type(f) ~= "table" then return end
  Part.DeepKill(f)
  Part.DeepRecolor(f)
  -- gossip / quest option lines are built by a scroll box over the next frames: keep looking for a moment
  if C_Timer and C_Timer.After then
    for _, delay in ipairs({ 0.05, 0.2, 0.5 }) do
      C_Timer.After(delay, function() if f:IsShown() then Part.DeepKill(f) Part.DeepRecolor(f) end end)
    end
  end
end

--- Texture regions of `frame` and its descendants cleared, skipping functional widgets and icons. Depth-limited.
function Part.DeepKill(frame, depth)
  depth = depth or 0
  if type(frame) ~= "table" or depth > 6 then return 0 end
  local kind = frame.GetObjectType and frame:GetObjectType() or "Frame"
  if depth > 0 and (KEEP_TYPES[kind] or frame.hhOurs) then return 0 end
  if depth > 0 and (type(rawget(frame, "Track")) == "table" or type(rawget(frame, "Thumb")) == "table") then return 0 end   -- a scroll bar
  local n = 0
  if frame.GetRegions then
    for _, r in ipairs({ frame:GetRegions() }) do
      if r and r.GetObjectType and r:GetObjectType() == "Texture" and not isIcon(r) and not isFunctional(r) and Skin.Kill(r) then n = n + 1 end
    end
  end
  if frame.GetChildren then
    for _, c in ipairs({ frame:GetChildren() }) do n = n + Part.DeepKill(c, depth + 1) end
  end
  return n
end

-- Pieces of Blizzard's window templates that are pure decoration: hidden whole (not only their textures) so a
-- re-applied border layout (NineSliceUtil on show) or a portrait ring cannot come back. Sean 2026-10-15: Friends and
-- Looking For Group still showed Blizzard's gold border, portrait and red X next to a skinned Character window.
Part.HIDE_CHILDREN = { "NineSlice", "PortraitContainer", "TopTileStreaks", "BorderFrame", "Border" }
-- BG / Header: in game 2026-11-05 the exit popup kept StaticPopup1.BG (UI-DiamondDialogBox-Border over
-- UI-DialogBox-Background-Dark) and the escape menu GameMenuFrame.Header (UI-Frame-DiamondMetal-Header-*); Sean: "remove that
-- inner box". Textures only: the header's title text stays.
Part.STRIP_CHILDREN = { "Bg", "TitleBg", "Inset", "InsetBg", "Background", "TitleContainer", "BG", "Header" }

local function hideWhole(child)
  if type(child) ~= "table" then return end
  Skin.KillRegions(child)
  Skin.call(child.SetAlpha, child, 0)
  if child.Hide and not child.hhHidden then
    child.hhHidden = true
    Skin.call(child.Hide, child)
    if type(hooksecurefunc) == "function" then
      pcall(hooksecurefunc, child, "Show", function(self)
        if Skin.cfg().enabled ~= false and Skin.cfg().panels.enabled ~= false then Skin.call(self.Hide, self) end
      end)
    end
  end
end

--- The art of a window, stripped. Runs on EVERY show: some templates re-apply their border when shown.
function Part.Strip(f, name)
  Skin.KillRegions(f)
  for _, k in ipairs(Part.HIDE_CHILDREN) do hideWhole(rawget(f, k)) end
  for _, k in ipairs(Part.STRIP_CHILDREN) do
    local child = rawget(f, k)
    if type(child) == "table" then
      if child.GetObjectType and child:GetObjectType() == "Texture" then Skin.Kill(child)
      else
        Skin.KillRegions(child)
        hideWhole(rawget(child, "NineSlice"))
        local bg = rawget(child, "Bg")
        if type(bg) == "table" then Skin.Kill(bg) end
      end
    end
  end
  if name ~= "" then   -- an unnamed pane: no global pieces to look up ("" .. "Bg" would be some other global)
    for _, suffix in ipairs({ "Portrait", "PortraitFrame", "TopLeft", "TopRight", "BottomLeft", "BottomRight", "TopBorder", "BottomBorder",
      "LeftBorder", "RightBorder", "Bg", "TitleBg", "Inset", "InsetBg", "BtnCornerLeft", "BtnCornerRight", "ButtonBottomBorder" }) do
      local g = rawget(_G, name .. suffix)
      if type(g) == "table" then
        if g.GetObjectType and g:GetObjectType() == "Texture" then Skin.Kill(g) else Skin.KillRegions(g) hideWhole(rawget(g, "NineSlice")) end
      end
    end
    Part.Tabs(f, name)
  end
  Part.SubWindows(f, name)
  Part.SideTabs(f, name)
end

-- ------------------------------------------------------------------------------------------------ framed panes
-- Windows whose visible content is a CHILD window with its own frame art. Sean 2026-10-17, /hh under over the Group
-- Finder: the window under the mouse is LFGListingFrame (a child of the styled LFGParentFrame) with its own metal
-- NineSlice, Bg, TopTileStreaks, Inset (groupfinder-background, common-insideframe), role background and divider, and
-- three side tabs (ListingTab / BrowsingTab / WhoListingTab, common-sidetab). The other panes' names are not known
-- on this client, so any direct child carrying a NineSlice or TopTileStreaks counts as one; each is stripped again
-- when its tab shows it (its own OnShow - the parent's does not fire on a tab switch).
Part.FRAMED = { LFGParentFrame = true, CommunitiesFrame = true }
Part.tinted = setmetatable({}, { __mode = "k" })

--- A Blizzard texture recoloured to ours (desaturated + tint): its shape and its show / hide stay Blizzard's, so a
-- selection mark or a divider keeps working, only the gold goes.
function Part.Tint(t, c, a)
  if type(t) ~= "table" or t.hhOurs or not t.SetVertexColor then return false end
  if t.SetDesaturated then Skin.call(t.SetDesaturated, t, true) end
  Skin.call(t.SetVertexColor, t, c[1], c[2], c[3], a or 1)
  Part.tinted[t] = true
  return true
end

--- One pane: stripped like a window; its divider kept as a line in our colour.
function Part.StripPane(c, cn)
  Part.Strip(c, cn)
  local div = rawget(c, "DividerFrame")
  if type(div) == "table" then
    for _, r in ipairs(Skin.all(div.GetRegions, div)) do
      if type(r) == "table" and Skin.call(r.GetObjectType, r) == "Texture" then Part.Tint(r, Skin.LINE) end
    end
  end
end

function Part.SubWindows(f, name)
  if not Part.FRAMED[name] then return 0 end
  local found = {}
  for _, c in ipairs(Skin.all(f.GetChildren, f)) do
    if type(c) == "table" and not c.hhOurs and (type(rawget(c, "NineSlice")) == "table" or type(rawget(c, "TopTileStreaks")) == "table") then
      local cn = Skin.call(c.GetName, c)
      cn = type(cn) == "string" and cn or ""
      Part.StripPane(c, cn)
      found[#found + 1] = cn ~= "" and cn or "?"
      if not Part.subHooked[c] and c.HookScript then
        Part.subHooked[c] = true
        c:HookScript("OnShow", function(self)
          if Skin.cfg().enabled == false or Skin.cfg().panels.enabled == false or skipped(name) then return end
          local ok, err = pcall(Part.StripPane, self, cn)
          if not ok then HH:LogError("skin window " .. name .. " pane " .. cn .. ": " .. tostring(err)) end
          if C_Timer and C_Timer.After then C_Timer.After(0.3, function() pcall(Part.Report, f, name) end) end
        end)
      end
    end
  end
  Part.subs[name] = table.concat(found, ",")
  return #found
end

--- The cell behind a tab: a rounded slab in the page's tag colour (parchment), else the ink panel.
function Part.Cell(tab, pad, alpha, name)
  local th = Part.ThemeFor(name)
  if th then
    local s = HH.Parchment.Slab(tab, "BACKGROUND")
    for _, part in ipairs(s.parts) do part.hhOurs = true end
    s:Fit(tab, -(pad or 0), 10)
    s:Color(th.tag)
    return s
  end
  return Skin.Panel(tab, tab, pad, alpha)
end

--- Side tabs down a window's edge: Blizzard's tab plate off, an ink cell behind, the selected and hover marks tinted
-- cyan (still shown / hidden by Blizzard), the icon kept.
function Part.SideTabs(f, name)
  if not Part.FRAMED[name] then return 0 end
  local n = 0
  for k, tab in pairs(f) do
    if type(k) == "string" and k:find("Tab$") and type(tab) == "table" and type(rawget(tab, "Background")) == "table" then
      Skin.Kill(rawget(tab, "Background"))
      if not Part.sideTabPanels[tab] then Part.sideTabPanels[tab] = Part.Cell(tab, -2, 0.9, name) end
      local pick = Part.ThemeFor(name) and Part.ThemeFor(name).pick or Skin.CYAN
      Part.Tint(rawget(tab, "SelectedTexture"), pick)
      Part.Tint(rawget(tab, "HighlightTexture"), pick, 0.5)
      n = n + 1
    end
  end
  return n
end

--- The tab strip under a window (FriendsFrameTab1.., LFGParentFrameTab1..): Blizzard's tab art off, a flat ink cell
-- behind each tab; the text stays Blizzard's (it carries the selected / disabled colours).
function Part.Tabs(f, name)
  for i = 1, 8 do
    local tab = rawget(_G, name .. "Tab" .. i)
    if type(tab) ~= "table" then break end
    Skin.KillRegions(tab)
    for _, k in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive", "LeftHighlight", "MiddleHighlight", "RightHighlight" }) do
      local t = rawget(tab, k)
      if type(t) == "table" then Skin.Kill(t) end
    end
    if not tab.hhTabPanel then tab.hhTabPanel = Part.Cell(tab, -2, 0.85, name) end
    if Part.ThemeFor(name) then Part.InkLabel(tab) end
  end
end

-- Named Blizzard pieces a window keeps after the strip (its own /hh skindiag leftovers): cleared by key path. Sean
-- 2026-10-17, the Friends window (SocialUIFrame) still showed the Battle.net bar's two backgrounds
-- (friends-frame-infoBG, 632259) and the friends list's two dividers (perks-divider-short). Its scroll bar track stays
-- (a control, not decoration).
Part.PIECES = {
  SocialUIFrame = { "BattleNetBar.Background", "BattleNetBar.ControlsContainer.BattleNetBackground", "FriendsList.TopDivider", "FriendsList.BottomDivider" },
}

function Part.KillPieces(f, name)
  local list = Part.PIECES[name]
  if not list then return 0 end
  local n = 0
  for _, path in ipairs(list) do
    local t = f
    for key in path:gmatch("[^%.]+") do t = type(t) == "table" and rawget(t, key) or nil end
    if type(t) == "table" and Skin.Kill(t) then n = n + 1 end
  end
  return n
end

function Part.StyleOnce(f, name)
  local d = Skin.cfg().panels
  local th = Part.ThemeFor(name)
  local tabs = type(rawget(_G, name .. "Tab1")) == "table"                     -- a tab strip hangs under the window: paper under it too
  local title = rawget(f, "TitleText") or (type(rawget(f, "TitleContainer")) == "table" and rawget(f.TitleContainer, "TitleText")) or rawget(_G, name .. "TitleText")
  -- the page is solid paper (in game 2026-11-05 at 0.9 the damage meter showed through it); the opacity slider is the ink panel's
  f.hhPanel = th and Part.Page(f, 1, tabs and Part.TAB_ROOM or 0, type(title) == "table") or Skin.Panel(f, f, 0, d and d.alpha or 0.9)
  if type(title) == "table" then
    if th then HH.Parchment.Font(title, d and d.titleSize or 13) else Skin.SetFont(title, d and d.titleSize or 13) end
    local tc = th and th.title or Skin.CREAM
    if title.SetTextColor then Skin.call(title.SetTextColor, title, tc[1], tc[2], tc[3]) end
  end
  local close = rawget(f, "CloseButton") or rawget(_G, name .. "CloseButton")
  if type(close) == "table" and close.CreateFontString and not close.hhX then
    Skin.KillRegions(close)
    for _, k in ipairs({ "Border", "NormalTexture", "PushedTexture", "HighlightTexture", "DisabledTexture" }) do
      local t = rawget(close, k)
      if type(t) == "table" then Skin.Kill(t) end
    end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
      if type(close[get]) == "function" then Skin.Kill(Skin.call(close[get], close)) end
    end
    close.hhX = close:CreateFontString(nil, "OVERLAY", "HogTronFontSmall")
    close.hhX:SetPoint("CENTER", close, "CENTER", 0, 0)
    close.hhX:SetText("x")
    close.hhX:SetTextColor(Skin.CREAM[1], Skin.CREAM[2], Skin.CREAM[3])
    Skin.SetFont(close.hhX, 14)
  end
  if th and type(close) == "table" and close.hhX and not close.hhCap then   -- the page's key cap under the x
    close.hhCap = HH.Parchment.Slab(close, "ARTWORK")
    for _, part in ipairs(close.hhCap.parts) do part.hhOurs = true end
    close.hhCap:Fit(close, 5, 8)
    close.hhCap:Color(th.key)
    close.hhX:SetTextColor(th.keyText[1], th.keyText[2], th.keyText[3])
    HH.Parchment.Font(close.hhX, 13)
  end
  if Part.PARCHMENT[name] then
    Part.RecolorFonts()
    -- scroll panels rebuild their parchment and text on show; do it again then
    if not f.hhParchHooked and f.HookScript then
      f.hhParchHooked = true
      f:HookScript("OnShow", function(self) if Skin.cfg().enabled ~= false and Skin.cfg().panels.enabled ~= false and not skipped(self:GetName() or "") then Part.Parchment(self) end end)
    end
  end
  Part.styled[#Part.styled + 1] = name
end

-- ------------------------------------------------------------------------------------------------ what is left
--- Visible Blizzard textures still inside a window (depth 5, at most `max`): "path file WxH". Buttons, bars and icons
-- are skipped (their art is the point). This is what /hh skindiag reports, so a window that still looks like
-- Blizzard's says exactly which piece did it, without guessing at this client's templates.
function Part.Leftovers(f, max)
  max = max or 25
  local out = {}
  local function key(parent, child)
    if type(parent) ~= "table" then return "?" end
    for k, v in pairs(parent) do if v == child and type(k) == "string" then return k end end
    return "?"
  end
  -- unnamed pieces (parentKey only): "Icon", "SelectedTexture", "HighlightTexture" are what they say
  local function keyFunctional(k)
    if k:find("Icon", 1, true) then return true end
    for _, w in ipairs(FUNCTIONAL) do if k:find(w, 1, true) then return true end end
    return false
  end
  local function walk(fr, path, depth)
    if #out >= max or depth > 5 or type(fr) ~= "table" or fr.hhOurs then return end
    if not Skin.call(fr.IsShown, fr) then return end
    local kind = Skin.call(fr.GetObjectType, fr) or "Frame"
    if depth > 0 and KEEP_TYPES[kind] then return end
    for _, r in ipairs(Skin.all(fr.GetRegions, fr)) do
      if #out >= max then return end
      if type(r) == "table" and Skin.call(r.GetObjectType, r) == "Texture" and not r.hhOurs and not isIcon(r) and not isFunctional(r)
        and not Part.tinted[r] and not keyFunctional(key(fr, r))
        and Skin.call(r.IsShown, r) and (Skin.num(Skin.call(r.GetAlpha, r)) or 1) > 0 then
        local file = Skin.call(r.GetAtlas, r) or Skin.call(r.GetTexture, r)
        if file ~= nil then
          local rn = Skin.call(r.GetName, r)
          if type(rn) ~= "string" or rawget(_G, rn) ~= r then rn = path .. "." .. key(fr, r) end   -- a name you can look up, else the key path
          local w, h = Skin.num(Skin.call(r.GetWidth, r)) or 0, Skin.num(Skin.call(r.GetHeight, r)) or 0
          out[#out + 1] = ("%s %s %dx%d"):format(tostring(rn), tostring(file), math.floor(w), math.floor(h))
        end
      end
    end
    for _, c in ipairs(Skin.all(fr.GetChildren, fr)) do
      if type(c) == "table" then
        local cn = Skin.call(c.GetName, c)
        if type(cn) ~= "string" or rawget(_G, cn) ~= c then cn = path .. "." .. key(fr, c) end
        walk(c, cn, depth + 1)
      end
    end
  end
  walk(f, Skin.call(f.GetName, f) or "?", 0)
  return out
end

function Part.Report(f, name, err)
  local g = HH.db and HH.db.global
  if not g then return end
  g.diag = g.diag or {}
  g.diag.skin = g.diag.skin or {}
  g.diag.skin.windows = g.diag.skin.windows or {}
  -- the style is recorded FIRST: walking what is left can throw on a window with forbidden / secret pieces, and that
  -- used to lose the whole record silently (Sean 2026-10-17: the Friends window looked stock and left no trace)
  local rec = { at = date and date("%Y-%m-%d %H:%M:%S") or "", styled = f.hhPanel ~= nil, error = err,
    shown = Skin.call(f.IsShown, f) and true or false, strata = Skin.call(f.GetFrameStrata, f), level = Skin.call(f.GetFrameLevel, f),
    panelLevel = f.hhPanel and f.hhPanel.GetFrameLevel and Skin.call(f.hhPanel.GetFrameLevel, f.hhPanel) or nil,
    panes = Part.subs[name] }
  g.diag.skin.windows[name] = rec
  if err then return end
  local ok, left = pcall(Part.Leftovers, f)
  if ok then rec.leftovers, rec.left = #left, table.concat(left, " | ")
  else rec.leftoversError = tostring(left):sub(1, 300) end
end

--- Style a window: the once-only parts the first time, the art strip every time. Errors are CAUGHT and logged with
-- the window's name (an OnShow hook error is otherwise silent with script errors off), and what is left is
-- recorded a moment later for /hh skindiag.
function Part.Style(f)
  if type(f) ~= "table" then return false end
  local name = f.GetName and f:GetName() or "?"
  if skipped(name) then return false end
  local first = f.hhPanel == nil
  local ok, err = xpcall(function()
    Part.Strip(f, name)
    Part.KillPieces(f, name)
    if first then Part.StyleOnce(f, name) end
    if Part.PARCHMENT[name] then Part.Parchment(f) end
    if f.hhPanel and f.hhPanel.pageTop then
      Part.Relay(f.hhPanel)
      Part.Inner(f, name)
      if C_Timer and C_Timer.After then
        for _, delay in ipairs({ 0.2, 0.6 }) do C_Timer.After(delay, function() if Skin.call(f.IsShown, f) then Part.Inner(f, name) end end) end
      end
    end
  end, HH.Trace or debugstack)
  if not ok then
    HH:LogError("skin window " .. name .. ": " .. tostring(err))
    Part.Report(f, name, tostring(err):sub(1, 300))
    return false
  end
  if C_Timer and C_Timer.After then C_Timer.After(0.3, function() pcall(Part.Report, f, name) end) else pcall(Part.Report, f, name) end
  return first
end

local function watch(f)
  if type(f) ~= "table" or Part.hooked[f] or not f.HookScript then return end
  Part.hooked[f] = true
  f:HookScript("OnShow", function(self)
    local n = self.GetName and self:GetName() or "?"
    Part.shows[n] = (Part.shows[n] or 0) + 1
    if Skin.cfg().enabled ~= false and Skin.cfg().panels.enabled ~= false then Part.Style(self) end
  end)
  if f.IsShown and f:IsShown() then Part.Style(f) end
end

function Part.Apply()
  local d = Skin.cfg().panels
  if not d or d.enabled == false then return end
  for _, n in ipairs(Part.NAMES) do
    local f = rawget(_G, n)
    if type(f) == "table" then Skin.found[n] = true watch(f) else Skin.missing[n] = true end
  end
  -- load-on-demand windows arrive later: ShowUIPanel is how the client opens them
  if not Part.showHooked and type(hooksecurefunc) == "function" and type(rawget(_G, "ShowUIPanel")) == "function" then
    Part.showHooked = true
    pcall(hooksecurefunc, "ShowUIPanel", function(frame)
      if type(frame) == "table" and frame.GetName and wanted[frame:GetName() or ""] and Skin.cfg().enabled ~= false and Skin.cfg().panels.enabled ~= false then
        watch(frame)
        Part.Style(frame)
      end
    end)
  end
end

Part.CONTENT_EVENTS = { GOSSIP_SHOW = "GossipFrame", QUEST_GREETING = "QuestFrame", QUEST_DETAIL = "QuestFrame", QUEST_PROGRESS = "QuestFrame",
  QUEST_COMPLETE = "QuestFrame", ITEM_TEXT_READY = "ItemTextFrame", MAIL_SHOW = "OpenMailFrame", QUEST_LOG_UPDATE = "QuestLogFrame" }

function Part.OnEvent(e, arg1)
  if e == "PLAYER_ENTERING_WORLD" or (e == "ADDON_LOADED" and type(arg1) == "string" and arg1:find("^Blizzard_")) then Part.Apply() return end
  local target = Part.CONTENT_EVENTS[e]
  if target and Skin.cfg().panels.enabled ~= false and not skipped(target) then
    local f = rawget(_G, target)
    if type(f) == "table" and f.hhPanel then Part.Parchment(f) end
  end
end

Skin.Register(Part)

-- ------------------------------------------------------------------------------------------------ /hh open
-- Opens one of Blizzard's windows by a short name, for checking the skin window by window (Sean 2026-11-05: "open up
-- every single window and look at this and adjust"). Each opener is the client's own toggle; a name this client
-- lacks says so. A check tool: a window opened from addon code can carry taint until the next /reload.
local function G(n) return rawget(_G, n) end
local function try(...)
  for _, f in ipairs({ ... }) do
    if type(f) == "function" and pcall(f) then return true end
  end
  return false
end
Part.OPEN = {
  character = function() return try(function() G("ToggleCharacter")("PaperDollFrame") end) end,
  reputation = function() return try(function() G("ToggleCharacter")("ReputationFrame") end) end,
  skills = function() return try(function() G("ToggleCharacter")("SkillFrame") end) end,
  honor = function() return try(function() G("ToggleCharacter")("HonorFrame") end) end,
  spellbook = function() return try(function() G("PlayerSpellsUtil").ToggleSpellBookFrame() end, function() G("ToggleSpellBook")("spell") end) end,
  talents = function() return try(function() G("PlayerSpellsUtil").ToggleClassTalentOrSpecFrame() end, function() G("ToggleTalentFrame")() end) end,
  questlog = function() return try(function() G("ToggleQuestLog")() end) end,
  social = function() return try(function() G("ToggleFriendsFrame")() end) end,
  guild = function() return try(function() G("ToggleGuildFrame")() end, function() G("ToggleCommunitiesFrame")() end) end,
  map = function() return try(function() G("ToggleWorldMap")() end) end,
  bags = function() return try(function() G("ToggleAllBags")() end) end,
  lfg = function() return try(function() G("ToggleLFGParentFrame")() end, function() G("PVEFrame_ToggleFrame")() end) end,
  pvp = function() return try(function() G("TogglePVPFrame")() end) end,
  raid = function() return try(function() G("ToggleRaidFrame")() end) end,
  options = function() return try(function() G("SettingsPanel"):Open() end, function() G("ShowUIPanel")(G("SettingsPanel")) end) end,
  macros = function() return try(function() G("ShowMacroFrame")() end) end,
  help = function() return try(function() G("ToggleHelpFrame")() end) end,
  achievements = function() return try(function() G("ToggleAchievementFrame")() end) end,
  collections = function() return try(function() G("ToggleCollectionsJournal")() end) end,
  journal = function() return try(function() G("ToggleEncounterJournal")() end) end,
  calendar = function() return try(function() G("ToggleCalendar")() end) end,
  time = function() return try(function() G("TimeManager_Toggle")() end) end,
  dressup = function() return try(function() G("ShowUIPanel")(G("DressUpFrame")) end) end,
  chatconfig = function() return try(function() G("ShowUIPanel")(G("ChatConfigFrame")) end) end,
  close = function() return try(function() G("CloseAllWindows")() end) end,
}

function Part.Open(what)
  local key = type(what) == "string" and what:lower():gsub("%s", "") or ""
  local f = Part.OPEN[key]
  if not f then
    local names = {}
    for k in pairs(Part.OPEN) do names[#names + 1] = k end
    table.sort(names)
    HH:Print("open: one of " .. table.concat(names, ", "))
    return nil
  end
  local ok = f()
  if not ok then HH:Print("open " .. key .. ": this client has no such window (or it is locked: level, combat)") end
  return ok
end

HH:RegisterSlash("open", function(rest) Part.Open(rest) end, "open one of Blizzard's windows by name, to check the skin (character, spellbook, questlog, social, guild, map, bags, ...)")
