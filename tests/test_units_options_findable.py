# Settings live next to the switch they belong to (Sean 2026-10-18, in Units > Player looking for the portrait's 3D
# look, which sat in General: "if I can't find it and you're giving me instructions to find it, nobody's going to be
# able to find it naturally. This isn't intuitive at all."). Driven through the real panel, the way a player clicks.
from test_edit_mode import ed  # noqa: F401  (fixture: core + HUD + Units + the rest)

P = "HogHeals.Panel"


def ctl(key):
    return f'{P}.controls["Units.{key}"]'


def open_tab(lua, tab):
    lua.execute(f'wipe(HogHeals.errors); {P}.Open(); {P}.Select("Units"); {P}.SelectTab("{tab}")')


def pick(lua, key, label):
    lua.execute(ctl(key) + ".button:Click()")
    n = lua.eval(f"#{P}.menu.items")
    for i in range(1, n + 1):
        if lua.eval(f"{P}.menu.items[{i}].label._text") == label:
            lua.execute(f"{P}.menu.items[{i}]:Click()")
            return
    raise AssertionError(f"{label} not in the {key} menu")


def test_the_portrait_look_sits_under_the_portrait_switch(ed):  # noqa: F811
    open_tab(ed, "player")
    assert ed.eval(ctl("player.portrait") + " ~= nil")
    assert ed.eval(ctl("player.portraitStyle")) is None                    # portrait off: nothing to pick yet
    ed.execute(ctl("player.portrait") + ".button:Click()")                  # turn it on, right there
    assert ed.eval("HogHeals.db.profile.units.player.portrait") is True
    assert ed.eval(ctl("player.portraitStyle") + " ~= nil")                 # ... and its look appears under it
    pick(ed, "player.portraitStyle", "Live model (3D)")
    assert ed.eval("HogHeals.db.profile.units.portraitStyle") == "3D"
    open_tab(ed, "general")
    assert ed.eval(ctl("general.portraitStyle")) is None                    # not split off into General any more
    assert ed.eval("HogHeals.errors[1]") is None


def test_the_target_tab_has_its_own_portrait_and_look(ed):  # noqa: F811
    open_tab(ed, "target")
    ed.execute(ctl("target.portrait") + ".button:Click()")
    assert ed.eval(ctl("target.portraitStyle") + " ~= nil")
    assert ed.eval(ctl("target.portraitStyle") + ".button.label._text") == "Picture (2D)"


def test_the_player_tab_puts_your_cast_bar_on_the_frame(ed):  # noqa: F811
    open_tab(ed, "player")
    assert ed.eval(ctl("player.castbarAttach") + ".button.label._text") == "In the HUD (not on this frame)"
    pick(ed, "player.castbarAttach", "Under this frame")
    assert ed.eval("HogHeals.db.profile.hud.castbar.attach") == "below"
    assert ed.eval("HogHealsHUD.HUD.rows.castbar.attached") == "below"      # the HUD bar moved, same setting
    hud_opt = "HogHeals.OptionsTable().args.HUD.args.castbar.args.attach"
    assert ed.eval(f"{hud_opt}.get({{}})") == "below"                       # HUD > Castbar shows the same choice


# The trap behind the above (in game 2026-10-18: "Portrait beside the frame" showed CHECKED while no portrait drew): the
# Units toggles read a missing setting as on (`~= false`), and portrait had no default. Every unit-frame checkbox is
# read through a proxy that sees which setting it looks at; one that shows on for a setting with no value at all fails.
SWEEP = '''(function()
  local out = {}
  local units = HogHeals.db.profile.units
  local tabs = HogHeals.OptionsTable().args.Units.args
  for _, unit in ipairs({ "player", "target", "targettarget", "pet", "focus" }) do
    local real = units[unit]
    local seen
    units[unit] = setmetatable({}, { __index = function(_, k) seen = k return real[k] end, __newindex = real })
    for _, opt in pairs(tabs[unit].args) do
      if opt.type == "toggle" then
        seen = nil
        local ok, v = pcall(opt.get, {})
        if ok and v == true and seen and real[seen] == nil then out[#out + 1] = unit .. "." .. seen end
      end
    end
    units[unit] = real
  end
  table.sort(out)
  return table.concat(out, ",")
end)()'''


def test_no_unit_checkbox_shows_on_for_a_setting_that_has_no_value(ed):  # noqa: F811
    assert ed.eval(SWEEP) == ""
