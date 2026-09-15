-- Ordered, idempotent schema migrations. db.global.schema records the last applied step.
local ADDON, ns = ...
local HH = HogHeals

local Migrate = {}
HH.Migrate = Migrate

-- Each step: { version = N, run = function(db) end }. Steps run in order when db.global.schema < version.
Migrate.steps = {
  { version = 1, run = function(db)
      -- Initial schema: nothing to transform, just stamp.
      db.profile.frames = db.profile.frames or {}
    end },
}

function Migrate.Run(db)
  if not db or not db.global then return end
  local current = tonumber(db.global.schema) or 0
  for _, step in ipairs(Migrate.steps) do
    if step.version > current then
      local ok, err = pcall(step.run, db)
      if not ok then
        if HH.LogError then HH:LogError(("migration %d failed: %s"):format(step.version, tostring(err))) end
        break
      end
      current = step.version
      db.global.schema = current
    end
  end
  return db.global.schema
end
