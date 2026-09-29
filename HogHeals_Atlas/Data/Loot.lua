-- Curated drops: Curated[dungeonKey][bossName] = { itemID, ... }. Badge in the window: "reported".
--
-- EMPTY ON PURPOSE. Forever changed the old tables and hides new item data, so nothing goes in here until a drop
-- was seen in play or reported by two independent sources. Item ids are never written from memory.
-- Filled by dev/atlas_import.py from a CSV (dungeon_key,boss_name,item_id,source).
local A = HogHealsAtlas
A.Data = A.Data or {}
A.Data.Curated = {}
