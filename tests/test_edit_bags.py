# Edit mode moves the bags (Sean 2026-11-06: "I want to be able to move the bag in the hogtron edit mode").
# Blizzard lays the open bags out itself on every open (UpdateContainerFrameAnchors): the first bag in the bottom-right
# corner, the next stacked on it, a full column -> a new column to the left. With a place saved, after each pass the
# first bag goes onto our anchor and the other column starts keep their distance from it.
import pytest

from test_bars import CLIENT, EXTRA_CLIENT

# Blizzard's layout pass, the way the modern client does it: bags in the order opened, first one in the corner
BAGS_CLIENT = r'''
ContainerFrameContainer = CreateFrame("Frame", "ContainerFrameContainer", UIParent)
for i = 1, 3 do
  local f = CreateFrame("Frame", "ContainerFrame" .. i, ContainerFrameContainer)
  f:SetSize(180, 220)
  f.TitleContainer = { TitleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal") }   -- the modern title
  f:Hide()
end
ContainerFrameCombinedBags = CreateFrame("Frame", "ContainerFrameCombinedBags", ContainerFrameContainer)
ContainerFrameCombinedBags:SetSize(400, 300)
ContainerFrameCombinedBags.TitleContainer = { TitleText = ContainerFrameCombinedBags:CreateFontString(nil, "OVERLAY", "GameFontNormal") }
ContainerFrameCombinedBags:Hide()
LAYOUTS = 0
function UpdateContainerFrameAnchors()
  LAYOUTS = LAYOUTS + 1
  local order = {}
  for _, n in ipairs({ "ContainerFrameCombinedBags", "ContainerFrame1", "ContainerFrame2", "ContainerFrame3" }) do
    if _G[n]:IsShown() then order[#order + 1] = _G[n] end
  end
  for i, f in ipairs(order) do
    f:ClearAllPoints()
    if i == 1 then f:SetPoint("BOTTOMRIGHT", f:GetParent(), "BOTTOMRIGHT", -40, 90)
    elseif i == 3 then f:SetPoint("BOTTOMRIGHT", f:GetParent(), "BOTTOMRIGHT", -220, 90)    -- a new column
    else f:SetPoint("BOTTOMRIGHT", order[i - 1], "TOPRIGHT", 0, 5) end                  -- stacked on the last
  end
end
function OpenBags(...)
  for _, n in ipairs({ ... }) do _G[n]:Show() local s = _G[n]:GetScript("OnShow") if s then s(_G[n]) end end
  UpdateContainerFrameAnchors()
end
'''


@pytest.fixture
def ed(lua):
    lua.execute(CLIENT + EXTRA_CLIENT + BAGS_CLIENT)
    for a in ("HogTronUI", "HogHeals_Frames", "HogTron_HUD", "HogTron_Units", "HogTron_Quests", "HogTron_Skin", "HogTron_Bars", "HogTron_Meter"):
        lua.load_addon(a)
    lua.player_login()
    lua.execute("""
      UIParent._cx, UIParent._cy = 960, 540
      function UIParent:GetCenter() return 960, 540 end
      wipe(HogHeals.errors)
    """)
    return lua


def errors(lua):
    return [e["msg"] for e in lua.eval("HogHeals.errors").values()]


def test_unlock_gives_the_bags_a_box_even_with_the_bags_closed(ed):
    ed.execute('HogHeals:SlashCommand("unlock")')
    keys = [t["key"] for t in ed.eval("HogHeals.EditMode.Targets()").values()]
    assert "bags" in keys
    b = "HogHeals.EditMode.boxes['bags']"
    assert ed.eval(f"{b}:IsShown()") is True and ed.eval(f"{b}.label._text") == "Bags"
    assert ed.eval(f"{b}._points[1][2] == HogUIBagsAnchor") is True
    # nothing saved: the box sits in Blizzard's corner, bag-sized, and no bag was touched
    assert ed.eval("HogUIBagsAnchor._points[1][1]") == "BOTTOMRIGHT" and ed.eval("HogUIBagsAnchor._points[1][3]") == "BOTTOMRIGHT"
    assert ed.eval("HogUIBagsAnchor:GetWidth()") == 200
    assert ed.eval("HogHeals.db.profile.edit.bags") is None
    assert errors(ed) == []


def test_no_place_saved_leaves_blizzards_layout_alone(ed):
    ed.execute('OpenBags("ContainerFrame1", "ContainerFrame2")')
    assert ed.eval("ContainerFrame1._points[1][2] == ContainerFrameContainer") is True
    assert ed.eval("ContainerFrame1._points[1][4]") == -40 and ed.eval("ContainerFrame1._points[1][5]") == 90
    assert ed.eval("ContainerFrame2._points[1][2] == ContainerFrame1") is True
    assert ed.eval("HogHeals.EditMode.PlaceBags('test')") == 0
    assert errors(ed) == []


def test_dragging_the_box_saves_the_corner_and_moves_the_open_bags(ed):
    ed.execute('HogHeals.db.profile.edit.snap = false; OpenBags("ContainerFrame1", "ContainerFrame2")')
    ed.execute('HogHeals:SlashCommand("unlock")')
    b = "HogHeals.EditMode.boxes['bags']"
    # unlocked with the bags open: the box starts sized like the first bag
    assert ed.eval("HogUIBagsAnchor:GetWidth()") == 180 and ed.eval("HogUIBagsAnchor:GetHeight()") == 220
    ed.execute(f'{b}:GetScript("OnDragStart")({b})')
    assert ed.eval("HogUIBagsAnchor._moving") is True                           # the anchor's own drag script ran
    ed.execute(f'HogUIBagsAnchor._points = {{ {{ "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -300, 400 }} }}; {b}:GetScript("OnDragStop")({b})')
    assert ed.eval("HogUIBagsAnchor._moving") is False
    saved = ed.eval("HogHeals.db.profile.edit.bags")
    assert saved["point"] == "BOTTOMRIGHT" and saved["x"] == -300 and saved["y"] == 400
    # the first bag hangs on the anchor at once, the stacked one still on the first
    assert ed.eval("ContainerFrame1._points[1][2] == HogUIBagsAnchor") is True
    assert ed.eval("ContainerFrame1._points[1][1]") == "BOTTOMRIGHT" and ed.eval("ContainerFrame1._points[1][4]") == 0
    assert ed.eval("ContainerFrame2._points[1][2] == ContainerFrame1") is True
    ed.execute(f'{b}:GetScript("OnMouseUp")({b}, "LeftButton")')
    assert ed.eval("HogHeals.Panel.frame == nil or not HogHeals.Panel.frame:IsShown()") is True   # a drag is not a click
    assert errors(ed) == []


def test_every_blizzard_pass_puts_the_stack_back_on_the_anchor_columns_keep_their_gap(ed):
    ed.execute("""
      HogHeals.db.profile.edit.bags = { point = "BOTTOMRIGHT", x = -500, y = 300 }
      HogHeals:SlashCommand("unlock"); HogHeals:SlashCommand("lock")
      OpenBags("ContainerFrame1", "ContainerFrame2", "ContainerFrame3")
    """)
    assert ed.eval("HogUIBagsAnchor._points[1][4]") == -500 and ed.eval("HogUIBagsAnchor._points[1][5]") == 300
    assert ed.eval("ContainerFrame1._points[1][2] == HogUIBagsAnchor") is True
    assert ed.eval("ContainerFrame2._points[1][2] == ContainerFrame1") is True                 # stacked: untouched
    # the second column: on the first bag, as far left of it as Blizzard put it (-220 - -40 = -180)
    assert ed.eval("ContainerFrame3._points[1][2] == ContainerFrame1") is True
    assert ed.eval("ContainerFrame3._points[1][4]") == -180 and ed.eval("ContainerFrame3._points[1][5]") == 0
    # Blizzard lays them out again (another bag opened, closed ...): ours again, nothing doubled
    ed.execute("UpdateContainerFrameAnchors(); UpdateContainerFrameAnchors()")
    assert ed.eval("ContainerFrame1._points[1][2] == HogUIBagsAnchor") is True and ed.eval("ContainerFrame1._points[1][4]") == 0
    assert ed.eval("ContainerFrame3._points[1][4]") == -180
    # already placed: a second call moves nothing
    assert ed.eval("HogHeals.EditMode.PlaceBags('again')") == 0
    assert ed.eval("HogHeals.db.global.diag.bags.last.lead") == "ContainerFrame1"
    assert errors(ed) == []


def test_combined_bags_follow_too(ed):
    ed.execute("""
      HogHeals.db.profile.edit.bags = { point = "BOTTOMRIGHT", x = -100, y = 500 }
      OpenBags("ContainerFrameCombinedBags")
    """)
    assert ed.eval("ContainerFrameCombinedBags._points[1][2] == HogUIBagsAnchor") is True
    assert errors(ed) == []


def test_the_saved_place_is_the_anchors_screen_corner_when_the_client_has_its_rect(ed):
    ed.execute("""
      HogHeals.db.profile.edit.snap = false
      HogHeals:SlashCommand("unlock")
      function UIParent:GetWidth() return 1920 end
      function HogUIBagsAnchor:GetRight() return 1700 end
      function HogUIBagsAnchor:GetBottom() return 250 end
      HogUIBagsAnchor._points = { { "TOPLEFT", UIParent, "TOPLEFT", 1500, -600 } }
      HogUIBagsAnchor:GetScript("OnDragStop")(HogUIBagsAnchor)
    """)
    saved = ed.eval("HogHeals.db.profile.edit.bags")
    assert saved["point"] == "BOTTOMRIGHT" and saved["x"] == -220 and saved["y"] == 250
    assert ed.eval("HogUIBagsAnchor._points[1][1]") == "BOTTOMRIGHT" and ed.eval("HogUIBagsAnchor._points[1][4]") == -220
    assert errors(ed) == []


def test_protected_bags_wait_for_the_end_of_combat(ed):
    ed.execute("""
      HogHeals.db.profile.edit.bags = { point = "BOTTOMRIGHT", x = -100, y = 500 }
      ContainerFrame1._protected = true
      MockState.inCombat = true
      OpenBags("ContainerFrame1")
    """)
    assert ed.eval("ContainerFrame1._points[1][2] == ContainerFrameContainer") is True       # not touched in combat
    ed.execute('MockState.inCombat = false; MockFire("PLAYER_REGEN_ENABLED")')
    assert ed.eval("ContainerFrame1._points[1][2] == HogUIBagsAnchor") is True
    assert errors(ed) == []


def test_blizzards_place_button_forgets_ours(ed):
    ed.execute("""
      HogHeals.db.profile.edit.bags = { point = "BOTTOMRIGHT", x = -100, y = 500 }
      HogHeals:SlashCommand("unlock")
    """)
    acts = ed.eval("HogHeals.Panel.ActionsFor('bags')")
    labels = [a["text"] for a in acts.values()]
    assert labels == ["Open bags", "Blizzard's place"]
    ed.execute("HogHeals.Panel.ActionsFor('bags')[2].func()")
    assert ed.eval("HogHeals.db.profile.edit.bags") is None
    ed.execute('OpenBags("ContainerFrame1")')
    assert ed.eval("ContainerFrame1._points[1][2] == ContainerFrameContainer") is True
    assert errors(ed) == []


def test_movediag_reports_the_bags(ed):
    ed.execute("""
      HogHeals.db.profile.edit.bags = { point = "BOTTOMRIGHT", x = -100, y = 500 }
      OpenBags("ContainerFrame1")
    """)
    lines = list(ed.eval("HogHeals.EditMode.MoveDiagnose()").values())
    bags = [l for l in lines if l.strip().startswith("bags:")]
    assert bags and "BOTTOMRIGHT -100,500" in bags[0] and "UpdateContainerFrameAnchors" in bags[0] and "ContainerFrame1" in bags[0]
    assert errors(ed) == []
