import pytest


@pytest.fixture
def ra(hud):
    hud.execute('''
      MockState.playerClass = "PRIEST"; MockUnits.player.class = "PRIEST"
      GetBuildInfo = function() return "1.15.8", "1", "", 11508 end
      HogHealsFrames.Compat.Init()
      MockState.spellbook = {
        { "Greater Heal", "Rank 1" }, { "Greater Heal", "Rank 2" }, { "Greater Heal", "Rank 3" }, { "Greater Heal", "Rank 4" },
        { "Flash Heal", "Rank 1" }, { "Flash Heal", "Rank 4" }, { "Flash Heal", "Rank 7" }, { "Renew", "Rank 10" }, { "Smite", "Rank 8" },
      }
      GetSpellBonusHealing = function() return 500 end
      HogHealsHUD.RankAdvisor.Scan()
    ''')
    return hud


def test_parse_rank(hud):
    assert hud.eval('HogHealsHUD.RankAdvisor.ParseRank("Rank 4")') == 4
    assert hud.eval('HogHealsHUD.RankAdvisor.ParseRank("")') is None
    assert hud.eval('HogHealsHUD.RankAdvisor.ParseRank(nil)') is None


def test_scan_known_ranks(ra):
    known = ra.eval('HogHealsHUD.RankAdvisor.known')
    assert sorted(known["Greater Heal"].values()) == [1, 2, 3, 4]
    assert sorted(known["Flash Heal"].values()) == [1, 4, 7]
    assert "Smite" not in dict(known.items())


def test_pick_lowest_sufficient_rank(ra):
    # Era Greater Heal r1..r4 avgs from generated data, coeff 0.857, bonus 500 -> +428
    r = ra.eval('HogHealsHUD.RankAdvisor.Pick("Greater Heal", 1200, 500, 0.9)')
    assert r is not None
    rank, amount = r["rank"], r["amount"]
    assert amount >= 1200 * 0.9
    lower = ra.eval(f'HogHealsHUD.RankAdvisor.Amount("Greater Heal", {rank} - 1, 500)')
    assert lower is None or lower < 1200 * 0.9


def test_pick_edge_cases(ra):
    assert ra.eval('HogHealsHUD.RankAdvisor.Pick("Greater Heal", 0, 500, 0.9)') is None
    assert ra.eval('HogHealsHUD.RankAdvisor.Pick("Nonexistent", 100, 500, 0.9)') is None
    big = ra.eval('HogHealsHUD.RankAdvisor.Pick("Greater Heal", 99999, 500, 0.9)')
    assert big["rank"] == 4 and big["capped"] is True  # highest known when nothing suffices


def test_hover_writes_info_line(ra):
    ra.execute('''
      MockUnits.party1 = { name = "Zugzug", class = "WARRIOR", health = 2000, maxHealth = 3500, guid = "Player-1" }
      HH_b = HogHealsFrames.UnitButton.Create("HogHealsRABtn", UIParent)
      HH_b.unit = "party1"
      HogHealsFrames.UnitButton.OnEnter(HH_b)
    ''')
    text = ra.eval('HogHealsHUD.HUD.rows.info.right:GetText()')
    assert text.startswith("GH r") and "FH r" in text
    ra.execute('HogHealsFrames.UnitButton.OnLeave(HH_b)')
    assert ra.eval('HogHealsHUD.HUD.rows.info.right:GetText()') == ""


def test_rankmacros_slash_prints(ra):
    ra.execute('MockLog.chat = {}; HogHeals:SlashCommand("rankmacros")')
    chat = list(ra.eval('MockLog.chat').values())
    assert any("/cast Greater Heal(Rank 4)" in line for line in chat)
    assert any("/cast Flash Heal(Rank 7)" in line for line in chat)
