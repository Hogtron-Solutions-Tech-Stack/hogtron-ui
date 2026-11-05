# Modules (HogTronUI/Core/Modules.lua): which addon folders load - step 2 of the setup guide and General > Modules.
# Sean 2026-11-05: "In the setup, they can pick what they want on or off as far as submodules."
from test_setup import full  # noqa: F401 (fixture)

CLIENT = '''
ADDONS = { HogTron_Units = 2, HogHeals_Frames = 2, HogTron_Bars = 2, HogTron_HUD = 2, HogTron_Plates = 2, HogTron_Quests = 2,
  HogTron_Skin = 2, HogTron_Chat = 0, HogTron_Meter = 2, HogTron_Atlas = 2, HogTron_Training = 2, HogTron_Awards = 2 }   -- no Journal here
CALLS = {}
C_AddOns.GetAddOnInfo = function(name) if ADDONS[name] == nil then error("Usage: unknown addon " .. tostring(name)) end return name end
C_AddOns.GetAddOnEnableState = function(name, who) WHO = who return ADDONS[name] end
C_AddOns.EnableAddOn = function(name, who) ADDONS[name] = 2 CALLS[#CALLS + 1] = { "on", name, who } end
C_AddOns.DisableAddOn = function(name, who) ADDONS[name] = 0 CALLS[#CALLS + 1] = { "off", name, who } end
'''


def errors(lua):
    return [e["msg"] for e in lua.eval("HogHeals.errors").values()]


def test_rows_follow_the_clients_addon_list_per_character(full):
    full.execute(CLIENT)
    rows = {r["name"]: r for r in full.eval("HogHeals.Modules.Rows()").values()}
    assert rows["HogTron_Units"]["enabled"] is True and rows["HogTron_Chat"]["enabled"] is False
    assert "HogTron_Journal" not in rows                                        # the client does not list it
    assert full.eval("WHO") == "Hognificent"                                     # this character's state
    assert full.eval('HogHeals.Modules.Set("HogTron_Chat", true)') is True
    assert list(full.eval("CALLS[1]").values()) == ["on", "HogTron_Chat", "Hognificent"]
    assert full.eval('HogHeals.Modules.Enabled("HogTron_Chat")') is True
    assert full.eval('HogHeals.Modules.Set("HogTron_Bars", false)') is True
    assert full.eval('HogHeals.Modules.Enabled("HogTron_Bars")') is False
    lines = list(full.eval("HogHeals.Modules.Lines()").values())
    assert "Action bars: off  -> off after /reload" in lines and "Chat: on  -> on after /reload" in lines
    assert errors(full) == []


def test_the_guides_pick_your_parts_page_carries_the_load_switches_and_marks_a_reload(full):
    full.execute(CLIENT)
    assert full.eval("HogHeals.Setup.STEPS[1].key") == "welcome"
    full.execute("T = HogHeals.Setup.Table()")
    assert full.eval("T.args.modules.name").endswith("Pick your parts")
    assert full.eval("T.args.modules.args.units_enabled.type") == "toggle"          # the profile switch stays
    assert full.eval("T.args.modules.args.loadHead.name") == "Load at all (this character)"
    assert full.eval("T.args.modules.args.HogTron_Chat.get()") is False
    assert full.eval("T.args.modules.args.HogTron_Journal") is None
    assert full.eval("HogHeals.Setup.pendingReload") is False
    full.execute("T.args.modules.args.HogTron_Chat.set(nil, true)")
    assert full.eval("HogHeals.Setup.pendingReload") is True
    assert full.eval('HogHeals.Modules.Enabled("HogTron_Chat")') is True
    assert full.eval("T.args.modules.args.reload.type") == "execute"
    assert errors(full) == []


def test_general_tab_carries_the_same_switches(full):
    full.execute(CLIENT)
    args = full.eval("HogHeals.OptionsTable().args.general.args.modules.args")
    assert args["HogTron_Units"]["type"] == "toggle" and args["HogTron_Chat"]["get"] is not None
    assert full.eval("HogHeals.OptionsTable().args.general.args.modules.args.HogTron_Chat.get()") is False
    assert errors(full) == []


def test_a_client_without_the_apis_is_reported_not_raised(full):
    full.execute("C_AddOns = {}; GetAddOnInfo = nil; GetAddOnEnableState = nil; EnableAddOn = nil; DisableAddOn = nil")
    rows = {r["name"]: r for r in full.eval("HogHeals.Modules.Rows()").values()}
    assert len(rows) == 13 and rows["HogTron_Units"]["installed"] is None       # cannot tell: every module listed
    assert rows["HogTron_Units"]["enabled"] is True                                # loaded now = on
    assert full.eval('(HogHeals.Modules.Set("HogTron_Units", false))') is False
    assert "no EnableAddOn" in full.eval('select(2, HogHeals.Modules.Set("HogTron_Units", false))')
    full.execute('HogHeals:SlashCommand("modules")')
    assert errors(full) == []


def test_older_clients_with_the_global_api_and_reversed_arguments(full):
    full.execute('''
      C_AddOns = {}
      STATE = { HogTron_Units = 0 }
      function GetAddOnInfo(name) return name end
      function GetAddOnEnableState(who, name) ARGS = { who, name } return STATE[name] or 2 end
      function EnableAddOn(name, who) STATE[name] = 2 end
      function DisableAddOn(name, who) STATE[name] = 0 end
    ''')
    assert full.eval('HogHeals.Modules.Enabled("HogTron_Units")') is False
    assert list(full.eval("ARGS").values()) == ["Hognificent", "HogTron_Units"]
    assert full.eval('HogHeals.Modules.Set("HogTron_Units", true)') is True
    assert full.eval('HogHeals.Modules.Enabled("HogTron_Units")') is True
    assert errors(full) == []
