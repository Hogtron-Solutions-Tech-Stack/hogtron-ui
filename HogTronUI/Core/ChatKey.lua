-- ChatKey: Enter belongs to chat. Sean 2026-10-08 in game: "Enter isn't opening the chat window, but / lets me type".
-- Enter opens chat through Blizzard's OPENCHAT binding; "/" through OPENCHATSLASH. Only the first was broken, so
-- something had taken the ENTER key: our own binders can - hover a slot in /hh bind or a row in the hover-heal panel
-- and press Enter, and ENTER was bound to that slot / spell (saved, so it survives a reload; the hover-heal keys are
-- applied as override bindings, which beat Blizzard's). Three guards:
--   RESERVED      keys neither binder will ever take (Enter = chat, Escape = clearing)
--   Strip         saved hover-heal bindings lose any reserved key at load (ClickCast.Init)
--   /hh enter     what ENTER does now; "/hh enter fix" puts OPENCHAT back and saves; a login check says so in chat
-- Every API looked up by name.
local HH = HogHeals

local CK = { seen = {} }
HH.ChatKey = CK

HH.RESERVED_KEYS = { ENTER = "opening chat", ESCAPE = "menus and clearing a key" }

local function g(name) local f = rawget(_G, name) if type(f) == "function" then return f end end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a = pcall(f, ...)
  if ok then return a end
end

--- Is `key` one we never bind? Returns the reason or nil.
function CK.Reserved(key)
  if type(key) ~= "string" then return nil end
  return HH.RESERVED_KEYS[key:upper()]
end

--- Drop bindings on reserved keys from a ClickCast-shaped list { { key, mod, ... } }. Returns the list and what went.
function CK.Strip(list)
  local out, gone = {}, {}
  for _, b in ipairs(list or {}) do
    if CK.Reserved(b.key) then gone[#gone + 1] = b else out[#out + 1] = b end
  end
  return out, gone
end

--- What ENTER is bound to: "ok" (OPENCHAT), "taken" (something else), "unbound", or "unknown" (client cannot say).
function CK.Check()
  local f = g("GetBindingAction")
  if not f then return "unknown", nil end
  local action = call(f, "ENTER")
  if type(action) ~= "string" then return "unknown", nil end
  if action == "OPENCHAT" then return "ok", action end
  if action == "" then return "unbound", action end
  return "taken", action
end

--- Put OPENCHAT back on ENTER and save the set. True when the client let us.
function CK.Fix()
  local set, save = g("SetBinding"), g("SaveBindings")
  if not set then return false, "this client gives addons no SetBinding" end
  if g("InCombatLockdown") and call(g("InCombatLockdown")) then return false, "not in combat" end
  local ok = call(set, "ENTER", "OPENCHAT")
  if ok == false then return false, "SetBinding refused" end
  if save then
    local which = call(g("GetCurrentBindingSet"))
    pcall(save, which == 2 and 2 or 1)
  end
  CK.seen.fixed = (CK.seen.fixed or 0) + 1
  return true
end

function CK.Lines()
  local state, action = CK.Check()
  local out = {}
  if state == "ok" then out[#out + 1] = "Enter: opens chat (OPENCHAT). Fine."
  elseif state == "taken" then out[#out + 1] = ("Enter: bound to %s - chat will not open on Enter. /hh enter fix puts OPENCHAT back."):format(tostring(action))
  elseif state == "unbound" then out[#out + 1] = "Enter: bound to nothing. /hh enter fix puts OPENCHAT back."
  else out[#out + 1] = "Enter: this client will not say what the key does." end
  return out
end

--- A moment after login: say so if Enter is not chat (the binding set is loaded by then).
function CK.Init()
  if CK.frame then return end
  local f = CreateFrame("Frame")
  pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")
  f:SetScript("OnEvent", function()
    local function check()
      local state = CK.Check()
      if state == "taken" or state == "unbound" then for _, l in ipairs(CK.Lines()) do HH:Print(l) end end
    end
    if C_Timer and C_Timer.After then C_Timer.After(3, check) else check() end
  end)
  CK.frame = f
end

HH:RegisterSlash("enter", function(rest)
  if (rest or ""):lower():match("fix") then
    local ok, why = CK.Fix()
    HH:Print(ok and "Enter: OPENCHAT is back on it (saved)." or ("Enter: could not fix - " .. tostring(why) .. "."))
    return
  end
  for _, l in ipairs(CK.Lines()) do HH:Print(l) end
end, "what the Enter key does; /hh enter fix gives it back to chat")

CK.Init()
