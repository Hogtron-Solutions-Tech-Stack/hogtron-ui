# Sean 2026-11-05: "the chat window keeps moving even after I save it." Edit mode now keeps a chat window's place and
# size in the profile too and puts them back at login and on every world entry, after Blizzard's own layout pass.
from test_edit_mode import ed, errors, CHAT_WINDOWS  # noqa: F401 (fixture)


def test_a_chat_window_place_and_size_are_remembered_and_put_back(ed):
    ed.execute(CHAT_WINDOWS)
    ed.execute('HogHeals.db.profile.edit.snap = false; HogHeals:SlashCommand("unlock")')
    b = "HogHeals.EditMode.boxes['chat:2']"
    ed.execute(f'{b}:GetScript("OnDragStart")({b}); ChatFrame2._points = {{ {{ "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 30, 120 }} }}; {b}:GetScript("OnDragStop")({b})')
    rec = "HogHeals.db.profile.edit.blizzard.ChatFrame2"
    assert ed.eval(f"{rec}.point") == "BOTTOMLEFT" and ed.eval(f"{rec}.x") == 30 and ed.eval(f"{rec}.y") == 120
    assert ed.eval(f"{rec}.w") == 400 and ed.eval(f"{rec}.h") == 200 and ed.eval(f"{rec}.sized") is True
    # Blizzard's layout moves and shrinks it; a world entry puts ours back
    ed.execute("ChatFrame2:ClearAllPoints(); ChatFrame2:SetPoint('CENTER', UIParent, 'CENTER', 0, 0); ChatFrame2:SetSize(10, 10)")
    ed.fire("PLAYER_ENTERING_WORLD")
    assert ed.eval("HogHeals.EditMode.lastApply.why") == "world" and ed.eval("HogHeals.EditMode.lastApply.n") >= 1
    assert ed.eval("ChatFrame2._points[1][1]") == "BOTTOMLEFT" and ed.eval("ChatFrame2._points[1][4]") == 30
    assert ed.eval("ChatFrame2._width") == 400 and ed.eval("ChatFrame2._height") == 200
    ed.execute("ChatFrame2:ClearAllPoints(); MockAdvance(1.5)")                     # the second pass, a second later
    assert ed.eval("HogHeals.EditMode.lastApply.why") == "world+1" and ed.eval("ChatFrame2._points[1][1]") == "BOTTOMLEFT"
    lines = list(ed.eval("HogHeals.EditMode.MoveDiagnose()").values())
    assert lines[0].startswith("remembered places: 1   last put back: world+1")
    assert any("ChatFrame2: saved BOTTOMLEFT 30,120 400x200" in l for l in lines)
    ed.execute('HogHeals:SlashCommand("movediag")')
    assert errors(ed) == []


def test_buff_frame_records_keep_their_old_shape_and_no_size(ed):
    ed.execute('BuffFrame = CreateFrame("Frame", "BuffFrame", UIParent); BuffFrame:SetSize(300, 60); BuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -10)')
    ed.execute('HogHeals.db.profile.edit.snap = false; HogHeals:SlashCommand("unlock")')
    b = "HogHeals.EditMode.boxes['blizzard:BuffFrame']"
    ed.execute(f'{b}:GetScript("OnDragStart")({b}); {b}:GetScript("OnDragStop")({b})')
    rec = "HogHeals.db.profile.edit.blizzard.BuffFrame"
    assert ed.eval(f"{rec}.point") == "TOPRIGHT" and ed.eval(f"{rec}.sized") is None     # Blizzard sizes its own buffs
    ed.execute("BuffFrame:SetSize(1, 1); HogHeals.EditMode.ApplyBlizzard('test')")
    assert ed.eval("BuffFrame._width") == 1                                                # size left alone
    assert errors(ed) == []
