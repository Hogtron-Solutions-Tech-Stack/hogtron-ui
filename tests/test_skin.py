# HogHeals_Skin: Blizzard action bars / bags / bag bar / micro menu / tooltips restyled, plus the info bar.
# Every Blizzard name is looked up; the mock builds a small "client" with a few of each.
import pytest

CLIENT = r'''
-- action bar: art + two buttons (one with a normal texture, hotkey, macro name), page arrows
MainMenuBarTexture0 = UIParent:CreateTexture("MainMenuBarTexture0"); MainMenuBarTexture0:SetTexture("art")
MainMenuBarLeftEndCap = UIParent:CreateTexture("MainMenuBarLeftEndCap"); MainMenuBarLeftEndCap:SetTexture("gryphon")
MainMenuBar = CreateFrame("Frame", "MainMenuBar", UIParent)
MainMenuBar.EndCaps = CreateFrame("Frame", nil, MainMenuBar)
MainMenuBar.EndCaps.LeftEndCap = MainMenuBar.EndCaps:CreateTexture(); MainMenuBar.EndCaps.LeftEndCap:SetTexture("gryphon2")
ActionBarUpButton = CreateFrame("Button", "ActionBarUpButton", UIParent)
for i = 1, 2 do
  local b = CreateFrame("CheckButton", "ActionButton" .. i, UIParent, "SecureActionButtonTemplate")
  b._normal = b:CreateTexture("ActionButton" .. i .. "NormalTexture"); b._normal:SetTexture("Interface\\Buttons\\UI-Quickslot2")
  function b:GetNormalTexture() return self._normal end
  b.icon = b:CreateTexture("ActionButton" .. i .. "Icon"); b.icon:SetTexture("spell")
  b.HotKey = b:CreateFontString("ActionButton" .. i .. "HotKey", "OVERLAY", "GameFontNormal")
  b.Name = b:CreateFontString("ActionButton" .. i .. "Name", "OVERLAY", "GameFontNormal")
  b.Border = b:CreateTexture("ActionButton" .. i .. "Border"); b.Border:SetTexture("border")
end
-- micro menu + bag bar
for _, n in ipairs({ "CharacterMicroButton", "SpellbookMicroButton", "MainMenuMicroButton" }) do
  local b = CreateFrame("Button", n, UIParent)
  b._left = ({ CharacterMicroButton = 10, SpellbookMicroButton = 40, MainMenuMicroButton = 70 })[n]
  function b:GetLeft() return self._left end
  function b:GetRight() return self._left + 28 end
end
MicroButtonAndBagsBar = CreateFrame("Frame", "MicroButtonAndBagsBar", UIParent)
MicroButtonAndBagsBar.MicroBagBar = MicroButtonAndBagsBar:CreateTexture(); MicroButtonAndBagsBar.MicroBagBar:SetTexture("bagbar-art")
MainMenuBarBackpackButton = CreateFrame("CheckButton", "MainMenuBarBackpackButton", UIParent)
MainMenuBarBackpackButton.icon = MainMenuBarBackpackButton:CreateTexture()
function MainMenuBarBackpackButton:GetLeft() return 200 end
function MainMenuBarBackpackButton:GetRight() return 230 end
CharacterBag0Slot = CreateFrame("CheckButton", "CharacterBag0Slot", UIParent)
function CharacterBag0Slot:GetLeft() return 170 end
function CharacterBag0Slot:GetRight() return 199 end
-- a classic-style bag with two item slots
ContainerFrame1 = CreateFrame("Frame", "ContainerFrame1", UIParent)
ContainerFrame1:SetID(0)
ContainerFrame1BackgroundTop = ContainerFrame1:CreateTexture("ContainerFrame1BackgroundTop"); ContainerFrame1BackgroundTop:SetTexture("bagart")
ContainerFrame1Name = ContainerFrame1:CreateFontString("ContainerFrame1Name", "OVERLAY", "GameFontNormal")
ContainerFrame1CloseButton = CreateFrame("Button", "ContainerFrame1CloseButton", ContainerFrame1)
for i = 1, 2 do
  local it = CreateFrame("Button", "ContainerFrame1Item" .. i, ContainerFrame1)
  it:SetID(i)
  it.icon = it:CreateTexture()
  it.IconBorder = it:CreateTexture(); it.IconBorder:SetTexture("qualityborder")
end
ContainerFrame1:Hide()
QUALITY = { [1] = 2, [2] = 4 }
C_Container = { GetContainerItemInfo = function(bag, slot) return { quality = QUALITY[slot] } end,
                GetContainerNumFreeSlots = function(bag) return bag == 0 and 4 or 2 end,
                GetContainerNumSlots = function(bag) return bag == 0 and 16 or 6 end }
ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0 }, [4] = { r = 0.64, g = 0.21, b = 0.93 } }
function ContainerFrame_Update(frame) end
-- tooltip with a modern NineSlice
GameTooltip.NineSlice = CreateFrame("Frame", nil, GameTooltip)
GameTooltip.NineSlice:CreateTexture():SetTexture("tt-border")
GameTooltipStatusBar = CreateFrame("StatusBar", "GameTooltipStatusBar", GameTooltip)
function GameTooltip:SetOwner(owner, anchor) self._owner, self._anchor = owner, anchor end
function GameTooltip_SetDefaultAnchor(tt, parent) tt:SetOwner(parent, "ANCHOR_NONE") end
-- info bar sources
function GetMoney() return 1234567 end
function GetFramerate() return 72 end
function GetInventoryItemDurability(slot) if slot == 5 then return 20, 100 end if slot == 1 then return 80, 100 end return nil end
function ToggleAllBags() TOGGLED_BAGS = (TOGGLED_BAGS or 0) + 1 end
function IsInGuild() return true end
function GetNumGuildMembers() return 50, 7 end
function UnitXP() return 250 end
function UnitXPMax() return 1000 end
function GetXPExhaustion() return 100 end
NUM_BAG_SLOTS = 4
'''


@pytest.fixture
def skin(lua):
    lua.execute(CLIENT)
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Skin")
    lua.player_login()
    lua.execute('wipe(HogHeals.errors)')
    return lua


def errors(lua):
    return [e["msg"] for e in lua.eval('HogHeals.errors').values()]


def test_action_bar_art_cleared_and_kept_clear(skin):
    assert skin.eval('MainMenuBarTexture0._texture') is None and skin.eval('MainMenuBarTexture0._alpha') == 0
    assert skin.eval('MainMenuBar.EndCaps.LeftEndCap._alpha') == 0
    assert skin.eval('ActionBarUpButton:IsShown()') is False
    skin.execute('MainMenuBarTexture0:SetTexture("art-again"); MainMenuBarTexture0:SetAlpha(1); ActionBarUpButton:Show()')
    assert skin.eval('MainMenuBarTexture0._alpha') == 0                       # re-applied art stays invisible
    assert skin.eval('ActionBarUpButton:IsShown()') is False
    assert errors(skin) == []


def test_action_buttons_flattened(skin):
    assert skin.eval('ActionButton1.hhSkinned') is True
    assert skin.eval('ActionButton1._normal._alpha') == 0
    assert skin.eval('ActionButton1.Border._alpha') == 0
    assert skin.eval('ActionButton1.icon._last.SetTexCoord[1]') == pytest.approx(0.08)
    assert skin.eval('#ActionButton1.hh.edges') == 4
    assert skin.eval('ActionButton1.HotKey._last.SetFont[2]') == 10
    assert skin.eval('ActionButton1.Name._alpha') == 0                       # macro names hidden by default
    assert skin.eval('HogHealsSkin.ActionBars.count') == 2
    assert "ActionButton" in skin.eval('table.concat((function() local f = {} for k in pairs(HogHealsSkin.Skin.found) do f[#f+1] = k end return f end)(), ",")')


def test_micro_and_bag_strips(skin):
    assert skin.eval('MicroButtonAndBagsBar.MicroBagBar._alpha') == 0
    s = 'HogHealsSkin.Micro.strips.micro'
    assert skin.eval(f'{s}._points[1][2] == CharacterMicroButton') and skin.eval(f'{s}._points[2][2] == MainMenuMicroButton')
    b = 'HogHealsSkin.Micro.strips.bags'
    assert skin.eval(f'{b}._points[1][2] == CharacterBag0Slot') and skin.eval(f'{b}._points[2][2] == MainMenuBarBackpackButton')
    assert skin.eval('MainMenuBarBackpackButton.hhSkinned') is True
    assert errors(skin) == []


def test_bag_styled_on_show_with_quality_outlines(skin):
    assert skin.eval('ContainerFrame1.hh') is None                           # hidden bags are left until shown
    skin.execute('ContainerFrame1:Show(); ContainerFrame1:GetScript("OnShow")(ContainerFrame1)')
    assert skin.eval('ContainerFrame1BackgroundTop._alpha') == 0
    assert skin.eval('ContainerFrame1.hh.panel.bg._color[4]') == pytest.approx(0.85)
    assert skin.eval('ContainerFrame1CloseButton.hhX._text') == "x"
    assert skin.eval('ContainerFrame1Item1.hh.edges[1]._color[2]') == pytest.approx(1.0)      # uncommon green
    assert skin.eval('ContainerFrame1Item2.hh.edges[1]._color[3]') == pytest.approx(0.93)     # epic purple
    assert skin.eval('ContainerFrame1Item1.IconBorder._alpha') == 0                            # Blizzard's quality border off
    skin.execute('QUALITY[1] = 1; MockFire("BAG_UPDATE_DELAYED")')
    assert skin.eval('ContainerFrame1Item1.hh.edges[1]._color[2]') == pytest.approx(0.20)     # common: plain line
    assert errors(skin) == []


def test_tooltip_on_ink_panel(skin):
    assert skin.eval('GameTooltip.NineSlice._alpha') == 0
    assert skin.eval('GameTooltip.hh.panel.bg._color[4]') == pytest.approx(0.9)
    assert skin.eval('GameTooltipStatusBar._texture') == "Interface\\Buttons\\WHITE8X8"
    skin.execute('GameTooltip.NineSlice:SetAlpha(1); GameTooltip:GetScript("OnShow")(GameTooltip)')
    assert skin.eval('GameTooltip.NineSlice._alpha') == 0
    skin.execute('HogHeals.db.profile.skin.tooltips.anchorCursor = true; GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)')
    assert skin.eval('GameTooltip._anchor') == "ANCHOR_CURSOR"


def test_info_bar_readouts(skin):
    skin.execute('HogHealsSkin.InfoBar.Update()')
    texts = [skin.eval(f'HogUIInfoBar and HogHealsSkin.InfoBar.slots[{i}].text._text') for i in range(1, 7)]
    assert "123g" in texts[0] and "45s" in texts[0]
    assert "20%" in texts[1] and "d93636" in texts[1]                         # worst slot 20 % -> red
    assert "12|r / 40 bags" in texts[2]                                        # 4+2+2+2+2 free of 16+6+6+6+6
    assert "72" in texts[3] and "fps" in texts[3]
    assert "250" in texts[4] and "ms" in texts[4]
    assert texts[5] != "" and texts[5] != "-"
    skin.execute('HogHealsSkin.InfoBar.slots[3]:Click()')
    assert skin.eval('TOGGLED_BAGS') == 1
    assert errors(skin) == []


def test_info_bar_extra_providers_and_slot_config(skin):
    skin.execute('HogHeals.db.profile.skin.infoBar.slots = { "guild", "xp", "coords", "none" }; HogHealsSkin.InfoBar.Refresh()')
    assert skin.eval('HogHealsSkin.InfoBar.slots[1].text._text') == "7 guild"
    assert skin.eval('HogHealsSkin.InfoBar.slots[2].text._text').startswith("25% xp")
    assert skin.eval('HogHealsSkin.InfoBar.slots[5]:IsShown()') is False
    assert errors(skin) == []


def test_info_bar_ticks_and_drags_when_unlocked(skin):
    skin.execute('function GetFramerate() return 20 end; MockAdvance(1.1)')
    assert "20" in skin.eval('HogHealsSkin.InfoBar.slots[4].text._text')
    skin.execute('HogUIInfoBar:GetScript("OnDragStart")(HogUIInfoBar)')
    assert skin.eval('HogUIInfoBar._moving') is not True
    skin.execute('HogHeals.db.profile.locked = false; HogUIInfoBar:GetScript("OnDragStart")(HogUIInfoBar)')
    assert skin.eval('HogUIInfoBar._moving') is True


def test_skin_off_leaves_blizzard_alone(lua):
    lua.execute(CLIENT + 'HogHealsDB = { profileKeys = {}, profiles = { Default = { skin = { enabled = false } } } }')
    lua.load_addon("HogHeals")
    lua.load_addon("HogHeals_Skin")
    lua.player_login()
    assert lua.eval('MainMenuBarTexture0._texture') == "art"
    assert lua.eval('ActionButton1.hhSkinned') is None
    assert lua.eval('HogUIInfoBar') is None


def test_skindiag_and_options_walk(skin):
    skin.execute('wipe(MockLog.chat or {}); HogHeals:SlashCommand("skindiag")')
    chat = "\n".join(skin.eval('MockLog.chat').values())
    assert "found" in chat and "missing" in chat
    assert "MultiBarBottomLeftButton" in skin.eval('HogHeals.db.global.diag.skin.missing')
    skin.execute('''
      local function walk(t)
        for _, o in pairs(t.args or {}) do
          if o.get and o.set and o.type ~= "execute" then o.set({}, (o.get({}))) end
          if type(o.values) == "function" then o.values() end
          if o.args then walk(o) end
        end
      end
      walk(HogHeals.OptionsTable().args.Skin)
    ''')
    assert errors(skin) == []


def test_player_buffs_and_xp_bar_flattened(lua):
    lua.execute(CLIENT + """
      for i = 1, 2 do
        local b = CreateFrame("Button", "BuffButton" .. i, UIParent)
        b.Icon = b:CreateTexture("BuffButton" .. i .. "Icon")
        b.Duration = b:CreateFontString("BuffButton" .. i .. "Duration", "OVERLAY", "GameFontNormal")
      end
      local d = CreateFrame("Button", "DebuffButton1", UIParent)
      d.Icon = d:CreateTexture()
      d.Border = d:CreateTexture(); d.Border:SetVertexColor(0.2, 0.6, 1.0)
      MainMenuExpBar = CreateFrame("StatusBar", "MainMenuExpBar", UIParent)
      MainMenuXPBarTexture0 = UIParent:CreateTexture("MainMenuXPBarTexture0"); MainMenuXPBarTexture0:SetTexture("xp-art")
      function BuffFrame_Update() end
    """)
    lua.load_addon("HogHeals"); lua.load_addon("HogHeals_Skin"); lua.player_login()
    assert lua.eval('BuffButton1.hhSkinned') is True and lua.eval('BuffButton2.hhSkinned') is True
    assert lua.eval('BuffButton1.Duration._last.SetFont[2]') == 10
    assert lua.eval('DebuffButton1.hh.edges[1]._color[3]') == pytest.approx(1.0)      # follows the type colour
    assert lua.eval('MainMenuExpBar._texture').endswith("WHITE8X8")
    assert lua.eval('MainMenuXPBarTexture0._alpha') == 0
    # a buff button that appears later is picked up through Blizzard's update hook
    lua.execute("""
      local b = CreateFrame("Button", "BuffButton3", UIParent); b.Icon = b:CreateTexture()
      BuffFrame_Update()
    """)
    assert lua.eval('BuffButton3.hhSkinned') is True
    assert [e["msg"] for e in lua.eval('HogHeals.errors').values()] == []


def test_blizzard_window_styled_on_show_and_lod_window_caught_by_showuipanel(lua):
    lua.execute(CLIENT + """
      CharacterFrame = CreateFrame("Frame", "CharacterFrame", UIParent)
      CharacterFrame:CreateTexture("CharacterFramePortrait"):SetTexture("portrait")
      CharacterFrame.NineSlice = CreateFrame("Frame", nil, CharacterFrame)
      CharacterFrame.NineSlice:CreateTexture():SetTexture("border")
      CharacterFrame.TitleText = CharacterFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      CharacterFrame.CloseButton = CreateFrame("Button", nil, CharacterFrame)
      CharacterFrame:Hide()
      function ShowUIPanel(f) f:Show() end
    """)
    lua.load_addon("HogHeals"); lua.load_addon("HogHeals_Skin"); lua.player_login()
    assert lua.eval('CharacterFrame.hhPanel') is None
    lua.execute('CharacterFrame:Show(); CharacterFrame:GetScript("OnShow")(CharacterFrame)')
    assert lua.eval('CharacterFramePortrait._alpha') == 0 and lua.eval('CharacterFrame.NineSlice._alpha') == 0
    assert lua.eval('CharacterFrame.hhPanel.bg._color[4]') == pytest.approx(0.9)
    assert lua.eval('CharacterFrame.CloseButton.hhX._text') == "x"
    # a load-on-demand window that did not exist at login, opened through ShowUIPanel
    lua.execute("""
      MacroFrame = CreateFrame("Frame", "MacroFrame", UIParent)
      MacroFrame:CreateTexture("MacroFrameBg"):SetTexture("art")
      ShowUIPanel(MacroFrame)
    """)
    assert lua.eval('MacroFrame.hhPanel ~= nil') and lua.eval('MacroFrameBg._alpha') == 0
    # the escape hatch: a skipped window is left alone
    lua.execute("""
      HogHeals.db.profile.skin.panels.skip.MailFrame = true
      MailFrame = CreateFrame("Frame", "MailFrame", UIParent); ShowUIPanel(MailFrame)
    """)
    assert lua.eval('MailFrame.hhPanel') is None
    assert [e["msg"] for e in lua.eval('HogHeals.errors').values()] == []


def test_vendor_sells_junk_and_repairs(lua):
    lua.execute(CLIENT + """
      SOLD, REPAIRED = {}, nil
      QUAL = { [1] = 0, [2] = 2, [3] = 0, [4] = 0 }
      C_Container.GetContainerItemInfo = function(bag, slot) if bag ~= 0 then return nil end local q = QUAL[slot] if q == nil then return nil end return { quality = q, stackCount = 2, hyperlink = "item" .. slot, hasNoValue = (slot == 4) } end
      C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 4 or 0 end
      C_Container.UseContainerItem = function(bag, slot) SOLD[#SOLD + 1] = slot end
      function GetItemInfo(link) return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 150 end
      function CanMerchantRepair() return true end
      function GetRepairAllCost() return 2500, true end
      function GetMoney() return 10000 end
      function RepairAllItems(guild) REPAIRED = guild or false end
      function SetCVar(k, v) CVARS = CVARS or {}; CVARS[k] = v end
    """)
    lua.load_addon("HogHeals"); lua.load_addon("HogHeals_Skin"); lua.player_login()
    lua.execute('wipe(MockLog.chat or {}); MockFire("MERCHANT_SHOW"); MockAdvance(0.4)')
    assert list(lua.eval('SOLD').values()) == [1, 3]                 # greys with a value only
    assert lua.eval('REPAIRED') is False                              # own gold, not guild
    chat = "\n".join(lua.eval('MockLog.chat').values())
    assert "sold 2 junk" in chat and "6s" in chat and "repaired for 25s" in chat
    assert lua.eval('CVARS.countdownForCooldowns') == "1"
    lua.execute('function GetMoney() return 100 end; HogHeals.db.profile.skin.auto.sellJunk = false; wipe(SOLD); REPAIRED = nil; wipe(MockLog.chat); MockFire("MERCHANT_SHOW"); MockAdvance(0.4)')
    assert lua.eval('#SOLD') == 0 and lua.eval('REPAIRED') is None
    assert "not enough gold" in "\n".join(lua.eval('MockLog.chat').values())


def test_vendor_classic_item_api_path(lua):
    lua.execute(CLIENT + """
      C_Container = nil
      SOLD = {}
      function GetContainerNumSlots(bag) return bag == 0 and 3 or 0 end
      function GetContainerItemInfo(bag, slot)
        local q = ({ [1] = 0, [2] = 0, [3] = 1 })[slot]
        return "icon", 1, false, q, false, false, "link" .. slot, false, slot == 2   -- slot 2: grey but no value
      end
      function UseContainerItem(bag, slot) SOLD[#SOLD + 1] = slot end
      function GetItemInfo() return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 40 end
      function CanMerchantRepair() return false end
    """)
    lua.load_addon("HogHeals"); lua.load_addon("HogHeals_Skin"); lua.player_login()
    lua.execute('wipe(MockLog.chat or {}); MockFire("MERCHANT_SHOW"); MockAdvance(0.4)')
    assert list(lua.eval('SOLD').values()) == [1]
    assert "sold 1 junk for ~40c" in "\n".join(lua.eval('MockLog.chat').values())


def test_parchment_windows_recoloured_and_stripped_deep_but_buttons_and_icons_kept(lua):
    lua.execute(CLIENT + """
      QuestFont = CreateFont("QuestFont"); QuestTitleFont = CreateFont("QuestTitleFont")
      GossipFrame = CreateFrame("Frame", "GossipFrame", UIParent)
      GossipFrame:CreateTexture("GossipFrameBg"):SetTexture("parchment-outer")
      local panel = CreateFrame("Frame", "GossipFrameGreetingPanel", GossipFrame)
      local scroll = CreateFrame("ScrollFrame", "GossipGreetingScrollFrame", panel)
      scroll:CreateTexture("GossipGreetingScrollFrameTop"):SetTexture("parchment-inner")
      local btn = CreateFrame("Button", "GossipTitleButton1", scroll)
      btn:CreateTexture("GossipTitleButton1Art"):SetTexture("button-art")
      btn:CreateTexture("GossipTitleButton1Icon"):SetTexture("quest-icon")
      local bar = CreateFrame("Slider", "GossipGreetingScrollFrameScrollBar", scroll)
      bar:CreateTexture("GossipGreetingScrollFrameScrollBarThumb"):SetTexture("thumb")
      function ShowUIPanel(f) f:Show() end
    """)
    lua.load_addon("HogHeals"); lua.load_addon("HogHeals_Skin"); lua.player_login()
    lua.execute('ShowUIPanel(GossipFrame)')
    assert lua.eval('GossipFrame.hhPanel ~= nil')
    assert lua.eval('GossipFrameBg._alpha') == 0 and lua.eval('GossipGreetingScrollFrameTop._alpha') == 0
    assert lua.eval('GossipTitleButton1Art._texture') == "button-art"          # buttons untouched
    assert lua.eval('GossipTitleButton1Icon._texture') == "quest-icon"
    assert lua.eval('GossipGreetingScrollFrameScrollBarThumb._texture') == "thumb" # scroll bar untouched
    assert lua.eval('QuestFont._color[1]') == pytest.approx(0.96)                 # cream body text
    assert lua.eval('QuestTitleFont._color[2]') == pytest.approx(0.65)            # amber titles
    assert [e["msg"] for e in lua.eval('HogHeals.errors').values()] == []


def test_world_map_still_skipped_by_default(lua):
    lua.execute(CLIENT + """
      WorldMapFrame = CreateFrame("Frame", "WorldMapFrame", UIParent); WorldMapFrame:CreateTexture("WorldMapFrameBg"):SetTexture("map-art")
      function ShowUIPanel(f) f:Show() end
    """)
    lua.load_addon("HogHeals"); lua.load_addon("HogHeals_Skin"); lua.player_login()
    lua.execute('ShowUIPanel(WorldMapFrame)')
    assert lua.eval('WorldMapFrame.hhPanel') is None and lua.eval('WorldMapFrameBg._texture') == "map-art"


def test_dark_gossip_text_lifted_to_cream_on_show_and_on_content_events(lua):
    lua.execute(CLIENT + """
      GossipFrame = CreateFrame("Frame", "GossipFrame", UIParent)
      local panel = CreateFrame("Frame", nil, GossipFrame)
      local scroll = CreateFrame("ScrollFrame", nil, panel)
      GREET = scroll:CreateFontString("GossipGreetingText", "OVERLAY", "GameFontNormal"); GREET:SetTextColor(0.18, 0.12, 0.06)
      OPTION = scroll:CreateFontString(nil, "OVERLAY", "GameFontNormal"); OPTION:SetTextColor(1, 0.82, 0)
      function ShowUIPanel(f) f:Show() end
    """)
    lua.load_addon("HogHeals"); lua.load_addon("HogHeals_Skin"); lua.player_login()
    lua.execute('ShowUIPanel(GossipFrame)')
    assert lua.eval('GREET._color[1]') == pytest.approx(0.96)                      # dark brown -> cream
    assert lua.eval('OPTION._color[2]') == pytest.approx(0.82)                     # gold option text untouched
    # Blizzard rebuilds the greeting on GOSSIP_SHOW with its dark colour again
    lua.execute('GREET:SetTextColor(0.18, 0.12, 0.06); MockFire("GOSSIP_SHOW"); MockAdvance(0.1)')
    assert lua.eval('GREET._color[1]') == pytest.approx(0.96)
    assert [e["msg"] for e in lua.eval('HogHeals.errors').values()] == []


def test_flight_map_left_alone_by_default(lua):
    lua.execute(CLIENT + """
      TaxiFrame = CreateFrame("Frame", "TaxiFrame", UIParent); TaxiFrame:CreateTexture("TaxiMap1"):SetTexture("map-tile")
      function ShowUIPanel(f) f:Show() end
    """)
    lua.load_addon("HogHeals"); lua.load_addon("HogHeals_Skin"); lua.player_login()
    lua.execute('ShowUIPanel(TaxiFrame)')
    assert lua.eval('TaxiFrame.hhPanel') is None and lua.eval('TaxiMap1._texture') == "map-tile"


def test_late_built_gossip_option_lines_lifted_and_kept_through_hover_repaint(lua):
    lua.execute(CLIENT + """
      GossipFrame = CreateFrame("Frame", "GossipFrame", UIParent)
      SCROLL = CreateFrame("ScrollFrame", nil, GossipFrame)
      function ShowUIPanel(f) f:Show() end
    """)
    lua.load_addon("HogHeals"); lua.load_addon("HogHeals_Skin"); lua.player_login()
    lua.execute('ShowUIPanel(GossipFrame)')
    # option line created after the window is shown, dark grey like the quest lines in game
    lua.execute("""
      local b = CreateFrame("Button", nil, SCROLL)
      OPT = b:CreateFontString(nil, "OVERLAY", "GameFontNormal"); OPT:SetTextColor(0.35, 0.35, 0.35)
      MockAdvance(0.3)
    """)
    assert lua.eval('OPT._color[1]') == pytest.approx(0.96)
    lua.execute('OPT:SetTextColor(0.35, 0.35, 0.35)')                        # Blizzard hover repaint
    assert lua.eval('OPT._color[1]') == pytest.approx(0.96)
    lua.execute('OPT:SetTextColor(1, 0.82, 0)')                               # gold stays gold
    assert lua.eval('OPT._color[2]') == pytest.approx(0.82)


FOREVER_BAGS = """
  SOLD = {}
  GetItemInfo = nil                                   -- measured on Forever: the global is gone
  C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 3 or 0 end
  C_Container.GetContainerItemInfo = function(bag, slot)
    if bag ~= 0 then return nil end
    return { quality = 0, stackCount = 4, hyperlink = "item" .. slot, hasNoValue = false }
  end
  C_Container.UseContainerItem = function(bag, slot) SOLD[#SOLD + 1] = slot end
  function CanMerchantRepair() return false end
"""


def test_vendor_price_from_c_item_when_global_is_gone(lua):
    # in game 2026-09-28: "sold 4 junk for ~0c" - price was read from a global that does not exist on Forever
    lua.execute(CLIENT + FOREVER_BAGS + """
      C_Item = C_Item or {}
      C_Item.GetItemInfo = function(link) return "n", link, 0, 5, 0, "t", "s", 20, "", 1, 46 end
    """)
    lua.load_addon("HogHeals"); lua.load_addon("HogHeals_Skin"); lua.player_login()
    lua.execute('wipe(MockLog.chat or {}); MockFire("MERCHANT_SHOW"); MockAdvance(0.4)')
    assert list(lua.eval('SOLD').values()) == [1, 2, 3]
    chat = "\n".join(lua.eval('MockLog.chat').values())
    assert "sold 3 junk for ~5s 52c" in chat                         # 3 stacks x 4 x 46c
    assert [e["msg"] for e in lua.eval('HogHeals.errors').values()] == []


def test_vendor_never_prints_zero_copper_for_unknown_prices(lua):
    lua.execute(CLIENT + FOREVER_BAGS + """
      C_Item = C_Item or {}
      C_Item.GetItemInfo = function(link) if link == "item2" then return nil end return "n", link, 0, 5, 0, "t", "s", 20, "", 1, 10 end
    """)
    lua.load_addon("HogHeals"); lua.load_addon("HogHeals_Skin"); lua.player_login()
    lua.execute('wipe(MockLog.chat or {}); MockFire("MERCHANT_SHOW"); MockAdvance(0.4)')
    chat = "\n".join(lua.eval('MockLog.chat').values())
    assert "sold 3 junk for at least 80c" in chat                    # one stack uncached: 2 x 4 x 10c known
    lua.execute('C_Item.GetItemInfo = nil; wipe(SOLD); wipe(MockLog.chat); MockFire("MERCHANT_SHOW"); MockAdvance(0.4)')
    chat = "\n".join(lua.eval('MockLog.chat').values())
    assert "sold 3 junk." in chat and "0c" not in chat               # no item API at all: count only
