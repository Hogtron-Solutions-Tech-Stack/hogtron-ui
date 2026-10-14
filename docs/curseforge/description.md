## HogTron UI

Your whole UI in one matching look: healer frames, unit frames, action bars, HUD, nameplates, a quest tracker and map, a dungeon guide, a meter, chat and a skin for Blizzard's own windows. Twelve small addons share one options window, so you can switch off any module you don't want.

**Beta.** Every module is built and covered by over 900 automated tests. In-game testing is still under way, so please report anything that breaks (see the bottom of this page).

### What's in it

| Addon | What it does |
|---|---|
| **HogHeals** (core) | Profiles, the `/hh` options window, group-size auto-layout, session stats (`/hh session`), performance meter (`/hh perf`) |
| **Frames** | Party and raid frames for healing: hover-and-press binding, dispel highlights for what your class can remove, buff and debuff rows, test mode, setup wizard |
| **Units** | Player, target, target-of-target, pet and focus frames |
| **HUD** | Cast bar, swing timer, mana bar with the five-second rule, experience bar |
| **Bars** | Your own action bars: per-bar layout, always-on grid, hover-and-press key binding |
| **Nameplates** | Flat bars, quest-mob icons, target and aggro highlights, own cast bar |
| **Quests & Map** | Quest tracker with a "go" row (`/hh go`), quest pins, square minimap, addon-button drawer, optional auto accept and turn-in |
| **Atlas** | Dungeon guide: level bands, bosses, dungeon quests, attunements and keys, gear upgrades, "where next" (`/hh next`) |
| **Training** | What your class trainer has for you now and at the next levels, with costs (`/hh train`) |
| **Meter** | Damage and healing meter built on the client's own combat data, where the client provides it |
| **Chat** | Chat windows restyled, short channel names, class-coloured names, URL copy |
| **Skin** | Blizzard's bags, menu bar, tooltips and windows in the same look, plus an info bar (gold, durability, bag space, fps) |

### Getting started

1. Install, then do a **full game restart** the first time (a `/reload` is enough after that).
2. `/hh` opens the options.
3. `/hh unlock` lets you drag things around; click a frame while unlocked for its settings. `/hh lock` when you're done.
4. `/hh test 5` previews the party frames out of a group (also 10 / 20 / 40, `off`).
5. Prefer Blizzard's look? `/hh` > General > Look > **Classic** keeps every feature on Blizzard's fonts, bars and windows.

### Game versions

WoW: Forever, Anniversary and Classic Era. One download covers all three.

### Bugs and ideas

Open an issue on GitHub (link below) with `/hh version`, the output of `/hh errors`, a screenshot, and one line on what you were doing. Even better: `/reload`, then attach `WTF\Account\<your account>\SavedVariables\HogHeals.lua`, which carries the error log and what your client supports.

### Credits

Bundled libraries keep their own licences: Ace3, LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0, LibSharedMedia-3.0, LibDeflate (zlib), LibRangeCheck-3.0 (MIT), LibHealComm-4.0, LibActionButton-1.0 and LibButtonGlow-1.0 (BSD, by nevcairiel). Fonts: Inter, Manrope and Barlow Condensed (SIL Open Font License 1.1). HogTron UI itself is MIT.

---

Source and issues: https://github.com/Hogtron-Solutions-Tech-Stack/hogtron-ui
Made by HogTron Solutions: https://hogtron-solutions.com
