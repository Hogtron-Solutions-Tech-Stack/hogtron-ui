-- GameMenu: the Escape menu says "HogTron Edit Mode" where Blizzard's "Edit Mode" was.
-- Sean 2026-11-03 (first Anniversary run): "I don't like that the edit mode is still visible on the menu ... there's extra
-- windows and I can't edit them ... only put the HogTron edit mode on there". Blizzard's Edit Mode arranges frames this
-- UI hides or replaces, so its button opens an editor over nothing. While profile.edit.gameMenu is on (default) that
-- button goes invisible and unclickable (alpha 0 + mouse off: it keeps its slot, so Blizzard's layout is untouched) and
-- our own button sits in that slot: it closes the menu and unlocks (= /hh unlock).
-- The menu with the diamond-metal header (Forever, Anniversary: diag.skin GameMenuFrame.Header) rebuilds its buttons from
-- a pool in GameMenuFrame:InitButtons() on every open, so a post-hook there re-applies each time and first restores any
-- pooled button muted last time (a pooled button comes back under another label - alpha 0 must never stay on it).
-- A menu without the pool (named GameMenuButton* children) gets the same through the frame's children on OnShow.
-- Nothing is written on Blizzard's frames (CLAUDE.md rule 6): alpha, EnableMouse and post-hooks only; the button is ours.
-- /hh menudiag prints what this client offered (diag.gameMenu).
local HH = HogHeals

local GM = { state = "not hooked", applied = 0, muted = setmetatable({}, { __mode = "k" }) }
HH.GameMenu = GM
GM.TEXT = "HogTron Edit Mode"

local function G(name) return rawget(_G, name) end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
end
local function cfg()
  local p = HH.db and HH.db.profile
  if not p then return {} end
  p.edit = p.edit or {}
  return p.edit
end
local function on() return cfg().gameMenu ~= false end

local function note(key, value)
  local g = HH.db and HH.db.global
  if not g then return end
  g.diag = g.diag or {}
  g.diag.gameMenu = g.diag.gameMenu or {}
  g.diag.gameMenu[key] = value
end

--- The label Blizzard gives its button (HUD_EDIT_MODE_MENU); "Edit Mode" when the client has no such string.
function GM.EditModeText()
  local s = G("HUD_EDIT_MODE_MENU")
  return (type(s) == "string" and s ~= "") and s or "Edit Mode"
end

local function text(btn)
  local t = btn and btn.GetText and call(btn.GetText, btn)
  return type(t) == "string" and t or nil
end

--- Blizzard's buttons on the menu: the pool's active frames when there is one, else the frame's children.
function GM.Buttons(menu)
  local out = {}
  local pool = menu.buttonPool
  if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
    local ok, iter, a, b = pcall(pool.EnumerateActive, pool)
    if ok and type(iter) == "function" then
      for btn in iter, a, b do if type(btn) == "table" then out[#out + 1] = btn end end
    end
    if #out > 0 then return out, "pool" end
  end
  if type(menu.GetChildren) == "function" then
    local r = { pcall(menu.GetChildren, menu) }
    if r[1] then for i = 2, #r do if type(r[i]) == "table" then out[#out + 1] = r[i] end end end
  end
  return out, "children"
end

--- Our button, made once: the menu's own button template when the client has one, else a plain one in our look.
function GM.Button(menu)
  if GM.button then return GM.button end
  local b
  for _, tpl in ipairs({ "MainMenuFrameButtonTemplate", "GameMenuButtonTemplate", "UIPanelButtonTemplate" }) do
    local ok, f = pcall(CreateFrame, "Button", "HogTronUIGameMenuEditButton", menu, tpl)
    if ok and type(f) == "table" then b, GM.template = f, tpl break end
  end
  if not b then
    b = CreateFrame("Button", "HogTronUIGameMenuEditButton", menu)
    GM.template = "plain"
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(b)
    b.bg:SetColorTexture(0.07, 0.07, 0.09, 0.9)
    b.label = b:CreateFontString(nil, "OVERLAY", "HogTronFontNormal")
    b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.label:SetText(GM.TEXT)
  end
  if b.SetText then call(b.SetText, b, GM.TEXT) end
  b:SetScript("OnClick", function()
    local hide = G("HideUIPanel")
    if type(hide) == "function" then pcall(hide, menu) else call(menu.Hide, menu) end
    HH:SetLocked(false)
  end)
  GM.button = b
  return b
end

--- Muted pooled buttons go back the way Blizzard left them; keep = the one that stays muted (nil = all back).
local function restore(keep)
  for btn in pairs(GM.muted) do
    if btn ~= keep then
      call(btn.SetAlpha, btn, 1)
      call(btn.EnableMouse, btn, true)
      GM.muted[btn] = nil
    end
  end
end

--- Apply to the menu: Blizzard's Edit Mode button muted + ours in its slot; off (or no such button) = everything back.
function GM.Apply(menu)
  menu = menu or G("GameMenuFrame")
  if type(menu) ~= "table" then GM.state = "no GameMenuFrame" note("state", GM.state) return GM.state end
  local want = GM.EditModeText()
  local list, how = GM.Buttons(menu)
  local target
  for _, btn in ipairs(list) do
    if btn ~= GM.button and text(btn) == want then target = btn break end
  end
  if not on() then target = nil end
  restore(target)
  note("how", how) note("count", #list)
  if not target then
    if GM.button then GM.button:Hide() end
    GM.state = on() and ("no '" .. want .. "' button (" .. how .. ", " .. #list .. " buttons)") or "off"
    note("state", GM.state)
    return GM.state
  end
  call(target.SetAlpha, target, 0)
  call(target.EnableMouse, target, false)
  GM.muted[target] = true
  local b = GM.Button(menu)
  b:ClearAllPoints()
  b:SetAllPoints(target)
  local lvl = call(target.GetFrameLevel, target)
  if type(lvl) == "number" then call(b.SetFrameLevel, b, lvl + 1) end
  b:Show()
  GM.applied = GM.applied + 1
  GM.state = "replaced (" .. how .. ")"
  note("state", GM.state) note("template", GM.template)
  return GM.state
end

--- Hook the menu once: after Blizzard rebuilds its buttons (InitButtons) and on show (menus without the pool).
function GM.Hook()
  local menu = G("GameMenuFrame")
  if type(menu) ~= "table" then GM.state = "no GameMenuFrame" note("state", GM.state) return false end
  if GM.hooked then return true end
  local via = {}
  if type(menu.InitButtons) == "function" and pcall(hooksecurefunc, menu, "InitButtons", function(self) GM.Apply(self) end) then via[#via + 1] = "InitButtons" end
  if type(menu.HookScript) == "function" and pcall(menu.HookScript, menu, "OnShow", function(self) GM.Apply(self) end) then via[#via + 1] = "OnShow" end
  if #via == 0 then GM.state = "cannot hook" note("state", GM.state) return false end
  GM.hooked = table.concat(via, "+")
  GM.state = "hooked via " .. GM.hooked
  note("hook", GM.hooked)
  if call(menu.IsShown, menu) then GM.Apply(menu) end
  return true
end

--- /hh menudiag lines.
function GM.Diagnose()
  local menu = G("GameMenuFrame")
  local out = { ("game menu: %s   setting: %s   applied: %d"):format(GM.state, on() and "on" or "off", GM.applied) }
  if type(menu) == "table" then
    local list, how = GM.Buttons(menu)
    local names = {}
    for _, btn in ipairs(list) do names[#names + 1] = text(btn) or (btn.GetName and call(btn.GetName, btn)) or "?" end
    out[#out + 1] = ("buttons (%s): %s"):format(how, table.concat(names, " | "))
    out[#out + 1] = ("InitButtons=%s buttonPool=%s HUD_EDIT_MODE_MENU=%s template=%s"):format(type(menu.InitButtons),
      type(menu.buttonPool), tostring(G("HUD_EDIT_MODE_MENU")), tostring(GM.template))
  end
  return out
end

HH:RegisterSlash("menudiag", function()
  local ok, lines = pcall(GM.Diagnose)
  if not ok then HH:Print("menudiag failed: " .. tostring(lines)) return end
  for _, l in ipairs(lines) do HH:Print(l) end
end, "what the Escape menu offers (the HogTron Edit Mode button)")

HH:RegisterModule("GameMenu", { OnEnable = function() GM.Hook() end })
