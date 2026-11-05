-- Camera: how far the camera may pull back. Sean 2026-11-04: "I also want to be able to zoom out further. I think the
-- default is very close." The client's cameraDistanceMaxZoomFactor (Classic default 1.9; the client caps what it keeps -
-- 2.6 on Era / Anniversary, Forever whatever it allows) is set at login, on entering the world and when the slider
-- moves. The value the client actually kept is read back and shown (/hh zoom), so a cap never hides behind the slider.
-- profile.camera.maxZoom (default 2.6); 0 = leave the client's own value alone.
local HH = HogHeals

local Camera = { CVAR = "cameraDistanceMaxZoomFactor" }
HH.Camera = Camera

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a = pcall(f, ...)
  if ok then return a end
end
local function g(n) return rawget(_G, n) end
local function fn(t, k) return type(t) == "table" and type(t[k]) == "function" and t[k] or nil end
local function cfg()
  local p = HH.db and HH.db.profile
  if not p then return {} end
  p.camera = p.camera or {}
  return p.camera
end

--- The value the client holds now, as a number, or nil.
function Camera.Get()
  local C = g("C_CVar")
  local v
  if fn(C, "GetCVar") then v = call(C.GetCVar, Camera.CVAR) else v = call(g("GetCVar"), Camera.CVAR) end
  if v == nil or isSecret(v) then return nil end
  return tonumber(v)
end

--- Set the client's value. true, or false + why.
function Camera.Set(v)
  local C = g("C_CVar")
  local ok, err
  if fn(C, "SetCVar") then ok, err = pcall(C.SetCVar, Camera.CVAR, v)
  else
    local f = g("SetCVar")
    if type(f) ~= "function" then return false, "no SetCVar on this client" end
    ok, err = pcall(f, Camera.CVAR, v)
  end
  if not ok then return false, tostring(err) end
  return true
end

--- Apply the profile's max zoom-out. Returns what the client kept (a number), or nil + why. 0 / nil = left alone.
function Camera.Apply(why)
  local want = tonumber(cfg().maxZoom)
  if not want or want <= 0 then Camera.last = { why = why, skipped = true } return nil, "off (0 = the client's own value)" end
  local ok, err = Camera.Set(want)
  local kept = Camera.Get()
  Camera.last = { why = why, want = want, kept = kept, ok = ok, err = err }
  if not ok then return nil, err end
  return kept
end

--- One chat line on where things stand.
function Camera.Say()
  local want = tonumber(cfg().maxZoom) or 0
  local kept, why = Camera.Apply("say")
  if not kept then return "camera: " .. tostring(why) end
  local cap = kept < want - 0.01 and " - this client's cap" or ""
  return ("camera: max zoom-out set to %.1f, the client keeps %.1f%s. Scroll out to use it."):format(want, kept, cap)
end

HH:RegisterSlash("zoom", function(rest)
  local n = tonumber((rest or ""):match("[%d%.]+"))
  if n then cfg().maxZoom = n end
  HH:Print(Camera.Say())
end, "camera max zoom-out: /hh zoom 2.6 (the client caps what it keeps; /hh zoom 0 = leave the client's)")

local Module = {}
function Module:OnEnable()
  Camera.Apply("login")
  local ev = CreateFrame("Frame")
  if pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD") then
    ev:SetScript("OnEvent", function() Camera.Apply("world") end)
  end
  Module.events = ev
end
function Module:OnProfileChanged() Camera.Apply("profile") end

HH:RegisterModule("Camera", Module)
