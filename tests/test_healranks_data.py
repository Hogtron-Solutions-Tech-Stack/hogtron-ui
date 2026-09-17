def test_generated_data_present(hud):
    assert hud.eval('type(HogHealsHUD.HealRanks)') == "table"
    assert hud.eval('type(HogHealsHUD.HealRanks.era)') == "table"
    assert hud.eval('type(HogHealsHUD.HealRanks.tbc)') == "table"


def test_greater_heal_era(hud):
    gh = hud.eval('HogHealsHUD.HealRanks.era["Greater Heal"]')
    assert abs(gh["coeff"] - 3 / 3.5) < 0.01
    ranks = list(gh["ranks"].values())
    assert len(ranks) == 5
    assert ranks[0]["rank"] == 1 and ranks[0]["level"] == 40 and ranks[0]["avg"] > 800
    assert ranks[-1]["avg"] > ranks[0]["avg"]


def test_tbc_has_more_ranks_and_paladin(hud):
    assert hud.eval('#HogHealsHUD.HealRanks.tbc["Greater Heal"].ranks') == 7
    assert hud.eval('HogHealsHUD.HealRanks.tbc["Flash of Light"] ~= nil')
    assert hud.eval('HogHealsHUD.HealRanks.era["Chain Heal"] ~= nil')
    assert hud.eval('HogHealsHUD.HealRanks.era["Healing Touch"] ~= nil')


def test_every_rank_well_formed(hud):
    bad = hud.eval('''(function()
      local bad = 0
      for _, flavor in pairs({"era","tbc"}) do
        for name, s in pairs(HogHealsHUD.HealRanks[flavor]) do
          if type(s.coeff) ~= "number" then bad = bad + 1 end
          for i, r in ipairs(s.ranks) do
            if r.rank ~= i or type(r.level) ~= "number" or type(r.avg) ~= "number" or r.avg <= 0 then bad = bad + 1 end
          end
        end
      end
      return bad
    end)()''')
    assert bad == 0
