# Vendored libraries (HogHeals_Bars)

Copied 2026-10-02 from Bartender4 4.17.4 on disk (`_anniversary_/Interface/AddOns/Bartender4/libs`). Both are
BSD-licensed (Hendrik "nevcairiel" Leppkes); the licence text is at the top of each file and stays there.
Bartender4 itself is *All rights reserved* and nothing of it is copied.

| Library | Version | Local changes |
|---|---|---|
| LibActionButton-1.0 | minor 145 (toc 0.60) | none |
| LibButtonGlow-1.0 | minor 9 | none |

LibStub and CallbackHandler-1.0 come from `HogHeals/Libs` (the core addon loads first).

Known watch-point on WoW: Forever: LibActionButton's `Midnight` switch keys off build >= 120000; Forever's build
is 70170 while the client hands out secret values. If an action button's count / charge text throws, flip that
switch to `issecretvalue ~= nil` (one line) and record it here.
