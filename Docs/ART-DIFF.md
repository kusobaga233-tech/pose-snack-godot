# ART-DIFF — Web original vs Godot port

Read-only visual audit. No source files were modified; nothing was run (no Godot, no adb).
Sources: `js/render.js`, `js/heads.js`, `js/fx.js`, `js/resultStage.js`, `style.css` (web) and
`src/present/ps_theme.gd`, `ps_world_view.gd`, `ps_hud.gd`, `ps_stage.gd`, `ps_assets.gd`, `ps_fx.gd` (Godot),
plus the curated screenshots in `screenshots/` and `evidence/`.

## 0. How to read the numbers (important)

Three different coordinate systems are in play. Every size below is converted to **CSS px at 1440×810**
(the reference resolution of most web captures) so the two builds are comparable.

| Build | Native canvas | Conversion to 1440×810 |
|---|---|---|
| Web | CSS px, 1:1 with the screenshot (captures are 1440×810 / 1578×746) | ×1.00 |
| Godot | **1920×1080 design canvas** (`ps_hud.gd:216` `DESIGN := Vector2(1920,1080)`, `project.godot:23-27` viewport 1920×1080, window override 1280×720, `stretch/mode="canvas_items"`, `aspect="expand"`) | **×0.75** |

So a Godot `14` px corner radius is **10.5 CSS px**; a Godot `20` px label is **15 CSS px**.
All "Godot" values in this document are already ×0.75 unless the table says `design`.

### 0.1 Which web skin is the target

`style.css` contains **two stacked design systems**:

1. lines 1–1380 — the original "Q 版" purple/glass layer: `#07030e` page, `rgba(20,10,38,.62)` cards,
   `rgba(160,120,255,.18)` borders, `border-radius:14px`, `backdrop-filter: blur(14px)`.
2. lines 1382–2921 — the **TV CONSOLE SKIN** (comment at `style.css:1382-1389` "这是最终主题层"), which
   overrides the first layer: hard 2–4 px corners, electric-cyan system colour, lime player colour,
   4 px accent edges, OSD corner brackets, scanlines.

Because layer 2 comes later in the cascade it wins. The newest captures confirm it is live:
`title-final-20261112-004643.png` (11-12 00:46) and `split-view-20261112-002000.png` (11-12 00:20) are pure
TV-skin. `01-arena.png`, `41-playing-quickplay.png`, `67-powerups-idle.png` are **undated and show the older
purple layer** (rounded 14 px glass cards, purple borders) — they are useful for canvas content (snake/food
drawing) but their *chrome* is stale.

> **Target = the TV console skin.** Note the irony: the Godot port currently looks *more* like the abandoned
> purple layer (14–26 px radii, steel-blue borders) than like the shipped TV skin. Most fixes below are
> "finish the migration the web already made".

---

## 1. Palette table

Web values are exact from source. Godot values are exact from source. Δ is in sRGB 0–255 unless noted.

### 1.1 Structure / surfaces

| Token | Web value + source | Godot current + source | Δ | Recommended target |
|---|---|---|---|---|
| Page ink (menus) | `#050912` — `style.css:1405` | `BG_TOP #081226` — `ps_theme.gd:9`; menu scrim `rgba(.02,.03,.06,.72)` — `ps_hud.gd:730` | Godot bg is +3 R, +9 G, +20 B (too blue) | `#050912` for all full-screen menu/settle backdrops |
| Arena base gradient | `#081226` → `#060D1C` @.55 → `#040914` — `render.js:83-85` | identical — `ps_theme.gd:9-11`, `ps_assets.gd:72-74` | **0 — exact match** | keep |
| Panel fill | `rgba(7,15,28,0.94)` + gradient overlay `linear-gradient(155deg,rgba(9,20,36,.98),rgba(5,10,20,.99))` — `style.css:1393`, `1831` | `rgba(11,19,33,0.84)` flat — `ps_theme.gd:39` | **+4 R, +4 G, +5 B, −10% alpha, no gradient** | `rgba(7,15,28,0.94)` **plus** a vertical gradient to `rgba(5,10,20,0.99)` |
| Panel stroke | `rgba(86,232,255,0.34)` — `style.css:1395` | `rgba(89,133,184,0.28)` — `ps_theme.gd:41` | **hue: cyan → steel blue; −49 G, −71 B** (see §3.1 — this is the single biggest whole-screen tell) | `rgba(86,232,255,0.34)` |
| Panel stroke (soft / inner dividers) | `rgba(86,232,255,0.15)` — `style.css:1396` | same const reused at .28 | +13% alpha, wrong hue | `rgba(86,232,255,0.15)` for internal rules |
| Panel muted fill | `rgba(6,14,26,0.94)` — `style.css:1658` | `CHIP_BG rgba(13,20,36,0.78)` — `ps_theme.gd:43` | +7 R, +6 G, +10 B, −16% alpha | `rgba(6,14,26,0.94)` |
| Panel shadow | `0 14px 38px rgba(0,0,0,.62)` **+ `0 0 26px rgba(86,232,255,.12)`** — `style.css:1493` | `0 5px 6px rgba(0,0,0,.35)` — `ps_theme.gd:202-205` | Godot shadow ~1/4 the spread, and **no cyan bloom term at all** | two shadows: black 0 14 38 @.62 + cyan 0 0 26 @.12 |
| Scrim over gameplay (pause) | `rgba(0,0,0,?)` on `#overlay` | `rgba(5,8,15,0.72)` — `ps_hud.gd:730` | acceptable | keep, but web TV also dims through the scanline layer |

### 1.2 Accents

| Token | Web | Godot | Δ | Target |
|---|---|---|---|---|
| System accent (cyan) | `#56e8ff` — `style.css:1397` | `CYAN #56E8FF` — `ps_theme.gd:17` | **0 — exact** | keep |
| Player accent (lime) | `#b6ff57` — `style.css:1398` | `LIME #B6FF57` — `ps_theme.gd:13` | **0 — exact** | keep |
| Gold (rank / best) | `#ffd54a` — `style.css:1399` | `GOLD #FFC53D` — `ps_theme.gd:20` | **−18 G, −13 B** (Godot gold is orange-ish) | `#FFD54A`; keep `#FFE066` as its light variant |
| Danger red (wall / last call) | `rgba(255,60,110,…)` — `render.js:163`; `#ff7a5c` last-call text — `style.css:1535` | `DANGER #FF3C6E` — `ps_theme.gd:22` | **−24 G** (Godot is pinker/harder) | walls `#FF3C6E` ✔; last-call clock `#FF7A5C` |
| Pink | — | `PINK #FF4D9D` — `ps_theme.gd:19` | fine (matches web food pink) | keep |
| Violet | `--tv-…` none; web food `#9D6BFF` | `VIOLET #9D6BFF` — `ps_theme.gd:23` | 0 | keep |
| Ready slot 1 (coral) | web 1P = lime/green `#b6ff57` family (TV skin) | `SLOT_1 #E03C14` — `ps_theme.gd:28` ("1024 reference project") | **totally different identity: orange-red vs lime** | 1P = `#B6FF57`; 2P = `#56E8FF` (see §3.6) |
| Ready slot 2 (violet) | web 2P = magenta/pink snake `#FF4D9D` | `SLOT_2 #8417A0` — `ps_theme.gd:29` | hue 40° off, too dark | `#FF4D9D` |

### 1.3 Text

| Token | Web | Godot | Δ | Target |
|---|---|---|---|---|
| Text primary | `#eaf6ff` `--tv-text` — `style.css:1400` | `TEXT #EAF4FF` — `ps_theme.gd:33` | −2 B | `#EAF6FF` |
| Text numeric emphasis | `#f2fbff` — `style.css:1528` | uses `TEXT #EAF4FF` | small | `#F2FBFF` for the four stat values |
| Text secondary | `rgba(190,214,238,0.62)` `--tv-dim` — `style.css:1401` | `MUTED #93A7C4` — `ps_theme.gd:35` | Godot is **opaque 100%** vs web 62%, and +? composite ≈ `#93A7C4` vs web-on-dark `#7A8798` | `rgba(190,214,238,0.62)` as an actual alpha |
| Text tertiary | `rgba(150,205,230,.6/.7)` — `style.css:1858,1919` | `MUTED_DARK #5F7291` — `ps_theme.gd:36` | −? | `rgba(150,205,230,0.65)` |
| Text on lime | `#06210c` (brand tag) / `#04101c` (keycap) — `style.css:1852,1451` | `INK #050810` — `ps_theme.gd:37` | ok | `#06210C` |
| Number glow | `text-shadow: 0 0 20px rgba(86,232,255,.34)`; gold `0 0 22px rgba(255,213,74,.55)` — `style.css:1529,1533` | none (plain `draw_string`) | **missing entirely** | add a 1-pass blurred/offset copy or an outline in the accent colour at 34% |

### 1.4 World / arena

| Token | Web | Godot | Δ | Target |
|---|---|---|---|---|
| Grid dot | `rgba(120,220,255,0.075)`, tile **90 px**, dot r=2.1 **+ a 14×1 px cross** — `render.js:56-67` | `rgba(120,219,255,0.085)`, tile 90 px — `ps_assets.gd:83-84` | alpha +0.010; **cross arm unverified in bake** | `rgba(120,220,255,0.075)`; ensure the `+` arm is drawn, it is what makes the floor read "arena" not "dotted paper" |
| Tile seam | `rgba(86,232,255,0.11)`, `lineWidth 2`, `setLineDash([14,18])` — `render.js:118-120` | **pure white** `Color(1,1,1,0.16)`, 2 px, 32 px dash texture — `ps_world_view.gd:173-181` | **hue: white → should be cyan; alpha +0.05** | `rgba(86,232,255,0.11)`, dash 14/18 |
| World light blobs | additive `globalCompositeOperation='lighter'`, radial `rgba(c,a)`→0 — `render.js:90-102` | `PSAssets.blob` normal blend, `a 0.075–0.15` — `ps_world_view.gd:89,152` | **additive → alpha** (blobs look like fog, not light) | draw blobs with `CanvasItemMaterial.BLEND_MODE_ADD` |
| Wall (idle) | not drawn; the wall only exists as a warning | `wall_strip` tinted `rgba(255,77,112,a)` + core line `rgba(255,107,140,a+.25)` — `ps_world_view.gd:198-206` | Godot shows a permanent pink margin | keep, but drop idle alpha to ≈0.12 so it reads like web's "only when near" |
| Wall (danger pulse) | `rgba(255,60,110, .35+danger*.55*pulse)`, `lineWidth 14` (CSS px), `shadowColor rgba(255,40,90,.9)`, `shadowBlur 40` — `render.js:159-166` | pulse exists (`a` from distance) but **no 40 px glow**, strip is a texture falloff | **missing the 40 px bloom = the "you are about to die" feeling** | add a 4-pass widening stroke at α .9/.5/.25/.1, widths 14/24/38/56 |
| Player body ramp | `#B6FF57` / `#5BEFA0` @.35 / `#2FD6C8` @.75 / `#1FA8D8` — `render.js:523-526` | `LIME/MINT/TEAL/CYAN_DEEP` via `ramp4` — `ps_theme.gd:13-18,234` | **0 — exact match** | keep |
| Body outer glow | **additive** `lighter`, `rgba(snakeColor,0.13)`, `lineWidth R*2+30` → halo +15 CSS px — `render.js:492-500` | 3 concentric normal-blend ribbons at α .085/.85·.085/1·.085, half-width `r+26 design` = **+19.5 CSS** — `ps_world_view.gd:375,437-442` | **blend mode wrong (normal vs additive); alpha ~0.13 vs 0.085/stack** | one additive ribbon at `rgba(color,0.13)`, half-width `r+15`; delete the 3-ribbon stack |
| Body outline | `rgba(6,30,34,0.5)`, `+5 px` — `render.js:507-508` | `rgba(3,13,19,0.85)`, `+5` — `ps_world_view.gd:101,463` | **+0.35 alpha, darker** — Godot's contour is hard/black, web's is a soft dark-teal | `rgba(6,30,34,0.5)` |
| Body sheen | white `.22`, width `R*0.6`, **offset −R*0.36 along the normal** — `render.js:545-553` | white `.13`, width `0.8r`, **centred on the spine** — `ps_world_view.gd:468` | **alpha −0.09, width +0.2R, offset missing 0.36R** | α .22, width .6r, offset −.36r. This one change is what makes the body look round |
| Scale ticks | arc `R*0.55`, `lineWidth R*0.2`, `rgba(235,255,225, .16…0.36)` — `render.js:569-592` | straight `draw_multiline`, `lineWidth 1.5 design (1.1 CSS)`, `rgba(255,255,255,0.075)` — `ps_world_view.gd:411-416` | **−0.09…−0.28 alpha, −3 CSS px width, straight vs arc** | arcs at α .20, width `r*0.18`, colour `#EBFFE1` |
| Head ink (pupil/mouth) | `#1B0A2A` — `render.js:294,307` | `#1B0A2A` — `ps_assets.gd:154` | **0 — exact** | keep |
| Aim ring | `rgba(255,255,255,0.5)`, 3 px, r `R*1.9`, dash 10/10, scrolling — `render.js:601-604` | `rgba(255,255,255,ra)`, 2 px, r `hr*1.95`, r AFC solid — `ps_world_view.gd:494` | **dash missing → reads as a bubble, not a reticle** | restore `[10,10]` dash + `lineDashOffset` scroll |
| Food glow | additive halo baked per face — `render.js:397-460` | `_glow(img, c, c, r*2.45, col, 0.34)` — `ps_assets.gd:141-142` | directionally right | keep; bump crown/big to .46 ✔ (already) |
| Food palette | web faces: pink/yellow/blue/violet/green/orange + `#FFD93D` boost | `FF4D9D, FFD93D, 5BC8FF, 9D6BFF, 4DEFA8, FF8A4D` — `ps_assets.gd:15-18` | good | keep |
| Minimap plate | `rgba(5,12,24,0.84)`, `roundRect r=12`, stroke `rgba(86,232,255,0.32)` 1 px, world `rgba(8,22,40,0.86)`, grid `rgba(86,232,255,0.13)` — `render.js:911-923` | `draw_rect` plate + border `rgba(107,199,255,0.22)` — `ps_hud.gd:721` | **radius 0 vs 12; border cyan .22 vs .32; grid colour unverified** | r 12 (CSS) plate, stroke `.32`, cyan grid `.13` |
| Minimap player dot | `#EAFFC9` r 3.4 + breathing ±0.7, ring `rgba(182,255,87,.85)` 1.4 px at r+3 — `render.js:959-970` | single rect `±16 design (12 CSS)` — `ps_hud.gd:719` | Godot dot is ~3.5× too big and square | 3.4 px dot + 1.4 px lime ring |
| Leaderboard "me" row | `rgba(182,255,87,0.16)` fill + `border-left 3px #b6ff57` — `style.css:1736` | `rgba(181,255,87,0.14)` + 3 px lime — `ps_hud.gd:661-662` | **0.02 alpha** | ✔ effectively matching — leave |

---

## 2. Per-screen comparison

Sizes: web = CSS px at 1440×810 (measured on the captures where noted); Godot = design px with the CSS
equivalent in brackets.

### 2.1 Title / mode select  ·  web `title-final-20261112-004643.png` vs `evidence/flow-01-mode-select.png`

| Aspect | Web | Godot | Verdict |
|---|---|---|---|
| Structure | **One 780×569 glass panel** centred (`style.css:1887` `width:min(780px,100%)`), measured x 398→1184, y 41→610 at 1578 wide | **No panel at all** — full-bleed type on the arena gradient | ❌ whole-screen |
| Panel chrome | `border-top:4px solid #b6ff57`, radius ~6, bg `linear-gradient(155deg,rgba(9,20,36,.98),rgba(5,10,20,.99))`, shadow `0 40px 100px rgba(0,0,0,.8), 0 0 60px rgba(86,232,255,.12)` — `style.css:1826-1833` | none | ❌ |
| Title | `clamp(34,4.6vw,58)` = **58 px @1440**, weight **900**, tracking `.04em`, **gradient text** `#eaffd0 → #b6ff57 40% → #56e8ff`, height 1.06 — `style.css:1897-1902,1859-1867` | `Pose Snake` ≈ **48 CSS px** (64 design), flat `#B6FF57`, no gradient, no tracking | ❌ −17% size, flat colour |
| Brand dot | 18×18, r3, lime, `shadow 0 0 0 4px rgba(182,255,87,.14), 0 0 28px rgba(182,255,87,.85)` — `style.css:1868` | 12 CSS px plain disc | partial |
| Brand tag | lime pill `4px 10px`, r2, **10 px / 900 / .24em**, `#06210c`, glow `0 0 20px rgba(182,255,87,.35)` — `style.css:1848-1857` | none | ❌ |
| Meta badges | 4 chips: `padding 6px 12px`, r2, `border-left:3px solid #56e8ff`, bg `rgba(86,232,255,.07)`, 11/700/.08em — `style.css:1871-1882` | none (a single subtitle line instead) | ❌ |
| Mode cards | 2 × ~390×70 (measured), r3, border 1px `rgba(86,232,255,.15)`, **border-bottom 3px** `rgba(86,232,255,.28)`, selected: border `rgba(182,255,87,.68)` + `inset 0 0 26px rgba(110,240,130,.14)`; label **19/900**, sub 11.5 — `style.css:1922-1948` | 2 × **344×268 CSS** (458×357 design), radius **19.5 CSS**, focus = lighter fill `rgba(.11,.155,.22,.97)`, top accent bar 54×4.5 CSS, label **40.5 CSS** (54 design), sub 15.75 | ❌ 3.5× too tall, 2× too much type, no lime selected state |
| Footer | keycap legend row: `A 确认  X 切换  ○ 设置  SPACE 立即开始`; keycap 21×20 r4, 10/900, `linear-gradient(180deg,#e2faff,#8ad8ee)`, `0 2px 0 rgba(0,0,0,.6)` — `style.css:1440-1456` | plain text `← → 选择 · OK 确认 · 按返回键退出` 16.5 CSS | ❌ keycaps are a signature UE element, absent |
| Background | flat `#050912` + vignette + scanlines | arena gradient + 8 floating emoji heads at the margins | ⚠ Godot's floating food heads on the menu are an invention; they look like debug noise |

### 2.2 Ready  ·  web (no TV-skin capture supplied; spec from `style.css`) vs `evidence/flow-02-ready.png`

There is **no web capture of the ready screen in TV skin** in the curated set — flag this as an evidence gap.
Judging by the port's own layout and the web tokens:

| Aspect | Web spec | Godot | Verdict |
|---|---|---|---|
| Slot identity | 1P `#b6ff57` lime / 2P `#56e8ff` cyan (TV) or magenta `#FF4D9D` (canvas snake) | 1P `#E03C14` **orange**, 2P `#8417A0` violet — `ps_theme.gd:28-29` | ❌ whole-screen colour identity |
| Card | r≈4, border 1px `rgba(86,232,255,.34)`, top or left 3–4 px accent | r **13 CSS** (18 design), 1 px orange border, inner camera box r 6, no accent edge | ❌ |
| Readiness bar | web uses a lime fill bar in the HUD | vertical orange bar, 10 CSS wide, **no track/glow**, "88%" 12 CSS below | ⚠ acceptable shape, flat |
| Backdrop | `#050912` flat | maroon→black radial glow (from the orange slot tint at `ps_hud.gd:324-327`) | ❌ the whole screen goes red for 1P; web never tints the full screen |
| Tracking chip | `#statusbar`: r3, `border-right:3px solid #56e8ff`, 12/800/.1em — `style.css:1651-1666` | chip r 7.5 CSS, steel border, 15 CSS text | ⚠ |

### 2.3 Arena + HUD  ·  web `20-bigmap.png`, `split-view-20261112-002000.png`, `01-arena.png` vs `evidence/flow-04-play.png`, `render-preview-1080p.png`

**Top HUD — the largest concrete layout difference.**

| Element | Web | Godot | Verdict |
|---|---|---|---|
| Container | **One merged segmented bar**: `border-radius:4px`, `border:1px solid rgba(86,232,255,.34)`, **`border-left:4px solid #b6ff57`**, bg `linear-gradient(100deg,rgba(6,14,26,.97),rgba(9,20,34,.88))`, shadow `0 14px 38px rgba(0,0,0,.62), 0 0 26px rgba(86,232,255,.12)` — `style.css:1483-1496` | **4 independent cards**, radius **10.5 CSS**, 1 px steel border, no left edge, no merged bar — `ps_hud.gd:136,541-545` | ❌ reads as "widgets" not "console scoreboard" |
| Cell metrics | `min-width:94`, `padding:8px 17px 9px`, separators `1px rgba(86,232,255,.15)` — `style.css:1497-1509` | 150×92 design = **112×69 CSS**, gap 12 CSS, no separators | ❌ +19% wide, +33% tall, no dividers |
| Label | **10 px / 600 / `.22em`**, `rgba(190,214,238,.62)` — `style.css:1520-1524` | **15 CSS** (20 design), weight 700, **no tracking** | ❌ +50% size, tracking missing |
| Value | **30 px / 900**, `#f2fbff`, `font-variant-numeric: tabular-nums`, glow `0 0 20px rgba(86,232,255,.34)`; accent value = gold `#ffd54a` + `0 0 22px rgba(255,213,74,.55)` — `style.css:1525-1534` | **30 CSS** (40 design) ✔ size matches, weight 700, no tabular figures, no glow, all four values white | ⚠ size right, everything else wrong |
| Watermark | each cell prints `data-en` top-right: **8 px / 800 / `.18em`** `rgba(86,232,255,.42)` — `style.css:1510-1519` | none | ❌ a cheap, very characteristic detail |
| Clock | Not in a card. **Label `剩余` above**, digits ≈ **60 px measured** with a cyan/white **glow halo**, and a **small diamond glyph** under the colon (`20-bigmap.png`); separate **2 px lime vertical charge bar** at the left of the bar | **208×96 CSS card** with a **cyan underline progress bar 126×3.75 CSS** at the bottom, "1:58" **36 CSS** (48 design), no glow, no label above; rank "第 1 名" 16.5 CSS below | ❌ Godot invented a card+underline the web does not have, halved the clock, dropped the glow and the 剩余 label |
| Rank | top-right block `我的名次` (label) + `2 / 8` at ≈**40 px**, slash-treated, plus `共 8 位玩家` 12 px (measured `20-bigmap.png`); colour lime when up, salmon `#ff9a72` when down — `style.css:2360-2383` | `第 N 名 ▲/▼` **16.5 CSS** under the clock, lime/gold | ❌ −59% size and wrong position; the `n / 8` fraction and the arrow animation are the signature |
| Status pill | `#statusbar` r3, `border-right:3px solid #56e8ff`, 12/800/.1em | chip r 7.5, steel border, 15 CSS, lime dot | ⚠ |
| Leaders board | width **226**, r3, `border-top:3px solid #56e8ff`, bg `rgba(6,14,26,.95)`, `.lb-rank` gold `.lb-row.me` lime fill + 3 px lime left — `style.css:1720-1737` | width 187.5 CSS (250 design), r 7.5, rows 202×28 design, gold rank, lime tint ✔ | ⚠ close; fix radius + top edge |
| Corner brackets | **all four screen corners, every screen**: `inset: var(--safe)` (=18–44 px), arms **30×2 px** `#56e8ff`, `opacity:.55` — `style.css:1421-1437` | only inside the ready-screen camera preview (`ps_hud.gd:415,451`); none on play/settle | ❌ **signature missing** |
| Scanlines | `repeating-linear-gradient(0deg, rgba(160,220,255,.022) 0 1px, transparent 1px 4px)` over the whole frame — `style.css:1418` | absent (grep: no `scan`/`vignette` anywhere in `src/present`) | ❌ |
| Vignette | `radial-gradient(ellipse at 50% 48%, transparent 46%, rgba(1,3,9,.62) 100%)` — `style.css:1419` | absent | ❌ |
| Minimap | r12 glass plate, cyan stroke, at `x:22, y:h−H−30` — `render.js:900-923` | square plate at 18 CSS left / 126 CSS up, steel border — `ps_hud.gd:606,721` | ❌ |
| Body | 8-pass draw with additive halo, white top sheen, arched scales | 5-pass draw, normal-blend halo, centred sheen, straight ticks | ❌ see §1.4 |

### 2.4 Pause  ·  `evidence/remote-04-pause.png` (+ `render-preview-pause.png`)

| Aspect | Web spec (derived — no TV pause capture supplied) | Godot | Verdict |
|---|---|---|---|
| Modal | `#overlay .panel` language: **r 4**, `border-top:4px solid #b6ff57`, bg `rgba(9,20,36,.98)`, shadow `0 40px 100px rgba(0,0,0,.8)` | **520×380 CSS** (693×507 design), **radius 18 CSS** (24 design), 1 px steel border, shadow 24 design | ❌ radius 4.5× and no lime top bar |
| Title | keycap/`900` weight | 暂停 **42 CSS** (56 design), weight 700–800 | ⚠ |
| Primary btn | web primary = lime fill, **r 3**, `900` | lime fill, **r 12 CSS** (16 design) | ❌ |
| Blur | web TV layer explicitly sets `backdrop-filter:none` — panels are opaque, *not* glass | Godot also opaque ✔ | ✔ (both are matte; do **not** reintroduce blur) |

### 2.5 Settlement  ·  web `stage-v4-20261111-190111.png`, `stage-v4grow`, `result-final2` vs `evidence/remote-05-settle.png`, `render-preview-settlement-1080p.png`

| Aspect | Web | Godot | Verdict |
|---|---|---|---|
| Header tab | cyan rectangle **470×46 CSS**, dark text, flush left at the safe area — measured; matches `ps_stage.gd:97-99` | 470×46 design = 352×34.5 CSS | ⚠ −25% size |
| Rank line | `第 1 名 · 本局获胜！` ≈**30 px**, single line, lime dot before it; a **long stat sentence in 12 px grey sits on the SAME line to the right** (measured `stage-v4`) | `• 第 1 名` **46 CSS** (62 design) on its own line, then **3 stacked lines** of 16.5 CSS description, `冠军！` 4th line | ❌ +53% size, 4 lines instead of 1, and the whole left column grows downward pushing the chart |
| Column shading | each worm is a **vertical gradient** (yellow→green) with a **coloured glow skirt** and a face near the cap (`stage-v4`) | `grad_v` texture + `draw_texture_rect` white strip `.16` + `blob` glow at `.30` — `ps_stage.gd:158-163` | ⚠ structurally there, but the glow reads weak; the white strip is `.16` vs web's gradient sheen |
| Grid rungs | thin cyan lines at 120/100 节 with **right-aligned dim-lime labels** — `ps_stage.gd:134-136` matches intent | ✔ present at `rgba(87,232,255,.07)` | ✔ |
| Rank cards | 8 cards ≈**72×86 CSS**, r≈3, fill = player colour at low alpha, 1st card lime-tinted; `1` **/ `你` / `136 节` / `吞 0 · 死 0`** | 8 cards 187.5×105 CSS design (250×140), r 6, dark fill, lime only on the player's card top bar | ⚠ Godot cards are 2.6× wider; web's are colour-coded per snake |
| Buttons | `再来一局` lime + `A` keycap, `900`, r3 | lime r 13.5 CSS (18 design) + `返回模式选择` ghost | ❌ radius again |

### 2.6 2P split  ·  web `split-view-20261112-002000.png` vs `evidence/flow-04-play-2p.png`

| Aspect | Web | Godot | Verdict |
|---|---|---|---|
| Top bar per player | `1P 名次 2/8` left, `2P 名次 1/8` right, each with a **camera preview card** at the far edge (cyan 1P, magenta 2P border), a **▼ arrow** beside the rank, and a **2 px lime charge bar** | stat cards only show 1 player's numbers; no per-player rank block; no cam preview in the split HUD; rank list is shared on the right | ❌ whole-screen information architecture differs |
| Divider | 1 px cyan seam between halves + corner brackets at all four corners | a 1 px seam exists ✔, no brackets | ⚠ |
| Symmetry | both halves show the **same world** (same seed), each centred on its own snake | same ✔ | ✔ |

### 2.7 Powerups HUD  ·  web `69-powerups-hud.png`, `67-powerups-idle.png`, `68-powerups-active.png` vs `evidence/flow-04-play.png`

| Aspect | Web | Godot | Verdict |
|---|---|---|---|
| Chip | `min-width:176`, **r3**, 1 px `rgba(86,232,255,.15)`, **`border-right:3px solid currentColor`**, bg `rgba(6,14,26,.95)`; boost colour `#ffd54a`, magnet `#56e8ff` — `style.css:1704-1717` | chip r 7.5 CSS, steel border, no right edge accent | ❌ |
| Bar | `.buff-bar` height **4 px**, radius **0**, `rgba(255,255,255,.12)` track — `style.css:1717` | 3 px design (2.25 CSS) bar, sits inside the chip | ⚠ |
| In-world pickup | dashed ring, icon, label under, breathing alpha `0.30 + 0.26·breathe + 0.20·energy`, `lineWidth 3` — `render.js:1018-1035` | `powerup_ring` baked texture + label 15 CSS under — `ps_world_view.gd:303-309` | ✔ good match |

### 2.8 Debug / tuning panel  ·  web `65-ai-tuning-panel.png`, `32-pose-diag.png` vs Godot `--debug` overlay

| Aspect | Web | Godot | Verdict |
|---|---|---|---|
| Panel | width **312**, r4, `border-left:3px solid #56e8ff`, bg `linear-gradient(155deg,rgba(8,17,31,.98),rgba(5,11,22,.98))`, shadow `0 20px 52px rgba(0,0,0,.7), 0 0 30px rgba(86,232,255,.1)` — `style.css:1538-1552` | debug panel `660×26+22n` at (292, h−320) with `rgba(0,0,0,.62)` fill and `rgba(89,183,255,.35)` border — `ps_hud.gd:812-814` | ⚠ functional, but web's is a designed drawer |
| Header | `tuning-head` 12/800/.14em, bg `linear-gradient(90deg,rgba(86,232,255,.13),transparent)`, `border-bottom 1px rgba(86,232,255,.15)` | single text line | ❌ |
| Sliders | track 6 px r0 `rgba(86,232,255,.15)` + `border-top:1px rgba(86,232,255,.22)`; thumb **14×18 r2** `linear-gradient(180deg,#e8fcff,#56e8ff)`, glow `0 0 14px rgba(86,232,255,.7)` — `style.css:1595-1608` | no sliders in the port's debug overlay | ❌ |
| Live readout | r3, `rgba(86,232,255,.09)`, `border-left:3px solid #56e8ff`, text `#bff4ff` — `style.css:1625-1632` | plain text | ⚠ |

---

## 3. Signature visual elements — missing or wrong, ranked by player noticeability

1. **The TV OSD frame (corner brackets + scanlines + vignette).** On the web every single screen carries
   four 30×2 px cyan corner brackets inset by the safe area at `opacity:.55` (`style.css:1421-1437`), a 1-in-4 px
   scanline at `rgba(160,220,255,.022)` (`:1418`) and a vignette to `rgba(1,3,9,.62)` at 46%→100% (`:1419`).
   This is the single strongest "this is a console game on a TV" cue and the Godot build has **none of it**
   outside one camera-preview widget. Cost to fix: one full-screen `CanvasLayer` with 3 draw calls.
2. **Hard 4 px corners everywhere.** Web panel radii are **2, 3, 4, and 12 (minimap only)**. Godot uses
   **10.5, 12, 13.5, 18, 19.5** CSS. Every card, chip, button, modal and settlement tile is visibly rounder,
   which changes the perceived genre from "broadcast scoreboard" to "mobile app". One constant fixes ~80% of it.
3. **The merged HUD scoreboard bar.** Web = one 4 px-radius strip with a 4 px lime left edge, internal 1 px
   cyan dividers, `data-en` 8 px watermarks, 30 px tabular figures with a cyan text glow. Godot = four floating
   rounded cards with 15 px labels and no dividers. This is the most-looked-at element in the game.
4. **Cyan strokes vs steel-blue strokes.** `rgba(86,232,255,.34)` → `rgba(89,133,184,.28)`. Every panel edge on
   every screen is desaturated by ~70 units of blue-green. Reads as "grey UI" instead of "electric UI".
5. **Snake body lighting.** Three separate omissions on the same object: the halo is alpha-blended instead of
   additive (`.13` `lighter` vs 3× `.085` normal), the white sheen is centred instead of offset −0.36 R upward
   (so the body has no roundness), and the scale arcs are straight 1.1 px lines at `.075` instead of curved
   `r*0.2` arcs at `.16–.36`. Together the body looks like a flat ribbon with a vapour trail.
6. **The clock and the rank block.** Web: `剩余` label + ~60 px glowing digits + a diamond glyph, and a
   `2 / 8` fraction with a ▲/▼ arrow at ~40 px. Godot: a 208×96 card with a cyan underline bar and 36 px
   digits, rank demoted to 16.5 px under it. The port invented chrome the web never had and shrank the two
   numbers players actually read.
7. **The title panel.** A 780 px lime-topped glass slab with gradient display type, brand tag, 4 mode badges
   and a keycap legend is a completely different composition from full-bleed centred text. Also the web
   title is a **gradient** (`#eaffd0→#b6ff57→#56e8ff`); Godot's is flat lime.
8. **Head variety and the settlement chart.** Web ships **17 hand-drawn heads** (`js/heads.js:135 HEAD_STYLES`,
   base radius 50 at `:30`, sheet `heads-check-static-all-20261112-090012.png`) — clown with a rainbow ruff,
   three-eye, robot with LED bar, R2-D2, Ultraman with glowing lens, pumpkin, Monkey King, bee, triceratops,
   the glyph 「四」, opera mask, steam engine, fried egg, power socket, bowling ball, dice, lightbulb —
   all with radial shading, 2 px dark contour and a specular blob. Godot has ~8 procedural variants
   (`ps_world_view.gd:586-704`) that are much simpler at gameplay scale and lose the "what is that thing?"
   discovery. The settlement columns inherit the same flatness.

**Honourable mentions** (high effort, lower noticeability): the `YUM!` burst text outline is right
(`fx.js:227` `900 size / stroke size*0.18 rgba(20,8,40,.85)` vs `ps_theme.gd:146-148` `size*0.16
rgba(.02,.03,.06,.82)` — close enough); food emoji faces are genuinely good in both; the additive food halo
is present in Godot.

---

## 4. Concrete fix list (ordered by visual impact ÷ effort)

Legend: **S** ≤ 1 h, **M** ≤ half a day, **L** > half a day.

| # | What to change | Target value | File | Effort |
|---|---|---|---|---|
| 1 | **Panel corner radius**: introduce a single `RADIUS = 4` constant (design px = 5) and switch every UI style box to it. Keep 12 CSS only for the minimap plate and 16 for *nothing*. | `2–4` CSS (`3–5` design) | `ps_theme.gd:190-208` (default arg), then call sites `ps_hud.gd:136-156,734,742`, `ps_stage.gd:39-44,215` | **S** |
| 2 | **Panel stroke colour** → cyan. Replace `PANEL_BORDER` and every hard-coded steel `Color(0.35,0.52,0.72,…)` / `(0.36,0.50,0.78,…)`. | `rgba(86,232,255,0.34)` normal, `0.15` for dividers | `ps_theme.gd:41-42`, `ps_hud.gd:734`, `ps_stage.gd:40` | **S** |
| 3 | **Add the OSD overlay**: full-screen layer drawing 4 corner brackets, scanlines, vignette. Draw it above everything (own `CanvasLayer` > HUD). | brackets 30×2 px cyan, `inset = safe area`, α `.55`; scanlines 1 px every 4 px `rgba(160,220,255,.022)`; vignette 46%→100% `rgba(1,3,9,.62)` | new `ps_osd.gd`, add child in `main.gd` | **M** |
| 4 | **Merge the HUD into one bar**: one style box for the whole strip, then 4 transparent cells + 1 px cyan right dividers; 4 px lime left edge; add the 8 px `data-en` watermark; tabular figures. | strip r4, `border-left 4px #b6ff57`, bg gradient `rgba(6,14,26,.97)→rgba(9,20,34,.88)`; cell 94×~52 CSS, pad `8/17/9`; label 10 px `.22em`; value 30 px `#f2fbff` + cyan glow; accent gold | `ps_hud.gd:534-545` | **M** |
| 5 | **Snake body lighting**: make the halo additive, offset the sheen, soften the contour, arch the scales. | halo `rgba(col,.13)` `lighter`, half-width `r+15`; sheen white `.22` w`.6r` at `−.36r`; outline `rgba(6,30,34,.5)`; ticks arcs `r*.55` w`r*.2` α`.20` `#EBFFE1` | `ps_world_view.gd:375,437-442,463,468,411-416`; may need a `CanvasItemMaterial` with `BLEND_MODE_ADD` for the glow pass | **M** |
| 6 | **Cyan seam dashes + cyan minimap plate.** | seams `rgba(86,232,255,.11)` dash 14/18; minimap r12 plate, stroke `.32`, player dot 3.4 px + 1.4 px lime ring | `ps_world_view.gd:173-181`; `ps_hud.gd:700-721` | **S** |
| 7 | **Clock + rank block redesign**: drop the card and the underline bar; `剩余` label above, 60 px glowing digits; move rank to the top-right as `n / 8` at ~40 px with the ▲/▼ arrow. | label 11 px `.18em` dim; digits 60 px 900 + glow `rgba(86,232,255,.34)`; rank `40 px/900` lime or `#ff9a72` | `ps_hud.gd:546-574` | **M** |
| 8 | **Wall danger bloom**: 4 widening strokes instead of one strip. | widths 14/24/38/56 CSS, α `.9/.5/.25/.1` of `#FF2872` | `ps_world_view.gd:203-231` | **S** |
| 9 | **Title panel**: wrap the mode-select content in one 780 px panel with a 4 px lime top edge, gradient H1, brand tag and 4 mode badges. | panel `linear-gradient(155deg,rgba(9,20,36,.98),rgba(5,10,20,.99))`, shadow `0 40px 100px rgba(0,0,0,.8), 0 0 60px rgba(86,232,255,.12)`; H1 58 px 900 `.04em`, gradient `#eaffd0→#b6ff57→#56e8ff` | `ps_hud.gd:200-290` | **L** |
| 10 | **Letter-spacing support**: `draw_string` has no tracking, so every label is tighter than web. Add a small tracked-text helper that advances per glyph, or bake spacing into the CJK strings. Apply `.18–.24em` on labels/brands. | label `.18em`, brand `.24em`, body `.02em` | `ps_theme.gd:140-185` | **M** |
| 11 | **Keycap widget** for the footer and buttons (`A`/`X`/`OK`): the white `linear-gradient(180deg,#e2faff,#8ad8ee)` chip with `0 2px 0 rgba(0,0,0,.6)` is a console-menu signature. | 21×20, r4, 10 px/900, `#04101c` | new helper in `ps_theme.gd` + `ps_hud.gd` footer | **S–M** |
| 12 | **Text glow** for numbers: a cheap 4-direction offset copy at 34% in the accent colour (no blur needed at TV distance). | `0 0 20px rgba(86,232,255,.34)` equivalent | `ps_theme.gd` (new `text_glow()`) | **S** |
| 13 | **Settlement header**: collapse the 4 stacked lines into one 30 px rank line + one 12 px grey stat sentence on the same line; shrink the rank from 62 to ~40 design. | rank 30 CSS, stats 12 CSS on the same baseline | `ps_stage.gd:106-123` | **S** |
| 14 | **Ready screen de-tint + slot colours**: stop tinting the whole backdrop by slot; move 1P to lime, 2P to cyan/magenta. | SLOT_1 `#B6FF57`, SLOT_2 `#FF4D9D` | `ps_theme.gd:28-29`, `ps_hud.gd:324-327` | **S** |
| 15 | **Minimap dot sizes**: 3.4 px player, 2.4 px AI, 1.6 px food, 3.4 px powerup squares, breathing ±0.7. | as listed | `ps_hud.gd:688-721` | **S** |
| 16 | **Head art** — the big one. Port 6–8 of the 17 web heads as baked 160×160 sprites (they are simple vector shapes; `ps_assets.gd` already has `_disc_shaded/_ring/_poly/_arc` helpers to bake them). Prioritise clown, three-eye, Ultraman, robot, pumpkin, dice. | base radius 24 px sprite (`HEAD_BASE_R 50` in world units), 2 px contour `#1B0A2A`, radial shade, specular blob | `ps_assets.gd` (new `_build_heads()`), `ps_world_view.gd:586-704` | **L** |

---

## 5. Things we should NOT copy

| Web effect | Why not on Mali-G52 | Substitute |
|---|---|---|
| `backdrop-filter: blur(14px)` on cards (`style.css:51,87` — the *old* layer) | Full-screen backdrop blur is 3–6× the fragment cost of anything else here and will tank 60 fps on a 1080p TV stick. The web's own TV layer already dropped it (`backdrop-filter:none` at `:1494,1548,1664`) — **the port is right to be matte.** | Opaque fill at ≥.92 alpha + a 1 px cyan stroke. Already the direction of travel. |
| `ctx.shadowBlur` per stroke (`render.js:166,538`) — canvas shadow is a separate blur pass per draw | Godot would need a real blur shader or a `BackBufferCopy`; on mobile that is a full-screen read per snake per frame. | **Bake the blur**: pre-render the halo as a radial/ribbon texture once (as `ps_assets.gd` already does for food), or use 3 widened ribbons with falling alpha (the current approach) but switch them to `BLEND_MODE_ADD`. |
| Additive `globalCompositeOperation='lighter'` across *all* FX layers at once | Additive over a dark floor is cheap, but the web stacks confetti + rings + glow + flash simultaneously (`01-arena.png`); matching that density per-frame is the one thing that will actually drop frames. | Keep `lighter` **only** for the snake halo and the food halo (2 passes). Cap particles at the existing `MAX_P = 220` and `MAX_W = 8`. Do **not** add a third additive layer. |
| 478-file screenshot zoo of tuning permutations | Not a runtime cost, just scope. | Ship one art-locked theme; keep variants behind `--debug`. |
| Full 17-head roster at launch | Each head is a bake + a draw variant; 17 × 2 face states is ~34 sprites and a lot of review surface. | Ship 8 heads now (one per silhouette family), keep the `HEAD_STYLES` map shaped so the rest drop in. |
| The stale purple/glass layer (`style.css:1-1380`) | It is dead code in the web already; porting it would double the theme surface. | Ignore. Target the TV layer only. |

---

## 6. Verification method

**Principle: same state, same resolution, side by side, same seed.** Art parity cannot be argued from
memory; every claim above should be re-checked against a paired capture.

### 6.1 Capture the Godot side with the harness that already exists

Documented flags (`src/main.gd:34-57`), user args after `--`:

```
# full screen walk: MODE_SELECT -> READY -> COUNTDOWN -> PLAY  -> evidence/flow-01..04 PNGs
godot --path . -- --capture-flow

# 2P branch: two ready cards + split-screen play -> flow-02-ready-2p / flow-04-play-2p
godot --path . -- --capture-flow --capture2p

# MODE_SELECT -> READY -> PLAY -> PAUSE -> SETTLE via real key events -> evidence/remote-0*.png
godot --path . -- --capture-remote

# settlement + split previews
godot --path . -- --capture            # render-preview*.png (1P round end state)
godot --path . -- --capture2p          # render-preview-split.png

# ready-screen no-pose timeout -> flow-05-ready-escape.png
godot --path . -- --capture-escape

# headless key journey, prints [key]/[flow] only (for input parity, not art)
godot --path . -- --remote-probe

# debug overlay on at boot (F3 toggles)
godot --path . -- --debug
```

Resolution: `project.godot` is **1920×1080 design** with a **1280×720 window override** and
`stretch/mode="canvas_items"`, `aspect="expand"`. To compare against a 1440×810 web capture either
(a) resize the window to 1440×810 and re-shoot, or (b) upscale the 1280×720 evidence by 1.125 and
compare *proportions*, never absolute pixels. Existing 1080p evidence (`render-preview-1080p.png`) proves
the layout scales — use it for the 1920 comparison against a 1920-wide web shot if one is ever taken.

### 6.2 Pairing table — the exact pairs to diff

| Screen | Web reference | Godot capture |
|---|---|---|
| Title / mode select | `title-final-20261112-004643.png` | `flow-01-mode-select.png` |
| Ready 1P | *none in TV skin* (evidence gap — capture one) | `flow-02-ready.png`, `flow-02b-ready-done.png` |
| Arena / HUD | `20-bigmap.png`, `split-view-20261112-002000.png` | `flow-04-play.png`, `render-preview-1080p.png` |
| Pause | *none in TV skin* (evidence gap) | `remote-04-pause.png` |
| Settlement | `stage-v4-20261111-190111.png` | `remote-05-settle.png`, `render-preview-settlement-1080p.png` |
| 2P split | `split-view-20261112-002000.png` | `flow-04-play-2p.png` |
| Powerups | `69-powerups-hud.png`, `67-powerups-idle.png` | `flow-04-play.png` (with a buff active) |
| Tuning / debug | `65-ai-tuning-panel.png`, `32-pose-diag.png` | `--debug` overlay |

> **Coverage gap to close first:** there is no TV-skin web capture for READY or PAUSE. Until one exists,
> those two screens can only be verified against the `style.css` spec in this document, not pixel-matched.

### 6.3 Five checks that turn "looks different" into pass/fail

1. **Corner radius sweep** — crop 5 cards (HUD cell, leaderboard, pause modal, settlement tile, mode card);
   overlay a 4 px-radius guide. All five must sit inside it.
2. **Stroke hue probe** — eyedropper any panel edge. Expected `#56e8ff` at ~34% over the fill; a reading
   with G−B < 60 is the steel-blue regression.
3. **Body lighting A/B** — at 200% zoom on one snake, the sheen line must be **above** the centreline by
   ~0.36 × radius, and a 15 px halo must **add** to the background (measure a floor pixel: additive lightens,
   alpha-blend desaturates toward grey).
4. **Clock/rank read test** — stand 2 m from the TV and read the round time and the `n / 8` rank. If the rank
   is unreadable, the size fix from §4.7 is not done.
5. **Frame cost guard** — re-run `--capture` after the fixes and compare the printed `fps min/avg` and draw
   calls against `evidence/capture-final*-out.txt`. Art changes must not move min fps by more than ~2.

---

## Appendix — evidence notes

- Colours in §1.1–1.4 were read from source, not eyeballed, except where marked *measured*.
- The two web layers (§0.1) mean several curated captures (`01-arena`, `41-playing-quickplay`,
  `67-powerups-idle`) show chrome that is **no longer the shipped look**. Their *canvas* content (snake glow,
  food halos, particle density) is still the best reference available and was used as such.
- `npc-faces-20261111-135553.png` and `land-split-20261111-005644.png` from the brief do not exist on disk;
  `heads-check-static-all-20261112-090012.png` + the `only-*.png` singles cover the same ground.
- Godot head-style count: `ps_world_view.gd:586-704` contains 9 distinguishable branches (2-eye + arc mouth,
  visor rect, polygon nose, curve mouth, dual-colour 3D glasses, robot rect+antenna, insect polygons,
  train/box, dark-disc robot, rounded-rect die, single-arc mouth) — comfortably more than the 8 quoted
  in §3.8, and still well short of the web's 17 with their shading detail.
