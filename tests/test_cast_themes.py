# HogTron_HUD/CastThemes.lua: the HUD cast bar takes on what you cast (Sean 2026-10-14, from the WoW Forever add-on
# clip #2 "Opulent Casting Bars"). The theme is read off the client - cast name, isTradeSkill, the spell's own
# description, the class - never from a spell table typed in by hand.
import pytest

from test_castbar import cb  # noqa: F401  (fixture)

T = "HogHealsHUD.CastThemes"

DESC = '''
DESC = {
  [133] = "Hurls a fiery ball that causes 14 to 23 Fire damage and an additional 2 Fire damage over 4 sec.",
  [116] = "Launches a bolt of frost at the enemy, causing 18 to 20 Frost damage and slowing movement speed.",
  [585] = "Smite an enemy for 13 to 17 Holy damage.",
  [15407] = "Assault the target's mind with Shadow energy, causing 75 Shadow damage over 3 sec and slowing.",
  [2061] = "Heals a friendly target for 193 to 237.",
  [118] = "Transforms the enemy into a sheep, forcing it to wander around for up to 20 sec.",
}
DESC_CALLS = 0
-- like the client, a secret id still names the spell: only our guard keeps it out
function GetSpellDescription(id) DESC_CALLS = DESC_CALLS + 1 return DESC[MockUnwrap(id)] end
'''


@pytest.fixture
def th(cb):  # noqa: F811
    cb.execute(DESC + 'MockState.playerClass = "MAGE"')
    return cb


def cast(f, name, spell, dur=2.0, interruptible=True, trade=False, channel=False):
    if channel:
        # UnitChannelInfo: name, text, texture, startMS, endMS, isTradeSkill, notInterruptible, spellID
        f.execute(f'''
          MockUnits.player.channeling = {{ "{name}", "{name}", "icon", {int(f.eval("MockState.time") * 1000)}, {int((f.eval("MockState.time") + dur) * 1000)}, {str(trade).lower()}, {"false" if interruptible else "true"}, {spell} }}
          MockFire("UNIT_SPELLCAST_CHANNEL_START", "player", 1, {spell})''')
    else:
        # UnitCastingInfo: name, text, texture, startMS, endMS, isTradeSkill, castID, notInterruptible, spellID
        f.execute(f'''
          MockUnits.player.casting = {{ "{name}", "{name}", "icon", {int(f.eval("MockState.time") * 1000)}, {int((f.eval("MockState.time") + dur) * 1000)}, {str(trade).lower()}, 1, {"false" if interruptible else "true"}, {spell} }}
          MockFire("UNIT_SPELLCAST_START", "player", 1, {spell})''')


def bar_colour(f):
    return list(f.eval("HH_cb._color").values())[:3]


def glow_shown(f):
    return f.eval(f"{T}.layers ~= nil and {T}.layers.glow:IsShown()") is True


def motes_shown(f):
    return f.eval(f"(function() local n = 0 for _, m in ipairs({T}.layers.motes) do if m:IsShown() then n = n + 1 end end return n end)()")


# ================================================================================================ reading the theme
def test_description_school_words(th):
    for spell, key in ((133, "fire"), (116, "frost"), (585, "holy"), (15407, "shadow")):
        assert th.eval(f"{T}.FromDescription(DESC[{spell}], 'MAGE')") == key, spell
    assert th.eval(f'{T}.FromDescription("Causes 40 Nature damage to the target.", "DRUID")') == "nature"
    assert th.eval(f'{T}.FromDescription("Causes 50 Arcane damage to the target.", "DRUID")') == "arcane"
    # the earliest school named wins
    assert th.eval(f'{T}.FromDescription("Deals 10 Frost damage, then 5 Fire damage.", "MAGE")') == "frost"
    assert th.eval(f'{T}.FromDescription("Deals 10 Fire damage, then 5 Frost damage.", "MAGE")') == "fire"
    assert th.eval(f'{T}.FromDescription("Holy light: 10 Nature damage, then 5 Holy damage.", "DRUID")') == "nature"
    # a heal takes the class's healing school; a class that does not heal gets nothing from it
    assert th.eval(f"{T}.FromDescription(DESC[2061], 'PRIEST')") == "holy"
    assert th.eval(f"{T}.FromDescription(DESC[2061], 'SHAMAN')") == "nature"
    assert th.eval(f"{T}.FromDescription(DESC[2061], 'MAGE')") is None
    assert th.eval(f"{T}.FromDescription(DESC[118], 'MAGE')") is None
    assert th.eval(f'{T}.FromDescription("", "MAGE")') is None


def test_resolve_order(th):
    def r(name, spell="nil", trade="false", cls="MAGE"):
        return tuple(th.eval(f'{T}.Resolve("{name}", {spell}, {trade}, "{cls}")'))
    assert r("Mining") == ("earth", "cast name")
    assert r("Smelting") == ("earth", "cast name")
    assert r("Herb Gathering") == ("herb", "cast name")
    assert r("Skinning") == ("leather", "cast name")
    assert r("Fishing") == ("water", "cast name")
    assert r("Opening") == ("gold", "cast name")
    assert r("Linen Bandage", trade="true") == ("craft", "trade skill")
    assert r("Fireball", 133) == ("fire", "description")
    assert r("Polymorph", 118) == ("arcane", "class")            # no school in the text: the mage's own
    assert r("Shoot", "nil", cls="WARRIOR") == (None, "none")      # no theme: your own colours


def test_only_a_real_description_is_cached(th):
    th.execute("DESC[9999] = nil")
    assert th.eval(f'{T}.Resolve("Newly Learned", 9999, false, "PRIEST")')[1] == "class"
    th.execute('DESC[9999] = "Causes 30 Shadow damage."')            # the text arrives later
    assert tuple(th.eval(f'{T}.Resolve("Newly Learned", 9999, false, "PRIEST")')) == ("shadow", "description")
    calls = th.eval("DESC_CALLS")
    th.eval(f'{T}.Resolve("Newly Learned", 9999, false, "PRIEST")')
    assert th.eval("DESC_CALLS") == calls                          # cached now


def test_a_secret_spell_id_is_never_used(th):
    th.execute("MockSetSecrets(true)")
    assert tuple(th.eval(f'{T}.Resolve("Fireball", MockSecret(133), false, "MAGE")')) == ("arcane", "class")
    th.execute("MockSetSecrets(false)")


# ================================================================================================ on the bar
def test_fireball_wears_fire(th):
    cast(th, "Fireball", 133)
    assert th.eval("HogHealsHUD.Castbar.state.theme") == "fire"
    assert bar_colour(th) == pytest.approx([0.50, 0.21, 0.05])   # fire fill dimmed under its light strip (ART_FILL)
    assert glow_shown(th)
    assert motes_shown(th) == 6
    spark = list(th.eval("HH_cb.spark._color").values())[:3]
    assert spark != pytest.approx([1, 1, 1])
    # every frame: the motes move with the head of the fill, the glow breathes
    th.execute("MockState.time = MockState.time + 1.0; HogHealsHUD.Castbar.OnUpdate(HH_cb)")
    assert th.eval(f"{T}.lastTick.head") == pytest.approx(100.0)  # 200 px bar, half way
    pts = list(th.eval(f"{T}.layers.motes[1]._points[1]").values())
    assert pts[0] == "CENTER" and pts[2] == "LEFT"
    th.execute('MockFire("UNIT_SPELLCAST_STOP", "player")')
    assert not glow_shown(th) and motes_shown(th) == 0
    assert list(th.eval("HH_cb.spark._color").values())[:3] == pytest.approx([1, 1, 1])


def test_channel_mind_flay_wears_shadow(th):
    th.execute('MockState.playerClass = "PRIEST"')
    cast(th, "Mind Flay", 15407, channel=True)
    assert th.eval("HogHealsHUD.Castbar.state.theme") == "shadow"
    assert bar_colour(th) == pytest.approx([0.26, 0.12, 0.40])   # shadow fill dimmed under its light strip
    th.execute('MockFire("UNIT_SPELLCAST_CHANNEL_STOP", "player")')
    assert not glow_shown(th)


def test_mining_is_earth_even_without_a_spell_id(th):
    cast(th, "Mining", "nil", trade=True)
    assert th.eval("HogHealsHUD.Castbar.state.theme") == "earth"
    assert th.eval("HogHealsHUD.Castbar.state.themeWhy") == "cast name"


def test_cannot_interrupt_keeps_its_grey(th):
    cast(th, "Fireball", 133, interruptible=False)
    assert bar_colour(th) == pytest.approx([0.6, 0.6, 0.6])
    assert not glow_shown(th)


def test_a_failed_cast_flashes_red_without_the_theme(th):
    cast(th, "Fireball", 133)
    th.execute('MockFire("UNIT_SPELLCAST_INTERRUPTED", "player")')
    assert bar_colour(th) == pytest.approx([0.85, 0.2, 0.2])
    assert not glow_shown(th)


def test_themes_off_means_your_own_colours(th):
    th.execute('HogHeals:SlashCommand("casttheme off")')
    cast(th, "Fireball", 133)
    assert bar_colour(th) == pytest.approx([0.13, 0.83, 0.88])
    assert th.eval(f"{T}.layers == nil or not {T}.layers.glow:IsShown()") is True
    th.execute('MockFire("UNIT_SPELLCAST_STOP", "player"); HogHeals:SlashCommand("casttheme on")')
    cast(th, "Fireball", 133)
    assert glow_shown(th)


def test_glow_and_motes_switches(th):
    th.execute("HogHeals.db.profile.hud.castbar.themes.motes = false")
    cast(th, "Frostbolt", 116)
    assert glow_shown(th) and motes_shown(th) == 0
    th.execute('MockFire("UNIT_SPELLCAST_STOP", "player"); HogHeals.db.profile.hud.castbar.themes.glow = false; HogHeals.db.profile.hud.castbar.themes.motes = true')
    cast(th, "Frostbolt", 116)
    assert not glow_shown(th) and motes_shown(th) == 5
    assert bar_colour(th) == pytest.approx([0.18, 0.33, 0.43])   # the fill still themed (dimmed: the frost strip is on)


def test_no_class_school_keeps_plain_colours(th):
    th.execute('MockState.playerClass = "WARRIOR"')
    cast(th, "Hearthstone", 8690)
    assert th.eval("HogHealsHUD.Castbar.state.theme") is None
    assert bar_colour(th) == pytest.approx([0.13, 0.83, 0.88])
    assert not glow_shown(th)


def test_every_fill_keeps_the_cream_text_readable(th):
    # the default cast colour (cyan, luminance 0.65) reads in game: no theme fill may be brighter than that, and no
    # two themes may be near twins
    fills = {}
    for key in th.eval(f"{T}.ORDER").values():
        r, g, b = th.eval(f"{T}.THEMES.{key}.fill").values()
        assert 0.2126 * r + 0.7152 * g + 0.0722 * b <= 0.65, key
        fills[key] = (r, g, b)
    keys = list(fills)
    for i, a in enumerate(keys):
        for b in keys[i + 1:]:
            assert sum(abs(x - y) for x, y in zip(fills[a], fills[b])) > 0.15, (a, b)


# ================================================================================================ pure + diag + preview
def test_motes_are_born_at_the_head_and_fade(th):
    for life_t in (0.0, 1.0 / 0.9):
        x, y, a = th.eval(f"{T}.Mote({life_t}, 1, 6, {T}.THEMES.fire.motes, 100, 18)")
        assert a == pytest.approx(0, abs=1e-6)
    _, y_fire, a_mid = th.eval(f"{T}.Mote(0.5, 1, 6, {T}.THEMES.fire.motes, 100, 18)")
    _, y_frost, _ = th.eval(f"{T}.Mote(0.5, 1, 5, {T}.THEMES.frost.motes, 100, 18)")
    _, y_earth, _ = th.eval(f"{T}.Mote(0.5, 1, 6, {T}.THEMES.earth.motes, 100, 18)")
    assert a_mid > 0 and y_fire > 0 and y_frost < 0 and y_earth < 0
    _, y_far, _ = th.eval(f"{T}.Mote(0.99, 1, 6, {{ rise = 500, drift = 0 }}, 100, 18)")
    assert y_far <= 18                                            # never far off the bar


def test_castdiag_names_the_theme(th):
    cast(th, "Fireball", 133)
    lines = list(th.eval("HogHealsHUD.Castbar.Diagnose()").values())
    assert any("theme: fire (from description)" in l and "spell id=133" in l for l in lines)


def test_preview_walks_every_theme_then_stops(th):
    th.execute("HogHealsHUD.Castbar.PreviewThemes()")
    assert th.eval("HogHealsHUD.Castbar.state.theme") == "holy"
    assert th.eval("HH_cb.text:GetText()").startswith("Flash Heal  (preview)")
    th.execute("MockAdvance(2)")
    assert th.eval("HogHealsHUD.Castbar.state.theme") == "fire"
    for _ in range(12):
        th.execute("MockAdvance(2)")
    assert th.eval("HogHealsHUD.Castbar.state.casting") is False
    assert th.eval("HogHealsHUD.Castbar.state.preview") is None


def test_a_real_cast_ends_the_preview(th):
    th.execute("HogHealsHUD.Castbar.PreviewThemes()")
    cast(th, "Frostbolt", 116)
    th.execute("MockAdvance(2); MockAdvance(2); MockAdvance(2)")
    assert th.eval("HogHealsHUD.Castbar.state.preview") is None
    assert th.eval("HH_cb.text:GetText()") == "Frostbolt » Zugzug"     # the real cast, never a preview sample
    assert th.eval("HogHealsHUD.Castbar.state.themeWhy") == "description"


def test_options(th):
    opts = th.eval("HogHealsHUD.Options.Build()")
    args = opts["args"]["castbar"]["args"]
    assert args["themesOn"]["type"] == "toggle" and args["themesPreview"]["type"] == "execute"
    assert th.eval("#HogHeals.errors") == 0


def test_preview_never_shows_a_question_mark(th):
    # Sean 2026-10-14 in game: the preview's icon was a question mark. Known spell = the client's own icon ...
    th.execute("HogHealsHUD.Castbar.PreviewThemes()")
    tex = th.eval("HH_cb.icon._texture")
    assert tex and "QuestionMark" not in tex
    # ... a spell you do not know = the theme's usual icon
    th.execute("HogHealsHUD.Castbar.state.preview = nil; HogHealsHUD.Castbar.state.casting = false")
    th.execute("C_Spell.GetSpellTexture = function() return nil end; GetSpellTexture = function() return nil end")
    th.execute("HogHealsHUD.Castbar.PreviewThemes()")
    assert th.eval("HH_cb.icon._texture").endswith("Spell_Holy_FlashHeal")
    for key in th.eval("HogHealsHUD.CastThemes.ORDER").values():
        assert th.eval(f'HogHealsHUD.Castbar.PreviewIcon("Unknown", "{key}")').startswith("Interface"), key



# ================================================================================================ art strips (10/14)
def test_the_art_strip_fills_the_cast_and_scrolls_toward_the_spark(th):
    th.execute("HH_cb:SetHeight(18)")
    cast(th, "Pyroblast", 133)                      # a fire spell without its own strip (Fireball, Scorch have one since 10/17)
    art = f"{T}.layers.art"
    assert th.eval(f"{art}:IsShown()") is True
    assert th.eval(f"{art}._texture").endswith("cast_fire")
    assert th.eval(f"{art}._blend") == "ADD"
    th.execute("MockState.time = MockState.time + 1.0; HogHealsHUD.Castbar.OnUpdate(HH_cb)")
    assert th.eval(f"{art}:GetWidth()") == pytest.approx(100.0)          # half the 200 px bar: only the filled part
    u0, u1, v0, v1 = th.eval(f"{art}._texCoord").values()
    assert (u1 - u0) == pytest.approx(100 / (512 * 18 / 64))             # the strip keeps its shape at 18 px tall
    assert (v0, v1) == (0, 1)
    th.execute("MockState.time = MockState.time + 0.5; HogHealsHUD.Castbar.OnUpdate(HH_cb)")
    assert list(th.eval(f"{art}._texCoord").values())[0] < u0           # moving toward the spark
    th.execute('MockFire("UNIT_SPELLCAST_STOP", "player")')
    assert th.eval(f"{art}:IsShown()") is False


def test_matter_strips_blend_and_light_strips_add(th):
    cast(th, "Mining", "nil", trade=True)
    assert th.eval(f"{T}.layers.art._blend") == "BLEND"
    assert th.eval(f"{T}.layers.art._texture").endswith("cast_earth")


def test_art_switch_and_a_strip_the_client_cannot_load(th):
    th.execute("HogHeals.db.profile.hud.castbar.themes.art = false")
    cast(th, "Fireball", 133)
    assert th.eval(f"{T}.layers.art:IsShown()") is False and glow_shown(th)
    th.execute('MockFire("UNIT_SPELLCAST_STOP", "player"); HogHeals.db.profile.hud.castbar.themes.art = true')
    th.execute(f"{T}.layers.art.SetTexture = function() return false end")
    cast(th, "Frostbolt", 116)
    assert th.eval(f"{T}.layers.art:IsShown()") is False
    assert th.eval(f"{T}.artMissing.frost") is True
    assert glow_shown(th) and bar_colour(th) == pytest.approx([0.36, 0.66, 0.86])   # the rest of the look stays
    assert th.eval("#HogHeals.errors") == 0


def test_art_coords_pure(th):
    u0, u1 = th.eval(f"{T}.ArtCoords(0, 144, 18, 30)")
    assert (u0, u1) == (0, pytest.approx(1.0))                           # 144 px = exactly one strip at 18 px tall
    u0, u1 = th.eval(f"{T}.ArtCoords(2, 72, 36, 30)")
    assert u0 == pytest.approx(-60 / 288) and (u1 - u0) == pytest.approx(0.25)
    assert th.eval(f"{T}.ArtCoords(1, 50, 0, 30)") is not None           # a bar with no height never divides by 0



# ================================================================================================ per-spell art (10/17 pilot)
# Sean: "create open art images for casting of spells, for every spell, for every class ... some of the lower level mage
# skills so I can test them in game right now: Frostbolt, Fireball"
def test_a_spell_with_its_own_strip_gets_it_with_its_schools_colours(th):
    cast(th, "Fireball", 133)
    assert th.eval(f"{T}.layers.art._texture").endswith("cast_spell_fireball")
    assert th.eval(f"{T}.active.key") == "fire" and th.eval(f"{T}.active.art") == "spell_fireball"
    assert th.eval("HogHealsHUD.Castbar.state.spellArt") == "spell_fireball"
    for name, art in (("Frostbolt", "spell_frostbolt"), ("Polymorph: Pig", "spell_polymorph"), ("Teleport: Stormwind", "spell_teleport"),
                      ("Portal: Darnassus", "spell_teleport")):
        assert th.eval(f'({T}.SpellArt("{name}"))') == art, name


def test_spell_art_off_or_missing_falls_back_to_the_school_strip(th):
    th.execute("HogHeals.db.profile.hud.castbar.themes.spellArt = false")
    cast(th, "Fireball", 133)
    assert th.eval(f"{T}.layers.art._texture").endswith("cast_fire")
    th.execute("HogHeals.db.profile.hud.castbar.themes.spellArt = true")
    th.execute(f"""local L = {T}.Build(HH_cb); local orig = L.art.SetTexture
      L.art.SetTexture = function(self, path, ...) if tostring(path):find("cast_spell_") then return false end return orig(self, path, ...) end""")
    cast(th, "Frostbolt", 116)
    assert th.eval(f"{T}.layers.art._texture").endswith("cast_frost") and th.eval(f"{T}.artMissing.spell_frostbolt") is True



def test_the_whole_mage_set_has_strips_and_the_files_exist():
    import pathlib
    root = pathlib.Path(__file__).resolve().parents[1]
    src = (root / "HogTron_HUD" / "CastThemes.lua").read_text(encoding="utf-8")
    import re
    arts = set(re.findall(r'\{ "\^[^"]+", "(spell_[a-z_]+)", "[a-z]+" \}', src))
    assert len(arts) == 12
    for a in arts:
        assert (root / "HogTronUI" / "Media" / f"cast_{a}.tga").is_file(), a


def test_mage_spells_match_their_strips(th):
    for name, art in (("Conjure Water", "spell_conjure_water"), ("Conjure Mana Ruby", "spell_conjure_gem"), ("Arcane Missiles", "spell_arcane_missiles"),
                      ("Flamestrike", "spell_flamestrike"), ("Blizzard", "spell_blizzard"), ("Evocation", "spell_evocation"), ("Scorch", "spell_scorch"),
                      ("Conjure Food", "spell_conjure_food"), ("Polymorph: Cow", "spell_polymorph")):
        assert th.eval(f'({T}.SpellArt("{name}"))') == art, name
