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

function Frames:LayoutFor(bucket)
  return self.db.layouts[bucket or self.bucket or "party"]
end

HH:RegisterModule("Frames", Frames)
