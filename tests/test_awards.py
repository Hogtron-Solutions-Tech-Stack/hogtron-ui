"""HogTron Awards (HogTron_Awards/): end-of-run awards. Data rules, metric collection on Forever's terms (meter RANKS,
own counters, no secret maths), winner resolution, stage selection, the HTR_AWD addon-message codec and the group
flow (3 s window, solo degrade), run-end triggers, prompt/stage timers, settings."""
import pytest

A = "HogTronAwards"

METER = '''
-- Blizzard meter with secret amounts; lists are ranked best-first like the client returns them
MockSetSecrets(true)
HH_meter = {}
function MockMeter(mode, seg, names)
  HH_meter[mode .. ":" .. seg] = names
end
Enum = Enum or {}
Enum.DamageMeterType = { DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4, Interrupts = 5, Dispels = 6,
  DamageTaken = 7, AvoidableDamageTaken = 8, Deaths = 9, EnemyDamageTaken = 10 }
Enum.DamageMeterSessionType = { Overall = 0, Current = 1, Expired = 2 }
local modeName, segName = {}, {}
for k, v in pairs(Enum.DamageMeterType) do modeName[v] = k end
for k, v in pairs(Enum.DamageMeterSessionType) do segName[v] = k end
C_DamageMeter = { GetCombatSessionFromType = function(st, mt)
  local names = HH_meter[modeName[mt] .. ":" .. segName[st]] or {}
  local src = {}
  for i, n in ipairs(names) do src[i] = { name = n .. "-Nightslayer", classFilename = "WARRIOR", totalAmount = MockSecret(1000 - i) } end
  return { combatSources = src, totalAmount = MockSecret(5000), maxAmount = MockSecret(999) }
end }
'''


@pytest.fixture
def aw(lua):
    lua.execute(METER)
    lua.execute('''
      HH_sent = {}
      C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
                     SendAddonMessage = function(p, m, ch) HH_sent[#HH_sent + 1] = { prefix = p, msg = m, channel = ch } return 0 end }
      GetServerTime = function() return 1760000000 end
      MockState.money = 10000
      GetMoney = function() return MockState.money end
      -- the client functions the module post-hooks for the player's own actions
      function DoEmote() end; function JumpOrAscendStart() end; function RollOnLoot() end; function SetRaidTarget() end
      function SendChatMessage() end
    ''')
    lua.load_addon("HogTronUI")
    lua.load_addon("HogTron_Awards")
    lua.player_login()
    lua.execute('wipe(HogHeals.errors)')
    return lua


def lst(v):
    return list(v.values()) if v is not None and hasattr(v, "values") else []


def errors(lua):
    return [e["msg"] for e in lst(lua.eval('HogHeals.errors'))]


def party(lua, n=5, instance="Wailing Caverns", itype="party"):
    lua.execute(f'''
      MockSetGroup({n}, false)
      GetInstanceInfo = function() return "{instance}", "{itype}", 1, "", 5, 0, false, 43, 5 end
      MockFire("PLAYER_ENTERING_WORLD", false, false)
    ''')


# ================================================================== data
def test_seventy_five_awards_split_honors_and_roasts(aw):
    awards = lst(aw.eval(f'{A}.LIST'))
    kinds = [a["kind"] for a in awards]
    assert len(awards) == 75 and kinds.count("honor") == 38 and kinds.count("roast") == 37
    ids = [a["id"] for a in awards]
    assert len(set(ids)) == 75


def test_every_award_is_complete_and_points_at_a_real_metric(aw):
    bad = aw.eval(f'''(function()
      local bad = {{}}
      for _, a in ipairs({A}.LIST) do
        local ok = {A}.Metrics.DEFS[a.metric] ~= nil and (a.dir == "high" or a.dir == "low") and {A}.EMOTES[a.emote] ~= nil
          and type(a.flavor) == "string" and #a.flavor > 10 and type(a.icon) == "string" and #a.icon > 10
          and not a.flavor:find("|", 1, true) and not a.name:find("|", 1, true)
          and (a.ctx == "any" or (type(a.ctx) == "table" and #a.ctx > 0))
        if not ok then bad[#bad + 1] = a.id end
      end
      return table.concat(bad, ",") end)()''')
    assert bad == ""


def test_seans_seed_names_are_all_in(aw):
    names = {a["name"] for a in lst(aw.eval(f'{A}.LIST'))}
    seeds = ["MVP", "Boar Slayer", "The Shield Wall", "Lifeline", "Executioner", "Clutch Rez", "Mana Monk", "Dispel Daddy",
             "Interrupt King", "Hog Wild", "Sow Many Heals", "Boar Mitzvah", "Oinkspiration", "Trotter's Pride",
             "Pigskin Protector", "Mythic Mover", "Objective Pig", "Pest Control", "The Wall",
             "Floor Inspector", "Pig Pen", "Loot Goblin", "Trough Lord", "Oinkmentum", "Lipstick", "Sow Low", "AFK Hogdown",
             "Wipe Lord", "Pacifist", "Magnet", "Pork Belly", "Boar of Hearts", "Breadcrumbs", "Bacon Bits",
             "Charcuterie Board", "Snoutburned", "Pork Chop", "Pigeon-Toed"]
    assert [s for s in seeds if s not in names] == []


def test_eligibility_by_context(aw):
    def el(i, ctx):
        return aw.eval(f'{A}.Eligible({A}.BY_ID.{i}, "{ctx}")')
    assert el("executioner", "bg") and not el("executioner", "dungeon")
    assert el("boar_slayer", "raid") and el("boar_slayer", "dungeon") and not el("boar_slayer", "bg")
    assert el("mvp", "bg") and el("mvp", "dungeon") and el("mvp", "raid")


def test_icon_prompt_fills_the_template(aw):
    p = aw.eval(f'{A}.IconPrompt({A}.BY_ID.lifeline)')
    assert "heartbeat line" in p and "{subject}" not in p and "magenta" in p and "bronze" in p


# ================================================================== codec
def test_end_message_round_trip(aw):
    m = aw.eval(f'{A}.Sync.EncodeEnd("Hog-1760000000", "raid")')
    d = aw.eval(f'{A}.Sync.Decode("{m}")')
    assert m == "1|E|Hog-1760000000|raid" and d["kind"] == "E" and d["runId"] == "Hog-1760000000" and d["ctx"] == "raid"


def test_nominations_round_trip_with_decimals_and_no_zeros(aw):
    out = lst(aw.eval(f'{A}.Sync.EncodeNominations("r1", {{ jumps = 42, readyTime = 2.5, lootGold = 12345, potions = 0 }})'))
    assert len(out) == 1
    d = aw.eval(f'{A}.Sync.Decode([[{out[0]}]])')
    c = dict(d["counts"].items())
    assert c == {"jumps": 42, "readyTime": 2.5, "lootGold": 12345}


def test_big_nomination_splits_under_255_bytes_and_merges_back(aw):
    aw.execute(f'''
      HH_counts = {{}}
      for i, k in ipairs({A}.Sync.Keys()) do HH_counts[k] = 100000 + i end
      HH_msgs = {A}.Sync.EncodeNominations("Somebody-1760000000", HH_counts)
      HH_back = {{}}
      for _, m in ipairs(HH_msgs) do local d = {A}.Sync.Decode(m) for k, v in pairs(d.counts) do HH_back[k] = v end end
    ''')
    msgs = lst(aw.eval('HH_msgs'))
    assert len(msgs) > 1 and all(len(m) <= 255 for m in msgs)
    assert aw.eval(f'(function() for k, v in pairs(HH_counts) do if HH_back[k] ~= v then return k end end return "same" end)()') == "same"


@pytest.mark.parametrize("msg", ["2|E|x|raid", "1|E|x|world", "1|E||raid", "1|N|r1|x|1=2", "garbage", "1|Q|x", "1|E|" + "x" * 300 + "|raid"])
def test_decode_rejects_bad_messages(aw, msg):
    assert aw.eval(f'({A}.Sync.Decode([[{msg}]]))') is None


def test_every_self_metric_has_a_frozen_code(aw):
    keys = lst(aw.eval(f'{A}.Sync.Keys()'))
    n_self = aw.eval(f'(function() local n = 0 for _, d in pairs({A}.Metrics.DEFS) do if d.src == "self" then n = n + 1 end end return n end)()')
    assert keys == sorted(keys) and len(keys) == n_self


# ================================================================== metrics: meter ranks
def test_meter_ranks_become_scores_and_absent_members_score_zero(aw):
    party(aw)
    aw.execute('MockMeter("DamageDone", "Overall", { "Unit2", "Hognificent", "Unit1" })')
    aw.execute(f'HH_d = {{}}; {A}.Metrics.ReadMeter(HH_d, {A}.Metrics.Roster())')
    assert aw.eval('HH_d.Unit2.damage') == 5 and aw.eval('HH_d.Hognificent.damage') == 4 and aw.eval('HH_d.Unit1.damage') == 3
    assert aw.eval('HH_d.Unit3.damage') == 0 and aw.eval('HH_d.Unit4.damage') == 0     # did no damage at all
    assert errors(aw) == []                                                              # secret amounts never touched


def test_no_meter_still_collects_from_counters(aw):
    party(aw, 3)
    aw.execute('C_DamageMeter = nil')
    aw.execute(f'HH_d, HH_n = {A}.Metrics.Collect({{ Unit1 = {{ jumps = 50 }} }}, "dungeon")')
    assert aw.eval('HH_d.Unit1.jumps') == 50 and aw.eval('HH_d.Unit1.damage') is None


def test_roles_inferred_from_meter_when_group_tool_has_none(aw):
    party(aw)
    aw.execute('''
      MockMeter("HealingDone", "Overall", { "Unit3", "Unit1" })
      MockMeter("DamageDone", "Overall", { "Unit1", "Unit2", "Hognificent", "Unit4", "Unit3" })
      MockMeter("DamageTaken", "Overall", { "Unit4", "Unit1", "Unit2" })
    ''')
    aw.execute(f'HH_d, HH_n, HH_r = {A}.Metrics.Collect({{}}, "dungeon")')
    assert aw.eval('HH_r.Unit3') == "healer" and aw.eval('HH_r.Unit4') == "tank" and aw.eval('HH_r.Unit1') == "dps"


def test_assigned_roles_win_over_inference(aw):
    party(aw)
    aw.execute('UnitGroupRolesAssigned = function(u) if u == "party2" then return "TANK" end return "NONE" end')
    aw.execute('MockMeter("DamageTaken", "Overall", { "Unit4", "Unit2" })')
    aw.execute(f'HH_d, HH_n, HH_r = {A}.Metrics.Collect({{}}, "dungeon")')
    assert aw.eval('HH_r.Unit2') == "tank" and aw.eval('HH_r.Unit4') == "dps"


# ================================================================== metrics: own counters
def own_spells(lua, names):
    book = ", ".join(f'[{900 + i}] = "{n}"' for i, n in enumerate(names))
    lua.execute(f'HH_book = {{ {book} }}; C_Spell.GetSpellName = function(id) return HH_book[id] end')
    return {n: 900 + i for i, n in enumerate(names)}


def test_own_casts_feed_the_counters(aw):
    party(aw)
    ids = own_spells(aw, ["Resurrection", "Taunt", "Polymorph", "Major Healing Potion", "Drink", "Food", "Flash Heal"])
    def cast(n): aw.execute(f'MockFire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", {ids[n]})')
    cast("Resurrection")
    aw.execute('MockState.inCombat = true')
    cast("Resurrection")
    aw.execute('MockState.inCombat = false')
    for n in ("Taunt", "Polymorph", "Major Healing Potion", "Drink", "Food", "Flash Heal", "Flash Heal"):
        cast(n)
    aw.execute('MockFire("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast", 906)')         # someone else's cast: ignored
    c = dict(aw.eval(f'{A}.Metrics.SelfSnapshot()').items())
    assert c["rezOOC"] == 1 and c["rezCombat"] == 1 and c["taunts"] == 1 and c["ccCast"] == 1 and c["potions"] == 1
    assert c["drinks"] == 1 and c["foodDrink"] == 2 and c["foodKinds"] == 1 and c["castsTotal"] == 9 and c["uniqueSpells"] == 7


def test_loot_lines_count_only_my_loot_by_quality(aw):
    party(aw)
    aw.execute('C_Item = C_Item or {}; C_Item.GetItemQualityByID = function(id) return ({ [1] = 0, [2] = 1, [3] = 4 })[id] end')
    for msg in ['You receive loot: |cnIQ0:|Hitem:1::::|h[Junk]|h|r', 'You receive loot: |cnIQ1:|Hitem:2::::|h[Cloth]|h|r',
                'You receive loot: |cnIQ4:|Hitem:3::::|h[Epic]|h|r', 'Unit1 receives loot: |Hitem:3::::|h[Epic]|h|r']:
        aw.execute(f'MockFire("CHAT_MSG_LOOT", [[{msg}]])')
    c = dict(aw.eval(f'{A}.Metrics.SelfSnapshot()').items())
    assert c["lootItems"] == 3 and c["lootJunk"] == 1 and c["lootRare"] == 1


def test_deaths_time_dead_and_corpse_runs(aw):
    party(aw)
    aw.execute('MockAdvance(30); MockFire("PLAYER_DEAD"); MockAdvance(20)')
    aw.execute('UnitIsDeadOrGhost = function() return true end; MockFire("PLAYER_ALIVE")')   # released: a ghost, not alive
    aw.execute('MockAdvance(40); UnitIsDeadOrGhost = function() return false end; MockFire("PLAYER_UNGHOST")')
    c = dict(aw.eval(f'{A}.Metrics.SelfSnapshot()').items())
    assert c["selfDeaths"] == 1 and c["firstDeath"] == 30 and c["timeDead"] == 60 and c["ghostRuns"] == 1


def test_wipe_deaths_and_swine_dive(aw):
    party(aw)
    aw.execute('MockFire("ENCOUNTER_START", 585, "Lady Anacondra", 1, 5); MockAdvance(10); MockFire("PLAYER_DEAD")')
    aw.execute('MockFire("ENCOUNTER_END", 585, "Lady Anacondra", 1, 5, 0)')
    c = dict(aw.eval(f'{A}.Metrics.SelfSnapshot()').items())
    assert c["wipeDeaths"] == 1 and c["earlyBossDeaths"] == 1


def test_emotes_jumps_rolls_marks_through_post_hooks(aw):
    party(aw)
    aw.execute('''
      DoEmote("THANK"); DoEmote("kiss"); DoEmote("DANCE")
      JumpOrAscendStart(); JumpOrAscendStart()
      RollOnLoot(1, 1); RollOnLoot(2, 2); MockFire("LOOT_ITEM_ROLL_WON", "x", 1, 1, 90)
      SetRaidTarget("target", 8)
    ''')
    c = dict(aw.eval(f'{A}.Metrics.SelfSnapshot()').items())
    assert c["emotes"] == 3 and c["emotesPositive"] == 1 and c["emotesRomantic"] == 1 and c["jumps"] == 2
    assert c["needRolls"] == 1 and c["rollsLost"] == 1 and c["marksSet"] == 1


def test_money_gained_and_spent(aw):
    party(aw)
    aw.execute('MockState.money = 15000; MockFire("PLAYER_MONEY"); MockState.money = 12000; MockFire("PLAYER_MONEY")')
    c = dict(aw.eval(f'{A}.Metrics.SelfSnapshot()').items())
    assert c["lootGold"] == 5000 and c["goldSpent"] == 3000


def test_ticker_counts_afk_and_moving_time(aw):
    party(aw)
    aw.execute('MockUnits.player.afk = true; MockFire("PLAYER_STARTED_MOVING")')
    aw.execute('for i = 1, 5 do MockAdvance(1) end')
    c = dict(aw.eval(f'{A}.Metrics.SelfSnapshot()').items())
    assert c["afkTime"] >= 5 and c["movingTime"] >= 5


def test_ready_check_average_and_no_death_means_no_first_death(aw):
    party(aw)
    aw.execute('MockFire("READY_CHECK"); MockAdvance(2); MockFire("READY_CHECK_CONFIRM", "player", true)')
    aw.execute('MockFire("READY_CHECK"); MockAdvance(4); MockFire("READY_CHECK_CONFIRM", "player", true)')
    c = dict(aw.eval(f'{A}.Metrics.SelfSnapshot()').items())
    assert c["readyTime"] == 3 and "firstDeath" not in c and c["latency"] == 250


def test_pulled_before_the_tank(aw):
    party(aw)
    aw.execute('''UnitGroupRolesAssigned = function(u) if u == "party1" then return "TANK" end return "NONE" end
      UnitAffectingCombat = function(u) return u ~= "party1" end
      MockFire("PLAYER_REGEN_DISABLED")''')
    assert aw.eval(f'{A}.Metrics.SelfSnapshot().tankPulls') == 1


# ================================================================== resolve
def winners(lua, data, names, roles, ctx="dungeon", enabled="nil"):
    lua.execute(f'HH_w = {A}.Resolve.Winners({data}, {names}, {roles}, "{ctx}", {enabled})')
    return {w["award"]["id"]: (w["name"], w["value"]) for w in lst(lua.eval('HH_w'))}


def test_highest_wins_and_ties_go_alphabetical(aw):
    w = winners(aw, '{ Zed = { jumps = 30 }, Amy = { jumps = 30 }, Bob = { jumps = 12 } }', '{ "Amy", "Bob", "Zed" }', '{}')
    assert w["pigeon_toed"] == ("Amy", 30)


def test_lowest_wins_for_low_awards_and_role_filter_applies(aw):
    w = winners(aw, '{ Amy = { damage = 3 }, Bob = { damage = 0 }, Cat = { damage = 1 }, Dan = { damage = 2 } }',
                '{ "Amy", "Bob", "Cat", "Dan" }', '{ Amy = "dps", Bob = "healer", Cat = "dps", Dan = "tank" }')
    assert w["pacifist"] == ("Cat", 1)                    # Bob did less but is the healer
    assert w["tusk_master"] == ("Amy", 3)


def test_minimum_thresholds_hold(aw):
    w = winners(aw, '{ Amy = { jumps = 9 }, Bob = { afkTime = 12 } }', '{ "Amy", "Bob" }', '{}')
    assert "pigeon_toed" not in w and "afk_hogdown" not in w


def test_tank_only_and_non_tank_awards(aw):
    w = winners(aw, '{ Amy = { taken = 5 }, Bob = { taken = 4 }, Cat = { taken = 1 } }', '{ "Amy", "Bob", "Cat" }',
                '{ Amy = "tank", Bob = "dps", Cat = "healer" }')
    assert w["shield_wall"] == ("Amy", 5) and w["magnet"] == ("Bob", 4)


def test_context_and_settings_filter_awards(aw):
    data = '{ Amy = { killingBlows = 9, damage = 2, jumps = 40 }, Bob = { damage = 1 } }'
    w = winners(aw, data, '{ "Amy", "Bob" }', '{}', ctx="dungeon")
    assert "executioner" not in w
    w = winners(aw, data, '{ "Amy", "Bob" }', '{}', ctx="bg")
    assert w["executioner"] == ("Amy", 9)
    aw.execute(f'{A}.Cfg().roasts = false')
    w = winners(aw, data, '{ "Amy", "Bob" }', '{}', ctx="dungeon", enabled=f'{A}.AwardEnabled')
    assert "pigeon_toed" not in w and "tusk_master" in w


def test_derived_mvp_survivor_clean_feet(aw):
    aw.execute(f'''HH_d = {{ Amy = {{ damage = 3, healing = 0, deaths = 0, taken = 2, avoidable = 0 }},
                             Bob = {{ damage = 2, healing = 3, deaths = 1, taken = 3, avoidable = 2 }} }}
      {A}.Metrics.Derive(HH_d, {{ "Amy", "Bob" }})''')
    assert aw.eval('HH_d.Amy.mvp') == 3 and aw.eval('HH_d.Bob.mvp') == 4
    assert aw.eval('HH_d.Amy.survivorTaken') == 2 and aw.eval('HH_d.Bob.survivorTaken') is None
    assert aw.eval('HH_d.Amy.cleanFeet') == 3 and aw.eval('HH_d.Bob.greaseFire') == 3


STAGE_DATA = '''{
  Amy = { mvp = 9, damage = 5, jumps = 40, lootItems = 9, healing = 0 },
  Bob = { mvp = 7, healing = 5, deaths = 3, lootJunk = 4, damage = 1 },
  Cat = { mvp = 5, interrupts = 4, afkTime = 300, taunts = 6, damage = 2 },
  Dan = { mvp = 4, dispels = 3, foodDrink = 12, damage = 3 },
  Eve = { mvp = 2, absorbs = 3, uiErrors = 40, damage = 4 },
}'''


def build_stage(lua, seed="run-A", slots=4):
    lua.execute(f'''
      HH_w = {A}.Resolve.Winners({STAGE_DATA}, {{ "Amy", "Bob", "Cat", "Dan", "Eve" }}, {{}}, "dungeon")
      HH_s = {A}.Resolve.Stage(HH_w, "{seed}", {{ slots = {slots}, roasts = true }})
    ''')
    s = lua.eval('HH_s')
    head = (s["headline"]["award"]["id"], s["headline"]["name"])
    others = [(o["award"]["id"], o["name"], o["award"]["kind"]) for o in lst(s["others"])]
    return head, others, len(lst(s["also"]))


def test_stage_headline_is_mvp_and_everyone_appears_once(aw):
    head, others, _ = build_stage(aw)
    assert head == ("mvp", "Amy")
    people = [head[1]] + [o[1] for o in others]
    awards = [head[0]] + [o[0] for o in others]
    assert len(others) == 4 and len(set(people)) == 5 and len(set(awards)) == 5
    kinds = [o[2] for o in others]
    assert kinds.count("honor") == 2 and kinds.count("roast") == 2


def test_stage_is_the_same_for_the_same_seed(aw):
    assert build_stage(aw, "run-A") == build_stage(aw, "run-A")
    draws = {tuple(build_stage(aw, f"run-{i}")[1]) for i in range(8)}
    assert len(draws) > 1                                  # different runs draw differently


def test_solo_stage_is_headline_only(aw):
    head, others, also = build_stage(aw, slots=0)
    assert head[0] == "mvp" and others == [] and also > 0


# ================================================================== group flow
def test_run_starts_on_entering_an_instance_and_resets_counters(aw):
    aw.execute(f'{A}.Metrics.self = nil')
    party(aw, 5, "Wailing Caverns", "party")
    assert aw.eval(f'{A}.run.ctx') == "dungeon" and aw.eval(f'{A}.run.instance') == "Wailing Caverns"
    assert aw.eval(f'{A}.Metrics.self.counts.jumps') == 0
    party(aw, 10, "Molten Core", "raid")
    assert aw.eval(f'{A}.run.ctx') == "raid"


def test_group_window_merges_a_groupmates_counters_then_prompts(aw):
    party(aw, 3)
    aw.execute('JumpOrAscendStart()')
    assert aw.eval(f'{A}.EndRun("manual")') is True
    sent = [m["msg"] for m in lst(aw.eval('HH_sent'))]
    assert any(m.startswith("1|E|Hognificent-1760000000|dungeon") for m in sent) and any(m.startswith("1|N|") for m in sent)
    assert all(m["channel"] == "PARTY" and m["prefix"] == "HTR_AWD" for m in lst(aw.eval('HH_sent')))
    msg = aw.eval(f'{A}.Sync.EncodeNominations("Unit1-1760000001", {{ jumps = 77 }})[1]')
    aw.execute(f'MockFire("CHAT_MSG_ADDON", "HTR_AWD", [[{msg}]], "PARTY", "Unit1-Nightslayer")')
    assert aw.eval('HogTronAwardsPrompt == nil or not HogTronAwardsPrompt:IsShown()')   # still collecting
    aw.execute('MockAdvance(3)')
    assert aw.eval('HogTronAwardsPrompt:IsShown()')
    assert aw.eval(f'{A}.last.seed') == "Hognificent-1760000000"
    names = lst(aw.eval(f'{A}.last.names'))
    assert "Unit1" in names


def test_my_own_echo_is_ignored_and_bad_sender_payloads_too(aw):
    party(aw, 3)
    aw.execute(f'{A}.EndRun("manual")')
    msg = aw.eval(f'{A}.Sync.EncodeNominations("x", {{ jumps = 999 }})[1]')
    aw.execute(f'MockFire("CHAT_MSG_ADDON", "HTR_AWD", [[{msg}]], "PARTY", "Hognificent-Nightslayer")')
    aw.execute('MockFire("CHAT_MSG_ADDON", "HTR_AWD", "nonsense", "PARTY", "Unit1")')
    assert aw.eval(f'{A}.Sync.window.nominations.Hognificent.jumps') in (None, 0)
    assert aw.eval(f'{A}.Sync.window.nominations.Unit1') is None


def test_a_groupmates_end_message_ends_my_run_too(aw):
    party(aw, 3)
    aw.execute('MockFire("CHAT_MSG_ADDON", "HTR_AWD", "1|E|Unit1-1759999999|dungeon", "PARTY", "Unit1")')
    assert aw.eval(f'{A}.run.ended') is True and aw.eval(f'{A}.Sync.window ~= nil')
    aw.execute('MockAdvance(3)')
    assert aw.eval(f'{A}.last.seed') == "Hognificent-1760000000"   # seed = lowest run id seen; every client sees both


def test_solo_degrades_to_local_only_or_skips_by_setting(aw):
    aw.execute('GetInstanceInfo = function() return "Wailing Caverns", "party", 1, "", 5, 0, false, 43, 5 end; MockFire("PLAYER_ENTERING_WORLD")')
    ok = aw.eval(f'{{ {A}.EndRun("manual") }}')
    assert ok[1] is False and "solo" in ok[2]
    aw.execute(f'{A}.Cfg().solo = true; {A}.run = nil; MockFire("PLAYER_ENTERING_WORLD")')
    aw.execute('MockMeter("DamageDone", "Overall", { "Hognificent" }); MockMeter("HealingDone", "Overall", { "Hognificent" })')
    assert aw.eval(f'{A}.EndRun("manual")') is True
    assert aw.eval('#HH_sent') == 0 and aw.eval(f'{A}.Sync.window') is None          # nobody to tell, finished at once
    assert aw.eval(f'{A}.last.stage.headline.name') == "Hognificent" and aw.eval(f'#{A}.last.stage.others') == 0


# ================================================================== triggers
def test_last_boss_ends_the_run_other_bosses_do_not(aw):
    party(aw, 3)
    aw.execute('MockFire("ENCOUNTER_END", 585, "Lady Anacondra", 1, 5, 1)')
    assert not aw.eval(f'{A}.run.ended')
    aw.execute('MockFire("ENCOUNTER_END", 593, "Mutanus the Devourer", 1, 5, 0)')         # wipe on the last boss
    assert not aw.eval(f'{A}.run.ended')
    aw.execute('MockFire("ENCOUNTER_END", 593, "Mutanus the Devourer", 1, 5, 1)')
    assert aw.eval(f'{A}.run.ended') and aw.eval(f'{A}.run.reason') == "boss"


def test_every_boss_instances_need_all_of_them(aw):
    party(aw, 3, "Ragefire Chasm")
    for b in ("Oggleflint", "Taragaman the Hungerer", "Bazzalan"):
        aw.execute(f'MockFire("BOSS_KILL", 1, "{b}")')
    assert not aw.eval(f'{A}.run.ended')
    aw.execute('MockFire("BOSS_KILL", 1, "Jergosh the Invoker")')
    assert aw.eval(f'{A}.run.ended')


def test_lfg_reward_and_battleground_winner_end_runs(aw):
    party(aw, 3)
    aw.execute('MockFire("LFG_COMPLETION_REWARD")')
    assert aw.eval(f'{A}.run.reason') == "lfg"
    party(aw, 10, "Warsong Gulch", "pvp")
    aw.execute('GetBattlefieldWinner = function() return nil end; MockFire("UPDATE_BATTLEFIELD_SCORE")')
    assert not aw.eval(f'{A}.run.ended')
    aw.execute('GetBattlefieldWinner = function() return 1 end; MockFire("UPDATE_BATTLEFIELD_SCORE")')
    assert aw.eval(f'{A}.run.ended') and aw.eval(f'{A}.run.ctx') == "bg"


def test_probe_counts_trigger_events_and_records_refusals(lua):
    lua.execute(METER)
    lua.execute('MockUnknownEvents.CHALLENGE_MODE_COMPLETED = true')
    lua.load_addon("HogTronUI")
    lua.load_addon("HogTron_Awards")
    lua.player_login()
    party(lua, 3)
    lua.execute('MockFire("BOSS_KILL", 1, "Kresh"); MockFire("BOSS_KILL", 2, "Skum")')
    d = lua.eval('HogHeals.db.global.diag.awards')
    assert d["fired"]["BOSS_KILL"] == 2 and "Skum" in d["last"]["BOSS_KILL"]
    assert d["failed"] == "CHALLENGE_MODE_COMPLETED"
    lua.execute('MockLog.chat = {}; HogHeals:SlashCommand("awards probe")')
    assert any("BOSS_KILL fired 2" in l for l in lst(lua.eval('MockLog.chat')))


# ================================================================== UI + settings
def test_prompt_hides_after_60s_and_stage_after_45s(aw):
    party(aw, 3)
    aw.execute(f'{A}.EndRun("manual"); MockAdvance(3)')
    assert aw.eval('HogTronAwardsPrompt:IsShown()')
    aw.execute('MockAdvance(59)')                                        # shown at t=3 s, so still up at 62 s
    assert aw.eval('HogTronAwardsPrompt:IsShown()')
    aw.execute('MockAdvance(2)')                                         # 64 s: gone
    assert not aw.eval('HogTronAwardsPrompt:IsShown()')
    aw.execute(f'{A}.Preview()')
    assert aw.eval('HogTronAwardsStage:IsShown()')
    assert aw.eval('(function() for _, n in ipairs(UISpecialFrames) do if n == "HogTronAwardsStage" then return true end end end)()')
    aw.execute('MockAdvance(46)')
    assert not aw.eval('HogTronAwardsStage:IsShown()')


def test_click_on_background_dismisses(aw):
    aw.execute(f'{A}.Preview(); HogTronAwardsStage:GetScript("OnMouseDown")(HogTronAwardsStage, "LeftButton")')
    assert not aw.eval('HogTronAwardsStage:IsShown()')


def test_both_layouts_place_five_players_headline_centred(aw):
    for layout in ("arc", "corners"):
        p = lst(aw.eval(f'{A}.UI.Positions("{layout}", 1920, 1080)'))
        assert len(p) == 5 and p[0]["x"] == 0 and p[0]["scale"] == 1
        assert all(o["scale"] < 1 for o in p[1:])
    arc = lst(aw.eval(f'{A}.UI.Positions("arc", 1920, 1080)'))
    cor = lst(aw.eval(f'{A}.UI.Positions("corners", 1920, 1080)'))
    assert [(o["x"], o["y"]) for o in arc] != [(o["x"], o["y"]) for o in cor]


def test_models_play_the_awards_emote(aw):
    aw.execute(f'{A}.Preview()')
    slot = aw.eval('HogTronAwardsStage.slots[1]')
    assert slot.model.anim == aw.eval(f'{A}.EMOTES.cheer')           # MVP cheers
    assert aw.eval('HogTronAwardsStage.slots[1].icon._texture') == "Interface\\AddOns\\HogTron_Awards\\assets\\awards\\mvp"


def test_settings_tabs_and_per_award_toggle(aw):
    t = aw.eval('HogHeals.OptionsTable().args.Awards.args')
    honors = [k for k in t["honors"]["args"].keys()]
    roasts = [k for k in t["roasts"]["args"].keys()]
    assert len(honors) == 38 and len(roasts) == 38                      # 37 roasts + the "show roasts" switch
    t["roasts"]["args"]["magnet"]["set"](None, False)
    assert aw.eval(f'{A}.Cfg().disabled.magnet') is True and not aw.eval(f'{A}.AwardEnabled({A}.BY_ID.magnet)')
    assert set(t["general"]["args"]["layout"]["values"].keys()) == {"arc", "corners"}


def test_slash_commands_and_htr_alias(aw):
    aw.execute('HogHeals:SlashCommand("awards preview")')
    assert aw.eval('HogTronAwardsStage:IsShown()')
    aw.execute(f'{A}.UI.HideStage(); SlashCmdList.HOGTRON("awards preview")')
    assert aw.eval('HogTronAwardsStage:IsShown()') and aw.eval('SLASH_HOGTRON1') == "/htr"
    assert errors(aw) == []


def test_a_lone_entry_reads_number_one_not_last(aw):
    # 2026-10-15 mockup caught "#5 of 5 in dispels" for the only dispeller: scores were relative to the list length
    party(aw)
    aw.execute('MockMeter("Dispels", "Overall", { "Hognificent" })')
    aw.execute(f'HH_d, HH_n, HH_r = {A}.Metrics.Collect({{}}, "dungeon"); HH_w = {A}.Resolve.Winners(HH_d, HH_n, HH_r, "dungeon")')
    w = {x["award"]["id"]: x for x in lst(aw.eval('HH_w'))}
    assert w["dispel_daddy"]["name"] == "Hognificent" and w["dispel_daddy"]["detail"] == "#1 of 5 in dispels"



# ================================================================== real numbers on the cards (2026-10-15)
AMOUNTS = """
-- meter rows with amounts: secret values that THROW on compare / arithmetic, exactly like Forever
HH_amounts = {}
function MockMeterAmounts(mode, seg, rows) HH_amounts[mode .. ":" .. seg] = rows end
local base = C_DamageMeter.GetCombatSessionFromType
C_DamageMeter.GetCombatSessionFromType = function(st, mt)
  local s = base(st, mt)
  for k, rows in pairs(HH_amounts) do
    local mode, seg = k:match("^(.-):(.-)$")
    if Enum.DamageMeterType[mode] == mt and Enum.DamageMeterSessionType[seg] == st then
      s.combatSources = {}
      for i, r in ipairs(rows) do
        s.combatSources[i] = { name = r[1], totalAmount = MockSecret(r[2]), amountPerSecond = r[3] and MockSecret(r[3]) or nil,
          sourceGUID = r[4], isLocalPlayer = r[1] == "Hognificent" }
      end
    end
  end
  return s
end
"""

ROWS = """
MockMeterAmounts("HealingDone", "Overall", { { "Hognificent", 48210, 1240 }, { "Unit1", 2210, 60 } })
MockMeterAmounts("Dps", "Overall", { { "Unit2", 61300, 412 }, { "Unit1", 40100, 280 } })
MockMeterAmounts("DamageDone", "Overall", { { "Unit2", 61300, 412 }, { "Unit1", 40100, 280 }, { "Hognificent", 900, 6 } })
"""


def run_with_amounts(aw):
    party(aw)
    aw.execute(AMOUNTS)
    aw.execute(ROWS)
    aw.execute(f'HH_d, HH_n, HH_r = {A}.Metrics.Collect({{ Unit3 = {{ jumps = 61, lootGold = 48210, firstDeath = 95, selfDeaths = 1 }} }}, "dungeon")')
    aw.execute(f'HH_w = {A}.Resolve.Winners(HH_d, HH_n, HH_r, "dungeon")')
    # stat strings built from secret amounts are themselves SECRET strings (as on Forever); unwrap only to assert
    aw.execute('for _, w in ipairs(HH_w) do w.statPlain = w.stat and MockUnwrap(w.stat) end')
    out = {}
    for w in lst(aw.eval('HH_w')):
        d = dict(w.items())
        d["stat"] = d.get("statPlain")
        out[w["award"]["id"]] = d
    return out


def test_cards_carry_the_meters_real_numbers_without_any_maths_on_them(aw):
    w = run_with_amounts(aw)
    assert w["lifeline"]["name"] == "Hognificent" and w["lifeline"]["stat"] == "48210 healing (1240 HPS)"
    assert w["hog_wild"]["name"] == "Unit2" and w["hog_wild"]["stat"] == "412 DPS"
    assert w["tusk_master"]["stat"] == "61300 damage (412 DPS)"
    assert w["lifeline"]["detail"] == "#1 of 5 in healing done"            # the rank stays in the hover
    assert errors(aw) == []                                                 # secrets were formatted, never compared


def test_counted_awards_show_their_own_numbers(aw):
    w = run_with_amounts(aw)
    assert w["pigeon_toed"]["stat"] == "61 jumps"
    assert w["piggy_bank"]["stat"] == "4g 82s 10c picked up"
    assert w["sow_low"]["stat"] == "first death at 1m 35s"


def test_abbreviation_is_used_when_the_client_has_it(aw):
    aw.execute('AbbreviateNumbers = function(v) v = MockUnwrap(v) return ("%.1fk"):format(v / 1000) end')
    w = run_with_amounts(aw)
    assert w["lifeline"]["stat"] == "48.2k healing (1240 HPS)"


def test_stat_line_and_tooltip_on_the_stage(aw):
    run_with_amounts(aw)
    aw.execute('for i, w in ipairs(HH_w) do if w.award.id == "lifeline" then HH_w[1], HH_w[i] = w, HH_w[1] break end end')
    aw.execute(f'{A}.UI.ShowStage({{ headline = HH_w[1], others = {{}}, also = {{}} }}, {{}})')
    stat = aw.eval('HH_w[1].statPlain')
    assert stat
    assert aw.eval('MockUnwrap(HogTronAwardsStage.slots[1].stat._text)') == stat
    aw.execute('GameTooltip._lines = {}; HogTronAwardsStage.slots[1].card:GetScript("OnEnter")(HogTronAwardsStage.slots[1].card)')
    assert aw.eval('(function() for _, l in ipairs(GameTooltip._lines) do if tostring(MockUnwrap(l)):find(HH_w[1].statPlain, 1, true) then return true end end return false end)()')


def test_preview_cards_show_numbers_too(aw):
    aw.execute(f'HH_p = {A}.PreviewStage("x")')
    assert aw.eval('HH_p.headline.stat') and all(o["stat"] for o in lst(aw.eval('HH_p.others')))


PROBE = """
MockMeterAmounts("DamageDone", "Overall", { { "Hognificent", 900, 6, "Player-0" }, { "Unit1", 500, 3, MockSecret("Player-1") } })
C_DamageMeter.GetCombatSessionSourceFromType = function(st, mt, guid)
  if MockUnwrap(guid) ~= "Player-0" then error("Secret values are only allowed during untainted execution") end
  return { totalAmount = MockSecret(900), combatSpells = { { spellID = 585, totalAmount = MockSecret(900),
    combatSpellDetails = { { critAmount = MockSecret(420), maxAmount = MockSecret(420), hitCount = 3 } } } } }
end
"""


def test_spell_detail_probe_reports_crit_like_fields_and_secret_guids(aw):
    party(aw)
    aw.execute(AMOUNTS)
    aw.execute(PROBE)
    r = aw.eval(f'{A}.Metrics.ProbeSpellDetail()')
    assert "critAmount" in r["candidates"] and "maxAmount" in r["candidates"]
    assert "SECRET" in r["DamageDone.other.guid"]
    assert aw.eval('HogHeals.db.global.diag.awards.spellProbe.candidates') == r["candidates"]
    aw.execute('MockLog.chat = {}; HogHeals:SlashCommand("awards probe")')
    assert any("crit / biggest hit" in l for l in lst(aw.eval('MockLog.chat')))
    assert errors(aw) == []


def test_probe_says_so_when_there_is_no_crit_field(aw):
    party(aw)
    aw.execute(AMOUNTS)
    aw.execute('MockMeterAmounts("DamageDone", "Overall", { { "Hognificent", 900, 6, "Player-0" } })')
    aw.execute('C_DamageMeter.GetCombatSessionSourceFromType = function() return { combatSpells = { { spellID = 1, totalAmount = 5, combatSpellDetails = {} } } } end')
    assert aw.eval(f'{A}.Metrics.ProbeSpellDetail().result') == "no crit / biggest-hit field found"


def test_mvp_shows_only_the_main_line_and_singular_counts_read_right(aw):
    w = run_with_amounts(aw)
    assert w["lifeline"]["stat"] == "48210 healing (1240 HPS)"
    aw.execute(f'HH_one = {A}.Resolve.Stat({A}.BY_ID.breadcrumbs, "x", 1)')
    assert aw.eval('HH_one') == "1 corpse run"
