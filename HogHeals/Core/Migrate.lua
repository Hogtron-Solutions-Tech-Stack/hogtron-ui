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
  { version = 2, run = function(db)
      -- 0.1.0 shipped wide 120x32 bars (x wizard density). Defaults are now square-ish cells; drop saved sizes
      -- that still have the old wide shape so the new defaults show through. Anything already squarer than
      -- 2.5:1 was a deliberate choice and is kept.
      for _, profile in pairs(db.profiles or { db.profile }) do
        local layouts = profile.frames and profile.frames.layouts
        local fresh = HH.defaults and HH.defaults.profile.frames.layouts or {}
        for bucket, l in pairs(layouts or {}) do
          local w, h = tonumber(rawget(l, "width")), tonumber(rawget(l, "height"))
          -- AceDB copies scalar defaults only at load, so write the new size explicitly (nil would stay nil).
          if w and h and h > 0 and w / h > 2.5 and fresh[bucket] then
            l.width, l.height = fresh[bucket].width, fresh[bucket].height
          end
        end
      end
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
