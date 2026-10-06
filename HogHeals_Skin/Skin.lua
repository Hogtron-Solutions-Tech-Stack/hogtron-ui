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

--- Every return value of a method (GetRegions / GetChildren return a list), as a table; {} when it errors.
function Skin.all(f, ...)
  if type(f) ~= "function" then return {} end
  local res = { pcall(f, ...) }
  if not res[1] then return {} end
  table.remove(res, 1)
  return res
end

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

--- Every texture of `frame` AND of its plain-Frame descendants (a NineSlice border, a backdrop holder) cleared:
-- the panel Blizzard draws around a group of buttons when we do not know its name on this client. Never descends
-- into buttons / bars / anything that is not a plain Frame (their icons and fills are the point), never into ours
-- (hhOurs), never into UIParent. Bounded: 3 levels, 80 textures. Returns how many it cleared.
function Skin.KillArt(frame, depth, budget, seen)
  depth, seen, budget = depth or 0, seen or {}, budget or { n = 80 }
  if type(frame) ~= "table" or seen[frame] or frame == UIParent or frame.hhOurs or budget.n <= 0 or depth > 3 then return 0 end
  seen[frame] = true
  local kind = call(frame.GetObjectType, frame)
  if kind ~= "Frame" then return 0 end
  local n = 0
  for _, r in ipairs(Skin.all(frame.GetRegions, frame)) do
    if budget.n > 0 and Skin.Kill(r) then n, budget.n = n + 1, budget.n - 1 end
  end
  for _, ch in ipairs(Skin.all(frame.GetChildren, frame)) do
    n = n + Skin.KillArt(ch, depth + 1, budget, seen)
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
  p.hhOurs = true
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

-- ------------------------------------------------------------------------------------------------ /hh under
-- What Blizzard draws under the cursor: every visible frame whose rect holds the cursor, deepest first, with the
-- textures it shows. For art we could not name (Sean 2026-10-02: a gold panel still behind the menu bar). Chat
-- gets the top lines, diag.under on disk gets them all.
local function describe(f)
  local name = call(f.GetName, f)
  if type(name) ~= "string" then
    local p, key = call(f.GetParent, f), nil
    if type(p) == "table" then for k, v in pairs(p) do if v == f and type(k) == "string" then key = k break end end end
    local pn = type(p) == "table" and call(p.GetName, p)
    name = (type(pn) == "string" and pn or "?") .. "." .. (key or "?")
  end
  local p = call(f.GetParent, f)
  local pn = type(p) == "table" and call(p.GetName, p)
  local w, h = Skin.num(call(f.GetWidth, f)) or 0, Skin.num(call(f.GetHeight, f)) or 0
  local tex = {}
  for _, r in ipairs(Skin.all(f.GetRegions, f)) do
    if type(r) == "table" and call(r.GetObjectType, r) == "Texture" and not r.hhOurs and call(r.IsShown, r) and (Skin.num(call(r.GetAlpha, r)) or 1) > 0 then
      local a = call(r.GetAtlas, r)
      local t = call(r.GetTexture, r)
      local s = (type(a) == "string" and ("atlas " .. a)) or (t ~= nil and tostring(t)) or "color"
      if #tex < 6 then tex[#tex + 1] = s end
    end
  end
  return ("%s [%s L%s %s %dx%d a=%.2f] < %s | %s"):format(name, tostring(call(f.GetObjectType, f)), tostring(call(f.GetFrameLevel, f)),
    tostring(call(f.GetFrameStrata, f)), w, h, Skin.num(call(f.GetAlpha, f)) or 1, type(pn) == "string" and pn or "?",
    #tex > 0 and table.concat(tex, ", ") or "no textures"), Skin.num(call(f.GetFrameLevel, f)) or 0
end

function Skin.Under()
  if type(EnumerateFrames) ~= "function" or type(GetCursorPosition) ~= "function" then return nil, "no frame walk on this client" end
  local cx, cy = GetCursorPosition()
  if not Skin.num(cx) or not Skin.num(cy) then return nil, "no cursor position" end
  local hits, f, n = {}, EnumerateFrames(), 0
  while type(f) == "table" and n < 20000 do
    n = n + 1
    local forbidden = f.IsForbidden and call(f.IsForbidden, f)
    if not forbidden and not f.hhOurs and call(f.IsVisible, f) then
      local name = call(f.GetName, f)
      if not (type(name) == "string" and name:find("^HogHeals")) then
        local s = Skin.num(call(f.GetEffectiveScale, f)) or 1
        local l, r, t, b = Skin.num(call(f.GetLeft, f)), Skin.num(call(f.GetRight, f)), Skin.num(call(f.GetTop, f)), Skin.num(call(f.GetBottom, f))
        local x, y = cx / s, cy / s
        if l and r and t and b and x >= l and x <= r and y >= b and y <= t then
          local line, level = describe(f)
          hits[#hits + 1] = { line = line, level = level }
        end
      end
    end
    f = EnumerateFrames(f)
  end
  table.sort(hits, function(a, b) return a.level > b.level end)
  local out = {}
  for i = 1, math.min(#hits, 60) do out[i] = hits[i].line end
  return out
end

HH:RegisterSlash("under", function()
  local lines, why = Skin.Under()
  if not lines then HH:Print("under: " .. tostring(why)) return end
  HH:Print(("under the cursor: %d frames (deepest first; all %d in diag.under)"):format(#lines, #lines))
  for i = 1, math.min(#lines, 20) do HH:Print("  " .. lines[i]) end
  local g = HH.db and HH.db.global
  if g then g.diag = g.diag or {} g.diag.under = { at = date and date("%Y-%m-%d %H:%M:%S") or "?", lines = table.concat(lines, "\n") } end
end, "which Blizzard frames and textures sit under the cursor (names the art the skin missed)")

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
  local micro = HHS.Micro
  if micro and (micro.containerDiag or micro.bagDiag) then
    HH:Print("  menu ancestors: " .. tostring(micro.containerDiag or "-") .. " | bag ancestors: " .. tostring(micro.bagDiag or "-"))
    HH:Print(("  bag slots found: %d [%s]; bar anchor: %s; menu buttons: %d"):format(micro.bagCount or 0, tostring(micro.bagNames or ""), tostring(micro.barAnchor), micro.microCount or 0))
    HH:Print("  faded over the slots: " .. tostring(micro.bagOverlayDiag or "-"))
  end
  local g = HH.db and HH.db.global
  local xp = (HHS.Extras and HHS.Extras.ProbeXP) and HHS.Extras.ProbeXP() or {}
  if g then g.diag = g.diag or {} g.diag.skin = { found = table.concat(f, ","), missing = table.concat(m, ","), xp = table.concat(xp, " ; "),
    micro = micro and micro.containerDiag or nil, bags = micro and micro.bagDiag or nil,
    bagCount = micro and micro.bagCount or nil, bagNames = micro and micro.bagNames or nil, barAnchor = micro and micro.barAnchor or nil,
    overlays = micro and micro.bagOverlayDiag or nil } end
  if #xp > 0 then HH:Print(("  xp bar textures: %d recorded (diag.skin.xp)"):format(#xp)) end
end, "which Blizzard frames the skin found / could not find on this client")
