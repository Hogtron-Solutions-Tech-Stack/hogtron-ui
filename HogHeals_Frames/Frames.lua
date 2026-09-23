-- Frames module entry: registers with core, spawns headers, applies profiles.
HogHealsFrames = HogHealsFrames or {}
local HHF = HogHealsFrames
local HH = HogHeals

local Frames = {}
HHF.module = Frames

function Frames:OnInitialize()
  self.db = HH.db.profile.frames
end

function Frames:OnEnable()
  self.db = HH.db.profile.frames
  HHF.UnitButton.FinalizeElements()
  if HHF.Compat and HHF.Compat.Init then HHF.Compat.Init() end
  if HHF.ClickCast and HHF.ClickCast.Init then HHF.ClickCast.Init() end
  if HHF.RequestDispel and HHF.RequestDispel.Init then HHF.RequestDispel.Init() end
  HH:RunOutOfCombat(function()
    if HHF.Headers and HHF.Headers.Spawn then HHF.Headers.Spawn() end
    self:ApplyProfile(HH:CurrentBucket())
  end)
  HH.RegisterCallback(self, "BUCKET_CHANGED", function(_, new) self:ApplyProfile(new) end)
end

function Frames:OnProfileChanged()
  self.db = HH.db.profile.frames
  self:ApplyProfile(HH:CurrentBucket())
end

--- Apply the layout profile for a bucket (queued if in combat).
function Frames:ApplyProfile(bucket)
  self.bucket = bucket or HH:CurrentBucket()
  if HHF.Headers and HHF.Headers.Apply then HHF.Headers.Apply(self.bucket) end
  self:Refresh()
end

--- Re-run appearance + every element on every live button.
function Frames:Refresh()
  if not HHF.UnitButton then return end
  for _, button in ipairs(HHF.UnitButton.All()) do
    HHF.UnitButton.ApplyAppearance(button)
    HHF.UnitButton.UpdateAll(button)
  end
end

--- The layout table a bucket edits and renders. With soloSharesParty (default) the solo bucket uses the party
-- layout, so being alone and being in a group never changes size, direction or position ("when I join a party it
-- makes my frames a different size"). showSolo is read from the solo table separately.
function Frames.ResolveLayout(bucket)
  local db = HH.db.profile.frames
  bucket = bucket or (HHF.module and HHF.module.bucket) or "party"
  if bucket == "solo" and db.soloSharesParty ~= false then return db.layouts.party, "party" end
  return db.layouts[bucket] or db.layouts.party, bucket
end

function Frames:LayoutFor(bucket)
  return (Frames.ResolveLayout(bucket or self.bucket or "party"))
end

-- ------------------------------------------------------------------------------------------------ frame snapshot
-- 2026-09-22: "my health goes grey in combat", no caught error, and a class-colour fix did not change it. Instead of a
-- third guess: record exactly what the bar IS. Taken automatically 3 s into every fight (the player cannot type then)
-- and on /hh framediag; kept in diag.frameSnapshots (last 4), written to disk at the next /reload or logout.
local function describe(v)
  if v == nil then return "nil" end
  if HHF.Compat.IsSecret(v) then return "SECRET" end
  if type(v) == "number" then return ("%.2f"):format(v) end
  return tostring(v)
end

function Frames.Snapshot(reason)
  local out = { at = date and date("%H:%M:%S") or "", reason = reason, inCombat = tostring(InCombatLockdown and InCombatLockdown()),
    classOfLoaded = tostring(HHF.Compat.ClassOf ~= nil), buttons = {} }
  local n = 0
  for _, b in ipairs(HHF.UnitButton.All()) do
    if b.unit and b.IsVisible and b:IsVisible() and n < 3 then
      n = n + 1
      local h = b.health
      local r, g, bl, a = h:GetStatusBarColor()
      local mn, mx = h:GetMinMaxValues()
      local tex = h.GetStatusBarTexture and h:GetStatusBarTexture()
      local okC, cName, cToken = pcall(UnitClass, b.unit)
      local alphas = {}
      for k, v in pairs(b._alphas or {}) do alphas[#alphas + 1] = k .. "=" .. describe(v) end
      out.buttons[n] = {
        unit = b.unit,
        color = describe(r) .. "," .. describe(g) .. "," .. describe(bl) .. "," .. describe(a),
        value = describe(h:GetValue()), min = describe(mn), max = describe(mx),
        UnitHealth = describe(UnitHealth(b.unit)), UnitHealthMax = describe(UnitHealthMax(b.unit)),
        UnitClass = okC and (describe(cName) .. "/" .. describe(cToken)) or "error",
        ClassOf = describe(HHF.Compat.ClassOf(b.unit)),
        healthDead = describe(b.healthDead), dispelColored = describe(b.dispelColored),
        buttonAlpha = describe(b:GetAlpha()), healthAlpha = describe(h:GetAlpha()), healthShown = describe(h:IsShown()),
        barTexture = tex and describe(tex.GetTexture and tex:GetTexture()) or "nil",
        barTextureAlpha = tex and describe(tex.GetAlpha and tex:GetAlpha()) or "nil",
        secretRange = describe(b._secretRange), alphaReasons = table.concat(alphas, ","),
        healthMode = describe(HH.db.profile.frames.appearance.healthMode),
      }
    end
  end
  local g = HH.db and HH.db.global
  if g then
    g.diag = g.diag or {}
    g.diag.frameSnapshots = g.diag.frameSnapshots or {}
    table.insert(g.diag.frameSnapshots, 1, out)
    while #g.diag.frameSnapshots > 4 do table.remove(g.diag.frameSnapshots) end
  end
  return out
end

local snapFrame = CreateFrame("Frame")
pcall(snapFrame.RegisterEvent, snapFrame, "PLAYER_REGEN_DISABLED")
snapFrame:SetScript("OnEvent", function()
  if C_Timer and C_Timer.After then
    C_Timer.After(3, function() pcall(Frames.Snapshot, "combat+3s") end)
  end
end)

HH:RegisterSlash("framediag", function()
  local ok, s = pcall(Frames.Snapshot, "slash")
  if not ok then HH:Print("framediag failed: " .. tostring(s)) return end
  HH:Print(("frames: combat=%s classOf=%s, %d button(s) (saved to diag.frameSnapshots)"):format(s.inCombat, s.classOfLoaded, #s.buttons))
  for _, b in ipairs(s.buttons) do
    HH:Print(("  %s colour=%s value=%s/%s alpha=%s texAlpha=%s class=%s dead=%s"):format(b.unit, b.color, b.value, b.max, b.buttonAlpha, b.barTextureAlpha, b.ClassOf, b.healthDead))
  end
end, "record what the unit frames look like right now (colour, fill, alpha)")

HH:RegisterModule("Frames", Frames)
