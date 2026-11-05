# Blizzard's own layout pass can no longer undo a place edit mode remembered: an Edit Mode system's UpdateSystem /
# ApplySystemAnchor is post-hooked, EDIT_MODE_LAYOUTS_UPDATED re-applies, and for a minute after every world entry a
# watch puts back a frame moved by anything else (HogTronUI/Core/EditMode.lua: Guard / Watch / Log / PutBack).
# Sean 2026-11-05: "I just move the buffs and resize the chat, and it's not saving my changes. So if I reload or load
# screen, it changes every time."
from test_edit_mode import ed, errors, CHAT_WINDOWS  # noqa: F401 (fixture)

SYSTEMS = '''
BuffFrame = CreateFrame("Frame", "BuffFrame", UIParent)
BuffFrame:SetSize(300, 60)
function BuffFrame:ApplySystemAnchor() self:ClearAllPoints(); self:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -328, -20) end
function BuffFrame:UpdateSystem(info) self:ApplySystemAnchor() end
BuffFrame:ApplySystemAnchor()
EditModeManagerFrame = CreateFrame("Frame", "EditModeManagerFrame", UIParent)
EditModeManagerFrame.active = false
function EditModeManagerFrame:IsEditModeActive() return self.active end
function EditModeManagerFrame:OnSystemPositionChange(frame) end
function EditModeManagerFrame:OnSystemSettingChange(frame, setting, value) end
HogHeals.db.profile.edit.blizzard = { BuffFrame = { point = "CENTER", x = 905, y = 512 } }
'''


def where(lua, f):
    return lua.eval(f'({f}._points[1] and ({f}._points[1][1] .. " " .. {f}._points[1][4] .. "," .. {f}._points[1][5])) or "none"')


def log(lua):
    return list(lua.eval("HogHeals.EditMode.log or {}").values())


def test_blizzards_layout_pass_is_undone_at_once_for_a_remembered_frame(ed):
    ed.execute(SYSTEMS)
    assert ed.eval("HogHeals.EditMode.ApplyBlizzard('login')") == 1
    assert where(ed, "BuffFrame") == "CENTER 905,512"
    assert sorted(ed.eval("HogHeals.EditMode.guarded.BuffFrame").values()) == ["ApplySystemAnchor", "UpdateSystem"]
    ed.execute("BuffFrame:UpdateSystem({})")                      # the layout arrives late (EDIT_MODE_LAYOUTS_UPDATED) and re-anchors
    assert where(ed, "BuffFrame") == "CENTER 905,512"
    ed.execute("BuffFrame:ApplySystemAnchor()")
    assert where(ed, "BuffFrame") == "CENTER 905,512"
    assert {e["why"] for e in log(ed)} >= {"hook:UpdateSystem", "hook:ApplySystemAnchor"}
    # while Blizzard's own Edit Mode is open the player is arranging there: its layout stands
    ed.execute("EditModeManagerFrame.active = true; BuffFrame:UpdateSystem({})")
    assert where(ed, "BuffFrame") == "TOPRIGHT -328,-20"
    # ... and a move made there hands the frame back to Blizzard for good
    ed.execute("EditModeManagerFrame:OnSystemPositionChange(BuffFrame); EditModeManagerFrame.active = false")
    assert ed.eval("HogHeals.db.profile.edit.blizzard.BuffFrame") is None
    ed.execute("BuffFrame:UpdateSystem({})")
    assert where(ed, "BuffFrame") == "TOPRIGHT -328,-20"
    assert log(ed)[-1]["why"] == "blizzard-edit"
    assert errors(ed) == []


def test_a_late_layout_event_and_a_silent_move_both_get_undone(ed):
    ed.execute(SYSTEMS + "BuffFrame.UpdateSystem = nil; BuffFrame.ApplySystemAnchor = nil")   # a buff frame that is no Edit Mode system
    ed.fire("PLAYER_ENTERING_WORLD")
    assert where(ed, "BuffFrame") == "CENTER 905,512" and list(ed.eval("HogHeals.EditMode.guarded.BuffFrame").values()) == []
    ed.execute("BuffFrame:ClearAllPoints(); BuffFrame:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', -328, -20)")
    ed.fire("EDIT_MODE_LAYOUTS_UPDATED")
    assert ed.eval("HogHeals.EditMode.lastApply.why") == "layouts" and where(ed, "BuffFrame") == "CENTER 905,512"
    # moved by something there is no hook for, 9 s in: the watch puts it back within 2 s and writes down where it had gone
    ed.execute("MockAdvance(9); BuffFrame:ClearAllPoints(); BuffFrame:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', -328, -20)")
    assert where(ed, "BuffFrame") == "TOPRIGHT -328,-20"
    ed.execute("MockAdvance(2.5)")
    assert where(ed, "BuffFrame") == "CENTER 905,512"
    e = log(ed)[-1]
    assert e["why"] == "drift" and e["name"] == "BuffFrame" and e["from"] == "TOPRIGHT -328,-20" and 11 <= e["at"] <= 12
    # the watch ends a minute after the last world entry; the diag keeps what happened for a logout read
    ed.execute("MockAdvance(70); BuffFrame:ClearAllPoints(); BuffFrame:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', -328, -20); MockAdvance(5)")
    assert where(ed, "BuffFrame") == "TOPRIGHT -328,-20" and ed.eval("HogHeals.EditMode.watching") is False
    assert ed.eval("HogHeals.db.global.diag.moves.events[1].why") is not None
    assert list(ed.eval("HogHeals.db.global.diag.moves.guards.BuffFrame").values()) == []
    lines = list(ed.eval("HogHeals.EditMode.MoveDiagnose()").values())
    assert any("drift" in l and "TOPRIGHT -328,-20" in l for l in lines), lines
    assert any("guards:" in l for l in lines)
    ed.execute('HogHeals:SlashCommand("movediag")')
    assert errors(ed) == []


def test_chat_windows_keep_blizzards_own_saved_size_through_its_layout_pass(ed):
    ed.execute(CHAT_WINDOWS + '''
      RESTORED = {}
      function FCF_RestorePositionAndDimensions(cf) RESTORED[#RESTORED + 1] = cf:GetName(); cf:SetSize(564, 285) end
      for i = 1, 3 do local cf = _G["ChatFrame" .. i]; function cf:UpdateSystem() self:SetSize(430, 120) end end
      EditModeManagerFrame = CreateFrame("Frame", "EditModeManagerFrame", UIParent)
      function EditModeManagerFrame:IsEditModeActive() return false end
    ''')
    ed.fire("PLAYER_ENTERING_WORLD")                                                 # the guards go on every chat window
    ed.execute("ChatFrame1:UpdateSystem({})")                                        # the layout sizes it back to its own number
    assert ed.eval("ChatFrame1._width") == 564 and list(ed.eval("RESTORED").values()) == ["ChatFrame1"]
    # a window edit mode sized itself: our record wins, Blizzard's cache is not consulted
    ed.execute("HogHeals.db.profile.edit.blizzard = { ChatFrame2 = { point = 'BOTTOMLEFT', x = 30, y = 120, w = 600, h = 300, sized = true } }; HogHeals.EditMode.ApplyBlizzard('login')")
    ed.execute("ChatFrame2:UpdateSystem({})")
    assert ed.eval("ChatFrame2._width") == 600 and where(ed, "ChatFrame2") == "BOTTOMLEFT 30,120"
    assert list(ed.eval("RESTORED").values()) == ["ChatFrame1"]
    assert errors(ed) == []


def test_a_place_that_cannot_be_read_is_written_down_not_lost_quietly(ed):
    ed.execute('X = CreateFrame("Frame", "X", UIParent)')                            # no point at all
    assert ed.eval("HogHeals.EditMode.RememberFrame(X)") is False
    e = log(ed)[-1]
    assert e["why"] == "remember-failed" and e["name"] == "X"
    assert errors(ed) == []
