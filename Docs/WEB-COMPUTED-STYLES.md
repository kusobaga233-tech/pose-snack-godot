# WEB-COMPUTED-STYLES — the shipped TV-console skin, measured

> **What this is.** Authoritative `getComputedStyle()` + `getBoundingClientRect()`
> numbers for the **web** build of Pose Snake, taken over CDP from headless Chrome
> (`--headless=new`) against the *live* page — not read off a screenshot, not
> copied from `style.css` by eye. Every cell in every table below is a real
> computed value.
>
> **Why it exists.** The curated reference screenshots in the Godot project are
> stale: several of them show the *abandoned* purple/glass layer (14 px glass
> cards, `rgba(160,120,255,…)` borders, `backdrop-filter: blur(14px)`). Two prior
> analyses disagreed about the clock / rank / card sizes because they measured
> different things at different viewports. This document replaces both.

| | |
|---|---|
| Source project | `D:/CODEX-PROJ/yoodou/pose-snake-full-20261112/pose-snake` |
| Server used | `http://127.0.0.1:8793/index.html` — a local static server started for this run; the pre-existing `127.0.0.1:8791` was **not** answering and was left alone |
| Capture tool | `evidence/web-ref/tools/capture-web-ref.mjs` |
| Generated | `2026-11-13T10:22:38.372Z` |
| Raw JSON | `Docs/WEB-COMPUTED-STYLES.json` (same folder) |
| Screenshots | `evidence/web-ref/*.png` |

**Units.** Every number is **CSS px at the stated viewport, 1:1 with the
screenshot** — no ×0.75, no design-canvas scaling. The Godot design canvas is
1920×1080, so the `1920` column maps **1:1** into a Godot `Control` hierarchy.
The `1440×810` pass is a *different* render: the CSS media query
`@media (max-height: 820px)` drops `--ui-scale` to `.74`, so 1440 numbers are
**not** the 1920 numbers scaled by hand — they are `0.74 ×` by construction.

---

## 0. Method

1. Serve the *source* project directory (not a build artefact) on a throwaway
   port and load it with a cache-busting query, in a **fresh Chrome profile**, so
   no stale CSS can survive.
2. Drive states through the page's own public debug surface `window.__poseSnake`
   — the same surface the web project's `tools/*.mjs` already use:

| State | How it was reached |
|---|---|
| `title` | just wait for `#overlay` to be visible |
| `ready` | `setPlayers(1)` → click `#kbBtn` → `setRoundDuration(120)` (resets the world to `state='ready'` with `body.in-round`) |
| `play` | `__poseSnake.start()` → wait `state==='playing'` → sleep 2.4 s so the clock really ticks |
| `pause` | `__poseSnake.setPauseOpen(true)` — identical to pressing **O** (`body.pause-open`) |
| `settle` | shortened the **real** round timer (`game.roundLeft = 2.0`) and let it expire on its own → `finishRound()` → `showResult()`, then clicked the real `#skipStageBtn` |
| `split2p` | fresh load → `setPlayers(2)` on the title screen |
| `split2p-play` | …then `#kbBtn`; 2 humans + 6 AI = 8 snakes |

3. For each state: one `Runtime.evaluate` that walks a fixed selector list and
   records `getBoundingClientRect()` + ~50 computed properties, **plus** the
   same for `::before` / `::after` pseudo-elements (that is where the OSD
   brackets and scanlines live), plus `getComputedStyle(root)` custom properties,
   plus a `querySelectorAll` existence probe for 44 suspect class names.
4. Screenshot in the same breath (`Page.captureScreenshot`), so the numbers and
   the pixels are the same frame.

Nothing in the web project was modified. No Godot, no adb, no camera.

---

## 1. Design tokens (custom properties, as computed)

From `getComputedStyle(document.documentElement)` on the live page.

| token | value at 1920×1080 | value at 1440×810 |
|---|---|---|
| `--tv-cyan` | `#56e8ff` | `#56e8ff` |
| `--tv-lime` | `#b6ff57` | `#b6ff57` |
| `--tv-gold` | `#ffd54a` | `#ffd54a` |
| `--tv-text` | `#eaf6ff` | `#eaf6ff` |
| `--tv-dim` | `rgba(190, 214, 238, 0.62)` | `rgba(190, 214, 238, 0.62)` |
| `--tv-line` | `rgba(86, 232, 255, 0.34)` | `rgba(86, 232, 255, 0.34)` |
| `--tv-line-soft` | `rgba(86, 232, 255, 0.15)` | `rgba(86, 232, 255, 0.15)` |
| `--tv-panel` | `rgba(7, 15, 28, 0.94)` | `rgba(7, 15, 28, 0.94)` |
| `--tv-deep` | `#060c18` | `#060c18` |
| `--safe` | `clamp(18px, 2.4vw, 44px)` | `clamp(18px, 2.4vw, 44px)` |
| `--ui-scale` | `1` | `.74` |
| `--ui-h` | `calc(200px * 1)` | `calc(200px * .74)` |
| `--ui-cam-w` | `calc(320px * 1)` | `calc(320px * .74)` |
| `--ui-side` | `calc(340px * 1)` | `calc(340px * .74)` |
| `--ui-rank-w` | `calc(300px * 1)` | `calc(300px * .74)` |
| `--arena-safe-x` | `calc(90px * 1)` | `calc(90px * .74)` |

`--result-rows-w` / `--result-lane` are empty at rest — they are written on
`#resultRows` by JS at settlement time (68.57% of the viewport width for 8 lanes).

**The single most important token is `--ui-scale`.** It is `1` at 1920×1080 and
`.74` at 1440×810 because of `@media (max-height: 820px)`. Every large size in the
shipped skin is `calc(<base>px * var(--ui-scale))`, so *every* number in this
document is `base × --ui-scale`. For the Godot port at a 1920×1080 design canvas
the base values are the ones to take.

---

## 2. Skin check — is this really the TV-console layer?

Recorded on every state; identical everywhere unless noted.

| check | value | verdict |
|---|---|---|
| `body` background | `rgb(5, 9, 18)` | TV-skin deep navy (purple layer was `#07030e`) |
| `body` colour | `rgb(234, 246, 255)` | `--tv-text` |
| `--tv-cyan` | `#56e8ff` | electric cyan, the system colour |
| `#uiBar` present | `yes` | the merged console scoreboard band |
| `#uiBar` border-radius | **`0px`** | **full-bleed band: radius 0**, not a rounded card |
| `#uiBar` height | **`200 px`** @1920 / **148 px** @1440 | `--ui-h` |
| title slab radius | **`4px`** | radius 4 — the TV skin, not the 14 px glass card |
| title slab `backdrop-filter` | `none` | **no glass** (purple layer had `blur(14px)`) |
| `body::after` OSD brackets | 8 × `linear-gradient(cyan…)`, opacity **`0.55`** | present |
| `body::before` scanlines | `repeating-lg(0deg, rgba(160, 220, 255, 0.024) 0px, rgba(160, 220, 255…` | 1 px line every 4 px |

**Purple-layer test:** zero elements in any state report a `backdrop-filter`
other than `none`, and **no element computes a `border-radius` above 4 px** —
the only larger values anywhere are `50%` circular dots. §5.3 lists every radius
above 3 px; there are five, all of them 4 px. If a capture ever shows 14 px
glass cards, the page is serving a stale or cached stylesheet — the shipped
skin has none.

---

## 3. Numbers that matter

**CSS px at 1920×1080. These are the values to convert 1:1 into the Godot
design canvas.** (Godot `Control` at 1920×1080 → use the number as-is.)

| what | computed value (CSS px) | selector | notes |
|---|---|---|---|
| HUD bar height | **200** | `#uiBar` | whole top band; radius 0 |
| HUD bar left edge / padding | **90** | `#uiBar` | arena safe-area inset |
| HUD bar background | `lg(0deg, rgba(cyan, 0.043) 1px, rgba(0, 0, 0, 0) 1px), lg(90deg, rgba…` | `#uiBar` | 3 layers: 1 px cyan grid (V+H) + vertical rgb(12,29,48) → rgb(9,21,36) 58% → rgb(5,12,22); **no lime left edge** — see §6 |
| Clock digits | **120** | `#timeLeft` | = 120 × --ui-scale |
| Clock digits weight | `900` | `#timeLeft` |  |
| Clock digits line-height | **117.6** | `#timeLeft` |  |
| Clock digits colour | `rgb(215, 247, 255)` | `#timeLeft` |  |
| Clock glow (text-shadow) | **rgba(86, 232, 255, 0.62) 0px 0px 38px, rgba(86, 232, 255, 0.85) 0px 0px 10** | `#timeLeft` | the halo ART-DIFF wants |
| Clock letter-spacing | **0.32** | `#timeLeft` |  |
| Clock cell (`#hud .stat`) | **305.578** | `#hud .stat` | cell width |
| Clock cell height | **164.594** | `#hud .stat` |  |
| Clock cell padding | **24** | `#hud .stat` |  |
| `剩余` label size | **36** | `#hud .stat .k` |  |
| `剩余` label weight | `700` | `#hud .stat .k` |  |
| `剩余` label letter-spacing | **10.08** | `#hud .stat .k` | = .28em |
| Rank numeral (`n / 8`) | **96** | `#rank` | = 96 × --ui-scale |
| Rank numeral weight | `900` | `#rank` |  |
| Rank numeral letter-spacing | **0.32** | `#rank` |  |
| Rank numeral colour | `rgb(255, 154, 114)` | `#rank` | state-driven: lime `rgb(182,255,87)` while rising, salmon `rgb(255,154,114)` while falling — **this frame was falling** |
| `我的名次` label | **36** | `#rankBlock .rank-k` |  |
| `共 8 位玩家` | **24** | `#rankBlock .rank-total` |  |
| Rank block width | **300** | `#rankBlock` |  |
| Rank block height | **150** | `#rankBlock` |  |
| Panel radius (title slab) | **4** | `#overlay .panel.title-screen` | radius 2–4 family |
| Title slab border-top | **4** | `#overlay .panel.title-screen` | lime accent edge |
| Title slab border-top colour | `rgb(182, 255, 87)` | `#overlay .panel.title-screen` |  |
| Title slab width | **780** | `#overlay .panel.title-screen` |  |
| Title slab height | **582.719** | `#overlay .panel.title-screen` |  |
| Title slab background | `lg(155deg, rgba(9, 20, 36, 0.98), rgba(5, 10, 20, 0.99))` | `#overlay .panel.title-screen` |  |
| Title slab shadow | **rgba(0, 0, 0, 0.8) 0px 40px 100px 0px, rgba(86, 232, 255, 0.12) 0px 0px 60px 0** | `#overlay .panel.title-screen` |  |
| Game title `h1` | **58** | `#panelTitle` |  |
| Game title weight | `900` | `#panelTitle` |  |
| Game title letter-spacing | **2.32** | `#panelTitle` |  |
| Game title glow | `none` | `#panelTitle` |  |
| Title sub-line | **13** | `#overlay .title-sub` |  |
| Meta badge chip | **11** | `#overlay .mode-badges span` |  |
| Meta badge padding | **12** | `#overlay .mode-badges span` |  |
| Meta badge left edge | **3** | `#overlay .mode-badges span` |  |
| Meta badge radius | **2** | `#overlay .mode-badges span` |  |
| Mode card (`.ps-btn`) width | **351** | `#overlay .ps-btn` |  |
| Mode card height | **79** | `#overlay .ps-btn` |  |
| Mode card radius | **3** | `#overlay .ps-btn` |  |
| Mode card selected border | `rgba(182, 255, 87, 0.68)` | `#overlay .ps-btn.active` |  |
| Mode card label `1 人` | **19** | `#overlay .ps-btn b` |  |
| Mode card sub-label | **11.5** | `#overlay .ps-btn span` |  |
| Primary button `#startBtn` | **14** | `#startBtn` |  |
| Primary button height | **54** | `#startBtn` |  |
| Primary button radius | **3** | `#startBtn` |  |
| Ghost button `#kbBtn` | **14** | `#kbBtn` |  |
| Keycap (`A` / `O`) | **10** | `#padBar .keycap` | in the key strip |
| Keycap height | **20** | `#padBar .keycap` |  |
| Keycap radius | **4** | `#padBar .keycap` |  |
| Stat value (pause row) | **48** | `#pauseStats .stat .v` |  |
| Stat label (pause row) | **28** | `#pauseStats .stat .k` |  |
| Pause kicker | **24** | `#pauseScrim .pause-kicker` | OPTIONS / 局内信息 |
| Pause kicker letter-spacing | **6.72** | `#pauseScrim .pause-kicker` |  |
| Pause headline | **44** | `#pauseScrim .pause-scrim-inner strong` |  |
| Pause scrim | `rgba(0, 0, 0, 0)` | `#pauseScrim` |  |
| Leaderboard width | **340** | `#leaderboard` |  |
| Leaderboard radius | **3** | `#leaderboard` |  |
| Leaderboard top edge | **3** | `#leaderboard` |  |
| Leaderboard top colour | `cyan` | `#leaderboard` |  |
| Leaderboard row | **24** | `#lbRows .lb-row` |  |
| Leaderboard head | **10** | `#leaderboard .lb-head` |  |
| Leaderboard head letter-spacing | **1.8** | `#leaderboard .lb-head` |  |
| Buff chip radius | **3** | `#buffBoost` |  |
| Buff chip right edge | **3** | `#buffBoost` |  |
| Buff bar height | **4** | `#buffBoost .buff-bar` |  |
| Buff bar radius | **0** | `#buffBoost .buff-bar` |  |
| Settlement headline | **36** | `#resultTitle` |  |
| Settlement stat line | **15** | `#resultStats` |  |
| Settlement rank numeral | **19** | `#resultRows .result-row .r-rank` |  |
| Settlement name | **15** | `#resultRows .result-row .r-name` |  |
| Settlement length | **23** | `#resultRows .result-row .r-len` |  |
| Settlement row width | **164.562** | `#resultRows .result-row` |  |
| Settlement row height | **92** | `#resultRows .result-row` |  |
| Settlement row radius | **0** | `#resultRows .result-row` |  |
| Settlement rows band width | **1316.53** | `#resultRows` |  |
| Result bottom band | **176** | `#resultOverlay .result-bottom` |  |
| Again button | **22** | `#againBtn` |  |
| Again button radius | **3** | `#againBtn` |  |
| 2P clock digits | **96** | `#timeLeft` |  |
| 2P rank numeral | **66** | `#rank` |  |
| 2P rank label | **24** | `#rankBlock .rank-k` |  |
| 2P mirror box width | **268** | `#cam` |  |
| 1P mirror box width | **320** | `#cam` |  |

### 3.1 Geometry cross-check (the three sizes that were disputed)

| element | 1920×1080 | 1440×810 | ratio | verdict |
|---|---|---|---|---|
| clock digits | **120px** | 88.8px | 0.740 | scales with `--ui-scale` |
| rank numeral | **96px** | 71.04px | 0.740 | scales with `--ui-scale` |
| 剩余 label | **36px** | 26.64px | 0.740 | scales with `--ui-scale` |
| `我的名次` label | **36px** | 26.64px | 0.740 | scales with `--ui-scale` |
| key strip | **11px** | 11px | 1.000 | **fixed px — does not scale** |
| `#uiBar` height | **200 px** | 148 px | 0.740 | band scales with `--ui-h` |

### 3.2 OSD overlay, verbatim

The OSD is **not** a DOM element — it is `body::before` + `body::after`. These
are the resolved values Chrome actually paints (verified pixel-for-pixel: at
1920 the top-left bracket occupies x=44..73, y=44..45 and samples as
`rgb(50,134,153)`, which is exactly `#56e8ff` × `.55` composited over
`rgb(5,9,18)`).

**`body::before (scanlines + vignette)`** — inset `0px`, opacity `1`

```css
background-image:    repeating-linear-gradient(0deg, rgba(160, 220, 255, 0.024) 0px, rgba(160, 220, 255, 0.024) 1px, rgba(0, 0, 0, 0) 1px, rgba(0, 0, 0, 0) 4px), radial-gradient(at 50% 48%, rgba(0, 0, 0, 0) 46%, rgba(1, 3, 9, 0.62) 100%);
background-size:     auto, auto;
background-position: 0% 0%, 0% 0%;
background-repeat:   repeat, repeat;
```

**`body::after (OSD 4-corner brackets)`** — inset `44px`, opacity `0.55`

```css
background-image:    linear-gradient(rgb(86, 232, 255), rgb(86, 232, 255)), linear-gradient(rgb(86, 232, 255), rgb(86, 232, 255)), linear-gradient(rgb(86, 232, 255), rgb(86, 232, 255)), linear-gradient(rgb(86, 232, 255), rgb(86, 232, 255)), linear-gradient(rgb(86, 232, 255), rgb(86, 232, 255)), linear-gradient(rgb(86, 232, 255), rgb(86, 232, 255)), linear-gradient(rgb(86, 232, 255), rgb(86, 232, 255)), linear-gradient(rgb(86, 232, 255), rgb(86, 232, 255));
background-size:     30px 2px, 2px 30px, 30px 2px, 2px 30px, 30px 2px, 2px 30px, 30px 2px, 2px 30px;
background-position: 0% 0%, 0% 0%, 100% 0%, 100% 0%, 0% 100%, 0% 100%, 100% 100%, 100% 100%;
background-repeat:   no-repeat, no-repeat, no-repeat, no-repeat, no-repeat, no-repeat, no-repeat, no-repeat;
```

The brackets sit on `inset: var(--safe)` = `clamp(18px, 2.4vw, 44px)`, so they
are **44 px** from each edge at 1920×1080 (`%s` at 1440×810). Bracket geometry
is 8 hard-stop gradients — a `30px 2px` arm plus a `2px 30px` arm at each of the
four corners — i.e. **30 × 2 px arms in `#56e8ff` at opacity .55**.

---

## 4. Per-state computed styles

One table per section per state. Columns: position/size are
`x, y` and `w × h` from `getBoundingClientRect()`; `fs/fw` is
`font-size / font-weight`; `ls` is `letter-spacing`; `bg` is the first
background layer only; long gradients are elided with `…`. `—` means the
element is **not in the DOM in that state**, and **hidden** means it is in the
DOM but computes to a 0×0 box (`display:none`, or a zero-size child); see §5.1
for whether a name is dead or merely conditional.

### 4.1 `title` @ 1920×1080

Title / start screen (「先用方向键玩」 is the keyboard path)

`body.class = ""` · `data-split = 1` · `game.state = ready` · `--ui-scale = 1`

**A. Panel chrome / OSD / merged HUD bar**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #uiBar (merged HUD bar) | `#uiBar` | 0, 0 | 1920 × 200 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(cyan, 0.043) 1px, rgba(0, 0, 0,… | B 3px cyan | 0px | rgba(0, 0, 0, 0.78) 0px 20px 52px 0px, … | 0 90 0 90 |
| #uiBar .ui-deco | `#uiBar .ui-deco` | 0, 0 | 1920 × 197 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-energy | `#uiBar .ui-energy` | 0, 0 | 1920 × 6 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(cyan, 0.16) |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-energy i | `#uiBar .ui-energy i` | -130.67, 0 | 729.59 × 6 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(0, 0, 0, 0), rgb(184, 247, 255… |  | 0px | rgba(cyan, 0.95) 0px 0px 26px 0px | 0 0 0 0 |
| #uiBar .ui-scan | `#uiBar .ui-scan` | 0, 0 | 1920 × 197 | 16/400 | 0.32px | rgb(234, 246, 255) | repeating-lg(0deg, rgba(190, 235, 255, 0.024)… |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-ruler | `#uiBar .ui-ruler` | 90, 185 | 1740 × 5 | 16/400 | 0.32px | rgb(234, 246, 255) | repeating-lg(90deg, rgba(cyan, 0.4) 0px, rgba… |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-seam | `#uiBar .ui-seam` | 0, 197 | 1920 × 3 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(0, 0, 0, 0), cyan 10%, rgb(230… |  | 0px | rgba(cyan, 0.75) 0px 0px 22px 0px | 0 0 0 0 |
| #uiBar .ui-diamond | `#uiBar .ui-diamond` | 950.81, 178.31 | 18.38 × 18.38 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(230, 251, 255) |  | 0px | cyan 0px 0px 18px 0px | 0 0 0 0 |
| #uiBar .ui-notch.left | `#uiBar .ui-notch.left` | 0, 183 | 30 × 14 | 16/400 | 0.32px | rgb(234, 246, 255) | cyan |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-notch.right | `#uiBar .ui-notch.right` | 1890, 183 | 30 × 14 | 16/400 | 0.32px | rgb(234, 246, 255) | cyan |  | 0px | none | 0 0 0 0 |

**B. Clock, stat cells, rank block**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #hud | `#hud` | 448, 23.5 | 1064 × 150 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(cyan, 0.1), rgba(cyan, 0.01) 6… | L 4px rgb(182, 255, 87) | 0px | none | 0 0 0 0 |
| #hud .stat | `#hud .stat` | 829.2, 16.2 | 305.58 × 164.59 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 24 0 24 |
| #hud .stat .k (剩余 label) | `#hud .stat .k` | 935.91, 16.2 | 92.17 × 47 | 36/700 | 10.08px | rgba(198, 232, 248, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #timeLeft (clock digits) | `#timeLeft` | 853.2, 63.2 | 257.58 × 117.59 | 120/900 | 0.32px | rgb(215, 247, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock | `#rankBlock` | 1530, 23.5 | 300 × 150 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(270deg, rgba(182, 255, 87, 0.09), rgba(0, … | R 4px rgb(182, 255, 87) | 0px | none | 0 8 0 38 |
| #rankBlock .rank-k | `#rankBlock .rank-k` | 1639.44, 11.5 | 178.56 × 47 | 36/700 | 8.64px | rgba(198, 232, 248, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rank (rank numeral) | `#rank` | 1595.42, 58.5 | 222.58 × 96 | 96/900 | 0.32px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock .rank-arrow | `#rankBlock .rank-arrow` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock .rank-total | `#rankBlock .rank-total` | 1676.92, 154.5 | 141.08 × 31 | 24/400 | 2.4px | rgba(190, 225, 240, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**C. Mirror box (the camera pane inside the HUD band)**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #cam (mirror box) | `#cam` | 90, 8.5 | 320 × 180 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(4, 11, 20) | T 2px rgba(cyan, 0.55)<br>R 2px rgba(cyan, 0.55)<br>B 2px rgba(cyan, 0.55)<br>L 2px rgba(cyan, 0.55) | 2px | rgba(cyan, 0.06) 0px 0px 0px 6px, rgba(… | 0 0 0 0 |
| #cam .cam-frame | `#cam .cam-frame` | 92, 10.5 | 316 × 176 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #cam .cam-frame i | `#cam .cam-frame i` | 97, 15.5 | 22 × 22 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | T 3px cyan<br>L 3px cyan | 0px | none | 0 0 0 0 |
| #cam .cam-rec | `#cam .cam-rec` | 385, 19.5 | 14 × 14 | 9/900 | 1.44px | rgb(255, 156, 174) | rgba(0, 0, 0, 0) |  | 50% | none | 0 0 0 0 |
| #cam .cam-tag | `#cam .cam-tag` | — | **hidden** | · | · | rgb(182, 255, 87) | rgba(4, 10, 20, 0.82) | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 1px rgba(182, 255, 87, 0.…<br>L 1px rgba(182, 255, 87, 0.… | 3px | none | 4 8 4 8 |
| #cam .cam-speed | `#cam .cam-speed` | 92, 144.5 | 316 × 42 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(2, 10, 20, 0.95), rgba(2, 10, 2… |  | 0px | none | 0 12 0 12 |
| #cam .cam-speed-val | `#cam .cam-speed-val` | 104, 148 | 92 × 35 | 26/800 | 0.52px | rgb(220, 248, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #cam .cam-speed-track | `#cam .cam-speed-track` | 206, 160.5 | 190 × 10 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 22, 36, 0.86) | T 1px rgba(cyan, 0.4)<br>R 1px rgba(cyan, 0.4)<br>B 1px rgba(cyan, 0.4)<br>L 1px rgba(cyan, 0.4) | 0px | none | 0 0 0 0 |
| #cam .cam-speed-track i | `#cam .cam-speed-track i` | 207, 161.5 | 56.39 × 8 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgb(47, 159, 214), cyan 55%, rgb(18… |  | 0px | rgba(cyan, 0.9) 0px 0px 14px 0px | 0 0 0 0 |
| #cam .cam-label | `#cam .cam-label` | 92, 151.5 | 316 × 35 | 10.5/700 | 1.05px | rgb(205, 238, 255) | lg(to top, rgba(8, 3, 16, 0.92), rgba(8, 3, 1… |  | 0px | none | 14 10 7 10 |
| #cam .cam-ready | `#cam .cam-ready` | — | **hidden** | · | · | rgb(234, 246, 255) | lg(rgba(4, 10, 20, 0), rgba(4, 10, 20, 0.88)) |  | 0px | none | 12 0 13 0 |

**D. Status, buttons, key strip, buffs, leaderboard**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #statusbar | `#statusbar` | 1784.39, 44 | 91.61 × 36 | 12/800 | 1.2px | rgb(217, 238, 251) | rgba(6, 14, 26, 0.94) | T 1px rgba(cyan, 0.34)<br>R 3px cyan<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.55) 0px 10px 26px 0px | 9 16 9 16 |
| #statusbar .dot | `#statusbar .dot` | 1801.39, 58 | 8 × 8 | 12/800 | 1.2px | rgb(217, 238, 251) | rgb(107, 95, 133) |  | 50% | rgba(0, 0, 0, 0) 0px 0px 0px 0px | 0 0 0 0 |
| #status (status text) | `#status` | 1817.39, 54 | 39.61 × 16 | 12/800 | 1.2px | rgb(217, 238, 251) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #quickPlayBtn | `#quickPlayBtn` | 1743, 94 | 133 × 42 | 12.5/800 | 1px | rgb(233, 255, 208) | lg(100deg, rgba(9, 26, 32, 0.97), rgba(14, 38… | T 1px rgba(182, 255, 87, 0.…<br>R 3px rgb(182, 255, 87)<br>B 1px rgba(182, 255, 87, 0.…<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(0, 0, 0, 0.55) 0px 8px 24px 0px, r… | 8 15 8 15 |
| #muteBtn | `#muteBtn` | 1630, 94 | 36 × 36 | 13.3333/400 | normal | cyan | rgba(6, 14, 26, 0.9) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | none | 0 0 0 0 |
| #padBar | `#padBar` | 274, 998 | 451.17 × 38 | 11/700 | 0.44px | rgba(214, 236, 250, 0.8) | rgba(6, 14, 26, 0.86) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px cyan | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 8 14 8 14 |
| #padBar .keycap | `#padBar .keycap` | 291, 1007 | 57.14 × 20 | 10/900 | 0.6px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) | T 1px rgba(255, 255, 255, 0…<br>R 1px rgba(255, 255, 255, 0…<br>B 1px rgba(255, 255, 255, 0…<br>L 1px rgba(255, 255, 255, 0… | 4px | rgba(0, 0, 0, 0.6) 0px 2px 0px 0px, rgb… | 0 6 0 6 |
| .keycap (generic keycap) | `.keycap` | — | **hidden** | · | · | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) | T 1px rgba(255, 255, 255, 0…<br>R 1px rgba(255, 255, 255, 0…<br>B 1px rgba(255, 255, 255, 0…<br>L 1px rgba(255, 255, 255, 0… | 4px | rgba(0, 0, 0, 0.6) 0px 2px 0px 0px, rgb… | 0 6 0 6 |
| #hint | `#hint` | 936, 1006 | 48 × 22 | 13/800 | 0.78px | rgb(220, 255, 224) | rgba(6, 14, 26, 0.93) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px rgb(182, 255, 87) | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 10 22 10 22 |
| #buffs | `#buffs` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost (buff chip) | `#buffBoost` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(6, 14, 26, 0.95) | T 1px rgba(255, 213, 74, 0.…<br>R 3px rgba(255, 213, 74, 0.…<br>B 1px rgba(255, 213, 74, 0.…<br>L 1px rgba(255, 213, 74, 0.… | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 7 11 11 11 |
| #buffBoost .buff-name | `#buffBoost .buff-name` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-time | `#buffBoost .buff-time` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-bar | `#buffBoost .buff-bar` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(255, 255, 255, 0.12) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-bar i | `#buffBoost .buff-bar i` | — | **hidden** | · | · | rgb(255, 213, 74) | rgb(255, 213, 74) |  | 2px | none | 0 0 0 0 |
| #leaderboard | `#leaderboard` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(6, 14, 26, 0.95) | T 3px cyan<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.6) 0px 16px 40px 0px | 11 12 10 12 |
| #leaderboard .lb-head | `#leaderboard .lb-head` | — | **hidden** | · | · | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #leaderboard .lb-head span | `#leaderboard .lb-head span` | — | **hidden** | · | · | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbTime | `#lbTime` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows | `#lbRows` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-row | `#lbRows .lb-row` | — | — | — | — | — | — | — | — | — | — |
| #lbRows .lb-row.me | `#lbRows .lb-row.me` | — | — | — | — | — | — | — | — | — | — |
| #lbRows .lb-rank | `#lbRows .lb-row .lb-rank` | — | — | — | — | — | — | — | — | — | — |
| #lbRows .lb-name | `#lbRows .lb-row .lb-name` | — | — | — | — | — | — | — | — | — | — |
| #lbRows .lb-len | `#lbRows .lb-row .lb-len` | — | — | — | — | — | — | — | — | — | — |

**E. Pause / OPTIONS layer**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #pauseScrim | `#pauseScrim` | 0, 200 | 1920 × 880 | 16/400 | 0.32px | rgb(234, 246, 255) | radial-gradient(at 50% 0%, rgba(6, 16, 30, 0.… |  | 0px | none | 22 0 0 0 |
| #pauseScrim .pause-scrim-inner | `#pauseScrim .pause-scrim-inner` | 793.67, 222 | 332.64 × 137 | 16/400 | 0.32px | rgb(223, 244, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim .pause-kicker | `#pauseScrim .pause-kicker` | 795.67, 222 | 328.64 × 31 | 24/800 | 6.72px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim strong | `#pauseScrim .pause-scrim-inner strong` | 793.67, 259 | 332.64 × 59 | 44/900 | 3.52px | rgb(223, 244, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim .pause-tip | `#pauseScrim .pause-tip` | 837.8, 324 | 244.39 × 35 | 26/400 | 0.32px | rgba(200, 230, 245, 0.7… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats | `#pauseStats` | 679.36, 318 | 561.28 × 193.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 16, 29, 0.97) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 4px cyan | 4px | rgba(0, 0, 0, 0.7) 0px 18px 48px 0px | 16 20 16 20 |
| #pauseStats .stat | `#pauseStats .stat` | 767.5, 335 | 120 × 110.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(12, 28, 46, 0.7) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.35) 0px 8px 28px 0px, r… | 10 14 10 14 |
| #pauseStats .stat .k | `#pauseStats .stat .k` | 782.5, 346 | 90 × 37 | 28/600 | 3.92px | rgba(190, 214, 238, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats .stat .v | `#pauseStats .stat .v` | 782.5, 384 | 90 × 50.39 | 48/900 | 0.32px | rgb(242, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats .legacy-stat (dead weight) | `#pauseStats .legacy-stat` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(12, 28, 46, 0.7) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.35) 0px 8px 28px 0px, r… | 10 14 10 14 |
| #pauseBuff | `#pauseBuff` | 703.36, 459.39 | 516.28 × 35 | 26/700 | 1.56px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning (settings drawer) | `#tuning` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(6, 14, 26, 0.95) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 3px rgb(182, 255, 87) | 4px | rgba(0, 0, 0, 0.55) 0px 10px 26px 0px | 0 0 0 0 |
| #tuning .tuning-head | `#tuning .tuning-head` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 11 13 11 13 |
| #tuning .tuning-title | `#tuning .tuning-title` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning .tuning-mark | `#tuning .tuning-mark` | — | **hidden** | · | · | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuningToggle | `#tuningToggle` | — | **hidden** | · | · | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) |  | 3px | none | 4 10 4 10 |
| #tuning .tuning-body | `#tuning .tuning-body` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 14 14 16 14 |
| #tuning .tuning-body .row | `#tuning .tuning-body .row` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning .ai-sep | `#tuning .ai-sep` | — | **hidden** | · | · | cyan | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.34)<br>L 3px rgb(182, 255, 87) | 0px | none | 9 0 0 10 |

**F. Start / title slab**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #overlay | `#overlay` | 0, 0 | 1920 × 1080 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(cyan, 0.043) 1px, rgba(0, 0, 0,… |  | 0px | none | 44 44 44 44 |
| #overlay .panel.title-screen (title slab) | `#overlay .panel.title-screen` | 570, 248.64 | 780 × 582.72 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(155deg, rgba(9, 20, 36, 0.98), rgba(5, 10,… | T 4px rgb(182, 255, 87)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 4px | rgba(0, 0, 0, 0.8) 0px 40px 100px 0px, … | 0 0 0 0 |
| #overlay .title-hero | `#overlay .title-hero` | 571, 252.64 | 778 × 206.47 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 20 32 14 32 |
| #overlay .brand-line | `#overlay .brand-line` | 603, 272.64 | 714 × 33 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | B 1px rgba(cyan, 0.15) | 0px | none | 0 0 10 0 |
| #overlay .brand-tag | `#overlay .brand-tag` | 848.86, 272.64 | 132.31 × 22 | 10/900 | 2.4px | rgb(6, 33, 12) | rgb(182, 255, 87) |  | 2px | rgba(182, 255, 87, 0.35) 0px 0px 20px 0… | 4 10 4 10 |
| #overlay .brand-ver | `#overlay .brand-ver` | 991.17, 276.64 | 79.95 × 14 | 10/800 | 2px | rgba(150, 205, 230, 0.6) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .title-hero .logo | `#overlay .title-hero .logo` | 603, 315.64 | 714 × 61.47 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .snake-dot | `#overlay .snake-dot` | 794.19, 337.38 | 18 × 18 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(182, 255, 87) |  | 3px | rgba(182, 255, 87, 0.14) 0px 0px 0px 4p… | 0 0 0 0 |
| #panelTitle | `#panelTitle` | 824.19, 315.64 | 301.61 × 61.47 | 58/900 | 2.32px | rgba(0, 0, 0, 0) | lg(100deg, rgb(234, 255, 208), rgb(182, 255, … |  | 0px | none | 0 0 0 0 |
| #overlay .title-sub | `#overlay .title-sub` | 603, 385.11 | 714 × 17 | 13/400 | 2.86px | rgba(196, 228, 244, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .mode-badges | `#overlay .mode-badges` | 603, 412.11 | 714 × 29 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .mode-badges span | `#overlay .mode-badges span` | 779.14, 412.11 | 87.94 × 29 | 11/700 | 0.88px | rgba(206, 234, 250, 0.8) | rgba(cyan, 0.07) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px cyan | 2px | none | 6 12 6 12 |
| #overlay .mode-badges b | `#overlay .mode-badges b` | 794.14, 419.11 | 27.02 × 15 | 11/900 | 0.88px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .player-select | `#overlay .player-select` | 571, 459.11 | 778 × 115 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 12 32 0 32 |
| #overlay .ps-label | `#overlay .ps-label` | 603, 471.11 | 714 × 15 | 11/800 | 2.86px | rgba(150, 205, 230, 0.7) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .ps-btn | `#overlay .ps-btn` | 603, 495.11 | 351 × 79 | 13.3333/400 | normal | rgb(236, 255, 214) | lg(rgba(110, 240, 130, 0.17), rgba(9, 24, 40,… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.14) 0px 0px 26px … | 13 10 14 10 |
| #overlay .ps-btn.active | `#overlay .ps-btn.active` | 603, 495.11 | 351 × 79 | 13.3333/400 | normal | rgb(236, 255, 214) | lg(rgba(110, 240, 130, 0.17), rgba(9, 24, 40,… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.14) 0px 0px 26px … | 13 10 14 10 |
| #overlay .ps-btn b | `#overlay .ps-btn b` | 757.2, 509.11 | 42.58 × 28 | 19/900 | 1.52px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .ps-btn span | `#overlay .ps-btn span` | 745.16, 541.11 | 66.67 × 16 | 11.5/400 | 0.69px | rgba(210, 240, 220, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .panel-actions | `#overlay .panel-actions` | 571, 574.11 | 778 × 216.25 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(5, 10, 20, 0.99) 60%, rgba(5, 1… |  | 0px | none | 12 32 16 32 |
| #overlay .menu-buttons | `#overlay .menu-buttons` | 603, 586.11 | 714 × 54 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #startBtn | `#startBtn` | 603, 586.11 | 391.11 × 54 | 14/900 | 1.4px | rgb(7, 32, 12) | lg(rgb(217, 255, 122), rgb(134, 240, 106) 60%… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.2) 0px 0px 30px 0… | 13 12 13 12 |
| #kbBtn | `#kbBtn` | 1004.11, 586.11 | 312.89 × 54 | 14/900 | 1.4px | rgb(216, 244, 255) | lg(rgba(20, 48, 70, 0.9), rgba(9, 24, 40, 0.9… | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 3px rgba(cyan, 0.45)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(4, 14, 26, 0.7) 0px 8px 0px 0px | 13 12 13 12 |
| #panelHint | `#panelHint` | 603, 664.11 | 714 × 18 | 12/400 | 0.32px | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .fineprint | `#overlay .fineprint` | 603, 691.11 | 714 × 47.25 | 10.5/400 | 0.32px | rgba(160, 196, 218, 0.5) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .pad-hints | `#overlay .pad-hints` | 603, 745.36 | 714 × 29 | 10/700 | 0.8px | rgba(190, 220, 238, 0.7) | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.15) | 0px | none | 8 0 0 0 |
| #overlay .rules-details | `#overlay .rules-details` | 603, 796.36 | 714 × 34 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.15) | 0px | none | 0 0 0 0 |

**G. Settlement**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #resultOverlay | `#resultOverlay` | 0, 0 | 1920 × 1080 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .result-top | `#resultOverlay .result-top` | 0, 0 | 1920 × 66 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(rgba(4, 9, 18, 0.86) 0px, rgba(4, 9, 18, 0… |  | 0px | none | 6 24 10 24 |
| #resultOverlay .result-headline | `#resultOverlay .result-headline` | 24, 7.3 | 188.89 × 47.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .result-headline .logo | `#resultOverlay .result-headline .logo` | 24, 7.3 | 174.89 × 41.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultTitle | `#resultTitle` | 52, 7.3 | 146.89 × 41.39 | 36/900 | 0.72px | rgb(244, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultStats | `#resultStats` | — | **hidden** | · | · | rgba(196, 224, 242, 0.7… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .stage-actions | `#resultOverlay .stage-actions` | 1752.09, 6 | 143.91 × 50 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 4 0 0 0 |
| #skipStageBtn | `#skipStageBtn` | 1752.09, 10 | 143.91 × 46 | 13/800 | 1.04px | rgb(223, 246, 255) | rgba(8, 20, 36, 0.92) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 3px rgba(cyan, 0.4)<br>L 1px rgba(cyan, 0.34) | 3px | none | 9 15 9 15 |
| #resultOverlay .result-bottom | `#resultOverlay .result-bottom` | 0, 996 | 1920 × 84 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(rgba(4, 9, 18, 0) 0px, rgba(4, 9, 18, 0.95… |  | 0px | none | 12 0 8 0 |
| #resultRows | `#resultRows` | 301.73, 1008 | 1316.53 × 0 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultRows .result-row | `#resultRows .result-row` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .result-row.me | `#resultRows .result-row.me` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-rank | `#resultRows .result-row .r-rank` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-name | `#resultRows .result-row .r-name` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-len | `#resultRows .result-row .r-len` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-extra | `#resultRows .result-row .r-extra` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-avatar | `#resultRows .r-avatar` | — | — | — | — | — | — | — | — | — | — |
| #resultOverlay .result-actions | `#resultOverlay .result-actions` | 0, 1008 | 1920 × 64 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 10 22 0 22 |
| #againBtn | `#againBtn` | 805.64, 1018 | 206.81 × 54 | 22/900 | 2.2px | rgb(10, 31, 16) | lg(rgb(212, 255, 122), rgb(134, 240, 106) 60%… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 4px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.2) 0px 0px 30px 0… | 10 30 10 30 |
| #resultOverlay .result-actions .hint | `#resultOverlay .result-actions .hint` | 1028.45, 1035 | 85.89 × 20 | 12/700 | 0.72px | rgba(190, 220, 238, 0.7) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**Pseudo-elements** (this is where the OSD lives)

| pseudo | content | box | opacity | background |
|---|---|---|---|---|
| `body::before (scanlines + vignette)` | `""` | {'w': '1920px', 'h': '1080px', 'top': '0px', 'right': '0px', 'bottom'… | 1 | repeating-lg(0deg, rgba(160, 220, 255, 0.024) 0px, rgba(160, 220, 255, 0.024) 1… |
| `body::after (OSD 4-corner brackets)` | `""` | {'w': '1832px', 'h': '992px', 'top': '44px', 'right': '44px', 'bottom… | 0.55 | lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan),… |
| `#uiBar::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#uiBar::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud .stat::after (data-en watermark)` | `"TIME"` | {'w': 'auto', 'h': 'auto', 'top': '4px', 'right': '8px', 'bottom': 'a… | 1 | none |
| `.stat::after (data-en watermark)` | `"TIME"` | {'w': 'auto', 'h': 'auto', 'top': '4px', 'right': '8px', 'bottom': 'a… | 1 | none |
| `#cam::before` | `""` | {'w': '316px', 'h': '176px', 'top': '0px', 'right': '0px', 'bottom': … | 1 | none |
| `#pauseStats .stat::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#overlay .panel::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#resultOverlay .result-bottom::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#leaderboard::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#quickPlayBtn::before` | `"A"` | {'w': '22px', 'h': '22px', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | lg(rgb(226, 250, 255), rgb(138, 216, 238)) |

### 4.2 `ready` @ 1920×1080

Ready — world reset to state `ready`: HUD band live, nothing moving

`body.class = "in-round"` · `data-split = 1` · `game.state = ready` · `--ui-scale = 1`

**A. Panel chrome / OSD / merged HUD bar**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #uiBar (merged HUD bar) | `#uiBar` | 0, 0 | 1920 × 200 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(cyan, 0.043) 1px, rgba(0, 0, 0,… | B 3px cyan | 0px | rgba(0, 0, 0, 0.78) 0px 20px 52px 0px, … | 0 90 0 90 |
| #uiBar .ui-deco | `#uiBar .ui-deco` | 0, 0 | 1920 × 197 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-energy | `#uiBar .ui-energy` | 0, 0 | 1920 × 6 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(cyan, 0.16) |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-energy i | `#uiBar .ui-energy i` | 731.91, 0 | 729.59 × 6 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(0, 0, 0, 0), rgb(184, 247, 255… |  | 0px | rgba(cyan, 0.95) 0px 0px 26px 0px | 0 0 0 0 |
| #uiBar .ui-scan | `#uiBar .ui-scan` | 0, 0 | 1920 × 197 | 16/400 | 0.32px | rgb(234, 246, 255) | repeating-lg(0deg, rgba(190, 235, 255, 0.024)… |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-ruler | `#uiBar .ui-ruler` | 90, 185 | 1740 × 5 | 16/400 | 0.32px | rgb(234, 246, 255) | repeating-lg(90deg, rgba(cyan, 0.4) 0px, rgba… |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-seam | `#uiBar .ui-seam` | 0, 197 | 1920 × 3 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(0, 0, 0, 0), cyan 10%, rgb(230… |  | 0px | rgba(cyan, 0.75) 0px 0px 22px 0px | 0 0 0 0 |
| #uiBar .ui-diamond | `#uiBar .ui-diamond` | 950.81, 178.31 | 18.38 × 18.38 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(230, 251, 255) |  | 0px | cyan 0px 0px 18px 0px | 0 0 0 0 |
| #uiBar .ui-notch.left | `#uiBar .ui-notch.left` | 0, 183 | 30 × 14 | 16/400 | 0.32px | rgb(234, 246, 255) | cyan |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-notch.right | `#uiBar .ui-notch.right` | 1890, 183 | 30 × 14 | 16/400 | 0.32px | rgb(234, 246, 255) | cyan |  | 0px | none | 0 0 0 0 |

**B. Clock, stat cells, rank block**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #hud | `#hud` | 448, 23.5 | 1064 × 150 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(cyan, 0.1), rgba(cyan, 0.01) 6… | L 4px rgb(182, 255, 87) | 0px | none | 0 0 0 0 |
| #hud .stat | `#hud .stat` | 829.2, 16.2 | 305.58 × 164.59 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 24 0 24 |
| #hud .stat .k (剩余 label) | `#hud .stat .k` | 935.91, 16.2 | 92.17 × 47 | 36/700 | 10.08px | rgba(198, 232, 248, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #timeLeft (clock digits) | `#timeLeft` | 853.2, 63.2 | 257.58 × 117.59 | 120/900 | 0.32px | rgb(215, 247, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock | `#rankBlock` | 1530, 23.5 | 300 × 150 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(270deg, rgba(182, 255, 87, 0.09), rgba(0, … | R 4px rgb(182, 255, 87) | 0px | none | 0 8 0 38 |
| #rankBlock .rank-k | `#rankBlock .rank-k` | 1639.44, 11.5 | 178.56 × 47 | 36/700 | 8.64px | rgba(198, 232, 248, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rank (rank numeral) | `#rank` | 1595.42, 58.5 | 222.58 × 96 | 96/900 | 0.32px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock .rank-arrow | `#rankBlock .rank-arrow` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock .rank-total | `#rankBlock .rank-total` | 1676.92, 154.5 | 141.08 × 31 | 24/400 | 2.4px | rgba(190, 225, 240, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**C. Mirror box (the camera pane inside the HUD band)**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #cam (mirror box) | `#cam` | 90, 8.5 | 320 × 180 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(4, 11, 20) | T 2px rgba(cyan, 0.55)<br>R 2px rgba(cyan, 0.55)<br>B 2px rgba(cyan, 0.55)<br>L 2px rgba(cyan, 0.55) | 2px | rgba(cyan, 0.06) 0px 0px 0px 6px, rgba(… | 0 0 0 0 |
| #cam .cam-frame | `#cam .cam-frame` | 92, 10.5 | 316 × 176 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #cam .cam-frame i | `#cam .cam-frame i` | 97, 15.5 | 22 × 22 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | T 3px cyan<br>L 3px cyan | 0px | none | 0 0 0 0 |
| #cam .cam-rec | `#cam .cam-rec` | 385, 19.5 | 14 × 14 | 9/900 | 1.44px | rgb(255, 156, 174) | rgba(0, 0, 0, 0) |  | 50% | none | 0 0 0 0 |
| #cam .cam-tag | `#cam .cam-tag` | — | **hidden** | · | · | rgb(182, 255, 87) | rgba(4, 10, 20, 0.82) | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 1px rgba(182, 255, 87, 0.…<br>L 1px rgba(182, 255, 87, 0.… | 3px | none | 4 8 4 8 |
| #cam .cam-speed | `#cam .cam-speed` | 92, 144.5 | 316 × 42 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(2, 10, 20, 0.95), rgba(2, 10, 2… |  | 0px | none | 0 12 0 12 |
| #cam .cam-speed-val | `#cam .cam-speed-val` | 104, 148 | 92 × 35 | 26/800 | 0.52px | rgb(220, 248, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #cam .cam-speed-track | `#cam .cam-speed-track` | 206, 160.5 | 190 × 10 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 22, 36, 0.86) | T 1px rgba(cyan, 0.4)<br>R 1px rgba(cyan, 0.4)<br>B 1px rgba(cyan, 0.4)<br>L 1px rgba(cyan, 0.4) | 0px | none | 0 0 0 0 |
| #cam .cam-speed-track i | `#cam .cam-speed-track i` | 207, 161.5 | 56.39 × 8 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgb(47, 159, 214), cyan 55%, rgb(18… |  | 0px | rgba(cyan, 0.9) 0px 0px 14px 0px | 0 0 0 0 |
| #cam .cam-label | `#cam .cam-label` | 92, 151.5 | 316 × 35 | 10.5/700 | 1.05px | rgb(205, 238, 255) | lg(to top, rgba(8, 3, 16, 0.92), rgba(8, 3, 1… |  | 0px | none | 14 10 7 10 |
| #cam .cam-ready | `#cam .cam-ready` | — | **hidden** | · | · | rgb(234, 246, 255) | lg(rgba(4, 10, 20, 0), rgba(4, 10, 20, 0.88)) |  | 0px | none | 12 0 13 0 |

**D. Status, buttons, key strip, buffs, leaderboard**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #statusbar | `#statusbar` | 1771.19, 44 | 104.81 × 36 | 12/800 | 1.2px | rgb(217, 238, 251) | rgba(6, 14, 26, 0.94) | T 1px rgba(cyan, 0.34)<br>R 3px cyan<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.55) 0px 10px 26px 0px | 9 16 9 16 |
| #statusbar .dot | `#statusbar .dot` | 1788.19, 58 | 8 × 8 | 12/800 | 1.2px | rgb(217, 238, 251) | rgb(255, 197, 61) |  | 50% | rgba(255, 197, 61, 0.9) 0px 0px 12px 0px | 0 0 0 0 |
| #status (status text) | `#status` | 1804.19, 54 | 52.81 × 16 | 12/800 | 1.2px | rgb(217, 238, 251) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #quickPlayBtn | `#quickPlayBtn` | 1743, 94 | 133 × 42 | 12.5/800 | 1px | rgb(233, 255, 208) | lg(100deg, rgba(9, 26, 32, 0.97), rgba(14, 38… | T 1px rgba(182, 255, 87, 0.…<br>R 3px rgb(182, 255, 87)<br>B 1px rgba(182, 255, 87, 0.…<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(0, 0, 0, 0.55) 0px 8px 24px 0px, r… | 8 15 8 15 |
| #muteBtn | `#muteBtn` | 1630, 94 | 36 × 36 | 13.3333/400 | normal | cyan | rgba(6, 14, 26, 0.9) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | none | 0 0 0 0 |
| #padBar | `#padBar` | 274, 998 | 451.17 × 38 | 11/700 | 0.44px | rgba(214, 236, 250, 0.8) | rgba(6, 14, 26, 0.86) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px cyan | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 8 14 8 14 |
| #padBar .keycap | `#padBar .keycap` | 291, 1007 | 57.14 × 20 | 10/900 | 0.6px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) | T 1px rgba(255, 255, 255, 0…<br>R 1px rgba(255, 255, 255, 0…<br>B 1px rgba(255, 255, 255, 0…<br>L 1px rgba(255, 255, 255, 0… | 4px | rgba(0, 0, 0, 0.6) 0px 2px 0px 0px, rgb… | 0 6 0 6 |
| .keycap (generic keycap) | `.keycap` | 207.16, 237 | 28.06 × 18 | 16/900 | 0.96px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) | T 1px rgba(255, 255, 255, 0…<br>R 1px rgba(255, 255, 255, 0…<br>B 1px rgba(255, 255, 255, 0…<br>L 1px rgba(255, 255, 255, 0… | 4px | rgba(0, 0, 0, 0.6) 0px 2px 0px 0px, rgb… | 0 6 0 6 |
| #hint | `#hint` | 890.01, 989 | 139.98 × 39 | 13/800 | 0.78px | rgb(220, 255, 224) | rgba(6, 14, 26, 0.93) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px rgb(182, 255, 87) | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 10 22 10 22 |
| #buffs | `#buffs` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost (buff chip) | `#buffBoost` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(6, 14, 26, 0.95) | T 1px rgba(255, 213, 74, 0.…<br>R 3px rgba(255, 213, 74, 0.…<br>B 1px rgba(255, 213, 74, 0.…<br>L 1px rgba(255, 213, 74, 0.… | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 7 11 11 11 |
| #buffBoost .buff-name | `#buffBoost .buff-name` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-time | `#buffBoost .buff-time` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-bar | `#buffBoost .buff-bar` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(255, 255, 255, 0.12) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-bar i | `#buffBoost .buff-bar i` | — | **hidden** | · | · | rgb(255, 213, 74) | rgb(255, 213, 74) |  | 2px | none | 0 0 0 0 |
| #leaderboard | `#leaderboard` | 1650, 248 | 226 × 126 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 14, 26, 0.95) | T 3px cyan<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.6) 0px 16px 40px 0px | 11 12 10 12 |
| #leaderboard .lb-head | `#leaderboard .lb-head` | 1663, 262 | 200 × 16 | 10/700 | 1.8px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #leaderboard .lb-head span | `#leaderboard .lb-head span` | 1663, 262 | 98.36 × 16 | 10/700 | 1.8px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbTime | `#lbTime` | 1837.36, 262 | 25.64 × 16 | 12/700 | normal | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows | `#lbRows` | 1663, 285 | 200 × 78 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-row | `#lbRows .lb-row` | 1663, 285 | 200 × 24 | 12/800 | 0.32px | rgb(234, 255, 210) | rgba(182, 255, 87, 0.16) | L 3px rgb(182, 255, 87) | 2px | none | 4 6 4 6 |
| #lbRows .lb-row.me | `#lbRows .lb-row.me` | 1663, 285 | 200 × 24 | 12/800 | 0.32px | rgb(234, 255, 210) | rgba(182, 255, 87, 0.16) | L 3px rgb(182, 255, 87) | 2px | none | 4 6 4 6 |
| #lbRows .lb-rank | `#lbRows .lb-row .lb-rank` | 1672, 289 | 16 × 16 | 12/900 | 0.32px | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-name | `#lbRows .lb-row .lb-name` | 1710, 289 | 108.34 × 16 | 12/800 | 0.32px | rgb(234, 255, 210) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-len | `#lbRows .lb-row .lb-len` | 1825.34, 289 | 31.66 × 16 | 12/800 | 0.32px | rgb(234, 255, 210) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**E. Pause / OPTIONS layer**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #pauseScrim | `#pauseScrim` | 0, 200 | 1920 × 880 | 16/400 | 0.32px | rgb(234, 246, 255) | radial-gradient(at 50% 0%, rgba(6, 16, 30, 0.… |  | 0px | none | 22 0 0 0 |
| #pauseScrim .pause-scrim-inner | `#pauseScrim .pause-scrim-inner` | 793.67, 222 | 332.64 × 137 | 16/400 | 0.32px | rgb(223, 244, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim .pause-kicker | `#pauseScrim .pause-kicker` | 795.67, 222 | 328.64 × 31 | 24/800 | 6.72px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim strong | `#pauseScrim .pause-scrim-inner strong` | 793.67, 259 | 332.64 × 59 | 44/900 | 3.52px | rgb(223, 244, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim .pause-tip | `#pauseScrim .pause-tip` | 837.8, 324 | 244.39 × 35 | 26/400 | 0.32px | rgba(200, 230, 245, 0.7… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats | `#pauseStats` | 679.36, 318 | 561.28 × 193.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 16, 29, 0.97) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 4px cyan | 4px | rgba(0, 0, 0, 0.7) 0px 18px 48px 0px | 16 20 16 20 |
| #pauseStats .stat | `#pauseStats .stat` | 767.5, 335 | 120 × 110.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(12, 28, 46, 0.7) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.35) 0px 8px 28px 0px, r… | 10 14 10 14 |
| #pauseStats .stat .k | `#pauseStats .stat .k` | 782.5, 346 | 90 × 37 | 28/600 | 3.92px | rgba(190, 214, 238, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats .stat .v | `#pauseStats .stat .v` | 782.5, 384 | 90 × 50.39 | 48/900 | 0.32px | rgb(242, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats .legacy-stat (dead weight) | `#pauseStats .legacy-stat` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(12, 28, 46, 0.7) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.35) 0px 8px 28px 0px, r… | 10 14 10 14 |
| #pauseBuff | `#pauseBuff` | 703.36, 459.39 | 516.28 × 35 | 26/700 | 1.56px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning (settings drawer) | `#tuning` | 21.59, 214 | 316.23 × 64 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 14, 26, 0.95) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 3px rgb(182, 255, 87) | 4px | rgba(0, 0, 0, 0.55) 0px 10px 26px 0px | 0 0 0 0 |
| #tuning .tuning-head | `#tuning .tuning-head` | 24.59, 215 | 312.23 × 62 | 22/800 | 3.08px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 12 18 12 18 |
| #tuning .tuning-title | `#tuning .tuning-title` | 42.59, 231.5 | 152.56 × 29 | 22/800 | 3.08px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning .tuning-mark | `#tuning .tuning-mark` | 42.59, 236.5 | 11.48 × 19 | 14/800 | 3.08px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuningToggle | `#tuningToggle` | 247.22, 227 | 71.61 × 38 | 18/800 | 1.8px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) |  | 3px | none | 7 16 7 16 |
| #tuning .tuning-body | `#tuning .tuning-body` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 14 14 16 14 |
| #tuning .tuning-body .row | `#tuning .tuning-body .row` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning .ai-sep | `#tuning .ai-sep` | — | **hidden** | · | · | cyan | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.34)<br>L 3px rgb(182, 255, 87) | 0px | none | 9 0 0 10 |

**F. Start / title slab**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #overlay | `#overlay` | 0, 0 | 1920 × 1080 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(cyan, 0.043) 1px, rgba(0, 0, 0,… |  | 0px | none | 44 44 44 44 |
| #overlay .panel.title-screen (title slab) | `#overlay .panel.title-screen` | 570, 240.02 | 780 × 599.97 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(155deg, rgba(9, 20, 36, 0.98), rgba(5, 10,… | T 4px rgb(182, 255, 87)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 4px | rgba(0, 0, 0, 0.8) 0px 40px 100px 0px, … | 0 0 0 0 |
| #overlay .title-hero | `#overlay .title-hero` | 571, 244.02 | 778 × 206.47 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 20 32 14 32 |
| #overlay .brand-line | `#overlay .brand-line` | 603, 264.02 | 714 × 33 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | B 1px rgba(cyan, 0.15) | 0px | none | 0 0 10 0 |
| #overlay .brand-tag | `#overlay .brand-tag` | 848.86, 264.02 | 132.31 × 22 | 10/900 | 2.4px | rgb(6, 33, 12) | rgb(182, 255, 87) |  | 2px | rgba(182, 255, 87, 0.35) 0px 0px 20px 0… | 4 10 4 10 |
| #overlay .brand-ver | `#overlay .brand-ver` | 991.17, 268.02 | 79.95 × 14 | 10/800 | 2px | rgba(150, 205, 230, 0.6) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .title-hero .logo | `#overlay .title-hero .logo` | 603, 307.02 | 714 × 61.47 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .snake-dot | `#overlay .snake-dot` | 794.19, 328.75 | 18 × 18 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(182, 255, 87) |  | 3px | rgba(182, 255, 87, 0.14) 0px 0px 0px 4p… | 0 0 0 0 |
| #panelTitle | `#panelTitle` | 824.19, 307.02 | 301.61 × 61.47 | 58/900 | 2.32px | rgba(0, 0, 0, 0) | lg(100deg, rgb(234, 255, 208), rgb(182, 255, … |  | 0px | none | 0 0 0 0 |
| #overlay .title-sub | `#overlay .title-sub` | 603, 376.48 | 714 × 17 | 13/400 | 2.86px | rgba(196, 228, 244, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .mode-badges | `#overlay .mode-badges` | 603, 403.48 | 714 × 29 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .mode-badges span | `#overlay .mode-badges span` | 779.14, 403.48 | 87.94 × 29 | 11/700 | 0.88px | rgba(206, 234, 250, 0.8) | rgba(cyan, 0.07) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px cyan | 2px | none | 6 12 6 12 |
| #overlay .mode-badges b | `#overlay .mode-badges b` | 794.14, 410.48 | 27.02 × 15 | 11/900 | 0.88px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .player-select | `#overlay .player-select` | 571, 450.48 | 778 × 115 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 12 32 0 32 |
| #overlay .ps-label | `#overlay .ps-label` | 603, 462.48 | 714 × 15 | 11/800 | 2.86px | rgba(150, 205, 230, 0.7) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .ps-btn | `#overlay .ps-btn` | 603, 486.48 | 351 × 79 | 13.3333/400 | normal | rgb(236, 255, 214) | lg(rgba(110, 240, 130, 0.17), rgba(9, 24, 40,… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.14) 0px 0px 26px … | 13 10 14 10 |
| #overlay .ps-btn.active | `#overlay .ps-btn.active` | 603, 486.48 | 351 × 79 | 13.3333/400 | normal | rgb(236, 255, 214) | lg(rgba(110, 240, 130, 0.17), rgba(9, 24, 40,… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.14) 0px 0px 26px … | 13 10 14 10 |
| #overlay .ps-btn b | `#overlay .ps-btn b` | 757.2, 500.48 | 42.58 × 28 | 19/900 | 1.52px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .ps-btn span | `#overlay .ps-btn span` | 745.16, 532.48 | 66.67 × 16 | 11.5/400 | 0.69px | rgba(210, 240, 220, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .panel-actions | `#overlay .panel-actions` | 571, 565.48 | 778 × 233.5 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(5, 10, 20, 0.99) 60%, rgba(5, 1… |  | 0px | none | 12 32 16 32 |
| #overlay .menu-buttons | `#overlay .menu-buttons` | 603, 577.48 | 714 × 54 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #startBtn | `#startBtn` | 603, 577.48 | 391.11 × 54 | 14/900 | 1.4px | rgb(7, 32, 12) | lg(rgb(217, 255, 122), rgb(134, 240, 106) 60%… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.2) 0px 0px 30px 0… | 13 12 13 12 |
| #kbBtn | `#kbBtn` | 1004.11, 577.48 | 312.89 × 54 | 14/900 | 1.4px | rgb(216, 244, 255) | lg(rgba(20, 48, 70, 0.9), rgba(9, 24, 40, 0.9… | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 3px rgba(cyan, 0.45)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(4, 14, 26, 0.7) 0px 8px 0px 0px | 13 12 13 12 |
| #panelHint | `#panelHint` | 603, 672.73 | 714 × 18 | 12/400 | 0.32px | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .fineprint | `#overlay .fineprint` | 603, 699.73 | 714 × 47.25 | 10.5/400 | 0.32px | rgba(160, 196, 218, 0.5) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .pad-hints | `#overlay .pad-hints` | 603, 753.98 | 714 × 29 | 10/700 | 0.8px | rgba(190, 220, 238, 0.7) | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.15) | 0px | none | 8 0 0 0 |
| #overlay .rules-details | `#overlay .rules-details` | 603, 804.98 | 714 × 34 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.15) | 0px | none | 0 0 0 0 |

**G. Settlement**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #resultOverlay | `#resultOverlay` | 0, 0 | 1920 × 1080 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .result-top | `#resultOverlay .result-top` | 0, 0 | 1920 × 66 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(rgba(4, 9, 18, 0.86) 0px, rgba(4, 9, 18, 0… |  | 0px | none | 6 24 10 24 |
| #resultOverlay .result-headline | `#resultOverlay .result-headline` | 24, 7.3 | 188.89 × 47.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .result-headline .logo | `#resultOverlay .result-headline .logo` | 24, 7.3 | 174.89 × 41.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultTitle | `#resultTitle` | 52, 7.3 | 146.89 × 41.39 | 36/900 | 0.72px | rgb(244, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultStats | `#resultStats` | — | **hidden** | · | · | rgba(196, 224, 242, 0.7… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .stage-actions | `#resultOverlay .stage-actions` | 1752.09, 6 | 143.91 × 50 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 4 0 0 0 |
| #skipStageBtn | `#skipStageBtn` | 1752.09, 10 | 143.91 × 46 | 13/800 | 1.04px | rgb(223, 246, 255) | rgba(8, 20, 36, 0.92) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 3px rgba(cyan, 0.4)<br>L 1px rgba(cyan, 0.34) | 3px | none | 9 15 9 15 |
| #resultOverlay .result-bottom | `#resultOverlay .result-bottom` | 0, 996 | 1920 × 84 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(rgba(4, 9, 18, 0) 0px, rgba(4, 9, 18, 0.95… |  | 0px | none | 12 0 8 0 |
| #resultRows | `#resultRows` | 301.73, 1008 | 1316.53 × 0 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultRows .result-row | `#resultRows .result-row` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .result-row.me | `#resultRows .result-row.me` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-rank | `#resultRows .result-row .r-rank` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-name | `#resultRows .result-row .r-name` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-len | `#resultRows .result-row .r-len` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-extra | `#resultRows .result-row .r-extra` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-avatar | `#resultRows .r-avatar` | — | — | — | — | — | — | — | — | — | — |
| #resultOverlay .result-actions | `#resultOverlay .result-actions` | 0, 1008 | 1920 × 64 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 10 22 0 22 |
| #againBtn | `#againBtn` | 805.64, 1018 | 206.81 × 54 | 22/900 | 2.2px | rgb(10, 31, 16) | lg(rgb(212, 255, 122), rgb(134, 240, 106) 60%… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 4px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.2) 0px 0px 30px 0… | 10 30 10 30 |
| #resultOverlay .result-actions .hint | `#resultOverlay .result-actions .hint` | 1028.45, 1035 | 85.89 × 20 | 12/700 | 0.72px | rgba(190, 220, 238, 0.7) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**Pseudo-elements** (this is where the OSD lives)

| pseudo | content | box | opacity | background |
|---|---|---|---|---|
| `body::before (scanlines + vignette)` | `""` | {'w': '1920px', 'h': '1080px', 'top': '0px', 'right': '0px', 'bottom'… | 1 | repeating-lg(0deg, rgba(160, 220, 255, 0.024) 0px, rgba(160, 220, 255, 0.024) 1… |
| `body::after (OSD 4-corner brackets)` | `""` | {'w': '1832px', 'h': '992px', 'top': '44px', 'right': '44px', 'bottom… | 0.55 | lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan),… |
| `#uiBar::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#uiBar::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud .stat::after (data-en watermark)` | `"TIME"` | {'w': 'auto', 'h': 'auto', 'top': '4px', 'right': '8px', 'bottom': 'a… | 1 | none |
| `.stat::after (data-en watermark)` | `"TIME"` | {'w': 'auto', 'h': 'auto', 'top': '4px', 'right': '8px', 'bottom': 'a… | 1 | none |
| `#cam::before` | `""` | {'w': '316px', 'h': '176px', 'top': '0px', 'right': '0px', 'bottom': … | 1 | none |
| `#pauseStats .stat::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#overlay .panel::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#resultOverlay .result-bottom::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#leaderboard::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#quickPlayBtn::before` | `"A"` | {'w': '22px', 'h': '22px', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | lg(rgb(226, 250, 255), rgb(138, 216, 238)) |

### 4.3 `play` @ 1920×1080

In-game (round actually running, clock counting down)

`body.class = "in-round"` · `data-split = 1` · `game.state = playing` · `--ui-scale = 1`

**A. Panel chrome / OSD / merged HUD bar**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #uiBar (merged HUD bar) | `#uiBar` | 0, 0 | 1920 × 200 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(cyan, 0.043) 1px, rgba(0, 0, 0,… | B 3px cyan | 0px | rgba(0, 0, 0, 0.78) 0px 20px 52px 0px, … | 0 90 0 90 |
| #uiBar .ui-deco | `#uiBar .ui-deco` | 0, 0 | 1920 × 197 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-energy | `#uiBar .ui-energy` | 0, 0 | 1920 × 6 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(cyan, 0.16) |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-energy i | `#uiBar .ui-energy i` | 13, 0 | 729.59 × 6 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(0, 0, 0, 0), rgb(184, 247, 255… |  | 0px | rgba(cyan, 0.95) 0px 0px 26px 0px | 0 0 0 0 |
| #uiBar .ui-scan | `#uiBar .ui-scan` | 0, 0 | 1920 × 197 | 16/400 | 0.32px | rgb(234, 246, 255) | repeating-lg(0deg, rgba(190, 235, 255, 0.024)… |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-ruler | `#uiBar .ui-ruler` | 90, 185 | 1740 × 5 | 16/400 | 0.32px | rgb(234, 246, 255) | repeating-lg(90deg, rgba(cyan, 0.4) 0px, rgba… |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-seam | `#uiBar .ui-seam` | 0, 197 | 1920 × 3 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(0, 0, 0, 0), cyan 10%, rgb(230… |  | 0px | rgba(cyan, 0.75) 0px 0px 22px 0px | 0 0 0 0 |
| #uiBar .ui-diamond | `#uiBar .ui-diamond` | 950.81, 178.31 | 18.38 × 18.38 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(230, 251, 255) |  | 0px | cyan 0px 0px 18px 0px | 0 0 0 0 |
| #uiBar .ui-notch.left | `#uiBar .ui-notch.left` | 0, 183 | 30 × 14 | 16/400 | 0.32px | rgb(234, 246, 255) | cyan |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-notch.right | `#uiBar .ui-notch.right` | 1890, 183 | 30 × 14 | 16/400 | 0.32px | rgb(234, 246, 255) | cyan |  | 0px | none | 0 0 0 0 |

**B. Clock, stat cells, rank block**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #hud | `#hud` | 448, 23.5 | 1064 × 150 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(cyan, 0.1), rgba(cyan, 0.01) 6… | L 4px rgb(182, 255, 87) | 0px | none | 0 0 0 0 |
| #hud .stat | `#hud .stat` | 829.2, 16.2 | 305.58 × 164.59 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 24 0 24 |
| #hud .stat .k (剩余 label) | `#hud .stat .k` | 935.91, 16.2 | 92.17 × 47 | 36/700 | 10.08px | rgba(198, 232, 248, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #timeLeft (clock digits) | `#timeLeft` | 853.2, 63.2 | 257.58 × 117.59 | 120/900 | 0.32px | rgb(215, 247, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock | `#rankBlock` | 1530, 23.5 | 300 × 150 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(270deg, rgba(182, 255, 87, 0.09), rgba(0, … | R 4px rgb(182, 255, 87) | 0px | none | 0 8 0 38 |
| #rankBlock .rank-k | `#rankBlock .rank-k` | 1639.44, 11.5 | 178.56 × 47 | 36/700 | 8.64px | rgba(198, 232, 248, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rank (rank numeral) | `#rank` | 1595.42, 60.31 | 222.58 × 96 | 96/900 | 0.32px | rgb(255, 154, 114) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock .rank-arrow | `#rankBlock .rank-arrow` | 1534, 75.56 | 35.95 × 47 | 36/900 | 0.32px | rgb(255, 154, 114) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock .rank-total | `#rankBlock .rank-total` | 1676.92, 154.5 | 141.08 × 31 | 24/400 | 2.4px | rgba(190, 225, 240, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**C. Mirror box (the camera pane inside the HUD band)**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #cam (mirror box) | `#cam` | 90, 8.5 | 320 × 180 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(4, 11, 20) | T 2px rgba(cyan, 0.55)<br>R 2px rgba(cyan, 0.55)<br>B 2px rgba(cyan, 0.55)<br>L 2px rgba(cyan, 0.55) | 2px | rgba(cyan, 0.06) 0px 0px 0px 6px, rgba(… | 0 0 0 0 |
| #cam .cam-frame | `#cam .cam-frame` | 92, 10.5 | 316 × 176 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #cam .cam-frame i | `#cam .cam-frame i` | 97, 15.5 | 22 × 22 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | T 3px cyan<br>L 3px cyan | 0px | none | 0 0 0 0 |
| #cam .cam-rec | `#cam .cam-rec` | 385, 19.5 | 14 × 14 | 9/900 | 1.44px | rgb(255, 156, 174) | rgba(0, 0, 0, 0) |  | 50% | none | 0 0 0 0 |
| #cam .cam-tag | `#cam .cam-tag` | — | **hidden** | · | · | rgb(182, 255, 87) | rgba(4, 10, 20, 0.82) | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 1px rgba(182, 255, 87, 0.…<br>L 1px rgba(182, 255, 87, 0.… | 3px | none | 4 8 4 8 |
| #cam .cam-speed | `#cam .cam-speed` | 92, 144.5 | 316 × 42 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(2, 10, 20, 0.95), rgba(2, 10, 2… |  | 0px | none | 0 12 0 12 |
| #cam .cam-speed-val | `#cam .cam-speed-val` | 104, 148 | 92 × 35 | 26/800 | 0.52px | rgb(220, 248, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #cam .cam-speed-track | `#cam .cam-speed-track` | 206, 160.5 | 190 × 10 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 22, 36, 0.86) | T 1px rgba(cyan, 0.4)<br>R 1px rgba(cyan, 0.4)<br>B 1px rgba(cyan, 0.4)<br>L 1px rgba(cyan, 0.4) | 0px | none | 0 0 0 0 |
| #cam .cam-speed-track i | `#cam .cam-speed-track i` | 207, 161.5 | 56.39 × 8 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgb(47, 159, 214), cyan 55%, rgb(18… |  | 0px | rgba(cyan, 0.9) 0px 0px 14px 0px | 0 0 0 0 |
| #cam .cam-label | `#cam .cam-label` | 92, 151.5 | 316 × 35 | 10.5/700 | 1.05px | rgb(205, 238, 255) | lg(to top, rgba(8, 3, 16, 0.92), rgba(8, 3, 1… |  | 0px | none | 14 10 7 10 |
| #cam .cam-ready | `#cam .cam-ready` | — | **hidden** | · | · | rgb(234, 246, 255) | lg(rgba(4, 10, 20, 0), rgba(4, 10, 20, 0.88)) |  | 0px | none | 12 0 13 0 |

**D. Status, buttons, key strip, buffs, leaderboard**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #statusbar | `#statusbar` | 1784.39, 44 | 91.61 × 36 | 12/800 | 1.2px | rgb(217, 238, 251) | rgba(6, 14, 26, 0.94) | T 1px rgba(cyan, 0.34)<br>R 3px cyan<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.55) 0px 10px 26px 0px | 9 16 9 16 |
| #statusbar .dot | `#statusbar .dot` | 1801.39, 58 | 8 × 8 | 12/800 | 1.2px | rgb(217, 238, 251) | rgb(91, 234, 160) |  | 50% | rgba(91, 234, 160, 0.9) 0px 0px 12px 0px | 0 0 0 0 |
| #status (status text) | `#status` | 1817.39, 54 | 39.61 × 16 | 12/800 | 1.2px | rgb(217, 238, 251) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #quickPlayBtn | `#quickPlayBtn` | 1743, 94 | 133 × 42 | 12.5/800 | 1px | rgb(233, 255, 208) | lg(100deg, rgba(9, 26, 32, 0.97), rgba(14, 38… | T 1px rgba(182, 255, 87, 0.…<br>R 3px rgb(182, 255, 87)<br>B 1px rgba(182, 255, 87, 0.…<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(0, 0, 0, 0.55) 0px 8px 24px 0px, r… | 8 15 8 15 |
| #muteBtn | `#muteBtn` | 1630, 94 | 36 × 36 | 13.3333/400 | normal | cyan | rgba(6, 14, 26, 0.9) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | none | 0 0 0 0 |
| #padBar | `#padBar` | 274, 998 | 451.17 × 38 | 11/700 | 0.44px | rgba(214, 236, 250, 0.8) | rgba(6, 14, 26, 0.86) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px cyan | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 8 14 8 14 |
| #padBar .keycap | `#padBar .keycap` | 291, 1007 | 57.14 × 20 | 10/900 | 0.6px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) | T 1px rgba(255, 255, 255, 0…<br>R 1px rgba(255, 255, 255, 0…<br>B 1px rgba(255, 255, 255, 0…<br>L 1px rgba(255, 255, 255, 0… | 4px | rgba(0, 0, 0, 0.6) 0px 2px 0px 0px, rgb… | 0 6 0 6 |
| .keycap (generic keycap) | `.keycap` | 207.16, 237 | 28.06 × 18 | 16/900 | 0.96px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) | T 1px rgba(255, 255, 255, 0…<br>R 1px rgba(255, 255, 255, 0…<br>B 1px rgba(255, 255, 255, 0…<br>L 1px rgba(255, 255, 255, 0… | 4px | rgba(0, 0, 0, 0.6) 0px 2px 0px 0px, rgb… | 0 6 0 6 |
| #hint | `#hint` | 890.01, 989 | 139.98 × 39 | 13/800 | 0.78px | rgb(220, 255, 224) | rgba(6, 14, 26, 0.93) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px rgb(182, 255, 87) | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 10 22 10 22 |
| #buffs | `#buffs` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost (buff chip) | `#buffBoost` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(6, 14, 26, 0.95) | T 1px rgba(255, 213, 74, 0.…<br>R 3px rgba(255, 213, 74, 0.…<br>B 1px rgba(255, 213, 74, 0.…<br>L 1px rgba(255, 213, 74, 0.… | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 7 11 11 11 |
| #buffBoost .buff-name | `#buffBoost .buff-name` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-time | `#buffBoost .buff-time` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-bar | `#buffBoost .buff-bar` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(255, 255, 255, 0.12) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-bar i | `#buffBoost .buff-bar i` | — | **hidden** | · | · | rgb(255, 213, 74) | rgb(255, 213, 74) |  | 2px | none | 0 0 0 0 |
| #leaderboard | `#leaderboard` | 1650, 248 | 226 × 153 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 14, 26, 0.95) | T 3px cyan<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.6) 0px 16px 40px 0px | 11 12 10 12 |
| #leaderboard .lb-head | `#leaderboard .lb-head` | 1663, 262 | 200 × 16 | 10/700 | 1.8px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #leaderboard .lb-head span | `#leaderboard .lb-head span` | 1663, 262 | 98.36 × 16 | 10/700 | 1.8px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbTime | `#lbTime` | 1837.36, 262 | 25.64 × 16 | 12/700 | normal | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows | `#lbRows` | 1663, 285 | 200 × 105 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-row | `#lbRows .lb-row` | 1663, 285 | 200 × 24 | 12/400 | 0.32px | rgb(220, 234, 245) | rgba(0, 0, 0, 0) |  | 2px | none | 4 6 4 6 |
| #lbRows .lb-row.me | `#lbRows .lb-row.me` | 1663, 366 | 200 × 24 | 12/800 | 0.32px | rgb(234, 255, 210) | rgba(182, 255, 87, 0.16) | L 3px rgb(182, 255, 87) | 2px | none | 4 6 4 6 |
| #lbRows .lb-rank | `#lbRows .lb-row .lb-rank` | 1669, 289 | 16 × 16 | 12/900 | 0.32px | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-name | `#lbRows .lb-row .lb-name` | 1707, 289 | 111.34 × 16 | 12/400 | 0.32px | rgb(220, 234, 245) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-len | `#lbRows .lb-row .lb-len` | 1825.34, 289 | 31.66 × 16 | 12/800 | 0.32px | rgb(220, 234, 245) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**E. Pause / OPTIONS layer**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #pauseScrim | `#pauseScrim` | 0, 200 | 1920 × 880 | 16/400 | 0.32px | rgb(234, 246, 255) | radial-gradient(at 50% 0%, rgba(6, 16, 30, 0.… |  | 0px | none | 22 0 0 0 |
| #pauseScrim .pause-scrim-inner | `#pauseScrim .pause-scrim-inner` | 793.67, 222 | 332.64 × 137 | 16/400 | 0.32px | rgb(223, 244, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim .pause-kicker | `#pauseScrim .pause-kicker` | 795.67, 222 | 328.64 × 31 | 24/800 | 6.72px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim strong | `#pauseScrim .pause-scrim-inner strong` | 793.67, 259 | 332.64 × 59 | 44/900 | 3.52px | rgb(223, 244, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim .pause-tip | `#pauseScrim .pause-tip` | 837.8, 324 | 244.39 × 35 | 26/400 | 0.32px | rgba(200, 230, 245, 0.7… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats | `#pauseStats` | 679.36, 318 | 561.28 × 193.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 16, 29, 0.97) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 4px cyan | 4px | rgba(0, 0, 0, 0.7) 0px 18px 48px 0px | 16 20 16 20 |
| #pauseStats .stat | `#pauseStats .stat` | 767.5, 335 | 120 × 110.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(12, 28, 46, 0.7) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.35) 0px 8px 28px 0px, r… | 10 14 10 14 |
| #pauseStats .stat .k | `#pauseStats .stat .k` | 782.5, 346 | 90 × 37 | 28/600 | 3.92px | rgba(190, 214, 238, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats .stat .v | `#pauseStats .stat .v` | 782.5, 384 | 90 × 50.39 | 48/900 | 0.32px | rgb(242, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats .legacy-stat (dead weight) | `#pauseStats .legacy-stat` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(12, 28, 46, 0.7) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.35) 0px 8px 28px 0px, r… | 10 14 10 14 |
| #pauseBuff | `#pauseBuff` | 703.36, 459.39 | 516.28 × 35 | 26/700 | 1.56px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning (settings drawer) | `#tuning` | 21.59, 214 | 316.23 × 64 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 14, 26, 0.95) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 3px rgb(182, 255, 87) | 4px | rgba(0, 0, 0, 0.55) 0px 10px 26px 0px | 0 0 0 0 |
| #tuning .tuning-head | `#tuning .tuning-head` | 24.59, 215 | 312.23 × 62 | 22/800 | 3.08px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 12 18 12 18 |
| #tuning .tuning-title | `#tuning .tuning-title` | 42.59, 231.5 | 152.56 × 29 | 22/800 | 3.08px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning .tuning-mark | `#tuning .tuning-mark` | 42.59, 236.5 | 11.48 × 19 | 14/800 | 3.08px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuningToggle | `#tuningToggle` | 247.22, 227 | 71.61 × 38 | 18/800 | 1.8px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) |  | 3px | none | 7 16 7 16 |
| #tuning .tuning-body | `#tuning .tuning-body` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 14 14 16 14 |
| #tuning .tuning-body .row | `#tuning .tuning-body .row` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning .ai-sep | `#tuning .ai-sep` | — | **hidden** | · | · | cyan | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.34)<br>L 3px rgb(182, 255, 87) | 0px | none | 9 0 0 10 |

**F. Start / title slab**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #overlay | `#overlay` | 0, 0 | 1920 × 1080 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(cyan, 0.043) 1px, rgba(0, 0, 0,… |  | 0px | none | 44 44 44 44 |
| #overlay .panel.title-screen (title slab) | `#overlay .panel.title-screen` | 570, 255.14 | 780 × 569.72 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(155deg, rgba(9, 20, 36, 0.98), rgba(5, 10,… | T 4px rgb(182, 255, 87)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 4px | rgba(0, 0, 0, 0.8) 0px 40px 100px 0px, … | 0 0 0 0 |
| #overlay .title-hero | `#overlay .title-hero` | 571, 259.14 | 778 × 206.47 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 20 32 14 32 |
| #overlay .brand-line | `#overlay .brand-line` | 603, 279.14 | 714 × 33 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | B 1px rgba(cyan, 0.15) | 0px | none | 0 0 10 0 |
| #overlay .brand-tag | `#overlay .brand-tag` | 848.86, 279.14 | 132.31 × 22 | 10/900 | 2.4px | rgb(6, 33, 12) | rgb(182, 255, 87) |  | 2px | rgba(182, 255, 87, 0.35) 0px 0px 20px 0… | 4 10 4 10 |
| #overlay .brand-ver | `#overlay .brand-ver` | 991.17, 283.14 | 79.95 × 14 | 10/800 | 2px | rgba(150, 205, 230, 0.6) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .title-hero .logo | `#overlay .title-hero .logo` | 603, 322.14 | 714 × 61.47 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .snake-dot | `#overlay .snake-dot` | 794.19, 343.88 | 18 × 18 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(182, 255, 87) |  | 3px | rgba(182, 255, 87, 0.14) 0px 0px 0px 4p… | 0 0 0 0 |
| #panelTitle | `#panelTitle` | 824.19, 322.14 | 301.61 × 61.47 | 58/900 | 2.32px | rgba(0, 0, 0, 0) | lg(100deg, rgb(234, 255, 208), rgb(182, 255, … |  | 0px | none | 0 0 0 0 |
| #overlay .title-sub | `#overlay .title-sub` | 603, 391.61 | 714 × 17 | 13/400 | 2.86px | rgba(196, 228, 244, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .mode-badges | `#overlay .mode-badges` | 603, 418.61 | 714 × 29 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .mode-badges span | `#overlay .mode-badges span` | 779.14, 418.61 | 87.94 × 29 | 11/700 | 0.88px | rgba(206, 234, 250, 0.8) | rgba(cyan, 0.07) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px cyan | 2px | none | 6 12 6 12 |
| #overlay .mode-badges b | `#overlay .mode-badges b` | 794.14, 425.61 | 27.02 × 15 | 11/900 | 0.88px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .player-select | `#overlay .player-select` | 571, 465.61 | 778 × 115 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 12 32 0 32 |
| #overlay .ps-label | `#overlay .ps-label` | 603, 477.61 | 714 × 15 | 11/800 | 2.86px | rgba(150, 205, 230, 0.7) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .ps-btn | `#overlay .ps-btn` | 603, 501.61 | 351 × 79 | 13.3333/400 | normal | rgb(236, 255, 214) | lg(rgba(110, 240, 130, 0.17), rgba(9, 24, 40,… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.14) 0px 0px 26px … | 13 10 14 10 |
| #overlay .ps-btn.active | `#overlay .ps-btn.active` | 603, 501.61 | 351 × 79 | 13.3333/400 | normal | rgb(236, 255, 214) | lg(rgba(110, 240, 130, 0.17), rgba(9, 24, 40,… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.14) 0px 0px 26px … | 13 10 14 10 |
| #overlay .ps-btn b | `#overlay .ps-btn b` | 757.2, 515.61 | 42.58 × 28 | 19/900 | 1.52px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .ps-btn span | `#overlay .ps-btn span` | 745.16, 547.61 | 66.67 × 16 | 11.5/400 | 0.69px | rgba(210, 240, 220, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .panel-actions | `#overlay .panel-actions` | 571, 580.61 | 778 × 203.25 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(5, 10, 20, 0.99) 60%, rgba(5, 1… |  | 0px | none | 12 32 16 32 |
| #overlay .menu-buttons | `#overlay .menu-buttons` | 603, 592.61 | 714 × 54 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #startBtn | `#startBtn` | 603, 592.61 | 391.11 × 54 | 14/900 | 1.4px | rgb(7, 32, 12) | lg(rgb(217, 255, 122), rgb(134, 240, 106) 60%… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.2) 0px 0px 30px 0… | 13 12 13 12 |
| #kbBtn | `#kbBtn` | 1004.11, 592.61 | 312.89 × 54 | 14/900 | 1.4px | rgb(216, 244, 255) | lg(rgba(20, 48, 70, 0.9), rgba(9, 24, 40, 0.9… | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 3px rgba(cyan, 0.45)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(4, 14, 26, 0.7) 0px 8px 0px 0px | 13 12 13 12 |
| #panelHint | `#panelHint` | 603, 657.61 | 714 × 18 | 12/400 | 0.32px | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .fineprint | `#overlay .fineprint` | 603, 684.61 | 714 × 47.25 | 10.5/400 | 0.32px | rgba(160, 196, 218, 0.5) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .pad-hints | `#overlay .pad-hints` | 603, 738.86 | 714 × 29 | 10/700 | 0.8px | rgba(190, 220, 238, 0.7) | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.15) | 0px | none | 8 0 0 0 |
| #overlay .rules-details | `#overlay .rules-details` | 603, 789.86 | 714 × 34 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.15) | 0px | none | 0 0 0 0 |

**G. Settlement**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #resultOverlay | `#resultOverlay` | 0, 0 | 1920 × 1080 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .result-top | `#resultOverlay .result-top` | 0, 0 | 1920 × 66 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(rgba(4, 9, 18, 0.86) 0px, rgba(4, 9, 18, 0… |  | 0px | none | 6 24 10 24 |
| #resultOverlay .result-headline | `#resultOverlay .result-headline` | 24, 7.3 | 188.89 × 47.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .result-headline .logo | `#resultOverlay .result-headline .logo` | 24, 7.3 | 174.89 × 41.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultTitle | `#resultTitle` | 52, 7.3 | 146.89 × 41.39 | 36/900 | 0.72px | rgb(244, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultStats | `#resultStats` | — | **hidden** | · | · | rgba(196, 224, 242, 0.7… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .stage-actions | `#resultOverlay .stage-actions` | 1752.09, 6 | 143.91 × 50 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 4 0 0 0 |
| #skipStageBtn | `#skipStageBtn` | 1752.09, 10 | 143.91 × 46 | 13/800 | 1.04px | rgb(223, 246, 255) | rgba(8, 20, 36, 0.92) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 3px rgba(cyan, 0.4)<br>L 1px rgba(cyan, 0.34) | 3px | none | 9 15 9 15 |
| #resultOverlay .result-bottom | `#resultOverlay .result-bottom` | 0, 996 | 1920 × 84 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(rgba(4, 9, 18, 0) 0px, rgba(4, 9, 18, 0.95… |  | 0px | none | 12 0 8 0 |
| #resultRows | `#resultRows` | 301.73, 1008 | 1316.53 × 0 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultRows .result-row | `#resultRows .result-row` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .result-row.me | `#resultRows .result-row.me` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-rank | `#resultRows .result-row .r-rank` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-name | `#resultRows .result-row .r-name` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-len | `#resultRows .result-row .r-len` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-extra | `#resultRows .result-row .r-extra` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-avatar | `#resultRows .r-avatar` | — | — | — | — | — | — | — | — | — | — |
| #resultOverlay .result-actions | `#resultOverlay .result-actions` | 0, 1008 | 1920 × 64 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 10 22 0 22 |
| #againBtn | `#againBtn` | 805.64, 1018 | 206.81 × 54 | 22/900 | 2.2px | rgb(10, 31, 16) | lg(rgb(212, 255, 122), rgb(134, 240, 106) 60%… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 4px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.2) 0px 0px 30px 0… | 10 30 10 30 |
| #resultOverlay .result-actions .hint | `#resultOverlay .result-actions .hint` | 1028.45, 1035 | 85.89 × 20 | 12/700 | 0.72px | rgba(190, 220, 238, 0.7) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**Pseudo-elements** (this is where the OSD lives)

| pseudo | content | box | opacity | background |
|---|---|---|---|---|
| `body::before (scanlines + vignette)` | `""` | {'w': '1920px', 'h': '1080px', 'top': '0px', 'right': '0px', 'bottom'… | 1 | repeating-lg(0deg, rgba(160, 220, 255, 0.024) 0px, rgba(160, 220, 255, 0.024) 1… |
| `body::after (OSD 4-corner brackets)` | `""` | {'w': '1832px', 'h': '992px', 'top': '44px', 'right': '44px', 'bottom… | 0.55 | lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan),… |
| `#uiBar::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#uiBar::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud .stat::after (data-en watermark)` | `"TIME"` | {'w': 'auto', 'h': 'auto', 'top': '4px', 'right': '8px', 'bottom': 'a… | 1 | none |
| `.stat::after (data-en watermark)` | `"TIME"` | {'w': 'auto', 'h': 'auto', 'top': '4px', 'right': '8px', 'bottom': 'a… | 1 | none |
| `#cam::before` | `""` | {'w': '316px', 'h': '176px', 'top': '0px', 'right': '0px', 'bottom': … | 1 | none |
| `#pauseStats .stat::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#overlay .panel::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#resultOverlay .result-bottom::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#leaderboard::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#quickPlayBtn::before` | `"A"` | {'w': '22px', 'h': '22px', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | lg(rgb(226, 250, 255), rgb(138, 216, 238)) |

### 4.4 `pause` @ 1920×1080

Pause / OPTIONS layer (`body.pause-open`, key O)

`body.class = "in-round pause-open"` · `data-split = 1` · `game.state = playing` · `--ui-scale = 1`

**A. Panel chrome / OSD / merged HUD bar**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #uiBar (merged HUD bar) | `#uiBar` | 0, 0 | 1920 × 200 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(cyan, 0.043) 1px, rgba(0, 0, 0,… | B 3px cyan | 0px | rgba(0, 0, 0, 0.78) 0px 20px 52px 0px, … | 0 90 0 90 |
| #uiBar .ui-deco | `#uiBar .ui-deco` | 0, 0 | 1920 × 197 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-energy | `#uiBar .ui-energy` | 0, 0 | 1920 × 6 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(cyan, 0.16) |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-energy i | `#uiBar .ui-energy i` | 863.59, 0 | 729.59 × 6 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(0, 0, 0, 0), rgb(184, 247, 255… |  | 0px | rgba(cyan, 0.95) 0px 0px 26px 0px | 0 0 0 0 |
| #uiBar .ui-scan | `#uiBar .ui-scan` | 0, 0 | 1920 × 197 | 16/400 | 0.32px | rgb(234, 246, 255) | repeating-lg(0deg, rgba(190, 235, 255, 0.024)… |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-ruler | `#uiBar .ui-ruler` | 90, 185 | 1740 × 5 | 16/400 | 0.32px | rgb(234, 246, 255) | repeating-lg(90deg, rgba(cyan, 0.4) 0px, rgba… |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-seam | `#uiBar .ui-seam` | 0, 197 | 1920 × 3 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(0, 0, 0, 0), cyan 10%, rgb(230… |  | 0px | rgba(cyan, 0.75) 0px 0px 22px 0px | 0 0 0 0 |
| #uiBar .ui-diamond | `#uiBar .ui-diamond` | 950.81, 178.31 | 18.38 × 18.38 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(230, 251, 255) |  | 0px | cyan 0px 0px 18px 0px | 0 0 0 0 |
| #uiBar .ui-notch.left | `#uiBar .ui-notch.left` | 0, 183 | 30 × 14 | 16/400 | 0.32px | rgb(234, 246, 255) | cyan |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-notch.right | `#uiBar .ui-notch.right` | 1890, 183 | 30 × 14 | 16/400 | 0.32px | rgb(234, 246, 255) | cyan |  | 0px | none | 0 0 0 0 |

**B. Clock, stat cells, rank block**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #hud | `#hud` | 448, 23.5 | 1064 × 150 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(cyan, 0.1), rgba(cyan, 0.01) 6… | L 4px rgb(182, 255, 87) | 0px | none | 0 0 0 0 |
| #hud .stat | `#hud .stat` | 829.2, 16.2 | 305.58 × 164.59 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 24 0 24 |
| #hud .stat .k (剩余 label) | `#hud .stat .k` | 935.91, 16.2 | 92.17 × 47 | 36/700 | 10.08px | rgba(198, 232, 248, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #timeLeft (clock digits) | `#timeLeft` | 853.2, 63.2 | 257.58 × 117.59 | 120/900 | 0.32px | rgb(215, 247, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock | `#rankBlock` | 1530, 23.5 | 300 × 150 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(270deg, rgba(182, 255, 87, 0.09), rgba(0, … | R 4px rgb(182, 255, 87) | 0px | none | 0 8 0 38 |
| #rankBlock .rank-k | `#rankBlock .rank-k` | 1639.44, 11.5 | 178.56 × 47 | 36/700 | 8.64px | rgba(198, 232, 248, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rank (rank numeral) | `#rank` | 1595.42, 71.22 | 222.58 × 96 | 96/900 | 0.32px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock .rank-arrow | `#rankBlock .rank-arrow` | 1534, 109.08 | 35.95 × 47 | 36/900 | 0.32px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock .rank-total | `#rankBlock .rank-total` | 1676.92, 154.5 | 141.08 × 31 | 24/400 | 2.4px | rgba(190, 225, 240, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**C. Mirror box (the camera pane inside the HUD band)**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #cam (mirror box) | `#cam` | 90, 8.5 | 320 × 180 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(4, 11, 20) | T 2px rgba(cyan, 0.55)<br>R 2px rgba(cyan, 0.55)<br>B 2px rgba(cyan, 0.55)<br>L 2px rgba(cyan, 0.55) | 2px | rgba(cyan, 0.06) 0px 0px 0px 6px, rgba(… | 0 0 0 0 |
| #cam .cam-frame | `#cam .cam-frame` | 92, 10.5 | 316 × 176 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #cam .cam-frame i | `#cam .cam-frame i` | 97, 15.5 | 22 × 22 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | T 3px cyan<br>L 3px cyan | 0px | none | 0 0 0 0 |
| #cam .cam-rec | `#cam .cam-rec` | 385, 19.5 | 14 × 14 | 9/900 | 1.44px | rgb(255, 156, 174) | rgba(0, 0, 0, 0) |  | 50% | none | 0 0 0 0 |
| #cam .cam-tag | `#cam .cam-tag` | — | **hidden** | · | · | rgb(182, 255, 87) | rgba(4, 10, 20, 0.82) | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 1px rgba(182, 255, 87, 0.…<br>L 1px rgba(182, 255, 87, 0.… | 3px | none | 4 8 4 8 |
| #cam .cam-speed | `#cam .cam-speed` | 92, 144.5 | 316 × 42 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(2, 10, 20, 0.95), rgba(2, 10, 2… |  | 0px | none | 0 12 0 12 |
| #cam .cam-speed-val | `#cam .cam-speed-val` | 104, 148 | 92 × 35 | 26/800 | 0.52px | rgb(220, 248, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #cam .cam-speed-track | `#cam .cam-speed-track` | 206, 160.5 | 190 × 10 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 22, 36, 0.86) | T 1px rgba(cyan, 0.4)<br>R 1px rgba(cyan, 0.4)<br>B 1px rgba(cyan, 0.4)<br>L 1px rgba(cyan, 0.4) | 0px | none | 0 0 0 0 |
| #cam .cam-speed-track i | `#cam .cam-speed-track i` | 207, 161.5 | 56.39 × 8 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgb(47, 159, 214), cyan 55%, rgb(18… |  | 0px | rgba(cyan, 0.9) 0px 0px 14px 0px | 0 0 0 0 |
| #cam .cam-label | `#cam .cam-label` | 92, 151.5 | 316 × 35 | 10.5/700 | 1.05px | rgb(205, 238, 255) | lg(to top, rgba(8, 3, 16, 0.92), rgba(8, 3, 1… |  | 0px | none | 14 10 7 10 |
| #cam .cam-ready | `#cam .cam-ready` | — | **hidden** | · | · | rgb(234, 246, 255) | lg(rgba(4, 10, 20, 0), rgba(4, 10, 20, 0.88)) |  | 0px | none | 12 0 13 0 |

**D. Status, buttons, key strip, buffs, leaderboard**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #statusbar | `#statusbar` | 1784.39, 44 | 91.61 × 36 | 12/800 | 1.2px | rgb(217, 238, 251) | rgba(6, 14, 26, 0.94) | T 1px rgba(cyan, 0.34)<br>R 3px cyan<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.55) 0px 10px 26px 0px | 9 16 9 16 |
| #statusbar .dot | `#statusbar .dot` | 1801.39, 58 | 8 × 8 | 12/800 | 1.2px | rgb(217, 238, 251) | rgb(91, 234, 160) |  | 50% | rgba(91, 234, 160, 0.9) 0px 0px 12px 0px | 0 0 0 0 |
| #status (status text) | `#status` | 1817.39, 54 | 39.61 × 16 | 12/800 | 1.2px | rgb(217, 238, 251) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #quickPlayBtn | `#quickPlayBtn` | 1743, 94 | 133 × 42 | 12.5/800 | 1px | rgb(233, 255, 208) | lg(100deg, rgba(9, 26, 32, 0.97), rgba(14, 38… | T 1px rgba(182, 255, 87, 0.…<br>R 3px rgb(182, 255, 87)<br>B 1px rgba(182, 255, 87, 0.…<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(0, 0, 0, 0.55) 0px 8px 24px 0px, r… | 8 15 8 15 |
| #muteBtn | `#muteBtn` | 1630, 94 | 36 × 36 | 13.3333/400 | normal | cyan | rgba(6, 14, 26, 0.9) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | none | 0 0 0 0 |
| #padBar | `#padBar` | 274, 998 | 451.17 × 38 | 11/700 | 0.44px | rgba(214, 236, 250, 0.8) | rgba(6, 14, 26, 0.86) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px cyan | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 8 14 8 14 |
| #padBar .keycap | `#padBar .keycap` | 291, 1007 | 57.14 × 20 | 10/900 | 0.6px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) | T 1px rgba(255, 255, 255, 0…<br>R 1px rgba(255, 255, 255, 0…<br>B 1px rgba(255, 255, 255, 0…<br>L 1px rgba(255, 255, 255, 0… | 4px | rgba(0, 0, 0, 0.6) 0px 2px 0px 0px, rgb… | 0 6 0 6 |
| .keycap (generic keycap) | `.keycap` | 205.83, 234.5 | 21.91 × 18 | 9/900 | 0.54px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) | T 1px rgba(255, 255, 255, 0…<br>R 1px rgba(255, 255, 255, 0…<br>B 1px rgba(255, 255, 255, 0…<br>L 1px rgba(255, 255, 255, 0… | 4px | rgba(0, 0, 0, 0.6) 0px 2px 0px 0px, rgb… | 0 6 0 6 |
| #hint | `#hint` | 890.01, 989 | 139.98 × 39 | 13/800 | 0.78px | rgb(220, 255, 224) | rgba(6, 14, 26, 0.93) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px rgb(182, 255, 87) | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 10 22 10 22 |
| #buffs | `#buffs` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost (buff chip) | `#buffBoost` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(6, 14, 26, 0.95) | T 1px rgba(255, 213, 74, 0.…<br>R 3px rgba(255, 213, 74, 0.…<br>B 1px rgba(255, 213, 74, 0.…<br>L 1px rgba(255, 213, 74, 0.… | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 7 11 11 11 |
| #buffBoost .buff-name | `#buffBoost .buff-name` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-time | `#buffBoost .buff-time` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-bar | `#buffBoost .buff-bar` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(255, 255, 255, 0.12) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-bar i | `#buffBoost .buff-bar i` | — | **hidden** | · | · | rgb(255, 213, 74) | rgb(255, 213, 74) |  | 2px | none | 0 0 0 0 |
| #leaderboard | `#leaderboard` | 1536, 248 | 340 × 171 | 24/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 14, 26, 0.95) | T 3px cyan<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.6) 0px 16px 40px 0px | 11 12 10 12 |
| #leaderboard .lb-head | `#leaderboard .lb-head` | 1549, 262 | 314 × 16 | 10/700 | 1.8px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #leaderboard .lb-head span | `#leaderboard .lb-head span` | 1549, 262 | 98.36 × 16 | 10/700 | 1.8px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbTime | `#lbTime` | 1837.36, 262 | 25.64 × 16 | 12/700 | normal | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows | `#lbRows` | 1549, 285 | 314 × 123 | 24/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-row | `#lbRows .lb-row` | 1549, 285 | 314 × 39 | 24/400 | 0.32px | rgb(220, 234, 245) | rgba(0, 0, 0, 0) |  | 2px | none | 4 6 4 6 |
| #lbRows .lb-row.me | `#lbRows .lb-row.me` | 1549, 369 | 314 × 39 | 24/800 | 0.32px | rgb(234, 255, 210) | rgba(182, 255, 87, 0.16) | L 3px rgb(182, 255, 87) | 2px | none | 4 6 4 6 |
| #lbRows .lb-rank | `#lbRows .lb-row .lb-rank` | 1555, 289 | 16 × 31 | 24/900 | 0.32px | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-name | `#lbRows .lb-row .lb-name` | 1593, 289 | 194.97 × 31 | 24/400 | 0.32px | rgb(220, 234, 245) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-len | `#lbRows .lb-row .lb-len` | 1794.97, 289 | 62.03 × 31 | 24/800 | 0.32px | rgb(220, 234, 245) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**E. Pause / OPTIONS layer**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #pauseScrim | `#pauseScrim` | 0, 200 | 1920 × 880 | 16/400 | 0.32px | rgb(234, 246, 255) | radial-gradient(at 50% 0%, rgba(6, 16, 30, 0.… |  | 0px | none | 22 0 0 0 |
| #pauseScrim .pause-scrim-inner | `#pauseScrim .pause-scrim-inner` | 793.67, 222 | 332.64 × 137 | 16/400 | 0.32px | rgb(223, 244, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim .pause-kicker | `#pauseScrim .pause-kicker` | 795.67, 222 | 328.64 × 31 | 24/800 | 6.72px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim strong | `#pauseScrim .pause-scrim-inner strong` | 793.67, 259 | 332.64 × 59 | 44/900 | 3.52px | rgb(223, 244, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim .pause-tip | `#pauseScrim .pause-tip` | 837.8, 324 | 244.39 × 35 | 26/400 | 0.32px | rgba(200, 230, 245, 0.7… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats | `#pauseStats` | 679.36, 318 | 561.28 × 193.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 16, 29, 0.97) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 4px cyan | 4px | rgba(0, 0, 0, 0.7) 0px 18px 48px 0px | 16 20 16 20 |
| #pauseStats .stat | `#pauseStats .stat` | 767.5, 335 | 120 × 110.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(12, 28, 46, 0.7) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.35) 0px 8px 28px 0px, r… | 10 14 10 14 |
| #pauseStats .stat .k | `#pauseStats .stat .k` | 782.5, 346 | 90 × 37 | 28/600 | 3.92px | rgba(190, 214, 238, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats .stat .v | `#pauseStats .stat .v` | 782.5, 384 | 90 × 50.39 | 48/900 | 0.32px | rgb(242, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats .legacy-stat (dead weight) | `#pauseStats .legacy-stat` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(12, 28, 46, 0.7) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.35) 0px 8px 28px 0px, r… | 10 14 10 14 |
| #pauseBuff | `#pauseBuff` | 703.36, 459.39 | 516.28 × 35 | 26/700 | 1.56px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning (settings drawer) | `#tuning` | 21.59, 214 | 420 × 852 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(155deg, rgba(8, 17, 31, 0.98), rgba(5, 11,… | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 3px cyan | 4px | rgba(0, 0, 0, 0.7) 0px 20px 52px 0px, r… | 0 0 0 0 |
| #tuning .tuning-head | `#tuning .tuning-head` | 24.59, 215 | 416 × 58 | 12/800 | 1.68px | rgb(234, 246, 255) | lg(90deg, rgba(cyan, 0.13), rgba(0, 0, 0, 0)) | B 1px rgba(cyan, 0.15) | 0px | none | 11 13 11 13 |
| #tuning .tuning-title | `#tuning .tuning-title` | 37.59, 226 | 159.23 × 35 | 26/800 | 1.68px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning .tuning-mark | `#tuning .tuning-mark` | 37.59, 236.5 | 7.69 × 14 | 10/800 | 1.68px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuningToggle | `#tuningToggle` | 385.59, 232.5 | 42 × 22 | 10/800 | 1px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) |  | 3px | none | 4 10 4 10 |
| #tuning .tuning-body | `#tuning .tuning-body` | 24.59, 273 | 416 × 1323.5 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 10 14 12 14 |
| #tuning .tuning-body .row | `#tuning .tuning-body .row` | 38.59, 283 | 388 × 35 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning .ai-sep | `#tuning .ai-sep` | 38.59, 428.5 | 388 × 36 | 20/700 | 4px | cyan | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.34)<br>L 3px rgb(182, 255, 87) | 0px | none | 9 0 0 10 |

**F. Start / title slab**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #overlay | `#overlay` | 0, 0 | 1920 × 1080 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(cyan, 0.043) 1px, rgba(0, 0, 0,… |  | 0px | none | 44 44 44 44 |
| #overlay .panel.title-screen (title slab) | `#overlay .panel.title-screen` | 570, 255.14 | 780 × 569.72 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(155deg, rgba(9, 20, 36, 0.98), rgba(5, 10,… | T 4px rgb(182, 255, 87)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 4px | rgba(0, 0, 0, 0.8) 0px 40px 100px 0px, … | 0 0 0 0 |
| #overlay .title-hero | `#overlay .title-hero` | 571, 259.14 | 778 × 206.47 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 20 32 14 32 |
| #overlay .brand-line | `#overlay .brand-line` | 603, 279.14 | 714 × 33 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | B 1px rgba(cyan, 0.15) | 0px | none | 0 0 10 0 |
| #overlay .brand-tag | `#overlay .brand-tag` | 848.86, 279.14 | 132.31 × 22 | 10/900 | 2.4px | rgb(6, 33, 12) | rgb(182, 255, 87) |  | 2px | rgba(182, 255, 87, 0.35) 0px 0px 20px 0… | 4 10 4 10 |
| #overlay .brand-ver | `#overlay .brand-ver` | 991.17, 283.14 | 79.95 × 14 | 10/800 | 2px | rgba(150, 205, 230, 0.6) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .title-hero .logo | `#overlay .title-hero .logo` | 603, 322.14 | 714 × 61.47 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .snake-dot | `#overlay .snake-dot` | 794.19, 343.88 | 18 × 18 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(182, 255, 87) |  | 3px | rgba(182, 255, 87, 0.14) 0px 0px 0px 4p… | 0 0 0 0 |
| #panelTitle | `#panelTitle` | 824.19, 322.14 | 301.61 × 61.47 | 58/900 | 2.32px | rgba(0, 0, 0, 0) | lg(100deg, rgb(234, 255, 208), rgb(182, 255, … |  | 0px | none | 0 0 0 0 |
| #overlay .title-sub | `#overlay .title-sub` | 603, 391.61 | 714 × 17 | 13/400 | 2.86px | rgba(196, 228, 244, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .mode-badges | `#overlay .mode-badges` | 603, 418.61 | 714 × 29 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .mode-badges span | `#overlay .mode-badges span` | 779.14, 418.61 | 87.94 × 29 | 11/700 | 0.88px | rgba(206, 234, 250, 0.8) | rgba(cyan, 0.07) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px cyan | 2px | none | 6 12 6 12 |
| #overlay .mode-badges b | `#overlay .mode-badges b` | 794.14, 425.61 | 27.02 × 15 | 11/900 | 0.88px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .player-select | `#overlay .player-select` | 571, 465.61 | 778 × 115 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 12 32 0 32 |
| #overlay .ps-label | `#overlay .ps-label` | 603, 477.61 | 714 × 15 | 11/800 | 2.86px | rgba(150, 205, 230, 0.7) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .ps-btn | `#overlay .ps-btn` | 603, 501.61 | 351 × 79 | 13.3333/400 | normal | rgb(236, 255, 214) | lg(rgba(110, 240, 130, 0.17), rgba(9, 24, 40,… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.14) 0px 0px 26px … | 13 10 14 10 |
| #overlay .ps-btn.active | `#overlay .ps-btn.active` | 603, 501.61 | 351 × 79 | 13.3333/400 | normal | rgb(236, 255, 214) | lg(rgba(110, 240, 130, 0.17), rgba(9, 24, 40,… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.14) 0px 0px 26px … | 13 10 14 10 |
| #overlay .ps-btn b | `#overlay .ps-btn b` | 757.2, 515.61 | 42.58 × 28 | 19/900 | 1.52px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .ps-btn span | `#overlay .ps-btn span` | 745.16, 547.61 | 66.67 × 16 | 11.5/400 | 0.69px | rgba(210, 240, 220, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .panel-actions | `#overlay .panel-actions` | 571, 580.61 | 778 × 203.25 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(5, 10, 20, 0.99) 60%, rgba(5, 1… |  | 0px | none | 12 32 16 32 |
| #overlay .menu-buttons | `#overlay .menu-buttons` | 603, 592.61 | 714 × 54 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #startBtn | `#startBtn` | 603, 592.61 | 391.11 × 54 | 14/900 | 1.4px | rgb(7, 32, 12) | lg(rgb(217, 255, 122), rgb(134, 240, 106) 60%… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.2) 0px 0px 30px 0… | 13 12 13 12 |
| #kbBtn | `#kbBtn` | 1004.11, 592.61 | 312.89 × 54 | 14/900 | 1.4px | rgb(216, 244, 255) | lg(rgba(20, 48, 70, 0.9), rgba(9, 24, 40, 0.9… | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 3px rgba(cyan, 0.45)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(4, 14, 26, 0.7) 0px 8px 0px 0px | 13 12 13 12 |
| #panelHint | `#panelHint` | 603, 657.61 | 714 × 18 | 12/400 | 0.32px | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .fineprint | `#overlay .fineprint` | 603, 684.61 | 714 × 47.25 | 10.5/400 | 0.32px | rgba(160, 196, 218, 0.5) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .pad-hints | `#overlay .pad-hints` | 603, 738.86 | 714 × 29 | 10/700 | 0.8px | rgba(190, 220, 238, 0.7) | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.15) | 0px | none | 8 0 0 0 |
| #overlay .rules-details | `#overlay .rules-details` | 603, 789.86 | 714 × 34 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.15) | 0px | none | 0 0 0 0 |

**G. Settlement**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #resultOverlay | `#resultOverlay` | 0, 0 | 1920 × 1080 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .result-top | `#resultOverlay .result-top` | 0, 0 | 1920 × 66 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(rgba(4, 9, 18, 0.86) 0px, rgba(4, 9, 18, 0… |  | 0px | none | 6 24 10 24 |
| #resultOverlay .result-headline | `#resultOverlay .result-headline` | 24, 7.3 | 188.89 × 47.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .result-headline .logo | `#resultOverlay .result-headline .logo` | 24, 7.3 | 174.89 × 41.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultTitle | `#resultTitle` | 52, 7.3 | 146.89 × 41.39 | 36/900 | 0.72px | rgb(244, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultStats | `#resultStats` | — | **hidden** | · | · | rgba(196, 224, 242, 0.7… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .stage-actions | `#resultOverlay .stage-actions` | 1752.09, 6 | 143.91 × 50 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 4 0 0 0 |
| #skipStageBtn | `#skipStageBtn` | 1752.09, 10 | 143.91 × 46 | 13/800 | 1.04px | rgb(223, 246, 255) | rgba(8, 20, 36, 0.92) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 3px rgba(cyan, 0.4)<br>L 1px rgba(cyan, 0.34) | 3px | none | 9 15 9 15 |
| #resultOverlay .result-bottom | `#resultOverlay .result-bottom` | 0, 996 | 1920 × 84 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(rgba(4, 9, 18, 0) 0px, rgba(4, 9, 18, 0.95… |  | 0px | none | 12 0 8 0 |
| #resultRows | `#resultRows` | 301.73, 1008 | 1316.53 × 0 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultRows .result-row | `#resultRows .result-row` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .result-row.me | `#resultRows .result-row.me` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-rank | `#resultRows .result-row .r-rank` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-name | `#resultRows .result-row .r-name` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-len | `#resultRows .result-row .r-len` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-extra | `#resultRows .result-row .r-extra` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-avatar | `#resultRows .r-avatar` | — | — | — | — | — | — | — | — | — | — |
| #resultOverlay .result-actions | `#resultOverlay .result-actions` | 0, 1008 | 1920 × 64 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 10 22 0 22 |
| #againBtn | `#againBtn` | 805.64, 1018 | 206.81 × 54 | 22/900 | 2.2px | rgb(10, 31, 16) | lg(rgb(212, 255, 122), rgb(134, 240, 106) 60%… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 4px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.2) 0px 0px 30px 0… | 10 30 10 30 |
| #resultOverlay .result-actions .hint | `#resultOverlay .result-actions .hint` | 1028.45, 1035 | 85.89 × 20 | 12/700 | 0.72px | rgba(190, 220, 238, 0.7) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**Pseudo-elements** (this is where the OSD lives)

| pseudo | content | box | opacity | background |
|---|---|---|---|---|
| `body::before (scanlines + vignette)` | `""` | {'w': '1920px', 'h': '1080px', 'top': '0px', 'right': '0px', 'bottom'… | 1 | repeating-lg(0deg, rgba(160, 220, 255, 0.024) 0px, rgba(160, 220, 255, 0.024) 1… |
| `body::after (OSD 4-corner brackets)` | `""` | {'w': '1832px', 'h': '992px', 'top': '44px', 'right': '44px', 'bottom… | 0.55 | lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan),… |
| `#uiBar::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#uiBar::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud .stat::after (data-en watermark)` | `"TIME"` | {'w': 'auto', 'h': 'auto', 'top': '4px', 'right': '8px', 'bottom': 'a… | 1 | none |
| `.stat::after (data-en watermark)` | `"TIME"` | {'w': 'auto', 'h': 'auto', 'top': '4px', 'right': '8px', 'bottom': 'a… | 1 | none |
| `#cam::before` | `""` | {'w': '316px', 'h': '176px', 'top': '0px', 'right': '0px', 'bottom': … | 1 | none |
| `#pauseStats .stat::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#overlay .panel::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#resultOverlay .result-bottom::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#leaderboard::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#quickPlayBtn::before` | `"A"` | {'w': '22px', 'h': '22px', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | lg(rgb(226, 250, 255), rgb(138, 216, 238)) |

### 4.5 `settle` @ 1920×1080

Settlement (`game.state === 'finished'`)

`body.class = "result-mode"` · `data-split = 1` · `game.state = finished` · `--ui-scale = 1`

**A. Panel chrome / OSD / merged HUD bar**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #uiBar (merged HUD bar) | `#uiBar` | 0, 0 | 1920 × 200 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(cyan, 0.043) 1px, rgba(0, 0, 0,… | B 3px cyan | 0px | rgba(0, 0, 0, 0.78) 0px 20px 52px 0px, … | 0 90 0 90 |
| #uiBar .ui-deco | `#uiBar .ui-deco` | 0, 0 | 1920 × 197 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-energy | `#uiBar .ui-energy` | 0, 0 | 1920 × 6 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(cyan, 0.16) |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-energy i | `#uiBar .ui-energy i` | 1258.77, 0 | 729.59 × 6 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(0, 0, 0, 0), rgb(184, 247, 255… |  | 0px | rgba(cyan, 0.95) 0px 0px 26px 0px | 0 0 0 0 |
| #uiBar .ui-scan | `#uiBar .ui-scan` | 0, 0 | 1920 × 197 | 16/400 | 0.32px | rgb(234, 246, 255) | repeating-lg(0deg, rgba(190, 235, 255, 0.024)… |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-ruler | `#uiBar .ui-ruler` | 90, 185 | 1740 × 5 | 16/400 | 0.32px | rgb(234, 246, 255) | repeating-lg(90deg, rgba(cyan, 0.4) 0px, rgba… |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-seam | `#uiBar .ui-seam` | 0, 197 | 1920 × 3 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(0, 0, 0, 0), cyan 10%, rgb(230… |  | 0px | rgba(cyan, 0.75) 0px 0px 22px 0px | 0 0 0 0 |
| #uiBar .ui-diamond | `#uiBar .ui-diamond` | 950.81, 178.31 | 18.38 × 18.38 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(230, 251, 255) |  | 0px | cyan 0px 0px 18px 0px | 0 0 0 0 |
| #uiBar .ui-notch.left | `#uiBar .ui-notch.left` | 0, 183 | 30 × 14 | 16/400 | 0.32px | rgb(234, 246, 255) | cyan |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-notch.right | `#uiBar .ui-notch.right` | 1890, 183 | 30 × 14 | 16/400 | 0.32px | rgb(234, 246, 255) | cyan |  | 0px | none | 0 0 0 0 |

**B. Clock, stat cells, rank block**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #hud | `#hud` | 448, 23.5 | 1064 × 150 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(cyan, 0.1), rgba(cyan, 0.01) 6… | L 4px rgb(182, 255, 87) | 0px | none | 0 0 0 0 |
| #hud .stat | `#hud .stat` | 829.2, 16.2 | 305.58 × 164.59 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 24 0 24 |
| #hud .stat .k (剩余 label) | `#hud .stat .k` | 935.91, 16.2 | 92.17 × 47 | 36/700 | 10.08px | rgba(198, 232, 248, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #timeLeft (clock digits) | `#timeLeft` | 853.2, 63.2 | 257.58 × 117.59 | 120/900 | 0.32px | rgb(215, 247, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock | `#rankBlock` | 1530, 23.5 | 300 × 150 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(270deg, rgba(182, 255, 87, 0.09), rgba(0, … | R 4px rgb(182, 255, 87) | 0px | none | 0 8 0 38 |
| #rankBlock .rank-k | `#rankBlock .rank-k` | 1639.44, 11.5 | 178.56 × 47 | 36/700 | 8.64px | rgba(198, 232, 248, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rank (rank numeral) | `#rank` | 1595.42, 58.5 | 222.58 × 96 | 96/900 | 0.32px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock .rank-arrow | `#rankBlock .rank-arrow` | 1534, 75 | 35.95 × 47 | 36/900 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock .rank-total | `#rankBlock .rank-total` | 1676.92, 154.5 | 141.08 × 31 | 24/400 | 2.4px | rgba(190, 225, 240, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**C. Mirror box (the camera pane inside the HUD band)**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #cam (mirror box) | `#cam` | 90, 8.5 | 320 × 180 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(4, 11, 20) | T 2px rgba(cyan, 0.55)<br>R 2px rgba(cyan, 0.55)<br>B 2px rgba(cyan, 0.55)<br>L 2px rgba(cyan, 0.55) | 2px | rgba(cyan, 0.06) 0px 0px 0px 6px, rgba(… | 0 0 0 0 |
| #cam .cam-frame | `#cam .cam-frame` | 92, 10.5 | 316 × 176 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #cam .cam-frame i | `#cam .cam-frame i` | 97, 15.5 | 22 × 22 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | T 3px cyan<br>L 3px cyan | 0px | none | 0 0 0 0 |
| #cam .cam-rec | `#cam .cam-rec` | 385, 19.5 | 14 × 14 | 9/900 | 1.44px | rgb(255, 156, 174) | rgba(0, 0, 0, 0) |  | 50% | none | 0 0 0 0 |
| #cam .cam-tag | `#cam .cam-tag` | — | **hidden** | · | · | rgb(182, 255, 87) | rgba(4, 10, 20, 0.82) | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 1px rgba(182, 255, 87, 0.…<br>L 1px rgba(182, 255, 87, 0.… | 3px | none | 4 8 4 8 |
| #cam .cam-speed | `#cam .cam-speed` | 92, 144.5 | 316 × 42 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(2, 10, 20, 0.95), rgba(2, 10, 2… |  | 0px | none | 0 12 0 12 |
| #cam .cam-speed-val | `#cam .cam-speed-val` | 104, 148 | 92 × 35 | 26/800 | 0.52px | rgb(220, 248, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #cam .cam-speed-track | `#cam .cam-speed-track` | 206, 160.5 | 190 × 10 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 22, 36, 0.86) | T 1px rgba(cyan, 0.4)<br>R 1px rgba(cyan, 0.4)<br>B 1px rgba(cyan, 0.4)<br>L 1px rgba(cyan, 0.4) | 0px | none | 0 0 0 0 |
| #cam .cam-speed-track i | `#cam .cam-speed-track i` | 207, 161.5 | 56.39 × 8 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgb(47, 159, 214), cyan 55%, rgb(18… |  | 0px | rgba(cyan, 0.9) 0px 0px 14px 0px | 0 0 0 0 |
| #cam .cam-label | `#cam .cam-label` | 92, 151.5 | 316 × 35 | 10.5/700 | 1.05px | rgb(205, 238, 255) | lg(to top, rgba(8, 3, 16, 0.92), rgba(8, 3, 1… |  | 0px | none | 14 10 7 10 |
| #cam .cam-ready | `#cam .cam-ready` | — | **hidden** | · | · | rgb(234, 246, 255) | lg(rgba(4, 10, 20, 0), rgba(4, 10, 20, 0.88)) |  | 0px | none | 12 0 13 0 |

**D. Status, buttons, key strip, buffs, leaderboard**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #statusbar | `#statusbar` | 1771.19, 44 | 104.81 × 36 | 12/800 | 1.2px | rgb(217, 238, 251) | rgba(6, 14, 26, 0.94) | T 1px rgba(cyan, 0.34)<br>R 3px cyan<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.55) 0px 10px 26px 0px | 9 16 9 16 |
| #statusbar .dot | `#statusbar .dot` | 1788.19, 58 | 8 × 8 | 12/800 | 1.2px | rgb(217, 238, 251) | rgb(91, 234, 160) |  | 50% | rgba(91, 234, 160, 0.9) 0px 0px 12px 0px | 0 0 0 0 |
| #status (status text) | `#status` | 1804.19, 54 | 52.81 × 16 | 12/800 | 1.2px | rgb(217, 238, 251) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #quickPlayBtn | `#quickPlayBtn` | 1743, 94 | 133 × 42 | 12.5/800 | 1px | rgb(233, 255, 208) | lg(100deg, rgba(9, 26, 32, 0.97), rgba(14, 38… | T 1px rgba(182, 255, 87, 0.…<br>R 3px rgb(182, 255, 87)<br>B 1px rgba(182, 255, 87, 0.…<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(0, 0, 0, 0.55) 0px 8px 24px 0px, r… | 8 15 8 15 |
| #muteBtn | `#muteBtn` | 1630, 94 | 36 × 36 | 13.3333/400 | normal | cyan | rgba(6, 14, 26, 0.9) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | none | 0 0 0 0 |
| #padBar | `#padBar` | 274, 998 | 451.17 × 38 | 11/700 | 0.44px | rgba(214, 236, 250, 0.8) | rgba(6, 14, 26, 0.86) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px cyan | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 8 14 8 14 |
| #padBar .keycap | `#padBar .keycap` | 291, 1007 | 57.14 × 20 | 10/900 | 0.6px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) | T 1px rgba(255, 255, 255, 0…<br>R 1px rgba(255, 255, 255, 0…<br>B 1px rgba(255, 255, 255, 0…<br>L 1px rgba(255, 255, 255, 0… | 4px | rgba(0, 0, 0, 0.6) 0px 2px 0px 0px, rgb… | 0 6 0 6 |
| .keycap (generic keycap) | `.keycap` | 157.28, 152 | 21.91 × 18 | 9/900 | 0.54px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) | T 1px rgba(255, 255, 255, 0…<br>R 1px rgba(255, 255, 255, 0…<br>B 1px rgba(255, 255, 255, 0…<br>L 1px rgba(255, 255, 255, 0… | 4px | rgba(0, 0, 0, 0.6) 0px 2px 0px 0px, rgb… | 0 6 0 6 |
| #hint | `#hint` | 690.38, 989 | 539.23 × 39 | 13/800 | 0.78px | rgb(220, 255, 224) | rgba(6, 14, 26, 0.93) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px rgb(182, 255, 87) | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 10 22 10 22 |
| #buffs | `#buffs` | 1700, 144 | 176 × 36 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost (buff chip) | `#buffBoost` | 1700, 144 | 176 × 36 | 12/800 | 0.96px | rgb(255, 213, 74) | rgba(6, 14, 26, 0.95) | T 1px rgba(255, 213, 74, 0.…<br>R 3px rgba(255, 213, 74, 0.…<br>B 1px rgba(255, 213, 74, 0.…<br>L 1px rgba(255, 213, 74, 0.… | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 7 11 11 11 |
| #buffBoost .buff-name | `#buffBoost .buff-name` | 1712, 152 | 25.92 × 16 | 12/800 | 0.96px | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-time | `#buffBoost .buff-time` | 1834, 152 | 28 × 16 | 12/800 | 0.96px | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-bar | `#buffBoost .buff-bar` | 1711, 170 | 152 × 4 | 12/800 | 0.96px | rgb(255, 213, 74) | rgba(255, 255, 255, 0.12) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-bar i | `#buffBoost .buff-bar i` | 1711, 170 | 140.89 × 4 | 12/800 | 0.96px | rgb(255, 213, 74) | rgb(255, 213, 74) |  | 2px | none | 0 0 0 0 |
| #leaderboard | `#leaderboard` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(6, 14, 26, 0.95) | T 3px cyan<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.6) 0px 16px 40px 0px | 11 12 10 12 |
| #leaderboard .lb-head | `#leaderboard .lb-head` | — | **hidden** | · | · | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #leaderboard .lb-head span | `#leaderboard .lb-head span` | — | **hidden** | · | · | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbTime | `#lbTime` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows | `#lbRows` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-row | `#lbRows .lb-row` | — | **hidden** | · | · | rgb(220, 234, 245) | rgba(0, 0, 0, 0) |  | 2px | none | 4 6 4 6 |
| #lbRows .lb-row.me | `#lbRows .lb-row.me` | — | **hidden** | · | · | rgb(234, 255, 210) | rgba(182, 255, 87, 0.16) | L 3px rgb(182, 255, 87) | 2px | none | 4 6 4 6 |
| #lbRows .lb-rank | `#lbRows .lb-row .lb-rank` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-name | `#lbRows .lb-row .lb-name` | — | **hidden** | · | · | rgb(220, 234, 245) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-len | `#lbRows .lb-row .lb-len` | — | **hidden** | · | · | rgb(220, 234, 245) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**E. Pause / OPTIONS layer**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #pauseScrim | `#pauseScrim` | 0, 200 | 1920 × 880 | 16/400 | 0.32px | rgb(234, 246, 255) | radial-gradient(at 50% 0%, rgba(6, 16, 30, 0.… |  | 0px | none | 22 0 0 0 |
| #pauseScrim .pause-scrim-inner | `#pauseScrim .pause-scrim-inner` | 793.67, 222 | 332.64 × 137 | 16/400 | 0.32px | rgb(223, 244, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim .pause-kicker | `#pauseScrim .pause-kicker` | 795.67, 222 | 328.64 × 31 | 24/800 | 6.72px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim strong | `#pauseScrim .pause-scrim-inner strong` | 793.67, 259 | 332.64 × 59 | 44/900 | 3.52px | rgb(223, 244, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim .pause-tip | `#pauseScrim .pause-tip` | 837.8, 324 | 244.39 × 35 | 26/400 | 0.32px | rgba(200, 230, 245, 0.7… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats | `#pauseStats` | 631.64, 318 | 656.72 × 193.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 16, 29, 0.97) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 4px cyan | 4px | rgba(0, 0, 0, 0.7) 0px 18px 48px 0px | 16 20 16 20 |
| #pauseStats .stat | `#pauseStats .stat` | 767.5, 335 | 120 × 110.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(12, 28, 46, 0.7) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.35) 0px 8px 28px 0px, r… | 10 14 10 14 |
| #pauseStats .stat .k | `#pauseStats .stat .k` | 782.5, 346 | 90 × 37 | 28/600 | 3.92px | rgba(190, 214, 238, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats .stat .v | `#pauseStats .stat .v` | 782.5, 384 | 90 × 50.39 | 48/900 | 0.32px | rgb(242, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats .legacy-stat (dead weight) | `#pauseStats .legacy-stat` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(12, 28, 46, 0.7) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.35) 0px 8px 28px 0px, r… | 10 14 10 14 |
| #pauseBuff | `#pauseBuff` | 655.64, 459.39 | 611.72 × 35 | 26/700 | 1.56px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning (settings drawer) | `#tuning` | 44, 138 | 200.19 × 46 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 14, 26, 0.95) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 3px rgb(182, 255, 87) | 4px | rgba(0, 0, 0, 0.55) 0px 10px 26px 0px | 0 0 0 0 |
| #tuning .tuning-head | `#tuning .tuning-head` | 47, 139 | 196.19 × 44 | 12/800 | 1.68px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 11 13 11 13 |
| #tuning .tuning-title | `#tuning .tuning-title` | 60, 153 | 88.28 × 16 | 12/800 | 1.68px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning .tuning-mark | `#tuning .tuning-mark` | 60, 154 | 7.69 × 14 | 10/800 | 1.68px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuningToggle | `#tuningToggle` | 188.19, 150 | 42 × 22 | 10/800 | 1px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) |  | 3px | none | 4 10 4 10 |
| #tuning .tuning-body | `#tuning .tuning-body` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 14 14 16 14 |
| #tuning .tuning-body .row | `#tuning .tuning-body .row` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning .ai-sep | `#tuning .ai-sep` | — | **hidden** | · | · | cyan | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.34)<br>L 3px rgb(182, 255, 87) | 0px | none | 9 0 0 10 |

**F. Start / title slab**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #overlay | `#overlay` | 0, 0 | 1920 × 1080 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(cyan, 0.043) 1px, rgba(0, 0, 0,… |  | 0px | none | 44 44 44 44 |
| #overlay .panel.title-screen (title slab) | `#overlay .panel.title-screen` | 570, 255.14 | 780 × 569.72 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(155deg, rgba(9, 20, 36, 0.98), rgba(5, 10,… | T 4px rgb(182, 255, 87)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 4px | rgba(0, 0, 0, 0.8) 0px 40px 100px 0px, … | 0 0 0 0 |
| #overlay .title-hero | `#overlay .title-hero` | 571, 259.14 | 778 × 206.47 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 20 32 14 32 |
| #overlay .brand-line | `#overlay .brand-line` | 603, 279.14 | 714 × 33 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | B 1px rgba(cyan, 0.15) | 0px | none | 0 0 10 0 |
| #overlay .brand-tag | `#overlay .brand-tag` | 848.86, 279.14 | 132.31 × 22 | 10/900 | 2.4px | rgb(6, 33, 12) | rgb(182, 255, 87) |  | 2px | rgba(182, 255, 87, 0.35) 0px 0px 20px 0… | 4 10 4 10 |
| #overlay .brand-ver | `#overlay .brand-ver` | 991.17, 283.14 | 79.95 × 14 | 10/800 | 2px | rgba(150, 205, 230, 0.6) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .title-hero .logo | `#overlay .title-hero .logo` | 603, 322.14 | 714 × 61.47 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .snake-dot | `#overlay .snake-dot` | 794.19, 343.88 | 18 × 18 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(182, 255, 87) |  | 3px | rgba(182, 255, 87, 0.14) 0px 0px 0px 4p… | 0 0 0 0 |
| #panelTitle | `#panelTitle` | 824.19, 322.14 | 301.61 × 61.47 | 58/900 | 2.32px | rgba(0, 0, 0, 0) | lg(100deg, rgb(234, 255, 208), rgb(182, 255, … |  | 0px | none | 0 0 0 0 |
| #overlay .title-sub | `#overlay .title-sub` | 603, 391.61 | 714 × 17 | 13/400 | 2.86px | rgba(196, 228, 244, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .mode-badges | `#overlay .mode-badges` | 603, 418.61 | 714 × 29 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .mode-badges span | `#overlay .mode-badges span` | 779.14, 418.61 | 87.94 × 29 | 11/700 | 0.88px | rgba(206, 234, 250, 0.8) | rgba(cyan, 0.07) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px cyan | 2px | none | 6 12 6 12 |
| #overlay .mode-badges b | `#overlay .mode-badges b` | 794.14, 425.61 | 27.02 × 15 | 11/900 | 0.88px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .player-select | `#overlay .player-select` | 571, 465.61 | 778 × 115 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 12 32 0 32 |
| #overlay .ps-label | `#overlay .ps-label` | 603, 477.61 | 714 × 15 | 11/800 | 2.86px | rgba(150, 205, 230, 0.7) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .ps-btn | `#overlay .ps-btn` | 603, 501.61 | 351 × 79 | 13.3333/400 | normal | rgb(236, 255, 214) | lg(rgba(110, 240, 130, 0.17), rgba(9, 24, 40,… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.14) 0px 0px 26px … | 13 10 14 10 |
| #overlay .ps-btn.active | `#overlay .ps-btn.active` | 603, 501.61 | 351 × 79 | 13.3333/400 | normal | rgb(236, 255, 214) | lg(rgba(110, 240, 130, 0.17), rgba(9, 24, 40,… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.14) 0px 0px 26px … | 13 10 14 10 |
| #overlay .ps-btn b | `#overlay .ps-btn b` | 757.2, 515.61 | 42.58 × 28 | 19/900 | 1.52px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .ps-btn span | `#overlay .ps-btn span` | 745.16, 547.61 | 66.67 × 16 | 11.5/400 | 0.69px | rgba(210, 240, 220, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .panel-actions | `#overlay .panel-actions` | 571, 580.61 | 778 × 203.25 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(5, 10, 20, 0.99) 60%, rgba(5, 1… |  | 0px | none | 12 32 16 32 |
| #overlay .menu-buttons | `#overlay .menu-buttons` | 603, 592.61 | 714 × 54 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #startBtn | `#startBtn` | 603, 592.61 | 391.11 × 54 | 14/900 | 1.4px | rgb(7, 32, 12) | lg(rgb(217, 255, 122), rgb(134, 240, 106) 60%… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.2) 0px 0px 30px 0… | 13 12 13 12 |
| #kbBtn | `#kbBtn` | 1004.11, 592.61 | 312.89 × 54 | 14/900 | 1.4px | rgb(216, 244, 255) | lg(rgba(20, 48, 70, 0.9), rgba(9, 24, 40, 0.9… | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 3px rgba(cyan, 0.45)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(4, 14, 26, 0.7) 0px 8px 0px 0px | 13 12 13 12 |
| #panelHint | `#panelHint` | 603, 657.61 | 714 × 18 | 12/400 | 0.32px | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .fineprint | `#overlay .fineprint` | 603, 684.61 | 714 × 47.25 | 10.5/400 | 0.32px | rgba(160, 196, 218, 0.5) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .pad-hints | `#overlay .pad-hints` | 603, 738.86 | 714 × 29 | 10/700 | 0.8px | rgba(190, 220, 238, 0.7) | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.15) | 0px | none | 8 0 0 0 |
| #overlay .rules-details | `#overlay .rules-details` | 603, 789.86 | 714 × 34 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.15) | 0px | none | 0 0 0 0 |

**G. Settlement**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #resultOverlay | `#resultOverlay` | 0, 0 | 1920 × 1080 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .result-top | `#resultOverlay .result-top` | 0, 0 | 1920 × 66 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(rgba(4, 9, 18, 0.86) 0px, rgba(4, 9, 18, 0… |  | 0px | none | 6 24 10 24 |
| #resultOverlay .result-headline | `#resultOverlay .result-headline` | 24, 7.3 | 237.89 × 47.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .result-headline .logo | `#resultOverlay .result-headline .logo` | 24, 7.3 | 147.25 × 41.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultTitle | `#resultTitle` | 52, 7.3 | 119.25 × 41.39 | 36/900 | 0.72px | rgb(244, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultStats | `#resultStats` | 185.25, 18.98 | 76.64 × 24 | 15/700 | 0.6px | rgba(196, 224, 242, 0.7… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .stage-actions | `#resultOverlay .stage-actions` | 1752.09, 6 | 143.91 × 50 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 4 0 0 0 |
| #skipStageBtn | `#skipStageBtn` | 1752.09, 10 | 143.91 × 46 | 13/800 | 1.04px | rgb(223, 246, 255) | rgba(8, 20, 36, 0.92) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 3px rgba(cyan, 0.4)<br>L 1px rgba(cyan, 0.34) | 3px | none | 9 15 9 15 |
| #resultOverlay .result-bottom | `#resultOverlay .result-bottom` | 0, 904 | 1920 × 176 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(rgba(4, 9, 18, 0) 0px, rgba(4, 9, 18, 0.95… |  | 0px | none | 12 0 8 0 |
| #resultRows | `#resultRows` | 301.73, 916 | 1316.53 × 92 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultRows .result-row | `#resultRows .result-row` | 301.73, 916 | 164.56 × 92 | 12/700 | 0.36px | rgb(220, 236, 247) | rgba(cyan, 0.043) | T 4px rgb(127, 92, 255)<br>R 1px rgba(cyan, 0.12) | 0px | none | 5 4 6 4 |
| #resultRows .result-row.me | `#resultRows .result-row.me` | 795.42, 916 | 164.58 × 92 | 12/700 | 0.36px | rgb(220, 236, 247) | rgba(182, 255, 87, 0.16) | T 4px rgb(182, 255, 87)<br>R 1px rgba(cyan, 0.12) | 0px | rgba(182, 255, 87, 0.2) 0px 0px 28px 0p… | 5 4 6 4 |
| #resultRows .r-rank | `#resultRows .result-row .r-rank` | 377.47, 925 | 12.08 × 25 | 19/900 | 0.36px | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultRows .r-name | `#resultRows .result-row .r-name` | 367.77, 951 | 31.48 × 20 | 15/700 | 0.36px | rgb(220, 236, 247) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultRows .r-len | `#resultRows .result-row .r-len` | 353.67, 972 | 59.67 × 30 | 23/900 | 0.36px | rgb(242, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultRows .r-extra | `#resultRows .result-row .r-extra` | 880.67, 984 | 56.75 × 15 | 11/600 | 0.36px | rgb(242, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultRows .r-avatar | `#resultRows .r-avatar` | — | — | — | — | — | — | — | — | — | — |
| #resultOverlay .result-actions | `#resultOverlay .result-actions` | 0, 1008 | 1920 × 64 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 10 22 0 22 |
| #againBtn | `#againBtn` | 805.64, 1018 | 206.81 × 54 | 22/900 | 2.2px | rgb(10, 31, 16) | lg(rgb(212, 255, 122), rgb(134, 240, 106) 60%… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 4px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.2) 0px 0px 30px 0… | 10 30 10 30 |
| #resultOverlay .result-actions .hint | `#resultOverlay .result-actions .hint` | 1028.45, 1035 | 85.89 × 20 | 12/700 | 0.72px | rgba(190, 220, 238, 0.7) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**Pseudo-elements** (this is where the OSD lives)

| pseudo | content | box | opacity | background |
|---|---|---|---|---|
| `body::before (scanlines + vignette)` | `""` | {'w': '1920px', 'h': '1080px', 'top': '0px', 'right': '0px', 'bottom'… | 1 | repeating-lg(0deg, rgba(160, 220, 255, 0.024) 0px, rgba(160, 220, 255, 0.024) 1… |
| `body::after (OSD 4-corner brackets)` | `""` | {'w': '1832px', 'h': '992px', 'top': '44px', 'right': '44px', 'bottom… | 0.55 | lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan),… |
| `#uiBar::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#uiBar::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud .stat::after (data-en watermark)` | `"TIME"` | {'w': 'auto', 'h': 'auto', 'top': '4px', 'right': '8px', 'bottom': 'a… | 1 | none |
| `.stat::after (data-en watermark)` | `"TIME"` | {'w': 'auto', 'h': 'auto', 'top': '4px', 'right': '8px', 'bottom': 'a… | 1 | none |
| `#cam::before` | `""` | {'w': '316px', 'h': '176px', 'top': '0px', 'right': '0px', 'bottom': … | 1 | none |
| `#pauseStats .stat::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#overlay .panel::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#resultOverlay .result-bottom::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#leaderboard::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#quickPlayBtn::before` | `"A"` | {'w': '22px', 'h': '22px', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | lg(rgb(226, 250, 255), rgb(138, 216, 238)) |

### 4.6 `split2p` @ 1920×1080

2P split — title screen with 2 players chosen

`body.class = ""` · `data-split = 2` · `game.state = ready` · `--ui-scale = 1`

**A. Panel chrome / OSD / merged HUD bar**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #uiBar (merged HUD bar) | `#uiBar` | 0, 0 | 1920 × 200 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(cyan, 0.043) 1px, rgba(0, 0, 0,… | B 3px cyan | 0px | rgba(0, 0, 0, 0.78) 0px 20px 52px 0px, … | 0 56 0 56 |
| #uiBar .ui-deco | `#uiBar .ui-deco` | 0, 0 | 1920 × 197 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-energy | `#uiBar .ui-energy` | 0, 0 | 1920 × 6 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(cyan, 0.16) |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-energy i | `#uiBar .ui-energy i` | 73.05, 0 | 729.59 × 6 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(0, 0, 0, 0), rgb(184, 247, 255… |  | 0px | rgba(cyan, 0.95) 0px 0px 26px 0px | 0 0 0 0 |
| #uiBar .ui-scan | `#uiBar .ui-scan` | 0, 0 | 1920 × 197 | 16/400 | 0.32px | rgb(234, 246, 255) | repeating-lg(0deg, rgba(190, 235, 255, 0.024)… |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-ruler | `#uiBar .ui-ruler` | 90, 185 | 1740 × 5 | 16/400 | 0.32px | rgb(234, 246, 255) | repeating-lg(90deg, rgba(cyan, 0.4) 0px, rgba… |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-seam | `#uiBar .ui-seam` | 0, 197 | 1920 × 3 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(0, 0, 0, 0), cyan 10%, rgb(230… |  | 0px | rgba(cyan, 0.75) 0px 0px 22px 0px | 0 0 0 0 |
| #uiBar .ui-diamond | `#uiBar .ui-diamond` | 950.81, 178.31 | 18.38 × 18.38 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(230, 251, 255) |  | 0px | cyan 0px 0px 18px 0px | 0 0 0 0 |
| #uiBar .ui-notch.left | `#uiBar .ui-notch.left` | 0, 183 | 30 × 14 | 16/400 | 0.32px | rgb(234, 246, 255) | cyan |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-notch.right | `#uiBar .ui-notch.right` | 1890, 183 | 30 × 14 | 16/400 | 0.32px | rgb(234, 246, 255) | cyan |  | 0px | none | 0 0 0 0 |

**B. Clock, stat cells, rank block**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #hud | `#hud` | 602, 23.5 | 716 × 150 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(cyan, 0.1), rgba(cyan, 0.01) 6… | L 4px rgb(182, 255, 87) | 0px | none | 0 0 0 0 |
| #hud .stat | `#hud .stat` | 844.84, 32.95 | 234.31 × 131.08 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 14 0 14 |
| #hud .stat .k (剩余 label) | `#hud .stat .k` | 926.16, 32.95 | 71.69 × 37 | 28/700 | 7.84px | rgba(198, 232, 248, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #timeLeft (clock digits) | `#timeLeft` | 858.84, 69.95 | 206.31 × 94.08 | 96/900 | 0.32px | rgb(215, 247, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock | `#rankBlock` | 338, 23.5 | 250 × 150 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(270deg, rgba(182, 255, 87, 0.09), rgba(0, … | R 4px rgb(182, 255, 87) | 0px | none | 0 4 0 20 |
| #rankBlock .rank-k | `#rankBlock .rank-k` | 472.67, 37.5 | 107.33 × 31 | 24/700 | 4.32px | rgba(198, 232, 248, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rank (rank numeral) | `#rank` | 426.47, 68.5 | 153.53 × 66 | 66/900 | 0.32px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock .rank-arrow | `#rankBlock .rank-arrow` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock .rank-total | `#rankBlock .rank-total` | 468.31, 134.5 | 111.69 × 25 | 19/400 | 1.9px | rgba(190, 225, 240, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**C. Mirror box (the camera pane inside the HUD band)**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #cam (mirror box) | `#cam` | 56, 23.13 | 268 × 150.75 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(4, 11, 20) | T 2px rgba(cyan, 0.55)<br>R 2px rgba(cyan, 0.55)<br>B 2px rgba(cyan, 0.55)<br>L 2px rgba(cyan, 0.55) | 2px | rgba(cyan, 0.06) 0px 0px 0px 6px, rgba(… | 0 0 0 0 |
| #cam .cam-frame | `#cam .cam-frame` | 58, 25.13 | 264 × 146.75 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #cam .cam-frame i | `#cam .cam-frame i` | 63, 30.13 | 22 × 22 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | T 3px cyan<br>L 3px cyan | 0px | none | 0 0 0 0 |
| #cam .cam-rec | `#cam .cam-rec` | 299, 34.13 | 14 × 14 | 9/900 | 1.44px | rgb(255, 156, 174) | rgba(0, 0, 0, 0) |  | 50% | none | 0 0 0 0 |
| #cam .cam-tag | `#cam .cam-tag` | 67, 33.13 | 32.75 × 20 | 10/900 | 1px | rgb(182, 255, 87) | rgba(4, 10, 20, 0.82) | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 1px rgba(182, 255, 87, 0.…<br>L 1px rgba(182, 255, 87, 0.… | 3px | none | 4 8 4 8 |
| #cam .cam-speed | `#cam .cam-speed` | 58, 129.88 | 264 × 42 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(2, 10, 20, 0.95), rgba(2, 10, 2… |  | 0px | none | 0 12 0 12 |
| #cam .cam-speed-val | `#cam .cam-speed-val` | 70, 133.38 | 92 × 35 | 26/800 | 0.52px | rgb(220, 248, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #cam .cam-speed-track | `#cam .cam-speed-track` | 172, 145.88 | 138 × 10 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 22, 36, 0.86) | T 1px rgba(cyan, 0.4)<br>R 1px rgba(cyan, 0.4)<br>B 1px rgba(cyan, 0.4)<br>L 1px rgba(cyan, 0.4) | 0px | none | 0 0 0 0 |
| #cam .cam-speed-track i | `#cam .cam-speed-track i` | 173, 146.88 | 40.8 × 8 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgb(47, 159, 214), cyan 55%, rgb(18… |  | 0px | rgba(cyan, 0.9) 0px 0px 14px 0px | 0 0 0 0 |
| #cam .cam-label | `#cam .cam-label` | 58, 136.88 | 264 × 35 | 10.5/700 | 1.05px | rgb(205, 238, 255) | lg(to top, rgba(8, 3, 16, 0.92), rgba(8, 3, 1… |  | 0px | none | 14 10 7 10 |
| #cam .cam-ready | `#cam .cam-ready` | — | **hidden** | · | · | rgb(234, 246, 255) | lg(rgba(4, 10, 20, 0), rgba(4, 10, 20, 0.88)) |  | 0px | none | 12 0 13 0 |

**D. Status, buttons, key strip, buffs, leaderboard**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #statusbar | `#statusbar` | 1784.39, 44 | 91.61 × 36 | 12/800 | 1.2px | rgb(217, 238, 251) | rgba(6, 14, 26, 0.94) | T 1px rgba(cyan, 0.34)<br>R 3px cyan<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.55) 0px 10px 26px 0px | 9 16 9 16 |
| #statusbar .dot | `#statusbar .dot` | 1801.39, 58 | 8 × 8 | 12/800 | 1.2px | rgb(217, 238, 251) | rgb(107, 95, 133) |  | 50% | rgba(0, 0, 0, 0) 0px 0px 0px 0px | 0 0 0 0 |
| #status (status text) | `#status` | 1817.39, 54 | 39.61 × 16 | 12/800 | 1.2px | rgb(217, 238, 251) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #quickPlayBtn | `#quickPlayBtn` | 1743, 94 | 133 × 42 | 12.5/800 | 1px | rgb(233, 255, 208) | lg(100deg, rgba(9, 26, 32, 0.97), rgba(14, 38… | T 1px rgba(182, 255, 87, 0.…<br>R 3px rgb(182, 255, 87)<br>B 1px rgba(182, 255, 87, 0.…<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(0, 0, 0, 0.55) 0px 8px 24px 0px, r… | 8 15 8 15 |
| #muteBtn | `#muteBtn` | 1630, 94 | 36 × 36 | 13.3333/400 | normal | cyan | rgba(6, 14, 26, 0.9) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | none | 0 0 0 0 |
| #padBar | `#padBar` | 274, 998 | 538.44 × 38 | 11/700 | 0.44px | rgba(214, 236, 250, 0.8) | rgba(6, 14, 26, 0.86) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px cyan | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 8 14 8 14 |
| #padBar .keycap | `#padBar .keycap` | 291, 1007 | 57.14 × 20 | 10/900 | 0.6px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) | T 1px rgba(255, 255, 255, 0…<br>R 1px rgba(255, 255, 255, 0…<br>B 1px rgba(255, 255, 255, 0…<br>L 1px rgba(255, 255, 255, 0… | 4px | rgba(0, 0, 0, 0.6) 0px 2px 0px 0px, rgb… | 0 6 0 6 |
| .keycap (generic keycap) | `.keycap` | — | **hidden** | · | · | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) | T 1px rgba(255, 255, 255, 0…<br>R 1px rgba(255, 255, 255, 0…<br>B 1px rgba(255, 255, 255, 0…<br>L 1px rgba(255, 255, 255, 0… | 4px | rgba(0, 0, 0, 0.6) 0px 2px 0px 0px, rgb… | 0 6 0 6 |
| #hint | `#hint` | 936, 1006 | 48 × 22 | 13/800 | 0.78px | rgb(220, 255, 224) | rgba(6, 14, 26, 0.93) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px rgb(182, 255, 87) | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 10 22 10 22 |
| #buffs | `#buffs` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost (buff chip) | `#buffBoost` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(6, 14, 26, 0.95) | T 1px rgba(255, 213, 74, 0.…<br>R 3px rgba(255, 213, 74, 0.…<br>B 1px rgba(255, 213, 74, 0.…<br>L 1px rgba(255, 213, 74, 0.… | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 7 11 11 11 |
| #buffBoost .buff-name | `#buffBoost .buff-name` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-time | `#buffBoost .buff-time` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-bar | `#buffBoost .buff-bar` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(255, 255, 255, 0.12) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-bar i | `#buffBoost .buff-bar i` | — | **hidden** | · | · | rgb(255, 213, 74) | rgb(255, 213, 74) |  | 2px | none | 0 0 0 0 |
| #leaderboard | `#leaderboard` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(6, 14, 26, 0.95) | T 3px cyan<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.6) 0px 16px 40px 0px | 11 12 10 12 |
| #leaderboard .lb-head | `#leaderboard .lb-head` | — | **hidden** | · | · | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #leaderboard .lb-head span | `#leaderboard .lb-head span` | — | **hidden** | · | · | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbTime | `#lbTime` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows | `#lbRows` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-row | `#lbRows .lb-row` | — | — | — | — | — | — | — | — | — | — |
| #lbRows .lb-row.me | `#lbRows .lb-row.me` | — | — | — | — | — | — | — | — | — | — |
| #lbRows .lb-rank | `#lbRows .lb-row .lb-rank` | — | — | — | — | — | — | — | — | — | — |
| #lbRows .lb-name | `#lbRows .lb-row .lb-name` | — | — | — | — | — | — | — | — | — | — |
| #lbRows .lb-len | `#lbRows .lb-row .lb-len` | — | — | — | — | — | — | — | — | — | — |

**E. Pause / OPTIONS layer**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #pauseScrim | `#pauseScrim` | 0, 200 | 1920 × 880 | 16/400 | 0.32px | rgb(234, 246, 255) | radial-gradient(at 50% 0%, rgba(6, 16, 30, 0.… |  | 0px | none | 22 0 0 0 |
| #pauseScrim .pause-scrim-inner | `#pauseScrim .pause-scrim-inner` | 793.67, 222 | 332.64 × 137 | 16/400 | 0.32px | rgb(223, 244, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim .pause-kicker | `#pauseScrim .pause-kicker` | 795.67, 222 | 328.64 × 31 | 24/800 | 6.72px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim strong | `#pauseScrim .pause-scrim-inner strong` | 793.67, 259 | 332.64 × 59 | 44/900 | 3.52px | rgb(223, 244, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim .pause-tip | `#pauseScrim .pause-tip` | 837.8, 324 | 244.39 × 35 | 26/400 | 0.32px | rgba(200, 230, 245, 0.7… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats | `#pauseStats` | 679.36, 318 | 561.28 × 193.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 16, 29, 0.97) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 4px cyan | 4px | rgba(0, 0, 0, 0.7) 0px 18px 48px 0px | 16 20 16 20 |
| #pauseStats .stat | `#pauseStats .stat` | 767.5, 335 | 120 × 110.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(12, 28, 46, 0.7) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.35) 0px 8px 28px 0px, r… | 10 14 10 14 |
| #pauseStats .stat .k | `#pauseStats .stat .k` | 782.5, 346 | 90 × 37 | 28/600 | 3.92px | rgba(190, 214, 238, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats .stat .v | `#pauseStats .stat .v` | 782.5, 384 | 90 × 50.39 | 48/900 | 0.32px | rgb(242, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats .legacy-stat (dead weight) | `#pauseStats .legacy-stat` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(12, 28, 46, 0.7) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.35) 0px 8px 28px 0px, r… | 10 14 10 14 |
| #pauseBuff | `#pauseBuff` | 703.36, 459.39 | 516.28 × 35 | 26/700 | 1.56px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning (settings drawer) | `#tuning` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(6, 14, 26, 0.95) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 3px rgb(182, 255, 87) | 4px | rgba(0, 0, 0, 0.55) 0px 10px 26px 0px | 0 0 0 0 |
| #tuning .tuning-head | `#tuning .tuning-head` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 11 13 11 13 |
| #tuning .tuning-title | `#tuning .tuning-title` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning .tuning-mark | `#tuning .tuning-mark` | — | **hidden** | · | · | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuningToggle | `#tuningToggle` | — | **hidden** | · | · | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) |  | 3px | none | 4 10 4 10 |
| #tuning .tuning-body | `#tuning .tuning-body` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 14 14 16 14 |
| #tuning .tuning-body .row | `#tuning .tuning-body .row` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning .ai-sep | `#tuning .ai-sep` | — | **hidden** | · | · | cyan | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.34)<br>L 3px rgb(182, 255, 87) | 0px | none | 9 0 0 10 |

**F. Start / title slab**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #overlay | `#overlay` | 0, 0 | 1920 × 1080 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(cyan, 0.043) 1px, rgba(0, 0, 0,… |  | 0px | none | 44 44 44 44 |
| #overlay .panel.title-screen (title slab) | `#overlay .panel.title-screen` | 570, 240.02 | 780 × 599.97 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(155deg, rgba(9, 20, 36, 0.98), rgba(5, 10,… | T 4px rgb(182, 255, 87)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 4px | rgba(0, 0, 0, 0.8) 0px 40px 100px 0px, … | 0 0 0 0 |
| #overlay .title-hero | `#overlay .title-hero` | 571, 244.02 | 778 × 206.47 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 20 32 14 32 |
| #overlay .brand-line | `#overlay .brand-line` | 603, 264.02 | 714 × 33 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | B 1px rgba(cyan, 0.15) | 0px | none | 0 0 10 0 |
| #overlay .brand-tag | `#overlay .brand-tag` | 848.86, 264.02 | 132.31 × 22 | 10/900 | 2.4px | rgb(6, 33, 12) | rgb(182, 255, 87) |  | 2px | rgba(182, 255, 87, 0.35) 0px 0px 20px 0… | 4 10 4 10 |
| #overlay .brand-ver | `#overlay .brand-ver` | 991.17, 268.02 | 79.95 × 14 | 10/800 | 2px | rgba(150, 205, 230, 0.6) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .title-hero .logo | `#overlay .title-hero .logo` | 603, 307.02 | 714 × 61.47 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .snake-dot | `#overlay .snake-dot` | 794.19, 328.75 | 18 × 18 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(182, 255, 87) |  | 3px | rgba(182, 255, 87, 0.14) 0px 0px 0px 4p… | 0 0 0 0 |
| #panelTitle | `#panelTitle` | 824.19, 307.02 | 301.61 × 61.47 | 58/900 | 2.32px | rgba(0, 0, 0, 0) | lg(100deg, rgb(234, 255, 208), rgb(182, 255, … |  | 0px | none | 0 0 0 0 |
| #overlay .title-sub | `#overlay .title-sub` | 603, 376.48 | 714 × 17 | 13/400 | 2.86px | rgba(196, 228, 244, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .mode-badges | `#overlay .mode-badges` | 603, 403.48 | 714 × 29 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .mode-badges span | `#overlay .mode-badges span` | 779.14, 403.48 | 87.94 × 29 | 11/700 | 0.88px | rgba(206, 234, 250, 0.8) | rgba(cyan, 0.07) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px cyan | 2px | none | 6 12 6 12 |
| #overlay .mode-badges b | `#overlay .mode-badges b` | 794.14, 410.48 | 27.02 × 15 | 11/900 | 0.88px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .player-select | `#overlay .player-select` | 571, 450.48 | 778 × 115 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 12 32 0 32 |
| #overlay .ps-label | `#overlay .ps-label` | 603, 462.48 | 714 × 15 | 11/800 | 2.86px | rgba(150, 205, 230, 0.7) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .ps-btn | `#overlay .ps-btn` | 603, 486.48 | 351 × 79 | 13.3333/400 | normal | rgba(214, 236, 250, 0.8… | lg(rgba(20, 48, 70, 0.55), rgba(9, 24, 40, 0.… | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 3px rgba(cyan, 0.28)<br>L 1px rgba(cyan, 0.15) | 3px | none | 13 10 14 10 |
| #overlay .ps-btn.active | `#overlay .ps-btn.active` | 966, 486.48 | 351 × 79 | 13.3333/400 | normal | rgb(236, 255, 214) | lg(rgba(110, 240, 130, 0.17), rgba(9, 24, 40,… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.14) 0px 0px 26px … | 13 10 14 10 |
| #overlay .ps-btn b | `#overlay .ps-btn b` | 757.2, 500.48 | 42.58 × 28 | 19/900 | 1.52px | rgba(214, 236, 250, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .ps-btn span | `#overlay .ps-btn span` | 745.16, 532.48 | 66.67 × 16 | 11.5/400 | 0.69px | rgba(160, 196, 218, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .panel-actions | `#overlay .panel-actions` | 571, 565.48 | 778 × 233.5 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(5, 10, 20, 0.99) 60%, rgba(5, 1… |  | 0px | none | 12 32 16 32 |
| #overlay .menu-buttons | `#overlay .menu-buttons` | 603, 577.48 | 714 × 54 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #startBtn | `#startBtn` | 603, 577.48 | 391.11 × 54 | 14/900 | 1.4px | rgb(7, 32, 12) | lg(rgb(217, 255, 122), rgb(134, 240, 106) 60%… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.2) 0px 0px 30px 0… | 13 12 13 12 |
| #kbBtn | `#kbBtn` | 1004.11, 577.48 | 312.89 × 54 | 14/900 | 1.4px | rgb(216, 244, 255) | lg(rgba(20, 48, 70, 0.9), rgba(9, 24, 40, 0.9… | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 3px rgba(cyan, 0.45)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(4, 14, 26, 0.7) 0px 8px 0px 0px | 13 12 13 12 |
| #panelHint | `#panelHint` | 603, 672.73 | 714 × 18 | 12/400 | 0.32px | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .fineprint | `#overlay .fineprint` | 603, 699.73 | 714 × 47.25 | 10.5/400 | 0.32px | rgba(160, 196, 218, 0.5) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .pad-hints | `#overlay .pad-hints` | 603, 753.98 | 714 × 29 | 10/700 | 0.8px | rgba(190, 220, 238, 0.7) | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.15) | 0px | none | 8 0 0 0 |
| #overlay .rules-details | `#overlay .rules-details` | 603, 804.98 | 714 × 34 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.15) | 0px | none | 0 0 0 0 |

**G. Settlement**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #resultOverlay | `#resultOverlay` | 0, 0 | 1920 × 1080 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .result-top | `#resultOverlay .result-top` | 0, 0 | 1920 × 66 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(rgba(4, 9, 18, 0.86) 0px, rgba(4, 9, 18, 0… |  | 0px | none | 6 24 10 24 |
| #resultOverlay .result-headline | `#resultOverlay .result-headline` | 24, 7.3 | 188.89 × 47.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .result-headline .logo | `#resultOverlay .result-headline .logo` | 24, 7.3 | 174.89 × 41.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultTitle | `#resultTitle` | 52, 7.3 | 146.89 × 41.39 | 36/900 | 0.72px | rgb(244, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultStats | `#resultStats` | — | **hidden** | · | · | rgba(196, 224, 242, 0.7… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .stage-actions | `#resultOverlay .stage-actions` | 1752.09, 6 | 143.91 × 50 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 4 0 0 0 |
| #skipStageBtn | `#skipStageBtn` | 1752.09, 10 | 143.91 × 46 | 13/800 | 1.04px | rgb(223, 246, 255) | rgba(8, 20, 36, 0.92) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 3px rgba(cyan, 0.4)<br>L 1px rgba(cyan, 0.34) | 3px | none | 9 15 9 15 |
| #resultOverlay .result-bottom | `#resultOverlay .result-bottom` | 0, 996 | 1920 × 84 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(rgba(4, 9, 18, 0) 0px, rgba(4, 9, 18, 0.95… |  | 0px | none | 12 0 8 0 |
| #resultRows | `#resultRows` | 301.73, 1008 | 1316.53 × 0 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultRows .result-row | `#resultRows .result-row` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .result-row.me | `#resultRows .result-row.me` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-rank | `#resultRows .result-row .r-rank` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-name | `#resultRows .result-row .r-name` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-len | `#resultRows .result-row .r-len` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-extra | `#resultRows .result-row .r-extra` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-avatar | `#resultRows .r-avatar` | — | — | — | — | — | — | — | — | — | — |
| #resultOverlay .result-actions | `#resultOverlay .result-actions` | 0, 1008 | 1920 × 64 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 10 22 0 22 |
| #againBtn | `#againBtn` | 805.64, 1018 | 206.81 × 54 | 22/900 | 2.2px | rgb(10, 31, 16) | lg(rgb(212, 255, 122), rgb(134, 240, 106) 60%… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 4px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.2) 0px 0px 30px 0… | 10 30 10 30 |
| #resultOverlay .result-actions .hint | `#resultOverlay .result-actions .hint` | 1028.45, 1035 | 85.89 × 20 | 12/700 | 0.72px | rgba(190, 220, 238, 0.7) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**Pseudo-elements** (this is where the OSD lives)

| pseudo | content | box | opacity | background |
|---|---|---|---|---|
| `body::before (scanlines + vignette)` | `""` | {'w': '1920px', 'h': '1080px', 'top': '0px', 'right': '0px', 'bottom'… | 1 | repeating-lg(0deg, rgba(160, 220, 255, 0.024) 0px, rgba(160, 220, 255, 0.024) 1… |
| `body::after (OSD 4-corner brackets)` | `""` | {'w': '1832px', 'h': '992px', 'top': '44px', 'right': '44px', 'bottom… | 0.55 | lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan),… |
| `#uiBar::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#uiBar::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud .stat::after (data-en watermark)` | `"TIME"` | {'w': 'auto', 'h': 'auto', 'top': '4px', 'right': '8px', 'bottom': 'a… | 1 | none |
| `.stat::after (data-en watermark)` | `"TIME"` | {'w': 'auto', 'h': 'auto', 'top': '4px', 'right': '8px', 'bottom': 'a… | 1 | none |
| `#cam::before` | `""` | {'w': '264px', 'h': '146.75px', 'top': '0px', 'right': '0px', 'bottom… | 1 | none |
| `#pauseStats .stat::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#overlay .panel::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#resultOverlay .result-bottom::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#leaderboard::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#quickPlayBtn::before` | `"A"` | {'w': '22px', 'h': '22px', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | lg(rgb(226, 250, 255), rgb(138, 216, 238)) |

### 4.7 `split2p-play` @ 1920×1080

2P split — in-game, five-column band

`body.class = "in-round"` · `data-split = 2` · `game.state = playing` · `--ui-scale = 1`

**A. Panel chrome / OSD / merged HUD bar**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #uiBar (merged HUD bar) | `#uiBar` | 0, 0 | 1920 × 200 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(cyan, 0.043) 1px, rgba(0, 0, 0,… | B 3px cyan | 0px | rgba(0, 0, 0, 0.78) 0px 20px 52px 0px, … | 0 56 0 56 |
| #uiBar .ui-deco | `#uiBar .ui-deco` | 0, 0 | 1920 × 197 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-energy | `#uiBar .ui-energy` | 0, 0 | 1920 × 6 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(cyan, 0.16) |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-energy i | `#uiBar .ui-energy i` | 1845.89, 0 | 729.59 × 6 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(0, 0, 0, 0), rgb(184, 247, 255… |  | 0px | rgba(cyan, 0.95) 0px 0px 26px 0px | 0 0 0 0 |
| #uiBar .ui-scan | `#uiBar .ui-scan` | 0, 0 | 1920 × 197 | 16/400 | 0.32px | rgb(234, 246, 255) | repeating-lg(0deg, rgba(190, 235, 255, 0.024)… |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-ruler | `#uiBar .ui-ruler` | 90, 185 | 1740 × 5 | 16/400 | 0.32px | rgb(234, 246, 255) | repeating-lg(90deg, rgba(cyan, 0.4) 0px, rgba… |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-seam | `#uiBar .ui-seam` | 0, 197 | 1920 × 3 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(0, 0, 0, 0), cyan 10%, rgb(230… |  | 0px | rgba(cyan, 0.75) 0px 0px 22px 0px | 0 0 0 0 |
| #uiBar .ui-diamond | `#uiBar .ui-diamond` | 950.81, 178.31 | 18.38 × 18.38 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(230, 251, 255) |  | 0px | cyan 0px 0px 18px 0px | 0 0 0 0 |
| #uiBar .ui-notch.left | `#uiBar .ui-notch.left` | 0, 183 | 30 × 14 | 16/400 | 0.32px | rgb(234, 246, 255) | cyan |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-notch.right | `#uiBar .ui-notch.right` | 1890, 183 | 30 × 14 | 16/400 | 0.32px | rgb(234, 246, 255) | cyan |  | 0px | none | 0 0 0 0 |

**B. Clock, stat cells, rank block**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #hud | `#hud` | 602, 23.5 | 716 × 150 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(cyan, 0.1), rgba(cyan, 0.01) 6… | L 4px rgb(182, 255, 87) | 0px | none | 0 0 0 0 |
| #hud .stat | `#hud .stat` | 844.84, 32.95 | 234.31 × 131.08 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 14 0 14 |
| #hud .stat .k (剩余 label) | `#hud .stat .k` | 926.16, 32.95 | 71.69 × 37 | 28/700 | 7.84px | rgba(198, 232, 248, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #timeLeft (clock digits) | `#timeLeft` | 858.84, 69.95 | 206.31 × 94.08 | 96/900 | 0.32px | rgb(215, 247, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock | `#rankBlock` | 338, 23.5 | 250 × 150 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(270deg, rgba(182, 255, 87, 0.09), rgba(0, … | R 4px rgb(182, 255, 87) | 0px | none | 0 4 0 20 |
| #rankBlock .rank-k | `#rankBlock .rank-k` | 472.67, 37.5 | 107.33 × 31 | 24/700 | 4.32px | rgba(198, 232, 248, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rank (rank numeral) | `#rank` | 426.47, 68.5 | 153.53 × 66 | 66/900 | 0.32px | rgb(255, 154, 114) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock .rank-arrow | `#rankBlock .rank-arrow` | 342, 75 | 35.95 × 47 | 36/900 | 0.32px | rgb(255, 154, 114) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock .rank-total | `#rankBlock .rank-total` | 468.31, 134.5 | 111.69 × 25 | 19/400 | 1.9px | rgba(190, 225, 240, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**C. Mirror box (the camera pane inside the HUD band)**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #cam (mirror box) | `#cam` | 56, 23.13 | 268 × 150.75 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(4, 11, 20) | T 2px rgba(cyan, 0.55)<br>R 2px rgba(cyan, 0.55)<br>B 2px rgba(cyan, 0.55)<br>L 2px rgba(cyan, 0.55) | 2px | rgba(cyan, 0.06) 0px 0px 0px 6px, rgba(… | 0 0 0 0 |
| #cam .cam-frame | `#cam .cam-frame` | 58, 25.13 | 264 × 146.75 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #cam .cam-frame i | `#cam .cam-frame i` | 63, 30.13 | 22 × 22 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | T 3px cyan<br>L 3px cyan | 0px | none | 0 0 0 0 |
| #cam .cam-rec | `#cam .cam-rec` | 299, 34.13 | 14 × 14 | 9/900 | 1.44px | rgb(255, 156, 174) | rgba(0, 0, 0, 0) |  | 50% | none | 0 0 0 0 |
| #cam .cam-tag | `#cam .cam-tag` | 67, 33.13 | 32.75 × 20 | 10/900 | 1px | rgb(182, 255, 87) | rgba(4, 10, 20, 0.82) | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 1px rgba(182, 255, 87, 0.…<br>L 1px rgba(182, 255, 87, 0.… | 3px | none | 4 8 4 8 |
| #cam .cam-speed | `#cam .cam-speed` | 58, 129.88 | 264 × 42 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(2, 10, 20, 0.95), rgba(2, 10, 2… |  | 0px | none | 0 12 0 12 |
| #cam .cam-speed-val | `#cam .cam-speed-val` | 70, 133.38 | 92 × 35 | 26/800 | 0.52px | rgb(220, 248, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #cam .cam-speed-track | `#cam .cam-speed-track` | 172, 145.88 | 138 × 10 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 22, 36, 0.86) | T 1px rgba(cyan, 0.4)<br>R 1px rgba(cyan, 0.4)<br>B 1px rgba(cyan, 0.4)<br>L 1px rgba(cyan, 0.4) | 0px | none | 0 0 0 0 |
| #cam .cam-speed-track i | `#cam .cam-speed-track i` | 173, 146.88 | 40.8 × 8 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgb(47, 159, 214), cyan 55%, rgb(18… |  | 0px | rgba(cyan, 0.9) 0px 0px 14px 0px | 0 0 0 0 |
| #cam .cam-label | `#cam .cam-label` | 58, 136.88 | 264 × 35 | 10.5/700 | 1.05px | rgb(205, 238, 255) | lg(to top, rgba(8, 3, 16, 0.92), rgba(8, 3, 1… |  | 0px | none | 14 10 7 10 |
| #cam .cam-ready | `#cam .cam-ready` | — | **hidden** | · | · | rgb(234, 246, 255) | lg(rgba(4, 10, 20, 0), rgba(4, 10, 20, 0.88)) |  | 0px | none | 12 0 13 0 |

**D. Status, buttons, key strip, buffs, leaderboard**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #statusbar | `#statusbar` | 1771.19, 44 | 104.81 × 36 | 12/800 | 1.2px | rgb(217, 238, 251) | rgba(6, 14, 26, 0.94) | T 1px rgba(cyan, 0.34)<br>R 3px cyan<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.55) 0px 10px 26px 0px | 9 16 9 16 |
| #statusbar .dot | `#statusbar .dot` | 1788.19, 58 | 8 × 8 | 12/800 | 1.2px | rgb(217, 238, 251) | rgb(255, 197, 61) |  | 50% | rgba(255, 197, 61, 0.9) 0px 0px 12px 0px | 0 0 0 0 |
| #status (status text) | `#status` | 1804.19, 54 | 52.81 × 16 | 12/800 | 1.2px | rgb(217, 238, 251) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #quickPlayBtn | `#quickPlayBtn` | 1743, 94 | 133 × 42 | 12.5/800 | 1px | rgb(233, 255, 208) | lg(100deg, rgba(9, 26, 32, 0.97), rgba(14, 38… | T 1px rgba(182, 255, 87, 0.…<br>R 3px rgb(182, 255, 87)<br>B 1px rgba(182, 255, 87, 0.…<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(0, 0, 0, 0.55) 0px 8px 24px 0px, r… | 8 15 8 15 |
| #muteBtn | `#muteBtn` | 1630, 94 | 36 × 36 | 13.3333/400 | normal | cyan | rgba(6, 14, 26, 0.9) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | none | 0 0 0 0 |
| #padBar | `#padBar` | 274, 998 | 538.44 × 38 | 11/700 | 0.44px | rgba(214, 236, 250, 0.8) | rgba(6, 14, 26, 0.86) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px cyan | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 8 14 8 14 |
| #padBar .keycap | `#padBar .keycap` | 291, 1007 | 57.14 × 20 | 10/900 | 0.6px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) | T 1px rgba(255, 255, 255, 0…<br>R 1px rgba(255, 255, 255, 0…<br>B 1px rgba(255, 255, 255, 0…<br>L 1px rgba(255, 255, 255, 0… | 4px | rgba(0, 0, 0, 0.6) 0px 2px 0px 0px, rgb… | 0 6 0 6 |
| .keycap (generic keycap) | `.keycap` | 207.16, 237 | 28.06 × 18 | 16/900 | 0.96px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) | T 1px rgba(255, 255, 255, 0…<br>R 1px rgba(255, 255, 255, 0…<br>B 1px rgba(255, 255, 255, 0…<br>L 1px rgba(255, 255, 255, 0… | 4px | rgba(0, 0, 0, 0.6) 0px 2px 0px 0px, rgb… | 0 6 0 6 |
| #hint | `#hint` | 890.01, 989 | 139.98 × 39 | 13/800 | 0.78px | rgb(220, 255, 224) | rgba(6, 14, 26, 0.93) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px rgb(182, 255, 87) | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 10 22 10 22 |
| #buffs | `#buffs` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost (buff chip) | `#buffBoost` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(6, 14, 26, 0.95) | T 1px rgba(255, 213, 74, 0.…<br>R 3px rgba(255, 213, 74, 0.…<br>B 1px rgba(255, 213, 74, 0.…<br>L 1px rgba(255, 213, 74, 0.… | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 7 11 11 11 |
| #buffBoost .buff-name | `#buffBoost .buff-name` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-time | `#buffBoost .buff-time` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-bar | `#buffBoost .buff-bar` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(255, 255, 255, 0.12) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-bar i | `#buffBoost .buff-bar i` | — | **hidden** | · | · | rgb(255, 213, 74) | rgb(255, 213, 74) |  | 2px | none | 0 0 0 0 |
| #leaderboard | `#leaderboard` | 1650, 248 | 226 × 153 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 14, 26, 0.95) | T 3px cyan<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.6) 0px 16px 40px 0px | 11 12 10 12 |
| #leaderboard .lb-head | `#leaderboard .lb-head` | 1663, 262 | 200 × 16 | 10/700 | 1.8px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #leaderboard .lb-head span | `#leaderboard .lb-head span` | 1663, 262 | 98.36 × 16 | 10/700 | 1.8px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbTime | `#lbTime` | 1837.36, 262 | 25.64 × 16 | 12/700 | normal | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows | `#lbRows` | 1663, 285 | 200 × 105 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-row | `#lbRows .lb-row` | 1663, 285 | 200 × 24 | 12/400 | 0.32px | rgb(220, 234, 245) | rgba(0, 0, 0, 0) |  | 2px | none | 4 6 4 6 |
| #lbRows .lb-row.me | `#lbRows .lb-row.me` | 1663, 366 | 200 × 24 | 12/800 | 0.32px | rgb(234, 255, 210) | rgba(182, 255, 87, 0.16) | L 3px rgb(182, 255, 87) | 2px | none | 4 6 4 6 |
| #lbRows .lb-rank | `#lbRows .lb-row .lb-rank` | 1669, 289 | 16 × 16 | 12/900 | 0.32px | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-name | `#lbRows .lb-row .lb-name` | 1707, 289 | 111.34 × 16 | 12/400 | 0.32px | rgb(220, 234, 245) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-len | `#lbRows .lb-row .lb-len` | 1825.34, 289 | 31.66 × 16 | 12/800 | 0.32px | rgb(220, 234, 245) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**E. Pause / OPTIONS layer**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #pauseScrim | `#pauseScrim` | 0, 200 | 1920 × 880 | 16/400 | 0.32px | rgb(234, 246, 255) | radial-gradient(at 50% 0%, rgba(6, 16, 30, 0.… |  | 0px | none | 22 0 0 0 |
| #pauseScrim .pause-scrim-inner | `#pauseScrim .pause-scrim-inner` | 793.67, 222 | 332.64 × 137 | 16/400 | 0.32px | rgb(223, 244, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim .pause-kicker | `#pauseScrim .pause-kicker` | 795.67, 222 | 328.64 × 31 | 24/800 | 6.72px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim strong | `#pauseScrim .pause-scrim-inner strong` | 793.67, 259 | 332.64 × 59 | 44/900 | 3.52px | rgb(223, 244, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim .pause-tip | `#pauseScrim .pause-tip` | 837.8, 324 | 244.39 × 35 | 26/400 | 0.32px | rgba(200, 230, 245, 0.7… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats | `#pauseStats` | 679.36, 318 | 561.28 × 193.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 16, 29, 0.97) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 4px cyan | 4px | rgba(0, 0, 0, 0.7) 0px 18px 48px 0px | 16 20 16 20 |
| #pauseStats .stat | `#pauseStats .stat` | 767.5, 335 | 120 × 110.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(12, 28, 46, 0.7) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.35) 0px 8px 28px 0px, r… | 10 14 10 14 |
| #pauseStats .stat .k | `#pauseStats .stat .k` | 782.5, 346 | 90 × 37 | 28/600 | 3.92px | rgba(190, 214, 238, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats .stat .v | `#pauseStats .stat .v` | 782.5, 384 | 90 × 50.39 | 48/900 | 0.32px | rgb(242, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats .legacy-stat (dead weight) | `#pauseStats .legacy-stat` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(12, 28, 46, 0.7) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.35) 0px 8px 28px 0px, r… | 10 14 10 14 |
| #pauseBuff | `#pauseBuff` | 703.36, 459.39 | 516.28 × 35 | 26/700 | 1.56px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning (settings drawer) | `#tuning` | 21.59, 214 | 316.23 × 64 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 14, 26, 0.95) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 3px rgb(182, 255, 87) | 4px | rgba(0, 0, 0, 0.55) 0px 10px 26px 0px | 0 0 0 0 |
| #tuning .tuning-head | `#tuning .tuning-head` | 24.59, 215 | 312.23 × 62 | 22/800 | 3.08px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 12 18 12 18 |
| #tuning .tuning-title | `#tuning .tuning-title` | 42.59, 231.5 | 152.56 × 29 | 22/800 | 3.08px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning .tuning-mark | `#tuning .tuning-mark` | 42.59, 236.5 | 11.48 × 19 | 14/800 | 3.08px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuningToggle | `#tuningToggle` | 247.22, 227 | 71.61 × 38 | 18/800 | 1.8px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) |  | 3px | none | 7 16 7 16 |
| #tuning .tuning-body | `#tuning .tuning-body` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 14 14 16 14 |
| #tuning .tuning-body .row | `#tuning .tuning-body .row` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning .ai-sep | `#tuning .ai-sep` | — | **hidden** | · | · | cyan | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.34)<br>L 3px rgb(182, 255, 87) | 0px | none | 9 0 0 10 |

**F. Start / title slab**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #overlay | `#overlay` | 0, 0 | 1920 × 1080 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(cyan, 0.043) 1px, rgba(0, 0, 0,… |  | 0px | none | 44 44 44 44 |
| #overlay .panel.title-screen (title slab) | `#overlay .panel.title-screen` | 570, 255.14 | 780 × 569.72 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(155deg, rgba(9, 20, 36, 0.98), rgba(5, 10,… | T 4px rgb(182, 255, 87)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 4px | rgba(0, 0, 0, 0.8) 0px 40px 100px 0px, … | 0 0 0 0 |
| #overlay .title-hero | `#overlay .title-hero` | 571, 259.14 | 778 × 206.47 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 20 32 14 32 |
| #overlay .brand-line | `#overlay .brand-line` | 603, 279.14 | 714 × 33 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | B 1px rgba(cyan, 0.15) | 0px | none | 0 0 10 0 |
| #overlay .brand-tag | `#overlay .brand-tag` | 848.86, 279.14 | 132.31 × 22 | 10/900 | 2.4px | rgb(6, 33, 12) | rgb(182, 255, 87) |  | 2px | rgba(182, 255, 87, 0.35) 0px 0px 20px 0… | 4 10 4 10 |
| #overlay .brand-ver | `#overlay .brand-ver` | 991.17, 283.14 | 79.95 × 14 | 10/800 | 2px | rgba(150, 205, 230, 0.6) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .title-hero .logo | `#overlay .title-hero .logo` | 603, 322.14 | 714 × 61.47 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .snake-dot | `#overlay .snake-dot` | 794.19, 343.88 | 18 × 18 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(182, 255, 87) |  | 3px | rgba(182, 255, 87, 0.14) 0px 0px 0px 4p… | 0 0 0 0 |
| #panelTitle | `#panelTitle` | 824.19, 322.14 | 301.61 × 61.47 | 58/900 | 2.32px | rgba(0, 0, 0, 0) | lg(100deg, rgb(234, 255, 208), rgb(182, 255, … |  | 0px | none | 0 0 0 0 |
| #overlay .title-sub | `#overlay .title-sub` | 603, 391.61 | 714 × 17 | 13/400 | 2.86px | rgba(196, 228, 244, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .mode-badges | `#overlay .mode-badges` | 603, 418.61 | 714 × 29 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .mode-badges span | `#overlay .mode-badges span` | 779.14, 418.61 | 87.94 × 29 | 11/700 | 0.88px | rgba(206, 234, 250, 0.8) | rgba(cyan, 0.07) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px cyan | 2px | none | 6 12 6 12 |
| #overlay .mode-badges b | `#overlay .mode-badges b` | 794.14, 425.61 | 27.02 × 15 | 11/900 | 0.88px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .player-select | `#overlay .player-select` | 571, 465.61 | 778 × 115 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 12 32 0 32 |
| #overlay .ps-label | `#overlay .ps-label` | 603, 477.61 | 714 × 15 | 11/800 | 2.86px | rgba(150, 205, 230, 0.7) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .ps-btn | `#overlay .ps-btn` | 603, 501.61 | 351 × 79 | 13.3333/400 | normal | rgba(214, 236, 250, 0.8… | lg(rgba(20, 48, 70, 0.55), rgba(9, 24, 40, 0.… | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 3px rgba(cyan, 0.28)<br>L 1px rgba(cyan, 0.15) | 3px | none | 13 10 14 10 |
| #overlay .ps-btn.active | `#overlay .ps-btn.active` | 966, 501.61 | 351 × 79 | 13.3333/400 | normal | rgb(236, 255, 214) | lg(rgba(110, 240, 130, 0.17), rgba(9, 24, 40,… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.14) 0px 0px 26px … | 13 10 14 10 |
| #overlay .ps-btn b | `#overlay .ps-btn b` | 757.2, 515.61 | 42.58 × 28 | 19/900 | 1.52px | rgba(214, 236, 250, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .ps-btn span | `#overlay .ps-btn span` | 745.16, 547.61 | 66.67 × 16 | 11.5/400 | 0.69px | rgba(160, 196, 218, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .panel-actions | `#overlay .panel-actions` | 571, 580.61 | 778 × 203.25 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(5, 10, 20, 0.99) 60%, rgba(5, 1… |  | 0px | none | 12 32 16 32 |
| #overlay .menu-buttons | `#overlay .menu-buttons` | 603, 592.61 | 714 × 54 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #startBtn | `#startBtn` | 603, 592.61 | 391.11 × 54 | 14/900 | 1.4px | rgb(7, 32, 12) | lg(rgb(217, 255, 122), rgb(134, 240, 106) 60%… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.2) 0px 0px 30px 0… | 13 12 13 12 |
| #kbBtn | `#kbBtn` | 1004.11, 592.61 | 312.89 × 54 | 14/900 | 1.4px | rgb(216, 244, 255) | lg(rgba(20, 48, 70, 0.9), rgba(9, 24, 40, 0.9… | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 3px rgba(cyan, 0.45)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(4, 14, 26, 0.7) 0px 8px 0px 0px | 13 12 13 12 |
| #panelHint | `#panelHint` | 603, 657.61 | 714 × 18 | 12/400 | 0.32px | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .fineprint | `#overlay .fineprint` | 603, 684.61 | 714 × 47.25 | 10.5/400 | 0.32px | rgba(160, 196, 218, 0.5) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .pad-hints | `#overlay .pad-hints` | 603, 738.86 | 714 × 29 | 10/700 | 0.8px | rgba(190, 220, 238, 0.7) | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.15) | 0px | none | 8 0 0 0 |
| #overlay .rules-details | `#overlay .rules-details` | 603, 789.86 | 714 × 34 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.15) | 0px | none | 0 0 0 0 |

**G. Settlement**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #resultOverlay | `#resultOverlay` | 0, 0 | 1920 × 1080 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .result-top | `#resultOverlay .result-top` | 0, 0 | 1920 × 66 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(rgba(4, 9, 18, 0.86) 0px, rgba(4, 9, 18, 0… |  | 0px | none | 6 24 10 24 |
| #resultOverlay .result-headline | `#resultOverlay .result-headline` | 24, 7.3 | 188.89 × 47.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .result-headline .logo | `#resultOverlay .result-headline .logo` | 24, 7.3 | 174.89 × 41.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultTitle | `#resultTitle` | 52, 7.3 | 146.89 × 41.39 | 36/900 | 0.72px | rgb(244, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultStats | `#resultStats` | — | **hidden** | · | · | rgba(196, 224, 242, 0.7… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .stage-actions | `#resultOverlay .stage-actions` | 1752.09, 6 | 143.91 × 50 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 4 0 0 0 |
| #skipStageBtn | `#skipStageBtn` | 1752.09, 10 | 143.91 × 46 | 13/800 | 1.04px | rgb(223, 246, 255) | rgba(8, 20, 36, 0.92) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 3px rgba(cyan, 0.4)<br>L 1px rgba(cyan, 0.34) | 3px | none | 9 15 9 15 |
| #resultOverlay .result-bottom | `#resultOverlay .result-bottom` | 0, 996 | 1920 × 84 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(rgba(4, 9, 18, 0) 0px, rgba(4, 9, 18, 0.95… |  | 0px | none | 12 0 8 0 |
| #resultRows | `#resultRows` | 301.73, 1008 | 1316.53 × 0 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultRows .result-row | `#resultRows .result-row` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .result-row.me | `#resultRows .result-row.me` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-rank | `#resultRows .result-row .r-rank` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-name | `#resultRows .result-row .r-name` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-len | `#resultRows .result-row .r-len` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-extra | `#resultRows .result-row .r-extra` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-avatar | `#resultRows .r-avatar` | — | — | — | — | — | — | — | — | — | — |
| #resultOverlay .result-actions | `#resultOverlay .result-actions` | 0, 1008 | 1920 × 64 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 10 22 0 22 |
| #againBtn | `#againBtn` | 805.64, 1018 | 206.81 × 54 | 22/900 | 2.2px | rgb(10, 31, 16) | lg(rgb(212, 255, 122), rgb(134, 240, 106) 60%… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 4px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.2) 0px 0px 30px 0… | 10 30 10 30 |
| #resultOverlay .result-actions .hint | `#resultOverlay .result-actions .hint` | 1028.45, 1035 | 85.89 × 20 | 12/700 | 0.72px | rgba(190, 220, 238, 0.7) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**Pseudo-elements** (this is where the OSD lives)

| pseudo | content | box | opacity | background |
|---|---|---|---|---|
| `body::before (scanlines + vignette)` | `""` | {'w': '1920px', 'h': '1080px', 'top': '0px', 'right': '0px', 'bottom'… | 1 | repeating-lg(0deg, rgba(160, 220, 255, 0.024) 0px, rgba(160, 220, 255, 0.024) 1… |
| `body::after (OSD 4-corner brackets)` | `""` | {'w': '1832px', 'h': '992px', 'top': '44px', 'right': '44px', 'bottom… | 0.55 | lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan),… |
| `#uiBar::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#uiBar::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud .stat::after (data-en watermark)` | `"TIME"` | {'w': 'auto', 'h': 'auto', 'top': '4px', 'right': '8px', 'bottom': 'a… | 1 | none |
| `.stat::after (data-en watermark)` | `"TIME"` | {'w': 'auto', 'h': 'auto', 'top': '4px', 'right': '8px', 'bottom': 'a… | 1 | none |
| `#cam::before` | `""` | {'w': '264px', 'h': '146.75px', 'top': '0px', 'right': '0px', 'bottom… | 1 | none |
| `#pauseStats .stat::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#overlay .panel::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#resultOverlay .result-bottom::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#leaderboard::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#quickPlayBtn::before` | `"A"` | {'w': '22px', 'h': '22px', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | lg(rgb(226, 250, 255), rgb(138, 216, 238)) |

### 4.8 `title` @ 1440×810

Title @ 1440×810 (`--ui-scale: .74`)

`body.class = ""` · `data-split = 1` · `game.state = ready` · `--ui-scale = .74`

**A. Panel chrome / OSD / merged HUD bar**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #uiBar (merged HUD bar) | `#uiBar` | 0, 0 | 1440 × 148 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(cyan, 0.043) 1px, rgba(0, 0, 0,… | B 3px cyan | 0px | rgba(0, 0, 0, 0.78) 0px 20px 52px 0px, … | 0 66.6 0 66.6 |
| #uiBar .ui-deco | `#uiBar .ui-deco` | 0, 0 | 1440 × 145 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-energy | `#uiBar .ui-energy` | 0, 0 | 1440 × 6 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(cyan, 0.16) |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-energy i | `#uiBar .ui-energy i` | -53.06, 0 | 547.19 × 6 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(0, 0, 0, 0), rgb(184, 247, 255… |  | 0px | rgba(cyan, 0.95) 0px 0px 26px 0px | 0 0 0 0 |
| #uiBar .ui-scan | `#uiBar .ui-scan` | 0, 0 | 1440 × 145 | 16/400 | 0.32px | rgb(234, 246, 255) | repeating-lg(0deg, rgba(190, 235, 255, 0.024)… |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-ruler | `#uiBar .ui-ruler` | 66.59, 133 | 1306.81 × 5 | 16/400 | 0.32px | rgb(234, 246, 255) | repeating-lg(90deg, rgba(cyan, 0.4) 0px, rgba… |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-seam | `#uiBar .ui-seam` | 0, 145 | 1440 × 3 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(0, 0, 0, 0), cyan 10%, rgb(230… |  | 0px | rgba(cyan, 0.75) 0px 0px 22px 0px | 0 0 0 0 |
| #uiBar .ui-diamond | `#uiBar .ui-diamond` | 710.81, 126.31 | 18.38 × 18.38 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(230, 251, 255) |  | 0px | cyan 0px 0px 18px 0px | 0 0 0 0 |
| #uiBar .ui-notch.left | `#uiBar .ui-notch.left` | 0, 131 | 30 × 14 | 16/400 | 0.32px | rgb(234, 246, 255) | cyan |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-notch.right | `#uiBar .ui-notch.right` | 1410, 131 | 30 × 14 | 16/400 | 0.32px | rgb(234, 246, 255) | cyan |  | 0px | none | 0 0 0 0 |

**B. Clock, stat cells, rank block**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #hud | `#hud` | 331.5, 17 | 806.59 × 111 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(cyan, 0.1), rgba(cyan, 0.01) 6… | L 4px rgb(182, 255, 87) | 0px | none | 0 0 0 0 |
| #hud .stat | `#hud .stat` | 623.58, 11.5 | 226.44 × 122.02 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 17.76 0 17.76 |
| #hud .stat .k (剩余 label) | `#hud .stat .k` | 702.69, 11.5 | 68.2 × 35 | 26.64/700 | 7.4592px | rgba(198, 232, 248, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #timeLeft (clock digits) | `#timeLeft` | 641.33, 46.5 | 190.94 × 87.02 | 88.8/900 | 0.32px | rgb(215, 247, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock | `#rankBlock` | 1151.41, 17 | 222 × 111 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(270deg, rgba(182, 255, 87, 0.09), rgba(0, … | R 4px rgb(182, 255, 87) | 0px | none | 0 5.92 0 28.12 |
| #rankBlock .rank-k | `#rankBlock .rank-k` | 1231.36, 7.48 | 132.14 × 35 | 26.64/700 | 6.3936px | rgba(198, 232, 248, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rank (rank numeral) | `#rank` | 1198.38, 42.48 | 165.13 × 71.05 | 71.04/900 | 0.32px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock .rank-arrow | `#rankBlock .rank-arrow` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock .rank-total | `#rankBlock .rank-total` | 1259.09, 113.53 | 104.41 × 24 | 17.76/400 | 1.776px | rgba(190, 225, 240, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**C. Mirror box (the camera pane inside the HUD band)**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #cam (mirror box) | `#cam` | 66.59, 5.91 | 236.8 × 133.19 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(4, 11, 20) | T 2px rgba(cyan, 0.55)<br>R 2px rgba(cyan, 0.55)<br>B 2px rgba(cyan, 0.55)<br>L 2px rgba(cyan, 0.55) | 2px | rgba(cyan, 0.06) 0px 0px 0px 6px, rgba(… | 0 0 0 0 |
| #cam .cam-frame | `#cam .cam-frame` | 68.59, 7.91 | 232.8 × 129.19 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #cam .cam-frame i | `#cam .cam-frame i` | 73.59, 12.91 | 22 × 22 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | T 3px cyan<br>L 3px cyan | 0px | none | 0 0 0 0 |
| #cam .cam-rec | `#cam .cam-rec` | 278.39, 16.91 | 14 × 14 | 9/900 | 1.44px | rgb(255, 156, 174) | rgba(0, 0, 0, 0) |  | 50% | none | 0 0 0 0 |
| #cam .cam-tag | `#cam .cam-tag` | — | **hidden** | · | · | rgb(182, 255, 87) | rgba(4, 10, 20, 0.82) | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 1px rgba(182, 255, 87, 0.…<br>L 1px rgba(182, 255, 87, 0.… | 3px | none | 4 8 4 8 |
| #cam .cam-speed | `#cam .cam-speed` | 68.59, 106.02 | 232.8 × 31.08 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(2, 10, 20, 0.95), rgba(2, 10, 2… |  | 0px | none | 0 8.88 0 8.88 |
| #cam .cam-speed-val | `#cam .cam-speed-val` | 77.47, 109.05 | 68.08 × 25 | 19.24/800 | 0.3848px | rgb(220, 248, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #cam .cam-speed-track | `#cam .cam-speed-track` | 152.94, 117.86 | 139.58 × 7.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 22, 36, 0.86) | T 1px rgba(cyan, 0.4)<br>R 1px rgba(cyan, 0.4)<br>B 1px rgba(cyan, 0.4)<br>L 1px rgba(cyan, 0.4) | 0px | none | 0 0 0 0 |
| #cam .cam-speed-track i | `#cam .cam-speed-track i` | 153.94, 118.86 | 41.27 × 5.39 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgb(47, 159, 214), cyan 55%, rgb(18… |  | 0px | rgba(cyan, 0.9) 0px 0px 10.36px 0px | 0 0 0 0 |
| #cam .cam-label | `#cam .cam-label` | 68.59, 102.09 | 232.8 × 35 | 10.5/700 | 1.05px | rgb(205, 238, 255) | lg(to top, rgba(8, 3, 16, 0.92), rgba(8, 3, 1… |  | 0px | none | 14 10 7 10 |
| #cam .cam-ready | `#cam .cam-ready` | — | **hidden** | · | · | rgb(234, 246, 255) | lg(rgba(4, 10, 20, 0), rgba(4, 10, 20, 0.88)) |  | 0px | none | 12 0 13 0 |

**D. Status, buttons, key strip, buffs, leaderboard**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #statusbar | `#statusbar` | 1313.84, 34.55 | 91.61 × 36 | 12/800 | 1.2px | rgb(217, 238, 251) | rgba(6, 14, 26, 0.94) | T 1px rgba(cyan, 0.34)<br>R 3px cyan<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.55) 0px 10px 26px 0px | 9 16 9 16 |
| #statusbar .dot | `#statusbar .dot` | 1330.84, 48.55 | 8 × 8 | 12/800 | 1.2px | rgb(217, 238, 251) | rgb(107, 95, 133) |  | 50% | rgba(0, 0, 0, 0) 0px 0px 0px 0px | 0 0 0 0 |
| #status (status text) | `#status` | 1346.84, 44.55 | 39.61 × 16 | 12/800 | 1.2px | rgb(217, 238, 251) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #quickPlayBtn | `#quickPlayBtn` | 1272.45, 84.55 | 133 × 42 | 12.5/800 | 1px | rgb(233, 255, 208) | lg(100deg, rgba(9, 26, 32, 0.97), rgba(14, 38… | T 1px rgba(182, 255, 87, 0.…<br>R 3px rgb(182, 255, 87)<br>B 1px rgba(182, 255, 87, 0.…<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(0, 0, 0, 0.55) 0px 8px 24px 0px, r… | 8 15 8 15 |
| #muteBtn | `#muteBtn` | 1159.45, 84.55 | 36 × 36 | 13.3333/400 | normal | cyan | rgba(6, 14, 26, 0.9) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | none | 0 0 0 0 |
| #padBar | `#padBar` | 264.55, 737.45 | 451.17 × 38 | 11/700 | 0.44px | rgba(214, 236, 250, 0.8) | rgba(6, 14, 26, 0.86) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px cyan | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 8 14 8 14 |
| #padBar .keycap | `#padBar .keycap` | 281.55, 746.45 | 57.14 × 20 | 10/900 | 0.6px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) | T 1px rgba(255, 255, 255, 0…<br>R 1px rgba(255, 255, 255, 0…<br>B 1px rgba(255, 255, 255, 0…<br>L 1px rgba(255, 255, 255, 0… | 4px | rgba(0, 0, 0, 0.6) 0px 2px 0px 0px, rgb… | 0 6 0 6 |
| .keycap (generic keycap) | `.keycap` | — | **hidden** | · | · | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) | T 1px rgba(255, 255, 255, 0…<br>R 1px rgba(255, 255, 255, 0…<br>B 1px rgba(255, 255, 255, 0…<br>L 1px rgba(255, 255, 255, 0… | 4px | rgba(0, 0, 0, 0.6) 0px 2px 0px 0px, rgb… | 0 6 0 6 |
| #hint | `#hint` | 696, 745.45 | 48 × 22 | 13/800 | 0.78px | rgb(220, 255, 224) | rgba(6, 14, 26, 0.93) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px rgb(182, 255, 87) | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 10 22 10 22 |
| #buffs | `#buffs` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost (buff chip) | `#buffBoost` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(6, 14, 26, 0.95) | T 1px rgba(255, 213, 74, 0.…<br>R 3px rgba(255, 213, 74, 0.…<br>B 1px rgba(255, 213, 74, 0.…<br>L 1px rgba(255, 213, 74, 0.… | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 7 11 11 11 |
| #buffBoost .buff-name | `#buffBoost .buff-name` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-time | `#buffBoost .buff-time` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-bar | `#buffBoost .buff-bar` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(255, 255, 255, 0.12) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-bar i | `#buffBoost .buff-bar i` | — | **hidden** | · | · | rgb(255, 213, 74) | rgb(255, 213, 74) |  | 2px | none | 0 0 0 0 |
| #leaderboard | `#leaderboard` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(6, 14, 26, 0.95) | T 3px cyan<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.6) 0px 16px 40px 0px | 11 12 10 12 |
| #leaderboard .lb-head | `#leaderboard .lb-head` | — | **hidden** | · | · | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #leaderboard .lb-head span | `#leaderboard .lb-head span` | — | **hidden** | · | · | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbTime | `#lbTime` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows | `#lbRows` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-row | `#lbRows .lb-row` | — | — | — | — | — | — | — | — | — | — |
| #lbRows .lb-row.me | `#lbRows .lb-row.me` | — | — | — | — | — | — | — | — | — | — |
| #lbRows .lb-rank | `#lbRows .lb-row .lb-rank` | — | — | — | — | — | — | — | — | — | — |
| #lbRows .lb-name | `#lbRows .lb-row .lb-name` | — | — | — | — | — | — | — | — | — | — |
| #lbRows .lb-len | `#lbRows .lb-row .lb-len` | — | — | — | — | — | — | — | — | — | — |

**E. Pause / OPTIONS layer**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #pauseScrim | `#pauseScrim` | 0, 148 | 1440 × 662 | 16/400 | 0.32px | rgb(234, 246, 255) | radial-gradient(at 50% 0%, rgba(6, 16, 30, 0.… |  | 0px | none | 16.28 0 0 0 |
| #pauseScrim .pause-scrim-inner | `#pauseScrim .pause-scrim-inner` | 596.92, 164.27 | 246.16 × 104 | 16/400 | 0.32px | rgb(223, 244, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim .pause-kicker | `#pauseScrim .pause-kicker` | 598.41, 164.27 | 243.19 × 24 | 17.76/800 | 4.9728px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim strong | `#pauseScrim .pause-scrim-inner strong` | 596.92, 194.27 | 246.16 × 43 | 32.56/900 | 2.6048px | rgb(223, 244, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim .pause-tip | `#pauseScrim .pause-tip` | 629.03, 243.27 | 181.94 × 25 | 19.24/400 | 0.32px | rgba(200, 230, 245, 0.7… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats | `#pauseStats` | 511.68, 235.31 | 416.64 × 143.08 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 16, 29, 0.97) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 4px cyan | 4px | rgba(0, 0, 0, 0.7) 0px 18px 48px 0px | 11.84 14.8 11.84 14.8 |
| #pauseStats .stat | `#pauseStats .stat` | 577.95, 248.14 | 88.8 × 82.06 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(12, 28, 46, 0.7) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.35) 0px 8px 28px 0px, r… | 7.4 10.36 7.4 10.36 |
| #pauseStats .stat .k | `#pauseStats .stat .k` | 589.3, 256.53 | 66.08 × 27 | 20.72/600 | 2.9008px | rgba(190, 214, 238, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats .stat .v | `#pauseStats .stat .v` | 589.3, 284.53 | 66.08 × 37.28 | 35.52/900 | 0.32px | rgb(242, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats .legacy-stat (dead weight) | `#pauseStats .legacy-stat` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(12, 28, 46, 0.7) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.35) 0px 8px 28px 0px, r… | 7.4 10.36 7.4 10.36 |
| #pauseBuff | `#pauseBuff` | 530.48, 340.56 | 382.05 × 25 | 19.24/700 | 1.1544px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning (settings drawer) | `#tuning` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(6, 14, 26, 0.95) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 3px rgb(182, 255, 87) | 4px | rgba(0, 0, 0, 0.55) 0px 10px 26px 0px | 0 0 0 0 |
| #tuning .tuning-head | `#tuning .tuning-head` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 11 13 11 13 |
| #tuning .tuning-title | `#tuning .tuning-title` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning .tuning-mark | `#tuning .tuning-mark` | — | **hidden** | · | · | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuningToggle | `#tuningToggle` | — | **hidden** | · | · | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) |  | 3px | none | 4 10 4 10 |
| #tuning .tuning-body | `#tuning .tuning-body` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 14 14 16 14 |
| #tuning .tuning-body .row | `#tuning .tuning-body .row` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning .ai-sep | `#tuning .ai-sep` | — | **hidden** | · | · | cyan | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.34)<br>L 3px rgb(182, 255, 87) | 0px | none | 9 0 0 10 |

**F. Start / title slab**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #overlay | `#overlay` | 0, 0 | 1440 × 810 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(cyan, 0.043) 1px, rgba(0, 0, 0,… |  | 0px | none | 34.56 34.56 34.56 34.56 |
| #overlay .panel.title-screen (title slab) | `#overlay .panel.title-screen` | 330, 105.02 | 780 × 599.97 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(155deg, rgba(9, 20, 36, 0.98), rgba(5, 10,… | T 4px rgb(182, 255, 87)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 4px | rgba(0, 0, 0, 0.8) 0px 40px 100px 0px, … | 0 0 0 0 |
| #overlay .title-hero | `#overlay .title-hero` | 331, 109.02 | 778 × 206.47 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 20 32 14 32 |
| #overlay .brand-line | `#overlay .brand-line` | 363, 129.02 | 714 × 33 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | B 1px rgba(cyan, 0.15) | 0px | none | 0 0 10 0 |
| #overlay .brand-tag | `#overlay .brand-tag` | 608.86, 129.02 | 132.31 × 22 | 10/900 | 2.4px | rgb(6, 33, 12) | rgb(182, 255, 87) |  | 2px | rgba(182, 255, 87, 0.35) 0px 0px 20px 0… | 4 10 4 10 |
| #overlay .brand-ver | `#overlay .brand-ver` | 751.17, 133.02 | 79.95 × 14 | 10/800 | 2px | rgba(150, 205, 230, 0.6) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .title-hero .logo | `#overlay .title-hero .logo` | 363, 172.02 | 714 × 61.47 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .snake-dot | `#overlay .snake-dot` | 554.19, 193.75 | 18 × 18 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(182, 255, 87) |  | 3px | rgba(182, 255, 87, 0.14) 0px 0px 0px 4p… | 0 0 0 0 |
| #panelTitle | `#panelTitle` | 584.19, 172.02 | 301.61 × 61.47 | 58/900 | 2.32px | rgba(0, 0, 0, 0) | lg(100deg, rgb(234, 255, 208), rgb(182, 255, … |  | 0px | none | 0 0 0 0 |
| #overlay .title-sub | `#overlay .title-sub` | 363, 241.48 | 714 × 17 | 13/400 | 2.86px | rgba(196, 228, 244, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .mode-badges | `#overlay .mode-badges` | 363, 268.48 | 714 × 29 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .mode-badges span | `#overlay .mode-badges span` | 539.14, 268.48 | 87.94 × 29 | 11/700 | 0.88px | rgba(206, 234, 250, 0.8) | rgba(cyan, 0.07) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px cyan | 2px | none | 6 12 6 12 |
| #overlay .mode-badges b | `#overlay .mode-badges b` | 554.14, 275.48 | 27.02 × 15 | 11/900 | 0.88px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .player-select | `#overlay .player-select` | 331, 315.48 | 778 × 115 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 12 32 0 32 |
| #overlay .ps-label | `#overlay .ps-label` | 363, 327.48 | 714 × 15 | 11/800 | 2.86px | rgba(150, 205, 230, 0.7) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .ps-btn | `#overlay .ps-btn` | 363, 351.48 | 351 × 79 | 13.3333/400 | normal | rgb(236, 255, 214) | lg(rgba(110, 240, 130, 0.17), rgba(9, 24, 40,… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.14) 0px 0px 26px … | 13 10 14 10 |
| #overlay .ps-btn.active | `#overlay .ps-btn.active` | 363, 351.48 | 351 × 79 | 13.3333/400 | normal | rgb(236, 255, 214) | lg(rgba(110, 240, 130, 0.17), rgba(9, 24, 40,… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.14) 0px 0px 26px … | 13 10 14 10 |
| #overlay .ps-btn b | `#overlay .ps-btn b` | 517.2, 365.48 | 42.58 × 28 | 19/900 | 1.52px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .ps-btn span | `#overlay .ps-btn span` | 505.16, 397.48 | 66.67 × 16 | 11.5/400 | 0.69px | rgba(210, 240, 220, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .panel-actions | `#overlay .panel-actions` | 331, 430.48 | 778 × 233.5 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(5, 10, 20, 0.99) 60%, rgba(5, 1… |  | 0px | none | 12 32 16 32 |
| #overlay .menu-buttons | `#overlay .menu-buttons` | 363, 442.48 | 714 × 54 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #startBtn | `#startBtn` | 363, 442.48 | 391.11 × 54 | 14/900 | 1.4px | rgb(7, 32, 12) | lg(rgb(217, 255, 122), rgb(134, 240, 106) 60%… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.2) 0px 0px 30px 0… | 13 12 13 12 |
| #kbBtn | `#kbBtn` | 764.11, 442.48 | 312.89 × 54 | 14/900 | 1.4px | rgb(216, 244, 255) | lg(rgba(20, 48, 70, 0.9), rgba(9, 24, 40, 0.9… | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 3px rgba(cyan, 0.45)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(4, 14, 26, 0.7) 0px 8px 0px 0px | 13 12 13 12 |
| #panelHint | `#panelHint` | 363, 537.73 | 714 × 18 | 12/400 | 0.32px | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .fineprint | `#overlay .fineprint` | 363, 564.73 | 714 × 47.25 | 10.5/400 | 0.32px | rgba(160, 196, 218, 0.5) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .pad-hints | `#overlay .pad-hints` | 363, 618.98 | 714 × 29 | 10/700 | 0.8px | rgba(190, 220, 238, 0.7) | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.15) | 0px | none | 8 0 0 0 |
| #overlay .rules-details | `#overlay .rules-details` | 363, 669.98 | 714 × 34 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.15) | 0px | none | 0 0 0 0 |

**G. Settlement**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #resultOverlay | `#resultOverlay` | 0, 0 | 1440 × 810 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .result-top | `#resultOverlay .result-top` | 0, 0 | 1440 × 66 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(rgba(4, 9, 18, 0.86) 0px, rgba(4, 9, 18, 0… |  | 0px | none | 6 24 10 24 |
| #resultOverlay .result-headline | `#resultOverlay .result-headline` | 24, 12.69 | 150.7 × 36.63 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .result-headline .logo | `#resultOverlay .result-headline .logo` | 24, 12.69 | 136.7 × 30.63 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultTitle | `#resultTitle` | 52, 12.69 | 108.7 × 30.63 | 26.64/900 | 0.5328px | rgb(244, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultStats | `#resultStats` | — | **hidden** | · | · | rgba(196, 224, 242, 0.7… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .stage-actions | `#resultOverlay .stage-actions` | 1272.09, 6 | 143.91 × 50 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 4 0 0 0 |
| #skipStageBtn | `#skipStageBtn` | 1272.09, 10 | 143.91 × 46 | 13/800 | 1.04px | rgb(223, 246, 255) | rgba(8, 20, 36, 0.92) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 3px rgba(cyan, 0.4)<br>L 1px rgba(cyan, 0.34) | 3px | none | 9 15 9 15 |
| #resultOverlay .result-bottom | `#resultOverlay .result-bottom` | 0, 731 | 1440 × 79 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(rgba(4, 9, 18, 0) 0px, rgba(4, 9, 18, 0.95… |  | 0px | none | 12 0 8 0 |
| #resultRows | `#resultRows` | 226.3, 743 | 987.41 × 0 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultRows .result-row | `#resultRows .result-row` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .result-row.me | `#resultRows .result-row.me` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-rank | `#resultRows .result-row .r-rank` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-name | `#resultRows .result-row .r-name` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-len | `#resultRows .result-row .r-len` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-extra | `#resultRows .result-row .r-extra` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-avatar | `#resultRows .r-avatar` | — | — | — | — | — | — | — | — | — | — |
| #resultOverlay .result-actions | `#resultOverlay .result-actions` | 0, 743 | 1440 × 59 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 10 22 0 22 |
| #againBtn | `#againBtn` | 578.23, 753 | 181.64 × 49 | 16.28/900 | 1.628px | rgb(10, 31, 16) | lg(rgb(212, 255, 122), rgb(134, 240, 106) 60%… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 4px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.2) 0px 0px 30px 0… | 10 30 10 30 |
| #resultOverlay .result-actions .hint | `#resultOverlay .result-actions .hint` | 775.88, 767.5 | 85.89 × 20 | 12/700 | 0.72px | rgba(190, 220, 238, 0.7) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**Pseudo-elements** (this is where the OSD lives)

| pseudo | content | box | opacity | background |
|---|---|---|---|---|
| `body::before (scanlines + vignette)` | `""` | {'w': '1440px', 'h': '810px', 'top': '0px', 'right': '0px', 'bottom':… | 1 | repeating-lg(0deg, rgba(160, 220, 255, 0.024) 0px, rgba(160, 220, 255, 0.024) 1… |
| `body::after (OSD 4-corner brackets)` | `""` | {'w': '1370.91px', 'h': '740.906px', 'top': '34.56px', 'right': '34.5… | 0.55 | lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan),… |
| `#uiBar::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#uiBar::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud .stat::after (data-en watermark)` | `"TIME"` | {'w': 'auto', 'h': 'auto', 'top': '4px', 'right': '8px', 'bottom': 'a… | 1 | none |
| `.stat::after (data-en watermark)` | `"TIME"` | {'w': 'auto', 'h': 'auto', 'top': '4px', 'right': '8px', 'bottom': 'a… | 1 | none |
| `#cam::before` | `""` | {'w': '232.797px', 'h': '129.188px', 'top': '0px', 'right': '0px', 'b… | 1 | none |
| `#pauseStats .stat::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#overlay .panel::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#resultOverlay .result-bottom::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#leaderboard::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#quickPlayBtn::before` | `"A"` | {'w': '22px', 'h': '22px', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | lg(rgb(226, 250, 255), rgb(138, 216, 238)) |

### 4.9 `play` @ 1440×810

In-game @ 1440×810

`body.class = "in-round"` · `data-split = 1` · `game.state = playing` · `--ui-scale = .74`

**A. Panel chrome / OSD / merged HUD bar**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #uiBar (merged HUD bar) | `#uiBar` | 0, 0 | 1440 × 148 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(cyan, 0.043) 1px, rgba(0, 0, 0,… | B 3px cyan | 0px | rgba(0, 0, 0, 0.78) 0px 20px 52px 0px, … | 0 66.6 0 66.6 |
| #uiBar .ui-deco | `#uiBar .ui-deco` | 0, 0 | 1440 × 145 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-energy | `#uiBar .ui-energy` | 0, 0 | 1440 × 6 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(cyan, 0.16) |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-energy i | `#uiBar .ui-energy i` | 1294.61, 0 | 547.19 × 6 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(0, 0, 0, 0), rgb(184, 247, 255… |  | 0px | rgba(cyan, 0.95) 0px 0px 26px 0px | 0 0 0 0 |
| #uiBar .ui-scan | `#uiBar .ui-scan` | 0, 0 | 1440 × 145 | 16/400 | 0.32px | rgb(234, 246, 255) | repeating-lg(0deg, rgba(190, 235, 255, 0.024)… |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-ruler | `#uiBar .ui-ruler` | 66.59, 133 | 1306.81 × 5 | 16/400 | 0.32px | rgb(234, 246, 255) | repeating-lg(90deg, rgba(cyan, 0.4) 0px, rgba… |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-seam | `#uiBar .ui-seam` | 0, 145 | 1440 × 3 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(0, 0, 0, 0), cyan 10%, rgb(230… |  | 0px | rgba(cyan, 0.75) 0px 0px 22px 0px | 0 0 0 0 |
| #uiBar .ui-diamond | `#uiBar .ui-diamond` | 710.81, 126.31 | 18.38 × 18.38 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(230, 251, 255) |  | 0px | cyan 0px 0px 18px 0px | 0 0 0 0 |
| #uiBar .ui-notch.left | `#uiBar .ui-notch.left` | 0, 131 | 30 × 14 | 16/400 | 0.32px | rgb(234, 246, 255) | cyan |  | 0px | none | 0 0 0 0 |
| #uiBar .ui-notch.right | `#uiBar .ui-notch.right` | 1410, 131 | 30 × 14 | 16/400 | 0.32px | rgb(234, 246, 255) | cyan |  | 0px | none | 0 0 0 0 |

**B. Clock, stat cells, rank block**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #hud | `#hud` | 331.5, 17 | 806.59 × 111 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgba(cyan, 0.1), rgba(cyan, 0.01) 6… | L 4px rgb(182, 255, 87) | 0px | none | 0 0 0 0 |
| #hud .stat | `#hud .stat` | 623.58, 11.5 | 226.44 × 122.02 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 17.76 0 17.76 |
| #hud .stat .k (剩余 label) | `#hud .stat .k` | 702.69, 11.5 | 68.2 × 35 | 26.64/700 | 7.4592px | rgba(198, 232, 248, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #timeLeft (clock digits) | `#timeLeft` | 638.44, 45.18 | 196.71 × 89.65 | 88.8/900 | 0.32px | rgb(215, 247, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock | `#rankBlock` | 1151.41, 17 | 222 × 111 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(270deg, rgba(182, 255, 87, 0.09), rgba(0, … | R 4px rgb(182, 255, 87) | 0px | none | 0 5.92 0 28.12 |
| #rankBlock .rank-k | `#rankBlock .rank-k` | 1231.36, 7.48 | 132.14 × 35 | 26.64/700 | 6.3936px | rgba(198, 232, 248, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rank (rank numeral) | `#rank` | 1198.38, 29.77 | 165.13 × 71.05 | 71.04/900 | 0.32px | rgb(255, 154, 114) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock .rank-arrow | `#rankBlock .rank-arrow` | 1154.36, 58.18 | 26.69 × 35 | 26.64/900 | 0.32px | rgb(255, 154, 114) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #rankBlock .rank-total | `#rankBlock .rank-total` | 1259.09, 113.53 | 104.41 × 24 | 17.76/400 | 1.776px | rgba(190, 225, 240, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**C. Mirror box (the camera pane inside the HUD band)**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #cam (mirror box) | `#cam` | 66.59, 5.91 | 236.8 × 133.19 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(4, 11, 20) | T 2px rgba(cyan, 0.55)<br>R 2px rgba(cyan, 0.55)<br>B 2px rgba(cyan, 0.55)<br>L 2px rgba(cyan, 0.55) | 2px | rgba(cyan, 0.06) 0px 0px 0px 6px, rgba(… | 0 0 0 0 |
| #cam .cam-frame | `#cam .cam-frame` | 68.59, 7.91 | 232.8 × 129.19 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #cam .cam-frame i | `#cam .cam-frame i` | 73.59, 12.91 | 22 × 22 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | T 3px cyan<br>L 3px cyan | 0px | none | 0 0 0 0 |
| #cam .cam-rec | `#cam .cam-rec` | 278.39, 16.91 | 14 × 14 | 9/900 | 1.44px | rgb(255, 156, 174) | rgba(0, 0, 0, 0) |  | 50% | none | 0 0 0 0 |
| #cam .cam-tag | `#cam .cam-tag` | — | **hidden** | · | · | rgb(182, 255, 87) | rgba(4, 10, 20, 0.82) | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 1px rgba(182, 255, 87, 0.…<br>L 1px rgba(182, 255, 87, 0.… | 3px | none | 4 8 4 8 |
| #cam .cam-speed | `#cam .cam-speed` | 68.59, 106.02 | 232.8 × 31.08 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(2, 10, 20, 0.95), rgba(2, 10, 2… |  | 0px | none | 0 8.88 0 8.88 |
| #cam .cam-speed-val | `#cam .cam-speed-val` | 77.47, 109.05 | 68.08 × 25 | 19.24/800 | 0.3848px | rgb(220, 248, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #cam .cam-speed-track | `#cam .cam-speed-track` | 152.94, 117.86 | 139.58 × 7.39 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 22, 36, 0.86) | T 1px rgba(cyan, 0.4)<br>R 1px rgba(cyan, 0.4)<br>B 1px rgba(cyan, 0.4)<br>L 1px rgba(cyan, 0.4) | 0px | none | 0 0 0 0 |
| #cam .cam-speed-track i | `#cam .cam-speed-track i` | 153.94, 118.86 | 41.27 × 5.39 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(90deg, rgb(47, 159, 214), cyan 55%, rgb(18… |  | 0px | rgba(cyan, 0.9) 0px 0px 10.36px 0px | 0 0 0 0 |
| #cam .cam-label | `#cam .cam-label` | 68.59, 102.09 | 232.8 × 35 | 10.5/700 | 1.05px | rgb(205, 238, 255) | lg(to top, rgba(8, 3, 16, 0.92), rgba(8, 3, 1… |  | 0px | none | 14 10 7 10 |
| #cam .cam-ready | `#cam .cam-ready` | — | **hidden** | · | · | rgb(234, 246, 255) | lg(rgba(4, 10, 20, 0), rgba(4, 10, 20, 0.88)) |  | 0px | none | 12 0 13 0 |

**D. Status, buttons, key strip, buffs, leaderboard**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #statusbar | `#statusbar` | 1300.64, 34.55 | 104.81 × 36 | 12/800 | 1.2px | rgb(217, 238, 251) | rgba(6, 14, 26, 0.94) | T 1px rgba(cyan, 0.34)<br>R 3px cyan<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.55) 0px 10px 26px 0px | 9 16 9 16 |
| #statusbar .dot | `#statusbar .dot` | 1317.64, 48.55 | 8 × 8 | 12/800 | 1.2px | rgb(217, 238, 251) | rgb(255, 197, 61) |  | 50% | rgba(255, 197, 61, 0.9) 0px 0px 12px 0px | 0 0 0 0 |
| #status (status text) | `#status` | 1333.64, 44.55 | 52.81 × 16 | 12/800 | 1.2px | rgb(217, 238, 251) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #quickPlayBtn | `#quickPlayBtn` | 1272.45, 84.55 | 133 × 42 | 12.5/800 | 1px | rgb(233, 255, 208) | lg(100deg, rgba(9, 26, 32, 0.97), rgba(14, 38… | T 1px rgba(182, 255, 87, 0.…<br>R 3px rgb(182, 255, 87)<br>B 1px rgba(182, 255, 87, 0.…<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(0, 0, 0, 0.55) 0px 8px 24px 0px, r… | 8 15 8 15 |
| #muteBtn | `#muteBtn` | 1159.45, 84.55 | 36 × 36 | 13.3333/400 | normal | cyan | rgba(6, 14, 26, 0.9) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | none | 0 0 0 0 |
| #padBar | `#padBar` | 264.55, 737.45 | 451.17 × 38 | 11/700 | 0.44px | rgba(214, 236, 250, 0.8) | rgba(6, 14, 26, 0.86) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px cyan | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 8 14 8 14 |
| #padBar .keycap | `#padBar .keycap` | 281.55, 746.45 | 57.14 × 20 | 10/900 | 0.6px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) | T 1px rgba(255, 255, 255, 0…<br>R 1px rgba(255, 255, 255, 0…<br>B 1px rgba(255, 255, 255, 0…<br>L 1px rgba(255, 255, 255, 0… | 4px | rgba(0, 0, 0, 0.6) 0px 2px 0px 0px, rgb… | 0 6 0 6 |
| .keycap (generic keycap) | `.keycap` | 156.13, 172.91 | 24.41 × 18 | 11.84/900 | 0.7104px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) | T 1px rgba(255, 255, 255, 0…<br>R 1px rgba(255, 255, 255, 0…<br>B 1px rgba(255, 255, 255, 0…<br>L 1px rgba(255, 255, 255, 0… | 4px | rgba(0, 0, 0, 0.6) 0px 2px 0px 0px, rgb… | 0 6 0 6 |
| #hint | `#hint` | 650.01, 728.45 | 139.98 × 39 | 13/800 | 0.78px | rgb(220, 255, 224) | rgba(6, 14, 26, 0.93) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px rgb(182, 255, 87) | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 10 22 10 22 |
| #buffs | `#buffs` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost (buff chip) | `#buffBoost` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(6, 14, 26, 0.95) | T 1px rgba(255, 213, 74, 0.…<br>R 3px rgba(255, 213, 74, 0.…<br>B 1px rgba(255, 213, 74, 0.…<br>L 1px rgba(255, 213, 74, 0.… | 3px | rgba(0, 0, 0, 0.5) 0px 10px 26px 0px | 7 11 11 11 |
| #buffBoost .buff-name | `#buffBoost .buff-name` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-time | `#buffBoost .buff-time` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-bar | `#buffBoost .buff-bar` | — | **hidden** | · | · | rgb(255, 213, 74) | rgba(255, 255, 255, 0.12) |  | 0px | none | 0 0 0 0 |
| #buffBoost .buff-bar i | `#buffBoost .buff-bar i` | — | **hidden** | · | · | rgb(255, 213, 74) | rgb(255, 213, 74) |  | 2px | none | 0 0 0 0 |
| #leaderboard | `#leaderboard` | 1179.45, 238.55 | 226 × 153 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 14, 26, 0.95) | T 3px cyan<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.6) 0px 16px 40px 0px | 11 12 10 12 |
| #leaderboard .lb-head | `#leaderboard .lb-head` | 1192.45, 252.55 | 200 × 16 | 10/700 | 1.8px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #leaderboard .lb-head span | `#leaderboard .lb-head span` | 1192.45, 252.55 | 98.36 × 16 | 10/700 | 1.8px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbTime | `#lbTime` | 1366.81, 252.55 | 25.64 × 16 | 12/700 | normal | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows | `#lbRows` | 1192.45, 275.55 | 200 × 105 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-row | `#lbRows .lb-row` | 1192.45, 275.55 | 200 × 24 | 12/400 | 0.32px | rgb(220, 234, 245) | rgba(0, 0, 0, 0) |  | 2px | none | 4 6 4 6 |
| #lbRows .lb-row.me | `#lbRows .lb-row.me` | 1192.45, 356.55 | 200 × 24 | 12/800 | 0.32px | rgb(234, 255, 210) | rgba(182, 255, 87, 0.16) | L 3px rgb(182, 255, 87) | 2px | none | 4 6 4 6 |
| #lbRows .lb-rank | `#lbRows .lb-row .lb-rank` | 1198.45, 279.55 | 16 × 16 | 12/900 | 0.32px | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-name | `#lbRows .lb-row .lb-name` | 1236.45, 279.55 | 111.34 × 16 | 12/400 | 0.32px | rgb(220, 234, 245) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #lbRows .lb-len | `#lbRows .lb-row .lb-len` | 1354.8, 279.55 | 31.66 × 16 | 12/800 | 0.32px | rgb(220, 234, 245) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**E. Pause / OPTIONS layer**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #pauseScrim | `#pauseScrim` | 0, 148 | 1440 × 662 | 16/400 | 0.32px | rgb(234, 246, 255) | radial-gradient(at 50% 0%, rgba(6, 16, 30, 0.… |  | 0px | none | 16.28 0 0 0 |
| #pauseScrim .pause-scrim-inner | `#pauseScrim .pause-scrim-inner` | 596.92, 164.27 | 246.16 × 104 | 16/400 | 0.32px | rgb(223, 244, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim .pause-kicker | `#pauseScrim .pause-kicker` | 598.41, 164.27 | 243.19 × 24 | 17.76/800 | 4.9728px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim strong | `#pauseScrim .pause-scrim-inner strong` | 596.92, 194.27 | 246.16 × 43 | 32.56/900 | 2.6048px | rgb(223, 244, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseScrim .pause-tip | `#pauseScrim .pause-tip` | 629.03, 243.27 | 181.94 × 25 | 19.24/400 | 0.32px | rgba(200, 230, 245, 0.7… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats | `#pauseStats` | 511.68, 235.31 | 416.64 × 143.08 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 16, 29, 0.97) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 4px cyan | 4px | rgba(0, 0, 0, 0.7) 0px 18px 48px 0px | 11.84 14.8 11.84 14.8 |
| #pauseStats .stat | `#pauseStats .stat` | 577.95, 248.14 | 88.8 × 82.06 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(12, 28, 46, 0.7) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.35) 0px 8px 28px 0px, r… | 7.4 10.36 7.4 10.36 |
| #pauseStats .stat .k | `#pauseStats .stat .k` | 589.3, 256.53 | 66.08 × 27 | 20.72/600 | 2.9008px | rgba(190, 214, 238, 0.6… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats .stat .v | `#pauseStats .stat .v` | 589.3, 284.53 | 66.08 × 37.28 | 35.52/900 | 0.32px | rgb(242, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #pauseStats .legacy-stat (dead weight) | `#pauseStats .legacy-stat` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(12, 28, 46, 0.7) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(0, 0, 0, 0.35) 0px 8px 28px 0px, r… | 7.4 10.36 7.4 10.36 |
| #pauseBuff | `#pauseBuff` | 530.48, 340.56 | 382.05 × 25 | 19.24/700 | 1.1544px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning (settings drawer) | `#tuning` | 15.97, 158.36 | 240.72 × 47.09 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(6, 14, 26, 0.95) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 3px rgb(182, 255, 87) | 4px | rgba(0, 0, 0, 0.55) 0px 10px 26px 0px | 0 0 0 0 |
| #tuning .tuning-head | `#tuning .tuning-head` | 18.97, 159.36 | 236.72 × 45.09 | 16.28/800 | 2.2792px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 8.88 13.32 8.88 13.32 |
| #tuning .tuning-title | `#tuning .tuning-title` | 32.28, 171.41 | 114.97 × 21 | 16.28/800 | 2.2792px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning .tuning-mark | `#tuning .tuning-mark` | 32.28, 174.91 | 8.5 × 14 | 10.36/800 | 2.2792px | cyan | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuningToggle | `#tuningToggle` | 189.41, 168.23 | 52.97 × 27.34 | 13.32/800 | 1.332px | rgb(4, 16, 28) | lg(rgb(226, 250, 255), rgb(138, 216, 238)) |  | 3px | none | 5.18 11.84 5.18 11.84 |
| #tuning .tuning-body | `#tuning .tuning-body` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 14 14 16 14 |
| #tuning .tuning-body .row | `#tuning .tuning-body .row` | — | **hidden** | · | · | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #tuning .ai-sep | `#tuning .ai-sep` | — | **hidden** | · | · | cyan | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.34)<br>L 3px rgb(182, 255, 87) | 0px | none | 9 0 0 10 |

**F. Start / title slab**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #overlay | `#overlay` | 0, 0 | 1440 × 810 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(cyan, 0.043) 1px, rgba(0, 0, 0,… |  | 0px | none | 34.56 34.56 34.56 34.56 |
| #overlay .panel.title-screen (title slab) | `#overlay .panel.title-screen` | 330, 120.14 | 780 × 569.72 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(155deg, rgba(9, 20, 36, 0.98), rgba(5, 10,… | T 4px rgb(182, 255, 87)<br>R 1px rgba(cyan, 0.34)<br>B 1px rgba(cyan, 0.34)<br>L 1px rgba(cyan, 0.34) | 4px | rgba(0, 0, 0, 0.8) 0px 40px 100px 0px, … | 0 0 0 0 |
| #overlay .title-hero | `#overlay .title-hero` | 331, 124.14 | 778 × 206.47 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 20 32 14 32 |
| #overlay .brand-line | `#overlay .brand-line` | 363, 144.14 | 714 × 33 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | B 1px rgba(cyan, 0.15) | 0px | none | 0 0 10 0 |
| #overlay .brand-tag | `#overlay .brand-tag` | 608.86, 144.14 | 132.31 × 22 | 10/900 | 2.4px | rgb(6, 33, 12) | rgb(182, 255, 87) |  | 2px | rgba(182, 255, 87, 0.35) 0px 0px 20px 0… | 4 10 4 10 |
| #overlay .brand-ver | `#overlay .brand-ver` | 751.17, 148.14 | 79.95 × 14 | 10/800 | 2px | rgba(150, 205, 230, 0.6) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .title-hero .logo | `#overlay .title-hero .logo` | 363, 187.14 | 714 × 61.47 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .snake-dot | `#overlay .snake-dot` | 554.19, 208.88 | 18 × 18 | 16/400 | 0.32px | rgb(234, 246, 255) | rgb(182, 255, 87) |  | 3px | rgba(182, 255, 87, 0.14) 0px 0px 0px 4p… | 0 0 0 0 |
| #panelTitle | `#panelTitle` | 584.19, 187.14 | 301.61 × 61.47 | 58/900 | 2.32px | rgba(0, 0, 0, 0) | lg(100deg, rgb(234, 255, 208), rgb(182, 255, … |  | 0px | none | 0 0 0 0 |
| #overlay .title-sub | `#overlay .title-sub` | 363, 256.61 | 714 × 17 | 13/400 | 2.86px | rgba(196, 228, 244, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .mode-badges | `#overlay .mode-badges` | 363, 283.61 | 714 × 29 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .mode-badges span | `#overlay .mode-badges span` | 539.14, 283.61 | 87.94 × 29 | 11/700 | 0.88px | rgba(206, 234, 250, 0.8) | rgba(cyan, 0.07) | T 1px rgba(cyan, 0.15)<br>R 1px rgba(cyan, 0.15)<br>B 1px rgba(cyan, 0.15)<br>L 3px cyan | 2px | none | 6 12 6 12 |
| #overlay .mode-badges b | `#overlay .mode-badges b` | 554.14, 290.61 | 27.02 × 15 | 11/900 | 0.88px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .player-select | `#overlay .player-select` | 331, 330.61 | 778 × 115 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 12 32 0 32 |
| #overlay .ps-label | `#overlay .ps-label` | 363, 342.61 | 714 × 15 | 11/800 | 2.86px | rgba(150, 205, 230, 0.7) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .ps-btn | `#overlay .ps-btn` | 363, 366.61 | 351 × 79 | 13.3333/400 | normal | rgb(236, 255, 214) | lg(rgba(110, 240, 130, 0.17), rgba(9, 24, 40,… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.14) 0px 0px 26px … | 13 10 14 10 |
| #overlay .ps-btn.active | `#overlay .ps-btn.active` | 363, 366.61 | 351 × 79 | 13.3333/400 | normal | rgb(236, 255, 214) | lg(rgba(110, 240, 130, 0.17), rgba(9, 24, 40,… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.14) 0px 0px 26px … | 13 10 14 10 |
| #overlay .ps-btn b | `#overlay .ps-btn b` | 517.2, 380.61 | 42.58 × 28 | 19/900 | 1.52px | rgb(182, 255, 87) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .ps-btn span | `#overlay .ps-btn span` | 505.16, 412.61 | 66.67 × 16 | 11.5/400 | 0.69px | rgba(210, 240, 220, 0.8… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .panel-actions | `#overlay .panel-actions` | 331, 445.61 | 778 × 203.25 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(0deg, rgba(5, 10, 20, 0.99) 60%, rgba(5, 1… |  | 0px | none | 12 32 16 32 |
| #overlay .menu-buttons | `#overlay .menu-buttons` | 363, 457.61 | 714 × 54 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #startBtn | `#startBtn` | 363, 457.61 | 391.11 × 54 | 14/900 | 1.4px | rgb(7, 32, 12) | lg(rgb(217, 255, 122), rgb(134, 240, 106) 60%… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 3px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.2) 0px 0px 30px 0… | 13 12 13 12 |
| #kbBtn | `#kbBtn` | 764.11, 457.61 | 312.89 × 54 | 14/900 | 1.4px | rgb(216, 244, 255) | lg(rgba(20, 48, 70, 0.9), rgba(9, 24, 40, 0.9… | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 3px rgba(cyan, 0.45)<br>L 1px rgba(cyan, 0.34) | 3px | rgba(4, 14, 26, 0.7) 0px 8px 0px 0px | 13 12 13 12 |
| #panelHint | `#panelHint` | 363, 522.61 | 714 × 18 | 12/400 | 0.32px | rgb(255, 213, 74) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .fineprint | `#overlay .fineprint` | 363, 549.61 | 714 × 47.25 | 10.5/400 | 0.32px | rgba(160, 196, 218, 0.5) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #overlay .pad-hints | `#overlay .pad-hints` | 363, 603.86 | 714 × 29 | 10/700 | 0.8px | rgba(190, 220, 238, 0.7) | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.15) | 0px | none | 8 0 0 0 |
| #overlay .rules-details | `#overlay .rules-details` | 363, 654.86 | 714 × 34 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) | T 1px rgba(cyan, 0.15) | 0px | none | 0 0 0 0 |

**G. Settlement**

| element | selector | x, y | w × h | fs/fw | ls | color | bg | border | r | shadow | pad |
|---|---|---|---|---|---|---|---|---|---|---|---|
| #resultOverlay | `#resultOverlay` | 0, 0 | 1440 × 810 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .result-top | `#resultOverlay .result-top` | 0, 0 | 1440 × 66 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(rgba(4, 9, 18, 0.86) 0px, rgba(4, 9, 18, 0… |  | 0px | none | 6 24 10 24 |
| #resultOverlay .result-headline | `#resultOverlay .result-headline` | 24, 12.69 | 150.7 × 36.63 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .result-headline .logo | `#resultOverlay .result-headline .logo` | 24, 12.69 | 136.7 × 30.63 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultTitle | `#resultTitle` | 52, 12.69 | 108.7 × 30.63 | 26.64/900 | 0.5328px | rgb(244, 251, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultStats | `#resultStats` | — | **hidden** | · | · | rgba(196, 224, 242, 0.7… | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultOverlay .stage-actions | `#resultOverlay .stage-actions` | 1272.09, 6 | 143.91 × 50 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 4 0 0 0 |
| #skipStageBtn | `#skipStageBtn` | 1272.09, 10 | 143.91 × 46 | 13/800 | 1.04px | rgb(223, 246, 255) | rgba(8, 20, 36, 0.92) | T 1px rgba(cyan, 0.34)<br>R 1px rgba(cyan, 0.34)<br>B 3px rgba(cyan, 0.4)<br>L 1px rgba(cyan, 0.34) | 3px | none | 9 15 9 15 |
| #resultOverlay .result-bottom | `#resultOverlay .result-bottom` | 0, 731 | 1440 × 79 | 16/400 | 0.32px | rgb(234, 246, 255) | lg(rgba(4, 9, 18, 0) 0px, rgba(4, 9, 18, 0.95… |  | 0px | none | 12 0 8 0 |
| #resultRows | `#resultRows` | 226.3, 743 | 987.41 × 0 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |
| #resultRows .result-row | `#resultRows .result-row` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .result-row.me | `#resultRows .result-row.me` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-rank | `#resultRows .result-row .r-rank` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-name | `#resultRows .result-row .r-name` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-len | `#resultRows .result-row .r-len` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-extra | `#resultRows .result-row .r-extra` | — | — | — | — | — | — | — | — | — | — |
| #resultRows .r-avatar | `#resultRows .r-avatar` | — | — | — | — | — | — | — | — | — | — |
| #resultOverlay .result-actions | `#resultOverlay .result-actions` | 0, 743 | 1440 × 59 | 16/400 | 0.32px | rgb(234, 246, 255) | rgba(0, 0, 0, 0) |  | 0px | none | 10 22 0 22 |
| #againBtn | `#againBtn` | 578.23, 753 | 181.64 × 49 | 16.28/900 | 1.628px | rgb(10, 31, 16) | lg(rgb(212, 255, 122), rgb(134, 240, 106) 60%… | T 1px rgba(182, 255, 87, 0.…<br>R 1px rgba(182, 255, 87, 0.…<br>B 4px rgb(95, 191, 58)<br>L 1px rgba(182, 255, 87, 0.… | 3px | rgba(110, 240, 130, 0.2) 0px 0px 30px 0… | 10 30 10 30 |
| #resultOverlay .result-actions .hint | `#resultOverlay .result-actions .hint` | 775.88, 767.5 | 85.89 × 20 | 12/700 | 0.72px | rgba(190, 220, 238, 0.7) | rgba(0, 0, 0, 0) |  | 0px | none | 0 0 0 0 |

**Pseudo-elements** (this is where the OSD lives)

| pseudo | content | box | opacity | background |
|---|---|---|---|---|
| `body::before (scanlines + vignette)` | `""` | {'w': '1440px', 'h': '810px', 'top': '0px', 'right': '0px', 'bottom':… | 1 | repeating-lg(0deg, rgba(160, 220, 255, 0.024) 0px, rgba(160, 220, 255, 0.024) 1… |
| `body::after (OSD 4-corner brackets)` | `""` | {'w': '1370.91px', 'h': '740.906px', 'top': '34.56px', 'right': '34.5… | 0.55 | lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan), lg(cyan, cyan),… |
| `#uiBar::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#uiBar::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#hud .stat::after (data-en watermark)` | `"TIME"` | {'w': 'auto', 'h': 'auto', 'top': '4px', 'right': '8px', 'bottom': 'a… | 1 | none |
| `.stat::after (data-en watermark)` | `"TIME"` | {'w': 'auto', 'h': 'auto', 'top': '4px', 'right': '8px', 'bottom': 'a… | 1 | none |
| `#cam::before` | `""` | {'w': '232.797px', 'h': '129.188px', 'top': '0px', 'right': '0px', 'b… | 1 | none |
| `#pauseStats .stat::after` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#overlay .panel::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#resultOverlay .result-bottom::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#leaderboard::before` | `none` | {'w': 'auto', 'h': 'auto', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | none |
| `#quickPlayBtn::before` | `"A"` | {'w': '22px', 'h': '22px', 'top': 'auto', 'right': 'auto', 'bottom': … | 1 | lg(rgb(226, 250, 255), rgb(138, 216, 238)) |

---

## 5. What exists, what does not

### 5.1 `querySelectorAll` probe counts

Counts are `document.querySelectorAll(sel).length`. A name that is 0 in *both*
the title and the pause state does not exist in the shipped build at all.

| selector | title | pause | reading |
|---|---|---|---|
| `.time` | 0 | 0 | **dead name** |
| `#time` | 0 | 0 | **dead name** |
| `.clock` | 0 | 0 | **dead name** |
| `#clock` | 0 | 0 | **dead name** |
| `.minimap` | 0 | 0 | **dead name** |
| `#minimap` | 0 | 0 | **dead name** |
| `.map` | 0 | 0 | **dead name** |
| `.stat-card` | 0 | 0 | **dead name** |
| `.stats` | 0 | 0 | **dead name** |
| `.hud-bar` | 0 | 0 | **dead name** |
| `.hud` | 0 | 0 | **dead name** |
| `.card` | 0 | 0 | **dead name** |
| `.panel` | 1 | 1 | alive |
| `.osd` | 0 | 0 | **dead name** |
| `.osd-bracket` | 0 | 0 | **dead name** |
| `.bracket` | 0 | 0 | **dead name** |
| `.scanline` | 0 | 0 | **dead name** |
| `.scanlines` | 0 | 0 | **dead name** |
| `.watermark` | 0 | 0 | **dead name** |
| `.rank-display` | 0 | 0 | **dead name** |
| `.rank` | 0 | 0 | **dead name** |
| `.title` | 0 | 0 | **dead name** |
| `.settle-row` | 0 | 0 | **dead name** |
| `.result-card` | 0 | 0 | **dead name** |
| `.result-tile` | 0 | 0 | **dead name** |
| `.chip` | 0 | 0 | **dead name** |
| `.buff-chip` | 2 | 2 | alive |
| `.pause-panel` | 0 | 0 | **dead name** |
| `.lb-row` | 0 | 3 | appears only in-round |
| `.lb` | 0 | 0 | **dead name** |
| `.keycap` | 11 | 11 | alive |
| `.ui-notch` | 2 | 2 | alive |
| `.ui-diamond` | 1 | 1 | alive |
| `.ui-seam` | 1 | 1 | alive |
| `.ui-ruler` | 1 | 1 | alive |
| `.ui-scan` | 1 | 1 | alive |
| `.ui-energy` | 1 | 1 | alive |
| `[data-en]` | 4 | 4 | alive |
| `.legacy-stat` | 2 | 2 | alive |
| `#score` | 1 | 1 | alive |
| `#best` | 1 | 1 | alive |
| `#leaderboard` | 1 | 1 | alive |
| `#pauseStats` | 1 | 1 | alive |
| `.split-only` | 2 | 2 | alive |
| `#cam2` | 1 | 1 | alive |
| `#rankBlock2` | 1 | 1 | alive |

### 5.2 Elements that hide *themselves*

Only elements that introduce the hiding with their **own** computed style are
listed. Descendants of a hidden ancestor are deliberately not repeated (otherwise
every `#resultOverlay` child would appear as "hidden" because the overlay is).

| element | hidden in | its own computed value |
|---|---|---|
| `#rankBlock .rank-arrow` | title, ready, settle, split2p, title@1440 | `opacity:0` |
| `#cam .cam-tag` | title, ready, play, pause, title@1440, play@1440 | `display:none` |
| `#cam .cam-speed` | title, split2p, title@1440 | `opacity:0` |
| `#cam .cam-label` | title, ready, play, pause, split2p, split2p-play, title@1440, play@1440 | `opacity:0` |
| `#cam .cam-ready` | title, ready, play, pause, split2p, split2p-play, title@1440, play@1440 | `display:none` |
| `#hint` | title, ready, play, pause, settle, split2p, split2p-play, title@1440, play@1440 | `opacity:0` |
| `#buffs` | title, ready, play, pause, settle, split2p, split2p-play, title@1440, play@1440 | `display:none` |
| `#leaderboard` | title, ready, play, settle, split2p, split2p-play, title@1440, play@1440 | `display:none` |
| `#pauseScrim` | title, ready, play, settle, split2p, split2p-play, title@1440, play@1440 | `visibility:hidden, opacity:0` |
| `#pauseStats` | title, ready, play, settle, split2p, split2p-play, title@1440, play@1440 | `opacity:0` |
| `#tuning` | title, settle, split2p, title@1440 | `display:none` |
| `#resultOverlay` | title, ready, play, pause, split2p, split2p-play, title@1440, play@1440 | `visibility:hidden, opacity:0` |
| `#statusbar` | ready, play, pause, settle, split2p-play, play@1440 | `opacity:0` |
| `#quickPlayBtn` | ready, play, pause, settle, split2p-play, play@1440 | `opacity:0` |
| `#muteBtn` | ready, play, pause, settle, split2p-play, play@1440 | `opacity:0` |
| `#padBar` | ready, play, pause, settle, split2p-play, play@1440 | `opacity:0` |
| `#tuning .tuning-body` | ready, play, split2p-play, play@1440 | `display:none` |
| `#overlay` | ready, play, pause, settle, split2p-play, play@1440 | `visibility:hidden, opacity:0` |
| `#pauseStats .legacy-stat` | pause | `display:none` |
| `#uiBar` | settle | `opacity:0` |
| `#skipStageBtn` | settle | `opacity:0` |

### 5.3 Radius audit — every visible `border-radius` above 3 px

| element | state | radius |
|---|---|---|
| `#padBar .keycap` | title | 4px |
| `.keycap` | title | 4px |
| `#pauseStats` | title | 4px |
| `#tuning` | title | 4px |
| `#overlay .panel.title-screen` | title | 4px |

---

## 6. Where the shipped skin differs from what `ART-DIFF.md` assumed

`ART-DIFF.md` is the existing audit. Its **palette** conclusions hold up. Its
**geometry** does not: it normalised everything to "CSS px at 1440×810" (§0 of
that doc) and read the big numbers off `20-bigmap.png`, a capture that is not the
shipped layout. Each row below is `ART-DIFF.md`'s claimed value vs the value
measured here.

> **Mind the anchor viewport.** `ART-DIFF.md` anchors on 1440×810, where the
> shipped skin runs at `--ui-scale: .74`. This document anchors on **1920×1080**
> (`--ui-scale: 1`), which is the Godot design canvas. The relation is
> `1440 value = 1920 value × .74`. Never compare a 1440 figure from that doc with
> a 1920 figure from this one.

### 6.1 The big three — clock, rank, cell (the "two analyses disagree" case)

| what | `ART-DIFF.md` | measured @1920 | measured @1440 | verdict |
|---|---|---|---|---|
| clock digits | "≈ **60 px** measured" (§2.4, §5 step 7) | **120 px** / 900 | 88.8 px | ✗ 2× too small at 1920, and 1.5× too small even at its own 1440 anchor |
| rank numeral `n / 8` | "≈ **40 px**" | **96 px** / 900 | 71.04 px | ✗ 2.4× too small |
| HUD cell box | "cell **94 × ~52** CSS, pad `8/17/9`" | **305.58 × 164.59**, pad `0/24/0/24` | 226.44 × 122.02, pad `0/17.76` | ✗ cell is 3.2× wider and 3.2× taller |
| HUD cell label | "label **10 px** `.22em`" | **36 px** / 700, ls 10.08 (= **.28em**) | 26.64 px | ✗ |
| HUD cell value | "value **30 px** `#f2fbff` + cyan glow" | **120 px** / 900, `rgb(215,247,255)`, glow `rgba(cyan,.62) 0 0 38px, rgba(cyan,.85) 0 0 10px` | 88.8 px | ✗ |
| HUD strip | "`r4`, `border-left:4px #b6ff57`, `lg(100deg,rgba(6,14,26,.97),…)`" | **radius 0**, `borderLeft 0`, bg = 1 px cyan grid + vertical `rgb(12,29,48)`→`rgb(9,21,36) 58%`→`rgb(5,12,22)`, plus a 3 px cyan bottom seam via `box-shadow` | same (radius/edges do not scale) | ✗ **and** the 4 px lime left edge is on `#hud`, not on the bar |
| HUD bar height | not stated | **200 px**, full-bleed 1920 wide | 148 px | new |
| `剩余` label | "**11 px** `.18em` dim" | **36 px** / 700 / 10.08 px (**0.28em**) | 26.64 px | ✗ 3.3× |
| `我的名次` label | not sized | **36 px** / 700 / 8.64 px (0.24em) | 26.64 px | new |
| `共 8 位玩家` | "**12 px**" | **24 px**, ls 2.4 | 17.76 px | ✗ 2× |
| diamond glyph | "a small diamond glyph under the colon" | real: `.ui-diamond` **13 × 13** rotated 45° (bbox 18.38), `rgb(230,251,255)`, `box-shadow: cyan 0 0 18px` — a DOM div, not a text glyph | same | ✔ exists |
| clock glow | "cyan/white glow halo" | ✔ two-stop cyan glow (`0 0 38px` @ .62 + `0 0 10px` @ .85) | same | ✔ |

**The disagreement is now settled: the web clock is 120 px, not 60.** ART-DIFF's
Godot-side target ("36 CSS = 48 design") is therefore **2.4× too small**, and the
Godot port's invented 208×96 clock card + underline progress bar has no
counterpart on the web at all (the web clock sits in a 1064 × 150 cell with a
4 px lime left edge and no underline).

### 6.2 Chrome that `ART-DIFF.md` got right

Confirmed exactly, no action needed beyond the radius sweep it already lists:

| element | confirmed computed value |
|---|---|
| title slab | radius **4**, `border-top 4px rgb(182,255,87)`, `lg(155deg, rgba(9,20,36,.98), rgba(5,10,20,.99))`, shadow `rgba(0,0,0,.8) 0 40px 100px, rgba(cyan,.12) 0 0 60px` — **and it is 780 × 569.72** (ART-DIFF had no size) |
| meta badge chips | 11 px / 700, padding 6/12, radius **2**, `border-left 3px` cyan, bg `rgba(cyan,.07)` |
| mode cards `.ps-btn` | radius **3**, label **19/900**, sub **11.5**, selected `rgba(182,255,87,.68)` + lime inset — but **351 × 79**, not "~390×70" |
| `#statusbar` | radius **3**, `border-right 3px rgb(86,232,255)`, 12/800, ls 1.2 px (= .1em) |
| buff chip | radius **3**, `border-right 3px` in the buff colour; `.buff-bar` height **4**, radius **0** |
| leaderboard | radius **3**, `border-top 3px rgb(86,232,255)` — see 6.4 for the width trap |
| OSD | arms **30 × 2** px, inset `var(--safe)` = **44 px** @1920, opacity **.55**; vignette `46% → 100% rgba(1,3,9,.62)`; scanlines `1 px / 4 px` — but alpha is **.024**, not .022 |
| pause drawer `#tuning` | radius **4**, `border-left 3px rgb(86,232,255)`, `lg(155deg, rgba(8,17,31,.98), rgba(5,11,22,.98))` — but width **420**, not 312 |

### 6.3 Names that no longer exist, or that never paint

Probe counts are `document.querySelectorAll(sel).length`, run on both the title
and the pause state. Full table in §5.1.

| name | status | what it actually is |
|---|---|---|
| `.time`, `#time`, `.clock`, `#clock` | **0 matches — dead** | the clock is `#timeLeft`, a `.stat .v.accent` inside `#hud` |
| `.minimap`, `#minimap`, `.map` | **0 matches — dead** | **there is no minimap in the DOM.** It is painted on the canvas (`render.js`), so it has *no computed style and no CSS radius*. ART-DIFF's "minimap r12 glass plate" cannot be verified from CSS — check the canvas code, not this document |
| `.stat-card`, `.hud-bar`, `.hud`, `.card`, `.osd`, `.osd-bracket`, `.bracket`, `.scanline`, `.scanlines`, `.watermark`, `.rank-display`, `.rank`, `.chip`, `.pause-panel`, `.lb`, `.title`, `.result-card`, `.result-tile`, `.settle-row` | **0 matches — dead** | names from the purple layer, or invented in prose. The live equivalents are `.stat`, `.lb-row`, `.buff-chip`, `.keycap`, `.panel` |
| `[data-en]` | 4 matches, but the watermark **never paints** | `#hud .stat::after` resolves `content: "TIME"` at font-size **8 px**, then is killed by `#hud .stat::after { display: none }`; `#pauseStats .stat::after` has **no `content` at all** (`content: none`). **Do not add an 8 px watermark for parity — the web does not show one.** |
| `.legacy-stat` | 2 matches, hidden | `#score` / `#best` cards kept only so old automation can still read the nodes |
| `.panel` | 1 match | the title slab only; there is no reusable panel class |
| `.lb-row` | alive, **in-round only** | rows are built by JS; 0 at the title, 3–4 in-round |
| `.ui-notch`, `.ui-diamond`, `.ui-seam`, `.ui-ruler`, `.ui-scan`, `.ui-energy` | alive (2/1/1/1/1/1) | the band's decor layer — this is the real "panel chrome / dividers / watermarks" set |

### 6.4 Layout facts `ART-DIFF.md` did not have

- **The band split.** `#uiBar` is a **full-bleed 200 px band, radius 0**;
  `#arena` starts at y=200 and is 1920×880; the canvas backing store is
  **1920×880, not 1920×1080**. The page's own `__poseSnake.arenaLayout` reports
  `{uiH:200, arenaTop:200, arenaW:1920, arenaH:880, viewW:1920, viewH:880}`.
- **1P band geometry** (measured x / w): `#cam` **x=90, 320 × 180** (y=8.5);
  `#hud` **x=448, 1064 × 150**; `#rankBlock` **x=1530, 300 × 150**;
  padding `0 90`; the cam→hud gap is **38 px**, the hud→rank gap **18 px**.
- **2P band geometry**: `grid-template-columns: 268px 250px 716px 250px 268px`,
  `column-gap: 14px`, `padding: 0 56px` → 268+250+716+250+268 + 4×14 + 112 = **1920
  exactly**. Clock **96 px**, rank **66 px**, cam **268 × 150.75**, and cam2's
  corner brackets flip to `#FF7AD9` (2P magenta) instead of cyan.
- **The lime edge is not on the bar.** `#hud` carries
  `border-left: 4px solid rgb(182,255,87)` — at x=448, i.e. a third of the way in,
  not at the screen edge.
- **The bar's bottom edge** is a **3 px cyan seam**, painted twice:
  `#uiBar` `box-shadow: rgba(0,0,0,.78) 0 20px 52px, rgba(86,232,255,.22) 0 3px 0 0`,
  and a `.ui-seam` div 3 px tall (`transparent → cyan 10% → rgb(230,251,255) 50% → cyan 90% → transparent`).
- **Leaderboard width trap.** Base width is **226** but its `opacity` is **0**
  in-round — it is only visible under `body.pause-open`, where it is
  **340 × 213**. So "226" is a number nobody ever sees; use 340.
- **The pause layer is not a modal.** `#pauseScrim` has
  `background-color: rgba(0,0,0,0)` (it is a text block, not a scrim); kicker
  **24 px / .28em** cyan; headline **44 px / 900**; `#pauseStats` is a
  **561.28 × 193.39** strip, radius 4, pad-left 20, whose cells are
  **120 × 110.39** with `border-left 1px rgba(cyan,.34)`, radius 3.
- **Settlement returns to full-bleed.** `body.result-mode` moves `#arena` to
  `top:0`, z-index 60, so the canvas is 1920×1080 again. `.result-top` is only
  **66 px** tall, `.result-bottom` **176 px**; the 8 rows are **164.56 × 92** with
  a **4 px top border in the lane colour**; `#resultRows` = **1316.53 px**
  (= 68.57 % of 1920).
- **The key strip is the one thing that does not scale**: `#padBar` is **11 px in
  both viewports** (ratio 1.000) while everything else is ×.74 — and it is
  `opacity: 0` in-round anyway.

### 6.5 What this means for the Godot port

1. **Take §3 as Godot design px directly.** 1920×1080 canvas, design px = CSS px.
   Do not apply ART-DIFF's ×0.75 to these numbers — that factor only exists
   because it compared a 1440 web capture to a 1920 Godot canvas.
2. **Radius scale:** `4` panels/menus/pause strip/cells-with-accent, `3`
   chips/cards/buttons/rows/status, `2` meta badges, `0` HUD band, buff bars,
   `#resultRows` and its rows.
3. **The clock is the headline number: 120 px / 900 / line-height .98 /
   letter-spacing 0.32 px / `rgb(215,247,255)` / two-stop cyan glow.** Its label
   is 36 px / 700 / 0.28em. Anything near "36 CSS (48 design)" is 2.5× too small.
4. **Draw the HUD band as one full-bleed 200 px strip with radius 0 and a 3 px
   cyan bottom seam**, not as four rounded cards.
5. **Do not add an 8 px `data-en` watermark** (§6.3) and **do not add a minimap
   radius from this document** — the web minimap lives in canvas code.

---

## 7. Reachability, and how honest each capture is

| target | status | how it was reached |
|---|---|---|
| `web-title-1920.png` | ✅ | load, wait for `#overlay` |
| `web-ready-1920.png` | ✅ **with a caveat (7.1)** | in-round HUD with the world reset to `state='ready'` via `setRoundDuration(120)` |
| `web-play-1920.png` | ✅ | click `#kbBtn` = 「先用方向键玩」 (keyboard path, no camera), then 2.4 s of real countdown |
| `web-pause-1920.png` | ✅ | `setPauseOpen(true)`, identical to pressing **O** (`body.pause-open`) |
| `web-settle-1920.png` | ✅ **with a caveat (7.2)** | shortened the real round timer to 2.0 s → real `finishRound()`/`showResult()` → clicked the real 「跳过演出」 |
| `web-split2p-1920.png` | ✅ | `setPlayers(2)` on the title screen |
| `web-split2p-play-1920.png` | ✅ (bonus, not requested) | then `#kbBtn`; verified 2 players + 6 AI = 8 snakes |
| `web-title-1440.png`, `web-play-1440.png` | ✅ | `Emulation.setDeviceMetricsOverride` 1440×810, fresh load |

Everything the brief asked for was reachable. Two of them need a footnote.

### 7.1 `ready` is the in-round HUD with a frozen world — not the raise-your-hand screen

The brief expected `web-ready` to be the pre-round "ready" screen. On the **web**
there is no such distinct screen:

- `#kbBtn` / `#startBtn` → `startGame()` → `game.start()`, which sets
  `state='playing'` **immediately**. `state==='ready'` only exists *before* the
  first start (it is the constructor default and what `game.reset()` restores).
- The 举手准备 layer (`.cam-ready`) needs `poseReady && started && state==='ready'`.
  Headless has a fake camera and no person, so `poseReady` never arms; `.cam-ready`
  measured **0 × 0 / hidden** in the ready capture.

So the capture shows the honest thing that *is* reachable: the **in-round HUD
band with a live 2:00 clock and a frozen arena** (`body.in-round`, `state='ready'`,
`roundLeft=120`). If the Godot reviewer needs the raise-to-start overlay, that is a
**Godot-only screen** (the port has a real ready phase); the web has nothing to
compare it against.

### 7.2 Settlement was not a real 2-minute round

The round timer was shortened — the brief explicitly allowed this — by writing
`__poseSnake.game.roundLeft = 2.0` and letting the **real** countdown expire. What
followed was the genuine code path: `game.finishRound()` → `showResult()` →
`resultStage` growth → the real `#skipStageBtn` ("跳过演出 ›") clicked by the tool.

- The **UI** in `web-settle-1920.png` is authentic and unmodified.
- The **numbers on it** are not: a ~4 s round produced lengths of 18–25 节 and a
  "第 7 名". Do **not** read that PNG as balance/score data.
- A 2-minute-length distribution was **not** produced. It would need a real
  2-minute run; per the brief, it is reported as not done rather than faked.

The alternative API (`__poseSnake.forceFinish()`) exists and is what the web
project's own `tools/measure.mjs` uses. It was deliberately **not** used here,
because letting the real timer expire is closer to what a player sees.

### 7.3 Stale-capture check — every frame is the cyan skin, not purple

Verified, not eyeballed:

- **9/9 captures**: `--tv-cyan` = `#56e8ff`; title slab `border-radius: 4px`;
  `backdrop-filter` is `none` on **every** measured element (the purple layer's
  signature `blur(14px)` is gone everywhere); `body` background `rgb(5,9,18)`.
- **OSD corner brackets** sampled at 1920: `rgb(50,134,153)` at x=44..73,
  y=44..45 — exactly `#56e8ff` × .55 over `rgb(5,9,18)`. Present in `ready`,
  `play`, `pause`, and at 1440 (where they sit at inset 34.56 px).
- Two states legitimately have **no visible brackets**, and that is the shipped
  behaviour, not a stale page:
  - **title** — `#overlay` is `z-index: 50` with its own full-screen grid
    background, covering `body::after` (`z-index: 39`);
  - **settlement** — `body.result-mode` lifts `#arena` to `z-index: 60` and the
    canvas now covers the whole 1920×1080.
- No cache-bust retry was needed: the run used a **fresh Chrome profile** plus a
  `?cb=` query, so no stale CSS could be served. (The purple-layer screenshots in
  `evidence/` are simply old files.)

### 7.4 Environment notes

- The brief said a static server was already running at `127.0.0.1:8791`. It was
  **not answering** (`Invoke-WebRequest` → *无法连接到远程服务器*). It was left
  untouched. The **source** project directory was served instead, on
  `127.0.0.1:8793`, using the project's own `serve.py --no-browser`.
- One headless Chrome at a time (`--headless=new`, throwaway profile); no Godot,
  no adb, no installs; total capture time **19.7 s** for 9 states.
- The web project was **not modified**. New files exist only under the Godot
  project: `Docs/WEB-COMPUTED-STYLES.{md,json}` and `evidence/web-ref/**`.
- Re-running `evidence/web-ref/tools/capture-web-ref.mjs` refreshes the JSON and
  the PNGs; `tools/gen-styles-doc.py` then rebuilds §0–§5 and §8 of this document
  from that JSON. **§6 and §7 are hand-written analysis and are not regenerated.**

---

## 8. Screenshot manifest

All in `evidence/web-ref/`, all captured in the same frame as the numbers above.

| file | state | size |
|---|---|---|
| `web-title-1920.png` | title | 1920×1080 |
| `web-ready-1920.png` | ready | 1920×1080 |
| `web-play-1920.png` | play | 1920×1080 |
| `web-pause-1920.png` | pause | 1920×1080 |
| `web-settle-1920.png` | settle | 1920×1080 |
| `web-split2p-1920.png` | split2p | 1920×1080 |
| `web-split2p-play-1920.png` | split2p-play | 1920×1080 |
| `web-title-1440.png` | title | 1440×810 |
| `web-play-1440.png` | play | 1440×810 |

Verification crops (5× nearest-neighbour zooms, produced from the same PNGs so
the corner brackets can be checked offline): `verify-osd-corner-tl.png`,
`verify-osd-corner-br.png`, `verify-scanlines.png`.
