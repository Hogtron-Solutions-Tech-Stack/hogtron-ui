# HogHeals_Units: player / target / target-of-target / pet / focus frames. Secure buttons, unit watch, secret-safe
# health / power / level text, class + reaction colours, auras under the target, Blizzard's frames hidden and its
# target cast bar adopted.
import pytest

BLIZZ = '''
PlayerFrame = CreateFrame("Button", "PlayerFrame", UIParent)
TargetFrame = CreateFrame("Button", "TargetFrame", UIParent)
TargetFrameToT = CreateFrame("Button", "TargetFrameToT", TargetFrame)
PetFrame = CreateFrame("Button", "PetFrame", UIParent)
TargetFrameSpellBar = CreateFrame("StatusBar", "TargetFrameSpellBar", TargetFrame)
TargetFrameSpellBar.Border = TargetFrameSpellBar:CreateTexture()
AbbreviateNumbers = function(v) local secret = issecretvalue and issecretvalue(v) v = MockUnwrap(v) local r = v >= 1000 and ("%.1fk"):format(v / 1000) or tostring(v) if secret then return MockSecret(r) end return r end   -- measured: a secret in, a secret string out
'''


def boot(lua, extra=""):
    lua.execute(BLIZZ + extra)
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Units")
    lua.player_login()
    lua.execute('wipe(HogHeals.errors)')
    return lua


@pytest.fixture
def units(lua):
    return boot(lua)


def errors(lua):
    return [e["msg"] for e in lua.eval('HogHeals.errors').values()]


def test_frames_are_secure_unit_buttons_with_unit_watch(units):
    for unit, name in (("player", "HogUIPlayer"), ("target", "HogUITarget"), ("targettarget", "HogUITargetOfTarget"), ("pet", "HogUIPet"), ("focus", "HogUIFocus")):
        assert units.eval(f'{name}._template') == "SecureUnitButtonTemplate"
        assert units.eval(f'{name}:GetAttribute("unit")') == unit
        assert units.eval(f'{name}:GetAttribute("*type1")') == "target"
        assert units.eval(f'{name}:GetAttribute("*type2")') == "togglemenu"
        # watched unless it is the player (always shown) or off by default (focus)
        assert units.eval(f'MockUnitWatch[{name}] == true') is (unit not in ("player", "focus"))
    assert units.eval('HogUIPlayer.health._texture') is not None        # texture set at build (never a 0x0 bar again)
    assert errors(units) == []


def test_player_bars_and_class_colour(units):
    units.execute('MockUnits.player.health = 75; MockUnits.player.maxHealth = 100; MockUnits.player.power = 40; MockUnits.player.maxPower = 80')
    units.execute('MockFire("UNIT_HEALTH", "player"); MockFire("UNIT_POWER_UPDATE", "player")')
    assert units.eval('HogUIPlayer.health._value') == 75 and units.eval('HogUIPlayer.health._max') == 100
    assert units.eval('HogUIPlayer.power._value') == 40
    cls = units.eval('MockState.playerClass')
    r = units.eval(f'RAID_CLASS_COLORS["{cls}"].r')
    assert units.eval('HogUIPlayer.health._color[1]') == pytest.approx(r)
    assert units.eval('HogUIPlayer.healthText._text') == "75 / 100"                 # default: current / max
    assert units.eval('HogUIPlayer.powerText._text') == "40 / 80"
    assert units.eval('HogUIPlayer.power._color[3]') == pytest.approx(1.0)   # mana blue


def test_target_shows_name_level_reaction_and_raid_icon(units):
    units.execute('MockUnits.target = { name = "Kobold Vermin", class = "WARRIOR", health = 30, maxHealth = 60, level = 5, classification = "elite", reaction = 2, isPlayer = false, raidIcon = 8, guid = "C-1" }')
    units.execute('MockFire("PLAYER_TARGET_CHANGED")')
    assert units.eval('HogUITarget.name._text') == "Kobold Vermin"
    assert units.eval('HogUITarget.level._text') == "5+"
    assert units.eval('HogUITarget.health._color[1]') == pytest.approx(0.85)     # hostile red
    assert units.eval('HogUITarget.raidIcon._raidIcon') == 8 and units.eval('HogUITarget.raidIcon:IsShown()') is True
    units.execute('MockUnits.target.level = -1; MockUnits.target.classification = "worldboss"; MockFire("UNIT_LEVEL", "target")')
    assert units.eval('HogUITarget.level._text') == "Boss"


def test_enemy_player_keeps_class_colour_when_class_is_hidden(units):
    units.execute('MockUnits.target = { name = "Zug", class = "MAGE", health = 1, maxHealth = 1, isPlayer = true, guid = "P-9" }; MockFire("PLAYER_TARGET_CHANGED")')
    assert units.eval('HogUITarget.health._color[3]') == pytest.approx(0.94, abs=0.02)
    units.execute('local real = UnitClass; UnitClass = function(u) if u == "target" then return nil end return real(u) end; MockFire("UNIT_HEALTH", "target")')
    assert units.eval('HogUITarget.health._color[3]') == pytest.approx(0.94, abs=0.02)   # remembered


def test_secret_values_never_error(units):
    units.execute('MockSetSecrets(true); MockUnits.target = { name = "Boar", class = "WARRIOR", health = 42, maxHealth = 80, power = 10, maxPower = 100, guid = "C-2" }')
    units.execute('MockFire("PLAYER_TARGET_CHANGED"); MockFire("UNIT_HEALTH", "target"); MockFire("UNIT_POWER_UPDATE", "player"); MockFire("UNIT_LEVEL", "target")')
    assert units.eval('HogUITarget.health._value') == 42                      # widget takes the secret
    assert units.eval('HogUITarget.healthText._text') == "42 / 80"            # secret current, plain max
    assert units.eval('HogUIPlayer.powerText._text').startswith("100")
    units.execute('HogHeals.db.profile.units.healthText = "current-percent"; CurveConstants = { ScaleTo100 = 1 }; function UnitHealthPercent(u, p, c) return MockSecret(52.5) end; MockFire("UNIT_HEALTH", "target")')
    assert units.eval('HogUITarget.healthText._text') == "42  52%"
    assert errors(units) == []


@pytest.mark.parametrize("mode,want", [("percent", "50%"), ("current", "50"), ("current-max", "50 / 100"), ("current-percent", "50  50%"), ("none", "")])
def test_health_text_modes(units, mode, want):
    units.execute(f'HogHeals.db.profile.units.healthText = "{mode}"; MockUnits.player.health = 50; MockUnits.player.maxHealth = 100; MockFire("UNIT_HEALTH", "player")')
    assert units.eval('HogUIPlayer.healthText._text') == want


def test_state_words_beat_numbers(units):
    units.execute('MockUnits.target = { name = "Gone", class = "WARRIOR", health = 0, maxHealth = 100, dead = true, guid = "C-3" }; MockFire("PLAYER_TARGET_CHANGED")')
    assert units.eval('HogUITarget.healthText._text') == "Dead"
    units.execute('MockUnits.target.dead = false; MockUnits.target.connected = false; MockFire("UNIT_HEALTH", "target")')
    assert units.eval('HogUITarget.healthText._text') == "Offline"


def test_target_auras_debuffs_first_with_dispel_colour_and_cooldown(units):
    units.execute('''
      MockUnits.target = { name = "Kobold", class = "WARRIOR", health = 1, maxHealth = 1, guid = "C-4",
        auras = { { name = "Renew", icon = "renew" }, { name = "Sleep", type = "Magic", count = 2, duration = 30, expires = 100 }, { name = "Poisoned", type = "Poison", debuff = true } } }
      MockState.time = 80
      MockFire("PLAYER_TARGET_CHANGED")
    ''')
    assert units.eval('#HogUITarget.auras.debuffs') == 2 and units.eval('#HogUITarget.auras.buffs') == 0   # buffs off by default
    d1 = 'HogUITarget.auras.debuffs[1]'
    assert units.eval(f'{d1}.edge._color[3]') == pytest.approx(1.0)              # Magic blue outline
    assert units.eval(f'{d1}.count._text') == "2"
    assert units.eval(f'{d1}.cd._last.SetCooldown[1]') == 70 and units.eval(f'{d1}.cd._last.SetCooldown[2]') == 30
    assert units.eval('HogUITarget.auras.debuffs[2].edge._color[2]') == pytest.approx(0.6)   # Poison green
    # layout: debuff row under the frame; buffs appear under it only when switched on
    assert units.eval(f'{d1}._points[1][1]') == "TOPLEFT" and units.eval(f'{d1}._points[1][3]') == "BOTTOMLEFT"
    units.execute('HogHeals.db.profile.units.target.buffs = true; HogHealsUnits.Units.Refresh()')
    assert units.eval('HogUITarget.auras.buffs[1]:IsShown()') is True
    assert units.eval('HogUITarget.auras.buffs[1]._points[1][5]') < units.eval(f'{d1}._points[1][5]')
    assert units.eval(f'{d1}.cd._last.SetHideCountdownNumbers[1]') is True
    units.execute('MockUnits.target.auras = {}; MockFire("UNIT_AURA", "target")')
    assert units.eval(f'{d1}:IsShown()') is False
    assert errors(units) == []


def test_secret_aura_fields_are_shown_not_computed(units):
    units.execute('MockSetSecrets(true); MockUnits.target = { name = "K", class = "WARRIOR", health = 1, maxHealth = 1, guid = "C-5", auras = { { name = "X", type = "Magic", count = MockSecret(3), duration = MockSecret(10), expires = MockSecret(50) } } }')
    units.execute('MockFire("PLAYER_TARGET_CHANGED")')
    d1 = 'HogUITarget.auras.debuffs[1]'
    assert units.eval(f'{d1}:IsShown()') is True
    assert units.eval(f'{d1}.count._text') == "3"                             # format on a secret
    assert units.eval(f'{d1}.cd:IsShown()') is False                          # no swipe without plain times
    assert errors(units) == []


def test_blizzard_frames_hidden_and_spellbar_adopted(units):
    assert units.eval('PlayerFrame:GetParent() == HogHealsHiddenParent')
    assert units.eval('TargetFrame:GetParent() == HogHealsHiddenParent')
    assert units.eval('PetFrame:GetParent() == HogHealsHiddenParent')
    assert units.eval('TargetFrameSpellBar:GetParent() == HogUITarget')
    assert units.eval('TargetFrameSpellBar._points[1][3]') == "TOPLEFT"       # sits above our target frame
    assert units.eval('TargetFrameSpellBar._texture') == "Interface\\Buttons\\WHITE8X8"
    units.execute('TargetFrame:Show()')
    assert units.eval('TargetFrame:IsShown()') is False                       # Blizzard re-show undone
    units.execute('TargetFrameSpellBar:SetPoint("TOP", TargetFrame, "BOTTOM", 0, 0)')
    assert units.eval('TargetFrameSpellBar._points[1][2] == HogUITarget')     # re-anchored under ours


def test_hide_blizzard_off_leaves_them_alone(lua):
    # seed the saved variables the way the client would (works whether the DB inits at ADDON_LOADED or at login)
    lua.execute(BLIZZ + 'HogHealsDB = { profileKeys = {}, profiles = { Default = { units = { hideBlizzard = false } } } }')
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Units")
    lua.player_login()
    assert lua.eval('PlayerFrame:GetParent() == UIParent')


def test_drag_only_when_unlocked_and_saves_position(units):
    units.execute('HogUIPlayer:GetScript("OnDragStart")(HogUIPlayer)')
    assert units.eval('HogUIPlayer._moving') is not True
    units.execute('HogHeals:SlashCommand("unlock"); HogUIPlayer:GetScript("OnDragStart")(HogUIPlayer)')
    assert units.eval('HogUIPlayer._moving') is True
    units.execute('HogUIPlayer:StopMovingOrSizing(); HogUIPlayer:ClearAllPoints(); HogUIPlayer:SetPoint("CENTER", UIParent, "CENTER", 11, -22); HogUIPlayer:GetScript("OnDragStop")(HogUIPlayer)')
    assert units.eval('HogHeals.db.profile.units.player.point') == "CENTER"
    assert units.eval('HogHeals.db.profile.units.player.x') == 11
    units.execute('HogHeals:SlashCommand("units reset")')
    assert units.eval('HogHeals.db.profile.units.player.x') == -280
    assert errors(units) == []


def test_player_status_glyphs(units):
    units.execute('MockState.inCombat = true; MockFire("PLAYER_REGEN_DISABLED")')
    assert units.eval('HogUIPlayer.status._text') == "+"
    units.execute('MockState.inCombat = false; MockState.resting = true; MockFire("PLAYER_REGEN_ENABLED")')
    assert units.eval('HogUIPlayer.status._text') == "zz"


def test_unknown_events_do_not_break_enable(lua):
    lua.execute('MockUnknownEvents.UNIT_POWER_FREQUENT = true; MockUnknownEvents.UNIT_CLASSIFICATION_CHANGED = true')
    boot(lua)
    assert lua.eval('HogUIPlayer ~= nil') and errors(lua) == []
    assert "UNIT_POWER_FREQUENT" in lua.eval('table.concat(HogHealsUnits.module.unknown, ",")')


def test_tot_polled_while_shown(units):
    units.execute('MockUnits.targettarget = { name = "Hog", class = "SHAMAN", health = 5, maxHealth = 9, guid = "P-1" }; MockAdvance(0.6)')
    assert units.eval('HogUITargetOfTarget.name._text') == "Hog"


def test_every_option_getter_and_setter_runs(units):
    units.execute('''
      local function walk(t)
        for _, o in pairs(t.args or {}) do
          if o.get and o.set and o.type ~= "execute" then
            if o.type == "color" then o.set({}, o.get({})) else o.set({}, (o.get({}))) end
          end
          if o.args then walk(o) end
        end
      end
      walk(HogHeals.OptionsTable().args.Units)
    ''')
    assert errors(units) == []


def test_disabling_a_frame_stops_its_unit_watch(units):
    assert units.eval('MockUnitWatch[HogUIPet] == true')
    units.execute('HogHeals.db.profile.units.pet.enabled = false; HogHealsUnits.Units.Refresh()')
    assert units.eval('MockUnitWatch[HogUIPet]') is None and units.eval('HogUIPet:IsShown()') is False
    units.execute('HogHeals.db.profile.units.pet.enabled = true; HogHealsUnits.Units.Refresh()')
    assert units.eval('MockUnitWatch[HogUIPet] == true')


def test_small_frames_use_one_row_layout(units):
    assert units.eval('HogUITargetOfTarget.compact') is True and units.eval('HogUIPlayer.compact') is False
    assert units.eval('HogUITargetOfTarget.name._points[1][1]') == "LEFT"
    assert units.eval('#HogUITargetOfTarget.name._points') == 1                     # never hung off another string
    assert units.eval('HogUITargetOfTarget.healthText._points[1][1]') == "RIGHT"
    assert units.eval('HogUITargetOfTarget.level:IsShown()') is False
    assert units.eval('HogUITargetOfTarget.powerText:IsShown()') is False
    assert units.eval('HogUIPlayer.name._points[1][1]') == "TOPLEFT" and units.eval('HogUIPlayer.powerText:IsShown()') is True
    assert units.eval('#HogUIPlayer.name._points') == 1 and units.eval('HogUIPlayer.name._width') == 240 - 6 - 5 - 5 - units.eval('HogUIPlayer.level:GetStringWidth()')
    assert units.eval('HogUIPlayer.name:IsShown()') is True and units.eval('HogUIPlayer.level:IsShown()') is True
    units.execute('HogHeals.db.profile.units.targettarget.height = 40; HogHealsUnits.Units.Refresh()')
    assert units.eval('HogUITargetOfTarget.compact') is False


def test_no_power_text_for_a_unit_without_power(units):
    units.execute('MockUnits.target = { name = "Bat", class = "WARRIOR", health = 5, maxHealth = 5, power = 0, maxPower = 0, guid = "C-9" }; MockFire("PLAYER_TARGET_CHANGED")')
    assert units.eval('HogUITarget.powerText._text') == ""
    units.execute('MockSetSecrets(true); MockFire("UNIT_POWER_UPDATE", "target")')
    assert units.eval('HogUITarget.powerText._text') == ""


def test_unlock_shows_every_frame_with_a_drag_label_and_lock_restores_the_watch(units):
    units.execute('HogUITarget:Hide(); HogHeals:SlashCommand("unlock")')
    assert units.eval('HogUITarget:IsShown()') is True
    assert units.eval('HogUITarget.dragHint._text') == "drag: target" and units.eval('HogUITarget.dragHint:IsShown()') is True
    assert units.eval('MockUnitWatch[HogUITarget]') is None                  # watch paused while moving
    units.execute('HogUITarget:GetScript("OnDragStart")(HogUITarget)')
    assert units.eval('HogUITarget._moving') is True
    units.execute('HogUITarget:StopMovingOrSizing(); HogHeals:SlashCommand("lock")')
    assert units.eval('MockUnitWatch[HogUITarget] == true')
    assert units.eval('HogUITarget.dragHint:IsShown()') is False
    assert units.eval('HogUITarget:IsShown()') is False                     # no target: hidden again
    assert errors(units) == []


def test_unitdiag_prints_every_frame(units):
    units.execute('wipe(MockLog.chat or {}); HogHeals:SlashCommand("unitdiag")')
    chat = "\n".join(units.eval('MockLog.chat').values())
    assert "locked=true" in chat and "player shown=true" in chat and "targettarget shown=" in chat
    assert errors(units) == []


def test_a_failing_piece_is_named_in_chat_and_does_not_block_the_others(units):
    units.execute("""
      MockUnits.target = { name = "Kobold", class = "WARRIOR", health = 30, maxHealth = 60, guid = "C-99" }
      local real = HogHealsUnits.Units.UpdateInfo
      HogHealsUnits.Units.UpdateInfo = function() error("boom") end
      wipe(MockLog.chat or {})
      MockFire("PLAYER_TARGET_CHANGED")
      HogHealsUnits.Units.UpdateInfo = real
    """)
    chat = " ".join(units.eval('MockLog.chat').values())
    assert "unit frame name/level (target): " in chat and "boom" in chat
    assert units.eval('HogUITarget.healthText._text') == "30 / 60"         # health still updated
    assert units.eval('HogUITarget.status._text') == ""                    # status piece still ran


def test_player_pet_and_tot_frames_never_get_aura_rows(units):
    units.execute('MockUnits.player.auras = { { name = "Fortitude" }, { name = "Weakened Soul", type = "Magic" } }; MockFire("UNIT_AURA", "player")')
    assert units.eval('HogUIPlayer.auras') is None
    units.execute('MockUnits.pet = { name = "Kongorg", class = "WARRIOR", health = 1, maxHealth = 1, guid = "Pet-1", auras = { { name = "X", type = "Poison" } } }; MockFire("UNIT_PET", "player")')
    assert units.eval('HogUIPet.auras') is None


def test_name_takes_every_pixel_the_row_leaves(units):
    # compact frame: name shares its one row with the health text, nothing else
    units.execute('MockUnits.target = { name = "Bat", class = "WARRIOR", health = 5, maxHealth = 5, power = 0, maxPower = 0, guid = "C-9" }')
    units.execute('MockUnits.targettarget = { name = "Hordecore Pwn", class = "PALADIN", health = 343, maxHealth = 343, power = 10, maxPower = 10, guid = "P-2" }')
    units.execute('MockFire("PLAYER_TARGET_CHANGED")')
    tot_w = units.eval('HogHeals.db.profile.units.targettarget.width')
    ht_w = units.eval('HogUITargetOfTarget.healthText:GetStringWidth()')
    assert ht_w > 0
    assert units.eval('HogUITargetOfTarget.name._width') == tot_w - ht_w - 8 - 6
    assert units.eval('HogUITargetOfTarget.name._width') >= 12 * 6                 # a 12-char player name at the mock's 6 px/char
    # full frame: name shares the top row with the level only; level off => the whole row
    lvl_w = units.eval('HogUITarget.level:GetStringWidth()')
    assert units.eval('HogUITarget.name._width') == 240 - lvl_w - 5 - 5 - 6
    units.execute('HogHeals.db.profile.units.target.showLevel = false; HogHealsUnits.Units.Refresh()')
    assert units.eval('HogUITarget.name._width') == 240 - 5 - 6
    # health text change re-fits the compact name
    units.execute('HogHeals.db.profile.units.healthText = "none"; MockFire("UNIT_HEALTH", "targettarget")')
    assert units.eval('HogUITargetOfTarget.name._width') == tot_w - 8 - 6
    assert errors(units) == []


def test_power_text_with_a_secret_current_value_never_compares_it(units):
    units.execute('MockSetSecrets(true); MockFire("UNIT_POWER_UPDATE", "player")')
    assert errors(units) == []
    assert units.eval('HogUIPlayer.powerText._text') != ""


def test_fit_name_with_a_hidden_health_text_width_estimates_instead_of_computing(units):
    units.execute('MockUnits.target = { name = "Bat", class = "WARRIOR", health = 5, maxHealth = 5, power = 0, maxPower = 0, guid = "C-9" }')
    units.execute('MockUnits.targettarget = { name = "Hordecore Pwn", class = "PALADIN", health = 343, maxHealth = 343, power = 10, maxPower = 10, guid = "P-2" }')
    units.execute('MockSetSecrets(true); MockFire("PLAYER_TARGET_CHANGED"); MockFire("UNIT_HEALTH", "targettarget"); MockFire("UNIT_HEALTH", "pet")')
    assert units.eval('issecretvalue(HogUITargetOfTarget.healthText:GetStringWidth())') is True     # the mock models the client
    assert errors(units) == []
    size = units.eval('HogHeals.db.profile.units.fontSize')
    tot_w = units.eval('HogHeals.db.profile.units.targettarget.width')
    assert units.eval('HogUITargetOfTarget.name._width') == max(20, tot_w - (11 * size * 0.6) - 8 - 6)
