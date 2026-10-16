"""Render HogTron Awards mockups to docs/mockups/awards/*.png.

Same pipeline as dev/render_mockups.py: the addon runs for real in the test harness (lupa + tests/wow_mock.lua).
The stage is not hand-arranged: a Wailing Caverns run is played through the REAL flow - meter rankings, four
groupmates' counters sent through the real HTR_AWD codec, the 3 s window, Metrics.Collect, Resolve.Winners/Stage -
and the picture shows whatever stage the code picked, at the positions UI.Positions() computes for each layout.
Settings pages are walked from the live options table. Icons are the real generated assets.

Not a WoW screenshot: the 3D character models cannot be drawn outside the client, so each player stands as a
class-coloured silhouette labelled with the emote the model plays. Fonts differ in game.

    python dev/render_awards.py
"""
from __future__ import annotations

import base64
import html
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
sys.path.insert(0, str(ROOT / "dev"))
from loader import AddonLoader  # noqa: E402
import render_mockups as rm  # noqa: E402

OUT = ROOT / "docs" / "mockups" / "awards"
ICONS = ROOT / "HogTron_Awards" / "assets" / "awards"
W, H = 1600, 900

CLASS = {"PRIEST": "#ffffff", "WARRIOR": "#c69b6d", "MAGE": "#3fc7eb", "ROGUE": "#fff468", "HUNTER": "#aad372",
         "SHAMAN": "#0070de", "DRUID": "#ff7c0a", "PALADIN": "#f48cba", "WARLOCK": "#8788ee"}
GROUP = [("Hognificent", "PRIEST"), ("Zugzug", "WARRIOR"), ("Brianna", "MAGE"), ("Anthony", "ROGUE"), ("Scoop", "HUNTER")]

SCENARIO = r'''
MockSetSecrets(true)
Enum = Enum or {}
Enum.DamageMeterType = { DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4, Interrupts = 5, Dispels = 6,
  DamageTaken = 7, AvoidableDamageTaken = 8, Deaths = 9, EnemyDamageTaken = 10 }
Enum.DamageMeterSessionType = { Overall = 0, Current = 1, Expired = 2 }
local modeName, segName = {}, {}
for k, v in pairs(Enum.DamageMeterType) do modeName[v] = k end
for k, v in pairs(Enum.DamageMeterSessionType) do segName[v] = k end
HH_meter = {
  ["DamageDone:Overall"] = { "Brianna", "Anthony", "Scoop", "Zugzug", "Hognificent" },
  ["Dps:Overall"] = { "Anthony", "Brianna", "Scoop", "Zugzug", "Hognificent" },
  ["HealingDone:Overall"] = { "Hognificent", "Zugzug" },
  ["Hps:Overall"] = { "Hognificent", "Zugzug" },
  ["Absorbs:Overall"] = { "Hognificent" },
  ["Interrupts:Overall"] = { "Anthony", "Zugzug" },
  ["Dispels:Overall"] = { "Hognificent" },
  ["DamageTaken:Overall"] = { "Zugzug", "Scoop", "Anthony", "Brianna", "Hognificent" },
  ["AvoidableDamageTaken:Overall"] = { "Scoop", "Brianna" },
  ["Deaths:Overall"] = { "Scoop", "Brianna" },
  ["DamageDone:Current"] = { "Anthony", "Brianna", "Scoop", "Zugzug", "Hognificent" },
  ["HealingDone:Current"] = { "Hognificent" },
}
C_DamageMeter = { GetCombatSessionFromType = function(st, mt)
  local names = HH_meter[modeName[mt] .. ":" .. segName[st]] or {}
  local src = {}
  for i, n in ipairs(names) do src[i] = { name = n, totalAmount = MockSecret(1000 - i) } end
  return { combatSources = src }
end }
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end, SendAddonMessage = function() return 0 end }
GetServerTime = function() return 1760000000 end
function DoEmote() end; function JumpOrAscendStart() end; function RollOnLoot() end; function SetRaidTarget() end
'''


def icon(award_id: str, size: int) -> str:
    p = ICONS / f"{award_id}.png"
    if not p.exists():
        return f'<div class="noicon" style="width:{size}px;height:{size}px"></div>'
    data = base64.b64encode(p.read_bytes()).decode()
    return f'<img src="data:image/png;base64,{data}" width="{size}" height="{size}">'


def boot():
    l = AddonLoader().bootstrap()
    l.execute(SCENARIO)
    l.load_addon("HogHeals")
    l.load_addon("HogTron_Awards")
    l.player_login()
    names = ", ".join(f'{{ name = "{n}", class = "{c}" }}' for n, c in GROUP[1:])
    l.execute(f'''
      MockState.playerClass = "PRIEST"; MockUnits.player.name = "Hognificent"; MockUnits.player.class = "PRIEST"
      MockSetGroup(5, false)
      for i, u in ipairs({{ {names} }}) do MockUnits["party" .. i].name = u.name; MockUnits["party" .. i].class = u.class end
      GetInstanceInfo = function() return "Wailing Caverns", "party", 1, "", 5, 0, false, 43, 5 end
      MockFire("PLAYER_ENTERING_WORLD", false, false)
    ''')
    return l


def play_run(l):
    """The real end-of-run flow with four groupmates' counters coming in over HTR_AWD."""
    l.execute('for i = 1, 3 do DoEmote("THANK") end; MockFire("READY_CHECK"); MockAdvance(1); MockFire("READY_CHECK_CONFIRM", "player", true)')
    l.execute('HogTronAwards.EndRun("manual")')
    mates = {
        "Zugzug": "{ taunts = 14, foodDrink = 3, jumps = 12, readyTime = 2 }",
        "Brianna": "{ ccCast = 9, drinks = 4, foodDrink = 6, lootItems = 11, selfDeaths = 1, firstDeath = 212, timeDead = 75, readyTime = 9 }",
        "Anthony": "{ lootItems = 23, lootJunk = 9, needRolls = 4, jumps = 61, castsTotal = 310, readyTime = 1.5 }",
        "Scoop": "{ selfDeaths = 2, firstDeath = 95, timeDead = 240, ghostRuns = 1, afkTime = 180, jumps = 40, lootGold = 48210, readyTime = 14 }",
    }
    for name, counts in mates.items():
        for m in l.eval(f'HogTronAwards.Sync.EncodeNominations("{name}-1760000003", {counts})').values():
            l.execute(f'MockFire("CHAT_MSG_ADDON", "HTR_AWD", [[{m}]], "PARTY", "{name}-Nightslayer")')
    l.execute('MockAdvance(3)')
    return l.eval('HogTronAwards.last')


def winner_dict(w):
    a = w["award"]
    return {"id": a["id"], "name": a["name"], "kind": a["kind"], "flavor": a["flavor"], "emote": a["emote"],
            "player": w["name"], "detail": w["detail"], "note": a["note"]}


CSS = """
*{box-sizing:border-box}body{margin:0;background:#0b0b0e;font-family:'Segoe UI',Arial,sans-serif;color:#F5EBDC}
.scene{position:relative;width:1600px;height:900px;overflow:hidden;
  background:radial-gradient(ellipse at 50% 35%,#2a3a46 0%,#141b22 55%,#07090c 100%)}
.world{position:absolute;inset:0;background:repeating-linear-gradient(115deg,#1d2a1f 0 40px,#18241a 40px 80px);opacity:.55}
.shade{position:absolute;inset:0;background:rgba(18,18,23,.78)}
.title{position:absolute;top:44px;width:100%;text-align:center;font-size:34px;font-weight:700;letter-spacing:6px;color:#ffdb6b;
  text-shadow:0 0 18px #d9a32e88,0 2px 0 #5a3a12}
.where{position:absolute;top:92px;width:100%;text-align:center;font-size:17px;color:#F5EBDC;opacity:.85}
.slot{position:absolute;width:240px;transform-origin:center center}
.model{height:250px;position:relative;display:flex;align-items:flex-end;justify-content:center}
.model svg{filter:drop-shadow(0 0 16px rgba(0,0,0,.6))}
.pedestal{position:absolute;bottom:-6px;left:40px;right:40px;height:16px;border-radius:50%;background:radial-gradient(#d9a32e66,#0000 70%)}
.emote{position:absolute;top:6px;left:0;right:0;text-align:center;font-size:11px;color:#9a9aa8;letter-spacing:1px}
.card{margin-top:6px;background:#121217f2;border:2px solid #8c5e2e;border-radius:6px;padding:10px;min-height:150px;
  box-shadow:0 6px 20px #000a, inset 0 0 0 1px #d9a32e33}
.card.head{border-color:#ffdb6b;box-shadow:0 0 24px #d9a32e66, inset 0 0 0 1px #ffdb6b55}
.row{display:flex;gap:10px}.kind{font-size:11px;font-weight:700;letter-spacing:2px;color:#d9a32e}.kind.roast{color:#f27340}
.aw{font-size:19px;font-weight:700;color:#ffdb6b;line-height:1.15}.pl{font-size:15px;font-weight:600;margin-top:3px}
.fl{font-size:12.5px;line-height:1.35;margin-top:8px;color:#e8dfd2}
.also{position:absolute;bottom:36px;width:100%;text-align:center;color:#9a9aa8;font-size:13px}
.hint{position:absolute;bottom:60px;width:100%;text-align:center;color:#737380;font-size:12px}
.conf{position:absolute;width:6px;height:12px;border-radius:1px;opacity:.9}
.note{position:absolute;left:16px;top:12px;font-size:12px;color:#737380}
.tip{position:absolute;background:#0d0d11f5;border:1px solid #737380;border-radius:4px;padding:8px 10px;width:300px;font-size:12.5px;line-height:1.4;z-index:4}
.tip b{color:#ffdb6b}.tip i{color:#9a9aa8;font-style:normal}
.prompt{position:absolute;left:660px;top:150px;width:280px;height:58px;background:#8c5e2e;border-radius:5px;padding:3px;
  box-shadow:0 0 30px #ffcf4a88}
.prompt div{height:52px;border-radius:3px;background:linear-gradient(#ffe08a 0 38%,#d9a32e 39%,#b07d1c);display:flex;
  flex-direction:column;align-items:center;justify-content:center}
.prompt b{font-size:22px;letter-spacing:3px;color:#121217}.prompt span{font-size:12px;color:#3a2408}
.cards{display:grid;grid-template-columns:repeat(4,1fr);gap:22px;padding:40px;width:1600px}
"""


def silhouette(color: str, big: bool) -> str:
    s = 1.0 if big else 0.9
    return (f'<svg width="{int(150 * s)}" height="{int(230 * s)}" viewBox="0 0 150 230">'
            f'<circle cx="75" cy="38" r="26" fill="{color}" opacity=".9"/>'
            f'<path d="M30 230 L38 110 Q40 74 75 70 Q110 74 112 110 L120 230 Z" fill="{color}" opacity=".85"/>'
            f'<path d="M38 112 L10 168 L24 174 L48 128 Z M112 112 L140 168 L126 174 L102 128 Z" fill="{color}" opacity=".75"/></svg>')


def confetti() -> str:
    cols = ["#d9a32e", "#ffdb6b", "#21D4E0", "#F5EBDC", "#8c5e2e"]
    out = []
    for i in range(70):
        x, y = (i * 137) % 1600, (i * 263) % 860
        out.append(f'<div class="conf" style="left:{x}px;top:{y}px;background:{cols[i % 5]};transform:rotate({(i * 47) % 180}deg)"></div>')
    return "".join(out)


def card(w: dict, head: bool = False) -> str:
    color = dict((n, CLASS[c]) for n, c in GROUP).get(w["player"], "#F5EBDC")
    kind = "ROAST" if w["kind"] == "roast" else "HONOR"
    return (f'<div class="card{" head" if head else ""}"><div class="row">{icon(w["id"], 72)}<div>'
            f'<div class="kind{" roast" if w["kind"] == "roast" else ""}">{kind}</div><div class="aw">{html.escape(w["name"])}</div>'
            f'<div class="pl" style="color:{color}">{html.escape(w["player"])}</div></div></div>'
            f'<div class="fl">{html.escape(w["flavor"])}</div></div>')


def stage_html(l, last, layout: str) -> str:
    stage = last["stage"]
    ws = [winner_dict(stage["headline"])] + [winner_dict(o) for o in stage["others"].values()]
    pos = list(l.eval(f'HogTronAwards.UI.Positions("{layout}", {W}, {H})').values())
    slots = []
    for i, (w, p) in enumerate(zip(ws, pos)):
        color = dict((n, CLASS[c]) for n, c in GROUP).get(w["player"], "#F5EBDC")
        cx, cy = W / 2 + p["x"], H / 2 - p["y"] + 40
        slots.append(f'<div class="slot" style="left:{cx - 120:.0f}px;top:{cy - 210:.0f}px;transform:scale({p["scale"]})">'
                     f'<div class="model"><div class="emote">3D model · /{w["emote"]}</div>{silhouette(color, i == 0)}<div class="pedestal"></div></div>'
                     f'{card(w, i == 0)}</div>')
    hov = ws[1]
    tip = (f'<div class="tip" style="left:{W / 2 + pos[1]["x"] - 150:.0f}px;top:{H / 2 - pos[1]["y"] - 160:.0f}px">'
           f'<b>{html.escape(hov["name"])}</b><br>{html.escape(hov["player"])}: {html.escape(str(hov["detail"]))}'
           + (f'<br><i>{html.escape(hov["note"])}</i>' if hov.get("note") else "") + '</div>')
    also = [f'{o["award"]["name"]}: {o["name"]}' for o in stage["also"].values()][:8]
    label = l.eval(f'HogTronAwards.UI.LAYOUT_LABELS.{layout}')
    return (f'<!doctype html><meta charset="utf-8"><style>{CSS}</style><div class="scene"><div class="world"></div><div class="shade"></div>'
            f'{confetti()}<div class="title">HOGTRON AWARDS</div><div class="where">{html.escape(last["where"])}</div>{"".join(slots)}{tip}'
            f'<div class="hint">Esc or click anywhere to close · closes itself after 45 s · hover a card for the numbers</div>'
            f'<div class="also">Also earned: {html.escape("  -  ".join(also))}</div>'
            f'<div class="note">Layout: {html.escape(label)} · stage picked by Resolve from a simulated Wailing Caverns run · '
            f'silhouettes stand in for the 3D models</div></div>')


def prompt_html() -> str:
    return (f'<!doctype html><meta charset="utf-8"><style>{CSS}</style><div class="scene"><div class="world"></div>'
            f'<div class="prompt"><div><b>VIEW AWARDS</b><span>Wailing Caverns</span></div></div>'
            f'<div class="note">The prompt after a run: top centre, gold, gently pulsing; click = the stage; gone after 60 s if ignored.</div></div>')


def cards_html(l, last) -> str:
    stage = last["stage"]
    ws = [winner_dict(stage["headline"])] + [winner_dict(o) for o in stage["others"].values()] + \
         [winner_dict(o) for o in stage["also"].values()]
    seen, pick = set(), []
    for w in ws:
        if w["id"] not in seen:
            seen.add(w["id"])
            pick.append(w)
    pick = pick[:8]
    return (f'<!doctype html><meta charset="utf-8"><style>{CSS} body{{background:#121217}}</style>'
            f'<div style="padding:24px 40px 0;color:#9a9aa8;font-size:13px">Award cards from the same simulated run (real winners, real icons, '
            f'flavor text from data/awards.lua). In game the card sits under the player\'s 3D model.</div>'
            f'<div class="cards">{"".join(card(w, i == 0) for i, w in enumerate(pick))}</div>')


def icons_html() -> str:
    from math import ceil  # noqa: F401
    l = AddonLoader().bootstrap()
    l.load_addon("HogHeals")
    l.load_addon("HogTron_Awards")
    rows = []
    for a in l.eval("HogTronAwards.LIST").values():
        col = "#f27340" if a["kind"] == "roast" else "#d9a32e"
        rows.append(f'<div style="width:150px;text-align:center;font-size:11.5px">{icon(a["id"], 96)}<div style="color:{col};margin-top:2px">'
                    f'{html.escape(a["name"])}</div></div>')
    return (f'<!doctype html><meta charset="utf-8"><style>{CSS} body{{background:#121217}}</style>'
            f'<div style="padding:20px 30px 0;color:#9a9aa8;font-size:13px">All 75 icons (OpenArt, Nano Banana 2.1, 3x3 sheets, magenta-keyed '
            f'to transparency). Gold = honor, orange = roast.</div>'
            f'<div style="display:flex;flex-wrap:wrap;gap:12px 6px;padding:20px 30px;width:1600px">{"".join(rows)}</div>')


def settings_pages(l):
    root = rm.lua_val(l.eval("HogHeals.OptionsTable()"))
    tab = rm.lua_val(rm.lua_val(root["args"])["Awards"])
    subs = rm.lua_val(tab["args"])
    ctx = l.lua.table()
    out = []
    side = ["General", "Honors", "Roasts"]
    for key, label in (("general", "General"), ("honors", "Honors"), ("roasts", "Roasts")):
        body = "".join(rm.render_args(rm.lua_val(subs[key])["args"], ctx))
        out.append((f"settings-{key}", rm.page(f"Awards › {label}", ["General", "Frames", "Awards"], "Awards", side, label, body,
                                                foot="/hh awards  ·  /htr awards  ·  mockup rendered from the live options table")))
    return out


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    l = boot()
    last = play_run(l)
    pages = [("stage-arc", stage_html(l, last, "arc")), ("stage-corners", stage_html(l, last, "corners")),
             ("prompt", prompt_html()), ("cards", cards_html(l, last)), ("icons-all", icons_html())]
    pages += settings_pages(l)
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width": 1600, "height": 900})
        for name, doc in pages:
            pg.set_content(doc)
            pg.screenshot(path=str(OUT / f"{name}.png"), full_page=True)
            print("rendered", OUT / f"{name}.png")
        b.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
