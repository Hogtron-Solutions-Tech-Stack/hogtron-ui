-- Level ranges and their colour for your level. The game's own range wins when it gives one (Group Finder, the
-- dungeon journal); the shipped list is the fallback and says so.
local A = HogHealsAtlas
local Levels = { ranges = {} }
A.Levels = Levels

--- Colour band for level L against [min, max]:
--   red    L < min            too low
--   orange min <= L < min+2   hard
--   green  min+2 <= L <= max  right
--   grey   L > max            outgrown
function Levels.Band(L, min, max)
  if type(L) ~= "number" or type(min) ~= "number" or type(max) ~= "number" then return "unknown" end
  if L < min then return "red" end
  if L > max then return "grey" end
  if L < min + 2 then return "orange" end
  return "green"
end

function Levels.Colour(L, min, max)
  local band = Levels.Band(L, min, max)
  local c = A.COLORS[band] or A.COLORS.cream
  return c[1], c[2], c[3], band
end

--- { min, max, source } for a dungeon: "game" when the client answered, "list" for the shipped range.
function Levels.For(d)
  local r = Levels.ranges[d.key]
  if r then return r.min, r.max, "game" end
  return d.min, d.max, "list"
end

--- Ask Group Finder for its ranges. Measured on Forever 2026-09-28: the activity list held zones only, with level
-- 0-nil, so this usually finds nothing; it costs nothing to ask and picks the data up the day Blizzard adds it.
function Levels.Refresh()
  local found = 0
  local cats = A.call(A.fn("C_LFGList.GetAvailableCategories"))
  local acts = A.fn("C_LFGList.GetAvailableActivities")
  local info = A.fn("C_LFGList.GetActivityInfoTable")
  if type(cats) == "table" and acts and info then
    for _, cat in ipairs(cats) do
      local list = A.call(acts, cat)
      for _, id in ipairs(type(list) == "table" and list or {}) do
        local t = A.call(info, id)
        if type(t) == "table" then
          local name = A.str(t.fullName) or A.str(t.shortName)
          local min = A.num(t.minLevelSuggestion) or A.num(t.minLevel)
          local max = A.num(t.maxLevelSuggestion)
          local d = name and A.Data.byName[name:lower()]
          if d and min and max and min > 0 and max >= min then
            Levels.ranges[d.key] = { min = min, max = max }
            found = found + 1
          end
        end
      end
    end
  end
  Levels.found = found
  return found
end

--- Dungeons for the list, lowest first. forMe = only orange and green for level L. Other faction's dungeons stay in
-- (you can walk there), marked by the window.
function Levels.List(L, forMe)
  local out = {}
  for _, d in ipairs(A.Data.Dungeons) do
    local min, max, source = Levels.For(d)
    local band = Levels.Band(L, min, max)
    if not forMe or band == "orange" or band == "green" then
      out[#out + 1] = { dungeon = d, min = min, max = max, band = band, source = source }
    end
  end
  table.sort(out, function(a, b)
    if a.min ~= b.min then return a.min < b.min end
    if a.max ~= b.max then return a.max < b.max end
    return a.dungeon.name < b.dungeon.name
  end)
  return out
end
