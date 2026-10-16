-- Blizzard's windows (character sheet, spellbook, quest log, escape menu, vendor, mail, trade, bank, ...) in the
-- HogTron UI panel: their art, portrait and border switched off, an ink panel with a 1 px outline behind them, the title
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

-- Pieces of Blizzard's window templates that are pure decoration: hidden whole (not only their textures) so a
-- re-applied border layout (NineSliceUtil on show) or a portrait ring cannot come back. Sean 2026-10-15: Friends and
-- Looking For Group still showed Blizzard's gold border, portrait and red X next to a skinned Character window.
Part.HIDE_CHILDREN = { "NineSlice", "PortraitContainer", "TopTileStreaks", "BorderFrame", "Border" }
Part.STRIP_CHILDREN = { "Bg", "TitleBg", "Inset", "InsetBg", "Background", "TitleContainer" }

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
  for _, suffix in ipairs({ "Portrait", "PortraitFrame", "TopLeft", "TopRight", "BottomLeft", "BottomRight", "TopBorder", "BottomBorder",
    "LeftBorder", "RightBorder", "Bg", "TitleBg", "Inset", "InsetBg", "BtnCornerLeft", "BtnCornerRight", "ButtonBottomBorder" }) do
    local g = rawget(_G, name .. suffix)
    if type(g) == "table" then
      if g.GetObjectType and g:GetObjectType() == "Texture" then Skin.Kill(g) else Skin.KillRegions(g) hideWhole(rawget(g, "NineSlice")) end
    end
  end
  Part.Tabs(f, name)
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
    if not tab.hhTabPanel then tab.hhTabPanel = Skin.Panel(tab, tab, -2, 0.85) end
  end
end

function Part.StyleOnce(f, name)
  local d = Skin.cfg().panels
  f.hhPanel = Skin.Panel(f, f, 0, d and d.alpha or 0.9)
  local title = rawget(f, "TitleText") or (type(rawget(f, "TitleContainer")) == "table" and rawget(f.TitleContainer, "TitleText")) or rawget(_G, name .. "TitleText")
  if type(title) == "table" then
    Skin.SetFont(title, d and d.titleSize or 13)
    if title.SetTextColor then Skin.call(title.SetTextColor, title, Skin.CREAM[1], Skin.CREAM[2], Skin.CREAM[3]) end
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
  local function walk(fr, path, depth)
    if #out >= max or depth > 5 or type(fr) ~= "table" or fr.hhOurs then return end
    if not Skin.call(fr.IsShown, fr) then return end
    local kind = Skin.call(fr.GetObjectType, fr) or "Frame"
    if depth > 0 and KEEP_TYPES[kind] then return end
    for _, r in ipairs(Skin.all(fr.GetRegions, fr)) do
      if #out >= max then return end
      if type(r) == "table" and Skin.call(r.GetObjectType, r) == "Texture" and not r.hhOurs and not isIcon(r) and not isFunctional(r)
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
  local left = err and {} or Part.Leftovers(f)
  g.diag.skin.windows[name] = { at = date and date("%Y-%m-%d %H:%M:%S") or "", styled = f.hhPanel ~= nil, error = err,
    leftovers = #left, left = table.concat(left, " | ") }
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
    if first then Part.StyleOnce(f, name) end
    if Part.PARCHMENT[name] then Part.Parchment(f) end
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
