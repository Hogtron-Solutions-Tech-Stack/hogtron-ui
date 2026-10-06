-- HogTron UI Skin: Blizzard's own action bars, bag bar, micro menu, bags and tooltips in the HogTron UI look.
--
-- Restyle, never replace: every Blizzard frame keeps doing what it does (secure action buttons stay Blizzard's,
-- bags stay Blizzard's); we clear their art and put flat HogTron UI pieces on top. Every Blizzard name is looked up
-- through a list and never assumed - a missing one is skipped and reported by /hh skindiag, because the names
-- differ between the client generations this addon runs on (Classic-era globals vs. modern mixins).
-- This file: shared helpers + the module. The pieces live in ActionBars.lua, Bags.lua, Micro.lua, Tooltip.lua,
-- InfoBar.lua and register themselves in Skin.parts.
HogHealsSkin = HogHealsSkin or {}
local HHS = HogHealsSkin
local HH = HogHeals

local Skin = { parts = {}, found = {}, missing = {} }
HHS.Skin = Skin

Skin.FLAT = "Interface\\Buttons\\WHITE8X8"
Skin.CREAM = { 0.96, 0.92, 0.86 }
Skin.CYAN = { 0.13, 0.83, 0.88 }
Skin.INK = { 0.07, 0.07, 0.09 }
Skin.GREY = { 0.55, 0.55, 0.60 }
Skin.LINE = { 0.20, 0.20, 0.25 }

function Skin.cfg() return HH.db.profile.skin end

function Skin.call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(f, ...)
  if ok then return a, b, c, d end
end
local call = Skin.call

function Skin.isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
function Skin.num(v) if type(v) == "number" and not Skin.isSecret(v) then return v end end

--- Global by name, recorded as found / missing for the diag.
function Skin.G(name)
  local v = rawget(_G, name)
  if v ~= nil then Skin.found[name] = true else Skin.missing[name] = true end
  return v
end

--- Nested Blizzard field ("MainMenuBar.EndCaps.LeftEndCap"): a table walk that never errors.
function Skin.Path(path)
  local cur = _G
  for piece in path:gmatch("[^%.]+") do
    if type(cur) ~= "table" then Skin.missing[path] = true return nil end
    cur = rawget(cur, piece)
    if cur == nil then Skin.missing[path] = true return nil end
  end
  Skin.found[path] = true
  return cur
end

function Skin.font()
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  local p = LSM and call(LSM.Fetch, LSM, "font", Skin.cfg().font or "Friz Quadrata TT")
  return p or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

function Skin.SetFont(fs, size, outline)
  if type(fs) == "table" and fs.SetFont then call(fs.SetFont, fs, Skin.font(), size, outline or "OUTLINE") end
end

--- A texture: cleared and kept clear (SetTexture(nil) + alpha 0). Blizzard re-applies art through SetTexture /
-- SetAtlas on some pieces; hook both so ours wins every time. Never touches our own pieces (hhOurs).
function Skin.Kill(t)
  if type(t) ~= "table" or t.hhOurs then return false end
  if t.GetObjectType and t:GetObjectType() ~= "Texture" then return false end
  call(t.SetTexture, t, nil)
  call(t.SetAlpha, t, 0)
  if not t.hhKilled and type(hooksecurefunc) == "function" then
    t.hhKilled = true
    for _, m in ipairs({ "SetTexture", "SetAtlas", "SetAlpha", "Show" }) do
      if type(t[m]) == "function" then
        pcall(hooksecurefunc, t, m, function(self)
          if self.hhRekilling or Skin.cfg().enabled == false then return end
          self.hhRekilling = true
          call(self.SetAlpha, self, 0)
          self.hhRekilling = false
        end)
      end
    end
  end
  return true
end

--- Every texture region of a frame (not its children), cleared.
function Skin.KillRegions(frame)
  if type(frame) ~= "table" or not frame.GetRegions then return 0 end
  local n = 0
  for _, r in ipairs({ frame:GetRegions() }) do
    if Skin.Kill(r) then n = n + 1 end
  end
  return n
end

local function solid(parent, layer, c, a, sub)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  t.hhOurs = true
  return t
end
Skin.Solid = solid

--- Ink panel + 1 px outline behind `anchor`, padded. Returns { bg, edges }.
function Skin.Panel(parent, anchor, pad, alpha)
  pad = pad or 0
  local p = CreateFrame("Frame", nil, parent)
  p:SetPoint("TOPLEFT", anchor, "TOPLEFT", -pad, pad)
  p:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", pad, -pad)
  p:SetFrameLevel(math.max(0, ((anchor.GetFrameLevel and anchor:GetFrameLevel()) or 1) - 1))
  p.bg = solid(p, "BACKGROUND", Skin.INK, alpha or (Skin.cfg().backgroundAlpha or 0.75))
  p.bg:SetAllPoints(p)
  p.edges = Skin.Outline(p, p)
  return p
end

function Skin.Outline(parent, anchor, color, thick)
  color, thick = color or Skin.LINE, thick or 1
  local edges = {}
  local spec = { { "TOPLEFT", "TOPRIGHT", nil, thick }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, thick }, { "TOPLEFT", "BOTTOMLEFT", thick, nil }, { "TOPRIGHT", "BOTTOMRIGHT", thick, nil } }
  for i, sp in ipairs(spec) do
    local e = solid(parent, "BORDER", color)
    e:SetPoint(sp[1], anchor, sp[1], 0, 0)
    e:SetPoint(sp[2], anchor, sp[2], 0, 0)
    if sp[3] then e:SetWidth(sp[3]) end
    if sp[4] then e:SetHeight(sp[4]) end
    edges[i] = e
  end
  return edges
end

function Skin.ColorEdges(edges, c)
  for _, e in ipairs(edges or {}) do e:SetColorTexture(c[1], c[2], c[3], 1) end
end

--- Flat icon button: Blizzard's normal / pushed / border art cleared, icon trimmed, 1 px outline + dark backdrop.
-- Works for action buttons, bag slots and bag item slots alike. Idempotent.
function Skin.IconButton(b, opts)
  if type(b) ~= "table" or b.hhSkinned then return b and b.hh end
  opts = opts or {}
  local hh = {}
  b.hh, b.hhSkinned = hh, true
  local name = b.GetName and b:GetName()
  local nt = b.GetNormalTexture and call(b.GetNormalTexture, b)
  if nt then Skin.Kill(nt) end
  for _, k in ipairs({ "FloatingBG", "Border", "NormalTexture", "SlotArt", "SlotBackground", "Flash", "NewActionTexture", "SpellHighlightTexture", "IconBorder", "IconOverlay" }) do
    local r = rawget(b, k) or (name and rawget(_G, name .. k))
    if type(r) == "table" and not (opts.keep and opts.keep[k]) then Skin.Kill(r) end
  end
  local icon = rawget(b, "icon") or rawget(b, "Icon") or (name and rawget(_G, name .. "Icon")) or (name and rawget(_G, name .. "IconTexture"))
  if type(icon) == "table" and icon.SetTexCoord then
    call(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
    icon.hhOurs = true   -- never killed by a region sweep
  end
  hh.icon = icon
  hh.backdrop = solid(b, "BACKGROUND", { 0.10, 0.10, 0.12 }, 0.9, -8)
  hh.backdrop:SetAllPoints(b)
  hh.edges = Skin.Outline(b, b)
  if opts.hotkeySize then
    local hk = rawget(b, "HotKey") or (name and rawget(_G, name .. "HotKey"))
    if hk then Skin.SetFont(hk, opts.hotkeySize) hk:ClearAllPoints() hk:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1) end
    local cnt = rawget(b, "Count") or (name and rawget(_G, name .. "Count"))
    if cnt then Skin.SetFont(cnt, opts.hotkeySize) end
    local nm = rawget(b, "Name") or (name and rawget(_G, name .. "Name"))
    if nm then if opts.hideNames then call(nm.SetAlpha, nm, 0) else Skin.SetFont(nm, math.max(7, opts.hotkeySize - 2)) end end
  end
  return hh
end

-- ------------------------------------------------------------------------------------------------ module
function Skin.ApplyAll(reason)
  if Skin.cfg().enabled == false then return end
  for _, part in ipairs(Skin.parts) do
    HH:RunOutOfCombat(function()
      local ok, err = xpcall(part.Apply, HH.Trace, reason)
      if not ok then HH:LogError("skin " .. part.name .. ": " .. tostring(err)) end
    end)
  end
end

function Skin.Register(part) Skin.parts[#Skin.parts + 1] = part end

function Skin.Diag()
  local f, m = {}, {}
  for k in pairs(Skin.found) do f[#f + 1] = k end
  for k in pairs(Skin.missing) do if not Skin.found[k] then m[#m + 1] = k end end
  table.sort(f) table.sort(m)
  return f, m
end

local Module = {}
HHS.module = Module

function Module:OnEnable()
  if Skin.cfg().enabled == false then return end
  Skin.ApplyAll("enable")
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE", "BAG_UPDATE_DELAYED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BINDINGS", "PLAYER_REGEN_ENABLED", "MERCHANT_SHOW", "ADDON_LOADED",
    "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "ITEM_TEXT_READY", "MAIL_SHOW", "QUEST_LOG_UPDATE" }) do
    pcall(ev.RegisterEvent, ev, e)
  end
  ev:SetScript("OnEvent", function(_, e, arg1)
    for _, part in ipairs(Skin.parts) do
      if part.OnEvent then
        local ok, err = xpcall(part.OnEvent, HH.Trace, e, arg1)
        if not ok and err ~= Skin.lastError then Skin.lastError = err HH:LogError("skin " .. part.name .. " " .. e .. ": " .. tostring(err)) end
      end
    end
  end)
  Module.events = ev
end

function Module:OnProfileChanged() Skin.ApplyAll("profile") end

function Module:GetOptions()
  if HHS.Options and HHS.Options.Build then return HHS.Options.Build() end
end

HH:RegisterModule("Skin", Module)

HH:RegisterSlash("skindiag", function()
  local f, m = Skin.Diag()
  HH:Print(("skin: %d Blizzard pieces found, %d missing on this client"):format(#f, #m))
  if #m > 0 then HH:Print("  missing: " .. table.concat(m, ", ")) end
  local g = HH.db and HH.db.global
  if g then g.diag = g.diag or {} g.diag.skin = { found = table.concat(f, ","), missing = table.concat(m, ",") } end
end, "which Blizzard frames the skin found / could not find on this client")
