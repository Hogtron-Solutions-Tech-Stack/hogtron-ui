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

function Part.OnEvent(e, arg1)
  if e == "PLAYER_ENTERING_WORLD" or (e == "ADDON_LOADED" and type(arg1) == "string" and arg1:find("^Blizzard_")) then Part.Apply() end
end

Skin.Register(Part)
