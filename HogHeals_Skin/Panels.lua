-- Blizzard's windows (character sheet, spellbook, quest log, escape menu, vendor, mail, trade, bank, ...) in the
-- HogUI panel: their art, portrait and border switched off, an ink panel with a 1 px outline behind them, the title
-- in our font, a flat close button. Styled when first shown (many are load-on-demand), caught through OnShow, the
-- ShowUIPanel hook and Blizzard_* addon loads. Each window can be excluded in the options.
local HHS = HogHealsSkin
local Skin = HHS.Skin
local HH = HogHeals

local Part = { name = "panels", styled = {}, hooked = {} }
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
}
local wanted = {}
for _, n in ipairs(Part.NAMES) do wanted[n] = true end

local function skipped(name)
  local d = Skin.cfg().panels
  return d and type(d.skip) == "table" and d.skip[name] == true
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
  for _, fn in ipairs(Part.BODY_FONTS) do
    local f = rawget(_G, fn)
    if type(f) == "table" and f.SetTextColor then Skin.call(f.SetTextColor, f, Skin.CREAM[1], Skin.CREAM[2], Skin.CREAM[3]) n = n + 1 end
  end
  for _, fn in ipairs(Part.TITLE_FONTS) do
    local f = rawget(_G, fn)
    if type(f) == "table" and f.SetTextColor then Skin.call(f.SetTextColor, f, 0.95, 0.65, 0.15) n = n + 1 end
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
local FUNCTIONAL = { "Highlight", "Selected", "Selection", "Check", "Glow" }
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
      if self.hhLifting or Skin.cfg().enabled == false or Skin.cfg().panels.enabled == false then return end
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
  if depth > 0 and KEEP_TYPES[kind] then return 0 end
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

function Part.Style(f)
  if type(f) ~= "table" or f.hhPanel then return false end
  local name = f.GetName and f:GetName() or "?"
  if skipped(name) then return false end
  local d = Skin.cfg().panels
  Skin.KillRegions(f)
  for _, k in ipairs({ "NineSlice", "Bg", "TitleBg", "Inset", "InsetBg", "PortraitContainer", "Background", "BorderFrame", "TopTileStreaks", "Border" }) do
    local child = rawget(f, k)
    if type(child) == "table" then
      if child.GetObjectType and child:GetObjectType() == "Texture" then Skin.Kill(child)
      else
        Skin.KillRegions(child)
        if child.SetAlpha and k == "NineSlice" then Skin.call(child.SetAlpha, child, 0) end
      end
    end
  end
  for _, suffix in ipairs({ "Portrait", "PortraitFrame", "TopLeft", "TopRight", "BottomLeft", "BottomRight", "TopBorder", "BottomBorder", "LeftBorder", "RightBorder", "Bg", "TitleBg" }) do
    Skin.Kill(rawget(_G, name .. suffix))
  end
  f.hhPanel = Skin.Panel(f, f, 0, d and d.alpha or 0.9)
  local title = rawget(f, "TitleText") or (type(rawget(f, "TitleContainer")) == "table" and rawget(f.TitleContainer, "TitleText")) or rawget(_G, name .. "TitleText")
  if type(title) == "table" then
    Skin.SetFont(title, d and d.titleSize or 13)
    if title.SetTextColor then Skin.call(title.SetTextColor, title, Skin.CREAM[1], Skin.CREAM[2], Skin.CREAM[3]) end
  end
  local close = rawget(f, "CloseButton") or rawget(_G, name .. "CloseButton")
  if type(close) == "table" and close.CreateFontString and not close.hhX then
    Skin.KillRegions(close)
    close.hhX = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    close.hhX:SetPoint("CENTER", close, "CENTER", 0, 0)
    close.hhX:SetText("x")
    close.hhX:SetTextColor(Skin.CREAM[1], Skin.CREAM[2], Skin.CREAM[3])
    Skin.SetFont(close.hhX, 14)
  end
  if Part.PARCHMENT[name] then
    Part.RecolorFonts()
    Part.Parchment(f)
    -- scroll panels rebuild their parchment and text on show; do it again then
    if not f.hhParchHooked and f.HookScript then
      f.hhParchHooked = true
      f:HookScript("OnShow", function(self) if Skin.cfg().enabled ~= false and Skin.cfg().panels.enabled ~= false and not skipped(self:GetName() or "") then Part.Parchment(self) end end)
    end
  end
  Part.styled[#Part.styled + 1] = name
  return true
end

local function watch(f)
  if type(f) ~= "table" or Part.hooked[f] or not f.HookScript then return end
  Part.hooked[f] = true
  f:HookScript("OnShow", function(self)
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
