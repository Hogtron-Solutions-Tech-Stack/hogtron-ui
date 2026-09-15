-- Combat-lockdown queue. Every secure-frame mutation goes through RunOutOfCombat.
local ADDON, ns = ...
local HH = HogHeals

local queue = {}

--- Run fn now if out of combat, else queue it until PLAYER_REGEN_ENABLED.
function HH:RunOutOfCombat(fn, ...)
  if type(fn) ~= "function" then return false end
  local n = select("#", ...)
  if InCombatLockdown() then
    queue[#queue + 1] = { fn = fn, n = n, ... }
    return false
  end
  local ok, err = pcall(fn, ...)
  if not ok then self:LogError(err) end
  return true
end

function HH:QueuedCount() return #queue end

function HH:DrainQueue()
  if InCombatLockdown() then return end
  local pending = queue
  queue = {}
  for _, item in ipairs(pending) do
    local ok, err = pcall(item.fn, unpack(item, 1, item.n))
    if not ok then self:LogError(err) end
  end
end

function HH:InitQueue()
  self:RegisterEvent("PLAYER_REGEN_ENABLED", "DrainQueue")
end
