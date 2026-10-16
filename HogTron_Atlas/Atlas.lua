-- HogTron UI Atlas: dungeon guide for WoW: Forever. Namespace, settings, and the small helpers every file shares.
--
-- Why this addon reads the game instead of shipping a database: Forever changed the old loot tables, added
-- dungeons, and encrypts item data, so no ready-made table exists. Loot here comes from three places, each marked:
--   journal   the client's own dungeon journal, when it answers (Journal.lua)
--   seen      a drop this character or its group saw (Capture.lua)
--   reported  the curated file shipped with the addon (Data/Loot.lua)
--
-- Rules for this client: every RegisterEvent is pcall'd (unknown events throw), COMBAT_LOG_EVENT_UNFILTERED is never
-- registered (a forbidden action), no value that might be secret is compared, tested or used in arithmetic, and the
-- global GetItemInfo does not exist (C_Item.GetItemInfo does).
HogHealsAtlas = HogHealsAtlas or {}
local A = HogHealsAtlas
local HH = HogHeals

A.COLORS = {
  cream = { 0.96, 0.92, 0.86 }, cyan = { 0.13, 0.83, 0.88 }, ink = { 0.07, 0.07, 0.09 }, panel = { 0.11, 0.11, 0.14 },
  line = { 0.20, 0.20, 0.25 }, grey = { 0.55, 0.55, 0.60 }, green = { 0.25, 0.80, 0.35 }, amber = { 0.95, 0.65, 0.15 },
  red = { 0.85, 0.20, 0.20 }, orange = { 1.00, 0.50, 0.25 },
}
A.QUALITY = {
  [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
  [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
}

-- Settings live in the core profile under .atlas. Defaults are filled in here, not in the core Defaults file, so the
-- module carries everything it needs.
A.DEFAULTS = {
  enabled = true,
  tooltip = true,            -- "Drops from" line on item tooltips
  tooltipScore = true,       -- upgrade score on item tooltips
  upgradeAlerts = true,      -- chat line when you loot something better than what you wear
  wishAlerts = true,         -- chat line when a wishlist item drops
  share = true,              -- tell party / guild about new drops, take theirs
  minimap = { hide = false },  -- the minimap button
  tracker = { enabled = true, point = "RIGHT", x = -40, y = 120 },   -- the on-screen panel inside dungeons
  forMeNow = false,          -- dungeon list: only dungeons for my level
  minQuality = 2,            -- discovery records green and better
  futureLevels = 3,          -- upgrade finder: include items up to this many levels above me
  role = "auto",             -- auto | healer | caster | melee | ranged | tank
  scale = 1, point = "CENTER", x = 0, y = 0,
  weights = {},              -- per role: overrides of the preset weights
}

local function fill(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      if type(v) == "table" then dst[k] = {} fill(dst[k], v) else dst[k] = v end
    end
  end
  return dst
end

--- The gear-scoring role is PER CHARACTER (db.char), never the profile: the profile is shared by every character
-- on the account, and one Tank pick on an alt scored the shaman's loot "+3.7 for tank" (Sean 2026-10-02). The old
-- profile.atlas.role is left alone and never read.
function A.roleCfg()
  local c = HH.db and HH.db.char
  if not c then A.roleFallback = A.roleFallback or {} return A.roleFallback end
  c.atlas = c.atlas or {}
  return c.atlas
end
function A.Role() return A.roleCfg().role or "auto" end
function A.SetRole(r) A.roleCfg().role = r end

function A.cfg()
  local p = HH.db and HH.db.profile
  if not p then return fill({}, A.DEFAULTS) end
  p.atlas = p.atlas or {}
  if A.filled ~= p.atlas then
    p.atlas._filled = nil   -- written by the first build, never read again
    fill(p.atlas, A.DEFAULTS)
    A.filled = p.atlas
  end
  return p.atlas
end

-- ------------------------------------------------------------------------------------------------ safe values
function A.isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
function A.num(v) if type(v) == "number" and not A.isSecret(v) then return v end end
function A.str(v) if type(v) == "string" and not A.isSecret(v) then return v end end
--- v when it is safe to compare or test, nil when it is secret. On this client even `secret == nil` throws.
function A.plain(v) if A.isSecret(v) then return nil end return v end

--- fn(...) without ever throwing; every return handed back. Missing function = nothing.
function A.call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local function pack(ok, ...) if ok then return ... end end
  return pack(pcall(fn, ...))
end

--- Function at a dotted path off _G ("C_Item.GetItemInfo"), or nil.
function A.fn(path)
  local cur = _G
  for piece in path:gmatch("[^%.]+") do
    if type(cur) ~= "table" then return nil end
    cur = rawget(cur, piece)
    if cur == nil then return nil end
  end
  if type(cur) == "function" then return cur end
end

function A.now() return (date and date("%Y-%m-%d %H:%M")) or "" end

--- "Name-Realm" of this character: sets and wishlists are kept per character.
function A.charKey()
  local name = A.str(A.call(UnitName, "player")) or "?"
  local realm = A.str(A.call(rawget(_G, "GetRealmName"))) or "?"
  return name .. "-" .. realm
end

function A.playerLevel() return A.num(A.call(UnitLevel, "player")) or 1 end
function A.playerClass()
  local _, class = A.call(UnitClass, "player")
  return A.str(class) or "WARRIOR"
end
function A.playerFaction()
  local f = A.str(A.call(rawget(_G, "UnitFactionGroup"), "player"))
  if f == "Horde" then return "H" elseif f == "Alliance" then return "A" end
end

-- ------------------------------------------------------------------------------------------------ items
--- itemID out of a link or an "item:123" string. A secret link gives nil.
function A.ItemIDFromLink(link)
  if type(link) == "number" then return A.num(link) end
  link = A.str(link)
  if not link then return nil end
  local id = link:match("item:(%d+)")
  return id and tonumber(id) or nil
end

A.pending = {}   -- itemIDs asked of the server, not yet answered

--- What the client knows about an item right now, or nil (then the data was requested and a redraw follows on
-- GET_ITEM_INFO_RECEIVED). Never blocks.
function A.ItemInfo(item)
  local id = A.ItemIDFromLink(item)
  if not id then return nil end
  local get = A.fn("C_Item.GetItemInfo") or rawget(_G, "GetItemInfo")
  local name, link, quality, ilvl, minLevel, itype, subType, _, equipLoc, icon, price, classID, subClassID
  if type(get) == "function" then
    name, link, quality, ilvl, minLevel, itype, subType, _, equipLoc, icon, price, classID, subClassID = A.call(get, (A.str(item) and item:find("item:", 1, true)) and item or id)
  end
  if not A.str(name) then
    if not A.pending[id] then
      A.pending[id] = true
      A.call(A.fn("C_Item.RequestLoadItemDataByID"), id)
    end
    -- the instant call answers without the server: enough for slot and icon
    local inst = A.fn("C_Item.GetItemInfoInstant") or rawget(_G, "GetItemInfoInstant")
    local _, t, st, loc, ic, cid, scid = A.call(inst, id)
    if A.str(loc) or A.num(ic) then
      return { id = id, partial = true, equipLoc = A.str(loc), icon = ic, type = A.str(t), subType = A.str(st), classID = A.num(cid), subClassID = A.num(scid) }
    end
    return nil
  end
  A.pending[id] = nil
  return { id = id, name = name, link = A.str(link), quality = A.num(quality) or 1, ilvl = A.num(ilvl) or 0,
    minLevel = A.num(minLevel) or 0, type = A.str(itype), subType = A.str(subType), equipLoc = A.str(equipLoc) or "",
    icon = icon, price = A.num(price) or 0, classID = A.num(classID), subClassID = A.num(subClassID) }
end

function A.QualityColor(q)
  local c = A.QUALITY[A.num(q) or 1] or A.QUALITY[1]
  return c[1], c[2], c[3]
end
