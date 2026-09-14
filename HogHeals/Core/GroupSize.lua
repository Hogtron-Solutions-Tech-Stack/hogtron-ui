-- Group-size bucketing: solo | party | raid10 | raid20 | raid40
local ADDON, ns = ...
local HH = HogHeals

--- Pure: map member count + raid flag to a layout bucket.
function HH.BucketForSize(n, isRaid)
  n = tonumber(n) or 0
  if isRaid then
    if n <= 10 then return "raid10" end
    if n <= 20 then return "raid20" end
    return "raid40"
  end
  if n <= 1 then return "solo" end
  return "party"
end

HH.BUCKETS = { "solo", "party", "raid10", "raid20", "raid40" }

function HH:CurrentBucket()
  return HH.BucketForSize(GetNumGroupMembers(), IsInRaid())
end

function HH:CheckBucket()
  local new = self:CurrentBucket()
  local old = self._bucket
  if new ~= old then
    self._bucket = new
    self.callbacks:Fire("BUCKET_CHANGED", new, old)
  end
  return new
end

function HH:InitGroupSize()
  self._bucket = self:CurrentBucket()
  self:RegisterEvent("GROUP_ROSTER_UPDATE", "CheckBucket")
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "CheckBucket")
end
