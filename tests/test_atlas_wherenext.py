# HogTron UI Atlas: "Where next" - dungeons, quests and zones for your level, nearest first.
import pytest

from atlas_helpers import boot, errors, vals

WN = "HogHealsAtlas.WhereNext"

LOG = """
LOGQ = {
  { title = "Wailing Caverns", header = true },
  { title = "Leaders of the Fang", level = 22, id = 914, objectives = { { text = "Gem of Cobrahn: 1/1", done = true }, { text = "Gem of Anacondra: 0/1", done = false } } },
  { title = "The Barrens", header = true },
  { title = "Deviate Hides", level = 17, id = 1486, complete = true, objectives = { { text = "Deviate Hide: 20/20", done = true } } },
  { title = "Plainstrider Menace", level = 12, id = 844, objectives = {} },
  { title = "Ashenvale", header = true },
  { title = "Raene's Cleansing", level = 24, id = 1001, objectives = {} },
}
function FakeLog()
  local out, zone = {}, nil
  for _, q in ipairs(LOGQ) do
    if q.header then zone = q.title else
      out[#out + 1] = { title = q.title, level = q.level, id = q.id, zone = zone, objectives = q.objectives, complete = q.complete }
    end
  end
  return out
end
HogHealsQuests = HogHealsQuests or {}
HogHealsQuests.Data = HogHealsQuests.Data or {}
HogHealsQuests.Data.List = FakeLog
function GetRealZoneText() return "The Barrens" end
"""


@pytest.fixture
def wn(lua):
    boot(lua, extra=LOG)
    lua.execute("MockUnits.player.level = 20")
    return lua


def keys(lua, code):
    return [r["dungeon"]["key"] for r in vals(lua.eval(code))]


def test_dungeons_that_fit_come_nearest_first(wn):
    ks = keys(wn, f"{WN}.Dungeons()")
    assert ks[0] == "wc"                                   # Barrens, 17-24: green at 20, same zone
    assert "rfc" not in ks and "sfk" not in ks            # outgrown / too low are left out
    assert ks.index("lordaeron") < ks.index("vc")         # Alliance's Deadmines ranks after a Horde dungeon over the sea
    first = vals(wn.eval(f"{WN}.Dungeons()"))[0]
    assert first["distance"] == 0 and first["band"] == "green" and first["foreign"] is False
    assert "rfc" in keys(wn, f"{WN}.Dungeons({{ all = true }})")
    assert errors(wn) == []


def test_named_drops_only_what_you_can_wear_with_what_you_have_now(wn):
    named = vals(wn.eval(f"{WN}.NamedFor('wc', 'SHAMAN', 20, 24)"))
    names = [n["name"] for n in named]
    assert "Serpent's Shoulders" in names                  # leather: a shaman wears it
    assert "Mutant Scale Breastplate" not in names         # mail: not before 40
    shoulders = [n for n in named if n["name"] == "Serpent's Shoulders"][0]
    assert shoulders["look"] == "empty slot" and shoulders["boss"] == "Lady Anacondra" and shoulders["slot"] == "Shoulder"
    priest = [n["name"] for n in vals(wn.eval(f"{WN}.NamedFor('wc', 'PRIEST', 20, 24)"))]
    assert "Serpent's Shoulders" not in priest and "Deep Fathom Ring" in priest
    # a worn piece under the dungeon's level says so; one above it is not flagged
    wn.execute("""
      ITEMS[1005] = { "Copper Ring", 2, 12, 10, "Armor", "Miscellaneous", "INVTYPE_FINGER", 4, 0, { "Copper Ring", "+2 Stamina" } }
      ITEMS[1007] = { "Elder's Crown", 4, 50, 45, "Armor", "Cloth", "INVTYPE_HEAD", 4, 1, { "Elder's Crown" } }
      function GetInventoryItemLink(u, slot) if slot == 11 or slot == 12 then return ItemLink(1005) elseif slot == 1 then return ItemLink(1007) end end
    """)
    named = {n["name"]: n for n in vals(wn.eval(f"{WN}.NamedFor('wc', 'SHAMAN', 20, 24)"))}
    assert named["Deep Fathom Ring"]["look"] == "yours is item level 12"
    # a head piece from Gnomeregan vs a level-50 crown: nothing to chase
    gn = {n["name"]: n for n in vals(wn.eval(f"{WN}.NamedFor('gnomer', 'SHAMAN', 20, 38)"))}
    assert gn["Electromagnetic Gigaflux Reactivator"]["look"] is None


def test_quest_log_by_zone_here_first_ready_first(wn):
    groups = vals(wn.eval(f"{WN}.Quests()"))
    assert [g["zone"] for g in groups][0] == "The Barrens" and groups[0]["here"] is True
    q = vals(groups[0]["quests"])
    assert q[0]["title"] == "Deviate Hides" and q[0]["ready"] is True
    assert q[1]["title"] == "Plainstrider Menace" and q[1]["band"] == "grey"           # level 12 at 20: outgrown
    asv = [g for g in groups if g["zone"] == "Ashenvale"][0]
    assert vals(asv["quests"])[0]["band"] == "orange"                                   # level 24 at 20
    assert errors(wn) == []


def test_zones_at_your_level_nearest_first(wn):
    zs = vals(wn.eval(f"{WN}.Zones()"))
    names = [z["zone"]["name"] for z in zs]
    assert names[0] == "The Barrens" and zs[0]["distance"] == 0
    assert sorted(names[1:3]) == ["Ashenvale", "Stonetalon Mountains"]                 # next door, both green at 20
    assert zs[1]["distance"] == 1 and zs[2]["distance"] == 1
    bar = zs[0]
    assert "Wailing Caverns" in vals(bar["dungeons"]) and "Razorfen Kraul" in vals(bar["dungeons"])
    # the other side's land ranks after everything on your own side at the same distance
    west = [z for z in zs if z["zone"]["name"] == "Westfall"][0]
    assert west["foreign"] is True and names.index("Westfall") > names.index("Silverpine Forest")


def test_rows_say_and_slash(wn):
    rows = vals(wn.eval(f"{WN}.Rows()"))
    texts = [r["text"] for r in rows]
    assert texts[0].startswith("Level 20, The Barrens")
    assert "Dungeons for you" in texts and "Your quest log, by zone" in texts and "Zones at your level, nearest first" in texts
    wc = [r for r in rows if r["key"] == "wc"]
    assert wc[0]["text"] == "Wailing Caverns" and any("old list" == r["right"] for r in wc)
    assert any("quests in your log" in r["text"] for r in wc)
    say = vals(wn.eval(f"{WN}.Say()"))
    assert say[0].startswith("Where next (level 20): Wailing Caverns (17-24, right for you, here)")
    assert any("1 quest(s) ready to turn in, first in The Barrens" in l for l in say)
    assert any("Nearest zone for you: The Barrens" in l for l in say)
    wn.execute('HogHeals:SlashCommand("next say")')
    assert any("Where next (level 20)" in m for m in vals(wn.eval("MockLog.chat")))
    assert errors(wn) == []


def test_window_opens_on_where_next_and_a_dungeon_row_jumps_to_it(wn):
    wn.execute("HogHealsAtlas.Window.Show('next')")
    assert wn.eval("HogHealsAtlas.Window.tab") == "next"
    assert wn.eval("HogHealsAtlas.Window.tabButtons.next ~= nil")                       # first tab in the bar
    n = wn.eval("#HogHealsAtlas.Window.lists.next.data")
    assert n > 5
    wn.execute("""
      local L = HogHealsAtlas.Window.lists.next
      for _, r in ipairs(L.data) do if r.key == "wc" then L.opts.onClick(r) break end end
    """)
    assert wn.eval("HogHealsAtlas.Window.tab") == "dungeons" and wn.eval("HogHealsAtlas.Window.dungeon") == "wc"
    wn.execute('HogHeals:SlashCommand("next")')
    assert wn.eval("HogHealsAtlas.Window.tab") == "next"
    assert errors(wn) == []
