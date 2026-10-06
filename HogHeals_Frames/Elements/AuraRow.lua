-- AuraRow: one row of small aura icons on a party / raid cell, shared by the buff row (Buffs.lua) and the debuff
-- row (Debuffs.lua). Icons are plain Frames with the mouse OFF so the cell under them keeps every hover-cast
-- binding. Secret-safe: icon, count and cooldown go straight to widgets; nothing secret is compared.
--
-- Row settings (profile.frames.buffs / .debuffs): size, max, anchor (one of the nine points), x, y, grow
-- ("RIGHT" | "LEFT", default from the anchor: a *RIGHT anchor grows left), gap, numbers (countdown text on the
-- swipe, needs size >= 14 to be readable).
local HHF = HogHealsFrames
local HH = HogHeals

local R = {}
HHF.AuraRow = R

R.LINE = { 0.20, 0.20, 0.25 }
R.CYAN = { 0.13, 0.83, 0.88 }
R.ANCHORS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

local function isSecret(v) return HHF.Compat.IsSecret(v) end
function R.num(v) if type(v) == "number" and not isSecret(v) then return v end end
function R.str(v) if type(v) == "string" and not isSecret(v) then return v end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a = pcall(f, ...)
  if ok then return a end
end

--- A key that tells two readings of one aura apart without touching a secret: the plain name, else the instance id.
function R.Key(a)
  local n = R.str(a.name)
  if n then return n end
  local id = R.num(a.auraInstanceID)
  if id then return "#" .. id end
  return nil
end

--- The icon frame i of row `key` on the button, made on first use.
function R.Icon(button, key, i)
  button[key] = button[key] or {}
  local b = button[key][i]
  if b then return b end
  b = CreateFrame("Frame", nil, button.overlay)
  b:EnableMouse(false)
  b:SetFrameLevel(button.overlay:GetFrameLevel() + 1)
  b.edge = b:CreateTexture(nil, "BACKGROUND")
  b.edge:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
  b.edge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
  b.edge:SetColorTexture(R.LINE[1], R.LINE[2], R.LINE[3], 1)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints(b)
  if b.icon.SetTexCoord then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints(b)
  if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
  if b.cd.SetDrawEdge then b.cd:SetDrawEdge(false) end
  b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
  b.count:SetJustifyH("RIGHT")
  button[key][i] = b
  return b
end

--- Paint one aura onto an icon frame. edge = { r, g, b } for the 1 px frame around it.
function R.Paint(b, a, size, edge, numbers)
  b.aura = a
  b:SetSize(size, size)
  b.icon:SetTexture(a.icon)
  local n = R.num(a.applications)
  if n and n > 1 then b.count:SetText(tostring(n)) b.count:Show()
  elseif n == nil and a.applications ~= nil and isSecret(a.applications) then b.count:SetText(string.format("%s", a.applications)) b.count:Show()
  else b.count:SetText("") b.count:Hide() end
  if b.count.SetFont then call(b.count.SetFont, b.count, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", math.max(7, math.floor(size * 0.6)), "OUTLINE") end
  edge = edge or R.LINE
  b.edge:SetColorTexture(edge[1], edge[2], edge[3], 1)
  local dur, exp = R.num(a.duration), R.num(a.expirationTime)
  if dur and exp and dur > 0 and b.cd.SetCooldown then
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(not numbers) end
    b.cd:SetCooldown(exp - dur, dur)
    b.cd:Show()
  else
    b.cd:Hide()
  end
  b:Show()
end

--- Where icon i of a row sits: anchor point + offsets, growing along the row. Pure.
--   returns point, x, y
function R.Place(cfg, i, size)
  local anchor = cfg.anchor or "BOTTOMLEFT"
  local gap = cfg.gap or 1
  local grow = cfg.grow
  if grow ~= "LEFT" and grow ~= "RIGHT" then grow = anchor:find("RIGHT", 1, true) and "LEFT" or "RIGHT" end
  local step = (i - 1) * (size + gap)
  local x = (cfg.x or 0) + (grow == "LEFT" and -step or step)
  return anchor, x, cfg.y or 0
end

--- Draw a whole row: list = aura tables (AuraData shape), edgeFor(a) = edge colour per aura (optional).
-- Hides the icons past the list. Returns how many are shown; also kept on button[key .. "Count"].
function R.Row(button, key, list, cfg, edgeFor)
  local size, max = cfg.size or 12, cfg.max or 4
  local shown = 0
  for i, a in ipairs(list) do
    if i > max then break end
    local b = R.Icon(button, key, i)
    R.Paint(b, a, size, edgeFor and edgeFor(a) or R.LINE, cfg.numbers == true)
    local point, x, y = R.Place(cfg, i, size)
    b:ClearAllPoints()
    b:SetPoint(point, button, point, x, y)
    shown = i
  end
  for i = shown + 1, #(button[key] or {}) do button[key][i]:Hide() end
  button[key .. "Count"] = shown
  return shown
end

function R.HideAll(button, key)
  for _, b in ipairs(button[key] or {}) do b:Hide() end
  button[key .. "Count"] = 0
end

--- The edge colour for a harmful aura: Blizzard's dispel-type colour when the type is a plain string, else the
-- panel line. Never indexes a table with a secret.
function R.HarmfulEdge(a)
  local t = R.str(a.dispelName)
  local colors = rawget(_G, "DebuffTypeColor")
  local c = t and type(colors) == "table" and colors[t]
  if type(c) == "table" and c.r then return { c.r, c.g, c.b } end
  return R.LINE
end

-- ---------------------------------------------------------------- test mode
-- A fake cell (/hh test) has no unit API: TestMode paints it directly and asks hooks to add their pieces. The fake
-- aura tables (name, type, icon, source, duration, expires, count) are mapped onto the AuraData shape here.
HHF.TestHooks = HHF.TestHooks or {}
function R.FakeAuras(fake)
  local harmful, helpful = {}, {}
  local _, class = UnitClass("player")
  for _, a in ipairs(fake.auras or {}) do
    local m = { name = a.name, icon = a.icon, applications = a.count, duration = a.duration, expirationTime = a.expires,
      dispelName = a.type, sourceUnit = a.source, mine = a.source == "player",
      canActivePlayerDispel = a.type and HH.CanDispel(class, a.type) or false }
    if a.source then helpful[#helpful + 1] = m else harmful[#harmful + 1] = m end
  end
  return harmful, helpful
end

HHF.TestHooks[#HHF.TestHooks + 1] = function(button, fake)
  local harmful, helpful = R.FakeAuras(fake)
  local enabled = HHF.UnitButton.ElementEnabled
  local d = HH.db.profile.frames
  if HHF.Debuffs and enabled("debuffs") then HHF.Debuffs.Draw(button, harmful) else R.HideAll(button, "debuffs") end
  if HHF.Buffs and enabled("buffs") then
    local mode = (d.buffs or {}).filter or "all"
    local list = {}
    for _, a in ipairs(helpful) do if a.mine then list[#list + 1] = a end end
    if mode == "all" then for _, a in ipairs(helpful) do if not a.mine then list[#list + 1] = a end end end
    HHF.Buffs.Draw(button, list, mode)
  else
    R.HideAll(button, "buffs")
  end
end
